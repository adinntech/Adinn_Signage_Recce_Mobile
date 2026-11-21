import 'dart:io';
import 'dart:typed_data';

import '../../core/utils/formatters.dart';
import '../../core/utils/length_input.dart';
import '../../data/catalog/measurement_fields.dart';
import '../../data/models/models.dart';
import '../../data/storage/media_storage.dart';
import '../../state/app_controller.dart';
import '../model3d/signage_spec.dart';
import 'gsb_board.dart';
import 'gsb_comparison_pdf.dart';
import 'gsb_rules.dart';

/// Writes [bytes] to a NEW file (never replaces an existing one).
Future<String> writeNewMediaFile(
  MediaStorage media,
  Uint8List bytes,
  String folder,
  String extension,
) async {
  final path = await media.newFilePath(folder, extension);
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

/// Review items worth showing on a customer-facing visual report.
const _reportReviewCodes = {
  'VARIANT_NOT_CONFIRMED',
  'DEPTH_OVERRIDE_REVIEW',
  'PROFILE_OVERRIDE_REVIEW',
  'RECORDED_DEPTH_DIFFERS',
  'DOUBLE_OPTICS_REVIEW',
};

/// Report data for one GSB signage item (shop / project / dimensions from
/// the canonical recce data; images supplied by the caller).
GsbComparisonData gsbComparisonData({
  required AppController app,
  required Shop shop,
  required Board board,
  required SignageUnit unit,
  required String source,
  required DateTime capturedAt,
  required PdfPicture original,
  required PdfPicture day,
  required PdfPicture night,
  PdfPicture? dayLabelled,
}) {
  final variant = GsbBoard.variantOf(board) ?? GsbVariant.single;
  final plan = GsbBoard.planFor(board, unit);
  final spec = SignageModelSpec.of(board, unit);
  final w = board.widthOf(unit), h = board.heightOf(unit);
  final imperial =
      board.unit == MeasureUnit.ft || board.unit == MeasureUnit.inch;
  final size = w == null || h == null
      ? 'Size not set'
      : imperial
      ? 'W ${fmtFeetInches(board.unit.toFeet(w))} x '
            'H ${fmtFeetInches(board.unit.toFeet(h))}'
      : fmtSize(w, h, board.unit);
  final mountFt = spec.mountingHeightMm / 304.8;
  final mount =
      '${imperial ? fmtFeetInches(mountFt) : fmtMm(spec.mountingHeightMm, board.unit)}'
      '${spec.isAssumed(SpecField.mountingHeight) ? ' (not measured - illustrative)' : ''}';
  final depth = GsbBoard.depthIn(board, unit);
  final depthOverride =
      GsbBoard.activeOverride(board, unit.id, GsbOverrideField.depth) != null;
  return GsbComparisonData(
    source: source,
    projectName: app.project(shop.projectId)?.name ?? shop.projectId,
    taskTitle: app.task(shop.taskId)?.title,
    shopName: shop.name,
    siteId:
        [
          shop.city,
          shop.pincode,
        ].where((s) => s.trim().isNotEmpty).join(' ').trim().isEmpty
        ? shop.id
        : '${shop.id} (${[shop.area, shop.city, shop.pincode].where((s) => s.trim().isNotEmpty).join(', ')})',
    boardName: board.name,
    unitLabel: board.unitLabel(unit),
    variantLabel: variant.label,
    sizeText: size,
    mountingText: mount,
    depthText:
        '${fmtNum(depth)} in${depthOverride ? ' (override - Requires Engineering Review)' : ''}',
    capturedAt: capturedAt,
    original: original,
    day: day,
    night: night,
    dayLabelled: dayLabelled,
    reviewNotes: [
      for (final i in plan?.reviewItems ?? const <GsbIssue>[])
        if (_reportReviewCodes.contains(i.code)) i.message,
    ],
    ruleVersion: kGsbRuleVersion,
  );
}
