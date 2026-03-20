# Push notifications – what you need to do

Push is **fully implemented** in the app and Cloud Functions. Follow these steps so it works on your devices and in production.

---

## 1. Deploy Firestore rules

The app saves device tokens and notification preferences under your user document. Rules for these collections are in `firestore.rules`. Deploy them:

```bash
firebase deploy --only firestore:rules
```

---

## 2. Deploy Cloud Functions

The backend sends notifications when checks run, git actions complete, repos sync, AI-generated diffs are ready for review, and when token balance is low. Deploy the functions:

```bash
cd functions
npm run build
cd ..
firebase deploy --only functions
```

---

## 3. Android

- **No extra steps.** The app already has:
  - `POST_NOTIFICATIONS` permission
  - Default FCM channel `forgeai_default`
  - Firebase Messaging in the app

- On first run, the user will be asked for notification permission (Android 13+). They can also enable it later in **Settings > Notifications** in the app.

---

## 4. iOS – enable APNs in Firebase

For push to work on real devices (simulator cannot receive push), Firebase must talk to Apple Push Notification service (APNs).

1. **Open Firebase Console**  
   [console.firebase.google.com](https://console.firebase.google.com) → your project.

2. **Project Settings (gear)** → **Cloud Messaging** tab.

3. **Apple app configuration**  
   - Select your iOS app (bundle ID must match the app).
   - Under **APNs Authentication Key**:
     - Either upload an **APNs Auth Key** (.p8) from [Apple Developer](https://developer.apple.com/account/resources/authkeys/list) (recommended),  
     - Or upload an **APNs Certificate** (development and/or production).

4. **Get the key in Apple Developer (if using key):**
   - [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, Identifiers & Profiles** → **Keys**.
   - Create a key with **Apple Push Notifications service (APNs)** enabled.
   - Download the `.p8` file once (you can’t download it again).
   - In Firebase, upload this key and enter your **Key ID** and **Team ID** and **Bundle ID**.

5. **Entitlement for production**  
   - In Xcode, your app target’s **Signing & Capabilities** must include **Push Notifications**.
   - `ios/Runner/Runner.entitlements` already has `aps-environment: development`.  
   - For **App Store / TestFlight** builds, change that to `production` or add a production entitlement in Xcode.

---

## 5. Test push

1. **Run the app** on a real device (iOS or Android).
2. **Sign in** with a real account.
3. Open **Settings** → **Notifications** → tap **Enable push** and allow when the system prompts.
4. Leave the app (background or close it).
5. Trigger an action that sends a notification, for example:
   - **Sync a repository** (Repo tab → sync), or  
   - **Run a check** (e.g. from the Checks screen), or  
   - **Connect a new repository**.

You should get a notification. Tapping it should open the app and take you to the right tab (Repo, Checks, etc.).

---

## Summary checklist

- [ ] Deploy Firestore rules: `firebase deploy --only firestore:rules`
- [ ] Build and deploy functions: `cd functions && npm run build && cd .. && firebase deploy --only functions`
- [ ] (iOS) Upload APNs key or certificate in Firebase Console → Project Settings → Cloud Messaging
- [ ] (iOS production) Set `aps-environment` to `production` for release builds
- [ ] Test on a real device: sign in → enable push in Settings → trigger an action → confirm notification and tap

After that, push is fully operational.
