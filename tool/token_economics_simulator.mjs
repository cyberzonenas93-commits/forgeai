#!/usr/bin/env node

/**
 * CodeCatalystAI token economics simulator.
 * Validates margin assumptions for hybrid monetization (subscriptions + top-ups).
 * Run: npm run simulate:tokens (or node tool/token_economics_simulator.mjs)
 */

import { collectLaunchContext } from './launch_lib.mjs';

const env = collectLaunchContext().env;

const appTokenValueUsd = Number(env.FORGEAI_TOKEN_VALUE_USD ?? '0.05');
const appleCutPercent = 30;
const marginTargetMultiplier = 5;

const aiAssumptions = {
  openai: {
    input: Number(env.OPENAI_INPUT_COST_PER_1K_USD ?? '0.001'),
    output: Number(env.OPENAI_OUTPUT_COST_PER_1K_USD ?? '0.004'),
    ratio: 0.35,
  },
  anthropic: {
    input: Number(env.ANTHROPIC_INPUT_COST_PER_1K_USD ?? '0.003'),
    output: Number(env.ANTHROPIC_OUTPUT_COST_PER_1K_USD ?? '0.015'),
    ratio: 0.35,
  },
  gemini: {
    input: Number(env.GEMINI_INPUT_COST_PER_1K_USD ?? '0.00015'),
    output: Number(env.GEMINI_OUTPUT_COST_PER_1K_USD ?? '0.0006'),
    ratio: 0.35,
  },
};

const actionPricing = {
  explain_code: { tokens: 2 },
  fix_bug: { tokens: 6 },
  generate_tests: { tokens: 8 },
  refactor_code: { tokens: 10 },
  deep_repo_analysis: { tokens: 25 },
  ai_suggestion: { tokens: 8 },
  ai_project_scaffold: { tokens: 40 },
  create_branch: { tokens: 12, providerCostUsd: 0.0005 },
  commit: { tokens: 24, providerCostUsd: 0.002 },
  open_pr: { tokens: 16, providerCostUsd: 0.0015 },
  merge_pr: { tokens: 18, providerCostUsd: 0.0015 },
  run_tests: { tokens: 30, providerCostUsd: 0.01 },
  run_lint: { tokens: 10, providerCostUsd: 0.004 },
  build_project: { tokens: 40, providerCostUsd: 0.012 },
};

const plans = {
  free: { priceUsd: 0, appleNetUsdAt30: 0, monthlyTokens: 20 },
  pro: { priceUsd: 14.99, appleNetUsdAt30: 10.49, monthlyTokens: 300 },
  power: { priceUsd: 29.99, appleNetUsdAt30: 20.99, monthlyTokens: 800 },
};

const topUpPacks = [
  { id: 'pack_small', tokens: 100, priceUsd: 5.99, appleNetUsdAt30: 4.19 },
  { id: 'pack_medium', tokens: 300, priceUsd: 14.99, appleNetUsdAt30: 10.49 },
  { id: 'pack_large', tokens: 1000, priceUsd: 34.99, appleNetUsdAt30: 24.49 },
];

function estimateAiCost(providerKey, chargedTokens) {
  const assumption = aiAssumptions[providerKey];
  if (!assumption) return 0;
  const inputTokens = chargedTokens / (1 + assumption.ratio);
  const outputTokens = chargedTokens - inputTokens;
  return (inputTokens / 1000) * assumption.input + (outputTokens / 1000) * assumption.output;
}

