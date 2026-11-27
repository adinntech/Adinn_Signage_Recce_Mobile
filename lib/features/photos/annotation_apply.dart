import '../../core/utils/formatters.dart';
import '../../data/catalog/measurement_fields.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../annotation/annotation_editor_screen.dart';

/// Unit options for the annotation editor's "link to signage item".
List<AnnotationUnitOption> unitOptionsFor(Board b) {
  final media = SignageCatalog.media(b.mediaCode)?.shortName ?? b.name;
  return [
    for (final u in b.activeUnits)
      AnnotationUnitOption(
        id: u.id,
        label: b.quantity <= 1
            ? b.name
            : '$media – ${b.unitLabel(u)} · '
                  '${fmtNum(b.widthOf(u) ?? 0)} × '
                  '${fmtNum(b.heightOf(u) ?? 0)} ${b.unit.label}'
                  '${SignageCatalog.installation(b.installationOf(u))?.name != null ? ' · ${SignageCatalog.installation(b.installationOf(u))!.name}' : ''}',
        width: b.widthOf(u),
        height: b.heightOf(u),
        unit: b.unit,
        recorded: [
          for (final (f, _) in MeasurementCatalog.recorded(b, u))
            if (f.kind == MeasureFieldKind.length)
              RecordedMeasurement(
                f.label,
                u.measurements.unit.fromMm(u.measurements.valuesMm[f.id]!),
                u.measurements.unit,
              ),
        ],
      ),
  ];
}

/// Saves an editor result: the editable markings and, when requested, the
/// measured size of the PHYSICAL BOARD the rectangle is linked to.
///
/// Never falls back to `units.first` or the workspace selection: the explicit
/// `result.applyUnitId` from the selected annotation is authoritative.
bool applyAnnotationResult(
  AppController c,
  String shopId,
  Board b,
  String photoId,
  AnnotationEditorResult result,
) {
  c.setAnnotations(shopId, b.id, photoId, result.annotations);
  final w = result.applyWidth;
  final h = result.applyHeight;
  if (w == null || h == null || w <= 0 || h <= 0) return false;

  final shop = c.shop(shopId);
  if (shop == null || !c.canEdit(shop)) return false;

  if (b.isSameSize) {
    // Shared size: a single group-level value, all units inherit it.
    b
      ..width = w
      ..height = h
      ..unit = result.applyUnit ?? b.unit;
    c.touchBoard(
      shopId,
      b,
      title: 'Board size updated',
      message:
          '${b.name} set to ${fmtSize(b.width, b.height, b.unit)} '
          'from photo marking.',
    );
    return true;
  }

  // Different Sizes: update ONLY the physical board this rectangle is linked
  // to. The group unit is untouched so other boards' numbers stay valid.
  SignageUnit? target;
  final id = result.applyUnitId;
  if (id != null) {
    for (final u in b.activeUnits) {
      if (u.id == id) target = u;
    }
  }
  if (target == null) return false; // no silent first-board fallback
  target
    ..width = w
    ..height = h;
  c.touchBoard(
    shopId,
    b,
    title: 'Board size updated',
    message:
        '${b.unitLabel(target)} set to ${fmtSize(w, h, b.unit)} '
        'from photo marking.',
  );
  return true;
}
