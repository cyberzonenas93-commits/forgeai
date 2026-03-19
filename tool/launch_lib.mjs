import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const repoRoot = path.resolve(__dirname, '..');

export const providerSecretMap = {
  github: ['GITHUB_TOKEN', 'GITHUB_APP_TOKEN'],
  openai: ['OPENAI_API_KEY'],
  anthropic: ['ANTHROPIC_API_KEY'],
  gemini: ['GEMINI_API_KEY', 'GOOGLE_API_KEY'],
};

export const providerNames = Object.keys(providerSecretMap);

export function fileExists(relativePath) {
  return fs.existsSync(path.join(repoRoot, relativePath));
}

export function readJson(relativePath, fallback = null) {
  try {
    return JSON.parse(
      fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'),
    );
  } catch {
    return fallback;
  }
}

export function readText(relativePath, fallback = '') {
  try {
    return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
  } catch {
    return fallback;
  }
}

export function parseEnvFile(content) {
  const values = {};
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
    const rawValue = line.slice(separatorIndex + 1).trim();
    values[key] = stripQuotes(rawValue);
  }
  return values;
}

function stripQuotes(value) {
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }
  return value;
}

export function loadMergedEnv() {
  const merged = {};
  const baseCandidateFiles = [
    '.env',
    '.env.local',
    'functions/.env',
    'functions/.env.local',
  ];

  for (const relativePath of baseCandidateFiles) {
    const absolutePath = path.join(repoRoot, relativePath);
    if (!fs.existsSync(absolutePath)) {
      continue;
    }
    Object.assign(merged, parseEnvFile(fs.readFileSync(absolutePath, 'utf8')));
  }

  const scopedProjectId =
    merged.FORGEAI_FIREBASE_PROJECT ??
    merged.FORGEAI_FIREBASE_PROJECT_ID ??
    merged.FIREBASE_PROJECT_ID ??
    merged.GCLOUD_PROJECT ??
    merged.GCP_PROJECT ??
    null;
  const scopedAppEnv = merged.FORGEAI_ENV ?? merged.FORGEAI_APP_ENV ?? null;
  const scopedCandidateFiles = [
    scopedProjectId ? `functions/.env.${scopedProjectId}` : null,
    scopedProjectId ? `functions/.env.${scopedProjectId}.local` : null,
    scopedAppEnv ? `functions/.env.${scopedAppEnv}` : null,
    scopedAppEnv ? `functions/.env.${scopedAppEnv}.local` : null,
  ].filter(Boolean);

  for (const relativePath of scopedCandidateFiles) {
    const absolutePath = path.join(repoRoot, relativePath);
    if (!fs.existsSync(absolutePath)) {
      continue;
    }
    Object.assign(merged, parseEnvFile(fs.readFileSync(absolutePath, 'utf8')));
  }

  for (const [key, value] of Object.entries(process.env)) {
    if (typeof value === 'string') {
      merged[key] = value;
    }
  }

  return merged;
}

export function readDefaultFirebaseProject() {
  const firebaserc = readJson('.firebaserc', {});
  return firebaserc?.projects?.default ?? null;
}

export function parseProviderList(rawValue) {
  if (!rawValue) {
    return [];
  }
  return rawValue
    .split(',')
    .map(item => item.trim().toLowerCase())
    .filter(item => providerNames.includes(item));
}

export function parseBoolean(rawValue, fallback = false) {
  if (rawValue == null || rawValue === '') {
    return fallback;
  }
  return ['1', 'true', 'yes', 'on'].includes(String(rawValue).toLowerCase());
}

export function githubCallbackUrl(projectId) {
  return projectId ? `https://${projectId}.firebaseapp.com/__/auth/handler` : null;
}

