# Validation Repair Loop

Read `AGENTS.md`, `WORK_MEMORY.md`, and `ARCHITECTURE_GUARDRAILS.md` first.

## Current Loop
The durable agent runtime now uses this validation-and-repair cycle:

1. Generate a repo-aware diff.
2. Validate the generated diff against task guardrails.
3. If the draft is too broad, regenerate a narrower diff before approval.
4. Clone or reuse the task-local base workspace, then create a sandbox copy for this validation attempt.
5. Apply the candidate diff inside that sandbox.
6. Run validation pass `N` against the sandbox:
   - static repo validation
   - the narrowest useful local workspace commands first
   - broader local validation only after those focused checks pass
   - remote CI validation when available
7. If sandbox validation fails, summarize the failure into structured repair context.
8. Persist failure memory for that task, including repeated signature counts, category counts, repair target paths, and the current repair strategy.
9. Generate a repaired diff and rerun sandbox validation.
10. When sandbox validation passes, wait for explicit apply approval.
11. Apply the validated diff to the task-local cloned workspace.
12. Confirm post-apply local-workspace consistency and continue to follow-up approvals or completion.

The runtime now also records the validation suite as an explicit tool execution and carries that record forward in task metadata, so repair work is visible as repeated tool-driven activity instead of hidden backend retries.

The current scale-up pass adds more active behavior around that loop:
- validation and repair now run inside a claimed distributed worker with a live lease and heartbeat
- the runtime records logical handoffs between validator and repair roles
- task metadata now accumulates a cost ledger so repeated retries can be budget-aware instead of blind

The second hardening pass also closes two weak spots:

- structured diff generation no longer stops after only two malformed model outputs; it now retries across a wider provider fallback chain
- validation failure paths are now fed back into repo exploration so repair passes can widen beyond the prior editable scope when the failure indicates missing adjacent context

The newest pass closes another pair of weak spots:

- repair and guardrail regeneration are no longer forced to stay on the last execution provider after the first failure, so the router can escalate to a stronger repair provider when available
- the generated diff is no longer cut back to a tiny extra file ceiling once the planner has already chosen a broader editable wave

The current behavioral hardening pass adds another layer:

- repeated validation failures are now fingerprinted by class, file paths, and exact failure locations
- repeated signatures escalate the repair strategy from `targeted_patch` to `widened_context` to `escalated_reasoning`
- repair prompts now include recent repair memory, not only recent validation output
- local validation reruns are now reordered by the last failure class so the runtime tests the smallest useful hypothesis first
- repair quality metrics now persist repeated-failure counts, bottleneck categories, passes-to-success, and estimated repair cost

## Failure Context Fed Into Repair
Repair passes no longer receive only a vague workflow summary.

The repair prompt now includes:

- failing tool names
- file/line-aware findings when available
- failed job/step summaries when annotations are missing
- workflow and branch context through stored validation metadata
- recent validation history across attempts
- recent repair memory across attempts
- guardrail failure context when the original draft had to be narrowed before approval

When the runtime stops because retries are exhausted, it now persists explicit hard-limit metadata so the UI can say, in plain terms, that the agent kept trying until it hit the configured limit.

## Failure Memory And Strategy Escalation
Every failed validation pass now records:

- failure signature
- failure category
- exact failure locations
- implicated file paths
- chosen repair target paths
- repair strategy label
- repair escalation level

The current escalation ladder is:

1. `targeted_patch`
2. `widened_context`
3. `escalated_reasoning`

Repeated failures do not reuse the same repair strategy blindly. The runtime widens the editable/read-only scope and can let provider routing promote a stronger repair path when the same signature or failure family keeps recurring.

## Narrow-First Validation
Validation now reruns in a failure-aware order.

Examples:

- import, syntax, typecheck, or lint failures prefer analyze/lint/build before test reruns
- build or CI failures prefer build-first reruns
- repeated test failures prefer test-first reruns

This keeps the loop cheaper and faster without weakening the broader validation suite, because the run still escalates to the rest of the available checks after the focused step passes.

That context comes from structured tool results built in:

- `/Users/angelonartey/Desktop/ForgeAI/functions/src/agent_validation_tools.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`

## Retry Limits
The runtime now differentiates retry budgets:

- normal mode: `3` repair retries
- deep mode: `5` repair retries

These limits are enforced through task guardrails in `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`.

## Validation Sources

### Always Available
- static repo validation over the sandbox draft
- post-apply local-workspace consistency checks

### Available When The Runtime Environment Supports It
- best-effort local workspace commands inside the ephemeral sandbox
- currently detected from the repo snapshot and available binaries
- current allowlist includes Flutter, Dart, npm, TypeScript, and eslint validation commands when those tools and repo artifacts are present

### Available When GitHub Validation Exists
- ephemeral validation branch creation
- commit of the current sandbox or task-local workspace to that branch
- GitHub Actions dispatch
- polling of workflow completion
- collection of failed jobs, steps, and annotations

### Available Through Manual Checks
- workflow dispatch from the Checks dashboard
- background monitoring to completion
- structured findings persisted back into `checksRuns`
- the same surfaced workflow results visible to the user outside the agent task view

## User-Visible Runtime States
The live agent experience now shows:

- `validation_started`
- `tool_started`
- `tool_passed`
- `tool_failed`
- `tool_skipped`
- `retrying`
- `validation_passed`
- `validation_failed`

The run UI also now shows:

- repair pass count versus max retries
- recent validation pass history
- explicit hard-limit state when retries are exhausted
- validated-before-apply state when the sandbox loop succeeds

This makes the run look like active work instead of a single prompt/reply exchange.

The current pass also surfaces:
- routed provider and model
- recent tool executions
- explicit tool catalog for the current task
- repair strategy labels
- repeated failure counts and bottleneck metrics through task metadata

## Stop Conditions
The loop stops when one of these happens:

- all validations pass
- repair retries are exhausted
- the task is cancelled or paused
- the runtime exceeds its max runtime guardrail

## Known Limits
- No arbitrary local shell/test/build execution yet.
- Local execution is allowlisted and bounded, not an open terminal session.
- Remote CI remains a proxy for true local execution.
- Validation branch lifecycle is currently append-only.
- Skipped remote validation is visible in results, but still relies on local/static validation as the hard floor.
- Manual checks are now monitored, but they still do not automatically trigger a repair pass unless they are part of an active agent task.
- The repair loop is still bounded by allowlisted commands, not an arbitrary terminal substrate.
- Failure memory is task-scoped and resets between tasks.
- Narrow-first validation is policy-driven, not yet learned from historical repo-level outcomes.
