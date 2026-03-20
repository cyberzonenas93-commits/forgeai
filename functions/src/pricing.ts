import { OPENAI_LATEST_CHAT_MODEL } from './economics-config';
import type { AiProviderName, ProviderName } from './runtime';

export type GitActionType = 'create_branch' | 'commit' | 'open_pr' | 'merge_pr';
export type CheckActionType = 'run_tests' | 'run_lint' | 'build_project';
export type AiTaskActionType =
  | 'explain_code'
  | 'fix_bug'
  | 'generate_tests'
  | 'refactor_code'
  | 'deep_repo_analysis';
export type BillableActionType =
  | GitActionType
  | CheckActionType
  | AiTaskActionType
  | 'ai_suggestion'
  | 'ai_project_scaffold'
  | 'repo_prompt';

export interface PricingRule {
  minTokens: number;
  multiplier: number;
  dailyCap: number;
  refundPolicy: string;
  note: string;
}

export interface CostSnapshot {
  actionType: BillableActionType;
  provider: ProviderName;
  appTokens: number;
  tokenValueUsd: number;
  estimatedProviderCostUsd: number;
  estimatedMarginUsd: number;
  assumedModel: string | null;
  dailyCap: number;
  refundPolicy: string;
  pricingVersion: string;
}

export const PRICING_VERSION = '2026-03-monetization-1';
export const APP_TOKEN_VALUE_USD = Number(
  process.env.FORGEAI_TOKEN_VALUE_USD ?? '0.05',
);

export const ACTION_PRICING: Record<BillableActionType, PricingRule> = {
  create_branch: {
    minTokens: 12,
    multiplier: 1,
    dailyCap: 80,
    refundPolicy: 'refund_on_remote_failure',
    note: 'Low-cost branch creation routed through Git provider APIs.',
  },
  commit: {
    minTokens: 24,
    multiplier: 1,
    dailyCap: 80,
    refundPolicy: 'refund_on_remote_failure',
    note: 'Captures file-write overhead plus provider API round trips.',
  },
  open_pr: {
    minTokens: 16,
    multiplier: 1,
    dailyCap: 80,
    refundPolicy: 'refund_on_remote_failure',
    note: 'Covers PR or MR creation plus review metadata staging.',
  },
  merge_pr: {
    minTokens: 18,
    multiplier: 1,
    dailyCap: 60,
    refundPolicy: 'refund_on_remote_failure',
    note: 'Protected merge path with explicit user confirmation.',
  },
  run_tests: {
    minTokens: 30,
    multiplier: 1,
    dailyCap: 40,
    refundPolicy: 'refund_on_dispatch_failure',
    note: 'Provider workflow dispatch only; build minutes are external.',
  },
  run_lint: {
    minTokens: 10,
    multiplier: 1,
    dailyCap: 80,
    refundPolicy: 'refund_on_dispatch_failure',
    note: 'Low-cost static analysis dispatch.',
  },
  build_project: {
    minTokens: 40,
    multiplier: 1,
    dailyCap: 30,
    refundPolicy: 'refund_on_dispatch_failure',
    note: 'Covers provider build dispatch and result tracking.',
  },
  ai_suggestion: {
    minTokens: 16,
    multiplier: 1,
    dailyCap: 30,
    refundPolicy: 'charge_on_successful_generation_only',
    note: 'Charged when a durable agent run successfully produces a reviewable diff; routes to priority-tier models.',
  },
  ai_project_scaffold: {
    minTokens: 40,
    multiplier: 1,
    dailyCap: 15,
    refundPolicy: 'charge_on_successful_generation_only',
    note: 'AI-generated starter files plus remote repository creation and commits.',
  },
  explain_code: {
    minTokens: 2,
    multiplier: 1,
    dailyCap: 50,
    refundPolicy: 'refund_on_provider_failure',
    note: 'Simple explanation; routes to basic tier.',
  },
  fix_bug: {
    minTokens: 6,
    multiplier: 1,
    dailyCap: 40,
    refundPolicy: 'refund_on_provider_failure',
    note: 'Medium complexity; routes to standard tier.',
  },
  generate_tests: {
    minTokens: 8,
    multiplier: 1,
    dailyCap: 30,
    refundPolicy: 'refund_on_provider_failure',
    note: 'Medium complexity; routes to standard tier.',
  },
  refactor_code: {
    minTokens: 10,
    multiplier: 1,
    dailyCap: 25,
    refundPolicy: 'refund_on_provider_failure',
    note: 'Heavy; routes to priority tier when available.',
  },
  deep_repo_analysis: {
    minTokens: 25,
    multiplier: 1,
    dailyCap: 10,
    refundPolicy: 'refund_on_provider_failure',
    note: 'Heavy; routes to priority tier.',
  },
  repo_prompt: {
    minTokens: 12,
    multiplier: 1,
    dailyCap: 60,
    refundPolicy: 'refund_on_provider_failure',
    note: 'Agent workspace request with repository context; charged per successful run kickoff.',
  },
};

