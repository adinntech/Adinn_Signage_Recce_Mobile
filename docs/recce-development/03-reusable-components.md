# 03 - Reusable components

## From Project B (pattern copied, B untouched)
- `core/network/dio_client.dart` auth interceptor with one-shot refresh; `token_manager.dart` single-flight refresh; `api_exception.dart` error mapping.
- `core/storage/session_store.dart` refresh token + user JSON on device.
- `features/auth/*` validation rules (phone +91 + 10 digits, MPIN 4 digits), vendor-ID login, forgot flow.
- `features/recce/data/recce_api.dart` `RecceApi` + `UploadQueue` (2 parallel, retry, cancel, saved on phone, idempotent `clientId`).
- `core/widgets/app_file_row.dart`, `app_photo_viewer.dart`, `input_formats.dart`, `services/location_service.dart`, `photo_service.dart`.

## From Project A (kept as is)
- `AdinnColors` / `AppTheme.light()`, `common_widgets.dart` (cards, chips, logo), geolocator `LocationService`, image_picker capture, annotation editor (`features/annotation`), version/compare widgets for later milestones.

## Backend
- `recceReview.field.ts` `mySite()` (ownership boundary), `presentPhoto`, `logEvent` (audit), `missingFor` (required photos), config `requiredPhotos`.

## New shared pieces (A)
`core/network/*`, `core/storage/session_store.dart`, `features/live_auth/*`, `features/live_recce/*` (own models; the offline models are not reused for server data).
