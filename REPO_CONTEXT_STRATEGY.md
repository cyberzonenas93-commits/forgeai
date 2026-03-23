# Repo Context Strategy

## Goal
Make CodeCatalystAI behave like a whole-repo coding agent even when literal all-file injection is not practical.

The strategy is now explicitly layered, size-aware, stateful across a run, and able to widen context during execution instead of stopping at an initial top-N file slice.

The second runtime pass also ties repo context directly into provider routing, so deeper context planning and repair loops can preferentially use stronger long-context reasoning providers when they are configured.

The latest runtime pass also keeps that broader repo context alive through sandbox validation. The agent no longer narrows to a diff and waits for approval before learning whether the draft actually works. It now carries the repo map, module focus, repair hint paths, and execution memory into pre-approval validation and repair passes inside an ephemeral workspace.

The newest hardening pass also removes an extra shallow cap that was still undercutting whole-repo behavior: once the planner selects the editable wave, execution is no longer forced back down to a separate tiny `10/20` file ceiling. The runtime now trusts the planner-selected writable scope and can still widen that wave later when repair passes expose additional ripple paths.

## What Changed

### 1. Repo-Wide Knowledge Map
The backend now builds a durable repo knowledge map in `/Users/angelonartey/Desktop/ForgeAI/functions/src/repo_knowledge_map.ts`.

That map includes:
- repo size class
- context budget and strategy label
- key files and entrypoints
- module summaries
- architecture zones
- architecture-zone overview text
- full module index text
- import and reverse-import graphs
- module dependency relationships
- repo, architecture, and module overviews

The current repo map is also persisted to Firestore at `repositories/{repoId}/contextMaps/current` so the system keeps a materialized repo-level view instead of rebuilding everything as an opaque one-shot prompt step.

### 2. Hierarchical Context Layers
The runtime now reasons through five layers:

1. Whole-repo knowledge map
2. Architecture zones and module summaries
3. File summaries and ranking signals
4. Exact hydrated file contents
5. Final editable and read-only scope

The execution prompt in `/Users/angelonartey/Desktop/ForgeAI/functions/src/repo_execution_format.ts` explicitly tells the model to use layered repository context, module summaries, and run memory.

### 3. Size-Aware Strategy
The repo is classified into one of five size classes in `/Users/angelonartey/Desktop/ForgeAI/functions/src/repo_knowledge_map.ts`.

- `tiny`
  - Strategy: `whole_repo_inline`
  - Behavior: hydrate the full repo because literal broad inline reasoning is practical.
- `small`
  - Strategy: `wide_repo_inline` or `hierarchical_small_repo`
  - Behavior: can still inline broadly when token footprint is modest; otherwise uses layered exploration.
- `medium`
  - Strategy: `hierarchical_progressive`
  - Behavior: module-first exploration with multiple context-expansion passes.
- `large`
  - Strategy: `hierarchical_graph_guided`
  - Behavior: relies more heavily on module grouping, dependency edges, and ripple expansion.
- `huge`
  - Strategy: `hierarchical_memory_heavy`
  - Behavior: keeps a broad repo map and stronger run memory while exact file hydration remains selective.

Deep mode no longer only means “more files.” It now increases:
- module seed breadth
- dependency-neighborhood expansion around focused modules
- planner candidate breadth
- exploration passes
- editable and read-only budgets
- tracked module breadth in run memory
- overall willingness to widen context

### 4. Progressive Context Expansion
For non-inline repos, `hydrateRepoExecutionContext(...)` in `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts` now does this:

1. Build the repo map and global anchors.
2. Seed broad context from key files, focused modules, current file, and high-signal ranked files.
3. Hydrate those paths.
4. Run one or more exploration passes.
5. On each pass, ask the planner for:
   - additional exact paths
   - directory prefixes
   - promoted editable paths
   - read-only paths
   - focus modules
   - architecture findings
   - uncertainties
6. Expand beyond planner hints using:
   - module membership
   - dependency-neighbor module expansion
   - import and reverse-import graph traversal
   - same-neighborhood expansion
   - ranked hint matching
7. Rebuild knowledge state after new file hydration.
8. Run a final execution-planning pass to choose editable scope and supporting context.

