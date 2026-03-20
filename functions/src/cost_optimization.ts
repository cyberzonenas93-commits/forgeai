import type { AiProviderName } from './runtime'

export type AgentCostProfile = 'economy' | 'balanced' | 'quality'

export type AgentCostStage =
  | 'planning'
  | 'context'
  | 'editing'
  | 'validation'
  | 'repair'
  | 'git'

export interface AgentTaskBudgetSnapshot {
  profile: AgentCostProfile
  taskTokenBudget: number
  repairReserveTokens: number
  dailySoftBudgetUsd: number
  taskSoftBudgetUsd: number
}

export interface AgentCostLedgerEntry {
  stage: AgentCostStage
  provider?: AiProviderName | null
  model?: string | null
  estimatedTokens: number
  estimatedCostUsd: number
  summary: string
  retryCount?: number
  recordedAtMs: number
}

/**
 * Blended cost per 1 000 tokens for the given model (input + output combined,
 * assuming a roughly 1:3 input-to-output ratio for typical agent workloads).
 *
 * Anthropic pricing (USD per 1M tokens, 2025-Q2):
 *   claude-haiku-4-5-20251001 : $0.25 in / $1.25 out  → blended ~$0.00094/K
 *   claude-sonnet-4-6         : $3    in / $15   out  → blended ~$0.012  /K
 *   claude-opus-4-6           : $15   in / $75   out  → blended ~$0.060  /K
 */
function modelCostPerThousandTokens(provider: AiProviderName, model: string | null | undefined) {
  const m = (model ?? '').toLowerCase()
  if (provider === 'anthropic') {
    if (m.includes('opus'))   return 0.060    // claude-opus-4-6
    if (m.includes('sonnet')) return 0.012    // claude-sonnet-4-6
    if (m.includes('haiku'))  return 0.00094  // claude-haiku-4-5-20251001
    return 0.012 // fallback: sonnet-level pricing
  }
  if (provider === 'gemini') {
    return m.includes('pro') ? 0.0035 : 0.0012
  }
  // OpenAI
  return m.includes('gpt-5') ? 0.006 : 0.003
}

export function estimateAgentStageCostUsd(params: {
  provider?: AiProviderName | null
  model?: string | null
  estimatedTokens: number
  stage: AgentCostStage
}) {
  if (!params.provider || params.estimatedTokens <= 0) {
    return 0
  }
  const base = (params.estimatedTokens / 1000) * modelCostPerThousandTokens(params.provider, params.model)
  switch (params.stage) {
    case 'planning':
      return Number((base * 0.6).toFixed(6))
    case 'context':
      return Number((base * 0.8).toFixed(6))
    case 'repair':
      return Number((base * 1.1).toFixed(6))
    case 'editing':
      return Number(base.toFixed(6))
    default:
      return Number((base * 0.25).toFixed(6))
  }
}

export function buildAgentTaskBudgetSnapshot(params: {
  deepMode: boolean
  maxTokenBudget: number
  maxRetries: number
}) {
  const taskSoftBudgetUsd = params.deepMode ? 1.8 : 0.8
  const dailySoftBudgetUsd = params.deepMode ? 12 : 6
  return {
    profile: params.deepMode ? 'quality' : 'balanced',
    taskTokenBudget: params.maxTokenBudget,
    repairReserveTokens: Math.max(Math.round(params.maxTokenBudget * 0.35), params.maxRetries * 400),
    dailySoftBudgetUsd,
    taskSoftBudgetUsd,
  } satisfies AgentTaskBudgetSnapshot
}

export function chooseAgentCostProfile(params: {
  stage: AgentCostStage
  deepMode: boolean
  retryCount?: number
  budgetRemainingRatio?: number | null
  repoSizeClass?: string | null
}) {
  const remaining = params.budgetRemainingRatio ?? 1
  const largeRepo = params.repoSizeClass === 'large' || params.repoSizeClass === 'huge'
  if (params.stage === 'repair') {
    return remaining < 0.18 ? 'balanced' : 'quality'
  }
  if (params.stage === 'planning' || params.stage === 'context') {
    if (!params.deepMode && remaining < 0.35) {
      return 'economy'
    }
    return params.deepMode || largeRepo ? 'balanced' : 'economy'
  }
  if ((params.retryCount ?? 0) > 1 || params.deepMode || largeRepo) {
    return remaining < 0.2 ? 'balanced' : 'quality'
  }
  return remaining < 0.3 ? 'economy' : 'balanced'
}

export function appendAgentCostLedgerEntry(
  metadata: Record<string, unknown> | null | undefined,
  entry: AgentCostLedgerEntry,
) {
  const existingMetadata = metadata && typeof metadata === 'object' ? metadata : {}
  const history = Array.isArray((existingMetadata as Record<string, unknown>).costLedger)
    ? ((existingMetadata as Record<string, unknown>).costLedger as unknown[])
        .filter((value): value is AgentCostLedgerEntry => value != null && typeof value === 'object')
    : []
  const nextLedger = [...history.slice(-23), entry]
  const totalEstimatedTokens = nextLedger.reduce(
    (sum, item) => sum + (typeof item.estimatedTokens === 'number' ? item.estimatedTokens : 0),
    0,
  )
  const totalEstimatedCostUsd = Number(
    nextLedger
      .reduce((sum, item) => sum + (typeof item.estimatedCostUsd === 'number' ? item.estimatedCostUsd : 0), 0)
      .toFixed(6),
  )
  return {
    ...existingMetadata,
    costLedger: nextLedger,
    costLedgerCount: nextLedger.length,
    totalEstimatedAgentTokens: totalEstimatedTokens,
    totalEstimatedAgentCostUsd: totalEstimatedCostUsd,
    latestCostEntry: entry,
  }
}

export function remainingTaskBudgetRatio(params: {
  metadata: Record<string, unknown> | null | undefined
  budget: AgentTaskBudgetSnapshot
}) {
  const totalEstimatedTokens =
    params.metadata &&
    typeof params.metadata === 'object' &&
    typeof (params.metadata as Record<string, unknown>).totalEstimatedAgentTokens === 'number'
      ? ((params.metadata as Record<string, unknown>).totalEstimatedAgentTokens as number)
      : 0
  const remaining = Math.max(params.budget.taskTokenBudget - totalEstimatedTokens, 0)
  return params.budget.taskTokenBudget <= 0 ? 0 : remaining / params.budget.taskTokenBudget
}

export function summarizeAgentCostLedger(metadata: Record<string, unknown> | null | undefined) {
  if (!metadata || typeof metadata !== 'object') {
    return 'No agent cost activity recorded yet.'
  }
  const data = metadata as Record<string, unknown>
  const totalTokens =
    typeof data.totalEstimatedAgentTokens === 'number' ? data.totalEstimatedAgentTokens : 0
  const totalCostUsd =
    typeof data.totalEstimatedAgentCostUsd === 'number' ? data.totalEstimatedAgentCostUsd : 0
  const latest = data.latestCostEntry
  if (!latest || typeof latest !== 'object') {
    return `Estimated agent usage: ${totalTokens} tokens (~$${totalCostUsd.toFixed(4)}).`
  }
  const latestEntry = latest as AgentCostLedgerEntry
  return `Estimated agent usage: ${totalTokens} tokens (~$${totalCostUsd.toFixed(4)}). Latest stage: ${latestEntry.stage}.`
}
