# App Store Connect — fully automated agent prompt (CodeCatalystAI)

Copy everything inside the **fenced block** below and give it to an AI agent (or autonomous browser agent) that is already signed into [App Store Connect](https://appstoreconnect.apple.com) and navigated to **My Apps → CodeCatalystAI** (or the app record matching bundle ID `com.angelonartey.forgeai`). The agent should work through every section until metadata, compliance, pricing, and IAP **except** attaching a **build** and **uploading screenshots / preview video**—those remain for the human.

**Live URLs (Firebase Hosting, deployed):**

| Field in App Store Connect | URL |
|----------------------------|-----|
| **Privacy Policy URL** | `https://forgeai-555ee.web.app/privacy` |
| **Support URL** | `https://forgeai-555ee.web.app/support` |
| **Marketing URL** (optional) | `https://forgeai-555ee.web.app` |

---

## Prompt for the agent (copy from here)

```
You are an App Store Connect setup specialist. You are logged into App Store Connect and viewing the iOS app record for CodeCatalystAI (bundle ID: com.angelonartey.forgeai). Your job is to complete every configurable field, questionnaire, and listing element required for submission, using only accurate information supplied below. Do not invent features, data practices, or integrations that are not listed here.

## Hard stop conditions — do not do these

1. Do NOT upload a build or select a build for the version (human handles Xcode / Transporter / CI).
2. Do NOT upload App Store screenshots, App Previews, or override screenshot requirements (human handles assets).
3. Do NOT change the Apple Developer Program membership, certificates, or provisioning profiles.
4. Do NOT create or delete the app record itself if it already exists; only edit this app.
5. When everything else below is done, STOP and report a checklist of what you completed and anything that required human confirmation (e.g. paid Applications Agreement, banking, tax forms).

## Product facts (use verbatim where appropriate)

- **App Store name (max 30 characters):** CodeCatalystAI
- **Subtitle (max 30 characters):** Git, edit & AI for developers
- **Bundle ID:** com.angelonartey.forgeai
- **Primary language:** English (U.S.)
- **SKU (if creating new app — otherwise leave):** forgeai-ios-001 (or any unique SKU not already used in the account)
- **User-facing description of the app:** CodeCatalystAI is a mobile developer companion for browsing Git repositories, reading and editing code, reviewing diffs, and preparing changes. Users sign in (guest, email, Google, Sign in with Apple, or GitHub), connect GitHub or GitHub, and work with their own repositories. AI-assisted suggestions are optional and always user-initiated; suggested changes are shown for review before any commit or pull/merge request. The app includes wallet and usage accounting for AI and automation actions, optional subscriptions and token packs (In-App Purchase), push notifications (optional), and CI workflow triggers where the user’s provider supports it. The app does not provide a terminal, shell, remote desktop, arbitrary command execution, or autonomous merge without user approval.

## URLs (required / optional)

- **Privacy Policy URL:** https://forgeai-555ee.web.app/privacy
- **Support URL:** https://forgeai-555ee.web.app/support
- **Marketing URL (optional):** https://forgeai-555ee.web.app

## Contact information (support)

- **Support email:** angelonartey@hotmail.com
- **Phone (App Store / support):** +233595494113 (E.164; display may add spaces)

Use the support email anywhere App Store Connect asks for a technical or support contact email. Use the phone for contact phone fields when required.

## Promotional text (max 170 characters; can be updated without a new binary in many cases)

Browse repos, edit code, and start AI agent runs on the go—then review diffs before you commit. Connect GitHub or GitHub, manage branches and PRs/MRs, and trigger CI checks. No terminal or shell.

## Description (App Store; max 4000 characters; review-safe, no misleading claims)

CodeCatalystAI helps developers work with Git repositories from their phone or tablet.

WHAT YOU CAN DO
• Sign in with guest access, email, Google, Sign in with Apple, or GitHub
• Connect GitHub or GitHub and browse your repositories
• Open files, edit code, and review changes with a clear diff view
• Start AI-assisted agent runs for your code; review output before applying
• Create branches, commit, and open pull requests or merge requests where your provider allows
• View and trigger CI workflows (for example GitHub Actions or GitHub CI) and see results
• Use a built-in wallet for usage accounting; optional subscriptions and token packs via In-App Purchase
• Optional push notifications for activity you choose to enable

WHAT THE APP IS NOT
• No terminal or command line
• No remote desktop or streaming of a full desktop environment
• No unrestricted execution of arbitrary shell commands
• No merging or pushing changes without your explicit review and confirmation where applicable

PRIVACY AND AI
• AI features send your prompts and relevant code to our backend and third-party AI providers to generate code changes. You control when this runs.
• Privacy Policy: https://forgeai-555ee.web.app/privacy
• Support: https://forgeai-555ee.web.app/support

Account deletion is available in the app (Settings → Account actions → Delete account), with re-authentication where required.

## Keywords (max 100 characters total including commas; no spaces after commas; do not repeat words from the app name)

git,github,github,code,editor,developer,repository,branch,commit,pullrequest,AI,diff,CI,workflow

(96 characters—fits the limit.)

## What’s New (for first release or version 1.0.0)

Initial release: connect GitHub or GitHub, browse and edit repository files, review diffs, user-initiated AI agent runs, branch and PR/MR workflows, optional CI triggers, wallet and In-App Purchases for plans and token packs, Sign in with Apple alongside other sign-in options, and in-app account deletion.

## Categories

- **Primary:** Developer Tools
- **Secondary (optional):** Productivity

## Age rating (questionnaire)

Complete Apple’s age rating questionnaire honestly. This app is a developer tool: it does not include built-in objectionable themes. Users may view source code and repository content from accounts they connect; treat any questions about user-generated content, unrestricted web access, or similar according to that reality (repository content comes from third-party hosts the user links). Do not understate content capabilities. If unsure on a specific question, choose the more conservative accurate answer.

## App Encryption / export compliance

The app uses standard HTTPS and platform cryptography for authentication and transport (e.g. Firebase, Git host APIs). Unless you have verified custom non-exempt encryption beyond that, answer consistent with **standard encryption only / exempt** per Apple’s definitions for this app. If App Store Connect asks whether the app uses encryption: follow Apple’s wording; do not claim proprietary encryption unless legal/engineering has confirmed it.

## Pricing and availability

- **Price:** Free (In-App Purchases for subscriptions and consumable token packs)
- **Availability:** All countries your account supports unless the owner restricts regions.

## In-App Purchases (create or complete metadata if missing)

Use these **exact Product IDs** (they must match the app and server configuration):

**Auto-renewable subscriptions** (same subscription group, e.g. “CodeCatalystAI Plans”):

| Product ID | Reference name | Suggested display name | Suggested description (store-facing, accurate) |
|------------|------------------|-------------------------|-----------------------------------------------|
| com.forgeai.app.subscription.pro | Pro | Pro | Monthly plan with included tokens and higher daily action limits for AI and workflows. |
| com.forgeai.app.subscription.power | Power | Power | Monthly plan with more included tokens and higher daily limits than Pro. |

**Consumables (token packs):**

| Product ID | Reference name | Suggested display name |
|------------|------------------|------------------------|
| com.forgeai.app.tokens.small | Tokens Small | Token pack (small) |
| com.forgeai.app.tokens.medium | Tokens Medium | Token pack (medium) |
| com.forgeai.app.tokens.large | Tokens Large | Token pack (large) |

Set pricing tiers per business decision (example USD references in internal docs: Pro $14.99, Power $29.99, small/medium/large packs $5.99 / $14.99 / $34.99—use App Store Connect pricing matrix, not hard-coded strings in the binary). Ensure each IAP is **Ready to Submit** and associated with this app. Do not rename Product IDs once live users depend on them.

## App Privacy (Privacy Nutrition Labels)

Declare data types that the app **actually** collects. Align with the published Privacy Policy (https://forgeai-555ee.web.app/privacy). Use the following as the source of truth for **types** and **purposes**; if a data type is not collected, do not declare it.

**Collected and linked to the user’s identity (typical):**

1. **Contact info** — Email address, Name (from account sign-up or OAuth profile).  
   **Purposes:** App functionality, account management, customer support.  
   **Not** used for tracking (unless you have separately enabled advertising/tracking SDKs for cross-app tracking—default assumption for this app: **no** tracking as defined by Apple).

2. **User content** — Other user content (repository metadata, file content the user opens or edits, prompts for AI).  
   **Purposes:** App functionality.  
   Processed on servers and sent to third-party AI providers only when the user requests AI features.

3. **Identifiers** — User ID (Firebase Auth UID or equivalent).  
   **Purposes:** App functionality, account management.

4. **Purchases** — In-app purchase history (subscriptions/consumables).  
   **Purposes:** App functionality, analytics (if you use purchase analytics internally—only declare what your implementation does).

5. **Usage data** — Product interaction (feature usage, in-app events).  
   **Purposes:** Analytics, app functionality, fraud prevention if applicable.

6. **Diagnostics** — Crash data, performance data (e.g. Firebase Crashlytics / similar).  
   **Purposes:** App functionality, analytics.

**Photos or videos (optional / limited):** The app may access the **photo library** only when the user attaches an image to a prompt (user-selected content). Declare **Photos or Videos** only if that access occurs in a way Apple considers collection; if the app only reads images the user explicitly selects and does not upload elsewhere beyond the stated AI/backend flow, follow Apple’s definitions for “collected” vs transient processing. When in doubt, declare narrowly but truthfully.

**Location:** Do not declare precise or coarse location unless the app or SDKs collect it for non-fraud purposes and you can verify.

**Tracking:** If the app does not use data for **tracking** as Apple defines it (e.g. linking with third-party data for ads), indicate **Data Not Used for Tracking** for the declared types. Update if advertising SDKs are added later.

**Third-party partners:** List Google (Firebase: Auth, Firestore, Analytics, Crashlytics, Cloud Functions as applicable), GitHub, GitHub, and AI providers (e.g. OpenAI) as appropriate in the privacy questionnaire’s partner section when prompted.

After editing labels, publish the summary so it matches the app version you will submit.

## Sign in with Apple

The app offers third-party sign-in (Google, GitHub) and **Sign in with Apple**, satisfying Guideline 4.8. No special App Store Connect toggle beyond accurate capability description; ensure reviewer notes mention it.

## Capabilities / background modes (informational)

Push notifications may be used for optional alerts. Photo library, microphone, and speech recognition are used only for attaching images or dictating prompts, with usage descriptions in Info.plist. Do not claim capabilities the binary does not request.

## Copyright and promotional fields

- **Copyright line:** Use the legal name from the Apple Developer account (individual or organization), e.g. “© 2026 [Legal name as on developer account].” Replace with the exact entity name shown in Membership details.
- **Trade name / app name** on store: CodeCatalystAI

## Review notes (paste into “App Review Information” / Notes for reviewer)

Use this text (adjust only if something is no longer true):

---
For App Review — CodeCatalystAI

Purpose: Mobile developer tool to browse GitHub/GitHub repositories, edit files, review diffs, and create branches, commits, and pull/merge requests. Optional user-initiated AI agent runs generate changes that are shown for review before commit or PR/MR. Optional CI workflow triggers and results. Wallet with In-App Purchase subscriptions and token packs.

Safety: No terminal, no shell, no remote desktop, no VM streaming, no arbitrary command execution, no autonomous merge without user approval.

Sign-in: Guest, email/password, Google, Sign in with Apple, GitHub. Account deletion: Settings → Account actions → Delete account (with re-auth where required).

Legal: Privacy Policy and Terms are linked in-app. Privacy Policy URL: https://forgeai-555ee.web.app/privacy — Support: https://forgeai-555ee.web.app/support

AI disclosure: AI-generated code changes are produced using third-party AI services; prompts and relevant code are sent when the user requests an agent run.

Contact for review: angelonartey@hotmail.com — +233595494113
---

## Demo account (if Apple requests sign-in credentials)

**Product demo (email/password):** See `APPLE_REVIEW_NOTES.md` and `docs/APP_STORE_REVIEWER_ACCOUNT.md` for `test@codecatalystai.com` (unlimited tokens for review; Auth user auto-deleted 30 days after creation). Paste the same table into App Store Connect if required.

For **IAP sandbox**, use a separate Sandbox Apple ID from App Store Connect → Users and Access → Sandbox (not the same as the in-app Firebase demo user).

## Content rights

Indicate that the app accesses user-connected third-party services (GitHub/GitHub). Users are responsible for content in their repositories under those services’ terms. The app does not sell user data.

## Final verification before you stop

1. App information: name, subtitle, categories, content rights, age rating complete.
2. Pricing and territories set.
3. Privacy Policy URL, Support URL, and contact email/phone saved.
4. App Privacy nutrition label published and consistent with policy.
5. IAP products exist with correct Product IDs and metadata; associated with app.
6. Version metadata: description, keywords, promotional text, what’s new—complete (screenshots and build explicitly skipped).
7. Export compliance / encryption questions answered.
8. Review notes and contact filled.

Output a markdown checklist to the user with ✅ / ⚠️ per item. For any ⚠️, explain what the human must do next.
```

## End of prompt

---

## Human follow-up (after the agent finishes)

1. Upload **screenshots** and optional **App Previews** for required device sizes.
2. Submit a **build** from Xcode or Transporter and attach it to the version.
3. Confirm **Paid Applications Agreement**, **banking**, and **tax** if IAP is live.
4. Double-check **App Privacy** after any SDK or analytics change.

## Deploying these pages again

Hosting root: `web/`. From repo root:

```bash
firebase deploy --only hosting
```

Privacy and support are also reachable as `/privacy` and `/support` (see `firebase.json` rewrites).
