# Apple Review Notes

**For App Review team:** Please use the details below when evaluating CodeCatalystAI.

## App Purpose

CodeCatalystAI is a mobile-first developer companion for repository browsing, code editing, AI-assisted agent runs that prepare code changes, diff review, commit preparation, pull request / merge request creation, and CI workflow triggering.

## Important Safety Boundaries

- No terminal UI
- No shell access
- No remote desktop
- No VM or emulator streaming
- No arbitrary command execution
- No autonomous merge or push without user approval

## Authentication

- Supports Guest access, Email/Password, Google, Sign in with Apple, and GitHub
- Account deletion is available in-app (Settings → Account actions → Delete account)
- Re-authentication is required before account deletion for non-guest users
- When a user deletes their account, we remove their authentication identity and delete or anonymize their app-held data (profiles, wallet, repository links, activity) in line with our Privacy Policy

## Privacy and Legal

- Our Privacy Policy and Terms of Service are linked in-app (auth screen footer and Settings → Legal)
- We disclose that AI-generated code changes are provided by third-party services and that user prompts and code are sent to those services to generate results
- We use industry-standard practices for data handling and do not sell user data

## Code Editing and AI

- Users can manually edit files
- AI actions are always user-triggered
- AI output is shown as a visible diff before approval
- Commits happen only after explicit user review and approval

## Git and Checks

- Git actions are UI-based only: create branch, commit, open PR/MR, merge PR/MR
- Checks are limited to GitHub Actions / GitHub CI workflow dispatches and results viewing
- No custom command entry is exposed to the user

## Demo account (App Review — email / password)

Use **Sign in with Email** (not guest) so wallet and AI limits match production behavior for signed-in users.

| Field | Value |
| --- | --- |
| **Email** | `test@codecatalystai.com` |
| **Password** | `M463/1i45a` |

This account is configured on the backend for **unlimited in-app tokens** during review. The Firebase Auth user is **scheduled for automatic deletion 30 days after the account was first created** (then recreate in Firebase Console if you need a fresh demo). See `docs/APP_STORE_REVIEWER_ACCOUNT.md` for setup and rotation.

**Owner:** Ensure this user exists under Firebase Console → Authentication → Users (Email/Password enabled). Password changes in Console override what is pasted here—keep App Store Connect notes in sync.

## Reviewer Copy (short description for review)

CodeCatalystAI is a mobile repository review and editing app for developers. It lets users authenticate, connect repositories, inspect files, make manual edits, start AI agent runs that generate code changes, review diffs, approve changes, create branches, commit, open pull requests or merge requests, and trigger CI workflows. The app does not provide shell access, remote desktop behavior, or unrestricted code execution. Privacy Policy and Terms of Service are available in-app.
