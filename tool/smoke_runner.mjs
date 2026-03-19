#!/usr/bin/env node

import { spawnSync } from 'node:child_process';

import {
  collectLaunchContext,
  printList,
  runCommand,
  summarizeValidation,
} from './launch_lib.mjs';

const modeIndex = process.argv.indexOf('--mode');
const mode = modeIndex >= 0 ? process.argv[modeIndex + 1] : 'backend';
const context = collectLaunchContext();
const summary = summarizeValidation(context);

console.log(`CodeCatalystAI smoke runner (${mode})`);

if (summary.errors.length > 0) {
  printList('Blocking errors', summary.errors);
  process.exit(1);
}

if (mode === 'backend') {
  runCommand('npm', ['--prefix', 'functions', 'run', 'build']);
  const firebaseStatus = spawnSync('firebase', ['login:list'], {
    cwd: process.cwd(),
    encoding: 'utf8',
  });
  console.log(firebaseStatus.stdout.trim());

  const smokeWarnings = [];
  if (!context.smoke.firebaseUserEmail) {
    smokeWarnings.push('Missing SMOKE_TEST_FIREBASE_USER_EMAIL.');
  }
  if (!context.smoke.githubRepo) {
    smokeWarnings.push('Missing SMOKE_TEST_GITHUB_REPO.');
  }
  if (
    context.smoke.githubBranchPrefix === 'main' ||
    context.smoke.githubBranchPrefix === 'master' ||
    !context.smoke.githubBranchPrefix.endsWith('/')
  ) {
    smokeWarnings.push('GitHub smoke branch prefix is unsafe.');
  }

  printList('Smoke warnings', smokeWarnings);
  process.exit(smokeWarnings.length > 0 ? 1 : 0);
}

printList('Smoke warnings', summary.warnings);
console.log('Recommended command sequence:');
console.log('  1. npm run validate:env:strict');
console.log('  2. npm run smoke:backend');
console.log('  3. npm run run:app');
