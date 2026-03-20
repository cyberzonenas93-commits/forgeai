import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import {
  FieldValue,
  getFirestore,
  Timestamp,
  type DocumentData,
} from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import * as functions from 'firebase-functions/v1';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import type { CallableOptions, CallableRequest } from 'firebase-functions/v2/https';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import {
  AI_PROVIDER_NAMES,
  PROVIDER_NAMES,
  assertRuntimeConfiguration,
  currentRuntimeSettings,
  lookupProviderToken,
  providerSecretNames,
  type AiProviderName,
  type ProviderName,
} from './runtime';
import {
  getModelForTierAndProvider,
  getTierForAction,
  OPENAI_LATEST_CHAT_MODEL,
  PLANS,
  TOP_UP_PACKS,
  type PlanId,
  type TopUpPackId,
} from './economics-config';
import {
  BILLABLE_ACTION_TYPES,
  buildActionCost,
  buildCostSnapshot,
  isBillableActionType,
  type BillableActionType,
  type CheckActionType,
  type GitActionType,
} from './pricing';
import {
  buildIndexEntryStoragePayload,
  buildRepoIndexEntries,
  buildRepoStructure,
  pickDependencyCandidates,
  rankRepoIndexEntries,
  type RepoIndexEntry,
  type RepoIndexFileInput,
  type RankedRepoIndexEntry,
} from './repo_index_service';
import {
  buildRepoExecutionRepairPrompt,
  buildRepoExecutionSystemPrompt,
  buildRepoExecutionUserPrompt,
  parseRepoExecutionResponse,
  summarizeRepoExecution,
} from './repo_execution_format';

initializeApp();

const db = getFirestore();
const messaging = getMessaging();
type ChangeKind = 'manual' | 'ai';
type GitMergeMethod = 'merge' | 'squash' | 'rebase';
type GitProviderName = Extract<ProviderName, 'github' | 'github'>;
type NotificationCategory =
  | 'checks'
  | 'git'
  | 'repository'
  | 'ai'
  | 'provider'
  | 'wallet'
  | 'security'
  | 'digest';

const CHANGE_KINDS: readonly ChangeKind[] = ['manual', 'ai'];
const GIT_ACTION_TYPES: readonly GitActionType[] = [
  'create_branch',
  'commit',
  'open_pr',
  'merge_pr',
];
const CHECK_ACTION_TYPES: readonly CheckActionType[] = [
  'run_tests',
  'run_lint',
  'build_project',
];

const runtimeValidation = assertRuntimeConfiguration();
const runtimeSettings = currentRuntimeSettings();
const TEST_WALLET_BALANCE = 999_999_999;
const BASE_CALLABLE_OPTIONS: CallableOptions = {
  region: runtimeSettings.firebaseRegion,
  timeoutSeconds: 120,
  memory: '512MiB',
};
const GIT_CALLABLE_OPTIONS: CallableOptions = {
  ...BASE_CALLABLE_OPTIONS,
  secrets: ['GITHUB_TOKEN'],
};
const AI_CALLABLE_OPTIONS: CallableOptions = {
  ...BASE_CALLABLE_OPTIONS,
  secrets: ['OPENAI_API_KEY'],
};
const GIT_AND_AI_CALLABLE_OPTIONS: CallableOptions = {
  ...BASE_CALLABLE_OPTIONS,
  secrets: ['OPENAI_API_KEY', 'GITHUB_TOKEN'],
};
const IAP_CALLABLE_OPTIONS: CallableOptions = {
  ...BASE_CALLABLE_OPTIONS,
  secrets: ['APPLE_IAP_SHARED_SECRET'],
};
const DEFAULT_NOTIFICATION_PREFERENCES = {
  enabled: true,
  checks: true,
  git: true,
  repository: true,
  ai: true,
  provider: true,
  wallet: true,
  security: true,
  digest: true,
} as const;
const AGENT_TASK_STATUSES: readonly AgentTaskStatus[] = [
  'queued',
  'running',
  'waiting_for_input',
  'completed',
  'failed',
  'cancelled',
];
const AGENT_TASK_RUNTIME_OPTIONS = {
  region: runtimeSettings.firebaseRegion,
  timeoutSeconds: 540,
  memory: '1GiB' as const,
  secrets: ['OPENAI_API_KEY', 'GITHUB_TOKEN'],
};
const AGENT_TASK_MAX_RUNTIME_MS = 12 * 60_000;
const AGENT_TASK_MAX_RETRIES = 2;
const AGENT_TASK_MAX_TOKEN_BUDGET_NORMAL = 4_200;
const AGENT_TASK_MAX_TOKEN_BUDGET_DEEP = 9_000;
const AGENT_TASK_MAX_FILE_TOUCHES_NORMAL = 6;
const AGENT_TASK_MAX_FILE_TOUCHES_DEEP = 14;
const AGENT_TASK_STALE_RUNNING_LOCK_MS = 15 * 60_000;

/** File text sent to suggestChange; GPT-5 Chat (latest alias) supports large contexts. */
const AI_SUGGESTION_BASE_CONTENT_MAX_CHARS = 200_000;
/** Max completion tokens for suggestChange (provider caps applied below). */
const AI_SUGGESTION_MAX_OUTPUT_TOKENS = 32_768;

function suggestionMaxOutputTokens(provider: AiProviderName): number {
  if (provider === 'anthropic') {
    return Math.min(AI_SUGGESTION_MAX_OUTPUT_TOKENS, 8192);
  }
  return AI_SUGGESTION_MAX_OUTPUT_TOKENS;
}

function repoExecutionMaxOutputTokens(model: string, mode: RepoExecutionMode): number {
  const requested = mode === 'deep' ? 24_000 : 12_000;
  // GPT-5 chat models currently cap output at 16,384 completion tokens.
  if (model.startsWith('gpt-5')) {
    return Math.min(requested, 16_384);
  }
  return requested;
}

/** GPT-5.x Chat Completions use max_completion_tokens; omit fixed temperature. */
function buildOpenAiChatCompletionJsonBody(params: {
  model: string;
  messages: unknown[];
  temperature: number;
  maxOutput: number;
  responseFormat?: { type: 'json_object' };
}): Record<string, unknown> {
  const body: Record<string, unknown> = {
    model: params.model,
    messages: params.messages,
  };
  if (params.responseFormat) {
    body.response_format = params.responseFormat;
  }
  if (params.model.startsWith('gpt-5')) {
    body.max_completion_tokens = params.maxOutput;
  } else {
    body.temperature = params.temperature;
    body.max_tokens = params.maxOutput;
  }
  return body;
}

interface SendPushNotificationInput {
  ownerId: string;
  category: NotificationCategory;
  type: string;
  title: string;
  body: string;
  destination: string;
  repoId?: string | null;
  threadId?: string | null;
  changeRequestId?: string | null;
}

/** App Store reviewer demo account: full token access; auto-deleted ~30 days after Auth creation. */
const APP_STORE_REVIEWER_TEST_EMAIL = 'test@codecatalystai.com';
const APP_STORE_REVIEWER_TEST_MAX_AGE_MS = 30 * 86400_000;

/**
 * Emails that receive unlimited token usage server-side. All others use paywall/subscription.
 * Keep this list small; `APP_STORE_REVIEWER_TEST_EMAIL` is purged on a schedule after 30 days.
 */
const UNLIMITED_USER_EMAILS = new Set(
  ['cyberzonenas93@gmail.com', APP_STORE_REVIEWER_TEST_EMAIL].map(email =>
    email.trim().toLowerCase(),
  ),
);

function isUnlimitedUser(email: string | null | undefined): boolean {
  const normalized = email?.trim().toLowerCase();
  if (!normalized) {
    return false;
  }
  return UNLIMITED_USER_EMAILS.has(normalized);
}

/** GitHub/OAuth often leave [user.email] empty; providerData may still include the address. */
function resolveAuthUserEmails(user: {
  email?: string | null;
  providerData?: { email?: string | null }[];
}): string[] {
  const emails = new Set<string>();
  const direct = user.email?.trim();
  if (direct) {
    emails.add(direct);
  }
  for (const p of user.providerData ?? []) {
    const fromProvider = p.email?.trim();
    if (fromProvider) {
      emails.add(fromProvider);
    }
  }
  return [...emails];
}

/** GitHub/OAuth often leave [user.email] empty; providerData may still include the address. */
function resolveAuthUserEmail(user: {
  email?: string | null;
  providerData?: { email?: string | null }[];
}): string | null {
  return resolveAuthUserEmails(user)[0] ?? null;
}

