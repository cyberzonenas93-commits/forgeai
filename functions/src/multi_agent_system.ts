export type LogicalAgentRole =
  | 'orchestrator'
  | 'planner'
  | 'context'
  | 'editor'
  | 'validator'
  | 'repair'
  | 'git'

export interface LogicalAgentStepRecord {
  role: LogicalAgentRole
  state: 'started' | 'completed' | 'handoff'
  summary: string
  createdAtMs: number
  data?: Record<string, unknown>
}

export function buildLogicalAgentPlan(params: {
  prompt: string
  deepMode: boolean
  followUpPlan?: {
    commitChanges?: boolean
    openPullRequest?: boolean
    mergePullRequest?: boolean
    deployWorkflow?: boolean
  } | null
}) {
  const steps: Array<{ role: LogicalAgentRole; summary: string }> = [
    {
      role: 'planner' as const,
      summary: params.deepMode
        ? 'Break the request into a broader repo-native execution plan.'
        : 'Break the request into a fast repo-native execution plan.',
    },
    {
      role: 'context' as const,
      summary: 'Map the repo, inspect dependencies, and widen context before edits.',
    },
    {
      role: 'editor' as const,
      summary: 'Generate a structured multi-file diff for the current edit wave.',
    },
    {
      role: 'validator' as const,
      summary: 'Run validation tools and collect structured failures.',
    },
  ]
  if (params.followUpPlan?.openPullRequest || params.followUpPlan?.commitChanges) {
    steps.push({
      role: 'git' as const,
      summary: 'Prepare git-native follow-up actions after approval.',
    })
  }
  return {
    promptPreview: params.prompt.slice(0, 160),
    deepMode: params.deepMode,
    steps,
  }
}

export function appendLogicalAgentRecord(
  metadata: Record<string, unknown> | null | undefined,
  record: LogicalAgentStepRecord,
) {
  const existingMetadata = metadata && typeof metadata === 'object' ? metadata : {}
  const history = Array.isArray((existingMetadata as Record<string, unknown>).logicalAgentTimeline)
    ? ((existingMetadata as Record<string, unknown>).logicalAgentTimeline as unknown[])
        .filter((value): value is LogicalAgentStepRecord => value != null && typeof value === 'object')
    : []
  const nextHistory = [...history.slice(-23), record]
  return {
    ...existingMetadata,
    logicalAgentTimeline: nextHistory,
    logicalAgentRole: record.role,
    logicalAgentState: record.state,
    logicalAgentSummary: record.summary,
    logicalAgentUpdatedAtMs: record.createdAtMs,
  }
}

export function buildLogicalAgentRecord(params: {
  role: LogicalAgentRole
  state: LogicalAgentStepRecord['state']
  summary: string
  data?: Record<string, unknown>
}) {
  return {
    role: params.role,
    state: params.state,
    summary: params.summary,
    createdAtMs: Date.now(),
    data: params.data,
  } satisfies LogicalAgentStepRecord
}

export function summarizeLogicalAgentTimeline(metadata: Record<string, unknown> | null | undefined) {
  if (!metadata || typeof metadata !== 'object') {
    return 'No logical agent activity recorded yet.'
  }
  const data = metadata as Record<string, unknown>
  const role = typeof data.logicalAgentRole === 'string' ? data.logicalAgentRole : null
  const summary = typeof data.logicalAgentSummary === 'string' ? data.logicalAgentSummary : null
  if (!role || !summary) {
    return 'Logical agent orchestration is active.'
  }
  return `${role}: ${summary}`
}
