# 09 - One real shop, start to finish (vendor "SR Glass", vendor ID 1121)

Everything below uses endpoints that already exist (verified in `recceReview.routes.ts`, `recceReview.field.ts`, `auth.validators.ts`). No new API was needed.
All values are **examples**: ids, tokens and signed file links are made up. Replace them with what your own responses return.

- Base URL: `{BASE}` = `http://<PC LAN IP>:4000/api/v1`
- Success envelope: `{ "success": true, "data": ..., "meta": ... }`. Error envelope: `{ "success": false, "message": "...", "error": { "code": "...", "details": [] } }`
- Header on every call after login: `Authorization: Bearer <accessToken>`
- Scenario: vendor **SR Glass** (vendor ID `1121`), project `ADN-2451 South Zone Retail Rollout`, shop `SM-0234 Sri Murugan Super Market`.
- Example ids: `projectId = 67e9a0000000000000000c04`, `siteId = 67f0a0000000000000000a01`, `submissionId = 6801b0000000000000000b02`.

> The access token cannot be written here as a real value: it is signed by the backend (`JWT_ACCESS_SECRET`) when you log in. Call step 1, copy `data.accessToken`, and paste it into the `Authorization` header of the next calls.

---
## 0. One-time Admin setup (needed for this flow)

`PUT {BASE}/recce-review/config` with an **Admin** token:
```json
{ "sequential": false,
  "requiredPhotos": { "default": ["SHOP_FRONT", "SIDE_VIEW", "LONG_SHOT", "ANNOTATED_VIEW", "LOCATION_VIEW", "ACCESS_PATH"] } }
```
- `sequential: false` = Operations and Client Servicing both get the shop at the same time and decide in any order (default for new databases since 2026-11-23). `true` = Client Servicing must wait for Operations (a CS approve first answers `409 An earlier review stage must approve first`). An existing database keeps its old value, so send this once.
- `requiredPhotos.default` = the photos a shop must have before submit. Out of the box it is only `SHOP_FRONT` + `NAME_BOARD`, so the six angles are **not** required until this is set.
- Both settings are tested in `tests/recce-19steps.test.ts`; the readable output of every step is in `10-flow-test-output.md`.

---
## 1. Login (get the token)

### 1a. Vendor login with the vendor ID
`POST {BASE}/auth/vendor-login`
```json
{ "vendorId": "1121", "remember": true, "device": "Android 14 / Adinn Recce 1.0" }
```
`vendorId` is 4 to 10 digits. Vendor default login must change its MPIN on first use (`user.mustChangeCredential`).

### 1b. Vendor or in-house login with MPIN
`POST {BASE}/auth/login`
```json
{ "identifier": "srglass@vendor.example", "mpin": "1234", "loginRole": "VENDOR", "platform": "mobile", "remember": true }
```
In-house recce person: same body with `"identifier": "emp101"` and `"loginRole": "RECCE"`. `password` can be sent instead of `mpin` for password accounts.

Response (both):
```json
{ "success": true, "data": {
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.<payload>.<signature>",
  "refreshToken": "9f2c...random...e41a",
  "remember": true,
  "user": { "id": "66f000000000000000000101", "name": "SR Glass", "role": "VENDOR", "vendorId": "66a000000000000000000011" } } }
```
Keep both tokens. Access token is short lived; when a call returns `401`:

`POST {BASE}/auth/refresh` body `{ "refreshToken": "9f2c...e41a" }` returns a new pair. **The refresh token rotates: save the new one every time.**

---
## 2. Project list

There is no separate "projects" endpoint for field logins. The project list is the shop list grouped by `projectId`, or the dashboard summary below.

