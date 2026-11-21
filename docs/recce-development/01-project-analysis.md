# 01 - Project analysis

## Projects

| | Path | Role |
|---|---|---|
| A (target) | `Recce_mobile_FullApp/Signage_Recce` | Flutter, Provider + ChangeNotifier (`AppController`, ~2600 lines), red/white Adinn theme, 109 Dart files. **Offline prototype**: local JSON store, mock seed, no HTTP, no login against a server. |
| B (reference, read-only) | `Signage_Recce_Mobile` | Flutter, Riverpod + Dio, 55 Dart files, blue/navy theme. Real login, register, forgot, vendor-ID login, assigned shops, shop-wise evidence upload. |
| Backend | `Signage_Backend/signage-recce-backend` | Node + TypeScript + Mongo (Atlas). Module `src/modules/recce-review` already implements the shop recce, photos, versions, two-stage review, rework, timeline, thread (see `docs/16-recce-photo-review-workflow.md`). |

## Status classification

**Existing and verified (backend, used by B)**
- Auth: `/auth/login`, `/auth/vendor-login`, `/auth/register`, `/auth/forgot`, `/auth/forgot/confirm`, `/auth/refresh`, `/auth/logout`, `/auth/me`; JWT access + rotating refresh; role/platform restriction.
- Assignment: Operations assigns on web; `/recce/shops` returns only this login's shops; other vendor's shop = 404.
- Shop recce: start, draft (media items + notes), photos (multipart, per-photo GPS/time/accuracy, idempotent `clientId`, sha256 duplicate refusal, server flags), annotation endpoint, submit with idempotency key, immutable `RecceVersion`.
- Review: two stages (OPS, CS) independent per version, reject/rework/additional with item-level instructions, v2 after rework, v1 approvals never carry over, Admin override/reopen, audit timeline, shop thread, notifications.
- 28 backend tests (docs/16).

**Existing but incomplete (for this request)**
- Photo categories were 10 shop-photo types; the six requested (Front, Side, Long Shot, Annotated, Location, Access Path) were not all present.
- Board items had type/qty/width/height/unit only (no sided, existing/proposed, position).
- No installation feasibility (ladder, scaffolding, crane, hydra, electrical, height) in the recce record.
- Field user could not read version snapshots or compare versions; no per-photo rework flag/history in the shop detail.
- Mobile annotation not wired to the new API; offline queue persists photo uploads only.

**Missing in Project A**: network layer, token storage, login/register against the backend, assigned projects/shops, shop recce screens bound to the API, upload queue.

**Proposed new (this work)**: see 04 and 05.

## A's reusable parts
Theme (`AdinnColors`, `AppTheme`), `common_widgets.dart`, geolocator `LocationService`, image_picker capture, annotation editor, compare/version history widgets (local-data based), PDF report. Its local models (Shop, Board, Photo) do not match the server model; the live flow therefore gets its own models in `features/live_recce`.

## Risks
See 06.
