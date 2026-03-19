# App Store reviewer test account

## Credentials (paste into App Store Connect → App Review Information)

| Field | Value |
| --- | --- |
| Email | `test@codecatalystai.com` |
| Password | `M463/1i45a` |

Sign in with **Email / password** inside the app (Firebase Email/Password provider must be enabled).

## Backend behavior

- **Tokens:** The address `test@codecatalystai.com` is allowlisted in Cloud Functions for the same **unlimited wallet** path as internal test accounts (`unlimitedWalletDocument` in `functions/src/index.ts`). Reviewers can run AI and billable actions without hitting normal free-tier caps.
- **Auto-delete:** A scheduled function `purgeExpiredAppStoreReviewerTestAccounts` runs daily and **deletes the Firebase Auth user** whose email is exactly `test@codecatalystai.com` when the account is **older than 30 days** (by Auth `creationTime`). That deletion runs the existing `deleteUserDataOnAuthDelete` hook and clears Firestore data for that UID.
- **Firestore markers:** On first sign-up, `syncUserProfile` sets `appStoreReviewerTestAccount` and `appStoreReviewerTestExpiresAt` on `users/{uid}` for operations/debugging. Purge decisions use **Auth email + creation time**, not client-editable fields.

## One-time setup (project owner)

1. Firebase Console → **Authentication** → **Users** → **Add user** with the email and password above (or the password you intend to share with Apple—then update this doc and `APPLE_REVIEW_NOTES.md`).
2. Deploy functions so allowlist + scheduler are live:  
   `firebase deploy --only functions:syncUserProfile,functions:purgeExpiredAppStoreReviewerTestAccounts,functions:deleteUserDataOnAuthDelete`  
   (or full `functions` deploy).

## After review / security hygiene

- Rotate the password in Firebase and update App Store Connect + this repo if you keep credentials in git.
- If the scheduled job removed the user, add a **new** Auth user with the same email to reuse the address (creation time resets the 30-day window).
