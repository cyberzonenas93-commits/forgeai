# Beta Release Plan

## Scope
Small TestFlight-style beta focused on authentication, repository operations, AI agent flow, checks, and token accounting.

## Target Group
- 5-10 internal engineering testers
- 5-15 trusted external developers with real GitHub/GitHub repos

## Beta Goals
- Validate live auth flows
- Validate GitHub/GitHub repository operations
- Measure AI latency and token burn
- Validate PR/MR and check dispatch reliability

## Must-Test Areas
- Apple / Google / GitHub sign-in
- Repo sync and file browsing
- Manual edit and save
- AI agent run and diff approval path
- Branch / commit / PR or MR creation
- CI workflow dispatch and log viewing
- Account deletion

## Monitoring Priorities
- Auth callback failures
- Provider token missing warnings
- AI generation failures or high latency
- Token reservations not matched by release/capture
- Git/check dispatch failures

## Rollback Criteria
- Repeated auth callback failures on iPhone
- Token overcharge or stranded reservation bug
- PR/MR creation reliability below acceptable threshold
- Crash spike after beta install

## Feature Flags
- Keep `FORGEAI_ENABLE_SCREENSHOT_STUDIO=false` for beta users
- Keep analytics and crash reporting enabled

## Feedback Intake
- Use `BETA_FEEDBACK_TEMPLATE.md` for all tester reports
- Route blocker or high-severity auth, token, crash, or PR/MR issues to the launch owner within the same day

## TestFlight Notes Draft
- "CodeCatalystAI beta adds mobile repository review, AI agent-driven diff generation, GitHub/GitHub actions, and CI checks. Please focus on sign-in, repo connection, editing, AI diff approval, and workflow reliability."
