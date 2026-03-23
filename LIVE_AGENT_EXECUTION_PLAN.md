# Live Agent Execution Plan

## Current Implemented Flow

### Submission
- Agent and Prompt surfaces both submit durable agent tasks.
- If a workspace is busy, later prompts queue automatically behind the active run.
- The dead Ask screen has been removed, so the mounted product has a single AI submission surface.

### Live Runtime
- The backend promotes the next queued task once the workspace lock is free.
- The backend writes an explicit run plan before repo inspection begins.
- The backend builds a repo knowledge map, classifies repo size, and chooses a context strategy before editing.
- Repo-inspection progress writes back onto the task while the run is still live, so the client can show mapped-file counts, focused modules, inspected breadth, exploration-pass progress, architecture findings, and context strategy before diff review.
- The UI streams live task events and renders them as a visible work session timeline.
- The selected task keeps its execution session and approval state in Firestore, so refreshes and resumes are durable.

### Review / Apply
- The agent pauses before mutating the approved task-local workspace.
- The user reviews the already-validated repo execution diff and approves or rejects.
- Approval resumes the same task; rejection cancels or completes the run depending on the checkpoint type.

### Validation / Repair
- Before apply, the agent validates sandbox copies of the task-local workspace.
- If GitHub validation workflows exist, the agent dispatches and monitors one against the sandbox draft branch.
- Validation failures can trigger repair passes that produce and validate a new diff in the same task.
- After apply, the agent confirms the approved task-local workspace still matches the validated diff before moving into follow-up actions.

### Follow-Up Actions
- Commit
- Open PR
- Merge PR
- Deploy workflow

These remain approval-gated and continue from the same task record.

## Product Outcome
The primary AI experience is now:

1. Submit task
2. Watch the agent plan, inspect, and expand repo context
3. Review the validated diff
4. Approve apply to the task-local workspace
5. Let the agent continue through commit / PR / merge / deploy checkpoints
6. Queue more prompts while the current repo run stays active

The main console now also keeps user-selected queued runs visible while another run is active, so queueing feels like part of one continuous live session instead of a hidden backlog.

## Still Needed For Even Closer Parity
- arbitrary shell execution beyond the current allowlisted workspace commands
- richer interruption points during long remote operations
- a mutable task graph instead of linear step metadata
- broader provider support for repo execution