export function collectLaunchContext() {
  const env = loadMergedEnv();
  const launchConfig = readJson('config/launch-config.json', {});
  const defaultProjectId = readDefaultFirebaseProject();
  const projectId =
    env.FORGEAI_FIREBASE_PROJECT ??
    env.FORGEAI_FIREBASE_PROJECT_ID ??
    env.FIREBASE_PROJECT_ID ??
    env.GCLOUD_PROJECT ??
    env.GCP_PROJECT ??
    defaultProjectId ??
    null;

  const appEnv = (
    env.FORGEAI_ENV ??
    env.FORGEAI_APP_ENV ??
    'beta'
  ).toLowerCase();
  const requiredProviders = parseProviderList(
    env.FORGEAI_REQUIRED_PROVIDERS ??
      (appEnv === 'production'
        ? 'github,openai,anthropic,gemini'
        : appEnv === 'beta'
          ? 'github,openai'
          : 'openai'),
  );
  const providerReadiness = Object.fromEntries(
    providerNames.map(provider => [
      provider,
      {
        secretNames: providerSecretMap[provider],
        presentSecretNames: providerSecretMap[provider].filter(
          name => typeof env[name] === 'string' && env[name].trim().length > 0,
        ),
      },
    ]),
  );

  const appFiles = {
    launchConfig: fileExists('config/launch-config.json'),
    firebaseJson: fileExists('firebase.json'),
    firebaserc: fileExists('.firebaserc'),
    firestoreRules: fileExists('firestore.rules'),
    firestoreIndexes: fileExists('firestore.indexes.json'),
    googleServices: fileExists('google-services.json'),
    googleServiceInfo: fileExists('GoogleService-Info.plist'),
    androidKeyProperties: fileExists('android/key.properties'),
    iosEntitlements: fileExists('ios/Runner/Runner.entitlements'),
    releaseConfig: fileExists('RELEASE_CONFIG.md'),
    providersSetup: fileExists('PROVIDERS_SETUP.md'),
    deploymentDoc: fileExists('DEPLOYMENT.md'),
    smokeTestsDoc: fileExists('SMOKE_TESTS.md'),
    observabilityDoc: fileExists('OBSERVABILITY.md'),
    tokenEconomicsDoc: fileExists('TOKEN_ECONOMICS.md'),
    betaReleasePlan: fileExists('BETA_RELEASE_PLAN.md'),
    iosGoogleSchemeConfigured: Boolean(
      launchConfig?.app?.iosGoogleReversedClientId &&
        readText('ios/Runner/Info.plist').includes(
          launchConfig.app.iosGoogleReversedClientId,
        ),
    ),
    iosFirebaseAuthSchemeConfigured: Boolean(
      launchConfig?.app?.iosFirebaseEncodedAppIdScheme &&
        readText('ios/Runner/Info.plist').includes(
          launchConfig.app.iosFirebaseEncodedAppIdScheme,
        ),
    ),
  };

  return {
    env,
    appEnv,
    projectId,
    defaultProjectId,
    requiredProviders,
    providerReadiness,
    appFiles,
    callbacks: {
      githubAuth: githubCallbackUrl(projectId),
      iosGoogleSignIn: launchConfig?.app?.iosGoogleReversedClientId ?? null,
      iosFirebaseAuth: launchConfig?.app?.iosFirebaseEncodedAppIdScheme ?? null,
    },
    smoke: {
      firebaseUserEmail:
        env.SMOKE_TEST_FIREBASE_USER_EMAIL ??
        env.FORGEAI_SMOKE_FIREBASE_USER_EMAIL ??
        '',
      githubRepo:
        env.SMOKE_TEST_GITHUB_REPO ?? env.FORGEAI_SMOKE_GITHUB_REPO ?? '',
      githubBranchPrefix:
        env.SMOKE_TEST_GITHUB_BRANCH_PREFIX ??
        env.SMOKE_TEST_BRANCH_PREFIX ??
        env.FORGEAI_SMOKE_GITHUB_BRANCH_PREFIX ??
        'beta/smoke/',
    },
  };
}

export function summarizeValidation(context) {
  const errors = [];
  const warnings = [];

  if (!context.projectId) {
    errors.push('Missing Firebase project id.');
  }
  if (!context.appFiles.firebaseJson) {
    errors.push('Missing firebase.json.');
  }
  if (!context.appFiles.launchConfig) {
    errors.push('Missing config/launch-config.json.');
  }
  if (!context.appFiles.firebaserc) {
    errors.push('Missing .firebaserc.');
  }
  if (!context.appFiles.firestoreRules) {
    errors.push('Missing firestore.rules.');
  }
  if (!context.appFiles.firestoreIndexes) {
    errors.push('Missing firestore.indexes.json.');
  }
  if (!context.appFiles.googleServices) {
    errors.push('Missing google-services.json.');
  }
  if (!context.appFiles.googleServiceInfo) {
    errors.push('Missing GoogleService-Info.plist.');
  }

  for (const provider of context.requiredProviders) {
    if (context.providerReadiness[provider].presentSecretNames.length === 0) {
      errors.push(
        `Missing required provider secret for ${provider}: ${context.providerReadiness[
          provider
        ].secretNames.join(' or ')}.`,
      );
    }
  }

  if (!context.appFiles.androidKeyProperties) {
    warnings.push(
      'Android release signing file android/key.properties is missing.',
    );
  }
  if (!context.appFiles.iosEntitlements) {
    warnings.push(
      'iOS entitlements file is missing; Sign in with Apple may not be App Store-ready.',
    );
  }
  if (!context.appFiles.iosGoogleSchemeConfigured) {
    warnings.push('iOS Google Sign-In URL scheme is not configured in Info.plist.');
  }
  if (!context.appFiles.iosFirebaseAuthSchemeConfigured) {
    warnings.push('iOS Firebase Auth URL scheme is not configured in Info.plist.');
  }
  if (!context.smoke.githubRepo) {
    warnings.push('GitHub smoke-test repository is not configured.');
  }
  if (!context.smoke.firebaseUserEmail) {
    warnings.push('Firebase smoke-test user email is not configured.');
  }

  return { errors, warnings };
}

export function runCommand(command, args, options = {}) {
  return spawnSync(command, args, {
    cwd: repoRoot,
    stdio: 'inherit',
    shell: false,
    ...options,
  });
}

export function printList(title, items) {
  console.log(title);
  if (items.length === 0) {
    console.log('  - none');
    return;
  }
  for (const item of items) {
    console.log(`  - ${item}`);
  }
}
