import { FieldValue, type Firestore } from 'firebase-admin/firestore'

export type DistributedAgentWorkerState =
  | 'queued'
  | 'claimed'
  | 'running'
  | 'completed'
  | 'failed'
  | 'cancelled'
  | 'stale'

export type DistributedAgentWorkerKind =
  | 'orchestrator'
  | 'planner'
  | 'context'
  | 'editor'
  | 'validator'
  | 'repair'
  | 'git'

export interface DistributedAgentWorkerRunDocument {
  runId: string
  ownerId: string
  taskId: string
  repoId: string
  queueWorkspaceId: string
  runToken: number
  state: DistributedAgentWorkerState
  kind: DistributedAgentWorkerKind
  phase: string
  summary: string
  createdAtMs: number
  updatedAtMs: number
  leaseDurationMs: number
  attempt: number
  workerId?: string | null
  claimedAtMs?: number | null
  heartbeatAtMs?: number | null
  completedAtMs?: number | null
  metadata?: Record<string, unknown>
}

export interface DistributedAgentWorkerQueueResult {
  runId: string
  created: boolean
}

export interface DistributedAgentWorkerClaimResult {
  claimed: boolean
  workerRun: DistributedAgentWorkerRunDocument | null
}

function workerRunsCollection(db: Firestore) {
  return db.collection('agentWorkerRuns')
}

export function distributedAgentWorkerRunRef(db: Firestore, runId: string) {
  return workerRunsCollection(db).doc(runId)
}

export function buildDistributedAgentWorkerRunId(params: {
  ownerId: string
  taskId: string
  runToken: number
}) {
  return `${params.ownerId}_${params.taskId}_${params.runToken}`
}

export function buildDistributedWorkerSummary(params: {
  kind: DistributedAgentWorkerKind
  phase: string
  repoId: string
}) {
  return `${params.kind} worker queued for ${params.repoId} during ${params.phase}.`
}

export async function queueDistributedAgentWorkerRun(params: {
  db: Firestore
  ownerId: string
  taskId: string
  repoId: string
  queueWorkspaceId: string
  runToken: number
  phase: string
  kind?: DistributedAgentWorkerKind
  leaseDurationMs: number
  metadata?: Record<string, unknown>
}) {
  const runId = buildDistributedAgentWorkerRunId({
    ownerId: params.ownerId,
    taskId: params.taskId,
    runToken: params.runToken,
  })
  const reference = distributedAgentWorkerRunRef(params.db, runId)
  const now = Date.now()
  let created = false
  await params.db.runTransaction(async transaction => {
    const snapshot = await transaction.get(reference)
    if (snapshot.exists) {
      return
    }
    created = true
    const workerRun: DistributedAgentWorkerRunDocument = {
      runId,
      ownerId: params.ownerId,
      taskId: params.taskId,
      repoId: params.repoId,
      queueWorkspaceId: params.queueWorkspaceId,
      runToken: params.runToken,
      state: 'queued',
      kind: params.kind ?? 'orchestrator',
      phase: params.phase,
      summary: buildDistributedWorkerSummary({
        kind: params.kind ?? 'orchestrator',
        phase: params.phase,
        repoId: params.repoId,
      }),
      createdAtMs: now,
      updatedAtMs: now,
      leaseDurationMs: params.leaseDurationMs,
      attempt: 1,
      workerId: null,
      claimedAtMs: null,
      heartbeatAtMs: null,
      completedAtMs: null,
      metadata: params.metadata ?? {},
    }
    transaction.set(reference, workerRun, { merge: true })
  })
  return {
    runId,
    created,
  } satisfies DistributedAgentWorkerQueueResult
}

export async function claimDistributedAgentWorkerRun(params: {
  db: Firestore
  runId: string
  workerId: string
  leaseDurationMs: number
}) {
  const reference = distributedAgentWorkerRunRef(params.db, params.runId)
  const now = Date.now()
  let workerRun: DistributedAgentWorkerRunDocument | null = null
  await params.db.runTransaction(async transaction => {
    const snapshot = await transaction.get(reference)
    if (!snapshot.exists) {
      return
    }
    const current = snapshot.data() as DistributedAgentWorkerRunDocument
    const expiredLease =
      (current.state === 'claimed' || current.state === 'running') &&
      typeof current.heartbeatAtMs === 'number' &&
      now - current.heartbeatAtMs > (current.leaseDurationMs || params.leaseDurationMs)
    if (
      current.state !== 'queued' &&
      current.state !== 'stale' &&
      !expiredLease
    ) {
      return
    }
    workerRun = {
      ...current,
      state: 'running',
      workerId: params.workerId,
      claimedAtMs: current.claimedAtMs ?? now,
      heartbeatAtMs: now,
      updatedAtMs: now,
      leaseDurationMs: params.leaseDurationMs,
      attempt: typeof current.attempt === 'number' ? current.attempt + (expiredLease ? 1 : 0) : 1,
      summary: expiredLease
        ? `Worker lease recovered and resumed by ${params.workerId}.`
        : `Worker claimed by ${params.workerId}.`,
    }
    transaction.set(reference, workerRun, { merge: true })
  })
  return {
    claimed: workerRun != null,
    workerRun,
  } satisfies DistributedAgentWorkerClaimResult
}

