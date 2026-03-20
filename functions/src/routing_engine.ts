import {
  getModelForTierAndProvider,
  type ModelTier,
} from './economics-config'
import type { AgentCostProfile } from './cost_optimization'
import {
  AI_PROVIDER_NAMES,
  lookupProviderToken,
  type AiProviderName,
} from './runtime'
import {
  getModelPerformanceStats,
  type ModelStats,
} from './routing_metrics'

export type RepoExecutionProviderStage =
  | 'context_planner'
  | 'execution_planner'
  | 'generate_diff'
  | 'repair_diff'

export interface RepoExecutionProviderRoutingDecision {
  provider: AiProviderName
  providerOrder: AiProviderName[]
  availableProviders: AiProviderName[]
  model: string
  tier: ModelTier
  stage: RepoExecutionProviderStage
  reason: string
  /** True when the decision was driven by historical performance data. */
  adaptiveRouting: boolean
}

function dedupeProviders(values: AiProviderName[]) {
  const seen = new Set<AiProviderName>()
  const ordered: AiProviderName[] = []
  for (const value of values) {
    if (seen.has(value)) {
      continue
    }
    seen.add(value)
    ordered.push(value)
  }
  return ordered
}

function repoExecutionTierForStage(stage: RepoExecutionProviderStage, deepMode: boolean): ModelTier {
  switch (stage) {
    case 'context_planner':
      return deepMode ? 'priority' : 'standard'
    case 'execution_planner':
      return deepMode ? 'priority' : 'standard'
    case 'generate_diff':
    case 'repair_diff':
      return 'priority'
  }
}

function preferredProviderOrder(params: {
  requestedProvider?: AiProviderName | null
  stage: RepoExecutionProviderStage
  deepMode: boolean
  repoSizeClass?: string | null
  retryCount?: number
  costProfile?: AgentCostProfile | null
}) {
  const requestedProvider = params.requestedProvider ?? null
  const largeRepo =
    params.repoSizeClass === 'large' || params.repoSizeClass === 'huge'
  const retrying = (params.retryCount ?? 0) > 0
  let preferred: AiProviderName[]

  if (params.stage === 'repair_diff') {
    preferred = ['anthropic', 'openai', 'gemini']
  } else if (params.stage === 'context_planner' || params.stage === 'execution_planner') {
    preferred =
      params.deepMode || largeRepo
        ? ['anthropic', 'openai', 'gemini']
        : ['openai', 'anthropic', 'gemini']
  } else {
    preferred =
      retrying || params.deepMode || largeRepo
        ? ['anthropic', 'openai', 'gemini']
        : ['openai', 'anthropic', 'gemini']
  }

  if (params.costProfile === 'economy') {
    preferred = ['openai', 'gemini', 'anthropic']
  } else if (params.costProfile === 'quality') {
    preferred = ['anthropic', 'openai', 'gemini']
  }

  return dedupeProviders([
    ...(requestedProvider ? [requestedProvider] : []),
    ...preferred,
    ...AI_PROVIDER_NAMES,
  ])
}

function providerReason(params: {
  provider: AiProviderName
  stage: RepoExecutionProviderStage
  deepMode: boolean
  repoSizeClass?: string | null
  retryCount?: number
}) {
  const retrying = (params.retryCount ?? 0) > 0
  const sizeLabel = params.repoSizeClass ? `${params.repoSizeClass} repo` : 'repo'
  switch (params.stage) {
    case 'context_planner':
      return params.deepMode
        ? `Using ${params.provider} for deeper repo-context planning on a ${sizeLabel}.`
        : `Using ${params.provider} for fast repo-context planning.`
    case 'execution_planner':
      return params.deepMode
        ? `Using ${params.provider} to plan a broader multi-file execution scope.`
        : `Using ${params.provider} to finalize the editable and read-only scope.`
    case 'repair_diff':
      return `Using ${params.provider} for repair pass ${retrying ? 'regeneration' : 'generation'} after validation feedback.`
    case 'generate_diff':
      return params.deepMode
        ? `Using ${params.provider} to generate a deeper repo-native diff.`
        : `Using ${params.provider} to generate the primary repo diff.`
  }
}

// ---------------------------------------------------------------------------
// Adaptive routing helpers
// ---------------------------------------------------------------------------

/**
 * Score a model candidate based on its historical performance stats.
 *
 *   score = 0.5 * successRate
 *         + 0.3 * (1 / normalizedLatency)   — lower latency → higher score
 *         + 0.2 * (1 / normalizedCost)       — lower cost    → higher score
 *
 * Latency and cost are normalised relative to the worst candidate in the set
 * so that all three components are on the same [0, 1] scale.
 */
function scoreModelStats(
  stats: ModelStats,
  maxLatencyMs: number,
  maxCostUsd: number,
): number {
  const successComponent = stats.successRate * 0.5

  // Avoid div-by-zero; if every model has the same cost/latency the component
  // doesn't meaningfully differentiate — treat it as 1 (neutral).
  const latencyComponent =
    maxLatencyMs > 0 && stats.avgLatencyMs > 0
      ? (1 - stats.avgLatencyMs / maxLatencyMs) * 0.3
      : 0.15 // neutral contribution when data is absent

  const costComponent =
    maxCostUsd > 0 && stats.avgCostUsd > 0
      ? (1 - stats.avgCostUsd / maxCostUsd) * 0.2
      : 0.1 // neutral contribution when data is absent

  return successComponent + latencyComponent + costComponent
}

/**
 * Attempt to select the best provider using historical performance metrics.
 *
 * Returns `null` if:
 *  - No stats are available (new repo / first run)
 *  - No available provider has a stat record
 *  - The budget-constrained provider set has fewer options
 *
 * The caller is responsible for falling back to static routing when `null`
 * is returned.
 */
