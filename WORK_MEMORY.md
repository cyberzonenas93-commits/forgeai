# CodeCatalystAI Working Memory

## Current System In One Pass
CodeCatalystAI is a distributed, agent-first mobile coding system.

The strongest path today is:

`prompt -> enqueueAgentTask -> repo lock -> runAgentTask dispatch -> processDistributedAgentWorker claim -> processAgentTaskRun -> layered repo context -> task-local cloned workspace -> structured multi-file diff -> sandbox validation/repair loop -> approval -> apply to task-local workspace -> post-apply validation -> commit/PR/merge/deploy follow-up`

This is the current product truth.

## What Is Already Built
- Durable task queueing with per-repo serialization.
- Distributed worker runs with leases, heartbeats, and stale-worker recovery.
- Layered repo awareness with repo knowledge map, module summaries, architecture zones, progressive hydration, and execution memory.
- Task-local cloned git workspace for the main execution path.
- Sandbox validation before apply approval.
- Post-apply validation and git-native follow-up actions.
- Structured tool layer and tool-execution history.
- Iterative repair loop with structured failure reuse, repeated-failure memory, strategy escalation, and narrow-first validation reruns.
- Stage-aware and cost-aware provider routing across `openai`, `anthropic`, and `gemini`.
- Logical planner/context/editor/validator/repair/git orchestration inside one visible agent.
- Live agent UI with queue state, repo-understanding visibility, validation history, and approvals.

## What Firestore Does
Firestore is the control plane and durable memory plane.

Firestore stores:
- synced repo metadata
- repo index or map artifacts
- execution sessions
- agent tasks
- task events
- approvals
- worker runs
- checks
- wallet and cost metadata
- compatibility data

Firestore is not the strongest-path execution workspace.
Firestore is not the source of truth for live repair attempts.

## What The Main Execution Workspace Is
The strongest execution workspace is task-local and git-native.

The runtime:
1. clones the repo into a task-local workspace
2. creates sandbox copies for validation
3. applies validated edits to the task-local workspace
4. runs real git commit/push/PR flows from that workspace
5. keeps repair attempts anchored to the failing sandbox or task-local workspace instead of a Firestore draft snapshot

Primary files:
- `functions/src/index.ts`
- `functions/src/ephemeral_workspace.ts`

## Strongest Files To Inspect First
- `functions/src/index.ts`
- `functions/src/distributed_agent_runtime.ts`
- `functions/src/ephemeral_workspace.ts`
- `functions/src/repo_knowledge_map.ts`
- `functions/src/repo_context_strategy.ts`
- `functions/src/repo_index_service.ts`
- `functions/src/repo_execution_format.ts`
- `functions/src/agent_validation_tools.ts`
- `functions/src/tool_registry.ts`
- `functions/src/tool_executor.ts`
- `functions/src/cost_optimization.ts`
- `functions/src/multi_agent_system.ts`
- `functions/src/routing_engine.ts`
- `lib/src/features/workspace/application/forge_workspace_controller.dart`
- `lib/src/features/workspace/data/forge_workspace_repository.dart`
- `lib/src/features/agent/agent_mode_screen.dart`
- `lib/src/features/agent/agent_task_details_screen.dart`
- `lib/src/features/diff/diff_review_screen.dart`

## Deprecated Or Compatibility Paths
These exist in code but are not the primary architecture:
- `askRepo`
- `suggestChange`
- `applyRepoExecution`
- `apply_file_edits`
- any chat-first mounted surface
- any single-file suggestion-first flow
- any Firestore-draft-only execution path used as the main agent path

If a future task touches these, keep the change compatibility-scoped and do not let them become the default product path again.

## Remaining Gaps Versus Claude Code / Cursor
- No arbitrary shell or terminal substrate.
- No fully open local test/build/stdout loop.
- Repo understanding still starts from synced metadata plus progressive hydration before execution shifts into the local clone.
- Distributed workers are Firebase-triggered, not a dedicated Cloud Run worker fleet.
- Provider routing is heuristic plus cost-aware, not benchmark-adaptive.
- Validation branch cleanup is still incomplete.
- Embeddings and vector retrieval are still not implemented.
- Repair strategy escalation is stronger now, but it is still policy-driven rather than learned from cross-task historical outcomes.

## Current Risks
- Firestore is still heavily involved in coordination, so architecture drift can happen if future work confuses the control plane with the execution workspace.
- Compatibility endpoints still exist and are easy to accidentally revive if future sessions do not read the memory docs first.
- Some historical docs still discuss older architectures in contrast. Use `AGENTS.md`, `WORK_MEMORY.md`, `ARCHITECTURE_GUARDRAILS.md`, and `AGENT_RUNTIME_ARCHITECTURE.md` as the current truth.
- Repeated-failure memory is task-scoped. Future work should avoid accidentally treating it as repo-global truth or training data.

## Verification Floor
Use this verification floor for runtime or architecture changes:
- `npm --prefix /Users/angelonartey/Desktop/ForgeAI/functions run lint`
- `npm --prefix /Users/angelonartey/Desktop/ForgeAI/functions run build`
- `dart analyze /Users/angelonartey/Desktop/ForgeAI/lib/src test`
- `flutter test`

Use broader checks when the change warrants them:
- `npm run verify:launch`
- `npm run smoke:backend`
- `node ./tool/validate_launch_env.mjs --strict`

## Next Priority Directions
- Expand the allowlisted local tool surface without opening arbitrary shell execution.
- Decide whether to move distributed workers to Cloud Run or another dedicated worker pool.
- Continue deprecating or isolating compatibility paths.
- Improve validation branch cleanup.
- Push repo understanding closer to local-clone indexing instead of synced-metadata-first bootstrapping.
- Consider whether repeated-failure patterns should inform future routing heuristics across tasks without weakening task-local determinism.

## Startup Rule For Future AI Runs
Before making architecture changes, answer these five questions:

1. Does the change preserve the distributed durable agent path?
2. Does it preserve validation-before-apply?
3. Does it preserve task-local git-native execution?
4. Does it preserve deep repo context and execution memory?
5. Does it keep compatibility paths secondary?

If any answer is no, stop and reconsider the change before implementing it.
