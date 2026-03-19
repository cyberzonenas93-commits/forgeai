# Changelog

## Unreleased
- Bootstrapped a Flutter mobile app for ForgeAI.
- Added a shared working memory file and agent ownership map.
- Created the Firebase backend scaffold and extended it into callable repository sync, file loading, AI suggestion, Git action, check, and wallet orchestration.
- Added Firestore rules and Firebase project wiring for the `forgeai-555ee` project.
- Implemented a premium dark design system, animated splash, and redesigned dashboard, repository, editor, diff, checks, wallet, activity, and settings screens.
- Replaced in-memory auth in production with Firebase-backed guest, email/password, Google, Apple, and GitHub authentication.
- Added a live workspace controller that binds Firestore repositories, connections, files, change requests, checks, wallet state, and activity into the app shell.
- Added repository connection flow with GitHub/GitLab slug entry and access-token-backed sync.
- Removed the last repository-browser mock fallback so file trees now come only from live workspace data.
- Re-verified Flutter analysis, tests, Android debug build, Cloud Functions TypeScript build, and iOS simulator build.
- Added explicit GitHub sign-in setup guidance for Firebase Authentication and GitHub OAuth App configuration.
- Improved auth failure messaging so GitHub sign-in explains missing provider setup and callback mismatches.
- Added launch automation commands, a Flutter launch-env wrapper, deployment validation, and a token economics simulator.
- Added screenshot studio scenes for fast App Store asset capture.
- Added iOS Firebase auth URL scheme wiring and Apple Sign In entitlements for release readiness.
- Added Android Crashlytics plugin wiring and release signing template support.
- Added backend runtime/provider validation, managed-secret-ready callable options, structured metrics, and pricing metadata.
- Fixed token reservation leaks for queued Git/check actions and empty commit payloads.
- Enforced daily action caps and monthly wallet limits in backend token capture/reserve paths.
- Added launch, deployment, smoke, observability, device, release, and beta readiness documentation.
- Added a reusable beta feedback intake template and synced Firestore schema docs with `opsMetrics` plus expanded wallet usage telemetry.