function selectAdaptiveProvider(params: {
  stats: ModelStats[]
  availableProviders: AiProviderName[]
  budgetProfile?: AgentCostProfile | null
}): {
  provider: AiProviderName
  model: string
  reason: string
} | null {
  const { stats, availableProviders, budgetProfile } = params

  if (stats.length === 0 || availableProviders.length === 0) return null

  // Filter stats to providers we actually have tokens for.
  const eligibleStats = stats.filter(s => availableProviders.includes(s.provider))
  if (eligibleStats.length === 0) return null

  // Enforce hard budget cap: economy → exclude anthropic if alternatives exist.
  let candidates = eligibleStats
  if (budgetProfile === 'economy') {
    const nonPremium = candidates.filter(s => s.provider !== 'anthropic')
    if (nonPremium.length > 0) candidates = nonPremium
  }

  // Minimum sample count before we trust adaptive routing for a model.
  const MIN_SAMPLES = 3
  const mature = candidates.filter(s => s.sampleCount >= MIN_SAMPLES)
  if (mature.length === 0) return null

  // Normalise latency + cost across the mature candidate set.
  const maxLatencyMs = mature.reduce((m, s) => Math.max(m, s.avgLatencyMs), 0)
  const maxCostUsd = mature.reduce((m, s) => Math.max(m, s.avgCostUsd), 0)

  const scored = mature.map(s => ({
    stats: s,
    score: scoreModelStats(s, maxLatencyMs, maxCostUsd),
  }))
  scored.sort((a, b) => b.score - a.score)

  const best = scored[0]
  if (!best) return null

  const { stats: bestStats, score } = best
  const reason =
    `Adaptive routing selected ${bestStats.provider} (${bestStats.model}) — ` +
    `score=${score.toFixed(3)}, successRate=${(bestStats.successRate * 100).toFixed(0)}%, ` +
    `avgLatency=${Math.round(bestStats.avgLatencyMs)}ms, ` +
    `avgCost=$${bestStats.avgCostUsd.toFixed(4)}, ` +
    `n=${bestStats.sampleCount}`

  return {
    provider: bestStats.provider,
    model: bestStats.model,
    reason,
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Resolve which provider + model to use for a given repo execution stage.
 *
 * When `repoId` is supplied and historical metrics exist for this repo+stage,
 * the system uses adaptive routing (scoring on success rate, latency, cost).
 * Falls back transparently to the existing static decision tree if no
 * historical data is available.
 */
export async function resolveRepoExecutionProviderRoutingAsync(params: {
  requestedProvider?: AiProviderName | null
  stage: RepoExecutionProviderStage
  deepMode: boolean
  repoSizeClass?: string | null
  retryCount?: number
  costProfile?: AgentCostProfile | null
  /** If provided, adaptive routing is attempted before falling back to static. */
  repoId?: string | null
}): Promise<RepoExecutionProviderRoutingDecision> {
  const providerOrder = preferredProviderOrder(params)
  const availableProviders = providerOrder.filter(
    provider => lookupProviderToken(provider) != null,
  )
  const provider0 = availableProviders[0]
  if (!provider0) {
    throw new Error('No AI provider token configured for repo execution.')
  }
  const tier = repoExecutionTierForStage(params.stage, params.deepMode)

  // --- Attempt adaptive routing when we have a repoId ---
  if (params.repoId) {
    try {
      const perfStats = await getModelPerformanceStats(params.repoId, params.stage)
      const adaptive = selectAdaptiveProvider({
        stats: perfStats,
        availableProviders,
        budgetProfile: params.costProfile,
      })

      if (adaptive && availableProviders.includes(adaptive.provider)) {
        return {
          provider: adaptive.provider,
          providerOrder,
          availableProviders,
          model: adaptive.model,
          tier,
          stage: params.stage,
          reason: adaptive.reason,
          adaptiveRouting: true,
        }
      }
    } catch {
      // Metrics query failed — fall through to static routing.
    }
  }

  // --- Static fallback ---
  return {
    provider: provider0,
    providerOrder,
    availableProviders,
    model: getModelForTierAndProvider(tier, provider0),
    tier,
    stage: params.stage,
    reason: providerReason({
      provider: provider0,
      stage: params.stage,
      deepMode: params.deepMode,
      repoSizeClass: params.repoSizeClass,
      retryCount: params.retryCount,
    }),
    adaptiveRouting: false,
  }
}

/**
 * Synchronous (static-only) variant — preserved for call sites that cannot
 * await or where adaptive routing is not desired.
 */
export function resolveRepoExecutionProviderRouting(params: {
  requestedProvider?: AiProviderName | null
  stage: RepoExecutionProviderStage
  deepMode: boolean
  repoSizeClass?: string | null
  retryCount?: number
  costProfile?: AgentCostProfile | null
}): RepoExecutionProviderRoutingDecision {
  const providerOrder = preferredProviderOrder(params)
  const availableProviders = providerOrder.filter(
    provider => lookupProviderToken(provider) != null,
  )
  const provider = availableProviders[0]
  if (!provider) {
    throw new Error('No AI provider token configured for repo execution.')
  }
  const tier = repoExecutionTierForStage(params.stage, params.deepMode)
  return {
    provider,
    providerOrder,
    availableProviders,
    model: getModelForTierAndProvider(tier, provider),
    tier,
    stage: params.stage,
    reason: providerReason({
      provider,
      stage: params.stage,
      deepMode: params.deepMode,
      repoSizeClass: params.repoSizeClass,
      retryCount: params.retryCount,
    }),
    adaptiveRouting: false,
  }
}
