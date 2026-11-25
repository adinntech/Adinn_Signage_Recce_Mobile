import 'dart:math' as math;

import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../model3d/signage_spec.dart';

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

/// Physical dimensions (in feet) of a board and its supporting structure,
/// derived from the recce data. Shared by the 2D drawing and the 3D preview.
class SignageGeometry {
  const SignageGeometry({
    required this.widthFt,
    required this.heightFt,
    required this.depthFt,
    required this.clearanceFt,
    required this.bottomFt,
    required this.buildingHeightFt,
    required this.poleGapFt,
    required this.projectionFt,
    required this.doubleSided,
    required this.mediaCode,
    required this.installationCode,
    required this.unit,
    required this.usingDefaults,
    required this.mediaSelected,
    required this.installationSelected,
    this.quantity = 1,
    this.foundationDepthFt = 3,
    this.letterHeightFt,
    this.panelCount = 2,
    this.acpColour,
    this.baseWidthFt = 0,
    this.baseDepthFt = 0,
    this.supportType,
    this.spec,
    this.gsbLedRear = false,
    this.nlbBoxFrame = false,
    this.nlbSingleFrame = false,
  });

  static const defaultWidthFt = 10.0;
  static const defaultHeightFt = 4.0;

  final double widthFt;
  final double heightFt;
  final double depthFt;

  /// Value of the installation's clearance answer (pole height, mount
  /// height, shutter height or structure height above the roof).
  final double clearanceFt;

  /// Elevation of the board bottom above ground.
  final double bottomFt;

  /// Building height (rooftop installations only, otherwise 0).
  final double buildingHeightFt;

  /// Centre-to-centre pole distance (double pole only, otherwise 0).
  final double poleGapFt;

  /// Gap between wall and board (flange bracket only, otherwise 0).
  final double projectionFt;
  final bool doubleSided;
  final String mediaCode;
  final String installationCode;
  final MeasureUnit unit;

  /// True when the board has no size yet and 10 × 4 ft is assumed.
  final bool usingDefaults;
  final bool mediaSelected;
  final bool installationSelected;
  final int quantity;
  final double foundationDepthFt;
  final double? letterHeightFt;
  final int panelCount;
  final String? acpColour;

  /// Standee ground base footprint (free standing only, otherwise 0).
  final double baseWidthFt;
  final double baseDepthFt;

  /// Standee support structure answer, e.g. "Twin side posts".
  final String? supportType;

  /// Full canonical spec of the signage item for catalog-v2 media (letter
  /// depth, GSB panel, pipes…) so Live Preview / AR models use exactly the
  /// recorded values. Null for GSB / NLB / ACP and legacy media, which keep
  /// the original scene builder.
  final SignageModelSpec? spec;

  /// GSB Double: the single physical LED set faces the rear (Night View
  /// glow only; never a quantity).
  final bool gsbLedRear;

  /// NLB Box Frame (rulebook NON_LIT_BOX): fully flex-covered 4-in box.
  final bool nlbBoxFrame;

  /// NLB Single Frame (NON_LIT): slim open steel frame, pipes visible.
  final bool nlbSingleFrame;

  double get topFt => bottomFt + heightFt;
  double get areaSqFt => widthFt * heightFt;

  /// Level the clearance is measured from (roof top for rooftop units).
  double get baseLevelFt =>
      installationCode == SignageCatalog.rooftop ? buildingHeightFt : 0;

  MediaType get media =>
      SignageCatalog.media(mediaCode) ?? SignageCatalog.mediaTypes.first;

  InstallationType get installation =>
      SignageCatalog.installation(installationCode) ??
      SignageCatalog.installationTypes.first;

  bool get isPoleMounted =>
      installationCode == SignageCatalog.doublePole ||
      installationCode == SignageCatalog.singlePole;

  bool get isFlangeBracket => installationCode == SignageCatalog.flangeBracket;

  bool get isFreeStanding => installationCode == SignageCatalog.freeStanding;

  /// Vinyl / wall painting applied directly on a wall or glass surface.
  bool get isSurfaceArtwork =>
      (mediaCode == SignageCatalog.vinyl ||
          mediaCode == SignageCatalog.wallPainting) &&
      (installationCode == SignageCatalog.directWall ||
          installationCode == SignageCatalog.glassPasting);

  bool get anyDefaults =>
      usingDefaults || !mediaSelected || !installationSelected;

  /// Answer id that stores the clearance for an installation type.
  static String? clearanceKey(String? installationCode) =>
      switch (installationCode) {
        SignageCatalog.doublePole || SignageCatalog.singlePole => 'pole_height',
        SignageCatalog.freeStanding => 'panel_bottom_height',
        SignageCatalog.shopFascia => 'shutter_height',
        SignageCatalog.rooftop => 'structure_height',
        SignageCatalog.wallMount ||
        SignageCatalog.flangeBracket ||
        SignageCatalog.directWall ||
        SignageCatalog.glassPasting => 'mount_height',
        _ => null,
      };

