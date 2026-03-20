export type AgentToolCategory =
  | 'repo_context'
  | 'editing'
  | 'validation'
  | 'git'

export type AgentToolName =
  | 'clone_repo_workspace'
  | 'repo_map'
  | 'context_expand'
  | 'generate_diff'
  | 'apply_working_copy'
  | 'validation_suite'
  | 'shell_exec'
  | 'commit_working_copy'
  | 'open_pull_request'
  | 'merge_pull_request'
  | 'trigger_deploy'

export interface AgentToolDefinition {
  name: AgentToolName
  label: string
  category: AgentToolCategory
  description: string
  automatic: boolean
  requiresApproval: boolean
}

export interface AgentToolPlanLike {
  commitChanges?: boolean
  openPullRequest?: boolean
  mergePullRequest?: boolean
  deployWorkflow?: boolean
}

const BASE_TOOL_REGISTRY: Record<AgentToolName, AgentToolDefinition> = {
  clone_repo_workspace: {
    name: 'clone_repo_workspace',
    label: 'Clone repo workspace',
    category: 'git',
    description: 'Clones the remote repository into an isolated per-task local workspace for validation, repair, and git-native follow-up actions.',
    automatic: true,
    requiresApproval: false,
  },
  repo_map: {
    name: 'repo_map',
    label: 'Repo map',
    category: 'repo_context',
    description: 'Scans the synced repository, knowledge map, module summaries, and global architecture zones.',
    automatic: true,
    requiresApproval: false,
  },
  context_expand: {
    name: 'context_expand',
    label: 'Context expansion',
    category: 'repo_context',
    description: 'Expands beyond the first candidate set using module, import, directory, and ripple-path signals.',
    automatic: true,
    requiresApproval: false,
  },
  generate_diff: {
    name: 'generate_diff',
    label: 'Structured diff generation',
    category: 'editing',
    description: 'Generates multi-file repo edits in the strict FILE / BEFORE / AFTER execution format.',
    automatic: true,
    requiresApproval: false,
  },
  apply_working_copy: {
    name: 'apply_working_copy',
    label: 'Apply local workspace',
    category: 'editing',
    description: 'Applies the approved execution session into the task-local cloned workspace.',
    automatic: true,
    requiresApproval: true,
  },
  validation_suite: {
    name: 'validation_suite',
    label: 'Validation suite',
    category: 'validation',
    description: 'Runs sandbox validation in cloned workspaces before approval, then confirms the applied local workspace and remote validation before follow-up actions.',
    automatic: true,
    requiresApproval: false,
  },
  shell_exec: {
    name: 'shell_exec',
    label: 'Shell execution',
    category: 'validation',
    description:
      'Runs an arbitrary shell command string in the cloned workspace. ' +
      'Optionally sandboxed via Docker (network-isolated, memory-capped). ' +
      'Captures stdout, stderr, exit code, and execution time.',
    automatic: true,
    requiresApproval: false,
  },
  commit_working_copy: {
    name: 'commit_working_copy',
    label: 'Commit local workspace',
    category: 'git',
    description: 'Commits and pushes the approved task-local workspace with real git commands.',
    automatic: false,
    requiresApproval: true,
  },
  open_pull_request: {
    name: 'open_pull_request',
    label: 'Open pull request',
    category: 'git',
    description: 'Creates a branch from the task-local workspace, pushes it, and opens a pull request.',
    automatic: false,
    requiresApproval: true,
  },
  merge_pull_request: {
    name: 'merge_pull_request',
    label: 'Merge pull request',
    category: 'git',
    description: 'Merges the generated pull request after approval.',
    automatic: false,
    requiresApproval: true,
  },
  trigger_deploy: {
    name: 'trigger_deploy',
    label: 'Trigger deploy',
    category: 'git',
    description: 'Dispatches the deploy workflow after code validation and optional pull request steps.',
    automatic: false,
    requiresApproval: true,
  },
}

export function getAgentToolDefinition(name: AgentToolName) {
  return BASE_TOOL_REGISTRY[name]
}

export function buildAgentToolRegistry(params: {
  deepMode: boolean
  followUpPlan?: AgentToolPlanLike | null
}) {
  const tools: AgentToolDefinition[] = [
    BASE_TOOL_REGISTRY.clone_repo_workspace,
    BASE_TOOL_REGISTRY.repo_map,
    BASE_TOOL_REGISTRY.context_expand,
    BASE_TOOL_REGISTRY.generate_diff,
    BASE_TOOL_REGISTRY.apply_working_copy,
    BASE_TOOL_REGISTRY.validation_suite,
  ]
  if (params.followUpPlan?.openPullRequest) {
    tools.push(BASE_TOOL_REGISTRY.open_pull_request)
  } else if (params.followUpPlan?.commitChanges) {
    tools.push(BASE_TOOL_REGISTRY.commit_working_copy)
  }
  if (params.followUpPlan?.mergePullRequest) {
    tools.push(BASE_TOOL_REGISTRY.merge_pull_request)
  }
  if (params.followUpPlan?.deployWorkflow) {
    tools.push(BASE_TOOL_REGISTRY.trigger_deploy)
  }
  return tools
}

export function serializeAgentToolRegistry(tools: AgentToolDefinition[]) {
  return tools.map(tool => ({
    name: tool.name,
    label: tool.label,
    category: tool.category,
    description: tool.description,
    automatic: tool.automatic,
    requiresApproval: tool.requiresApproval,
  }))
}

export function summarizeAgentToolRegistry(tools: AgentToolDefinition[]) {
  return tools.map(tool => tool.label).join(' -> ')
}