`GET {BASE}/recce/dashboard` (counts per project)
```json
{ "success": true, "data": {
  "assignedProjects": 1, "assignedShops": 3, "started": 1, "submitted": 1, "underReview": 1, "approved": 0, "rework": 0,
  "completed": 0, "pending": 3, "avgCompletionHours": null, "reworkCount": 0, "reworkPercent": 0,
  "projects": [ { "projectId": "67e9a0000000000000000c04", "projectCode": "ADN-2451", "projectName": "South Zone Retail Rollout",
                  "assigned": 3, "started": 1, "submitted": 1, "approved": 0, "rework": 0, "pending": 3 } ] } }
```

---
## 3. Project with its shops

`GET {BASE}/recce/shops?projectId=67e9a0000000000000000c04&q=&status=&page=1&limit=50`
```json
{ "success": true,
  "data": [ {
    "siteId": "67f0a0000000000000000a01", "projectId": "67e9a0000000000000000c04", "projectCode": "ADN-2451",
    "projectName": "South Zone Retail Rollout", "client": "ABC Retail",
    "siteCode": "SM-0234", "shopName": "Sri Murugan Super Market", "dealerName": "Murugan Stores", "district": "Chennai", "location": "T. Nagar",
    "address": "12 Usman Road, T. Nagar, Chennai, 600017", "contactPerson": "Murugan", "mobile": "9876543210",
    "mediaTypes": [ { "name": "GSB", "quantity": 2 }, { "name": "Acrylic", "quantity": 1 } ],
    "assignedAt": "2026-11-20T05:00:00.000Z", "expectedBy": "2026-11-28T00:00:00.000Z",
    "status": "NOT_STARTED", "progress": 0, "photoCount": 0, "missing": 8, "reworkOpen": false, "version": 0, "submissionId": null } ],
  "meta": { "page": 1, "limit": 50, "total": 3, "summary": { "NOT_STARTED": 2, "UNDER_REVIEW": 1 } } }
```
`status`: `NOT_STARTED, IN_PROGRESS, DRAFT, READY_TO_SUBMIT, SUBMITTED, UNDER_REVIEW, APPROVED, REWORK_REQUIRED, REJECTED`.
A vendor only gets shops of its own vendor record; another vendor's shop is `404`.

---
## 4. One shop, full recce

### 4.1 Open the shop and start the visit
`GET {BASE}/recce/shops/67f0a0000000000000000a01` returns the whole record (shape in 4.6).
`POST {BASE}/recce/shops/67f0a0000000000000000a01/start` with body `{}` creates the working record (`IN_PROGRESS`).

### 4.2 Boards (one shop, many boards) and measurements
`PUT {BASE}/recce/shops/67f0a0000000000000000a01/draft`
```json
{ "mediaItems": [
    { "key": "b1", "name": "GSB",     "quantity": 2, "width": 6, "height": 4, "unit": "FT", "sided": "SINGLE", "condition": "PROPOSED", "position": "Shop fascia", "notes": "" },
    { "key": "b2", "name": "Acrylic", "quantity": 1, "width": 4, "height": 2, "unit": "FT", "sided": "SINGLE", "condition": "PROPOSED", "position": "Entrance glass" } ],
  "notes": "Shop opens at 9 am" }
```
Rules: each board type has a unique `key` (max 20 chars). Same size = one item with `quantity`. A different size (for example GSB 8 x 4) is **another item with its own key** (`b3`), so each board keeps its identity through rework. Max 12 items. A board that already has photos cannot be removed (`409`).

### 4.3 Installation requirement (ladder, crane, equipment)
`PUT {BASE}/recce/shops/67f0a0000000000000000a01/draft` (can be sent alone; only the fields sent change)
```json
{ "installation": {
    "ladderRequired": "YES", "scaffoldingRequired": "NO", "craneRequired": "NO", "hydraRequired": "NO",
    "manualInstallationPossible": "YES", "electricalAccess": "AVAILABLE", "installationHeightFt": 12,
    "accessRestrictions": ["Narrow lane"], "additionalEquipment": ["Ladder 12 ft", "Drill machine"],
    "obstruction": "Tree branch near right side", "roadsideConstraints": "", "safetyNotes": "Work before 6 pm", "notes": "Ladder access available" } }
```
`YES | NO | NOT_ASSESSED` for ladder, scaffolding, crane, hydra, manualInstallationPossible; `electricalAccess` is `AVAILABLE | NOT_AVAILABLE | NOT_ASSESSED`. Anything left `NOT_ASSESSED` blocks submit (never treated as NO).

