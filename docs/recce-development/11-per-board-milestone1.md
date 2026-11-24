# 11. Per-board workflow, Milestone 1 (2026-11-24)

Flow now: Shop > Boards tab > **Add boards** > Media type > Quantity > Measurements (same or different sizes) > boards saved > Photos tab (seven photos per board) > Installation > Save / Submit.

Milestone 2 (photo and measurement rework, multi-select rejection) and Milestone 3 (OPS/CS approval, communication, regression) are NOT started.

## 1. What was found before building

| Question | Answer |
|---|---|
| Does the database support one id per physical board? | Yes. `RecceSubmission.mediaItems[]` already has `key` (max 20 characters, unique in the shop). Until now one item could stand for several boards (`quantity` above 1). Milestone 1 makes **one item = one physical board**. |
| Is `boardItemId` a new field? | No. `mediaItems[].key` IS the permanent board id and a photo's `mediaKey` points at it. Nothing was renamed (the prompt asks for no rename). |
| Photo categories | `PHOTO_CATEGORIES` already holds `SHOP_FRONT, NAME_BOARD, LEFT_SIDE, RIGHT_SIDE, MEASUREMENT, ..., SIDE_VIEW, LONG_SHOT, ANNOTATED_VIEW, LOCATION_VIEW, ACCESS_PATH`. **No enum change.** FRONT_VIEW = `SHOP_FRONT`, LEFT_VIEW = `LEFT_SIDE`, RIGHT_VIEW = `RIGHT_SIDE`. |
| Review order OPS / CS | Config `sequential` already defaults to `false` (both stages decide at the same time, since 2026-11-23). Untouched. |
| Is the "mediaKey" photo rule per board? | Yes. Server `missingFor`: a photo satisfies a board if its `mediaKey` is that board's key or empty. The phone now always sends the board key. |

## 2. New backend fields (backward compatible, no migration)

`mediaItems[]` gets two OPTIONAL fields:

| Field | Type | Rule |
|---|---|---|
| `mediaType` | string, max 30 | Short name of the media type as the person saw it ("GSB", "ACP 2D", "Standee 1S"). |
| `seq` | integer 1 to 99 | Number among boards of the same media type. GSB seq 1 = **GSB-01**. |

- A board without them (made before 2026-11-24) is shown by its name and keeps working, including `quantity` above 1. No record is rewritten.
- Responses add `label` ("GSB-01", or the name for an older line), `mediaType` and `seq` (null on older lines).
- Mongo: `recceReview.model.ts` `mediaItemSchema`. No new collection, no new file category, so `PROJECT_OWNED` / the project cascade need no change.

## 3. API contracts (all under `/api/v1`, bearer token)

Roles for all four: the recce login the shop is assigned to (vendor login or in-house recce login). `GET .../shops/:siteId` and the others only ever see the person's own shops (another person's shop is 404).

### 3.1 `PUT /recce/shops/:siteId/draft` (changed: accepts `mediaType`, `seq`)

Request (the three boards of the test):
```json
{
  "mediaItems": [
    { "key": "b1", "name": "GSB Board (Glow Sign Board)", "mediaType": "GSB", "seq": 1, "quantity": 1, "width": 6, "height": 4, "unit": "FT" },
    { "key": "b2", "name": "GSB Board (Glow Sign Board)", "mediaType": "GSB", "seq": 2, "quantity": 1, "width": 8, "height": 4, "unit": "FT" },
    { "key": "b3", "name": "Clear Acrylic", "mediaType": "Acrylic", "seq": 1, "quantity": 1, "width": 3, "height": 2, "unit": "FT" }
  ]
}
```
Response `200`, `data.mediaItems` (real output of `tests/recce-boards.test.ts`; the rest of `data` is the usual shop detail):
```json
[
  { "key": "b1", "name": "GSB Board (Glow Sign Board)", "mediaType": "GSB", "seq": 1, "label": "GSB-01", "quantity": 1, "width": 6, "height": 4, "unit": "FT",
    "notes": "", "sided": null, "condition": null, "position": "", "installationNotes": "", "required": ["SHOP_FRONT", "NAME_BOARD"] },
  { "key": "b2", "mediaType": "GSB", "seq": 2, "label": "GSB-02", "width": 8, "height": 4, "...": "..." },
  { "key": "b3", "mediaType": "Acrylic", "seq": 1, "label": "Acrylic-01", "width": 3, "height": 2, "...": "..." }
]
```
Validation: 1 to 12 items; `key` letters, digits, `_`, `-`, 1 to 20 characters; no two equal keys; no two boards with the same `mediaType` + `seq` (case-insensitive); a board that has live photos cannot be dropped. `required` is read-only (what the server needs for the board).

