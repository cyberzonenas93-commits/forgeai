# Test IAP (Paywall → Purchase → Restore)

Run through the paywall and subscription flow on a device or simulator where in-app purchase is available.

## Prerequisites

- **Apple**: App Store Connect app and (for real purchases) **Sandbox** tester account. Optional: **StoreKit Configuration** file in Xcode for simulator testing without Sandbox.
- **Backend**: `APPLE_IAP_SHARED_SECRET` set and `syncPurchase` / `getSubscriptionState` deployed (see [PAYMENTS_SETUP.md](../PAYMENTS_SETUP.md)).

## 1. Set the IAP secret (one-time)

From the project root:

```bash
npm run setup:iap-secret
```

When prompted, paste your **App-Specific Shared Secret** from App Store Connect (App Information → App-Specific Shared Secret). If you already created the secret with an empty value, run the same command again and paste the real secret to add a new version. Then redeploy functions:

```bash
npm run deploy:functions -- --yes
```

## 2. Run the app

**iOS (simulator or device):**

A **StoreKit Configuration** file is already set up for the simulator:

- **File:** `ios/CodeCatalystAI.storekit` — defines Pro/Power subscriptions and token packs (same product IDs as the app).
- **Scheme:** The **Runner** scheme points at `CodeCatalystAI.storekit` (Edit Scheme → Run → Options → StoreKit Configuration). When you run from **Xcode**, the simulator will use this config so IAP works without a Sandbox account.

To run:

```bash
npm run run:app
# or: flutter run
# or: open ios/Runner.xcworkspace and run in Xcode (recommended for StoreKit testing)
```

Choose an **iOS** device or simulator.

- **For App Store screenshots / UI capture:** default debug runs now use mock billing (no Apple ID prompt), so you can open Wallet, Paywall, and Token screens quickly.
- **For real IAP testing in debug:** run with `--dart-define=FORGEAI_ENABLE_IAP_DEBUG=true`.
- **For simulator StoreKit testing:** open `ios/Runner.xcworkspace` in Xcode and run the `Runner` scheme (now wired to `ios/CodeCatalystAI.storekit`).
- **For real device sandbox testing:** use a Sandbox Apple ID when prompted.

**Android:** Use a device or emulator with Google Play; IAP is available when Play Billing is present.

## 3. Test flow

1. **Sign in** with an account that is **not** the allowlisted unlimited user (so limits apply).
2. Open **Wallet** (from Dashboard or Settings).
3. Tap **Upgrade** to open the paywall.
4. Tap **Upgrade to Pro** (or Power):
   - **Simulator with StoreKit**: Use the configured StoreKit transactions (no real payment).
   - **Real device**: Sign in with your **Sandbox** Apple ID when prompted and complete the purchase.
5. Expect:
   - Snackbar: “Purchase in progress…” or “Subscription updated.”
   - Wallet shows updated plan (e.g. Pro) and limits (e.g. 300 tokens/mo, 50 actions/day).
6. **Restore**: On the paywall, tap **Restore purchases**. Expect “Purchases restored” (or “No purchases to restore” if none).
7. **Token packs** (optional): From Wallet tap **Get tokens**, choose a pack, complete purchase; confirm balance increases.

## 4. Verify backend

- **Firestore**: `wallets/{your-uid}` should have `planId`, `planName`, `monthlyLimit`, `dailyActionCap`, `subscriptionExpiresAt` after a subscription purchase.
- **Cloud Functions**: Check logs for `syncPurchase` / `getSubscriptionState` if something fails.

## Troubleshooting

- **“In-app purchases are not available”**  
  Use a real device or a simulator with StoreKit configured; the app falls back to the mock otherwise.

- **“Invalid receipt”**  
  Ensure `APPLE_IAP_SHARED_SECRET` is set and matches App Store Connect. For Sandbox, the backend retries with the sandbox URL automatically (status 21007).

- **Products not found**  
  In App Store Connect, create the products with IDs in [PAYMENTS_SETUP.md](../PAYMENTS_SETUP.md) and wait for propagation (or use a StoreKit Configuration file in Xcode for simulator).
