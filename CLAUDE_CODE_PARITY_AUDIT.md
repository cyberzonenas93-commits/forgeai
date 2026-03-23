# Claude Code Parity Audit

## Summary
CodeCatalystAI is now materially closer to a repo-native coding agent than it was before this pass. It has a durable task queue, per-repo locking, streamed live events, a layered repo knowledge map, explicit run planning, multi-file structured edits, approval-resume continuation, task-local cloned-workspace apply, real git commit/PR follow-ups, and an automatic validation/repair loop that can dispatch GitHub Actions and retry with a new diff.

This pass also closes a backend architecture gap that was still weakening parity: the main repo-agent path now has explicit provider routing plus a real tool catalog/execution layer instead of hardcoding OpenAI and burying all execution semantics inside one monolithic runtime file.

The second hardening pass goes further on agent feel: repair passes now promote failing files back into repo exploration, structured execution payloads retry across multiple providers instead of stopping after two malformed attempts, and the mounted prompt/editor handoff now describes the run as live work instead of a reply-style suggestion.

This user-perspective pass also closed an important product gap: queued runs and repo understanding now stay visible in the main Agent console instead of being hidden behind the currently active task or delayed until the diff is already generated.

The latest runtime pass closes another major parity gap: approval is no longer the point where validation and repair first begin. The agent now clones a task-local repo workspace, materializes sandbox copies from that clone, applies the generated diff there, runs the validation suite, repairs failed drafts, and only then asks the user to approve the already-validated result for the task-local workspace.

The newest second pass removes another shallow-agent behavior: once repo planning has selected a broad editable wave, the execution model is no longer artificially forced back down to a tiny `10/20` file ceiling. The runtime can now use the full editable-wave budget chosen by the repo planner, and repair routing can escalate away from the previous provider after failures instead of staying pinned to it.

The current scale-up pass closes another production gap: task execution is no longer a single inline trigger pass. The runtime now dispatches distributed worker runs with leases and heartbeats, records logical planner/context/editor/validator/repair/git handoffs, and tracks a task-level cost ledger that influences routing profiles.

It is still not full Claude Code / Codex / Cursor parity because it does not expose arbitrary shell commands, repo understanding is still seeded from synced metadata before execution moves into the cloned workspace, and Firestore still remains the durable coordination layer around the main agent path.

## What Was Verified
- Repo sync previously capped discovery to the first `200` tree entries. This pass raises the sync ceiling to `4000` entries and batches Firestore writes.
- Repo execution now builds a repo manifest, determines when whole-repo inline context is feasible, plans broader context, expands exploration beyond a shallow first slice, and then runs a second planning pass for editable vs read-only files.
- Repo execution now also builds a persistent repo knowledge map with module summaries, architecture zones, import/reverse-import graph edges, size-aware context budgets, and run-level memory that carries exploration results into later planning and repair calls.
- Repo execution planning and diff generation are no longer OpenAI-only by construction. The main runtime now routes across `openai`, `anthropic`, and `gemini` depending on stage, deep mode, repo size, and repair needs.
- Repair passes now widen context around explicit validation failure paths instead of only reusing the prior selected scope.
- The agent queue, workspace lock, event stream, approvals, and continuation flow are real and durable.
- Prompt/Ask submissions now use the same durable agent queue path instead of bypassing it with a one-shot direct execution call.
- The runtime now writes an explicit run plan before repo inspection starts and persists ordered steps plus follow-up intent into task metadata.
- The runtime now writes repo-inspection state back onto the task while the run is still in progress, including repo file count, selected files, inspected paths, dependency context, global context anchors, and whole-repo-inline versus expanded-context strategy.
- Before apply approval, the agent now validates a sandboxed workspace, optionally dispatches GitHub validation workflows against the candidate draft, ingests structured failures, and repairs the draft until success or retry exhaustion.
- After apply approval, the runtime now applies the validated session to the task-local cloned workspace, treats validation as a final local consistency checkpoint, and commits or pushes from that same workspace.
- The runtime now has an explicit tool registry plus structured tool-execution records for apply, validation, commit, pull request, merge, and deploy steps.
- The runtime now dispatches `agentWorkerRuns`, claims workers through a separate worker trigger, and recovers stale workers by bumping the task `runToken`.
- The runtime now records logical multi-agent orchestration and per-stage cost ledgers in task metadata.
- Repo mapping, context expansion, and diff generation are now also persisted as explicit tool executions, so the live session reads more like active runtime work and less like hidden backend orchestration.
- The main agent path now clones a real local repo workspace per task and uses real git commands for commit / push / pull-request follow-ups.
- Flutter session parsing now exposes `inspectedFiles`, `globalContextFiles`, `repoOverview`, `wholeRepoEligible`, and `planningSummary`.
- The dead Ask UI and the mounted single-file change-request review path were removed from the app, so the visible AI flow is agent-first end to end.
- Legacy backend callables (`askRepo`, `suggestChange`) remain only as deprecated compatibility endpoints and are no longer used by the mounted app.

