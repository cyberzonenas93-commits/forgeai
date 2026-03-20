import { getFirestore, Timestamp } from 'firebase-admin/firestore';

import type { AiProviderName } from './runtime';
import type { RepoExecutionProviderStage } from './routing_engine';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** One metric record written after each agent stage completes. */
export interface RoutingMetricRecord {
  model: string;
  provider: AiProviderName;
  stage: RepoExecutionProviderStage;
  latencyMs: number;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
  /** Whether the validation / diff-apply step passed on this attempt. */
  validationPassed: boolean;
  /** How many repair passes were needed (0 = first attempt succeeded). */
  repairPassesNeeded: number;
  timestamp: Timestamp;
}

/** Per-model aggregate computed from the last N records. */
export interface ModelStats {
  model: string;
  provider: AiProviderName;
  /** Fraction of records where validationPassed === true. */
  successRate: number;
  avgLatencyMs: number;
  avgCostUsd: number;
  avgRepairPasses: number;
  sampleCount: number;
}

// ---------------------------------------------------------------------------
// Firestore path
// ---------------------------------------------------------------------------

/**
 * `routingMetrics/{repoId}/{stage}/{taskId}`
 *
 * Keyed by taskId at the leaf so concurrent writes from different tasks
 * don't collide. We query by collection-group later for per-stage stats.
 */
function metricsRef(repoId: string, stage: RepoExecutionProviderStage, taskId: string) {
  return getFirestore()
    .collection('routingMetrics')
    .doc(repoId)
    .collection(stage)
    .doc(taskId);
}

// ---------------------------------------------------------------------------
// Write
// ---------------------------------------------------------------------------

/**
 * Record a metric for a completed agent stage.
 * Fire-and-forget — errors are swallowed so they never block the main flow.
 */
export function recordRoutingMetric(params: {
  repoId: string;
  taskId: string;
  model: string;
  provider: AiProviderName;
  stage: RepoExecutionProviderStage;
  latencyMs: number;
  inputTokens?: number;
  outputTokens?: number;
  costUsd?: number;
  validationPassed: boolean;
  repairPassesNeeded?: number;
}): void {
  const record: RoutingMetricRecord = {
    model: params.model,
    provider: params.provider,
    stage: params.stage,
    latencyMs: params.latencyMs,
    inputTokens: params.inputTokens ?? 0,
    outputTokens: params.outputTokens ?? 0,
    costUsd: params.costUsd ?? 0,
    validationPassed: params.validationPassed,
    repairPassesNeeded: params.repairPassesNeeded ?? 0,
    timestamp: Timestamp.now(),
  };

  // Non-blocking write — intentionally void.
  void metricsRef(params.repoId, params.stage, params.taskId)
    .set(record)
    .catch(() => {
      // Swallow — metrics are best-effort.
    });
}

// ---------------------------------------------------------------------------
// Read / aggregate
// ---------------------------------------------------------------------------

const SAMPLE_LIMIT = 50;

/**
 * Return per-model performance stats for a given repo + stage, computed
 * from the last `SAMPLE_LIMIT` metric records.
 *
 * Returns an empty array if no metrics are stored yet (new repo).
 */
export async function getModelPerformanceStats(
  repoId: string,
  stage: RepoExecutionProviderStage,
): Promise<ModelStats[]> {
  try {
    const snap = await getFirestore()
      .collection('routingMetrics')
      .doc(repoId)
      .collection(stage)
      .orderBy('timestamp', 'desc')
      .limit(SAMPLE_LIMIT)
      .get();

    if (snap.empty) return [];

    // Group records by model.
    const byModel = new Map<
      string,
      Array<RoutingMetricRecord>
    >();
    for (const doc of snap.docs) {
      const record = doc.data() as RoutingMetricRecord;
      const key = `${record.provider}::${record.model}`;
      if (!byModel.has(key)) byModel.set(key, []);
      byModel.get(key)!.push(record);
    }

    const stats: ModelStats[] = [];
    for (const records of byModel.values()) {
      const n = records.length;
      const successCount = records.filter(r => r.validationPassed).length;
      const avgLatencyMs =
        records.reduce((s, r) => s + r.latencyMs, 0) / n;
      const avgCostUsd =
        records.reduce((s, r) => s + r.costUsd, 0) / n;
      const avgRepairPasses =
        records.reduce((s, r) => s + r.repairPassesNeeded, 0) / n;

      stats.push({
        model: records[0]!.model,
        provider: records[0]!.provider,
        successRate: successCount / n,
        avgLatencyMs,
        avgCostUsd,
        avgRepairPasses,
        sampleCount: n,
      });
    }

    return stats;
  } catch {
    // Firestore query failures (e.g., missing index) should not break routing.
    return [];
  }
}
