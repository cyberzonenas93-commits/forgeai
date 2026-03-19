#!/usr/bin/env node

import {
  collectLaunchContext,
  printList,
  summarizeValidation,
} from './launch_lib.mjs';

const strict = process.argv.includes('--strict');
const json = process.argv.includes('--json');

const context = collectLaunchContext();
const summary = summarizeValidation(context);

if (json) {
  console.log(
    JSON.stringify(
      {
        projectId: context.projectId,
        requiredProviders: context.requiredProviders,
        providerReadiness: context.providerReadiness,
        callbacks: context.callbacks,
        appFiles: context.appFiles,
        smoke: context.smoke,
        errors: summary.errors,
        warnings: summary.warnings,
      },
      null,
      2,
    ),
  );
  process.exit(strict && summary.errors.length > 0 ? 1 : 0);
}

console.log('CodeCatalystAI launch environment validation');
console.log(`Project: ${context.projectId ?? 'missing'}`);
console.log(`GitHub auth callback: ${context.callbacks.githubAuth ?? 'missing'}`);
printList('Required providers', context.requiredProviders);

for (const [provider, readiness] of Object.entries(context.providerReadiness)) {
  const present =
    readiness.presentSecretNames.length > 0
      ? readiness.presentSecretNames.join(', ')
      : 'none';
  console.log(
    `Provider ${provider}: ${present} present; expected ${readiness.secretNames.join(
      ' or ',
    )}`,
  );
}

printList('Errors', summary.errors);
printList('Warnings', summary.warnings);

if (strict && summary.errors.length > 0) {
  process.exit(1);
}
