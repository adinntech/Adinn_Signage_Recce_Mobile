import 'dart:math' as math;

import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../preview3d/scene3d.dart';
import '../preview3d/signage_scene_builder.dart';
import '../preview_live/live_preview_controller.dart' show unitGeometry;

/// Feet → metres (the AR engine works in metres).
const double kFeetToMetres = 0.3048;

/// Installations that hang on a wall / facade / glass → vertical surfaces.
const _verticalInstallations = {
  SignageCatalog.shopFascia,
  SignageCatalog.wallMount,
  SignageCatalog.directWall,
  SignageCatalog.glassPasting,
  SignageCatalog.flangeBracket,
  // Support pipes hold the board off a wall / parapet.
  SignageCatalog.supportPipe,
};

/// Wall-type installations prefer vertical ARCore planes; poles, standees
/// and rooftop structures prefer horizontal (floor / ground / roof) planes.
bool prefersVerticalPlacement(String? installationCode) =>
    _verticalInstallations.contains(installationCode);

/// Glass is often not detected by ARCore: offer manual placement.
bool mayNeedManualPlacement(String? installationCode) =>
    installationCode == SignageCatalog.glassPasting;

/// One flat face of the AR model, in metres.
class ArFaceData {
  const ArFaceData({
    required this.points,
    required this.normal,
    required this.color,
    this.label,
    this.labelColor = 0xFFFFFFFF,
    this.emissive = false,
    this.layer = 0,
    this.glow,
  });

  /// x0, y0, z0, x1, … (metres, model space: +Y up, +Z out of the board).
  final List<double> points;
  final List<double> normal;
  final int color;
  final String? label;
  final int labelColor;
  final bool emissive;
  final int layer;

  /// Night View: whether this self-lit face glows (null = follows
  /// [emissive]).
  final bool? glow;

  Map<String, Object?> toMap() => {
    'p': points,
    'n': normal,
    'c': color,
    if (label != null) 'l': label,
    'lc': labelColor,
    'e': emissive,
    'k': layer,
    if (glow != null) 'g': glow,
  };
}

/// Signage model for the native AR engine, generated from the same
/// [SignageSceneBuilder.buildModel] geometry used by the photo Live Preview,
/// so dimensions are never duplicated inside the AR module.
class ArModelData {
  const ArModelData({
    required this.unitId,
    required this.mediaCode,
    required this.installationCode,
    required this.faces,
    required this.pivotWall,
    required this.pivotGround,
    required this.preferVertical,
    required this.widthM,
    required this.heightM,
    required this.doubleSided,
  });

  final String unitId;
  final String mediaCode;
  final String installationCode;
  final List<ArFaceData> faces;

  /// Model point placed on a wall anchor (back of the board, centre height).
  final List<double> pivotWall;

  /// Model point placed on a floor / ground anchor.
  final List<double> pivotGround;
  final bool preferVertical;
  final double widthM;
  final double heightM;
  final bool doubleSided;

  Map<String, Object?> toMap() => {
    'unitId': unitId,
    'mediaCode': mediaCode,
    'installationCode': installationCode,
    'faces': faces.map((f) => f.toMap()).toList(),
    'pivotWall': pivotWall,
    'pivotGround': pivotGround,
    'preferVertical': preferVertical,
    'widthM': widthM,
    'heightM': heightM,
  };
}

List<double> _m(Vec3 v) => [
  v.x * kFeetToMetres,
  v.y * kFeetToMetres,
  v.z * kFeetToMetres,
];

/// Builds the AR model of one signage unit (its size and installation).
ArModelData buildArModel(Board b, SignageUnit u, {String brand = 'ADINN'}) {
  final g = unitGeometry(b, u);
  final scene = SignageSceneBuilder.buildModel(g, brand: brand);
  final faces = <ArFaceData>[];
  var minY = double.infinity, minZ = double.infinity;
  var maxY = -double.infinity, maxZ = -double.infinity;
  for (final solid in scene.solids) {
    final isBoard = solid.name == 'board';
    for (final (face, decal) in [
      for (final f in solid.faces) (f, false),
      for (final f in solid.decals) (f, true),
    ]) {
      if (isBoard) {
        for (final p in face.points) {
          minY = math.min(minY, p.y);
          minZ = math.min(minZ, p.z);
          maxY = math.max(maxY, p.y);
          maxZ = math.max(maxZ, p.z);
        }
      }
      faces.add(
        ArFaceData(
          points: [for (final p in face.points) ..._m(p)],
          normal: [face.normal.x, face.normal.y, face.normal.z],
          color: face.color.toARGB32(),
          label: face.label,
          labelColor: face.labelColor.toARGB32(),
          emissive: face.emissive,
          glow: face.glow,
          layer: decal ? math.max(1, face.layer) : 0,
        ),
      );
    }
  }
  if (minY == double.infinity) {
    // No board solid (should not happen): pivot around the scene focus.
    minY = maxY = scene.focus.y;
    minZ = maxZ = scene.focus.z;
  }
  final centreY = (minY + maxY) / 2;
  // Flange boards project from the wall plane (z = 0); others mount by
  // their back face.
  final wallZ = g.isFlangeBracket ? 0.0 : minZ;
  final groundY = g.baseLevelFt; // roof top for rooftop structures
  return ArModelData(
    unitId: u.id,
    mediaCode: g.mediaCode,
    installationCode: g.installationCode,
    faces: faces,
    pivotWall: _m(Vec3(0, centreY, wallZ)),
    pivotGround: _m(Vec3(0, groundY, (minZ + maxZ) / 2)),
    preferVertical: prefersVerticalPlacement(g.installationCode),
    widthM: g.widthFt * kFeetToMetres,
    heightM: g.heightFt * kFeetToMetres,
    doubleSided: g.doubleSided,
  );
}
