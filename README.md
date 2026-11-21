# Adinn Signage Board Recce (Flutter · Android)

Offline Flutter prototype of the Adinn signage-recce field app. It covers the full
journey from vendor login to the two-stage approval, using local dummy data only.
There is no backend, Firebase or network API: everything is stored on the device.

## Run

```bash
flutter pub get
flutter run            # on an Android emulator or device
flutter test
```

## Demo logins (4-digit PIN only)

| Role | PIN | Registered mobile (for Forgot PIN) |
|------|-----|-----------------------------------|
| Recce Vendor (field survey) | `5678` | 9876543210 |
| Business Team (1st approval) | `1234` | 9840011223 |
| Recce Operations (final approval) | `4321` | 9840044556 |

- Login asks only for the PIN, so every user's PIN is unique. After 5 wrong PINs the
  keypad locks for 30 seconds.
- Forgot PIN: registered mobile → demo OTP `246810` (no SMS is sent) → new PIN.
- Profile → **Change login PIN**; Profile → **Reset demo data** restores the original dataset.

## GPS

- Each shop needs a GPS location (captured on site from the shop screen or the Add Shop
  form) before it can be submitted.
- Camera photos are geotagged automatically. Reviewers see a "Site checks" card that
  flags photos taken more than 300 m from the shop and GPS fixes worse than ±50 m.
- "Open in Maps" hands the coordinates to the phone's maps app. No maps SDK, API key or
  reverse geocoding is used, and nothing leaves the device.

## Feature map

| Area | Where |
|------|-------|
| PIN login with lockout, forgot PIN (OTP stepper), change PIN, logout | `lib/features/auth`, `lib/features/profile` |
| Shop GPS capture, photo geotags, Open in Maps | `lib/features/location`, `lib/data/services/location_service.dart` |
| Dashboard (role-aware stats, rework queue, tasks, recent activity) | `lib/features/home` |
| Projects → tasks → multiple shops (add/edit/delete, call shop) | `lib/features/projects`, `lib/features/shop` |
| Multiple boards per shop, 7-step board editor | `lib/features/board` |
| 6 media types, installation types, dynamic + conditional site questions | `lib/data/catalog/signage_catalog.dart` |
| Camera / gallery capture, angle labels, sample photo for emulators | `lib/features/photos` |
| Photo annotation (rectangles, arrows, text; move/resize/rotate; W×H labels) | `lib/features/annotation` |
| Auto 2D technical drawing (front + side elevation, title block, PNG export) | `lib/features/drawing` |
| Interactive 3D preview (pure-Dart renderer: rotate/zoom/pan, presets, live dimensions) | `lib/features/preview3d` |
| Voice notes (record/play/delete) and text notes | `lib/features/notes` |
| Submission checklist, versioned snapshots, change diff | `lib/features/submission`, `lib/state/version_diff.dart` |
| Business Team and Recce Ops approval / rejection with reasons | `lib/features/approvals` |
| Version history, locked snapshots, activity timeline | `lib/features/history` |

## Architecture

- **State:** `provider` + a single `AppController` (`lib/state/app_controller.dart`) holding
  the session, the dummy data and the workflow rules.
- **Persistence:** the whole state is one JSON file in the app documents folder
  (`FileLocalStore`); photos, voice notes and drawings go in `adinn_recce/media/`.
- **Workflow:** Not Started → In Progress → Pending Business → Pending Ops → Approved.
  A rejection at either stage sends the recce back to the vendor, and resubmitting
  creates the next version (v2, v3, …) with an immutable snapshot.
