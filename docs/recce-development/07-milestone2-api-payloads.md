# 07 - Review payloads: dual approval, rework, versions, history

Base `{BASE}` = `/api/v1`, Bearer token, envelope `{success, data, meta}`. Scenario: shop SM-0234, `siteId = 67f0...a1`, `submissionId = 6801...b2`. The same calls with a full shop are in 09; `10` shows the tested output.

## 1. Who reviews, and the two review modes

`POST /recce-review/submissions/:submissionId/decision` - roles OPERATIONS / RECCE_COORDINATOR = stage `OPS`; CLIENT_SERVICING = stage `CS`. A field worker gets 403, Admin only through `/override`.

Admin setting `sequential` (`PUT /recce-review/config`):

| | `false` = parallel (default for new databases) | `true` = sequential |
|---|---|---|
| At submit | OPS and CS both get the notification and the shop in their inbox | only the first stage; the next one after it approves |
| CS approves first | 200 | `409 An earlier review stage must approve first` |
| Both decide at the same moment | both 200 | n/a |

An existing database keeps its old value: send `{"sequential": false}` once to switch.

## 2. Outcome table (both modes)

| OPS | CS | Shop status |
|---|---|---|
| APPROVED | APPROVED | `APPROVED` |
| APPROVED | pending | `UNDER_REVIEW` |
| REWORK | APPROVED or pending | `REWORK_REQUIRED` |
| REJECTED | anything | `REJECTED` (reject beats rework beats approve) |

Rules: each stage decides **once per version**; stale `versionNo` -> 409; `APPROVED` only when every stage approved the **current** version (v1 approvals never count for v2); a reject / rework voids the other stage's waiting review; two decisions at the same instant never roll back each other, and if both write the same outcome both calls return 200.
Tested (`recce-19steps`, A-H): approve+approve together = APPROVED; reject+reject = REJECTED; approve+reject = REJECTED; approve+rework = REWORK_REQUIRED; same stage twice = 409; wrong stage = 403; `sequential: true` -> CS first = 409.

## 3. Decision payloads

Approve:
```json
{ "stage":"CS","decision":"APPROVE","versionNo":1,"comment":"Looks good",
  "checklist":[{"key":"correct_shop","passed":true},{"key":"shop_front","passed":true},{"key":"board_area","passed":true}] }
```
Rework only the Front View photo and one measurement (field level; the other photos are not asked again):
```json
{ "stage":"OPS","decision":"REWORK","versionNo":1,"comment":"Fix front photo and width",
  "items":[
    {"type":"REPLACE_PHOTO","category":"SHOP_FRONT","photo":"6800...e1","note":"Board not clear, retake straight on"},
    {"type":"FIX_MEASUREMENT","mediaKey":"b1","note":"Width is 8 ft, not 6 ft"} ] }
```
`decision`: `APPROVE | REJECT (needs "reason") | REWORK | ADDITIONAL (more photos)`. Item `type`: `REPLACE_PHOTO | ADDITIONAL_PHOTO | FIX_MEASUREMENT | OTHER`.

Change an approval later: `POST /recce-review/submissions/:id/change-decision` same body with `decision` = `REJECT | REWORK | ADDITIONAL` and a reason of 5+ characters (`reason` for reject, `comment` otherwise; rework / more-photos `items` as above). Only the stage's own login, on the current version, while the shop is still with the review teams or after final approval. One atomic update: new decision and status (`REJECTED` or `REWORK_REQUIRED`), the old answer kept in `reviews[].history`, the other stage's waiting review `VOID`, rework opened, `finalApprovedAt` cleared; event `DECISION_CHANGED`. The workspace (`GET /submissions/:id`) returns `me.canChange` (true only for a stage that holds an approval). Refused: stage has not approved 409, other team 403, vendor 403, old `versionNo` 409, short reason 400, `APPROVE` as the new answer 422. Tested in `tests/recce-change-decision.test.ts`.

