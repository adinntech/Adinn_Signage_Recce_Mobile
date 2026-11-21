# GSB Regression Test Report

Environment: Windows 11, Flutter 3.50.1, Dart 3.14. No emulator or device used.

## Executed
| Check | Result |
|---|---|
| Baseline `flutter test` (before changes) | 390 passed |
| `flutter test` (after changes) | **425 passed, 0 failed** (35 new) |
| `flutter analyze` | 0 new issues. Remaining output predates this change: `material.dart` deprecation infos in every file, plus 2 warnings in `report_service.dart:96` and `photo_render.dart:21`. |
| `flutter build apk --debug` | Built `app-debug.apk` (compiles the Kotlin ARCore changes). AGP 9.1.1 / Kotlin 2.4.10 deprecation warnings predate this change. |

## New tests
* `test/gsb_rules_test.dart`: module layouts (16/17/18/20×7, 20×10, 32×10, 40×8), 17×7 mirrored bays, even/odd bays (6×3, 8×3, 10×4, 13×4), unapproved partitions (8×5, 22×4, 50×15), depth stations, extra horizontal, Single vs Double (plane, braces, GI, flex, one LED set), seam braces, connector cut length, member validity / unique ids, inserts + fit/clash, trim (8×3, 9×3, 8×10), GI (8×5, 21×7, 12×8 review), validation (0, negative, NaN, depth ≤ 2 profiles), depth override, ft-in parser / formatter, variant JSON compatibility, override add / blank reason / same value / revert / persistence / other boards unaffected.
* `test/gsb_preview_test.dart`: homography corners + mirrored/collapsed rejection, NaN guards, symmetric perspective, day/night keeps placement, composer output aspect + night darker, 4-page PDF with long names, AR night forwarding / capture refusal, Render View only for GSB (not NLB / MDF+GSB), 3D exact width (invalid text ignored, `12 ft 7 in` → 151 in applied exactly).
* Updated: `media_catalog_test` (popup flow, cancel, restore, NLB control kept), `widget_test` (popup), `scene_test` + `ar_engine_test` (GSB depth 9 → 8 in).

## Not executed (device required)
Camera permission granted/denied, ARCore session, tracking interruption, background/foreground, rotation, on-device night shader look, AR render-set capture, PDF share sheet, real-photo Live Preview PDF on device storage, low-memory devices. Code paths exist; physical-device testing is still required.
