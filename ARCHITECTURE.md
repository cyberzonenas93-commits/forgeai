# Architecture

## System Overview
CodeCatalystAI is split into a Flutter mobile client and a Firebase backend.

## Client
- Flutter owns the user experience, navigation, editor shell, diff review, and all approval flows.
- Riverpod providers bootstrap the auth controller and workspace controller.
- A dedicated workspace controller binds live repositories, connections, files, change requests, checks, wallet state, and activity streams into the shell.
- The client never exposes a terminal, shell, or remote execution surface.

## Backend
- Firebase Auth provides identity and account lifecycle management.
- Firestore stores repositories, files, suggested changes, diffs, token usage, audit events, checks, and activity history.
- Cloud Functions provide controlled contracts for provider config lookup, repository connect/sync, repository file loading, AI suggestion staging, Git actions, CI triggers, and token accounting.

## Data Flow
1. A user authenticates or continues as a guest.
2. The user connects a GitHub or GitHub repository using a provider slug and access token.
3. Cloud Functions sync repository metadata and file trees into Firestore.
4. The workspace controller reads repository, file, wallet, activity, and check streams from Firestore.
5. AI suggestions create staged change records and token reservations.
6. The user reviews a diff and explicitly approves the change before Git actions.
7. Git and check actions execute through provider APIs only after explicit user confirmation.

## Safety Boundaries
- No arbitrary command execution.
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
