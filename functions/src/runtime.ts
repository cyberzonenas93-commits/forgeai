import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export type ProviderName = 'github' | 'openai' | 'anthropic' | 'gemini';
export type AiProviderName = Extract<ProviderName, 'openai' | 'anthropic' | 'gemini'>;
export type ForgeAppEnv = 'local' | 'beta' | 'production';

export const PROVIDER_NAMES: readonly ProviderName[] = [
  'github',
  'openai',
  'anthropic',
  'gemini',
];

export const AI_PROVIDER_NAMES: readonly AiProviderName[] = [
  'openai',
  'anthropic',
  'gemini',
];

const PROVIDER_SECRET_MAP: Record<ProviderName, string[]> = {
  github: ['GITHUB_TOKEN', 'GITHUB_APP_TOKEN'],
  openai: ['OPENAI_API_KEY'],
  anthropic: ['ANTHROPIC_API_KEY'],
  gemini: ['GEMINI_API_KEY', 'GOOGLE_API_KEY'],
};

export const MANAGED_SECRET_NAMES = Array.from(
  new Set(Object.values(PROVIDER_SECRET_MAP).flat()),
);

let localEnvLoaded = false;

function parseEnvFile(content: string) {
  const entries: Record<string, string> = {};
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) {
      continue;
    }
    const separatorIndex = line.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }
    const key = line.slice(0, separatorIndex).trim();
    if (!key) {
      continue;
    }
    const rawValue = line.slice(separatorIndex + 1).trim();
    const value =
      rawValue.startsWith('"') && rawValue.endsWith('"')
        ? rawValue.slice(1, -1)
        : rawValue.startsWith("'") && rawValue.endsWith("'")
          ? rawValue.slice(1, -1)
          : rawValue;
    entries[key] = value;
  }
  return entries;
}

export function loadLocalEnvFiles() {
  if (localEnvLoaded) {
    return;
  }
  const baseCandidatePaths = [
    resolve(__dirname, '..', '.env.local'),
    resolve(__dirname, '..', '.env'),
    resolve(__dirname, '..', '..', '.env.local'),
    resolve(__dirname, '..', '..', '.env'),
  ];

  for (const filePath of baseCandidatePaths) {
    if (!existsSync(filePath)) {
      continue;
    }
    const parsed = parseEnvFile(readFileSync(filePath, 'utf8'));
    for (const [key, value] of Object.entries(parsed)) {
      if (!process.env[key]) {
        process.env[key] = value;
      }
    }
  }

  const projectId =
    process.env.FORGEAI_FIREBASE_PROJECT ??
    process.env.FIREBASE_PROJECT_ID ??
    process.env.GCLOUD_PROJECT ??
    process.env.GCP_PROJECT ??
    '';
  const appEnv = process.env.FORGEAI_ENV ?? process.env.FORGEAI_APP_ENV ?? '';
  const scopedCandidatePaths = [
    projectId
      ? resolve(__dirname, '..', `.env.${projectId}`)
      : null,
    projectId
      ? resolve(__dirname, '..', `.env.${projectId}.local`)
      : null,
    appEnv
      ? resolve(__dirname, '..', `.env.${appEnv}`)
      : null,
    appEnv
      ? resolve(__dirname, '..', `.env.${appEnv}.local`)
      : null,
  ].filter((value): value is string => Boolean(value));

  for (const filePath of scopedCandidatePaths) {
    if (!existsSync(filePath)) {
      continue;
    }
    const parsed = parseEnvFile(readFileSync(filePath, 'utf8'));
    for (const [key, value] of Object.entries(parsed)) {
      if (!process.env[key]) {
        process.env[key] = value;
      }
    }
  }

  localEnvLoaded = true;
}

function parseProviderList(rawValue: string | undefined) {
  if (!rawValue) {
    return [] as ProviderName[];
  }
  return rawValue
    .split(',')
    .map(item => item.trim().toLowerCase())
    .filter((item): item is ProviderName => PROVIDER_NAMES.includes(item as ProviderName));
}

function parseAppEnv(rawValue: string | undefined): ForgeAppEnv {
  switch ((rawValue ?? '').trim().toLowerCase()) {
    case 'production':
    case 'prod':
      return 'production';
    case 'beta':
    case 'staging':
      return 'beta';
    default:
      return 'local';
  }
}

export function providerSecretNames(provider: ProviderName) {
  return [...PROVIDER_SECRET_MAP[provider]];
}

export function lookupProviderToken(provider: ProviderName) {
  loadLocalEnvFiles();
  const secretNames = providerSecretNames(provider);
  for (const secretName of secretNames) {
    const token = process.env[secretName];
    if (typeof token === 'string' && token.trim().length > 0) {
      return { token: token.trim(), secretName };
    }
  }
  return null;
}

export function githubAuthCallbackUrl(projectId: string | null) {
  if (!projectId) {
    return null;
  }
  return `https://${projectId}.firebaseapp.com/__/auth/handler`;
}

export interface RuntimeSettings {
  appEnv: ForgeAppEnv;
  projectId: string | null;
  strictValidation: boolean;
  requiredProviders: ProviderName[];
  firebaseRegion: string;
  githubOAuthCallbackUrl: string | null;
}

export interface RuntimeValidation {
  ok: boolean;
  missingCore: string[];
  missingProviders: ProviderName[];
  settings: RuntimeSettings;
}

export function currentRuntimeSettings(): RuntimeSettings {
  loadLocalEnvFiles();
  const projectId =
    process.env.FORGEAI_FIREBASE_PROJECT_ID ??
    process.env.FORGEAI_FIREBASE_PROJECT ??
    process.env.FIREBASE_PROJECT_ID ??
    process.env.GCLOUD_PROJECT ??
    process.env.GCP_PROJECT ??
    null;

  return {
    appEnv: parseAppEnv(process.env.FORGEAI_ENV ?? process.env.FORGEAI_APP_ENV),
    projectId,
    strictValidation:
      (
        process.env.FORGEAI_ENFORCE_PROVIDER_SECRETS ??
        process.env.FORGEAI_STRICT_ENV_VALIDATION ??
        ''
      )
        .trim()
        .toLowerCase() === 'true',
    requiredProviders: parseProviderList(
      process.env.FORGEAI_REQUIRED_PROVIDERS,
    ),
    firebaseRegion: (process.env.FORGEAI_FIREBASE_REGION ?? 'us-central1').trim(),
    githubOAuthCallbackUrl: githubAuthCallbackUrl(projectId),
  };
}

export function validateRuntimeConfiguration(): RuntimeValidation {
  const settings = currentRuntimeSettings();
  const missingCore: string[] = [];

  if (!settings.projectId) {
    missingCore.push('FORGEAI_FIREBASE_PROJECT_ID');
  }

  const missingProviders = settings.requiredProviders.filter(
    provider => lookupProviderToken(provider) == null,
  );

  return {
    ok: missingCore.length === 0 && missingProviders.length === 0,
    missingCore,
    missingProviders,
    settings,
  };
}

export function assertRuntimeConfiguration() {
  const validation = validateRuntimeConfiguration();
  if (!validation.ok && validation.settings.strictValidation) {
    const missingSegments = [
      validation.missingCore.length > 0
        ? `core env: ${validation.missingCore.join(', ')}`
        : null,
      validation.missingProviders.length > 0
        ? `provider secrets: ${validation.missingProviders.join(', ')}`
        : null,
    ].filter(Boolean);
    throw new Error(
      `CodeCatalystAI runtime validation failed: ${missingSegments.join(' | ')}`,
    );
  }
  return validation;
}
