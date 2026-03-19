# ForgeAI Agents

This file tracks domain ownership for the coordinated build. Agents should stay within their owned areas unless integration requires collaboration.

## Product Architect
- Owns app structure, module boundaries, navigation model, and integration standards.

## Flutter UI
- Owns shared design system, shell layout, dashboard, repository list, settings screens, and reusable widgets.

## Auth
- Owns authentication flows, guest mode, sign-in providers, account state, and deletion/re-auth UX.

## Git Integration
- Owns GitHub/GitLab repository sync, branches, commits, pull requests / merge requests, and activity logging.

## Editor/Diff
- Owns code editor, file save flows, AI change staging, diff review, and approval controls.

## AI Providers
- Owns provider abstraction, prompt task models, token estimation, and AI suggestion pipelines.

## Token Economy
- Owns wallet, usage ledger, pricing previews, and usage limit enforcement.

## Checks/CI
- Owns workflow listing, check execution, build/test/lint trigger actions, and logs/results presentation.

## Firebase Backend
- Owns data models, Firestore repositories, Cloud Function contracts, and Firebase bootstrapping.

## Security
- Owns secrets handling guidance, permission boundaries, audit considerations, and destructive-action confirmations.

## Compliance
- Owns App Store safety posture, deletion compliance, provider disclaimers, and Apple review notes.

## QA/Docs
- Owns verification coverage, setup docs, changelog, schema docs, and release-readiness notes.
