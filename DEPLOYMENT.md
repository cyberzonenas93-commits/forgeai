# Deployment

## Preconditions
- Firebase CLI installed and authenticated
- Target project has required secrets configured
- `npm run validate:env:strict` passes

## Validation
```bash
npm run validate:env
npm run validate:env:strict
npm --prefix functions run build
flutter analyze
flutter test
```

## Dry Run Commands
```bash
npm run deploy:functions
npm run deploy:rules
npm run deploy:indexes
npm run deploy:prod
```

Each `deploy:*` command is dry-run only until you append `-- --yes`.

## Real Deploy Commands
```bash
npm run deploy:functions -- --yes
npm run deploy:rules -- --yes
npm run deploy:indexes -- --yes
npm run deploy:prod -- --yes
```

## What The Wrapper Does
- Reads launch env context
- Verifies Firebase project and required secrets
- Runs Functions TypeScript build
- Calls `firebase deploy --only ...`

## Firebase Functions Predeploy
`firebase.json` now runs:
- `npm run validate:env:strict`
- `npm --prefix functions run build`

That prevents direct Functions deploys from skipping validation.

## Managed Secret Path
Use Firebase/GCP managed secrets for deployed backends:
```bash
firebase functions:secrets:set OPENAI_API_KEY
firebase functions:secrets:set GITHUB_TOKEN
firebase functions:secrets:set GITHUB_TOKEN
firebase functions:secrets:set APPLE_IAP_SHARED_SECRET   # For IAP receipt validation (Payments)
```
For `APPLE_IAP_SHARED_SECRET`, use the **App-Specific Shared Secret** from [App Store Connect](https://appstoreconnect.apple.com) → Your App → App Information → App-Specific Shared Secret (or Users and Access → Shared Secret). You can also run `npm run setup:iap-secret` to be prompted for it.

`functions/src/index.ts` binds the managed secrets through callable options, so the deployed runtime does not depend on committed env files.

## Hosting (Privacy & Support URLs)

Static pages in `web/` provide the **Privacy Policy** and **Support** URLs for the App Store and in-app links.

**Deploy hosting:**
```bash
firebase deploy --only hosting
```

**URLs** (replace `PROJECT_ID` with your Firebase project ID, e.g. from `.firebaserc` or Firebase console):

- **Privacy Policy:** `https://PROJECT_ID.web.app/privacy` (or `https://PROJECT_ID.firebaseapp.com/privacy`)
- **Support:** `https://PROJECT_ID.web.app/support` (or `https://PROJECT_ID.firebaseapp.com/support`)

Use these in App Store Connect (App Information → Privacy Policy URL, Support URL) and anywhere you need a public link.

## Expected Manual Steps
1. Set Firebase project secrets.
2. Confirm `.firebaserc` target if you introduce staging/prod aliases.
3. Run `npm run deploy:prod -- --yes` (or deploy hosting separately with `firebase deploy --only hosting`).
4. Run `npm run smoke:backend`.
