# 08 - Milestone 3 API payloads (shop thread, dashboards, notifications)

Base `{API_BASE_URL}` = `/api/v1`, Bearer token on every call. Success envelope is `{ "success": true, "data": ..., "meta": ... }` (`meta` only when there is one). Error envelope is `{ "success": false, "error": { "code": "...", "message": "...", "details": [...] } }`. All changes are additive: calls that worked before return the same data.

Scenario ids: shop `siteId = 67f0...a1`, `submissionId = 6801...b2`, project `6700...01`.

## 1. Shop thread

Field routes (login role VENDOR or RECCE_EXECUTIVE, own shops only) and the reviewer twins share one shape.

| Purpose | Field app | Reviewer / web |
|---|---|---|
| list | `GET /recce/shops/:siteId/messages` | `GET /recce-review/submissions/:submissionId/messages` |
| post | `POST /recce/shops/:siteId/messages` | `POST /recce-review/submissions/:submissionId/messages` |
| unread | `GET /recce/shops/:siteId/messages/unread` | `GET /recce-review/submissions/:submissionId/messages/unread` |
| mark read | `POST /recce/shops/:siteId/messages/read` | `POST /recce-review/submissions/:submissionId/messages/read` |

### 1.1 List

No query = the original reply: the last 100 messages, **oldest first**, no `meta`.
With `?limit=` (1-100) and / or `?before=` = a page, **newest first**.
`before` is a message id or an ISO time; only older messages come back. Pass `meta.nextBefore` as the next `before`; `null` means nothing older.

`GET /recce/shops/67f0...a1/messages?limit=2`
```json
{ "success": true,
  "data": [
    { "id": "6810...c5", "channel": "6801...d1", "author": { "id": "66f...01", "name": "Siva Creations", "role": "VENDOR" },
      "body": "Board is faded, photo attached", "parent": null, "mentions": [],
      "attachments": [ { "fileId": "6810...f1", "name": "lane.jpg", "size": 182044, "mimeType": "image/jpeg", "kind": "image", "voice": false, "durationSec": null, "peaks": [],
                          "url": "https://.../signed", "expiresAt": "2026-11-21T10:30:00.000Z" } ],
      "reactions": [], "card": null, "shop": "67f0...a1",
      "refs": [ { "type": "PHOTO", "id": "6800...e1" }, { "type": "BOARD", "id": "b1" }, { "type": "VERSION", "id": "2" } ],
      "replyCount": 0, "lastReplyAt": null, "edited": false, "deleted": false, "deletedAt": null, "pinned": false, "createdAt": "2026-11-21T10:15:00.000Z" },
    { "id": "6810...c4", "author": { "id": "66f...09", "name": "Arvind K.", "role": "OPERATIONS" }, "body": "", "attachments": [], "refs": [ { "type": "PHOTO", "id": "6800...e1" }, { "type": "VERSION", "id": "1" } ],
      "card": { "title": "Recce Review Update", "tone": "warn", "path": "/recce-review/6801...b2",
                "lines": [ { "label": "Shop", "value": "Shop 1" }, { "label": "Decision", "value": "Rework required" }, { "label": "Reviewer", "value": "Arvind K. (Recce Operations)" },
                           { "label": "Rework items", "value": "Full Shop Front View (Blurry)" }, { "label": "Comments", "value": "Front view is blurry, please retake it" } ] },
      "createdAt": "2026-11-21T10:10:00.000Z", "...": "same fields as above" } ],
  "meta": { "limit": 2, "hasMore": true, "nextBefore": "6810...c4" } }
```
`attachments[].url` is a short-lived private link (see `expiresAt`); ask the list again for a fresh one. `card` is set on system messages (see 1.5) and is `null` on people's messages. A message about nothing in particular has `"refs": []`.

### 1.2 Post (text, refs, one image)

JSON:
```json
POST /recce/shops/67f0...a1/messages
{ "body": "About this photo", "refs": [ { "type": "PHOTO", "id": "6800...e1" }, { "type": "BOARD", "id": "b1" }, { "type": "VERSION", "id": "2" } ] }
```
Multipart (text plus one image): fields `body`, `refs` (a **JSON string**) and file field **`file`** (one image: same types, size limit and content check as shop photos).
```
POST /recce/shops/67f0...a1/messages        Content-Type: multipart/form-data
  body = "Photo of the lane"
  refs = [{"type":"BOARD","id":"b1"}]
  file = lane.jpg
```
Response `201`: the created message in the shape of 1.1 (`{ "success": true, "data": { ...message } }`).

