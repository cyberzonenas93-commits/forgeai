# ForgeAI

ForgeAI is a mobile-first developer tool for reviewing, editing, and shipping code from a phone without exposing a terminal or remote desktop experience.

## What It Does
- Connect GitHub or GitLab repositories
- Browse files and edit code on mobile
- Ask AI to suggest changes, then review the diff before approval
- Commit approved changes to a branch
- Open pull requests or merge requests
- Trigger CI checks and inspect logs/results
- Track AI usage through a wallet and token ledger

## Safety Model
ForgeAI is intentionally not a cloud IDE, shell, or code execution platform. Every AI or Git action is user-triggered, visibly reviewed, and approval-gated before commit or merge.

## Project Layout
- `lib/` Flutter mobile app
- `functions/` Firebase Cloud Functions TypeScript backend
- `firestore.rules` Firestore security rules
- `firebase.json` Firebase deployment configuration
- `WORK_MEMORY.md` shared build memory for the coordinated agents
- `agents.md` domain ownership map

## Current Status
ForgeAI now includes:
- a premium dark Flutter mobile UI system
- live Firebase Auth for guest, email/password, Google, Apple, and GitHub sign-in
- a workspace controller that binds repositories, files, diffs, checks, wallet state, and activity into the app shell
- callable backend orchestration for repository connect/sync, file loading, AI suggestions, Git actions, checks, and token accounting

Repository connection uses a provider slug plus token-backed provider access for real GitHub/GitLab sync. GitHub sign-in now reuses the signed-in user's GitHub OAuth access automatically, while GitLab can still use a pasted token. All AI, Git, and checks actions remain explicit, visible, and approval-based.

GitHub account sign-in is already wired in the mobile auth flow; finish setup by enabling the GitHub provider in Firebase Authentication and pointing your GitHub OAuth App callback to `https://forgeai-555ee.firebaseapp.com/__/auth/handler`.
