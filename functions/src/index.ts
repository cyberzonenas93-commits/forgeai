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

const MAX_AGENT_RECRUIT_ROUNDS = 3;

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

  let rounds = 0;
  while (rounds < MAX_AGENT_RECRUIT_ROUNDS) {
    rounds += 1;
    const body: Record<string, unknown> = {
      model,
      temperature: 0.3,
      max_completion_tokens: 2000,
      messages,
      tools: [{ type: 'function', function: RECRUIT_AGENT_TOOL.function }],
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
        if (tc.function.name !== 'recruit_agent') {
          messages.push({ role: 'tool', tool_call_id: tc.id, content: 'Unknown tool.' });
          continue;
        }
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
      if (!mimeType.startsWith('image/') || dataBase64.length < 32 || dataBase64.length > 3_000_000) {
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

  let repoContext = 'The user is not currently in a specific repository.';
  const searchTerms = buildRepoSearchTerms(prompt, history);
  let inspectedFilesForTrace: string[] = [];
  if (data.repoId) {
    const repo = await ensureRepositoryAccess(data.repoId, ownerId);
    const fullName = repo.fullName ?? `${repo.owner}/${repo.name}`;
    const filesSnapshot = await db
      .collection('repositories')
      .doc(data.repoId)
      .collection('files')
      .limit(220)
      .get();
    const fileRows = filesSnapshot.docs.map(d => {
      const raw = d.data() as { path?: string; content?: string };
      return {
        path: typeof raw.path === 'string' ? raw.path : d.id,
        content: typeof raw.content === 'string' ? raw.content : '',
      };
    });
    const paths = fileRows.map(r => r.path).filter(Boolean).slice(0, 140);
    const ranked = fileRows
      .map(file => ({
        ...file,
        score: scoreRepoFileForPrompt(file.path, file.content, searchTerms),
      }))
      .filter(file => file.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, 8);
    inspectedFilesForTrace = ranked.map(file => file.path);
    const relevantSnippets = ranked
      .map(file => {
        const normalized = normalizeText(file.content);
        const shortBody = truncate(normalized, 900);
        if (!shortBody) {
          return `- ${file.path} (matched by path/metadata)`;
        }
        return `- ${file.path}: ${shortBody}`;
      })
      .join('\n');
    repoContext = `The user is in repository: ${fullName}. Files in the repo (up to 140): ${paths.join(', ') || '(none synced yet)'}.

Likely relevant files/snippets for this request:
${relevantSnippets || '(no strong matches from synced content yet)'}`;
  } else {
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

    const sampledRepoContexts = await Promise.all(
      repos.slice(0, 10).map(async repo => {
        const filesSnapshot = await db
          .collection('repositories')
          .doc(repo.id)
          .collection('files')
          .limit(25)
          .get();
        const paths = filesSnapshot.docs
          .map(d => (d.data().path as string) ?? d.id)
          .filter(Boolean)
          .slice(0, 25);
        return `${repo.fullName}: ${paths.join(', ') || '(none synced yet)'}`;
      }),
    );

    repoContext = `The user selected ALL projects. They have ${repos.length} connected repositories. Repository list: ${repos
      .map(r => r.fullName)
      .join(', ') || '(none connected)'}. Sample file index across repositories: ${sampledRepoContexts.join(' | ') || '(no files indexed yet)'}.`;
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

  const systemPrompt = `You are CodeCatalystAI, an autonomous coding agent on mobile. Behave like a strong IDE coding assistant: confident, practical, and action-first. The user has connected repositories and expects you to work from repo context immediately.

${repoContext}

${dangerMode ? 'Advanced mode: provide decisive implementation guidance and concrete next steps. Still avoid unsafe or impossible claims.' : 'Standard mode: stay concise and practical; ask a short clarifying question only when absolutely required to avoid a wrong answer.'}

How to write replies (this matters most):
- Sound human: warm, conversational plain English—like a skilled coworker texting back, not a server log or API doc.
- Avoid: fake log lines ("INFO:", "Result:", "Step 1/3"), robotic bullet walls, tables of metadata, or syntax-heavy dumps unless they asked for raw output.
- Prefer: short paragraphs, natural phrasing, and code blocks only when code helps. If you use bullets, keep them light and readable.
- Do not narrate your process ("I will now analyze…") unless it genuinely helps.
- Never claim you "don't have enough info about the repo" when repo context exists above. Start with the best actionable answer using that context.
- Do not ask the user to locate files for you as a first step. First, name the likely files/modules yourself and propose concrete edits.

When you need deeper expertise (security, naming, refactor plan, explanation), you may use the recruit_agent tool with a clear role and task; weave the result into your answer in normal language. Do not over-use it for simple questions.

When they ask to make or fix something, default to execution mode (like Cursor): act as if you are making the edits now, name the exact files you will touch, describe the concrete changes in order, and include ready-to-apply code for each changed area. Avoid "just run this" style replies unless a required permission or secret is missing.
If they ask to deploy Firebase functions via git, remind them they can type **deploy functions** or **deploy firebase** in Prompt (dispatches deploy-functions.yml) after adding that workflow and one auth secret in repo Actions secrets: FIREBASE_TOKEN (easy) or FIREBASE_SERVICE_ACCOUNT (recommended)—or use Prompt tools.
If they ask to run the app via git, remind them they can type **run app**, **run the app**, or **run app via git** in Prompt (dispatches run-app.yml) or use Prompt tools → Run app via Git. Mention installing workflows if missing: **install run app** / **install deploy workflow**.

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
    },
  };
});

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
  const fileChanges = Array.isArray(data.fileChanges)
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