This is materially different from “pick five files and hope.”

### 5. Run-Level Memory
Each run now maintains a `RepoExecutionRunMemory` object.

It tracks:
- focused modules
- explored paths
- hydrated paths
- editable paths
- read-only paths
- global context paths
- architecture conclusions
- unresolved questions
- summarized module memory
- per-pass exploration history

The memory is:
- seeded from the repo map
- updated after every exploration pass
- fed into later planner and execution prompts
- stored in execution sessions
- copied into agent task metadata
- reused in repair passes

That means the run accumulates repo understanding instead of starting over from scratch on every model call.

The second pass also widened the retained memory surface significantly:
- many more explored and hydrated paths are preserved
- many more focused modules are retained
- more recent exploration passes are kept
- tracked module summaries are now chosen using focused-module relevance, not only top modules by size
- run-memory summaries now emphasize module coverage and architecture findings instead of dumping a short list of paths

### 6. Dynamic File Hydration
Exact file contents are still loaded lazily, but the system is no longer trapped in a static initial subset.

The runtime can hydrate more files during a run based on:
- planner requests
- focused modules
- dependency-neighbor modules
- import graph edges
- reverse dependencies
- neighborhood expansion
- current editable scope
- new repair requirements

This gives the closest practical equivalent to “inspect any part of the repo during the run” without pretending that every repo can always fit literally into one prompt.

The latest repair-loop pass also feeds validation failure paths directly back into repo exploration. When validation implicates files outside the last editable scope, those paths are now promoted into the next repair expansion pass instead of hoping the original selected bundle was sufficient.

Those same repair hint paths now also feed the pre-approval sandbox loop, so the runtime can widen repo exploration before the approved task-local workspace is touched.

### 7. Live Exposure
The agent runtime now streams exploration progress into task metadata and live events:
- repo size class
- context strategy
- exploration pass counts
- focused modules
- architecture findings
- unresolved questions
- execution-memory summaries

The Agent console can therefore show repo understanding as it deepens, not only after diff generation.

### 8. Context-Aware Provider Routing
The main repo-agent path now routes providers by execution stage in `/Users/angelonartey/Desktop/ForgeAI/functions/src/routing_engine.ts`.

That means:
- context planning can use a deeper reasoning provider than fast normal diff generation
- repair loops can prefer a stronger repair provider instead of reusing the first-pass provider blindly
- repo size class now influences provider choice, not only context breadth

This does not replace the repo-context system, but it does make the strongest repo context more likely to land on the strongest configured model for that stage.

## Current Constraints

### Repo Sync Is Still Bounded
Initial GitHub tree sync is broader than before and now capped at `10000` entries in `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`.

When sync is still truncated, the runtime now injects an explicit sync-coverage notice into repo context so the model does not silently assume it has a perfect remote snapshot.

### Full File Bodies Are Still Lazy
The synced repo store still keeps metadata broadly and hydrates file bodies on demand. That is intentional for scale, but it means whole-repo understanding is achieved behaviorally through map + exploration + memory rather than eagerly caching every file body.

### Embeddings Are Still Not Real
`embeddingText` is still prepared in `/Users/angelonartey/Desktop/ForgeAI/functions/src/file_summary_generator.ts`, but the runtime does not yet generate or query actual vector embeddings. Repo understanding is currently powered by:
- summaries
- imports / exports
- symbol hints
- roles
- architecture hints
- module grouping
- graph traversal
- planner-guided expansion

### Literal Full-Repo Injection Is Still Size-Limited
Small repos can be hydrated broadly. Medium and larger repos still require staged context accumulation because of model-context cost and latency realities.

### Prompt Context Is Still Curated
The runtime now includes repo overview, architecture zones, module overview, module index, focused-module details, and execution memory in planner/execution prompts, but this is still a curated long-context strategy rather than raw full-code injection for every module in large repos.

## Net Result
The system still has budgets, but it no longer behaves like a narrow bounded retriever.

It now behaves as:
- repo-map driven
- module aware
- graph aware
- progressively exploratory
- run-memory backed
- repair-pass aware

That is the strongest practical whole-repo strategy currently implemented in this architecture.
