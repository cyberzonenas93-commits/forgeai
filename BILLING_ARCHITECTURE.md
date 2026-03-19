# Billing Architecture

## Overview
Billing is abstracted so the app can support **Apple IAP**, **web billing**, or **dev/test grants** without changing business logic.

## Components
- **Product catalog**: Plans and token packs with product IDs (e.g. `com.forgeai.app.subscription.pro`, `com.forgeai.app.tokens.small`). Defined in `forge_economics_config.dart` and `economics-config.ts`.
- **Billing service interface**: `ForgeBillingService` (Dart) — `purchaseSubscription`, `purchaseTokenPack`, `restorePurchases`, `subscriptionState`, `isAvailable`.
- **Mock implementation**: `MockForgeBillingService` for development and when StoreKit is not configured; returns `notAvailable` for real purchases.

## Wallet and Ledger
- **Wallet**: Firestore `wallets/{uid}` — balance, reserved, monthlyLimit, monthlyUsed, planName, dailyActionCap.
- **Ledger**: `wallets/{uid}/usage` — each balance change with reason, amount, before/after balance, actionType, timestamps. Written atomically with wallet updates in backend transactions.

## Reservation Flow
1. Client or backend calls **reserve** (tokens held, ledger entry “reserved”).
2. On success: **capture** (balance and monthlyUsed updated, ledger “captured”).
3. On failure: **release** (reservation cleared, ledger “released”). No charge.

## What Is Not Implemented Yet
- Actual Apple StoreKit / RevenueCat (or similar) integration.
- Web checkout for token packs or subscriptions.
- Server-side receipt validation and subscription sync to Firestore (planId, expiresAt).

## Next Steps for Store Setup
1. Create subscription and consumable products in App Store Connect with the IDs in the catalog.
2. Implement an IAP-backed `ForgeBillingService` (e.g. `in_app_purchase` or RevenueCat).
3. Add a Cloud Function or backend job to validate receipts and update `wallets/{uid}` (planId, monthlyIncludedTokens, dailyActionCap) and optionally a `subscriptions` collection.
