# 08 - Shop thread, dashboards, notifications

Base `{BASE}` = `/api/v1`, Bearer token. Success `{ "success": true, "data": ..., "meta": ... }`; error `{ "success": false, "error": { "code", "message", "details" } }`. Additive: calls that worked before return the same data. Scenario ids: `siteId = 67f0...a1`, `submissionId = 6801...b2`, project `6700...01`.

## 1. Shop thread

One thread per shop, shared by the field person, Operations and Client Servicing (Connect project channel). Field routes (VENDOR / RECCE_EXECUTIVE, own shops) and reviewer twins have the same shape:

| Purpose | Field app | Reviewer / web |
|---|---|---|
| list | `GET /recce/shops/:siteId/messages` | `GET /recce-review/submissions/:submissionId/messages` |
| post | `POST /recce/shops/:siteId/messages` | `POST /recce-review/submissions/:submissionId/messages` |
| unread | `GET .../messages/unread` | `GET .../messages/unread` |
| mark read | `POST .../messages/read` | `POST .../messages/read` |

**List.** No query = last 100 messages, oldest first, no `meta`. With `?limit=` (1-100) and / or `?before=` (message id or ISO time) = a page, newest first; pass `meta.nextBefore` as the next `before` (`null` = nothing older).
```json
{ "success": true,
  "data": [ { "id":"6810...c5", "author":{"id":"66f...01","name":"Siva Creations","role":"VENDOR"}, "body":"Board is faded, photo attached",
              "attachments":[{"fileId":"6810...f1","name":"lane.jpg","mimeType":"image/jpeg","kind":"image","url":"https://.../signed","expiresAt":"2026-11-21T10:30:00.000Z"}],
              "refs":[{"type":"PHOTO","id":"6800...e1"},{"type":"BOARD","id":"b1"},{"type":"VERSION","id":"2"}],
              "card":null, "shop":"67f0...a1", "createdAt":"2026-11-21T10:15:00.000Z" },
            { "id":"6810...c4", "author":{"name":"Arvind K.","role":"OPERATIONS"}, "body":"", "attachments":[], "refs":[{"type":"PHOTO","id":"6800...e1"},{"type":"VERSION","id":"1"}],
              "card":{"title":"Recce Review Update","tone":"warn","path":"/recce-review/6801...b2",
                      "lines":[{"label":"Decision","value":"Rework required"},{"label":"Reviewer","value":"Arvind K. (Recce Operations)"},{"label":"Rework items","value":"Full Shop Front View (Blurry)"}]} } ],
  "meta": { "limit": 2, "hasMore": true, "nextBefore": "6810...c4" } }
```
Messages also carry `parent, mentions, reactions, replyCount, edited, deleted, pinned`. `attachments[].url` is a short-lived private link: list again for a fresh one. `card` is set on system messages, `null` on people's messages.

**Post.** JSON `{ "body": "About this photo", "refs": [{"type":"PHOTO","id":"6800...e1"},{"type":"BOARD","id":"b1"},{"type":"VERSION","id":"2"}] }`, or multipart `body` + `refs` (a **JSON string**) + file field **`file`** (one image: same types, size limit and content check as shop photos). Response `201` = the message.
Rules: text or an image is required (422); `body` max 2000; `refs` max 10, duplicates dropped; `refs[].type` is `PHOTO` (a photo of this shop, reviewers cannot point at drafts), `BOARD` (a media `key` of this shop, current or earlier, or the seeded `m1`) or `VERSION` (a really submitted version). Unknown type = 422; a ref not in THIS shop = 400 and nothing is stored (not even the image). Non-image = 400, over the size limit = 413. A closed project refuses messages (409). The image is filed under the project (`Connect/<client>/<project code>/...`) and erased with it.

**Unread / read.** `GET .../messages/unread` -> `{ "unread": 3 }` (messages from others after this person last marked read; own messages never count). `POST .../messages/read` (no body, repeatable) -> `{ "ok": true, "unread": 0 }`; it also marks this person's `RECCE_MESSAGE` notifications of the shop read.