  static String clearanceLabel(String? installationCode) =>
      switch (installationCode) {
        SignageCatalog.doublePole || SignageCatalog.singlePole => 'Pole height',
        SignageCatalog.shopFascia => 'Shutter height',
        SignageCatalog.rooftop => 'Above roof',
        SignageCatalog.freeStanding => 'Panel bottom',
        _ => 'Mount height',
      };

  static double defaultClearance(String installationCode) =>
      switch (installationCode) {
        SignageCatalog.doublePole || SignageCatalog.singlePole => 9,
        SignageCatalog.wallMount => 8,
        SignageCatalog.flangeBracket => 9,
        SignageCatalog.directWall => 3,
        SignageCatalog.glassPasting => 1,
        SignageCatalog.shopFascia => 9,
        SignageCatalog.rooftop => 4,
        SignageCatalog.freeStanding => 2.5,
        _ => 8,
      };

  /// Board bottom elevation for a clearance value.
  static double bottomFor(
    String installationCode,
    double clearanceFt,
    double buildingHeightFt,
  ) => switch (installationCode) {
    SignageCatalog.shopFascia => clearanceFt + 0.5,
    SignageCatalog.rooftop => buildingHeightFt + clearanceFt,
    _ => clearanceFt,
  };

  /// Builds the geometry for [b]. Optional overrides (in feet) let the 3D
  /// preview show live "what-if" dimensions before they are applied.
  factory SignageGeometry.fromBoard(
    Board b, {
    double? widthFt,
    double? heightFt,
    double? clearanceFt,
    double? bottomFt,
    SignageUnit? unit,
  }) {
    // Canonical advanced measurements (mm) win over legacy site answers.
    final mu = unit ?? (b.activeUnits.isEmpty ? null : b.activeUnits.first);
    final rec = mu?.measurements.valuesMm ?? const <String, double>{};
    double? recFt(String id) => rec[id] == null ? null : rec[id]! / 304.8;
    final selectedMedia = SignageCatalog.media(b.mediaCode);
    final media = selectedMedia ?? SignageCatalog.mediaTypes.first;
    // The unit's own installation (override, else the group's).
    var inst = mu != null ? b.installationOf(mu) : b.installationCode;
    final installationSelected =
        inst != null && SignageCatalog.installation(inst) != null;
    if (!installationSelected) inst = media.installations.isEmpty
          ? SignageCatalog.shopFascia
          : media.installations.first;
    final installation = inst;
    // This physical board's own answers (group map for the first unit).
    final a = SignageCatalog.answersOf(b, mu);

    // An explicitly requested unit uses its OWN size (different sizes);
    // without a unit the historical group size is used as before.
    final unitSized = unit != null && b.unitHasSize(unit);
    final hasSize = unitSized || b.hasSize;
    final ownW = unitSized ? b.unit.toFeet(b.widthOf(unit)!) : b.widthFt;
    final ownH = unitSized ? b.unit.toFeet(b.heightOf(unit)!) : b.heightFt;
    final w = (widthFt ?? (hasSize ? ownW : defaultWidthFt))
        .clamp(0.1, 2000.0)
        .toDouble();
    final h = (heightFt ?? (hasSize ? ownH : defaultHeightFt))
        .clamp(0.1, 2000.0)
        .toDouble();

    final floors = installation == SignageCatalog.rooftop
        ? (_num(a['building_floors']) ?? 2).clamp(1, 60).roundToDouble()
        : 0.0;
    final buildingH = floors * 10;

    final key = clearanceKey(installation);
    final recBottom = recFt('bottom_height');
    final recClearance = recBottom == null
        ? null
        : switch (installation) {
            SignageCatalog.shopFascia => recBottom - 0.5,
            SignageCatalog.rooftop => recBottom - buildingH,
            _ => recBottom,
          };
    final clearance =
        (clearanceFt ??
                recClearance ??
                (key == null ? null : _num(a[key])) ??
                defaultClearance(installation))
            .clamp(0.0, 500.0)
            .toDouble();
    final bottom =
        bottomFt ?? bottomFor(installation, clearance, buildingH.toDouble());

    final poleGap = installation == SignageCatalog.doublePole
        ? (recFt('pole_spacing') ?? _num(a['pole_gap']) ?? w * 0.7)
              .clamp(w < 0.5 ? w : 0.5, w)
              .toDouble()
        : 0.0;

    final projection = installation == SignageCatalog.flangeBracket
        ? (_num(a['projection']) ?? 1.0).clamp(0.0, 20.0).toDouble()
        : 0.0;

    final letterIn = _num(a['letter_height']);
    final panels = _num(a['panel_count'])?.round() ?? 2;

    return SignageGeometry(
      widthFt: w,
      heightFt: h,
      nlbBoxFrame: b.isNlbBoxFrame,
      nlbSingleFrame: b.isNlbSingleFrame,
      depthFt:
          recFt('board_depth') ??
          (b.isNlbSingleFrame
              ? 1 / 12
              : b.isNlbBoxFrame
              ? 4 / 12
              : (media.depthFt < 0.05 ? 0.05 : media.depthFt)),
      clearanceFt: clearance,
      bottomFt: bottom,
      buildingHeightFt: buildingH.toDouble(),
      poleGapFt: poleGap,
      projectionFt: projection,
      doubleSided: SignageCatalog.isDoubleSided(b),
      gsbLedRear: b.gsbLedOnRear,
      mediaCode: media.code,
      installationCode: installation,
      unit: b.unit,
      usingDefaults: !hasSize && widthFt == null && heightFt == null,
      mediaSelected: selectedMedia != null,
      installationSelected: installationSelected,
      quantity: b.quantity < 1 ? 1 : b.quantity,
      foundationDepthFt:
          (recFt('pole_embedment') ?? _num(a['foundation_depth']) ?? 3)
              .clamp(0.5, 20.0)
              .toDouble(),
      letterHeightFt: letterIn == null || letterIn <= 0 ? null : letterIn / 12,
      panelCount: panels.clamp(1, 12),
      acpColour: a['acp_colour'] as String?,
      baseWidthFt: installation == SignageCatalog.freeStanding
          ? (recFt('base_width') ??
                    _num(a['base_width']) ??
                    math.max(1.5, w * 0.7))
                .clamp(0.3, 100.0)
                .toDouble()
          : 0,
      baseDepthFt: installation == SignageCatalog.freeStanding
          ? (recFt('base_depth') ?? _num(a['base_depth']) ?? 1.5)
                .clamp(0.2, 50.0)
                .toDouble()
          : 0,
      supportType: installation == SignageCatalog.freeStanding
          ? (a['support_structure'] as String?) ?? 'Twin side posts'
          : null,
      spec: _specFor(
        b,
        mu,
        overrides:
            widthFt != null ||
            heightFt != null ||
            clearanceFt != null ||
            bottomFt != null,
        widthFt: w,
        heightFt: h,
        bottomFt: bottom,
      ),
    );
  }

