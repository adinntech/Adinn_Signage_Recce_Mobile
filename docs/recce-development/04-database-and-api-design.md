# 04 - Database and API design (one project, one shop, full flow)

Base URL: `{API_BASE_URL}` = `http://<host>:4000/api/v1` (dart-define `API_BASE_URL`). All responses use the envelope
`{ "success": true, "message": "...", "data": ..., "meta": ... }`; errors are `{ "success": false, "message": "...", "error": { "code": "...", "details": [] } }`.
Header on every call after login: `Authorization: Bearer <accessToken>`. Dates are UTC ISO-8601.

Legend: **[EXISTS]** verified in `Signage_Backend/.../recce-review` and used by `Signage_Recce_Mobile`; **[NEW]** added in this work (backend).

Scenario used below: project `ADN-2451 South Zone Retail Rollout`, vendor `Siva Creations`, shop `SM-0234 Sri Murugan Super Market`.
Ids are Mongo ObjectIds (`siteId`, `projectId`, `submissionId`).

---
## 1. Authentication [EXISTS] (same as Project B)

| Step | Method + URL | Body |
|---|---|---|
| In-house / vendor login | `POST /auth/login` | `{"identifier":"emp101","mpin":"1234","loginRole":"RECCE","platform":"mobile"}` (or `"password":"..."`); `loginRole` is `RECCE` or `VENDOR` |
| Vendor ID login | `POST /auth/vendor-login` | `{"vendorId":"4821"}` (last 4+ digits of vendor ID) |
| Create account | `POST /auth/register` | `{"name","email","phone"(10 digits),"employeeId","role":"RECCE_EXECUTIVE"\|"VENDOR","platform":"mobile","authMethod":"MPIN"\|"PASSWORD","mpin":"1234"}` |
| Forgot | `POST /auth/forgot` `{identifier}` then `POST /auth/forgot/confirm` `{identifier,code,authMethod,newSecret,confirmReuse?}` | |
| Refresh | `POST /auth/refresh` | `{"refreshToken":"..."}` (rotated token must be saved) |
| Me / Logout | `GET /auth/me`, `POST /auth/logout` | |

Success: `data = { accessToken, refreshToken, user:{ id, name, email, role, vendorId?, mustChangeCredential? ... } }`.
Rules: roles `VENDOR`, `RECCE_EXECUTIVE` are mobile-only. Vendor default login forces an MPIN change (`POST /users/me/change-credential`).

## 2. Assignment [EXISTS]

Operations assigns shops on the web; the mobile only reads them. The backend filter is the security boundary: vendor -> shops of the vendor linked to the login (`assignedTo` me or unassigned-in-vendor), in-house -> `assignedTo = me`. Another vendor's shop returns **404**.

`GET /recce/shops?projectId=&q=&status=&page=1&limit=50` (roles VENDOR, RECCE_EXECUTIVE)

```json
{ "success": true, "data": [ {
  "siteId":"67f0...a1","projectId":"67e9...c4","projectCode":"ADN-2451","projectName":"South Zone Retail Rollout","client":"ABC Retail",
  "siteCode":"SM-0234","shopName":"Sri Murugan Super Market","address":"T. Nagar, Chennai, 600017","contactPerson":"Murugan","mobile":"9876543210",
  "mediaTypes":[{"name":"GSB","quantity":2},{"name":"Acrylic","quantity":1}],
  "assignedAt":"2026-11-20T05:00:00.000Z","expectedBy":"2026-11-28T00:00:00.000Z",
  "status":"NOT_STARTED","progress":0,"photoCount":0,"missing":8,"reworkOpen":false,"version":0,"submissionId":null } ],
  "meta": { "page":1,"limit":50,"total":1,"summary":{"NOT_STARTED":1} } }
```
Projects screen = group this list by `projectId`. Status values: `NOT_STARTED, IN_PROGRESS, DRAFT, READY_TO_SUBMIT, SUBMITTED, UNDER_REVIEW, APPROVED, REWORK_REQUIRED, REJECTED` (DRAFT / READY_TO_SUBMIT computed by the server). Requested names `RESUBMITTED/COMPLETED` map to: v2 `SUBMITTED/UNDER_REVIEW` and `APPROVED`.

## 3. Open shop and start recce

