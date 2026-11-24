# 03 - Reusable components

## From Project B (pattern copied, B untouched)
- `core/network/dio_client.dart` auth interceptor with one-shot refresh; `token_manager.dart` single-flight refresh; `api_exception.dart` error mapping.
- `core/storage/session_store.dart` refresh token + user JSON on the device.
- `features/auth/*` rules (phone +91 + 10 digits, MPIN 4 digits), vendor-ID login, forgot flow.
- `features/recce/data/recce_api.dart` `RecceApi` + `UploadQueue` (2 parallel, retry, cancel, saved on the phone, idempotent `clientId`).
- `core/widgets/app_file_row.dart`, `input_formats.dart`, `services/location_service.dart`, `photo_service.dart`.

## From Project A (kept as is)
`AdinnColors` / `AppTheme.light()`, `common_widgets.dart` (cards, chips, logo), geolocator `LocationService`, image_picker capture, annotation editor (`features/annotation`), PDF report.

## Backend (reused, not duplicated)
`recceReview.field.ts` `mySite()` (ownership boundary), `presentPhoto`, `logEvent` (audit), `missingFor` (required photos), `postShopMessage` (cards with event key), `overallOutcome` (one place for the review result), config `requiredPhotos`. Shared: `src/common/requestLog.ts` (recce console line with the person's name).

## New in A (own models; the offline models are not reused for server data)
`core/network/*`, `core/storage/session_store.dart`, `features/live_auth/*`, `features/live_recce/*`: `recce_api.dart`, `upload_queue.dart`, `photo_shrink.dart`, `submit_validator.dart`, `chat_controller.dart`, `dashboard_controller.dart`, `notifications_controller.dart`, `history_controllers.dart`, and the screens listed in 01.

## Photo types and the testing switch (2026-11-23)
- Any picture format is accepted: backend `isImageContent()` (`files/file.service.ts`) checks the real first bytes (JPEG, PNG, WebP, GIF, BMP, HEIC/HEIF/AVIF) under ANY picture extension, so a PNG screenshot saved as `photo.jpg` is stored. A non-picture is still refused ("the file content does not match its type"). `.gif .bmp .heic .heif` were added to the allowed image extensions. Mobile names the upload by what the bytes really are (`photoExtension()` in `photo_shrink.dart`).
- Photos tab testing switch "Use the first photo for all types" (`ShopDetailController.useFirstPhotoForAll`, `queueFirstPhotoForAll`): shown in debug and profile builds only, never in a release build. The first picture taken is also queued, with a file of its own, for every empty type of the shop.
- ~~The server refuses the same content twice in one shop (`ALLOW_DUPLICATE_RECCE_PHOTOS`).~~ **Removed 2026-11-24.** The same picture may be stored for several angles (and boards) of one shop in every environment: each angle is a photo of its own. A retry of one upload (same `clientId`) is still stored once. The env name no longer exists. The person chooses the angles on the photo preview ("Use this photo for other angles too", see doc 11 section 6c); the testing checkbox above stays for filling every board at once.
