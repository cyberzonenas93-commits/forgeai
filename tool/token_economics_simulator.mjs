#!/usr/bin/env node

import { collectLaunchContext } from './launch_lib.mjs';

const env = collectLaunchContext().env;

const appTokenValueUsd = Number(env.FORGEAI_TOKEN_VALUE_USD ?? '0.0010');
const aiAssumptions = {
  openai: {
    input: Number(env.OPENAI_INPUT_COST_PER_1K_USD ?? '0.0004'),
    output: Number(env.OPENAI_OUTPUT_COST_PER_1K_USD ?? '0.0016'),
    ratio: Number(env.OPENAI_OUTPUT_TO_INPUT_RATIO ?? '0.35'),
  },
  anthropic: {
    input: Number(env.ANTHROPIC_INPUT_COST_PER_1K_USD ?? '0.0030'),
    output: Number(env.ANTHROPIC_OUTPUT_COST_PER_1K_USD ?? '0.0150'),
    ratio: Number(env.ANTHROPIC_OUTPUT_TO_INPUT_RATIO ?? '0.35'),
  },
  gemini: {
    input: Number(env.GEMINI_INPUT_COST_PER_1K_USD ?? '0.00015'),
    output: Number(env.GEMINI_OUTPUT_COST_PER_1K_USD ?? '0.00060'),
    ratio: Number(env.GEMINI_OUTPUT_TO_INPUT_RATIO ?? '0.35'),
  },
};

const actionPricing = {
  create_branch: { tokens: 12, providerCostUsd: 0.0005 },
  commit: { tokens: 24, providerCostUsd: 0.0020 },
  open_pr: { tokens: 16, providerCostUsd: 0.0015 },
  merge_pr: { tokens: 18, providerCostUsd: 0.0015 },
  run_tests: { tokens: 30, providerCostUsd: 0.0100 },
  run_lint: { tokens: 10, providerCostUsd: 0.0040 },
  build_project: { tokens: 40, providerCostUsd: 0.0120 },
};

const scenarios = [
  {
    name: 'beta-light',
    aiRuns: 6,
    aiProvider: 'openai',
    apiActions: {
      create_branch: 4,
      commit: 4,
      open_pr: 2,
      run_tests: 2,
    },
  },
  {
    name: 'beta-typical',
    aiRuns: 18,
    aiProvider: 'openai',
    apiActions: {
      create_branch: 10,
      commit: 10,
      open_pr: 6,
      run_tests: 6,
      build_project: 2,
    },
  },
  {
    name: 'beta-heavy',
    aiRuns: 40,
    aiProvider: 'anthropic',
    apiActions: {
      create_branch: 18,
      commit: 20,
      open_pr: 14,
      merge_pr: 8,
      run_tests: 14,
      build_project: 6,
    },
  },
];

function estimateAiCost(providerKey, chargedTokens) {
  const assumption = aiAssumptions[providerKey];
  const inputTokens = chargedTokens / (1 + assumption.ratio);
  const outputTokens = chargedTokens - inputTokens;
  return (inputTokens / 1000) * assumption.input + (outputTokens / 1000) * assumption.output;
}

console.log('ForgeAI token economics simulator');
console.log(`App token value: $${appTokenValueUsd.toFixed(4)}`);

for (const scenario of scenarios) {
  const aiTokenFloor = 80;
  const aiTokens = scenario.aiRuns * aiTokenFloor;
  const aiRevenue = aiTokens * appTokenValueUsd;
  const aiCost = estimateAiCost(scenario.aiProvider, aiTokens);

  let apiTokens = 0;
  let apiCost = 0;
  for (const [actionType, count] of Object.entries(scenario.apiActions)) {
    apiTokens += actionPricing[actionType].tokens * count;
    apiCost += actionPricing[actionType].providerCostUsd * count;
  }

  const totalTokens = aiTokens + apiTokens;
  const totalRevenue = totalTokens * appTokenValueUsd;
  const totalCost = aiCost + apiCost;
  const totalMargin = totalRevenue - totalCost;
  const marginPercent = totalRevenue === 0 ? 0 : (totalMargin / totalRevenue) * 100;

  console.log(
    `${scenario.name}: tokens=${totalTokens} revenue=$${totalRevenue.toFixed(2)} cost=$${totalCost.toFixed(4)} margin=${marginPercent.toFixed(1)}%`
  );
}