export async function heartbeatDistributedAgentWorkerRun(params: {
  db: Firestore
  runId: string
  workerId: string
  phase?: string
  summary?: string
  metadata?: Record<string, unknown>
}) {
  const reference = distributedAgentWorkerRunRef(params.db, params.runId)
  const snapshot = await reference.get()
  if (!snapshot.exists) {
    return false
  }
  const current = snapshot.data() as DistributedAgentWorkerRunDocument
  if (current.workerId && current.workerId !== params.workerId) {
    return false
  }
  await reference.set(
    {
      state: 'running',
      workerId: params.workerId,
      phase: params.phase ?? current.phase,
      summary: params.summary ?? current.summary,
      heartbeatAtMs: Date.now(),
      updatedAtMs: Date.now(),
      metadata: {
        ...(current.metadata ?? {}),
        ...(params.metadata ?? {}),
      },
    },
    { merge: true },
  )
  return true
}

export async function finalizeDistributedAgentWorkerRun(params: {
  db: Firestore
  runId: string
  workerId: string
  state: Extract<DistributedAgentWorkerState, 'completed' | 'failed' | 'cancelled' | 'stale'>
  summary: string
  phase?: string
  metadata?: Record<string, unknown>
}) {
  const reference = distributedAgentWorkerRunRef(params.db, params.runId)
  const snapshot = await reference.get()
  if (!snapshot.exists) {
    return
  }
  const current = snapshot.data() as DistributedAgentWorkerRunDocument
  await reference.set(
    {
      state: params.state,
      workerId: current.workerId ?? params.workerId,
      phase: params.phase ?? current.phase,
      summary: params.summary,
      heartbeatAtMs: Date.now(),
      completedAtMs: Date.now(),
      updatedAtMs: Date.now(),
      metadata: {
        ...(current.metadata ?? {}),
        ...(params.metadata ?? {}),
      },
    },
    { merge: true },
  )
}

export async function recoverStaleDistributedAgentWorkerRuns(params: {
  db: Firestore
  staleAfterMs: number
  limit?: number
}) {
  const snapshot = await workerRunsCollection(params.db)
    .where('state', 'in', ['claimed', 'running'])
    .limit(params.limit ?? 40)
    .get()
  const now = Date.now()
  const staleRuns: DistributedAgentWorkerRunDocument[] = []
  for (const doc of snapshot.docs) {
    const data = doc.data() as DistributedAgentWorkerRunDocument
    const heartbeatAtMs =
      typeof data.heartbeatAtMs === 'number' ? data.heartbeatAtMs : data.updatedAtMs
    if (now - heartbeatAtMs <= params.staleAfterMs) {
      continue
    }
    staleRuns.push(data)
    await doc.ref.set(
      {
        state: 'stale',
        summary: 'Worker lease expired before completion.',
        updatedAtMs: now,
        completedAtMs: now,
        metadata: {
          ...(data.metadata ?? {}),
          recoveredAtMs: now,
        },
      },
      { merge: true },
    )
  }
  return staleRuns
}

export function serializeDistributedWorkerMetadata(params: {
  runId: string
  state: DistributedAgentWorkerState
  workerId?: string | null
  summary: string
  heartbeatAtMs?: number | null
  claimedAtMs?: number | null
  completedAtMs?: number | null
  phase?: string | null
}) {
  return {
    latestWorkerRunId: params.runId,
    latestWorkerState: params.state,
    latestWorkerId: params.workerId ?? null,
    latestWorkerSummary: params.summary,
    latestWorkerHeartbeatAtMs: params.heartbeatAtMs ?? null,
    latestWorkerClaimedAtMs: params.claimedAtMs ?? null,
    latestWorkerCompletedAtMs: params.completedAtMs ?? null,
    latestWorkerPhase: params.phase ?? null,
  }
}

export async function appendDistributedWorkerMetric(params: {
  db: Firestore
  runId: string
  metricType: string
  payload: Record<string, unknown>
}) {
  await distributedAgentWorkerRunRef(params.db, params.runId)
    .collection('metrics')
    .add({
      metricType: params.metricType,
      payload: params.payload,
      createdAt: FieldValue.serverTimestamp(),
      createdAtMs: Date.now(),
    })
}