### 4.4 Photos with GPS (demo images)
Six photo categories: `SHOP_FRONT` (Front View), `SIDE_VIEW`, `LONG_SHOT`, `ANNOTATED_VIEW`, `LOCATION_VIEW`, `ACCESS_PATH`.
For the demo, download any six pictures (for example from Unsplash) to `front.jpg`, `side.jpg`, `long.jpg`, `annotated.jpg`, `location.jpg`, `access.jpg`, then upload them. Each photo carries its own GPS taken at the moment of capture.

`POST {BASE}/recce/shops/67f0a0000000000000000a01/photos` as `multipart/form-data`
- file field `photos` (one or more files)
- text field `meta` = JSON array, one object per file, same order

```bash
curl -X POST "{BASE}/recce/shops/67f0a0000000000000000a01/photos" \
  -H "Authorization: Bearer <accessToken>" \
  -F "photos=@front.jpg" \
  --form-string 'meta=[{"clientId":"c-1732170000-front","category":"SHOP_FRONT","mediaKey":"","caption":"Front view","capturedAt":"2026-11-21T06:30:00Z","lat":13.0412,"lng":80.2345,"gpsAccuracy":8.2,"width":3000,"height":4000,"source":"LIVE_CAMERA","device":"Android 14 / Adinn Recce 1.0"}]'
```
`meta` keys: `clientId` (8-80 chars, idempotency: same id stored once), `category` (required), `mediaKey` (leave `""` for the six angle photos of the shop: they then count for **every** board. A photo with `"mediaKey":"b1"` counts only for board b1, so b2 would still show as missing and submit answers 422), `caption`, `capturedAt`, `lat`, `lng`, `gpsAccuracy` (metres), `width`, `height`, `source` (`LIVE_CAMERA | GALLERY`), `device`, `replaces` (old photo id, for rework).

The other five photos use the same call with their category, own `clientId` and own lat/lng, for example:

| category | clientId | lat | lng | accuracy |
|---|---|---|---|---|
| SIDE_VIEW | c-1732170060-side | 13.04122 | 80.23455 | 7.5 |
| LONG_SHOT | c-1732170120-long | 13.04105 | 80.23430 | 9.0 |
| ANNOTATED_VIEW | c-1732170180-annot | 13.04121 | 80.23448 | 6.8 |
| LOCATION_VIEW | c-1732170240-loc | 13.04118 | 80.23451 | 5.9 |
| ACCESS_PATH | c-1732170300-access | 13.04090 | 80.23420 | 11.0 |

Response `201` is the full shop detail; each photo looks like this:
```json
{ "id": "6800a0000000000000000e01", "category": "SHOP_FRONT", "mediaKey": "b1", "caption": "Front view", "order": 0, "state": "DRAFT", "version": null,
  "url": "https://<storage>/signed/front.jpg?exp=...", "editedUrl": null, "hasEdited": false, "annotations": null,
  "capturedAt": "2026-11-21T06:30:00.000Z", "uploadedAt": "2026-11-21T06:31:10.000Z", "uploadedBy": "SR Glass", "capturedByRole": "VENDOR",
  "source": "LIVE_CAMERA", "device": "Android 14 / Adinn Recce 1.0", "gpsVerified": true,
  "lat": 13.0412, "lng": 80.2345, "gpsAccuracy": 8.2, "width": 3000, "height": 4000, "size": 482113, "replaces": null, "supersededBy": null,
  "review": { "status": "PENDING", "openRework": null } }
```
`url` is a short-lived signed link; read the shop again for a fresh one. The server never replaces missing GPS with the shop's saved address. Weak or far GPS is kept and flagged for the reviewer (`GPS_MISSING, GPS_ZERO, GPS_FAR, GPS_WEAK, TIME_FUTURE, TIME_OLD, TIME_MISSING, LOW_RESOLUTION`). The same file twice in one shop is refused.