## Current Capability Map

### Repo Understanding
- Stronger than bounded top-file retrieval.
- Uses repo-wide metadata, summaries, architecture zones, module summaries, dependency graph signals, ranked candidates, context-expansion planning, execution memory, and final execution planning.
- Can inline near-whole repos when they are small enough.
- Still does not inject arbitrary large repos in one literal full-code context window.

### File Modification
- Multi-file create/update/delete is supported.
- Edits are generated as structured rewrites and applied to a task-local cloned workspace.
- The runtime can produce a repair diff after validation failures and apply it automatically.

### Commit / Push / PR
- The agent can continue into commit, branch + PR, merge, and deploy follow-ups after approval.
- Commit and push now run through real git commands from the task-local cloned workspace.
- These remote steps are integrated into the same durable task record and event timeline.

### Live Agent Experience
- Tasks are queued behind active work per repository.
- A workspace lock prevents concurrent mutation of the same repo.
- Timeline events and approvals are persisted and streamed live to the client.
- The task UI now exposes planned steps, inspected breadth, repo-context summaries, context strategy, exploration passes, queue position, and follow-up intent instead of only showing raw diff state.
- The main Agent view now lets users keep a queued run selected and visible while another run is actively working, which makes queueing feel durable instead of hidden.

### Validation / Repair
- Sandbox validation now exists before approval.
- Local workspace consistency validation still exists after approval.
- GitHub workflow dispatch and polling now provide a practical remote validation signal.
- Failed validation can trigger automatic repair passes inside the same task.
- The runtime now records explicit tool executions instead of treating apply/validation/follow-up steps as anonymous side effects.
- Structured diff generation now retries more aggressively and can widen provider fallback when the model returns malformed edit payloads.

## Biggest Remaining Gaps To Parity
- No local shell / terminal execution substrate.
- No arbitrary shell / terminal execution substrate inside that local checkout.
- Distributed worker execution is still Firebase-triggered rather than a dedicated Cloud Run worker fleet.
- Validation polling is GitHub-oriented; there is no comparable generalized tool loop.
- Follow-up intent is now explicitly planned, but the plan is still a linear set of booleans + ordered steps rather than a fully mutable task graph.
- Embeddings and true semantic vector retrieval are still not implemented.
- Repo understanding still begins from synced repo metadata and progressive hydration before execution switches to the cloned workspace.
- Writable scope is still constrained per generated execution pass, but that cap is now aligned to the planner-selected editable-wave budget instead of an extra tiny hard stop layered on top.
- Multi-provider routing exists now, but routing is still heuristic and the mounted app does not yet expose a user-facing provider override.

## Net Result
The system now behaves much more like a live repo agent and much less like a suggestion bot. It is closest to “durable repo agent with task-local cloned workspaces, explicit planning, and repair loops” rather than “full local autonomous coding environment.”