Errors (real):
```json
{ "success": false, "error": { "code": "BAD_REQUEST", "message": "Two boards have the same number" } }          // 400
{ "success": false, "error": { "code": "BAD_REQUEST", "message": "Each media type needs its own key" } }       // 400
{ "success": false, "error": { "code": "CONFLICT", "message": "A media type that has photos cannot be removed. Delete or move its photos first." } }  // 409
```

### 3.2 `POST /recce/shops/:siteId/photos` (unchanged contract; the phone now sends the board key as `mediaKey`)

`multipart/form-data`: `photos` (file, any picture format, see doc 03) and `meta` (JSON array, one object per file):
```json
[{ "clientId": "c1732170000000123456", "category": "LEFT_SIDE", "mediaKey": "b2", "capturedAt": "2026-11-24T04:30:46.937Z",
   "lat": 9.9, "lng": 78.1, "gpsAccuracy": 8.2, "width": 1600, "height": 1200, "source": "LIVE_CAMERA", "device": "android / Adinn Recce 1.0" }]
```
Response `201`, `data.photos[]` (real, trimmed):
```json
{ "id": "6b0512f75737a6cec5c08c04", "category": "SHOP_FRONT", "mediaKey": "b1", "state": "DRAFT", "version": null,
  "capturedAt": "2026-11-24T04:30:46.937Z", "uploadedAt": "2026-11-24T04:30:46.993Z", "uploadedBy": "VA",
  "lat": 9.9, "lng": 78.1, "gpsAccuracy": null, "replaces": null, "review": { "status": "PENDING", "openRework": null }, "url": "<signed url>" }
```
Validation: `mediaKey` must be a board key of this shop (else 400 `Unknown media type for a photo`); same `clientId` twice stores once. The same picture for another angle (another `clientId`) is accepted: since 2026-11-24 the server no longer compares picture content (section 6c).

### 3.3 `GET /recce/shops/:siteId`

`mediaItems[]` as in 3.1. `progress.missing[]` names the board (real):
```json
{ "mediaKey": "b2", "mediaName": "GSB Board (Glow Sign Board)", "category": "SHOP_FRONT", "label": "Full Shop Front View" }
```
With the default configuration the server asks every board for `SHOP_FRONT` and `NAME_BOARD`. The phone asks for the seven photos below on top.

### 3.4 `POST /recce/shops/:siteId/submit` and `GET .../versions`

Unchanged. Version snapshots copy `mediaItems` (now with `mediaType`, `seq`), so V1 keeps GSB-01 as it was.

## 4. Mobile

| Rule | Where |
|---|---|
| One media type selector, the old card design | `features/board/media_type_grid.dart` (`MediaTypeGrid`), used by the old board editor AND "Add boards" |
| Add boards: type, quantity, same or different sizes, per-board size boxes named GSB-01, GSB-02 ... | `live_recce/presentation/add_boards_screen.dart` |
| Boards are saved the moment they are added (photos need a saved board) and a refused save changes nothing | `ShopDetailController.addBoardsOfType` |
| Numbered board: type fixed, no quantity box; a board with photos cannot be removed | `boards_tab.dart`, `boardHasPhotos` |
| Photos tab: one section per board, header "GSB-01 6 x 4 ft  3 / 8", seven tiles plus server extras (NAME_BOARD) | `photos_tab.dart`, `boardPhotoCategories`, `extraTilesFor` |
| Seven photos: Front View, Left View, Right View, Long Shot, Annotated View, Location View, Access Path | `recce_models.dart` `boardPhotoCategories` |
| Submit check names the board ("GSB-02: Front View photo is missing"); one board keeps the short text | `submit_validator.dart` |
| Files list shows "GSB-02 · Front View" when the shop has more than one board | `photos_tab.dart` |
| Testing checkbox now fills every empty place of EVERY board | `queueFirstPhotoForAll`, `photoSlots` |

Web review workspace (display only): "Media types" lists GSB-01 / GSB-02 with their own sizes, and each photo thumbnail carries its board number when the shop has more than one board (`components/recce-review/workspace.tsx`, `lib/api/recceReview.ts` `boardLabel`).

## 5. Files changed

Backend: `recceReview.model.ts`, `recceReview.field.ts`, `recceReview.common.ts`, `recceReview.versions.ts`; tests `recce-boards.test.ts` (new).
Mobile: `board/media_type_grid.dart` (new), `board/board_editor_screen.dart` (uses it), `live_recce/presentation/add_boards_screen.dart` (new), `boards_tab.dart`, `photos_tab.dart`; `live_recce/data/recce_models.dart`, `recce_controllers.dart`, `recce_api.dart`, `submit_validator.dart`; tests `live_recce_boards_test.dart` (new), `live_recce_test.dart`, `live_recce_fix_test.dart`, `live_recce_m2_test.dart` (six photos became seven).
Web: `lib/api/recceReview.ts`, `components/recce-review/workspace.tsx`.
Env: none added in this milestone.

