# 02 - Existing API inventory (verified from source, 2026-11-21)

Backend `src/app.ts` mounts `/api/v1/recce` (field) and `/api/v1/recce-review` (reviewers). Auth under `/api/v1/auth`.

## Auth (`modules/auth/auth.routes.ts`)
POST `/auth/login`, `/auth/vendor-login`, `/auth/register`, `/auth/forgot`, `/auth/forgot/confirm`, `/auth/refresh`, `/auth/logout`; GET `/auth/register-options`, `/auth/me`. Login body: `identifier` (email or employee ID), `mpin` (4 digits) or `password`, optional `loginRole` (`BD, CLIENT_SERVICING, RECCE, VENDOR, OPERATIONS, ADMIN`), `platform` (`web|mobile`). Register body adds `name, email, phone, employeeId, role, platform, authMethod`. Mobile may register `RECCE_EXECUTIVE` and `VENDOR` only. Token handling in B: Bearer header, single-flight refresh on 401, refresh token stored on device, rotated on every refresh.

## Field router `/api/v1/recce` (roles VENDOR, RECCE_EXECUTIVE)
GET `/shops`; GET `/shops/:siteId`; POST `/shops/:siteId/start`; PUT `/shops/:siteId/draft`; POST `/shops/:siteId/photos` (multipart `photos` + `meta`); PUT `/shops/:siteId/photos/order`; PATCH|DELETE `/shops/:siteId/photos/:photoId`; PUT `/shops/:siteId/photos/:photoId/annotation`; POST `/shops/:siteId/submit`; GET|POST `/shops/:siteId/messages`; GET `/shops/:siteId/activity`.

## Review router `/api/v1/recce-review`
GET `/inbox`, `/progress`, `/monitor`, `/reviewers`, `/config`; PUT `/config`; GET `/submissions/:id`; POST `/submissions/:id/start|decision|override|reopen`; PUT `/submissions/:id/reviewer`; POST `/submissions/:id/photos/:photoId/restore`; GET `/submissions/:id/activity`; GET|POST `/submissions/:id/messages`.

## Mapping to the requested suggested routes
| Suggested | Existing equivalent |
|---|---|
| GET `/projects/:p/assigned-shops` | GET `/recce/shops?projectId=` |
| GET `/projects/:p/shops/:s/recce` | GET `/recce/shops/:siteId` |
| POST `.../recce/draft` | PUT `/recce/shops/:siteId/draft` |
| POST `.../recce/photos` | POST `/recce/shops/:siteId/photos` |
| DELETE `.../photos/:id` | DELETE `/recce/shops/:siteId/photos/:photoId` |
| POST `.../recce/submit` | POST `/recce/shops/:siteId/submit` |
| GET `.../recce/versions` | **new** GET `/recce/shops/:siteId/versions` |
| `/recce/:id/versions/:v/reviews` | POST `/recce-review/submissions/:id/decision` |
| `/recce/:id/audit-history` | GET `/recce/shops/:siteId/activity`, `/recce-review/submissions/:id/activity` |
| `/recce/:id/versions/compare` | **new** GET `/recce/shops/:siteId/versions/compare` |

No duplicate endpoints are created; the existing ones are reused (rule 6).
