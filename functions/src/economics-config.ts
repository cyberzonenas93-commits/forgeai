/**
 * Centralized monetization config: plans, packs, model routing.
 * Single source for wallet onboarding, caps, and IAP product catalog.
 */

export type PlanId = 'free' | 'pro' | 'power';
export type ModelTier = 'basic' | 'standard' | 'priority';
export type TopUpPackId = 'pack_small' | 'pack_medium' | 'pack_large';

export interface PlanDefinition {
  id: PlanId;
  productId: string | null;
  displayName: string;
  priceUsd: number;
  appleNetUsdAt30: number;
  monthlyIncludedTokens: number;
  dailyActionCap: number;
  allowedModelTier: ModelTier;
}

export interface TopUpPackDefinition {
  id: TopUpPackId;
  productId: string;
  tokens: number;
  priceUsd: number;
  appleNetUsdAt30: number;
}

export const PLANS: Record<PlanId, PlanDefinition> = {
  free: {
    id: 'free',
    productId: null,
    displayName: 'Free',
    priceUsd: 0,
    appleNetUsdAt30: 0,
    monthlyIncludedTokens: 20,
    dailyActionCap: 10,
    allowedModelTier: 'basic',
  },
  pro: {
    id: 'pro',
    productId: 'com.forgeai.app.subscription.pro',
    displayName: 'Pro',
    priceUsd: 14.99,
    appleNetUsdAt30: 10.49,
    monthlyIncludedTokens: 300,
    dailyActionCap: 50,
    allowedModelTier: 'standard',
  },
  power: {
    id: 'power',
    productId: 'com.forgeai.app.subscription.power',
    displayName: 'Power',
    priceUsd: 29.99,
    appleNetUsdAt30: 20.99,
    monthlyIncludedTokens: 800,
    dailyActionCap: 150,
    allowedModelTier: 'priority',
  },
};

export const TOP_UP_PACKS: Record<TopUpPackId, TopUpPackDefinition> = {
  pack_small: {
    id: 'pack_small',
    productId: 'com.forgeai.app.tokens.small',
    tokens: 100,
    priceUsd: 5,
    appleNetUsdAt30: 3.5,
  },
  pack_medium: {
    id: 'pack_medium',
    productId: 'com.forgeai.app.tokens.medium',
    tokens: 300,
    priceUsd: 12,
    appleNetUsdAt30: 8.4,
  },
  pack_large: {
    id: 'pack_large',
    productId: 'com.forgeai.app.tokens.large',
    tokens: 1000,
    priceUsd: 30,
    appleNetUsdAt30: 21,
  },
};

/** Action type -> routing tier for profitability (simple = cheapest, heavy = premium when needed). */
export const ACTION_TIER: Record<string, ModelTier> = {
  explain_code: 'basic',
  fix_bug: 'standard',
  generate_tests: 'standard',
  refactor_code: 'priority',
  deep_repo_analysis: 'priority',
  ai_suggestion: 'standard',
  create_branch: 'basic',
  commit: 'basic',
  open_pr: 'basic',
  merge_pr: 'basic',
  run_tests: 'standard',
  run_lint: 'basic',
  build_project: 'standard',
};

/** Model tier -> provider model id (env can override at runtime). */
export type ProviderName = 'openai' | 'anthropic' | 'gemini';

export const MODEL_TIERS: Record<ModelTier, Record<ProviderName, string>> = {
  basic: {
    openai: process.env.OPENAI_MODEL_BASIC ?? 'gpt-4.1-mini',
    anthropic: process.env.ANTHROPIC_MODEL_BASIC ?? 'claude-3-5-haiku-20241022',
    gemini: process.env.GEMINI_MODEL_BASIC ?? 'gemini-2.0-flash',
  },
  standard: {
    openai: process.env.OPENAI_MODEL_STANDARD ?? 'gpt-4.1-mini',
    anthropic: process.env.ANTHROPIC_MODEL_STANDARD ?? 'claude-3-5-sonnet-latest',
    gemini: process.env.GEMINI_MODEL_STANDARD ?? 'gemini-2.0-flash',
  },
  priority: {
    openai: process.env.OPENAI_MODEL_PRIORITY ?? 'gpt-4.1',
    anthropic: process.env.ANTHROPIC_MODEL_PRIORITY ?? 'claude-3-5-sonnet-latest',
    gemini: process.env.GEMINI_MODEL_PRIORITY ?? 'gemini-2.0-flash',
  },
};

export function getModelForTierAndProvider(
  tier: ModelTier,
  provider: ProviderName,
): string {
  return MODEL_TIERS[tier]?.[provider] ?? MODEL_TIERS.basic[provider];
}

export function getTierForAction(actionType: string): ModelTier {
  return ACTION_TIER[actionType] ?? 'standard';
}

export const APPLE_CUT_PERCENT = 30;
export const MARGIN_TARGET_MULTIPLIER = 5;
export const MARGIN_TARGET_MULTIPLIER_PREFERRED = 8;
