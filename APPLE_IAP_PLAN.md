# Apple IAP Plan

## Product Catalog (production)

| Type | Product ID | Display price | Apple net (30%) |
|------|------------|---------------|-----------------|
| Subscription Pro | com.forgeai.app.subscription.pro | $14.99/mo | $10.49 |
| Subscription Power | com.forgeai.app.subscription.power | $29.99/mo | $20.99 |
| Consumable small | com.forgeai.app.tokens.small | **$5.99** | **$4.19** |
| Consumable medium | com.forgeai.app.tokens.medium | **$14.99** | **$10.49** |
| Consumable large | com.forgeai.app.tokens.large | **$34.99** | **$24.49** |

Set these exactly in App Store Connect. Source: `config/monetization.json`, `forge_economics_config.dart`.

## Assumptions
- **Worst case**: 30% Apple cut on all IAP.
- **Small business / year-2**: 15% — document separately for margin sensitivity.

## Implementation Status
- **Done**: Catalog in code, billing abstraction, paywall and token pack UI, mock billing service.
- **Blocked**: No StoreKit product setup or credentials in repo; no live purchase flow.

## Manual Steps to Go Live
1. In App Store Connect, create **auto-renewable subscriptions** for Pro and Power with the IDs above.
2. Create **consumables** for token packs (small / medium / large).
3. Add StoreKit configuration or server-side product list; implement `ForgeBillingService` using `in_app_purchase` or a provider (e.g. RevenueCat).
4. Implement server-side receipt validation and map subscription state to wallet (planId, monthlyIncludedTokens, dailyActionCap); optionally sync to Firestore.
5. Test with sandbox accounts and verify paywall → purchase → wallet update flow.

## Compliance
- Do not hardcode purchase flows in core business logic; keep billing behind `ForgeBillingService`.
- Show clear pricing and restore-purchases option on paywall (implemented in `PaywallScreen`).
