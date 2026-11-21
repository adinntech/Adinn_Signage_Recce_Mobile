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
        label: b.quantity <= 1 ? b.name : '$media – ${b.unitLabel(u)}',
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
/// measured board size. Returns true when the board size changed.
bool applyAnnotationResult(
  AppController c,
  String shopId,
  Board b,
  String photoId,
  AnnotationEditorResult result,
) {
  c.setAnnotations(shopId, b.id, photoId, result.annotations);
  if (result.applyWidth == null || result.applyHeight == null) return false;
  b.width = result.applyWidth;
  b.height = result.applyHeight;
  b.unit = result.applyUnit ?? b.unit;
  if (!b.isSameSize && b.units.isNotEmpty) {
    // Different sizes: the measured size belongs to unit 1 (mirrored).
    b.units.first
      ..width = b.width
      ..height = b.height;
  }
  c.touchBoard(
    shopId,
    b,
    title: 'Board size updated',
    message:
        '${b.name} set to ${fmtSize(b.width, b.height, b.unit)} from photo marking.',
  );
  return true;
}
