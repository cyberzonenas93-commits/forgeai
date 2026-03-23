# Execution Memory Plan

## Goal
Make each coding run accumulate repository understanding instead of re-deriving it from scratch on every model call.

## Memory Model
Run-level memory is implemented as `RepoExecutionRunMemory` in `/Users/angelonartey/Desktop/ForgeAI/functions/src/repo_knowledge_map.ts`.

It stores:
- `sizeClass`
- `contextStrategy`
- `repoOverview`
- `architectureOverview`
- `moduleOverview`
- `focusedModules`
- `exploredPaths`
- `hydratedPaths`
- `editablePaths`
- `readOnlyPaths`
- `globalContextPaths`
- `architectureConclusions`
- `unresolvedQuestions`
- `moduleSummaries`
- `passes`

Each pass is stored as `RepoExecutionMemoryPass`, which captures:
- pass number
- requested paths
- hydrated paths
- promoted editable paths
- read-only paths
- focus modules
- conclusions
- uncertainties
- rationale
- done flag

## Lifecycle

### 1. Seed
The runtime seeds memory from the repo knowledge map inside `hydrateRepoExecutionContext(...)` in `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`.

The seed includes:
- repo overviews
- initial focused modules
- initial exploration set
- first editable guesses
- global context files

If a task already has prior run memory, the new seed is merged with that state instead of replacing it.

### 2. Exploration Passes
Each context-expansion pass records:
- what the planner requested
- what the runtime actually loaded
- what architecture the run now believes
- what remains uncertain

This is handled through `recordRepoExecutionMemoryPass(...)`.

### 3. Final Planning Pass
After broad exploration, the runtime records a final pass that captures:
- chosen editable files
- read-only support files
- architecture notes
- unresolved questions that remain relevant

### 4. Persistence
Execution memory is persisted in multiple places:

- execution session documents
- agent task metadata
- repair-pass inputs

This allows the same task to:
- pause and resume
- survive approvals
- perform repair passes with prior knowledge intact

### 5. Repair Reuse
Repair passes call `generateRepoExecutionSession(...)` with existing run memory so the runtime keeps the repo understanding it already built during the initial run.

That means repair work is not blind “retry from zero” behavior.

## Prompt Integration
Execution memory now feeds into:
- repo context planner prompts
- execution planning prompts
- final structured diff generation prompts

The prompt layer therefore receives:
- repo overview
- architecture overview
- module overview
- run memory summary

This gives the model continuity across the run.

## UI Exposure
The live agent system now surfaces execution-memory signals through:
- task metadata
- execution sessions
- repo-awareness panel
- exploration-pass timeline events

Users can therefore see:
- current repo strategy
- repo size class
- explored breadth
- focused modules
- architecture findings
- growing run understanding

## Current Limits

### Per-Run, Not Cross-Run
Execution memory is durable for a task and its repair passes, but it is not yet a general long-term cross-task memory system.

### Memory Still Uses Budgets
The runtime remembers exploration, but exact-file hydration remains budgeted for scale and latency.

### No Parser-Grade Semantic Memory
The memory is structurally useful, but it is not yet backed by a full AST or LSP-grade symbol engine.

## Practical Outcome
The agent now behaves more like a long-context coding run:
- inspect broadly
- remember what it learned
- widen context when uncertain
- finalize edit scope later
- carry knowledge into repair passes

That is the current execution-memory design.
