# 07 - Milestone 2 API payloads (dual approval, rework, versions, history)

Base `{API_BASE_URL}` = `/api/v1`, Bearer token. Envelope `{success,message,data,meta}`. Scenario: shop SM-0234, `siteId = 67f0...a1`, `submissionId = 6801...b2`.

## 1. Reviewer decision (Recce Operations or Client Servicing, web or reviewer login)

`POST /recce-review/submissions/:submissionId/decision` (roles OPERATIONS / RECCE_COORDINATOR = stage `OPS`; CLIENT_SERVICING = stage `CS`)

Approve:
```json
{ "stage":"CS","decision":"APPROVE","versionNo":1,"comment":"Looks good",
  "checklist":[{"key":"correct_shop","passed":true},{"key":"shop_front","passed":true},{"key":"board_area","passed":true}] }
```
Rework only the Front View photo and one measurement (field-level):
```json
{ "stage":"OPS","decision":"REWORK","versionNo":1,"comment":"Fix front photo and width",
  "items":[
    {"type":"REPLACE_PHOTO","category":"SHOP_FRONT","photo":"6800...e1","note":"Board not clear, retake straight on"},
    {"type":"FIX_MEASUREMENT","mediaKey":"b1","note":"Width is 8 ft, not 6 ft"} ] }
```
Other `decision` values: `REJECT` (needs `reason`), `ADDITIONAL` (more photos). Item `type`: `REPLACE_PHOTO | ADDITIONAL_PHOTO | FIX_MEASUREMENT | OTHER`.
Rules: each stage decides once per version; Admin only through `/override`; field worker gets 403; stale `versionNo` -> 409; overall `APPROVED` only when both stages approved the **current** version.
Overall status examples: CS APPROVED + OPS PENDING = `UNDER_REVIEW`; CS APPROVED + OPS REWORK = `REWORK_REQUIRED`; both APPROVED = `APPROVED`.

## 2. Field user sees the rework (shop detail)

`GET /recce/shops/:siteId` -> `status:"REWORK_REQUIRED"`, `editable:true`, and per photo:
```json
{ "id":"6800...e1","category":"SHOP_FRONT","state":"SUBMITTED","lat":13.0412,"lng":80.2345,"gpsAccuracy":8.2,"gpsVerified":true,
  "review":{"status":"REWORK_REQUIRED","openRework":{"reworkId":"6803...c1","itemId":"6803...c2","note":"Board not clear, retake straight on",
    "stage":"OPS","stageLabel":"Recce Operations","instructions":"Fix front photo and width","requestedBy":"Arvind K.","requestedAt":"2026-11-22T05:10:00.000Z"}} }
```
and `reworks[]` with `items[]` (type, category, mediaKey, photo, note, resolved). The other photos keep `review.status:"PENDING"` and are not requested again.

## 3. Replace only the rejected photo

`POST /recce/shops/:siteId/photos` multipart: file `photos`, `meta` = `[{"clientId":"c...","category":"SHOP_FRONT","capturedAt":"2026-11-22T07:00:00Z","lat":13.0413,"lng":80.2346,"gpsAccuracy":6.1,"replaces":"6800...e1","source":"LIVE_CAMERA","device":"Android / Adinn Recce 1.0"}]`.
The old photo becomes `SUPERSEDED` (kept in V1 history); the new one is `DRAFT` until resubmit.

Change the measurement: `PUT /recce/shops/:siteId/draft` `{"mediaItems":[{"key":"b1","name":"GSB","quantity":2,"width":8,"height":4,"unit":"FT"}, ...]}`.

## 4. Resubmit -> Version 2

`POST /recce/shops/:siteId/submit` `{"idempotencyKey":"submit-67f0...a1-2","notes":"Front retaken, width corrected"}` ->
`{"duplicate":false,"version":2,"detail":{...,"status":"SUBMITTED"|"UNDER_REVIEW","version":2}}`. V1 stays immutable; both stages must approve V2 again (V1 approvals never carry over).

## 5. Version list and compare

