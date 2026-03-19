# ForgeAI — App Store Review Readiness Analysis

This document summarizes the chances of passing App Store review based on a full codebase and compliance review. It maps to Apple’s **App Store Review Guidelines** and common rejection reasons.

---

## Executive Summary

| Verdict | **Moderate–high risk without fixes** |
|--------|--------------------------------------|
| **Strengths** | Clear purpose, strong safety story, in-app account deletion with re-auth, Sign in with Apple, guest mode, no terminal/shell. |
| **Blockers / high risk** | No in-app Privacy Policy or Terms links (Guideline 5.1.1), no AI/third-party disclaimers, incomplete data deletion (Firestore not cleaned on account delete). |
| **Medium risk** | Missing Photo Library usage description (image picker), export compliance not declared, reviewer demo path (Git/AI) needs working backend. |
| **Recommendation** | Address the blockers and medium items below, then submit with `APPLE_REVIEW_NOTES.md` in App Store Connect notes. |

---

## 1. Guideline 5.1.1 — Privacy & Data (High impact)

**Requirement:** Apps that collect user or device data must have a privacy policy and, where relevant, explain data use. Links must be visible in the app (or in the App Store listing and easily discoverable).

**Current state:**
- **No in-app link to a Privacy Policy or Terms of Service.** Searches across `lib/` show no URLs or copy for “privacy”, “terms”, or “policy”.
- Data collection in place: Firebase (Auth, Firestore, Analytics, Crashlytics), custom telemetry (e.g. `forge_telemetry.dart` with auth provider, `is_guest`), and user content (code, prompts) sent to backend/AI providers.
- No in-app explanation of what is collected, how it’s used, or who it’s shared with (e.g. AI providers).

**Risk:** **High** — Rejection under 5.1.1 is common when there is no visible privacy policy.

**Recommendations:**
1. Publish a Privacy Policy (and Terms of Service if you impose contractual terms).
2. Add a “Privacy” (and optionally “Terms”) link in-app — e.g. on the auth/sign-up screen and in Settings — that opens the policy URL in a browser or in-app web view.
3. In the policy, cover: account data, repo/code and prompts, AI provider usage (OpenAI/Anthropic/etc.), Firebase/Analytics/Crashlytics, and retention/deletion.

---

## 2. Guideline 5.1.1(v) — Account deletion (Medium–high impact)

**Requirement:** Apps that support account creation must allow users to delete their account from within the app.

**Current state:**
- **Account deletion is implemented in-app:** Settings → “Delete account” → `DeleteAccountScreen`.
- Flow: re-authenticate (for non-guest), then type “DELETE” to confirm; delete is only enabled when the phrase matches and (for non-guest) re-auth is within the last 10 minutes.
- Backend: client calls Firebase Auth `user.delete()` then signs out. There is **no** Cloud Function or other server-side logic that deletes or anonymizes the user’s Firestore data (e.g. `users`, `wallets`, repositories, activity). So Auth identity is removed, but Firestore documents can remain.

**Risk:** **Medium–high** — Apple has been strict about “full” account deletion. Orphaned Firestore data could be seen as incomplete deletion.

**Recommendations:**
1. Add an Auth `onDelete` (or equivalent) trigger that deletes or anonymizes the user’s Firestore documents (users, wallets, repos, activity, etc.) when the Auth user is deleted.
2. Alternatively, implement a callable (or secure endpoint) that the client calls before/after `user.delete()` to perform the same server-side wipe, and document in the privacy policy that deletion removes account and associated app data.

---

## 3. Guideline 4.8 — Sign in with Apple (Compliant)

**Requirement:** If the app offers third-party sign-in (e.g. Google, GitHub), it must also offer Sign in with Apple.

**Current state:** Auth entry “Quick access” includes **Guest**, **Google**, **Apple**, and **GitHub**. Sign in with Apple is present and parity is satisfied.

**Risk:** **Low** — No change needed for 4.8.

---

## 4. Guideline 2.1 — App completeness & safety (Strong, with caveats)

**Requirement:** App must work as described, not crash, and not facilitate harmful or policy-violating behavior.

**Current state:**
- **Purpose and safety are well documented:** `APPLE_REVIEW_NOTES.md` clearly states no terminal, shell, remote desktop, VM, or autonomous merge; AI and Git actions are user-triggered and approval-gated.
- App is a substantive mobile Git + AI workflow tool (repos, editor, diffs, commits, PR/MR, CI checks, wallet), not a thin wrapper.
- Reviewer path: reviewer will need to sign in (guest is available), connect a repo (GitHub/GitLab), and use AI/Git features. That depends on backend (Firebase, provider keys) and OAuth being correctly configured.

**Risk:** **Low** if backend and auth are working; **medium** if reviewer hits broken sign-in, “no backend” errors, or empty states with no way to demo value.

**Recommendations:**
1. Paste `APPLE_REVIEW_NOTES.md` (or the “Reviewer copy” section) into the “Notes for reviewer” in App Store Connect.
2. Ensure the demo account / test repo and backend (OpenAI or other provider) are live and stable during review.
3. Optionally provide a test GitHub/GitLab account and repo in the notes so the reviewer can exercise the full flow.

