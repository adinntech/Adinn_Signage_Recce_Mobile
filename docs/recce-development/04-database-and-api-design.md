# 04 - Data model and design decisions

Routes, payloads, rules and errors: **09** (the one API reference). Backend behaviour: `D:\Projects\Signage\docs\16-recce-photo-review-workflow.md`. This file keeps what 09 does not: how the data is stored, why it is built this way, and how the Flutter app maps to the API.

## 1. Design decisions

| Decision | Why |
|---|---|
| One shop = **one document** (`RecceSubmission`, unique per `site`) with `photos[]`, `versions[]`, `reviews[]`, `reworks[]` embedded (since 2026-11-23) | One atomic update per workflow step; no cross-collection half-writes; delete project = delete shop documents |
| Every step is one update with a guard (`rev`, `status`, the `PENDING` review entry, `clientId` not stored yet) | Two reviewers, a double tap or a retry cannot both win |
| `versions[]` snapshots are immutable (photo ids, boards, installation, notes, `stages`, `sequential`) | V1 stays readable after V2; compare = V1 snapshot against V2 snapshot |
| Photo ids = embedded `_id`; clients only see photo ids, version numbers, review rows | Storage shape can change without an API change |
| Review mode is a config switch (`sequential`, default `false`) and is copied into each version | Operations and Client Servicing decide independently; old versions keep the rule they were submitted under |
| One physical board = one `mediaItems` entry; different size = new `key` | A rework can point at exactly one board (`6x4 -> 8x4` is `width 6 -> 8`) |
| Installation answers are tri-state, default `NOT_ASSESSED` | An unanswered question is never read as NO |
| GPS comes only from the device, per photo; doubtful data is kept and flagged | Reviewer decides; the shop's registered address is never substituted |
| Photo files are never overwritten: replace = new photo + `SUPERSEDED` old one; annotation = separate `edited` file | Full history per photo |
| API is the only security boundary (`mySite`, stage rights, project scope) | The mobile UI is not trusted |

## 2. Collections

**`RecceSubmission`** (one per shop)
- Shop level: `project`, `site` (unique), `assignee`, `channel` (VENDOR | IN_HOUSE), `vendor`, `status` (`IN_PROGRESS, SUBMITTED, UNDER_REVIEW, APPROVED, REWORK_REQUIRED, REJECTED`), `currentVersion`, `mediaItems[]`, `notes`, `installation`, `reviewers {OPS, CS}`, `priority`, `attempts`, `startedAt`, `submittedAt`, `finalApprovedAt`, `pendingStage`, `dueAt`, `rev`.
- `photos[]`: `category`, `mediaKey`, `caption`, `order`, `state` (`DRAFT, SUBMITTED, SUPERSEDED, REMOVED`), `original` (file), `edited` (file) + `annotations`, `capturedAt`, `lat`, `lng`, `gpsAccuracy`, `source`, `device`, `width`, `height`, `flags[]`, `uploadedBy`, `clientId`, `version`, `replaces`, `supersededBy`, `removedAt/By/Reason`.
- `versions[]`: `version`, `submittedBy/At`, `photos[]`, `added[]`, `removed[]`, `mediaItems[]`, `notes`, `installation`, `stages[]`, `sequential`, `dueAt`, `idempotencyKey`.
- `reviews[]` (unique per `versionNo` + `stage`): `decision` (`PENDING, APPROVED, REJECTED, REWORK, VOID`), `reviewer`, `reviewerRole`, `decidedAt`, `comment`, `checklist[]`, `override {by, reason}`, `history[]` (answers replaced by `change-decision`).
- `reworks[]`: `versionNo`, `stage`, `kind` (REWORK | ADDITIONAL), `instructions`, `items[]` (`type, category, mediaKey, photo, note, resolved, resolvedInVersion`), `status` (OPEN | RESOLVED | CLOSED), `requestedBy`.
- Size: at most `maxPhotos` (40) photos and a handful of versions per shop, far below 16 MB. Lists and dashboards read only the fields they need.

**Others:** `RecceConfig` (`stages`, `sequential`, `allowRetryAfterReject`, `slaHours`, `maxPhotos`, `requireGps`, `checklist`, `requiredPhotos`), `RecceThreadRead` (per shop and person: last read time), `AuditLog` (timeline, entity `RecceSubmission`, `meta` visibility ALL / REVIEW / ADMIN), Connect channel + messages (shop thread, `card` and `shop` fields), notifications.
Indexes: project, site (unique), assignee, vendor, status, pendingStage, dueAt, `(project, status)`. Everything is owned by the project cascade (`PROJECT_OWNED`); photo files are erased first by `removeProjectRecceFiles`. Data from before 2026-11-23 is not migrated: `npx tsx scripts/purge-legacy-recce.ts` (dry run) / `--apply`.

## 3. Names asked for versus names built

| Asked | Built |
|---|---|
| Status `RESUBMITTED` | V2 with `SUBMITTED` / `UNDER_REVIEW` (`version: 2`, `Shop Recce Resubmitted` card) |
| Status `COMPLETED` | `APPROVED` by every stage on the current version |
| `/projects/:p/assigned-shops` | `GET /recce/shops?projectId=` |
| `/recce/:id/audit-history` | `GET /recce/shops/:siteId/activity`, `/recce-review/submissions/:id/activity` |
| `/recce/:id/versions/compare` | `GET /recce/shops/:siteId/versions/compare?from=&to=` |

## 4. Flutter mapping (Project A: `lib/features/live_auth`, `lib/features/live_recce`, `lib/core/network`)

| Screen | Code -> call |
|---|---|
| Login, Register, Forgot, Change MPIN | `AuthRepository.login / vendorLogin / register / requestResetCode / confirmReset / changeOwnMpin` |
| Dashboard, Projects, Shops | `RecceApi.dashboard / shops` (projects = shops grouped by `projectId`) |
| Shop tabs (photos, boards, installation, review, chat) | `RecceApi.detail / start / saveDraft` |
| Capture + upload | `capture_flow` -> `UploadQueue` -> `RecceApi.uploadPhoto` (2 parallel, retry, saved on the phone) |
| Submit, rework sheet, versions, compare, approval history | `RecceApi.submit / versions / compare / photoHistory / activity` |
| Thread, notifications | `ChatController` (`messages / postMessage / messagesUnread`), `NotificationsController` (`notifications`) |
| Token handling | `DioClient` interceptor + `TokenManager` (single-flight refresh, rotating refresh token in `SessionStore`) |
