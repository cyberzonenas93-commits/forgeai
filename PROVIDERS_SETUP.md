# Providers Setup

## Firebase Project
- Project ID: `forgeai-555ee`
- Firebase Auth handler URL: `https://forgeai-555ee.firebaseapp.com/__/auth/handler`
- iOS bundle ID: `com.forgeai.app`
- Android application ID: `com.forgeai.app`

## Environment Variables

### Root / Flutter Launch
- `FORGEAI_ENV`
- `FORGEAI_BETA_CHANNEL`
- `FORGEAI_ENABLE_ANALYTICS`
- `FORGEAI_ENABLE_CRASHLYTICS`
- `FORGEAI_ENABLE_SCREENSHOT_STUDIO`
- `FORGEAI_SCREENSHOT_SCENE`

### Functions / Backend
- `FORGEAI_FIREBASE_PROJECT_ID`
- `FORGEAI_FIREBASE_REGION`
- `FORGEAI_REQUIRED_PROVIDERS`
- `FORGEAI_ENFORCE_PROVIDER_SECRETS`
- `FORGEAI_STRICT_ENV_VALIDATION`
- `FORGEAI_TOKEN_VALUE_USD`
- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `GEMINI_API_KEY`
- `GITHUB_TOKEN` or `GITHUB_APP_TOKEN`
- `GITHUB_TOKEN`

## Firebase Authentication

### Enable In Console
- Anonymous
- Email/Password
- Google
- Apple
- GitHub

### GitHub Provider
1. In GitHub Developer Settings, create an OAuth App.
2. Homepage URL: your website or placeholder product URL.
3. Authorization callback URL: `https://forgeai-555ee.firebaseapp.com/__/auth/handler`
4. Copy the GitHub client ID and client secret into Firebase Authentication → GitHub provider.

### Google Provider
1. Enable Google in Firebase Authentication.
2. Ensure Android SHA-1/SHA-256 are registered in Firebase for release devices.
3. iOS reversed client ID already wired in `ios/Runner/Info.plist`.

### Apple Provider
1. Enable Sign in with Apple in the Apple Developer portal for `com.forgeai.app`.
2. Create or reuse the Apple private key, Key ID, and Services ID.
3. In Firebase Authentication → Apple provider, enter:
   - Services ID
   - Apple Team ID
   - Key ID
   - Private key contents
4. Confirm the entitlement in `ios/Runner/Runner.entitlements` remains enabled.

## GitHub Service Token
- Variable: `GITHUB_TOKEN` or `GITHUB_APP_TOKEN`
- Minimum beta scopes for PAT: `repo`, `workflow`, `read:user`, `user:email`

## Checks / CI workflow
- **GitHub**: The app discovers workflows via the Actions API and triggers one (by name/path match for tests, lint, build). Repos need at least one **active** workflow under `.github/workflows/` with `workflow_dispatch:` enabled. Works with any workflow filename (e.g. `ci.yml`, `test.yml`, `lint.yml`).
- **GitHub**: The app triggers a pipeline on the default branch; no workflow list is used.
- If GitHub returns no workflows, the app shows: "No workflows found. Add a workflow with workflow_dispatch in .github/workflows/ (e.g. ci.yml)."

## GitHub Service Token
- Variable: `GITHUB_TOKEN`
- Current beta connection mode is personal access token, not mobile OAuth
- Minimum scopes: `api`, `read_repository`, `write_repository`

## OpenAI
- Variable: `OPENAI_API_KEY`
- Default model: `gpt-5-chat-latest` (OpenAI alias that follows the latest ChatGPT GPT-5 snapshot; pin `OPENAI_MODEL` to a dated snapshot if you need stability)

## Anthropic
- Variable: `ANTHROPIC_API_KEY`
- Optional for beta unless explicitly enabled

## Gemini
- Variable: `GEMINI_API_KEY` or `GOOGLE_API_KEY`
- Optional for beta unless explicitly enabled

## iOS Callback / URL Scheme Inventory
- Google reversed client ID: `com.googleusercontent.apps.560540704761-2l7cj1v94jud4u7kelp9k1qkvgbt0t8v`
- Firebase auth encoded app ID scheme: `app-1-560540704761-ios-b731e8b285335363a0e728`
- These are already wired in `ios/Runner/Info.plist`

## Recommended Secret Commands
```bash
firebase functions:secrets:set OPENAI_API_KEY
firebase functions:secrets:set GITHUB_TOKEN
firebase functions:secrets:set GITHUB_TOKEN
firebase functions:secrets:set ANTHROPIC_API_KEY
firebase functions:secrets:set GEMINI_API_KEY
```

## Current Manual Blockers
- Firebase Auth provider enablement
- GitHub OAuth App creation
- Apple provider key/Services ID setup
- Real provider tokens and smoke-test repos
