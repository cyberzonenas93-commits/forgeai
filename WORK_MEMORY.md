# CodeCatalystAI Working Memory

## Mission
- Build a production-oriented Flutter mobile app called CodeCatalystAI.
- Keep the app App Store safe: no terminal UI, no raw command execution, no remote desktop behavior.
- All AI and Git actions must be user-triggered, visible, reviewable, and approval-based.

## Known Environment
- Workspace root: `/Users/angelonartey/Desktop/ForgeAI`
- Flutter: `3.41.1`
- Dart: `3.11.0`
- Firebase project id: `forgeai-555ee`
- Android package: `com.forgeai.app`
- iOS bundle id: `com.forgeai.app`

## Product Constraints
- Frontend: Flutter
- Backend: Firebase Auth, Firestore, Cloud Functions
- Providers: OpenAI, Anthropic, Gemini
- Git providers: GitHub and GitHub APIs
- Checks system only via GitHub Actions / GitHub CI
- No terminal, shell, remote execution, or arbitrary command runner

## Active Workstreams
- Bootstrap Flutter project from scratch in this workspace.
- Create `agents.md` and assign domain ownership.
- Keep the now-live app shell, auth, workspace, and backend contracts green after the integration pass.
- Maintain docs, Firestore rules, and verification notes in sync with the real implementation.
- Drive the repo from build-verified to launch-ready beta with deploy scripts, provider setup docs, smoke-test harnesses, observability, and token-economics guardrails.

## Decisions
- Use `com.forgeai.app` to match the provided Firebase files.
- Prefer Riverpod for modular state management and testable feature boundaries.
- Use mock-friendly service interfaces so backend/API implementations can be swapped or completed incrementally.
- Keep a preview/offline workspace controller path for widget tests where Firebase is not initialized.

## Integration Notes
- There was no existing Flutter project or Git repo in this folder at start.
- Root already contains `google-services.json` and `GoogleService-Info.plist`.
- Re-read this file before major edits or integration steps.
- Root branding source folder (if present) is `ForgeAI_iOS_Icons/` — legacy on-disk name; see `tool/generate_branding_assets.dart`.
- `tool/generate_branding_assets.dart` is the current helper for producing branding assets from the icon pack.
- Local provider secrets should live in git-ignored env files under `functions/`; never store raw keys in tracked docs or source files.
- GitHub account sign-in is implemented in the Flutter auth flow; setup still depends on enabling the GitHub provider in Firebase Authentication and using `https://forgeai-555ee.firebaseapp.com/__/auth/handler` as the OAuth callback URL.

## Implementation Status
- CodeCatalystAI now has a custom app entrypoint, auth gate, signed-in home shell, and feature hubs wired to agent-built screens.
- Workflow modules exist under `lib/src/features/editor`, `diff`, `ai`, `checks`, `wallet`, `activity`, and `git`.
- UI modules exist under `lib/src/features/dashboard`, `repos`, `settings`, and `lib/src/shared`.
- Auth/account modules exist under `lib/src/features/auth`, `account`, and `lib/src/core/firebase`.
- Firebase backend/docs package exists under `functions/` plus root docs and Firebase config files.
- The UI layer now uses a shared premium dark design system under `lib/src/core/theme` and `lib/src/core/widgets`.
- The app now has a custom animated splash screen, premium auth entry flow, redesigned dashboard, repository browser, editor workflow, diff review, checks, wallet, activity timeline, and settings UI.
- Native splash and launcher icon resources were regenerated from the root icon pack and branding assets.
- FirebaseAuth-backed auth is now wired in through a dedicated repository, with guest, email/password, Google, Apple, and GitHub flows plus reauthentication, sign-out, and delete-account handling.
- GitHub sign-in setup is now documented with the Firebase/GitHub OAuth callback path, and the auth layer surfaces a GitHub-specific configuration error when the provider is not enabled correctly.
- Cloud Functions now expose provider config lookup, repository connect/sync, repository file loading, AI suggestion orchestration, Git action scaffolding, check dispatch scaffolding, and wallet movement helpers.
- A live workspace controller and repository now bind Firestore repositories, provider connections, file trees, editor drafts, AI change requests, checks, wallet data, and activity into the Flutter shell.
- Repository connection now supports GitHub/GitHub slug entry plus access-token-backed sync from the mobile app.
- The editor, diff review, Git flow, checks dashboard, wallet, activity history, and settings screens now read from live workspace state instead of static mock-only props.
- The repository browser no longer falls back to mock file data when no live repository is selected.
- Launch automation now includes env validation, Firebase deploy wrappers, smoke-test checklist runners, and screenshot-studio routes for release asset capture.
- Backend runtime validation is centralized in `functions/src/runtime.ts`, pricing is centralized in `functions/src/pricing.ts`, and Cloud Functions now emit structured `opsMetrics` plus richer wallet usage telemetry.
- Wallet reservation/capture flows now enforce daily action caps, monthly wallet limits, and release tokens on queued Git/check failure paths or empty commit payloads.
- Native release prep now includes Android release-signing templates, Crashlytics plugin wiring, iOS Sign in with Apple entitlements, and iOS Firebase/Google auth URL schemes.
- Launch docs now exist for provider setup, deployment, smoke tests, device testing, release config, observability, token economics, and beta release operations.

## Verification Status
- `flutter analyze` passed after the UI redesign and Firebase auth integration.
- `flutter test` passed after fixing a responsive overflow in `ForgeBrandMark` and wiring the Firebase auth repository.
- `flutter build apk --debug` passed after the UI redesign and produced `build/app/outputs/flutter-apk/app-debug.apk`.
- `npm run build` passed in `functions/`.
- `flutter build ios --simulator` passed after the live workspace integration pass and produced `build/ios/iphonesimulator/Runner.app`.
- `npm --prefix functions run build` passed after the launch-readiness backend changes.
- `npm run simulate:tokens` passed and modeled >90% gross margin across light, typical, and heavy beta usage profiles.
- `node ./tool/validate_launch_env.mjs --strict` currently fails only on expected live-secret / console blockers, not on repo wiring.
- `npm run build:ios:sim` stalled inside local `xcodebuild` during the launch pass on this machine, so iOS simulator verification needs one clean rerun outside the hung local session before beta sign-off.

## Platform Notes
- Android package and iOS bundle identifiers are aligned to `com.forgeai.app`.
- iOS deployment target had to be raised to `15.0` for the current Firebase/Firestore stack.
- Android splash resources live under `android/app/src/main/res/drawable*` and Android launcher icons were regenerated in `android/app/src/main/res/mipmap-*`.
- iOS launcher icons live under `ios/Runner/Assets.xcassets/AppIcon.appiconset`, and iOS launch images were regenerated under `ios/Runner/Assets.xcassets/LaunchImage.imageset`.
- Firestore rules now cover `users/{uid}/connections/{provider}` and restrict repository file reads/writes to the owning user.
- Current in-repo Firebase environment separation is still single-project only (`forgeai-555ee`).
- GitHub beta flow is token-based; full GitHub mobile OAuth is not yet implemented.
