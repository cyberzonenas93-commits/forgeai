/**
 * Centralized monetization config: plans, packs, model routing.
 * Single source for wallet onboarding, caps, and IAP product catalog.
 */

/**
 * OpenAI alias for the current GPT-5 snapshot used in ChatGPT; OpenAI rolls this forward over time.
 * @see https://developers.openai.com/api/docs/models/gpt-5-chat-latest
 * Pin a snapshot with OPENAI_MODEL / OPENAI_MODEL_* env vars when you need fixed behavior.
 */
export const OPENAI_LATEST_CHAT_MODEL = 'gpt-5-chat-latest';

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
    priceUsd: 5.99,
    appleNetUsdAt30: 4.19,
  },
  pack_medium: {
    id: 'pack_medium',
    productId: 'com.forgeai.app.tokens.medium',
    tokens: 300,
    priceUsd: 14.99,
    appleNetUsdAt30: 10.49,
  },
  pack_large: {
    id: 'pack_large',
    productId: 'com.forgeai.app.tokens.large',
    tokens: 1000,
    priceUsd: 34.99,
    appleNetUsdAt30: 24.49,
  },
};

/** Action type -> routing tier for profitability (simple = cheapest, heavy = premium when needed). */
export const ACTION_TIER: Record<string, ModelTier> = {
  explain_code: 'basic',
  fix_bug: 'standard',
  generate_tests: 'standard',
  refactor_code: 'priority',
  deep_repo_analysis: 'priority',
  /** Full-file edits: use priority tier (strongest configured model per provider). */
  ai_suggestion: 'priority',
  ai_project_scaffold: 'priority',
  repo_prompt: 'standard',
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

// ---------------------------------------------------------------------------
// Claude model identifiers (current generation)
// Costs (USD per 1M tokens):  input / output
//   claude-haiku-4-5-20251001 : $0.25  / $1.25   — fast, cheap, validation/repair
//   claude-sonnet-4-6         : $3     / $15      — balanced, best for diff generation
//   claude-opus-4-6           : $15    / $75      — highest quality, complex planning
// Override at runtime via ANTHROPIC_MODEL_BASIC / _STANDARD / _PRIORITY env vars.
// ---------------------------------------------------------------------------
export const CLAUDE_HAIKU_MODEL  = 'claude-haiku-4-5-20251001'
export const CLAUDE_SONNET_MODEL = 'claude-sonnet-4-6'
export const CLAUDE_OPUS_MODEL   = 'claude-opus-4-6'

export const MODEL_TIERS: Record<ModelTier, Record<ProviderName, string>> = {
  // basic  → fast/cheap  → Haiku for Anthropic
  basic: {
    openai: process.env.OPENAI_MODEL_BASIC ?? OPENAI_LATEST_CHAT_MODEL,
    anthropic: process.env.ANTHROPIC_MODEL_BASIC ?? CLAUDE_HAIKU_MODEL,
    gemini: process.env.GEMINI_MODEL_BASIC ?? 'gemini-2.0-flash',
  },
  // standard → balanced  → Sonnet for Anthropic
  standard: {
    openai: process.env.OPENAI_MODEL_STANDARD ?? OPENAI_LATEST_CHAT_MODEL,
    anthropic: process.env.ANTHROPIC_MODEL_STANDARD ?? CLAUDE_SONNET_MODEL,
    gemini: process.env.GEMINI_MODEL_STANDARD ?? 'gemini-2.0-flash',
  },
  // priority → high quality → Opus for Anthropic
  priority: {
    openai: process.env.OPENAI_MODEL_PRIORITY ?? OPENAI_LATEST_CHAT_MODEL,
    anthropic: process.env.ANTHROPIC_MODEL_PRIORITY ?? CLAUDE_OPUS_MODEL,
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