`GET /recce/shops/:siteId/versions` (also `GET /recce-review/submissions/:id/versions`) -> array oldest first:
```json
[{ "version":1,"current":false,"submittedAt":"2026-11-21T08:00:00.000Z","submittedBy":"Siva Creations","notes":"All angles done",
   "mediaItems":[{"key":"b1","name":"GSB","quantity":2,"width":6,"height":4,"unit":"FT"}],
   "installation":{"ladderRequired":"YES","craneRequired":"NO", "...":"..."},"installationRecorded":true,
   "photos":[{"id":"6800...e1","category":"SHOP_FRONT","lat":13.0412,"lng":80.2345,"capturedAt":"2026-11-21T06:30:00.000Z"}],
   "addedIds":["6800...e1"],"removedIds":[],"stages":["OPS","CS"],
   "decisions":[{"stage":"CS","stageLabel":"Client Servicing","decision":"APPROVED","reviewer":"Priya M.","decidedAt":"2026-11-22T04:00:00.000Z","comment":""},
                {"stage":"OPS","stageLabel":"Recce Operations","decision":"REWORK","reviewer":"Arvind K.","decidedAt":"2026-11-22T05:10:00.000Z","comment":"Fix front photo and width"}],
   "reworks":[{"id":"6803...c1","stage":"OPS","kind":"REWORK","status":"RESOLVED","instructions":"...","items":[]}] },
 { "version":2,"current":true,"...":"..." }]
```
`GET /recce/shops/:siteId/versions/compare?from=1&to=2`:
```json
{ "from":{"version":1,"submittedAt":"...","submittedBy":"Siva Creations","reviewerComments":[{"stage":"OPS","comment":"Fix front photo and width"}]},
  "to":{"version":2,"submittedAt":"...","submittedBy":"Siva Creations","reviewerComments":[]},
  "photos":{"added":[],"replaced":[{"from":{"id":"6800...e1","category":"SHOP_FRONT"},"to":{"id":"6805...f9","category":"SHOP_FRONT"}}],
            "unchanged":[{"id":"6800...e2","category":"SIDE_VIEW"}],"removed":[]},
  "mediaItems":{"added":[],"removed":[],"changed":[{"key":"b1","name":"GSB","fields":[{"field":"width","from":6,"to":8}]}]},
  "installation":[],"notes":{"from":"All angles done","to":"Front retaken, width corrected"},"changed":true }
```
Display: `6 x 4 ft -> 8 x 4 ft`, Front View replaced, remaining photos unchanged.

## 6. Photo history and approval history

`GET /recce/shops/:siteId/photos/:photoId/history` -> `{"photoId":"...","revisions":[{"revision":1,"current":false,"id":"6800...e1","capturedAt":"...","lat":..,"lng":..},{"revision":2,"current":true,"id":"6805...f9"}],"events":[{"type":"PHOTO_CAPTURED","at":"...","actor":"..."}],"reworks":[...]}`.

`GET /recce/shops/:siteId/activity` (field) and `GET /recce-review/submissions/:id/activity` (reviewer, more detail) -> chronological audit events, append-only: each has type (e.g. `SUBMITTED`, `REVIEW_APPROVED`, `REWORK_REQUESTED`, `PHOTO_REPLACED`, `RESUBMITTED`, `SHOP_APPROVED`), actor name + role, version, time, comment, related photo / media key. Admin override reasons are hidden from the field user.

## 7. Reviewer read side

`GET /recce-review/inbox?view=pending|mine|all`, `GET /recce-review/submissions/:id` (full workspace: photos with GPS/flags, versions, reviews, reworks, checklist per stage), `POST /recce-review/submissions/:id/start` (mark review started), `POST .../reopen` `{"reason":"..."}` and `POST .../override` `{"action":"APPROVE"|"REJECT","reason":"..."}` (Admin).

## 8. Errors

| Case | Status / code |
|---|---|
| Field worker calls a review route | 403 FORBIDDEN |
| Other vendor's shop | 404 |
| Stage already decided for this version / stale `versionNo` | 409 |
| Edit while `SUBMITTED / UNDER_REVIEW / APPROVED` | 409 with reason text |
| Rework item refers to unknown photo | 400 |
| Unknown version in compare | 404 |