`GET /recce/shops/:siteId` [EXISTS] returns shop, project, `status`, `editable`, `version`, `mediaItems[]`, `photos[]`, `categories[]`, `progress{percent,required,done,missing[]}`, `versions[]`, `reviews[]`, `reworks[]`, plus [NEW] `installation` and per-photo `review`.
`POST /recce/shops/:siteId/start` [EXISTS] body `{}` creates the working record (status `IN_PROGRESS`) and an audit event. It also reassigns safely if the shop was moved to this login.

## 4. GPS-tagged photos (6 categories)

Categories `categories[].key`: `SHOP_FRONT` (= Front View), `SIDE_VIEW`, `LONG_SHOT`, `ANNOTATED_VIEW`, `LOCATION_VIEW`, `ACCESS_PATH` [NEW five; older keys such as `LEFT_SIDE`, `MEASUREMENT` remain]. Required set is `RecceConfig.requiredPhotos` (Admin, `PUT /recce-review/config`).

`POST /recce/shops/:siteId/photos` [EXISTS] multipart/form-data: file field `photos` (one or more), text field `meta` = JSON array, one object per file in the same order.

```json
[{ "clientId":"c1732170000000123456","category":"SHOP_FRONT","mediaKey":"b1","caption":"Front",
   "capturedAt":"2026-11-21T06:30:00Z","lat":13.0412,"lng":80.2345,"gpsAccuracy":8.2,"width":3000,"height":4000,
   "source":"LIVE_CAMERA","device":"Android 14 / Adinn Recce 1.0" }]
```
`mediaKey` ties the photo to a board item (optional). Every photo carries its own lat/lng/accuracy/time. `clientId` is the idempotency key (same id = stored once; same file twice = 409 "already uploaded"). Response 201 = full shop detail (as in section 3) with the photo in `photos[]`:

```json
{ "id":"6800..e1","category":"SHOP_FRONT","categoryLabel":"Full Shop Front View","state":"DRAFT","mediaKey":"b1","caption":"Front",
  "capturedAt":"2026-11-21T06:30:00.000Z","lat":13.0412,"lng":80.2345,"gpsAccuracy":8.2,"flags":[],"gpsVerified":true,
  "source":"LIVE_CAMERA","uploadedBy":"Siva Creations","url":"<file url>","review":{"status":"PENDING","openRework":null} }
```
Server flags (kept, shown to reviewer): `GPS_MISSING, GPS_ZERO, GPS_FAR (>1 km from shop), GPS_WEAK (>200 m), TIME_FUTURE, TIME_OLD, TIME_MISSING, LOW_RESOLUTION`. If config `requireGps` is true, submit is refused while a required photo has no usable GPS. The app never substitutes the shop's registered location.

Other photo calls [EXISTS]: `PATCH .../photos/:photoId` `{category?,mediaKey?,caption?,order?}`, `DELETE .../photos/:photoId?reason=` (draft = erased; submitted only in rework, soft remove with reason), `PUT .../photos/order` `{ids:[]}`, `PUT .../photos/:photoId/annotation` multipart `edited` (annotated image copy, original untouched) + `annotations` JSON `[{"type":"rect|line|arrow|text|measure","x":0.1,"y":0.2,"w":0.3,"h":0.1,"text":"6 ft","color":"#ff0000"}]`.
Replace a rejected photo: upload with `meta.replaces = <old photoId>` (old becomes `SUPERSEDED`, still in v1 history).

## 5. Board items and measurements

`PUT /recce/shops/:siteId/draft` [EXISTS, extended]

```json
{ "mediaItems":[
   {"key":"b1","name":"GSB","quantity":2,"width":6,"height":4,"unit":"FT","sided":"SINGLE","condition":"PROPOSED","position":"Shop fascia","notes":""},
   {"key":"b2","name":"Acrylic","quantity":1,"width":4,"height":2,"unit":"FT"} ],
  "installation":{ "ladderRequired":"YES","scaffoldingRequired":"NO","craneRequired":"NO","hydraRequired":"NO","manualInstallationPossible":"YES",
                   "electricalAccess":"AVAILABLE","installationHeightFt":12,"accessRestrictions":[],"obstruction":"","roadsideConstraints":"","safetyNotes":"","additionalEquipment":[],"notes":"Ladder access available" },
  "notes":"Shop open from 9 am" }
```
`sided, condition, position, installationNotes` and `installation` are [NEW]. Same-size boards = one item with `quantity`. **Different sizes = separate items with unique `key`** (e.g. `b1` GSB 6x4, `b3` GSB 8x4) so each physical board keeps its identity during rework. Tri-state values: `YES | NO | NOT_ASSESSED` (default NOT_ASSESSED, never read as NO). Items with photos cannot be dropped (409). Response 200 = shop detail.

