# Observability

## Implemented
- Firebase Analytics in Flutter
- Firebase Crashlytics in Flutter
- Cloud Functions structured metrics written to `opsMetrics`
- Wallet usage ledger written to `wallets/{uid}/usage`

## Flutter Signals
- `forge_app_boot`
- `forge_auth_state_changed`
- auth action success/failure events
- repository sync/connect/open/save events
- AI run events
- Git action events
- check action events

## Backend Signals
`functions/src/index.ts` writes `opsMetrics` for:
- provider configuration failures
- repository sync/load failures
- AI generation success/failure
- Git action success/failure
- check dispatch success/failure

## Revenue and Cost Observability
- **Backend**: Every reserve/capture/release writes to `wallets/{uid}/usage` with `estimatedProviderCostUsd`, `estimatedMarginUsd`, `refundPolicy`, `pricingVersion`, `model`, `latencyMs`, and `beforeBalance`/`afterBalance`.
- **opsMetrics**: AI, Git, and check operations log `actionType`, `chargedTokens`, `estimatedProviderCostUsd`, `estimatedMarginUsd`, `refundPolicy`, `dailyCap`, `pricingVersion` for revenue/cost and margin tracking.
- **Flutter**: `forge_paywall_viewed`, `forge_token_packs_viewed` for funnel analytics.

## Token Observability
Wallet usage rows now include:
- `estimatedProviderCostUsd`
- `actualProviderCostUsd`
- `estimatedMarginUsd`
- `refundPolicy`
- `dailyCap`
- `pricingVersion`
- `model`
- `latencyMs`

## Recommended Dashboards
- Crash-free sessions by app version
- Auth success/failure by provider
- Repository sync failures by provider
- AI latency and failure rate by provider/model
- Git action completion rate
- CI dispatch completion rate
- Token capture vs release counts
- Margin trend by action type

## Current Limitation
- AI provider cost is still assumption-based from configured token pricing, not invoice-backed provider billing export

## Launch Monitors
- Watch `opsMetrics` for `awaiting_provider_configuration`
- Watch `wallets/{uid}/usage` for unreleased reservations
- Watch Crashlytics for auth callback and editor crashes
