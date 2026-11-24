# 12. Media catalog, admin editing and per-board requirements (started 2026-11-24)

Asked for: the admin can add, edit and delete media types, installation types and the site questions of each media type, on the web AND on the phone (an admin login on the phone); the field person can select several media types at once; each board keeps its own photos, installation requirement and answers, and a change of quantity is handled per board.

Today the 13 media cards, 10 installation methods and about 90 questions are written into the phone's code (`lib/data/catalog/signage_catalog.dart`), so nobody can change them without a new app. This work moves them into the database and keeps the built-in copy on the phone only as an offline fallback.

## Milestones (stop and wait for approval after each)

| # | What | State |
|---|---|---|
| **C1** | Backend: catalog data, seed from the built-in list, read API for everyone, edit API for the admin, per-board `mediaCode` / `installationType` / `answers` | **Built 2026-11-24** (this document) |
| C2 | Phone, field flow: read the server catalog (cached, built-in fallback), select several media types in one go, one card per board with Type, Quantity, Size, Photos, Installation, Questions top to bottom, quantity change per board | not started |
| C3 | Web: admin screen "Media catalog" (media, installation types, questions; add, edit, delete, order, active switch, usage) | not started |
| C4 | Phone: admin login (SUPER_ADMIN on the phone) and the same catalog screens | not started. Needs an auth change (web roles are refused on the phone today) |

## C1. What was built

### Data (4 new collections, no project cascade: this is global master data, not owned by a project)

| Collection | Holds | Unique |
|---|---|---|
| `CatalogMedia` | code, shortName, name, description, icon, color, illuminated, sidedness (SINGLE / DOUBLE / SELECTABLE), depthFt, thicknessMm, template, installations[] (codes offered), legacy, active, order | `code` |
| `CatalogInstallation` | code, name, description, icon, active, order | `code` |
| `CatalogQuestion` | scope (COMMON / MEDIA / INSTALLATION), scopeCode, id (the answer key), label, type (TEXT / NUMBER / YES_NO / CHOICE), options[], unit, required, hint, showIfId + showIfValue, active, order | scope + scopeCode + id |
| `CatalogMeta` | one counter `version` raised by every write, and `seededAt` | |

Questions of one board = its installation's questions, then its media's, then the common ones, the first of a key wins (the same rule the phone uses today). `legacy` media (5, kept so old records stay readable) are never offered for a new board.

### Seed

`catalog.seed.ts` was generated ONCE from the phone's catalog: 18 media (13 offered + 5 legacy), 10 installations, 93 questions (4 common). The first read or write loads it when `seededAt` is empty, so a new system needs no setup step. After that **the database is the master**: the seed only adds an entry whose code / key is missing and never overwrites an edit. `POST /catalog/defaults` ("Load built-in defaults") adds back any built-in entry that was deleted; a catalog the admin empties is not refilled by itself.

### API (all under `/api/v1/catalog`, bearer token)

| Method and path | Who | What |
|---|---|---|
| `GET /` and `GET /?version=N` | any signed-in role | Everything in one answer. With the current version: `{ "version": 14, "unchanged": true }` |
| `GET /usage` | admin | boards using each media / installation: `{ media: { GSB: 2 }, installations: { shop_fascia: 2 } }` |
| `POST /media`, `PUT /media/:code`, `DELETE /media/:code` | admin | |
| `POST /installations`, `PUT /installations/:code`, `DELETE /installations/:code` | admin | |
| `POST /questions`, `PUT /questions/:uid`, `DELETE /questions/:uid` | admin | `uid` = the question's database id |
| `POST /reorder` `{ kind: "media" \| "installations" \| "questions", ids: [...] }` | admin | codes, or the question uids of ONE group |
| `POST /defaults` | admin | `{ media: 0, installations: 0, questions: 1 }` entries added back |

Admin = the new permission `catalog:manage`, held by SUPER_ADMIN only. A vendor or recce login gets `403` on every write and on `/usage`.

`GET /catalog` (trimmed):
```json
{ "version": 14, "unchanged": false,
  "media": [ { "code": "GSB", "shortName": "GSB", "name": "GSB Board (Glow Sign Board)", "description": "Back-lit flex/ACP box ...", "icon": "lightbulb_outline", "color": "#D71920",
               "illuminated": true, "sidedness": "SELECTABLE", "depthFt": 0.75, "thicknessMm": 0, "template": "gsb",
               "installations": ["shop_fascia", "wall_mount", "double_pole", "single_pole", "rooftop", "support_pipe"], "legacy": false, "active": true, "order": 0 } ],
  "installations": [ { "code": "shop_fascia", "name": "Shop Fascia", "description": "Fixed on the shop front elevation above the shutter.", "icon": "storefront_outlined", "active": true, "order": 0 } ],
  "questions": [ { "uid": "6b0...", "scope": "COMMON", "scopeCode": "", "id": "remove_existing", "label": "Existing board removal required?", "type": "YES_NO", "options": [],
                   "unit": null, "required": true, "hint": null, "showIfId": "existing_board", "showIfValue": true, "active": true, "order": 1 } ] }
```
Create a question: `POST /questions` `{ "scope": "MEDIA", "scopeCode": "GSB", "id": "led_colour", "label": "LED colour", "type": "CHOICE", "options": ["White","Warm white","RGB"], "required": false }` gives `201` with the stored question.

