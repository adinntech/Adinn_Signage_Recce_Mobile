# 05 - Milestone plan

## Milestone 1 - Auth + shop recce + Version 1 (this delivery)
Backend (additive): six photo categories, per-photo `source`/`device`/`gpsVerified`, board-item extras, installation feasibility with tri-state (NOT_ASSESSED never = NO), submit validation (installation, GPS when required), field-user version list + compare, per-photo review state and history, tests.
Flutter A: network layer, login / create account / forgot / vendor-ID login in the Adinn red theme, dashboard, assigned projects, assigned shops, shop recce (six photo checklist with per-photo GPS, boards, installation, Save Draft, Submit V1).
Acceptance: login -> project -> shop -> six photos with own GPS -> 2 x GSB 6x4 + 1 Acrylic 4x2 -> installation -> save draft -> reopen -> submit V1 -> snapshot, two review stages pending, status UNDER_REVIEW/SUBMITTED, thread event. Backend part is covered by automated tests; the phone flow needs a manual run (no emulator is started by this work).

## Milestone 2 - Dual approval, field-level rework, versions UI
Backend already done (decision API, rework items, v2, audit). Remaining in A: rework flag + sheet with history, replace only the flagged photo, version list and compare screen (6x4 -> 8x4, replaced/unchanged photos), approval timeline screen, reviewer screens if reviewers use mobile.

## Milestone 3 - Communication, dashboard, notifications
Shop thread screen (poll with unread counts), performance dashboard APIs (in-house vs vendor, rework %, completion time; cost only from verified records via the existing `recce-cost` module), notification list, final regression pass.

Rule: stop after each milestone and wait for approval.