  static SignageModelSpec? _specFor(
    Board b,
    SignageUnit? u, {
    required bool overrides,
    required double widthFt,
    required double heightFt,
    required double bottomFt,
  }) {
    if (u == null ||
        !SignageCatalog.newMediaTypes.any((m) => m.code == b.mediaCode)) {
      return null;
    }
    final spec = SignageModelSpec.of(b, u);
    if (!overrides) return spec;
    return spec.copyWith(
      values: {
        SpecField.width: widthFt * 304.8,
        SpecField.height: heightFt * 304.8,
        SpecField.mountingHeight: bottomFt * 304.8,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SignageGeometry &&
      other.widthFt == widthFt &&
      other.heightFt == heightFt &&
      other.depthFt == depthFt &&
      other.clearanceFt == clearanceFt &&
      other.bottomFt == bottomFt &&
      other.buildingHeightFt == buildingHeightFt &&
      other.poleGapFt == poleGapFt &&
      other.projectionFt == projectionFt &&
      other.doubleSided == doubleSided &&
      other.gsbLedRear == gsbLedRear &&
      other.nlbBoxFrame == nlbBoxFrame &&
      other.nlbSingleFrame == nlbSingleFrame &&
      other.mediaCode == mediaCode &&
      other.installationCode == installationCode &&
      other.unit == unit &&
      other.usingDefaults == usingDefaults &&
      other.letterHeightFt == letterHeightFt &&
      other.panelCount == panelCount &&
      other.acpColour == acpColour &&
      other.baseWidthFt == baseWidthFt &&
      other.baseDepthFt == baseDepthFt &&
      other.supportType == supportType &&
      other.foundationDepthFt == foundationDepthFt &&
      other.spec?.signature == spec?.signature;

  @override
  int get hashCode => Object.hashAll([
    widthFt,
    heightFt,
    depthFt,
    clearanceFt,
    bottomFt,
    buildingHeightFt,
    poleGapFt,
    projectionFt,
    doubleSided,
    gsbLedRear,
    nlbBoxFrame,
    nlbSingleFrame,
    mediaCode,
    installationCode,
    unit,
    usingDefaults,
    letterHeightFt,
    panelCount,
    acpColour,
    foundationDepthFt,
    baseWidthFt,
    baseDepthFt,
    supportType,
    spec?.signature,
  ]);
}
