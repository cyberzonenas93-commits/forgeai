# Launch Queue

Last updated: 2026-03-18

## Automatable Now
- [x] Centralized backend runtime validation in `functions/src/runtime.ts`.
- [x] Centralized pricing rules in `functions/src/pricing.ts`.
- [x] Added Functions structured metrics and wallet usage pricing metadata.
- [x] Added Firebase managed-secret-ready callable config in `functions/src/index.ts`.
- [x] Added Firestore indexes manifest and wired it in `firebase.json`.
- [x] Added root launch scripts in `package.json`.
- [x] Added Flutter launch-env wrapper in `tool/flutter_with_launch_env.mjs`.
- [x] Added token economics simulator in `tool/token_economics_simulator.mjs`.
- [x] Added screenshot capture scenes in `lib/src/features/screenshot/presentation/forge_screenshot_studio.dart`.
- [x] Added iOS Apple Sign In entitlements and Firebase auth URL scheme.
- [x] Added Android release signing template and Crashlytics plugin wiring.
- [x] Added deployment, provider, smoke, release, device, observability, and beta docs.
- [x] Fixed stranded token reservations for queued Git/check actions and empty commit payloads.
- [x] Enforced daily action caps and monthly wallet caps in backend wallet capture/reserve paths.

## Blocked By Credentials Or Console Access
- [ ] Set production or beta Firebase Auth providers in the Firebase console: Anonymous, Email/Password, Google, Apple, GitHub.
- [ ] Add GitHub OAuth App client ID and secret to Firebase Authentication.
- [ ] Add GitHub service token or app token as `GITHUB_TOKEN` or `GITHUB_APP_TOKEN`.
- [ ] Add GitLab service token as `GITLAB_TOKEN`.
- [ ] Add Anthropic and Gemini secrets if those providers are enabled in beta.
- [ ] Set Firebase managed secrets in the target project before production deploy.
- [ ] Provide safe smoke-test users and disposable GitHub/GitLab repositories.

## Blocked By Apple / Device / TestFlight
- [ ] Confirm Apple Developer App ID capability for Sign in with Apple.
- [ ] Confirm Firebase Apple provider configuration with Services ID / key ID / team ID.
- [ ] Run physical iPhone OAuth return-flow tests for Apple, Google, and GitHub.
- [ ] Capture final App Store screenshots on approved simulator/device sizes.
- [ ] Upload signed archive to TestFlight and enroll tester groups.

## Current Gaps Still Open
- [ ] In-repo Firebase environment separation is still single-project only (`forgeai-555ee`).
- [ ] GitLab mobile OAuth is not implemented; beta uses token-based GitLab connection flow.
- [ ] iOS simulator build repeatedly stalls inside local `xcodebuild` on this machine and needs a clean rerun outside the hung session.

## Execution Order
1. Console secrets and auth provider setup
2. `npm run validate:env:strict`
3. `npm run deploy:prod -- --yes`
4. `npm run smoke:backend`
5. Device test plan execution
6. TestFlight beta rollout
