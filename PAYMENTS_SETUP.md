# Payments setup checklist

This doc lists what’s implemented and what you need to do to go live with in-app purchases.

## Implemented

- **Flutter**
  - `in_app_purchase` dependency and **IAPForgeBillingService** (load products, buy subscription, buy token pack, restore, sync with backend).
  - **ForgeHomeShell** uses IAP when available (real device/simulator with StoreKit/Play Billing), otherwise **MockForgeBillingService**.
  - Paywall and token packs UI; Upgrade and Restore wired to the billing service.
- **Backend (Cloud Functions)**
  - **getSubscriptionState** – returns `planId`, `productId`, `expiresAt`, `isActive` from `wallets/{uid}`.
  - **syncPurchase** – accepts `platform`, `productId`, `verificationData`, `source`; for **iOS** validates receipt with Apple (`verifyReceipt`), then updates wallet (subscription plan or token top-up); for **Android** applies plan/top-up (Play verification can be added later).
  - Subscriptions write `planId`, `planName`, `monthlyLimit`, `dailyActionCap`, `subscriptionProductId`, `subscriptionExpiresAt` to the wallet; token packs add tokens to `balance`.
- **Product catalog** (single source in code and backend):
  - Subscriptions: `com.forgeai.app.subscription.pro`, `com.forgeai.app.subscription.power`
  - Token packs: `com.forgeai.app.tokens.small`, `com.forgeai.app.tokens.medium`, `com.forgeai.app.tokens.large`

## What you need to do

### 1. App Store Connect (Apple)

**Step-by-step:** See **[docs/APP_STORE_CONNECT_IAP_SETUP.md](docs/APP_STORE_CONNECT_IAP_SETUP.md)** for the full walkthrough (shared secret, subscription group, Pro/Power subscriptions, token-pack consumables, Sandbox tester, backend secret, and real-device testing).

Quick steps:
1. Create **auto-renewable subscriptions** with the exact product IDs above (Pro $14.99/mo, Power $29.99/mo).
2. Create **consumables** for the three token packs with the IDs above and prices ($5.99, $14.99, $34.99).
3. In **App Store Connect → Your App → App Information → App-Specific Shared Secret**, create or copy the **shared secret**.
4. Create a **Sandbox** tester (Users and Access → Sandbox) for testing on a real device.
5. Run `npm run setup:iap-secret` and paste the secret; then deploy `syncPurchase`.

### 2. Backend secret (Apple)

Set the shared secret in your Firebase project so the backend can validate iOS receipts:

- **Option A (recommended)** – Firebase/Google Cloud Secret Manager:
  - Create a secret (e.g. `APPLE_IAP_SHARED_SECRET`) with the value of the App Store Connect shared secret.
  - In `functions`, configure the callable to use that secret (e.g. in `syncPurchase` we read `process.env.APPLE_IAP_SHARED_SECRET` or `APPLE_SHARED_SECRET`). If using Firebase Functions v2 with `defineSecret`, add the secret to the function and pass it into the handler.
- **Option B** – Environment / `.env` (only for local or if you use env in production):
  - Set `APPLE_IAP_SHARED_SECRET` (or `APPLE_SHARED_SECRET`) to the shared secret value.

Redeploy Cloud Functions after setting the secret.

### 3. Google Play (Android, optional)

- In **Google Play Console**, create the same **subscriptions** and **consumables** with matching product IDs (or your Android product IDs if you use different ones).
- For production, implement **server-side verification** for Android (Google Play Developer API) in **syncPurchase** and call it when `platform === 'android'` instead of trusting the client. Until then, the backend applies plan/top-up for Android without verification.

### 4. Test the flow

1. Run the app on a **real device** or a **simulator with StoreKit configured** (iOS) so `InAppPurchase.instance.isAvailable` is true.
2. Sign in with a non-allowlisted account (so limits apply).
3. Open **Wallet → Upgrade** (paywall), tap **Upgrade to Pro** (or Power). Complete the purchase with a **Sandbox** account.
4. Confirm the paywall shows “Purchase in progress” or “Subscription updated”, and that **Wallet** and backend show the updated plan (e.g. Pro) and limits.
5. Test **Restore purchases** after reinstalling or on another device with the same Apple ID.
6. Test **token packs** (Wallet → Get tokens) and confirm balance increases after purchase and after **syncPurchase**.

### 5. Compliance

- **Restore purchases** is available on the paywall (already implemented).
- Do not hardcode purchase flows in core logic; all purchase/restore goes through **ForgeBillingService** (already the case).
- Show clear pricing and terms where required by the stores; the paywall already shows plan names and prices from the catalog.

## Product IDs reference

| Type           | Product ID                            | Display price |
|----------------|---------------------------------------|---------------|
| Subscription   | com.forgeai.app.subscription.pro      | $14.99/mo     |
| Subscription   | com.forgeai.app.subscription.power    | $29.99/mo     |
| Consumable     | com.forgeai.app.tokens.small          | $5.99         |
| Consumable     | com.forgeai.app.tokens.medium         | $14.99        |
| Consumable     | com.forgeai.app.tokens.large          | $34.99        |

Set these **exactly** in App Store Connect (and in Play Console if you use the same IDs on Android).

## Troubleshooting

- **“In-app purchases are not available”** – IAP is only available on real devices or simulators with StoreKit/Play Billing; the app falls back to the mock and shows this message.
- **“Invalid receipt”** – Ensure `APPLE_IAP_SHARED_SECRET` (or `APPLE_SHARED_SECRET`) is set and correct, and that you’re using the **Sandbox** URL when testing (the backend uses status `21007` to retry with sandbox).
- **Products not found** – In App Store Connect, ensure the products are in **Ready to Submit** and associated with the app; allow some time for propagation.
