# Live Execution UI

## Main Experience
The old prompt-and-reply view has been replaced by an Agent tab that behaves like a work session console.

## Screen Areas
- work session header
  - active task title with animated pulse
  - status chip
  - current step
  - elapsed time
  - token estimate
  - diff count
  - files touched
  - retry count
- bottom composer
  - stays visible as a pinned work-session input
  - starts a task immediately when the workspace is idle
  - queues the prompt automatically when another task is active
  - shows queue state and workspace mode
- task controls
  - cancel active task
  - request pause at the next safe checkpoint
  - surface approval checkpoint actions inline and in a modal sheet
- live timeline
  - streamed task events in real time
  - repo clone, repo scan, file reads, model calls, retries, approvals, applies, validation, completion
- files touched
  - shows files read, modified, created, validation-failed, or ready for review
  - supports jumping into the editor
- queued prompts
  - ordered queue preview on the main screen
  - dedicated bottom sheet for the full queue
  - queue position visible
  - queued tasks can be removed
- task details
  - full event history
  - validation summary
  - diff/session metadata
  - rerun entry point
- recent runs
  - completed / failed / cancelled task history for quick inspection

## Approval UX
- apply diff
  - opens the existing diff review flow through the editor when needed
- commit / PR / merge / deploy
  - shown as explicit next-step approvals after the task-local workspace is updated

## Diff Review Integration
- task-generated execution sessions are persisted in Firestore
- the workspace controller loads the selected task's execution session into the existing diff review screen
- approving the diff now resumes the task runner instead of applying the session inline from a transient local object

## Observable State
The UI subscribes to:
- `agentTasks` for status, queue, and summaries
- selected task `events` for live timeline rendering
- selected task execution session for diff review

## Reusable Components
- `active_step_header`
- `task_status_chip`
- `live_event_row`
- `queue_item_card`
- `files_touched_panel`
- `task_summary_card`
- `empty_workspace_state`
- `failure_state_card`
- `success_state_card`
- `approval_action_sheet`

## Product Outcome
The primary AI interaction is now:
- submit prompt
- watch the agent clone, inspect, edit, validate, and retry
- review the timeline
- approve or reject at checkpoints
- queue additional prompts while the current task continues
