# App Store Connect: IAP setup for real devices

Follow this in order. Use the exact **Product ID** and **Reference Name** values so the app and backend stay in sync.

---

## Prerequisites

- Apple Developer account (enrolled).
- Your app created in App Store Connect (e.g. **CodeCatalystAI** as the App Store name; bundle ID `com.angelonartey.forgeai` or whatever you use).

---

## 1. App-Specific Shared Secret (for backend receipt validation)

1. Go to [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → select your app (e.g. CodeCatalystAI).
2. In the left sidebar, open **App Information** (under **General**).
3. Scroll to **App-Specific Shared Secret**.
4. Click **Generate** (or **Manage** if one exists) and copy the secret. You’ll use it in step 6.
5. Keep it safe; you’ll paste it when running `npm run setup:iap-secret`.

---

## 2. Subscription group and subscriptions

1. In App Store Connect, with your app selected, go to **Features** → **In-App Purchases** (or **Subscriptions** in older UI).
2. Click **+** or **Create** to add a **Subscription Group**.
   - **Reference Name:** `CodeCatalystAI Plans` (or any internal label; product IDs must still match the table below)
   - Create the group.

3. **Add first subscription (Pro):**
   - In the group, click **+** to add a subscription.
   - **Reference Name:** `Pro`
   - **Product ID:** `com.forgeai.app.subscription.pro` (must match exactly).
   - **Subscription Duration:** 1 month.
   - Add **Subscription Prices**: e.g. **$14.99** (or your tier).
   - Add **Display Name** and **Description** (e.g. “Pro” / “300 tokens/month, 50 actions/day”).
   - Save. Status should move toward **Ready to Submit**.

4. **Add second subscription (Power):**
   - In the same group, add another subscription.
   - **Reference Name:** `Power`
   - **Product ID:** `com.forgeai.app.subscription.power`
   - **Subscription Duration:** 1 month.
   - **Subscription Prices:** e.g. **$29.99**.
   - Add display name and description. Save.

---

## 3. Consumables (token packs)

1. In **In-App Purchases**, go to **Consumables** (or create consumable products).
2. **Add consumable 1:**
   - **Reference Name:** `Tokens Small`
   - **Product ID:** `com.forgeai.app.tokens.small`
   - **Price:** $5.99 (or equivalent tier).
   - Save.

3. **Add consumable 2:**
   - **Reference Name:** `Tokens Medium`
   - **Product ID:** `com.forgeai.app.tokens.medium`
   - **Price:** $14.99.
   - Save.

4. **Add consumable 3:**
   - **Reference Name:** `Tokens Large`
   - **Product ID:** `com.forgeai.app.tokens.large`
   - **Price:** $34.99.
   - Save.

Ensure all five products (2 subscriptions + 3 consumables) are in **Ready to Submit** and associated with your app.

---

## 4. Sandbox tester (for testing on real device)

1. App Store Connect → **Users and Access** (top-right account menu).
2. Open **Sandbox** (under **Sandbox** in the sidebar, or **Testers** → **Sandbox Testers**).
3. Click **+** to add a tester.
   - **First / Last Name:** e.g. Test User
   - **Email:** use a **new** email that is not a real Apple ID (e.g. `forgeai.sandbox.1@gmail.com` or a unique address you control).
   - **Password:** choose a password (Sandbox only).
   - **Country or Region:** e.g. United States.
4. Save. Use this account only for Sandbox; do not use a real Apple ID here.

---

## 5. Set the shared secret in your project (backend)

From your **project root**:

```bash
npm run setup:iap-secret
```

When prompted, paste the **App-Specific Shared Secret** from step 1 and press Enter.

Then redeploy the function that validates receipts:

```bash
npx firebase deploy --only functions:syncPurchase
```

(Or deploy all functions if you prefer.)

---

## 6. Test on a real device

1. **On the iPhone/iPad:**
   - **Settings → App Store** (or **App Store → account**) and sign in to **Sandbox Account** with the Sandbox tester from step 4.  
   - Or leave it unsigned; when you buy in the app, iOS will prompt for a Sandbox Apple ID.

2. **Install the app** on the device (e.g. run from Xcode or `flutter run` with the device selected).

3. **In the app:**
   - Sign in with a **non-allowlisted** account (so limits apply).
   - Open **Wallet** → **Upgrade**.
   - Tap **Upgrade to Pro** (or Power) and complete the purchase when iOS prompts (use the Sandbox account).
   - Confirm you see “Purchase in progress” or “Subscription updated” and that the wallet shows the new plan/limits.
   - Tap **Restore purchases** and confirm behavior.
   - Optionally buy a token pack (Wallet → Get tokens) and confirm balance increases.

4. **Backend:** In Firestore, check `wallets/<your-uid>` for `planId`, `planName`, `subscriptionExpiresAt` after a subscription purchase.

---

## Quick reference: product IDs and prices

| Type         | Product ID                             | Price   |
|-------------|----------------------------------------|---------|
| Subscription| com.forgeai.app.subscription.pro       | $14.99/mo |
| Subscription| com.forgeai.app.subscription.power      | $29.99/mo |
| Consumable  | com.forgeai.app.tokens.small           | $5.99   |
| Consumable  | com.forgeai.app.tokens.medium          | $14.99  |
| Consumable  | com.forgeai.app.tokens.large           | $34.99  |

These must match exactly what’s in the app and in `ios/CodeCatalystAI.storekit` (simulator).
