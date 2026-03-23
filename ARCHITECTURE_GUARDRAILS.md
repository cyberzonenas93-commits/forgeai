# Architecture Guardrails

## Purpose
This file exists to stop future AI runs from weakening CodeCatalystAI back into a chat assistant, a shallow retrieval wrapper, or a draft-only execution system.

If a proposed change conflicts with these guardrails, update the guardrails in the same pass with a deliberate architectural reason or do not make the change.

## What Must Remain True
- The main product experience is live agent work, not chatbot reply.
- The main user-facing AI path is durable task execution, not direct one-shot prompt execution.
- Same-repo tasks remain serialized behind a repo lock.
- Different repos may run in parallel through distributed worker runs.
- Sandbox validation and repair happen before apply approval.
- The main execution workspace remains task-local and git-native.
- Repo understanding remains layered, progressive, and stateful.
- Approval checkpoints remain first-class for apply and git follow-up actions.
- The user should be able to see the agent working through queueing, progress, validation, retries, and approvals.

## Strongest Path That Must Stay Default
The strongest path is:

`prompt -> durable queued task -> distributed worker run -> layered repo context -> structured multi-file diff -> sandbox validation/repair -> approval -> apply to task-local workspace -> post-apply validation -> commit/PR/merge/deploy follow-up`

Any new path that is weaker than this must not become the default.

## Regressions That Must Not Happen
Do not let these become the main path again:
- chat-first prompt/reply UX
- suggestion-only AI output
- one-shot direct execution without durable task state
- single-file-only review as the default AI path
- Firestore-draft-only execution as the main workspace model
- bypassing sandbox validation before apply approval
- bypassing repo locks or queue semantics
- hiding retries or validation behind passive UI
- collapsing repo context back to shallow fixed tiny file bundles

## Compatibility Paths That Must Stay Secondary
These are compatibility surfaces, not product truth:
- `askRepo`
- `suggestChange`
- `applyRepoExecution`
- `apply_file_edits`
- any resurrected `AskScreen`-style mounted flow

If they are touched, keep the work clearly compatibility-scoped and do not let app wiring drift back toward them.

## Changes That Require Extra Caution
- repo context strategy changes
- execution-memory changes
- worker dispatch or lease changes
- workspace model changes
- validation or repair-loop changes
- provider routing or cost-routing changes
- git follow-up path changes
- Firestore schema changes affecting tasks, approvals, events, execution sessions, checks, or worker runs
- UI changes that could make the app feel passive, chat-like, or suggestion-first

## Required Docs To Update After Core Changes
When core architecture changes, update the relevant docs in the same pass:
- `CHANGELOG.md`
- `AGENTS.md`
- `WORK_MEMORY.md`
- `ARCHITECTURE_GUARDRAILS.md`
- `README.md`
- `ARCHITECTURE.md`
- `AGENT_RUNTIME_ARCHITECTURE.md`
- `CLAUDE_CODE_PARITY_AUDIT.md`
- `REPO_CONTEXT_STRATEGY.md`
- `TOOL_EXECUTION_ARCHITECTURE.md`
- `VALIDATION_REPAIR_LOOP.md`
- `DISTRIBUTED_AGENT_ARCHITECTURE.md`
- `WORKER_SYSTEM.md`
- `COST_OPTIMIZATION.md`
- `MULTI_AGENT_SYSTEM.md`

## Verification Expectations
For runtime or architecture changes, the default verification floor is:
- `npm --prefix /Users/angelonartey/Desktop/ForgeAI/functions run lint`
- `npm --prefix /Users/angelonartey/Desktop/ForgeAI/functions run build`
- `dart analyze /Users/angelonartey/Desktop/ForgeAI/lib/src test`
- `flutter test`

## Decision Rule
Before merging an architectural change, ask:

1. Is the strongest path still unmistakably the default?
2. Could a future AI run misread the repo and accidentally revive a weaker path?
3. Did the docs get updated so the new truth is obvious?

If any answer is no, the change is not finished.
