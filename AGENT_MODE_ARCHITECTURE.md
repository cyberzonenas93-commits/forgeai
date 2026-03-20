# Agent Mode Architecture

## Goal
CodeCatalystAI now treats prompts as durable agent tasks instead of one-shot chat replies. A prompt becomes a persisted task, joins a workspace queue, emits live events while it runs, pauses for approvals, and resumes from the backend.

## Core Components
- Flutter client: submits prompts, watches task/event streams, shows the active work session, queued prompts, approvals, and controls.
- Firestore task store: persists agent tasks, task events, approvals, execution sessions, and workspace locks.
- Cloud Functions runner: owns queue promotion, workspace locking, repo inspection, model calls, approval pauses, follow-up actions, and final task completion.

## Firestore Model
- `users/{ownerId}/agentTasks/{taskId}`
  - durable task record
  - status: `queued`, `running`, `waiting_for_input`, `completed`, `failed`, `cancelled`
  - stores prompt, repo scope, guardrails, selected files, diff counts, approval state, session id, and summaries
- `users/{ownerId}/agentTasks/{taskId}/events/{eventId}`
  - structured progress stream
  - ordered by `sequence`
- `users/{ownerId}/agentTasks/{taskId}/approvals/{approvalId}`
  - persisted approval history for apply/commit/PR/merge/deploy/pause-resume checkpoints
- `workspaceLocks/{repoId}`
  - single active task per workspace/repository
- `repositories/{repoId}/executionSessions/{sessionId}`
  - reviewable multi-file diff payload used by the diff screen and task approval flow

## Backend Flow
1. `enqueueAgentTask` validates scope, creates the task record, writes `task_created`, and tries to promote the task if the workspace is idle.
2. `promoteNextQueuedAgentTask` acquires `workspaceLocks/{repoId}` and flips the next queued task to `running`.
3. Firestore trigger `runAgentTask` starts when `runToken` changes.
4. The runner executes a multi-step pass:
   - analyze request
   - inspect repo and load file content
   - rank/select files
   - call the model
   - retry once with a repair prompt if the diff payload is invalid
   - validate guardrails
   - pause for approval before writes
5. After approval, the runner applies edits, validates the working copy, then optionally pauses for commit / PR / merge / deploy checkpoints requested by the prompt.
6. Final states release the workspace lock and automatically promote the next queued task.

## Frontend Flow
- `ForgeWorkspaceController` watches `agentTasks` and the selected task's `events`.
- The Agent tab is the primary AI surface.
- Diff review still works through the editor, but it is now driven by the selected task's persisted execution session.
- Queued tasks survive refresh because the source of truth is Firestore, not local widget state.

## Guardrails
- max runtime per task
- max retries per task
- max token budget per task
- max file touch count per task
- explicit cancellation support
- pause at safe checkpoints
- approval gates before any working-copy write or risky remote action

## Follow-up Actions
When a prompt explicitly asks for remote actions, the runner can continue into approved follow-up steps:
- commit current working copy
- create branch + open pull request
- merge an agent-created pull request
- dispatch the deploy workflow

## Observability
- every task stage writes a structured event
- task docs mirror the latest status, step, and summary for fast UI rendering
- approvals are stored separately for auditability
- workspace locks make queue state debuggable from Firestore