Rules:
- A message needs text or an image (`422 VALIDATION_ERROR` otherwise). `body` max 2000 characters. `refs` max 10; duplicates are dropped.
- `refs[].type` is `PHOTO` (a photo id of this shop's recce record; reviewers cannot point at drafts), `BOARD` (a media item `key` of this shop: current, from an earlier version, or the seeded board `m1` before the visit starts) or `VERSION` (a version number that was really submitted, as text). A wrong type is `422`; a ref that does not exist in THIS shop is `400 BAD_REQUEST` and nothing is stored (not even the image).
- A document, video or other non-image file is `400`; a file over the image size limit is `413`.
- The image is filed under the project (`Connect/<client>/<project code>/...`), so deleting the project erases it.
- A closed / cancelled project refuses new messages with `409`.
- The other side gets a notification (`kind` `RECCE_MESSAGE`, see section 5); the sender never does.

### 1.3 Unread

`GET /recce/shops/:siteId/messages/unread`
```json
{ "success": true, "data": { "unread": 3 } }
```
Counts messages written by other people after the moment this person last marked the thread read (everything, if they never did). Own messages never count.

### 1.4 Mark read

`POST /recce/shops/:siteId/messages/read` (no body; safe to repeat)
```json
{ "success": true, "data": { "ok": true, "unread": 0 } }
```
It also marks this person's unread `RECCE_MESSAGE` notifications of this shop as read.

### 1.5 System cards in the thread

Posted once each (an event key makes a retry harmless), oldest first, with `refs` the app can open:

| Event | `card.title` | Decision line (`card.lines`) | `refs` |
|---|---|---|---|
| Version submitted | `Shop Recce Submitted` / `Shop Recce Resubmitted` (v2+) | - | `VERSION n` |
| A stage approved | `Recce Review Update` | `Recce Operations approved` / `Client Servicing approved` | `VERSION n` |
| Rework / more photos asked | `Recce Review Update` | `Rework required` / `Additional photos requested`, plus a `Rework items` / `Needed` line (e.g. `Full Shop Front View`) | `VERSION n`, `PHOTO id` per photo, `BOARD key` |
| Both stages approved | `Recce Review Update` | `Final approval` | `VERSION n` |
| Rejected / Admin override | `Recce Review Update` | `Rejected` / `Admin override: approved` | `VERSION n` |
| Hand-over to the next stage (sequential review only) | `Client Servicing Review Due` | - | `VERSION n` |
| Shop reopened | `Shop Reopened` | `Reason`, `Previous status` lines | `VERSION n` |

### 1.6 Who can read

A shop of another vendor / another login: `404` on all four routes (field). Reviewers: only projects they review (Operations: assigned projects, Client Servicing: their orders, Admin / Management: all), otherwise `404`. History is kept per shop, not per person: when a shop moves to another vendor the new vendor sees the whole thread and the old one gets `404`.

## 2. Field dashboard

`GET /recce/dashboard` (VENDOR / RECCE_EXECUTIVE; only the shops given to this login, projects not cancelled / lost)
```json
{ "success": true, "data": {
  "assignedProjects": 2, "assignedShops": 3,
  "started": 1, "submitted": 1, "underReview": 0, "approved": 1, "rework": 0,
  "completed": 1, "pending": 2,
  "avgCompletionHours": 26.4, "reworkCount": 0, "reworkPercent": 0,
  "projects": [
    { "projectId": "6700...01", "projectCode": "P-M3",  "projectName": "Recce M3",   "assigned": 2, "started": 1, "submitted": 1, "approved": 1, "rework": 0, "pending": 1 },
    { "projectId": "6700...02", "projectCode": "P-M3B", "projectName": "Recce M3 B", "assigned": 1, "started": 0, "submitted": 0, "approved": 0, "rework": 0, "pending": 1 } ] } }
```
Definitions (same on the staff screen):
- `started` shops with a recce record (visit started). `submitted` shops submitted at least once. `underReview` waiting for a reviewer now (`SUBMITTED` / `UNDER_REVIEW`). `approved` status `APPROVED`. `rework` status `REWORK_REQUIRED` now.
- `completed` = **APPROVED by every required stage on the current version** (status `APPROVED` and an approved review row for each stage of that version). One stage approving is not completed; a V1 approval never counts for V2.
- `pending` = assigned shops not completed (not started, draft, under review, rework, rejected).
- `reworkCount` = shops that ever had a rework / more-photos request (each shop once). `reworkPercent` = `reworkCount / submitted x 100`, one decimal, `0` when nothing was submitted.
- `avgCompletionHours` = mean of (`finalApprovedAt` - `startedAt`) over completed shops, one decimal, `null` when there is none.
Others get `403`; no token `401`.

## 3. Staff performance

`GET /recce-review/performance?projectId=&from=&to=` (same visibility as `/progress`: Operations / Client Servicing only their projects, Admin / Management all; vendor, in-house recce login and other roles `403`; a project outside your scope `404`; `from` after `to` `422`).
`from` / `to` (date or ISO time) keep the shops whose recce was started in that range.
```json
{ "success": true, "data": {
  "filters": { "projectId": null, "from": null, "to": null },
  "totals":  { "started": 5, "submitted": 3, "underReview": 0, "approved": 2, "rework": 0, "completed": 2, "pending": 3, "reworkCount": 1, "reworkPercent": 33.3, "avgCompletionHours": 12.5 },
  "inHouse": { "started": 2, "submitted": 1, "underReview": 0, "approved": 1, "rework": 0, "completed": 1, "pending": 1, "reworkCount": 0, "reworkPercent": 0, "avgCompletionHours": 3.1 },
  "vendor":  { "started": 3, "submitted": 2, "underReview": 0, "approved": 1, "rework": 0, "completed": 1, "pending": 2, "reworkCount": 1, "reworkPercent": 50, "avgCompletionHours": 21.9 },
  "projects": [
    { "projectId": "6700...01", "projectCode": "P-M3", "projectName": "Recce M3",
      "total": { "...": "same keys as totals" }, "inHouse": { "...": "..." }, "vendor": { "...": "..." } } ],
  "vendors": [
    { "vendorId": "66a...01", "name": "VND-A", "started": 2, "submitted": 2, "underReview": 0, "approved": 1, "rework": 0, "completed": 1, "pending": 1, "reworkCount": 1, "reworkPercent": 50, "avgCompletionHours": 21.9 } ],
  "cost": { "inHouse": 1500.5, "vendor": 5000, "total": 6500.5,
            "perProject": [ { "projectId": "6700...01", "projectCode": "P-M3", "projectName": "Recce M3", "inHouse": 1500.5, "vendor": null, "total": 1500.5 } ],
            "perShop": [] } } }
```
Here `pending` = started shops not completed. Same definitions as section 2 (`avgCompletionHours` = `startedAt` to `finalApprovedAt`).

`cost` is present **only** for roles that may review recce cost (Admin, Operations) **and** only when the recce cost module holds verified records for the selected projects / dates. Values come only from stored records: in-house = `approved.total` of trip claims that are `APPROVED` or `SETTLED` (by trip start date); vendor = `total` of the vendor rate applied to the project (by the date it was applied). A side without records is `null`; a project without records has no row; claims still in flight are not counted; nothing is estimated. `perShop` is always `[]` (no verified per-shop value exists). When nothing is verified the `cost` key is absent.

## 4. Notifications list (existing endpoints, nothing new)

The mobile login uses the notification routes that already exist: `GET /notifications`, `POST /notifications/read` (all), `POST /notifications/:id/read`, live stream `GET /notifications/stream`.

`GET /notifications`
```json
{ "success": true, "data": {
  "unread": 2,
  "items": [
    { "id": "6820...a1", "kind": "activity", "type": "RECCE_REVIEWED", "title": "Rework required",
      "text": "Shop 1: Arvind K. (Recce Operations) - rework. Front view is blurry, please retake it",
      "at": "2026-11-21T10:10:00.000Z", "projectId": "6700...01", "projectCode": "P-M3", "orderId": null,
      "path": "/recce-review/6801...b2", "siteId": "67f0...a1", "client": "Amul", "read": false } ] } }
```
New additive fields: `type` (the stored kind: `RECCE_SUBMITTED`, `RECCE_REVIEWED`, `RECCE_MESSAGE`, `SHOPS_ADDED`, ...) and `siteId` (the shop to open, `null` when the event is not about one shop). `kind` keeps the old web grouping. `path` is a web path; the mobile app should open the shop by `siteId`.

## 5. Notification events (who is told, once)

Each notification has a per-person key (event + person), so a retry never sends twice; the person who caused the event is never notified.

| Event | Recipient | `type` |
|---|---|---|
| Shops given to a vendor / in-house login | the vendor logins or the chosen executive | `SHOPS_ADDED` |
| Version submitted / resubmitted after rework | reviewers of the stage waiting (named reviewer, else Operations / Client Servicing of the project) | `RECCE_SUBMITTED` |
| A stage approved, rejected, rework / more photos asked, Admin override | the recce person (and, for rework / reject, the other stage's people) | `RECCE_REVIEWED` |
| Next stage's turn (sequential review) | that stage's people | `RECCE_SUBMITTED` |
| Both stages approved (final) | the recce person (`Final approval`) and the people of both stages (`Shop approved by all stages`), except whoever made the last decision | `RECCE_REVIEWED` |
| Shop reopened | the recce person | `RECCE_REVIEWED` |
| New thread message | field person writes: reviewers of the stage waiting (every stage when none is waiting); reviewer writes: the person doing the shop | `RECCE_MESSAGE` |
| Saving a draft | nobody (by design) | - |

## 6. Errors

| Status | `error.code` | When |
|---|---|---|
| 400 | `BAD_REQUEST` | a ref does not exist in this shop; `refs` is not valid JSON; non-image file; invalid id |
| 401 | `UNAUTHORIZED` | no / expired token |
| 403 | `FORBIDDEN` | dashboard for a non-field login; performance for vendor / field login / role without review rights |
| 404 | `NOT_FOUND` | another vendor's shop or thread; a submission or project outside your scope |
| 409 | `CONFLICT` | project closed or cancelled; message could not be saved (retry) |
| 413 | `FILE_TOO_LARGE` / `LIMIT_FILE_SIZE` | image over the size limit |
| 422 | `VALIDATION_ERROR` | empty message (no text and no image); `limit` / `before` not valid; `refs[].type` unknown; `from` after `to` |
