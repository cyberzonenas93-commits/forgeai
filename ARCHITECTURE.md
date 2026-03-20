# Architecture

Read `AGENTS.md`, `WORK_MEMORY.md`, and `ARCHITECTURE_GUARDRAILS.md` first.

Those files define the current architectural truth, the strongest execution path, and the regressions that must not be reintroduced. This file is a supporting architecture overview, not the first source of truth for anti-drift decisions.

## System Overview
CodeCatalystAI is split into a Flutter mobile client and a Firebase backend.

## Client
- Flutter owns the user experience, navigation, editor shell, diff review, and all approval flows.
- Riverpod providers bootstrap the auth controller and workspace controller.
- A dedicated workspace controller binds live repositories, tasks, execution sessions, checks, wallet state, and activity streams into the shell.
- The client never exposes a terminal, shell, or remote execution surface.

## Backend
- Firebase Auth provides identity and account lifecycle management.
- Firestore stores synced repository metadata, context maps, execution sessions, tasks, events, approvals, token usage, audit events, checks, and activity history.
- Cloud Functions provide controlled contracts for provider config lookup, repository connect/sync, repo context assembly, task orchestration, local workspace cloning, validation/repair, Git actions, CI triggers, and token accounting.
- The main agent execution path uses task-local cloned workspaces plus sandbox copies for validation; Firestore is not the primary file-mutation workspace for that path.

## Data Flow
1. A user authenticates or continues as a guest.
2. The user connects a GitHub or GitHub repository using a provider slug and access token.
3. Cloud Functions sync repository metadata and file trees into Firestore.
4. The workspace controller reads repository, task, wallet, activity, and check streams from Firestore.
5. A prompt enqueues a durable agent task.
6. The backend builds repo context, clones a task-local workspace, generates a structured multi-file diff, and validates or repairs it in sandbox copies.
7. The user reviews the validated diff and explicitly approves apply.
8. The backend applies the diff to the task-local workspace and continues into approval-gated git/check actions.

## Safety Boundaries
- No arbitrary command execution.
- No arbitrary shell or terminal surface in the client.
- Local command execution in the backend runtime is allowlisted and bounded.
- No remote desktop or emulator streaming.
- No silent pushes, merges, or destructive actions.
- All write actions require a logged user intent and should remain auditable.

## Backend Contract Style
The Cloud Functions layer is intentionally controlled and auditable. Functions should:
- validate input carefully
- write auditable records
- return explicit next-step metadata
- keep provider tokens out of the visible client data surface
- avoid performing unsafe implicit actions