const scenarios = [
  {
    name: '100 free / 50 pro / 20 power',
    users: { free: 100, pro: 50, power: 20 },
    aiRunsPerUser: { free: 3, pro: 15, power: 40 },
    aiProvider: 'openai',
    aiActionMix: { explain_code: 2, fix_bug: 1, ai_suggestion: 1 },
    apiActionsPerUser: { create_branch: 2, commit: 2, open_pr: 1 },
    topUpsPerProUser: 0.2,
    topUpsPerPowerUser: 0.5,
  },
  {
    name: 'heavy deep_repo_analysis',
    users: { free: 0, pro: 30, power: 10 },
    aiRunsPerUser: { free: 0, pro: 20, power: 50 },
    aiProvider: 'openai',
    aiActionMix: { deep_repo_analysis: 3, refactor_code: 2, fix_bug: 2 },
    apiActionsPerUser: { create_branch: 5, commit: 8, open_pr: 4 },
    topUpsPerProUser: 0.5,
    topUpsPerPowerUser: 1,
  },
  {
    name: 'high failure / refund case',
    users: { free: 50, pro: 20, power: 5 },
    aiRunsPerUser: { free: 5, pro: 25, power: 60 },
    aiProvider: 'anthropic',
    aiActionMix: { ai_suggestion: 2, fix_bug: 1 },
    apiActionsPerUser: { create_branch: 3, commit: 4, open_pr: 2 },
    refundRate: 0.15,
    topUpsPerProUser: 0,
    topUpsPerPowerUser: 0.3,
  },
];

console.log('CodeCatalystAI token economics simulator');
console.log(`Token value: $${appTokenValueUsd.toFixed(2)} | Apple cut: ${appleCutPercent}% | Target margin: ${marginTargetMultiplier}x`);
console.log('');

for (const scenario of scenarios) {
  let totalRevenueUsd = 0;
  let totalAppleNetUsd = 0;
  let totalProviderCostUsd = 0;
  let totalTokensCharged = 0;

  for (const [planKey, count] of Object.entries(scenario.users)) {
    if (count === 0) continue;
    const plan = plans[planKey];
    totalRevenueUsd += count * plan.priceUsd;
    totalAppleNetUsd += count * plan.appleNetUsdAt30;
    const aiRuns = count * (scenario.aiRunsPerUser[planKey] ?? 0);
    const aiMix = scenario.aiActionMix || { ai_suggestion: 1 };
    let aiTokens = 0;
    for (const [action, weight] of Object.entries(aiMix)) {
      const tokens = actionPricing[action]?.tokens ?? 8;
      aiTokens += aiRuns * weight * tokens;
    }
    totalTokensCharged += aiTokens;
    let apiTokens = 0;
    let apiCost = 0;
    for (const [actionType, perUser] of Object.entries(scenario.apiActionsPerUser || {})) {
      const n = count * perUser;
      const p = actionPricing[actionType];
      if (p) {
        apiTokens += n * p.tokens;
        apiCost += n * (p.providerCostUsd ?? 0);
      }
    }
    totalTokensCharged += apiTokens;
    const effectiveAiTokens = aiTokens;
    totalProviderCostUsd += estimateAiCost(scenario.aiProvider, effectiveAiTokens) + apiCost;
  }

  const topUpRevenue = (scenario.users.pro || 0) * (scenario.topUpsPerProUser ?? 0) * 12 +
    (scenario.users.power || 0) * (scenario.topUpsPerPowerUser ?? 0) * 30;
  totalRevenueUsd += topUpRevenue;
  totalAppleNetUsd += topUpRevenue * (1 - appleCutPercent / 100);

  const refundRate = scenario.refundRate ?? 0;
  totalProviderCostUsd *= 1 - refundRate * 0.5;
  totalTokensCharged *= 1 - refundRate;

  const tokenRevenue = totalTokensCharged * appTokenValueUsd;
  totalRevenueUsd += tokenRevenue;
  totalAppleNetUsd += tokenRevenue * (1 - appleCutPercent / 100);

  const grossMargin = totalAppleNetUsd - totalProviderCostUsd;
  const marginMultiple = totalProviderCostUsd > 0 ? totalAppleNetUsd / totalProviderCostUsd : 0;
  const ok = marginMultiple >= marginTargetMultiplier;

  console.log(`Scenario: ${scenario.name}`);
  console.log(`  Revenue (gross): $${totalRevenueUsd.toFixed(2)} | Apple net: $${totalAppleNetUsd.toFixed(2)}`);
  console.log(`  Provider cost: $${totalProviderCostUsd.toFixed(4)} | Tokens charged: ${totalTokensCharged.toFixed(0)}`);
  console.log(`  Margin: ${marginMultiple.toFixed(1)}x ${ok ? '✓' : '✗ BELOW TARGET'}`);
  console.log('');
}

console.log('Run with FORGEAI_TOKEN_VALUE_USD=0.05 (default) for production pricing.');
