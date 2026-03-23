# Agent Runtime Architecture

Read `AGENTS.md`, `WORK_MEMORY.md`, and `ARCHITECTURE_GUARDRAILS.md` first.

This document explains the current runtime shape in detail. It does not replace the startup rules and anti-drift constraints in those files.

## Current Runtime Shape
The main CodeCatalystAI agent path now runs as a distributed durable backend loop instead of a one-shot suggestion flow.

The latest hardening pass removes another “chatbot” remnant:
- repo execution is no longer artificially capped to a tiny generated-file count once the context planner has already selected a broader editable wave
- repair and guardrail regeneration can stop pinning themselves to the last execution provider after the first failure
- repo map, context expansion, and diff generation are now persisted as first-class tool executions instead of hidden orchestration
- the task trigger no longer executes the full agent loop inline; it dispatches an isolated worker run that claims a lease, heartbeats, and can be recovered if it goes stale

1. `enqueueAgentTask` creates a persisted task in `users/{ownerId}/agentTasks/{taskId}`.
2. `runAgentTask` promotes the queued task under a per-repo workspace lock and enqueues a distributed worker run in `agentWorkerRuns/{runId}`.
3. `processDistributedAgentWorker` claims the worker run, heartbeats during execution, and invokes `processAgentTaskRun(...)` as the worker body.
4. `processAgentTaskRun(...)` plans the run, materializes the repo context, and generates a structured multi-file diff.
5. The runtime validates and repairs that draft inside a sandbox workspace before approval.
6. The runtime pauses for explicit apply approval only after the candidate diff has already passed the sandbox loop.
7. After approval, the runtime applies the validated diff to the task-local cloned workspace, confirms post-apply local consistency, and continues into commit / pull request / merge / deploy follow-up steps behind explicit approvals.

## Runtime Layers

### 1. Task Queue And Locking
Implemented in `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`.

- Tasks are persisted before execution starts.
- Only one active task may mutate a repository at a time.
- Later prompts queue behind the active run instead of replacing it.
- Queue promotion still happens per repo, but worker execution is now distributed through `agentWorkerRuns`.

### 2. Distributed Worker Plane
Implemented in:
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/distributed_agent_runtime.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`

The runtime now has:
- a control plane in Firestore task docs, approvals, workspace locks, and worker-run docs
- a worker plane backed by `processDistributedAgentWorker`
- lease and heartbeat tracking per worker run
- scheduled stale-worker recovery that bumps `runToken` and safely re-dispatches the task

This keeps the existing agent loop intact while making the execution substrate scalable across multiple repos and concurrent tasks.

### 3. Repo Context Layer
Implemented across:
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/repo_knowledge_map.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/repo_context_strategy.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/repo_index_service.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`

The runtime now builds:
- a repo-wide knowledge map
- architecture zones
- module summaries
- progressive exploration passes
- durable execution memory

### 4. Provider Routing Layer
Implemented in:
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/routing_engine.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/provider_interface.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/cost_optimization.ts`

The repo-agent path no longer hardcodes OpenAI for planning and diff generation.

The router now:
- considers stage (`context_planner`, `execution_planner`, `generate_diff`, `repair_diff`)
- considers deep mode
- considers repo size class
- considers a task-level cost profile (`economy`, `balanced`, `quality`)
- prefers Anthropic for deeper planning and repair loops when available
- prefers OpenAI for faster primary normal-mode diff generation when available
- keeps Gemini in the active fallback order

The chosen provider, model, routing reason, and estimated stage cost are now persisted into task/session metadata.

### 5. Tool Registry And Execution Layer
Implemented in:
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/tool_registry.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/tool_executor.ts`

The runtime now has an explicit tool catalog for the main agent path:
- clone repo workspace
- repo map
- context expansion
- structured diff generation
- apply local workspace
- validation suite
- commit local workspace
- open pull request
- merge pull request
- trigger deploy

Tool executions are now recorded into task metadata so the user can see which runtime tools actually ran during the task.

The follow-up hardening pass also records explicit live tool executions for repo clone, repo map, context expansion, diff generation, local-workspace apply, validation, and remote follow-up steps instead of limiting visibility to validation only.

The latest pass adds a task-local cloned workspace substrate in `/Users/angelonartey/Desktop/ForgeAI/functions/src/ephemeral_workspace.ts`, which lets the runtime validate candidate edits in sandbox copies and then commit or push approved changes with real git commands from that cloned workspace.

### 6. Validation And Repair Layer
Implemented in:
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/agent_validation_tools.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`

Validation is now agent-driven:
- sandbox validation before approval
- workspace consistency after approval
- static repo validation
- CI validation on validation branches
- structured failure reuse
- repair-pass regeneration

Repair loops now also:
- promote failing file paths back into repo exploration
- retry malformed structured edit payloads across a broader provider fallback chain

### 7. Logical Multi-Agent Layer
Implemented in:
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/multi_agent_system.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`

The system still presents one visible agent, but internally it now records role-based orchestration across:
- planner
- context
- editor
- validator
- repair
- git

Those handoffs are persisted into task metadata so the runtime can coordinate specialized phases without reviving a weak chatbot path.

### 8. Live Session Layer
Implemented in:
- `/Users/angelonartey/Desktop/ForgeAI/lib/src/features/agent/agent_mode_screen.dart`
- `/Users/angelonartey/Desktop/ForgeAI/lib/src/features/agent/agent_task_details_screen.dart`
- `/Users/angelonartey/Desktop/ForgeAI/lib/src/features/agent/widgets/active_step_header.dart`
- `/Users/angelonartey/Desktop/ForgeAI/lib/src/features/agent/widgets/task_summary_card.dart`
- `/Users/angelonartey/Desktop/ForgeAI/lib/src/features/agent/widgets/queue_item_card.dart`

The UI now surfaces:
- queue state
- repo-understanding progress
- routed provider/model
- tool catalog
- recent tool executions
- validation pass counts
- repair pass counts
- explicit hard-limit stop state

## Still Not Full Local-Agent Parity
The runtime is materially closer to Claude Code / Cursor / Codex, but these limits remain:

- no arbitrary shell execution beyond the allowlisted workspace commands
- no fully general local test/build/stdout loop with terminal-style iteration
- repo understanding still starts from synced metadata plus hydrated file content before execution switches to the cloned workspace
- Firestore still stores repo metadata, events, approvals, and some legacy compatibility draft flows outside the main agent path
- GitHub remains the strongest remote validation backend
- worker execution is distributed inside Firebase Functions rather than a dedicated Cloud Run worker pool