## 6. Submit Version 1

`POST /recce/shops/:siteId/submit` [EXISTS, validation extended]
Request `{"idempotencyKey":"submit-67f0...a1-1","notes":"All angles done"}`
Success 200 -> `{"duplicate":false,"version":1,"detail":<shop detail with status "UNDER_REVIEW" or "SUBMITTED", version 1>}`. A repeated key returns `duplicate:true` with the same version.
Check order: 422 `MISSING_EVIDENCE` (photos, dimensions), 422 `GPS_REQUIRED`, unresolved rework, then 400 installation incomplete (`details:[{"path":"installation.craneRequired","message":"craneRequired is not assessed"}]`).
Server work: immutable `RecceVersion` snapshot (photos, mediaItems, installation, notes, submitter, time); creates one pending `RecceReview` per stage (OPS = Recce Operations, CS = Client Servicing, order from config); notifies reviewers; posts a card in the shop thread; writes `AuditLog`.
Errors: 400 `VALIDATION_ERROR` missing required photos / dimensions / [NEW] installation fields still `NOT_ASSESSED` / [NEW] GPS when required; 409 already submitted or locked; same `idempotencyKey` repeated returns the same version (no v2 created).

## 7. After submit (Milestone 2/3 contracts, already available)

| Need | API |
|---|---|
| Shop thread (text + system events) | `GET/POST /recce/shops/:siteId/messages` (`{"body":"..."}`) |
| Timeline (approved history, time based) | `GET /recce/shops/:siteId/activity` |
| Reviewer inbox / workspace | `GET /recce-review/inbox`, `GET /recce-review/submissions/:id` |
| Approve / Reject / Rework (per photo, measurement) | `POST /recce-review/submissions/:id/decision` |
| Version list + compare (6x4 -> 8x4) | [NEW] `GET /recce/shops/:siteId/versions`, `GET /recce/shops/:siteId/versions/compare?from=1&to=2` |
| Per-photo history | [NEW] `GET /recce/shops/:siteId/photos/:photoId/history` |

Review decision body: `{"stage":"OPS"|"CS","decision":"APPROVE"|"REJECT"|"REWORK"|"ADDITIONAL","versionNo":1,"comment":"","checklist":[{"key":"shop_front","passed":true}],"reason":"","items":[{"type":"REPLACE_PHOTO","category":"SHOP_FRONT","photo":"<photoId>","note":"Board not clear"},{"type":"FIX_MEASUREMENT","mediaKey":"b1","note":"Width is 8 ft"}]}`.
Rules: each stage decides alone and once per version; overall `APPROVED` only when every required stage approved the **current** version; v1 approvals never carry to v2; a worker cannot review (role check in the backend). Rework keeps v1 and the owner replaces only the flagged items, then submits v2 (`POST .../submit` with a new key).

## 8. Collections (all existing, owned by project cascade)

`RecceSubmission` (one per shop, `mediaItems`, [NEW] `installation`), `ReccePhoto` (per-photo GPS/time, [NEW] `source`, `device`), `RecceVersion` (immutable snapshot, [NEW] `installation`), `RecceReview` (unique per version+stage), `RecceRework`, `RecceConfig`, `AuditLog` (timeline), Connect channel/messages (shop thread). Indexes already on project, site (unique), assignee, status, pendingStage, `(submission,state,order)`, `(submission,clientId)` unique.

## 9. Flutter mapping (Project A)

| Screen | Service call |
|---|---|
| Login / Register / Forgot | `AuthService.login / vendorLogin / register / requestReset / confirmReset` |
| Dashboard + Projects + Shops | `RecceApi.shops()` (group by project; counts from `meta.summary`) |
| Shop details | `RecceApi.detail(siteId)`, `start(siteId)` |
| Photo capture | `UploadQueue.add(UploadItem)` -> `RecceApi.uploadPhoto` (2 parallel, retry, saved on phone) |
| Boards + installation | `RecceApi.saveDraft(siteId, mediaItems:, installation:, notes:)` |
| Submit | `RecceApi.submit(siteId, key)` |
| Versions / compare / history | `RecceApi.versions / compare / photoHistory / activity` |