Annotated copy of a photo (original stays untouched):
`PUT {BASE}/recce/shops/:siteId/photos/:photoId/annotation` multipart: file `edited` (marked image) + text `annotations`:
```json
[ { "type": "measure", "x": 0.1, "y": 0.2, "x2": 0.6, "y2": 0.2, "text": "6 ft", "color": "#ff0000" },
  { "type": "arrow", "x": 0.4, "y": 0.5, "x2": 0.5, "y2": 0.3 } ]
```
Other photo calls: `PATCH .../photos/:photoId` `{category?, mediaKey?, caption?, order?}`, `PUT .../photos/order` `{ "ids": [...] }`, `DELETE .../photos/:photoId?reason=` (draft = erased; submitted photo only during rework, with a reason).

### 4.5 Submit Version 1
`POST {BASE}/recce/shops/67f0a0000000000000000a01/submit`
```json
{ "idempotencyKey": "submit-67f0a0000000000000000a01-1", "notes": "All angles done" }
```
Response `200`: `{ "duplicate": false, "version": 1, "detail": { ...shop detail, "status": "UNDER_REVIEW" or "SUBMITTED", "version": 1 } }`.
The same key sent again returns `duplicate: true` and the same version (no second version).
Refusals: `422 MISSING_EVIDENCE` (required photo or size missing), `422 GPS_REQUIRED` (only when the admin switched `requireGps` on), `400` installation fields still `NOT_ASSESSED`, `409` already submitted or locked.
Server work: immutable snapshot (photos, boards, installation, notes), one pending review for **Recce Operations** and one for **Client Servicing**, notifications, a card in the shop channel, audit entry.

### 4.6 Shop detail shape (`GET /recce/shops/:siteId`) after Version 1
```json
{ "success": true, "data": {
  "siteId": "67f0a0000000000000000a01", "siteCode": "SM-0234", "shopName": "Sri Murugan Super Market", "dealerName": "Murugan Stores",
  "district": "Chennai", "contactPerson": "Murugan", "mobile": "9876543210", "address": "12 Usman Road, T. Nagar, Chennai, 600017",
  "lat": 13.0410, "lng": 80.2340, "remarks": null,
  "project": { "id": "67e9a0000000000000000c04", "code": "ADN-2451", "name": "South Zone Retail Rollout", "client": "ABC Retail", "expectedBy": "2026-11-28T00:00:00.000Z", "closed": false },
  "submissionId": "6801b0000000000000000b02", "status": "UNDER_REVIEW", "rawStatus": "UNDER_REVIEW", "editable": false, "version": 1, "attempts": 1,
  "mediaItems": [
    { "key": "b1", "name": "GSB", "quantity": 2, "width": 6, "height": 4, "unit": "FT", "sided": "SINGLE", "condition": "PROPOSED", "position": "Shop fascia", "notes": "", "installationNotes": "", "required": ["SHOP_FRONT", "SIDE_VIEW"] },
    { "key": "b2", "name": "Acrylic", "quantity": 1, "width": 4, "height": 2, "unit": "FT", "sided": "SINGLE", "condition": "PROPOSED", "position": "Entrance glass", "notes": "", "installationNotes": "", "required": [] } ],
  "notes": "Shop opens at 9 am",
  "installation": { "ladderRequired": "YES", "scaffoldingRequired": "NO", "craneRequired": "NO", "hydraRequired": "NO", "manualInstallationPossible": "YES",
                    "electricalAccess": "AVAILABLE", "installationHeightFt": 12, "accessRestrictions": ["Narrow lane"], "obstruction": "Tree branch near right side",
                    "roadsideConstraints": "", "safetyNotes": "Work before 6 pm", "additionalEquipment": ["Ladder 12 ft", "Drill machine"], "notes": "Ladder access available" },
  "installationPending": [],
  "categories": [ { "key": "SHOP_FRONT", "label": "Full Shop Front View" }, { "key": "SIDE_VIEW", "label": "Side View" }, { "key": "LONG_SHOT", "label": "Long Shot" },
                  { "key": "ANNOTATED_VIEW", "label": "Annotated View" }, { "key": "LOCATION_VIEW", "label": "Location View" }, { "key": "ACCESS_PATH", "label": "Access Path" } ],
  "photos": [ { "id": "6800a0000000000000000e01", "category": "SHOP_FRONT", "state": "SUBMITTED", "lat": 13.0412, "lng": 80.2345, "gpsVerified": true,
                "review": { "status": "PENDING", "openRework": null } } ],
  "progress": { "percent": 100, "required": 8, "done": 8, "missing": [] },
  "versions": [ { "version": 1, "submittedAt": "2026-11-21T08:00:00.000Z", "photoCount": 6 } ],
  "reviews": [ { "versionNo": 1, "stage": "OPS", "stageLabel": "Recce Operations", "decision": "PENDING", "comment": "", "reviewer": null, "decidedAt": null },
               { "versionNo": 1, "stage": "CS",  "stageLabel": "Client Servicing",  "decision": "PENDING", "comment": "", "reviewer": null, "decidedAt": null } ],
  "reworks": [], "maxPhotos": 40 } }
```

