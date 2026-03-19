# Release Checklist

## Repo And Build
- [x] `flutter analyze`
- [x] `flutter test`
- [x] `npm --prefix functions run build`
- [x] `npm run build:android:debug`
- [ ] `npm run build:ios:sim`
- [x] `firebase.json` includes Functions predeploy validation and Firestore indexes
- [x] `firestore.rules` and `firestore.indexes.json` are present

## Environment And Secrets
- [x] Root `.env.example` exists
- [x] `functions/.env.example` exists
- [x] `functions/.env.production.example` exists
- [x] No provider secret is stored in tracked source
- [ ] GitHub service secret configured
- [ ] GitLab service secret configured
- [ ] OpenAI secret configured in target Firebase project
- [ ] Anthropic secret configured if enabled
- [ ] Gemini secret configured if enabled

## Auth And Provider Console
- [ ] Firebase Anonymous auth enabled
- [ ] Firebase Email/Password auth enabled
- [ ] Firebase Google auth enabled
- [ ] Firebase Apple auth enabled
- [ ] Firebase GitHub auth enabled
- [ ] GitHub OAuth callback set to `https://forgeai-555ee.firebaseapp.com/__/auth/handler`
- [ ] Apple provider values entered in Firebase console

## Native Release Readiness
- [x] iOS Sign in with Apple entitlements file present
- [x] iOS Google reversed-client URL scheme present
- [x] iOS Firebase auth URL scheme present
- [x] Android release signing template present at `android/key.properties.example`
- [ ] Real `android/key.properties` created for release builds
- [ ] Physical iPhone auth return-flow validation completed

## Launch Operations
- [x] `PROVIDERS_SETUP.md`
- [x] `DEPLOYMENT.md`
- [x] `SMOKE_TESTS.md`
- [x] `DEVICE_TEST_PLAN.md`
- [x] `OBSERVABILITY.md`
- [x] `TOKEN_ECONOMICS.md`
- [x] `BETA_RELEASE_PLAN.md`
- [x] `BETA_TEST_PLAN.md`
- [x] `BETA_FEEDBACK_TEMPLATE.md`

## Go / No-Go
- Go when all unchecked console/device items above are complete and smoke tests pass on real accounts.
- No-go if auth callbacks fail, token reservations drift, or PR/MR/check dispatches fail against live repos.
