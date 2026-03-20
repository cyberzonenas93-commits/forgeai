# Task Queue

## Queue Scope
The queue is workspace-scoped. In this app, a workspace maps to a repository id, so only one task can actively own a repo at a time.

## Lifecycle
1. Prompt submission creates `users/{ownerId}/agentTasks/{taskId}` with status `queued`.
2. If `workspaceLocks/{repoId}` is free, the task is promoted to `running`.
3. If another task already owns the lock, the task stays queued and the UI shows its position.
4. When a task reaches `completed`, `failed`, or `cancelled`, the lock is released.
5. The backend immediately promotes the next queued task for that repo.

## Ordering
- Queue order is FIFO by `createdAtMs`.
- The frontend computes queue position from the streamed task list for the selected repo.

## Waiting For Input
- `waiting_for_input` still holds the workspace lock.
- This keeps the queue stable while the user reviews a diff or approves a risky remote action.
- New prompts during this time are accepted, but they remain queued behind the blocked task.

## Cancellation
- queued task: removed immediately and marked `cancelled`
- waiting task: cancelled immediately, lock released, next task promoted
- running task: records a cancellation request and stops at the next safe checkpoint

## Pause
- pause is implemented as a checkpoint request
- the runner pauses at a safe boundary, transitions to `waiting_for_input`, and requires approval to resume

## Failure Recovery
- stale running locks are recoverable by the queue promoter
- final task states always release the lock
- malformed structured execution output retries across the repair and provider fallback path until retry guardrails are exhausted

## Persistence
- queue state lives in Firestore
- app refreshes do not drop tasks
- the selected task can be re-opened and its event timeline replayed from Firestore