---

## 5. Guideline 5.1.2 — Data use & third-party disclosure (AI / providers)

**Requirement:** Users should be informed when data is shared with third parties (e.g. AI providers). Apple also expects clarity around AI-generated content.

**Current state:**
- AI is used for code suggestions; backend uses OpenAI (and optionally Anthropic/Gemini). User code and prompts are sent to these providers.
- **No in-app disclaimer or disclosure** that content is sent to third-party AI services or that output may be AI-generated.

**Risk:** **Medium** — Rejection or request for clarification if reviewers or policy interpret this as undisclosed third-party data sharing or AI content.

**Recommendations:**
1. Add a short in-app disclosure (e.g. on first use of AI, or in Settings/About): e.g. “Suggestions are generated by third-party AI services. Your code and prompts are sent to these services to provide results.”
2. Reference AI and third-party services in the Privacy Policy (who they are, what data is sent, link to their policies if appropriate).
3. If you surface AI-generated content as “AI-generated” in the UI, that aligns with current expectations.

---

## 6. Permission usage descriptions (Info.plist)

**Requirement:** Every permission (camera, microphone, photo library, speech recognition, etc.) must have a usage description string in `Info.plist`, or the app can be rejected.

**Current state:**
- **Present:** `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` (for voice/dictation).
- **Missing:** The app uses `ImagePicker` with `ImageSource.gallery` in `lib/src/features/ask/ask_screen.dart`, but there is **no** `NSPhotoLibraryUsageDescription` (or `NSCameraUsageDescription` if camera is ever used) in `ios/Runner/Info.plist`. On first gallery access, the system may prompt, but Apple often expects the key to be present.

**Risk:** **Medium** — Missing usage description can lead to rejection or follow-up.

**Recommendation:** Add to `ios/Runner/Info.plist`:
- `NSPhotoLibraryUsageDescription` — e.g. “ForgeAI uses the photo library so you can attach images to prompts.”
- `NSCameraUsageDescription` only if you use the camera for image capture elsewhere.

---

## 7. Export compliance (Encryption)

**Requirement:** If the app uses encryption beyond standard HTTPS/toolkit crypto, you may need to declare export compliance in App Store Connect and/or in Info.plist (`ITSAppUsesNonExemptEncryption`).

**Current state:** No `ITSAppUsesNonExemptEncryption` key was found in `ios/Runner/Info.plist`. The app uses HTTPS, Firebase, and Cloud Functions; typically this is considered exempt (standard encryption for authentication/transport). Third-party SDKs (e.g. gRPC, Firebase) may include crypto but are usually covered under “exempt” when used for standard purposes.

**Risk:** **Low** — Often you can answer “No” to using non-exempt encryption in App Store Connect. If Apple or your legal team says otherwise, add the key and/or the export compliance documentation.

**Recommendation:** In App Store Connect, answer the export compliance question according to your actual use (commonly “No” for apps that only use standard HTTPS and auth). If you add custom crypto later, re-evaluate and add `ITSAppUsesNonExemptEncryption` if needed.

---

## 8. Other checklist items (Release / operational)

From `RELEASE_CHECKLIST.md`:
- iOS sim build still unchecked; several auth/provider and native release items (e.g. real `key.properties`, physical device validation) are unchecked.
- Firebase Auth providers (Anonymous, Email, Google, Apple, GitHub) and OAuth callbacks must be correctly set for the build you submit.

**Risk:** **Medium** — Submitting before these are done can lead to “app doesn’t work” or “login broken” rejections.

**Recommendation:** Complete the release checklist (at least for the iOS path and the auth methods you expose) and run a full sign-in + repo + AI flow on a real device before submission.

---

## 9. Summary: What to fix before submission

| Priority | Item | Action |
|----------|------|--------|
| **P0** | Privacy Policy & Terms | Publish policies and add in-app links (auth + Settings). |
| **P0** | Account deletion | Extend deletion to Firestore (onDelete trigger or callable) and document in policy. |
| **P1** | AI / third-party disclosure | Add in-app disclaimer and document in Privacy Policy. |
| **P1** | Photo Library | Add `NSPhotoLibraryUsageDescription` to `Info.plist`. |
| **P2** | Reviewer experience | Paste reviewer notes in App Store Connect; ensure backend and test account work. |
| **P2** | Export compliance | Confirm and answer in App Store Connect; add Info.plist key if required. |
| **P2** | Release checklist | Complete iOS and auth-related items and validate on device. |

---

## 10. Chances of passing after fixes

- **As-is:** Chances are **low–moderate** — missing privacy/terms and incomplete deletion are frequent rejection reasons; missing usage description and lack of AI disclosure add risk.
- **After P0 + P1 fixes:** Chances are **good** — you address the main policy and data-handling expectations and permission requirements.
- **After full checklist + reviewer notes:** Chances are **high** — you align with guidelines 2.1, 4.8, 5.1.1, 5.1.2, and permission/export expectations, and give review a clear, working path to approve the app.

---

*Generated from codebase and doc review. Re-check Apple’s current guidelines and your legal requirements before submission.*
