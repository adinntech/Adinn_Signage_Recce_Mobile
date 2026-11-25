# 12. Media catalog, admin editing and per-board requirements (started 2026-11-24)

Asked for: the admin can add, edit and delete media types, installation types and the site questions of each media type, on the web AND on the phone (an admin login on the phone); the field person can select several media types at once; each board keeps its own photos, installation requirement and answers, and a change of quantity is handled per board.

Today the 13 media cards, 10 installation methods and about 90 questions are written into the phone's code (`lib/data/catalog/signage_catalog.dart`), so nobody can change them without a new app. This work moves them into the database and keeps the built-in copy on the phone only as an offline fallback.

## Milestones (stop and wait for approval after each)

| # | What | State |
|---|---|---|
| **C1** | Backend: catalog data, seed from the built-in list, read API for everyone, edit API for the admin, per-board `mediaCode` / `installationType` / `answers` | **Built 2026-11-24** (this document) |
| C2 | Phone, field flow: read the server catalog (cached, built-in fallback), select several media types in one go, one card per board with Type, Quantity, Size, Photos, Installation, Questions top to bottom, quantity change per board | **Built 2026-11-24** (section C2 below) |
| C3 | Web: admin screen "Media catalog" (media, installation types, questions; add, edit, delete, order, active switch, usage) | files exist (parallel session), not reviewed or tested here |
| C4 | Phone: admin login (SUPER_ADMIN on the phone) and the same catalog screens | files exist (parallel session), not reviewed or tested here |

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

## C2. Phone, field flow (built 2026-11-24)

Flow now, per shop: **Boards** tab > Add boards (tick one or more media types, quantity and size of each) > for each board its **photos** (Photos tab, one board open at a time) > that board's **installation requirement** (Boards tab: installation method, then the site questions) > the next board > site **Install** tab > Review. The tabs are in that order (Boards, Photos, Install, Review, Chat). The Install tab stays what it was: the site-level feasibility (ladder, scaffolding, crane, hydra, manual, electrical, height). The new per-board requirement is a different thing and lives on the board.

### What was built

| Part | Where |
|---|---|
| Catalog on the phone: `CatalogData` (media, installation methods, questions; JSON; lookups `installationsFor`, `questionsFor`, `missingAnswers`), `CatalogData.builtIn()` = the same entries as the older editor, `CatalogController` (built-in copy, then the copy saved on the phone, then the server's; one "since version N" call; a failed read keeps what is held). Read at sign-in and whenever a shop opens. | `live_recce/data/catalog_data.dart`, `catalog_controller.dart`, `RecceApi.catalog`, `LiveServices.catalog` (saved under `live_catalog_cache_v1`) |
| `BoardItem` carries `mediaCode`, `installationType`, `answers` (sent only when set; copied by `copy()`) | `recce_models.dart` |
| **Add boards, several media types**: the cards toggle (tick / untick); each ticked type gets its own card with quantity (+ / -), same or different sizes and the numbers it will get; one unit for all; the shop limit (12) is shared by all ticked types; ONE save for everything (`ShopDetailController.addBoards`); the first new board is the one photographed first | `add_boards_screen.dart`, `MediaTypeGrid(selectedCodes:, media:)` |
| **Boards tab**: boards of one media type sit under a header with the quantity (`-` removes the highest-numbered board of the type, `+` adds one like the last: same size, installation and answers, its own number and no photos, saved at once; `-` is off at one board and refuses a board with photos). Each board is a card folded to one line with status chips (Size, Installation, Photos 3/7). A card opens (one at a time) to Size, Installation (the methods of its media type as tiles) and Site questions (the media's, the method's and the common ones), then Photos and Next. | `boards_tab.dart` |
| **Flow**: `_nextWork()` decides what comes next in this order: a board's size, then board by board its photos and its installation, then the site Install, then Review. The last photo of a board opens that board's installation (card open, section in view) when it still has one to fill; "Next" on a board saves what was typed and goes to the next board's photos or installation; when every board is complete it asks "another board?" (Add another board, or Continue). A shop opens on the step the person is at. Rework and locked shops are not moved. | `live_shop_screen.dart` |
| Submit check, first submit only: `GSB-01: choose the installation type`, `GSB-01: answer "Fascia material"` (the board name is left out when the shop has one board) | `submit_validator.dart` `installationProblems`, `ShopDetailController.installationProblems` |

### Rules (decisions)

- **Who must fill it**: a board made from the catalog (numbered, or with a `mediaCode`) whose media type has at least one active installation method, on the FIRST submit only. Older lines and every resubmission are never asked (rework asks only for what the reviewer flagged). The server does not enforce it (the phone does, like the seven photos); say if it should.
- **Quantity** is per media type: each unit is its own board, so each has its own photos, installation and answers. An older line with a quantity above 1 keeps its quantity box.
- **A required question counts only when it shows** (`remove_existing` only when `existing_board` is yes, `power_distance` only when `power_available` is no).
- **A save tidies the answers**: an answer to a question this catalog knows but that no longer applies to the board's installation is dropped (the server keeps at most 60 per board). An answer whose key the phone does not know is kept. Choosing another installation method keeps the answers until the save.
- The media of an older numbered board (made before codes were stored) is found by its name; an older unnumbered line has no catalog media, so the card shows "Choose the media type above first" and nothing is required.
- An admin who makes a media type or installation inactive removes it from new boards only; a board that already holds it keeps it.

### Files

New: `catalog_data.dart`, `catalog_controller.dart`; tests `live_recce_installation_test.dart` (26).
Changed: `recce_models.dart`, `recce_controllers.dart` (`addBoards`, `NewBoards`, board and installation helpers, card state, `boardPhotoProgress`), `recce_api.dart`, `live_services.dart`, `submit_validator.dart`, `add_boards_screen.dart` (rewritten), `boards_tab.dart` (rewritten), `live_shop_screen.dart`, `board/media_type_grid.dart`; tests `live_recce_boards_test.dart` (Add boards group rewritten for several types), `live_recce_guided_flow_test.dart`, `live_recce_m3_test.dart` (six new flow tests).

### Tests

`flutter analyze lib test`: clean except two old warnings (`report_service.dart`, `photo_render.dart`). New and changed tests pass: installation 26, Add boards screen 7, six new shop screen flow tests. The older failures are the same as before this work (`live_recce_m3_test.dart` chat and dashboard, `photo_shrink_test.dart`).

### C3 and C4

The web admin screen (`signage_web/app/(app)/admin/media-catalog`, `components/admin/media-catalog/*`, `lib/api/catalog.ts`) and the phone admin screens (`lib/features/catalog_admin/*`, the admin login in `live_auth`) were written in a parallel session while C2 was being built. **They are not reviewed or tested here**; the milestone table below says "not started" for them only because this document was written before. Check them against the API in section C1 before relying on them.

## Open for the next milestones

1. **Order of the next milestones.** C2 (phone field flow) is what the field person sees and was asked for first; C3 and C4 give the admin the screens. Tell me if you want C3 (web admin) first.
2. **Admin on the phone (C4)** means a SUPER_ADMIN account may sign in on the phone, limited to the catalog screens and profile. Today `auth.service` refuses web roles on the mobile platform on purpose. Confirm before I change that.
3. The measurement fields and site checklists of the older offline app (`measurement_fields.dart`, `site_checklists.dart`) are NOT part of this catalog; only media types, installation types and site questions are.
