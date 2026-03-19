# Setup

## Prerequisites
- Flutter 3.41.1 or newer
- Dart 3.11.0
- Node.js 20.x for Firebase Functions
- Firebase CLI
- A Firebase project matching `forgeai-555ee`

## Flutter App
1. Install dependencies with `flutter pub get`.
2. Run the mobile app with `flutter run`.
3. For iOS, make sure the `GoogleService-Info.plist` file is present at the project root and copied into the Xcode target as part of your app setup.
4. For Android, keep `google-services.json` at the project root and ensure the Firebase Gradle setup is wired before release builds.
5. In Firebase Authentication, enable:
   - Anonymous
   - Email/Password
   - Google
   - Apple
   - GitHub
6. Add your Android SHA-1 fingerprint in Firebase project settings before testing provider sign-in flows on Android devices.

## Firebase Backend
1. Change into `functions/`.
2. Install dependencies with `npm install`.
3. Create a local provider secrets file such as `functions/.env.local` or copy `functions/.env.example` into a local-only env file and fill in the required keys.
4. Build the TypeScript functions with `npm run build`.
5. Deploy with `firebase deploy --only functions,firestore:rules`.

## Provider Setup
- GitHub repository sync can reuse the signed-in user's GitHub OAuth access automatically after Firebase GitHub sign-in succeeds.
- GitHub/GitLab repository sync also supports a repository slug plus access token flow from the app when you want to override or manually provide provider access.
- OpenAI, Anthropic, and Gemini provider hooks are implemented in Cloud Functions with safe fallbacks when provider secrets are missing.
- For local development, keep provider keys in a git-ignored env file under `functions/`.
- For production AI execution, configure the relevant provider secrets in your deployed Firebase Functions environment.

## GitHub Sign-In Setup
1. In the Firebase console for `forgeai-555ee`, open Authentication, then Sign-in method, then enable the GitHub provider.
2. In GitHub Developer Settings, create an OAuth App for ForgeAI.
3. Use `https://forgeai-555ee.firebaseapp.com/__/auth/handler` as the Authorization callback URL for the GitHub OAuth App.
4. Copy the GitHub OAuth App client ID and client secret into the GitHub provider settings in Firebase Authentication and save.
5. Keep `GitHub` enabled in the ForgeAI auth entry screen. The mobile app routes that button through Firebase Auth using `GithubAuthProvider` and stores the resulting GitHub OAuth access for later repository sync.
6. If GitHub sign-in fails with a configuration error in the app, re-check the Firebase GitHub provider toggle, the OAuth client secret, and the callback URL above.

## Local Development Notes
- The functions package now performs controlled repository sync/file loading and AI/Git/check orchestration while preserving approval-first UX boundaries.
- AI, Git, and checks operations remain safe, explicit, and auditable rather than acting like unchecked remote execution.
- Firestore access should always go through the rules in `firestore.rules`.

## Recommended Environment Variables
- `GOOGLE_APPLICATION_CREDENTIALS` for local Firebase Admin access
- `FIREBASE_PROJECT_ID=forgeai-555ee`
