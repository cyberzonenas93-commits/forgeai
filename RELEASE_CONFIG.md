# Release Config

## App Identity
- Display name: `ForgeAI`
- iOS bundle ID: `com.forgeai.app`
- Android application ID: `com.forgeai.app`
- Development team: `36TZ8UKL8W`

## Firebase
- Current in-repo Firebase project: `forgeai-555ee`
- Current Firebase config is single-project only
- TestFlight and production are not yet separated in-repo by distinct Firebase app files

## Native Auth Config
- iOS Google URL scheme: `com.googleusercontent.apps.560540704761-2l7cj1v94jud4u7kelp9k1qkvgbt0t8v`
- iOS Firebase auth URL scheme: `app-1-560540704761-ios-b731e8b285335363a0e728`
- Apple Sign In entitlements file: `ios/Runner/Runner.entitlements`

## Android Release Signing
- Template file: `android/key.properties.example`
- Real release file expected at: `android/key.properties`
- Release builds fail fast if the keystore file is missing

## Launch Env Wrapper
Use the wrapper so Flutter builds inherit the launch defines from `.env` files:
```bash
npm run build:android:debug
npm run build:android:release
npm run build:ios:sim
npm run build:ios:release
```

## Screenshot Studio
Use env overrides for screenshot capture:
```bash
FORGEAI_ENABLE_SCREENSHOT_STUDIO=true FORGEAI_SCREENSHOT_SCENE=dashboard npm run run:app
```

Available scenes:
- `auth`
- `dashboard`
- `repo`
- `editor`
- `diff`
- `checks`
- `wallet`
- `settings`

## Versioning
- Current app version: `1.0.0+1`
- Increase `pubspec.yaml` before each beta drop