async function getOwnerEmail(ownerId: string): Promise<string | null> {
  const userRef = db.collection('users').doc(ownerId);
  const userSnap = await userRef.get();
  const existing = userSnap.data()?.email;
  if (typeof existing === 'string' && existing.trim().length > 0) {
    return existing.trim();
  }
  try {
    const record = await getAuth().getUser(ownerId);
    const resolved = resolveAuthUserEmail(record);
    if (resolved) {
      await userRef.set(
        { email: resolved, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
      return resolved;
    }
  } catch {
    // User missing in Auth, etc.
  }
  return null;
}

async function isUnlimitedOwner(ownerId: string): Promise<boolean> {
  const userRef = db.collection('users').doc(ownerId);
  const userSnap = await userRef.get();
  const data = userSnap.data();
  if (data?.unlimited === true) {
    return true;
  }
  const existing = data?.email;
  if (typeof existing === 'string' && isUnlimitedUser(existing)) {
    await userRef.set({ unlimited: true, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return true;
  }
  try {
    const record = await getAuth().getUser(ownerId);
    const authEmails = resolveAuthUserEmails(record);
    if (authEmails.some(isUnlimitedUser)) {
      const preferredEmail = authEmails.find(isUnlimitedUser) ?? authEmails[0] ?? null;
      const patch: Record<string, unknown> = {
        unlimited: true,
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (preferredEmail) {
        patch.email = preferredEmail;
      }
      await userRef.set(
        patch,
        { merge: true },
      );
      return true;
    }
  } catch {
    // User missing in Auth, etc.
  }
  return false;
}

async function notificationPreferencesForUser(ownerId: string) {
  const snapshot = await db
    .collection('users')
    .doc(ownerId)
    .collection('notificationPreferences')
    .doc('default')
    .get();
  return {
    ...DEFAULT_NOTIFICATION_PREFERENCES,
    ...(snapshot.data() ?? {}),
  } as typeof DEFAULT_NOTIFICATION_PREFERENCES;
}

function notificationCategoryEnabled(
  preferences: Record<string, boolean | undefined>,
  category: NotificationCategory,
) {
  return preferences.enabled !== false && preferences[category] !== false;
}

async function notificationTargetsForUser(ownerId: string) {
  const snapshot = await db.collection('users').doc(ownerId).collection('devices').get();
  return snapshot.docs
    .map(doc => ({
      id: doc.id,
      token: typeof doc.data().token === 'string' ? doc.data().token.trim() : '',
      permissionStatus:
        typeof doc.data().permissionStatus === 'string'
          ? doc.data().permissionStatus
          : 'notDetermined',
    }))
    .filter(device => Boolean(device.token))
    .filter(
      device => device.permissionStatus === 'authorized' || device.permissionStatus === 'provisional',
    );
}

async function pruneInvalidNotificationTokens(
  ownerId: string,
  devices: Array<{ id: string }>,
  response: Awaited<ReturnType<typeof messaging.sendEachForMulticast>>,
) {
  const invalidCodes = new Set([
    'messaging/registration-token-not-registered',
    'messaging/invalid-registration-token',
  ]);
  const removals = response.responses.flatMap((result, index) => {
    const code = result.error?.code;
    if (!code || !invalidCodes.has(code)) {
      return [];
    }
    return [
      db.collection('users').doc(ownerId).collection('devices').doc(devices[index]!.id).delete(),
    ];
  });
  if (removals.length > 0) {
    await Promise.all(removals);
  }
}

async function sendPushNotification(input: SendPushNotificationInput) {
  const preferences = await notificationPreferencesForUser(input.ownerId);
  if (!notificationCategoryEnabled(preferences, input.category)) {
    return { delivered: 0, skipped: true };
  }

  const devices = await notificationTargetsForUser(input.ownerId);
  if (devices.length === 0) {
    return { delivered: 0, skipped: true };
  }

  const payload = {
    type: input.type,
    destination: input.destination,
    repoId: input.repoId ?? '',
    threadId: input.threadId ?? '',
    changeRequestId: input.changeRequestId ?? '',
    title: input.title,
    body: input.body,
  };

  const response = await messaging.sendEachForMulticast({
    tokens: devices.map(device => device.token),
    notification: {
      title: input.title,
      body: input.body,
    },
    data: payload,
    android: {
      priority: 'high',
      notification: {
        channelId: 'forgeai_default',
      },
    },
    apns: {
      headers: {
        'apns-priority': '10',
      },
      payload: {
        aps: {
          sound: 'default',
        },
      },
    },
  });

  await pruneInvalidNotificationTokens(input.ownerId, devices, response);
  return {
    delivered: response.successCount,
    skipped: false,
  };
}

async function maybeSendLowBalanceNotification(ownerId: string) {
  const snapshot = await db.collection('wallets').doc(ownerId).get();
  const balance = snapshot.data()?.balance;
  if (typeof balance !== 'number' || balance > 200) {
    return;
  }
  await sendPushNotification({
    ownerId,
    category: 'wallet',
    type: 'wallet_alert',
    title: 'Token balance running low',
    body: `${Math.max(0, Math.floor(balance))} tokens remain in your CodeCatalystAI wallet.`,
    destination: 'wallet',
  });
}

functions.logger.info('forgeai_runtime_validation', {
  appEnv: runtimeValidation.settings.appEnv,
  projectId: runtimeValidation.settings.projectId,
  strictValidation: runtimeValidation.settings.strictValidation,
  requiredProviders: runtimeValidation.settings.requiredProviders,
  missingCore: runtimeValidation.missingCore,
  missingProviders: runtimeValidation.missingProviders,
});

interface ProviderConfigRequest {
  provider?: ProviderName;
}

interface ProviderConnectionSyncData {
  provider: GitProviderName;
  accessToken: string;
}

interface ProviderRepositoryListData {
  provider?: 'github' | 'github';
  query?: string;
  apiBaseUrl?: string;
}

interface RepositoryConnectionData {
  provider: 'github' | 'github';
  repository: string;
  defaultBranch?: string;
  description?: string;
  htmlUrl?: string;
  syncNow?: boolean;
  accessToken?: string;
  apiBaseUrl?: string;
  owner?: string;
  name?: string;
}

interface RepositorySyncData {
  repoId?: string;
  provider?: 'github' | 'github';
  owner?: string;
  name?: string;
  forceRefresh?: boolean;
  accessToken?: string;
  apiBaseUrl?: string;
}

interface RepositoryFileLoadData {
  repoId: string;
  filePath: string;
  accessToken?: string;
  apiBaseUrl?: string;
}

interface SuggestChangeData {
  repoId: string;
  filePath: string;
  provider: ProviderName;
  prompt: string;
  changeKind: ChangeKind;
  baseContent?: string;
  branchName?: string;
  accessToken?: string;
  apiBaseUrl?: string;
}

interface RepoExecutionData {
  repoId: string;
  prompt: string;
  provider?: ProviderName;
  currentFilePath?: string;
  deepMode?: boolean;
}

interface ApplyRepoExecutionData {
  repoId: string;
  sessionId: string;
}

interface EnqueueAgentTaskData {
  repoId: string;
  prompt: string;
  currentFilePath?: string;
  deepMode?: boolean;
  threadId?: string;
}

interface AgentTaskControlData {
  taskId: string;
}

interface ResolveAgentTaskApprovalData extends AgentTaskControlData {
  decision: 'approved' | 'rejected';
}

interface GitFileChange {
  path: string;
  content: string;
  sha?: string;
  mode?: string;
}

interface GitActionData {
  repoId: string;
  provider: 'github' | 'github';
  actionType: GitActionType;
  branchName?: string;
  sourceBranch?: string;
  baseBranch?: string;
  commitMessage?: string;
  prTitle?: string;
  prDescription?: string;
  pullRequestNumber?: number;
  mergeRequestId?: number;
  mergeMethod?: GitMergeMethod;
  fileChanges?: GitFileChange[];
  confirmed?: boolean;
}

interface CheckActionData {
  repoId: string;
  provider: 'github' | 'github';
  actionType: CheckActionType;
  workflowName: string;
  ref?: string;
  inputs?: Record<string, string>;
  confirmed?: boolean;
}

interface TokenActionData {
  repoId: string;
  actionType: BillableActionType;
  amount: number;
  costPreview: number;
  provider: ProviderName;
  reason?: string;
}

interface ProviderConfigSnapshot {
  provider: ProviderName;
  label: string;
  configured: boolean;
  tokenPresent: boolean;
  tokenHint: string | null;
  baseUrl: string;
  secretNames: string[];
  capabilities: string[];
  defaultModel: string | null;
}

interface RemoteRepositorySnapshot {
  remoteId: string | number | null;
  provider: 'github' | 'github';
  owner: string;
  name: string;
  fullName: string;
  defaultBranch: string;
  description: string | null;
  htmlUrl: string | null;
  isPrivate: boolean;
  branches: string[];
  openPullRequests: number;
  openMergeRequests: number;
  files: RemoteFileSnapshot[];
}

interface RemoteFileSnapshot {
  path: string;
  type: string;
  language: string | null;
  size: number | null;
}

interface ProviderRepositoryListItem {
  provider: GitProviderName;
  owner: string;
  name: string;
  fullName: string;
  defaultBranch: string;
  description: string | null;
  htmlUrl: string | null;
  isPrivate: boolean;
}

interface WalletState {
  balance: number;
  reserved: number;
  monthlyLimit: number;
  monthlyUsed: number;
  currency: string;
  planName: string;
  dailyActionCap: number;
}

interface AiSuggestionDraft {
  providerUsed: ProviderName;
  model: string | null;
  summary: string;
  rationale: string;
  afterContent: string;
  diffPreview: string;
  riskNotes: string[];
  suggestedCommitMessage: string;
  estimatedTokens: number;
  source: string;
}

interface ResolvedProviderToken {
  token: string;
  secretName: string;
  source: 'request' | 'user_connection' | 'runtime';
}

type AgentTaskStatus =
  | 'queued'
  | 'running'
  | 'waiting_for_input'
  | 'completed'
  | 'failed'
  | 'cancelled';

type AgentTaskEventType =
  | 'task_created'
  | 'task_started'
  | 'repo_scanned'
  | 'files_selected'
  | 'file_read'
  | 'ai_called'
  | 'edits_applied'
  | 'diff_generated'
  | 'validation_started'
  | 'validation_failed'
  | 'retrying'
  | 'awaiting_approval'
  | 'remote_action_started'
  | 'remote_action_completed'
  | 'task_completed'
  | 'task_failed'
  | 'task_cancel_requested'
  | 'task_cancelled'
  | 'task_paused'
  | 'task_resumed';

type AgentTaskApprovalType =
  | 'apply_changes'
  | 'commit_changes'
  | 'open_pull_request'
  | 'merge_pull_request'
  | 'deploy_workflow'
  | 'resume_task'
  | 'risky_operation';

type AgentTaskPhase =
  | 'queued'
  | 'analyze_request'
  | 'inspect_repo'
  | 'generate_diff'
  | 'awaiting_approval'
  | 'apply_edits'
  | 'validate'
  | 'follow_up'
  | 'completed'
  | 'failed'
  | 'cancelled';

interface AgentTaskFollowUpPlan {
  commitChanges: boolean;
  openPullRequest: boolean;
  mergePullRequest: boolean;
  deployWorkflow: boolean;
  riskyOperation: boolean;
}

interface AgentTaskGuardrails {
  maxRuntimeMs: number;
  maxRetries: number;
  maxTokenBudget: number;
  maxFileTouchCount: number;
}

interface AgentTaskPendingApproval {
  id: string;
  type: AgentTaskApprovalType;
  title: string;
  description: string;
  status: 'pending' | 'approved' | 'rejected';
  actionLabel: string;
  cancelLabel: string;
  payload: Record<string, unknown>;
  createdAtMs: number;
  resolvedAtMs?: number | null;
}

interface AgentTaskDocument {
  ownerId: string;
  repoId: string;
  prompt: string;
  threadId?: string | null;
  currentFilePath?: string | null;
  deepMode: boolean;
  status: AgentTaskStatus;
  phase: AgentTaskPhase;
  currentStep: string;
  queueWorkspaceId: string;
  runToken: number;
  createdAtMs: number;
  updatedAtMs: number;
  startedAtMs?: number | null;
  completedAtMs?: number | null;
  cancelledAtMs?: number | null;
  failedAtMs?: number | null;
  cancelRequestedAtMs?: number | null;
  pauseRequestedAtMs?: number | null;
  currentPass: number;
  retryCount: number;
  eventCount: number;
  selectedFiles: string[];
  inspectedFiles: string[];
  dependencyFiles: string[];
  filesTouched: string[];
  diffCount: number;
  estimatedTokens: number;
  sessionId?: string | null;
  executionSummary?: string | null;
  resultSummary?: string | null;
  errorMessage?: string | null;
  latestEventType?: AgentTaskEventType | null;
  latestEventMessage?: string | null;
  latestEventAtMs?: number | null;
  latestValidationError?: string | null;
  followUpPlan: AgentTaskFollowUpPlan;
  guardrails: AgentTaskGuardrails;
  pendingApproval?: AgentTaskPendingApproval | null;
  metadata?: Record<string, unknown>;
}

interface AgentTaskEventDocument {
  type: AgentTaskEventType;
  step: string;
  message: string;
  status: AgentTaskStatus;
  phase: AgentTaskPhase;
  sequence: number;
  createdAtMs: number;
  data?: Record<string, unknown>;
}

interface RepoExecutionObserver {
  onRepoScanned?: (details: { fileCount: number }) => Promise<void> | void;
  onFilesSelected?: (details: {
    selectedFiles: string[];
    dependencyFiles: string[];
    inspectedFiles: string[];
  }) => Promise<void> | void;
  onFileRead?: (details: { path: string; source: string }) => Promise<void> | void;
  onAiCalled?: (details: { attempt: number; mode: RepoExecutionMode }) => Promise<void> | void;
  onRetrying?: (details: { reason: string; attempt: number }) => Promise<void> | void;
  onDiffGenerated?: (details: {
    editCount: number;
    summary: string;
    sessionId: string;
  }) => Promise<void> | void;
}

function requireAuth(request: CallableRequest<unknown>) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  return request.auth.uid;
}

function asString(value: unknown, field: string) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError('invalid-argument', `Expected ${field} to be a non-empty string.`);
  }
  return value.trim();
}

function asOptionalString(value: unknown): string | undefined {
  if (typeof value !== 'string') {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function asNumber(value: unknown, field: string) {
  if (typeof value !== 'number' || Number.isNaN(value) || !Number.isFinite(value)) {
    throw new HttpsError('invalid-argument', `Expected ${field} to be a finite number.`);
  }
  return value;
}

function asInteger(value: unknown, field: string) {
  const numberValue = asNumber(value, field);
  if (!Number.isInteger(numberValue)) {
    throw new HttpsError('invalid-argument', `Expected ${field} to be an integer.`);
  }
  return numberValue;
}

function asBoolean(value: unknown, field: string) {
  if (typeof value !== 'boolean') {
    throw new HttpsError('invalid-argument', `Expected ${field} to be a boolean.`);
  }
  return value;
}

function asEnum<T extends string>(value: unknown, field: string, allowed: readonly T[]) {
  if (typeof value !== 'string' || !allowed.includes(value as T)) {
    throw new HttpsError(
      'invalid-argument',
      `Expected ${field} to be one of: ${allowed.join(', ')}.`,
    );
  }
  return value as T;
}

function isAiProvider(provider: ProviderName): provider is AiProviderName {
  return AI_PROVIDER_NAMES.includes(provider as AiProviderName);
}

function safeDocId(value: string) {
  return encodeURIComponent(value).replace(/\./g, '%2E');
}

function makeRepositoryId(provider: 'github' | 'github', owner: string, name: string) {
  return [provider, owner, name].map(safeDocId).join('__');
}

function parseRepositorySlug(repository: string) {
  const normalized = repository.trim().replace(/^\/+|\/+$/g, '');
  const parts = normalized.split('/');
  if (parts.length < 2) {
    throw new HttpsError(
      'invalid-argument',
      'repository must be in owner/name form when owner and name are not provided separately.',
    );
  }
  const owner = parts[0];
  const name = parts.slice(1).join('/');
  if (!owner || !name) {
    throw new HttpsError('invalid-argument', 'repository must include both owner and name.');
  }
  return { owner, name };
}

function truncate(value: string, max = 400) {
  if (value.length <= max) {
    return value;
  }
  return `${value.slice(0, max - 1)}…`;
}

function normalizeText(value: string) {
  return value.replace(/\s+/g, ' ').trim();
}

function maskSecret(secret: string) {
  if (secret.length <= 8) {
    return '********';
  }
  return `${secret.slice(0, 4)}…${secret.slice(-4)}`;
}

function currentIsoTimestamp() {
  return new Date().toISOString();
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function coerceRecord(value: unknown): Record<string, string> {
  if (!isObject(value)) {
    return {};
  }
  const record: Record<string, string> = {};
  for (const [key, rawValue] of Object.entries(value)) {
    if (typeof rawValue === 'string') {
      record[key] = rawValue;
    }
  }
  return record;
}

function agentTaskCollection(ownerId: string) {
  return db.collection('users').doc(ownerId).collection('agentTasks');
}

function agentTaskRef(ownerId: string, taskId: string) {
  return agentTaskCollection(ownerId).doc(taskId);
}

function agentTaskEventsCollection(ownerId: string, taskId: string) {
  return agentTaskRef(ownerId, taskId).collection('events');
}

function agentTaskApprovalsCollection(ownerId: string, taskId: string) {
  return agentTaskRef(ownerId, taskId).collection('approvals');
}

function workspaceLockRef(repoId: string) {
  return db.collection('workspaceLocks').doc(repoId);
}

function isAgentTaskFinalStatus(status: unknown): status is 'completed' | 'failed' | 'cancelled' {
  return status === 'completed' || status === 'failed' || status === 'cancelled';
}

function buildAgentTaskGuardrails(deepMode: boolean): AgentTaskGuardrails {
  return {
    maxRuntimeMs: AGENT_TASK_MAX_RUNTIME_MS,
    maxRetries: AGENT_TASK_MAX_RETRIES,
    maxTokenBudget: deepMode
      ? AGENT_TASK_MAX_TOKEN_BUDGET_DEEP
      : AGENT_TASK_MAX_TOKEN_BUDGET_NORMAL,
    maxFileTouchCount: deepMode
      ? AGENT_TASK_MAX_FILE_TOUCHES_DEEP
      : AGENT_TASK_MAX_FILE_TOUCHES_NORMAL,
  };
}

function inferAgentFollowUpPlan(prompt: string): AgentTaskFollowUpPlan {
  const normalized = prompt.toLowerCase();
  const has = (...phrases: string[]) => phrases.some(phrase => normalized.includes(phrase));
  const openPullRequest = has('open pr', 'open a pr', 'pull request', 'open merge request');
  const mergePullRequest = has('merge pr', 'merge the pr', 'merge pull request', 'merge the pull request');
  const deployWorkflow = has('deploy', 'ship', 'release');
  const riskyOperation = has(
    'force push',
    'delete branch',
    'drop database',
    'remove secret',
    'wipe',
    'destroy',
    'rm -rf',
  );
  return {
    commitChanges: has('commit', 'push') || openPullRequest,
    openPullRequest,
    mergePullRequest,
    deployWorkflow,
    riskyOperation,
  };
}

function buildAgentTaskPendingApproval(params: {
  type: AgentTaskApprovalType;
  title: string;
  description: string;
  actionLabel: string;
  cancelLabel?: string;
  payload?: Record<string, unknown>;
}): AgentTaskPendingApproval {
  return {
    id: db.collection('_').doc().id,
    type: params.type,
    title: params.title,
    description: params.description,
    status: 'pending',
    actionLabel: params.actionLabel,
    cancelLabel: params.cancelLabel ?? 'Reject',
    payload: params.payload ?? {},
    createdAtMs: Date.now(),
  };
}

function summarizeAgentTaskResult(task: Pick<AgentTaskDocument, 'executionSummary' | 'resultSummary'>) {
  return task.resultSummary ?? task.executionSummary ?? 'Task completed.';
}

function safeAgentTask(data: DocumentData | undefined): AgentTaskDocument {
  return {
    ownerId: typeof data?.ownerId === 'string' ? data.ownerId : '',
    repoId: typeof data?.repoId === 'string' ? data.repoId : '',
    prompt: typeof data?.prompt === 'string' ? data.prompt : '',
    threadId: typeof data?.threadId === 'string' ? data.threadId : null,
    currentFilePath: typeof data?.currentFilePath === 'string' ? data.currentFilePath : null,
    deepMode: data?.deepMode === true,
    status: AGENT_TASK_STATUSES.includes(data?.status as AgentTaskStatus)
      ? (data?.status as AgentTaskStatus)
      : 'queued',
    phase: typeof data?.phase === 'string' ? (data.phase as AgentTaskPhase) : 'queued',
    currentStep: typeof data?.currentStep === 'string' ? data.currentStep : 'Queued',
    queueWorkspaceId: typeof data?.queueWorkspaceId === 'string' ? data.queueWorkspaceId : '',
    runToken: typeof data?.runToken === 'number' ? data.runToken : 0,
    createdAtMs: typeof data?.createdAtMs === 'number' ? data.createdAtMs : Date.now(),
    updatedAtMs: typeof data?.updatedAtMs === 'number' ? data.updatedAtMs : Date.now(),
    startedAtMs: typeof data?.startedAtMs === 'number' ? data.startedAtMs : null,
    completedAtMs: typeof data?.completedAtMs === 'number' ? data.completedAtMs : null,
    cancelledAtMs: typeof data?.cancelledAtMs === 'number' ? data.cancelledAtMs : null,
    failedAtMs: typeof data?.failedAtMs === 'number' ? data.failedAtMs : null,
    cancelRequestedAtMs:
      typeof data?.cancelRequestedAtMs === 'number' ? data.cancelRequestedAtMs : null,
    pauseRequestedAtMs:
      typeof data?.pauseRequestedAtMs === 'number' ? data.pauseRequestedAtMs : null,
    currentPass: typeof data?.currentPass === 'number' ? data.currentPass : 1,
    retryCount: typeof data?.retryCount === 'number' ? data.retryCount : 0,
    eventCount: typeof data?.eventCount === 'number' ? data.eventCount : 0,
    selectedFiles: Array.isArray(data?.selectedFiles)
      ? data.selectedFiles.filter((value): value is string => typeof value === 'string')
      : [],
    inspectedFiles: Array.isArray(data?.inspectedFiles)
      ? data.inspectedFiles.filter((value): value is string => typeof value === 'string')
      : [],
    dependencyFiles: Array.isArray(data?.dependencyFiles)
      ? data.dependencyFiles.filter((value): value is string => typeof value === 'string')
      : [],
    filesTouched: Array.isArray(data?.filesTouched)
      ? data.filesTouched.filter((value): value is string => typeof value === 'string')
      : [],
    diffCount: typeof data?.diffCount === 'number' ? data.diffCount : 0,
    estimatedTokens: typeof data?.estimatedTokens === 'number' ? data.estimatedTokens : 0,
    sessionId: typeof data?.sessionId === 'string' ? data.sessionId : null,
    executionSummary:
      typeof data?.executionSummary === 'string' ? data.executionSummary : null,
    resultSummary: typeof data?.resultSummary === 'string' ? data.resultSummary : null,
    errorMessage: typeof data?.errorMessage === 'string' ? data.errorMessage : null,
    latestEventType:
      typeof data?.latestEventType === 'string'
        ? (data.latestEventType as AgentTaskEventType)
        : null,
    latestEventMessage:
      typeof data?.latestEventMessage === 'string' ? data.latestEventMessage : null,
    latestEventAtMs:
      typeof data?.latestEventAtMs === 'number' ? data.latestEventAtMs : null,
    latestValidationError:
      typeof data?.latestValidationError === 'string' ? data.latestValidationError : null,
    followUpPlan: isObject(data?.followUpPlan)
      ? {
          commitChanges: data.followUpPlan.commitChanges === true,
          openPullRequest: data.followUpPlan.openPullRequest === true,
          mergePullRequest: data.followUpPlan.mergePullRequest === true,
          deployWorkflow: data.followUpPlan.deployWorkflow === true,
          riskyOperation: data.followUpPlan.riskyOperation === true,
        }
      : {
          commitChanges: false,
          openPullRequest: false,
          mergePullRequest: false,
          deployWorkflow: false,
          riskyOperation: false,
        },
    guardrails: isObject(data?.guardrails)
      ? {
          maxRuntimeMs:
            typeof data.guardrails.maxRuntimeMs === 'number'
              ? data.guardrails.maxRuntimeMs
              : AGENT_TASK_MAX_RUNTIME_MS,
          maxRetries:
            typeof data.guardrails.maxRetries === 'number'
              ? data.guardrails.maxRetries
              : AGENT_TASK_MAX_RETRIES,
          maxTokenBudget:
            typeof data.guardrails.maxTokenBudget === 'number'
              ? data.guardrails.maxTokenBudget
              : AGENT_TASK_MAX_TOKEN_BUDGET_NORMAL,
          maxFileTouchCount:
            typeof data.guardrails.maxFileTouchCount === 'number'
              ? data.guardrails.maxFileTouchCount
              : AGENT_TASK_MAX_FILE_TOUCHES_NORMAL,
        }
      : buildAgentTaskGuardrails(data?.deepMode === true),
    pendingApproval: isObject(data?.pendingApproval)
      ? {
          id:
            typeof data.pendingApproval.id === 'string'
              ? data.pendingApproval.id
              : db.collection('_').doc().id,
          type:
            typeof data.pendingApproval.type === 'string'
              ? (data.pendingApproval.type as AgentTaskApprovalType)
              : 'apply_changes',
          title:
            typeof data.pendingApproval.title === 'string'
              ? data.pendingApproval.title
              : 'Approval required',
          description:
            typeof data.pendingApproval.description === 'string'
              ? data.pendingApproval.description
              : 'Review the next action before the agent continues.',
          status:
            data.pendingApproval.status === 'approved' ||
            data.pendingApproval.status === 'rejected'
              ? data.pendingApproval.status
              : 'pending',
          actionLabel:
            typeof data.pendingApproval.actionLabel === 'string'
              ? data.pendingApproval.actionLabel
              : 'Approve',
          cancelLabel:
            typeof data.pendingApproval.cancelLabel === 'string'
              ? data.pendingApproval.cancelLabel
              : 'Reject',
          payload: isObject(data.pendingApproval.payload)
            ? (data.pendingApproval.payload as Record<string, unknown>)
            : {},
          createdAtMs:
            typeof data.pendingApproval.createdAtMs === 'number'
              ? data.pendingApproval.createdAtMs
              : Date.now(),
          resolvedAtMs:
            typeof data.pendingApproval.resolvedAtMs === 'number'
              ? data.pendingApproval.resolvedAtMs
              : null,
        }
      : null,
    metadata: isObject(data?.metadata) ? (data.metadata as Record<string, unknown>) : {},
  };
}

async function appendAgentTaskEvent(params: {
  ownerId: string;
  taskId: string;
  type: AgentTaskEventType;
  step: string;
  message: string;
  status: AgentTaskStatus;
  phase: AgentTaskPhase;
  data?: Record<string, unknown>;
}) {
  const taskReference = agentTaskRef(params.ownerId, params.taskId);
  const eventReference = agentTaskEventsCollection(params.ownerId, params.taskId).doc();
  const now = Date.now();
  await db.runTransaction(async transaction => {
    const taskSnapshot = await transaction.get(taskReference);
    if (!taskSnapshot.exists) {
      return;
    }
    const task = safeAgentTask(taskSnapshot.data());
    const nextSequence = task.eventCount + 1;
    const eventPayload: AgentTaskEventDocument = {
      type: params.type,
      step: params.step,
      message: params.message,
      status: params.status,
      phase: params.phase,
      sequence: nextSequence,
      createdAtMs: now,
      data: params.data ?? {},
    };
    transaction.set(eventReference, eventPayload, { merge: true });
    transaction.set(
      taskReference,
      {
        eventCount: nextSequence,
        latestEventType: params.type,
        latestEventMessage: params.message,
        latestEventAtMs: now,
        updatedAtMs: now,
      },
      { merge: true },
    );
    if (task.status === 'running' || task.status === 'waiting_for_input') {
      transaction.set(
        workspaceLockRef(task.repoId),
        {
          ownerId: task.ownerId,
          repoId: task.repoId,
          taskId: params.taskId,
          status: task.status,
          updatedAtMs: now,
          acquiredAtMs: task.startedAtMs ?? task.createdAtMs,
        },
        { merge: true },
      );
    }
  });
}

async function releaseWorkspaceLockIfOwned(ownerId: string, repoId: string, taskId: string) {
  await db.runTransaction(async transaction => {
    const lockReference = workspaceLockRef(repoId);
    const lockSnapshot = await transaction.get(lockReference);
    if (!lockSnapshot.exists) {
      return;
    }
    const lock = lockSnapshot.data() as { ownerId?: string; taskId?: string } | undefined;
    if (lock?.ownerId === ownerId && lock?.taskId === taskId) {
      transaction.delete(lockReference);
    }
  });
}

async function transitionAgentTaskToFinalState(params: {
  ownerId: string;
  taskId: string;
  status: Extract<AgentTaskStatus, 'completed' | 'failed' | 'cancelled'>;
  phase: Extract<AgentTaskPhase, 'completed' | 'failed' | 'cancelled'>;
  step: string;
  summary: string;
  errorMessage?: string;
  eventType: Extract<AgentTaskEventType, 'task_completed' | 'task_failed' | 'task_cancelled'>;
}) {
  const taskReference = agentTaskRef(params.ownerId, params.taskId);
  const taskSnapshot = await taskReference.get();
  if (!taskSnapshot.exists) {
    return;
  }
  const task = safeAgentTask(taskSnapshot.data());
  const now = Date.now();
  await taskReference.set(
    {
      status: params.status,
      phase: params.phase,
      currentStep: params.step,
      resultSummary: params.summary,
      errorMessage: params.errorMessage ?? null,
      completedAtMs: params.status === 'completed' ? now : task.completedAtMs ?? null,
      failedAtMs: params.status === 'failed' ? now : task.failedAtMs ?? null,
      cancelledAtMs: params.status === 'cancelled' ? now : task.cancelledAtMs ?? null,
      pendingApproval: null,
      pauseRequestedAtMs: null,
      updatedAtMs: now,
    },
    { merge: true },
  );
  await releaseWorkspaceLockIfOwned(params.ownerId, task.repoId, params.taskId);
  await appendAgentTaskEvent({
    ownerId: params.ownerId,
    taskId: params.taskId,
    type: params.eventType,
    step: params.step,
    message: params.summary,
    status: params.status,
    phase: params.phase,
  });
  await promoteNextQueuedAgentTask(params.ownerId, task.repoId);
}

async function cancelAgentTaskNow(
  ownerId: string,
  taskId: string,
  reason = 'Task cancelled.',
) {
  await transitionAgentTaskToFinalState({
    ownerId,
    taskId,
    status: 'cancelled',
    phase: 'cancelled',
    step: 'Task cancelled',
    summary: reason,
    eventType: 'task_cancelled',
  });
}

async function failAgentTaskNow(
  ownerId: string,
  taskId: string,
  message: string,
) {
  await transitionAgentTaskToFinalState({
    ownerId,
    taskId,
    status: 'failed',
    phase: 'failed',
    step: 'Task failed',
    summary: message,
    errorMessage: message,
    eventType: 'task_failed',
  });
}

async function completeAgentTaskNow(
  ownerId: string,
  taskId: string,
  summary: string,
) {
  await transitionAgentTaskToFinalState({
    ownerId,
    taskId,
    status: 'completed',
    phase: 'completed',
    step: 'Task completed',
    summary,
    eventType: 'task_completed',
  });
}

async function putAgentTaskIntoApprovalState(params: {
  ownerId: string;
  taskId: string;
  approval: AgentTaskPendingApproval;
  step: string;
  message: string;
}) {
  const taskReference = agentTaskRef(params.ownerId, params.taskId);
  const taskSnapshot = await taskReference.get();
  if (!taskSnapshot.exists) {
    return;
  }
  const task = safeAgentTask(taskSnapshot.data());
  const now = Date.now();
  await db.runTransaction(async transaction => {
    transaction.set(
      taskReference,
      {
        status: 'waiting_for_input',
        phase: 'awaiting_approval',
        currentStep: params.step,
        pendingApproval: params.approval,
        pauseRequestedAtMs: null,
        updatedAtMs: now,
      },
      { merge: true },
    );
    transaction.set(
      agentTaskApprovalsCollection(params.ownerId, params.taskId).doc(params.approval.id),
      {
        ...params.approval,
        createdAtMs: params.approval.createdAtMs,
        updatedAtMs: now,
      },
      { merge: true },
    );
    transaction.set(
      workspaceLockRef(task.repoId),
      {
        ownerId: task.ownerId,
        repoId: task.repoId,
        taskId: params.taskId,
        status: 'waiting_for_input',
        acquiredAtMs: task.startedAtMs ?? task.createdAtMs,
        updatedAtMs: now,
      },
      { merge: true },
    );
  });
  await appendAgentTaskEvent({
    ownerId: params.ownerId,
    taskId: params.taskId,
    type: 'awaiting_approval',
    step: params.step,
    message: params.message,
    status: 'waiting_for_input',
    phase: 'awaiting_approval',
    data: {
      approvalType: params.approval.type,
      approvalId: params.approval.id,
    },
  });
}

async function promoteNextQueuedAgentTask(ownerId: string, repoId: string) {
  const candidates = await agentTaskCollection(ownerId)
    .orderBy('createdAtMs', 'asc')
    .limit(50)
    .get();
  const candidate = candidates.docs.find(document => {
    const task = safeAgentTask(document.data());
    return task.repoId === repoId && task.status === 'queued';
  });
  if (!candidate) {
    return null;
  }

  const taskReference = candidate.ref;
  const lockReference = workspaceLockRef(repoId);
  const now = Date.now();
  let started = false;
  let runToken = 0;
  await db.runTransaction(async transaction => {
    const [taskSnapshot, lockSnapshot] = await Promise.all([
      transaction.get(taskReference),
      transaction.get(lockReference),
    ]);
    if (!taskSnapshot.exists) {
      return;
    }
    const task = safeAgentTask(taskSnapshot.data());
    if (task.status !== 'queued') {
      return;
    }
    if (lockSnapshot.exists) {
      const lock = lockSnapshot.data() as
        | { taskId?: string; status?: AgentTaskStatus; updatedAtMs?: number; ownerId?: string }
        | undefined;
      const lockedTaskId = typeof lock?.taskId === 'string' ? lock.taskId : null;
      if (lockedTaskId) {
        const lockedTaskSnapshot = await transaction.get(agentTaskRef(ownerId, lockedTaskId));
        const lockedTask = lockedTaskSnapshot.exists
          ? safeAgentTask(lockedTaskSnapshot.data())
          : null;
        const lockIsStale =
          lock?.status === 'running' &&
          typeof lock?.updatedAtMs === 'number' &&
          now - lock.updatedAtMs > AGENT_TASK_STALE_RUNNING_LOCK_MS;
        if (
          lockedTask &&
          !isAgentTaskFinalStatus(lockedTask.status) &&
          !(lockIsStale && lockedTask.status === 'running')
        ) {
          return;
        }
      }
    }

    runToken = task.runToken + 1;
    transaction.set(
      lockReference,
      {
        ownerId,
        repoId,
        taskId: taskReference.id,
        status: 'running',
        acquiredAtMs: task.startedAtMs ?? now,
        updatedAtMs: now,
      },
      { merge: true },
    );
    transaction.set(
      taskReference,
      {
        status: 'running',
        phase: 'analyze_request',
        currentStep: 'Analyzing request',
        runToken,
        startedAtMs: task.startedAtMs ?? now,
        updatedAtMs: now,
        cancelRequestedAtMs: null,
      },
      { merge: true },
    );
    started = true;
  });

  if (!started) {
    return null;
  }

  await appendAgentTaskEvent({
    ownerId,
    taskId: taskReference.id,
    type: 'task_started',
    step: 'Analyzing request',
    message: 'Agent picked up the next queued task for this workspace.',
    status: 'running',
    phase: 'analyze_request',
  });
  return { taskId: taskReference.id, runToken };
}

class AgentTaskStopError extends Error {
  constructor(readonly kind: 'cancelled' | 'paused' | 'superseded') {
    super(kind);
  }
}

async function assertAgentTaskStillRunnable(ownerId: string, taskId: string, runToken: number) {
  const snapshot = await agentTaskRef(ownerId, taskId).get();
  if (!snapshot.exists) {
    throw new AgentTaskStopError('superseded');
  }
  const task = safeAgentTask(snapshot.data());
  if (task.status !== 'running' || task.runToken !== runToken) {
    throw new AgentTaskStopError('superseded');
  }
  const now = Date.now();
  if (task.cancelRequestedAtMs) {
    await cancelAgentTaskNow(ownerId, taskId, 'Task cancelled before completion.');
    throw new AgentTaskStopError('cancelled');
  }
  if (
    typeof task.startedAtMs === 'number' &&
    now - task.startedAtMs > task.guardrails.maxRuntimeMs
  ) {
    await failAgentTaskNow(ownerId, taskId, 'Task exceeded the maximum runtime.');
    throw new AgentTaskStopError('superseded');
  }
  if (task.pauseRequestedAtMs) {
    await putAgentTaskIntoApprovalState({
      ownerId,
      taskId,
      approval: buildAgentTaskPendingApproval({
        type: 'resume_task',
        title: 'Resume task?',
        description: 'The task was paused. Resume when you are ready to continue the current agent run.',
        actionLabel: 'Resume',
        cancelLabel: 'Cancel task',
      }),
      step: 'Task paused',
      message: 'Task paused and is holding the workspace lock until you resume or cancel it.',
    });
    throw new AgentTaskStopError('paused');
  }
  return task;
}

function providerConnectionRef(ownerId: string, provider: GitProviderName) {
  return db.collection('users').doc(ownerId).collection('connections').doc(provider);
}

function providerTokenRef(ownerId: string, provider: GitProviderName) {
  return db.collection('users').doc(ownerId).collection('providerTokens').doc(provider);
}

function defaultConnectionScopeSummary(provider: GitProviderName) {
  return provider === 'github'
    ? 'Repository metadata, diffs, commits, pull requests, and checks'
    : 'Projects, merge requests, pipelines, and repository sync';
}

function summarizeGitHubScopes(scopes: string[]) {
  if (scopes.length === 0) {
    return defaultConnectionScopeSummary('github');
  }
  return `OAuth scopes: ${scopes.join(', ')}`;
}

async function lookupUserProviderToken(
  ownerId: string,
  provider: GitProviderName,
): Promise<ResolvedProviderToken | null> {
  const snapshot = await providerTokenRef(ownerId, provider).get();
  const data = snapshot.data();
  const token = typeof data?.token === 'string' ? data.token.trim() : '';
  if (!token) {
    return null;
  }
  return {
    token,
    secretName: `users/${ownerId}/providerTokens/${provider}`,
    source: 'user_connection',
  };
}

async function resolveProviderToken(
  ownerId: string,
  provider: GitProviderName,
  accessToken?: string,
): Promise<ResolvedProviderToken | null> {
  const requestToken = asOptionalString(accessToken);
  if (requestToken) {
    return {
      token: requestToken,
      secretName: 'request.accessToken',
      source: 'request',
    };
  }

  const userToken = await lookupUserProviderToken(ownerId, provider);
  if (userToken) {
    return userToken;
  }

  const runtimeToken = lookupProviderToken(provider);
  if (!runtimeToken) {
    return null;
  }
  return {
    token: runtimeToken.token,
    secretName: runtimeToken.secretName,
    source: 'runtime',
  };
}

async function fetchGitHubConnectionProfile(accessToken: string) {
  const response = await fetch(`${providerBaseUrl('github')}/user`, {
    headers: buildGitHubHeaders(accessToken),
    signal: AbortSignal.timeout(20_000),
  });

  if (!response.ok) {
    const body = await response.text();
    const message = truncate(body || response.statusText, 220);
    const code =
      response.status === 401 || response.status === 403
        ? 'permission-denied'
        : response.status === 404
          ? 'not-found'
          : response.status === 429
            ? 'resource-exhausted'
            : 'internal';
    throw new HttpsError(code as any, `Remote provider error (${response.status}): ${message}`);
  }

  const profile = (await response.json()) as {
    login?: string;
    name?: string | null;
    email?: string | null;
  };
  const scopes = (response.headers.get('x-oauth-scopes') ?? '')
    .split(',')
    .map(scope => scope.trim())
    .filter(Boolean);

  return {
    account: profile.login ?? profile.email ?? 'github',
    displayName: profile.name ?? profile.login ?? profile.email ?? 'GitHub',
    scopes,
  };
}

const MAX_REPOS_PAGES = 10;
const REPOS_PAGE_SIZE = 100;

async function listGitHubRepositories(
  token: string,
  query?: string,
  apiBaseUrl?: string,
): Promise<ProviderRepositoryListItem[]> {
  const baseUrl = resolveApiBaseUrl('github', apiBaseUrl);
  const headers = buildGitHubHeaders(token);
  const allRepos: Array<{
    name?: string;
    full_name?: string;
    default_branch?: string | null;
    description?: string | null;
    html_url?: string | null;
    private?: boolean | null;
    owner?: { login?: string | null } | null;
  }> = [];
  for (let page = 1; page <= MAX_REPOS_PAGES; page++) {
    const repositories = await fetchJson<
      Array<{
        name?: string;
        full_name?: string;
        default_branch?: string | null;
        description?: string | null;
        html_url?: string | null;
        private?: boolean | null;
        owner?: { login?: string | null } | null;
      }>
    >(
      `${baseUrl}/user/repos?per_page=${REPOS_PAGE_SIZE}&page=${page}&sort=updated&affiliation=owner,collaborator,organization_member`,
      { headers },
    );
    allRepos.push(...repositories);
    if (repositories.length < REPOS_PAGE_SIZE) {
      break;
    }
  }

  const normalizedQuery = normalizeText(query ?? '').toLowerCase();
  const items: ProviderRepositoryListItem[] = [];
  for (const repository of allRepos) {
    const owner = repository.owner?.login?.trim() ?? '';
    const name = repository.name?.trim() ?? '';
    if (!owner || !name) {
      continue;
    }
    items.push({
      provider: 'github',
      owner,
      name,
      fullName: repository.full_name?.trim() || `${owner}/${name}`,
      defaultBranch: repository.default_branch?.trim() || 'main',
      description: repository.description?.trim() || null,
      htmlUrl: repository.html_url?.trim() || null,
      isPrivate: Boolean(repository.private),
    });
  }
  return items
    .filter(repository => {
      if (!normalizedQuery) {
        return true;
      }
      return [
        repository.fullName,
        repository.name,
        repository.owner,
        repository.description ?? '',
      ]
        .join(' ')
        .toLowerCase()
        .includes(normalizedQuery);
    })
    .sort((left, right) => left.fullName.localeCompare(right.fullName));
}

function normalizeRepoSlugInput(value: string) {
  const slug = normalizeText(value)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 100);
  if (!slug || slug.startsWith('.') || slug.startsWith('-')) {
    throw new HttpsError(
      'invalid-argument',
      'Repository name must be a short slug (letters, numbers, dots, hyphens).',
    );
  }
  return slug;
}

function asOptionalNamespace(value: unknown): string | null {
  const s = typeof value === 'string' ? value.trim() : '';
  if (!s) {
    return null;
  }
  if (!/^[a-zA-Z0-9][-a-zA-Z0-9]*$/.test(s)) {
    throw new HttpsError('invalid-argument', 'Organization or namespace name is invalid.');
  }
  return s;
}

async function createRemoteEmptyRepository(
  provider: 'github' | 'github',
  token: string,
  options: {
    name: string;
    description: string;
    isPrivate: boolean;
    githubOrg?: string | null;
    apiBaseUrl?: string;
  },
): Promise<{
  owner: string;
  name: string;
  fullName: string;
  htmlUrl: string | null;
  defaultBranch: string;
  remoteId: number;
}> {
  if (provider === 'github') {
    const baseUrl = resolveApiBaseUrl('github', options.apiBaseUrl);
    const endpoint = options.githubOrg
      ? `${baseUrl}/orgs/${encodeURIComponent(options.githubOrg)}/repos`
      : `${baseUrl}/user/repos`;
    const created = await fetchJson<{
      id?: number;
      name?: string;
      full_name?: string;
      owner?: { login?: string | null };
      html_url?: string | null;
      default_branch?: string | null;
    }>(endpoint, {
      method: 'POST',
      headers: buildGitHubHeaders(token),
      body: JSON.stringify({
        name: options.name,
        description: truncate(options.description, 350),
        private: options.isPrivate,
        auto_init: false,
      }),
    });
    const owner = created.owner?.login?.trim() ?? '';
    const name = created.name?.trim() ?? options.name;
    const fullName = created.full_name?.trim() ?? `${owner}/${name}`;
    if (!owner || !name) {
      throw new HttpsError('internal', 'GitHub returned an incomplete repository payload.');
    }
    return {
      owner,
      name,
      fullName,
      htmlUrl: created.html_url ?? null,
      defaultBranch: created.default_branch?.trim() || 'main',
      remoteId: Number(created.id ?? 0) || 0,
    };
  }

  const baseUrl = resolveApiBaseUrl('github', options.apiBaseUrl);
  const displayName = options.name.replace(/[-_.]+/g, ' ').trim() || options.name;
  const created = await fetchJson<{
    id?: number;
    path_with_namespace?: string | null;
    web_url?: string | null;
    default_branch?: string | null;
  }>(`${baseUrl}/projects`, {
    method: 'POST',
    headers: buildGitHubHeaders(token),
    body: JSON.stringify({
      name: displayName,
      path: options.name,
      description: truncate(options.description, 500),
      visibility: options.isPrivate ? 'private' : 'public',
      initialize_with_readme: false,
    }),
  });
  const fullName = created.path_with_namespace?.trim() ?? '';
  const segments = fullName.split('/');
  const name = segments.length >= 1 ? segments[segments.length - 1]! : options.name;
  const owner = segments.length >= 2 ? segments.slice(0, -1).join('/') : '';
  if (!owner || !name) {
    throw new HttpsError('internal', 'GitHub returned an incomplete project payload.');
  }
  return {
    owner,
    name,
    fullName,
    htmlUrl: created.web_url ?? null,
    defaultBranch: created.default_branch?.trim() || 'main',
    remoteId: Number(created.id ?? 0) || 0,
  };
}

function sanitizeScaffoldFileEntries(raw: unknown): Array<{ path: string; content: string }> {
  if (!Array.isArray(raw)) {
    return [];
  }
  const out: Array<{ path: string; content: string }> = [];
  let total = 0;
  for (const item of raw.slice(0, 12)) {
    if (!item || typeof item !== 'object') {
      continue;
    }
    const rec = item as Record<string, unknown>;
    const path = typeof rec.path === 'string' ? rec.path.trim().replace(/^\/+/u, '') : '';
    const content = typeof rec.content === 'string' ? rec.content : '';
    if (!path || path.includes('..') || path.startsWith('/')) {
      continue;
    }
    if (!/^[\w./+@-]+$/u.test(path)) {
      continue;
    }
    if (content.length > 100_000) {
      continue;
    }
    if (total + content.length > 400_000) {
      break;
    }
    total += content.length;
    out.push({ path, content });
  }
  return out;
}

async function generateProjectScaffoldPlan(
  idea: string,
  repoSlug: string,
  stackHint?: string,
): Promise<{
  description: string;
  files: Array<{ path: string; content: string }>;
}> {
  const tokenInfo = lookupProviderToken('openai');
  if (!tokenInfo) {
    throw new HttpsError('failed-precondition', 'OpenAI is not configured for this environment.');
  }
  const tier = getTierForAction('ai_project_scaffold');
  const model = getModelForTierAndProvider(tier, 'openai');
  const systemPrompt = `You help users bootstrap a brand-new codebase. Return ONLY valid JSON with shape:
{"description":"one-line repo description for Git hosting","files":[{"path":"relative/path.ext","content":"full file text"}]}
Rules:
- Include 3 to 10 files: at least README.md and sensible entry files for the stack (e.g. main.dart, package.json, etc.) when applicable.
- Paths use forward slashes, no leading slash, no ".." segments.
- Content must be real, compilable or runnable starter code when possible—not placeholders like "TODO" only.
- Keep total output reasonably small for a mobile app (avoid huge assets or long prose).
- If the user names a stack in stackHint, follow it. Otherwise pick a sensible default (e.g. Flutter for mobile, Node for a small API).
- Escape JSON strings properly (newlines as \\n inside JSON).`;
  const userPrompt = JSON.stringify({
    repoSlug,
    userIdea: truncate(idea, 4000),
    stackHint: stackHint ? truncate(stackHint, 400) : null,
  });

  const response = await fetchJson<{ choices: Array<{ message?: { content?: string | null } }> }>(
    `${providerBaseUrl('openai')}/chat/completions`,
    {
      method: 'POST',
      headers: buildOpenAiHeaders(tokenInfo.token),
      body: JSON.stringify(
        buildOpenAiChatCompletionJsonBody({
          model,
          temperature: 0.35,
          maxOutput: 8192,
          responseFormat: { type: 'json_object' },
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: userPrompt },
          ],
        }),
      ),
    },
  );

  const rawText = response.choices?.[0]?.message?.content?.trim() ?? '{}';
  let parsed: { description?: unknown; files?: unknown };
  try {
    parsed = JSON.parse(rawText) as { description?: unknown; files?: unknown };
  } catch {
    throw new HttpsError('internal', 'AI returned invalid JSON for the project scaffold.');
  }
  const description =
    typeof parsed.description === 'string' ? parsed.description.trim().slice(0, 350) : '';
  let files = sanitizeScaffoldFileEntries(parsed.files);
  const readmeFallback = `# ${repoSlug}

${truncate(idea, 2000)}

Generated with CodeCatalystAI.
`;
  if (files.length === 0) {
    files = [
      { path: 'README.md', content: readmeFallback },
      { path: '.gitignore', content: '# OS\n.DS_Store\n' },
    ];
  } else if (!files.some(f => f.path.toLowerCase() === 'readme.md')) {
    files = [{ path: 'README.md', content: readmeFallback }, ...files];
  }
  return {
    description: description || truncate(normalizeText(idea), 200) || `New project ${repoSlug}`,
    files,
  };
}

interface CreateProjectRepositoryData {
  provider?: 'github' | 'github';
  repoName?: string;
  idea?: string;
  stackHint?: string;
  isPrivate?: boolean;
  namespace?: string;
  accessToken?: string;
  apiBaseUrl?: string;
}

async function persistUserProviderToken(
  ownerId: string,
  provider: GitProviderName,
  accessToken: string,
  options?: {
    account?: string | null;
    scopeSummary?: string | null;
    metadata?: Record<string, unknown>;
  },
) {
  const token = accessToken.trim();
  if (!token) {
    throw new HttpsError('invalid-argument', 'Expected accessToken to be a non-empty string.');
  }

  await providerTokenRef(ownerId, provider).set(
    {
      provider,
      token,
      tokenHint: maskSecret(token),
      account: options?.account ?? null,
      scopeSummary: options?.scopeSummary ?? defaultConnectionScopeSummary(provider),
      source: 'oauth',
      updatedAt: FieldValue.serverTimestamp(),
      ...options?.metadata,
    },
    { merge: true },
  );

  await providerConnectionRef(ownerId, provider).set(
    {
      provider,
      account: options?.account ?? providerLabel(provider),
      scopeSummary: options?.scopeSummary ?? defaultConnectionScopeSummary(provider),
      status: 'connected',
      lastChecked: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function walletDefaults(): WalletState {
  const freePlan = PLANS.free;
  return {
    balance: 0,
    reserved: 0,
    monthlyLimit: freePlan.monthlyIncludedTokens,
    monthlyUsed: 0,
    currency: 'tokens',
    planName: freePlan.displayName,
    dailyActionCap: freePlan.dailyActionCap,
  };
}

function normalizeWalletState(data: DocumentData | undefined): WalletState {
  const defaults = walletDefaults();
  if (!data) {
    return defaults;
  }
  const dailyCap = Number(data.dailyActionCap ?? defaults.dailyActionCap);
  return {
    balance: Number(data.balance ?? defaults.balance),
    reserved: Number(data.reserved ?? defaults.reserved),
    monthlyLimit: Number(data.monthlyLimit ?? defaults.monthlyLimit),
    monthlyUsed: Number(data.monthlyUsed ?? defaults.monthlyUsed),
    currency: typeof data.currency === 'string' ? data.currency : defaults.currency,
    planName: typeof data.planName === 'string' ? data.planName : defaults.planName,
    dailyActionCap: dailyCap > 0 ? dailyCap : defaults.dailyActionCap,
  };
}

function unlimitedWalletDocument() {
  return {
    balance: TEST_WALLET_BALANCE,
    reserved: 0,
    monthlyLimit: 0,
    monthlyAllowance: TEST_WALLET_BALANCE,
    monthlyUsed: 0,
    spentThisWeek: 0,
    nextReset: 'Testing mode',
    currency: 'tokens',
    currencySymbol: 'tokens',
    planName: 'Test Unlimited',
    dailyActionCap: 9999,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function providerBaseUrl(provider: ProviderName) {
  switch (provider) {
    case 'github':
      return 'https://api.github.com';
    case 'github':
      return 'https://github.com/api/v4';
    case 'openai':
      return 'https://api.openai.com/v1';
    case 'anthropic':
      return 'https://api.anthropic.com/v1';
    case 'gemini':
      return 'https://generativelanguage.googleapis.com/v1beta';
  }
}

function resolveApiBaseUrl(provider: ProviderName, override?: string) {
  const trimmed = asOptionalString(override);
  if (trimmed) {
    return trimmed.replace(/\/+$/, '');
  }
  return providerBaseUrl(provider);
}

function providerLabel(provider: ProviderName) {
  switch (provider) {
    case 'github':
      return 'GitHub';
    case 'github':
      return 'GitHub';
    case 'openai':
      return 'OpenAI';
    case 'anthropic':
      return 'Anthropic';
    case 'gemini':
      return 'Gemini';
  }
}

function providerCapabilities(provider: ProviderName) {
  switch (provider) {
    case 'github':
      return ['repository-sync', 'branch-management', 'pull-requests', 'workflow-dispatch'];
    case 'github':
      return ['repository-sync', 'branch-management', 'merge-requests', 'pipeline-trigger'];
    case 'openai':
    case 'anthropic':
    case 'gemini':
      return ['ai-suggestions', 'diff-generation', 'token-estimation'];
  }
}

function defaultModelFor(provider: ProviderName) {
  switch (provider) {
    case 'openai':
      return OPENAI_LATEST_CHAT_MODEL;
    case 'anthropic':
      return process.env.ANTHROPIC_MODEL ?? 'claude-3-5-sonnet-latest';
    case 'gemini':
      return process.env.GEMINI_MODEL ?? 'gemini-2.0-flash';
    default:
      return null;
  }
}

function buildProviderSnapshot(provider: ProviderName): ProviderConfigSnapshot {
  const token = lookupProviderToken(provider);
  return {
    provider,
    label: providerLabel(provider),
    configured: Boolean(token),
    tokenPresent: Boolean(token),
    tokenHint: token ? maskSecret(token.token) : null,
    baseUrl: providerBaseUrl(provider),
    secretNames: providerSecretNames(provider),
    capabilities: providerCapabilities(provider),
    defaultModel: defaultModelFor(provider),
  };
}

interface OperationalMetric {
  operation: string;
  status: 'success' | 'failure' | 'queued' | 'warning';
  ownerId?: string;
  repoId?: string;
  provider?: ProviderName;
  actionType?: string;
  model?: string | null;
  durationMs?: number;
  estimatedTokens?: number;
  chargedTokens?: number;
  estimatedProviderCostUsd?: number | null;
  actualProviderCostUsd?: number | null;
  estimatedMarginUsd?: number | null;
  refundPolicy?: string | null;
  dailyCap?: number | null;
  pricingVersion?: string | null;
  remoteStatus?: string | null;
  remoteId?: string | number | null;
  errorCode?: string | null;
  errorMessage?: string | null;
  metadata?: Record<string, unknown>;
}

function normalizeError(error: unknown) {
  if (error instanceof HttpsError) {
    return {
      code: error.code,
      message: error.message,
    };
  }
  if (error instanceof Error) {
    return {
      code: 'internal',
      message: error.message,
    };
  }
  return {
    code: 'internal',
    message: 'Unknown error',
  };
}

function buildUsagePricingSnapshot(
  actionType: BillableActionType,
  provider: ProviderName,
  estimatedTokens: number,
) {
  if (!isBillableActionType(actionType)) {
    return null;
  }
  return buildCostSnapshot({
    actionType,
    provider,
    estimatedTokens,
  });
}

async function writeOperationalMetric(metric: OperationalMetric) {
  const payload = {
    ...metric,
    metadata: metric.metadata ?? null,
  };
  functions.logger.info('forgeai_metric', payload);
  try {
    await db.collection('opsMetrics').add({
      ...payload,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    const normalizedError = normalizeError(error);
    functions.logger.warn('forgeai_metric_write_failed', {
      operation: metric.operation,
      errorCode: normalizedError.code,
      errorMessage: normalizedError.message,
    });
  }
}

async function writeActivityEntry(
  ownerId: string,
  kind: string,
  subjectId: string,
  message: string,
  details?: Record<string, unknown>,
) {
  await db.collection('activity').add({
    ownerId,
    kind,
    subjectId,
    message,
    details: details ?? null,
    createdAt: FieldValue.serverTimestamp(),
  });
}

async function logWalletUsage(ownerId: string, payload: {
  repoId: string;
  actionType: BillableActionType;
  amount: number;
  provider: ProviderName;
  costPreview: number;
  status: 'reserved' | 'captured' | 'released' | 'queued' | 'completed';
  reason?: string;
  estimatedProviderCostUsd?: number | null;
  actualProviderCostUsd?: number | null;
  estimatedMarginUsd?: number | null;
  refundPolicy?: string | null;
  dailyCap?: number | null;
  pricingVersion?: string | null;
  model?: string | null;
  latencyMs?: number | null;
}) {
  await db.collection('wallets').doc(ownerId).collection('usage').add({
    ...payload,
    createdAt: FieldValue.serverTimestamp(),
  });
}

async function updateWalletState(
  ownerId: string,
  updater: (state: WalletState) => WalletState,
  usage?: Parameters<typeof logWalletUsage>[1],
) {
  const walletRef = db.collection('wallets').doc(ownerId);
  if (await isUnlimitedOwner(ownerId)) {
    await walletRef.set(unlimitedWalletDocument(), { merge: true });
    if (usage) {
      await logWalletUsage(ownerId, usage);
    }
    return;
  }
  await db.runTransaction(async transaction => {
    const snapshot = await transaction.get(walletRef);
    const current = normalizeWalletState(snapshot.data());
    const next = updater(current);

    if (next.balance < 0 || next.reserved < 0 || next.monthlyLimit < 0 || next.monthlyUsed < 0) {
      throw new HttpsError('failed-precondition', 'Wallet would become negative.');
    }

    transaction.set(
      walletRef,
      {
        balance: next.balance,
        reserved: next.reserved,
        monthlyLimit: next.monthlyLimit,
        monthlyUsed: next.monthlyUsed,
        currency: next.currency,
        planName: next.planName,
        dailyActionCap: next.dailyActionCap,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    if (usage) {
      const usageRef = walletRef.collection('usage').doc();
      transaction.set(usageRef, {
        ...usage,
        beforeBalance: current.balance,
        afterBalance: next.balance,
        beforeReserved: current.reserved,
        afterReserved: next.reserved,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  });
}

function startOfUtcDay(date = new Date()) {
  const start = new Date(date);
  start.setUTCHours(0, 0, 0, 0);
  return start;
}

async function countDailyReservedActions(
  ownerId: string,
  actionType: BillableActionType,
) {
  if (!isBillableActionType(actionType)) {
    return 0;
  }

  const usageSnapshot = await db
    .collection('wallets')
    .doc(ownerId)
    .collection('usage')
    .where('createdAt', '>=', startOfUtcDay())
    .get();

  let count = 0;
  for (const document of usageSnapshot.docs) {
    const data = document.data();
    if (data.actionType === actionType && data.status === 'reserved') {
      count += 1;
    }
  }
  return count;
}

/** Count total billable actions today (reserved + captured) for plan-based daily cap. */
async function countTotalDailyActions(ownerId: string): Promise<number> {
  const usageSnapshot = await db
    .collection('wallets')
    .doc(ownerId)
    .collection('usage')
    .where('createdAt', '>=', startOfUtcDay())
    .get();

  let count = 0;
  for (const document of usageSnapshot.docs) {
    const data = document.data();
    if (data.status === 'reserved' || data.status === 'captured') {
      count += 1;
    }
  }
  return count;
}

interface WalletUsageMetadata {
  actualProviderCostUsd?: number | null;
  latencyMs?: number | null;
  model?: string | null;
}

async function reserveWalletTokens(
  ownerId: string,
  repoId: string,
  amount: number,
  provider: ProviderName,
  costPreview: number,
  actionType: BillableActionType,
  reason?: string,
) {
  if (await isUnlimitedOwner(ownerId)) {
    const pricing = buildUsagePricingSnapshot(actionType, provider, costPreview);
    await updateWalletState(
      ownerId,
      state => state,
      {
        repoId,
        actionType,
        amount,
        provider,
        costPreview,
        status: 'reserved',
        reason,
        estimatedProviderCostUsd: pricing?.estimatedProviderCostUsd ?? null,
        actualProviderCostUsd: null,
        estimatedMarginUsd: pricing?.estimatedMarginUsd ?? null,
        refundPolicy: pricing?.refundPolicy ?? null,
        dailyCap: pricing?.dailyCap ?? null,
        pricingVersion: pricing?.pricingVersion ?? null,
        model: pricing?.assumedModel ?? null,
        latencyMs: null,
      },
    );
    return;
  }

  const walletRef = db.collection('wallets').doc(ownerId);
  const walletSnap = await walletRef.get();
  const state = normalizeWalletState(walletSnap.data());
  const totalDailyActions = await countTotalDailyActions(ownerId);
  if (state.dailyActionCap > 0 && totalDailyActions >= state.dailyActionCap) {
    throw new HttpsError(
      'resource-exhausted',
      `Daily action limit (${state.dailyActionCap}) reached for your plan.`,
    );
  }
  const pricing = buildUsagePricingSnapshot(actionType, provider, costPreview);
  if (pricing && isBillableActionType(actionType)) {
    const currentDailyUsage = await countDailyReservedActions(ownerId, actionType);
    if (currentDailyUsage >= pricing.dailyCap) {
      throw new HttpsError(
        'resource-exhausted',
        `Daily ${actionType} limit reached for this account.`,
      );
    }
  }
  await updateWalletState(
    ownerId,
    state => {
      if (state.balance - state.reserved < amount) {
        throw new HttpsError('failed-precondition', 'Insufficient token balance.');
      }
      return {
        ...state,
        reserved: state.reserved + amount,
      };
    },
    {
      repoId,
      actionType,
      amount,
      provider,
      costPreview,
      status: 'reserved',
      reason,
      estimatedProviderCostUsd: pricing?.estimatedProviderCostUsd ?? null,
      actualProviderCostUsd: null,
      estimatedMarginUsd: pricing?.estimatedMarginUsd ?? null,
      refundPolicy: pricing?.refundPolicy ?? null,
      dailyCap: pricing?.dailyCap ?? null,
      pricingVersion: pricing?.pricingVersion ?? null,
      model: pricing?.assumedModel ?? null,
      latencyMs: null,
    },
  );
}

async function releaseWalletTokens(
  ownerId: string,
  repoId: string,
  amount: number,
  provider: ProviderName,
  costPreview: number,
  actionType: BillableActionType,
  reason?: string,
  metadata: WalletUsageMetadata = {},
) {
  const pricing = buildUsagePricingSnapshot(actionType, provider, costPreview);
  await updateWalletState(
    ownerId,
    state => {
      if (state.reserved < amount) {
        throw new HttpsError('failed-precondition', 'Cannot release more tokens than are reserved.');
      }
      return {
        ...state,
        reserved: state.reserved - amount,
      };
    },
    {
      repoId,
      actionType,
      amount,
      provider,
      costPreview,
      status: 'released',
      reason,
      estimatedProviderCostUsd: pricing?.estimatedProviderCostUsd ?? null,
      actualProviderCostUsd: metadata.actualProviderCostUsd ?? null,
      estimatedMarginUsd: pricing?.estimatedMarginUsd ?? null,
      refundPolicy: pricing?.refundPolicy ?? null,
      dailyCap: pricing?.dailyCap ?? null,
      pricingVersion: pricing?.pricingVersion ?? null,
      model: metadata.model ?? pricing?.assumedModel ?? null,
      latencyMs: metadata.latencyMs ?? null,
    },
  );
}

async function captureWalletTokens(
  ownerId: string,
  repoId: string,
  amount: number,
  provider: ProviderName,
  costPreview: number,
  actionType: BillableActionType,
  reason?: string,
  metadata: WalletUsageMetadata = {},
) {
  const pricing = buildUsagePricingSnapshot(actionType, provider, costPreview);
  await updateWalletState(
    ownerId,
    state => {
      if (state.reserved < amount || state.balance < amount) {
        throw new HttpsError('failed-precondition', 'Cannot capture tokens without an existing reservation.');
      }
      if (state.monthlyLimit > 0 && state.monthlyUsed + amount > state.monthlyLimit) {
        throw new HttpsError('resource-exhausted', 'Monthly token limit reached.');
      }
      return {
        ...state,
        reserved: state.reserved - amount,
        balance: state.balance - amount,
        monthlyUsed: state.monthlyUsed + amount,
      };
    },
    {
      repoId,
      actionType,
      amount,
      provider,
      costPreview,
      status: 'captured',
      reason,
      estimatedProviderCostUsd: pricing?.estimatedProviderCostUsd ?? null,
      actualProviderCostUsd:
        metadata.actualProviderCostUsd ?? pricing?.estimatedProviderCostUsd ?? null,
      estimatedMarginUsd: pricing?.estimatedMarginUsd ?? null,
      refundPolicy: pricing?.refundPolicy ?? null,
      dailyCap: pricing?.dailyCap ?? null,
      pricingVersion: pricing?.pricingVersion ?? null,
      model: metadata.model ?? pricing?.assumedModel ?? null,
      latencyMs: metadata.latencyMs ?? null,
    },
  );
}

async function fetchJson<T>(url: string, init: RequestInit): Promise<T> {
  const response = await fetch(url, {
    ...init,
    signal: AbortSignal.timeout(20_000),
  });

  if (!response.ok) {
    const body = await response.text();
    const message = truncate(body || response.statusText, 220);
    const code =
      response.status === 400
        ? 'invalid-argument'
        : response.status === 401 || response.status === 403
        ? 'permission-denied'
        : response.status === 404
          ? 'not-found'
          : response.status === 409 || response.status === 412 || response.status === 422
            ? 'failed-precondition'
          : response.status === 429
            ? 'resource-exhausted'
            : 'internal';
    throw new HttpsError(code as any, `Remote provider error (${response.status}): ${message}`);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  const text = await response.text();
  if (text.trim().length === 0) {
    return undefined as T;
  }
  return JSON.parse(text) as T;
}

async function fetchText(url: string, init: RequestInit): Promise<string> {
  const response = await fetch(url, {
    ...init,
    signal: AbortSignal.timeout(20_000),
  });

  if (!response.ok) {
    const body = await response.text();
    const message = truncate(body || response.statusText, 220);
    const code =
      response.status === 401 || response.status === 403
        ? 'permission-denied'
        : response.status === 404
          ? 'not-found'
          : response.status === 429
            ? 'resource-exhausted'
            : 'internal';
    throw new HttpsError(code as any, `Remote provider error (${response.status}): ${message}`);
  }

  return await response.text();
}

function buildGitHubHeaders(token: string) {
  return {
    Accept: 'application/vnd.github+json',
    Authorization: `Bearer ${token}`,
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'CodeCatalystAI',
    'Content-Type': 'application/json',
  };
}

function buildOpenAiHeaders(token: string) {
  return {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  };
}

function buildAnthropicHeaders(token: string) {
  return {
    'x-api-key': token,
    'anthropic-version': '2023-06-01',
    'Content-Type': 'application/json',
  };
}

function buildGeminiHeaders() {
  return {
    'Content-Type': 'application/json',
  };
}

function parseJsonMaybe(value: string) {
  const trimmed = value.trim();
  try {
    return JSON.parse(trimmed) as unknown;
  } catch {
    const match = trimmed.match(/\{[\s\S]*\}/);
    if (!match) {
      return null;
    }
    try {
      return JSON.parse(match[0]) as unknown;
    } catch {
      return null;
    }
  }
}

function buildDiffLines(beforeContent: string, afterContent: string) {
  if (beforeContent === afterContent) {
    return [] as Array<{
      prefix: ' ' | '+' | '-';
      line: string;
      isAddition: boolean;
    }>;
  }

  const beforeLines = beforeContent.split('\n');
  const afterLines = afterContent.split('\n');
  let start = 0;

  while (
    start < beforeLines.length &&
    start < afterLines.length &&
    beforeLines[start] === afterLines[start]
  ) {
    start += 1;
  }

  let endBefore = beforeLines.length - 1;
  let endAfter = afterLines.length - 1;
  while (
    endBefore >= start &&
    endAfter >= start &&
    beforeLines[endBefore] === afterLines[endAfter]
  ) {
    endBefore -= 1;
    endAfter -= 1;
  }

  const lines: Array<{
    prefix: ' ' | '+' | '-';
    line: string;
    isAddition: boolean;
  }> = [];

  for (let index = Math.max(0, start - 2); index < start; index += 1) {
    lines.push({
      prefix: ' ',
      line: beforeLines[index] ?? '',
      isAddition: false,
    });
  }

  for (let index = start; index <= endBefore; index += 1) {
    lines.push({
      prefix: '-',
      line: beforeLines[index] ?? '',
      isAddition: false,
    });
  }

  for (let index = start; index <= endAfter; index += 1) {
    lines.push({
      prefix: '+',
      line: afterLines[index] ?? '',
      isAddition: true,
    });
  }

  for (
    let index = endAfter + 1;
    index < Math.min(afterLines.length, endAfter + 3);
    index += 1
  ) {
    lines.push({
      prefix: ' ',
      line: afterLines[index] ?? '',
      isAddition: false,
    });
  }

  return lines;
}

function buildUnifiedDiff(
  filePath: string,
  beforeContent: string,
  afterContent: string,
) {
  if (beforeContent === afterContent) {
    return `--- a/${filePath}\n+++ b/${filePath}\n@@\n  No code changes were generated.`;
  }

  const body = buildDiffLines(beforeContent, afterContent)
      .map(line => `${line.prefix}${line.line}`)
      .join('\n');
  return `--- a/${filePath}\n+++ b/${filePath}\n@@\n${body}`;
}

type RepoExecutionMode = 'normal' | 'deep';
type RepoExecutionAction = 'create' | 'modify' | 'delete';

interface RepoExecutionPreparedEdit {
  path: string;
  action: RepoExecutionAction;
  beforeContent: string;
  afterContent: string;
  summary: string;
  diffPreview: string;
  diffLines: ReturnType<typeof buildDiffLines>;
}

interface RepoExecutionSessionResult {
  sessionId: string;
  mode: RepoExecutionMode;
  summary: string;
  estimatedTokens: number;
  selectedFiles: string[];
  dependencyFiles: string[];
  steps: string[];
  edits: RepoExecutionPreparedEdit[];
}

function normalizeRepoExecutionPath(raw: string) {
  const normalized = normalizePromptRepoPath(raw);
  if (!normalized) {
    throw new HttpsError('invalid-argument', `Invalid repo path: ${raw}`);
  }
  return normalized;
}

function trimRepoExecutionContent(
  value: string,
  maxChars: number,
) {
  if (value.length <= maxChars) {
    return value;
  }
  const head = Math.max(2000, Math.floor(maxChars * 0.7));
  const tail = Math.max(1000, maxChars - head);
  return `${value.slice(0, head)}\n/* ... trimmed for context ... */\n${value.slice(value.length - tail)}`;
}

async function persistRepoIndexEntries(
  repoId: string,
  entries: RepoIndexEntry[],
) {
  const collection = db
    .collection('repositories')
    .doc(repoId)
    .collection('indexEntries');
  const batch = db.batch();
  for (const entry of entries.slice(0, 250)) {
    batch.set(
      collection.doc(safeDocId(entry.path)),
      {
        ...buildIndexEntryStoragePayload(entry),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  await batch.commit();
}

function executionSummaryForPath(path: string, action: RepoExecutionAction) {
  return action === 'create'
    ? `Create ${path}`
    : action === 'delete'
      ? `Delete ${path}`
      : `Update ${path}`;
}

async function hydrateRepoExecutionContext(params: {
  ownerId: string;
  repoId: string;
  repo: {
    ownerId?: string;
    provider?: 'github' | 'github';
    owner?: string;
    name?: string;
    defaultBranch?: string;
    fullName?: string;
    remoteId?: string | number | null;
    apiBaseUrl?: string | null;
  };
  prompt: string;
  currentFilePath?: string | null;
  deepMode: boolean;
  observer?: RepoExecutionObserver;
}) {
  const snapshot = await db
    .collection('repositories')
    .doc(params.repoId)
    .collection('files')
    .get();
  await params.observer?.onRepoScanned?.({ fileCount: snapshot.docs.length });
  const files = snapshot.docs
    .map<RepoIndexFileInput | null>(document => {
      const data = document.data() as {
        path?: string;
        type?: string;
        language?: string;
        content?: string;
        contentPreview?: string;
        sha?: string;
        isDeleted?: boolean;
      };
      if (data.isDeleted === true) {
        return null;
      }
      return {
        path: typeof data.path === 'string' && data.path.trim().length > 0 ? data.path : document.id,
        type: data.type ?? 'blob',
        language: data.language ?? guessLanguageFromPath(typeof data.path === 'string' ? data.path : document.id),
        content: data.content ?? '',
        contentPreview: data.contentPreview ?? data.content ?? '',
        sha: data.sha ?? null,
      };
    })
    .filter((file): file is RepoIndexFileInput => file != null);

  const fileMap = new Map<string, RepoIndexFileInput>(
    files.map(file => [file.path, { ...file }]),
  );
  const limit = params.deepMode ? 12 : 5;
  const preloadLimit = params.deepMode ? 16 : 8;

  let entries = buildRepoIndexEntries([...fileMap.values()]);
  let ranked = rankRepoIndexEntries({
    prompt: params.prompt,
    currentFilePath: params.currentFilePath,
    entries,
    deepMode: params.deepMode,
  });

  const preloadPaths = new Set<string>();
  if (params.currentFilePath) {
    preloadPaths.add(normalizeRepoExecutionPath(params.currentFilePath));
  }
  for (const entry of ranked.slice(0, preloadLimit)) {
    preloadPaths.add(entry.path);
  }

  for (const path of preloadPaths) {
    const existing = fileMap.get(path);
    if (existing?.content && existing.content.length > 0) {
      continue;
    }
    try {
      const loaded = await loadRepositoryFileContent(
        params.ownerId,
        params.repoId,
        path,
        {
          apiBaseUrl: params.repo.apiBaseUrl ?? undefined,
        },
      );
      fileMap.set(path, {
        path,
        type: 'blob',
        language: loaded.language,
        content: loaded.content,
        contentPreview: truncate(loaded.content, 1600),
        sha: null,
      });
      await params.observer?.onFileRead?.({
        path,
        source: loaded.source,
      });
    } catch (error) {
      functions.logger.warn('repo_execution.load_candidate_failed', {
        repoId: params.repoId,
        path,
        errorMessage: normalizeError(error).message,
      });
    }
  }

  entries = buildRepoIndexEntries([...fileMap.values()]);
  ranked = rankRepoIndexEntries({
    prompt: params.prompt,
    currentFilePath: params.currentFilePath,
    entries,
    deepMode: params.deepMode,
  });
  await persistRepoIndexEntries(params.repoId, entries);

  const selectedEntries = ranked.slice(0, limit);
  const dependencyPaths = pickDependencyCandidates(
    entries,
    selectedEntries.map(entry => entry.path),
    params.deepMode ? 6 : 3,
  );
  const dependencyEntries = dependencyPaths
    .map(path => entries.find(entry => entry.path === path))
    .filter((entry): entry is RepoIndexEntry => Boolean(entry));
  await params.observer?.onFilesSelected?.({
    selectedFiles: selectedEntries.map(entry => entry.path),
    dependencyFiles: dependencyEntries.map(entry => entry.path),
    inspectedFiles: ranked.slice(0, params.deepMode ? 16 : 8).map(entry => entry.path),
  });

  return {
    fileMap,
    entries,
    ranked,
    selectedEntries,
    dependencyEntries,
    repoStructure: buildRepoStructure(entries.map(entry => entry.path)),
  };
}

async function callRepoExecutionModel(params: {
  provider: AiProviderName;
  mode: RepoExecutionMode;
  contextPrompt: string;
  repairPrompt?: string;
}) {
  const tokenInfo = lookupProviderToken(params.provider);
  if (!tokenInfo) {
    throw new HttpsError('failed-precondition', `No ${providerLabel(params.provider)} token configured.`);
  }
  const model = defaultModelFor(params.provider);
  if (!model) {
    throw new HttpsError('failed-precondition', `No model configured for ${params.provider}.`);
  }
  const messages = [
    { role: 'system', content: buildRepoExecutionSystemPrompt() },
    {
      role: 'user',
      content: params.repairPrompt ?? params.contextPrompt,
    },
  ];
  const response = await fetchJson<{ choices?: Array<{ message?: { content?: string | null } }> }>(
    `${providerBaseUrl(params.provider)}/chat/completions`,
    {
      method: 'POST',
      headers: buildOpenAiHeaders(tokenInfo.token),
      body: JSON.stringify(
        buildOpenAiChatCompletionJsonBody({
          model,
          messages,
          temperature: 0.1,
          maxOutput: repoExecutionMaxOutputTokens(model, params.mode),
        }),
      ),
    },
  );
  return response.choices?.[0]?.message?.content?.trim() ?? '';
}

function validateRepoExecutionEdits(
  edits: ReturnType<typeof parseRepoExecutionResponse>,
  knownFiles: Map<string, RepoIndexFileInput>,
  allowedPaths: Set<string>,
  maxFiles: number,
) {
  if (edits.length === 0 || edits.length > maxFiles) {
    return false;
  }
  const seen = new Set<string>();
  for (const edit of edits) {
    const path = normalizePromptRepoPath(edit.path);
    if (!path) {
      return false;
    }
    if (!allowedPaths.has(path)) {
      return false;
    }
    if (seen.has(path)) {
      return false;
    }
    seen.add(path);
    const beforeContent = knownFiles.get(path)?.content ?? '';
    const fileExists = knownFiles.has(path);
    if (fileExists && edit.beforeContent !== beforeContent) {
      return false;
    }
    if (!fileExists && edit.beforeContent.trim().length > 0) {
      return false;
    }
    if (edit.beforeContent === edit.afterContent) {
      return false;
    }
  }
  return true;
}

async function generateRepoExecutionSession(params: {
  ownerId: string;
  repoId: string;
  prompt: string;
  currentFilePath?: string | null;
  deepMode: boolean;
  observer?: RepoExecutionObserver;
}) {
  const repo = await ensureRepositoryAccess(params.repoId, params.ownerId);
  const mode: RepoExecutionMode = params.deepMode ? 'deep' : 'normal';
  const preparedContext = await hydrateRepoExecutionContext({
    ownerId: params.ownerId,
    repoId: params.repoId,
    repo,
    prompt: params.prompt,
    currentFilePath: params.currentFilePath,
    deepMode: params.deepMode,
    observer: params.observer,
  });

  const maxCharsPerFile = params.deepMode ? 28_000 : 16_000;
  const contextPayload = {
    repoStructure: preparedContext.repoStructure,
    currentFilePath: params.currentFilePath ?? null,
    deepMode: params.deepMode,
    userPrompt: params.prompt,
    relevantFiles: preparedContext.selectedEntries.map(entry => ({
      path: entry.path,
      summary: entry.summary,
      reasons: entry.reasons,
      content:
          preparedContext.fileMap.get(entry.path)?.content ??
          preparedContext.fileMap.get(entry.path)?.contentPreview ??
          '',
    })),
    dependencyFiles: preparedContext.dependencyEntries.map(entry => ({
      path: entry.path,
      summary: entry.summary,
      reasons: ['dependency_context'],
      content: trimRepoExecutionContent(
        preparedContext.fileMap.get(entry.path)?.content ??
            preparedContext.fileMap.get(entry.path)?.contentPreview ??
            '',
        Math.floor(maxCharsPerFile * 0.6),
      ),
    })),
  };

  await params.observer?.onAiCalled?.({ attempt: 1, mode });
  let rawOutput = await callRepoExecutionModel({
    provider: 'openai',
    mode,
    contextPrompt: buildRepoExecutionUserPrompt(contextPayload),
  });
  let parsedEdits = parseRepoExecutionResponse(rawOutput);
  const maxFiles = params.deepMode ? 14 : 6;
  const allowedPaths = new Set(
    preparedContext.selectedEntries.map(entry => entry.path),
  );

  if (!validateRepoExecutionEdits(parsedEdits, preparedContext.fileMap, allowedPaths, maxFiles)) {
    await params.observer?.onRetrying?.({
      reason: 'Structured diff payload failed validation. Retrying with repair prompt.',
      attempt: 2,
    });
    await params.observer?.onAiCalled?.({ attempt: 2, mode });
    rawOutput = await callRepoExecutionModel({
      provider: 'openai',
      mode,
      contextPrompt: buildRepoExecutionUserPrompt(contextPayload),
      repairPrompt: buildRepoExecutionRepairPrompt(contextPayload, rawOutput),
    });
    parsedEdits = parseRepoExecutionResponse(rawOutput);
  }

  if (!validateRepoExecutionEdits(parsedEdits, preparedContext.fileMap, allowedPaths, maxFiles)) {
    throw new HttpsError(
      'internal',
      'The AI returned an invalid repo execution payload twice. Please retry with a narrower request.',
    );
  }

  const edits: RepoExecutionPreparedEdit[] = parsedEdits.map(edit => {
    const normalizedPath = normalizeRepoExecutionPath(edit.path);
    const beforeContent = preparedContext.fileMap.get(normalizedPath)?.content ?? '';
    const fileExists = preparedContext.fileMap.has(normalizedPath);
    const action: RepoExecutionAction =
      edit.afterContent.trim().length == 0
        ? 'delete'
        : fileExists
          ? 'modify'
          : 'create';
    return {
      path: normalizedPath,
      action,
      beforeContent,
      afterContent: edit.afterContent,
      summary: executionSummaryForPath(normalizedPath, action),
      diffPreview: buildUnifiedDiff(normalizedPath, beforeContent, edit.afterContent),
      diffLines: buildDiffLines(beforeContent, edit.afterContent),
    };
  });
  const estimatedTokens = Math.max(
    params.deepMode ? 420 : 240,
    Math.ceil(
      (
        params.prompt.length +
        preparedContext.selectedEntries.reduce((sum, entry) => sum + entry.approxTokens * 4, 0) +
        preparedContext.dependencyEntries.reduce((sum, entry) => sum + Math.floor(entry.approxTokens * 2.5), 0)
      ) / 4,
    ),
  );

  const sessionRef = db
    .collection('repositories')
    .doc(params.repoId)
    .collection('executionSessions')
    .doc();
  const steps = [
    'Indexed repository files',
    `Selected ${preparedContext.selectedEntries.length} relevant files`,
    `Loaded ${edits.length} executable diff block${edits.length == 1 ? '' : 's'}`,
    'Validated structured output',
  ];
  await sessionRef.set({
    repoId: params.repoId,
    ownerId: params.ownerId,
    prompt: params.prompt,
    mode,
    estimatedTokens,
    summary: summarizeRepoExecution(parsedEdits),
    selectedFiles: preparedContext.selectedEntries.map(entry => entry.path),
    dependencyFiles: preparedContext.dependencyEntries.map(entry => entry.path),
    inspectedFiles: preparedContext.ranked.slice(0, params.deepMode ? 16 : 8).map(entry => entry.path),
    steps,
    status: 'draft',
    edits,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await params.observer?.onDiffGenerated?.({
    editCount: edits.length,
    summary: summarizeRepoExecution(parsedEdits),
    sessionId: sessionRef.id,
  });

  return {
    sessionId: sessionRef.id,
    mode,
    estimatedTokens,
    summary: summarizeRepoExecution(parsedEdits),
    selectedFiles: preparedContext.selectedEntries.map(entry => entry.path),
    dependencyFiles: preparedContext.dependencyEntries.map(entry => entry.path),
    steps,
    edits,
  };
}

async function applyRepoExecutionSession(
  ownerId: string,
  repoId: string,
  sessionId: string,
) {
  await ensureRepositoryAccess(repoId, ownerId);
  const sessionRef = db
    .collection('repositories')
    .doc(repoId)
    .collection('executionSessions')
    .doc(sessionId);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) {
    throw new HttpsError('not-found', 'Repo execution session not found.');
  }
  const session = sessionSnap.data() as {
    status?: string;
    edits?: Array<{
      path?: string;
      action?: RepoExecutionAction;
      beforeContent?: string;
      afterContent?: string;
    }>;
  };
  const edits = Array.isArray(session.edits) ? session.edits : [];
  if (edits.length === 0) {
    throw new HttpsError('failed-precondition', 'Repo execution session has no edits to apply.');
  }

  const batch = db.batch();
  const fileCollection = db.collection('repositories').doc(repoId).collection('files');
  const appliedPaths: string[] = [];
  for (const edit of edits) {
    const path = normalizeRepoExecutionPath(asString(edit.path, 'executionSession.edits.path'));
    const action = (typeof edit.action === 'string' ? edit.action : 'modify') as RepoExecutionAction;
    const beforeContent = typeof edit.beforeContent === 'string' ? edit.beforeContent : '';
    const afterContent = typeof edit.afterContent === 'string' ? edit.afterContent : '';
    const fileRef = fileCollection.doc(safeDocId(path));
    appliedPaths.push(path);
    if (action === 'delete') {
      batch.set(
        fileRef,
        {
          path,
          content: '',
          baseContent: beforeContent,
          isDeleted: true,
          updatedAt: FieldValue.serverTimestamp(),
          source: 'repo_execution',
        },
        { merge: true },
      );
      continue;
    }
    batch.set(
      fileRef,
      {
        path,
        language: guessLanguageFromPath(path),
        content: afterContent,
        contentPreview: truncate(afterContent, 1200),
        baseContent: beforeContent,
        isDeleted: false,
        updatedAt: FieldValue.serverTimestamp(),
        source: 'repo_execution',
      },
      { merge: true },
    );
  }
  batch.set(
    sessionRef,
    {
      status: 'applied',
      appliedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await batch.commit();
  await writeActivityEntry(
    ownerId,
    'ai',
    sessionId,
    `Applied ${appliedPaths.length} repo execution change${appliedPaths.length === 1 ? '' : 's'} to the working copy.`,
    {
      repoId,
      appliedPaths,
    },
  );
  return appliedPaths;
}

async function validateAppliedRepoExecutionSession(
  repoId: string,
  sessionId: string,
) {
  const sessionSnapshot = await db
    .collection('repositories')
    .doc(repoId)
    .collection('executionSessions')
    .doc(sessionId)
    .get();
  if (!sessionSnapshot.exists) {
    return {
      ok: false,
      mismatchedPaths: ['<missing session>'],
    };
  }
  const session = sessionSnapshot.data() as {
    edits?: Array<{
      path?: string;
      action?: RepoExecutionAction;
      afterContent?: string;
    }>;
  };
  const edits = Array.isArray(session.edits) ? session.edits : [];
  const mismatchedPaths: string[] = [];
  for (const edit of edits) {
    const path = normalizeRepoExecutionPath(asString(edit.path, 'executionSession.edits.path'));
    const action = (typeof edit.action === 'string' ? edit.action : 'modify') as RepoExecutionAction;
    const expectedContent = typeof edit.afterContent === 'string' ? edit.afterContent : '';
    const fileSnapshot = await db
      .collection('repositories')
      .doc(repoId)
      .collection('files')
      .doc(safeDocId(path))
      .get();
    const fileData = fileSnapshot.data() as
      | { content?: string; isDeleted?: boolean }
      | undefined;
    if (action === 'delete') {
      if (!(fileData?.isDeleted === true || !fileSnapshot.exists)) {
        mismatchedPaths.push(path);
      }
      continue;
    }
    if ((fileData?.content ?? '') !== expectedContent) {
      mismatchedPaths.push(path);
    }
  }
  return {
    ok: mismatchedPaths.length === 0,
    mismatchedPaths,
  };
}

function parsePullRequestNumber(value: unknown) {
  if (typeof value === 'number' && Number.isInteger(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (/^\d+$/.test(trimmed)) {
      return Number.parseInt(trimmed, 10);
    }
  }
  return null;
}

async function stageNextAgentFollowUpOrComplete(ownerId: string, taskId: string) {
  const snapshot = await agentTaskRef(ownerId, taskId).get();
  if (!snapshot.exists) {
    return;
  }
  const task = safeAgentTask(snapshot.data());
  const metadata = isObject(task.metadata) ? task.metadata : {};
  if (task.followUpPlan.openPullRequest && metadata.pullRequestOpened !== true) {
    await putAgentTaskIntoApprovalState({
      ownerId,
      taskId,
      approval: buildAgentTaskPendingApproval({
        type: 'open_pull_request',
        title: 'Open a pull request?',
        description:
          'The agent has applied the workspace edits. Approve to create a branch, commit the working copy, and open a pull request.',
        actionLabel: 'Open PR',
        cancelLabel: 'Skip remote step',
      }),
      step: 'Awaiting approval to open a pull request',
      message: 'Workspace edits are ready. Approve before the agent creates a branch and opens a pull request.',
    });
    return;
  }
  if (
    task.followUpPlan.commitChanges &&
    !task.followUpPlan.openPullRequest &&
    metadata.commitCompleted !== true
  ) {
    await putAgentTaskIntoApprovalState({
      ownerId,
      taskId,
      approval: buildAgentTaskPendingApproval({
        type: 'commit_changes',
        title: 'Commit workspace changes?',
        description:
          'The agent has applied the workspace edits. Approve to commit the current working copy to the remote repository.',
        actionLabel: 'Commit changes',
        cancelLabel: 'Skip remote step',
      }),
      step: 'Awaiting approval to commit changes',
      message: 'Workspace edits are ready. Approve before the agent pushes a commit.',
    });
    return;
  }
  const pullRequestNumber = parsePullRequestNumber(metadata.pullRequestNumber);
  if (
    task.followUpPlan.mergePullRequest &&
    pullRequestNumber != null &&
    metadata.pullRequestMerged !== true
  ) {
    await putAgentTaskIntoApprovalState({
      ownerId,
      taskId,
      approval: buildAgentTaskPendingApproval({
        type: 'merge_pull_request',
        title: 'Merge the pull request?',
        description:
          `A pull request is ready (#${pullRequestNumber}). Approve to merge it into the target branch.`,
        actionLabel: 'Merge PR',
        cancelLabel: 'Leave PR open',
        payload: {
          pullRequestNumber,
        },
      }),
      step: 'Awaiting approval to merge the pull request',
      message: `Pull request #${pullRequestNumber} is ready. Approve before the agent merges it.`,
    });
    return;
  }
  if (task.followUpPlan.deployWorkflow && metadata.deployTriggered !== true) {
    await putAgentTaskIntoApprovalState({
      ownerId,
      taskId,
      approval: buildAgentTaskPendingApproval({
        type: 'deploy_workflow',
        title: 'Deploy from this repo?',
        description:
          'Approve to dispatch the deployment workflow after the workspace edits are in place.',
        actionLabel: 'Deploy',
        cancelLabel: 'Skip deploy',
      }),
      step: 'Awaiting approval to deploy',
      message: 'Workspace edits are ready. Approve before the agent dispatches the deploy workflow.',
    });
    return;
  }

  await completeAgentTaskNow(ownerId, taskId, summarizeAgentTaskResult(task));
}

async function executeAgentCommitFollowUp(
  ownerId: string,
  taskId: string,
  task: AgentTaskDocument,
) {
  const repo = await ensureRepositoryAccess(task.repoId, ownerId);
  const provider = repo.provider ?? 'github';
  const tokenInfo = await resolveProviderToken(ownerId, provider);
  if (!tokenInfo) {
    throw new HttpsError(
      'failed-precondition',
      `No ${providerLabel(provider)} token configured for remote commit.`,
    );
  }
  const fileChanges = await buildDraftFileChangesFromWorkingCopy(task.repoId);
  if (fileChanges.length === 0) {
    return {
      remoteId: null,
      remoteUrl: null,
      summary: 'No working-copy changes were available to commit.',
    };
  }
  const commitMessage =
    `feat(agent): ${truncate(normalizeText(task.prompt), 72)}` || 'feat(agent): apply generated changes';
  const result = await commitRemoteChanges(
    provider,
    tokenInfo.token,
    {
      owner: repo.owner ?? '',
      name: repo.name ?? '',
      remoteId: repo.remoteId ?? null,
      defaultBranch: repo.defaultBranch,
    },
    repo.defaultBranch ?? 'main',
    commitMessage,
    fileChanges,
    repo.apiBaseUrl ?? undefined,
  );
  return {
    remoteId: result.remoteId ?? null,
    remoteUrl: result.url ?? null,
    summary: 'Committed the applied workspace changes to the remote repository.',
  };
}

async function executeAgentPullRequestFollowUp(
  ownerId: string,
  taskId: string,
  task: AgentTaskDocument,
) {
  const repo = await ensureRepositoryAccess(task.repoId, ownerId);
  const provider = repo.provider ?? 'github';
  const tokenInfo = await resolveProviderToken(ownerId, provider);
  if (!tokenInfo) {
    throw new HttpsError(
      'failed-precondition',
      `No ${providerLabel(provider)} token configured for pull request creation.`,
    );
  }
  const fileChanges = await buildDraftFileChangesFromWorkingCopy(task.repoId);
  if (fileChanges.length === 0) {
    throw new HttpsError('failed-precondition', 'No working-copy changes were available to push.');
  }
  const branchName = `forgeai/agent-${taskId.slice(0, 8)}`;
  await createRemoteBranch(
    provider,
    tokenInfo.token,
    {
      owner: repo.owner ?? '',
      name: repo.name ?? '',
      remoteId: repo.remoteId ?? null,
      defaultBranch: repo.defaultBranch,
    },
    branchName,
    repo.defaultBranch ?? 'main',
    repo.apiBaseUrl ?? undefined,
  );
  const commitMessage =
    `feat(agent): ${truncate(normalizeText(task.prompt), 72)}` || 'feat(agent): apply generated changes';
  await commitRemoteChanges(
    provider,
    tokenInfo.token,
    {
      owner: repo.owner ?? '',
      name: repo.name ?? '',
      remoteId: repo.remoteId ?? null,
      defaultBranch: repo.defaultBranch,
    },
    branchName,
    commitMessage,
    fileChanges,
    repo.apiBaseUrl ?? undefined,
  );
  const prTitle = `Agent task: ${truncate(normalizeText(task.prompt), 88)}`;
  const prDescription =
    `Opened from CodeCatalystAI agent task ${taskId} after user approval.\n\n${task.executionSummary ?? task.prompt}`;
  const result = await openRemotePullRequest(
    provider,
    tokenInfo.token,
    {
      owner: repo.owner ?? '',
      name: repo.name ?? '',
      remoteId: repo.remoteId ?? null,
      defaultBranch: repo.defaultBranch,
    },
    branchName,
    repo.defaultBranch,
    prTitle,
    prDescription,
    repo.apiBaseUrl ?? undefined,
  );
  return {
    remoteId: result.remoteId ?? null,
    remoteUrl: result.url ?? null,
    branchName,
    pullRequestNumber: parsePullRequestNumber(result.remoteId),
    summary: 'Created a branch, pushed the generated changes, and opened a pull request.',
  };
}

async function executeAgentMergeFollowUp(
  ownerId: string,
  task: AgentTaskDocument,
  pullRequestNumber: number,
) {
  const repo = await ensureRepositoryAccess(task.repoId, ownerId);
  const provider = repo.provider ?? 'github';
  const tokenInfo = await resolveProviderToken(ownerId, provider);
  if (!tokenInfo) {
    throw new HttpsError(
      'failed-precondition',
      `No ${providerLabel(provider)} token configured for merge execution.`,
    );
  }
  const result = await mergeRemotePullRequest(
    provider,
    tokenInfo.token,
    {
      owner: repo.owner ?? '',
      name: repo.name ?? '',
      remoteId: repo.remoteId ?? null,
    },
    pullRequestNumber,
    'merge',
    repo.apiBaseUrl ?? undefined,
  );
  return {
    remoteUrl: result.url ?? null,
    summary: `Merged pull request #${pullRequestNumber}.`,
  };
}

async function executeAgentDeployFollowUp(
  ownerId: string,
  task: AgentTaskDocument,
) {
  const repo = await ensureRepositoryAccess(task.repoId, ownerId);
  const provider = repo.provider ?? 'github';
  const tokenInfo = await resolveProviderToken(ownerId, provider);
  if (!tokenInfo) {
    throw new HttpsError(
      'failed-precondition',
      `No ${providerLabel(provider)} token configured for deployment.`,
    );
  }
  const workflowName = 'deploy-functions.yml';
  const result = await triggerCheckExecution(
    provider,
    tokenInfo.token,
    {
      owner: repo.owner ?? '',
      name: repo.name ?? '',
      remoteId: repo.remoteId ?? null,
      defaultBranch: repo.defaultBranch,
    },
    workflowName,
    repo.defaultBranch ?? 'main',
    {},
    repo.apiBaseUrl ?? undefined,
  );
  return {
    remoteId: result.remoteId ?? null,
    remoteUrl: result.logsUrl ?? null,
    summary: `Dispatched ${workflowName} for ${repo.fullName ?? task.repoId}.`,
  };
}

async function resolveApprovedAgentTaskContinuation(
  ownerId: string,
  taskId: string,
  task: AgentTaskDocument,
  approval: AgentTaskPendingApproval,
) {
  const taskReference = agentTaskRef(ownerId, taskId);
  const now = Date.now();
  switch (approval.type) {
    case 'resume_task': {
      await taskReference.set(
        {
          pendingApproval: null,
          phase: 'analyze_request',
          currentStep: 'Resuming task',
          currentPass: task.currentPass + 1,
          updatedAtMs: now,
        },
        { merge: true },
      );
      return;
    }
    case 'apply_changes': {
      await appendAgentTaskEvent({
        ownerId,
        taskId,
        type: 'task_resumed',
        step: 'Applying approved edits',
        message: 'Approval received. Applying the generated edits to the working copy.',
        status: 'running',
        phase: 'apply_edits',
      });
      const sessionId = asOptionalString(task.sessionId);
      if (!sessionId) {
        throw new HttpsError('failed-precondition', 'Task has no execution session to apply.');
      }
      await taskReference.set(
        {
          pendingApproval: null,
          phase: 'apply_edits',
          currentStep: 'Applying approved edits',
          updatedAtMs: now,
        },
        { merge: true },
      );
      const appliedPaths = await applyRepoExecutionSession(ownerId, task.repoId, sessionId);
      await taskReference.set(
        {
          filesTouched: appliedPaths,
          metadata: {
            ...(isObject(task.metadata) ? task.metadata : {}),
            appliedChanges: true,
          },
          updatedAtMs: Date.now(),
        },
        { merge: true },
      );
      await appendAgentTaskEvent({
        ownerId,
        taskId,
        type: 'edits_applied',
        step: 'Working copy updated',
        message: `Applied ${appliedPaths.length} file change${appliedPaths.length === 1 ? '' : 's'} to the working copy.`,
        status: 'running',
        phase: 'apply_edits',
        data: {
          filesTouched: appliedPaths,
        },
      });
      await taskReference.set(
        {
          phase: 'validate',
          currentStep: 'Validating applied edits',
          updatedAtMs: Date.now(),
        },
        { merge: true },
      );
      await appendAgentTaskEvent({
        ownerId,
        taskId,
        type: 'validation_started',
        step: 'Validating applied edits',
        message: 'Verifying that the working copy matches the approved diff.',
        status: 'running',
        phase: 'validate',
      });
      const validation = await validateAppliedRepoExecutionSession(task.repoId, sessionId);
      if (!validation.ok) {
        const message =
          `Working-copy validation failed for ${validation.mismatchedPaths.join(', ')}.`;
        await taskReference.set(
          {
            latestValidationError: message,
            updatedAtMs: Date.now(),
          },
          { merge: true },
        );
        await appendAgentTaskEvent({
          ownerId,
          taskId,
          type: 'validation_failed',
          step: 'Validation failed',
          message,
          status: 'running',
          phase: 'validate',
          data: {
            mismatchedPaths: validation.mismatchedPaths,
          },
        });
        await failAgentTaskNow(ownerId, taskId, message);
        return;
      }
      await stageNextAgentFollowUpOrComplete(ownerId, taskId);
      return;
    }
    case 'commit_changes': {
      await appendAgentTaskEvent({
        ownerId,
        taskId,
        type: 'remote_action_started',
        step: 'Committing workspace changes',
        message: 'Creating a remote commit from the approved working copy.',
        status: 'running',
        phase: 'follow_up',
      });
      const result = await executeAgentCommitFollowUp(ownerId, taskId, task);
      await taskReference.set(
        {
          pendingApproval: null,
          metadata: {
            ...(isObject(task.metadata) ? task.metadata : {}),
            commitCompleted: true,
            commitRemoteId: result.remoteId,
            commitRemoteUrl: result.remoteUrl,
          },
          resultSummary: result.summary,
          updatedAtMs: Date.now(),
        },
        { merge: true },
      );
      await appendAgentTaskEvent({
        ownerId,
        taskId,
        type: 'remote_action_completed',
        step: 'Remote commit created',
        message: result.summary,
        status: 'running',
        phase: 'follow_up',
        data: {
          remoteUrl: result.remoteUrl,
          remoteId: result.remoteId,
        },
      });
      await stageNextAgentFollowUpOrComplete(ownerId, taskId);
      return;
    }
    case 'open_pull_request': {
      await appendAgentTaskEvent({
        ownerId,
        taskId,
        type: 'remote_action_started',
        step: 'Opening a pull request',
        message: 'Creating a branch, pushing the approved working copy, and opening a pull request.',
        status: 'running',
        phase: 'follow_up',
      });
      const result = await executeAgentPullRequestFollowUp(ownerId, taskId, task);
      await taskReference.set(
        {
          pendingApproval: null,
          metadata: {
            ...(isObject(task.metadata) ? task.metadata : {}),
            commitCompleted: true,
            pullRequestOpened: true,
            pullRequestNumber: result.pullRequestNumber,
            pullRequestRemoteId: result.remoteId,
            pullRequestUrl: result.remoteUrl,
            branchName: result.branchName,
          },
          resultSummary: result.summary,
          updatedAtMs: Date.now(),
        },
        { merge: true },
      );
      await appendAgentTaskEvent({
        ownerId,
        taskId,
        type: 'remote_action_completed',
        step: 'Pull request opened',
        message: result.summary,
        status: 'running',
        phase: 'follow_up',
        data: {
          remoteUrl: result.remoteUrl,
          branchName: result.branchName,
          pullRequestNumber: result.pullRequestNumber,
        },
      });
      await stageNextAgentFollowUpOrComplete(ownerId, taskId);
      return;
    }
    case 'merge_pull_request': {
      const pullRequestNumber = parsePullRequestNumber(
        approval.payload.pullRequestNumber ??
          (isObject(task.metadata) ? task.metadata.pullRequestNumber : null),
      );
      if (pullRequestNumber == null) {
        throw new HttpsError(
          'failed-precondition',
          'No pull request number is available for merge.',
        );
      }
      await appendAgentTaskEvent({
        ownerId,
        taskId,
        type: 'remote_action_started',
        step: 'Merging pull request',
        message: `Merging pull request #${pullRequestNumber}.`,
        status: 'running',
        phase: 'follow_up',
      });
      const result = await executeAgentMergeFollowUp(ownerId, task, pullRequestNumber);
      await taskReference.set(
        {
          pendingApproval: null,
          metadata: {
            ...(isObject(task.metadata) ? task.metadata : {}),
            pullRequestMerged: true,
            mergeRemoteUrl: result.remoteUrl,
          },
          resultSummary: result.summary,
          updatedAtMs: Date.now(),
        },
        { merge: true },
      );
      await appendAgentTaskEvent({
        ownerId,
        taskId,
        type: 'remote_action_completed',
        step: 'Pull request merged',
        message: result.summary,
        status: 'running',
        phase: 'follow_up',
        data: {
          remoteUrl: result.remoteUrl,
          pullRequestNumber,
        },
      });
      await stageNextAgentFollowUpOrComplete(ownerId, taskId);
      return;
    }
    case 'deploy_workflow': {
      await appendAgentTaskEvent({
        ownerId,
        taskId,
        type: 'remote_action_started',
        step: 'Dispatching deploy workflow',
        message: 'Triggering the deployment workflow after user approval.',
        status: 'running',
        phase: 'follow_up',
      });
      const result = await executeAgentDeployFollowUp(ownerId, task);
      await taskReference.set(
        {
          pendingApproval: null,
          metadata: {
            ...(isObject(task.metadata) ? task.metadata : {}),
            deployTriggered: true,
            deployRemoteId: result.remoteId,
            deployRemoteUrl: result.remoteUrl,
          },
          resultSummary: result.summary,
          updatedAtMs: Date.now(),
        },
        { merge: true },
      );
      await appendAgentTaskEvent({
        ownerId,
        taskId,
        type: 'remote_action_completed',
        step: 'Deploy workflow queued',
        message: result.summary,
        status: 'running',
        phase: 'follow_up',
        data: {
          remoteUrl: result.remoteUrl,
          remoteId: result.remoteId,
        },
      });
      await stageNextAgentFollowUpOrComplete(ownerId, taskId);
      return;
    }
    case 'risky_operation': {
      await completeAgentTaskNow(
        ownerId,
        taskId,
        'Risky operation approval was acknowledged. Continue from the existing repo controls for any destructive remote step.',
      );
      return;
    }
  }
}

async function processAgentTaskRun(ownerId: string, taskId: string, runToken: number) {
  let task = await assertAgentTaskStillRunnable(ownerId, taskId, runToken);
  const taskReference = agentTaskRef(ownerId, taskId);
  const pendingApproval = task.pendingApproval;
  if (pendingApproval && pendingApproval.status !== 'pending') {
    if (pendingApproval.status === 'rejected') {
      if (pendingApproval.type === 'apply_changes' || pendingApproval.type === 'resume_task') {
        await cancelAgentTaskNow(
          ownerId,
          taskId,
          pendingApproval.type === 'apply_changes'
            ? 'Task cancelled after the proposed diff was rejected.'
            : 'Task cancelled while paused.',
        );
        return;
      }
      await taskReference.set(
        {
          pendingApproval: null,
          updatedAtMs: Date.now(),
        },
        { merge: true },
      );
      await completeAgentTaskNow(
        ownerId,
        taskId,
        'Remote follow-up step was skipped after rejection. Workspace edits remain available in the app.',
      );
      return;
    }
    await resolveApprovedAgentTaskContinuation(ownerId, taskId, task, pendingApproval);
    return;
  }

  await taskReference.set(
    {
      phase: 'inspect_repo',
      currentStep: 'Inspecting workspace',
      currentPass: task.currentPass + 1,
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
  task = await assertAgentTaskStillRunnable(ownerId, taskId, runToken);

  const observed = {
    selectedFiles: [] as string[],
    dependencyFiles: [] as string[],
    inspectedFiles: [] as string[],
  };
  const session = await generateRepoExecutionSession({
    ownerId,
    repoId: task.repoId,
    prompt: task.prompt,
    currentFilePath: task.currentFilePath ?? undefined,
    deepMode: task.deepMode,
    observer: {
      onRepoScanned: async details => {
        await appendAgentTaskEvent({
          ownerId,
          taskId,
          type: 'repo_scanned',
          step: 'Indexed repository snapshot',
          message: `Indexed ${details.fileCount} repository file${details.fileCount === 1 ? '' : 's'}.`,
          status: 'running',
          phase: 'inspect_repo',
          data: {
            fileCount: details.fileCount,
          },
        });
      },
      onFilesSelected: async details => {
        observed.selectedFiles = details.selectedFiles;
        observed.dependencyFiles = details.dependencyFiles;
        observed.inspectedFiles = details.inspectedFiles;
        await appendAgentTaskEvent({
          ownerId,
          taskId,
          type: 'files_selected',
          step: 'Selected relevant files',
          message: `Selected ${details.selectedFiles.length} file${details.selectedFiles.length === 1 ? '' : 's'} for the agent pass.`,
          status: 'running',
          phase: 'inspect_repo',
          data: {
            selectedFiles: details.selectedFiles,
            dependencyFiles: details.dependencyFiles,
            inspectedFiles: details.inspectedFiles,
          },
        });
      },
      onFileRead: async details => {
        await appendAgentTaskEvent({
          ownerId,
          taskId,
          type: 'file_read',
          step: 'Loaded file content',
          message: `Loaded ${details.path} from ${details.source}.`,
          status: 'running',
          phase: 'inspect_repo',
          data: {
            path: details.path,
            source: details.source,
          },
        });
      },
      onAiCalled: async details => {
        await appendAgentTaskEvent({
          ownerId,
          taskId,
          type: 'ai_called',
          step: 'Calling model',
          message:
            details.attempt === 1
              ? 'Calling the model to generate the first draft diff.'
              : 'Calling the model again with repair instructions.',
          status: 'running',
          phase: 'generate_diff',
          data: {
            attempt: details.attempt,
            mode: details.mode,
          },
        });
      },
      onRetrying: async details => {
        await appendAgentTaskEvent({
          ownerId,
          taskId,
          type: 'retrying',
          step: 'Retrying generation',
          message: details.reason,
          status: 'running',
          phase: 'generate_diff',
          data: {
            attempt: details.attempt,
          },
        });
      },
      onDiffGenerated: async details => {
        await appendAgentTaskEvent({
          ownerId,
          taskId,
          type: 'diff_generated',
          step: 'Generated reviewable diff',
          message: `Prepared ${details.editCount} reviewable file change${details.editCount === 1 ? '' : 's'}.`,
          status: 'running',
          phase: 'generate_diff',
          data: {
            editCount: details.editCount,
            summary: details.summary,
            sessionId: details.sessionId,
          },
        });
      },
    },
  });

  task = await assertAgentTaskStillRunnable(ownerId, taskId, runToken);
  await taskReference.set(
    {
      phase: 'validate',
      currentStep: 'Validating generated diff',
      sessionId: session.sessionId,
      executionSummary: session.summary,
      selectedFiles: observed.selectedFiles.length > 0 ? observed.selectedFiles : session.selectedFiles,
      dependencyFiles:
        observed.dependencyFiles.length > 0
          ? observed.dependencyFiles
          : session.dependencyFiles,
      inspectedFiles:
        observed.inspectedFiles.length > 0
          ? observed.inspectedFiles
          : session.selectedFiles,
      filesTouched: session.edits.map(edit => edit.path),
      diffCount: session.edits.length,
      estimatedTokens: session.estimatedTokens,
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
  await appendAgentTaskEvent({
    ownerId,
    taskId,
    type: 'validation_started',
    step: 'Validating generated diff',
    message: 'Checking the proposed diff against agent guardrails.',
    status: 'running',
    phase: 'validate',
    data: {
      diffCount: session.edits.length,
      estimatedTokens: session.estimatedTokens,
    },
  });

  const validationErrors: string[] = [];
  if (session.edits.length > task.guardrails.maxFileTouchCount) {
    validationErrors.push(
      `Diff touches ${session.edits.length} files, exceeding the limit of ${task.guardrails.maxFileTouchCount}.`,
    );
  }
  if (session.estimatedTokens > task.guardrails.maxTokenBudget) {
    validationErrors.push(
      `Estimated token usage (${session.estimatedTokens}) exceeds the task budget of ${task.guardrails.maxTokenBudget}.`,
    );
  }
  if (validationErrors.length > 0) {
    const message = validationErrors.join(' ');
    await taskReference.set(
      {
        latestValidationError: message,
        updatedAtMs: Date.now(),
      },
      { merge: true },
    );
    await appendAgentTaskEvent({
      ownerId,
      taskId,
      type: 'validation_failed',
      step: 'Validation failed',
      message,
      status: 'running',
      phase: 'validate',
      data: {
        errors: validationErrors,
      },
    });
    await failAgentTaskNow(ownerId, taskId, message);
    return;
  }

  const riskySuffix = task.followUpPlan.riskyOperation
    ? ' The original prompt included a risky operation request, so the agent is pausing for approval before writing anything.'
    : '';
  await putAgentTaskIntoApprovalState({
    ownerId,
    taskId,
    approval: buildAgentTaskPendingApproval({
      type: 'apply_changes',
      title: 'Apply the generated edits?',
      description:
        `The agent prepared ${session.edits.length} file change${session.edits.length === 1 ? '' : 's'} across the working copy. Review the diff before applying it.${riskySuffix}`,
      actionLabel: 'Apply edits',
      cancelLabel: 'Reject diff',
      payload: {
        sessionId: session.sessionId,
        diffCount: session.edits.length,
      },
    }),
    step: 'Awaiting approval to apply edits',
    message: 'Review the generated diff. The workspace stays locked until you approve, reject, or cancel this task.',
  });
}

async function buildDraftFileChangesFromWorkingCopy(repoId: string) {
  const snapshot = await db
    .collection('repositories')
    .doc(repoId)
    .collection('files')
    .get();
  const changes: GitFileChange[] = [];
  for (const document of snapshot.docs) {
    const data = document.data() as {
      path?: string;
      content?: string;
      baseContent?: string;
      sha?: string;
      isDeleted?: boolean;
    };
    const path = typeof data.path === 'string' ? data.path.trim() : '';
    if (!path) {
      continue;
    }
    const content = typeof data.content === 'string' ? data.content : '';
    const baseContent = typeof data.baseContent === 'string' ? data.baseContent : '';
    const sha = typeof data.sha === 'string' && data.sha.trim().length > 0 ? data.sha.trim() : undefined;
    const isDeleted = data.isDeleted === true;
    if (isDeleted) {
      if (sha || baseContent.length > 0) {
        changes.push({
          path,
          content: '',
          sha,
          mode: 'delete',
        });
      }
      continue;
    }
    if (content === baseContent) {
      continue;
    }
    changes.push({
      path,
      content,
      sha,
      mode: sha ? 'update' : 'create',
    });
  }
  return changes;
}

function toAiSuggestionDraft(
  providerUsed: ProviderName,
  model: string | null,
  responseText: string,
  fallbackContext: {
    repoFullName: string;
    filePath: string;
    prompt: string;
    baseContent?: string;
  },
): AiSuggestionDraft {
  const parsed = parseJsonMaybe(responseText);
  if (isObject(parsed)) {
    const afterContent =
      asOptionalString(parsed.modifiedContent) ??
      asOptionalString(parsed.afterContent) ??
      fallbackContext.baseContent ??
      '';
    return {
      providerUsed,
      model,
      summary: asOptionalString(parsed.summary) ?? `AI suggestion for ${fallbackContext.filePath}`,
      rationale:
        asOptionalString(parsed.rationale) ??
        `Generated from provider response for ${fallbackContext.repoFullName}.`,
      afterContent,
      diffPreview:
        asOptionalString(parsed.diffPreview) ??
        buildUnifiedDiff(
          fallbackContext.filePath,
          fallbackContext.baseContent ?? '',
          afterContent,
        ),
      riskNotes:
        Array.isArray(parsed.riskNotes) && parsed.riskNotes.every(item => typeof item === 'string')
          ? parsed.riskNotes.map(item => item.trim()).filter(Boolean)
          : [],
      suggestedCommitMessage:
        asOptionalString(parsed.suggestedCommitMessage) ??
        `Update ${fallbackContext.filePath}`,
      estimatedTokens: Number(parsed.estimatedTokens ?? 0) || 0,
      source: 'provider',
    };
  }

  const summaryLine = normalizeText(responseText.split('\n').find(line => line.trim().length > 0) ?? responseText);
  return {
    providerUsed,
    model,
    summary: summaryLine || `AI suggestion for ${fallbackContext.filePath}`,
    rationale: `The provider returned non-JSON output, so CodeCatalystAI preserved it as a reviewable draft.`,
    afterContent: fallbackContext.baseContent ?? '',
    diffPreview: truncate(
      buildUnifiedDiff(
        fallbackContext.filePath,
        fallbackContext.baseContent ?? '',
        fallbackContext.baseContent ?? '',
      ),
      1600,
    ),
    riskNotes: ['Provider output was not structured JSON. Review the draft carefully.'],
    suggestedCommitMessage: `Update ${fallbackContext.filePath}`,
    estimatedTokens: Math.max(120, Math.ceil(responseText.length / 4)),
    source: 'provider-text',
  };
}

function buildFallbackDraft(fallbackContext: {
  repoFullName: string;
  filePath: string;
  prompt: string;
  baseContent?: string;
}) {
  const promptSummary = truncate(normalizeText(fallbackContext.prompt), 120);
  return {
    providerUsed: 'openai' as const,
    model: null,
    summary: `Drafted mobile-safe change for ${fallbackContext.filePath}`,
    rationale: `CodeCatalystAI could not reach an AI provider, so it created a conservative draft from the user prompt.`,
    afterContent: fallbackContext.baseContent ?? '',
    diffPreview: buildUnifiedDiff(
      fallbackContext.filePath,
      fallbackContext.baseContent ?? '',
      fallbackContext.baseContent ?? '',
    ),
    riskNotes: ['No AI provider token was configured or the provider call failed.'],
    suggestedCommitMessage: `Update ${fallbackContext.filePath}`,
    estimatedTokens: Math.max(120, Math.ceil((fallbackContext.prompt.length + (fallbackContext.baseContent?.length ?? 0)) / 4)),
    source: 'fallback',
  } satisfies AiSuggestionDraft;
}

async function callAiProvider(
  provider: AiProviderName,
  prompt: string,
  context: {
    repoFullName: string;
    filePath: string;
    baseContent?: string;
  },
  modelOverride?: string,
) {
  const tokenInfo = lookupProviderToken(provider);
  if (!tokenInfo) {
    throw new HttpsError('failed-precondition', `No ${providerLabel(provider)} token is configured.`);
  }

  const model = modelOverride ?? defaultModelFor(provider);
  const systemPrompt =
    'You are CodeCatalystAI, a mobile-first code assistant. The user describes changes in everyday language. You have full authority to edit this path: apply their request completely—rewrite the whole file, refactor structure, add or remove large sections, or replace the entire contents when that is what they want. If baseContent is missing or empty, treat the file as new and return the complete file text they asked for. Return only valid JSON with keys summary, rationale, modifiedContent, diffPreview, riskNotes, suggestedCommitMessage, and estimatedTokens. modifiedContent must always be the full file after your edits (never a fragment or patch-only body). For summary, rationale, and riskNotes: write like a helpful teammate—short, natural sentences in plain English. Do not use log-style labels (e.g. "Summary:", "INFO:", "Output:"), bullet dumps, or stiff technical report tone. suggestedCommitMessage should read like a normal human git message, not a machine tag. Mention any risky or destructive edits briefly in riskNotes.';
  const userPrompt = JSON.stringify({
    repoFullName: context.repoFullName,
    filePath: context.filePath,
    prompt,
    baseContent: truncate(context.baseContent ?? '', AI_SUGGESTION_BASE_CONTENT_MAX_CHARS),
  });

  const maxOut = suggestionMaxOutputTokens(provider);

  if (provider === 'openai') {
    const openaiModel = model ?? OPENAI_LATEST_CHAT_MODEL;
    const response = await fetchJson<{ choices: Array<{ message?: { content?: string | null } }> }>(
      `${providerBaseUrl(provider)}/chat/completions`,
      {
        method: 'POST',
        headers: buildOpenAiHeaders(tokenInfo.token),
        body: JSON.stringify(
          buildOpenAiChatCompletionJsonBody({
            model: openaiModel,
            temperature: 0.2,
            maxOutput: maxOut,
            responseFormat: { type: 'json_object' },
            messages: [
              { role: 'system', content: systemPrompt },
              { role: 'user', content: userPrompt },
            ],
          }),
        ),
      },
    );

    return response.choices[0]?.message?.content ?? '{}';
  }

  if (provider === 'anthropic') {
    const response = await fetchJson<{
      content?: Array<{ text?: string }>;
    }>(`${providerBaseUrl(provider)}/messages`, {
      method: 'POST',
      headers: buildAnthropicHeaders(tokenInfo.token),
      body: JSON.stringify({
        model,
        max_tokens: maxOut,
        temperature: 0.2,
        system: systemPrompt,
        messages: [{ role: 'user', content: userPrompt }],
      }),
    });

    return response.content?.[0]?.text ?? '{}';
  }

  const geminiResponse = await fetchJson<{
    candidates?: Array<{
      content?: {
        parts?: Array<{ text?: string }>;
      };
    }>;
  }>(
    `${providerBaseUrl(provider)}/models/${model}:generateContent?key=${encodeURIComponent(tokenInfo.token)}`,
    {
      method: 'POST',
      headers: buildGeminiHeaders(),
      body: JSON.stringify({
        systemInstruction: {
          parts: [{ text: systemPrompt }],
        },
        contents: [
          {
            role: 'user',
            parts: [{ text: userPrompt }],
          },
        ],
        generationConfig: {
          temperature: 0.2,
          maxOutputTokens: maxOut,
          responseMimeType: 'application/json',
        },
      }),
    },
  );

  return geminiResponse.candidates?.[0]?.content?.parts?.[0]?.text ?? '{}';
}

/** Runs a single sub-agent with a role and task. Used when the main agent recruits help. */
async function runSubAgent(
  provider: AiProviderName,
  role: string,
  task: string,
  sharedContext: string,
): Promise<string> {
  const subSystemPrompt = `You are helping CodeCatalystAI as: ${role || 'assistant'}. Context (repos/files): ${truncate(sharedContext, 1500)}. Answer the task in plain, conversational English—like explaining to a colleague. No log prefixes, no fake "DEBUG/INFO" lines, no dense numbered pipelines unless the user clearly asked for steps. Be concise and useful.`;
  return callAiChatText(provider, subSystemPrompt, task, [], []);
}

const RECRUIT_AGENT_TOOL = {
  type: 'function' as const,
  function: {
    name: 'recruit_agent',
    description:
      'Recruit another AI agent to handle a specialized subtask. Use when you need focused expertise (e.g. security review, code explanation, naming, refactor plan). Provide the role and the exact task.',
    parameters: {
      type: 'object',
      properties: {
        role: {
          type: 'string',
          description: 'The role or expertise of the sub-agent (e.g. "security reviewer", "naming specialist").',
        },
        task: {
          type: 'string',
          description: 'The precise task or question for the sub-agent.',
        },
      },
      required: ['task'],
    },
  },
};

/** Persist Prompt-suggested file changes to the repo working copy (Firestore), not to GitHub. */
const APPLY_FILE_EDITS_TOOL = {
  type: 'function' as const,
  function: {
    name: 'apply_file_edits',
    description:
      "Save implementation work to the user's in-app repository draft (synced Firestore files). " +
      'Call this when the user wants real changes, not only explanation. For create/modify you must pass the COMPLETE file text. ' +
      'You may call multiple times. Nothing is pushed to Git until the user commits from the app.',
    parameters: {
      type: 'object',
      properties: {
        edits: {
          type: 'array',
          description: 'Files to create, fully replace, or remove from the working copy.',
          items: {
            type: 'object',
            properties: {
              path: {
                type: 'string',
                description: 'Repo-relative path (e.g. lib/main.dart). No parent-directory segments.',
              },
              action: { type: 'string', enum: ['create', 'modify', 'delete'] },
              content: {
                type: 'string',
                description: 'Full file body for create/modify. Empty string allowed; omit for delete.',
              },
            },
            required: ['path', 'action'],
          },
        },
      },
      required: ['edits'],
    },
  },
};

type PromptAppliedEditAction = 'create' | 'modify' | 'delete';

const MAX_PROMPT_APPLY_FILES = 16;
const MAX_PROMPT_APPLY_SINGLE_FILE_CHARS = 350_000;
const MAX_PROMPT_APPLY_TOTAL_CHARS = 450_000;
const DEFAULT_AGENT_RECRUIT_ROUNDS = 3;
const REPO_PROMPT_TOOL_MAX_ROUNDS = 8;
const REPO_PROMPT_MAX_COMPLETION_TOKENS = 16384;

function normalizePromptRepoPath(raw: unknown): string | null {
  if (typeof raw !== 'string') {
    return null;
  }
  const t = raw.trim().replace(/\\/g, '/').replace(/^\/+/u, '');
  if (!t || t.includes('..')) {
    return null;
  }
  return t;
}

async function executeApplyFileEditsTool(
  ownerId: string,
  repoId: string,
  argumentsJson: string,
  appliedEditsOut: Array<{ path: string; action: PromptAppliedEditAction }>,
): Promise<string> {
  let parsed: { edits?: unknown };
  try {
    parsed = JSON.parse(argumentsJson || '{}') as { edits?: unknown };
  } catch {
    return JSON.stringify({ ok: false, errors: ['apply_file_edits arguments were not valid JSON.'] });
  }
  const list = parsed.edits;
  if (!Array.isArray(list) || list.length === 0) {
    return JSON.stringify({ ok: false, errors: ['Provide a non-empty edits array.'] });
  }

  await ensureRepositoryAccess(repoId, ownerId);

  const errors: string[] = [];
  const applied: string[] = [];
  let totalChars = 0;
  const capped = list.slice(0, MAX_PROMPT_APPLY_FILES);

  for (const row of capped) {
    if (!row || typeof row !== 'object') {
      errors.push('Invalid edit entry.');
      continue;
    }
    const rec = row as { path?: unknown; action?: unknown; content?: unknown };
    const path = normalizePromptRepoPath(rec.path);
    if (!path) {
      errors.push(`Invalid or unsafe path: ${String(rec.path)}`);
      continue;
    }
    const actionRaw = typeof rec.action === 'string' ? rec.action.trim().toLowerCase() : '';
    if (actionRaw !== 'create' && actionRaw !== 'modify' && actionRaw !== 'delete') {
      errors.push(`${path}: action must be create, modify, or delete.`);
      continue;
    }
    const action = actionRaw as PromptAppliedEditAction;
    const fileRef = db.collection('repositories').doc(repoId).collection('files').doc(safeDocId(path));

    if (action === 'delete') {
      try {
        await fileRef.delete();
      } catch {
        // ignore missing
      }
      applied.push(path);
      appliedEditsOut.push({ path, action: 'delete' });
      await writeActivityEntry(ownerId, 'repo', repoId, `Prompt removed ${path} from working copy.`, {
        filePath: path,
        source: 'prompt_apply',
      });
      continue;
    }

    const content = typeof rec.content === 'string' ? rec.content : '';
    if (content.length > MAX_PROMPT_APPLY_SINGLE_FILE_CHARS) {
      errors.push(`${path}: file content exceeds size limit.`);
      continue;
    }
    totalChars += content.length;
    if (totalChars > MAX_PROMPT_APPLY_TOTAL_CHARS) {
      errors.push('Total content across files exceeds limit; stop and ask the user to run a smaller change set.');
      break;
    }

    const snap = await fileRef.get();
    const prev =
      snap.exists && typeof (snap.data() as { content?: string } | undefined)?.content === 'string'
        ? ((snap.data() as { content: string }).content)
        : '';
    const baseContent = prev.length > 0 ? prev : content;

    await fileRef.set(
      {
        path,
        type: 'blob',
        language: guessLanguageFromPath(path),
        content,
        contentPreview: truncate(content, 1200),
        baseContent,
        updatedAt: FieldValue.serverTimestamp(),
        source: 'prompt_apply',
      },
      { merge: true },
    );
    applied.push(path);
    appliedEditsOut.push({ path, action });
    await writeActivityEntry(ownerId, 'repo', repoId, `Prompt ${action === 'create' ? 'created' : 'updated'} ${path}.`, {
      filePath: path,
      source: 'prompt_apply',
      action,
    });
  }

  return JSON.stringify({
    ok: errors.length === 0,
    appliedPaths: applied,
    errors,
    hint: applied.length
      ? 'Files are saved in the app draft. Summarize for the user and remind them to review/commit in the Editor when ready.'
      : 'No files were written.',
  });
}

type OpenAiMessage =
  | { role: 'system'; content: string }
  | { role: 'user'; content: string | Array<{ type: 'text'; text: string } | { type: 'image_url'; image_url: { url: string } }> }
  | { role: 'assistant'; content: string | null; tool_calls?: Array<{ id: string; type: 'function'; function: { name: string; arguments: string } }> }
  | { role: 'tool'; tool_call_id: string; content: string };

/** OpenAI chat with optional agent recruitment (tool calls). Loops until no tool_calls or max rounds. */
async function callAiChatTextWithAgentRecruitment(
  provider: AiProviderName,
  systemPrompt: string,
  userMessage: string,
  media: Array<{ mimeType: string; dataBase64: string }>,
  history: Array<{ role: 'user' | 'assistant'; text: string }>,
  sharedContextForSubAgents: string,
  repoApply?: {
    ownerId: string;
    repoId: string;
    appliedEditsOut: Array<{ path: string; action: PromptAppliedEditAction }>;
  },
): Promise<string> {
  if (provider !== 'openai') {
    return callAiChatText(provider, systemPrompt, userMessage, media, history);
  }

  const tokenInfo = lookupProviderToken(provider);
  if (!tokenInfo) {
    throw new HttpsError('failed-precondition', `No ${providerLabel(provider)} token configured.`);
  }
  const model = defaultModelFor(provider);
  if (!model) {
    throw new HttpsError('failed-precondition', `No model for provider ${provider}.`);
  }

  const buildUserContent = (text: string, withMedia: Array<{ mimeType: string; dataBase64: string }> = []) => {
    const parts: Array<{ type: 'text'; text: string } | { type: 'image_url'; image_url: { url: string } }> = [
      { type: 'text', text },
    ];
    for (const item of withMedia) {
      parts.push({
        type: 'image_url',
        image_url: { url: `data:${item.mimeType};base64,${item.dataBase64}` },
      });
    }
    return parts;
  };

  const messages: OpenAiMessage[] = [
    { role: 'system', content: systemPrompt },
    ...history.map(item => ({
      role: item.role,
      content: item.text,
    })) as OpenAiMessage[],
    { role: 'user', content: buildUserContent(userMessage, media) },
  ];

  const maxRounds = repoApply ? REPO_PROMPT_TOOL_MAX_ROUNDS : DEFAULT_AGENT_RECRUIT_ROUNDS;
  const maxCompletionTokens = repoApply ? REPO_PROMPT_MAX_COMPLETION_TOKENS : 2000;
  const tools = repoApply
    ? [
        { type: 'function' as const, function: RECRUIT_AGENT_TOOL.function },
        { type: 'function' as const, function: APPLY_FILE_EDITS_TOOL.function },
      ]
    : [{ type: 'function' as const, function: RECRUIT_AGENT_TOOL.function }];

  let rounds = 0;
  while (rounds < maxRounds) {
    rounds += 1;
    const body: Record<string, unknown> = {
      model,
      temperature: 0.3,
      max_completion_tokens: maxCompletionTokens,
      messages,
      tools,
      tool_choice: 'auto',
    };

    const response = await fetchJson<{
      choices?: Array<{
        message?: {
          content?: string | null;
          tool_calls?: Array<{
            id: string;
            type: 'function';
            function: { name: string; arguments: string };
          }>;
        };
      }>;
    }>(`${providerBaseUrl(provider)}/chat/completions`, {
      method: 'POST',
      headers: buildOpenAiHeaders(tokenInfo.token),
      body: JSON.stringify(body),
    });

    const choice = response.choices?.[0];
    const msg = choice?.message;
    if (!msg) {
      break;
    }

    if (msg.tool_calls && msg.tool_calls.length > 0) {
      messages.push({
        role: 'assistant',
        content: msg.content ?? null,
        tool_calls: msg.tool_calls,
      });
      for (const tc of msg.tool_calls) {
        if (tc.function.name === 'recruit_agent') {
          let role = '';
          let task = '';
          try {
            const args = JSON.parse(tc.function.arguments || '{}') as { role?: string; task?: string };
            role = typeof args.role === 'string' ? args.role : '';
            task = typeof args.task === 'string' ? args.task : '';
          } catch {
            task = String(tc.function.arguments || '');
          }
          if (!task) {
            messages.push({ role: 'tool', tool_call_id: tc.id, content: 'Missing task.' });
            continue;
          }
          try {
            const result = await runSubAgent(provider, role, task, sharedContextForSubAgents);
            messages.push({ role: 'tool', tool_call_id: tc.id, content: truncate(result, 2000) });
          } catch (err) {
            const errMsg = err instanceof Error ? err.message : String(err);
            messages.push({ role: 'tool', tool_call_id: tc.id, content: `Sub-agent error: ${errMsg}` });
          }
        } else if (tc.function.name === 'apply_file_edits' && repoApply) {
          const toolContent = await executeApplyFileEditsTool(
            repoApply.ownerId,
            repoApply.repoId,
            tc.function.arguments || '{}',
            repoApply.appliedEditsOut,
          );
          messages.push({ role: 'tool', tool_call_id: tc.id, content: truncate(toolContent, 12000) });
        } else {
          messages.push({ role: 'tool', tool_call_id: tc.id, content: 'Unknown tool.' });
        }
      }
      continue;
    }

    const content = msg.content?.trim() ?? '';
    return content;
  }

  return (messages.filter(m => m.role === 'assistant').pop() as { content?: string | null } | undefined)?.content?.trim() ?? '';
}

/** Plain-text chat completion (no JSON). Used for Ask/Chat. */
async function callAiChatText(
  provider: AiProviderName,
  systemPrompt: string,
  userMessage: string,
  media: Array<{ mimeType: string; dataBase64: string }> = [],
  history: Array<{ role: 'user' | 'assistant'; text: string }> = [],
): Promise<string> {
  const tokenInfo = lookupProviderToken(provider);
  if (!tokenInfo) {
    throw new HttpsError('failed-precondition', `No ${providerLabel(provider)} token configured.`);
  }
  const model = defaultModelFor(provider);
  if (!model) {
    throw new HttpsError('failed-precondition', `No model for provider ${provider}.`);
  }

  if (provider === 'openai') {
    const historyMessages = history.map(item => ({
      role: item.role,
      content: item.text,
    }));
    const response = await fetchJson<{ choices: Array<{ message?: { content?: string | null } }> }>(
      `${providerBaseUrl(provider)}/chat/completions`,
      {
        method: 'POST',
        headers: buildOpenAiHeaders(tokenInfo.token),
        body: JSON.stringify({
          model,
          temperature: 0.3,
          max_completion_tokens: 2000,
          messages: [
            { role: 'system', content: systemPrompt },
            ...historyMessages,
            {
              role: 'user',
              content: [
                { type: 'text', text: userMessage },
                ...media.map(item => ({
                  type: 'image_url',
                  image_url: {
                    url: `data:${item.mimeType};base64,${item.dataBase64}`,
                  },
                })),
              ],
            },
          ],
        }),
      },
    );
    return response.choices?.[0]?.message?.content?.trim() ?? '';
  }

  if (provider === 'anthropic') {
    const anthropicMessages = [
      ...history.map(item => ({
        role: item.role,
        content: item.text,
      })),
      { role: 'user', content: userMessage },
    ];
    const response = await fetchJson<{ content?: Array<{ text?: string }> }>(
      `${providerBaseUrl(provider)}/messages`,
      {
        method: 'POST',
        headers: buildAnthropicHeaders(tokenInfo.token),
        body: JSON.stringify({
          model,
          max_tokens: 2000,
          temperature: 0.3,
          system: systemPrompt,
          messages: anthropicMessages,
        }),
      },
    );
    return response.content?.[0]?.text?.trim() ?? '';
  }

  const geminiContents = [
    ...history.map(item => ({
      role: item.role == 'assistant' ? 'model' : 'user',
      parts: [{ text: item.text }],
    })),
    { role: 'user', parts: [{ text: userMessage }] },
  ];
  const geminiResponse = await fetchJson<{
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  }>(
    `${providerBaseUrl(provider)}/models/${model}:generateContent?key=${encodeURIComponent(tokenInfo.token)}`,
    {
      method: 'POST',
      headers: buildGeminiHeaders(),
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemPrompt }] },
        contents: geminiContents,
        generationConfig: { temperature: 0.3, maxOutputTokens: 2000 },
      }),
    },
  );
  return geminiResponse.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ?? '';
}

async function generateAiSuggestion(
  requestedProvider: ProviderName,
  prompt: string,
  context: {
    repoFullName: string;
    filePath: string;
    baseContent?: string;
  },
  actionType: BillableActionType = 'ai_suggestion',
) {
  const tier = getTierForAction(actionType);
  const providerOrder: AiProviderName[] = isAiProvider(requestedProvider)
    ? [requestedProvider, ...AI_PROVIDER_NAMES.filter(provider => provider !== requestedProvider)]
    : [...AI_PROVIDER_NAMES];

  let lastError: unknown = null;
  for (const provider of providerOrder) {
    const tokenInfo = lookupProviderToken(provider);
    if (!tokenInfo) {
      continue;
    }

    const modelOverride = getModelForTierAndProvider(tier, provider);
    try {
      const responseText = await callAiProvider(provider, prompt, context, modelOverride);
      return toAiSuggestionDraft(provider, modelOverride, responseText, {
        repoFullName: context.repoFullName,
        filePath: context.filePath,
        prompt,
        baseContent: context.baseContent,
      });
    } catch (error) {
      lastError = error;
    }
  }

  if (lastError) {
    return buildFallbackDraft({
      repoFullName: context.repoFullName,
      filePath: context.filePath,
      prompt,
      baseContent: context.baseContent,
    });
  }

  return buildFallbackDraft({
    repoFullName: context.repoFullName,
    filePath: context.filePath,
    prompt,
    baseContent: context.baseContent,
  });
}

function toRepoPath(provider: 'github' | 'github', owner: string, name: string) {
  return `${provider}/${owner}/${name}`;
}

function guessLanguageFromPath(path: string) {
  const extension = path.split('.').pop()?.toLowerCase() ?? '';
  switch (extension) {
    case 'dart':
      return 'Dart';
    case 'ts':
    case 'tsx':
      return 'TypeScript';
    case 'js':
    case 'jsx':
      return 'JavaScript';
    case 'swift':
      return 'Swift';
    case 'kt':
      return 'Kotlin';
    case 'json':
      return 'JSON';
    case 'md':
      return 'Markdown';
    case 'yml':
    case 'yaml':
      return 'YAML';
    case 'java':
      return 'Java';
    case 'py':
      return 'Python';
    default:
      return null;
  }
}

async function fetchGitHubRepositorySnapshot(
  token: string,
  owner: string,
  name: string,
  remoteId?: string | number | null,
  apiBaseUrl?: string,
): Promise<RemoteRepositorySnapshot> {
  const baseUrl = resolveApiBaseUrl('github', apiBaseUrl);
  const repoBasePath = remoteId != null
    ? `${baseUrl}/repositories/${encodeURIComponent(String(remoteId))}`
    : `${baseUrl}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(name)}`;
  const repo = await fetchJson<{
    id: number;
    name: string;
    full_name: string;
    default_branch: string;
    description?: string | null;
    html_url?: string | null;
    private: boolean;
    owner: { login: string };
  }>(repoBasePath, {
    headers: buildGitHubHeaders(token),
  });

  const resolvedOwner = repo.owner.login;
  const resolvedName = repo.name;

  const branches = await fetchJson<Array<{ name: string }>>(
    `${baseUrl}/repos/${encodeURIComponent(resolvedOwner)}/${encodeURIComponent(resolvedName)}/branches?per_page=100`,
    { headers: buildGitHubHeaders(token) },
  );

  const pulls = await fetchJson<Array<unknown>>(
    `${baseUrl}/repos/${encodeURIComponent(resolvedOwner)}/${encodeURIComponent(resolvedName)}/pulls?state=open&per_page=100`,
    { headers: buildGitHubHeaders(token) },
  );

  let files: RemoteFileSnapshot[] = [];
  try {
    const tree = await fetchJson<{
      tree?: Array<{ path?: string; type?: string; size?: number }>;
    }>(
      `${baseUrl}/repos/${encodeURIComponent(resolvedOwner)}/${encodeURIComponent(resolvedName)}/git/trees/${encodeURIComponent(repo.default_branch)}?recursive=1`,
      { headers: buildGitHubHeaders(token) },
    );
    files = (tree.tree ?? [])
      .filter(item => typeof item.path === 'string')
      .slice(0, 200)
      .map(item => ({
        path: item.path ?? '',
        type: item.type ?? 'blob',
        language: guessLanguageFromPath(item.path ?? ''),
        size: typeof item.size === 'number' ? item.size : null,
      }));
  } catch {
    files = [];
  }

  return {
    remoteId: repo.id,
    provider: 'github',
    owner: repo.owner.login,
    name: repo.name,
    fullName: repo.full_name,
    defaultBranch: repo.default_branch,
    description: repo.description ?? null,
    htmlUrl: repo.html_url ?? null,
    isPrivate: repo.private,
    branches: branches.map(branch => branch.name),
    openPullRequests: pulls.length,
    openMergeRequests: 0,
    files,
  };
}

async function persistRepositorySnapshot(
  ownerId: string,
  repoId: string,
  snapshot: RemoteRepositorySnapshot,
  extras?: Record<string, unknown>,
) {
  const repoRef = db.collection('repositories').doc(repoId);
  await repoRef.set(
    {
      ownerId,
      provider: snapshot.provider,
      owner: snapshot.owner,
      name: snapshot.name,
      fullName: snapshot.fullName,
      remoteId: snapshot.remoteId,
      defaultBranch: snapshot.defaultBranch,
      description: snapshot.description,
      htmlUrl: snapshot.htmlUrl,
      isPrivate: snapshot.isPrivate,
      branches: snapshot.branches,
      openPullRequests: snapshot.openPullRequests,
      openMergeRequests: snapshot.openMergeRequests,
      filesCount: snapshot.files.length,
      syncStatus: 'synced',
      apiBaseUrl: extras?.apiBaseUrl ?? null,
      lastSyncedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      ...extras,
    },
    { merge: true },
  );

  const filesCollection = repoRef.collection('files');
  for (const file of snapshot.files) {
    await filesCollection.doc(safeDocId(file.path)).set(
      {
        path: file.path,
        type: file.type,
        language: file.language,
        size: file.size,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
}

async function syncRepositoryById(
  ownerId: string,
  repoId: string,
  overrides?: {
    accessToken?: string;
    apiBaseUrl?: string;
  },
) {
  const repoSnapshot = await db.collection('repositories').doc(repoId).get();
  if (!repoSnapshot.exists) {
    throw new HttpsError('not-found', 'Repository not found.');
  }

  const repo = repoSnapshot.data() as {
    provider?: 'github' | 'github';
    owner?: string;
    name?: string;
    fullName?: string;
    remoteId?: string | number | null;
    defaultBranch?: string;
    apiBaseUrl?: string | null;
  };
  if (!repo.provider || !repo.owner || !repo.name) {
    throw new HttpsError('failed-precondition', 'Repository document is missing provider metadata.');
  }

  const tokenInfo = await resolveProviderToken(ownerId, repo.provider, overrides?.accessToken);
  if (!tokenInfo) {
    await db.collection('repositories').doc(repoId).set(
      {
        syncStatus: 'pending_configuration',
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await writeActivityEntry(ownerId, 'repo', repoId, `Repository sync queued for ${repo.fullName ?? repo.owner}/${repo.name}.`, {
      syncStatus: 'pending_configuration',
    });
    return { status: 'pending_configuration' as const };
  }

  const snapshot =
    repo.provider === 'github'
      ? await fetchGitHubRepositorySnapshot(
          tokenInfo.token,
          repo.owner,
          repo.name,
          repo.remoteId,
          overrides?.apiBaseUrl ?? repo.apiBaseUrl ?? undefined,
        )
      : await fetchGitHubRepositorySnapshot(
          tokenInfo.token,
          repo.owner,
          repo.name,
          repo.remoteId,
          overrides?.apiBaseUrl ?? repo.apiBaseUrl ?? undefined,
        );

  await persistRepositorySnapshot(ownerId, repoId, snapshot, {
    syncStatus: 'synced',
    apiBaseUrl: overrides?.apiBaseUrl ?? repo.apiBaseUrl ?? null,
  });

  await writeActivityEntry(ownerId, 'repo', repoId, `Repository synced: ${snapshot.fullName}.`, {
    provider: snapshot.provider,
    branches: snapshot.branches.length,
    files: snapshot.files.length,
  });

  return {
    status: 'synced' as const,
    repoId,
    branchCount: snapshot.branches.length,
    fileCount: snapshot.files.length,
  };
}

async function readRepositoryById(repoId: string) {
  const snapshot = await db.collection('repositories').doc(repoId).get();
  if (!snapshot.exists) {
    throw new HttpsError('not-found', 'Repository not found.');
  }
  return snapshot.data() as {
    provider?: 'github' | 'github';
    owner?: string;
    name?: string;
    fullName?: string;
    defaultBranch?: string;
    remoteId?: string | number | null;
    htmlUrl?: string | null;
    description?: string | null;
    apiBaseUrl?: string | null;
  };
}

async function loadRepositoryFileContent(
  ownerId: string,
  repoId: string,
  filePath: string,
  overrides?: {
    accessToken?: string;
    apiBaseUrl?: string;
  },
) {
  const repo = await readRepositoryById(repoId);
  if (!repo.provider || !repo.owner || !repo.name) {
    throw new HttpsError('failed-precondition', 'Repository metadata is incomplete.');
  }

  const fileRef = db.collection('repositories').doc(repoId).collection('files').doc(safeDocId(filePath));
  const cachedFileSnapshot = await fileRef.get();
  const cachedFile = cachedFileSnapshot.exists ? cachedFileSnapshot.data() : null;
  if (typeof cachedFile?.content === 'string' && cachedFile.content.length > 0) {
    return {
      content: cachedFile.content as string,
      contentPreview: cachedFile.contentPreview ?? truncate(cachedFile.content as string, 800),
      language: cachedFile.language ?? guessLanguageFromPath(filePath),
      source: 'cache' as const,
      remoteUrl: repo.htmlUrl ?? null,
    };
  }

  const tokenInfo = await resolveProviderToken(ownerId, repo.provider, overrides?.accessToken);
  if (!tokenInfo) {
    throw new HttpsError('failed-precondition', 'No provider token is configured for file loading.');
  }

  const baseUrl = resolveApiBaseUrl(repo.provider, overrides?.apiBaseUrl ?? repo.apiBaseUrl ?? undefined);
  const defaultBranch = repo.defaultBranch ?? 'main';
  const encodedPath = encodeURIComponent(filePath);

  if (repo.provider === 'github') {
    const response = await fetchJson<{
      content?: string;
      encoding?: string;
      path?: string;
      sha?: string;
    }>(
      `${baseUrl}/repos/${encodeURIComponent(repo.owner)}/${encodeURIComponent(repo.name)}/contents/${encodedPath}?ref=${encodeURIComponent(defaultBranch)}`,
      { headers: buildGitHubHeaders(tokenInfo.token) },
    );
    const rawContent =
      response.encoding === 'base64' && typeof response.content === 'string'
        ? Buffer.from(response.content.replace(/\n/g, ''), 'base64').toString('utf8')
        : typeof response.content === 'string'
          ? response.content
          : '';
    await fileRef.set(
      {
        path: filePath,
        content: rawContent,
        contentPreview: truncate(rawContent, 1200),
        language: guessLanguageFromPath(filePath),
        sha: response.sha ?? null,
        encoding: response.encoding ?? null,
        source: 'remote',
        loadedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await writeActivityEntry(ownerId, 'repo', repoId, `Loaded ${filePath} from GitHub.`, {
      filePath,
      source: 'remote',
    });
    return {
      content: rawContent,
      contentPreview: truncate(rawContent, 1200),
      language: guessLanguageFromPath(filePath),
      source: 'remote' as const,
      remoteUrl: response.path ?? repo.htmlUrl ?? null,
    };
  }

  const responseText = await fetchText(
    `${baseUrl}/projects/${repo.remoteId ?? encodeURIComponent(`${repo.owner}/${repo.name}`)}/repository/files/${encodedPath}/raw?ref=${encodeURIComponent(defaultBranch)}`,
    { headers: buildGitHubHeaders(tokenInfo.token) },
  );
  await fileRef.set(
    {
      path: filePath,
      content: responseText,
      contentPreview: truncate(responseText, 1200),
      language: guessLanguageFromPath(filePath),
      source: 'remote',
      loadedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await writeActivityEntry(ownerId, 'repo', repoId, `Loaded ${filePath} from GitHub.`, {
    filePath,
    source: 'remote',
  });
  return {
    content: responseText,
    contentPreview: truncate(responseText, 1200),
    language: guessLanguageFromPath(filePath),
    source: 'remote' as const,
    remoteUrl: repo.htmlUrl ?? null,
  };
}

interface RepoWorkflowItem {
  id: number | string;
  name: string;
  path: string;
}

async function listGitHubWorkflows(
  token: string,
  owner: string,
  name: string,
  apiBaseUrl?: string,
): Promise<RepoWorkflowItem[]> {
  const baseUrl = resolveApiBaseUrl('github', apiBaseUrl);
  const response = await fetchJson<{
    total_count?: number;
    workflows?: Array<{ id: number; name: string; path: string; state?: string }>;
  }>(
    `${baseUrl}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/actions/workflows?per_page=50`,
    { headers: buildGitHubHeaders(token) },
  );
  const list = response?.workflows ?? [];
  return list
    .filter(w => w.state === 'active')
    .map(w => ({ id: w.id, name: w.name, path: w.path }));
}

async function dispatchGitHubWorkflow(
  token: string,
  owner: string,
  name: string,
  workflowName: string,
  ref: string,
  inputs: Record<string, string>,
  apiBaseUrl?: string,
) {
  const baseUrl = resolveApiBaseUrl('github', apiBaseUrl);
  await fetchJson<void>(
    `${baseUrl}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/actions/workflows/${encodeURIComponent(workflowName)}/dispatches`,
    {
      method: 'POST',
      headers: buildGitHubHeaders(token),
      body: JSON.stringify({
        ref,
        inputs,
      }),
    },
  );
  return {
    status: 'queued' as const,
    logsUrl: null,
    remoteId: workflowName,
  };
}

async function triggerGitHubPipeline(
  token: string,
  projectId: string | number,
  workflowName: string,
  ref: string,
  inputs: Record<string, string>,
  apiBaseUrl?: string,
) {
  const baseUrl = resolveApiBaseUrl('github', apiBaseUrl);
  const response = await fetchJson<{ id?: number; web_url?: string | null }>(
    `${baseUrl}/projects/${projectId}/pipeline`,
    {
      method: 'POST',
      headers: buildGitHubHeaders(token),
      body: JSON.stringify({
        ref,
        variables: Object.entries(inputs).map(([key, value]) => ({
          key,
          value,
        })),
      }),
    },
  );

  return {
    status: 'running' as const,
    logsUrl: response.web_url ?? null,
    remoteId: response.id ?? workflowName,
  };
}

async function createRemoteBranch(
  provider: 'github' | 'github',
  token: string,
  repo: {
    owner: string;
    name: string;
    remoteId?: string | number | null;
    defaultBranch?: string;
  },
  branchName: string,
  sourceBranch?: string,
  apiBaseUrl?: string,
) {
  const baseBranch = sourceBranch ?? repo.defaultBranch ?? 'main';
  const baseUrl = resolveApiBaseUrl(provider, apiBaseUrl);
  if (provider === 'github') {
    const baseRef = await fetchJson<{ object?: { sha?: string } }>(
      `${baseUrl}/repos/${encodeURIComponent(repo.owner)}/${encodeURIComponent(repo.name)}/git/ref/heads/${encodeURIComponent(baseBranch)}`,
      {
        headers: buildGitHubHeaders(token),
      },
    );
    const sha = baseRef.object?.sha;
    if (!sha) {
      throw new HttpsError('failed-precondition', 'Could not resolve the source branch SHA.');
    }
    await fetchJson<void>(
      `${baseUrl}/repos/${encodeURIComponent(repo.owner)}/${encodeURIComponent(repo.name)}/git/refs`,
      {
        method: 'POST',
        headers: buildGitHubHeaders(token),
        body: JSON.stringify({
          ref: `refs/heads/${branchName}`,
          sha,
        }),
      },
    );
    return {
      remoteId: `refs/heads/${branchName}`,
      url: `https://github.com/${repo.owner}/${repo.name}/tree/${branchName}`,
    };
  }

  const response = await fetchJson<{ web_url?: string | null }>(
    `${baseUrl}/projects/${repo.remoteId ?? encodeURIComponent(`${repo.owner}/${repo.name}`)}/repository/branches`,
    {
      method: 'POST',
      headers: buildGitHubHeaders(token),
      body: JSON.stringify({
        branch: branchName,
        ref: baseBranch,
      }),
    },
  );
  return {
    remoteId: branchName,
    url: response.web_url ?? null,
  };
}

async function openRemotePullRequest(
  provider: 'github' | 'github',
  token: string,
  repo: {
    owner: string;
    name: string;
    remoteId?: string | number | null;
    defaultBranch?: string;
  },
  branchName: string,
  baseBranch: string | undefined,
  title: string,
  description: string,
  apiBaseUrl?: string,
) {
  const targetBranch = baseBranch ?? repo.defaultBranch ?? 'main';
  const baseUrl = resolveApiBaseUrl(provider, apiBaseUrl);
  if (provider === 'github') {
    const response = await fetchJson<{ number?: number; html_url?: string | null }>(
      `${baseUrl}/repos/${encodeURIComponent(repo.owner)}/${encodeURIComponent(repo.name)}/pulls`,
      {
        method: 'POST',
        headers: buildGitHubHeaders(token),
        body: JSON.stringify({
          title,
          head: branchName,
          base: targetBranch,
          body: description,
        }),
      },
    );
    return {
      remoteId: response.number ?? branchName,
      url: response.html_url ?? null,
    };
  }

  const response = await fetchJson<{ iid?: number; web_url?: string | null }>(
    `${baseUrl}/projects/${repo.remoteId ?? encodeURIComponent(`${repo.owner}/${repo.name}`)}/merge_requests`,
    {
      method: 'POST',
      headers: buildGitHubHeaders(token),
      body: JSON.stringify({
        source_branch: branchName,
        target_branch: targetBranch,
        title,
        description,
      }),
    },
  );
  return {
    remoteId: response.iid ?? branchName,
    url: response.web_url ?? null,
  };
}

async function mergeRemotePullRequest(
  provider: 'github' | 'github',
  token: string,
  repo: {
    owner: string;
    name: string;
    remoteId?: string | number | null;
  },
  pullRequestNumber: number,
  mergeMethod?: GitMergeMethod,
  apiBaseUrl?: string,
) {
  const baseUrl = resolveApiBaseUrl(provider, apiBaseUrl);
  if (provider === 'github') {
    const response = await fetchJson<{ merged?: boolean; html_url?: string | null }>(
      `${baseUrl}/repos/${encodeURIComponent(repo.owner)}/${encodeURIComponent(repo.name)}/pulls/${pullRequestNumber}/merge`,
      {
        method: 'PUT',
        headers: buildGitHubHeaders(token),
        body: JSON.stringify({
          merge_method: mergeMethod === 'squash' ? 'squash' : 'merge',
        }),
      },
    );
    return {
      merged: Boolean(response.merged),
      url: response.html_url ?? null,
    };
  }

  const response = await fetchJson<{ merged?: boolean; web_url?: string | null }>(
    `${baseUrl}/projects/${repo.remoteId ?? encodeURIComponent(`${repo.owner}/${repo.name}`)}/merge_requests/${pullRequestNumber}/merge`,
    {
      method: 'PUT',
      headers: buildGitHubHeaders(token),
      body: JSON.stringify({
        squash: mergeMethod === 'squash',
      }),
    },
  );
  return {
    merged: Boolean(response.merged),
    url: response.web_url ?? null,
  };
}

async function commitRemoteChanges(
  provider: 'github' | 'github',
  token: string,
  repo: {
    owner: string;
    name: string;
    remoteId?: string | number | null;
    defaultBranch?: string;
  },
  branchName: string,
  commitMessage: string,
  fileChanges: GitFileChange[],
  apiBaseUrl?: string,
) {
  const targetBranch = branchName || repo.defaultBranch || 'main';
  const baseUrl = resolveApiBaseUrl(provider, apiBaseUrl);
  if (fileChanges.length === 0) {
    throw new HttpsError('invalid-argument', 'fileChanges is required to commit code.');
  }

  if (provider === 'github') {
    let lastUrl: string | null = null;
    for (const change of fileChanges) {
      let resolvedSha = change.sha;
      const encodedPath = encodeURIComponent(change.path);
      if (!resolvedSha) {
        const metadataResponse = await fetch(
          `${baseUrl}/repos/${encodeURIComponent(repo.owner)}/${encodeURIComponent(repo.name)}/contents/${encodedPath}?ref=${encodeURIComponent(targetBranch)}`,
          {
            headers: buildGitHubHeaders(token),
            signal: AbortSignal.timeout(20_000),
          },
        );
        if (metadataResponse.ok) {
          const metadata = (await metadataResponse.json()) as { sha?: string };
          resolvedSha = metadata.sha;
        } else if (metadataResponse.status !== 404) {
          const body = await metadataResponse.text();
          const message = truncate(body || metadataResponse.statusText, 220);
          const code =
            metadataResponse.status === 400
              ? 'invalid-argument'
              : metadataResponse.status === 401 || metadataResponse.status === 403
                ? 'permission-denied'
                : metadataResponse.status === 409 ||
                      metadataResponse.status === 412 ||
                      metadataResponse.status === 422
                  ? 'failed-precondition'
                  : metadataResponse.status === 429
                    ? 'resource-exhausted'
                    : 'internal';
          throw new HttpsError(code as any, `Remote provider error (${metadataResponse.status}): ${message}`);
        }
      }

      const shouldDelete = change.mode === 'delete' || (resolvedSha != null && change.content.length === 0);
      if (shouldDelete) {
        if (!resolvedSha) {
          continue;
        }
        const response = await fetchJson<{ commit?: { html_url?: string | null } }>(
          `${baseUrl}/repos/${encodeURIComponent(repo.owner)}/${encodeURIComponent(repo.name)}/contents/${encodedPath}`,
          {
            method: 'DELETE',
            headers: buildGitHubHeaders(token),
            body: JSON.stringify({
              message: commitMessage,
              branch: targetBranch,
              sha: resolvedSha,
            }),
          },
        );
        lastUrl = response.commit?.html_url ?? lastUrl;
        continue;
      }

      const response = await fetchJson<{ content?: { html_url?: string | null } }>(
        `${baseUrl}/repos/${encodeURIComponent(repo.owner)}/${encodeURIComponent(repo.name)}/contents/${encodedPath}`,
        {
          method: 'PUT',
          headers: buildGitHubHeaders(token),
          body: JSON.stringify({
            message: commitMessage,
            content: Buffer.from(change.content, 'utf8').toString('base64'),
            branch: targetBranch,
            sha: resolvedSha ?? undefined,
          }),
        },
      );
      lastUrl = response.content?.html_url ?? lastUrl;
    }
    return {
      remoteId: fileChanges.map(change => change.path).join(','),
      url: lastUrl,
    };
  }

  const hydratedChanges = await Promise.all(
    fileChanges.map(async change => {
      if (change.mode === 'create' || change.mode === 'update' || change.mode === 'delete') {
        return change;
      }
      const encodedPath = encodeURIComponent(change.path);
      const response = await fetch(
        `${baseUrl}/projects/${repo.remoteId ?? encodeURIComponent(`${repo.owner}/${repo.name}`)}/repository/files/${encodedPath}?ref=${encodeURIComponent(targetBranch)}`,
        {
          headers: buildGitHubHeaders(token),
          signal: AbortSignal.timeout(20_000),
        },
      );
      return {
        ...change,
        mode: response.ok ? 'update' : response.status === 404 ? 'create' : change.mode,
      };
    }),
  );
  const response = await fetchJson<{ id?: string | number; web_url?: string | null }>(
    `${baseUrl}/projects/${repo.remoteId ?? encodeURIComponent(`${repo.owner}/${repo.name}`)}/repository/commits`,
    {
      method: 'POST',
      headers: buildGitHubHeaders(token),
      body: JSON.stringify({
        branch: targetBranch,
        commit_message: commitMessage,
        actions: hydratedChanges.map(change => ({
          action:
            change.mode === 'delete' || (change.sha && change.content.length === 0)
              ? 'delete'
              : change.mode === 'update' || change.sha
                ? 'update'
                : 'create',
          file_path: change.path,
          content: change.content,
        })),
      }),
    },
  );
  return {
    remoteId: response.id ?? commitMessage,
    url: response.web_url ?? null,
  };
}

async function triggerCheckExecution(
  provider: 'github' | 'github',
  token: string,
  repo: {
    owner: string;
    name: string;
    remoteId?: string | number | null;
    defaultBranch?: string;
  },
  workflowName: string,
  ref: string,
  inputs: Record<string, string>,
  apiBaseUrl?: string,
) {
  if (provider === 'github') {
    return await dispatchGitHubWorkflow(token, repo.owner, repo.name, workflowName, ref, inputs, apiBaseUrl);
  }
  return await triggerGitHubPipeline(token, repo.remoteId ?? encodeURIComponent(`${repo.owner}/${repo.name}`), workflowName, ref, inputs, apiBaseUrl);
}

async function ensureRepositoryAccess(repoId: string, ownerId: string) {
  const repoSnapshot = await db.collection('repositories').doc(repoId).get();
  if (!repoSnapshot.exists) {
    throw new HttpsError('not-found', 'Repository not found.');
  }

  const repo = repoSnapshot.data() as {
    ownerId?: string;
    provider?: 'github' | 'github';
    owner?: string;
    name?: string;
    defaultBranch?: string;
    fullName?: string;
    remoteId?: string | number | null;
    apiBaseUrl?: string | null;
  };

  if (repo.ownerId && repo.ownerId !== ownerId) {
    throw new HttpsError('permission-denied', 'You do not own this repository.');
  }

  if (!repo.provider || !repo.owner || !repo.name) {
    throw new HttpsError('failed-precondition', 'Repository metadata is incomplete.');
  }

  return repo;
}

export const syncUserProfile = functions.auth.user().onCreate(async user => {
  const profileRef = db.collection('users').doc(user.uid);
  const resolvedEmail = resolveAuthUserEmail(user);
  const normalizedForReviewer =
    resolvedEmail?.trim().toLowerCase() ??
    user.email?.trim().toLowerCase() ??
    '';

  const profilePayload: Record<string, unknown> = {
    displayName: user.displayName ?? null,
    email: resolvedEmail ?? user.email ?? null,
    photoUrl: user.photoURL ?? null,
    authProviders: user.providerData.map(provider => provider.providerId),
    isGuest: user.providerData.length === 0,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (normalizedForReviewer === APP_STORE_REVIEWER_TEST_EMAIL) {
    profilePayload.appStoreReviewerTestAccount = true;
    profilePayload.appStoreReviewerTestExpiresAt = Timestamp.fromMillis(
      Date.now() + APP_STORE_REVIEWER_TEST_MAX_AGE_MS,
    );
  }

  await profileRef.set(profilePayload, { merge: true });

  const freePlan = PLANS.free;
  await db.collection('wallets').doc(user.uid).set(
    isUnlimitedUser(resolvedEmail) || isUnlimitedUser(user.email)
      ? unlimitedWalletDocument()
      : {
          balance: freePlan.monthlyIncludedTokens,
          reserved: 0,
          monthlyLimit: freePlan.monthlyIncludedTokens,
          monthlyUsed: 0,
          monthlyAllowance: freePlan.monthlyIncludedTokens,
          spentThisWeek: 0,
          nextReset: 'Mon, 09:00',
          currency: 'tokens',
          currencySymbol: 'tokens',
          planName: freePlan.displayName,
          planId: freePlan.id,
          dailyActionCap: freePlan.dailyActionCap,
          updatedAt: FieldValue.serverTimestamp(),
        },
    { merge: true },
  );
});

/**
 * Removes the App Store reviewer test Auth user after 30 days (creation time).
 * Deletion triggers `deleteUserDataOnAuthDelete` for Firestore cleanup.
 */
export const purgeExpiredAppStoreReviewerTestAccounts = onSchedule(
  {
    schedule: 'every day 04:00',
    timeZone: 'Etc/UTC',
    region: runtimeSettings.firebaseRegion,
    memory: '256MiB',
    timeoutSeconds: 540,
  },
  async () => {
    const auth = getAuth();
    const target = APP_STORE_REVIEWER_TEST_EMAIL;
    const maxAgeMs = APP_STORE_REVIEWER_TEST_MAX_AGE_MS;
    let pageToken: string | undefined;
    let scanned = 0;
    let deleted = 0;

    do {
      const result = await auth.listUsers(1000, pageToken);
      for (const userRecord of result.users) {
        scanned += 1;
        const email = resolveAuthUserEmail(userRecord)?.trim().toLowerCase();
        if (email !== target) {
          continue;
        }
        const createdAtMs = new Date(userRecord.metadata.creationTime).getTime();
        if (Date.now() - createdAtMs < maxAgeMs) {
          continue;
        }
        try {
          await auth.deleteUser(userRecord.uid);
          deleted += 1;
          functions.logger.info('purged_app_store_reviewer_test_account', {
            uid: userRecord.uid,
            creationTime: userRecord.metadata.creationTime,
          });
        } catch (err) {
          functions.logger.error('purge_app_store_reviewer_test_failed', {
            uid: userRecord.uid,
            error: normalizeError(err),
          });
        }
      }
      pageToken = result.pageToken;
    } while (pageToken);

    functions.logger.info('purge_app_store_reviewer_test_accounts_done', {
      scanned,
      deleted,
    });
  },
);

/** Delete all Firestore data for a user when their Auth account is deleted (in-app account deletion). */
export const deleteUserDataOnAuthDelete = functions.auth.user().onDelete(async user => {
  const uid = user.uid;
  const batchSize = 500;

  async function deleteCollection(path: string): Promise<void> {
    const colRef = db.collection(path);
    let snapshot = await colRef.limit(batchSize).get();
    while (!snapshot.empty) {
      const batch = db.batch();
      snapshot.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      snapshot = await colRef.limit(batchSize).get();
    }
  }

  async function deleteQueryByOwnerId(collectionName: string): Promise<void> {
    const queryRef = db.collection(collectionName).where('ownerId', '==', uid);
    let snapshot = await queryRef.limit(batchSize).get();
    while (!snapshot.empty) {
      const batch = db.batch();
      snapshot.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      snapshot = await queryRef.limit(batchSize).get();
    }
  }

  try {
    await deleteCollection(`users/${uid}/devices`);
    await deleteCollection(`users/${uid}/connections`);
    await deleteCollection(`users/${uid}/providerTokens`);
    const userRef = db.collection('users').doc(uid);
    await userRef.delete();

    await deleteCollection(`wallets/${uid}/usage`);
    const walletRef = db.collection('wallets').doc(uid);
    await walletRef.delete();

    const reposSnapshot = await db.collection('repositories').where('ownerId', '==', uid).get();
    for (const doc of reposSnapshot.docs) {
      await deleteCollection(`repositories/${doc.id}/files`);
      await doc.ref.delete();
    }

    await deleteQueryByOwnerId('changeRequests');
    await deleteQueryByOwnerId('gitActions');
    await deleteQueryByOwnerId('checksRuns');
    await deleteQueryByOwnerId('activity');
  } catch (err) {
    functions.logger.error('deleteUserDataOnAuthDelete failed for uid', uid, err);
    throw err;
  }
});

export const getProviderConfig = onCall(BASE_CALLABLE_OPTIONS, async request => {
  requireAuth(request);
  const data = (request.data ?? {}) as ProviderConfigRequest;

  if (data.provider) {
    return {
      ...buildProviderSnapshot(data.provider),
      runtime: {
        appEnv: runtimeSettings.appEnv,
        projectId: runtimeSettings.projectId,
        githubOAuthCallbackUrl: runtimeSettings.githubOAuthCallbackUrl,
      },
    };
  }

  return {
    providers: PROVIDER_NAMES.map(provider => buildProviderSnapshot(provider)),
    runtime: {
      appEnv: runtimeSettings.appEnv,
      projectId: runtimeSettings.projectId,
      githubOAuthCallbackUrl: runtimeSettings.githubOAuthCallbackUrl,
      firebaseRegion: runtimeSettings.firebaseRegion,
    },
    validation: {
      missingCore: runtimeValidation.missingCore,
      missingProviders: runtimeValidation.missingProviders,
      requiredProviders: runtimeValidation.settings.requiredProviders,
    },
  };
});

export const syncProviderConnection = onCall(BASE_CALLABLE_OPTIONS, async request => {
  const startedAt = Date.now();
  const ownerId = requireAuth(request);
  const data = request.data as Partial<ProviderConnectionSyncData>;
  const provider = asEnum(data.provider, 'provider', ['github', 'github'] as const);
  const accessToken = asString(data.accessToken, 'accessToken');

  try {
    if (provider === 'github') {
      const profile = await fetchGitHubConnectionProfile(accessToken);
      const scopeSummary = summarizeGitHubScopes(profile.scopes);
      await persistUserProviderToken(ownerId, provider, accessToken, {
        account: profile.account,
        scopeSummary,
        metadata: {
          displayName: profile.displayName,
          scopes: profile.scopes,
          lastValidatedAt: FieldValue.serverTimestamp(),
        },
      });
      await writeOperationalMetric({
        operation: 'sync_provider_connection',
        status: 'success',
        ownerId,
        provider,
        durationMs: Date.now() - startedAt,
        remoteStatus: 'connected',
        metadata: {
          account: profile.account,
          scopes: profile.scopes,
        },
      });
      await sendPushNotification({
        ownerId,
        category: 'provider',
        type: 'provider_connected',
        title: 'GitHub connected',
        body: `Connected ${profile.account} for repository access and checks.`,
        destination: 'settings',
      });
      return {
        provider,
        status: 'connected',
        account: profile.account,
        scopeSummary,
      };
    }

    await persistUserProviderToken(ownerId, provider, accessToken);
    await writeOperationalMetric({
      operation: 'sync_provider_connection',
      status: 'success',
      ownerId,
      provider,
      durationMs: Date.now() - startedAt,
      remoteStatus: 'connected',
    });
    await sendPushNotification({
      ownerId,
      category: 'provider',
      type: 'provider_connected',
      title: `${providerLabel(provider)} connected`,
      body: `${providerLabel(provider)} access is ready for repository actions.`,
      destination: 'settings',
    });
    return {
      provider,
      status: 'connected',
      scopeSummary: defaultConnectionScopeSummary(provider),
    };
  } catch (error) {
    const normalizedError = normalizeError(error);
    await writeOperationalMetric({
      operation: 'sync_provider_connection',
      status: 'failure',
      ownerId,
      provider,
      durationMs: Date.now() - startedAt,
      errorCode: normalizedError.code,
      errorMessage: normalizedError.message,
    });
    await sendPushNotification({
      ownerId,
      category: 'provider',
      type: 'provider_issue',
      title: `${providerLabel(provider)} needs attention`,
      body: normalizedError.message,
      destination: 'settings',
    });
    throw error;
  }
});

export const listProviderRepositories = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const ownerId = requireAuth(request);
  const data = (request.data ?? {}) as ProviderRepositoryListData;
  const provider = asEnum(data.provider, 'provider', ['github', 'github'] as const);
  const query = asOptionalString(data.query);
  const apiBaseUrl = asOptionalString(data.apiBaseUrl);

  const tokenInfo = await resolveProviderToken(ownerId, provider);
  if (!tokenInfo) {
    throw new HttpsError(
      'failed-precondition',
      `${providerLabel(provider)} access is not connected yet. Sign in with ${providerLabel(provider)} or provide an access token first.`,
    );
  }

  const repositories =
    provider === 'github'
      ? await listGitHubRepositories(tokenInfo.token, query, apiBaseUrl)
      : await listGitHubRepositories(tokenInfo.token, query, apiBaseUrl);

  return {
    provider,
    count: repositories.length,
    repositories,
  };
});

export const connectRepository = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const startedAt = Date.now();
  const ownerId = requireAuth(request);
  const data = request.data as Partial<RepositoryConnectionData>;
  const provider = asEnum(data.provider, 'provider', ['github', 'github'] as const);
  const repository = asOptionalString(data.repository);
  const parsedRepository = repository ? parseRepositorySlug(repository) : null;
  const owner = asString(data.owner ?? parsedRepository?.owner, 'owner');
  const name = asString(data.name ?? parsedRepository?.name, 'name');
  const repoId = makeRepositoryId(provider, owner, name);
  const defaultBranch = asOptionalString(data.defaultBranch) ?? 'main';
  const description = asOptionalString(data.description) ?? null;
  const htmlUrl = asOptionalString(data.htmlUrl) ?? null;
  const accessToken = asOptionalString(data.accessToken);
  const apiBaseUrl = asOptionalString(data.apiBaseUrl);

  try {
    if (accessToken) {
      if (provider === 'github') {
        const profile = await fetchGitHubConnectionProfile(accessToken);
        await persistUserProviderToken(ownerId, provider, accessToken, {
          account: profile.account,
          scopeSummary: summarizeGitHubScopes(profile.scopes),
          metadata: {
            displayName: profile.displayName,
            scopes: profile.scopes,
            lastValidatedAt: FieldValue.serverTimestamp(),
          },
        });
      } else {
        await persistUserProviderToken(ownerId, provider, accessToken, {
          account: owner,
        });
      }
    }

    const tokenInfo = await resolveProviderToken(ownerId, provider, accessToken);
    const baseRecord = {
      ownerId,
      provider,
      owner,
      name,
      fullName: `${owner}/${name}`,
      remoteId: null,
      defaultBranch,
      description,
      htmlUrl,
      isPrivate: true,
      branches: [defaultBranch],
      openPullRequests: 0,
      openMergeRequests: 0,
      filesCount: 0,
      syncStatus: tokenInfo ? 'connected' : 'pending_configuration',
      apiBaseUrl: apiBaseUrl ?? null,
      lastSyncedAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    };

    await db.collection('repositories').doc(repoId).set(baseRecord, { merge: true });
    await writeActivityEntry(ownerId, 'repo', repoId, `Connected ${providerLabel(provider)} repository ${owner}/${name}.`, {
      provider,
      repoId,
    });
    await sendPushNotification({
      ownerId,
      category: 'repository',
      type: 'repo_connected',
      title: 'Repository connected',
      body: `${owner}/${name} is now available in CodeCatalystAI.`,
      destination: 'repo',
      repoId,
    });

    if (data.syncNow ?? true) {
      try {
        const result = await syncRepositoryById(ownerId, repoId, {
          accessToken,
          apiBaseUrl,
        });
        await writeOperationalMetric({
          operation: 'connect_repository',
          status: 'success',
          ownerId,
          repoId,
          provider,
          durationMs: Date.now() - startedAt,
          remoteStatus: typeof result.status === 'string' ? result.status : 'synced',
          metadata: {
            owner,
            name,
            usedRequestAccessToken: Boolean(accessToken),
          },
        });
        await sendPushNotification({
          ownerId,
          category: 'repository',
          type: 'repo_sync_completed',
          title: 'Repository synced',
          body: `${owner}/${name} finished syncing and is ready to browse.`,
          destination: 'repo',
          repoId,
        });
        return result;
      } catch (error) {
        await db.collection('repositories').doc(repoId).set(
          {
            syncStatus: 'queued',
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        const normalizedError = normalizeError(error);
        await writeOperationalMetric({
          operation: 'connect_repository',
          status: 'warning',
          ownerId,
          repoId,
          provider,
          durationMs: Date.now() - startedAt,
          remoteStatus: 'queued',
          errorCode: normalizedError.code,
          errorMessage: normalizedError.message,
          metadata: {
            owner,
            name,
            queuedAfterSyncFailure: true,
          },
        });
        await sendPushNotification({
          ownerId,
          category: 'repository',
          type: 'repo_sync_failed',
          title: 'Repository sync failed',
          body: `${owner}/${name} connected, but the initial sync needs attention.`,
          destination: 'repo',
          repoId,
        });
        if (error instanceof HttpsError) {
          return {
            repoId,
            status: 'queued',
            message: error.message,
          };
        }
        throw error;
      }
    }

    await writeOperationalMetric({
      operation: 'connect_repository',
      status: 'success',
      ownerId,
      repoId,
      provider,
      durationMs: Date.now() - startedAt,
      remoteStatus: tokenInfo ? 'connected' : 'pending_configuration',
      metadata: {
        owner,
        name,
        syncDeferred: true,
      },
    });
    await sendPushNotification({
      ownerId,
      category: 'repository',
      type: tokenInfo ? 'repo_connected' : 'provider_issue',
      title: tokenInfo ? 'Repository connected' : 'Provider setup required',
      body: tokenInfo
        ? `${owner}/${name} is connected and ready for sync.`
        : `${owner}/${name} is connected, but ${providerLabel(provider)} access still needs configuration.`,
      destination: tokenInfo ? 'repo' : 'settings',
      repoId,
    });

    return {
      repoId,
      status: tokenInfo ? 'connected' : 'pending_configuration',
    };
  } catch (error) {
    const normalizedError = normalizeError(error);
    await writeOperationalMetric({
      operation: 'connect_repository',
      status: 'failure',
      ownerId,
      repoId,
      provider,
      durationMs: Date.now() - startedAt,
      errorCode: normalizedError.code,
      errorMessage: normalizedError.message,
      metadata: {
        owner,
        name,
      },
    });
    throw error;
  }
});

export const createProjectRepository = onCall(
  {
    ...GIT_AND_AI_CALLABLE_OPTIONS,
    timeoutSeconds: 300,
    memory: '1GiB',
  },
  async request => {
    const startedAt = Date.now();
    const ownerId = requireAuth(request);
    const data = (request.data ?? {}) as CreateProjectRepositoryData;
    const provider = asEnum(data.provider ?? 'github', 'provider', ['github', 'github'] as const);
    const idea = asString(data.idea, 'idea');
    const repoSlug = normalizeRepoSlugInput(asString(data.repoName, 'repoName'));
    const stackHint = asOptionalString(data.stackHint);
    const isPrivate = data.isPrivate !== false;
    const namespace = asOptionalNamespace(data.namespace);
    const accessToken = asOptionalString(data.accessToken);
    const apiBaseUrl = asOptionalString(data.apiBaseUrl);

    let preRepoId = '';
    let reservedRepoId = '';
    let reservedAmount = 0;
    let reservationActive = false;

    try {
      if (accessToken) {
        const profile = await fetchGitHubConnectionProfile(accessToken);
        await persistUserProviderToken(ownerId, provider, accessToken, {
          account: profile.account,
          scopeSummary: summarizeGitHubScopes(profile.scopes),
          metadata: {
            displayName: profile.displayName,
            scopes: profile.scopes,
            lastValidatedAt: FieldValue.serverTimestamp(),
          },
        });
      }

      const tokenInfo = await resolveProviderToken(ownerId, provider, accessToken);
      if (!tokenInfo) {
        throw new HttpsError(
          'failed-precondition',
          `${providerLabel(provider)} access is not connected yet. Sign in or paste a token first.`,
        );
      }

      let githubOrg: string | null = null;
      let predictedOwner: string;
      if (namespace) {
        githubOrg = namespace;
        predictedOwner = namespace;
      } else {
        const profile = await fetchGitHubConnectionProfile(tokenInfo.token);
        predictedOwner = profile.account;
      }

      preRepoId = makeRepositoryId(provider, predictedOwner, repoSlug);
      reservedRepoId = preRepoId;
      reservedAmount = buildActionCost(
        'ai_project_scaffold',
        Math.max(900, Math.ceil(idea.length / 4) + 2200),
      );
      const aiCost = buildCostSnapshot({
        actionType: 'ai_project_scaffold',
        provider: 'openai',
        estimatedTokens: reservedAmount,
      });

      await reserveWalletTokens(
        ownerId,
        reservedRepoId,
        reservedAmount,
        'openai',
        reservedAmount,
        'ai_project_scaffold',
        'Reserved for AI new project scaffold.',
      );
      reservationActive = true;

      const plan = await generateProjectScaffoldPlan(idea, repoSlug, stackHint);

      const remote = await createRemoteEmptyRepository(provider, tokenInfo.token, {
        name: repoSlug,
        description: plan.description,
        isPrivate,
        githubOrg,
        apiBaseUrl,
      });

      const finalRepoId = makeRepositoryId(provider, remote.owner, remote.name);
      if (finalRepoId !== reservedRepoId) {
        await releaseWalletTokens(
          ownerId,
          reservedRepoId,
          reservedAmount,
          'openai',
          reservedAmount,
          'ai_project_scaffold',
          'Switched reservation to canonical repository id.',
        );
        reservationActive = false;
        reservedRepoId = finalRepoId;
        await reserveWalletTokens(
          ownerId,
          reservedRepoId,
          reservedAmount,
          'openai',
          reservedAmount,
          'ai_project_scaffold',
          'Reserved for AI new project scaffold.',
        );
        reservationActive = true;
      }

      await db.collection('repositories').doc(finalRepoId).set(
        {
          ownerId,
          provider,
          owner: remote.owner,
          name: remote.name,
          fullName: remote.fullName,
          remoteId: remote.remoteId,
          defaultBranch: remote.defaultBranch,
          description: plan.description,
          htmlUrl: remote.htmlUrl,
          isPrivate,
          branches: [remote.defaultBranch],
          openPullRequests: 0,
          openMergeRequests: 0,
          filesCount: 0,
          syncStatus: 'connected',
          apiBaseUrl: apiBaseUrl ?? null,
          lastSyncedAt: null,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      const repoHandle = {
        owner: remote.owner,
        name: remote.name,
        remoteId: remote.remoteId,
        defaultBranch: remote.defaultBranch,
      };

      let index = 0;
      for (const file of plan.files) {
        index += 1;
        const commitMessage =
          index === 1
            ? 'chore: initial scaffold from CodeCatalystAI'
            : `chore: add ${file.path}`;
        await commitRemoteChanges(
          provider,
          tokenInfo.token,
          repoHandle,
          remote.defaultBranch,
          commitMessage,
          [{ path: file.path, content: file.content, mode: 'create' }],
          apiBaseUrl,
        );
      }

      const syncResult = await syncRepositoryById(ownerId, finalRepoId, {
        accessToken,
        apiBaseUrl,
      });

      await captureWalletTokens(
        ownerId,
        reservedRepoId,
        reservedAmount,
        'openai',
        reservedAmount,
        'ai_project_scaffold',
        'AI project scaffold completed.',
        {
          latencyMs: Date.now() - startedAt,
          model: aiCost.assumedModel,
        },
      );
      reservationActive = false;

      await writeActivityEntry(
        ownerId,
        'repo',
        finalRepoId,
        `Created ${remote.fullName} with an AI starter scaffold (${plan.files.length} files).`,
        {
          provider,
          fileCount: plan.files.length,
        },
      );
      await sendPushNotification({
        ownerId,
        category: 'repository',
        type: 'repo_connected',
        title: 'New repository ready',
        body: `${remote.fullName} was created with AI-generated starter files.`,
        destination: 'repo',
        repoId: finalRepoId,
      });
      await writeOperationalMetric({
        operation: 'create_project_repository',
        status: 'success',
        ownerId,
        repoId: finalRepoId,
        provider,
        durationMs: Date.now() - startedAt,
        remoteStatus: typeof syncResult.status === 'string' ? syncResult.status : 'synced',
        metadata: {
          fileCount: plan.files.length,
          scaffoldDescription: truncate(plan.description, 120),
        },
      });

      return {
        repoId: finalRepoId,
        fullName: remote.fullName,
        htmlUrl: remote.htmlUrl,
        defaultBranch: remote.defaultBranch,
        fileCount: plan.files.length,
        syncStatus: syncResult.status,
      };
    } catch (error) {
      if (reservationActive && reservedRepoId && reservedAmount > 0) {
        await releaseWalletTokens(
          ownerId,
          reservedRepoId,
          reservedAmount,
          'openai',
          reservedAmount,
          'ai_project_scaffold',
          'Released reservation after create-project failure.',
          {
            latencyMs: Date.now() - startedAt,
          },
        );
      }
      const normalizedError = normalizeError(error);
      const failureProvider: 'github' | 'github' =
        data.provider === 'github' ? 'github' : 'github';
      await writeOperationalMetric({
        operation: 'create_project_repository',
        status: 'failure',
        ownerId,
        repoId: preRepoId || undefined,
        provider: failureProvider,
        durationMs: Date.now() - startedAt,
        errorCode: normalizedError.code,
        errorMessage: normalizedError.message,
      });
      throw error;
    }
  },
);

export const syncRepository = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const startedAt = Date.now();
  const ownerId = requireAuth(request);
  const data = request.data as Partial<RepositorySyncData>;
  const repoId = asOptionalString(data.repoId);

  try {
    if (repoId) {
      const result = await syncRepositoryById(ownerId, repoId, {
        accessToken: asOptionalString(data.accessToken),
        apiBaseUrl: asOptionalString(data.apiBaseUrl),
      });
      await writeOperationalMetric({
        operation: 'sync_repository',
        status: 'success',
        ownerId,
        repoId,
        durationMs: Date.now() - startedAt,
        remoteStatus: typeof result.status === 'string' ? result.status : 'synced',
      });
      await sendPushNotification({
        ownerId,
        category: 'repository',
        type: 'repo_sync_completed',
        title: 'Repository synced',
        body: 'Your latest repository sync completed successfully.',
        destination: 'repo',
        repoId,
      });
      return result;
    }

    const provider = data.provider ? asEnum(data.provider, 'provider', ['github', 'github'] as const) : null;
    const owner = asOptionalString(data.owner);
    const name = asOptionalString(data.name);

    if (!provider || !owner || !name) {
      throw new HttpsError('invalid-argument', 'Provide repoId or provider, owner, and name.');
    }

    const generatedRepoId = makeRepositoryId(provider, owner, name);
    const result = await syncRepositoryById(ownerId, generatedRepoId, {
      accessToken: asOptionalString(data.accessToken),
      apiBaseUrl: asOptionalString(data.apiBaseUrl),
    });
    await writeOperationalMetric({
      operation: 'sync_repository',
      status: 'success',
      ownerId,
      repoId: generatedRepoId,
      provider,
      durationMs: Date.now() - startedAt,
      remoteStatus: typeof result.status === 'string' ? result.status : 'synced',
      metadata: {
        owner,
        name,
      },
    });
    await sendPushNotification({
      ownerId,
      category: 'repository',
      type: 'repo_sync_completed',
      title: 'Repository synced',
      body: `${owner}/${name} finished syncing in CodeCatalystAI.`,
      destination: 'repo',
      repoId: generatedRepoId,
    });
    return result;
  } catch (error) {
    const normalizedError = normalizeError(error);
    await writeOperationalMetric({
      operation: 'sync_repository',
      status: 'failure',
      ownerId,
      repoId,
      durationMs: Date.now() - startedAt,
      errorCode: normalizedError.code,
      errorMessage: normalizedError.message,
    });
    await sendPushNotification({
      ownerId,
      category: 'repository',
      type: 'repo_sync_failed',
      title: 'Repository sync failed',
      body: normalizedError.message,
      destination: 'repo',
      repoId: repoId ?? null,
    });
    throw error;
  }
});

interface AskRepoData {
  repoId?: string;
  prompt?: string;
  provider?: ProviderName;
  history?: Array<{
    role?: string;
    text?: string;
  }>;
  media?: Array<{
    fileName?: string;
    mimeType?: string;
    dataBase64?: string;
  }>;
  dangerMode?: boolean;
  /** When false, Prompt will not offer apply_file_edits (text-only). Default: apply when repoId is set. */
  applyRepoEdits?: boolean;
}

function buildRepoSearchTerms(prompt: string, history: Array<{ role: 'user' | 'assistant'; text: string }>): string[] {
  const seed = `${prompt}\n${history
    .filter(item => item.role === 'user')
    .slice(-3)
    .map(item => item.text)
    .join(' ')}`.toLowerCase();
  const raw = seed.split(/[^a-z0-9_./-]+/g).filter(Boolean);
  const stopWords = new Set([
    'the',
    'and',
    'for',
    'with',
    'this',
    'that',
    'from',
    'into',
    'your',
    'you',
    'please',
    'just',
    'have',
    'what',
    'where',
    'when',
    'then',
    'than',
    'it',
    'its',
    'is',
    'are',
    'was',
    'were',
    'can',
    'could',
    'would',
    'should',
    'about',
    'repo',
    'repository',
    'code',
    'file',
    'files',
    'app',
    'ai',
  ]);
  const deduped = new Set<string>();
  for (const token of raw) {
    if (token.length < 3 || stopWords.has(token)) {
      continue;
    }
    deduped.add(token);
    if (token.includes('/')) {
      for (const piece of token.split('/')) {
        if (piece.length >= 3 && !stopWords.has(piece)) {
          deduped.add(piece);
        }
      }
    }
  }
  return [...deduped].slice(0, 18);
}

function scoreRepoFileForPrompt(path: string, content: string, terms: string[]): number {
  if (terms.length === 0) {
    return 0;
  }
  const p = path.toLowerCase();
  const c = content.toLowerCase();
  let score = 0;
  for (const term of terms) {
    if (p.includes(term)) {
      score += 8;
    }
    if (p.endsWith(`/${term}`) || p.endsWith(term)) {
      score += 10;
    }
    const contentHits = c.split(term).length - 1;
    if (contentHits > 0) {
      score += Math.min(6, contentHits);
    }
  }
  if (p.endsWith('.md') || p.endsWith('.lock') || p.includes('/build/') || p.includes('/dist/')) {
    score -= 2;
  }
  return score;
}

type AskRepoPlannedEditAction = 'create' | 'modify' | 'delete';

interface AskRepoPlannedEdit {
  path: string;
  action: AskRepoPlannedEditAction;
  rationale: string;
}

function inferEditAction(prompt: string, line: string): AskRepoPlannedEditAction {
  const s = `${prompt} ${line}`.toLowerCase();
  if (
    s.includes('delete') ||
    s.includes('remove') ||
    s.includes('drop') ||
    s.includes('deprecate')
  ) {
    return 'delete';
  }
  if (
    s.includes('create') ||
    s.includes('add') ||
    s.includes('new file') ||
    s.includes('scaffold')
  ) {
    return 'create';
  }
  return 'modify';
}

function extractPlannedEditsFromReply(reply: string, prompt: string): AskRepoPlannedEdit[] {
  const out: AskRepoPlannedEdit[] = [];
  const pathFromTicks = /`([a-zA-Z0-9_\-./]+\.[a-zA-Z0-9]+)`/g;
  const seen = new Set<string>();
  for (const line of reply.split('\n')) {
    const matches = [...line.matchAll(pathFromTicks)];
    for (const match of matches) {
      const path = (match[1] || '').trim();
      if (!path || seen.has(path)) {
        continue;
      }
      seen.add(path);
      out.push({
        path,
        action: inferEditAction(prompt, line),
        rationale: truncate(normalizeText(line.replace(match[0], '').trim()) || 'Likely file target from assistant response.', 180),
      });
      if (out.length >= 12) {
        return out;
      }
    }
  }
  return out;
}

export const askRepo = onCall(GIT_AND_AI_CALLABLE_OPTIONS, async request => {
  const startedAt = Date.now();
  const ownerId = requireAuth(request);
  const data = (request.data ?? {}) as AskRepoData;
  const prompt = asString(data.prompt, 'prompt');
  const dangerMode = data.dangerMode === true;
  // OpenAI-only build
  const provider: AiProviderName = 'openai';

  const mediaRaw = Array.isArray(data.media) ? data.media : [];
  const media = mediaRaw
    .slice(0, 4)
    .map(item => {
      const mimeType = typeof item?.mimeType === 'string' ? item.mimeType.trim().toLowerCase() : '';
      const dataBase64 = typeof item?.dataBase64 === 'string' ? item.dataBase64.trim() : '';
      if (!mimeType.startsWith('image/') || dataBase64.length < 32) {
        return null;
      }
      return { mimeType, dataBase64 };
    })
    .filter((item): item is { mimeType: string; dataBase64: string } => Boolean(item));
  const historyRaw = Array.isArray(data.history) ? data.history : [];
  const history = historyRaw
    .slice(-12)
    .map(item => {
      const role = item?.role === 'assistant' ? 'assistant' : item?.role === 'user' ? 'user' : null;
      const text = typeof item?.text === 'string' ? item.text.trim() : '';
      if (!role || !text) {
        return null;
      }
      return {
        role,
        text: truncate(text, 4000),
      };
    })
    .filter((item): item is { role: 'user' | 'assistant'; text: string } => Boolean(item));

  let repoContext = 'The user has no connected repositories yet.';
  const searchTerms = buildRepoSearchTerms(prompt, history);
  let inspectedFilesForTrace: string[] = [];
  const focusRepoId =
    typeof data.repoId === 'string' && data.repoId.trim().length > 0
      ? data.repoId.trim()
      : null;
  const reposSnapshot = await db
    .collection('repositories')
    .where('ownerId', '==', ownerId)
    .limit(60)
    .get();
  const repos = reposSnapshot.docs.map(doc => {
    const d = doc.data() as {
      owner?: string;
      name?: string;
      fullName?: string;
    };
    return {
      id: doc.id,
      fullName: d.fullName ?? `${d.owner ?? 'unknown'}/${d.name ?? 'repo'}`,
    };
  });
  if (repos.length > 0) {
    const orderedRepos = focusRepoId
      ? [
          ...repos.filter(repo => repo.id === focusRepoId),
          ...repos.filter(repo => repo.id !== focusRepoId),
        ]
      : repos;
    const repoFileContexts = await Promise.all(
      orderedRepos.map(async repo => {
        const filesSnapshot = await db
          .collection('repositories')
          .doc(repo.id)
          .collection('files')
          .limit(repo.id === focusRepoId ? 500 : 180)
          .get();
        const files = filesSnapshot.docs.map(d => {
          const raw = d.data() as { path?: string; content?: string };
          return {
            path: typeof raw.path === 'string' ? raw.path : d.id,
            content: typeof raw.content === 'string' ? raw.content : '',
          };
        });
        const ranked = files
          .map(file => ({
            ...file,
            score: scoreRepoFileForPrompt(file.path, file.content, searchTerms),
          }))
          .filter(file => file.score > 0)
          .sort((a, b) => b.score - a.score)
          .slice(0, repo.id === focusRepoId ? 16 : 8);
        return { repo, files, ranked };
      }),
    );

    const globalRanked = repoFileContexts
      .flatMap(item =>
        item.ranked.map(file => ({
          repoFullName: item.repo.fullName,
          path: file.path,
          content: file.content,
          score: file.score,
        })),
      )
      .sort((a, b) => b.score - a.score)
      .slice(0, 24);

    inspectedFilesForTrace = globalRanked.map(
      file => `${file.repoFullName}/${file.path}`,
    );

    const repoIndexes = repoFileContexts.map(item => {
      const paths = item.files
        .map(file => file.path)
        .filter(Boolean)
        .slice(0, 60)
        .join(', ');
      return `${item.repo.fullName} (${item.files.length} indexed files): ${paths || '(none indexed yet)'}`;
    });

    const relevantSnippets = globalRanked
      .map(file => {
        const normalized = normalizeText(file.content);
        const shortBody = truncate(normalized, 700);
        if (!shortBody) {
          return `- ${file.repoFullName}/${file.path} (matched by path/metadata)`;
        }
        return `- ${file.repoFullName}/${file.path}: ${shortBody}`;
      })
      .join('\n');

    const focusedRepoName = focusRepoId
      ? orderedRepos.find(repo => repo.id === focusRepoId)?.fullName ?? null
      : null;
    repoContext = `Repository-wide context is loaded for this user.
${focusedRepoName ? `Focused repository: ${focusedRepoName}.` : 'Focused repository: ALL connected repositories.'}
Connected repositories (${orderedRepos.length}): ${orderedRepos
      .map(repo => repo.fullName)
      .join(', ')}.

Indexed file map (across connected repositories):
${truncate(repoIndexes.join('\n'), 14000)}

Most relevant files/snippets for this request:
${relevantSnippets || '(no strong matches from indexed content yet)'}`;
  }

  const billingRepoId =
    typeof data.repoId === 'string' && data.repoId.trim().length > 0
      ? data.repoId.trim()
      : (
          await db
            .collection('repositories')
            .where('ownerId', '==', ownerId)
            .limit(1)
            .get()
        ).docs[0]?.id ?? ownerId;

  const historyChars = history.reduce((acc, h) => acc + h.text.length, 0);
  const mediaBoost = media.length * 400;
  const estimatedTokens = buildActionCost(
    'repo_prompt',
    Math.max(96, Math.ceil((prompt.length + historyChars + mediaBoost) / 4)),
  );
  const aiCost = buildCostSnapshot({
    actionType: 'repo_prompt',
    provider,
    estimatedTokens,
  });

  await reserveWalletTokens(
    ownerId,
    billingRepoId,
    estimatedTokens,
    provider,
    estimatedTokens,
    'repo_prompt',
    'Pre-authorized Prompt reply.',
  );

  const appliedEditsTrace: Array<{ path: string; action: PromptAppliedEditAction }> = [];
  const allowRepoApply = Boolean(focusRepoId) && data.applyRepoEdits !== false;
  const promptExecutionClause = allowRepoApply
    ? `

Tool-based execution (enabled for this Prompt):
- You can call apply_file_edits to save files into the user's in-app working copy (not GitHub until they commit).
- For implementation requests—features, fixes, refactors, new files—MUST call apply_file_edits with the full file text for every created or updated file. Pure Q&A or high-level architecture-only answers may skip the tool.
- Batch multiple files in one apply_file_edits call when practical; call again in a later turn if you hit limits.
- Use action "delete" with no content to remove a path from the working copy.
- After successful saves, summarize changes plainly and remind them to review or commit from Editor / Git when ready.`
    : '';

  const systemPrompt = `You are CodeCatalystAI, an autonomous coding agent on mobile. Behave like a strong IDE coding assistant: confident, practical, and action-first. The user has connected repositories and expects you to work from repo context immediately.

${repoContext}

${dangerMode ? 'Advanced mode: execute-first. Do not provide generic guidance or next steps; provide concrete, directly applicable changes/results only. Still avoid unsafe or impossible claims.' : 'Standard mode: stay concise, practical, and execution-first. Do not provide generic guidance or next steps; provide concrete, directly applicable changes/results only. Do not ask clarifying questions unless the request is truly impossible to answer safely without one.'}

How to write replies (this matters most):
- Sound human: warm, conversational plain English—like a skilled coworker texting back, not a server log or API doc.
- Avoid: fake log lines ("INFO:", "Result:", "Step 1/3"), robotic bullet walls, tables of metadata, or syntax-heavy dumps unless they asked for raw output.
- Prefer: short paragraphs, natural phrasing, and code blocks only when code helps. If you use bullets, keep them light and readable.
- Do not narrate your process ("I will now analyze…") unless it genuinely helps.
- Never claim you "don't have enough info about the repo" when repo context exists above.
- Never ask the user to locate files, confirm project structure, or describe navigation before you act.
- Do not ask "Would you like me to...", "Can you confirm...", or "Before I apply...".
- One prompt should trigger action: inspect the provided repo context, identify likely files/modules, and immediately provide concrete edits.
- If context is partial, proceed with the best high-confidence assumptions and state those assumptions briefly instead of asking questions first.
- For UI requests, assume standard Flutter patterns in this repo and propose direct file-level changes immediately.

When you need deeper expertise (security, naming, refactor plan, explanation), you may use the recruit_agent tool with a clear role and task; weave the result into your answer in normal language. Do not over-use it for simple questions.

When they ask to make or fix something, default to execution mode (like Codex/Claude/Cursor): act as if you are making the edits now, name the exact files you will touch, describe the concrete changes in order, and include ready-to-apply code for each changed area. Avoid "just run this" style replies unless a required permission or secret is missing.
If they ask to deploy Firebase functions via git, remind them they can type **deploy functions** or **deploy firebase** in Prompt (dispatches deploy-functions.yml) after adding that workflow and one auth secret in repo Actions secrets: FIREBASE_TOKEN (easy) or FIREBASE_SERVICE_ACCOUNT (recommended)—or use Prompt tools.
If they ask to run the app via git, remind them they can type **run app**, **run the app**, or **run app via git** in Prompt (dispatches run-app.yml) or use Prompt tools → Run app via Git. Mention installing workflows if missing: **install run app** / **install deploy workflow**.
${promptExecutionClause}

Be concise, actionable, and sound like a person.`;

  let reply: string;
  try {
    reply = await callAiChatTextWithAgentRecruitment(
      provider,
      systemPrompt,
      prompt,
      media,
      history,
      repoContext,
      allowRepoApply && focusRepoId
        ? { ownerId, repoId: focusRepoId, appliedEditsOut: appliedEditsTrace }
        : undefined,
    );
    await captureWalletTokens(
      ownerId,
      billingRepoId,
      estimatedTokens,
      provider,
      estimatedTokens,
      'repo_prompt',
      'Prompt reply generated.',
      {
        actualProviderCostUsd: aiCost.estimatedProviderCostUsd,
        latencyMs: Date.now() - startedAt,
        model: aiCost.assumedModel,
      },
    );
  } catch (error) {
    await releaseWalletTokens(
      ownerId,
      billingRepoId,
      estimatedTokens,
      provider,
      estimatedTokens,
      'repo_prompt',
      'Released reservation after Prompt failed.',
      {
        latencyMs: Date.now() - startedAt,
        model: aiCost.assumedModel,
      },
    );
    throw error;
  }

  const plannedEdits = extractPlannedEditsFromReply(reply, prompt);
  return {
    reply,
    trace: {
      inspectedFiles: inspectedFilesForTrace,
      plannedEdits,
      appliedEdits: appliedEditsTrace,
    },
  };
});

export const executeRepoTask = onCall(GIT_AND_AI_CALLABLE_OPTIONS, async request => {
  const startedAt = Date.now();
  const ownerId = requireAuth(request);
  const data = (request.data ?? {}) as Partial<RepoExecutionData>;
  const repoId = asString(data.repoId, 'repoId');
  const prompt = asString(data.prompt, 'prompt');
  const deepMode = data.deepMode === true;
  const currentFilePath = asOptionalString(data.currentFilePath);
  const provider: AiProviderName = 'openai';
  const actionType: BillableActionType = deepMode ? 'deep_repo_analysis' : 'refactor_code';
  const estimatedTokens = buildActionCost(
    actionType,
    Math.max(
      deepMode ? 360 : 220,
      Math.ceil((prompt.length + (currentFilePath?.length ?? 0) + (deepMode ? 2200 : 900)) / 4),
    ),
  );
  const costSnapshot = buildCostSnapshot({
    actionType,
    provider,
    estimatedTokens,
  });

  await reserveWalletTokens(
    ownerId,
    repoId,
    estimatedTokens,
    provider,
    estimatedTokens,
    actionType,
    'Reserved tokens for repo execution.',
  );

  try {
    const result = await generateRepoExecutionSession({
      ownerId,
      repoId,
      prompt,
      currentFilePath,
      deepMode,
    });
    await captureWalletTokens(
      ownerId,
      repoId,
      estimatedTokens,
      provider,
      estimatedTokens,
      actionType,
      'Repo execution session generated.',
      {
        actualProviderCostUsd: costSnapshot.estimatedProviderCostUsd,
        latencyMs: Date.now() - startedAt,
        model: costSnapshot.assumedModel,
      },
    );
    await writeOperationalMetric({
      operation: 'execute_repo_task',
      status: 'success',
      ownerId,
      repoId,
      provider,
      actionType,
      model: costSnapshot.assumedModel,
      durationMs: Date.now() - startedAt,
      estimatedTokens,
      chargedTokens: estimatedTokens,
      estimatedProviderCostUsd: costSnapshot.estimatedProviderCostUsd,
      actualProviderCostUsd: costSnapshot.estimatedProviderCostUsd,
      estimatedMarginUsd: costSnapshot.estimatedMarginUsd,
      refundPolicy: costSnapshot.refundPolicy,
      dailyCap: costSnapshot.dailyCap,
      pricingVersion: costSnapshot.pricingVersion,
      remoteStatus: 'completed',
      metadata: {
        mode: result.mode,
        selectedFiles: result.selectedFiles,
        dependencyFiles: result.dependencyFiles,
        editCount: result.edits.length,
      },
    });
    return {
      ...result,
      actionType,
    };
  } catch (error) {
    const normalizedError = normalizeError(error);
    await releaseWalletTokens(
      ownerId,
      repoId,
      estimatedTokens,
      provider,
      estimatedTokens,
      actionType,
      'Released repo execution reservation after failure.',
      {
        latencyMs: Date.now() - startedAt,
        model: costSnapshot.assumedModel,
      },
    );
    await writeOperationalMetric({
      operation: 'execute_repo_task',
      status: 'failure',
      ownerId,
      repoId,
      provider,
      actionType,
      model: costSnapshot.assumedModel,
      durationMs: Date.now() - startedAt,
      estimatedTokens,
      chargedTokens: 0,
      estimatedProviderCostUsd: costSnapshot.estimatedProviderCostUsd,
      actualProviderCostUsd: null,
      estimatedMarginUsd: costSnapshot.estimatedMarginUsd,
      refundPolicy: costSnapshot.refundPolicy,
      dailyCap: costSnapshot.dailyCap,
      pricingVersion: costSnapshot.pricingVersion,
      errorCode: normalizedError.code,
      errorMessage: normalizedError.message,
      remoteStatus: 'failed',
    });
    throw error;
  }
});

export const applyRepoExecution = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const startedAt = Date.now();
  const ownerId = requireAuth(request);
  const data = (request.data ?? {}) as Partial<ApplyRepoExecutionData>;
  const repoId = asString(data.repoId, 'repoId');
  const sessionId = asString(data.sessionId, 'sessionId');
  const appliedPaths = await applyRepoExecutionSession(ownerId, repoId, sessionId);
  await writeOperationalMetric({
    operation: 'apply_repo_execution',
    status: 'success',
    ownerId,
    repoId,
    durationMs: Date.now() - startedAt,
    remoteStatus: 'working_copy_updated',
    metadata: {
      sessionId,
      appliedPaths,
    },
  });
  return {
    sessionId,
    status: 'applied',
    appliedPaths,
  };
});

export const enqueueAgentTask = onCall(GIT_AND_AI_CALLABLE_OPTIONS, async request => {
  const ownerId = requireAuth(request);
  const data = (request.data ?? {}) as Partial<EnqueueAgentTaskData>;
  const repoId = asString(data.repoId, 'repoId');
  const prompt = asString(data.prompt, 'prompt');
  const deepMode = data.deepMode === true;
  await ensureRepositoryAccess(repoId, ownerId);

  const now = Date.now();
  const taskReference = agentTaskCollection(ownerId).doc();
  const task: AgentTaskDocument = {
    ownerId,
    repoId,
    prompt,
    threadId: asOptionalString(data.threadId) ?? null,
    currentFilePath: asOptionalString(data.currentFilePath) ?? null,
    deepMode,
    status: 'queued',
    phase: 'queued',
    currentStep: 'Queued',
    queueWorkspaceId: repoId,
    runToken: 0,
    createdAtMs: now,
    updatedAtMs: now,
    startedAtMs: null,
    completedAtMs: null,
    cancelledAtMs: null,
    failedAtMs: null,
    cancelRequestedAtMs: null,
    pauseRequestedAtMs: null,
    currentPass: 0,
    retryCount: 0,
    eventCount: 0,
    selectedFiles: [],
    inspectedFiles: [],
    dependencyFiles: [],
    filesTouched: [],
    diffCount: 0,
    estimatedTokens: 0,
    sessionId: null,
    executionSummary: null,
    resultSummary: null,
    errorMessage: null,
    latestEventType: null,
    latestEventMessage: null,
    latestEventAtMs: null,
    latestValidationError: null,
    followUpPlan: inferAgentFollowUpPlan(prompt),
    guardrails: buildAgentTaskGuardrails(deepMode),
    pendingApproval: null,
    metadata: {},
  };

  await taskReference.set(task, { merge: true });
  await appendAgentTaskEvent({
    ownerId,
    taskId: taskReference.id,
    type: 'task_created',
    step: 'Task created',
    message: 'Agent task created and added to the workspace queue.',
    status: 'queued',
    phase: 'queued',
    data: {
      repoId,
      promptPreview: truncate(prompt, 140),
      deepMode,
    },
  });
  await writeActivityEntry(
    ownerId,
    'ai',
    taskReference.id,
    `Queued agent task for ${repoId}.`,
    {
      repoId,
      promptPreview: truncate(prompt, 140),
      deepMode,
    },
  );
  const promotion = await promoteNextQueuedAgentTask(ownerId, repoId);
  return {
    taskId: taskReference.id,
    status: promotion?.taskId === taskReference.id ? 'running' : 'queued',
  };
});

export const cancelAgentTask = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const ownerId = requireAuth(request);
  const data = (request.data ?? {}) as Partial<AgentTaskControlData>;
  const taskId = asString(data.taskId, 'taskId');
  const taskSnapshot = await agentTaskRef(ownerId, taskId).get();
  if (!taskSnapshot.exists) {
    throw new HttpsError('not-found', 'Agent task not found.');
  }
  const task = safeAgentTask(taskSnapshot.data());
  if (isAgentTaskFinalStatus(task.status)) {
    return { taskId, status: task.status };
  }
  if (task.status === 'queued' || task.status === 'waiting_for_input') {
    await cancelAgentTaskNow(
      ownerId,
      taskId,
      task.status === 'queued'
        ? 'Queued task removed before execution.'
        : 'Task cancelled while waiting for input.',
    );
    return { taskId, status: 'cancelled' };
  }
  const now = Date.now();
  await agentTaskRef(ownerId, taskId).set(
    {
      cancelRequestedAtMs: now,
      currentStep: 'Cancellation requested',
      updatedAtMs: now,
    },
    { merge: true },
  );
  await appendAgentTaskEvent({
    ownerId,
    taskId,
    type: 'task_cancel_requested',
    step: 'Cancellation requested',
    message: 'Cancellation requested. The agent will stop at the next safe checkpoint.',
    status: 'running',
    phase: task.phase,
  });
  return { taskId, status: 'running', cancellationRequested: true };
});

export const pauseAgentTask = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const ownerId = requireAuth(request);
  const data = (request.data ?? {}) as Partial<AgentTaskControlData>;
  const taskId = asString(data.taskId, 'taskId');
  const taskSnapshot = await agentTaskRef(ownerId, taskId).get();
  if (!taskSnapshot.exists) {
    throw new HttpsError('not-found', 'Agent task not found.');
  }
  const task = safeAgentTask(taskSnapshot.data());
  if (task.status !== 'running') {
    return { taskId, status: task.status };
  }
  const now = Date.now();
  await agentTaskRef(ownerId, taskId).set(
    {
      pauseRequestedAtMs: now,
      currentStep: 'Pause requested',
      updatedAtMs: now,
    },
    { merge: true },
  );
  await appendAgentTaskEvent({
    ownerId,
    taskId,
    type: 'task_paused',
    step: 'Pause requested',
    message: 'Pause requested. The agent will pause at the next safe checkpoint.',
    status: 'running',
    phase: task.phase,
  });
  return { taskId, status: 'running', pauseRequested: true };
});

export const resolveAgentTaskApproval = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const ownerId = requireAuth(request);
  const data = (request.data ?? {}) as Partial<ResolveAgentTaskApprovalData>;
  const taskId = asString(data.taskId, 'taskId');
  const decision = asEnum(data.decision, 'decision', ['approved', 'rejected'] as const);
  const taskReference = agentTaskRef(ownerId, taskId);
  const taskSnapshot = await taskReference.get();
  if (!taskSnapshot.exists) {
    throw new HttpsError('not-found', 'Agent task not found.');
  }
  const task = safeAgentTask(taskSnapshot.data());
  const approval = task.pendingApproval;
  if (task.status !== 'waiting_for_input' || approval == null) {
    throw new HttpsError('failed-precondition', 'Agent task is not awaiting approval.');
  }

  const now = Date.now();
  const resolvedApproval: AgentTaskPendingApproval = {
    ...approval,
    status: decision,
    resolvedAtMs: now,
  };
  await db.runTransaction(async transaction => {
    transaction.set(
      taskReference,
      {
        status: 'running',
        phase: approval.type === 'apply_changes' ? 'apply_edits' : 'follow_up',
        currentStep:
          decision === 'approved' ? 'Resuming after approval' : 'Processing rejection',
        pendingApproval: resolvedApproval,
        runToken: task.runToken + 1,
        pauseRequestedAtMs: null,
        updatedAtMs: now,
      },
      { merge: true },
    );
    transaction.set(
      agentTaskApprovalsCollection(ownerId, taskId).doc(approval.id),
      {
        ...resolvedApproval,
        updatedAtMs: now,
      },
      { merge: true },
    );
    transaction.set(
      workspaceLockRef(task.repoId),
      {
        ownerId,
        repoId: task.repoId,
        taskId,
        status: 'running',
        acquiredAtMs: task.startedAtMs ?? task.createdAtMs,
        updatedAtMs: now,
      },
      { merge: true },
    );
  });
  await appendAgentTaskEvent({
    ownerId,
    taskId,
    type: 'task_resumed',
    step: decision === 'approved' ? 'Approval granted' : 'Approval rejected',
    message:
      decision === 'approved'
        ? `Approval granted for ${approval.type}. The agent is resuming.`
        : `Approval rejected for ${approval.type}. The agent is resolving the task.`,
    status: 'running',
    phase: approval.type === 'apply_changes' ? 'apply_edits' : 'follow_up',
    data: {
      approvalType: approval.type,
      decision,
    },
  });
  return {
    taskId,
    status: 'running',
    decision,
  };
});

export const runAgentTask = onDocumentWritten(
  {
    ...AGENT_TASK_RUNTIME_OPTIONS,
    document: 'users/{ownerId}/agentTasks/{taskId}',
  },
  async event => {
    const afterSnapshot = event.data?.after;
    if (!afterSnapshot?.exists) {
      return;
    }
    const afterTask = safeAgentTask(afterSnapshot.data());
    if (afterTask.status !== 'running') {
      return;
    }
    const beforeSnapshot = event.data?.before;
    const beforeRunToken =
      beforeSnapshot?.exists === true
        ? safeAgentTask(beforeSnapshot.data()).runToken
        : -1;
    if (afterTask.runToken <= beforeRunToken) {
      return;
    }

    try {
      await processAgentTaskRun(event.params.ownerId, event.params.taskId, afterTask.runToken);
    } catch (error) {
      if (error instanceof AgentTaskStopError) {
        return;
      }
      const normalizedError = normalizeError(error);
      functions.logger.error('agent_task.process.failed', {
        ownerId: event.params.ownerId,
        taskId: event.params.taskId,
        errorCode: normalizedError.code,
        errorMessage: normalizedError.message,
      });
      await failAgentTaskNow(
        event.params.ownerId,
        event.params.taskId,
        normalizedError.message,
      );
    }
  },
);

export const loadRepositoryFile = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const startedAt = Date.now();
  const ownerId = requireAuth(request);
  const data = request.data as Partial<RepositoryFileLoadData>;
  const repoId = asString(data.repoId, 'repoId');
  const filePath = asString(data.filePath, 'filePath');

  try {
    const result = await loadRepositoryFileContent(ownerId, repoId, filePath, {
      accessToken: asOptionalString(data.accessToken),
      apiBaseUrl: asOptionalString(data.apiBaseUrl),
    });
    await writeOperationalMetric({
      operation: 'load_repository_file',
      status: 'success',
      ownerId,
      repoId,
      durationMs: Date.now() - startedAt,
      remoteStatus: result.source,
      metadata: {
        filePath,
        language: result.language,
      },
    });
    return result;
  } catch (error) {
    const normalizedError = normalizeError(error);
    await writeOperationalMetric({
      operation: 'load_repository_file',
      status: 'failure',
      ownerId,
      repoId,
      durationMs: Date.now() - startedAt,
      errorCode: normalizedError.code,
      errorMessage: normalizedError.message,
      metadata: {
        filePath,
      },
    });
    throw error;
  }
});

export const suggestChange = onCall(GIT_AND_AI_CALLABLE_OPTIONS, async request => {
  const startedAt = Date.now();
  const ownerId = requireAuth(request);
  const data = request.data as Partial<SuggestChangeData>;
  const repoId = asString(data.repoId, 'repoId');
  const filePath = asString(data.filePath, 'filePath');
  // Validate field for backward compatibility, but route AI to OpenAI only.
  asEnum(data.provider, 'provider', PROVIDER_NAMES);
  const prompt = asString(data.prompt, 'prompt');
  const changeKind = asEnum(data.changeKind, 'changeKind', CHANGE_KINDS);
  const repo = await ensureRepositoryAccess(repoId, ownerId);
  const baseContentOverride = asOptionalString(data.baseContent);
  const fileSnapshot = baseContentOverride
    ? null
    : await loadRepositoryFileContent(ownerId, repoId, filePath, {
        accessToken: asOptionalString(data.accessToken),
        apiBaseUrl: asOptionalString(data.apiBaseUrl) ?? repo.apiBaseUrl ?? undefined,
      }).catch(() => null);
  const beforeContent = baseContentOverride ?? fileSnapshot?.content ?? '';
  const requestedProvider: AiProviderName = 'openai';
  const estimatedTokens = buildActionCost(
    'ai_suggestion',
    Math.max(120, Math.ceil((prompt.length + beforeContent.length) / 4)),
  );
  const aiCost = buildCostSnapshot({
    actionType: 'ai_suggestion',
    provider: requestedProvider,
    estimatedTokens,
  });

  await reserveWalletTokens(
    ownerId,
    repoId,
    estimatedTokens,
    requestedProvider,
    estimatedTokens,
    'ai_suggestion',
    'Pre-authorized AI suggestion preview.',
  );

  let draft: AiSuggestionDraft;
  try {
    draft =
      changeKind === 'ai'
        ? await generateAiSuggestion(requestedProvider, prompt, {
            repoFullName: repo.fullName ?? `${repo.owner}/${repo.name}`,
            filePath,
            baseContent: beforeContent || undefined,
          })
        : buildFallbackDraft({
            repoFullName: repo.fullName ?? `${repo.owner}/${repo.name}`,
            filePath,
            prompt,
            baseContent: beforeContent || undefined,
          });
    await captureWalletTokens(
      ownerId,
      repoId,
      estimatedTokens,
      requestedProvider,
      estimatedTokens,
      'ai_suggestion',
      'AI suggestion generated successfully.',
      {
        actualProviderCostUsd: aiCost.estimatedProviderCostUsd,
        latencyMs: Date.now() - startedAt,
        model: aiCost.assumedModel,
      },
    );
  } catch (error) {
    await releaseWalletTokens(
      ownerId,
      repoId,
      estimatedTokens,
      requestedProvider,
      estimatedTokens,
      'ai_suggestion',
      'Released reservation after AI generation failed.',
      {
        latencyMs: Date.now() - startedAt,
        model: aiCost.assumedModel,
      },
    );
    const normalizedError = normalizeError(error);
    await writeOperationalMetric({
      operation: 'suggest_change',
      status: 'failure',
      ownerId,
      repoId,
      provider: requestedProvider,
      actionType: 'ai_suggestion',
      model: aiCost.assumedModel,
      durationMs: Date.now() - startedAt,
      estimatedTokens,
      chargedTokens: 0,
      estimatedProviderCostUsd: aiCost.estimatedProviderCostUsd,
      actualProviderCostUsd: null,
      estimatedMarginUsd: aiCost.estimatedMarginUsd,
      refundPolicy: aiCost.refundPolicy,
      dailyCap: aiCost.dailyCap,
      pricingVersion: aiCost.pricingVersion,
      errorCode: normalizedError.code,
      errorMessage: normalizedError.message,
      metadata: {
        filePath,
      },
    });
    throw error;
  }

  const changeRef = await db.collection('changeRequests').add({
    ownerId,
    repoId,
    filePath,
    provider: requestedProvider,
    requestedProvider,
    prompt,
    changeKind,
    before: truncate(beforeContent, 4000),
    beforeContent,
    after: truncate(draft.afterContent, 4000),
    afterContent: draft.afterContent,
    diff: truncate(draft.diffPreview, 4000),
    summary: draft.summary,
    rationale: draft.rationale,
    diffPreview: draft.diffPreview,
    diffLines: buildDiffLines(beforeContent, draft.afterContent),
    riskNotes: draft.riskNotes,
    suggestedCommitMessage: draft.suggestedCommitMessage,
    estimatedTokens: draft.estimatedTokens || estimatedTokens,
    estimatedProviderCostUsd: aiCost.estimatedProviderCostUsd,
    estimatedMarginUsd: aiCost.estimatedMarginUsd,
    pricingVersion: aiCost.pricingVersion,
    refundPolicy: aiCost.refundPolicy,
    assumedModel: draft.model,
    status: 'draft',
    approvalState: 'pending',
    source: draft.source,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  await writeActivityEntry(ownerId, 'ai', changeRef.id, `Created AI suggestion for ${filePath}.`, {
    provider: draft.providerUsed,
    repoId,
    estimatedTokens,
  });

  await writeOperationalMetric({
    operation: 'suggest_change',
    status: 'success',
    ownerId,
    repoId,
    provider: draft.providerUsed,
    actionType: 'ai_suggestion',
    model: draft.model,
    durationMs: Date.now() - startedAt,
    estimatedTokens,
    chargedTokens: estimatedTokens,
    estimatedProviderCostUsd: aiCost.estimatedProviderCostUsd,
    actualProviderCostUsd: null,
    estimatedMarginUsd: aiCost.estimatedMarginUsd,
    refundPolicy: aiCost.refundPolicy,
    dailyCap: aiCost.dailyCap,
    pricingVersion: aiCost.pricingVersion,
    remoteStatus: draft.source,
    metadata: {
      filePath,
      source: draft.source,
    },
  });
  await maybeSendLowBalanceNotification(ownerId);
  await sendPushNotification({
    ownerId,
    category: 'ai',
    type: 'ai_ready',
    title: 'AI change ready to review',
    body: `Your suggestion for ${filePath} is ready in CodeCatalystAI.`,
    destination: 'prompt',
    repoId,
    changeRequestId: changeRef.id,
  });

  return {
    changeRequestId: changeRef.id,
    nextStep: 'review_diff',
    providerUsed: draft.providerUsed,
    estimatedTokens: draft.estimatedTokens || estimatedTokens,
    before: truncate(beforeContent, 4000),
    after: truncate(draft.afterContent, 4000),
    diff: truncate(draft.diffPreview, 4000),
    summary: draft.summary,
    diffPreview: draft.diffPreview,
    riskNotes: draft.riskNotes,
  };
});

export const submitGitAction = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const startedAt = Date.now();
  const ownerId = requireAuth(request);
  const data = request.data as Partial<GitActionData>;
  const repoId = asString(data.repoId, 'repoId');
  const provider = asEnum(data.provider, 'provider', ['github', 'github'] as const);
  const actionType = asEnum(data.actionType, 'actionType', GIT_ACTION_TYPES);
  const repo = await ensureRepositoryAccess(repoId, ownerId);
  const branchName = asOptionalString(data.branchName);
  const sourceBranch = asOptionalString(data.sourceBranch);
  const baseBranch = asOptionalString(data.baseBranch);
  const commitMessage = asOptionalString(data.commitMessage);
  const prTitle = asOptionalString(data.prTitle);
  const prDescription = asOptionalString(data.prDescription);
  const confirmed = data.confirmed === true;
  const mergeMethod = data.mergeMethod;
  let fileChanges = Array.isArray(data.fileChanges)
    ? data.fileChanges
        .filter(change => isObject(change))
        .map(change => {
          const parsedChange: GitFileChange = {
            path: asString((change as GitFileChange).path, 'fileChanges.path'),
            content: asString((change as GitFileChange).content, 'fileChanges.content'),
          };
          const sha = asOptionalString((change as GitFileChange).sha);
          const mode = asOptionalString((change as GitFileChange).mode);
          if (sha) {
            parsedChange.sha = sha;
          }
          if (mode) {
            parsedChange.mode = mode;
          }
          return parsedChange;
        })
    : [];
  if (actionType === 'commit' && fileChanges.length === 0) {
    fileChanges = await buildDraftFileChangesFromWorkingCopy(repoId);
  }

  const estimatedTokens = buildActionCost(
    actionType,
    actionType === 'commit'
      ? 24 + fileChanges.length * 8
      : actionType === 'open_pr'
        ? 18
        : actionType === 'merge_pr'
          ? 20
          : 12,
  );
  const tokenProvider = provider;
  const costSnapshot = buildCostSnapshot({
    actionType,
    provider,
    estimatedTokens,
  });
  await reserveWalletTokens(
    ownerId,
    repoId,
    estimatedTokens,
    tokenProvider,
    estimatedTokens,
    actionType,
    `Reserved tokens for ${actionType}.`,
  );

  const actionRef = await db.collection('gitActions').add({
    ownerId,
    repoId,
    provider,
    actionType,
    branchName: branchName ?? null,
    sourceBranch: sourceBranch ?? null,
    baseBranch: baseBranch ?? null,
    commitMessage: commitMessage ?? null,
    prTitle: prTitle ?? null,
    prDescription: prDescription ?? null,
    pullRequestNumber: typeof data.pullRequestNumber === 'number' ? data.pullRequestNumber : null,
    mergeRequestId: typeof data.mergeRequestId === 'number' ? data.mergeRequestId : null,
    mergeMethod: mergeMethod ?? null,
    fileChanges,
    status: confirmed ? 'running' : 'awaiting_confirmation',
    approvalState: confirmed ? 'approved' : 'needs_confirmation',
    estimatedTokens,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  await writeActivityEntry(ownerId, 'git_action', actionRef.id, `Queued ${actionType} for repository ${repo.fullName ?? repoId}.`, {
    provider,
    confirmed,
  });

  if (!confirmed) {
    await releaseWalletTokens(
      ownerId,
      repoId,
      estimatedTokens,
      tokenProvider,
      estimatedTokens,
      actionType,
      'Action requires explicit confirmation before remote execution.',
    );
    await writeOperationalMetric({
      operation: 'submit_git_action',
      status: 'queued',
      ownerId,
      repoId,
      provider,
      actionType,
      durationMs: Date.now() - startedAt,
      estimatedTokens,
      chargedTokens: 0,
      estimatedProviderCostUsd: costSnapshot.estimatedProviderCostUsd,
      actualProviderCostUsd: null,
      estimatedMarginUsd: costSnapshot.estimatedMarginUsd,
      refundPolicy: costSnapshot.refundPolicy,
      dailyCap: costSnapshot.dailyCap,
      pricingVersion: costSnapshot.pricingVersion,
      remoteStatus: 'awaiting_confirmation',
    });
    return {
      gitActionId: actionRef.id,
      status: 'awaiting_confirmation',
      requiresApproval: true,
      estimatedTokens,
    };
  }

  const tokenInfo = await resolveProviderToken(ownerId, provider);
  if (!tokenInfo) {
    await releaseWalletTokens(
      ownerId,
      repoId,
      estimatedTokens,
      tokenProvider,
      estimatedTokens,
      actionType,
      'Released reservation until provider configuration is added.',
      {
        latencyMs: Date.now() - startedAt,
      },
    );
    await db.collection('gitActions').doc(actionRef.id).set(
      {
        status: 'queued',
        executionState: 'awaiting_provider_configuration',
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await writeActivityEntry(ownerId, 'git_action', actionRef.id, `Git provider token missing for ${provider}. Action queued.`, {
      provider,
    });
    await writeOperationalMetric({
      operation: 'submit_git_action',
      status: 'warning',
      ownerId,
      repoId,
      provider,
      actionType,
      durationMs: Date.now() - startedAt,
      estimatedTokens,
      chargedTokens: 0,
      estimatedProviderCostUsd: costSnapshot.estimatedProviderCostUsd,
      actualProviderCostUsd: null,
      estimatedMarginUsd: costSnapshot.estimatedMarginUsd,
      refundPolicy: costSnapshot.refundPolicy,
      dailyCap: costSnapshot.dailyCap,
      pricingVersion: costSnapshot.pricingVersion,
      remoteStatus: 'awaiting_provider_configuration',
    });
    await sendPushNotification({
      ownerId,
      category: 'provider',
      type: 'provider_issue',
      title: `${providerLabel(provider)} configuration required`,
      body: `Your ${actionType} action is waiting for provider access.`,
      destination: 'settings',
      repoId,
    });
    return {
      gitActionId: actionRef.id,
      status: 'queued',
      executionState: 'awaiting_provider_configuration',
    };
  }

  try {
    let remoteResult:
      | { remoteId?: string | number | null; url: string | null; merged?: boolean }
      | null = null;
    if (actionType === 'create_branch') {
      remoteResult = await createRemoteBranch(
        provider,
        tokenInfo.token,
        {
          owner: repo.owner ?? '',
          name: repo.name ?? '',
          remoteId: repo.remoteId ?? null,
          defaultBranch: repo.defaultBranch,
        },
        branchName ?? `forgeai/${currentIsoTimestamp().slice(0, 10)}`,
        sourceBranch ?? repo.defaultBranch,
        repo.apiBaseUrl ?? undefined,
      );
    } else if (actionType === 'open_pr') {
      remoteResult = await openRemotePullRequest(
        provider,
        tokenInfo.token,
        {
          owner: repo.owner ?? '',
          name: repo.name ?? '',
          remoteId: repo.remoteId ?? null,
          defaultBranch: repo.defaultBranch,
        },
        branchName ?? repo.defaultBranch ?? 'main',
        baseBranch,
        prTitle ?? commitMessage ?? `Change for ${repo.fullName ?? repoId}`,
        prDescription ?? 'Opened from CodeCatalystAI after user approval.',
        repo.apiBaseUrl ?? undefined,
      );
    } else if (actionType === 'merge_pr') {
      const mergeNumber = data.pullRequestNumber ?? data.mergeRequestId;
      if (typeof mergeNumber !== 'number') {
        throw new HttpsError('invalid-argument', 'pullRequestNumber or mergeRequestId is required for merge_pr.');
      }
      remoteResult = await mergeRemotePullRequest(
        provider,
        tokenInfo.token,
        {
          owner: repo.owner ?? '',
          name: repo.name ?? '',
          remoteId: repo.remoteId ?? null,
        },
        mergeNumber,
        mergeMethod,
        repo.apiBaseUrl ?? undefined,
      );
    } else if (actionType === 'commit') {
      if (fileChanges.length === 0) {
        await releaseWalletTokens(
          ownerId,
          repoId,
          estimatedTokens,
          tokenProvider,
          estimatedTokens,
          actionType,
          'Released reservation until file payload is attached.',
          {
            latencyMs: Date.now() - startedAt,
          },
        );
        await db.collection('gitActions').doc(actionRef.id).set(
          {
            status: 'queued',
            executionState: 'awaiting_file_payload',
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        await writeActivityEntry(ownerId, 'commit', actionRef.id, 'Commit queued until file payload is attached.', {
          repoId,
        });
        return {
          gitActionId: actionRef.id,
          status: 'queued',
          executionState: 'awaiting_file_payload',
        };
      }

      remoteResult = await commitRemoteChanges(
        provider,
        tokenInfo.token,
        {
          owner: repo.owner ?? '',
          name: repo.name ?? '',
          remoteId: repo.remoteId ?? null,
          defaultBranch: repo.defaultBranch,
        },
        branchName ?? repo.defaultBranch ?? 'main',
        commitMessage ?? `CodeCatalystAI commit for ${repo.fullName ?? repoId}`,
        fileChanges,
        repo.apiBaseUrl ?? undefined,
      );
    }

    await captureWalletTokens(
      ownerId,
      repoId,
      estimatedTokens,
      tokenProvider,
      estimatedTokens,
      actionType,
      'Remote Git action completed.',
      {
        actualProviderCostUsd: costSnapshot.estimatedProviderCostUsd,
        latencyMs: Date.now() - startedAt,
      },
    );

    await db.collection('gitActions').doc(actionRef.id).set(
      {
        status: 'completed',
        executionState: 'completed',
        remoteId: remoteResult?.remoteId ?? null,
        remoteUrl: remoteResult?.url ?? null,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await writeActivityEntry(ownerId, 'git_action', actionRef.id, `${actionType} completed for ${repo.fullName ?? repoId}.`, {
      provider,
      remoteUrl: remoteResult?.url ?? null,
    });

    await writeOperationalMetric({
      operation: 'submit_git_action',
      status: 'success',
      ownerId,
      repoId,
      provider,
      actionType,
      durationMs: Date.now() - startedAt,
      estimatedTokens,
      chargedTokens: estimatedTokens,
      estimatedProviderCostUsd: costSnapshot.estimatedProviderCostUsd,
      actualProviderCostUsd: null,
      estimatedMarginUsd: costSnapshot.estimatedMarginUsd,
      refundPolicy: costSnapshot.refundPolicy,
      dailyCap: costSnapshot.dailyCap,
      pricingVersion: costSnapshot.pricingVersion,
      remoteStatus: 'completed',
      remoteId: remoteResult?.remoteId ?? null,
      metadata: {
        remoteUrl: remoteResult?.url ?? null,
      },
    });
    await maybeSendLowBalanceNotification(ownerId);
    await sendPushNotification({
      ownerId,
      category: 'git',
      type: 'git_action_completed',
      title: actionType === 'merge_pr' ? 'Pull request merged' : 'Git action completed',
      body:
        actionType === 'open_pr'
          ? `Pull request opened for ${repo.fullName ?? repoId}.`
          : actionType === 'commit'
            ? `Commit pushed for ${repo.fullName ?? repoId}.`
            : actionType === 'merge_pr'
              ? `Merge completed for ${repo.fullName ?? repoId}.`
              : `Branch created for ${repo.fullName ?? repoId}.`,
      destination: 'repo',
      repoId,
    });

    return {
      gitActionId: actionRef.id,
      status: 'completed',
      remoteId: remoteResult?.remoteId ?? null,
      remoteUrl: remoteResult?.url ?? null,
    };
  } catch (error) {
    const normalizedError = normalizeError(error);
    try {
      await releaseWalletTokens(
        ownerId,
        repoId,
        estimatedTokens,
        tokenProvider,
        estimatedTokens,
        actionType,
        'Released reservation after Git action failed.',
        {
          latencyMs: Date.now() - startedAt,
        },
      );
    } catch (cleanupError) {
      functions.logger.error('submitGitAction.releaseWalletTokens.failed', cleanupError);
    }
    try {
      await db.collection('gitActions').doc(actionRef.id).set(
        {
          status: 'queued',
          executionState: 'remote_failed',
          errorMessage: normalizedError.message,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    } catch (cleanupError) {
      functions.logger.error('submitGitAction.persistFailure.failed', cleanupError);
    }
    try {
      await writeOperationalMetric({
        operation: 'submit_git_action',
        status: 'failure',
        ownerId,
        repoId,
        provider,
        actionType,
        durationMs: Date.now() - startedAt,
        estimatedTokens,
        chargedTokens: 0,
        estimatedProviderCostUsd: costSnapshot.estimatedProviderCostUsd,
        actualProviderCostUsd: null,
        estimatedMarginUsd: costSnapshot.estimatedMarginUsd,
        refundPolicy: costSnapshot.refundPolicy,
        dailyCap: costSnapshot.dailyCap,
        pricingVersion: costSnapshot.pricingVersion,
        errorCode: normalizedError.code,
        errorMessage: normalizedError.message,
        remoteStatus: 'remote_failed',
      });
    } catch (cleanupError) {
      functions.logger.error('submitGitAction.writeOperationalMetric.failed', cleanupError);
    }
    await sendPushNotification({
      ownerId,
      category: 'git',
      type: 'git_action_failed',
      title: 'Git action failed',
      body: normalizedError.message,
      destination: 'repo',
      repoId,
    });
    throw error instanceof HttpsError
      ? error
      : new HttpsError(normalizedError.code as any, normalizedError.message);
  }
});

interface ListRepoWorkflowsData {
  repoId?: string;
}

export const listRepoWorkflows = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const ownerId = requireAuth(request);
  const data = (request.data ?? {}) as ListRepoWorkflowsData;
  const repoId = asString(data.repoId, 'repoId');
  const repo = await ensureRepositoryAccess(repoId, ownerId);
  const tokenInfo = await resolveProviderToken(ownerId, repo.provider!);
  if (!tokenInfo) {
    return { provider: repo.provider, workflows: [] };
  }
  if (repo.provider === 'github') {
    const workflows = await listGitHubWorkflows(
      tokenInfo.token,
      repo.owner!,
      repo.name!,
      repo.apiBaseUrl ?? undefined,
    );
    return { provider: repo.provider, workflows };
  }
  return { provider: repo.provider, workflows: [] };
});

export const submitCheckAction = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const startedAt = Date.now();
  const ownerId = requireAuth(request);
  const data = request.data as Partial<CheckActionData>;
  const repoId = asString(data.repoId, 'repoId');
  const provider = asEnum(data.provider, 'provider', ['github', 'github'] as const);
  const actionType = asEnum(data.actionType, 'actionType', CHECK_ACTION_TYPES);
  const workflowName = asString(data.workflowName, 'workflowName');
  const repo = await ensureRepositoryAccess(repoId, ownerId);
  const ref = asOptionalString(data.ref) ?? repo.defaultBranch ?? 'main';
  const inputs = coerceRecord(data.inputs);
  const confirmed = data.confirmed === true;
  const estimatedTokens = buildActionCost(
    actionType,
    actionType === 'build_project' ? 40 : actionType === 'run_tests' ? 30 : 12,
  );
  const tokenProvider = provider;
  const costSnapshot = buildCostSnapshot({
    actionType,
    provider,
    estimatedTokens,
  });

  await reserveWalletTokens(
    ownerId,
    repoId,
    estimatedTokens,
    tokenProvider,
    estimatedTokens,
    actionType,
    `Reserved tokens for ${actionType}.`,
  );

  const checkRef = await db.collection('checksRuns').add({
    ownerId,
    repoId,
    provider,
    actionType,
    workflowName,
    ref,
    inputs,
    status: confirmed ? 'running' : 'queued',
    executionState: confirmed ? 'running' : 'awaiting_confirmation',
    logsUrl: null,
    summary: null,
    estimatedTokens,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  await writeActivityEntry(ownerId, 'check_action', checkRef.id, `Queued ${actionType} check ${workflowName}.`, {
    provider,
    confirmed,
  });

  if (!confirmed) {
    await releaseWalletTokens(
      ownerId,
      repoId,
      estimatedTokens,
      tokenProvider,
      estimatedTokens,
      actionType,
      'Check action requires explicit confirmation.',
    );
    await writeOperationalMetric({
      operation: 'submit_check_action',
      status: 'queued',
      ownerId,
      repoId,
      provider,
      actionType,
      durationMs: Date.now() - startedAt,
      estimatedTokens,
      chargedTokens: 0,
      estimatedProviderCostUsd: costSnapshot.estimatedProviderCostUsd,
      actualProviderCostUsd: null,
      estimatedMarginUsd: costSnapshot.estimatedMarginUsd,
      refundPolicy: costSnapshot.refundPolicy,
      dailyCap: costSnapshot.dailyCap,
      pricingVersion: costSnapshot.pricingVersion,
      remoteStatus: 'awaiting_confirmation',
      metadata: {
        workflowName,
      },
    });
    return {
      checkRunId: checkRef.id,
      status: 'queued',
      requiresApproval: true,
      estimatedTokens,
    };
  }

  const tokenInfo = await resolveProviderToken(ownerId, provider);
  if (!tokenInfo) {
    await releaseWalletTokens(
      ownerId,
      repoId,
      estimatedTokens,
      tokenProvider,
      estimatedTokens,
      actionType,
      'Released reservation until provider configuration is added.',
      {
        latencyMs: Date.now() - startedAt,
      },
    );
    await db.collection('checksRuns').doc(checkRef.id).set(
      {
        status: 'queued',
        executionState: 'awaiting_provider_configuration',
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await writeActivityEntry(ownerId, 'check_action', checkRef.id, `Check provider token missing for ${provider}.`, {
      provider,
    });
    await writeOperationalMetric({
      operation: 'submit_check_action',
      status: 'warning',
      ownerId,
      repoId,
      provider,
      actionType,
      durationMs: Date.now() - startedAt,
      estimatedTokens,
      chargedTokens: 0,
      estimatedProviderCostUsd: costSnapshot.estimatedProviderCostUsd,
      actualProviderCostUsd: null,
      estimatedMarginUsd: costSnapshot.estimatedMarginUsd,
      refundPolicy: costSnapshot.refundPolicy,
      dailyCap: costSnapshot.dailyCap,
      pricingVersion: costSnapshot.pricingVersion,
      remoteStatus: 'awaiting_provider_configuration',
      metadata: {
        workflowName,
      },
    });
    return {
      checkRunId: checkRef.id,
      status: 'queued',
      executionState: 'awaiting_provider_configuration',
    };
  }

  try {
    const remoteResult = await triggerCheckExecution(
      provider,
      tokenInfo.token,
      {
        owner: repo.owner ?? '',
        name: repo.name ?? '',
        remoteId: repo.remoteId ?? null,
        defaultBranch: repo.defaultBranch,
      },
      workflowName,
      ref,
      inputs,
      repo.apiBaseUrl ?? undefined,
    );

    await captureWalletTokens(
      ownerId,
      repoId,
      estimatedTokens,
      tokenProvider,
      estimatedTokens,
      actionType,
      'Check action dispatched successfully.',
      {
        actualProviderCostUsd: costSnapshot.estimatedProviderCostUsd,
        latencyMs: Date.now() - startedAt,
      },
    );

    await db.collection('checksRuns').doc(checkRef.id).set(
      {
        status: remoteResult.status,
        executionState: remoteResult.status,
        logsUrl: remoteResult.logsUrl,
        remoteId: remoteResult.remoteId,
        summary: `${workflowName} triggered from CodeCatalystAI.`,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await writeActivityEntry(ownerId, 'checks', checkRef.id, `${actionType} dispatched for ${repo.fullName ?? repoId}.`, {
      provider,
      workflowName,
      remoteId: remoteResult.remoteId,
    });

    await writeOperationalMetric({
      operation: 'submit_check_action',
      status: 'success',
      ownerId,
      repoId,
      provider,
      actionType,
      durationMs: Date.now() - startedAt,
      estimatedTokens,
      chargedTokens: estimatedTokens,
      estimatedProviderCostUsd: costSnapshot.estimatedProviderCostUsd,
      actualProviderCostUsd: null,
      estimatedMarginUsd: costSnapshot.estimatedMarginUsd,
      refundPolicy: costSnapshot.refundPolicy,
      dailyCap: costSnapshot.dailyCap,
      pricingVersion: costSnapshot.pricingVersion,
      remoteStatus: remoteResult.status,
      remoteId: remoteResult.remoteId,
      metadata: {
        workflowName,
        logsUrl: remoteResult.logsUrl,
      },
    });

    await sendPushNotification({
      ownerId,
      category: 'checks',
      type: 'workflow_finished',
      title: 'Check dispatched',
      body: `${workflowName} was triggered for ${repo.fullName ?? repoId}.`,
      destination: 'checks',
      repoId,
    });

    return {
      checkRunId: checkRef.id,
      status: remoteResult.status,
      logsUrl: remoteResult.logsUrl,
      remoteId: remoteResult.remoteId,
    };
  } catch (error) {
    await releaseWalletTokens(
      ownerId,
      repoId,
      estimatedTokens,
      tokenProvider,
      estimatedTokens,
      actionType,
      'Released reservation after check trigger failed.',
      {
        latencyMs: Date.now() - startedAt,
      },
    );
    await db.collection('checksRuns').doc(checkRef.id).set(
      {
        status: 'failed',
        executionState: 'failed',
        errorMessage: error instanceof Error ? error.message : 'Unknown error',
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    const normalizedError = normalizeError(error);
    await writeOperationalMetric({
      operation: 'submit_check_action',
      status: 'failure',
      ownerId,
      repoId,
      provider,
      actionType,
      durationMs: Date.now() - startedAt,
      estimatedTokens,
      chargedTokens: 0,
      estimatedProviderCostUsd: costSnapshot.estimatedProviderCostUsd,
      actualProviderCostUsd: null,
      estimatedMarginUsd: costSnapshot.estimatedMarginUsd,
      refundPolicy: costSnapshot.refundPolicy,
      dailyCap: costSnapshot.dailyCap,
      pricingVersion: costSnapshot.pricingVersion,
      errorCode: normalizedError.code,
      errorMessage: normalizedError.message,
      remoteStatus: 'failed',
      metadata: {
        workflowName,
      },
    });
    await sendPushNotification({
      ownerId,
      category: 'checks',
      type: 'check_failed',
      title: 'Check failed',
      body: normalizedError.message,
      destination: 'checks',
      repoId,
    });
    throw error;
  }
});

export const reserveTokens = onCall(BASE_CALLABLE_OPTIONS, async request => {
  const ownerId = requireAuth(request);
  const data = request.data as Partial<TokenActionData>;
  const repoId = asString(data.repoId, 'repoId');
  const actionType = asEnum(data.actionType, 'actionType', BILLABLE_ACTION_TYPES);
  const amount = asInteger(data.amount, 'amount');
  const costPreview = asInteger(data.costPreview, 'costPreview');
  const provider = asEnum(data.provider, 'provider', PROVIDER_NAMES);
  const reason = asOptionalString(data.reason);

  await reserveWalletTokens(
    ownerId,
    repoId,
    amount,
    provider,
    costPreview,
    actionType,
    reason ?? `Reserved ${amount} tokens.`,
  );

  await writeActivityEntry(ownerId, 'wallet', repoId, `Reserved ${amount} tokens for ${actionType}.`, {
    provider,
    costPreview,
  });

  return {
    reserved: amount,
    status: 'reserved',
  };
});

export const releaseTokens = onCall(BASE_CALLABLE_OPTIONS, async request => {
  const ownerId = requireAuth(request);
  const data = request.data as Partial<TokenActionData>;
  const repoId = asString(data.repoId, 'repoId');
  const actionType = asEnum(data.actionType, 'actionType', BILLABLE_ACTION_TYPES);
  const amount = asInteger(data.amount, 'amount');
  const provider = asEnum(data.provider, 'provider', PROVIDER_NAMES);
  const costPreview = asInteger(data.costPreview, 'costPreview');
  const reason = asOptionalString(data.reason);

  await releaseWalletTokens(
    ownerId,
    repoId,
    amount,
    provider,
    costPreview,
    actionType,
    reason ?? `Released ${amount} reserved tokens.`,
  );

  await writeActivityEntry(ownerId, 'wallet', repoId, `Released ${amount} reserved tokens.`, {
    provider,
    costPreview,
  });

  return {
    released: amount,
    status: 'released',
  };
});

export const captureTokens = onCall(BASE_CALLABLE_OPTIONS, async request => {
  const ownerId = requireAuth(request);
  const data = request.data as Partial<TokenActionData>;
  const repoId = asString(data.repoId, 'repoId');
  const actionType = asEnum(data.actionType, 'actionType', BILLABLE_ACTION_TYPES);
  const amount = asInteger(data.amount, 'amount');
  const provider = asEnum(data.provider, 'provider', PROVIDER_NAMES);
  const costPreview = asInteger(data.costPreview, 'costPreview');
  const reason = asOptionalString(data.reason);

  await captureWalletTokens(
    ownerId,
    repoId,
    amount,
    provider,
    costPreview,
    actionType,
    reason ?? `Captured ${amount} tokens.`,
  );

  await writeActivityEntry(ownerId, 'wallet', repoId, `Captured ${amount} tokens.`, {
    provider,
    costPreview,
  });

  await maybeSendLowBalanceNotification(ownerId);

  return {
    captured: amount,
    status: 'captured',
  };
});

/** Returns subscription state from wallet for the current user (for paywall/UI). */
export const getSubscriptionState = onCall(BASE_CALLABLE_OPTIONS, async request => {
  const ownerId = requireAuth(request);
  const walletRef = db.collection('wallets').doc(ownerId);
  const snap = await walletRef.get();
  const data = snap.data();
  const planId = (data?.planId as PlanId | undefined) ?? 'free';
  const rawExp = data?.subscriptionExpiresAt;
  const expiresAt =
    typeof rawExp === 'number' ? rawExp : typeof rawExp?.toMillis === 'function' ? (rawExp as { toMillis: () => number }).toMillis() : null;
  const productId = data?.subscriptionProductId as string | undefined ?? null;
  const isActive = planId === 'free' || (expiresAt != null && expiresAt > Date.now());
  return {
    planId,
    productId,
    expiresAt,
    isActive,
  };
});

const APPLE_VERIFY_RECEIPT_URL = 'https://buy.itunes.apple.com/verifyReceipt';
const APPLE_VERIFY_RECEIPT_SANDBOX_URL = 'https://sandbox.itunes.apple.com/verifyReceipt';
const SUBSCRIPTION_PRODUCT_IDS = new Set<string>([
  PLANS.pro.productId!,
  PLANS.power.productId!,
]);
const TOKEN_PACK_PRODUCT_IDS = new Set<string>(
  Object.values(TOP_UP_PACKS).map(p => p.productId),
);

interface SyncPurchasePayload {
  platform: string;
  productId: string;
  purchaseId?: string;
  verificationData: string;
  source?: 'purchase' | 'restore';
}

/** Validates IAP receipt (iOS/Android) and updates wallet (subscription or token top-up). */
export const syncPurchase = onCall(IAP_CALLABLE_OPTIONS, async request => {
  const ownerId = requireAuth(request);
  const data = request.data as Partial<SyncPurchasePayload>;
  const platform = asString(data.platform ?? '', 'platform');
  const productId = asString(data.productId ?? '', 'productId');
  const verificationData = asString(data.verificationData ?? '', 'verificationData');
  const source = (data.source === 'restore' ? 'restore' : 'purchase') as 'purchase' | 'restore';

  if (SUBSCRIPTION_PRODUCT_IDS.has(productId)) {
    if (platform === 'ios') {
      const sharedSecret = process.env.APPLE_IAP_SHARED_SECRET ?? process.env.APPLE_SHARED_SECRET;
      if (!sharedSecret?.trim()) {
        throw new HttpsError(
          'failed-precondition',
          'IAP receipt validation is not configured (missing APPLE_IAP_SHARED_SECRET).',
        );
      }
      const verified = await verifyAppleReceipt(verificationData, sharedSecret.trim(), productId);
      if (!verified.valid) {
        throw new HttpsError('invalid-argument', verified.error ?? 'Invalid receipt');
      }
      const planId = productId === PLANS.power.productId ? 'power' : 'pro';
      const expiresAtMs = verified.expiresAtMs ?? Date.now() + 30 * 24 * 60 * 60 * 1000;
      await applySubscriptionToWallet(ownerId, planId as PlanId, productId, expiresAtMs);
      const plan = PLANS[planId as PlanId];
      return {
        planId,
        productId,
        expiresAt: expiresAtMs,
        isActive: true,
      };
    }
    if (platform === 'android') {
      throw new HttpsError(
        'failed-precondition',
        'Android purchase verification is not enabled yet. Configure Play verification before enabling Android IAP in production.',
      );
    }
  }

  if (TOKEN_PACK_PRODUCT_IDS.has(productId)) {
    const pack = Object.entries(TOP_UP_PACKS).find(([, p]) => p.productId === productId)?.[1];
    if (pack) {
      if (platform === 'ios') {
        const sharedSecret = process.env.APPLE_IAP_SHARED_SECRET ?? process.env.APPLE_SHARED_SECRET;
        if (!sharedSecret?.trim()) {
          throw new HttpsError(
            'failed-precondition',
            'IAP receipt validation is not configured (missing APPLE_IAP_SHARED_SECRET).',
          );
        } else {
          const verified = await verifyAppleReceipt(verificationData, sharedSecret.trim(), productId);
          if (!verified.valid) {
            throw new HttpsError('invalid-argument', verified.error ?? 'Invalid receipt');
          }
        }
      } else if (platform === 'android') {
        throw new HttpsError(
          'failed-precondition',
          'Android purchase verification is not enabled yet. Configure Play verification before enabling Android IAP in production.',
        );
      }
      await addTokensToWallet(ownerId, pack.tokens, productId, source);
      const walletSnap = await db.collection('wallets').doc(ownerId).get();
      const current = normalizeWalletState(walletSnap.data());
      return {
        planId: (walletSnap.data()?.planId as PlanId) ?? 'free',
        productId: walletSnap.data()?.subscriptionProductId as string ?? null,
        expiresAt: (walletSnap.data()?.subscriptionExpiresAt as number) ?? null,
        isActive: true,
      };
    }
  }

  throw new HttpsError('invalid-argument', `Unknown product: ${productId}`);
});

async function verifyAppleReceipt(
  receiptDataBase64: string,
  sharedSecret: string,
  expectedProductId: string,
): Promise<{ valid: boolean; expiresAtMs?: number; error?: string }> {
  const body = JSON.stringify({
    'receipt-data': receiptDataBase64,
    password: sharedSecret,
    'exclude-old-transactions': true,
  });
  let res = await fetch(APPLE_VERIFY_RECEIPT_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });
  let json = (await res.json()) as {
    status: number;
    latest_receipt_info?: Array<{ expires_date_ms?: string; product_id?: string }>;
  };
  if (json.status === 21007) {
    res = await fetch(APPLE_VERIFY_RECEIPT_SANDBOX_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body,
    });
    json = (await res.json()) as {
      status: number;
      latest_receipt_info?: Array<{ expires_date_ms?: string; product_id?: string }>;
    };
  }
  if (json.status !== 0) {
    return { valid: false, error: `Apple status ${json.status}` };
  }
  const latest = json.latest_receipt_info;
  let expiresAtMs: number | undefined;
  if (Array.isArray(latest) && latest.length > 0) {
    const hasExpectedProduct = latest.some(item => item.product_id === expectedProductId);
    if (!hasExpectedProduct) {
      return { valid: false, error: 'Receipt does not contain the requested product.' };
    }
    const last = latest[latest.length - 1];
    if (last?.expires_date_ms) {
      expiresAtMs = parseInt(last.expires_date_ms, 10);
    }
  }
  return { valid: true, expiresAtMs };
}

async function applySubscriptionToWallet(
  ownerId: string,
  planId: PlanId,
  productId: string,
  expiresAtMs: number,
): Promise<void> {
  const plan = PLANS[planId];
  const walletRef = db.collection('wallets').doc(ownerId);
  await walletRef.set(
    {
      planId,
      planName: plan.displayName,
      monthlyLimit: plan.monthlyIncludedTokens,
      dailyActionCap: plan.dailyActionCap,
      subscriptionProductId: productId,
      subscriptionExpiresAt: expiresAtMs,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function addTokensToWallet(
  ownerId: string,
  tokens: number,
  productId: string,
  source: string,
): Promise<void> {
  const walletRef = db.collection('wallets').doc(ownerId);
  await db.runTransaction(async transaction => {
    const snap = await transaction.get(walletRef);
    const current = normalizeWalletState(snap.data());
    const newBalance = current.balance + tokens;
    transaction.set(
      walletRef,
      {
        balance: newBalance,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    transaction.set(walletRef.collection('usage').doc(), {
      actionType: 'top_up',
      amount: tokens,
      beforeBalance: current.balance,
      afterBalance: newBalance,
      reason: `${source}: ${productId}`,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
}
