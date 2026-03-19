# Device Test Plan

## Target
Physical iPhone validation before TestFlight.

## Build Commands
```bash
npm run build:ios:sim
node ./tool/flutter_with_launch_env.mjs run -d <device-id>
```

## Required Manual Device Tests
- Sign in with Apple
- Sign in with Google
- Sign in with GitHub
- OAuth return to the app after Safari / ASWebAuthenticationSession
- Connect GitHub repository
- Connect GitHub repository token flow
- Open file tree and editor
- Save manual code edit
- Generate AI diff
- Approve diff
- Trigger tests/build/lint checks
- Delete account with re-authentication

## Keyboard / Editor Checks
- Cursor remains stable while editing long files
- Keyboard does not cover action buttons
- Save, AI, and Diff controls remain reachable
- Diff screen scrolls smoothly in long patches

## Performance Targets
- Cold start: under 3 seconds on modern test device
- Sign-in completion: under 10 seconds excluding provider login latency
- Repo sync/open: under 8 seconds for smoke repo
- Editor keystroke latency: no visible dropped input on medium files

## Useful Logging During Device Runs
- Crashlytics enabled
- Analytics enabled
- Cloud Functions `opsMetrics` collection
- Wallet usage ledger for token capture/release confirmation

## Current Manual Apple Blockers
- Verify Sign in with Apple capability in Apple Developer portal
- Verify Services ID / key config in Firebase console
- Complete real-device auth round-trip testing
