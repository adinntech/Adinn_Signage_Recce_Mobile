# GSB Flutter Project Audit (read-only phase)

Date: 21 Nov 2026 · Branch `saran_3d` · Source: *Signage Frame & 3D Fabrication Master Rulebook* 1.0.

## Architecture
| Area | Finding |
|---|---|
| Stack | Flutter 3.50.1 / Dart 3.14, single `:app` Android project, package `signage_recce` ("offline Flutter prototype"). |
| State | `provider` + one `ChangeNotifier`, `lib/state/app_controller.dart`. |
| Persistence | Local JSON (`data/storage/local_store.dart`) + private media folders (`MediaStorage`). |
| Backend / API | **None** (no HTTP dependency; seed data in `data/mock/mock_seed.dart`). No server contract exists, so all new fields are additive JSON. |
| Auth | PIN login, roles vendor / businessTeam / recceOps. Not touched. |
| Navigation | Dashboard → Projects → Project → Task → Shop → `board/board_editor_screen.dart` (Stepper). |
| PDF | `pdf` + `printing`, Helvetica, `pdfSafe()` in `report/report_pdf.dart`. |
| 3D | Pure-Dart software renderer (`preview3d/scene3d.dart`, `renderer_painter.dart`); parametric models from `model3d/parametric_builder.dart`. No new 3D engine was added. |
| Camera AR | **Real ARCore world tracking** with anchors (Kotlin GL renderer `android/.../ar/*`, channel `adinn/ar`). It is not a camera overlay. |

## GSB flow before the change
Media grid (13 `SignageCatalog.catalogCodes`) → GSB (`'GSB'`, sidedness `selectable`) → Single/Double chosen at the bottom (`_SidednessChoice`), stored in `Board.doubleSided` (`bool?`; null = never chosen, treated as single) → Installation → Questions → Measurements → Photos (`PhotoWorkspaceScreen`: Photo Editor / Live Preview / Camera AR) → Notes → 2D/3D.

## Live Preview distortion: root causes
1. **The artwork label used an affine map** built from 3 projected corners, ignoring the 4th. Under Turn or Perspective the face is a trapezoid, so the artwork sheared off the face. Fixed with a homography (`Scene3DPainter.squareToQuad`).
2. **The Perspective slider is camera elevation with range −0.15…+0.9 rad.** At 0.9 rad the board is vertically foreshortened to about 62 % ("squeezed"), and the view from below (the usual street photo) was barely reachable. Changed to a symmetric ±0.6 rad. Old saved values are restored unclamped.
3. **Camera distance 2.8 × scene radius** exaggerated keystone when turning. Photo overlays now use 4.0 × (`kOverlayDistanceFactor`); the 3D Preview is unchanged.
4. **`NaN.clamp(a,b)` returns a bound in Dart.** A NaN gesture value could jump the scale. Setters now reject non-finite input.
5. Ruled out: non-uniform scale (the overlay box is square), double rotation, and image fit (the stage uses the exact photo aspect).

## Other findings
* GSB default depth was 0.75 ft (9 in) and the default frame was 40 mm. The rulebook says 8 in and 1 × 1 in SHS; both now follow the rulebook (GSB only).
* The 3D Preview already had a "Night" chip for all media; it is kept.
* Baseline `flutter test`: **390 passed** before any change.
