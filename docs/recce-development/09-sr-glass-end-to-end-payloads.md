# 09 - Recce API: one shop end to end (compact)

The whole shop flow in call order with real payloads (vendor "SR Glass", vendor ID 1121), plus the index of every recce route.
Details live where they belong: data and design in 04, review modes / outcomes / decision changes in 07, thread / dashboards / notifications in 08, the tested output in 10.
Everything here is checked by `tests/recce-19steps.test.ts` (in-memory database); that test writes `10-flow-test-output.md`. Ids, tokens and signed links below are made up.

## 0. Basics

- `{BASE}` = `http://<PC LAN IP>:4000/api/v1`. After login every call carries `Authorization: Bearer <accessToken>` (signed by the backend at login). JSON body max 1 MB.
- Success `{ "success": true, "data": ..., "meta": ... }`. Error `{ "success": false, "error": { "code", "message", "details": [] } }`. Dates are UTC ISO-8601.
- **Two ids.** `siteId` = the shop (field routes `/recce/...`). `submissionId` = the shop's recce record (review routes `/recce-review/submissions/:id/...`); the shop detail returns it once the visit is started.
- **Who.** Field: VENDOR, RECCE_EXECUTIVE (own shops only; another vendor's shop = 404). Stage `OPS`: OPERATIONS, RECCE_COORDINATOR (their projects). Stage `CS`: CLIENT_SERVICING (projects they created or whose order is theirs). ADMIN: everything, decides only through `override`. MANAGEMENT: read only.
- **Status.** `NOT_STARTED, IN_PROGRESS, DRAFT, READY_TO_SUBMIT, SUBMITTED, UNDER_REVIEW, APPROVED, REWORK_REQUIRED, REJECTED` (`DRAFT` / `READY_TO_SUBMIT` are worked out by the server).
- **One-time Admin setup for the six-angle flow** `PUT /recce-review/config`:
  ```json
  { "sequential": false,
    "requiredPhotos": { "default": ["SHOP_FRONT", "SIDE_VIEW", "LONG_SHOT", "ANNOTATED_VIEW", "LOCATION_VIEW", "ACCESS_PATH"] } }
  ```
  A new database starts with `sequential: false` (parallel review, since 2026-11-23) and only `SHOP_FRONT` + `NAME_BOARD` required. **An existing database keeps the values it has stored**, so send this once.

## 1. Route index

**Field** `/recce` (VENDOR, RECCE_EXECUTIVE)

| Route | What it does |
|---|---|
| `GET /recce/dashboard` | counts for my shops (08) |
| `GET /recce/shops?projectId=&q=&status=&page=&limit=` | my shops: status, progress, photoCount, missing, reworkOpen, version; `meta.summary`. The project list = these grouped by `projectId` |
| `GET /recce/shops/:siteId` | full detail: boards, installation, photos (each with `review`), progress, versions, reviews, reworks, `editable`, `maxPhotos` |
| `POST .../start` | start the visit. **No body**: the shop comes from the URL, the person from the token. Creates the record once; safe to repeat |
| `PUT .../draft` | boards (`mediaItems`, whole list replaced), `notes`, `installation` (only sent fields change) |
| `POST .../photos` | upload, multipart `photos` + `meta` |
| `PUT .../photos/order`, `PATCH .../photos/:photoId` | reorder / change category, board, caption of a **draft** photo |
| `PUT .../photos/:photoId/annotation` | marked copy (`edited` + `annotations`), draft only, original untouched |
| `DELETE .../photos/:photoId?reason=` | draft: erased with its file. Submitted: only while rework is open, soft `REMOVED`, reason required |
| `GET .../photos/:photoId/history` | replace chain, events, rework notes of one photo |
| `POST .../submit` | submit the next version |
| `GET .../versions`, `GET .../versions/compare?from=&to=` | all versions / what changed |
| `GET .../activity` | time-based history |
| `GET/POST .../messages`, `GET .../messages/unread`, `POST .../messages/read` | the shop channel (08) |

**Review** `/recce-review` (OPS, CS, ADMIN, MANAGEMENT; only the projects the login may review)

| Route | What it does |
|---|---|
| `GET /inbox?view=pending\|mine\|all` + filters (`projectId, client, district, vendor, assignee, q, mediaType, status, from, to, reviewer, dueBefore, overdue, priority, page, limit`) | review list |
| `GET /submissions/:id` | workspace: shop, project, versions with reviews, photos, reworks, `checklist` for my stage, `me` (`canDecide`, `canChange`, `openStage`, ...) |
| `POST /submissions/:id/start` | review started (`SUBMITTED` to `UNDER_REVIEW`), optional |
| `POST /submissions/:id/decision` | approve / reject / rework / more photos (section 3) |
| `POST /submissions/:id/change-decision` | a stage that approved changes its mind to reject / rework / more photos (07) |
| `POST /submissions/:id/override` | ADMIN: decide every pending stage `{action: APPROVE\|REJECT, reason (5+)}` |
| `POST /submissions/:id/reopen` | back to the recce person `{reason (5+)}` (ADMIN; OPS/CS after a rejection when `allowRetryAfterReject`) |
| `PUT /submissions/:id/reviewer` | name the reviewer of a stage `{stage, userId \| null}` (OPS, ADMIN) |
| `POST /submissions/:id/photos/:photoId/restore` | ADMIN: bring a removed photo back |
| `GET .../versions`, `.../versions/compare`, `.../activity`, `.../messages`, `.../messages/unread`, `POST .../messages`, `.../messages/read` | same as the field side, more detail |
| `GET /progress`, `/performance`, `/monitor`, `/reviewers`, `GET/PUT /config` | dashboards, reviewer list, configuration (08) |

**Others:** `POST /auth/login`, `/auth/vendor-login`, `/auth/refresh`, `/auth/logout`, `GET /auth/me` (04); `GET /notifications`, `POST /notifications/read`, `POST /notifications/:id/read`, `GET /notifications/stream` (08).

## 2. Vendor: from login to Version 1

**Login** `POST /auth/vendor-login` `{ "vendorId": "1121", "remember": true, "device": "Android 14 / Adinn Recce 1.0" }` (4 to 10 digits), or `POST /auth/login` `{ "identifier": "srglass@vendor.example", "mpin": "1234", "loginRole": "VENDOR", "platform": "mobile", "remember": true }`. In-house person: `"identifier": "emp101"`, `"loginRole": "RECCE"`.
Response `data = { accessToken, refreshToken, remember, user: { id, name, role, vendorId } }`. On `401` call `POST /auth/refresh` `{ "refreshToken": "..." }` once; the refresh token **rotates**, save the new one. A vendor default login must change its MPIN first (`user.mustChangeCredential`).

**Shops** `GET /recce/shops?projectId={projectId}` then `GET /recce/shops/{siteId}`. **Start** `POST /recce/shops/{siteId}/start` (no body) -> `IN_PROGRESS`, `submissionId` set, board `m1` seeded from the shop's own board type and quantity.

**Boards and installation** `PUT /recce/shops/{siteId}/draft` (installation may be sent alone)
```json
{ "mediaItems": [
    { "key": "b1", "name": "GSB",     "quantity": 2, "width": 6, "height": 4, "unit": "FT", "sided": "SINGLE", "condition": "PROPOSED", "position": "Shop fascia" },
    { "key": "b2", "name": "Acrylic", "quantity": 1, "width": 4, "height": 2, "unit": "FT", "sided": "SINGLE", "condition": "PROPOSED", "position": "Entrance glass" } ],
  "notes": "Shop opens at 9 am",
  "installation": { "ladderRequired": "YES", "scaffoldingRequired": "NO", "craneRequired": "NO", "hydraRequired": "NO", "manualInstallationPossible": "YES",
                    "electricalAccess": "AVAILABLE", "installationHeightFt": 12, "accessRestrictions": ["Narrow lane"], "additionalEquipment": ["Ladder 12 ft", "Drill machine"],
                    "obstruction": "", "roadsideConstraints": "", "safetyNotes": "Work before 6 pm", "notes": "Ladder access available" } }
```
- `mediaItems` is **replaced as a whole**: send every board each time. A board with photos cannot be removed (409). `key` unique per board (max 20 chars); same size = one item with `quantity`, a different size (GSB 8 x 4) = another item with its own key (`b3`). Max 12 items.
- `YES | NO | NOT_ASSESSED` for ladder, scaffolding, crane, hydra, manualInstallationPossible; `electricalAccess` `AVAILABLE | NOT_AVAILABLE | NOT_ASSESSED`. Anything `NOT_ASSESSED` blocks submit (never read as NO).

**Photos** `POST /recce/shops/{siteId}/photos` multipart: file field `photos` (1 to 10 files), text field `meta` = JSON array, one object per file in the same order.
```bash
curl -X POST "{BASE}/recce/shops/{siteId}/photos" -H "Authorization: Bearer <accessToken>" -F "photos=@front.jpg" \
  --form-string 'meta=[{"clientId":"c-1732170000-front","category":"SHOP_FRONT","mediaKey":"","caption":"Front view","capturedAt":"2026-11-21T06:30:00Z","lat":13.0412,"lng":80.2345,"gpsAccuracy":8.2,"width":3000,"height":4000,"source":"LIVE_CAMERA","device":"Android 14 / Adinn Recce 1.0"}]'
```
- `category` (required): `SHOP_FRONT` (Front View), `SIDE_VIEW`, `LONG_SHOT`, `ANNOTATED_VIEW`, `LOCATION_VIEW`, `ACCESS_PATH` (the six GPS photos) and the older `NAME_BOARD, LEFT_SIDE, RIGHT_SIDE, MEASUREMENT, MOUNTING_AREA, ELECTRICAL, EXISTING_BOARD, OBSTRUCTION, ADDITIONAL`. Each photo carries its own lat / lng / accuracy taken at capture.
- `mediaKey`: `""` = the whole shop; such a photo counts for **every** board (use it for the six angle photos). `"b1"` ties it to board b1 only: b2 then still shows as missing and submit answers 422. **A key that is not one of the shop's current boards is refused (400 "Unknown media type for a photo")**, so after boards are replaced, old keys such as `m1` stop working.
- `clientId` (8 to 80 chars) makes a retry safe: the same id is stored once. The same file content twice in a shop is refused (409 "already uploaded"). `replaces` = the old photo id (rework).
- Limits: jpg / jpeg / png / webp; each file up to `MAX_IMAGE_SIZE` (3 MB here, else 413 "File is too large"; the mobile app shrinks bigger pictures itself); 10 files per request; `maxPhotos` (40) per shop.
- The server never fills in a missing location. Doubtful data is kept and flagged for the reviewer: `GPS_MISSING, GPS_ZERO, GPS_FAR` (over 1 km from the shop), `GPS_WEAK` (over 200 m), `TIME_FUTURE, TIME_OLD, TIME_MISSING, LOW_RESOLUTION`. `gpsVerified` = location present, not 0,0, accuracy 200 m or better. With config `requireGps` on, submit is refused (422 `GPS_REQUIRED`) while a required photo has no usable location.
- A photo in the response: `{ id, category, mediaKey, caption, order, state: DRAFT|SUBMITTED|SUPERSEDED|REMOVED, version, url, editedUrl, hasEdited, annotations, capturedAt, uploadedAt, uploadedBy, capturedByRole, source, device, gpsVerified, lat, lng, gpsAccuracy, width, height, size, replaces, supersededBy, review: { status: PENDING|APPROVED|REWORK_REQUIRED, openRework } }`. `url` is a signed link valid about 10 minutes: read the shop again for a fresh one.
- Annotation: `PUT .../photos/{photoId}/annotation` multipart `edited` (file) + `annotations` `[{ "type": "measure", "x": 0.1, "y": 0.2, "x2": 0.6, "y2": 0.2, "text": "6 ft", "color": "#ff0000" }]` (types `rect, line, arrow, text, measure`).

**Submit** `POST /recce/shops/{siteId}/submit`
```json
{ "idempotencyKey": "submit-{siteId}-1", "notes": "All angles done" }
```
-> `200 { "duplicate": false, "version": 1, "detail": { ... "status": "SUBMITTED", "version": 1, "reviews": [ { "versionNo": 1, "stage": "OPS", "decision": "PENDING" }, { "versionNo": 1, "stage": "CS", "decision": "PENDING" } ] } }`. The same key again returns `duplicate: true` and the same version.
Checks in this order: `400` no photo; `422 MISSING_EVIDENCE` (names the missing photo / size); `422 GPS_REQUIRED`; `422 REWORK_UNRESOLVED` (section 4); `400` installation `NOT_ASSESSED` (`details[].path = "installation.craneRequired"`); `409` already submitted or locked.
Result: an immutable version snapshot, one `PENDING` review per stage, reviewer notifications, a card in the shop channel, history entries, all in one atomic update (a half-submitted shop is never visible).

## 3. Reviewers: approve, rework, reject

Open: `GET /recce-review/inbox?view=pending`, then `GET /recce-review/submissions/{submissionId}` (`currentVersion`, `checklist` for my stage, `photos[].id`, `me.canDecide`). Optional `POST .../start`.

`POST /recce-review/submissions/{submissionId}/decision`. `versionNo` must be the current version (else 409). Each stage decides **once per version**.

**Approve needs the whole checklist ticked** (else `400 "Tick every checklist item before approving: ..."`). Mandatory keys come from the configuration: stage `ALL` items plus the items of my stage (`gps` only when `requireGps` is on).

| Stage | Mandatory keys (default configuration) |
|---|---|
| OPS | `correct_shop, shop_front, board_area, angles, measurements, media_type, quantity, quality` |
| CS | `correct_shop, shop_front, board_area, media_type, quantity, client_req` |

```json
{ "stage": "OPS", "decision": "APPROVE", "versionNo": 1, "comment": "Looks good",
  "checklist": [ { "key": "correct_shop", "passed": true }, { "key": "shop_front", "passed": true }, { "key": "board_area", "passed": true },
                 { "key": "angles", "passed": true }, { "key": "measurements", "passed": true }, { "key": "media_type", "passed": true },
                 { "key": "quantity", "passed": true }, { "key": "quality", "passed": true } ] }
```
CS: the same body with `"stage": "CS"` and its six keys.

**Rework** (no checklist; `comment` 5+ characters). Only the named photos / measurements are asked again:
```json
{ "stage": "OPS", "decision": "REWORK", "versionNo": 1, "comment": "Fix the front photo and the width",
  "items": [ { "type": "REPLACE_PHOTO", "category": "SHOP_FRONT", "photo": "{photoId}", "note": "Board not clear, retake straight on" },
             { "type": "FIX_MEASUREMENT", "mediaKey": "b1", "note": "Width is 8 ft, not 6 ft" } ] }
```
`type`: `REPLACE_PHOTO | ADDITIONAL_PHOTO | FIX_MEASUREMENT | OTHER`; a `photo` must belong to this shop. **More photos:** `"decision": "ADDITIONAL"` with at least one `{ "type": "ADDITIONAL_PHOTO", "category": "LEFT_SIDE", "mediaKey": "b1" }`.
**Reject:** `{ "stage": "OPS", "decision": "REJECT", "versionNo": 1, "reason": "Wrong shop photographed" }`.

**Result** (details and the two review modes in 07): both stages approved = `APPROVED` (locked); one approved and one waiting = `UNDER_REVIEW`; any rework = `REWORK_REQUIRED` (the other waiting stage becomes `VOID`); any reject = `REJECTED` (reject beats rework beats approve). Default review is **parallel**: either stage may decide first. With `sequential: true` CS first gets `409 An earlier review stage must approve first`.
**Change an approval later:** `POST .../change-decision`, same body with `decision` = `REJECT | REWORK | ADDITIONAL` and a reason of 5+ characters; only that stage's own login, on the current version (07).
Other errors: stage already decided 409, vendor 403, OPS deciding the CS stage 403, ADMIN deciding directly 403 (use `/override`), closed project 409.

## 4. Vendor: rework answer, Version 2

1. `GET /recce/shops/{siteId}` -> `status: REWORK_REQUIRED`, `editable: true`; each asked photo has `review: { status: "REWORK_REQUIRED", openRework: { reworkId, itemId, note, stage, stageLabel, instructions, requestedBy, requestedAt } }`, the others stay `PENDING`; `reworks[]` has the full request. One photo's history: `GET .../photos/{photoId}/history`.
2. Replace only the flagged photo: `POST .../photos`, `meta[].replaces = "{old photoId}"`, same category and `mediaKey`, a new file and a new `clientId`:
   ```json
   [ { "clientId": "c-1732260000-front2", "category": "SHOP_FRONT", "mediaKey": "", "capturedAt": "2026-11-22T07:00:00Z",
       "lat": 13.0413, "lng": 80.2346, "gpsAccuracy": 6.1, "replaces": "{old photoId}", "source": "LIVE_CAMERA", "device": "Android 14 / Adinn Recce 1.0" } ]
   ```
   The old photo becomes `SUPERSEDED` at submit and stays in V1.
3. Fix the measurement: `PUT .../draft` with the full `mediaItems` list (`b1` width 8).
4. `POST .../submit` `{ "idempotencyKey": "submit-{siteId}-2", "notes": "Front retaken, width corrected" }` -> `version: 2`.
   Open rework must be answered or submit gives `422 REWORK_UNRESOLVED`: a `REPLACE_PHOTO` item needs a new photo with `replaces` = that photo, an `ADDITIONAL_PHOTO` item needs a new photo of that category. `FIX_MEASUREMENT` and `OTHER` are not enforced.
5. V1 stays unchanged. **Both stages review V2 again**; a V1 approval never counts for V2 (`versionNo: 2`).

## 5. Versions, compare, history

`GET /recce/shops/{siteId}/versions` (reviewer: `/recce-review/submissions/{id}/versions`), oldest first:
```json
[{ "version": 1, "current": false, "submittedAt": "...", "submittedBy": "SR Glass", "notes": "All angles done",
   "mediaItems": [ { "key": "b1", "name": "GSB", "quantity": 2, "width": 6, "height": 4, "unit": "FT" } ], "installation": { "...": "..." }, "installationRecorded": true,
   "photos": [ { "id": "...", "category": "SHOP_FRONT", "lat": 13.0412, "lng": 80.2345 } ], "addedIds": ["..."], "removedIds": [], "stages": ["OPS", "CS"],
   "decisions": [ { "stage": "CS", "decision": "APPROVED", "reviewer": "Priya M.", "decidedAt": "...", "comment": "" }, { "stage": "OPS", "decision": "REWORK", "reviewer": "Arvind K.", "comment": "Fix the front photo and the width" } ],
   "reworks": [ { "id": "...", "stage": "OPS", "kind": "REWORK", "status": "RESOLVED", "items": [] } ] },
 { "version": 2, "current": true, "...": "..." }]
```
`GET .../versions/compare?from=1&to=2`:
```json
{ "from": { "version": 1, "submittedAt": "...", "reviewerComments": [ { "stage": "OPS", "decision": "REWORK", "comment": "..." } ] },
  "to":   { "version": 2, "submittedAt": "...", "reviewerComments": [] },
  "photos": { "added": [], "removed": [], "replaced": [ { "from": { "id": "...", "category": "SHOP_FRONT" }, "to": { "id": "...", "category": "SHOP_FRONT" } } ], "unchanged": [ { "id": "...", "category": "SIDE_VIEW" } ] },
  "mediaItems": { "added": [], "removed": [], "changed": [ { "key": "b1", "name": "GSB", "fields": [ { "field": "width", "from": 6, "to": 8 } ] } ] },
  "installation": [], "notes": { "from": "All angles done", "to": "Front retaken, width corrected" }, "changed": true }
```
Show `6 x 4 ft -> 8 x 4 ft`, "Front View replaced", the other photos unchanged.

**History** `GET /recce/shops/{siteId}/activity` (reviewer: `/recce-review/submissions/{id}/activity?type=&person=&from=&to=&limit=`, more detail incl. admin overrides): append-only, newest first, each `{ type, label, actor, role, at, reason, mediaKey, photo, version, changes }`. Types: `SHOP_VISIT_STARTED, PHOTO_CAPTURED, PHOTO_REPLACED, PHOTO_ANNOTATED, PHOTO_DELETED, PHOTO_REMOVED, PHOTO_RESTORED, MEASUREMENT_UPDATED, DRAFT_SAVED, INSTALLATION_UPDATED, SUBMISSION_CREATED, REWORK_SUBMITTED, REVIEW_STARTED, REVIEW_APPROVED, REVIEW_REJECTED, REWORK_REQUESTED, ADDITIONAL_PHOTOS_REQUESTED, DECISION_CHANGED, FINAL_APPROVAL, ADMIN_OVERRIDE, REOPENED, REVIEWER_ASSIGNED, COMMENT_ADDED`. The field person sees only events marked visible to them.
One photo: `GET .../photos/{photoId}/history` -> `{ photoId, revisions: [ { revision, current, ...photo } ], events: [...], reworks: [ { reworkId, itemId, stage, requestedBy, note, instructions, resolved, resolvedInVersion } ] }`.

## 6. Channel, notifications, dashboards (details in 08)

- **Channel** (one thread for vendor, Operations and Client Servicing): `GET/POST /recce/shops/{siteId}/messages` and `/recce-review/submissions/{id}/messages`. Post `{ "body": "Front photo retaken as asked", "refs": [ { "type": "BOARD", "id": "b1" }, { "type": "VERSION", "id": "2" }, { "type": "PHOTO", "id": "{photoId}" } ] }` or multipart with `body`, `refs` (a JSON string) and one image in `file`. `GET .../messages?limit=20&before=<id>` newest-first pages; `GET .../messages/unread` -> `{ "unread": 3 }`; `POST .../messages/read` clears it. System cards (submitted, each decision, final approval, reopened) are posted automatically.
- **Notifications** `GET /notifications` (items carry `type` = `RECCE_SUBMITTED | RECCE_REVIEWED | RECCE_MESSAGE | SHOPS_ADDED` and `siteId`: open the shop by `siteId`), `POST /notifications/read`, `POST /notifications/{id}/read`. Submit tells the reviewers, a decision tells the recce person, a message tells the other side, never the sender.
- **Dashboards** `GET /recce/dashboard` (counts per project; `completed` = approved by every required stage on the current version), `GET /recce-review/progress|performance|monitor` (staff).

## 7. Errors

| Status | When |
|---|---|
| 400 | no photo; unknown `mediaKey`; checklist not ticked; rework without instructions (under 5 characters); a photo / ref not in this shop; installation `NOT_ASSESSED`; malformed JSON |
| 401 | no or expired token (refresh once, then log in again) |
| 403 | wrong role: vendor on a review route, OPS deciding the CS stage, ADMIN deciding without `/override` |
| 404 | another vendor's shop; a submission or project outside your scope |
| 409 | shop locked (`SUBMITTED / UNDER_REVIEW / APPROVED`), stage already decided, stale `versionNo`, same photo content twice, shop changed at the same time, closed project |
| 413 | image over `MAX_IMAGE_SIZE` |
| 422 | `MISSING_EVIDENCE`, `GPS_REQUIRED`, `REWORK_UNRESOLVED`, validation errors (`details[].path` names the field) |

## 8. Run it

Postman / curl order: login, dashboard, shops, start, boards, installation, six photos, submit V1, reviewer workspace, approve / rework, replace photo, boards V2, submit V2, versions, compare, history, channel, unread, notifications, both approve V2, result.
The same flow as an automated test (in-memory database, never the real one) that also writes the request / response transcript: `FLOW_OUT=<file.md> npx vitest run tests/recce-19steps.test.ts` in `Signage_Backend/signage-recce-backend` (the checked-in copy is `10-flow-test-output.md`).
