import type { AgentToolCategory, AgentToolDefinition, AgentToolName } from './tool_registry'

export type AgentToolExecutionStatus = 'passed' | 'failed' | 'skipped'

export interface AgentToolExecutionRecord {
  toolName: AgentToolName
  label: string
  category: AgentToolCategory
  status: AgentToolExecutionStatus
  summary: string
  durationMs: number
  metadata?: Record<string, unknown>
}

export async function executeAgentTool<T>(params: {
  tool: AgentToolDefinition
  run: () => Promise<T>
  summarizeSuccess?: (value: T) => string
  metadataFromSuccess?: (value: T) => Record<string, unknown> | undefined
}) {
  const startedAt = Date.now()
  try {
    const value = await params.run()
    return {
      value,
      execution: {
        toolName: params.tool.name,
        label: params.tool.label,
        category: params.tool.category,
        status: 'passed' as const,
        summary:
          params.summarizeSuccess?.(value) ??
          `${params.tool.label} completed successfully.`,
        durationMs: Date.now() - startedAt,
        metadata: params.metadataFromSuccess?.(value),
      },
    }
  } catch (error) {
    const message =
      error instanceof Error ? error.message : String(error ?? 'Unknown tool failure.')
    throw Object.assign(error instanceof Error ? error : new Error(message), {
      agentToolExecution: {
        toolName: params.tool.name,
        label: params.tool.label,
        category: params.tool.category,
        status: 'failed' as const,
        summary: `${params.tool.label} failed: ${message}`,
        durationMs: Date.now() - startedAt,
      } satisfies AgentToolExecutionRecord,
    })
  }
}