**System cards** (posted once each, an event key makes a retry harmless; `refs` the app can open):

| Event | `card.title` | Decision line | `refs` |
|---|---|---|---|
| Version submitted | `Shop Recce Submitted` / `Shop Recce Resubmitted` (v2+) | - | `VERSION n` |
| A stage approved | `Recce Review Update` | `Recce Operations approved` / `Client Servicing approved` | `VERSION n` |
| Rework / more photos | `Recce Review Update` | `Rework required` / `Additional photos requested` + `Rework items` / `Needed` | `VERSION n`, `PHOTO id`, `BOARD key` |
| All stages approved | `Recce Review Update` | `Final approval` | `VERSION n` |
| Rejected / Admin override | `Recce Review Update` | `Rejected` / `Admin override: approved` | `VERSION n` |
| Approval changed | `Recce Review Update` | `Decision changed: rejected / rework required / more photos requested` + `Earlier decision: Approved` | `VERSION n`, `PHOTO id` |
| Hand-over (sequential mode only) | `Client Servicing Review Due` | - | `VERSION n` |
| Shop reopened | `Shop Reopened` | `Reason`, `Previous status` | `VERSION n` |

**Who can read.** Another vendor's / login's shop: 404 on all four routes. Reviewers: only projects they review (Operations: assigned, Client Servicing: their orders, Admin / Management: all), else 404. History stays with the shop: after a reassignment the new vendor sees the whole thread, the old one gets 404.

## 2. Field dashboard

