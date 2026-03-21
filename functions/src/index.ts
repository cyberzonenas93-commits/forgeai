import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { existsSync } from 'node:fs';
import path from 'node:path';
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
import { onDocumentCreated, onDocumentWritten } from 'firebase-functions/v2/firestore';
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
  appendAgentCostLedgerEntry,
  buildAgentTaskBudgetSnapshot,
  chooseAgentCostProfile,
  estimateAgentStageCostUsd,
  remainingTaskBudgetRatio,
  summarizeAgentCostLedger,
  type AgentCostLedgerEntry,
  type AgentCostStage,
} from './cost_optimization';
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
  buildRepoExecutionPlanningSystemPrompt,
  buildRepoExecutionPlanningUserPrompt,
  buildRepoExecutionRepairPrompt,
  buildRepoExecutionSystemPrompt,
  buildRepoExecutionUserPrompt,
  parseRepoExecutionPlanResponse,
  parseRepoExecutionResponse,
  summarizeRepoExecution,
} from './repo_execution_format';
import {
  buildRepoContextManifest,
  buildRepoContextPlannerSystemPrompt,
  buildRepoContextPlannerUserPrompt,
  expandRepoContextPaths,
  formatRepoContextManifest,
  parseRepoContextExpansionPlan,
  pickGlobalContextPaths,
} from './repo_context_strategy';
import {
  buildInitialKnowledgeSeedPaths,
  buildRepoContextBudget,
  buildRepoKnowledgeMap,
  collectModulePaths,
  collectRelatedModules,
  collectRelatedPaths,
  createRepoExecutionRunMemory,
  findPromptFocusedModules,
  formatFocusedModuleDetails,
  formatRepoExecutionRunMemory,
  formatRepoKnowledgeMap,
  recordRepoExecutionMemoryPass,
  selectMemoryModuleSummaries,
  serializeRepoExecutionRunMemory,
  serializeRepoKnowledgeMap,
  type RepoExecutionRunMemory,
  type RepoKnowledgeMap,
} from './repo_knowledge_map';
import { buildContextOrchestratorSnapshot } from './context_orchestrator';
import {
  loadExecutionMemorySnapshot,
  persistExecutionMemorySnapshot,
} from './execution_memory_store';
import {
  appendDistributedWorkerMetric,
  buildDistributedAgentWorkerRunId,
  claimDistributedAgentWorkerRun,
  finalizeDistributedAgentWorkerRun,
  heartbeatDistributedAgentWorkerRun,
  queueDistributedAgentWorkerRun,
  recoverStaleDistributedAgentWorkerRuns,
  serializeDistributedWorkerMetadata,
} from './distributed_agent_runtime';
import {
  buildValidationWorkflowPlan,
  runStaticRepoValidations,
  serializeValidationToolResults,
  summarizeValidationToolResults,
  type AgentValidationFinding,
  type AgentValidationToolResult,
  type PlannedValidationWorkflow,
  type RepoWorkingCopyFile,
} from './agent_validation_tools';
import {
  applyEphemeralWorkspaceEdits,
  checkoutEphemeralWorkspaceBranch,
  cleanupEphemeralWorkspace,
  cloneEphemeralWorkspace,
  commitEphemeralWorkspaceChanges,
  detectLocalWorkspaceValidationCommands,
  materializeLocalRepoWorkspace,
  materializeEphemeralWorkspace,
  pushEphemeralWorkspaceBranch,
  readEphemeralWorkspaceHeadRevision,
  runLocalWorkspaceCommand,
  runOpenShellCommand,
  snapshotEphemeralWorkspace,
  type LocalWorkspaceValidationCommand,
  type LocalRepoWorkspaceInfo,
} from './ephemeral_workspace';
import { callProviderTextCompletion } from './provider_interface';
import {
  appendLogicalAgentRecord,
  buildLogicalAgentPlan,
  buildLogicalAgentRecord,
  summarizeLogicalAgentTimeline,
  type LogicalAgentRole,
} from './multi_agent_system';
import { persistRepoMapSnapshot } from './repo_map_service';
import { resolveRepoExecutionProviderRouting } from './routing_engine';
import {
  buildAgentToolRegistry,
  getAgentToolDefinition,
  serializeAgentToolRegistry,
  summarizeAgentToolRegistry,
} from './tool_registry';
import { executeAgentTool, type AgentToolExecutionRecord } from './tool_executor';
import { parseToolOutputFindings, summarizeToolOutputFailure } from './tool_output_parser';
import {
  indexFileEmbeddings,
  markRepoEmbeddingsIndexed,
} from './vector_store';
import { recordRoutingMetric } from './routing_metrics';
import { resolveRepoExecutionProviderRoutingAsync } from './routing_engine';

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
  secrets: ['OPENAI_API_KEY', 'ANTHROPIC_API_KEY'],
};
const GIT_AND_AI_CALLABLE_OPTIONS: CallableOptions = {
  ...BASE_CALLABLE_OPTIONS,
  secrets: ['OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'GITHUB_TOKEN'],
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
  secrets: ['OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'GITHUB_TOKEN'],
};
const AGENT_WORKER_RUNTIME_OPTIONS = {
  ...AGENT_TASK_RUNTIME_OPTIONS,
  memory: '2GiB' as const,
};
const CHECK_MONITOR_RUNTIME_OPTIONS = {
  region: runtimeSettings.firebaseRegion,
  timeoutSeconds: 540,
  memory: '1GiB' as const,
  secrets: ['GITHUB_TOKEN'],
};
const AGENT_TASK_MAX_RUNTIME_MS = 8 * 60_000;
const AGENT_WORKER_LEASE_MS = 90_000;
const AGENT_WORKER_HEARTBEAT_MS = 20_000;
const AGENT_TASK_MAX_RETRIES_NORMAL = 3;
const AGENT_TASK_MAX_RETRIES_DEEP = 5;
const AGENT_TASK_MAX_TOKEN_BUDGET_NORMAL = 30_000;
const AGENT_TASK_MAX_TOKEN_BUDGET_DEEP = 60_000;
const AGENT_TASK_MAX_FILE_TOUCHES_NORMAL = 6;
const AGENT_TASK_MAX_FILE_TOUCHES_DEEP = 14;
const AGENT_TASK_STALE_RUNNING_LOCK_MS = 15 * 60_000;
const DISTRIBUTED_AGENT_STALE_WORKER_MS = 3 * 60_000;
const REPO_SYNC_TREE_LIMIT = 10_000;
const FIRESTORE_BATCH_WRITE_LIMIT = 400;
const REPO_VALIDATION_POLL_INTERVAL_MS = 5_000;
const REPO_VALIDATION_TIMEOUT_MS = 3 * 60_000;

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
  provider?: ProviderName;
  trustLevel?: AgentTaskTrustLevel;
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
  treeTruncated?: boolean;
  totalTreeEntries?: number | null;
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
  | 'validation_passed'
  | 'validation_failed'
  | 'tool_started'
  | 'tool_passed'
  | 'tool_failed'
  | 'tool_skipped'
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

// Trust level for autonomous agent execution.
// SUPERVISED: all approval gates are enforced (default behaviour).
// AUTO_APPROVE_ON_SUCCESS: skip approval gates when validation passes; still pause on failure.
// FULLY_AUTONOMOUS: skip all approval gates, including after validation failures.
type AgentTaskTrustLevel = 'SUPERVISED' | 'AUTO_APPROVE_ON_SUCCESS' | 'FULLY_AUTONOMOUS';

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
  trustLevel: AgentTaskTrustLevel;
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
  streamLog?: AgentStreamLogEntry[];
}

interface AgentStreamLogEntry {
  timestampMs: number;
  type: 'stdout' | 'stderr' | 'info' | 'error';
  content: string;
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

interface AgentValidationToolSuiteResult {
  passed: boolean;
  summary: string;
  results: AgentValidationToolResult[];
  branchName: string | null;
}

interface RepoExecutionObserver {
  onRepoScanned?: (details: { fileCount: number }) => Promise<void> | void;
  onFilesSelected?: (details: {
    selectedFiles: string[];
    dependencyFiles: string[];
    inspectedFiles: string[];
    globalContextFiles: string[];
    wholeRepoEligible: boolean;
    planningSummary?: string;
    repoOverview?: string;
    architectureOverview?: string;
    moduleOverview?: string;
    repoSizeClass?: string;
    contextStrategy?: string;
    executionMemorySummary?: string;
    focusedModules?: string[];
    repoCoverageNotice?: string;
    moduleCount?: number;
    architectureZoneCount?: number;
    explorationPassCount?: number;
    hydratedPathCount?: number;
    contextPlannerProvider?: AiProviderName;
    contextPlannerModel?: string;
    executionPlannerProvider?: AiProviderName;
    executionPlannerModel?: string;
  }) => Promise<void> | void;
  onExplorationPass?: (details: {
    passNumber: number;
    totalPasses: number;
    wholeRepoInline: boolean;
    repoSizeClass: string;
    contextStrategy: string;
    focusModules: string[];
    requestedPaths: string[];
    hydratedPaths: string[];
    promotedPaths: string[];
    readOnlyPaths: string[];
    architectureFindings: string[];
    uncertainties: string[];
    rationale: string;
    done: boolean;
    executionMemorySummary: string;
    repoCoverageNotice?: string;
    moduleCount?: number;
    architectureZoneCount?: number;
  }) => Promise<void> | void;
  onFileRead?: (details: { path: string; source: string }) => Promise<void> | void;
  onAiCalled?: (details: {
    attempt: number;
    mode: RepoExecutionMode;
    provider?: AiProviderName;
    model?: string;
    stage?: string;
    reason?: string;
  }) => Promise<void> | void;
  onRetrying?: (details: { reason: string; attempt: number }) => Promise<void> | void;
  onDiffGenerated?: (details: {
    editCount: number;
    summary: string;
    sessionId: string;
  }) => Promise<void> | void;
}

async function requireAuth(request: CallableRequest<unknown>): Promise<string> {
  // Primary path: the callable SDK included the Authorization header and
  // Firebase already verified the token, populating `request.auth`.
  if (request.auth?.uid) {
    return request.auth.uid;
  }

  // Fallback path: on iOS the cloud_functions SDK sometimes fails to include
  // the Authorization header (native FIRAuth stale state). The client passes
  // the Dart-side ID token inside the payload as `_idToken`. Verify it
  // manually via Firebase Admin Auth and return the UID.
  const data = (request.data ?? {}) as Record<string, unknown>;
  const fallbackToken =
    typeof data._idToken === 'string' ? data._idToken.trim() : '';
  if (fallbackToken) {
    try {
      const decoded = await getAuth().verifyIdToken(fallbackToken);
      return decoded.uid;
    } catch {
      // Token verification failed — fall through to throw unauthenticated.
    }
  }

  throw new HttpsError('unauthenticated', 'Authentication is required.');
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
    maxRetries: deepMode
      ? AGENT_TASK_MAX_RETRIES_DEEP
      : AGENT_TASK_MAX_RETRIES_NORMAL,
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

function defaultAgentPlanSummary(plan: AgentTaskFollowUpPlan) {
  const followUps: string[] = [];
  if (plan.openPullRequest) {
    followUps.push(plan.mergePullRequest ? 'open and merge a pull request' : 'open a pull request');
  } else if (plan.commitChanges) {
    followUps.push('push a commit');
  }
  if (plan.deployWorkflow) {
    followUps.push('dispatch deployment');
  }
  if (followUps.length === 0) {
    return 'Inspect the repository deeply, prepare and validate a multi-file diff in a sandbox workspace, then pause for apply approval before finishing.';
  }
  return `Inspect the repository deeply, prepare and validate a multi-file diff in a sandbox workspace, pause for apply approval, and ${followUps.join(' and ')} if approvals allow.`;
}

function defaultAgentPlannedSteps(plan: AgentTaskFollowUpPlan) {
  const steps = [
    'Inspect the repository and expand context around the request.',
    'Generate a multi-file diff, validate it in a sandbox workspace, and repair failures until stable or limits are hit.',
    'Pause for review once the candidate diff has already passed validation.',
    'Apply approved edits to the task-local workspace and confirm post-apply consistency.',
  ];
  if (plan.openPullRequest) {
    steps.push('Create a branch, commit the local workspace, and open a pull request after approval.');
  } else if (plan.commitChanges) {
    steps.push('Commit the approved local workspace after approval.');
  }
  if (plan.mergePullRequest) {
    steps.push('Merge the pull request after a final approval checkpoint.');
  }
  if (plan.deployWorkflow) {
    steps.push('Dispatch the deployment workflow after approval.');
  }
  return steps;
}

function sanitizeAgentPlanSteps(value: unknown, fallback: string[]) {
  if (!Array.isArray(value)) {
    return fallback;
  }
  const steps = value
    .filter((item): item is string => typeof item === 'string')
    .map(item => normalizeText(item))
    .filter(Boolean)
    .slice(0, 7);
  return steps.length > 0 ? steps : fallback;
}

function sanitizeAgentFollowUpPlan(
  value: unknown,
  fallback: AgentTaskFollowUpPlan,
): AgentTaskFollowUpPlan {
  if (!isObject(value)) {
    return fallback;
  }
  const mergePullRequest = value.mergePullRequest === true;
  const openPullRequest = value.openPullRequest === true || mergePullRequest;
  const commitChanges = value.commitChanges === true || openPullRequest;
  return {
    commitChanges,
    openPullRequest,
    mergePullRequest,
    deployWorkflow: value.deployWorkflow === true,
    riskyOperation: value.riskyOperation === true || fallback.riskyOperation,
  };
}

async function planAgentFollowUp(params: {
  prompt: string;
  repoId: string;
  currentFilePath?: string | null;
  deepMode: boolean;
}) {
  const fallbackPlan = inferAgentFollowUpPlan(params.prompt);
  const fallback = {
    plan: fallbackPlan,
    summary: defaultAgentPlanSummary(fallbackPlan),
    steps: defaultAgentPlannedSteps(fallbackPlan),
    source: 'heuristic' as const,
  };
  const tokenInfo = lookupProviderToken('openai');
  const model = defaultModelFor('openai');
  if (!tokenInfo || !model) {
    return fallback;
  }
  const systemPrompt = `You plan durable follow-up work for a repository coding agent. Return ONLY valid JSON with keys:
- commitChanges: boolean
- openPullRequest: boolean
- mergePullRequest: boolean
- deployWorkflow: boolean
- riskyOperation: boolean
- summary: string
- orderedSteps: string[]

Rules:
- Only set commitChanges/openPullRequest/mergePullRequest/deployWorkflow true when the user clearly asked for that remote action.
- mergePullRequest implies openPullRequest and commitChanges.
- openPullRequest implies commitChanges.
- riskyOperation should be true for destructive or forceful remote operations.
- summary should describe the intended end-to-end run in one concise sentence.
- orderedSteps should be 3 to 7 short, user-visible steps for the run.
- Do not mention internal implementation details, tokens, or model names.`;
  const userPrompt = JSON.stringify({
    prompt: params.prompt,
    repoId: params.repoId,
    currentFilePath: params.currentFilePath ?? null,
    deepMode: params.deepMode,
  });
  try {
    const response = await fetchJson<{ choices?: Array<{ message?: { content?: string | null } }> }>(
      `${providerBaseUrl('openai')}/chat/completions`,
      {
        method: 'POST',
        headers: buildOpenAiHeaders(tokenInfo.token),
        body: JSON.stringify(
          buildOpenAiChatCompletionJsonBody({
            model,
            temperature: 0,
            maxOutput: 280,
            responseFormat: { type: 'json_object' },
            messages: [
              { role: 'system', content: systemPrompt },
              { role: 'user', content: userPrompt },
            ],
          }),
        ),
      },
    );
    const raw = response.choices?.[0]?.message?.content ?? '{}';
    const parsed = parseJsonMaybe(raw);
    const plan = sanitizeAgentFollowUpPlan(parsed, fallbackPlan);
    const summary =
      isObject(parsed) && typeof parsed.summary === 'string' && normalizeText(parsed.summary).length > 0
        ? normalizeText(parsed.summary)
        : defaultAgentPlanSummary(plan);
    const steps = sanitizeAgentPlanSteps(
      isObject(parsed) ? parsed.orderedSteps : null,
      defaultAgentPlannedSteps(plan),
    );
    return {
      plan,
      summary,
      steps,
      source: 'ai' as const,
    };
  } catch {
    return fallback;
  }
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
    trustLevel:
      data?.trustLevel === 'AUTO_APPROVE_ON_SUCCESS' ||
      data?.trustLevel === 'FULLY_AUTONOMOUS'
        ? (data.trustLevel as AgentTaskTrustLevel)
        : 'SUPERVISED',
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
              : data?.deepMode === true
                ? AGENT_TASK_MAX_RETRIES_DEEP
                : AGENT_TASK_MAX_RETRIES_NORMAL,
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
    streamLog: Array.isArray(data?.streamLog) ? data.streamLog : [],
  };
}

// Appends a single real-time log entry to the task's streamLog array in
// Firestore.  Callers fire-and-forget; failures are silently swallowed so a
// logging hiccup never crashes the main execution path.
async function appendStreamLogEntry(
  ownerId: string,
  taskId: string,
  entry: AgentStreamLogEntry,
): Promise<void> {
  try {
    await agentTaskRef(ownerId, taskId).set(
      { streamLog: FieldValue.arrayUnion(entry), updatedAtMs: Date.now() },
      { merge: true },
    );
  } catch {
    // Non-fatal — streaming best-effort only.
  }
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

function coerceLocalWorkspaceInfo(value: unknown): LocalRepoWorkspaceInfo | null {
  if (!isObject(value)) {
    return null;
  }
  const workspacePath =
    typeof value.localWorkspacePath === 'string' ? value.localWorkspacePath.trim() : '';
  const manifestPath =
    typeof value.localWorkspaceManifestPath === 'string'
      ? value.localWorkspaceManifestPath.trim()
      : '';
  if (!workspacePath || !manifestPath) {
    return null;
  }
  return {
    workspacePath,
    manifestPath,
    fileCount:
      typeof value.localWorkspaceFileCount === 'number' ? value.localWorkspaceFileCount : 0,
    createdAtMs:
      typeof value.localWorkspaceCreatedAtMs === 'number'
        ? value.localWorkspaceCreatedAtMs
        : 0,
    provider: 'github',
    owner: typeof value.localWorkspaceOwner === 'string' ? value.localWorkspaceOwner : '',
    name: typeof value.localWorkspaceName === 'string' ? value.localWorkspaceName : '',
    defaultBranch:
      typeof value.localWorkspaceBaseBranch === 'string'
        ? value.localWorkspaceBaseBranch
        : 'main',
    htmlUrl:
      typeof value.localWorkspaceHtmlUrl === 'string' ? value.localWorkspaceHtmlUrl : null,
  };
}

function serializeLocalWorkspaceInfo(workspace: LocalRepoWorkspaceInfo) {
  return {
    localWorkspaceMode: 'repo_clone',
    localWorkspacePath: workspace.workspacePath,
    localWorkspaceManifestPath: workspace.manifestPath,
    localWorkspaceFileCount: workspace.fileCount,
    localWorkspaceCreatedAtMs: workspace.createdAtMs,
    localWorkspaceProvider: workspace.provider,
    localWorkspaceOwner: workspace.owner,
    localWorkspaceName: workspace.name,
    localWorkspaceBaseBranch: workspace.defaultBranch,
    localWorkspaceHtmlUrl: workspace.htmlUrl,
  };
}

async function ensureAgentTaskLocalWorkspace(
  ownerId: string,
  taskId: string,
  task: AgentTaskDocument,
) {
  const metadata = isObject(task.metadata) ? task.metadata : null;
  const existing = coerceLocalWorkspaceInfo(metadata);
  if (existing && existsSync(existing.workspacePath)) {
    return existing;
  }

  const repo = await ensureRepositoryAccess(task.repoId, ownerId);
  const provider = repo.provider ?? 'github';
  const tokenInfo = await resolveProviderToken(ownerId, provider);
  if (!tokenInfo) {
    throw new HttpsError(
      'failed-precondition',
      `No ${providerLabel(provider)} token configured for local workspace execution.`,
    );
  }
  if (!repo.owner || !repo.name) {
    throw new HttpsError(
      'failed-precondition',
      'Repository owner/name metadata is missing, so the agent cannot clone a local workspace.',
    );
  }

  const workspace = await materializeLocalRepoWorkspace({
    ownerId,
    repoId: task.repoId,
    taskId,
    provider: 'github',
    owner: repo.owner,
    name: repo.name,
    defaultBranch: repo.defaultBranch ?? 'main',
    token: tokenInfo.token,
    htmlUrl: repo.htmlUrl ?? null,
  });
  await agentTaskRef(ownerId, taskId).set(
    {
      metadata: {
        ...(metadata ?? {}),
        ...serializeLocalWorkspaceInfo(workspace),
      },
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
  return workspace;
}

async function createAgentSandboxWorkspace(params: {
  ownerId: string;
  taskId: string;
  task: AgentTaskDocument;
  validationAttempt: number;
}) {
  const baseWorkspace = await ensureAgentTaskLocalWorkspace(
    params.ownerId,
    params.taskId,
    params.task,
  );
  const sandboxPath = path.join(
    path.dirname(baseWorkspace.workspacePath),
    `sandbox-${params.validationAttempt}`,
  );
  const sandboxWorkspace = await cloneEphemeralWorkspace({
    sourceWorkspacePath: baseWorkspace.workspacePath,
    targetWorkspacePath: sandboxPath,
  });
  return {
    baseWorkspace,
    sandboxWorkspace,
  };
}

async function buildWorkspaceRepoFileRecords(workspacePath: string): Promise<WorkingCopyRepoFileRecord[]> {
  const snapshot = await snapshotEphemeralWorkspace({ workspacePath });
  return snapshot.map(file => ({
    path: file.path,
    content: file.content,
    baseContent: '',
    isDeleted: file.isDeleted === true,
    sha: undefined,
  }));
}

async function applyRepoExecutionEditsToLocalWorkspace(
  workspacePath: string,
  edits: RepoExecutionPreparedEdit[],
) {
  return applyEphemeralWorkspaceEdits({
    workspacePath,
    edits: edits.map(edit => ({
      path: edit.path,
      action: edit.action,
      afterContent: edit.afterContent,
    })),
  });
}

async function loadRepoExecutionSessionEdits(repoId: string, sessionId: string) {
  const sessionSnap = await db
    .collection('repositories')
    .doc(repoId)
    .collection('executionSessions')
    .doc(sessionId)
    .get();
  if (!sessionSnap.exists) {
    throw new HttpsError('not-found', 'Repo execution session not found.');
  }
  const data = sessionSnap.data() as
    | {
        edits?: Array<{
          path?: string;
          action?: RepoExecutionAction;
          beforeContent?: string;
          afterContent?: string;
          summary?: string;
          diffPreview?: string;
          diffLines?: ReturnType<typeof buildDiffLines>;
        }>;
      }
    | undefined;
  const editsRaw = Array.isArray(data?.edits) ? data?.edits : [];
  if (editsRaw.length === 0) {
    throw new HttpsError('failed-precondition', 'Repo execution session has no edits to apply.');
  }
  return editsRaw.map(edit => {
    const path = normalizeRepoExecutionPath(asString(edit.path, 'executionSession.edits.path'));
    const action = (typeof edit.action === 'string' ? edit.action : 'modify') as RepoExecutionAction;
    const beforeContent = typeof edit.beforeContent === 'string' ? edit.beforeContent : '';
    const afterContent = typeof edit.afterContent === 'string' ? edit.afterContent : '';
    return {
      path,
      action,
      beforeContent,
      afterContent,
      summary:
        typeof edit.summary === 'string' && edit.summary.trim().length > 0
          ? edit.summary
          : executionSummaryForPath(path, action),
      diffPreview:
        typeof edit.diffPreview === 'string' && edit.diffPreview.trim().length > 0
          ? edit.diffPreview
          : buildUnifiedDiff(path, beforeContent, afterContent),
      diffLines: Array.isArray(edit.diffLines)
        ? (edit.diffLines as ReturnType<typeof buildDiffLines>)
        : buildDiffLines(beforeContent, afterContent),
    } satisfies RepoExecutionPreparedEdit;
  });
}

async function validateWorkspaceAgainstSessionEdits(
  workspacePath: string,
  edits: RepoExecutionPreparedEdit[],
) {
  const snapshot = await snapshotEphemeralWorkspace({ workspacePath });
  const pathMap = new Map(snapshot.map(file => [file.path.toLowerCase(), file]));
  const mismatchedPaths: string[] = [];
  for (const edit of edits) {
    const key = normalizeRepoExecutionPath(edit.path).toLowerCase();
    const file = pathMap.get(key);
    if (edit.action === 'delete') {
      if (file) {
        mismatchedPaths.push(edit.path);
      }
      continue;
    }
    if ((file?.content ?? '') !== edit.afterContent) {
      mismatchedPaths.push(edit.path);
    }
  }
  return {
    ok: mismatchedPaths.length === 0,
    mismatchedPaths,
  };
}

async function cleanupAgentTaskLocalWorkspace(task: AgentTaskDocument) {
  const metadata = isObject(task.metadata) ? task.metadata : null;
  if (!metadata) {
    return;
  }
  const candidates = [
    typeof metadata.localWorkspacePath === 'string' ? metadata.localWorkspacePath.trim() : null,
    typeof metadata.sandboxWorkspacePath === 'string' ? metadata.sandboxWorkspacePath.trim() : null,
    typeof metadata.workspacePath === 'string' ? metadata.workspacePath.trim() : null,
  ].filter((value): value is string => Boolean(value));
  const roots = new Set<string>();
  for (const candidate of candidates) {
    roots.add(path.dirname(candidate));
  }
  await Promise.all(
    [...roots].map(root => cleanupEphemeralWorkspace(root).catch(() => undefined)),
  );
}

async function prepareWorkspaceBranchForRemoteGitOps(params: {
  workspacePath: string;
  provider: GitProviderName;
  token: string;
  branchName: string;
  commitMessage: string;
  forcePush?: boolean;
}) {
  await checkoutEphemeralWorkspaceBranch({
    workspacePath: params.workspacePath,
    branchName: params.branchName,
  });
  const commitResult = await commitEphemeralWorkspaceChanges({
    workspacePath: params.workspacePath,
    commitMessage: params.commitMessage,
  });
  if (!commitResult.committed) {
    return {
      committed: false,
      summary: commitResult.summary,
    };
  }
  await pushEphemeralWorkspaceBranch({
    workspacePath: params.workspacePath,
    provider: params.provider,
    token: params.token,
    branchName: params.branchName,
    force: params.forcePush,
  });
  return {
    committed: true,
    summary: 'Committed and pushed local workspace changes.',
  };
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
  await cleanupAgentTaskLocalWorkspace(task);
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

// Returns true if the approval gate was bypassed (auto-approved), false if the task was
// paused for human review.
async function putAgentTaskIntoApprovalState(params: {
  ownerId: string;
  taskId: string;
  approval: AgentTaskPendingApproval;
  step: string;
  message: string;
  // When true the caller signals that pre-approval validation passed cleanly.
  validationPassed?: boolean;
}): Promise<boolean> {
  const taskReference = agentTaskRef(params.ownerId, params.taskId);
  const taskSnapshot = await taskReference.get();
  if (!taskSnapshot.exists) {
    return false;
  }
  const task = safeAgentTask(taskSnapshot.data());

  // ── Auto-approve logic ──────────────────────────────────────────────────
  // FULLY_AUTONOMOUS: bypass every gate (except risky operations when no
  //   explicit trust override was requested for risky ops — still bypass here
  //   because the caller already decided to call this function).
  // AUTO_APPROVE_ON_SUCCESS: bypass only when validation passed cleanly.
  const isFullyAutonomous = task.trustLevel === 'FULLY_AUTONOMOUS';
  const isAutoApproveOnSuccess =
    task.trustLevel === 'AUTO_APPROVE_ON_SUCCESS' && params.validationPassed === true;

  if (isFullyAutonomous || isAutoApproveOnSuccess) {
    // Record the auto-approval event so the audit trail is complete.
    await appendAgentTaskEvent({
      ownerId: params.ownerId,
      taskId: params.taskId,
      type: 'awaiting_approval',
      step: params.step,
      message: `[AUTO-APPROVED] ${params.message}`,
      status: 'running',
      phase: 'apply_edits',
      data: {
        approvalType: params.approval.type,
        approvalId: params.approval.id,
        autoApproved: true,
        trustLevel: task.trustLevel,
      },
    });
    // Immediately record the approval as approved in Firestore so the normal
    // continuation path can use it.
    const now = Date.now();
    const approvedApproval: AgentTaskPendingApproval = {
      ...params.approval,
      status: 'approved',
      resolvedAtMs: now,
    };
    await taskReference.set({ pendingApproval: approvedApproval, updatedAtMs: now }, { merge: true });
    await agentTaskApprovalsCollection(params.ownerId, params.taskId)
      .doc(params.approval.id)
      .set({ ...approvedApproval, updatedAtMs: now }, { merge: true });
    return true;
  }

  // ── Standard supervised path ─────────────────────────────────────────────
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
  return false;
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
  inspectedFiles: string[];
  globalContextFiles: string[];
  steps: string[];
  edits: RepoExecutionPreparedEdit[];
  repoOverview?: string;
  architectureOverview?: string;
  moduleOverview?: string;
  repoSizeClass?: string;
  contextStrategy?: string;
  executionMemory?: ReturnType<typeof serializeRepoExecutionRunMemory>;
  executionMemorySummary?: string;
  repoCoverageNotice?: string | null;
  focusedModules?: string[];
  moduleCount?: number;
  architectureZoneCount?: number;
  explorationPassCount?: number;
  hydratedPathCount?: number;
  wholeRepoEligible?: boolean;
  planningSummary?: string;
  executionProvider?: AiProviderName;
  executionModel?: string;
  executionProviderReason?: string;
  contextPlannerProvider?: AiProviderName | null;
  contextPlannerModel?: string | null;
  executionPlannerProvider?: AiProviderName | null;
  executionPlannerModel?: string | null;
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
  for (let index = 0; index < entries.length; index += FIRESTORE_BATCH_WRITE_LIMIT) {
    const batch = db.batch();
    for (const entry of entries.slice(index, index + FIRESTORE_BATCH_WRITE_LIMIT)) {
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
}

async function persistRepoKnowledgeSnapshot(
  repoId: string,
  map: RepoKnowledgeMap,
) {
  await persistRepoMapSnapshot({
    db,
    repoId,
    map,
  });
}

function buildRepoCoverageNotice(repo: {
  treeTruncated?: boolean | null;
  totalTreeEntries?: number | null;
}, syncedFileCount: number) {
  if (repo.treeTruncated !== true) {
    return null;
  }
  const totalEntries = typeof repo.totalTreeEntries === 'number' && repo.totalTreeEntries > 0
    ? repo.totalTreeEntries
    : null;
  if (totalEntries && totalEntries > syncedFileCount) {
    return `Repository sync currently covers ${syncedFileCount} of about ${totalEntries} tree entries, so whole-repo reasoning is strongest within the synced surface and may need a broader sync for untouched areas.`;
  }
  return `Repository sync hit the current ingestion ceiling at ${syncedFileCount} files, so whole-repo reasoning is based on the synced surface rather than the entire remote tree.`;
}

function dedupeRepoPaths(values: Array<string | null | undefined>, limit: number) {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of values) {
    if (typeof raw !== 'string') {
      continue;
    }
    const value = normalizePromptRepoPath(raw);
    if (!value) {
      continue;
    }
    const key = value.toLowerCase();
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    out.push(value);
    if (out.length >= limit) {
      break;
    }
  }
  return out;
}

function dedupeTextValues(values: Array<string | null | undefined>, limit: number) {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of values) {
    if (typeof raw !== 'string') {
      continue;
    }
    const value = raw.trim();
    if (!value) {
      continue;
    }
    const key = value.toLowerCase();
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    out.push(value);
    if (out.length >= limit) {
      break;
    }
  }
  return out;
}

function coerceRepoExecutionRunMemory(value: unknown): RepoExecutionRunMemory | null {
  if (!isObject(value)) {
    return null;
  }
  const passes = Array.isArray(value.passes)
    ? value.passes
        .filter((item): item is Record<string, unknown> => isObject(item))
        .map(item => ({
          passNumber: typeof item.passNumber === 'number' ? item.passNumber : 0,
          focusModules: Array.isArray(item.focusModules)
            ? item.focusModules.filter((entry): entry is string => typeof entry === 'string')
            : [],
          requestedPaths: Array.isArray(item.requestedPaths)
            ? item.requestedPaths.filter((entry): entry is string => typeof entry === 'string')
            : [],
          hydratedPaths: Array.isArray(item.hydratedPaths)
            ? item.hydratedPaths.filter((entry): entry is string => typeof entry === 'string')
            : [],
          promotedPaths: Array.isArray(item.promotedPaths)
            ? item.promotedPaths.filter((entry): entry is string => typeof entry === 'string')
            : [],
          readOnlyPaths: Array.isArray(item.readOnlyPaths)
            ? item.readOnlyPaths.filter((entry): entry is string => typeof entry === 'string')
            : [],
          conclusions: Array.isArray(item.conclusions)
            ? item.conclusions.filter((entry): entry is string => typeof entry === 'string')
            : [],
          uncertainties: Array.isArray(item.uncertainties)
            ? item.uncertainties.filter((entry): entry is string => typeof entry === 'string')
            : [],
          rationale: typeof item.rationale === 'string' ? item.rationale : '',
          done: item.done === true,
        }))
    : [];
  return {
    sizeClass: typeof value.sizeClass === 'string' ? (value.sizeClass as RepoExecutionRunMemory['sizeClass']) : 'medium',
    contextStrategy: typeof value.contextStrategy === 'string' ? value.contextStrategy : '',
    repoOverview: typeof value.repoOverview === 'string' ? value.repoOverview : '',
    architectureOverview:
      typeof value.architectureOverview === 'string' ? value.architectureOverview : '',
    moduleOverview: typeof value.moduleOverview === 'string' ? value.moduleOverview : '',
    focusedModules: Array.isArray(value.focusedModules)
      ? value.focusedModules.filter((entry): entry is string => typeof entry === 'string')
      : [],
    exploredPaths: Array.isArray(value.exploredPaths)
      ? value.exploredPaths.filter((entry): entry is string => typeof entry === 'string')
      : [],
    hydratedPaths: Array.isArray(value.hydratedPaths)
      ? value.hydratedPaths.filter((entry): entry is string => typeof entry === 'string')
      : [],
    editablePaths: Array.isArray(value.editablePaths)
      ? value.editablePaths.filter((entry): entry is string => typeof entry === 'string')
      : [],
    readOnlyPaths: Array.isArray(value.readOnlyPaths)
      ? value.readOnlyPaths.filter((entry): entry is string => typeof entry === 'string')
      : [],
    globalContextPaths: Array.isArray(value.globalContextPaths)
      ? value.globalContextPaths.filter((entry): entry is string => typeof entry === 'string')
      : [],
    architectureConclusions: Array.isArray(value.architectureConclusions)
      ? value.architectureConclusions.filter((entry): entry is string => typeof entry === 'string')
      : [],
    unresolvedQuestions: Array.isArray(value.unresolvedQuestions)
      ? value.unresolvedQuestions.filter((entry): entry is string => typeof entry === 'string')
      : [],
    moduleSummaries: Array.isArray(value.moduleSummaries)
      ? value.moduleSummaries
          .filter((item): item is Record<string, unknown> => isObject(item))
          .map(item => ({
            id: typeof item.id === 'string' ? item.id : '',
            summary: typeof item.summary === 'string' ? item.summary : '',
            keyFiles: Array.isArray(item.keyFiles)
              ? item.keyFiles.filter((entry): entry is string => typeof entry === 'string')
              : [],
            dependencies: Array.isArray(item.dependencies)
              ? item.dependencies.filter((entry): entry is string => typeof entry === 'string')
              : [],
            dependents: Array.isArray(item.dependents)
              ? item.dependents.filter((entry): entry is string => typeof entry === 'string')
              : [],
          }))
      : [],
    passes,
  };
}

function seedRepoExecutionRunMemory(
  base: RepoExecutionRunMemory,
  existing?: RepoExecutionRunMemory | null,
) {
  if (!existing) {
    return base;
  }
  return {
    ...base,
    focusedModules: dedupeRepoPaths(
      [...existing.focusedModules, ...base.focusedModules],
      48,
    ),
    exploredPaths: dedupeRepoPaths(
      [...existing.exploredPaths, ...base.exploredPaths],
      960,
    ),
    hydratedPaths: dedupeRepoPaths(
      [...existing.hydratedPaths, ...base.hydratedPaths],
      960,
    ),
    editablePaths: dedupeRepoPaths(
      [...existing.editablePaths, ...base.editablePaths],
      220,
    ),
    readOnlyPaths: dedupeRepoPaths(
      [...existing.readOnlyPaths, ...base.readOnlyPaths],
      280,
    ),
    globalContextPaths: dedupeRepoPaths(
      [...existing.globalContextPaths, ...base.globalContextPaths],
      160,
    ),
    architectureConclusions: dedupeTextValues(
      [...existing.architectureConclusions, ...base.architectureConclusions],
      32,
    ),
    unresolvedQuestions: dedupeTextValues(
      [...existing.unresolvedQuestions, ...base.unresolvedQuestions],
      32,
    ),
    passes: [...existing.passes.slice(-8), ...base.passes].slice(-12),
  };
}

function selectRepoEntriesByPaths(entries: RepoIndexEntry[], paths: string[]) {
  const pathMap = new Map(entries.map(entry => [entry.path.toLowerCase(), entry]));
  const selected: RepoIndexEntry[] = [];
  for (const path of paths) {
    const match = pathMap.get(path.toLowerCase());
    if (match) {
      selected.push(match);
    }
  }
  return selected;
}

function findRepoEntriesByHints(
  entries: RepoIndexEntry[],
  hints: string[],
  limit: number,
) {
  const normalizedHints = hints
    .map(value => value.trim().toLowerCase())
    .filter(value => value.length >= 2);
  if (normalizedHints.length === 0) {
    return [] as string[];
  }
  const matches = entries
    .map(entry => {
      const haystack = [
        entry.path,
        entry.summary,
        entry.embeddingText,
        entry.keywords.join(' '),
        entry.imports.join(' '),
        entry.symbolHints.join(' '),
      ]
        .join(' ')
        .toLowerCase();
      let score = 0;
      for (const hint of normalizedHints) {
        if (entry.path.toLowerCase().includes(hint)) {
          score += 12;
          continue;
        }
        if (haystack.includes(hint)) {
          score += 6;
        }
      }
      return { path: entry.path, score };
    })
    .filter(item => item.score > 0)
    .sort((a, b) => b.score - a.score || a.path.localeCompare(b.path));
  return dedupeRepoPaths(matches.map(item => item.path), limit);
}

async function loadRepoExecutionPaths(params: {
  ownerId: string;
  repoId: string;
  repo: {
    apiBaseUrl?: string | null;
  };
  fileMap: Map<string, RepoIndexFileInput>;
  paths: string[];
  observer?: RepoExecutionObserver;
}) {
  for (const rawPath of params.paths) {
    const path = normalizePromptRepoPath(rawPath);
    if (!path) {
      continue;
    }
    const existing = params.fileMap.get(path);
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
      params.fileMap.set(path, {
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
}

async function callRepoContextPlannerModel(params: {
  provider: AiProviderName;
  model: string;
  mode: RepoExecutionMode;
  prompt: string;
}) {
  return callProviderTextCompletion({
    provider: params.provider,
    modelOverride: params.model,
    systemPrompt: buildRepoContextPlannerSystemPrompt(),
    userPrompt: params.prompt,
    temperature: 0.1,
    maxOutputTokens: Math.min(repoExecutionMaxOutputTokens(params.model, params.mode), 4_096),
    jsonMode: true,
  });
}

async function callRepoExecutionPlanningModel(params: {
  provider: AiProviderName;
  model: string;
  mode: RepoExecutionMode;
  prompt: string;
}) {
  return callProviderTextCompletion({
    provider: params.provider,
    modelOverride: params.model,
    systemPrompt: buildRepoExecutionPlanningSystemPrompt(),
    userPrompt: params.prompt,
    temperature: 0.1,
    maxOutputTokens: Math.min(repoExecutionMaxOutputTokens(params.model, params.mode), 4_096),
    jsonMode: true,
  });
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
    treeTruncated?: boolean | null;
    totalTreeEntries?: number | null;
  };
  prompt: string;
  currentFilePath?: string | null;
  deepMode: boolean;
  repairHintPaths?: string[];
  targetedEditablePaths?: string[];
  repoFilesOverride?: WorkingCopyRepoFileRecord[];
  observer?: RepoExecutionObserver;
  existingRunMemory?: RepoExecutionRunMemory | null;
  budgetRemainingRatio?: number | null;
}) {
  const files =
    params.repoFilesOverride != null
      ? params.repoFilesOverride
          .filter(file => file.isDeleted !== true)
          .map<RepoIndexFileInput>(file => ({
            path: file.path,
            type: 'blob',
            language: guessLanguageFromPath(file.path),
            content: file.content ?? '',
            contentPreview: file.content ?? '',
            sha: file.sha ?? null,
          }))
      : (
          await db
            .collection('repositories')
            .doc(params.repoId)
            .collection('files')
            .get()
        ).docs
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
              path:
                typeof data.path === 'string' && data.path.trim().length > 0
                  ? data.path
                  : document.id,
              type: data.type ?? 'blob',
              language:
                data.language ??
                guessLanguageFromPath(
                  typeof data.path === 'string' ? data.path : document.id,
                ),
              content: data.content ?? '',
              contentPreview: data.contentPreview ?? data.content ?? '',
              sha: data.sha ?? null,
            };
          })
          .filter((file): file is RepoIndexFileInput => file != null);
  await params.observer?.onRepoScanned?.({ fileCount: files.length });

  const fileMap = new Map<string, RepoIndexFileInput>(
    files.map(file => [file.path, { ...file }]),
  );
  let entries = [] as RepoIndexEntry[];
  let ranked = [] as RankedRepoIndexEntry[];
  let manifest = buildRepoContextManifest({
    entries: [],
    deepMode: params.deepMode,
  });
  let knowledgeMap = buildRepoKnowledgeMap({
    entries: [],
    deepMode: params.deepMode,
  });
  let repoOverview = '';
  let globalContextPaths = [] as string[];
  let repoCoverageNotice =
    params.repoFilesOverride != null
      ? 'Using the task-local workspace snapshot as the source of truth for this execution pass.'
      : buildRepoCoverageNotice(params.repo, files.length);
  let contextPlannerProvider: AiProviderName | null = null;
  let contextPlannerModel: string | null = null;
  let executionPlannerProvider: AiProviderName | null = null;
  let executionPlannerModel: string | null = null;

  const rebuildKnowledgeState = () => {
    entries = buildRepoIndexEntries([...fileMap.values()]);
    ranked = rankRepoIndexEntries({
      prompt: params.prompt,
      currentFilePath: params.currentFilePath,
      entries,
      deepMode: params.deepMode,
    });
    manifest = buildRepoContextManifest({
      entries,
      deepMode: params.deepMode,
    });
    knowledgeMap = buildRepoKnowledgeMap({
      entries,
      deepMode: params.deepMode,
    });
    repoCoverageNotice = buildRepoCoverageNotice(params.repo, entries.length);
    repoOverview = repoCoverageNotice
      ? `${formatRepoKnowledgeMap(knowledgeMap)}\n\nSYNC COVERAGE:\n${repoCoverageNotice}`
      : formatRepoKnowledgeMap(knowledgeMap);
    globalContextPaths = dedupeRepoPaths(
      [
        ...pickGlobalContextPaths(
          entries,
          Math.min(knowledgeMap.budget.exactReadOnlyBudget, params.deepMode ? 32 : 18),
        ),
        ...knowledgeMap.entryPoints,
        ...knowledgeMap.keyFiles,
      ],
      Math.min(knowledgeMap.budget.exactReadOnlyBudget, params.deepMode ? 48 : 24),
    );
  };

  const buildFocusedModulePromptContext = (moduleIds: string[]) =>
    formatFocusedModuleDetails({
      map: knowledgeMap,
      moduleIds,
      limit: params.deepMode ? 24 : 14,
    });

  rebuildKnowledgeState();

  const initialKnowledgeSeed = buildInitialKnowledgeSeedPaths({
    map: knowledgeMap,
    entries,
    prompt: params.prompt,
    currentFilePath: params.currentFilePath,
  });
  const normalizedRepairHintPaths = dedupeRepoPaths(
    (params.repairHintPaths ?? []).map(path => normalizeRepoExecutionPath(path)),
    Math.max(knowledgeMap.budget.explorationBudgetPerPass, 24),
  );
  const normalizedTargetedEditablePaths = dedupeRepoPaths(
    (params.targetedEditablePaths ?? []).map(path => normalizeRepoExecutionPath(path)),
    Math.max(knowledgeMap.budget.exactEditableBudget, 18),
  );
  const repairHintModules = dedupeRepoPaths(
    [...normalizedRepairHintPaths, ...normalizedTargetedEditablePaths].map(
      path => knowledgeMap.pathToModule[path] ?? null,
    ),
    Math.max(knowledgeMap.budget.initialModuleSeedLimit, 12),
  );
  let focusedModules = dedupeRepoPaths(
    [...initialKnowledgeSeed.focusedModules, ...repairHintModules],
    Math.max(knowledgeMap.budget.initialModuleSeedLimit * 2, 24),
  );
  let explorationPaths = dedupeRepoPaths(
    [
      params.currentFilePath ?? null,
      ...normalizedRepairHintPaths,
      ...normalizedTargetedEditablePaths,
      ...globalContextPaths,
      ...initialKnowledgeSeed.seedPaths,
      ...ranked
        .slice(0, Math.min(knowledgeMap.budget.plannerCandidateLimit, params.deepMode ? 18 : 10))
        .map(entry => entry.path),
    ],
    Math.max(knowledgeMap.budget.explorationBudgetPerPass, 24),
  );

  await loadRepoExecutionPaths({
    ownerId: params.ownerId,
    repoId: params.repoId,
    repo: params.repo,
    fileMap,
    paths: explorationPaths,
    observer: params.observer,
  });
  rebuildKnowledgeState();

  focusedModules = dedupeRepoPaths(
    [
      ...focusedModules,
      ...collectRelatedModules({
        map: knowledgeMap,
        moduleIds: focusedModules,
        limit: Math.max(knowledgeMap.budget.initialModuleSeedLimit, 12),
      }),
      ...findPromptFocusedModules({
        map: knowledgeMap,
        prompt: params.prompt,
        currentFilePath: params.currentFilePath,
        limit: knowledgeMap.budget.initialModuleSeedLimit,
      }),
    ],
    Math.max(knowledgeMap.budget.initialModuleSeedLimit * 2, 24),
  );

  let runMemory = seedRepoExecutionRunMemory(
    createRepoExecutionRunMemory({
      map: knowledgeMap,
      globalContextPaths,
      focusedModules,
      exploredPaths: explorationPaths,
      hydratedPaths: explorationPaths.filter(
        path => (fileMap.get(path)?.content ?? '').trim().length > 0,
      ),
      editablePaths: ranked
        .slice(0, Math.min(knowledgeMap.budget.exactEditableBudget, params.deepMode ? 12 : 6))
        .map(entry => entry.path)
        .concat(normalizedTargetedEditablePaths),
      readOnlyPaths: globalContextPaths,
    }),
    params.existingRunMemory,
  );

  if (knowledgeMap.budget.exactWholeRepoEligible) {
    const allPaths = entries.map(entry => entry.path);
    await loadRepoExecutionPaths({
      ownerId: params.ownerId,
      repoId: params.repoId,
      repo: params.repo,
      fileMap,
      paths: allPaths,
      observer: params.observer,
    });
    rebuildKnowledgeState();
    explorationPaths = dedupeRepoPaths(allPaths, knowledgeMap.totalFiles);
    runMemory = recordRepoExecutionMemoryPass({
      memory: runMemory,
      pass: {
        passNumber: 1,
        focusModules: focusedModules,
        requestedPaths: allPaths,
        hydratedPaths: allPaths.filter(
          path => (fileMap.get(path)?.content ?? '').trim().length > 0,
        ),
        promotedPaths: allPaths,
        readOnlyPaths: [],
        conclusions: [
          `Repository is small enough for the ${knowledgeMap.budget.strategyLabel} strategy.`,
        ],
        uncertainties: [],
        rationale: 'Hydrated the repo broadly because inline whole-repo reasoning is practical.',
        done: true,
      },
      focusedModules,
      exploredPaths: allPaths,
      hydratedPaths: allPaths.filter(
        path => (fileMap.get(path)?.content ?? '').trim().length > 0,
      ),
      editablePaths: allPaths,
      readOnlyPaths: [],
      conclusions: [
        `Whole-repo inline reasoning is available for this ${knowledgeMap.sizeClass} repository.`,
      ],
    });
    await params.observer?.onExplorationPass?.({
      passNumber: 1,
      totalPasses: 1,
      wholeRepoInline: true,
      repoSizeClass: knowledgeMap.sizeClass,
      contextStrategy: knowledgeMap.budget.strategyLabel,
      focusModules: focusedModules,
      requestedPaths: allPaths,
      hydratedPaths: allPaths.filter(
        path => (fileMap.get(path)?.content ?? '').trim().length > 0,
      ),
      promotedPaths: allPaths,
      readOnlyPaths: [],
      architectureFindings: runMemory.architectureConclusions,
      uncertainties: runMemory.unresolvedQuestions,
      rationale: 'Hydrated the full repo because inline whole-repo reasoning is practical.',
      done: true,
      executionMemorySummary: formatRepoExecutionRunMemory(runMemory),
      repoCoverageNotice: repoCoverageNotice ?? undefined,
      moduleCount: knowledgeMap.modules.length,
      architectureZoneCount: knowledgeMap.architectureZones.length,
    });
  } else {
    let passNumber = 0;
    while (passNumber < knowledgeMap.budget.explorationPasses) {
      passNumber += 1;
      let contextExpansionPlan = {
        additionalPaths: [] as string[],
        directoryPrefixes: [] as string[],
        promotePaths: [] as string[],
        readOnlyPaths: [] as string[],
        focus: [] as string[],
        focusModules: [] as string[],
        architectureFindings: [] as string[],
        uncertainties: [] as string[],
        done: false,
        rationale: '',
      };
      try {
        const plannerRouting = resolveRepoExecutionProviderRouting({
          stage: 'context_planner',
          deepMode: params.deepMode,
          repoSizeClass: knowledgeMap.sizeClass,
          retryCount: Math.max(passNumber - 1, 0),
          costProfile: chooseAgentCostProfile({
            stage: 'context',
            deepMode: params.deepMode,
            retryCount: Math.max(passNumber - 1, 0),
            budgetRemainingRatio: params.budgetRemainingRatio,
            repoSizeClass: knowledgeMap.sizeClass,
          }),
        });
        contextPlannerProvider = plannerRouting.provider;
        contextPlannerModel = plannerRouting.model;
        const plannerResponse = await callRepoContextPlannerModel({
          provider: plannerRouting.provider,
          model: plannerRouting.model,
          mode: params.deepMode ? 'deep' : 'normal',
          prompt: buildRepoContextPlannerUserPrompt({
            prompt: params.prompt,
            repoOverview,
            repoStructure: manifest.tree,
            architectureOverview: knowledgeMap.architectureOverview,
            architectureZoneOverview: knowledgeMap.architectureZoneOverview,
            moduleOverview: knowledgeMap.moduleOverview,
            moduleIndex: knowledgeMap.moduleIndex,
            focusedModuleDetails: buildFocusedModulePromptContext(runMemory.focusedModules),
            currentFilePath: params.currentFilePath ?? null,
            selectedPaths: runMemory.editablePaths,
            inspectedPaths: runMemory.exploredPaths,
            candidateEntries: ranked.slice(0, knowledgeMap.budget.plannerCandidateLimit),
            runMemory,
            deepMode: params.deepMode,
          }),
        });
        contextExpansionPlan = parseRepoContextExpansionPlan(plannerResponse.text);
      } catch (error) {
        functions.logger.warn('repo_execution.context_planner_failed', {
          repoId: params.repoId,
          errorMessage: normalizeError(error).message,
          passNumber,
        });
      }

      const requestedFocusModules = dedupeRepoPaths(
        [
          ...focusedModules,
          ...contextExpansionPlan.focusModules,
          ...collectRelatedModules({
            map: knowledgeMap,
            moduleIds: [...focusedModules, ...contextExpansionPlan.focusModules],
            limit: Math.max(Math.ceil(knowledgeMap.budget.initialModuleSeedLimit * 1.5), 12),
          }),
        ],
        Math.max(knowledgeMap.budget.initialModuleSeedLimit * 2, 24),
      );
      const hintedPaths = findRepoEntriesByHints(
        entries,
        [...contextExpansionPlan.focus, ...contextExpansionPlan.additionalPaths],
        Math.ceil(knowledgeMap.budget.explorationBudgetPerPass / 2),
      );
      const directoryExpansionPaths = dedupeRepoPaths(
        entries
          .filter(entry =>
            contextExpansionPlan.directoryPrefixes.some(
              prefix => entry.path === prefix || entry.path.startsWith(`${prefix}/`),
            ),
          )
          .map(entry => entry.path),
        knowledgeMap.budget.explorationBudgetPerPass,
      );
      const moduleExpansionPaths = collectModulePaths({
        map: knowledgeMap,
        entries,
        moduleIds: requestedFocusModules,
        limit: knowledgeMap.budget.explorationBudgetPerPass,
      });
      const graphExpansionPaths = collectRelatedPaths({
        map: knowledgeMap,
        entries,
        seedPaths: [
          ...runMemory.editablePaths,
          ...contextExpansionPlan.promotePaths,
          ...contextExpansionPlan.readOnlyPaths,
          ...hintedPaths,
          ...moduleExpansionPaths,
        ],
        currentFilePath: params.currentFilePath,
        limit: knowledgeMap.budget.explorationBudgetPerPass,
      });
      const neighborhoodPaths = expandRepoContextPaths({
        entries,
        seedPaths: [
          ...runMemory.editablePaths,
          ...contextExpansionPlan.promotePaths,
          ...moduleExpansionPaths,
          ...hintedPaths,
        ],
        currentFilePath: params.currentFilePath,
        maxAdditional: Math.ceil(knowledgeMap.budget.explorationBudgetPerPass / 2),
      });
      const requestedPaths = dedupeRepoPaths(
        [
          ...contextExpansionPlan.additionalPaths,
          ...contextExpansionPlan.readOnlyPaths,
          ...hintedPaths,
          ...directoryExpansionPaths,
          ...moduleExpansionPaths,
          ...graphExpansionPaths,
          ...neighborhoodPaths,
        ],
        knowledgeMap.budget.explorationBudgetPerPass,
      );
      const loadPaths = requestedPaths.filter(
        path => (fileMap.get(path)?.content ?? '').trim().length === 0,
      );
      if (loadPaths.length > 0) {
        await loadRepoExecutionPaths({
          ownerId: params.ownerId,
          repoId: params.repoId,
          repo: params.repo,
          fileMap,
          paths: loadPaths,
          observer: params.observer,
        });
        rebuildKnowledgeState();
      }
      runMemory = recordRepoExecutionMemoryPass({
        memory: runMemory,
        pass: {
          passNumber,
          focusModules: requestedFocusModules,
          requestedPaths,
          hydratedPaths: requestedPaths.filter(
            path => (fileMap.get(path)?.content ?? '').trim().length > 0,
          ),
          promotedPaths: contextExpansionPlan.promotePaths,
          readOnlyPaths: contextExpansionPlan.readOnlyPaths,
          conclusions: contextExpansionPlan.architectureFindings,
          uncertainties: contextExpansionPlan.uncertainties,
          rationale: contextExpansionPlan.rationale || `Expanded repo context in pass ${passNumber}.`,
          done: contextExpansionPlan.done,
        },
        focusedModules: requestedFocusModules,
        exploredPaths: requestedPaths,
        hydratedPaths: requestedPaths.filter(
          path => (fileMap.get(path)?.content ?? '').trim().length > 0,
        ),
        editablePaths: contextExpansionPlan.promotePaths,
        readOnlyPaths: contextExpansionPlan.readOnlyPaths,
        conclusions: contextExpansionPlan.architectureFindings,
        unresolvedQuestions: contextExpansionPlan.uncertainties,
      });
      await params.observer?.onExplorationPass?.({
        passNumber,
        totalPasses: knowledgeMap.budget.explorationPasses,
        wholeRepoInline: false,
        repoSizeClass: knowledgeMap.sizeClass,
        contextStrategy: knowledgeMap.budget.strategyLabel,
        focusModules: requestedFocusModules,
        requestedPaths,
        hydratedPaths: requestedPaths.filter(
          path => (fileMap.get(path)?.content ?? '').trim().length > 0,
        ),
        promotedPaths: contextExpansionPlan.promotePaths,
        readOnlyPaths: contextExpansionPlan.readOnlyPaths,
        architectureFindings: contextExpansionPlan.architectureFindings,
        uncertainties: contextExpansionPlan.uncertainties,
        rationale: contextExpansionPlan.rationale || `Expanded repo context in pass ${passNumber}.`,
        done: contextExpansionPlan.done,
        executionMemorySummary: formatRepoExecutionRunMemory(runMemory),
        repoCoverageNotice: repoCoverageNotice ?? undefined,
        moduleCount: knowledgeMap.modules.length,
        architectureZoneCount: knowledgeMap.architectureZones.length,
      });
      focusedModules = runMemory.focusedModules;
      explorationPaths = dedupeRepoPaths(
        [...explorationPaths, ...requestedPaths],
        Math.max(knowledgeMap.budget.exactReadOnlyBudget + knowledgeMap.budget.exactEditableBudget, 220),
      );
      if (contextExpansionPlan.done) {
        break;
      }
    }
  }

  const executionCandidatePaths = knowledgeMap.budget.exactWholeRepoEligible
    ? entries.map(entry => entry.path)
    : dedupeRepoPaths(
        [
          ...runMemory.editablePaths,
          ...normalizedTargetedEditablePaths,
      ...runMemory.readOnlyPaths,
      ...runMemory.exploredPaths,
      ...normalizedRepairHintPaths,
      ...collectRelatedPaths({
        map: knowledgeMap,
        entries,
            seedPaths: runMemory.exploredPaths,
            currentFilePath: params.currentFilePath,
            limit: knowledgeMap.budget.plannerCandidateLimit,
          }),
          ...ranked.slice(0, knowledgeMap.budget.plannerCandidateLimit).map(entry => entry.path),
        ],
        knowledgeMap.budget.plannerCandidateLimit + knowledgeMap.budget.exactEditableBudget,
      );
  const executionCandidateEntries = ranked.filter(entry =>
    executionCandidatePaths.includes(entry.path),
  );
  let executionPlan = {
    summary: '',
    primaryPaths: [] as string[],
    readOnlyPaths: [] as string[],
    additionalPathHints: [] as string[],
    focusModules: [] as string[],
    architectureNotes: [] as string[],
    unresolvedQuestions: [] as string[],
    needsBroadContext: knowledgeMap.budget.exactWholeRepoEligible,
  };
  if (!knowledgeMap.budget.exactWholeRepoEligible && executionCandidateEntries.length > 0) {
    try {
      const executionPlannerRouting = resolveRepoExecutionProviderRouting({
        stage: 'execution_planner',
        deepMode: params.deepMode,
        repoSizeClass: knowledgeMap.sizeClass,
        costProfile: chooseAgentCostProfile({
          stage: 'planning',
          deepMode: params.deepMode,
          budgetRemainingRatio: params.budgetRemainingRatio,
          repoSizeClass: knowledgeMap.sizeClass,
        }),
      });
      executionPlannerProvider = executionPlannerRouting.provider;
      executionPlannerModel = executionPlannerRouting.model;
      const planningResponse = await callRepoExecutionPlanningModel({
        provider: executionPlannerRouting.provider,
        model: executionPlannerRouting.model,
        mode: params.deepMode ? 'deep' : 'normal',
        prompt: buildRepoExecutionPlanningUserPrompt({
          repoOverview,
          architectureOverview: knowledgeMap.architectureOverview,
          architectureZoneOverview: knowledgeMap.architectureZoneOverview,
          moduleOverview: knowledgeMap.moduleOverview,
          moduleIndex: knowledgeMap.moduleIndex,
          focusedModuleDetails: buildFocusedModulePromptContext(runMemory.focusedModules),
          runMemorySummary: formatRepoExecutionRunMemory(runMemory),
          repoSizeClass: knowledgeMap.sizeClass,
          contextStrategy: knowledgeMap.budget.strategyLabel,
          repoStructure: manifest.tree,
          candidateFiles: executionCandidateEntries.map(entry => ({
            path: entry.path,
            summary: entry.summary,
            reasons: entry.reasons,
          })),
          currentFilePath: params.currentFilePath ?? null,
          userPrompt: params.prompt,
          deepMode: params.deepMode,
        }),
      });
      executionPlan = parseRepoExecutionPlanResponse(planningResponse.text);
    } catch (error) {
      functions.logger.warn('repo_execution.edit_planner_failed', {
        repoId: params.repoId,
        errorMessage: normalizeError(error).message,
      });
    }
  }

  const planningFocusedModules = dedupeRepoPaths(
    [
      ...focusedModules,
      ...executionPlan.focusModules,
      ...collectRelatedModules({
        map: knowledgeMap,
        moduleIds: [...focusedModules, ...executionPlan.focusModules],
        limit: Math.max(Math.ceil(knowledgeMap.budget.initialModuleSeedLimit * 1.5), 12),
      }),
    ],
    Math.max(knowledgeMap.budget.initialModuleSeedLimit * 2, 24),
  );
  const planningModulePaths = collectModulePaths({
    map: knowledgeMap,
    entries,
    moduleIds: planningFocusedModules,
    limit: knowledgeMap.budget.exactEditableBudget,
  });
  const planningHintPaths = findRepoEntriesByHints(
    entries,
    executionPlan.additionalPathHints,
    Math.ceil(knowledgeMap.budget.exactReadOnlyBudget / 2),
  );
  const ripplePaths = collectRelatedPaths({
    map: knowledgeMap,
    entries,
    seedPaths: [
      ...executionPlan.primaryPaths,
      ...normalizedTargetedEditablePaths,
      ...planningModulePaths,
      ...planningHintPaths,
      ...runMemory.editablePaths,
    ],
    currentFilePath: params.currentFilePath,
    limit: knowledgeMap.budget.exactReadOnlyBudget,
  });
  const planningHydrationPaths = dedupeRepoPaths(
    [
      ...executionPlan.primaryPaths,
      ...executionPlan.readOnlyPaths,
      ...planningModulePaths,
      ...planningHintPaths,
      ...ripplePaths,
    ],
    knowledgeMap.budget.exactEditableBudget + knowledgeMap.budget.exactReadOnlyBudget,
  );
  const planningLoadPaths = planningHydrationPaths.filter(
    path => (fileMap.get(path)?.content ?? '').trim().length === 0,
  );
  if (planningLoadPaths.length > 0) {
    await loadRepoExecutionPaths({
      ownerId: params.ownerId,
      repoId: params.repoId,
      repo: params.repo,
      fileMap,
      paths: planningLoadPaths,
      observer: params.observer,
    });
    rebuildKnowledgeState();
  }
  runMemory = recordRepoExecutionMemoryPass({
    memory: runMemory,
    pass: {
      passNumber: runMemory.passes.length + 1,
      focusModules: planningFocusedModules,
      requestedPaths: planningHydrationPaths,
      hydratedPaths: planningHydrationPaths.filter(
        path => (fileMap.get(path)?.content ?? '').trim().length > 0,
      ),
      promotedPaths: executionPlan.primaryPaths,
      readOnlyPaths: executionPlan.readOnlyPaths,
      conclusions: executionPlan.architectureNotes,
      uncertainties: executionPlan.unresolvedQuestions,
      rationale: executionPlan.summary || 'Finalized the edit and dependency scope.',
      done: true,
    },
    focusedModules: planningFocusedModules,
    exploredPaths: planningHydrationPaths,
    hydratedPaths: planningHydrationPaths.filter(
      path => (fileMap.get(path)?.content ?? '').trim().length > 0,
    ),
    editablePaths: executionPlan.primaryPaths,
    readOnlyPaths: executionPlan.readOnlyPaths,
    conclusions: executionPlan.architectureNotes,
    unresolvedQuestions: executionPlan.unresolvedQuestions,
  });

  let selectedPaths = knowledgeMap.budget.exactWholeRepoEligible
    ? entries.map(entry => entry.path)
    : dedupeRepoPaths(
        [
          ...normalizedTargetedEditablePaths,
          ...executionPlan.primaryPaths,
          ...runMemory.editablePaths,
          ...normalizedRepairHintPaths,
          ...planningModulePaths,
          ...collectRelatedPaths({
            map: knowledgeMap,
            entries,
            seedPaths:
              executionPlan.primaryPaths.length > 0 || normalizedTargetedEditablePaths.length > 0
                ? [
                    ...normalizedTargetedEditablePaths,
                    ...executionPlan.primaryPaths,
                    ...normalizedRepairHintPaths,
                  ]
                : [...runMemory.editablePaths, ...normalizedRepairHintPaths],
            currentFilePath: params.currentFilePath,
            limit: knowledgeMap.budget.exactEditableBudget,
          }),
          params.currentFilePath ?? null,
        ],
        knowledgeMap.budget.exactEditableBudget,
      );
  if (selectedPaths.length === 0) {
    selectedPaths = dedupeRepoPaths(
      [
        params.currentFilePath ?? null,
        ...ranked
          .slice(0, Math.min(knowledgeMap.budget.exactEditableBudget, params.deepMode ? 24 : 12))
          .map(entry => entry.path),
      ],
      knowledgeMap.budget.exactEditableBudget,
    );
  }
  const dependencyPaths = knowledgeMap.budget.exactWholeRepoEligible
    ? []
    : dedupeRepoPaths(
        [
          ...globalContextPaths,
          ...executionPlan.readOnlyPaths,
          ...planningHintPaths,
          ...normalizedRepairHintPaths,
          ...pickDependencyCandidates(
            entries,
            selectedPaths,
            Math.max(knowledgeMap.budget.exactReadOnlyBudget - globalContextPaths.length, 0),
          ),
          ...collectRelatedPaths({
            map: knowledgeMap,
            entries,
            seedPaths: [...selectedPaths, ...runMemory.readOnlyPaths],
            currentFilePath: params.currentFilePath,
            limit: knowledgeMap.budget.exactReadOnlyBudget,
          }),
        ],
        knowledgeMap.budget.exactReadOnlyBudget,
      ).filter(path => !selectedPaths.includes(path));
  const finalContextPaths = dedupeRepoPaths(
    [...selectedPaths, ...dependencyPaths],
    knowledgeMap.budget.exactWholeRepoEligible
      ? entries.length
      : knowledgeMap.budget.exactEditableBudget + knowledgeMap.budget.exactReadOnlyBudget,
  );

  const finalLoadPaths = finalContextPaths.filter(
    path => (fileMap.get(path)?.content ?? '').trim().length === 0,
  );
  if (finalLoadPaths.length > 0) {
    await loadRepoExecutionPaths({
      ownerId: params.ownerId,
      repoId: params.repoId,
      repo: params.repo,
      fileMap,
      paths: finalLoadPaths,
      observer: params.observer,
    });
    rebuildKnowledgeState();
  }

  await persistRepoIndexEntries(params.repoId, entries);
  await persistRepoKnowledgeSnapshot(params.repoId, knowledgeMap);

  const selectedPathSet = new Set(selectedPaths);
  const selectedEntries = ranked.filter(entry => selectedPathSet.has(entry.path));
  const dependencyEntries = selectRepoEntriesByPaths(entries, dependencyPaths);
  const globalContextEntries = selectRepoEntriesByPaths(
    entries,
    globalContextPaths.filter(
      path =>
        !selectedPaths.includes(path) &&
        !dependencyPaths.includes(path),
    ),
  );
  const inspectedPaths = dedupeRepoPaths(
    [
      ...runMemory.exploredPaths,
      ...finalContextPaths,
      ...planningHydrationPaths,
      ...ranked.slice(0, knowledgeMap.budget.plannerCandidateLimit).map(entry => entry.path),
    ],
    Math.max(
      knowledgeMap.budget.exactEditableBudget + knowledgeMap.budget.exactReadOnlyBudget + 320,
      900,
    ),
  );
  runMemory = {
    ...runMemory,
    repoOverview: knowledgeMap.repoOverview,
    architectureOverview: knowledgeMap.architectureOverview,
    moduleOverview: knowledgeMap.moduleOverview,
    focusedModules: planningFocusedModules,
    exploredPaths: inspectedPaths,
    hydratedPaths: dedupeRepoPaths(
      [...runMemory.hydratedPaths, ...finalContextPaths],
      960,
    ),
    editablePaths: selectedPaths,
    readOnlyPaths: dependencyPaths,
    globalContextPaths,
    moduleSummaries: selectMemoryModuleSummaries({
      map: knowledgeMap,
      focusedModules: planningFocusedModules,
      limit: 48,
    }),
  };

  const planningSummary = [
    ...runMemory.passes
      .map(pass => pass.rationale)
      .filter(value => typeof value === 'string' && value.trim().length > 0)
      .slice(-6),
    executionPlan.summary,
  ]
    .filter(value => typeof value === 'string' && value.trim().length > 0)
    .join(' ');

  await params.observer?.onFilesSelected?.({
    selectedFiles: selectedEntries.map(entry => entry.path),
    dependencyFiles: dependencyEntries.map(entry => entry.path),
    inspectedFiles: inspectedPaths,
    globalContextFiles: globalContextEntries.map(entry => entry.path),
    wholeRepoEligible: knowledgeMap.budget.exactWholeRepoEligible,
    planningSummary,
    repoOverview,
    architectureOverview: knowledgeMap.architectureOverview,
    moduleOverview: knowledgeMap.moduleOverview,
    repoSizeClass: knowledgeMap.sizeClass,
    contextStrategy: knowledgeMap.budget.strategyLabel,
    executionMemorySummary: formatRepoExecutionRunMemory(runMemory),
    focusedModules: runMemory.focusedModules,
    repoCoverageNotice: repoCoverageNotice ?? undefined,
    moduleCount: knowledgeMap.modules.length,
    architectureZoneCount: knowledgeMap.architectureZones.length,
    explorationPassCount: runMemory.passes.length,
    hydratedPathCount: runMemory.hydratedPaths.length,
    contextPlannerProvider: contextPlannerProvider ?? undefined,
    contextPlannerModel: contextPlannerModel ?? undefined,
    executionPlannerProvider: executionPlannerProvider ?? undefined,
    executionPlannerModel: executionPlannerModel ?? undefined,
  });

  return {
    fileMap,
    entries,
    ranked,
    selectedEntries,
    dependencyEntries,
    globalContextEntries,
    repoStructure: manifest.tree || buildRepoStructure(entries.map(entry => entry.path)),
    repoOverview,
    architectureOverview: knowledgeMap.architectureOverview,
    architectureZoneOverview: knowledgeMap.architectureZoneOverview,
    moduleOverview: knowledgeMap.moduleOverview,
    moduleIndex: knowledgeMap.moduleIndex,
    focusedModuleDetails: buildFocusedModulePromptContext(planningFocusedModules),
    inspectedPaths,
    repoSizeClass: knowledgeMap.sizeClass,
    contextStrategy: knowledgeMap.budget.strategyLabel,
    executionMemory: runMemory,
    executionMemorySummary: formatRepoExecutionRunMemory(runMemory),
    wholeRepoEligible: knowledgeMap.budget.exactWholeRepoEligible,
    planningSummary,
    repoCoverageNotice,
    focusedModules: planningFocusedModules,
    moduleCount: knowledgeMap.modules.length,
    architectureZoneCount: knowledgeMap.architectureZones.length,
    explorationPassCount: runMemory.passes.length,
    hydratedPathCount: runMemory.hydratedPaths.length,
    contextPlannerProvider,
    contextPlannerModel,
    executionPlannerProvider,
    executionPlannerModel,
  };
}

async function callRepoExecutionModel(params: {
  provider: AiProviderName;
  model: string;
  mode: RepoExecutionMode;
  contextPrompt: string;
  repairPrompt?: string;
}) {
  return callProviderTextCompletion({
    provider: params.provider,
    modelOverride: params.model,
    systemPrompt: buildRepoExecutionSystemPrompt(),
    userPrompt: params.repairPrompt ?? params.contextPrompt,
    temperature: 0.1,
    maxOutputTokens: repoExecutionMaxOutputTokens(params.model, params.mode),
  });
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
  requestedProvider?: AiProviderName | null;
  repairMode?: boolean;
  repairHintPaths?: string[];
  targetedEditablePaths?: string[];
  repoFilesOverride?: WorkingCopyRepoFileRecord[];
  observer?: RepoExecutionObserver;
  existingRunMemory?: RepoExecutionRunMemory | null;
  retryCount?: number;
  budgetRemainingRatio?: number | null;
}): Promise<RepoExecutionSessionResult> {
  const repo = await ensureRepositoryAccess(params.repoId, params.ownerId);
  const mode: RepoExecutionMode = params.deepMode ? 'deep' : 'normal';
  const effectiveRetryCount = Math.max(params.retryCount ?? 0, 0);
  const preparedContext = await hydrateRepoExecutionContext({
    ownerId: params.ownerId,
    repoId: params.repoId,
    repo,
    prompt: params.prompt,
    currentFilePath: params.currentFilePath,
    deepMode: params.deepMode,
    repairHintPaths: params.repairHintPaths,
    targetedEditablePaths: params.targetedEditablePaths,
    repoFilesOverride: params.repoFilesOverride,
    observer: params.observer,
    existingRunMemory: params.existingRunMemory,
    budgetRemainingRatio: params.budgetRemainingRatio,
  });
  const initialCostProfile = chooseAgentCostProfile({
    stage: params.repairMode === true ? 'repair' : 'editing',
    deepMode: params.deepMode,
    retryCount: effectiveRetryCount,
    budgetRemainingRatio: params.budgetRemainingRatio,
    repoSizeClass: preparedContext.repoSizeClass,
  });
  // Adaptive routing: use historical per-repo performance data when available;
  // falls back to static ordering transparently.
  const executionRouting = await resolveRepoExecutionProviderRoutingAsync({
    requestedProvider: params.requestedProvider ?? null,
    stage: params.repairMode === true ? 'repair_diff' : 'generate_diff',
    deepMode: params.deepMode,
    repoSizeClass: preparedContext.repoSizeClass,
    retryCount: effectiveRetryCount,
    costProfile: initialCostProfile,
    repoId: params.repoId,
  });
  const maxStructuredOutputAttempts = params.deepMode ? 5 : 4;
  let finalExecutionRouting = executionRouting;

  const maxCharsPerFile = params.deepMode ? 28_000 : 16_000;
  const contextPayload = {
    repoOverview: preparedContext.repoOverview,
    architectureOverview: preparedContext.architectureOverview,
    architectureZoneOverview: preparedContext.architectureZoneOverview,
    moduleOverview: preparedContext.moduleOverview,
    moduleIndex: preparedContext.moduleIndex,
    focusedModuleDetails: preparedContext.focusedModuleDetails,
    runMemorySummary: preparedContext.executionMemorySummary,
    repoSizeClass: preparedContext.repoSizeClass,
    contextStrategy: preparedContext.contextStrategy,
    repoStructure: preparedContext.repoStructure,
    currentFilePath: params.currentFilePath ?? null,
    deepMode: params.deepMode,
    userPrompt: params.prompt,
    globalContextFiles: preparedContext.globalContextEntries.map(entry => ({
      path: entry.path,
      summary: entry.summary,
      reasons: ['repo_global_context'],
      content: trimRepoExecutionContent(
        preparedContext.fileMap.get(entry.path)?.content ??
            preparedContext.fileMap.get(entry.path)?.contentPreview ??
            '',
        Math.floor(maxCharsPerFile * 0.6),
      ),
    })),
    relevantFiles: preparedContext.selectedEntries.map(entry => ({
      path: entry.path,
      summary: entry.summary,
      reasons: entry.reasons,
      content: trimRepoExecutionContent(
        preparedContext.fileMap.get(entry.path)?.content ??
            preparedContext.fileMap.get(entry.path)?.contentPreview ??
            '',
        maxCharsPerFile,
      ),
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
  const contextSnapshot = buildContextOrchestratorSnapshot({
    fileMap: preparedContext.fileMap,
    selectedEntries: preparedContext.selectedEntries,
    dependencyEntries: preparedContext.dependencyEntries,
    globalContextEntries: preparedContext.globalContextEntries,
    inspectedPaths: preparedContext.inspectedPaths,
    repoOverview: preparedContext.repoOverview,
    architectureOverview: preparedContext.architectureOverview,
    moduleOverview: preparedContext.moduleOverview,
    repoSizeClass: preparedContext.repoSizeClass,
    contextStrategy: preparedContext.contextStrategy,
    executionMemorySummary: preparedContext.executionMemorySummary,
    planningSummary: preparedContext.planningSummary,
  });

  const pickRoutingForAttempt = async (attempt: number) => {
    const stage =
      attempt === 1 && params.repairMode !== true ? 'generate_diff' : 'repair_diff';
    // Use adaptive routing for repair attempts as well — historical data on
    // repair_diff performance may differ from generate_diff.
    const routing = await resolveRepoExecutionProviderRoutingAsync({
      requestedProvider:
        attempt === 1 ? params.requestedProvider ?? null : null,
      stage,
      deepMode: params.deepMode,
      repoSizeClass: preparedContext.repoSizeClass,
      retryCount: Math.max(effectiveRetryCount + attempt - 1, 0),
      costProfile: chooseAgentCostProfile({
        stage: stage === 'repair_diff' ? 'repair' : 'editing',
        deepMode: params.deepMode,
        retryCount: Math.max(effectiveRetryCount + attempt - 1, 0),
        budgetRemainingRatio: params.budgetRemainingRatio,
        repoSizeClass: preparedContext.repoSizeClass,
      }),
      repoId: params.repoId,
    });
    const provider =
      routing.availableProviders[Math.min(attempt - 1, routing.availableProviders.length - 1)] ??
      routing.provider;
    return {
      ...routing,
      provider,
      model: getModelForTierAndProvider(routing.tier, provider),
      reason:
        attempt === 1
          ? routing.reason
          : `${routing.reason} Retry ${attempt} is widening provider fallback after invalid structured output.`,
    };
  };

  let generationResult: Awaited<ReturnType<typeof callRepoExecutionModel>> | null = null;
  let rawOutput = '';
  let parsedEdits = [] as ReturnType<typeof parseRepoExecutionResponse>;
  const maxFiles = Math.max(preparedContext.selectedEntries.length, 1);
  const allowedPaths = new Set(
    preparedContext.selectedEntries.map(entry => entry.path),
  );
  for (let attempt = 1; attempt <= maxStructuredOutputAttempts; attempt += 1) {
    const routing = attempt === 1 ? executionRouting : await pickRoutingForAttempt(attempt);
    finalExecutionRouting = routing;
    if (attempt > 1) {
      await params.observer?.onRetrying?.({
        reason:
          `Structured diff payload failed validation. Retrying with ${routing.provider} on attempt ${attempt}.`,
        attempt,
      });
    }
    await params.observer?.onAiCalled?.({
      attempt,
      mode,
      provider: routing.provider,
      model: routing.model,
      stage: routing.stage,
      reason: routing.reason,
    });
    generationResult = await callRepoExecutionModel({
      provider: routing.provider,
      model: routing.model,
      mode,
      contextPrompt: buildRepoExecutionUserPrompt(contextPayload),
      repairPrompt:
        attempt === 1
          ? undefined
          : buildRepoExecutionRepairPrompt(contextPayload, rawOutput),
    });
    rawOutput = generationResult.text;
    parsedEdits = parseRepoExecutionResponse(rawOutput);
    if (validateRepoExecutionEdits(parsedEdits, preparedContext.fileMap, allowedPaths, maxFiles)) {
      break;
    }
  }

  if (!generationResult || !validateRepoExecutionEdits(parsedEdits, preparedContext.fileMap, allowedPaths, maxFiles)) {
    throw new HttpsError(
      'internal',
      `The AI returned an invalid repo execution payload after ${maxStructuredOutputAttempts} attempts. Please retry with a narrower request.`,
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
        (preparedContext.repoOverview?.length ?? 0) +
        preparedContext.globalContextEntries.reduce(
          (sum, entry) => sum + Math.floor(entry.approxTokens * 1.5),
          0,
        ) +
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
    preparedContext.wholeRepoEligible
      ? 'Repository qualified for whole-repo inline context'
      : 'Built expanded repo manifest and planned context',
    `Routed ${params.repairMode === true ? 'repair' : 'execution'} through ${generationResult.provider} (${generationResult.model})`,
    `Selected ${preparedContext.selectedEntries.length} editable files`,
    `Loaded ${preparedContext.inspectedPaths.length} files into the exploration set`,
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
    ...contextSnapshot,
    executionMemory: serializeRepoExecutionRunMemory(preparedContext.executionMemory),
    executionMemorySummary: preparedContext.executionMemorySummary,
    repoCoverageNotice: preparedContext.repoCoverageNotice,
    focusedModules: preparedContext.focusedModules,
    moduleCount: preparedContext.moduleCount,
    architectureZoneCount: preparedContext.architectureZoneCount,
    explorationPassCount: preparedContext.explorationPassCount,
    hydratedPathCount: preparedContext.hydratedPathCount,
    contextPlannerProvider: preparedContext.contextPlannerProvider ?? null,
    contextPlannerModel: preparedContext.contextPlannerModel ?? null,
    executionPlannerProvider: preparedContext.executionPlannerProvider ?? null,
    executionPlannerModel: preparedContext.executionPlannerModel ?? null,
    wholeRepoEligible: preparedContext.wholeRepoEligible,
    planningSummary: preparedContext.planningSummary,
    executionProvider: generationResult.provider,
    executionModel: generationResult.model,
    executionProviderReason: finalExecutionRouting.reason,
    executionProviderOrder: finalExecutionRouting.providerOrder,
    executionAvailableProviders: finalExecutionRouting.availableProviders,
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
    ...contextSnapshot,
    steps,
    edits,
    executionMemory: serializeRepoExecutionRunMemory(preparedContext.executionMemory),
    executionMemorySummary: preparedContext.executionMemorySummary,
    repoCoverageNotice: preparedContext.repoCoverageNotice,
    focusedModules: preparedContext.focusedModules,
    moduleCount: preparedContext.moduleCount,
    architectureZoneCount: preparedContext.architectureZoneCount,
    explorationPassCount: preparedContext.explorationPassCount,
    hydratedPathCount: preparedContext.hydratedPathCount,
    contextPlannerProvider: preparedContext.contextPlannerProvider,
    contextPlannerModel: preparedContext.contextPlannerModel,
    executionPlannerProvider: preparedContext.executionPlannerProvider,
    executionPlannerModel: preparedContext.executionPlannerModel,
    wholeRepoEligible: preparedContext.wholeRepoEligible,
    planningSummary: preparedContext.planningSummary,
    executionProvider: generationResult.provider,
    executionModel: generationResult.model,
    executionProviderReason: finalExecutionRouting.reason,
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
    `Applied ${appliedPaths.length} repo execution change${appliedPaths.length === 1 ? '' : 's'} to the legacy repo draft.`,
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
          'The agent has applied the workspace edits. Approve to create a branch, commit the local workspace, and open a pull request.',
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
          'The agent has applied the workspace edits. Approve to commit the current local workspace to the remote repository.',
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
  const workspace = await ensureAgentTaskLocalWorkspace(ownerId, taskId, task);
  const commitMessage =
    `feat(agent): ${truncate(normalizeText(task.prompt), 72)}` || 'feat(agent): apply generated changes';
  const pushResult = await prepareWorkspaceBranchForRemoteGitOps({
    workspacePath: workspace.workspacePath,
    provider,
    token: tokenInfo.token,
    branchName: repo.defaultBranch ?? 'main',
    commitMessage,
  });
  if (!pushResult.committed) {
    return {
      remoteId: null,
      remoteUrl: null,
      summary: pushResult.summary,
    };
  }
  const headSha = await readEphemeralWorkspaceHeadRevision({
    workspacePath: workspace.workspacePath,
  }).catch(() => null);
  return {
    remoteId: headSha,
    remoteUrl:
      headSha != null && repo.htmlUrl != null ? `${repo.htmlUrl}/commit/${headSha}` : repo.htmlUrl ?? null,
    summary: 'Committed and pushed the applied local workspace changes to the remote repository.',
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
  const workspace = await ensureAgentTaskLocalWorkspace(ownerId, taskId, task);
  const branchName = `forgeai/agent-${taskId.slice(0, 8)}`;
  const commitMessage =
    `feat(agent): ${truncate(normalizeText(task.prompt), 72)}` || 'feat(agent): apply generated changes';
  const pushResult = await prepareWorkspaceBranchForRemoteGitOps({
    workspacePath: workspace.workspacePath,
    provider,
    token: tokenInfo.token,
    branchName,
    commitMessage,
  });
  if (!pushResult.committed) {
    throw new HttpsError('failed-precondition', pushResult.summary);
  }
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

type AgentRepairWorkspaceSource =
  | 'local_workspace'
  | 'sandbox_workspace'
  | 'repo_sync';

interface AgentRepairPromptOptions {
  reason: string;
  failurePaths?: string[];
  failureLocations?: string[];
  failureCategory?: string | null;
  targetPaths?: string[];
  workspaceSource?: AgentRepairWorkspaceSource;
}

function normalizeRepairPaths(paths: readonly string[], limit = 16) {
  const normalized: string[] = [];
  const seen = new Set<string>();
  for (const raw of paths) {
    if (typeof raw !== 'string' || raw.trim().length === 0) {
      continue;
    }
    const path = normalizePromptRepoPath(raw);
    if (!path || seen.has(path)) {
      continue;
    }
    seen.add(path);
    normalized.push(path);
    if (normalized.length >= limit) {
      break;
    }
  }
  return normalized;
}

function coerceMetadataStringList(
  metadata: Record<string, unknown> | null | undefined,
  key: string,
  limit = 16,
) {
  if (!isObject(metadata)) {
    return [] as string[];
  }
  const raw = metadata[key];
  if (!Array.isArray(raw)) {
    return [] as string[];
  }
  return raw
    .filter((value): value is string => typeof value === 'string' && value.trim().length > 0)
    .slice(0, limit);
}

function workspaceSourceOfTruthLabel(source: AgentRepairWorkspaceSource | null | undefined) {
  switch (source) {
    case 'sandbox_workspace':
      return 'the sandbox workspace candidate';
    case 'repo_sync':
      return 'the legacy synced repository metadata snapshot';
    case 'local_workspace':
    default:
      return 'the task-local workspace';
  }
}

function formatFailureCategoryLabel(category: string | null | undefined) {
  switch (category) {
    case 'workspace':
      return 'Workspace consistency';
    case 'import':
      return 'Import or module resolution';
    case 'typecheck':
      return 'Type or compile';
    case 'syntax':
      return 'Syntax';
    case 'test':
      return 'Test failure';
    case 'build':
      return 'Build';
    case 'lint':
      return 'Lint or static analysis';
    case 'ci':
      return 'Remote CI';
    default:
      return null;
  }
}

function formatRepairStrategyLabel(strategy: string | null | undefined) {
  switch (strategy) {
    case 'targeted_patch':
      return 'Targeted patch';
    case 'widened_context':
      return 'Widened context';
    case 'escalated_reasoning':
      return 'Escalated reasoning';
    default:
      return null;
  }
}

function buildRepairTargetPaths(params: {
  failurePaths?: string[];
  priorTouchedPaths?: string[];
  currentFilePath?: string | null;
  limit?: number;
}) {
  return normalizeRepairPaths(
    [
      ...(params.failurePaths ?? []),
      ...(params.priorTouchedPaths ?? []),
      ...(params.currentFilePath ? [params.currentFilePath] : []),
    ],
    params.limit ?? 18,
  );
}

function buildFailureSignature(params: {
  failureCategory: string | null | undefined;
  failurePaths: string[];
  failureLocations: string[];
}) {
  const category = params.failureCategory?.trim() || 'unknown';
  const paths = normalizeRepairPaths(params.failurePaths, 4);
  const locations = params.failureLocations
    .map(value => value.trim())
    .filter(value => value.length > 0)
    .slice(0, 2)
    .map(value => truncate(value, 180));
  return [category, ...paths, ...locations].join('|');
}

function coerceRepairFailureHistory(
  metadata: Record<string, unknown> | null | undefined,
) {
  if (!isObject(metadata) || !Array.isArray(metadata.repairFailureHistory)) {
    return [] as Record<string, unknown>[];
  }
  return metadata.repairFailureHistory.filter(isObject);
}

function buildRepairFailureState(params: {
  task: AgentTaskDocument;
  validationAttempt: number;
  validationMode: 'working_copy' | 'sandbox';
  failureInsights: ReturnType<typeof buildValidationFailureInsights>;
  summary: string;
}) {
  const metadata = isObject(params.task.metadata) ? params.task.metadata : null;
  const history = coerceRepairFailureHistory(metadata);
  const failureSignature = buildFailureSignature({
    failureCategory: params.failureInsights.failureCategory,
    failurePaths: params.failureInsights.failurePaths,
    failureLocations: params.failureInsights.failureLocations,
  });
  const repeatedSignatureCount = history.filter(
    entry => entry.signature === failureSignature,
  ).length;
  const repeatedCategoryCount = history.filter(
    entry => entry.category === params.failureInsights.failureCategory,
  ).length;
  const repairEscalationLevel =
    repeatedSignatureCount >= 2 || repeatedCategoryCount >= 3
      ? 2
      : repeatedSignatureCount >= 1
        ? 1
        : 0;
  const repairStrategyLabel =
    repairEscalationLevel >= 2
      ? 'escalated_reasoning'
      : repairEscalationLevel == 1
        ? 'widened_context'
        : 'targeted_patch';
  const repairTargetPaths = normalizeRepairPaths(
    [
      ...params.failureInsights.failurePaths,
      ...params.task.filesTouched,
      ...(params.task.currentFilePath ? [params.task.currentFilePath] : []),
      ...(repairEscalationLevel >= 1 ? params.task.selectedFiles : []),
      ...(
        repairEscalationLevel >= 1 &&
        ['import', 'typecheck', 'build', 'ci'].includes(
          params.failureInsights.failureCategory,
        )
          ? params.task.dependencyFiles
          : []
      ),
      ...(repairEscalationLevel >= 2 ? params.task.inspectedFiles : []),
    ],
    repairEscalationLevel >= 2
      ? (params.task.deepMode ? 32 : 22)
      : repairEscalationLevel == 1
        ? (params.task.deepMode ? 24 : 18)
        : (params.task.deepMode ? 18 : 12),
  );
  const historyEntry = {
    attempt: params.validationAttempt,
    retryCount: params.task.retryCount,
    validationMode: params.validationMode,
    category: params.failureInsights.failureCategory,
    signature: failureSignature,
    summary: truncate(params.summary, 800),
    failurePaths: params.failureInsights.failurePaths.slice(0, 16),
    failureLocations: params.failureInsights.failureLocations.slice(0, 12),
    repairTargetPaths,
    repeatedSignatureCount: repeatedSignatureCount + 1,
    repeatedCategoryCount: repeatedCategoryCount + 1,
    repairStrategyLabel,
    repairEscalationLevel,
    recordedAtMs: Date.now(),
  };
  const nextHistory = [...history.slice(-11), historyEntry];
  const repairQualityMetrics = buildRepairQualityMetrics({
    metadata: {
      ...(metadata ?? {}),
      repairFailureHistory: nextHistory,
    },
    validationAttempt: params.validationAttempt,
    retryCount: params.task.retryCount,
    validationPassed: false,
  });
  return {
    failureSignature,
    repeatedSignatureCount,
    repeatedCategoryCount,
    repairEscalationLevel,
    repairStrategyLabel,
    repairTargetPaths,
    nextHistory,
    metadataPatch: {
      repairFailureHistory: nextHistory,
      latestFailureSignature: failureSignature,
      latestFailureCategory: params.failureInsights.failureCategory,
      latestFailureLocations: params.failureInsights.failureLocations,
      repeatedFailureDetected: repeatedSignatureCount > 0,
      repeatedFailureSignatureCount: repeatedSignatureCount + 1,
      repeatedFailureCategoryCount: repeatedCategoryCount + 1,
      repairStrategyLabel,
      repairEscalationLevel,
      repairTargetPaths,
      repairQualityMetrics,
      workspaceSourceOfTruth:
        params.validationMode === 'sandbox'
          ? 'sandbox_workspace'
          : 'local_workspace',
    },
  };
}

function buildRepairQualityMetrics(params: {
  metadata: Record<string, unknown> | null | undefined;
  validationAttempt: number;
  retryCount: number;
  validationPassed: boolean;
}) {
  const metadata = isObject(params.metadata) ? params.metadata : null;
  const history = coerceRepairFailureHistory(metadata);
  const categoryCounts = new Map<string, number>();
  for (const entry of history) {
    const category =
      typeof entry.category === 'string' && entry.category.trim().length > 0
        ? entry.category.trim()
        : 'unknown';
    categoryCounts.set(category, (categoryCounts.get(category) ?? 0) + 1);
  }
  const repeatedFailures = history.filter(entry => {
    const count =
      typeof entry.repeatedSignatureCount === 'number'
        ? entry.repeatedSignatureCount
        : 0;
    return count > 1;
  }).length;
  const sortedCategories = [...categoryCounts.entries()].sort(
    (a, b) => b[1] - a[1] || a[0].localeCompare(b[0]),
  );
  const mostCommonFailureCategory = sortedCategories[0]?.[0] ?? null;
  return {
    repairAttemptCount: params.retryCount,
    validationPassCount: params.validationAttempt,
    failureEventCount: history.length,
    repeatedFailureEventCount: repeatedFailures,
    uniqueFailureCategoryCount: sortedCategories.length,
    mostCommonFailureCategory,
    bottlenecks: sortedCategories.slice(0, 3).map(([category, count]) => ({
      category,
      count,
    })),
    successfulAfterRepair: params.validationPassed && params.retryCount > 0,
    passesToSuccess: params.validationPassed ? params.validationAttempt : null,
    totalEstimatedAgentTokens:
      metadata != null && typeof metadata.totalEstimatedAgentTokens === 'number'
        ? metadata.totalEstimatedAgentTokens
        : 0,
    totalEstimatedAgentCostUsd:
      metadata != null && typeof metadata.totalEstimatedAgentCostUsd === 'number'
        ? metadata.totalEstimatedAgentCostUsd
        : 0,
  };
}

function buildAgentRepairPrompt(
  task: AgentTaskDocument,
  options: AgentRepairPromptOptions,
) {
  const metadata = isObject(task.metadata) ? task.metadata : null;
  const failurePaths = normalizeRepairPaths(
    options.failurePaths ??
        coerceMetadataStringList(metadata, 'failurePaths'),
    16,
  );
  const failureLocations =
    (options.failureLocations ??
            coerceMetadataStringList(metadata, 'latestFailureLocations', 12))
        .filter(value => value.trim().length > 0)
        .slice(0, 12);
  const failureCategory =
    options.failureCategory ??
    (metadata != null && typeof metadata.latestFailureCategory === 'string'
        ? metadata.latestFailureCategory
        : null);
  const targetPaths = normalizeRepairPaths(
    options.targetPaths ??
        coerceMetadataStringList(metadata, 'repairTargetPaths', 18),
    18,
  );
  const workspaceSource =
    options.workspaceSource ??
    (metadata != null && typeof metadata.workspaceSourceOfTruth === 'string'
        ? (metadata.workspaceSourceOfTruth as AgentRepairWorkspaceSource)
        : 'local_workspace');
  const repairStrategyLabel =
    metadata != null && typeof metadata.repairStrategyLabel === 'string'
      ? formatRepairStrategyLabel(metadata.repairStrategyLabel)
      : null;
  const repeatedFailureSignatureCount =
    metadata != null && typeof metadata.repeatedFailureSignatureCount === 'number'
      ? metadata.repeatedFailureSignatureCount
      : 0;
  const recentValidationHistory = formatRecentValidationHistory(task.metadata);
  const recentRepairMemory = formatRecentRepairFailureMemory(task.metadata);
  return [
    task.prompt,
    '',
    `The previous implementation was materialized in ${workspaceSourceOfTruthLabel(workspaceSource)}, but validation failed.`,
    'Repair the current candidate implementation in place instead of starting over.',
    'Do not rewrite unaffected files. Patch the failing area first and widen the scope only if validation proves another file must change.',
    targetPaths.length > 0 ? `Target these files first:\n${targetPaths.join('\n')}` : '',
    repairStrategyLabel != null ? `Repair strategy: ${repairStrategyLabel}` : '',
    repeatedFailureSignatureCount > 1
      ? `This failure signature has now repeated ${repeatedFailureSignatureCount} times. Avoid repeating the last patch pattern unchanged.`
      : '',
    failureCategory != null
      ? `Failure category: ${formatFailureCategoryLabel(failureCategory) ?? failureCategory}`
      : '',
    `Validation failure:\n${truncate(options.reason, 4_000)}`,
    failureLocations.length > 0
      ? `Exact failing locations:\n${failureLocations.join('\n')}`
      : '',
    failurePaths.length > 0
      ? `Files implicated by validation:\n${failurePaths.join('\n')}`
      : '',
    recentValidationHistory,
    recentRepairMemory,
    'Preserve the intended product behavior and change only the files needed to resolve the failure.',
  ]
    .filter(value => value.trim().length > 0)
    .join('\n');
}

function buildAgentGuardrailRepairPrompt(params: {
  task: AgentTaskDocument;
  validationErrors: string[];
  priorSummary: string;
}) {
  return [
    params.task.prompt,
    '',
    'The generated diff did not satisfy the agent guardrails before apply approval.',
    'Generate a narrower patch that stays within the allowed file-count and token budget.',
    'Do not restart the feature from scratch.',
    `Current draft summary:\n${truncate(params.priorSummary, 2_000)}`,
    `Guardrail failures:\n${params.validationErrors.join('\n')}`,
    'Prefer the smallest correct change set and keep non-essential edits out of scope.',
    formatRecentValidationHistory(params.task.metadata),
  ]
    .filter(value => value.trim().length > 0)
    .join('\n');
}

function formatRecentValidationHistory(
  metadata: Record<string, unknown> | null | undefined,
) {
  if (!isObject(metadata)) {
    return '';
  }
  const history = Array.isArray(metadata.validationHistory)
    ? metadata.validationHistory.filter(isObject)
    : [];
  const lines = history.slice(-2).flatMap(entry => {
    const attempt =
      typeof entry.attempt === 'number' ? entry.attempt.toString() : '?';
    const summary =
      typeof entry.summary === 'string' ? truncate(entry.summary, 600) : '';
    const results = Array.isArray(entry.results)
      ? entry.results.filter(isObject)
      : [];
    const resultLines = results.slice(0, 3).map(result => {
      const name = typeof result.name === 'string' ? result.name : 'Validation tool';
      const findings = Array.isArray(result.findings)
        ? result.findings.filter(isObject)
        : [];
      const findingSummary = findings
        .slice(0, 2)
        .map(finding => {
          const filePath =
            typeof finding.filePath === 'string' ? finding.filePath : null;
          const line =
            typeof finding.line === 'number' ? `:${finding.line}` : '';
          const message =
            typeof finding.message === 'string' ? finding.message : '';
          return `${filePath ?? 'repo'}${line} ${message}`.trim();
        })
        .filter(value => value.length > 0)
        .join(' | ');
      return findingSummary.length > 0
        ? `- ${name}: ${truncate(findingSummary, 320)}`
        : `- ${name}: ${truncate(
            typeof result.summary === 'string' ? result.summary : 'Validation result recorded.',
            320,
          )}`;
    });
    return [
      `Attempt ${attempt}: ${summary || 'Validation result recorded.'}`,
      ...resultLines,
    ];
  });
  if (lines.length === 0) {
    return '';
  }
  return `Recent validation history:\n${lines.join('\n')}`;
}

function formatRecentRepairFailureMemory(
  metadata: Record<string, unknown> | null | undefined,
) {
  if (!isObject(metadata)) {
    return '';
  }
  const history = coerceRepairFailureHistory(metadata).slice(-2);
  if (history.length === 0) {
    return '';
  }
  const lines = history.flatMap(entry => {
    const attempt =
      typeof entry.attempt === 'number' ? entry.attempt.toString() : '?';
    const category =
      typeof entry.category === 'string' && entry.category.trim().length > 0
        ? formatFailureCategoryLabel(entry.category) ?? entry.category
        : 'Unknown';
    const strategy =
      typeof entry.repairStrategyLabel === 'string'
        ? formatRepairStrategyLabel(entry.repairStrategyLabel)
        : 'Targeted patch';
    const repeatedSignatureCount =
      typeof entry.repeatedSignatureCount === 'number'
        ? entry.repeatedSignatureCount
        : 1;
    const targetPaths = Array.isArray(entry.repairTargetPaths)
      ? entry.repairTargetPaths
          .filter((value): value is string => typeof value === 'string')
          .slice(0, 4)
      : [];
    return [
      `Attempt ${attempt}: ${category} using ${strategy}${repeatedSignatureCount > 1 ? ` (repeat ${repeatedSignatureCount})` : ''}.`,
      targetPaths.length > 0 ? `- Targeted paths: ${targetPaths.join(', ')}` : '',
    ];
  });
  return `Recent repair memory:\n${lines.filter(line => line.trim().length > 0).join('\n')}`;
}

function buildAgentRepoExecutionObserver(params: {
  ownerId: string;
  taskId: string;
}) {
  const taskReference = db
    .collection('users')
    .doc(params.ownerId)
    .collection('agentTasks')
    .doc(params.taskId);
  const observed = {
    selectedFiles: [] as string[],
    dependencyFiles: [] as string[],
    inspectedFiles: [] as string[],
  };
  const observer: RepoExecutionObserver = {
    onRepoScanned: async details => {
      await taskReference.set(
        <Record<string, unknown>>{
          currentStep: 'Mapping repository snapshot',
          updatedAtMs: Date.now(),
          'metadata.repoFileCount': details.fileCount,
        },
        { merge: true },
      );
      await appendAgentTaskEvent({
        ownerId: params.ownerId,
        taskId: params.taskId,
        type: 'repo_scanned',
        step: 'Indexed repository snapshot',
        message: `Indexed ${details.fileCount} repository file${details.fileCount === 1 ? '' : 's'}.`,
        status: 'running',
        phase: 'inspect_repo',
        data: {
          fileCount: details.fileCount,
        },
      });
      await recordPassiveAgentToolExecution({
        ownerId: params.ownerId,
        taskId: params.taskId,
        toolName: 'repo_map',
        summary: `Mapped ${details.fileCount} synced repository file${details.fileCount === 1 ? '' : 's'}.`,
        metadata: {
          fileCount: details.fileCount,
        },
      });
    },
    onFilesSelected: async details => {
      observed.selectedFiles = details.selectedFiles;
      observed.dependencyFiles = details.dependencyFiles;
      observed.inspectedFiles = details.inspectedFiles;
      await taskReference.set(
        <Record<string, unknown>>{
          currentStep: details.wholeRepoEligible
            ? 'Preparing whole-repo context'
            : 'Expanding repository context',
          selectedFiles: details.selectedFiles,
          dependencyFiles: details.dependencyFiles,
          inspectedFiles: details.inspectedFiles,
          updatedAtMs: Date.now(),
          'metadata.wholeRepoEligible': details.wholeRepoEligible,
          'metadata.globalContextFiles': details.globalContextFiles,
          'metadata.repoOverview': details.repoOverview ?? null,
          'metadata.architectureOverview': details.architectureOverview ?? null,
          'metadata.moduleOverview': details.moduleOverview ?? null,
          'metadata.planningSummary': details.planningSummary ?? null,
          'metadata.repoSizeClass': details.repoSizeClass ?? null,
          'metadata.contextStrategy': details.contextStrategy ?? null,
          'metadata.executionMemorySummary': details.executionMemorySummary ?? null,
          'metadata.focusedModules': details.focusedModules ?? [],
          'metadata.repoCoverageNotice': details.repoCoverageNotice ?? null,
          'metadata.moduleCount': details.moduleCount ?? null,
          'metadata.architectureZoneCount': details.architectureZoneCount ?? null,
          'metadata.explorationPassCount': details.explorationPassCount ?? null,
          'metadata.hydratedPathCount': details.hydratedPathCount ?? null,
          'metadata.contextPlannerProvider': details.contextPlannerProvider ?? null,
          'metadata.contextPlannerModel': details.contextPlannerModel ?? null,
          'metadata.executionPlannerProvider': details.executionPlannerProvider ?? null,
          'metadata.executionPlannerModel': details.executionPlannerModel ?? null,
          'metadata.repoContextStrategy': details.contextStrategy ??
              (details.wholeRepoEligible ? 'whole_repo_inline' : 'expanded_repo_context'),
          'metadata.selectedFileCount': details.selectedFiles.length,
          'metadata.dependencyFileCount': details.dependencyFiles.length,
          'metadata.inspectedFileCount': details.inspectedFiles.length,
          'metadata.globalContextFileCount': details.globalContextFiles.length,
        },
        { merge: true },
      );
      await appendAgentTaskEvent({
        ownerId: params.ownerId,
        taskId: params.taskId,
        type: 'files_selected',
        step: 'Planned editable wave',
        message:
          `Planned the current editable wave across ${details.selectedFiles.length} file${details.selectedFiles.length === 1 ? '' : 's'} ` +
          `after inspecting ${details.inspectedFiles.length} repository path${details.inspectedFiles.length === 1 ? '' : 's'} across ${details.moduleCount ?? details.focusedModules?.length ?? 0} modules. ` +
          'The agent can still widen this scope during repair if validation exposes additional ripple paths.',
        status: 'running',
        phase: 'inspect_repo',
        data: {
          selectedFiles: details.selectedFiles,
          dependencyFiles: details.dependencyFiles,
          inspectedFiles: details.inspectedFiles,
          globalContextFiles: details.globalContextFiles,
          wholeRepoEligible: details.wholeRepoEligible,
          planningSummary: details.planningSummary,
          repoSizeClass: details.repoSizeClass,
          contextStrategy: details.contextStrategy,
          focusedModules: details.focusedModules ?? [],
          repoCoverageNotice: details.repoCoverageNotice ?? null,
          moduleCount: details.moduleCount ?? null,
          architectureZoneCount: details.architectureZoneCount ?? null,
          explorationPassCount: details.explorationPassCount ?? null,
          hydratedPathCount: details.hydratedPathCount ?? null,
          contextPlannerProvider: details.contextPlannerProvider ?? null,
          executionPlannerProvider: details.executionPlannerProvider ?? null,
        },
      });
      await recordPassiveAgentToolExecution({
        ownerId: params.ownerId,
        taskId: params.taskId,
        toolName: 'context_expand',
        summary:
          `Expanded repo context to ${details.inspectedFiles.length} inspected path${details.inspectedFiles.length === 1 ? '' : 's'} ` +
          `and planned ${details.selectedFiles.length} editable file${details.selectedFiles.length === 1 ? '' : 's'} for the current wave.`,
        metadata: {
          selectedFileCount: details.selectedFiles.length,
          inspectedFileCount: details.inspectedFiles.length,
          dependencyFileCount: details.dependencyFiles.length,
          focusedModules: details.focusedModules ?? [],
          contextStrategy: details.contextStrategy ?? null,
        },
      });
    },
    onExplorationPass: async details => {
      await taskReference.set(
        <Record<string, unknown>>{
          currentStep: details.wholeRepoInline
              ? 'Hydrating whole-repo context'
              : 'Expanding repository context',
          updatedAtMs: Date.now(),
          'metadata.repoSizeClass': details.repoSizeClass,
          'metadata.contextStrategy': details.contextStrategy,
          'metadata.focusedModules': details.focusModules,
          'metadata.architectureConclusions': details.architectureFindings,
          'metadata.unresolvedQuestions': details.uncertainties,
          'metadata.executionMemorySummary': details.executionMemorySummary,
          'metadata.explorationPass': details.passNumber,
          'metadata.explorationPassLimit': details.totalPasses,
          'metadata.repoCoverageNotice': details.repoCoverageNotice ?? null,
          'metadata.moduleCount': details.moduleCount ?? null,
          'metadata.architectureZoneCount': details.architectureZoneCount ?? null,
          'metadata.hydratedPathCount': details.hydratedPaths.length,
        },
        { merge: true },
      );
      await appendAgentTaskEvent({
        ownerId: params.ownerId,
        taskId: params.taskId,
        type: 'repo_scanned',
        step: details.wholeRepoInline
            ? 'Hydrated whole-repo context'
            : `Expanded repo context (pass ${details.passNumber}/${details.totalPasses})`,
        message: details.wholeRepoInline
            ? `Loaded the full synced repository because broad inline reasoning is practical here (${details.hydratedPaths.length} hydrated paths across ${details.moduleCount ?? details.focusModules.length} modules).`
            : `Expanded repo understanding through ${details.hydratedPaths.length} hydrated paths across ${details.focusModules.length} focused modules. ${details.rationale}`,
        status: 'running',
        phase: 'inspect_repo',
        data: {
          passNumber: details.passNumber,
          totalPasses: details.totalPasses,
          repoSizeClass: details.repoSizeClass,
          contextStrategy: details.contextStrategy,
          focusModules: details.focusModules,
          requestedPaths: details.requestedPaths,
          hydratedPaths: details.hydratedPaths,
          readOnlyPaths: details.readOnlyPaths,
          selectedFiles: details.promotedPaths,
          architectureFindings: details.architectureFindings,
          uncertainties: details.uncertainties,
          executionMemorySummary: details.executionMemorySummary,
          repoCoverageNotice: details.repoCoverageNotice ?? null,
          moduleCount: details.moduleCount ?? null,
          architectureZoneCount: details.architectureZoneCount ?? null,
          done: details.done,
        },
      });
      await recordPassiveAgentToolExecution({
        ownerId: params.ownerId,
        taskId: params.taskId,
        toolName: 'context_expand',
        summary: details.wholeRepoInline
            ? `Hydrated the synced repo broadly for whole-repo inline reasoning (${details.hydratedPaths.length} hydrated paths).`
            : `Exploration pass ${details.passNumber}/${details.totalPasses} widened context across ${details.hydratedPaths.length} hydrated path${details.hydratedPaths.length === 1 ? '' : 's'}.`,
        metadata: {
          passNumber: details.passNumber,
          totalPasses: details.totalPasses,
          wholeRepoInline: details.wholeRepoInline,
          hydratedPathCount: details.hydratedPaths.length,
          focusModules: details.focusModules,
          done: details.done,
        },
      });
    },
    onFileRead: async details => {
      await appendAgentTaskEvent({
        ownerId: params.ownerId,
        taskId: params.taskId,
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
      await taskReference.set(
        {
          phase: 'generate_diff',
          currentStep:
            details.attempt === 1
              ? 'Generating repository diff'
              : 'Generating repair diff',
          'metadata.executionProvider': details.provider ?? null,
          'metadata.executionModel': details.model ?? null,
          'metadata.executionStage': details.stage ?? null,
          'metadata.executionProviderReason': details.reason ?? null,
          updatedAtMs: Date.now(),
        },
        { merge: true },
      );
      await appendAgentTaskEvent({
        ownerId: params.ownerId,
        taskId: params.taskId,
        type: 'ai_called',
        step: 'Calling model',
        message:
          details.attempt === 1
            ? `Calling ${details.provider ?? 'the model'} to generate the next repo diff.`
            : `Calling ${details.provider ?? 'the model'} again with repair instructions.`,
        status: 'running',
        phase: 'generate_diff',
        data: {
          attempt: details.attempt,
          mode: details.mode,
          provider: details.provider,
          model: details.model,
          stage: details.stage,
          reason: details.reason,
        },
      });
    },
    onRetrying: async details => {
      await taskReference.set(
        {
          phase: 'generate_diff',
          currentStep: 'Retrying diff generation',
          updatedAtMs: Date.now(),
        },
        { merge: true },
      );
      await appendAgentTaskEvent({
        ownerId: params.ownerId,
        taskId: params.taskId,
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
      await taskReference.set(
        {
          phase: 'generate_diff',
          currentStep: 'Diff ready for validation',
          updatedAtMs: Date.now(),
        },
        { merge: true },
      );
      await appendAgentTaskEvent({
        ownerId: params.ownerId,
        taskId: params.taskId,
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
      await recordPassiveAgentToolExecution({
        ownerId: params.ownerId,
        taskId: params.taskId,
        toolName: 'generate_diff',
        summary:
          `Generated a ${details.editCount}-file reviewable diff that is ready for validation.`,
        metadata: {
          editCount: details.editCount,
          sessionId: details.sessionId,
          summary: details.summary,
        },
      });
    },
  };
  return {
    observed,
    observer,
  };
}

function buildWorkspaceConsistencyResult(params: {
  mismatchedPaths: string[];
  durationMs: number;
}) {
  const findings = params.mismatchedPaths.slice(0, 12).map<AgentValidationFinding>(path => ({
    severity: 'error',
    filePath: path,
    code: 'workspace_mismatch',
    source: 'workspace_consistency',
    message: 'The applied local workspace no longer matches the approved diff.',
  }));
  return {
    id: 'workspace_consistency',
    kind: 'workspace_consistency' as const,
    name: 'Workspace consistency',
    status: params.mismatchedPaths.length === 0 ? 'passed' : 'failed',
    summary:
      params.mismatchedPaths.length === 0
        ? 'Applied diff still matches the local workspace.'
        : `Local workspace validation failed for ${params.mismatchedPaths.length} path${params.mismatchedPaths.length === 1 ? '' : 's'}.`,
    durationMs: params.durationMs,
    findings,
    executed: true,
  } satisfies AgentValidationToolResult;
}

function buildSkippedValidationToolResult(params: {
  id: string;
  name: string;
  summary: string;
  kind?: AgentValidationToolResult['kind'];
  workflowName?: string | null;
  workflowPath?: string | null;
  workflowCategory?: string | null;
}) {
  return {
    id: params.id,
    kind: params.kind ?? ('ci_workflow' as const),
    name: params.name,
    status: 'skipped' as const,
    summary: params.summary,
    durationMs: 0,
    findings: [] as AgentValidationFinding[],
    workflowName: params.workflowName ?? null,
    workflowPath: params.workflowPath ?? null,
    workflowCategory: params.workflowCategory ?? null,
    executed: false,
  } satisfies AgentValidationToolResult;
}

function buildLocalWorkspaceValidationResult(params: {
  id: string;
  name: string;
  status: 'passed' | 'failed' | 'skipped' | 'timed_out';
  summary: string;
  output: string;
  durationMs: number;
}) {
  return {
    id: params.id,
    kind: 'workspace_command' as const,
    name: params.name,
    status: params.status,
    summary: params.summary,
    durationMs: params.durationMs,
    findings:
      params.status === 'passed' || params.status === 'skipped'
        ? ([] as AgentValidationFinding[])
        : parseToolOutputFindings({
            output: params.output,
            source: params.name,
            limit: 16,
          }),
    executed: params.status !== 'skipped',
  } satisfies AgentValidationToolResult;
}

async function appendAgentValidationToolStarted(params: {
  ownerId: string;
  taskId: string;
  toolName: string;
}) {
  await agentTaskRef(params.ownerId, params.taskId).set(
    {
      phase: 'validate',
      currentStep: `Running ${params.toolName}`,
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
  await appendAgentTaskEvent({
    ownerId: params.ownerId,
    taskId: params.taskId,
    type: 'tool_started',
    step: `Running ${params.toolName}`,
    message: `Running ${params.toolName} against the latest agent edits.`,
    status: 'running',
    phase: 'validate',
    data: {
      toolName: params.toolName,
    },
  });
}

async function appendAgentValidationToolFinished(params: {
  ownerId: string;
  taskId: string;
  result: AgentValidationToolResult;
}) {
  await appendAgentTaskEvent({
    ownerId: params.ownerId,
    taskId: params.taskId,
    type:
      params.result.status === 'passed'
        ? 'tool_passed'
        : params.result.status === 'skipped'
          ? 'tool_skipped'
          : 'tool_failed',
    step:
      params.result.status === 'passed'
        ? `${params.result.name} passed`
        : params.result.status === 'skipped'
          ? `${params.result.name} skipped`
          : `${params.result.name} failed`,
    message: buildToolRunSummary(params.result),
    status: 'running',
    phase: 'validate',
    data: buildAgentValidationToolEventData(params.result),
  });
}

async function runAgentValidationWorkflowTool(params: {
  ownerId: string;
  taskId: string;
  repoId: string;
  repo: Awaited<ReturnType<typeof ensureRepositoryAccess>>;
  token: string;
  workflow: PlannedValidationWorkflow;
  branchName: string;
}) {
  const checkRef = db.collection('checksRuns').doc();
  await checkRef.set({
    ownerId: params.ownerId,
    repoId: params.repoId,
    provider: 'github',
    actionType:
      params.workflow.workflowCategory === 'lint'
        ? 'run_lint'
        : params.workflow.workflowCategory === 'build'
          ? 'build_project'
          : 'run_tests',
    workflowName: params.workflow.workflowName,
    workflowCategory: params.workflow.workflowCategory,
    ref: params.branchName,
    inputs: {},
    status: 'running',
    executionState: 'running',
    logsUrl: null,
    summary: `Agent dispatched ${params.workflow.workflowName} on ${params.branchName}.`,
    estimatedTokens: 0,
    agentTaskId: params.taskId,
    source: 'agent_validation',
    startedAtMs: Date.now(),
    findings: [],
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  const startedAt = Date.now();
  const remoteResult = await triggerCheckExecution(
    'github',
    params.token,
    {
      owner: params.repo.owner ?? '',
      name: params.repo.name ?? '',
      remoteId: params.repo.remoteId ?? null,
      defaultBranch: params.repo.defaultBranch,
    },
    params.workflow.workflowName,
    params.branchName,
    {},
    params.repo.apiBaseUrl ?? undefined,
  );
  await checkRef.set(
    {
      status: 'running',
      executionState: remoteResult.status,
      logsUrl: remoteResult.logsUrl,
      remoteId: remoteResult.remoteId,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const runResult = await waitForGitHubWorkflowRun({
    token: params.token,
    owner: params.repo.owner ?? '',
    name: params.repo.name ?? '',
    workflowName: params.workflow.workflowName,
    ref: params.branchName,
    dispatchStartedAtMs: startedAt,
    apiBaseUrl: params.repo.apiBaseUrl ?? undefined,
  });
  const passed = runResult.timedOut !== true && runResult.conclusion === 'success';
  const fallbackFindings = [...runResult.failedJobs, ...runResult.failedSteps]
    .slice(0, 8)
    .map<AgentValidationFinding>(message => ({
      severity: 'error',
      source: 'ci_workflow',
      message,
    }));
  const findings =
    runResult.findings.length > 0 ? runResult.findings.slice(0, 12) : fallbackFindings;
  const summary = runResult.timedOut
    ? `${params.workflow.name} did not finish within the validation window on ${params.branchName}.`
    : passed
      ? `${params.workflow.name} passed on ${params.branchName}.`
      : `${params.workflow.name} failed on ${params.branchName}.`;
  await checkRef.set(
    buildCompletedCheckRunPayload({
      summary,
      passed,
      timedOut: runResult.timedOut,
      remoteId: runResult.runId ?? remoteResult.remoteId,
      logsUrl: runResult.htmlUrl ?? remoteResult.logsUrl,
      runStatus: runResult.status,
      runConclusion: runResult.conclusion,
      failureNotes: [...runResult.failedJobs, ...runResult.failedSteps].slice(0, 10),
      findings,
    }),
    { merge: true },
  );
  return {
    id: params.workflow.id,
    kind: 'ci_workflow' as const,
    name: params.workflow.name,
    status: passed ? 'passed' : runResult.timedOut ? 'timed_out' : 'failed',
    summary,
    durationMs: Date.now() - startedAt,
    findings,
    workflowName: params.workflow.workflowName,
    workflowPath: params.workflow.workflowPath,
    workflowCategory: params.workflow.workflowCategory,
    checkRunId: checkRef.id,
    logsUrl: runResult.htmlUrl ?? remoteResult.logsUrl,
    branchName: params.branchName,
    executed: true,
  } satisfies AgentValidationToolResult;
}

async function runAgentValidationToolSuite(params: {
  ownerId: string;
  taskId: string;
  task: AgentTaskDocument;
  validationAttempt: number;
  repoFilesOverride?: WorkingCopyRepoFileRecord[];
  workspaceOverride?: Awaited<ReturnType<typeof materializeEphemeralWorkspace>> | null;
  skipWorkspaceConsistencyCheck?: boolean;
  validationMode?: 'working_copy' | 'sandbox';
}) {
  const results: AgentValidationToolResult[] = [];
  const validationMode = params.validationMode ?? 'working_copy';
  const failureFocusCategory =
    isObject(params.task.metadata) &&
    typeof params.task.metadata.latestFailureCategory === 'string'
      ? params.task.metadata.latestFailureCategory
      : null;

  if (params.skipWorkspaceConsistencyCheck === true) {
    const skippedConsistency = buildSkippedValidationToolResult({
      id: 'workspace_consistency',
      name: 'Workspace consistency',
      kind: 'workspace_consistency',
        summary:
          validationMode === 'sandbox'
          ? 'Workspace consistency is deferred until the validated diff is approved and written into the local workspace.'
          : 'Workspace consistency check was skipped for this validation pass.',
    });
    results.push(skippedConsistency);
    await appendAgentValidationToolFinished({
      ownerId: params.ownerId,
      taskId: params.taskId,
      result: skippedConsistency,
    });
  } else {
    await appendAgentValidationToolStarted({
      ownerId: params.ownerId,
      taskId: params.taskId,
      toolName: 'workspace consistency checks',
    });
    const localStartedAt = Date.now();
    const persistedLocalWorkspace = coerceLocalWorkspaceInfo(params.task.metadata);
    const sessionId = asString(params.task.sessionId, 'task.sessionId');
    const localValidation =
      persistedLocalWorkspace != null && existsSync(persistedLocalWorkspace.workspacePath)
        ? await validateWorkspaceAgainstSessionEdits(
            persistedLocalWorkspace.workspacePath,
            await loadRepoExecutionSessionEdits(params.task.repoId, sessionId),
          )
        : await validateAppliedRepoExecutionSession(params.task.repoId, sessionId);
    const localResult = buildWorkspaceConsistencyResult({
      mismatchedPaths: localValidation.mismatchedPaths,
      durationMs: Date.now() - localStartedAt,
    });
    results.push(localResult);
    await appendAgentValidationToolFinished({
      ownerId: params.ownerId,
      taskId: params.taskId,
      result: localResult,
    });
    if (localResult.status === 'failed') {
      return {
        passed: false,
        summary: summarizeValidationToolResults(results),
        results,
        branchName: null,
      } satisfies AgentValidationToolSuiteResult;
    }
  }

  const persistedLocalWorkspace = coerceLocalWorkspaceInfo(params.task.metadata);
  const localWorkspaceOverride =
    params.workspaceOverride ??
    (persistedLocalWorkspace != null && existsSync(persistedLocalWorkspace.workspacePath)
      ? persistedLocalWorkspace
      : null);
  const seedWorkingCopyFiles =
    params.repoFilesOverride ??
    (localWorkspaceOverride == null
      ? await loadWorkingCopyRepoFiles(params.task.repoId)
      : null);
  const workspace =
    localWorkspaceOverride ??
    (await materializeEphemeralWorkspace({
      ownerId: params.ownerId,
      repoId: params.task.repoId,
      taskId: params.taskId,
      files: (seedWorkingCopyFiles ?? []).map(file => ({
        path: file.path,
        content: file.content,
        isDeleted: file.isDeleted,
      })),
    }));
  const workingCopyFiles =
    params.repoFilesOverride ??
    (localWorkspaceOverride != null
      ? await buildWorkspaceRepoFileRecords(workspace.workspacePath)
      : (seedWorkingCopyFiles ?? await loadWorkingCopyRepoFiles(params.task.repoId)));
  await agentTaskRef(params.ownerId, params.taskId).set(
    {
      metadata: {
        ...(isObject(params.task.metadata) ? params.task.metadata : {}),
        ...(persistedLocalWorkspace != null
          ? serializeLocalWorkspaceInfo(persistedLocalWorkspace)
          : {}),
        ...(validationMode === 'sandbox'
          ? {
              sandboxWorkspacePath: workspace.workspacePath,
              sandboxWorkspaceFileCount: workspace.fileCount,
            }
          : {
              workspacePath: workspace.workspacePath,
              workspaceFileCount: workspace.fileCount,
            }),
      },
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
  await appendAgentValidationToolStarted({
    ownerId: params.ownerId,
    taskId: params.taskId,
    toolName: 'static repo validation',
  });
  const staticResult = runStaticRepoValidations({
    files: workingCopyFiles,
  });
  results.push(staticResult);
  await appendAgentValidationToolFinished({
    ownerId: params.ownerId,
    taskId: params.taskId,
    result: staticResult,
  });
  if (staticResult.status === 'failed') {
    return {
      passed: false,
      summary: summarizeValidationToolResults(results),
      results,
      branchName: null,
    } satisfies AgentValidationToolSuiteResult;
  }

  const localWorkspaceCommands = await detectLocalWorkspaceValidationCommands({
    workspacePath: workspace.workspacePath,
    deepMode: params.task.deepMode,
  });
  const orderedLocalWorkspaceCommands = orderLocalWorkspaceValidationCommands({
    commands: localWorkspaceCommands,
    failureCategory: failureFocusCategory,
    validationAttempt: params.validationAttempt,
  });
  if (localWorkspaceCommands.length === 0) {
    const localCommandResult = buildSkippedValidationToolResult({
      id: 'local_workspace_validation',
      name: 'Local workspace validation',
      kind: 'workspace_command',
      summary:
        'No local workspace command was available in the runtime environment for this repository snapshot.',
    });
    results.push(localCommandResult);
    await appendAgentValidationToolFinished({
      ownerId: params.ownerId,
      taskId: params.taskId,
      result: localCommandResult,
    });
  } else {
    for (const command of orderedLocalWorkspaceCommands) {
      await appendAgentValidationToolStarted({
        ownerId: params.ownerId,
        taskId: params.taskId,
        toolName: command.name,
      });
      void appendStreamLogEntry(params.ownerId, params.taskId, {
        timestampMs: Date.now(),
        type: 'info',
        content: `▶ ${command.name}`,
      });
      const commandResult = await runLocalWorkspaceCommand({
        workspacePath: workspace.workspacePath,
        command,
      });
      void appendStreamLogEntry(params.ownerId, params.taskId, {
        timestampMs: Date.now(),
        type: commandResult.status === 'passed' ? 'stdout' : 'stderr',
        content: commandResult.output.slice(0, 8000),
      });
      const validationResult =
        commandResult.status === 'passed'
          ? buildLocalWorkspaceValidationResult({
              id: command.id,
              name: command.name,
              status: 'passed',
              summary: `${command.name} passed in the ephemeral workspace.`,
              output: commandResult.output,
              durationMs: commandResult.durationMs,
            })
          : commandResult.status === 'skipped'
            ? buildLocalWorkspaceValidationResult({
                id: command.id,
                name: command.name,
                status: 'skipped',
                summary: commandResult.output,
                output: commandResult.output,
                durationMs: commandResult.durationMs,
              })
            : buildLocalWorkspaceValidationResult({
                id: command.id,
                name: command.name,
                status: commandResult.status,
                summary: summarizeToolOutputFailure({
                  commandLabel: command.name,
                  output: commandResult.output,
                  fallbackMessage:
                    commandResult.status === 'timed_out'
                      ? `${command.name} timed out in the ephemeral workspace.`
                      : `${command.name} failed in the ephemeral workspace.`,
                }),
                output: commandResult.output,
                durationMs: commandResult.durationMs,
              });
      results.push(validationResult);
      await appendAgentValidationToolFinished({
        ownerId: params.ownerId,
        taskId: params.taskId,
        result: validationResult,
      });
      if (validationResult.status === 'failed' || validationResult.status === 'timed_out') {
        return {
          passed: false,
          summary: summarizeValidationToolResults(results),
          results,
          branchName: null,
        } satisfies AgentValidationToolSuiteResult;
      }
    }
  }

  const repo = await ensureRepositoryAccess(params.task.repoId, params.ownerId);
  const provider = repo.provider ?? 'github';
  if (provider !== 'github') {
    results.push(
      buildSkippedValidationToolResult({
        id: 'remote_validation',
        name: 'Remote CI validation',
        summary: 'Remote validation runs are currently enabled only for GitHub repositories.',
      }),
    );
    await appendAgentValidationToolFinished({
      ownerId: params.ownerId,
      taskId: params.taskId,
      result: results[results.length - 1]!,
    });
    return {
      passed: true,
      summary: summarizeValidationToolResults(results),
      results,
      branchName: null,
    } satisfies AgentValidationToolSuiteResult;
  }

  const tokenInfo = await resolveProviderToken(params.ownerId, provider);
  if (!tokenInfo) {
    results.push(
      buildSkippedValidationToolResult({
        id: 'remote_validation',
        name: 'Remote CI validation',
        summary: `No ${providerLabel(provider)} token is configured for remote validation.`,
      }),
    );
    await appendAgentValidationToolFinished({
      ownerId: params.ownerId,
      taskId: params.taskId,
      result: results[results.length - 1]!,
    });
    return {
      passed: true,
      summary: summarizeValidationToolResults(results),
      results,
      branchName: null,
    } satisfies AgentValidationToolSuiteResult;
  }

  const workflows = await listGitHubWorkflows(
    tokenInfo.token,
    repo.owner ?? '',
    repo.name ?? '',
    repo.apiBaseUrl ?? undefined,
  );
  const workflowPlan = buildValidationWorkflowPlan({
    workflows,
    prompt: params.task.prompt,
    deepMode: params.task.deepMode,
  });
  const orderedWorkflowPlan = orderValidationWorkflows({
    workflows: workflowPlan,
    failureCategory: failureFocusCategory,
    validationAttempt: params.validationAttempt,
  });
  if (workflowPlan.length === 0) {
    results.push(
      buildSkippedValidationToolResult({
        id: 'remote_validation',
        name: 'Remote CI validation',
        summary: 'No active validation workflow was available for this repository.',
      }),
    );
    await appendAgentValidationToolFinished({
      ownerId: params.ownerId,
      taskId: params.taskId,
      result: results[results.length - 1]!,
    });
    return {
      passed: true,
      summary: summarizeValidationToolResults(results),
      results,
      branchName: null,
    } satisfies AgentValidationToolSuiteResult;
  }

  const branchName = buildAgentValidationBranchName(
    params.taskId,
    params.validationAttempt,
  );
  try {
    if (localWorkspaceOverride != null) {
      const pushResult = await prepareWorkspaceBranchForRemoteGitOps({
        workspacePath: workspace.workspacePath,
        provider,
        token: tokenInfo.token,
        branchName,
        commitMessage: `chore(agent-validation): snapshot task ${params.taskId.slice(0, 8)}`,
        forcePush: true,
      });
      if (!pushResult.committed) {
        results.push(
          buildSkippedValidationToolResult({
            id: 'remote_validation',
            name: 'Remote CI validation',
            summary: pushResult.summary,
          }),
        );
        await appendAgentValidationToolFinished({
          ownerId: params.ownerId,
          taskId: params.taskId,
          result: results[results.length - 1]!,
        });
        return {
          passed: true,
          summary: summarizeValidationToolResults(results),
          results,
          branchName: null,
        } satisfies AgentValidationToolSuiteResult;
      }
    } else {
      const fileChanges = buildDraftFileChangesFromRecords(workingCopyFiles);
      if (fileChanges.length === 0) {
        results.push(
          buildSkippedValidationToolResult({
            id: 'remote_validation',
            name: 'Remote CI validation',
            summary: 'No local workspace changes were available to validate remotely.',
          }),
        );
        await appendAgentValidationToolFinished({
          ownerId: params.ownerId,
          taskId: params.taskId,
          result: results[results.length - 1]!,
        });
        return {
          passed: true,
          summary: summarizeValidationToolResults(results),
          results,
          branchName: null,
        } satisfies AgentValidationToolSuiteResult;
      }
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
        `chore(agent-validation): snapshot task ${params.taskId.slice(0, 8)}`,
        fileChanges,
        repo.apiBaseUrl ?? undefined,
      );
    }
  } catch (error) {
    const message = `Remote validation branch could not be prepared: ${normalizeError(error).message}`;
    results.push(
      buildSkippedValidationToolResult({
        id: 'remote_validation',
        name: 'Remote CI validation',
        summary: message,
      }),
    );
    await appendAgentValidationToolFinished({
      ownerId: params.ownerId,
      taskId: params.taskId,
      result: results[results.length - 1]!,
    });
    return {
      passed: true,
      summary: summarizeValidationToolResults(results),
      results,
      branchName: null,
    } satisfies AgentValidationToolSuiteResult;
  }

  for (const workflow of orderedWorkflowPlan) {
    await appendAgentValidationToolStarted({
      ownerId: params.ownerId,
      taskId: params.taskId,
      toolName: workflow.name,
    });
    const workflowResult = await runAgentValidationWorkflowTool({
      ownerId: params.ownerId,
      taskId: params.taskId,
      repoId: params.task.repoId,
      repo,
      token: tokenInfo.token,
      workflow,
      branchName,
    });
    results.push(workflowResult);
    await appendAgentValidationToolFinished({
      ownerId: params.ownerId,
      taskId: params.taskId,
      result: workflowResult,
    });
    if (workflowResult.status === 'failed' || workflowResult.status === 'timed_out') {
      return {
        passed: false,
        summary: summarizeValidationToolResults(results),
        results,
        branchName,
      } satisfies AgentValidationToolSuiteResult;
    }
  }

  return {
    passed: true,
    summary: summarizeValidationToolResults(results),
    results,
    branchName,
  } satisfies AgentValidationToolSuiteResult;
}

async function generateAndApplyAgentRepairPass(params: {
  ownerId: string;
  taskId: string;
  runToken: number;
  task: AgentTaskDocument;
  failureReason: string;
  failurePaths?: string[];
  failureLocations?: string[];
  failureCategory?: string | null;
  repairTargetPaths?: string[];
  repairStrategyLabel?: string | null;
  repairEscalationLevel?: number;
}) {
  if (params.task.retryCount >= params.task.guardrails.maxRetries) {
    const hardLimitSummary = buildAgentRetryLimitMessage({
      retryCount: params.task.retryCount,
      maxRetries: params.task.guardrails.maxRetries,
      reason: params.failureReason,
      scope: 'validation',
    });
    await markAgentHardLimitReached({
      ownerId: params.ownerId,
      taskId: params.taskId,
      summary: hardLimitSummary,
      type: 'validation',
      retryCount: params.task.retryCount,
      maxRetries: params.task.guardrails.maxRetries,
    });
    return null;
  }
  const taskReference = agentTaskRef(params.ownerId, params.taskId);
  const nextRetryCount = params.task.retryCount + 1;
  const repairStrategyLabel = params.repairStrategyLabel ?? 'targeted_patch';
  const repairEscalationLevel = Math.max(params.repairEscalationLevel ?? 0, 0);
  const repairTargetPaths = buildRepairTargetPaths({
    failurePaths: params.failurePaths,
    priorTouchedPaths:
      params.repairTargetPaths ??
      (params.task.filesTouched.length > 0 ? params.task.filesTouched : undefined),
    currentFilePath: params.task.currentFilePath,
    limit: params.task.deepMode ? 20 : 14,
  });
  await taskReference.set(
    {
      retryCount: nextRetryCount,
      phase: 'generate_diff',
      currentStep: 'Generating repair diff',
      latestValidationError: params.failureReason,
      metadata: {
        ...(isObject(params.task.metadata) ? params.task.metadata : {}),
        failurePaths: params.failurePaths ?? [],
        latestFailureLocations: (params.failureLocations ?? []).slice(0, 12),
        latestFailureCategory: params.failureCategory ?? null,
        repairTargetPaths,
        repairStrategyLabel,
        repairEscalationLevel,
        workspaceSourceOfTruth: 'local_workspace',
      },
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
  await appendAgentTaskEvent({
    ownerId: params.ownerId,
    taskId: params.taskId,
    type: 'retrying',
    step: 'Repairing failed validation',
    message: `Validation failed, so the agent is generating repair pass #${nextRetryCount}.`,
    status: 'running',
    phase: 'generate_diff',
    data: {
      attempt: nextRetryCount,
      reason: truncate(params.failureReason, 500),
      failureCategory: params.failureCategory ?? null,
      failureLocations: (params.failureLocations ?? []).slice(0, 8),
      failingPaths: params.failurePaths ?? [],
      repairTargetPaths,
      repairStrategyLabel,
      repairEscalationLevel,
    },
  });
  const repairPromptTaskSnapshot = await taskReference.get();
  const repairPromptTask = repairPromptTaskSnapshot.exists
    ? safeAgentTask(repairPromptTaskSnapshot.data())
    : params.task;
  const workspace = await ensureAgentTaskLocalWorkspace(
    params.ownerId,
    params.taskId,
    repairPromptTask,
  );
  const workspaceRepoFiles = await buildWorkspaceRepoFileRecords(
    workspace.workspacePath,
  );

  const repoObserver = buildAgentRepoExecutionObserver({
    ownerId: params.ownerId,
    taskId: params.taskId,
  });
  const adaptiveRepairProvider =
    isObject(repairPromptTask.metadata) &&
            typeof repairPromptTask.metadata.requestedProvider === 'string' &&
            isAiProvider(repairPromptTask.metadata.requestedProvider as ProviderName) &&
            repairPromptTask.retryCount === 1 &&
            repairEscalationLevel === 0
      ? (repairPromptTask.metadata.requestedProvider as AiProviderName)
      : null;
  const session = await generateRepoExecutionSession({
    ownerId: params.ownerId,
    repoId: repairPromptTask.repoId,
    prompt: buildAgentRepairPrompt(repairPromptTask, {
      reason: params.failureReason,
      failurePaths: params.failurePaths,
      failureLocations: params.failureLocations,
      failureCategory: params.failureCategory,
      targetPaths: repairTargetPaths,
      workspaceSource: 'local_workspace',
    }),
    currentFilePath: repairPromptTask.currentFilePath ?? undefined,
    deepMode: repairPromptTask.deepMode,
    requestedProvider: adaptiveRepairProvider,
    repairMode: true,
    repairHintPaths: repairTargetPaths,
    targetedEditablePaths: repairTargetPaths,
    observer: repoObserver.observer,
    existingRunMemory: coerceRepoExecutionRunMemory(
      isObject(repairPromptTask.metadata)
        ? repairPromptTask.metadata.executionMemory
        : null,
    ),
    retryCount: nextRetryCount + repairEscalationLevel,
    budgetRemainingRatio: remainingTaskBudgetRatio({
      metadata: repairPromptTask.metadata,
      budget: buildAgentTaskBudgetSnapshot({
        deepMode: repairPromptTask.deepMode,
        maxTokenBudget: repairPromptTask.guardrails.maxTokenBudget,
        maxRetries: repairPromptTask.guardrails.maxRetries,
      }),
    }),
    repoFilesOverride: workspaceRepoFiles,
  });
  await recordLogicalAgentActivity({
    ownerId: params.ownerId,
    taskId: params.taskId,
    role: 'repair',
    state: 'started',
    summary: `Repair worker generated post-apply pass #${nextRetryCount}.`,
    data: {
      executionProvider: session.executionProvider ?? null,
      executionModel: session.executionModel ?? null,
      failingPaths: params.failurePaths ?? [],
      repairTargetPaths,
      repairStrategyLabel,
      repairEscalationLevel,
    },
  });
  await recordAgentCostActivity({
    ownerId: params.ownerId,
    taskId: params.taskId,
    stage: 'repair',
    provider: session.executionProvider ?? null,
    model: session.executionModel ?? null,
    estimatedTokens: session.estimatedTokens,
    summary: `Generated post-apply repair pass #${nextRetryCount}.`,
    retryCount: nextRetryCount,
  });
  await assertAgentTaskStillRunnable(params.ownerId, params.taskId, params.runToken);
  await taskReference.set(
    {
      phase: 'apply_edits',
      currentStep: 'Applying repair diff',
      sessionId: session.sessionId,
      executionSummary: session.summary,
      selectedFiles:
        repoObserver.observed.selectedFiles.length > 0
          ? repoObserver.observed.selectedFiles
          : session.selectedFiles,
      dependencyFiles:
        repoObserver.observed.dependencyFiles.length > 0
          ? repoObserver.observed.dependencyFiles
          : session.dependencyFiles,
      inspectedFiles:
        repoObserver.observed.inspectedFiles.length > 0
          ? repoObserver.observed.inspectedFiles
          : session.selectedFiles,
      filesTouched: session.edits.map(edit => edit.path),
      diffCount: session.edits.length,
      estimatedTokens: session.estimatedTokens,
      metadata: {
        ...(isObject(repairPromptTask.metadata) ? repairPromptTask.metadata : {}),
        repoSizeClass: session.repoSizeClass ?? null,
        contextStrategy: session.contextStrategy ?? null,
        executionMemory: session.executionMemory ?? null,
        executionMemorySummary: session.executionMemorySummary ?? null,
        executionProvider: session.executionProvider ?? null,
        executionModel: session.executionModel ?? null,
        executionProviderReason: session.executionProviderReason ?? null,
        contextPlannerProvider: session.contextPlannerProvider ?? null,
        contextPlannerModel: session.contextPlannerModel ?? null,
        executionPlannerProvider: session.executionPlannerProvider ?? null,
        executionPlannerModel: session.executionPlannerModel ?? null,
        failurePaths: params.failurePaths ?? [],
        latestFailureLocations: (params.failureLocations ?? []).slice(0, 12),
        latestFailureCategory: params.failureCategory ?? null,
        repairTargetPaths,
        repairStrategyLabel,
        repairEscalationLevel,
        workspaceSourceOfTruth: 'local_workspace',
      },
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
  const sessionEdits = await loadRepoExecutionSessionEdits(
    params.task.repoId,
    session.sessionId,
  );
  const appliedPaths = await applyRepoExecutionEditsToLocalWorkspace(
    workspace.workspacePath,
    sessionEdits,
  );
  await taskReference.set(
    {
      filesTouched: appliedPaths,
      metadata: {
        ...(isObject(repairPromptTask.metadata) ? repairPromptTask.metadata : {}),
        ...serializeLocalWorkspaceInfo(workspace),
        appliedChanges: true,
        repairPassApplied: true,
        repairTargetPaths,
        repairStrategyLabel,
        repairEscalationLevel,
        workspaceSourceOfTruth: 'local_workspace',
      },
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
  await appendAgentTaskEvent({
    ownerId: params.ownerId,
    taskId: params.taskId,
    type: 'edits_applied',
    step: 'Repair diff applied',
    message: `Applied ${appliedPaths.length} repair file change${appliedPaths.length === 1 ? '' : 's'} to the local workspace.`,
    status: 'running',
    phase: 'apply_edits',
    data: {
      filesTouched: appliedPaths,
      retryCount: nextRetryCount,
      repairTargetPaths,
      repairStrategyLabel,
      repairEscalationLevel,
    },
  });
  await recordLogicalAgentActivity({
    ownerId: params.ownerId,
    taskId: params.taskId,
    role: 'repair',
    state: 'handoff',
    summary: 'Repair worker reapplied the latest patch and returned the task to validation.',
    data: {
      retryCount: nextRetryCount,
      filesTouched: appliedPaths,
      repairStrategyLabel,
      repairEscalationLevel,
    },
  });
  const updatedSnapshot = await taskReference.get();
  return updatedSnapshot.exists ? safeAgentTask(updatedSnapshot.data()) : null;
}

async function validateAndRepairAgentTask(params: {
  ownerId: string;
  taskId: string;
  runToken: number;
}) {
  const taskReference = agentTaskRef(params.ownerId, params.taskId);
  let task = await assertAgentTaskStillRunnable(params.ownerId, params.taskId, params.runToken);
  let validationAttempt =
    isObject(task.metadata) && typeof task.metadata.validationAttemptCount === 'number'
      ? task.metadata.validationAttemptCount
      : 0;

  while (true) {
    task = await assertAgentTaskStillRunnable(params.ownerId, params.taskId, params.runToken);
    const sessionId = asOptionalString(task.sessionId);
    if (!sessionId) {
      throw new HttpsError('failed-precondition', 'Task has no execution session to validate.');
    }
    validationAttempt += 1;
    await taskReference.set(
      {
        phase: 'validate',
        currentStep: `Validation pass ${validationAttempt}`,
        updatedAtMs: Date.now(),
      },
      { merge: true },
    );
    await appendAgentTaskEvent({
      ownerId: params.ownerId,
      taskId: params.taskId,
      type: 'validation_started',
      step: 'Validating applied edits',
      message: 'Running workspace, static, and remote validation tools against the latest agent edits.',
      status: 'running',
      phase: 'validate',
      data: {
        attempt: validationAttempt,
        maxRetries: task.guardrails.maxRetries,
      },
    });
    await recordLogicalAgentActivity({
      ownerId: params.ownerId,
      taskId: params.taskId,
      role: 'validator',
      state: 'started',
      summary: `Validator worker is running post-apply pass ${validationAttempt}.`,
      data: {
        validationAttempt,
        sessionId,
      },
    });
    const validationTool = getAgentToolDefinition('validation_suite');
    const { value: validation, execution: validationExecution } = await executeAgentTool({
      tool: validationTool,
      run: () =>
        runAgentValidationToolSuite({
          ownerId: params.ownerId,
          taskId: params.taskId,
          task,
          validationAttempt,
        }),
      summarizeSuccess: result => result.summary,
      metadataFromSuccess: result => ({
        passed: result.passed,
        branchName: result.branchName,
        resultCount: result.results.length,
      }),
    });
    const validationMetadata = buildAgentValidationMetadata({
      existingMetadata: appendAgentToolExecutionToMetadata(
        isObject(task.metadata) ? task.metadata : null,
        validationExecution,
      ),
      attempt: validationAttempt,
      passed: validation.passed,
      summary: validation.summary,
      results: validation.results,
      branchName: validation.branchName,
      retryCount: task.retryCount,
    });
    const failureInsights = buildValidationFailureInsights(validation.results);
    const failureState = buildRepairFailureState({
      task,
      validationAttempt,
      validationMode: 'working_copy',
      failureInsights,
      summary: validation.summary,
    });
    if (!validation.passed) {
      await recordLogicalAgentActivity({
        ownerId: params.ownerId,
        taskId: params.taskId,
        role: 'validator',
        state: 'handoff',
        summary: `Validator worker handed post-apply failures to repair after pass ${validationAttempt}.`,
        data: {
          validationAttempt,
          failingPaths: failureInsights.failurePaths,
          failureCategory: failureInsights.failureCategory,
          failureLocations: failureInsights.failureLocations.slice(0, 6),
          repairTargetPaths: failureState.repairTargetPaths,
          repairStrategyLabel: failureState.repairStrategyLabel,
          repairEscalationLevel: failureState.repairEscalationLevel,
          summary: validation.summary,
        },
      });
      await taskReference.set(
        {
          latestValidationError: validation.summary,
          metadata: {
            ...validationMetadata,
            ...failureState.metadataPatch,
            failurePaths: failureInsights.failurePaths,
          },
          updatedAtMs: Date.now(),
        },
        { merge: true },
      );
      await writeOperationalMetric({
        operation: 'agent_repair_failure',
        status: failureState.repeatedSignatureCount > 0 ? 'warning' : 'failure',
        ownerId: params.ownerId,
        repoId: task.repoId,
        provider:
          isObject(task.metadata) &&
          typeof task.metadata.executionProvider === 'string'
            ? (task.metadata.executionProvider as ProviderName)
            : undefined,
        metadata: {
          taskId: params.taskId,
          validationMode: 'working_copy',
          validationAttempt,
          failureCategory: failureInsights.failureCategory,
          failureSignature: failureState.failureSignature,
          repeatedSignatureCount: failureState.repeatedSignatureCount + 1,
          repeatedCategoryCount: failureState.repeatedCategoryCount + 1,
          repairStrategyLabel: failureState.repairStrategyLabel,
          repairEscalationLevel: failureState.repairEscalationLevel,
          repairTargetCount: failureState.repairTargetPaths.length,
          repairQualityMetrics:
            isObject(failureState.metadataPatch.repairQualityMetrics)
              ? failureState.metadataPatch.repairQualityMetrics
              : null,
        },
      });
      await appendAgentTaskEvent({
        ownerId: params.ownerId,
        taskId: params.taskId,
        type: 'validation_failed',
        step: 'Validation failed',
        message: validation.summary,
        status: 'running',
        phase: 'validate',
        data: {
          attempt: validationAttempt,
          branchName: validation.branchName,
          failingPaths: failureInsights.failurePaths,
          failureCategory: failureInsights.failureCategory,
          failureLocations: failureInsights.failureLocations,
          repairTargetPaths: failureState.repairTargetPaths,
          repairStrategyLabel: failureState.repairStrategyLabel,
          repairEscalationLevel: failureState.repairEscalationLevel,
          results: serializeValidationToolResults(validation.results),
        },
      });
      const repairedTask = await generateAndApplyAgentRepairPass({
        ownerId: params.ownerId,
        taskId: params.taskId,
        runToken: params.runToken,
        task,
        failureReason: buildAgentValidationFailurePrompt(validation.results),
        failurePaths: failureInsights.failurePaths,
        failureLocations: failureInsights.failureLocations,
        failureCategory: failureInsights.failureCategory,
        repairTargetPaths: failureState.repairTargetPaths,
        repairStrategyLabel: failureState.repairStrategyLabel,
        repairEscalationLevel: failureState.repairEscalationLevel,
      });
      if (!repairedTask) {
        const hardLimitSummary = buildAgentRetryLimitMessage({
          retryCount: task.retryCount,
          maxRetries: task.guardrails.maxRetries,
          reason: validation.summary,
          scope: 'validation',
        });
        return {
          ok: false,
          message: hardLimitSummary,
        };
      }
      task = repairedTask;
      continue;
    }

    await taskReference.set(
      {
        latestValidationError: null,
        metadata: {
          ...validationMetadata,
          failurePaths: [],
          latestFailureSignature: null,
          latestFailureLocations: [],
          latestFailureCategory: null,
          repairTargetPaths: [],
          repeatedFailureDetected: false,
          repeatedFailureSignatureCount: 0,
          repeatedFailureCategoryCount: 0,
          repairStrategyLabel: null,
          repairEscalationLevel: 0,
        },
        updatedAtMs: Date.now(),
      },
      { merge: true },
    );
    await writeOperationalMetric({
      operation: 'agent_repair_success',
      status: 'success',
      ownerId: params.ownerId,
      repoId: task.repoId,
      provider:
        isObject(task.metadata) &&
        typeof task.metadata.executionProvider === 'string'
          ? (task.metadata.executionProvider as ProviderName)
          : undefined,
      metadata: {
        taskId: params.taskId,
        validationMode: 'working_copy',
        validationAttempt,
        repairAttemptCount: task.retryCount,
        repairQualityMetrics:
          isObject(validationMetadata.repairQualityMetrics)
            ? validationMetadata.repairQualityMetrics
            : null,
      },
    });
    await recordLogicalAgentActivity({
      ownerId: params.ownerId,
      taskId: params.taskId,
      role: 'validator',
      state: 'completed',
      summary: `Validator worker cleared post-apply pass ${validationAttempt}.`,
      data: {
        validationAttempt,
        branchName: validation.branchName,
      },
    });
    await appendAgentTaskEvent({
      ownerId: params.ownerId,
      taskId: params.taskId,
      type: 'validation_passed',
      step: 'Validation passed',
      message: validation.summary,
      status: 'running',
      phase: 'validate',
      data: {
        attempt: validationAttempt,
        branchName: validation.branchName,
        results: serializeValidationToolResults(validation.results),
      },
    });
    return {
      ok: true,
      task,
      message: validation.summary,
    };
  }
}

async function validateGeneratedSessionBeforeApproval(params: {
  ownerId: string;
  taskId: string;
  runToken: number;
  task: AgentTaskDocument;
  session: RepoExecutionSessionResult;
  repoObserver: ReturnType<typeof buildAgentRepoExecutionObserver>;
}): Promise<
  | {
      ok: true;
      session: RepoExecutionSessionResult;
      validation: AgentValidationToolSuiteResult;
    }
  | {
      ok: false;
      message: string;
    }
> {
  const taskReference = agentTaskRef(params.ownerId, params.taskId);
  let task = params.task;
  let session = params.session;
  let validationAttempt = 0;

  while (true) {
    task = await assertAgentTaskStillRunnable(params.ownerId, params.taskId, params.runToken);
    validationAttempt += 1;
    const { baseWorkspace, sandboxWorkspace } = await createAgentSandboxWorkspace({
      ownerId: params.ownerId,
      taskId: params.taskId,
      task,
      validationAttempt,
    });
    await applyRepoExecutionEditsToLocalWorkspace(sandboxWorkspace.workspacePath, session.edits);
    const candidateFiles = await buildWorkspaceRepoFileRecords(sandboxWorkspace.workspacePath);
    await taskReference.set(
      {
        phase: 'validate',
        currentStep: `Validating sandbox workspace (pass ${validationAttempt})`,
        sessionId: session.sessionId,
        executionSummary: session.summary,
        selectedFiles:
          params.repoObserver.observed.selectedFiles.length > 0
            ? params.repoObserver.observed.selectedFiles
            : session.selectedFiles,
        dependencyFiles:
          params.repoObserver.observed.dependencyFiles.length > 0
            ? params.repoObserver.observed.dependencyFiles
            : session.dependencyFiles,
        inspectedFiles:
          params.repoObserver.observed.inspectedFiles.length > 0
            ? params.repoObserver.observed.inspectedFiles
            : session.selectedFiles,
        filesTouched: session.edits.map(edit => edit.path),
        diffCount: session.edits.length,
        estimatedTokens: session.estimatedTokens,
        metadata: {
          ...(isObject(task.metadata) ? task.metadata : {}),
          repoSizeClass: session.repoSizeClass ?? null,
          contextStrategy: session.contextStrategy ?? null,
          executionMemory: session.executionMemory ?? null,
          executionMemorySummary: session.executionMemorySummary ?? null,
          executionProvider: session.executionProvider ?? null,
          executionModel: session.executionModel ?? null,
          executionProviderReason: session.executionProviderReason ?? null,
          contextPlannerProvider: session.contextPlannerProvider ?? null,
          contextPlannerModel: session.contextPlannerModel ?? null,
          executionPlannerProvider: session.executionPlannerProvider ?? null,
          executionPlannerModel: session.executionPlannerModel ?? null,
          ...serializeLocalWorkspaceInfo(baseWorkspace),
          workspaceSourceOfTruth: 'sandbox_workspace',
          sandboxWorkspacePath: sandboxWorkspace.workspacePath,
          sandboxWorkspaceFileCount: sandboxWorkspace.fileCount,
        },
        updatedAtMs: Date.now(),
      },
      { merge: true },
    );
    await persistExecutionMemorySnapshot({
      db,
      ownerId: params.ownerId,
      taskId: params.taskId,
      repoId: task.repoId,
      phase: 'sandbox_validate',
      summary: session.executionMemorySummary ?? session.summary,
      memory: coerceRepoExecutionRunMemory(session.executionMemory),
    });
    await appendAgentTaskEvent({
      ownerId: params.ownerId,
      taskId: params.taskId,
      type: 'validation_started',
      step: 'Validating sandbox workspace',
      message:
        'Running validation tools against a sandboxed workspace before asking for approval.',
      status: 'running',
      phase: 'validate',
      data: {
        attempt: validationAttempt,
        diffCount: session.edits.length,
        estimatedTokens: session.estimatedTokens,
        baseWorkspacePath: baseWorkspace.workspacePath,
        workspacePath: sandboxWorkspace.workspacePath,
      },
    });
    await recordLogicalAgentActivity({
      ownerId: params.ownerId,
      taskId: params.taskId,
      role: 'validator',
      state: 'started',
      summary: `Validator worker is running sandbox pass ${validationAttempt}.`,
      data: {
        validationAttempt,
        sessionId: session.sessionId,
        sandboxWorkspacePath: sandboxWorkspace.workspacePath,
      },
    });

    const validationTool = getAgentToolDefinition('validation_suite');
    const { value: validation, execution: validationExecution } = await executeAgentTool({
      tool: validationTool,
      run: () =>
        runAgentValidationToolSuite({
          ownerId: params.ownerId,
          taskId: params.taskId,
          task,
          validationAttempt,
          repoFilesOverride: candidateFiles,
          workspaceOverride: sandboxWorkspace,
          skipWorkspaceConsistencyCheck: true,
          validationMode: 'sandbox',
        }),
      summarizeSuccess: result => result.summary,
      metadataFromSuccess: result => ({
        passed: result.passed,
        branchName: result.branchName,
        resultCount: result.results.length,
        mode: 'sandbox',
      }),
    });
    const validationMetadata = buildAgentValidationMetadata({
      existingMetadata: appendAgentToolExecutionToMetadata(
        isObject(task.metadata) ? task.metadata : null,
        validationExecution,
      ),
      attempt: validationAttempt,
      passed: validation.passed,
      summary: validation.summary,
      results: validation.results,
      branchName: validation.branchName,
      retryCount: task.retryCount,
    });
    const failureInsights = buildValidationFailureInsights(validation.results);
    const failureState = buildRepairFailureState({
      task,
      validationAttempt,
      validationMode: 'sandbox',
      failureInsights,
      summary: validation.summary,
    });

    if (!validation.passed) {
      await recordLogicalAgentActivity({
        ownerId: params.ownerId,
        taskId: params.taskId,
        role: 'validator',
        state: 'handoff',
        summary: `Validator worker handed failure analysis to repair after sandbox pass ${validationAttempt}.`,
        data: {
          validationAttempt,
          failingPaths: failureInsights.failurePaths,
          failureCategory: failureInsights.failureCategory,
          failureLocations: failureInsights.failureLocations.slice(0, 6),
          repairTargetPaths: failureState.repairTargetPaths,
          repairStrategyLabel: failureState.repairStrategyLabel,
          repairEscalationLevel: failureState.repairEscalationLevel,
          summary: validation.summary,
        },
      });
      await taskReference.set(
        {
          latestValidationError: validation.summary,
          metadata: {
            ...validationMetadata,
            ...failureState.metadataPatch,
            failurePaths: failureInsights.failurePaths,
            preApplyValidationPassed: false,
            preApplyValidationSummary: validation.summary,
            preApplyValidatedSessionId: null,
            preApplyValidationBranch: validation.branchName,
            sandboxWorkspacePath: sandboxWorkspace.workspacePath,
            sandboxWorkspaceFileCount: sandboxWorkspace.fileCount,
          },
          updatedAtMs: Date.now(),
        },
        { merge: true },
      );
      await writeOperationalMetric({
        operation: 'agent_repair_failure',
        status: failureState.repeatedSignatureCount > 0 ? 'warning' : 'failure',
        ownerId: params.ownerId,
        repoId: task.repoId,
        provider:
          isObject(task.metadata) &&
          typeof task.metadata.executionProvider === 'string'
            ? (task.metadata.executionProvider as ProviderName)
            : undefined,
        metadata: {
          taskId: params.taskId,
          validationMode: 'sandbox',
          validationAttempt,
          failureCategory: failureInsights.failureCategory,
          failureSignature: failureState.failureSignature,
          repeatedSignatureCount: failureState.repeatedSignatureCount + 1,
          repeatedCategoryCount: failureState.repeatedCategoryCount + 1,
          repairStrategyLabel: failureState.repairStrategyLabel,
          repairEscalationLevel: failureState.repairEscalationLevel,
          repairTargetCount: failureState.repairTargetPaths.length,
          repairQualityMetrics:
            isObject(failureState.metadataPatch.repairQualityMetrics)
              ? failureState.metadataPatch.repairQualityMetrics
              : null,
        },
      });
      await appendAgentTaskEvent({
        ownerId: params.ownerId,
        taskId: params.taskId,
        type: 'validation_failed',
        step: 'Sandbox validation failed',
        message: validation.summary,
        status: 'running',
        phase: 'validate',
        data: {
          attempt: validationAttempt,
          branchName: validation.branchName,
          failingPaths: failureInsights.failurePaths,
          failureCategory: failureInsights.failureCategory,
          failureLocations: failureInsights.failureLocations,
          repairTargetPaths: failureState.repairTargetPaths,
          repairStrategyLabel: failureState.repairStrategyLabel,
          repairEscalationLevel: failureState.repairEscalationLevel,
          results: serializeValidationToolResults(validation.results),
          mode: 'sandbox',
        },
      });
      if (task.retryCount >= task.guardrails.maxRetries) {
        const hardLimitSummary = buildAgentRetryLimitMessage({
          retryCount: task.retryCount,
          maxRetries: task.guardrails.maxRetries,
          reason: validation.summary,
          scope: 'validation',
        });
        await markAgentHardLimitReached({
          ownerId: params.ownerId,
          taskId: params.taskId,
          summary: hardLimitSummary,
          type: 'validation',
          retryCount: task.retryCount,
          maxRetries: task.guardrails.maxRetries,
        });
        return {
          ok: false,
          message: hardLimitSummary,
        };
      }

      const nextRetryCount = task.retryCount + 1;
      await taskReference.set(
        {
          retryCount: nextRetryCount,
          phase: 'generate_diff',
          currentStep: 'Repairing sandbox validation failure',
          latestValidationError: validation.summary,
          updatedAtMs: Date.now(),
        },
        { merge: true },
      );
      await appendAgentTaskEvent({
        ownerId: params.ownerId,
        taskId: params.taskId,
        type: 'retrying',
        step: 'Repairing sandbox validation failure',
        message:
          `Sandbox validation failed, so the agent is generating repair pass #${nextRetryCount} before approval.`,
        status: 'running',
        phase: 'generate_diff',
        data: {
          attempt: nextRetryCount,
          reason: truncate(validation.summary, 500),
          failingPaths: failureInsights.failurePaths,
          failureCategory: failureInsights.failureCategory,
          failureLocations: failureInsights.failureLocations.slice(0, 6),
          repairTargetPaths: failureState.repairTargetPaths,
        },
      });
      const repairPromptTaskSnapshot = await taskReference.get();
      const repairPromptTask = repairPromptTaskSnapshot.exists
        ? safeAgentTask(repairPromptTaskSnapshot.data())
        : task;
      session = await generateRepoExecutionSession({
        ownerId: params.ownerId,
        repoId: repairPromptTask.repoId,
        prompt: buildAgentRepairPrompt(repairPromptTask, {
          reason: buildAgentValidationFailurePrompt(validation.results),
          failurePaths: failureInsights.failurePaths,
          failureLocations: failureInsights.failureLocations,
          failureCategory: failureInsights.failureCategory,
          targetPaths: failureState.repairTargetPaths,
          workspaceSource: 'sandbox_workspace',
        }),
        currentFilePath: repairPromptTask.currentFilePath ?? undefined,
        deepMode: repairPromptTask.deepMode,
        requestedProvider:
          isObject(repairPromptTask.metadata) &&
                  typeof repairPromptTask.metadata.executionProvider === 'string' &&
                  isAiProvider(repairPromptTask.metadata.executionProvider as ProviderName) &&
                  repairPromptTask.retryCount === 1 &&
                  failureState.repairEscalationLevel === 0
            ? (repairPromptTask.metadata.executionProvider as AiProviderName)
            : null,
        repairMode: true,
        repairHintPaths: failureState.repairTargetPaths,
        targetedEditablePaths: failureState.repairTargetPaths,
        repoFilesOverride: candidateFiles,
        observer: params.repoObserver.observer,
        existingRunMemory:
          session.executionMemory ??
          coerceRepoExecutionRunMemory(
            isObject(repairPromptTask.metadata)
              ? repairPromptTask.metadata.executionMemory
              : null,
          ),
        budgetRemainingRatio: remainingTaskBudgetRatio({
          metadata: repairPromptTask.metadata,
          budget: buildAgentTaskBudgetSnapshot({
            deepMode: repairPromptTask.deepMode,
            maxTokenBudget: repairPromptTask.guardrails.maxTokenBudget,
            maxRetries: repairPromptTask.guardrails.maxRetries,
          }),
        }),
        retryCount: nextRetryCount + failureState.repairEscalationLevel,
      });
      await recordLogicalAgentActivity({
        ownerId: params.ownerId,
        taskId: params.taskId,
        role: 'repair',
        state: 'started',
        summary: `Repair worker generated sandbox fix pass #${nextRetryCount}.`,
        data: {
          validationAttempt,
          executionProvider: session.executionProvider ?? null,
          executionModel: session.executionModel ?? null,
          failingPaths: failureInsights.failurePaths,
          repairTargetPaths: failureState.repairTargetPaths,
          repairStrategyLabel: failureState.repairStrategyLabel,
          repairEscalationLevel: failureState.repairEscalationLevel,
        },
      });
      await recordAgentCostActivity({
        ownerId: params.ownerId,
        taskId: params.taskId,
        stage: 'repair',
        provider: session.executionProvider ?? null,
        model: session.executionModel ?? null,
        estimatedTokens: session.estimatedTokens,
        summary: `Generated sandbox repair pass #${nextRetryCount}.`,
        retryCount: nextRetryCount,
      });
      const refreshedTaskSnapshot = await taskReference.get();
      if (refreshedTaskSnapshot.exists) {
        task = safeAgentTask(refreshedTaskSnapshot.data());
      }
      continue;
    }

    await taskReference.set(
      {
        latestValidationError: null,
        metadata: {
          ...validationMetadata,
          failurePaths: [],
          latestFailureSignature: null,
          latestFailureLocations: [],
          latestFailureCategory: null,
          repairTargetPaths: [],
          repeatedFailureDetected: false,
          repeatedFailureSignatureCount: 0,
          repeatedFailureCategoryCount: 0,
          repairStrategyLabel: null,
          repairEscalationLevel: 0,
          preApplyValidationPassed: true,
          preApplyValidationSummary: validation.summary,
          preApplyValidatedSessionId: session.sessionId,
          preApplyValidationBranch: validation.branchName,
          sandboxWorkspacePath: sandboxWorkspace.workspacePath,
          sandboxWorkspaceFileCount: sandboxWorkspace.fileCount,
          workspaceSourceOfTruth: 'sandbox_workspace',
        },
        updatedAtMs: Date.now(),
      },
      { merge: true },
    );
    await writeOperationalMetric({
      operation: 'agent_repair_success',
      status: 'success',
      ownerId: params.ownerId,
      repoId: task.repoId,
      provider:
        isObject(task.metadata) &&
        typeof task.metadata.executionProvider === 'string'
          ? (task.metadata.executionProvider as ProviderName)
          : undefined,
      metadata: {
        taskId: params.taskId,
        validationMode: 'sandbox',
        validationAttempt,
        repairAttemptCount: task.retryCount,
        repairQualityMetrics:
          isObject(validationMetadata.repairQualityMetrics)
            ? validationMetadata.repairQualityMetrics
            : null,
      },
    });
    await recordLogicalAgentActivity({
      ownerId: params.ownerId,
      taskId: params.taskId,
      role: 'validator',
      state: 'completed',
      summary: `Validator worker cleared sandbox pass ${validationAttempt}.`,
      data: {
        validationAttempt,
        branchName: validation.branchName,
        summary: validation.summary,
      },
    });
    await appendAgentTaskEvent({
      ownerId: params.ownerId,
      taskId: params.taskId,
      type: 'validation_passed',
      step: 'Sandbox validation passed',
      message:
        'The agent validated the candidate workspace before approval and is ready for final review.',
      status: 'running',
      phase: 'validate',
      data: {
        attempt: validationAttempt,
        branchName: validation.branchName,
        results: serializeValidationToolResults(validation.results),
        mode: 'sandbox',
      },
    });
    return {
      ok: true,
      session,
      validation,
    };
  }
}

async function resolveApprovedAgentTaskContinuation(
  ownerId: string,
  taskId: string,
  runToken: number,
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
        message: 'Approval received. Applying the generated edits to the local workspace.',
        status: 'running',
        phase: 'apply_edits',
      });
      const sessionId = asOptionalString(task.sessionId);
      if (!sessionId) {
        throw new HttpsError('failed-precondition', 'Task has no execution session to apply.');
      }
      const sessionEdits = await loadRepoExecutionSessionEdits(task.repoId, sessionId);
      await taskReference.set(
        {
          pendingApproval: null,
          phase: 'apply_edits',
          currentStep: 'Applying approved edits',
          updatedAtMs: now,
        },
        { merge: true },
      );
      const { value: appliedPaths, execution } = await runAgentToolWithEvents({
        ownerId,
        taskId,
        phase: 'apply_edits',
        toolName: 'apply_working_copy',
        startStep: 'Applying approved edits',
        startMessage: 'Writing the approved diff into the local task workspace.',
        run: async () => {
          const workspace = await ensureAgentTaskLocalWorkspace(ownerId, taskId, task);
          return applyRepoExecutionEditsToLocalWorkspace(workspace.workspacePath, sessionEdits);
        },
        summarizeSuccess: paths =>
          `Applied ${paths.length} file change${paths.length === 1 ? '' : 's'} to the local workspace.`,
        metadataFromSuccess: paths => ({
          fileCount: paths.length,
          paths: paths.slice(0, 40),
        }),
      });
      const localWorkspace = await ensureAgentTaskLocalWorkspace(ownerId, taskId, task);
      await taskReference.set(
        {
          filesTouched: appliedPaths,
          metadata: {
            ...appendAgentToolExecutionToMetadata(
              isObject(task.metadata) ? task.metadata : null,
              execution,
            ),
            ...serializeLocalWorkspaceInfo(localWorkspace),
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
        step: 'Local workspace updated',
        message: `Applied ${appliedPaths.length} file change${appliedPaths.length === 1 ? '' : 's'} to the local workspace.`,
        status: 'running',
        phase: 'apply_edits',
        data: {
          filesTouched: appliedPaths,
        },
      });
      const preApplyValidatedSessionId =
        isObject(task.metadata) && typeof task.metadata.preApplyValidatedSessionId === 'string'
          ? task.metadata.preApplyValidatedSessionId.trim()
          : null;
      const preApplyValidationPassed =
        isObject(task.metadata) &&
        task.metadata.preApplyValidationPassed === true &&
        preApplyValidatedSessionId != null &&
        preApplyValidatedSessionId === sessionId;
      if (preApplyValidationPassed) {
        const consistency = await validateWorkspaceAgainstSessionEdits(
          localWorkspace.workspacePath,
          sessionEdits,
        );
        if (!consistency.ok) {
          const mismatchSummary =
            consistency.mismatchedPaths.length === 0
              ? 'The applied local workspace no longer matches the validated diff.'
              : `The applied local workspace no longer matches the validated diff for ${consistency.mismatchedPaths.join(', ')}.`;
          await failAgentTaskNow(ownerId, taskId, mismatchSummary);
          return;
        }
        await taskReference.set(
          {
            latestValidationError: null,
            metadata: {
              ...(isObject(task.metadata) ? task.metadata : {}),
              postApplyConsistencyPassed: true,
              postApplyValidatedSessionId: sessionId,
            },
            updatedAtMs: Date.now(),
          },
          { merge: true },
        );
        await appendAgentTaskEvent({
          ownerId,
          taskId,
          type: 'validation_passed',
          step: 'Applied workspace confirmed',
          message:
            'The diff already passed sandbox validation before approval, and the applied local workspace still matches that validated result.',
          status: 'running',
          phase: 'validate',
          data: {
            mode: 'post_apply_consistency',
            sessionId,
          },
        });
        await stageNextAgentFollowUpOrComplete(ownerId, taskId);
        return;
      }
      const validation = await validateAndRepairAgentTask({
        ownerId,
        taskId,
        runToken,
      });
      if (!validation.ok) {
        await failAgentTaskNow(ownerId, taskId, validation.message);
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
        message: 'Creating a remote commit from the approved local workspace.',
        status: 'running',
        phase: 'follow_up',
      });
      const { value: result, execution } = await runAgentToolWithEvents({
        ownerId,
        taskId,
        phase: 'follow_up',
        toolName: 'commit_working_copy',
        startStep: 'Committing workspace changes',
        startMessage: 'Creating a remote commit from the approved local workspace.',
        run: () => executeAgentCommitFollowUp(ownerId, taskId, task),
        summarizeSuccess: value => value.summary,
        metadataFromSuccess: value => ({
          remoteId: value.remoteId,
          remoteUrl: value.remoteUrl,
        }),
      });
      await taskReference.set(
        {
          pendingApproval: null,
          metadata: {
            ...appendAgentToolExecutionToMetadata(
              isObject(task.metadata) ? task.metadata : null,
              execution,
            ),
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
        message: 'Creating a branch, pushing the approved local workspace, and opening a pull request.',
        status: 'running',
        phase: 'follow_up',
      });
      const { value: result, execution } = await runAgentToolWithEvents({
        ownerId,
        taskId,
        phase: 'follow_up',
        toolName: 'open_pull_request',
        startStep: 'Opening a pull request',
        startMessage: 'Creating a branch, pushing the approved local workspace, and opening a pull request.',
        run: () => executeAgentPullRequestFollowUp(ownerId, taskId, task),
        summarizeSuccess: value => value.summary,
        metadataFromSuccess: value => ({
          remoteId: value.remoteId,
          remoteUrl: value.remoteUrl,
          branchName: value.branchName,
          pullRequestNumber: value.pullRequestNumber,
        }),
      });
      await taskReference.set(
        {
          pendingApproval: null,
          metadata: {
            ...appendAgentToolExecutionToMetadata(
              isObject(task.metadata) ? task.metadata : null,
              execution,
            ),
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
      const { value: result, execution } = await runAgentToolWithEvents({
        ownerId,
        taskId,
        phase: 'follow_up',
        toolName: 'merge_pull_request',
        startStep: 'Merging pull request',
        startMessage: `Merging pull request #${pullRequestNumber}.`,
        run: () => executeAgentMergeFollowUp(ownerId, task, pullRequestNumber),
        summarizeSuccess: value => value.summary,
        metadataFromSuccess: value => ({
          remoteUrl: value.remoteUrl,
          pullRequestNumber,
        }),
      });
      await taskReference.set(
        {
          pendingApproval: null,
          metadata: {
            ...appendAgentToolExecutionToMetadata(
              isObject(task.metadata) ? task.metadata : null,
              execution,
            ),
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
      const { value: result, execution } = await runAgentToolWithEvents({
        ownerId,
        taskId,
        phase: 'follow_up',
        toolName: 'trigger_deploy',
        startStep: 'Dispatching deploy workflow',
        startMessage: 'Triggering the deployment workflow after user approval.',
        run: () => executeAgentDeployFollowUp(ownerId, task),
        summarizeSuccess: value => value.summary,
        metadataFromSuccess: value => ({
          remoteId: value.remoteId,
          remoteUrl: value.remoteUrl,
        }),
      });
      await taskReference.set(
        {
          pendingApproval: null,
          metadata: {
            ...appendAgentToolExecutionToMetadata(
              isObject(task.metadata) ? task.metadata : null,
              execution,
            ),
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

// ---------------------------------------------------------------------------
// Conversational prompt short-circuit
// ---------------------------------------------------------------------------
// Detects prompts that are greetings, small-talk, or general questions with
// no code intent and responds with a lightweight AI call instead of spinning
// up the full repo-inspection pipeline.

const CONVERSATIONAL_PATTERNS: RegExp[] = [
  // Greetings / small-talk
  /^\s*(hi|hello|hey|yo|sup|howdy|hiya|what'?s? up|good (morning|afternoon|evening))\s*[!?.]*\s*$/i,
  // Single-word / very short non-code prompts
  /^\s*(thanks|thank you|ok|okay|cool|sure|yes|no|nope|yep|bye|goodbye)\s*[!?.]*\s*$/i,
  // "Who are you" / identity questions
  /^\s*(who|what) are you\s*\??\s*$/i,
  // "How are you" / wellbeing
  /^\s*how (are|r) (you|u)\s*\??\s*$/i,
  // "Can you help me" without specifics
  /^\s*can you help( me)?\s*\??\s*$/i,
  // "What can you do" / capability questions
  /^\s*what (can|do) you do\s*\??\s*$/i,
];

function isConversationalPrompt(prompt: string): boolean {
  const trimmed = prompt.trim();
  // Very short prompts (≤ 12 chars) with no code indicators are likely conversational.
  if (trimmed.length <= 12 && !/[{}<>()=;/\\|`]/.test(trimmed)) {
    return CONVERSATIONAL_PATTERNS.some(pattern => pattern.test(trimmed));
  }
  return CONVERSATIONAL_PATTERNS.some(pattern => pattern.test(trimmed));
}

async function handleConversationalPrompt(
  ownerId: string,
  taskId: string,
  prompt: string,
): Promise<boolean> {
  if (!isConversationalPrompt(prompt)) {
    return false;
  }
  // Pick the cheapest available provider for the lightweight reply.
  const lightProvider: AiProviderName =
    lookupProviderToken('anthropic') ? 'anthropic'
      : lookupProviderToken('openai') ? 'openai'
        : 'gemini';

  let replyText: string;
  try {
    const result = await callProviderTextCompletion({
      provider: lightProvider,
      systemPrompt:
        'You are ForgeAI, a mobile AI Git client that helps users review, edit, and ship code. ' +
        'The user sent a conversational message instead of a code task. Reply in 1-2 short sentences. ' +
        'Be friendly and briefly remind them you can help with code tasks like implementing features, ' +
        'fixing bugs, refactoring, opening PRs, etc.',
      userPrompt: prompt,
      maxOutputTokens: 200,
      temperature: 0.7,
      modelOverride: lightProvider === 'anthropic' ? 'claude-haiku-4-5-20251001' : null,
    });
    replyText = result.text;
  } catch {
    replyText =
      "Hey! I'm ForgeAI — I help with code tasks like implementing features, fixing bugs, " +
      'refactoring, and opening PRs. What would you like me to work on?';
  }

  await completeAgentTaskNow(ownerId, taskId, replyText);
  return true;
}

async function processAgentTaskRun(ownerId: string, taskId: string, runToken: number) {
  let task = await assertAgentTaskStillRunnable(ownerId, taskId, runToken);
  const taskReference = agentTaskRef(ownerId, taskId);

  // Fast path: respond to conversational / non-code prompts without repo context.
  if (await handleConversationalPrompt(ownerId, taskId, task.prompt)) {
    return;
  }

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
    await resolveApprovedAgentTaskContinuation(ownerId, taskId, runToken, task, pendingApproval);
    return;
  }

  const followUpPlan = await planAgentFollowUp({
    prompt: task.prompt,
    repoId: task.repoId,
    currentFilePath: task.currentFilePath ?? null,
    deepMode: task.deepMode,
  });
  const costBudget = buildAgentTaskBudgetSnapshot({
    deepMode: task.deepMode,
    maxTokenBudget: task.guardrails.maxTokenBudget,
    maxRetries: task.guardrails.maxRetries,
  });
  const logicalPlan = buildLogicalAgentPlan({
    prompt: task.prompt,
    deepMode: task.deepMode,
    followUpPlan: followUpPlan.plan,
  });
  const toolRegistry = buildAgentToolRegistry({
    deepMode: task.deepMode,
    followUpPlan: followUpPlan.plan,
  });
  await taskReference.set(
    {
      phase: 'analyze_request',
      currentStep: 'Planning run',
      currentPass: task.currentPass + 1,
      followUpPlan: followUpPlan.plan,
      metadata: {
        ...(isObject(task.metadata) ? task.metadata : {}),
        planSource: followUpPlan.source,
        planSummary: followUpPlan.summary,
        plannedSteps: followUpPlan.steps,
        toolRegistry: serializeAgentToolRegistry(toolRegistry),
        toolRegistrySummary: summarizeAgentToolRegistry(toolRegistry),
        toolRegistryCount: toolRegistry.length,
        costBudget,
        costBudgetSummary: `Soft task budget ~$${costBudget.taskSoftBudgetUsd.toFixed(2)} with ${costBudget.taskTokenBudget} planned tokens.`,
        logicalAgentPlan: logicalPlan,
        logicalAgentPlanSummary: logicalPlan.steps.map(step => `${step.role}:${step.summary}`).join(' | '),
      },
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
  await recordLogicalAgentActivity({
    ownerId,
    taskId,
    role: 'planner',
    state: 'started',
    summary: followUpPlan.summary,
    data: {
      plannedSteps: followUpPlan.steps,
      planSource: followUpPlan.source,
    },
  });
  await appendAgentTaskEvent({
    ownerId,
    taskId,
    type: 'task_started',
    step: 'Planned run',
    message: followUpPlan.summary,
    status: 'running',
    phase: 'analyze_request',
    data: {
      planSource: followUpPlan.source,
      commitChanges: followUpPlan.plan.commitChanges,
      openPullRequest: followUpPlan.plan.openPullRequest,
      mergePullRequest: followUpPlan.plan.mergePullRequest,
      deployWorkflow: followUpPlan.plan.deployWorkflow,
      riskyOperation: followUpPlan.plan.riskyOperation,
      toolRegistrySummary: summarizeAgentToolRegistry(toolRegistry),
    },
  });
  await taskReference.set(
    {
      phase: 'inspect_repo',
      currentStep: 'Inspecting workspace',
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
  task = await assertAgentTaskStillRunnable(ownerId, taskId, runToken);
  const { value: taskWorkspace, execution: workspaceExecution } = await runAgentToolWithEvents({
    ownerId,
    taskId,
    phase: 'inspect_repo',
    toolName: 'clone_repo_workspace',
    startStep: 'Cloning repo workspace',
    startMessage:
      'Cloning the repository into an isolated task workspace before repo inspection and validation.',
    run: () => ensureAgentTaskLocalWorkspace(ownerId, taskId, task),
    summarizeSuccess: workspace =>
      `Cloned ${workspace.fileCount} file${workspace.fileCount === 1 ? '' : 's'} into a task-local repo workspace.`,
    metadataFromSuccess: workspace => ({
      workspacePath: workspace.workspacePath,
      workspaceFileCount: workspace.fileCount,
      baseBranch: workspace.defaultBranch,
      repoOwner: workspace.owner,
      repoName: workspace.name,
    }),
  });
  await taskReference.set(
    {
      metadata: {
        ...appendAgentToolExecutionToMetadata(
          isObject(task.metadata) ? task.metadata : null,
          workspaceExecution,
        ),
        ...serializeLocalWorkspaceInfo(taskWorkspace),
        workspaceSourceOfTruth: 'local_workspace',
      },
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
  await recordLogicalAgentActivity({
    ownerId,
    taskId,
    role: 'planner',
    state: 'handoff',
    summary: 'Planner handed the run to the context worker after task-local workspace clone.',
    data: {
      workspacePath: taskWorkspace.workspacePath,
      workspaceFileCount: taskWorkspace.fileCount,
    },
  });
  await recordLogicalAgentActivity({
    ownerId,
    taskId,
    role: 'context',
    state: 'started',
    summary: 'Context worker is mapping the repo and expanding execution memory.',
    data: {
      workspaceFileCount: taskWorkspace.fileCount,
    },
  });
  task = await assertAgentTaskStillRunnable(ownerId, taskId, runToken);
  const workspaceRepoFiles = await buildWorkspaceRepoFileRecords(
    taskWorkspace.workspacePath,
  );

  const repoObserver = buildAgentRepoExecutionObserver({
    ownerId,
    taskId,
  });
  // Record the wall-clock start time for routing metrics latency tracking.
  const generateSessionStartMs = Date.now();
  let session = await generateRepoExecutionSession({
    ownerId,
    repoId: task.repoId,
    prompt: task.prompt,
    currentFilePath: task.currentFilePath ?? undefined,
    deepMode: task.deepMode,
    requestedProvider:
      isObject(task.metadata) &&
              typeof task.metadata.requestedProvider === 'string' &&
              isAiProvider(task.metadata.requestedProvider as ProviderName)
        ? (task.metadata.requestedProvider as AiProviderName)
        : null,
    observer: repoObserver.observer,
    existingRunMemory: coerceRepoExecutionRunMemory(
      (await loadExecutionMemorySnapshot({
        db,
        ownerId,
        taskId,
      })) ??
          (isObject(task.metadata) ? task.metadata.executionMemory : null),
    ),
    budgetRemainingRatio: remainingTaskBudgetRatio({
      metadata: task.metadata,
      budget: buildAgentTaskBudgetSnapshot({
        deepMode: task.deepMode,
        maxTokenBudget: task.guardrails.maxTokenBudget,
        maxRetries: task.guardrails.maxRetries,
      }),
    }),
    retryCount: task.retryCount,
    repoFilesOverride: workspaceRepoFiles,
  });
  await recordLogicalAgentActivity({
    ownerId,
    taskId,
    role: 'context',
    state: 'completed',
    summary: session.executionMemorySummary ?? 'Context worker finalized the execution wave.',
    data: {
      repoSizeClass: session.repoSizeClass ?? null,
      contextStrategy: session.contextStrategy ?? null,
      selectedFileCount: session.selectedFiles.length,
      inspectedFileCount: session.inspectedFiles.length,
    },
  });
  // Log the routing decision reason to the real-time streamLog so users can
  // see which model was selected (and whether adaptive routing was used).
  if (session.executionProviderReason) {
    void appendStreamLogEntry(ownerId, taskId, {
      timestampMs: Date.now(),
      type: 'info',
      content: `[routing] ${session.executionProviderReason}`,
    });
  }
  await recordLogicalAgentActivity({
    ownerId,
    taskId,
    role: 'editor',
    state: 'started',
    summary: `Editor worker generated a ${session.edits.length}-file candidate diff.`,
    data: {
      executionProvider: session.executionProvider ?? null,
      executionModel: session.executionModel ?? null,
      estimatedTokens: session.estimatedTokens,
    },
  });
  await recordAgentCostActivity({
    ownerId,
    taskId,
    stage: 'editing',
    provider: session.executionProvider ?? null,
    model: session.executionModel ?? null,
    estimatedTokens: session.estimatedTokens,
    summary: `Generated candidate diff with ${session.selectedFiles.length} editable files.`,
    retryCount: task.retryCount,
  });

  while (true) {
    task = await assertAgentTaskStillRunnable(ownerId, taskId, runToken);
    await taskReference.set(
      {
        phase: 'validate',
        currentStep: 'Validating generated diff',
        sessionId: session.sessionId,
        executionSummary: session.summary,
        selectedFiles:
          repoObserver.observed.selectedFiles.length > 0
            ? repoObserver.observed.selectedFiles
            : session.selectedFiles,
        dependencyFiles:
          repoObserver.observed.dependencyFiles.length > 0
            ? repoObserver.observed.dependencyFiles
            : session.dependencyFiles,
        inspectedFiles:
          repoObserver.observed.inspectedFiles.length > 0
            ? repoObserver.observed.inspectedFiles
            : session.selectedFiles,
        filesTouched: session.edits.map(edit => edit.path),
        diffCount: session.edits.length,
        estimatedTokens: session.estimatedTokens,
        metadata: {
          ...(isObject(task.metadata) ? task.metadata : {}),
          repoSizeClass: session.repoSizeClass ?? null,
          contextStrategy: session.contextStrategy ?? null,
          executionMemory: session.executionMemory ?? null,
          executionMemorySummary: session.executionMemorySummary ?? null,
          executionProvider: session.executionProvider ?? null,
          executionModel: session.executionModel ?? null,
          executionProviderReason: session.executionProviderReason ?? null,
          contextPlannerProvider: session.contextPlannerProvider ?? null,
          contextPlannerModel: session.contextPlannerModel ?? null,
          executionPlannerProvider: session.executionPlannerProvider ?? null,
          executionPlannerModel: session.executionPlannerModel ?? null,
        },
        updatedAtMs: Date.now(),
      },
      { merge: true },
    );
    await persistExecutionMemorySnapshot({
      db,
      ownerId,
      taskId,
      repoId: task.repoId,
      phase: 'generate_diff',
      summary: session.executionMemorySummary ?? session.summary,
      memory: coerceRepoExecutionRunMemory(session.executionMemory),
    });
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

    const validationErrors = collectSessionGuardrailValidationErrors({
      task,
      session,
    });
    if (validationErrors.length === 0) {
      break;
    }

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
    if (task.retryCount >= task.guardrails.maxRetries) {
      const hardLimitSummary = buildAgentRetryLimitMessage({
        retryCount: task.retryCount,
        maxRetries: task.guardrails.maxRetries,
        reason: message,
        scope: 'guardrails',
      });
      await markAgentHardLimitReached({
        ownerId,
        taskId,
        summary: hardLimitSummary,
        type: 'guardrails',
        retryCount: task.retryCount,
        maxRetries: task.guardrails.maxRetries,
      });
      await failAgentTaskNow(ownerId, taskId, hardLimitSummary);
      return;
    }
    const nextRetryCount = task.retryCount + 1;
    await taskReference.set(
      {
        retryCount: nextRetryCount,
        phase: 'generate_diff',
        currentStep: 'Regenerating narrower diff',
        latestValidationError: message,
        updatedAtMs: Date.now(),
      },
      { merge: true },
    );
    await appendAgentTaskEvent({
      ownerId,
      taskId,
      type: 'retrying',
      step: 'Regenerating within guardrails',
      message: `The initial diff exceeded guardrails, so the agent is generating repair pass #${nextRetryCount} before approval.`,
      status: 'running',
      phase: 'generate_diff',
      data: {
        attempt: nextRetryCount,
        reason: truncate(message, 500),
      },
    });
    session = await generateRepoExecutionSession({
      ownerId,
      repoId: task.repoId,
      prompt: buildAgentGuardrailRepairPrompt({
        task,
        validationErrors,
        priorSummary: session.summary,
      }),
      currentFilePath: task.currentFilePath ?? undefined,
      deepMode: task.deepMode,
      requestedProvider:
        isObject(task.metadata) &&
                typeof task.metadata.requestedProvider === 'string' &&
                isAiProvider(task.metadata.requestedProvider as ProviderName) &&
                task.retryCount === 0
          ? (task.metadata.requestedProvider as AiProviderName)
          : null,
      repairMode: true,
      repairHintPaths: session.edits.map(edit => edit.path),
      targetedEditablePaths: session.edits.map(edit => edit.path),
      observer: repoObserver.observer,
      existingRunMemory:
        session.executionMemory ??
        coerceRepoExecutionRunMemory(
          isObject(task.metadata) ? task.metadata.executionMemory : null,
        ),
      budgetRemainingRatio: remainingTaskBudgetRatio({
        metadata: task.metadata,
        budget: buildAgentTaskBudgetSnapshot({
          deepMode: task.deepMode,
          maxTokenBudget: task.guardrails.maxTokenBudget,
          maxRetries: task.guardrails.maxRetries,
        }),
      }),
      retryCount: nextRetryCount,
      repoFilesOverride: workspaceRepoFiles,
    });
    await recordLogicalAgentActivity({
      ownerId,
      taskId,
      role: 'repair',
      state: 'started',
      summary: `Repair worker generated pre-approval guardrail pass #${nextRetryCount}.`,
      data: {
        estimatedTokens: session.estimatedTokens,
        executionProvider: session.executionProvider ?? null,
        executionModel: session.executionModel ?? null,
      },
    });
    await recordAgentCostActivity({
      ownerId,
      taskId,
      stage: 'repair',
      provider: session.executionProvider ?? null,
      model: session.executionModel ?? null,
      estimatedTokens: session.estimatedTokens,
      summary: `Generated guardrail repair pass #${nextRetryCount}.`,
      retryCount: nextRetryCount,
    });
    const refreshedTaskSnapshot = await taskReference.get();
    if (refreshedTaskSnapshot.exists) {
      task = safeAgentTask(refreshedTaskSnapshot.data());
    }
  }

  const preApplyValidation = await validateGeneratedSessionBeforeApproval({
    ownerId,
    taskId,
    runToken,
    task,
    session,
    repoObserver,
  });

  // Record routing metric now that we know the final validation outcome.
  // repairPassesNeeded = task.retryCount at this point (how many repair
  // passes were run before this validation check).
  if (session.executionProvider && session.executionModel) {
    recordRoutingMetric({
      repoId: task.repoId,
      taskId,
      model: session.executionModel,
      provider: session.executionProvider,
      stage: task.retryCount > 0 ? 'repair_diff' : 'generate_diff',
      latencyMs: Date.now() - generateSessionStartMs,
      inputTokens: session.estimatedTokens,
      outputTokens: 0,
      costUsd: estimateAgentStageCostUsd({
        provider: session.executionProvider,
        model: session.executionModel,
        estimatedTokens: session.estimatedTokens,
        stage: task.retryCount > 0 ? 'repair' : 'editing',
      }),
      validationPassed: preApplyValidation.ok,
      repairPassesNeeded: task.retryCount,
    });
  }

  if (!preApplyValidation.ok) {
    await failAgentTaskNow(ownerId, taskId, preApplyValidation.message);
    return;
  }
  session = preApplyValidation.session;
  const riskySuffix = task.followUpPlan.riskyOperation
    ? ' The original prompt included a risky operation request, so the agent is pausing for approval before writing anything.'
    : '';
  // Risky operations always require human approval regardless of trust level.
  const forceSupervised = task.followUpPlan.riskyOperation;
  const refreshedSnapshot = await agentTaskRef(ownerId, taskId).get();
  const refreshedTask = refreshedSnapshot.exists ? safeAgentTask(refreshedSnapshot.data()) : task;
  const effectiveTrustLevel: AgentTaskTrustLevel = forceSupervised
    ? 'SUPERVISED'
    : refreshedTask.trustLevel;
  // Temporarily patch the task trust level in the local reference so the
  // approval helper sees the correct value (avoids another Firestore read).
  const taskWithEffectiveTrust = { ...refreshedTask, trustLevel: effectiveTrustLevel };
  // We pass a fabricated snapshot so putAgentTaskIntoApprovalState reads the
  // right trust level. Since that function re-reads Firestore, persist the
  // effective trust level first if it differs.
  if (effectiveTrustLevel !== refreshedTask.trustLevel) {
    await agentTaskRef(ownerId, taskId).set(
      { trustLevel: effectiveTrustLevel, updatedAtMs: Date.now() },
      { merge: true },
    );
  }
  const wasAutoApproved = await putAgentTaskIntoApprovalState({
    ownerId,
    taskId,
    approval: buildAgentTaskPendingApproval({
      type: 'apply_changes',
      title: 'Apply the validated edits?',
      description:
        `The agent prepared, validated, and if needed repaired ${session.edits.length} file change${session.edits.length === 1 ? '' : 's'} in a sandboxed workspace. Review the diff before applying it to the task-local workspace.${riskySuffix}`,
      actionLabel: 'Apply edits',
      cancelLabel: 'Reject diff',
      payload: {
        sessionId: session.sessionId,
        diffCount: session.edits.length,
      },
    }),
    step: 'Awaiting approval to apply validated edits',
    message:
      'Review the validated diff. The workspace stays locked until you approve, reject, or cancel this task.',
    validationPassed: preApplyValidation.ok,
  });
  // If auto-approved, immediately continue to the apply-and-follow-up path.
  if (wasAutoApproved) {
    // Re-read task so the continuation sees pendingApproval.status === 'approved'.
    const autoApprovedSnapshot = await agentTaskRef(ownerId, taskId).get();
    const autoApprovedTask = autoApprovedSnapshot.exists
      ? safeAgentTask(autoApprovedSnapshot.data())
      : taskWithEffectiveTrust;
    if (autoApprovedTask.pendingApproval) {
      await resolveApprovedAgentTaskContinuation(
        ownerId,
        taskId,
        runToken,
        autoApprovedTask,
        autoApprovedTask.pendingApproval,
      );
    }
  }
}

interface WorkingCopyRepoFileRecord extends RepoWorkingCopyFile {
  sha?: string;
}

async function loadWorkingCopyRepoFiles(repoId: string): Promise<WorkingCopyRepoFileRecord[]> {
  const snapshot = await db
    .collection('repositories')
    .doc(repoId)
    .collection('files')
    .get();
  const files: WorkingCopyRepoFileRecord[] = [];
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
    files.push({
      path,
      content: typeof data.content === 'string' ? data.content : '',
      baseContent: typeof data.baseContent === 'string' ? data.baseContent : '',
      sha:
        typeof data.sha === 'string' && data.sha.trim().length > 0
          ? data.sha.trim()
          : undefined,
      isDeleted: data.isDeleted === true,
    });
  }
  return files;
}

function buildDraftFileChangesFromRecords(files: WorkingCopyRepoFileRecord[]) {
  const changes: GitFileChange[] = [];
  for (const file of files) {
    if (file.isDeleted) {
      if (file.sha || file.baseContent.length > 0) {
        changes.push({
          path: file.path,
          content: '',
          sha: file.sha,
          mode: 'delete',
        });
      }
      continue;
    }
    if (file.content === file.baseContent) {
      continue;
    }
    changes.push({
      path: file.path,
      content: file.content,
      sha: file.sha,
      mode: file.sha ? 'update' : 'create',
    });
  }
  return changes;
}

async function buildDraftFileChangesFromWorkingCopy(repoId: string) {
  const files = await loadWorkingCopyRepoFiles(repoId);
  return buildDraftFileChangesFromRecords(files);
}

function formatValidationFinding(finding: AgentValidationFinding) {
  const location =
    typeof finding.filePath === 'string' && finding.filePath.trim().length > 0
      ? `${finding.filePath}${finding.line != null ? `:${finding.line}` : ''}`
      : null;
  const code =
    typeof finding.code === 'string' && finding.code.trim().length > 0
      ? `[${finding.code.trim()}] `
      : '';
  return location != null
    ? `${location} ${code}${finding.message}`.trim()
    : `${code}${finding.message}`.trim();
}

function buildAgentValidationMetadata(params: {
  existingMetadata: Record<string, unknown> | null | undefined;
  attempt: number;
  passed: boolean;
  summary: string;
  results: AgentValidationToolResult[];
  branchName: string | null;
  retryCount: number;
}) {
  const existingMetadata = isObject(params.existingMetadata) ? params.existingMetadata : {};
  const historyRaw = Array.isArray(existingMetadata.validationHistory)
    ? existingMetadata.validationHistory
    : [];
  const nextEntry = {
    attempt: params.attempt,
    passed: params.passed,
    summary: params.summary,
    branchName: params.branchName,
    results: serializeValidationToolResults(params.results),
    recordedAtMs: Date.now(),
  };
  const repairQualityMetrics = buildRepairQualityMetrics({
    metadata: existingMetadata,
    validationAttempt: params.attempt,
    retryCount: params.retryCount,
    validationPassed: params.passed,
  });
  return {
    ...existingMetadata,
    validationAttemptCount: params.attempt,
    validationPassed: params.passed,
    validationSummary: params.summary,
    hardLimitReached: false,
    hardLimitSummary: null,
    latestValidationBranch: params.branchName,
    latestValidationToolResults: serializeValidationToolResults(params.results),
    validationHistory: [...historyRaw.slice(-7), nextEntry],
    repairQualityMetrics,
  };
}

function appendAgentToolExecutionToMetadata(
  metadata: Record<string, unknown> | null | undefined,
  execution: AgentToolExecutionRecord,
) {
  const existingMetadata = isObject(metadata) ? metadata : {};
  const historyRaw = Array.isArray(existingMetadata.toolExecutions)
    ? existingMetadata.toolExecutions.filter(isObject)
    : [];
  return {
    ...existingMetadata,
    lastToolExecution: execution,
    toolExecutions: [
      ...historyRaw.slice(-11),
      execution,
    ],
  };
}

function appendAgentCostActivityToMetadata(
  metadata: Record<string, unknown> | null | undefined,
  entry: AgentCostLedgerEntry,
) {
  return appendAgentCostLedgerEntry(metadata, entry);
}

async function recordAgentCostActivity(params: {
  ownerId: string;
  taskId: string;
  stage: AgentCostStage;
  provider?: AiProviderName | null;
  model?: string | null;
  estimatedTokens: number;
  summary: string;
  retryCount?: number;
}) {
  const taskReference = agentTaskRef(params.ownerId, params.taskId);
  const snapshot = await taskReference.get();
  const existingMetadata =
    snapshot.exists && isObject(snapshot.data()?.metadata)
      ? (snapshot.data()?.metadata as Record<string, unknown>)
      : null;
  const entry: AgentCostLedgerEntry = {
    stage: params.stage,
    provider: params.provider ?? null,
    model: params.model ?? null,
    estimatedTokens: params.estimatedTokens,
    estimatedCostUsd: estimateAgentStageCostUsd({
      provider: params.provider ?? null,
      model: params.model ?? null,
      estimatedTokens: params.estimatedTokens,
      stage: params.stage,
    }),
    summary: params.summary,
    retryCount: params.retryCount,
    recordedAtMs: Date.now(),
  };
  const nextMetadata = appendAgentCostActivityToMetadata(existingMetadata, entry);
  await taskReference.set(
    {
      metadata: nextMetadata,
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
}

async function recordLogicalAgentActivity(params: {
  ownerId: string;
  taskId: string;
  role: LogicalAgentRole;
  state: 'started' | 'completed' | 'handoff';
  summary: string;
  data?: Record<string, unknown>;
}) {
  const taskReference = agentTaskRef(params.ownerId, params.taskId);
  const snapshot = await taskReference.get();
  const existingMetadata =
    snapshot.exists && isObject(snapshot.data()?.metadata)
      ? (snapshot.data()?.metadata as Record<string, unknown>)
      : null;
  const record = buildLogicalAgentRecord({
    role: params.role,
    state: params.state,
    summary: params.summary,
    data: params.data,
  });
  await taskReference.set(
    {
      metadata: appendLogicalAgentRecord(existingMetadata, record),
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
}

async function recordPassiveAgentToolExecution(params: {
  ownerId: string;
  taskId: string;
  toolName: Parameters<typeof getAgentToolDefinition>[0];
  summary: string;
  metadata?: Record<string, unknown>;
}) {
  const tool = getAgentToolDefinition(params.toolName);
  const execution: AgentToolExecutionRecord = {
    toolName: tool.name,
    label: tool.label,
    category: tool.category,
    status: 'passed',
    summary: params.summary,
    durationMs: 0,
    metadata: params.metadata,
  };
  const taskReference = agentTaskRef(params.ownerId, params.taskId);
  const snapshot = await taskReference.get();
  const existingMetadata =
    snapshot.exists && isObject(snapshot.data()?.metadata)
      ? (snapshot.data()?.metadata as Record<string, unknown>)
      : null;
  await taskReference.set(
    {
      metadata: appendAgentToolExecutionToMetadata(existingMetadata, execution),
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
}

async function runAgentToolWithEvents<T>(params: {
  ownerId: string;
  taskId: string;
  phase: AgentTaskPhase;
  toolName: Parameters<typeof getAgentToolDefinition>[0];
  startStep: string;
  startMessage: string;
  run: () => Promise<T>;
  summarizeSuccess?: (value: T) => string;
  metadataFromSuccess?: (value: T) => Record<string, unknown> | undefined;
}) {
  const tool = getAgentToolDefinition(params.toolName);
  await appendAgentTaskEvent({
    ownerId: params.ownerId,
    taskId: params.taskId,
    type: 'tool_started',
    step: params.startStep,
    message: params.startMessage,
    status: 'running',
    phase: params.phase,
    data: {
      toolName: tool.label,
      toolKind: tool.category,
    },
  });
  try {
    const { value, execution } = await executeAgentTool({
      tool,
      run: params.run,
      summarizeSuccess: params.summarizeSuccess,
      metadataFromSuccess: params.metadataFromSuccess,
    });
    await appendAgentTaskEvent({
      ownerId: params.ownerId,
      taskId: params.taskId,
      type: 'tool_passed',
      step: params.startStep,
      message: execution.summary,
      status: 'running',
      phase: params.phase,
      data: {
        toolName: execution.label,
        toolKind: execution.category,
        durationMs: execution.durationMs,
        ...(execution.metadata ?? {}),
      },
    });
    return { value, execution };
  } catch (error) {
    const execution =
      error instanceof Error &&
              'agentToolExecution' in error &&
              error.agentToolExecution != null
        ? (error.agentToolExecution as AgentToolExecutionRecord)
        : {
            toolName: tool.name,
            label: tool.label,
            category: tool.category,
            status: 'failed' as const,
            summary: error instanceof Error ? error.message : String(error ?? 'Tool failed.'),
            durationMs: 0,
          };
    await appendAgentTaskEvent({
      ownerId: params.ownerId,
      taskId: params.taskId,
      type: 'tool_failed',
      step: params.startStep,
      message: execution.summary,
      status: 'running',
      phase: params.phase,
      data: {
        toolName: execution.label,
        toolKind: execution.category,
        durationMs: execution.durationMs,
      },
    });
    throw error;
  }
}

function buildAgentRetryLimitMessage(params: {
  retryCount: number;
  maxRetries: number;
  reason: string;
  scope: 'validation' | 'guardrails';
}) {
  const intro =
    params.scope === 'guardrails'
      ? `The agent regenerated the diff ${params.retryCount} time${params.retryCount == 1 ? '' : 's'} but still could not satisfy the pre-approval guardrails.`
      : `The agent attempted ${params.retryCount} repair pass${params.retryCount == 1 ? '' : 'es'} but validation still failed.`;
  return `${intro} The hard limit is ${params.maxRetries} repair pass${params.maxRetries == 1 ? '' : 'es'}. Latest failure: ${truncate(
    params.reason,
    900,
  )}`;
}

async function markAgentHardLimitReached(params: {
  ownerId: string;
  taskId: string;
  summary: string;
  type: 'validation' | 'guardrails';
  retryCount: number;
  maxRetries: number;
}) {
  await agentTaskRef(params.ownerId, params.taskId).set(
    {
      currentStep:
        params.type === 'guardrails'
            ? 'Reached pre-approval repair limit'
            : 'Reached validation repair limit',
      latestValidationError: params.summary,
      metadata: {
        hardLimitReached: true,
        hardLimitType: params.type,
        hardLimitSummary: params.summary,
        maxRetries: params.maxRetries,
        retryCountAtLimit: params.retryCount,
      },
      updatedAtMs: Date.now(),
    },
    { merge: true },
  );
}

function buildAgentValidationBranchName(taskId: string, attempt: number) {
  return `forgeai/validation-${taskId.slice(0, 8)}-${attempt}-${Date.now().toString(36)}`;
}

function buildAgentValidationFailurePrompt(results: AgentValidationToolResult[]) {
  const failureSummary = summarizeValidationToolResults(results);
  const findings = results
    .flatMap(result =>
      result.findings
        .slice(0, 5)
        .map(finding => `${result.name}: ${formatValidationFinding(finding)}`),
    )
    .slice(0, 12)
    .join('\n');
  return findings.trim().length > 0
    ? `${failureSummary}\n${findings}`
    : failureSummary;
}

function classifyValidationFailureResults(results: AgentValidationToolResult[]) {
  const relevantResults = results.filter(
    result => result.status === 'failed' || result.status === 'timed_out',
  );
  const sourceResults =
    relevantResults.length > 0
      ? relevantResults
      : results.filter(result => result.findings.length > 0);
  const text = sourceResults
    .flatMap(result => [
      result.name,
      result.summary,
      ...result.findings.map(finding =>
        `${finding.code ?? ''} ${finding.message}`.trim(),
      ),
    ])
    .join('\n')
    .toLowerCase();
  if (sourceResults.some(result => result.kind === 'workspace_consistency')) {
    return 'workspace';
  }
  if (
    /missing_import|cannot resolve local import|cannot find module|module not found|uri does not exist|target of uri/i.test(
      text,
    )
  ) {
    return 'import';
  }
  if (
    /syntax|parse error|unexpected token|unterminated|expected to find|expected an identifier/i.test(
      text,
    )
  ) {
    return 'syntax';
  }
  if (
    sourceResults.some(
      result =>
        result.workflowCategory === 'test' ||
        /\btest\b|\bassert\b|\bexpect(?:ed)?\b|test_failure|failing test/i.test(
          `${result.name} ${result.summary}`.toLowerCase(),
        ),
    )
  ) {
    return 'test';
  }
  if (
    /not assignable|undefined name|isn't defined|type '?[^']+'? not found|ts\d+|compile error|type error/i.test(
      text,
    )
  ) {
    return 'typecheck';
  }
  if (
    sourceResults.some(
      result =>
        result.workflowCategory === 'build' ||
        /\bbuild\b|\bcompile\b|\bbundle\b|\bxcode\b|\bgradle\b/i.test(
          `${result.name} ${result.summary}`.toLowerCase(),
        ),
    )
  ) {
    return 'build';
  }
  if (
    sourceResults.some(
      result =>
        result.workflowCategory === 'lint' ||
        /\blint\b|\banaly[sz]e\b|\beslint\b|\bwarning\b/i.test(
          `${result.name} ${result.summary}`.toLowerCase(),
        ),
    )
  ) {
    return 'lint';
  }
  if (sourceResults.some(result => result.kind === 'ci_workflow')) {
    return 'ci';
  }
  return 'unknown';
}

function buildValidationCategoryOrder(
  failureCategory: string | null | undefined,
  validationAttempt: number,
) {
  switch (failureCategory) {
    case 'workspace':
    case 'import':
    case 'syntax':
    case 'typecheck':
    case 'lint':
      return ['bootstrap', 'analyze', 'lint', 'build', 'test'];
    case 'build':
    case 'ci':
      return ['bootstrap', 'build', 'analyze', 'lint', 'test'];
    case 'test':
      return ['bootstrap', 'test', 'analyze', 'lint', 'build'];
    default:
      return validationAttempt > 1
        ? ['bootstrap', 'analyze', 'lint', 'build', 'test']
        : ['bootstrap', 'analyze', 'lint', 'build', 'test'];
  }
}

function orderLocalWorkspaceValidationCommands(params: {
  commands: LocalWorkspaceValidationCommand[];
  failureCategory: string | null;
  validationAttempt: number;
}) {
  const order = buildValidationCategoryOrder(
    params.failureCategory,
    params.validationAttempt,
  );
  const orderIndex = new Map(order.map((category, index) => [category, index]));
  return [...params.commands].sort((left, right) => {
    const leftPriority = orderIndex.get(left.category) ?? order.length;
    const rightPriority = orderIndex.get(right.category) ?? order.length;
    if (leftPriority !== rightPriority) {
      return leftPriority - rightPriority;
    }
    return left.name.localeCompare(right.name);
  });
}

function orderValidationWorkflows(params: {
  workflows: PlannedValidationWorkflow[];
  failureCategory: string | null;
  validationAttempt: number;
}) {
  const order = buildValidationCategoryOrder(
    params.failureCategory,
    params.validationAttempt,
  );
  const orderIndex = new Map(order.map((category, index) => [category, index]));
  return [...params.workflows].sort((left, right) => {
    const leftCategory = left.workflowCategory ?? 'test';
    const rightCategory = right.workflowCategory ?? 'test';
    const leftPriority = orderIndex.get(leftCategory) ?? order.length;
    const rightPriority = orderIndex.get(rightCategory) ?? order.length;
    if (leftPriority !== rightPriority) {
      return leftPriority - rightPriority;
    }
    return left.name.localeCompare(right.name);
  });
}

function collectValidationFailureLocations(
  results: AgentValidationToolResult[],
  limit = 12,
) {
  const locations: string[] = [];
  const seen = new Set<string>();
  for (const result of results) {
    for (const finding of result.findings) {
      const formatted = `${result.name}: ${formatValidationFinding(finding)}`.trim();
      if (!formatted || seen.has(formatted)) {
        continue;
      }
      seen.add(formatted);
      locations.push(formatted);
      if (locations.length >= limit) {
        return locations;
      }
    }
  }
  return locations;
}

function buildValidationFailureInsights(results: AgentValidationToolResult[]) {
  const findings = results.flatMap(result => result.findings);
  const failurePaths = collectFailingPathsFromFindings(findings);
  const failureLocations = collectValidationFailureLocations(results);
  return {
    failurePaths,
    failureLocations,
    failureCategory: classifyValidationFailureResults(results),
  };
}

function buildAgentValidationToolEventData(result: AgentValidationToolResult) {
  const failureInsights =
    result.status === 'failed' || result.status === 'timed_out'
      ? buildValidationFailureInsights([result])
      : null;
  return {
    toolId: result.id,
    toolKind: result.kind,
    toolName: result.name,
    toolStatus: result.status,
    summary: result.summary,
    durationMs: result.durationMs,
    findings: result.findings.slice(0, 8).map(finding => ({
      message: finding.message,
      severity: finding.severity,
      filePath: finding.filePath ?? null,
      line: finding.line ?? null,
      code: finding.code ?? null,
    })),
    failureCategory: failureInsights?.failureCategory ?? null,
    failureLocations: failureInsights?.failureLocations.slice(0, 8) ?? [],
    repairTargetPaths: failureInsights?.failurePaths.slice(0, 8) ?? [],
    workflowName: result.workflowName ?? null,
    workflowPath: result.workflowPath ?? null,
    workflowCategory: result.workflowCategory ?? null,
    checkRunId: result.checkRunId ?? null,
    logsUrl: result.logsUrl ?? null,
    branchName: result.branchName ?? null,
  };
}

function buildToolRunSummary(result: AgentValidationToolResult) {
  if (result.findings.length === 0) {
    return result.summary;
  }
  return `${result.summary} ${result.findings
    .slice(0, 3)
    .map(finding => formatValidationFinding(finding))
    .join(' | ')}`;
}

function collectSessionGuardrailValidationErrors(params: {
  task: AgentTaskDocument;
  session: {
    edits: Array<unknown>;
    estimatedTokens: number;
  };
}) {
  const validationErrors: string[] = [];
  if (params.session.edits.length > params.task.guardrails.maxFileTouchCount) {
    validationErrors.push(
      `Diff touches ${params.session.edits.length} files, exceeding the limit of ${params.task.guardrails.maxFileTouchCount}.`,
    );
  }
  if (params.session.estimatedTokens > params.task.guardrails.maxTokenBudget) {
    validationErrors.push(
      `Estimated token usage (${params.session.estimatedTokens}) exceeds the task budget of ${params.task.guardrails.maxTokenBudget}.`,
    );
  }
  return validationErrors;
}

function serializeValidationFindingsForStorage(findings: AgentValidationFinding[]) {
  return findings.map(finding => ({
    message: finding.message,
    severity: finding.severity,
    filePath: finding.filePath ?? null,
    line: finding.line ?? null,
    code: finding.code ?? null,
    source: finding.source ?? null,
  }));
}

function collectFailingPathsFromFindings(findings: AgentValidationFinding[]) {
  return [
    ...new Set(
      findings
        .map(finding => finding.filePath)
        .filter((value): value is string => typeof value === 'string' && value.trim().length > 0),
    ),
  ];
}

function buildCompletedCheckRunPayload(params: {
  summary: string;
  passed: boolean;
  timedOut: boolean;
  remoteId: string | number | null;
  logsUrl: string | null;
  runStatus: string | null;
  runConclusion: string | null;
  failureNotes: string[];
  findings: AgentValidationFinding[];
}) {
  return {
    status: params.passed ? 'passed' : 'failed',
    executionState: params.timedOut
      ? 'timed_out'
      : params.runConclusion ?? params.runStatus ?? 'completed',
    logsUrl: params.logsUrl,
    remoteId: params.remoteId,
    summary: params.summary,
    logs: params.failureNotes,
    findings: serializeValidationFindingsForStorage(params.findings),
    failingFiles: collectFailingPathsFromFindings(params.findings),
    monitorState: 'completed',
    completedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
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
      summary: asOptionalString(parsed.summary) ?? `Legacy AI draft for ${fallbackContext.filePath}`,
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
    summary: summaryLine || `Legacy AI draft for ${fallbackContext.filePath}`,
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

/** Legacy compatibility path: persist Prompt-suggested file changes to the repo draft store in Firestore, not to GitHub. */
const APPLY_FILE_EDITS_TOOL = {
  type: 'function' as const,
  function: {
    name: 'apply_file_edits',
    description:
      "Save implementation work to the user's legacy in-app repository draft (synced Firestore files). " +
      'Call this when the user wants real changes, not only explanation. For create/modify you must pass the COMPLETE file text. ' +
      'You may call multiple times. Nothing is pushed to Git until the user commits from the app.',
    parameters: {
      type: 'object',
      properties: {
        edits: {
          type: 'array',
          description: 'Files to create, fully replace, or remove from the legacy repo draft.',
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
      await writeActivityEntry(ownerId, 'repo', repoId, `Prompt removed ${path} from the legacy repo draft.`, {
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
  let treeTruncated = false;
  let totalTreeEntries: number | null = null;
  try {
    const tree = await fetchJson<{
      truncated?: boolean;
      tree?: Array<{ path?: string; type?: string; size?: number }>;
    }>(
      `${baseUrl}/repos/${encodeURIComponent(resolvedOwner)}/${encodeURIComponent(resolvedName)}/git/trees/${encodeURIComponent(repo.default_branch)}?recursive=1`,
      { headers: buildGitHubHeaders(token) },
    );
    const treeEntries = (tree.tree ?? []).filter(item => typeof item.path === 'string');
    totalTreeEntries = treeEntries.length;
    treeTruncated = tree.truncated === true || treeEntries.length > REPO_SYNC_TREE_LIMIT;
    files = treeEntries
      .filter(item => typeof item.path === 'string')
      .slice(0, REPO_SYNC_TREE_LIMIT)
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
    treeTruncated,
    totalTreeEntries,
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
      totalTreeEntries: snapshot.totalTreeEntries ?? snapshot.files.length,
      treeTruncated: snapshot.treeTruncated === true,
      syncStatus: 'synced',
      apiBaseUrl: extras?.apiBaseUrl ?? null,
      lastSyncedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      ...extras,
    },
    { merge: true },
  );

  const filesCollection = repoRef.collection('files');
  for (let index = 0; index < snapshot.files.length; index += FIRESTORE_BATCH_WRITE_LIMIT) {
    const batch = db.batch();
    for (const file of snapshot.files.slice(index, index + FIRESTORE_BATCH_WRITE_LIMIT)) {
      batch.set(
        filesCollection.doc(safeDocId(file.path)),
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
    await batch.commit();
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

function sleepMs(durationMs: number) {
  return new Promise<void>(resolve => {
    setTimeout(resolve, durationMs);
  });
}

interface GitHubWorkflowRunStatus {
  runId: number;
  status: string;
  conclusion: string | null;
  htmlUrl: string | null;
  createdAtMs: number | null;
  updatedAtMs: number | null;
}

interface GitHubWorkflowJobStatus {
  jobId: number | null;
  name: string;
  conclusion: string | null;
  htmlUrl: string | null;
  checkRunUrl: string | null;
  steps: Array<{
    name: string;
    conclusion: string | null;
  }>;
}

interface GitHubCheckRunAnnotation {
  path: string | null;
  startLine: number | null;
  endLine: number | null;
  annotationLevel: string | null;
  message: string;
  title: string | null;
  rawDetails: string | null;
}

async function listGitHubWorkflowRuns(
  token: string,
  owner: string,
  name: string,
  workflowName: string,
  ref: string,
  apiBaseUrl?: string,
) {
  const baseUrl = resolveApiBaseUrl('github', apiBaseUrl);
  const response = await fetchJson<{
    workflow_runs?: Array<{
      id?: number;
      status?: string | null;
      conclusion?: string | null;
      html_url?: string | null;
      created_at?: string | null;
      updated_at?: string | null;
    }>;
  }>(
    `${baseUrl}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/actions/workflows/${encodeURIComponent(workflowName)}/runs?branch=${encodeURIComponent(ref)}&event=workflow_dispatch&per_page=10`,
    {
      headers: buildGitHubHeaders(token),
    },
  );
  return (response.workflow_runs ?? [])
    .map<GitHubWorkflowRunStatus | null>(run => {
      if (typeof run.id !== 'number') {
        return null;
      }
      return {
        runId: run.id,
        status: typeof run.status === 'string' ? run.status : 'queued',
        conclusion: typeof run.conclusion === 'string' ? run.conclusion : null,
        htmlUrl: typeof run.html_url === 'string' ? run.html_url : null,
        createdAtMs: typeof run.created_at === 'string' ? Date.parse(run.created_at) : null,
        updatedAtMs: typeof run.updated_at === 'string' ? Date.parse(run.updated_at) : null,
      };
    })
    .filter((run): run is GitHubWorkflowRunStatus => run != null)
    .sort((a, b) => (b.createdAtMs ?? 0) - (a.createdAtMs ?? 0));
}

async function getGitHubWorkflowRun(
  token: string,
  owner: string,
  name: string,
  runId: number,
  apiBaseUrl?: string,
) {
  const baseUrl = resolveApiBaseUrl('github', apiBaseUrl);
  const run = await fetchJson<{
    id?: number;
    status?: string | null;
    conclusion?: string | null;
    html_url?: string | null;
    created_at?: string | null;
    updated_at?: string | null;
  }>(
    `${baseUrl}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/actions/runs/${runId}`,
    { headers: buildGitHubHeaders(token) },
  );
  return {
    runId,
    status: typeof run.status === 'string' ? run.status : 'queued',
    conclusion: typeof run.conclusion === 'string' ? run.conclusion : null,
    htmlUrl: typeof run.html_url === 'string' ? run.html_url : null,
    createdAtMs: typeof run.created_at === 'string' ? Date.parse(run.created_at) : null,
    updatedAtMs: typeof run.updated_at === 'string' ? Date.parse(run.updated_at) : null,
  } satisfies GitHubWorkflowRunStatus;
}

async function listGitHubWorkflowRunJobs(
  token: string,
  owner: string,
  name: string,
  runId: number,
  apiBaseUrl?: string,
) {
  const baseUrl = resolveApiBaseUrl('github', apiBaseUrl);
  const response = await fetchJson<{
    jobs?: Array<{
      id?: number | null;
      name?: string | null;
      conclusion?: string | null;
      html_url?: string | null;
      check_run_url?: string | null;
      steps?: Array<{
        name?: string | null;
        conclusion?: string | null;
      }> | null;
    }>;
  }>(
    `${baseUrl}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/actions/runs/${runId}/jobs?per_page=100`,
    { headers: buildGitHubHeaders(token) },
  );
  return (response.jobs ?? []).map<GitHubWorkflowJobStatus>(job => ({
    jobId: typeof job.id === 'number' ? job.id : null,
    name:
      typeof job.name === 'string' && job.name.trim().length > 0
        ? job.name.trim()
        : 'job',
    conclusion: typeof job.conclusion === 'string' ? job.conclusion : null,
    htmlUrl: typeof job.html_url === 'string' ? job.html_url : null,
    checkRunUrl:
      typeof job.check_run_url === 'string' ? job.check_run_url : null,
    steps: (job.steps ?? []).map(step => ({
      name:
        typeof step?.name === 'string' && step.name.trim().length > 0
          ? step.name.trim()
          : 'step',
      conclusion: typeof step?.conclusion === 'string' ? step.conclusion : null,
    })),
  }));
}

async function listGitHubCheckRunAnnotations(
  token: string,
  checkRunUrl: string,
) {
  const response = await fetchJson<{
    output?: {
      annotations_url?: string | null;
    };
  }>(checkRunUrl, {
    headers: buildGitHubHeaders(token),
  });
  const annotationsUrl = response.output?.annotations_url;
  if (typeof annotationsUrl !== 'string' || annotationsUrl.trim().length === 0) {
    return [] as GitHubCheckRunAnnotation[];
  }
  const annotations = await fetchJson<unknown[]>(`${annotationsUrl}?per_page=30`, {
    headers: buildGitHubHeaders(token),
  });
  return annotations
    .filter(isObject)
    .map<GitHubCheckRunAnnotation>(annotation => ({
      path:
        typeof annotation.path === 'string' && annotation.path.trim().length > 0
          ? annotation.path.trim()
          : null,
      startLine:
        typeof annotation.start_line === 'number' ? annotation.start_line : null,
      endLine: typeof annotation.end_line === 'number' ? annotation.end_line : null,
      annotationLevel:
        typeof annotation.annotation_level === 'string'
          ? annotation.annotation_level
          : null,
      message:
        typeof annotation.message === 'string' && annotation.message.trim().length > 0
          ? annotation.message.trim()
          : 'Check annotation',
      title:
        typeof annotation.title === 'string' && annotation.title.trim().length > 0
          ? annotation.title.trim()
          : null,
      rawDetails:
        typeof annotation.raw_details === 'string' && annotation.raw_details.trim().length > 0
          ? annotation.raw_details.trim()
          : null,
    }));
}

async function collectGitHubWorkflowFailureFindings(
  token: string,
  jobs: GitHubWorkflowJobStatus[],
) {
  const findings: AgentValidationFinding[] = [];
  for (const job of jobs) {
    if (job.conclusion == null || job.conclusion === 'success') {
      continue;
    }
    if (job.checkRunUrl) {
      try {
        const annotations = await listGitHubCheckRunAnnotations(token, job.checkRunUrl);
        for (const annotation of annotations.slice(0, 8 - findings.length)) {
          findings.push({
            severity:
              annotation.annotationLevel === 'warning' ? 'warning' : 'error',
            filePath: annotation.path,
            line: annotation.startLine,
            code: annotation.title,
            source: 'ci_workflow',
            message: annotation.rawDetails ?? annotation.message,
          });
        }
      } catch (error) {
        functions.logger.warn('github_check_run_annotations.failed', {
          errorMessage: normalizeError(error).message,
          checkRunUrl: job.checkRunUrl,
        });
      }
    }
    if (findings.length >= 8) {
      break;
    }
  }
  return findings;
}

function summarizeGitHubWorkflowFailure(jobs: GitHubWorkflowJobStatus[]) {
  const failedSteps: string[] = [];
  const failedJobs: string[] = [];
  for (const job of jobs) {
    const jobName = job.name;
    if (job.conclusion && job.conclusion !== 'success') {
      failedJobs.push(`${jobName} (${job.conclusion})`);
    }
    for (const step of job.steps) {
      if (!step || step.conclusion == null || step.conclusion === 'success') {
        continue;
      }
      const stepName = step.name;
      failedSteps.push(`${jobName} > ${stepName} (${step.conclusion})`);
    }
  }
  return {
    failedJobs: failedJobs.slice(0, 6),
    failedSteps: failedSteps.slice(0, 10),
  };
}

async function waitForGitHubWorkflowRun(params: {
  token: string;
  owner: string;
  name: string;
  workflowName: string;
  ref: string;
  dispatchStartedAtMs: number;
  timeoutMs?: number;
  pollIntervalMs?: number;
  apiBaseUrl?: string;
}) {
  const deadline = Date.now() + (params.timeoutMs ?? REPO_VALIDATION_TIMEOUT_MS);
  const pollIntervalMs = params.pollIntervalMs ?? REPO_VALIDATION_POLL_INTERVAL_MS;
  let run: GitHubWorkflowRunStatus | null = null;

  while (Date.now() < deadline) {
    if (run == null) {
      const runs = await listGitHubWorkflowRuns(
        params.token,
        params.owner,
        params.name,
        params.workflowName,
        params.ref,
        params.apiBaseUrl,
      );
      run =
        runs.find(
          item =>
            item.createdAtMs != null &&
            item.createdAtMs >= params.dispatchStartedAtMs - 60_000,
        ) ?? runs[0] ?? null;
    } else {
      run = await getGitHubWorkflowRun(
        params.token,
        params.owner,
        params.name,
        run.runId,
        params.apiBaseUrl,
      );
    }

    if (run && run.status === 'completed') {
      const jobs = await listGitHubWorkflowRunJobs(
        params.token,
        params.owner,
        params.name,
        run.runId,
        params.apiBaseUrl,
      );
      const failureSummary = summarizeGitHubWorkflowFailure(jobs);
      const findings = await collectGitHubWorkflowFailureFindings(params.token, jobs);
      return {
        status: run.status,
        conclusion: run.conclusion,
        htmlUrl: run.htmlUrl,
        runId: run.runId,
        failedJobs: failureSummary.failedJobs,
        failedSteps: failureSummary.failedSteps,
        findings,
        timedOut: false,
      };
    }

    await sleepMs(pollIntervalMs);
  }

  return {
    status: run?.status ?? 'queued',
    conclusion: run?.conclusion ?? null,
    htmlUrl: run?.htmlUrl ?? null,
    runId: run?.runId ?? null,
    failedJobs: [] as string[],
    failedSteps: [] as string[],
    findings: [] as AgentValidationFinding[],
    timedOut: true,
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
    htmlUrl?: string | null;
    remoteId?: string | number | null;
    apiBaseUrl?: string | null;
    treeTruncated?: boolean | null;
    totalTreeEntries?: number | null;
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
  const ownerId = await requireAuth(request);
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
  const ownerId = await requireAuth(request);
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
  const ownerId = await requireAuth(request);
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
    const ownerId = await requireAuth(request);
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
  const ownerId = await requireAuth(request);
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

// DEPRECATED — Legacy single-shot chat endpoint (pre-agent era). The app now routes all
// user-facing AI work through enqueueAgentTask / processAgentTaskRun which provides durable,
// multi-step, validated, and approval-gated execution.  Retained for backward compatibility
// with old clients only. New code must not call this function.
export const askRepo = onCall(GIT_AND_AI_CALLABLE_OPTIONS, async request => {
  const startedAt = Date.now();
  const ownerId = await requireAuth(request);
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

Legacy tool-based execution (enabled for this Prompt):
- You can call apply_file_edits to save files into the user's in-app legacy repo draft (not GitHub until they commit).
- For implementation requests—features, fixes, refactors, new files—MUST call apply_file_edits with the full file text for every created or updated file. Pure Q&A or high-level architecture-only answers may skip the tool.
- Batch multiple files in one apply_file_edits call when practical; call again in a later turn if you hit limits.
- Use action "delete" with no content to remove a path from the legacy repo draft.
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
If they ask to deploy Firebase functions via git, remind them they can type **deploy functions** or **deploy firebase** in the agent workspace after adding that workflow and one auth secret in repo Actions secrets: FIREBASE_TOKEN (easy) or FIREBASE_SERVICE_ACCOUNT (recommended).
If they ask to run the app via git, remind them they can type **run app**, **run the app**, or **run app via git** in the agent workspace. Mention installing workflows if missing: **install run app** / **install deploy workflow**.
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
  const ownerId = await requireAuth(request);
  const data = (request.data ?? {}) as Partial<RepoExecutionData>;
  const repoId = asString(data.repoId, 'repoId');
  const prompt = asString(data.prompt, 'prompt');
  const deepMode = data.deepMode === true;
  const currentFilePath = asOptionalString(data.currentFilePath);
  const requestedProvider =
    typeof data.provider === 'string' && isAiProvider(data.provider as ProviderName)
      ? (data.provider as AiProviderName)
      : null;
  const routing = resolveRepoExecutionProviderRouting({
    requestedProvider,
    stage: 'generate_diff',
    deepMode,
  });
  const provider = routing.provider;
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
      requestedProvider,
      retryCount: 0,
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
        model:
          typeof result.executionModel === 'string' && result.executionModel.trim().length > 0
            ? result.executionModel
            : costSnapshot.assumedModel,
      },
    );
    await writeOperationalMetric({
      operation: 'execute_repo_task',
      status: 'success',
      ownerId,
      repoId,
      provider,
      actionType,
      model:
        typeof result.executionModel === 'string' && result.executionModel.trim().length > 0
          ? result.executionModel
          : costSnapshot.assumedModel,
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

// DEPRECATED — Legacy Firestore-draft apply path. The primary execution flow
// uses git-native ephemeral workspaces (enqueueAgentTask / processAgentTaskRun).
// This callable is retained only for backward compatibility with old clients and
// will be removed in a future release. New code must not call this function.
export const applyRepoExecution = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const startedAt = Date.now();
  const ownerId = await requireAuth(request);
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
  const ownerId = await requireAuth(request);
  const data = (request.data ?? {}) as Partial<EnqueueAgentTaskData>;
  const repoId = asString(data.repoId, 'repoId');
  const prompt = asString(data.prompt, 'prompt');
  const deepMode = data.deepMode === true;
  const trustLevel: AgentTaskTrustLevel =
    data.trustLevel === 'AUTO_APPROVE_ON_SUCCESS' ||
    data.trustLevel === 'FULLY_AUTONOMOUS'
      ? data.trustLevel
      : 'SUPERVISED';
  const requestedProvider =
    typeof data.provider === 'string' && isAiProvider(data.provider as ProviderName)
      ? (data.provider as AiProviderName)
      : null;
  await ensureRepositoryAccess(repoId, ownerId);
  const initialFollowUpPlan = inferAgentFollowUpPlan(prompt);
  const guardrails = buildAgentTaskGuardrails(deepMode);
  const costBudget = buildAgentTaskBudgetSnapshot({
    deepMode,
    maxTokenBudget: guardrails.maxTokenBudget,
    maxRetries: guardrails.maxRetries,
  });
  const logicalPlan = buildLogicalAgentPlan({
    prompt,
    deepMode,
    followUpPlan: initialFollowUpPlan,
  });
  const initialToolRegistry = buildAgentToolRegistry({
    deepMode,
    followUpPlan: initialFollowUpPlan,
  });

  const now = Date.now();
  const taskReference = agentTaskCollection(ownerId).doc();
  const task: AgentTaskDocument = {
    ownerId,
    repoId,
    prompt,
    threadId: asOptionalString(data.threadId) ?? null,
    currentFilePath: asOptionalString(data.currentFilePath) ?? null,
    deepMode,
    trustLevel,
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
    followUpPlan: initialFollowUpPlan,
    guardrails,
    pendingApproval: null,
    streamLog: [],
    metadata: {
      planSource: 'heuristic',
      planSummary: defaultAgentPlanSummary(initialFollowUpPlan),
      plannedSteps: defaultAgentPlannedSteps(initialFollowUpPlan),
      requestedProvider,
      toolRegistry: serializeAgentToolRegistry(initialToolRegistry),
      toolRegistrySummary: summarizeAgentToolRegistry(initialToolRegistry),
      toolRegistryCount: initialToolRegistry.length,
      maxRetries: guardrails.maxRetries,
      validationAttemptCount: 0,
      hardLimitReached: false,
      hardLimitSummary: null,
      costBudget,
      costBudgetSummary: `Soft task budget ~$${costBudget.taskSoftBudgetUsd.toFixed(2)} with ${costBudget.taskTokenBudget} planned tokens.`,
      totalEstimatedAgentTokens: 0,
      totalEstimatedAgentCostUsd: 0,
      logicalAgentPlan: logicalPlan,
      logicalAgentPlanSummary: logicalPlan.steps.map(step => `${step.role}:${step.summary}`).join(' | '),
      distributedRuntime: {
        dispatchMode: 'firestore_worker',
        latestWorkerRunId: null,
        latestWorkerState: 'queued',
      },
    },
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
      requestedProvider,
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

// ─── Shell Execution ──────────────────────────────────────────────────────────
// Runs an arbitrary shell command in the task-local cloned workspace.
// Requires the task to exist and belong to the caller.
// Returns stdout, stderr, exitCode, status, and durationMs.
// When sandboxed=true, wraps execution in a network-isolated Docker container
// (falls back to direct execution if Docker is unavailable).
interface ShellExecAgentTaskData {
  taskId: string;
  command: string;
  sandboxed?: boolean;
  timeoutMs?: number;
}

export const shellExecAgentTask = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const ownerId = await requireAuth(request);
  const data = (request.data ?? {}) as Partial<ShellExecAgentTaskData>;
  const taskId = asString(data.taskId, 'taskId');
  const command = asString(data.command, 'command');
  if (!command.trim()) {
    throw new HttpsError('invalid-argument', 'command must not be empty.');
  }
  const sandboxed = data.sandboxed === true;
  const timeoutMs = typeof data.timeoutMs === 'number' ? Math.min(data.timeoutMs, 300_000) : 60_000;

  const taskSnapshot = await agentTaskRef(ownerId, taskId).get();
  if (!taskSnapshot.exists) {
    throw new HttpsError('not-found', 'Agent task not found.');
  }
  const task = safeAgentTask(taskSnapshot.data());

  const workspace = await ensureAgentTaskLocalWorkspace(ownerId, taskId, task);

  // Stream the command start event.
  void appendStreamLogEntry(ownerId, taskId, {
    timestampMs: Date.now(),
    type: 'info',
    content: `$ ${command}`,
  });

  const result = await runOpenShellCommand({
    workspacePath: workspace.workspacePath,
    command,
    sandboxed,
    timeoutMs,
  });

  // Stream the output.
  if (result.stdout.trim()) {
    void appendStreamLogEntry(ownerId, taskId, {
      timestampMs: Date.now(),
      type: 'stdout',
      content: result.stdout.slice(0, 8000),
    });
  }
  if (result.stderr.trim()) {
    void appendStreamLogEntry(ownerId, taskId, {
      timestampMs: Date.now(),
      type: 'stderr',
      content: result.stderr.slice(0, 8000),
    });
  }
  void appendStreamLogEntry(ownerId, taskId, {
    timestampMs: Date.now(),
    type: result.status === 'passed' ? 'info' : 'error',
    content: `Exit ${result.exitCode ?? 'null'} (${result.status}) — ${result.durationMs}ms`,
  });

  return {
    exitCode: result.exitCode,
    stdout: result.stdout.slice(0, 50_000),
    stderr: result.stderr.slice(0, 50_000),
    output: result.output.slice(0, 50_000),
    status: result.status,
    durationMs: result.durationMs,
    sandboxed,
  };
});

// ---------------------------------------------------------------------------
// Vector Embeddings Index
// ---------------------------------------------------------------------------

interface IndexRepoEmbeddingsData {
  repoId?: unknown;
  /** Optional soft cap on files to embed per call (default: 200). */
  maxFiles?: unknown;
}

/**
 * Reads all text files for the given repo from the Firestore `files` sub-
 * collection (populated by `syncRepository`), generates OpenAI embeddings for
 * new or changed files, and stores them under `repositories/{repoId}/embeddings`.
 *
 * Safe to call repeatedly — only new/changed files are re-embedded.
 * Intended to be triggered after a repo is first connected or re-synced.
 */
export const indexRepoEmbeddings = onCall(
  {
    ...BASE_CALLABLE_OPTIONS,
    secrets: ['OPENAI_API_KEY'],
    timeoutSeconds: 300,
    memory: '1GiB',
  },
  async request => {
    requireAuth(request);
    const data = (request.data ?? {}) as Partial<IndexRepoEmbeddingsData>;
    const repoId = asString(data.repoId, 'repoId');
    const maxFiles =
      typeof data.maxFiles === 'number'
        ? Math.min(Math.max(data.maxFiles, 1), 500)
        : 200;

    // Load up to maxFiles text files from the repo's `files` sub-collection.
    // Each document has `path`, `content` / `contentPreview`, and `language`.
    const MAX_CONTENT_BYTES = 50 * 1024; // 50 KB per file
    const filesSnap = await db
      .collection('repositories')
      .doc(repoId)
      .collection('files')
      .limit(maxFiles)
      .get();

    if (filesSnap.empty) {
      return { indexed: 0, skipped: 0, total: 0, message: 'No files found for this repo.' };
    }

    const filesToEmbed: Array<{ path: string; content: string }> = [];
    for (const doc of filesSnap.docs) {
      const docData = doc.data() as Record<string, unknown>;
      const path = typeof docData['path'] === 'string' ? docData['path'] : doc.id;
      const rawContent =
        typeof docData['content'] === 'string'
          ? docData['content']
          : typeof docData['contentPreview'] === 'string'
            ? docData['contentPreview']
            : null;
      if (!rawContent || rawContent.trim().length === 0) continue;
      // Skip binary/large files.
      if (rawContent.length > MAX_CONTENT_BYTES) continue;
      filesToEmbed.push({ path, content: rawContent });
    }

    if (filesToEmbed.length === 0) {
      return {
        indexed: 0,
        skipped: filesSnap.size,
        total: filesSnap.size,
        message: 'All files were empty or exceeded the size limit.',
      };
    }

    const { indexed, skipped } = await indexFileEmbeddings(repoId, filesToEmbed);
    await markRepoEmbeddingsIndexed(repoId);

    functions.logger.info('indexRepoEmbeddings.complete', { repoId, indexed, skipped });

    return {
      indexed,
      skipped,
      total: filesToEmbed.length,
      message: `Indexed ${indexed} files (${skipped} unchanged/skipped).`,
    };
  },
);

export const cancelAgentTask = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const ownerId = await requireAuth(request);
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
  const ownerId = await requireAuth(request);
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
  const ownerId = await requireAuth(request);
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

function currentDistributedWorkerId() {
  const service = process.env.K_SERVICE ?? 'forgeai-worker'
  const revision = process.env.K_REVISION ?? 'local'
  return `${service}:${revision}:${process.pid}`
}

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
    const queueResult = await queueDistributedAgentWorkerRun({
      db,
      ownerId: event.params.ownerId,
      taskId: event.params.taskId,
      repoId: afterTask.repoId,
      queueWorkspaceId: afterTask.queueWorkspaceId,
      runToken: afterTask.runToken,
      phase: afterTask.phase,
      leaseDurationMs: AGENT_WORKER_LEASE_MS,
      metadata: {
        deepMode: afterTask.deepMode,
        retryCount: afterTask.retryCount,
        requestedProvider:
          isObject(afterTask.metadata) && typeof afterTask.metadata.requestedProvider === 'string'
            ? afterTask.metadata.requestedProvider
            : null,
      },
    });
    await agentTaskRef(event.params.ownerId, event.params.taskId).set(
      {
        metadata: {
          ...(isObject(afterTask.metadata) ? afterTask.metadata : {}),
          distributedRuntime: {
            ...(isObject(afterTask.metadata?.distributedRuntime)
              ? (afterTask.metadata?.distributedRuntime as Record<string, unknown>)
              : {}),
            dispatchMode: 'firestore_worker',
            dispatchCount:
              (isObject(afterTask.metadata?.distributedRuntime) &&
              typeof (afterTask.metadata?.distributedRuntime as Record<string, unknown>).dispatchCount === 'number'
                ? ((afterTask.metadata?.distributedRuntime as Record<string, unknown>).dispatchCount as number)
                : 0) + (queueResult.created ? 1 : 0),
            ...serializeDistributedWorkerMetadata({
              runId: queueResult.runId,
              state: 'queued',
              summary: 'Distributed worker queued for this run token.',
              phase: afterTask.phase,
            }),
          },
        },
        updatedAtMs: Date.now(),
      },
      { merge: true },
    );
  },
);

export const processDistributedAgentWorker = onDocumentCreated(
  {
    ...AGENT_WORKER_RUNTIME_OPTIONS,
    document: 'agentWorkerRuns/{runId}',
  },
  async event => {
    const snapshot = event.data;
    if (!snapshot?.exists) {
      return;
    }
    const workerRun = snapshot.data() as {
      ownerId?: string;
      taskId?: string;
      repoId?: string;
      runToken?: number;
      phase?: string;
    };
    const ownerId = typeof workerRun.ownerId === 'string' ? workerRun.ownerId : '';
    const taskId = typeof workerRun.taskId === 'string' ? workerRun.taskId : '';
    const repoId = typeof workerRun.repoId === 'string' ? workerRun.repoId : '';
    const runToken = typeof workerRun.runToken === 'number' ? workerRun.runToken : -1;
    if (!ownerId || !taskId || !repoId || runToken < 0) {
      return;
    }

    const workerId = currentDistributedWorkerId();
    const claim = await claimDistributedAgentWorkerRun({
      db,
      runId: event.params.runId,
      workerId,
      leaseDurationMs: AGENT_WORKER_LEASE_MS,
    });
    if (!claim.claimed || !claim.workerRun) {
      return;
    }
    const claimedPhase =
      (typeof workerRun.phase === 'string' ? workerRun.phase : 'analyze_request') as AgentTaskPhase;
    const taskSnapshotBeforeWorker = await agentTaskRef(ownerId, taskId).get();
    const liveTaskBeforeWorker =
      taskSnapshotBeforeWorker.exists ? safeAgentTask(taskSnapshotBeforeWorker.data()) : null;

    await agentTaskRef(ownerId, taskId).set(
      {
        metadata: {
          ...(isObject(liveTaskBeforeWorker?.metadata) ? liveTaskBeforeWorker?.metadata : {}),
          distributedRuntime: {
            ...serializeDistributedWorkerMetadata({
              runId: event.params.runId,
              state: 'running',
              workerId,
              summary: 'Distributed worker claimed the task run.',
              heartbeatAtMs: Date.now(),
              claimedAtMs: Date.now(),
              phase: claimedPhase,
            }),
          },
        },
        updatedAtMs: Date.now(),
      },
      { merge: true },
    );
    await appendAgentTaskEvent({
      ownerId,
      taskId,
      type: 'task_started',
      step: 'Distributed worker claimed',
      message: 'A distributed worker claimed this run and started the full agent loop.',
      status: 'running',
      phase: liveTaskBeforeWorker?.phase ?? claimedPhase,
      data: {
        workerRunId: event.params.runId,
        workerId,
      },
    });
    await appendDistributedWorkerMetric({
      db,
      runId: event.params.runId,
      metricType: 'worker_claimed',
      payload: {
        ownerId,
        taskId,
        repoId,
        runToken,
        workerId,
      },
    });

    const heartbeat = setInterval(() => {
      void heartbeatDistributedAgentWorkerRun({
        db,
        runId: event.params.runId,
        workerId,
        summary: 'Distributed worker heartbeat active during agent loop.',
      })
    }, AGENT_WORKER_HEARTBEAT_MS)

    try {
      await processAgentTaskRun(ownerId, taskId, runToken);
      clearInterval(heartbeat)
      const taskSnapshot = await agentTaskRef(ownerId, taskId).get()
      const task = taskSnapshot.exists ? safeAgentTask(taskSnapshot.data()) : null
      await finalizeDistributedAgentWorkerRun({
        db,
        runId: event.params.runId,
        workerId,
        state: task && isAgentTaskFinalStatus(task.status) ? 'completed' : 'completed',
        summary:
          task?.status === 'waiting_for_input'
            ? 'Distributed worker finished its current pass and parked at an approval checkpoint.'
            : task?.resultSummary ?? 'Distributed worker completed the current agent pass.',
        phase: task?.phase ?? claimedPhase,
        metadata: {
          taskStatus: task?.status ?? null,
          resultSummary: task?.resultSummary ?? null,
          costSummary: summarizeAgentCostLedger(task?.metadata),
          logicalAgentSummary: summarizeLogicalAgentTimeline(task?.metadata),
        },
      })
      await agentTaskRef(ownerId, taskId).set(
        {
          metadata: {
            ...(isObject(task?.metadata) ? task?.metadata : {}),
            distributedRuntime: {
              ...serializeDistributedWorkerMetadata({
                runId: event.params.runId,
                state: 'completed',
                workerId,
                summary:
                  task?.status === 'waiting_for_input'
                    ? 'Worker finished the current pass and is waiting for approval.'
                    : 'Worker finished the current pass.',
                heartbeatAtMs: Date.now(),
                completedAtMs: Date.now(),
                phase: task?.phase ?? claimedPhase,
              }),
            },
          },
          updatedAtMs: Date.now(),
        },
        { merge: true },
      )
    } catch (error) {
      clearInterval(heartbeat)
      if (error instanceof AgentTaskStopError) {
        await finalizeDistributedAgentWorkerRun({
          db,
          runId: event.params.runId,
          workerId,
          state: error.kind === 'cancelled' ? 'cancelled' : 'completed',
          summary:
            error.kind === 'paused'
              ? 'Worker paused after reaching a checkpoint.'
              : error.kind === 'superseded'
                ? 'Worker stopped because a newer run token superseded this pass.'
                : 'Worker stopped after task cancellation.',
        })
        return;
      }
      const normalizedError = normalizeError(error);
      functions.logger.error('agent_task.worker.failed', {
        ownerId,
        taskId,
        runId: event.params.runId,
        errorCode: normalizedError.code,
        errorMessage: normalizedError.message,
      });
      await finalizeDistributedAgentWorkerRun({
        db,
        runId: event.params.runId,
        workerId,
        state: 'failed',
        summary: normalizedError.message,
        metadata: {
          errorCode: normalizedError.code,
        },
      })
      await failAgentTaskNow(ownerId, taskId, normalizedError.message)
    }
  },
);

export const recoverStaleAgentWorkers = onSchedule(
  {
    region: runtimeSettings.firebaseRegion,
    schedule: 'every 5 minutes',
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async () => {
    const staleRuns = await recoverStaleDistributedAgentWorkerRuns({
      db,
      staleAfterMs: DISTRIBUTED_AGENT_STALE_WORKER_MS,
      limit: 50,
    })
    for (const staleRun of staleRuns) {
      try {
        const taskReference = agentTaskRef(staleRun.ownerId, staleRun.taskId)
        const snapshot = await taskReference.get()
        if (!snapshot.exists) {
          continue
        }
        const task = safeAgentTask(snapshot.data())
        if (task.status !== 'running' || task.runToken !== staleRun.runToken) {
          continue
        }
        const now = Date.now()
        await taskReference.set(
          {
            currentStep: 'Recovering stale worker',
            runToken: task.runToken + 1,
            updatedAtMs: now,
            metadata: {
              ...(isObject(task.metadata) ? task.metadata : {}),
              distributedRuntime: {
                ...(isObject(task.metadata?.distributedRuntime)
                  ? (task.metadata?.distributedRuntime as Record<string, unknown>)
                  : {}),
                staleRecoveryCount:
                  (isObject(task.metadata?.distributedRuntime) &&
                  typeof (task.metadata?.distributedRuntime as Record<string, unknown>).staleRecoveryCount === 'number'
                    ? ((task.metadata?.distributedRuntime as Record<string, unknown>).staleRecoveryCount as number)
                    : 0) + 1,
                latestWorkerRunId: staleRun.runId,
                latestWorkerState: 'stale',
                latestWorkerSummary: 'Recovering a stale distributed worker lease.',
                latestWorkerCompletedAtMs: now,
              },
            },
          },
          { merge: true },
        )
        await appendAgentTaskEvent({
          ownerId: staleRun.ownerId,
          taskId: staleRun.taskId,
          type: 'retrying',
          step: 'Recovering stale worker',
          message: 'The previous distributed worker lease went stale, so the task is being re-dispatched safely.',
          status: 'running',
          phase: task.phase,
          data: {
            staleWorkerRunId: staleRun.runId,
          },
        })
      } catch (error) {
        functions.logger.warn('agent_task.worker_recovery_failed', {
          runId: staleRun.runId,
          errorMessage: normalizeError(error).message,
        })
      }
    }
  },
);

export const loadRepositoryFile = onCall(GIT_CALLABLE_OPTIONS, async request => {
  const startedAt = Date.now();
  const ownerId = await requireAuth(request);
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

// DEPRECATED — Legacy single-file suggestion endpoint. The app now generates reviewable,
// multi-file repo execution sessions via enqueueAgentTask with full sandbox validation and
// approval gates. Retained for backward compatibility with old clients only. New code must
// not call this function.
export const suggestChange = onCall(GIT_AND_AI_CALLABLE_OPTIONS, async request => {
  const startedAt = Date.now();
  const ownerId = await requireAuth(request);
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
    'Pre-authorized legacy AI draft preview.',
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
      'Legacy AI draft generated successfully.',
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

  await writeActivityEntry(ownerId, 'ai', changeRef.id, `Created legacy AI draft for ${filePath}.`, {
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
    body: `Your legacy AI draft for ${filePath} is ready in CodeCatalystAI.`,
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
  const ownerId = await requireAuth(request);
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
  const ownerId = await requireAuth(request);
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
  const ownerId = await requireAuth(request);
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
    source: 'manual_check',
    monitorState: confirmed ? 'pending' : 'idle',
    startedAtMs: Date.now(),
    logsUrl: null,
    summary: null,
    findings: [],
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
        status: 'running',
        executionState: remoteResult.status,
        logsUrl: remoteResult.logsUrl,
        remoteId: remoteResult.remoteId,
        summary: `${workflowName} triggered from CodeCatalystAI. Monitoring workflow progress now.`,
        monitorState: 'pending',
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
      status: 'running',
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

function timestampLikeToMillis(value: unknown) {
  if (value instanceof Timestamp) {
    return value.toMillis();
  }
  if (isObject(value) && typeof value.toMillis === 'function') {
    try {
      const millis = value.toMillis();
      return typeof millis === 'number' ? millis : null;
    } catch (_) {
      return null;
    }
  }
  return typeof value === 'number' ? value : null;
}

export const monitorCheckRun = onDocumentWritten(
  {
    ...CHECK_MONITOR_RUNTIME_OPTIONS,
    document: 'checksRuns/{checkRunId}',
  },
  async event => {
    if (!event.data) {
      return;
    }
    const after = event.data.after;
    if (!after.exists) {
      return;
    }
    const beforeData = event.data.before.exists ? event.data.before.data() : null;
    const afterData = after.data() as Record<string, unknown>;
    if ((typeof afterData.source === 'string' ? afterData.source : null) !== 'manual_check') {
      return;
    }
    if (afterData.status !== 'running') {
      return;
    }
    if (
      (typeof afterData.monitorState === 'string'
        ? afterData.monitorState
        : null) !== 'pending'
    ) {
      return;
    }
    if (
      (typeof beforeData?.monitorState === 'string'
        ? beforeData.monitorState
        : null) === 'running'
    ) {
      return;
    }
    await after.ref.set(
      {
        monitorState: 'running',
        monitorStartedAtMs: Date.now(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const ownerId = typeof afterData.ownerId === 'string' ? afterData.ownerId : '';
    const repoId = typeof afterData.repoId === 'string' ? afterData.repoId : '';
    const workflowName =
      typeof afterData.workflowName === 'string' ? afterData.workflowName : '';
    const ref = typeof afterData.ref === 'string' ? afterData.ref : 'main';
    const provider = afterData.provider === 'github' ? 'github' : null;
    if (!ownerId || !repoId || !workflowName || !provider) {
      await after.ref.set(
        {
          status: 'failed',
          executionState: 'failed',
          summary: 'Check monitor could not read the workflow configuration for this run.',
          monitorState: 'completed',
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }
    let repo: Awaited<ReturnType<typeof ensureRepositoryAccess>>;
    try {
      repo = await ensureRepositoryAccess(repoId, ownerId);
    } catch (error) {
      await after.ref.set(
        {
          status: 'failed',
          executionState: 'failed',
          summary: normalizeError(error).message,
          monitorState: 'completed',
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }
    const tokenInfo = await resolveProviderToken(ownerId, provider);
    if (!tokenInfo) {
      await after.ref.set(
        {
          status: 'failed',
          executionState: 'awaiting_provider_configuration',
          summary: `No ${providerLabel(provider)} token is configured for workflow monitoring.`,
          monitorState: 'completed',
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }
    const dispatchStartedAtMs =
      timestampLikeToMillis(afterData.createdAt) ??
      timestampLikeToMillis(afterData.updatedAt) ??
      timestampLikeToMillis(afterData.startedAtMs) ??
      Date.now();
    try {
      const runResult = await waitForGitHubWorkflowRun({
        token: tokenInfo.token,
        owner: repo.owner ?? '',
        name: repo.name ?? '',
        workflowName,
        ref,
        dispatchStartedAtMs,
        apiBaseUrl: repo.apiBaseUrl ?? undefined,
      });
      const failureNotes = [...runResult.failedJobs, ...runResult.failedSteps].slice(0, 10);
      const findings =
        runResult.findings.length > 0
          ? runResult.findings.slice(0, 12)
          : failureNotes.map<AgentValidationFinding>(message => ({
              severity: 'error',
              source: 'ci_workflow',
              message,
            }));
      const passed =
        runResult.timedOut !== true && runResult.conclusion === 'success';
      const summary = runResult.timedOut
        ? `${workflowName} did not finish within the validation window.`
        : passed
          ? `${workflowName} passed.`
          : `${workflowName} failed.`;
      await after.ref.set(
        buildCompletedCheckRunPayload({
          summary,
          passed,
          timedOut: runResult.timedOut,
          remoteId:
            runResult.runId ??
            (typeof afterData.remoteId === 'string' ||
                    typeof afterData.remoteId === 'number'
              ? afterData.remoteId
              : null),
          logsUrl:
            runResult.htmlUrl ??
            (typeof afterData.logsUrl === 'string' ? afterData.logsUrl : null),
          runStatus: runResult.status,
          runConclusion: runResult.conclusion,
          failureNotes,
          findings,
        }),
        { merge: true },
      );
    } catch (error) {
      const normalizedError = normalizeError(error);
      await after.ref.set(
        {
          status: 'failed',
          executionState: 'failed',
          summary: normalizedError.message,
          errorMessage: normalizedError.message,
          monitorState: 'completed',
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
  },
);

export const reserveTokens = onCall(BASE_CALLABLE_OPTIONS, async request => {
  const ownerId = await requireAuth(request);
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
  const ownerId = await requireAuth(request);
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
  const ownerId = await requireAuth(request);
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
  const ownerId = await requireAuth(request);
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
  const ownerId = await requireAuth(request);
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