---
## 5. Two-person approval and rework (reviewer logins, not the vendor)

Reviewer logs in with `POST /auth/login` (Operations / Coordinator = stage `OPS`, Client Servicing = stage `CS`; web or reviewer login). A vendor calling these gets `403`.

Approve: `POST {BASE}/recce-review/submissions/6801b0000000000000000b02/decision`
```json
{ "stage": "CS", "decision": "APPROVE", "versionNo": 1, "comment": "Looks good",
  "checklist": [ { "key": "correct_shop", "passed": true }, { "key": "shop_front", "passed": true }, { "key": "board_area", "passed": true } ] }
```
Rework only one photo and one measurement (the other photos are not asked again):
```json
{ "stage": "OPS", "decision": "REWORK", "versionNo": 1, "comment": "Fix front photo and width",
  "items": [
    { "type": "REPLACE_PHOTO", "category": "SHOP_FRONT", "photo": "6800a0000000000000000e01", "note": "Board not clear, retake straight on" },
    { "type": "FIX_MEASUREMENT", "mediaKey": "b1", "note": "Width is 8 ft, not 6 ft" } ] }
```
`decision`: `APPROVE | REJECT (needs "reason") | REWORK | ADDITIONAL`. Item `type`: `REPLACE_PHOTO | ADDITIONAL_PHOTO | FIX_MEASUREMENT | OTHER`.
Each stage decides once per version. Overall `APPROVED` only when **both** stages approved the **current** version; a Version 1 approval never counts for Version 2. Examples: CS approved + OPS pending = `UNDER_REVIEW`; CS approved + OPS rework = `REWORK_REQUIRED`.

What the vendor sees afterwards (`GET /recce/shops/:siteId`): `status: "REWORK_REQUIRED"`, `editable: true`, and a flag on the exact photo:
```json
{ "id": "6800a0000000000000000e01", "category": "SHOP_FRONT", "state": "SUBMITTED",
  "review": { "status": "REWORK_REQUIRED", "openRework": {
      "reworkId": "6803c0000000000000000c01", "itemId": "6803c0000000000000000c02", "note": "Board not clear, retake straight on",
      "stage": "OPS", "stageLabel": "Recce Operations", "instructions": "Fix front photo and width", "requestedBy": "Arvind K.", "requestedAt": "2026-11-22T05:10:00.000Z" } } }
```
Other photos stay `"review": { "status": "PENDING", "openRework": null }`. The rework icon in the app opens this note; the history of that photo is `GET {BASE}/recce/shops/:siteId/photos/:photoId/history`.

