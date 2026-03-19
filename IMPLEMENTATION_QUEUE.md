# Implementation Queue

Last updated: 2026-03-19

## Monetization (completed)
- [x] Centralized pricing/economics config (config/monetization.json, functions pricing + economics-config, Dart forge_economics_config)
- [x] Action token costs: explain_code, fix_bug, generate_tests, refactor_code, deep_repo_analysis, ai_suggestion, git/check actions
- [x] Plan definitions (Free/Pro/Power) and top-up packs with Apple net assumptions
- [x] Wallet onboarding with free plan defaults (20 tokens, 10 daily cap)
- [x] Ledger: beforeBalance, afterBalance, beforeReserved, afterReserved in usage docs (atomic with wallet transaction)
- [x] Plan-based daily action cap enforcement in reserve path
- [x] Billable action types extended; token callables accept billable action type
- [x] Model routing (tier → provider model) in economics-config and AI call path
- [x] Billing service interface and mock implementation
- [x] Paywall screen (plan comparison, upgrade CTA, restore)
- [x] Token packs screen
- [x] Wallet screen: upgrade plan + get tokens CTAs, next refresh copy
- [x] Analytics: forge_paywall_viewed, forge_token_packs_viewed
- [x] Token economics simulator: subscription/top-up scenarios, margin validation
- [x] Docs: TOKEN_ECONOMICS, PRICING_MODEL, BILLING_ARCHITECTURE, APPLE_IAP_PLAN, REVENUE_SIMULATION

## Blocked by store / credentials
- [ ] Create subscription and consumable products in App Store Connect
- [ ] Implement Apple IAP–backed ForgeBillingService
- [ ] Server-side receipt validation and wallet/subscription sync

## Other (from LAUNCH_QUEUE)
See LAUNCH_QUEUE.md for auth, providers, TestFlight, and environment items.