`GET /recce/dashboard` (VENDOR / RECCE_EXECUTIVE; only this login's shops, projects not cancelled / lost)
```json
{ "success": true, "data": {
  "assignedProjects": 2, "assignedShops": 3, "started": 1, "submitted": 1, "underReview": 0, "approved": 1, "rework": 0,
  "completed": 1, "pending": 2, "avgCompletionHours": 26.4, "reworkCount": 0, "reworkPercent": 0,
  "projects": [ { "projectId":"6700...01","projectCode":"P-M3","projectName":"Recce M3","assigned":2,"started":1,"submitted":1,"approved":1,"rework":0,"pending":1 } ] } }
```
Definitions (same on the staff screen):
- `started` has a recce record; `submitted` submitted at least once; `underReview` = `SUBMITTED` / `UNDER_REVIEW` now; `approved` = status `APPROVED`; `rework` = `REWORK_REQUIRED` now.
- `completed` = approved by **every stage on the current version** (status `APPROVED` and an approved review row per stage of that version). One stage is not completed; a V1 approval never counts for V2.
- `pending` = assigned shops not completed. `reworkCount` = shops that ever had a rework / more-photos request; `reworkPercent` = `reworkCount / submitted x 100` (one decimal, 0 when none submitted).
- `avgCompletionHours` = mean of `finalApprovedAt - startedAt` over completed shops (one decimal, `null` when none).
Non-field roles 403; no token 401.

## 3. Staff performance

`GET /recce-review/performance?projectId=&from=&to=` - same visibility as `/progress` (Operations / Client Servicing their projects, Admin / Management all; vendor, in-house login and other roles 403; project outside scope 404; `from` after `to` 422). `from` / `to` keep shops whose recce started in that range.
```json
{ "success": true, "data": {
  "filters": {"projectId":null,"from":null,"to":null},
  "totals":  { "started":5,"submitted":3,"underReview":0,"approved":2,"rework":0,"completed":2,"pending":3,"reworkCount":1,"reworkPercent":33.3,"avgCompletionHours":12.5 },
  "inHouse": { "...": "same keys as totals" }, "vendor": { "...": "same keys" },
  "projects": [ { "projectId":"6700...01","projectCode":"P-M3","projectName":"Recce M3","total":{"...":"..."},"inHouse":{"...":"..."},"vendor":{"...":"..."} } ],
  "vendors": [ { "vendorId":"66a...01","name":"VND-A","started":2,"submitted":2,"completed":1,"pending":1,"reworkCount":1,"reworkPercent":50,"avgCompletionHours":21.9 } ],
  "cost": { "inHouse":1500.5,"vendor":5000,"total":6500.5,"perProject":[{"projectId":"6700...01","projectCode":"P-M3","inHouse":1500.5,"vendor":null,"total":1500.5}],"perShop":[] } } }
```
Here `pending` = started shops not completed. `cost` is present **only** for roles that may review recce cost (Admin, Operations) **and** only when verified records exist: in-house = `approved.total` of trip claims `APPROVED` / `SETTLED` (by trip start date); vendor = `total` of the vendor rate applied to the project (by the date applied). A side without records is `null`, a project without records has no row, claims in flight are not counted, nothing is estimated, `perShop` is always `[]`. With nothing verified the `cost` key is absent.

## 4. Notifications list (existing endpoints)

`GET /notifications`, `POST /notifications/read` (all), `POST /notifications/:id/read`, stream `GET /notifications/stream`.
```json
{ "success": true, "data": { "unread": 2, "items": [
  { "id":"6820...a1","kind":"activity","type":"RECCE_REVIEWED","title":"Rework required",
    "text":"Shop 1: Arvind K. (Recce Operations) - rework. Front view is blurry, please retake it",
    "at":"2026-11-21T10:10:00.000Z","projectId":"6700...01","projectCode":"P-M3","path":"/recce-review/6801...b2","siteId":"67f0...a1","client":"Amul","read":false } ] } }
```
Additive fields: `type` (stored kind: `RECCE_SUBMITTED`, `RECCE_REVIEWED`, `RECCE_MESSAGE`, `SHOPS_ADDED`, ...) and `siteId` (the shop to open, `null` if not about one shop). `kind` keeps the old web grouping; `path` is a web path, so mobile opens the shop by `siteId`.

## 5. Who is told (once)

Per-person key (event + person): a retry never sends twice; the person who caused the event is never notified.

| Event | Recipient | `type` |
|---|---|---|
| Shops given to a login | the vendor logins or the chosen executive | `SHOPS_ADDED` |
| Version submitted / resubmitted | **parallel (default): reviewers of every stage at once**; sequential: first stage only (named reviewer, else Operations / Client Servicing of the project) | `RECCE_SUBMITTED` |
| Stage approved / rejected / rework / override | the recce person (and, for rework / reject, the other stage's people) | `RECCE_REVIEWED` |
| Next stage's turn | **sequential mode only** | `RECCE_SUBMITTED` |
| All stages approved | recce person (`Final approval`) + people of both stages (`Shop approved by all stages`), except whoever made the last decision; only the call that moved the status sends it | `RECCE_REVIEWED` |
| Approval changed | recce person and the other stage | `RECCE_REVIEWED` |
| Shop reopened | the recce person | `RECCE_REVIEWED` |
| New thread message | field person writes: reviewers of the stage in `pendingStage` (every stage when none); reviewer writes: the person doing the shop | `RECCE_MESSAGE` |
| Saving a draft | nobody | - |

Known limit: in parallel mode `pendingStage` is the first stage, so a field message notifies only that stage's people, not both.

## 6. Errors

| Status | `error.code` | When |
|---|---|---|
| 400 | `BAD_REQUEST` | a ref not in this shop; `refs` not valid JSON; non-image file; invalid id |
| 401 | `UNAUTHORIZED` | no / expired token |
| 403 | `FORBIDDEN` | dashboard for a non-field login; performance for vendor / field login / role without review rights |
| 404 | `NOT_FOUND` | another vendor's shop or thread; submission or project outside your scope |
| 409 | `CONFLICT` | project closed or cancelled; message could not be saved (retry) |
| 413 | `FILE_TOO_LARGE` / `LIMIT_FILE_SIZE` | image over the size limit |
| 422 | `VALIDATION_ERROR` | empty message; bad `limit` / `before`; unknown `refs[].type`; `from` after `to` |