---
## 6. Fix and submit Version 2

1. Replace only the flagged photo: `POST {BASE}/recce/shops/:siteId/photos` (multipart, new file in `photos`):
```json
[ { "clientId": "c-1732260000-front2", "category": "SHOP_FRONT", "mediaKey": "", "capturedAt": "2026-11-22T07:00:00Z",
    "lat": 13.0413, "lng": 80.2346, "gpsAccuracy": 6.1, "replaces": "6800a0000000000000000e01", "source": "LIVE_CAMERA", "device": "Android 14 / Adinn Recce 1.0" } ]
```
The old photo becomes `SUPERSEDED` (stays in Version 1 history); the new one is `DRAFT` until resubmit.

2. Change the measurement: `PUT {BASE}/recce/shops/:siteId/draft`
```json
{ "mediaItems": [
    { "key": "b1", "name": "GSB",     "quantity": 2, "width": 8, "height": 4, "unit": "FT", "sided": "SINGLE", "condition": "PROPOSED", "position": "Shop fascia" },
    { "key": "b2", "name": "Acrylic", "quantity": 1, "width": 4, "height": 2, "unit": "FT" } ] }
```
3. Submit: `POST {BASE}/recce/shops/:siteId/submit` body `{ "idempotencyKey": "submit-67f0a0000000000000000a01-2", "notes": "Front retaken, width corrected" }` returns `version: 2`. Version 1 stays unchanged; both stages must approve Version 2 again.

---
## 7. Version 1 / Version 2 as an array, and compare

`GET {BASE}/recce/shops/67f0a0000000000000000a01/versions` (oldest first)
```json
{ "success": true, "data": [
  { "version": 1, "current": false, "submittedAt": "2026-11-21T08:00:00.000Z", "submittedBy": "SR Glass", "notes": "All angles done",
    "mediaItems": [ { "key": "b1", "name": "GSB", "quantity": 2, "width": 6, "height": 4, "unit": "FT" }, { "key": "b2", "name": "Acrylic", "quantity": 1, "width": 4, "height": 2, "unit": "FT" } ],
    "installation": { "ladderRequired": "YES", "craneRequired": "NO", "...": "..." }, "installationRecorded": true,
    "photos": [ { "id": "6800a0000000000000000e01", "category": "SHOP_FRONT", "lat": 13.0412, "lng": 80.2345, "capturedAt": "2026-11-21T06:30:00.000Z" } ],
    "addedIds": ["6800a0000000000000000e01"], "removedIds": [], "stages": ["OPS", "CS"],
    "decisions": [ { "stage": "CS",  "stageLabel": "Client Servicing", "decision": "APPROVED", "reviewer": "Priya M.", "decidedAt": "2026-11-22T04:00:00.000Z", "comment": "" },
                   { "stage": "OPS", "stageLabel": "Recce Operations", "decision": "REWORK",   "reviewer": "Arvind K.", "decidedAt": "2026-11-22T05:10:00.000Z", "comment": "Fix front photo and width" } ],
    "reworks": [ { "id": "6803c0000000000000000c01", "stage": "OPS", "kind": "REWORK", "status": "RESOLVED", "instructions": "Fix front photo and width", "items": [] } ] },
  { "version": 2, "current": true, "submittedAt": "2026-11-22T08:30:00.000Z", "submittedBy": "SR Glass", "notes": "Front retaken, width corrected",
    "mediaItems": [ { "key": "b1", "name": "GSB", "quantity": 2, "width": 8, "height": 4, "unit": "FT" }, { "key": "b2", "name": "Acrylic", "quantity": 1, "width": 4, "height": 2, "unit": "FT" } ],
    "decisions": [], "reworks": [] } ] }
```
`GET {BASE}/recce/shops/:siteId/versions/compare?from=1&to=2`
```json
{ "success": true, "data": {
  "from": { "version": 1, "submittedAt": "2026-11-21T08:00:00.000Z", "submittedBy": "SR Glass", "reviewerComments": [ { "stage": "OPS", "comment": "Fix front photo and width" } ] },
  "to":   { "version": 2, "submittedAt": "2026-11-22T08:30:00.000Z", "submittedBy": "SR Glass", "reviewerComments": [] },
  "photos": { "added": [], "removed": [],
              "replaced": [ { "from": { "id": "6800a0000000000000000e01", "category": "SHOP_FRONT" }, "to": { "id": "6805f0000000000000000f09", "category": "SHOP_FRONT" } } ],
              "unchanged": [ { "id": "6800a0000000000000000e02", "category": "SIDE_VIEW" } ] },
  "mediaItems": { "added": [], "removed": [], "changed": [ { "key": "b1", "name": "GSB", "fields": [ { "field": "width", "from": 6, "to": 8 } ] } ] },
  "installation": [], "notes": { "from": "All angles done", "to": "Front retaken, width corrected" }, "changed": true } }
```
Display as `6 x 4 ft -> 8 x 4 ft`, Front View replaced, the other photos unchanged.

