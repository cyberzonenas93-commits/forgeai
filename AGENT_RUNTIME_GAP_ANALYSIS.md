# Agent Runtime Gap Analysis

## Implemented Runtime
The durable runtime now behaves like this:

1. Queue task in `users/{ownerId}/agentTasks/{taskId}`.
2. Plan the run and persist ordered steps plus follow-up intent.
3. Acquire the per-repo workspace lock.
4. Build a repo knowledge map, inspect the repo, and expand context across multiple passes.
5. Generate a structured multi-file diff.
6. Materialize the candidate draft in an ephemeral sandbox workspace.
7. Run a structured validation suite before approval:
   - static repo validation
   - local workspace commands when available
   - remote CI validation on an ephemeral validation branch when available
8. If validation fails and retries remain, generate another repo-aware repair diff and validate again.
9. Pause for explicit apply approval only after the candidate draft passes that sandbox loop.
10. Apply the approved diff to the task-local cloned workspace and confirm post-apply consistency.
11. Emit per-tool lifecycle events and persist structured validation history onto the task.
12. After successful validation, stage commit / PR / merge / deploy follow-up approvals.
13. Complete the task and release the workspace lock.

## What Closed In This Pass
- The runtime now has an explicit provider-routing layer and no longer hardcodes OpenAI for repo planning and diff generation.
- The runtime now has an explicit tool registry and structured tool-execution records for apply, validation, commit, pull request, merge, and deploy steps.
- The runtime now has durable run-level execution memory, not just transient selected-file metadata.
- Repo exploration is now size-aware and module-aware, with dependency-graph-guided expansion instead of a shallow bounded file bundle.
- Exploration passes now stream visible metadata into the live task record and timeline, including repo size class, context strategy, focused modules, and architecture findings.
- `retryCount` and `maxRetries` now matter at the task level.
- Validation failure is no longer always terminal.
- The runtime now has a closed repair loop using structured repo failure context.
- The runtime now persists repeated failure memory per task, fingerprints failure signatures, and escalates repair strategy instead of blindly replaying the same patch shape.
- Validation reruns are now narrow-first and failure-aware, so repeated test failures do not always pay for the whole validation suite before the most likely failing check reruns.
- The runtime now validates and repairs the candidate draft before apply approval instead of asking approval before real validation begins.
- Validation now runs against the actual edited draft when GitHub validation is available by pushing the sandboxed local workspace onto a fresh validation branch before dispatching CI.
- The runtime now includes a static repo validator that can catch JSON issues, merge markers, and local import breakage before remote CI runs.
- Tool execution is now explicit in the live event stream through `tool_started`, `tool_passed`, `tool_failed`, and `tool_skipped`.
- Agent tasks now persist structured validation history, latest tool results, validation branch names, and validation attempt counts in task metadata.
- Agent tasks now also persist repair quality metrics such as repeated failure events, bottleneck categories, passes to success, and estimated repair cost.
- Prompt/Ask no longer needs to bypass the durable queue.
- Follow-up continuity is no longer only a keyword guess; the runtime now persists an explicit run plan before it starts editing.
- The mounted app no longer exposes the legacy Ask screen or single-file diff-review path.
- Runtime repo-inspection metadata now lands on the task record during execution, so the UI can show selected files, inspected breadth, and context strategy before diff approval.
- The main Agent console no longer forces focus back to the active task when the user selects a queued one, which keeps queued work visible and understandable.

## Remaining Runtime Gaps

### Missing General Shell Loop
The runtime now has a real cloned checkout per task plus allowlisted local commands, but it still cannot:
- run arbitrary shell commands in that checkout
- execute any project script on demand
- inspect a fully open-ended terminal session
- patch again from unrestricted local command output

That is the main remaining gap to Claude Code / Codex / Cursor parity.

### Failure Learning Is Still Task-Local
The repair loop now learns within a task, but it does not yet carry failure-pattern learning across tasks or repositories. That keeps runs deterministic and bounded, but it also means strategy improvements are not yet accumulated into repo-level historical heuristics.

### Routing Is Better, But Still Heuristic
The main repo-agent path now routes between OpenAI, Anthropic, and Gemini, but the routing engine is still heuristic rather than benchmark-adaptive or user-configurable in the mounted app.

### Remote Validation Is Still A Proxy
The new validation-branch strategy means CI now runs against the actual edited draft, which is a major upgrade. It is still a remote proxy for a true local dev loop, though, not a real shell/build sandbox on a checked-out workspace.

### Planning Is Still Linear
The runtime now persists an explicit run plan plus exploration memory, but the user-visible plan is still a linear ordered step list plus follow-up booleans. It is not yet a full mutable goal graph that can branch, reprioritize, or spawn parallel child plans inside the backend.

### Execution Model Is Still Split
The main agent path now clones and edits a local workspace, then commits and pushes from that checkout. Firestore still remains the durable system of record for repo metadata, task state, approvals, execution sessions, and some legacy compatibility draft flows. That is much closer to parity, but it is not yet a fully local-first architecture across every product surface.

### Sync Breadth Is Still Finite
Whole-repo awareness is materially stronger, but initial tree sync still has a hard cap and exact file hydration remains budgeted for scale.

### Cancellation Granularity
The runtime is more durable than before, but long-running remote operations still do not have the same fine-grained interruption model as a local agent loop.

### Validation Coverage Is Still Partial
The runtime now has meaningful validation and repair behavior, but it still does not run:
- arbitrary repo-native formatters
- every framework analyzer locally
- arbitrary project scripts
- arbitrary toolchains outside the allowlist or GitHub Actions
- repo-specific validation ordering learned from historical success/failure data

### Validation Branch Cleanup
The runtime currently creates fresh validation branches for each validation attempt and does not automatically prune them afterward.

## Recommended Next Milestones
- Broaden the allowlisted shell/test/build tool surface with strict safety boundaries.
- Unify remaining legacy editor and draft flows around the local-workspace model or clearly deprecate them.
- Upgrade the linear plan metadata into a mutable task graph with richer continuation semantics.
- Allow additional writable-file promotion between repair passes when new evidence demands it.
- Add validation-branch cleanup and richer workflow-log ingestion.
- Decide whether task-local failure memory should feed opt-in repo-level repair heuristics without becoming an opaque black box.
