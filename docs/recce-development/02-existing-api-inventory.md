# 02 - API inventory (verified from source, 2026-11-23)

Backend `src/app.ts` mounts `/api/v1/recce` (field), `/api/v1/recce-review` (reviewers), `/api/v1/auth` and `/api/v1/notifications`.
Roles, payloads and rules of every recce route: **09 section 1** (index) and 09 sections 2 to 5. This page keeps the auth rules and the mapping to the routes first suggested.

## Auth (`modules/auth/auth.routes.ts`)
POST `/auth/login`, `/auth/vendor-login`, `/auth/register`, `/auth/forgot`, `/auth/forgot/confirm`, `/auth/refresh`, `/auth/logout`; GET `/auth/register-options`, `/auth/me`. Login body: `identifier` (email or employee ID), `mpin` (4 digits) or `password`, optional `loginRole` (`BD, CLIENT_SERVICING, RECCE, VENDOR, OPERATIONS, ADMIN`), `platform` (`web|mobile`). Register body adds `name, email, phone, employeeId, role, platform, authMethod`. Mobile may register `RECCE_EXECUTIVE` and `VENDOR` only. Token handling: Bearer header, single-flight refresh on 401, refresh token stored on the device and rotated on every refresh.

## Routes at a glance
- **Field `/recce`** (VENDOR, RECCE_EXECUTIVE): GET `/dashboard`, `/shops`, `/shops/:siteId`; POST `/shops/:siteId/start`, `/photos`, `/submit`, `/messages`, `/messages/read`; PUT `/draft`, `/photos/order`, `/photos/:photoId/annotation`; PATCH|DELETE `/photos/:photoId`; GET `/photos/:photoId/history`, `/versions`, `/versions/compare`, `/activity`, `/messages`, `/messages/unread`.
- **Review `/recce-review`** (OPS, CS, ADMIN, MANAGEMENT): GET `/inbox`, `/progress`, `/performance`, `/monitor`, `/reviewers`, `/config`, `/submissions/:id`, `/submissions/:id/versions`, `.../versions/compare`, `.../activity`, `.../messages`, `.../messages/unread`; PUT `/config`, `/submissions/:id/reviewer`; POST `/submissions/:id/start|decision|change-decision|override|reopen|messages|messages/read` and `/submissions/:id/photos/:photoId/restore`.
- **Notifications `/notifications`**: GET `/`, `/stream`; POST `/read`, `/:id/read`.

## Mapping to the routes first suggested
| Suggested | Equivalent |
|---|---|
| GET `/projects/:p/assigned-shops` | GET `/recce/shops?projectId=` |
| GET `/projects/:p/shops/:s/recce` | GET `/recce/shops/:siteId` |
| POST `.../recce/draft` | PUT `/recce/shops/:siteId/draft` |
| POST `.../recce/photos` | POST `/recce/shops/:siteId/photos` |
| DELETE `.../photos/:id` | DELETE `/recce/shops/:siteId/photos/:photoId` |
| POST `.../recce/submit` | POST `/recce/shops/:siteId/submit` |
| GET `.../recce/versions` | GET `/recce/shops/:siteId/versions` |
| `/recce/:id/versions/:v/reviews` | POST `/recce-review/submissions/:id/decision` |
| `/recce/:id/audit-history` | GET `/recce/shops/:siteId/activity`, `/recce-review/submissions/:id/activity` |
| `/recce/:id/versions/compare` | GET `/recce/shops/:siteId/versions/compare` |

No duplicate endpoints were created; the existing ones are reused.