---
## 8. Approval history (time based) and the shop channel

`GET {BASE}/recce/shops/:siteId/activity` (vendor view) and `GET {BASE}/recce-review/submissions/:id/activity` (reviewer view, more detail). Append-only events with type (`SUBMITTED`, `REVIEW_APPROVED`, `REWORK_REQUESTED`, `PHOTO_REPLACED`, `RESUBMITTED`, `SHOP_APPROVED`), actor name and role, version, time, comment, related photo or board key. Admin override reasons are hidden from the vendor.

Channel (vendor, recce operations and client servicing share one thread per shop):
- `GET {BASE}/recce/shops/:siteId/messages?limit=20` (newest first; use `meta.nextBefore` for older), `GET .../messages/unread`, `POST .../messages/read`
- `POST {BASE}/recce/shops/:siteId/messages` JSON `{ "body": "Board is faded, photo attached", "refs": [ { "type": "PHOTO", "id": "6800a0000000000000000e01" }, { "type": "BOARD", "id": "b1" }, { "type": "VERSION", "id": "2" } ] }`, or multipart with `body`, `refs` (JSON string) and one image in `file`.
- System cards (submitted, each stage's decision, rework, final approval) are posted automatically.

Notifications: `GET {BASE}/notifications` (items carry `type` and `siteId`; open the shop by `siteId`).

---
## 9. Error cases to test

| Call | Result |
|---|---|
| any call without or with expired token | `401` (refresh once, then login again) |
| vendor calls `/recce-review/...` | `403 FORBIDDEN` |
| SR Glass opens another vendor's shop | `404` |
| submit with a photo category missing | `422 MISSING_EVIDENCE` |
| submit with `craneRequired` still `NOT_ASSESSED` | `400`, `details[].path = "installation.craneRequired"` |
| edit while `SUBMITTED / UNDER_REVIEW / APPROVED` | `409` |
| same `clientId` uploaded twice | stored once; same file under a new id: `409` |
| second decision by the same stage on one version | `409` |

## 10. Quick order to run it (Postman / curl)
1 vendor-login -> 2 dashboard -> 3 shops -> 4.1 start -> 4.2 boards -> 4.3 installation -> 4.4 six photos -> 4.5 submit V1 -> 5 reviewer rework (login as Operations) -> 6 replace front photo + width 8 -> submit V2 -> 7 versions and compare -> 8 activity and messages.
