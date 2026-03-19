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
firebase functions:secrets:set GITLAB_TOKEN
```

`functions/src/index.ts` binds the managed secrets through callable options, so the deployed runtime does not depend on committed env files.

## Expected Manual Steps
1. Set Firebase project secrets.
2. Confirm `.firebaserc` target if you introduce staging/prod aliases.
3. Run `npm run deploy:prod -- --yes`.
4. Run `npm run smoke:backend`.
