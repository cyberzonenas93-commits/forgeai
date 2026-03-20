# CodeCatalystAI

CodeCatalystAI is a mobile-first coding-agent product for reviewing, editing, validating, and shipping code from a phone without exposing a terminal or remote desktop experience.

Before changing core systems, read these first and in this order:
- `AGENTS.md`
- `WORK_MEMORY.md`
- `ARCHITECTURE_GUARDRAILS.md`

If you are changing runtime, repo context, validation, workspace, queueing, approvals, git follow-up, or core agent UI, do not proceed until you have read them.

## What It Does
- Connect GitHub or GitHub repositories
- Browse files and edit code on mobile
- Start durable AI agent runs that inspect the repo, prepare multi-file diffs, validate or repair them, and pause for approval
- Commit approved changes from the task-local workspace to a branch
- Open pull requests or merge requests
- Trigger CI checks and inspect logs/results
- Track AI usage through a wallet and token ledger

## Safety Model
CodeCatalystAI is intentionally not a cloud IDE, shell, or code execution platform. Every AI or Git action is user-triggered, visibly reviewed, and approval-gated before commit or merge.

## Project Layout
- `lib/` Flutter mobile app
- `functions/` Firebase Cloud Functions TypeScript backend
- `firestore.rules` Firestore security rules
- `firebase.json` Firebase deployment configuration
- `AGENTS.md` repo-level instructions for future AI and contributor runs
- `WORK_MEMORY.md` current architecture memory snapshot
- `ARCHITECTURE_GUARDRAILS.md` anti-drift rules for core systems
- `DISTRIBUTED_AGENT_ARCHITECTURE.md` worker-plane and control-plane design
- `WORKER_SYSTEM.md` worker lifecycle, leases, and stale recovery
- `COST_OPTIMIZATION.md` task budgets, cost profiles, and routing strategy
- `MULTI_AGENT_SYSTEM.md` logical planner/context/editor/validator/repair/git orchestration

## Current Status
CodeCatalystAI now includes:
- a premium dark Flutter mobile UI system
- live Firebase Auth for guest, email/password, Google, Apple, and GitHub sign-in
- a workspace controller that binds repositories, tasks, diffs, checks, wallet state, and activity into the app shell
- a distributed backend agent runtime with queueing, repo locks, Firestore-dispatched worker runs, repo-aware context building, validation or repair loops, and git follow-up continuity
- task-local cloned workspaces for main agent execution, sandbox validation, and real git commit/push/PR follow-up

Repository connection uses a provider slug plus token-backed provider access for real GitHub/GitHub sync. GitHub sign-in now reuses the signed-in user's GitHub OAuth access automatically, while GitHub can still use a pasted token. All AI, Git, and checks actions remain explicit, visible, and approval-based.

GitHub account sign-in is already wired in the mobile auth flow; finish setup by enabling the GitHub provider in Firebase Authentication and pointing your GitHub OAuth App callback to `https://forgeai-555ee.firebaseapp.com/__/auth/handler`.
