#!/usr/bin/env node

import { spawnSync } from 'node:child_process';

import {
  collectLaunchContext,
  runCommand,
  summarizeValidation,
} from './launch_lib.mjs';

const target = process.argv[2] ?? 'prod';
const explicitProjectIndex = process.argv.indexOf('--project');
const explicitProject =
  explicitProjectIndex >= 0 ? process.argv[explicitProjectIndex + 1] : null;
const allowDeploy =
  process.argv.includes('--yes') ||
  String(process.env.FORGEAI_ALLOW_DEPLOY).toLowerCase() === 'true';

const context = collectLaunchContext();
const summary = summarizeValidation(context);
const projectId = explicitProject ?? context.projectId;

if (!projectId) {
  console.error('No Firebase project id is configured.');
  process.exit(1);
}

if (summary.errors.length > 0) {
  console.error('Launch environment validation failed.');
  for (const error of summary.errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

const deployTargets = {
  functions: 'functions',
  rules: 'firestore:rules',
  indexes: 'firestore:indexes',
  prod: 'functions,firestore:rules,firestore:indexes',
};

if (!(target in deployTargets)) {
  console.error(`Unsupported deploy target: ${target}`);
  process.exit(1);
}

const loginCheck = spawnSync('firebase', ['login:list'], {
  cwd: process.cwd(),
  encoding: 'utf8',
});
if (loginCheck.status !== 0) {
  console.error('Firebase CLI is not authenticated.');
  process.exit(loginCheck.status ?? 1);
}

runCommand('node', ['./tool/validate_launch_env.mjs', '--strict']);
if (target === 'functions' || target === 'prod') {
  runCommand('npm', ['--prefix', 'functions', 'run', 'build']);
}

const firebaseArgs = [
  'deploy',
  '--project',
  projectId,
  '--only',
  deployTargets[target],
];

if (!allowDeploy) {
  console.log(
    `Dry run only. Re-run with --yes or FORGEAI_ALLOW_DEPLOY=true to execute: firebase ${firebaseArgs.join(
      ' ',
    )}`,
  );
  process.exit(0);
}

runCommand('firebase', firebaseArgs);
