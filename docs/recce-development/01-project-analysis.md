# 01 - Project analysis and status (2026-11-23)

## Projects

| | Path | Role |
|---|---|---|
| A (target) | `Recce_mobile_FullApp/Signage_Recce` | Flutter, Provider + ChangeNotifier, red / white Adinn theme. The original offline prototype (local JSON store, mock seed) is kept untouched; the **live, server-backed flow** is new code in `lib/core/network`, `lib/core/storage`, `lib/features/live_auth` (login, register, forgot, vendor-ID login, change MPIN) and `lib/features/live_recce` (dashboard, projects, shops, shop tabs, capture, rework sheet, versions, compare, approval history, chat, notifications). |
| B (reference, read-only) | `Signage_Recce_Mobile` | Flutter, Riverpod + Dio, blue / navy theme. Real login, register, forgot, vendor-ID login, assigned shops, shop-wise evidence upload. Must stay unchanged. |
| Backend | `Signage_Backend/signage-recce-backend` | Node + TypeScript + Mongo (Atlas). Module `src/modules/recce-review` (rules: `D:\Projects\Signage\docs\16-recce-photo-review-workflow.md`). |

## Status

**Backend (done, tested in memory: recce-review, m1, m3, 19steps, change-decision, one-document suites)**
- Auth: login, vendor-login, register, forgot, refresh (rotating), logout, me; role / platform restriction.
- Assignment: Operations assigns on the web; `/recce/shops` returns only this login's shops; another vendor's shop = 404.
- Shop recce: start, draft (boards, notes, installation), photos (multipart, per-photo GPS / time, idempotent `clientId`, duplicate refusal, server flags, six mobile categories), annotation copy, submit with idempotency key, immutable versions, field-side versions / compare / photo history.
- Review: Recce Operations and Client Servicing decide independently; **always parallel** (any order or at the same moment; the old `sequential` switch is ignored since 2026-11-25); reject / rework (per photo and measurement) / more photos; v2 after rework; v1 approvals never carry over; change of an approval; Admin override / reopen; time-based history; shop thread with refs and one image; notifications; field dashboard and staff performance.
- Storage: one document per shop (`RecceSubmission`) with photos, versions, reviews and reworks embedded (see 04).
- Console: one line per recce call with the person's name (`requestLog`).

**Mobile app A**: the screens above exist in `lib/features/live_*`. The phone run and the live mail / push paths were not part of this documentation pass.

**Open**
- A manual run on a phone / emulator against a running backend.
- Photo annotation is not wired to the new API on mobile (backend endpoint and web viewer exist; the older local editor is untouched).
- `change-decision` has no mobile screen (reviewers use the web).
- Offline queue persists photo uploads only; measurements, notes and submit need network. No FCM push for a closed app.
- Existing databases keep only two required photos until Admin sends the one-time config call (09 section 0). Their old `sequential: true` no longer matters (ignored).

## Reusable parts of A
Theme (`AdinnColors`, `AppTheme`), `common_widgets.dart`, geolocator `LocationService`, image_picker capture, annotation editor, PDF report. A's offline models (Shop, Board, Photo) do not match the server model, so the live flow has its own models in `features/live_recce/data`.

## Risks
See 06.
