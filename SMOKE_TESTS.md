# Smoke Tests

## Purpose
Run a safe beta-readiness pass against disposable repositories and non-production accounts.

## Required Env
- `SMOKE_TEST_FIREBASE_USER_EMAIL`
- `SMOKE_TEST_FIREBASE_USER_PASSWORD`
- `SMOKE_TEST_GITHUB_REPO`
- `SMOKE_TEST_GITLAB_REPO`
- `SMOKE_TEST_BRANCH_PREFIX`

Use a disposable prefix such as `beta/smoke/`.

## Automated Preflight
```bash
npm run validate:env:strict
npm run smoke:backend
```

What `smoke:backend` checks:
- Functions build succeeds
- Firebase CLI is authenticated
- Smoke-test repos are configured
- Branch prefixes are safe

## Manual End-To-End Scenarios

### GitHub
1. Sign in with GitHub.
2. Connect `SMOKE_TEST_GITHUB_REPO`.
3. Open a small text or code file.
4. Add a manual edit and save.
5. Run AI suggestion.
6. Approve diff.
7. Create branch using `SMOKE_TEST_BRANCH_PREFIX`.
8. Commit.
9. Open PR.
10. Trigger tests and inspect logs.

### GitLab
1. Sign in with Email/Password or Google.
2. Connect `SMOKE_TEST_GITLAB_REPO` using a GitLab token.
3. Open a file and save a manual edit.
4. Run AI suggestion.
5. Approve or reject diff.
6. Create branch using `SMOKE_TEST_BRANCH_PREFIX`.
7. Commit.
8. Open MR.
9. Trigger checks and inspect logs.

## Pass / Fail Checklist
- [ ] Auth succeeded
- [ ] Repository connected
- [ ] File opened
- [ ] Manual save worked
- [ ] AI diff generated
- [ ] Token reservation released or captured correctly
- [ ] Branch created
- [ ] Commit created
- [ ] PR/MR opened
- [ ] Checks triggered
- [ ] Logs visible

## Safety Rules
- Never use `main` or `master` as the smoke branch prefix
- Use throwaway repositories only
- Do not merge smoke PRs/MRs into production branches
