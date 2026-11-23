import '../../../data/catalog/signage_catalog.dart';
import '../../../data/models/models.dart';
import '../../drawing/signage_geometry.dart';
import 'recce_models.dart';

/// Turns a live recce board (`BoardItem`: type, size, unit, sided, position) into the [SignageGeometry] that the existing 2D drawing
/// and 3D preview painters already understand. Nothing here is stored: it is only the picture of what the recce person entered.

/// Catalog media code of a live board type. GSB, Flex and LED boards look like a GSB box; an unknown type ("Other") falls back to GSB.
String mediaCodeForBoard(String name) => switch (name.trim().toUpperCase()) {
      'ACP' => SignageCatalog.acp,
      'VINYL' => SignageCatalog.vinyl,
      'ACRYLIC' => SignageCatalog.clearAcrylic,
      _ => SignageCatalog.gsb,
    };

/// True when the board type is one the drawing really knows (so the picture is not a guess).
bool boardTypeKnown(String name) => const {'GSB', 'FLEX', 'LED', 'ACP', 'VINYL', 'ACRYLIC'}.contains(name.trim().toUpperCase());

/// The installation the free-text "position" points at ("Shop fascia", "Entrance glass", "Left wall", "Roof"), or null when it names none.
String? installationFromPosition(String position) {
  final p = position.toLowerCase();
  if (p.contains('roof')) return SignageCatalog.rooftop;
  if (p.contains('glass')) return SignageCatalog.glassPasting;
  if (p.contains('pole')) return SignageCatalog.singlePole;
  if (p.contains('free') || p.contains('stand')) return SignageCatalog.freeStanding;
  if (p.contains('fascia') || p.contains('shutter') || p.contains('front')) return SignageCatalog.shopFascia;
  if (p.contains('wall')) return SignageCatalog.wallMount;
  return null;
}

/// Feet in one of the live board units (FT, IN, M, CM, MM).
double feetPer(String unit) => switch (unit) {
      'IN' => 1 / 12,
      'M' => 3.280839895,
      'CM' => 0.03280839895,
      'MM' => 0.003280839895,
      _ => 1.0,
    };

/// The unit the drawing labels use (the painter has no centimetres: a CM board is labelled in metres).
MeasureUnit drawingUnit(String unit) => switch (unit) {
      'IN' => MeasureUnit.inch,
      'M' || 'CM' => MeasureUnit.m,
      'MM' => MeasureUnit.mm,
      _ => MeasureUnit.ft,
    };

/// Geometry of one live board. A board with no size yet is drawn 10 x 4 ft and flagged [SignageGeometry.usingDefaults].
SignageGeometry geometryForBoard(BoardItem b) {
  final media = SignageCatalog.media(mediaCodeForBoard(b.name)) ?? SignageCatalog.mediaTypes.first;
  final wanted = installationFromPosition(b.position);
  final installation = wanted != null && media.installations.contains(wanted) ? wanted : media.installations.first;
  final hasSize = b.hasSize;
  final f = feetPer(b.unit);
  final w = (hasSize ? b.width! * f : SignageGeometry.defaultWidthFt).clamp(0.1, 2000.0).toDouble();
  final h = (hasSize ? b.height! * f : SignageGeometry.defaultHeightFt).clamp(0.1, 2000.0).toDouble();
  final rooftop = installation == SignageCatalog.rooftop;
  final buildingH = rooftop ? 20.0 : 0.0; // two floors, the same default the recce flow of the old app uses
  final clearance = SignageGeometry.defaultClearance(installation);
  return SignageGeometry(
    widthFt: w,
    heightFt: h,
    depthFt: media.depthFt < 0.05 ? 0.05 : media.depthFt,
    clearanceFt: clearance,
    bottomFt: SignageGeometry.bottomFor(installation, clearance, buildingH),
    buildingHeightFt: buildingH,
    poleGapFt: installation == SignageCatalog.doublePole ? w * 0.7 : 0,
    projectionFt: installation == SignageCatalog.flangeBracket ? 1.0 : 0,
    doubleSided: b.sided == 'DOUBLE',
    mediaCode: media.code,
    installationCode: installation,
    unit: drawingUnit(b.unit),
    usingDefaults: !hasSize,
    mediaSelected: boardTypeKnown(b.name),
    installationSelected: wanted != null && media.installations.contains(wanted),
    quantity: b.quantity < 1 ? 1 : b.quantity,
  );
}
