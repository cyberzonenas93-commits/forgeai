# Whole-Repo Awareness Audit

This audit is grounded in the current backend/runtime implementation, not in intended behavior.

## Audit Answers

### 1. How much of the repo is actually synced initially?
Initial repository sync still stores a metadata-first snapshot, not eager full file bodies. GitHub tree ingestion is capped and then persisted into `repositories/{repoId}/files`.

Current cap:
- `REPO_SYNC_TREE_LIMIT = 10000` in `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`

Current behavior:
- broader than the earlier shallow sync
- still not unbounded
- still remote-provider dependent

### 2. Is repo sync capped?
Yes.

The current system is materially better than the old shallow cap, but it still caps initial tree sync at `10000` entries.

### 3. What file metadata is stored?
The index and snapshot system now stores or derives:
- path
- language
- file type
- content preview
- summary
- keywords
- imports
- exports
- symbol hints
- role
- architecture hints
- entrypoint signal
- approximate token footprint

Those signals are produced primarily through:
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/file_summary_generator.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/repo_index_service.ts`

### 4. Are full file contents stored or loaded lazily?
Full file bodies are still loaded lazily.

The runtime uses `loadRepositoryFileContent(...)` and `loadRepoExecutionPaths(...)` in `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts` to hydrate exact files when needed.

So the answer is:
- metadata is broad
- exact bodies are progressive

### 5. How are relevant files chosen today?
Relevant files are no longer chosen through a single fixed top-N retrieval step.

The current path is:
1. build repo index entries
2. build repo manifest
3. build repo knowledge map
4. seed broad exploration paths
5. hydrate files
6. run exploration planner passes
7. expand through modules, hints, directory prefixes, dependency graph, reverse dependency graph, and neighborhood traversal
8. run final execution planner
9. hydrate final supporting files
10. choose editable and read-only scope

Primary implementation:
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/repo_context_strategy.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/repo_knowledge_map.ts`

### 6. Is retrieval purely heuristic?
Not purely anymore, but still non-embedding.

The system now combines:
- lexical ranking
- import / export matching
- symbol hints
- role and architecture hints
- module grouping
- dependency graph traversal
- reverse dependency traversal
- planner-guided path expansion
- run-memory carry-forward

That said, it is still not vector-semantic retrieval.

### 7. Are embeddings actually generated and queried?
No.

`embeddingText` is real as preparation, but embeddings are still placeholders rather than active retrieval infrastructure.

### 8. Is there any repo-wide map or memory object?
Yes, now there are both.

Repo-wide map:
- `RepoKnowledgeMap` in `/Users/angelonartey/Desktop/ForgeAI/functions/src/repo_knowledge_map.ts`

Run memory:
- `RepoExecutionRunMemory` in `/Users/angelonartey/Desktop/ForgeAI/functions/src/repo_knowledge_map.ts`

Persisted repo snapshot:
- `repositories/{repoId}/contextMaps/current`

Persisted run/session memory:
- execution session documents
- agent task metadata

### 9. Does the current execution session accumulate knowledge over time?
Yes.

The runtime now records exploration passes, architecture findings, focused modules, hydrated paths, editable scope, and unresolved questions across the run. Repair passes also inherit existing execution memory instead of starting cold.

### 10. Can the agent request more files during a run?
Yes.

The exploration planner can request:
- exact paths
- directory prefixes
- promoted paths
- read-only files
- focus modules

The runtime then expands beyond those requests using graph traversal and module-aware expansion.

### 11. Does deep mode materially change reasoning depth or only file count?
It now materially changes strategy, not just count.

Deep mode affects:
- context strategy selection
- module seed limits
- planner candidate breadth
- editable/read-only budgets
- number of exploration passes
- expansion budget per pass

### 12. Are summaries shallow or structurally useful?
They are now structurally useful.

Summaries now include:
- imports
- exports
- symbol hints
- file role
- architecture hints
- entrypoint inference

This is significantly stronger than plain filename-based summaries.

### 13. Is there any module/import/dependency graph?
Yes.

The runtime now builds:
- import graph
- reverse dependency graph
- module dependency map
- architecture zones
- path-to-module map

### 14. Is there any symbol index?
There is a lightweight symbol-hint index, not a full parser-grade symbol database.

It is enough to improve repo mapping and prompt assembly, but it is not yet a full semantic symbol engine like an LSP-backed code index.

### 15. Can the current system support progressive context expansion?
Yes.

This is now one of the central runtime behaviors. Exploration is iterative and can continue widening context before final edit scope is fixed.

## What Still Remains Bounded

- Initial sync is still capped at `10000` tree entries.
- Literal full-code inline context is still limited to smaller repos.
- Exact file hydration still uses budgets to control cost and latency.
- Embeddings are still not implemented.
- Whole-repo awareness still starts from synced repo metadata plus progressive hydration, even though the agent now executes approved edits inside a task-local cloned workspace.

## Bottom Line
The system still uses budgets, but it is no longer accurately described as a shallow bounded-subset retriever.

The closer description is:
- metadata-first repo map
- layered summaries
- module and architecture awareness
- dependency-guided expansion
- progressive exact-file hydration
- durable run-level memory
- final edit scope chosen after exploration, not before it

That is the current whole-repo-awareness posture of CodeCatalystAI.
