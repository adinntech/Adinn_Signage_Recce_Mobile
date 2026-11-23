# 05 - Milestone plan and status (2026-11-23)

Rule: stop after each milestone and wait for approval.

## Milestone 1 - Auth + shop recce + Version 1 (delivered)
Backend (additive): six photo categories, per-photo `source` / `device` / `gpsVerified`, board-item extras, installation feasibility (tri-state, `NOT_ASSESSED` never = NO), submit validation (installation, GPS when required), field-side versions / compare, per-photo review state and history.
Flutter A: network layer, login / create account / forgot / vendor-ID login in the Adinn red theme, dashboard, projects, shops, shop recce (six-photo checklist with per-photo GPS, boards, installation, save draft, submit V1).
Acceptance: login -> project -> shop -> six photos with own GPS -> 2 x GSB 6x4 + 1 Acrylic 4x2 -> installation -> save draft -> reopen -> submit V1 -> snapshot, both review stages pending. Covered by automated tests; the phone flow needs a manual run.

## Milestone 2 - Dual approval, field-level rework, versions UI (delivered)
Backend: decision API, rework items, V2, audit, version compare. Flutter A: rework flag + sheet with history, replace only the flagged photo, version list and compare screen (6x4 -> 8x4), approval history screen.

## Milestone 3 - Communication, dashboard, notifications (delivered)
Backend: shop thread (refs, one image, unread), field dashboard, staff performance (cost only from verified records), notification `type` / `siteId`. Flutter A: chat tab, dashboard, notifications screen.

## Milestone 4 - One document per shop, parallel review (2026-11-23)
- Shop data moved into one `RecceSubmission` document (photos, versions, reviews, reworks embedded); legacy data is purged with `scripts/purge-legacy-recce.ts`.
- Review default changed to **parallel** (`sequential: false`): both stages notified and see the shop at submit, any order or at the same moment, no rollback on simultaneous decisions; `sequential: true` keeps the old order.
- `change-decision` (an approved stage may reject / rework later).
- 19-step flow test, Postman / Bruno collection, per-call console log with the person's name.

## Open (not started, wait for approval)
Phone run and screenshots; mobile photo annotation wired to the API; mobile screen for `change-decision` (if reviewers should use the phone); FCM push; notify both stages for a field message in parallel mode.
