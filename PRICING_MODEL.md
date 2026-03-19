# Pricing Model

## Why Action-Based Pricing
- Predictable cost for users (fixed token price per action type).
- Backend can route to cheaper or premium models while keeping user price constant.
- Aligns revenue with usage and supports margin targets (5x–8x on AI cost).

## Hybrid Model
1. **Subscription**: Monthly access + included token allocation (Free / Pro / Power).
2. **Token usage**: Every billable action (AI, git, checks) deducts tokens at a fixed rate per type.
3. **Token top-ups**: One-time packs for extra tokens; revenue on top of subscriptions.

## Apple IAP Impact
- Assume **30%** platform cut on in-app purchases.
- Display prices are gross; economics use **Apple net** (e.g. $14.99 → $10.49) for margin calculations.
- 15% small-business / year-2 rate documented separately where applicable.

## Centralized Config
- **Backend**: `functions/src/pricing.ts` (action rules, token value, cost assumptions), `functions/src/economics-config.ts` (plans, packs, model routing).
- **App**: `lib/src/core/config/forge_economics_config.dart` (display prices, plans, packs, action labels).
- **Tooling**: `config/monetization.json`, `config/launch-config.json` (token value, action floors).

All user-facing numbers must stay consistent with these sources.
