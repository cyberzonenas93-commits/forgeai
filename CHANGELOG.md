# Changelog

## Unreleased
- **App Store review**: Documented demo credentials (`test@codecatalystai.com`) in `APPLE_REVIEW_NOTES.md` and `docs/APP_STORE_REVIEWER_ACCOUNT.md`. Backend allowlists that email for unlimited wallet usage and adds scheduled `purgeExpiredAppStoreReviewerTestAccounts` to delete the Auth user 30 days after creation (Firestore cleanup via existing `deleteUserDataOnAuthDelete`).
- **New project (AI)**: Repositories tab can create a new GitHub or GitHub repository, generate a starter file set with OpenAI, commit files remotely, sync into the workspace, and select the new repo. Callable `createProjectRepository`, wallet action `ai_project_scaffold`, Flutter `NewAiProjectScreen` + `ForgeWorkspaceController.createProjectWithAi`.
- **Monetization**: Hybrid model (subscriptions + token usage + top-ups). Centralized pricing in `config/monetization.json`, `functions/src/pricing.ts`, and `lib/src/core/config/forge_economics_config.dart`. Token value $0.01; action prices for explain_code (2), fix_bug (6), generate_tests (8), refactor_code (10), deep_repo_analysis (25), ai_suggestion (8), plus git/check actions. Plan definitions (Free/Pro/Power) and token packs (small/medium/large) with Apple-net assumptions. Wallet ledger now includes before/after balance and plan-based daily action cap. Billing abstraction (`ForgeBillingService`), mock implementation, paywall and token pack screens, wallet upgrade/get-tokens CTAs. Model routing by tier (basic/standard/priority) in `economics-config.ts` and wired into AI call path. Revenue/cost telemetry via existing opsMetrics and `forge_paywall_viewed` / `forge_token_packs_viewed` analytics. Token economics simulator extended for subscription/top-up scenarios and margin validation. Docs: TOKEN_ECONOMICS.md, PRICING_MODEL.md, BILLING_ARCHITECTURE.md, APPLE_IAP_PLAN.md, REVENUE_SIMULATION.md.
- Bootstrapped a Flutter mobile app for CodeCatalystAI.
- Added a shared working memory file and agent ownership map.
- Created the Firebase backend scaffold and extended it into callable repository sync, file loading, AI suggestion, Git action, check, and wallet orchestration.
- Added Firestore rules and Firebase project wiring for the `forgeai-555ee` project.
- Implemented a premium dark design system, animated splash, and redesigned dashboard, repository, editor, diff, checks, wallet, activity, and settings screens.
- Replaced in-memory auth in production with Firebase-backed guest, email/password, Google, Apple, and GitHub authentication.
- Added a live workspace controller that binds Firestore repositories, connections, files, change requests, checks, wallet state, and activity into the app shell.
- Added repository connection flow with GitHub/GitHub slug entry and access-token-backed sync.
- Removed the last repository-browser mock fallback so file trees now come only from live workspace data.
- Re-verified Flutter analysis, tests, Android debug build, Cloud Functions TypeScript build, and iOS simulator build.
- Added explicit GitHub sign-in setup guidance for Firebase Authentication and GitHub OAuth App configuration.
- Improved auth failure messaging so GitHub sign-in explains missing provider setup and callback mismatches.
- Added launch automation commands, a Flutter launch-env wrapper, deployment validation, and a token economics simulator.
- Added screenshot studio scenes for fast App Store asset capture.
- Added iOS Firebase auth URL scheme wiring and Apple Sign In entitlements for release readiness.
- Added Android Crashlytics plugin wiring and release signing template support.
- Added backend runtime/provider validation, managed-secret-ready callable options, structured metrics, and pricing metadata.
- Fixed token reservation leaks for queued Git/check actions and empty commit payloads.
- Enforced daily action caps and monthly wallet limits in backend token capture/reserve paths.
- Added launch, deployment, smoke, observability, device, release, and beta readiness documentation.
- Added a reusable beta feedback intake template and synced Firestore schema docs with `opsMetrics` plus expanded wallet usage telemetry.
