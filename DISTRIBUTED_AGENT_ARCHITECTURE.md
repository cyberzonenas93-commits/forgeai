# Distributed Agent Architecture

Read `AGENTS.md`, `WORK_MEMORY.md`, and `ARCHITECTURE_GUARDRAILS.md` first.

## Goal
Scale the existing repo-native agent loop into a production-oriented distributed execution system without weakening the current agent-first behavior.

The current implementation uses Firebase Functions plus Firestore as:
- control plane
- worker queue
- lease store
- event bus
- approval state store

## Control Plane
Implemented primarily in:
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/distributed_agent_runtime.ts`

The control plane is responsible for:
1. Creating agent tasks in `users/{ownerId}/agentTasks/{taskId}`.
2. Enforcing one active write task per repo with `workspaceLocks/{repoId}`.
3. Promoting queued tasks when a repo lock becomes free.
4. Dispatching a worker run doc in `agentWorkerRuns/{ownerId_taskId_runToken}`.
5. Holding approvals, task state, live events, and execution metadata in Firestore.

## Worker Plane
Implemented in:
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`
  - `processDistributedAgentWorker`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/distributed_agent_runtime.ts`

Each worker run:
1. Claims a Firestore worker-run lease.
2. Writes heartbeat updates while the task loop runs.
3. Executes the full repo agent loop via `processAgentTaskRun(...)`.
4. Finalizes the worker run as completed, cancelled, failed, or stale.

## Queue Model
- Queue is still per repository.
- Multiple repos can execute in parallel because each promoted task now becomes an independent worker run.
- Same-repo tasks remain serialized by the repo workspace lock.

## Worker Lifecycle
1. Task enters `running` with a new `runToken`.
2. `runAgentTask` enqueues a worker run doc.
3. `processDistributedAgentWorker` claims the run.
4. Worker heartbeats every `20s`.
5. Worker finishes or pauses at approval.
6. `recoverStaleAgentWorkers` detects expired leases and re-dispatches by bumping `runToken`.

## Event Bus
Live events remain persisted to:
- `users/{ownerId}/agentTasks/{taskId}/events`

Worker metrics are additionally stored under:
- `agentWorkerRuns/{runId}/metrics`

This keeps the mobile UI aligned with the active run while also making worker execution inspectable.

## Why This Is Better Than The Old Shape
Previously, the Firestore trigger that noticed a task start also ran the full agent loop inline.

Now:
- dispatch is separated from execution
- workers have leases and heartbeats
- stale runs can be recovered
- concurrent multi-repo execution scales better
- the control plane remains durable even if a worker dies mid-run

## Current Limits
- Worker execution is still distributed within Firebase Functions rather than a dedicated Cloud Run worker fleet.
- Firestore remains the queue and lease backbone.
- Long-running tasks still depend on function timeout ceilings and heartbeat recovery instead of permanently running agents.
