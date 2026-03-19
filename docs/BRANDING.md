# App display name vs bundle ID vs IAP

## Customer-facing name

Edit **`lib/src/core/branding/app_branding.dart`**:

```dart
const String kAppDisplayName = 'CodeCatalystAI';
```

Most in-app strings and `MaterialApp.title` use this constant.

## What does *not* change when you rename

- **Bundle ID** (e.g. `com.angelonartey.forgeai`) — set in Xcode / Firebase; do not change unless you register a new app.
- **IAP product IDs** (e.g. `com.forgeai.app.subscription.pro`) — must stay the same as in App Store Connect until you create new products and update code + backend.
- **Firebase project** (`forgeai-555ee`), **Android package** (`com.forgeai.app`), **guest email domains** (`*.forgeai.local`) — technical identifiers; renaming is a larger migration.

## App Store Connect

- **Name** on the App Store should match **CodeCatalystAI** (or your listing name) even if the internal project folder is still `ForgeAI`.
- **Bundle ID** stays tied to your Apple Developer app record.

## Native labels

- **iOS:** `ios/Runner/Info.plist` — `CFBundleDisplayName` / `CFBundleName` (keep in sync with `kAppDisplayName`).
- **Android:** `android/app/src/main/AndroidManifest.xml` — `android:label`.

## Splash & logo asset

- **`assets/branding/forge_mark.png`** — Use a **PNG with an alpha channel** (transparent background) so the mark blends with the gradient on the in-app splash (`ForgeBrandMark(blendWithBackground: true)`).
- **Native splash** (`flutter_native_splash` in `pubspec.yaml`) uses the same file on a solid `color`; transparency still helps the logo read cleanly on that color.

## Legal / web

- `assets/legal/*.md`, `web/*.html` — updated to match **CodeCatalystAI**; adjust support email if you use a new domain.
