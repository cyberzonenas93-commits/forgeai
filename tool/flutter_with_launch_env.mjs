#!/usr/bin/env node

import { spawnSync } from 'node:child_process';

import { collectLaunchContext } from './launch_lib.mjs';

const passthroughArgs = process.argv.slice(2);

if (passthroughArgs.length === 0) {
  console.error('Usage: node ./tool/flutter_with_launch_env.mjs <flutter args...>');
  process.exit(1);
}

const env = collectLaunchContext().env;
const dartDefines = [
  ['FORGEAI_ENV', env.FORGEAI_ENV ?? env.FORGEAI_APP_ENV ?? 'beta'],
  [
    'FORGEAI_BETA_CHANNEL',
    env.FORGEAI_BETA_CHANNEL ?? env.FORGEAI_RELEASE_CHANNEL ?? 'internal',
  ],
  ['FORGEAI_ENABLE_ANALYTICS', env.FORGEAI_ENABLE_ANALYTICS ?? 'true'],
  ['FORGEAI_ENABLE_CRASHLYTICS', env.FORGEAI_ENABLE_CRASHLYTICS ?? 'true'],
  [
    'FORGEAI_ENABLE_SCREENSHOT_STUDIO',
    env.FORGEAI_ENABLE_SCREENSHOT_STUDIO ??
      env.FORGEAI_ENABLE_SCREENSHOT_ROUTES ??
      'false',
  ],
  ['FORGEAI_SCREENSHOT_SCENE', env.FORGEAI_SCREENSHOT_SCENE ?? 'dashboard'],
];

const args = [
  ...passthroughArgs,
  ...dartDefines.map(([key, value]) => `--dart-define=${key}=${value}`),
];

console.log(
  `flutter ${args.join(' ')}\nInjected launch defines: ${dartDefines
    .map(([key, value]) => `${key}=${value}`)
    .join(', ')}`,
);

const result = spawnSync('flutter', args, {
  cwd: process.cwd(),
  stdio: 'inherit',
  shell: false,
});

process.exit(result.status ?? 1);