Admin: `POST .../override` `{"action":"APPROVE"|"REJECT","reason":"..."}` decides every still-pending stage; `POST .../reopen` `{"reason":"..."}` sends the shop back to `IN_PROGRESS`.

## 4. Field user sees the rework

`GET /recce/shops/:siteId` -> `status:"REWORK_REQUIRED"`, `editable:true`, and on the flagged photo:
```json
{ "id":"6800...e1","category":"SHOP_FRONT","state":"SUBMITTED","gpsVerified":true,
  "review":{"status":"REWORK_REQUIRED","openRework":{"reworkId":"6803...c1","itemId":"6803...c2","note":"Board not clear, retake straight on",
    "stage":"OPS","stageLabel":"Recce Operations","instructions":"Fix front photo and width","requestedBy":"Arvind K.","requestedAt":"2026-11-22T05:10:00.000Z"}} }
```
Other photos keep `review.status:"PENDING"`. `reworks[]` carries `items[]` (type, category, mediaKey, photo, note, resolved).

## 5. Replace, change, resubmit (Version 2)

1. Replace only the flagged photo: `POST /recce/shops/:siteId/photos` with `meta.replaces = "6800...e1"` (old = `SUPERSEDED`, new = `DRAFT`).
2. Change the measurement: `PUT /recce/shops/:siteId/draft` `{"mediaItems":[{"key":"b1","name":"GSB","quantity":2,"width":8,"height":4,"unit":"FT"}, ...]}`.
3. `POST /recce/shops/:siteId/submit` `{"idempotencyKey":"submit-67f0...a1-2","notes":"Front retaken, width corrected"}` -> `{duplicate:false, version:2}`. V1 stays immutable; every stage reviews V2 again.

## 6. Versions, compare, history

* `GET /recce/shops/:siteId/versions` (reviewer twin `/recce-review/submissions/:id/versions`) -> array oldest first: `{version, current, submittedAt, submittedBy, notes, mediaItems[], installation, photos[], addedIds, removedIds, stages, decisions[{stage, decision, reviewer, decidedAt, comment}], reworks[]}`.
* `GET /recce/shops/:siteId/versions/compare?from=1&to=2` -> `{from, to, photos:{added, replaced:[{from,to}], unchanged, removed}, mediaItems:{added, removed, changed:[{key, name, fields:[{field:"width", from:6, to:8}]}]}, installation[], notes:{from,to}, changed}`. Show `6 x 4 ft -> 8 x 4 ft`, Front View replaced, rest unchanged. Full example in 09 section 5.
* `GET /recce/shops/:siteId/photos/:photoId/history` -> `{photoId, revisions[{revision, current, id, capturedAt, lat, lng}], events[], reworks[]}`.
* `GET /recce/shops/:siteId/activity` and `GET /recce-review/submissions/:id/activity` (more detail) -> append-only events: `SUBMITTED`, `REVIEW_APPROVED`, `REWORK_REQUESTED`, `PHOTO_REPLACED`, `RESUBMITTED`, `SHOP_APPROVED`, `DECISION_CHANGED` with actor, role, version, time, comment, photo / board. Admin override reasons are hidden from the field user.

## 7. Reviewer read side

`GET /recce-review/inbox?view=pending|mine|all` (in parallel mode `mine` also lists shops where your stage is still pending), `GET /recce-review/submissions/:id` (photos with GPS and flags, versions, reviews, reworks, checklist per stage), `POST .../start`, `PUT .../reviewer`.

## 8. Errors

| Case | Status / code |
|---|---|
| Field worker calls a review route | 403 FORBIDDEN |
| Wrong stage for your role | 403 |
| Other vendor's shop | 404 |
| Stage already decided / stale `versionNo` | 409 |
| Sequential mode, earlier stage not approved | 409 |
| Edit while `SUBMITTED / UNDER_REVIEW / APPROVED` | 409 with reason text |
| Rework item points to an unknown photo | 400 |
| Unknown version in compare | 404 |
