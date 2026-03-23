# Tool Execution Architecture

Read `AGENTS.md`, `WORK_MEMORY.md`, and `ARCHITECTURE_GUARDRAILS.md` first.

## Goal
CodeCatalystAI now validates agent-generated edits through a real tool suite instead of stopping at a one-pass diff. The tool layer is still bounded by the app architecture, but it now behaves like:

1. Clone an isolated task-local workspace from the remote repository.
2. Create a sandbox copy from that cloned workspace for candidate validation.
3. Apply the candidate diff into that sandbox before approval.
4. Run static and local workspace validation against the sandbox.
5. If GitHub validation is available, push the candidate draft from the sandbox to an ephemeral validation branch.
6. Dispatch selected CI workflows against that validation branch.
7. Poll completion, collect structured failures, and feed them back into a repair pass.
8. Repeat until success or retry exhaustion.
9. Ask the user to approve the already-validated diff.
10. Apply the approved diff to the task-local cloned workspace and confirm consistency there before follow-up git actions.

The current pass also formalizes the tool architecture itself instead of leaving it implicit inside the runtime.

The latest hardening pass also makes the tool loop feel less passive:
- apply / commit / pull request / merge / deploy now emit explicit tool lifecycle records
- tool execution history is persisted into task metadata and shown in the task details UI
- the mounted editor handoff now describes the run as live repo work instead of a suggestion reply

The newest second pass pushes that further:
- repo map
- context expansion
- diff generation

are now also persisted as first-class tool executions, so the user can watch the runtime inspect, widen, and generate instead of only seeing validation and Git-side work after the fact.

The distributed-runtime pass adds two more important truths:
- the tool loop now runs inside a claimed distributed worker run instead of a monolithic trigger pass
- task metadata now also records cost-ledger and logical-role context around tool execution, so retries can be reasoned about as active worker stages instead of passive backend work

## Second-Pass Upgrades
The repair loop was hardened again in this pass:

- pre-approval guardrail failures now trigger a narrower regeneration pass instead of always failing the task immediately
- repair prompts now include recent validation history, not only the latest failure summary
- manual checks are no longer dispatch-only and are now monitored to completion in the backend
- the Checks dashboard now reflects both manual checks and agent-driven validation runs with structured findings
- hard-limit failures now persist explicit retry-limit metadata so the UI can show that the agent kept trying until it reached its configured stop condition

## Implemented Tool Types

