# CodeCatalystAI Repo Instructions

## Read This First
Before touching runtime, repo context, validation, workspace, queueing, approvals, git follow-up, or agent UI, read these files in this order:

1. `AGENTS.md`
2. `WORK_MEMORY.md`
3. `ARCHITECTURE_GUARDRAILS.md`
4. `AGENT_RUNTIME_ARCHITECTURE.md`

If a proposed change conflicts with these files, update the files in the same pass or do not make the change.

## Project Mission
CodeCatalystAI is a mobile-first coding-agent product.

It is not a chat assistant.
It is not a suggestion engine.
It is not a single-shot diff generator.

The product goal is a live coding-agent workflow where the system:
- inspects the repo deeply
- edits real task-local files
- validates and repairs automatically
- pauses only at explicit approvals
- continues into commit, PR, merge, and deploy follow-up steps

## Primary Product Truth
The default and strongest path must remain:

`prompt -> durable queued task -> distributed worker run -> repo context expansion -> structured multi-file diff -> sandbox validation/repair loop -> approval -> apply to task-local workspace -> post-apply validation -> commit/PR/merge/deploy follow-up`

Anything weaker than that is not the main architecture.

## Non-Negotiable Architecture Truths
- The main UX is a live agent run with queue state, progress, validation, retries, and approvals.
- The primary execution path is agent-first and durable. UI flows must enqueue tasks instead of bypassing the runtime.
- Firestore is the control plane and coordination plane. It stores task state, queue state, approvals, events, worker runs, repo metadata, checks, cost ledgers, and compatibility data.
- Firestore is not the primary execution workspace for the strongest agent path.
- The primary execution workspace is task-local and git-native. See `functions/src/ephemeral_workspace.ts`.
- Validation and repair happen before apply approval. The user should review a validated candidate, not an unvalidated first draft.
- Same-repo tasks serialize behind the repo lock. Different repos may run in parallel.
- Repo understanding is layered, progressive, and stateful. Do not collapse it back to a shallow top-N file picker.
- Provider routing is stage-aware and cost-aware. Do not collapse it back to a single-provider assumption.
- The system may record logical planner/context/editor/validator/repair/git roles internally, but the product still presents one visible agent.

## Execution Path That Must Be Preserved
1. `enqueueAgentTask` creates the durable task.
2. `promoteNextQueuedAgentTask` grants the repo lock and moves the task to `running`.
3. `runAgentTask` dispatches a worker run instead of executing the whole loop inline.
4. `processDistributedAgentWorker` claims the worker lease, heartbeats, and runs `processAgentTaskRun(...)`.
5. The runtime builds repo context through repo knowledge maps, context planning, execution memory, and progressive hydration.
6. The runtime clones a task-local repo workspace.
7. The runtime generates a structured multi-file diff.
8. The runtime validates and repairs that diff in sandbox workspace copies until pass or hard limit.
9. Only after sandbox validation passes does the runtime request apply approval.
10. Approval applies the validated diff to the task-local workspace.
11. The runtime validates post-apply state and continues into explicit git follow-up approvals.

## Files Future Runs Should Inspect First
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

## Deprecated Paths That Must Not Become Primary Again
These may still exist for compatibility. They are not the product path.

- `askRepo`
- `suggestChange`
- `applyRepoExecution`
- `apply_file_edits`
- any single-file-only suggestion or approval flow that bypasses durable task queueing
- any resurrected `AskScreen`-style mounted chat surface
- any UI path that turns the main experience back into prompt/reply text instead of live agent work
- any change that makes Firestore draft docs the main execution workspace again

If a task touches one of these paths, keep it isolated and clearly compatibility-scoped.

## Rules For Future AI Runs
- Start from the strongest path above. Do not reason from older launch-era or chat-era architecture.
- Do not reintroduce chatbot wording, suggestion-first UX, or “here is what to do” behavior as the main experience.
- Do not bypass queueing, worker dispatch, repo locks, validation-before-apply, or follow-up approvals.
- Do not weaken repo context into fixed tiny file bundles when deeper layered context already exists.
- Do not treat compatibility endpoints as architectural truth.
- When changing runtime, workspace, validation, repo context, provider routing, or queue semantics, update the architecture docs in the same pass.
- Keep user-facing AI language agentic and active: inspecting, expanding context, editing, validating, retrying, awaiting approval, continuing.

## Required AI Run Checklist
1. Read `AGENTS.md`, `WORK_MEMORY.md`, and `ARCHITECTURE_GUARDRAILS.md`.
2. Inspect the current strongest-path files for the subsystem you are touching.
3. Check whether any compatibility path is involved and keep it secondary.
4. Implement the change without weakening the main agent path.
5. Run verification.
6. Update `CHANGELOG.md` and any affected architecture docs.

## Verification Floor
For core runtime or architecture changes, the default verification floor is:

- `npm --prefix /Users/angelonartey/Desktop/ForgeAI/functions run lint`
- `npm --prefix /Users/angelonartey/Desktop/ForgeAI/functions run build`
- `dart analyze /Users/angelonartey/Desktop/ForgeAI/lib/src test`
- `flutter test`

Use broader checks when relevant:

- `npm run verify:launch`
- `npm run smoke:backend`
- `node ./tool/validate_launch_env.mjs --strict`
