# Apple Review Notes

## App Purpose
ForgeAI is a mobile-first developer companion for repository browsing, code editing, AI-assisted patch generation, diff review, commit preparation, pull request / merge request creation, and CI workflow triggering.

## Important Safety Boundaries
- No terminal UI
- No shell access
- No remote desktop
- No VM or emulator streaming
- No arbitrary command execution
- No autonomous merge or push without user approval

## Authentication
- Supports Guest access, Email/Password, Google, Sign in with Apple, and GitHub
- Account deletion is available in-app
- Re-authentication is required before destructive deletion for non-guest users

## Code Editing And AI
- Users can manually edit files
- AI actions are always user-triggered
- AI output is shown as a visible diff before approval
- Commits happen only after explicit user review and approval

## Git And Checks
- Git actions are UI-based only: create branch, commit, open PR/MR, merge PR/MR
- Checks are limited to GitHub Actions / GitLab CI workflow dispatches and results viewing
- No custom command entry is exposed to the user

## Reviewer Copy
ForgeAI is a mobile repository review and editing app for developers. It lets users authenticate, connect repositories, inspect files, make manual edits, request AI-generated code suggestions, review diffs, approve changes, create branches, commit, open pull requests or merge requests, and trigger CI workflows. The app does not provide shell access, remote desktop behavior, or unrestricted code execution.