### Runtime Tool Registry
Implemented in:
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/tool_registry.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/tool_executor.ts`

The agent runtime now exposes an explicit catalog for:
- clone repo workspace
- repo map
- context expansion
- structured diff generation
- apply local workspace
- validation suite
- commit local workspace
- open pull request
- merge pull request
- trigger deploy

These tool definitions are persisted into task metadata so the user can see the intended runtime surface before the task finishes.

### Workspace Consistency
Implemented in `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`.

- Re-reads the approved execution session.
- Confirms each edited file in the task-local cloned workspace still matches the expected `afterContent`.
- Produces structured findings for mismatched or unexpectedly undeleted paths.
- This now acts as a post-approval confirmation step when the diff already passed sandbox validation earlier in the run.

### Ephemeral Workspace Validation
Implemented in `/Users/angelonartey/Desktop/ForgeAI/functions/src/ephemeral_workspace.ts` and `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`.

- Clones a per-task base workspace from the remote repository under the runtime temp directory.
- Creates sandbox copies from that base workspace before the approved task-local workspace is touched.
- Runs best-effort local validation commands when the runtime environment and repo snapshot make them possible.
- Detects and runs additional Node or TS validation commands when available, including `npm run build`, `npx tsc --noEmit`, and `npx eslint . --max-warnings 0`.
- Persists sandbox workspace metadata back onto the task so the validation/repair flow is visible and durable.

### Static Repo Validation
Implemented in `/Users/angelonartey/Desktop/ForgeAI/functions/src/agent_validation_tools.ts`.

- Runs directly against the sandboxed local draft assembled from the cloned workspace.
- Detects unresolved merge-conflict markers.
- Validates changed JSON files with `JSON.parse`.
- Resolves local JS/TS relative imports.
- Resolves local Dart relative imports and same-package `package:` imports when `pubspec.yaml` identifies the package name.
- Produces structured findings with file path, line, message, code, and severity.

### Remote CI Validation
Implemented in `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`.

- Available when the repo is GitHub-backed and a provider token exists.
- Selects a validation workflow plan through `/Users/angelonartey/Desktop/ForgeAI/functions/src/agent_validation_tools.ts`.
- Creates a fresh validation branch such as `forgeai/validation-<task>-<attempt>-<suffix>`.
- Commits the current sandbox or task-local workspace diff to that branch with real git commands.
- Dispatches selected GitHub Actions workflows against that validation branch.
- Polls workflow completion and collects:
  - workflow conclusion
  - failed jobs
  - failed steps
  - check-run annotations when GitHub exposes them

### Monitored Manual Checks
Implemented through `submitCheckAction` plus `monitorCheckRun` in `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`.

- writes manual checks with `source: manual_check`
- monitors them asynchronously through a Firestore trigger
- polls workflow completion
- persists structured findings, failing files, provider notes, and final execution state

## Structured Tool Results
Every validation step now yields a structured tool result with:

- `id`
- `kind`
- `name`
- `status`
- `summary`
- `durationMs`
- `findings[]`
- optional `workflowName`
- optional `workflowPath`
- optional `workflowCategory`
- optional `checkRunId`
- optional `logsUrl`
- optional `branchName`
- `executed`

These results are persisted into agent task metadata as:

- `metadata.validationAttemptCount`
- `metadata.validationPassed`
- `metadata.validationSummary`
- `metadata.latestValidationBranch`
- `metadata.latestValidationToolResults`
- `metadata.validationHistory`

The broader runtime now also persists structured tool-execution history for:
- clone repo workspace
- local-workspace apply
- validation suite
- commit follow-up
- pull-request follow-up
- merge follow-up
- deploy follow-up

Those records live under:
- `metadata.toolRegistry`
- `metadata.toolRegistrySummary`
- `metadata.toolExecutions`
- `metadata.lastToolExecution`

## Runtime Orchestration
The main orchestrators are `validateGeneratedSessionBeforeApproval(...)` and `validateAndRepairAgentTask(...)` in `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`.

It now:

1. Emits sandbox validation events before approval.
2. Runs `runAgentValidationToolSuite(...)` against a candidate sandbox workspace.
3. Emits `tool_started` and `tool_passed` / `tool_failed` / `tool_skipped` for each tool.
4. On failure, stores structured results in task metadata.
5. Builds a repair prompt from summarized tool findings.
6. Generates a repaired diff and validates that new candidate draft again.
7. Only after sandbox validation passes does it ask for approval.
8. After approval, writes the validated diff into the task-local cloned workspace and confirms consistency before follow-up actions.

Before user approval, the runtime also checks the generated diff against task guardrails. If the first draft is too broad, the agent now regenerates a narrower diff instead of stopping after a single oversized patch.

## Workflow Planning
Validation workflow planning is no longer a single best-guess workflow name.

`buildValidationWorkflowPlan(...)` now:

- classifies workflows by `test`, `lint`, `build`, `ci`, or `other`
- excludes deploy/release-like workflows from validation
- scores workflows against prompt hints
- selects a small but intentional validation plan
- uses a broader plan in deep mode than in normal mode

## Live Visibility
The agent UI now reflects this runtime:

- tool start
- tool pass
- tool fail
- tool skip
- validation pass
- validation fail
- repair retry

The validation panel shows the latest structured tool results, findings, branch, and logs URL where available.

The task header, queue cards, task summary card, repo-understanding panel, and task-details screen now also surface:
- routed provider
- provider/model reasoning metadata
- tool count
- tool registry summary
- recent tool executions

The checks dashboard now also shows:

- manual versus agent-driven source
- workflow category and ref
- structured findings
- provider failure notes
- logs URL
- agent task linkage when the run came from the validation loop

The agent runtime surfaces retry-limit state into the live task UI as:

- current repair pass count versus configured max retries
- recent validation pass history
- explicit “hard limit hit” status when the loop stops

## Practical Limits
This is the strongest practical tool loop in the current architecture, but it is not yet full Claude Code / Codex parity.

Still missing:

- arbitrary local shell execution
- a fully general terminal-style stdout loop from the cloned workspace
- automatic cleanup of ephemeral validation branches
- non-GitHub remote CI parity