const AI_COST_ASSUMPTIONS: Record<
  AiProviderName,
  {
    model: string;
    inputPer1kUsd: number;
    outputPer1kUsd: number;
    outputToInputRatio: number;
  }
> = {
  openai: {
    model: process.env.OPENAI_MODEL ?? OPENAI_LATEST_CHAT_MODEL,
    inputPer1kUsd: Number(process.env.OPENAI_INPUT_COST_PER_1K_USD ?? '0.0004'),
    outputPer1kUsd: Number(
      process.env.OPENAI_OUTPUT_COST_PER_1K_USD ?? '0.0016',
    ),
    outputToInputRatio: Number(
      process.env.OPENAI_OUTPUT_TO_INPUT_RATIO ?? '0.35',
    ),
  },
  anthropic: {
    model: process.env.ANTHROPIC_MODEL ?? 'claude-3-5-sonnet-latest',
    inputPer1kUsd: Number(
      process.env.ANTHROPIC_INPUT_COST_PER_1K_USD ?? '0.0030',
    ),
    outputPer1kUsd: Number(
      process.env.ANTHROPIC_OUTPUT_COST_PER_1K_USD ?? '0.0150',
    ),
    outputToInputRatio: Number(
      process.env.ANTHROPIC_OUTPUT_TO_INPUT_RATIO ?? '0.35',
    ),
  },
  gemini: {
    model: process.env.GEMINI_MODEL ?? 'gemini-2.0-flash',
    inputPer1kUsd: Number(process.env.GEMINI_INPUT_COST_PER_1K_USD ?? '0.00015'),
    outputPer1kUsd: Number(
      process.env.GEMINI_OUTPUT_COST_PER_1K_USD ?? '0.00060',
    ),
    outputToInputRatio: Number(
      process.env.GEMINI_OUTPUT_TO_INPUT_RATIO ?? '0.35',
    ),
  },
};

const NON_AI_PROVIDER_COSTS_USD: Partial<Record<BillableActionType, number>> = {
  create_branch: 0.0005,
  commit: 0.0020,
  open_pr: 0.0015,
  merge_pr: 0.0015,
  run_tests: 0.0100,
  run_lint: 0.0040,
  build_project: 0.0120,
};

function roundCurrency(value: number) {
  return Number(value.toFixed(6));
}

export const BILLABLE_ACTION_TYPES: readonly BillableActionType[] = [
  'create_branch',
  'commit',
  'open_pr',
  'merge_pr',
  'run_tests',
  'run_lint',
  'build_project',
  'ai_suggestion',
  'ai_project_scaffold',
  'explain_code',
  'fix_bug',
  'generate_tests',
  'refactor_code',
  'deep_repo_analysis',
  'repo_prompt',
] as const;

export function isBillableActionType(
  actionType: string,
): actionType is BillableActionType {
  return Object.prototype.hasOwnProperty.call(ACTION_PRICING, actionType);
}

export function buildActionCost(
  actionType: BillableActionType,
  estimate: number,
) {
  const rule = ACTION_PRICING[actionType];
  return Math.max(rule.minTokens, Math.round(estimate * rule.multiplier));
}

export function buildCostSnapshot(input: {
  actionType: BillableActionType;
  provider: ProviderName;
  estimatedTokens: number;
}): CostSnapshot {
  const rule = ACTION_PRICING[input.actionType];
  const appTokens = buildActionCost(input.actionType, input.estimatedTokens);
  const tokenValueUsd = APP_TOKEN_VALUE_USD;

  let estimatedProviderCostUsd = 0;
  let assumedModel: string | null = null;

  const isAiAction =
    input.actionType === 'ai_suggestion' ||
    input.actionType === 'ai_project_scaffold' ||
    input.actionType === 'explain_code' ||
    input.actionType === 'fix_bug' ||
    input.actionType === 'generate_tests' ||
    input.actionType === 'refactor_code' ||
    input.actionType === 'deep_repo_analysis' ||
    input.actionType === 'repo_prompt';
  if (isAiAction) {
    const aiProvider = input.provider as AiProviderName;
    const assumption = AI_COST_ASSUMPTIONS[aiProvider];
    assumedModel = assumption.model;
    const inputTokens = input.estimatedTokens / (1 + assumption.outputToInputRatio);
    const outputTokens = input.estimatedTokens - inputTokens;
    estimatedProviderCostUsd =
      (inputTokens / 1000) * assumption.inputPer1kUsd +
      (outputTokens / 1000) * assumption.outputPer1kUsd;
  } else {
    estimatedProviderCostUsd = NON_AI_PROVIDER_COSTS_USD[input.actionType] ?? 0;
  }

  const revenueUsd = appTokens * tokenValueUsd;

  return {
    actionType: input.actionType,
    provider: input.provider,
    appTokens,
    tokenValueUsd,
    estimatedProviderCostUsd: roundCurrency(estimatedProviderCostUsd),
    estimatedMarginUsd: roundCurrency(revenueUsd - estimatedProviderCostUsd),
    assumedModel,
    dailyCap: rule.dailyCap,
    refundPolicy: rule.refundPolicy,
    pricingVersion: PRICING_VERSION,
  };
}
