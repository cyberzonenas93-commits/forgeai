# Firestore Schema

This schema is the product backbone for the mobile app and the contract-first backend.

## Collections

### `users/{uid}`
Profile and entitlement record for an authenticated user.
- `displayName`
- `email`
- `photoUrl`
- `authProviders`
- `isGuest`
- `createdAt`
- `updatedAt`
- `deletedAt`

### `users/{uid}/connections/{provider}`
User-visible provider connection status for GitHub or GitLab.
- `provider`
- `account`
- `scopeSummary`
- `status`
- `lastChecked`

### `users/{uid}/providerTokens/{provider}`
Backend-only provider access tokens captured from OAuth sign-in or manual token entry.
- `provider`
- `token`
- `tokenHint`
- `account`
- `scopeSummary`
- `source`
- `updatedAt`
- `lastValidatedAt`

### `repositories/{repoId}`
Connected repository metadata.
- `ownerId`
- `provider` (`github` | `gitlab`)
- `owner`
- `name`
- `fullName`
- `defaultBranch`
- `description`
- `htmlUrl`
- `remoteId`
- `branches`
- `isPrivate`
- `openPullRequests`
- `openMergeRequests`
- `filesCount`
- `syncStatus`
- `apiBaseUrl`
- `lastSyncedAt`
- `updatedAt`

### `repositories/{repoId}/files/{pathId}`
Tracked file metadata and editor state.
- `path`
- `type`
- `language`
- `size`
- `content`
- `contentPreview`
- `baseContent`
- `sha`
- `source`
- `loadedAt`
- `updatedAt`

### `changeRequests/{changeRequestId}`
AI-generated or manual staged changes awaiting review.
- `ownerId`
- `repoId`
- `filePath`
- `provider`
- `prompt`
- `changeKind`
- `summary`
- `status`
- `beforeContent`
- `afterContent`
- `diffPreview`
- `diffLines`
- `estimatedTokens`
- `riskNotes`
- `createdAt`
- `approvedAt`

### `gitActions/{actionId}`
Commit, branch, PR/MR, and merge activity records.
- `ownerId`
- `repoId`
- `actionType`
- `provider`
- `branchName`
- `sourceBranch`
- `baseBranch`
- `commitMessage`
- `prTitle`
- `prDescription`
- `pullRequestNumber`
- `mergeRequestId`
- `mergeMethod`
- `fileChanges`
- `approvalState`
- `executionState`
- `remoteId`
- `remoteUrl`
- `estimatedTokens`
- `errorMessage`
- `createdAt`
- `updatedAt`

### `checksRuns/{runId}`
CI/check execution records.
- `ownerId`
- `repoId`
- `provider`
- `actionType`
- `workflowName`
- `ref`
- `inputs`
- `status`
- `approvalState`
- `executionState`
- `logsUrl`
- `logs`
- `summary`
- `estimatedTokens`
- `createdAt`
- `updatedAt`

### `wallets/{uid}`
Token wallet and usage tracking.
- `balance`
- `reserved`
- `monthlyLimit`
- `monthlyUsed`
- `currency`
- `planName`
- `monthlyAllowance`
- `spentThisWeek`
- `nextReset`
- `currencySymbol`
- `updatedAt`

### `wallets/{uid}/usage/{usageId}`
Token ledger entries.
- `actionType`
- `amount`
- `costPreview`
- `provider`
- `model`
- `latencyMs`
- `estimatedProviderCostUsd`
- `actualProviderCostUsd`
- `estimatedMarginUsd`
- `refundPolicy`
- `dailyCap`
- `pricingVersion`
- `reason`
- `createdAt`

### `activity/{activityId}`
Unified audit log for user-visible actions.
- `ownerId`
- `kind`
- `subjectId`
- `message`
- `metadata`
- `createdAt`

### `opsMetrics/{metricId}`
Structured operational telemetry emitted by Cloud Functions for launch monitoring.
- `metricType`
- `severity`
- `provider`
- `ownerId`
- `repoId`
- `actionType`
- `status`
- `model`
- `latencyMs`
- `estimatedProviderCostUsd`
- `actualProviderCostUsd`
- `pricingVersion`
- `metadata`
- `createdAt`

## Access Pattern
- Users can read their own profile, wallet, repository state, and activity.
- Write paths should be restricted to authenticated owners or trusted backend functions.
- Sensitive actions such as deletion, merge, and token debit should be logged before or during execution.