## 6. Tests

- Backend: 137 pass across the recce, files and cascade suites (new: board numbers, same key or number refused, photo tied to one board, older line still works, board with photos kept).
- Mobile: 21 new tests pass (identity, numbering, per-board validator, Add boards controller and screen). `flutter analyze` clean for `lib/features/live_recce`, `lib/features/board` and the touched tests.
- Web: `tsc` and `eslint` clean for the two touched files.
- Failing before and after, not touched here: `live_recce_m3_test.dart` (6: chat tab, dashboard, shop five tabs) and `photo_shrink_test.dart` (2).

## 6a. Guided flow addendum (2026-11-24, mobile only, no backend change)

Reason: the earlier board editor moved on by itself after every choice (media type > installation > ...); the live Boards tab showed a plain "Board type" dropdown and the person had to find the next tab alone.

| Change | Where |
|---|---|
| Boards tab: an older line (no number) picks its type on the same 13 media type cards in a sheet. No dropdown, no free "Type name" text. A single line becomes `GSB-01` style; a line with quantity above 1 only takes the name; a numbered board keeps its type. | `boards_tab.dart` `_pickType`, `ShopDetailController.changeBoardType` |
| After "Add boards" saves, the screen opens the Photos tab. | `BoardsTab.onBoardsAdded` |
| **Board by board (changed the same day, after the first version above).** With several boards the Photos tab opens only the board being photographed; the others are one line each ("GSB-01 6 x 4 ft  7 / 7", tap to open). When the last photo place of that board is filled (stored, or taken and uploading) the screen waits 0.9 s and opens the next board that still lacks photos ("GSB-01 photos done. Next: GSB-02."). When every board has its photos it asks "Is there another board in this shop?": **Add another board** (media type cards, size, then that board's photos) or **No more boards. Continue** (Install, else Review). Each board is announced once. Only while the person is on the Photos tab, only on the change to done (opening a finished shop moves nothing), never during rework (rework and locked shops show every board open). Add boards makes its first new board the open one. | `live_shop_screen.dart` `_watchSteps`, `_boardPhotosFinished`, `_askWhatNext`; `photos_tab.dart` `_closedBoard`; `ShopDetailController.boardPhotosDone`, `firstBoardWithoutPhotos`, `photoBoard`, `focusBoard` |
| Install tab ends with "Continue to Review" (blocked, naming the open questions, until the five required answers are given). It does NOT jump away by itself, because electrical access, height, restrictions and notes sit below the five questions. | `installation_tab.dart` `onNext` |
| A shop with no board opens on Boards (photos need a board). Photos tab with no board shows "Add the boards first" and a button. | `_landOnFirstStep`, `PhotosTab.onAddBoards` |
| Step rules: Boards done = at least one board, each with type and size. Photos done = all seven places of every saved board (plus server extras). Install done = the five required answers, valid height. | `boardsDone`, `photosDone`, `installDone` |

Also fixed: the Photos tab testing checkbox sat in a coloured box without its own Material (Flutter asserted in debug builds and in tests).

### 6d. Boards first, small fixes (2026-11-24, same day)

| Change | Where |
|---|---|
| **Tab order is now Boards, Photos, Install, Review, Chat** (it was Photos first, so the work ran against the tab order). `ShopTab.boards = 0`, `photos = 1`. | `live_shop_screen.dart` `ShopTab`, tab labels, `TabBarView` |
| A shop opens on the step the person is at: no board or a board without size = Boards; photos missing = Photos; installation not answered = Install; everything done = Review. A locked shop or one in rework opens on Photos (flagged photos). A tab asked for (a notification about a message or a review) stays. `LiveShopScreen.initialTab` and `openShop(tab:)` are now nullable (null = decide). | `_landOnFirstStep` |
| "photos complete / another board?" sheet overflowed by 21 px in a small window (it was a plain column in a sheet limited to 9/16 of the height). It scrolls and may use the full height. The "Complete these before submitting" sheet got the same treatment (several boards make it long). | `_askWhatNext`, `_submit` |
| Splash logo appeared late: the picture was loaded when first drawn. `main()` now waits (at most 2 s) for `preloadAdinnLogo()`, so the splash has it in its first frame; the logo box has the logo's own shape (125 x 47) from the start and fades in only if it had to load. | `main.dart`, `common_widgets.dart` |

Tests: five shop-screen tests (tab order, landing on Photos / Install / Review, a requested tab stays, small-window sheet; the small-window test was checked to fail with the old plain-column sheet) and the preload test in `adinn_logo_test.dart`.

### 6c. Same picture for other angles, and folding every board (2026-11-24)

Why it was refused before: the first version of the photo upload (2026-11-23) refused identical picture content twice in one shop, on purpose, so one picture could not stand as proof for two different angles. The product owner asked for it to be allowed ("one good view serves other angles"), so the rule is gone.

| Change | Where |
|---|---|
| Backend: no content comparison on upload. Only a retry of the same upload (same `clientId`) is stored once. `ALLOW_DUPLICATE_RECCE_PHOTOS` and `env.allowDuplicateRecce` deleted from `env.ts`, `.env.example`, `.env.development.example`, `.env.development`. | `recceReview.field.ts` `uploadPhotos` |
| Backend: per-shop photo limit default 40 > **100** (each board has seven photos and a shop may hold 12 boards; 40 allowed only five boards). **The stored configuration in the database keeps its old value** (40 on an existing system): change `maxPhotos` once in the recce review settings (`PUT /api/v1/recce/config`, 100 is the largest accepted). Copies for other angles count as photos too. | `recceReview.model.ts` |
| Phone: the photo preview (Use photo / Retake) has "Use this photo for other angles too". It opens one chip per EMPTY angle of the same board (nothing ticked by default, Select all / Clear). "Use for 3 angles" saves the picture for this angle and the two ticked ones, each copy with its own file and upload id and the same location and time. Not offered when no other angle of the board is empty, nor when retaking or replacing a photo. | `capture_flow.dart` `_PhotoPreview`, `CapturedPhoto.alsoFor`; `photos_tab.dart` `_capture`, `_emptyAnglesOf`; `queueFirstPhotoForAll` |
| Phone: with several boards the open board's own line folds it too (every board one line); a tap on a line opens that board. A single board has nothing to fold. | `photos_tab.dart` `_BoardPhotoHeader.onToggle`; `ShopDetailController.closePhotoBoards` |

Tests: backend `recce-one-document` (same picture for three angles, a retry stored once), `recce-review` (same), `recce-photo-types`; phone `live_recce_same_photo_test.dart` (7) and the fold test in `live_recce_m3_test.dart`.

### 6b. Original Adinn logo on the phone (2026-11-24)

The phone drew its own imitation (a red square with "a" and the text "adinn"). It now shows the website's own artwork.

| What | Where |
|---|---|
| Full logo = the website sidebar file `signage_web/public/Images/Adinn_Logo.svg`, rendered to `assets/images/adinn_logo.png` (600 px wide, transparent). The "A" mark = `Adinn_A_Only_Logo.png`, trimmed, `assets/images/adinn_mark.png`. | `pubspec.yaml` `assets: assets/images/` |
| `AdinnLogo(size, light)` draws that image (height 1.45 x size). `light: true` (red header of the older dashboard) puts it on a white rounded plate so its own red and black stay as designed. Used by splash, login, the sign-in pages and the older dashboard. | `core/widgets/common_widgets.dart` |
| Launcher icon: the Flutter default is replaced by the "A" on white (5 sizes) and an adaptive foreground (5 sizes); adaptive background is white. | `android/app/src/main/res/mipmap-*/ic_launcher.png`, `ic_launcher_foreground.png`, `mipmap-anydpi-v26/ic_launcher.xml`, `values/ic_launcher_background.xml` |
| If the website logo changes: render it again with the same sizes (the one-off script was `make-logos.cjs`: sharp over the two website files). | |

iOS, web and desktop icons are not changed (the phones in use are Android). The launcher icon only changes after a fresh install or rebuild (`flutter run` again), not on hot reload.

Tests: `live_recce_guided_flow_test.dart` (12, new) and four screen tests in `live_recce_m3_test.dart` group "shop screen". Still failing, not from this change: `live_recce_m3_test.dart` six (chat bubble card border at `chat_bubbles.dart:114` "borderRadius needs uniform border colours", chat attach and references, dashboard), `photo_shrink_test.dart` two.

## 7. Decisions for Milestone 2 and 3

1. **Reject one photo of one board.** The data already supports it: a rework item `REPLACE_PHOTO` carries `photo` (the photo id) and `mediaKey` (the board). Web review currently sends `mediaKey: w.mediaItems[0]` for "more photos" requests, which is wrong with several boards; that is fixed in Milestone 2.
2. **Measurement rework per board.** `FIX_MEASUREMENT` items already carry `mediaKey`. Old and new values are in the version snapshots (`mediaItems` of V1 and V2); a field-level change log (`fieldChanged / oldValue / newValue`) is the Milestone 2 addition.
3. **OPS and CS together.** Already the default (`sequential: false`). Say if the business wants sequential again; it is one config value.
4. **Older boards with quantity above 1** are left as they are. A one-time split into numbered boards is possible but would change shops already under review, so it is not done without your approval.
5. The server only requires `SHOP_FRONT` and `NAME_BOARD` per board; the seven-photo rule is enforced on the phone (same as the six-photo rule before). Moving it into the server configuration (`requiredPhotos`) is a one-time admin change if you want web reviewers to see the same rule.
