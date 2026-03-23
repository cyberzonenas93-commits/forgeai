# Worker System

## Physical Worker Model
The physical worker system is currently implemented with:
- Firestore task docs
- Firestore worker-run docs
- Firebase Functions triggers

Key files:
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/distributed_agent_runtime.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`

## Worker Run Document
Worker runs are stored in:
- `agentWorkerRuns/{runId}`

Each run records:
- ownerId
- taskId
- repoId
- queueWorkspaceId
- runToken
- worker state
- worker kind
- lease duration
- heartbeat time
- claim time
- completion time
- worker metadata

## Worker States
- `queued`
- `claimed`
- `running`
- `completed`
- `failed`
- `cancelled`
- `stale`

## Current Logical Worker Roles
The system still presents one visible agent, but internally tracks role-oriented phases:
- planner
- context
- editor
- validator
- repair
- git

Those roles are logical handoffs recorded in task metadata, while the physical worker is the distributed executor that owns the lease and runs the loop.

## Lease And Heartbeat
- Lease duration: `90s`
- Heartbeat interval: `20s`
- Stale worker recovery threshold: `3m`

Heartbeat updates are written during the agent loop so stale workers can be detected and superseded safely.

## Recovery
Scheduled recovery scans `agentWorkerRuns` for claimed or running leases whose heartbeat is too old.

When a stale run is found:
1. Worker run is marked `stale`.
2. Task metadata records the stale recovery.
3. The task `runToken` is incremented.
4. The normal dispatcher enqueues a fresh worker run.

This prevents a dead worker from permanently wedging the repo queue.

## Same-Repo Serialization
The worker system does not replace the repo lock.

Instead:
- worker runs can exist for many repos in parallel
- one repo still has one active mutating task at a time
- queued tasks remain ordered per repo

## Current Limits
- Physical workers are still generic orchestrator workers, not separate deployable worker binaries per role.
- There is no external autoscaling worker pool dashboard yet.
- Worker recovery is safe and durable, but still centered on Firestore and Functions rather than a dedicated job system.