Errors (real): `422 VALIDATION_ERROR` (bad shape), `400 BAD_REQUEST` ("Unknown installation type nope", "GSB Board is not offered for ..."), `404`, `409 CONFLICT` ("A media type with code X already exists", "GSB Board (Glow Sign Board) is used by 1 board already. Mark it inactive instead of deleting it.").

### Rules

- **Edits never rewrite a recce.** A board stores the media NAME, `mediaCode`, `installationType` and the answers as plain values. Renaming or deleting a catalog entry changes nothing already recorded.
- **A used entry cannot be deleted** (409, counted over all recces: by `mediaCode`, or by name for older boards); the admin makes it `active: false` instead. Inactive = not offered for a new board, still known to the boards that use it. An unused one can be deleted. Deleting a media type deletes its own questions; deleting an installation type takes it off every media type and deletes its questions. Answers already given stay on their boards under their key.
- A question's scope, key and type cannot change after it is made (answers are stored under the key and its type): delete it and make a new one.
- **An edit sends only what changes.** The edit schemas carry no defaults; a first version that did filled every field not sent and overwrote the stored values (found by the test that checks an edit that changes nothing leaves the version alone).
- An edit that changes nothing does not raise the version. Every CRUD write is audited (`AuditLog`: who, what field, old and new value).
- Typed text: no control characters and no `<` `>`; lengths are capped (name 80, label 120, option 60, answer 300; at most 60 media, 40 installations, 40 questions per group, 20 options per question).
- Icons come from a fixed list of 32 names (`CATALOG_ICONS`); the phone and the web each map a name to their own icon. The 3D `template` is not editable (a new media type uses the generic model).

### Per-board fields (`PUT /recce/shops/:siteId/draft`, `mediaItems[]`, all optional)

| Field | Rule |
|---|---|
| `mediaCode` | catalog code, `^[A-Z0-9_]{2,30}$`; must be an active media type when it is new or changed |
| `installationType` | catalog installation code; must be active, and offered for the board's media, when new or changed |
| `answers` | object, at most 60 keys; key `^[a-z0-9_]{1,50}$`; value a trimmed string up to 300, a number, or true / false |

Checked only when the value **changed** against what the board already holds, so an older draft that carries an installation since made inactive or deleted can still be saved as it is. Answers are not matched against the questions on the server (a deleted question would otherwise block saving an old draft). Responses and version snapshots carry `mediaCode`, `installationType` (null when none) and `answers` (`{}` when none); the version comparison lists a change of installation or answers per board. As with the seven photos, **"every required question is answered" is enforced on the phone** (as today), not by the server. Say if the server should block the submit too.

Note for C2: a draft save replaces the whole `mediaItems` list, so a client that does not send these three fields clears them. The phone as it is today does not send them (it does not know them yet); C2 must carry `mediaCode`, `installationType` and `answers` through `BoardItem` before any board gets them.

### Files

New: `src/modules/catalog/` (`catalog.types.ts`, `catalog.model.ts`, `catalog.validators.ts`, `catalog.service.ts`, `catalog.routes.ts`, `catalog.seed.ts`), `tests/catalog.test.ts`.
Changed: `roles.ts` (permission `catalog:manage`), `app.ts` (route), `recceReview.model.ts`, `recceReview.field.ts`, `recceReview.common.ts`, `recceReview.versions.ts`.
Env: none added.

### Tests

`tests/catalog.test.ts`: 22 pass (first read seeds 18 / 10 / 93; version and "unchanged"; vendor refused on every write; media add / edit / delete with cascade and in-use block; installation add / delete with cascade and in-use block; question rules per type; immutable scope / key / type; null clears a value; order; load defaults keeps an edit; board fields stored, validated, older draft kept, usage counts).

Full backend suite (one clean run, 2026-11-24): 1210 pass, 16 fail. None of the 16 is in the catalog, recce or files tests. They are the older failures of `bd-crm-unit`, `client-servicing` (2), `handover-import-unit`, `recce-codes-validator` (2), `role-home` (2), `signage-code-mail` (4), `signage-vendor-mail` (2), `vendors-zoho-kyc`, and one `project-cascade` test that failed once under load and passed 3 of 3 alone (a fire-and-forget notification arriving after the delete). An earlier run showed 51 failures because two suites ran at the same time and the machine ran out of memory: run the backend suite one at a time.

## Open for the next milestones

1. **Order of the next milestones.** C2 (phone field flow) is what the field person sees and was asked for first; C3 and C4 give the admin the screens. Tell me if you want C3 (web admin) first.
2. **Admin on the phone (C4)** means a SUPER_ADMIN account may sign in on the phone, limited to the catalog screens and profile. Today `auth.service` refuses web roles on the mobile platform on purpose. Confirm before I change that.
3. The measurement fields and site checklists of the older offline app (`measurement_fields.dart`, `site_checklists.dart`) are NOT part of this catalog; only media types, installation types and site questions are.
