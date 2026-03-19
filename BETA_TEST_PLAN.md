# Beta Test Plan

## Goal
Validate that CodeCatalystAI can safely authenticate, sync repositories, edit files, generate AI diffs, open PRs/MRs, run checks, and meter token usage from mobile without exposing terminal or remote-execution behavior.

## Tester Cohorts
- Internal engineering: full flow coverage, console access, thorough bug finding.
- Friendly external developers: real-world repository and latency coverage.
- iPhone-first testers: OAuth and editor ergonomics validation.

## Required Environments
- Firebase project with live Auth providers enabled
- One GitHub test account and disposable repository
- One GitHub test account and disposable repository
- OpenAI secret configured
- Optional Anthropic/Gemini secrets if beta routing includes them

## Must-Pass Flows
- Sign in with Email/Password
- Continue as Guest
- Sign in with Google
- Sign in with Apple on physical iPhone
- Sign in with GitHub
- Connect GitHub repository
- Connect GitHub repository via token flow
- Browse file tree
- Open and edit file
- Save manual edit
- Generate AI diff
- Approve AI diff
- Reject AI diff
- Create branch
- Commit changes
- Open PR/MR
- Trigger tests, lint, and build checks
- View logs/results
- Delete account with re-authentication

## Pass Criteria
- No auth flow leaves the app in a broken state
- No Git or check action strands reserved tokens
- AI actions either capture tokens on success or release them on failure
- All destructive actions remain user-confirmed
- No terminal, shell, or arbitrary command surfaces appear

## Failure Buckets To Track
- Auth callback mismatch
- Missing provider token / configuration
- Repo sync mismatch or empty file tree
- AI latency above acceptable range
- Token overcharge / refund bug
- PR/MR dispatch failure
- CI workflow dispatch failure

## Beta Exit Criteria
- All must-pass flows succeed for at least one GitHub and one GitHub repo
- Crash-free internal beta session rate is acceptable
- Token usage logs reconcile with successful/failed actions
- No App Store review blocker remains in `APPLE_REVIEW_NOTES.md`
