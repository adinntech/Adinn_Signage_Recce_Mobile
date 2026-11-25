import 'dart:math' as math;

import '../../data/catalog/measurement_fields.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';

/// Editable dimensions of a signage model. Lengths are millimetres; the
/// angle is degrees; counts are plain numbers.
///
/// Every field has exactly one canonical home in the recce data:
/// * [width] / [height] – the board size (group size or per-unit size);
/// * all others – the unit's [MeasurementDetails] ([measureId]).
/// Legacy site answers (e.g. `pole_gap`) are read only as a fallback and
/// are kept mirrored on write, so there is one logical value everywhere.
enum SpecField {
  width,
  height,
  depth,
  mountingHeight,
  poleHeight,
  poleEmbedment,
  poleSpacing,
  poleCount,
  pipeCount,
  pipeLength,
  pipeSpacing,
  frameThickness,
  materialThickness,
  standoff,
  letterDepthFront,
  letterDepthRear,
  mdfThickness,
  gsbPanelWidth,
  gsbPanelHeight,
  gsbDepth,
  openingAngle,
  rooftopFrameHeight,
  baseWidth,
  baseDepth,
  overallHeight,
}

enum SpecValueKind { length, count, angle }

/// Where a resolved value came from.
enum SpecSource {
  /// Entered by the user (board size or recorded measurement).
  recorded,

  /// Read from an older site-question answer.
  siteAnswer,

  /// Not measured: a labelled illustrative default.
  assumed,
}

extension SpecFieldX on SpecField {
  /// Measurement field id in [MeasurementDetails] (null for width/height).
  String? get measureId => switch (this) {
    SpecField.width || SpecField.height => null,
    SpecField.depth => 'board_depth',
    SpecField.mountingHeight => 'bottom_height',
    SpecField.poleHeight => 'pole_above_ground',
    SpecField.poleEmbedment => 'pole_embedment',
    SpecField.poleSpacing => 'pole_spacing',
    SpecField.poleCount => 'pole_count',
    SpecField.pipeCount => 'pipe_count',
    SpecField.pipeLength => 'pipe_length',
    SpecField.pipeSpacing => 'pipe_spacing',
    SpecField.frameThickness => 'frame_thickness',
    SpecField.materialThickness => 'material_thickness',
    SpecField.standoff => 'standoff_offset',
    SpecField.letterDepthFront => 'letter_depth_front',
    SpecField.letterDepthRear => 'letter_depth_rear',
    SpecField.mdfThickness => 'mdf_thickness',
    SpecField.gsbPanelWidth => 'gsb_panel_width',
    SpecField.gsbPanelHeight => 'gsb_panel_height',
    SpecField.gsbDepth => 'gsb_depth',
    SpecField.openingAngle => 'opening_angle',
    SpecField.rooftopFrameHeight => 'rooftop_frame_height',
    SpecField.baseWidth => 'base_width',
    SpecField.baseDepth => 'base_depth',
    SpecField.overallHeight => 'standee_overall_height',
  };

  SpecValueKind get kind => switch (this) {
    SpecField.poleCount || SpecField.pipeCount => SpecValueKind.count,
    SpecField.openingAngle => SpecValueKind.angle,
    _ => SpecValueKind.length,
  };

  String get label => switch (this) {
    SpecField.width => 'Board width',
    SpecField.height => 'Board height',
    SpecField.depth => 'Board depth',
    SpecField.mountingHeight => 'Mounting height (ground clearance)',
    SpecField.poleHeight => 'Pole height above ground',
    SpecField.poleEmbedment => 'Pole embedment depth',
    SpecField.poleSpacing => 'Pole spacing',
    SpecField.poleCount => 'Pole count',
    SpecField.pipeCount => 'Support pipe count',
    SpecField.pipeLength => 'Support pipe length',
    SpecField.pipeSpacing => 'Support pipe spacing',
    SpecField.frameThickness => 'Frame thickness',
    SpecField.materialThickness => 'Material thickness',
    SpecField.standoff => 'Standoff offset',
    SpecField.letterDepthFront => 'Letter projection (front)',
    SpecField.letterDepthRear => 'Letter projection (rear)',
    SpecField.mdfThickness => 'MDF thickness',
    SpecField.gsbPanelWidth => 'GSB panel width',
    SpecField.gsbPanelHeight => 'GSB panel height',
    SpecField.gsbDepth => 'GSB box depth',
    SpecField.openingAngle => 'Opening angle',
    SpecField.rooftopFrameHeight => 'Rooftop frame height',
    SpecField.baseWidth => 'Base width',
    SpecField.baseDepth => 'Base depth',
    SpecField.overallHeight => 'Overall height',
  };
}

/// Mirrors between legacy site answers (feet) and measurement fields.
/// `pole_height` / `mount_height` / `panel_bottom_height` are all "ground
/// to board bottom" in the existing forms, i.e. the mounting height.
const Map<String, String> kAnswerMirrors = {
  'mount_height': 'bottom_height',
  'pole_height': 'bottom_height',
  'panel_bottom_height': 'bottom_height',
  'pole_gap': 'pole_spacing',
  'foundation_depth': 'pole_embedment',
  'base_width': 'base_width',
  'base_depth': 'base_depth',
  'overall_height': 'standee_overall_height',
  'structure_height': 'rooftop_frame_height',
  'pipe_length': 'pipe_length',
  'pipe_count': 'pipe_count',
};

/// Answer key that mirrors the mounting height for an installation.
String? mountAnswerKey(String? installationCode) => switch (installationCode) {
  SignageCatalog.singlePole || SignageCatalog.doublePole => 'pole_height',
  SignageCatalog.freeStanding => 'panel_bottom_height',
  SignageCatalog.wallMount ||
  SignageCatalog.flangeBracket ||
  SignageCatalog.directWall ||
  SignageCatalog.glassPasting ||
  SignageCatalog.supportPipe => 'mount_height',
  _ => null,
};

/// Model status label (never "factory verified" unless a reference was
/// technically approved).
enum ModelStatus { illustrative, referencePending, technicallyReviewed }

extension ModelStatusX on ModelStatus {
  String get label => switch (this) {
    ModelStatus.illustrative => 'Illustrative Model',
    ModelStatus.referencePending => 'Reference Pending',
    ModelStatus.technicallyReviewed => 'Technically Reviewed',
  };
}

/// Typed, renderer-independent specification of one signage item's model,
/// resolved from the canonical recce data. Business measurements only:
/// camera orientation and preview scale are never part of it.
class SignageModelSpec {
  SignageModelSpec({
    required this.signageItemId,
    required this.groupId,
    required this.mediaCode,
    required this.installationCode,
    required this.isDoubleSided,
    required this.template,
    required this.legacyMedia,
    required this.displayUnit,
    required Map<SpecField, double> values,
    required Map<SpecField, SpecSource> sources,
    this.mediaSelected = true,
    this.installationSelected = true,
    this.gsbLedRear = false,
    this.nlbBoxFrame = false,
    this.nlbSingleFrame = false,
  }) : values = Map.unmodifiable(values),
       sources = Map.unmodifiable(sources);

  final String signageItemId;
  final String groupId;
  final String mediaCode;
  final String installationCode;
  final bool isDoubleSided;

  /// Parametric template id (see [MediaType.template]).
  final String template;
  final bool legacyMedia;
  final MeasureUnit displayUnit;
  final bool mediaSelected;
  final bool installationSelected;

  /// GSB Double: the single LED set faces the rear (Night View only).
  final bool gsbLedRear;

  /// NLB Box Frame (NON_LIT_BOX): fully covered 4-in box.
  final bool nlbBoxFrame;

  /// NLB Single Frame (NON_LIT): slim open frame, pipes visible.
  final bool nlbSingleFrame;
  final Map<SpecField, double> values;
  final Map<SpecField, SpecSource> sources;

  /// Stable text of everything that shapes the model (cache key).
  String get signature => [
    signageItemId,
    mediaCode,
    installationCode,
    isDoubleSided,
    gsbLedRear,
    nlbBoxFrame,
    nlbSingleFrame,
    for (final f in SpecField.values)
      if (values.containsKey(f)) '${f.name}=${values[f]}',
  ].join('|');

  double operator [](SpecField f) => values[f] ?? 0;
  bool has(SpecField f) => values.containsKey(f);
  bool isAssumed(SpecField f) => sources[f] == SpecSource.assumed;

  double get widthMm => this[SpecField.width];
  double get heightMm => this[SpecField.height];
  double get depthMm => this[SpecField.depth];
  double get mountingHeightMm => this[SpecField.mountingHeight];
  double get topHeightMm => mountingHeightMm + heightMm;

  MediaType? get media => SignageCatalog.media(mediaCode);

  /// Fields relevant to this media + installation (what the editor shows).
  List<SpecField> get editableFields => [
    for (final f in SpecField.values)
      if (values.containsKey(f)) f,
  ];

  SignageModelSpec copyWith({
    Map<SpecField, double>? values,
    String? installationCode,
  }) => SignageModelSpec(
    signageItemId: signageItemId,
    groupId: groupId,
    mediaCode: mediaCode,
    installationCode: installationCode ?? this.installationCode,
    isDoubleSided: isDoubleSided,
    template: template,
    legacyMedia: legacyMedia,
    displayUnit: displayUnit,
    values: {...this.values, ...?values},
    sources: {
      ...sources,
      for (final f in (values ?? const <SpecField, double>{}).keys)
        f: SpecSource.recorded,
    },
    mediaSelected: mediaSelected,
    installationSelected: installationSelected,
    gsbLedRear: gsbLedRear,
    nlbBoxFrame: nlbBoxFrame,
    nlbSingleFrame: nlbSingleFrame,
  );

  /// Resolves the spec of unit [u] of [b] (pure; never writes).
  factory SignageModelSpec.of(Board b, SignageUnit u) {
    final media = SignageCatalog.media(b.mediaCode);
    final mediaCode = media?.code ?? SignageCatalog.gsb;
    var inst = b.installationOf(u);
    final instSelected =
        inst != null && SignageCatalog.installation(inst) != null;
    if (!instSelected) {
      inst = media?.installations.firstOrNull ?? SignageCatalog.shopFascia;
    }
    final installation = inst;
    final m = u.measurements;
    // This physical board's own Site Question answers.
    final a = SignageCatalog.answersOf(b, u);
    final values = <SpecField, double>{};
    final sources = <SpecField, SpecSource>{};
    final ft = MeasureUnit.ft.mmFactor;

    double? answerFt(String key) {
      final v = a[key];
      final d = v is num ? v.toDouble() : double.tryParse('$v');
      return d == null || !d.isFinite ? null : d;
    }

    void put(SpecField f, double fallback, {double? answerMm}) {
      final id = f.measureId;
      final rec = id == null
          ? null
          : (f.kind == SpecValueKind.length ? m.valuesMm[id] : m.counts[id]);
      if (rec != null) {
        values[f] = rec;
        sources[f] = SpecSource.recorded;
      } else if (answerMm != null) {
        values[f] = answerMm;
        sources[f] = SpecSource.siteAnswer;
      } else {
        values[f] = fallback;
        sources[f] = SpecSource.assumed;
      }
    }

    // Board size (canonical: group / unit size).
    final w = b.widthOf(u), h = b.heightOf(u);
    if (b.unitHasSize(u)) {
      values[SpecField.width] = b.unit.toMm(w!);
      values[SpecField.height] = b.unit.toMm(h!);
      sources[SpecField.width] = SpecSource.recorded;
      sources[SpecField.height] = SpecSource.recorded;
    } else {
      values[SpecField.width] = 10 * ft;
      values[SpecField.height] = 4 * ft;
      sources[SpecField.width] = SpecSource.assumed;
      sources[SpecField.height] = SpecSource.assumed;
    }
    final wMm = values[SpecField.width]!;
    final hMm = values[SpecField.height]!;
    final tpl = media?.template ?? '';
    final code = mediaCode;
    final thin = (media?.depthFt ?? 0.25) < 0.05;

    // Depth for rigid boards.
    if (!thin) {
      put(
        SpecField.depth,
        b.isNlbSingleFrame
            ? 25.4
            : b.isNlbBoxFrame
            ? 4 * 25.4
            : (media?.depthFt ?? 0.25) * ft,
      );
    }

    // Mounting height (ground clearance).
    final mountKey = mountAnswerKey(installation);
    double? mountAns = mountKey == null ? null : answerFt(mountKey);
    if (installation == SignageCatalog.shopFascia) {
      final shutter = answerFt('shutter_height');
      mountAns = shutter == null ? null : shutter + 0.5;
    }
    put(
      SpecField.mountingHeight,
      _defaultMountFt(installation) * ft,
      answerMm: mountAns == null ? null : mountAns * ft,
    );

    final poles =
        installation == SignageCatalog.singlePole ||
        installation == SignageCatalog.doublePole;
    if (poles) {
      final two = installation == SignageCatalog.doublePole;
      put(SpecField.poleCount, two ? 2 : 1);
      final mount = values[SpecField.mountingHeight]!;
      put(SpecField.poleHeight, mount + hMm);
      final emb = answerFt('foundation_depth');
      put(
        SpecField.poleEmbedment,
        3 * ft,
        answerMm: emb == null ? null : emb * ft,
      );
      if (two) {
        final gap = answerFt('pole_gap');
        put(
          SpecField.poleSpacing,
          wMm * 0.7,
          answerMm: gap == null ? null : gap * ft,
        );
      }
    }

    final pipes =
        installation == SignageCatalog.supportPipe ||
        installation == SignageCatalog.rooftop ||
        m.flags[MeasurementCatalog.pipesUsedFlag] == true;
    if (pipes) {
      final cnt = answerFt('pipe_count');
      put(SpecField.pipeCount, 2, answerMm: cnt);
      final len = answerFt('pipe_length');
      put(
        SpecField.pipeLength,
        2 * ft,
        answerMm: len == null ? null : len * ft,
      );
      put(SpecField.pipeSpacing, wMm * 0.6);
    }

    if (installation == SignageCatalog.rooftop) {
      final sh = answerFt('structure_height');
      put(
        SpecField.rooftopFrameHeight,
        4 * ft,
        answerMm: sh == null ? null : sh * ft,
      );
    }

    if (installation == SignageCatalog.freeStanding) {
      final bw = answerFt('base_width');
      final bd = answerFt('base_depth');
      put(
        SpecField.baseWidth,
        math.max(1.5 * ft, wMm * 0.7),
        answerMm: bw == null ? null : bw * ft,
      );
      put(SpecField.baseDepth, 1.5 * ft, answerMm: bd == null ? null : bd * ft);
      final oh = answerFt('overall_height');
      put(
        SpecField.overallHeight,
        values[SpecField.mountingHeight]! + hMm,
        answerMm: oh == null ? null : oh * ft,
      );
    }

    // Template-specific construction.
    if (tpl == 'gsb' || tpl == 'nonlit' || tpl == 'sandwich') {
      // GSB main frame: 1 × 1 in MS SHS (rulebook); others unchanged.
      put(SpecField.frameThickness, switch (tpl) {
        'sandwich' => 25,
        'gsb' when code == SignageCatalog.gsb => 25.4,
        _ => 40,
      });
    }
    if (const {'foam', 'acrylic', 'acp2d', 'acp3d', 'sandwich'}.contains(tpl)) {
      put(SpecField.materialThickness, media!.thicknessMm);
    }
    if (tpl == 'acrylic') put(SpecField.standoff, 25);
    if (tpl == 'acp3d') {
      put(SpecField.letterDepthFront, 50);
      if (code == SignageCatalog.acp3dDouble) {
        put(SpecField.letterDepthRear, 50);
      }
    }
    if (tpl == 'mdfgsb') {
      put(SpecField.mdfThickness, 18);
      put(SpecField.gsbPanelWidth, wMm * 0.8);
      put(SpecField.gsbPanelHeight, hMm * 0.6);
      put(SpecField.gsbDepth, 150);
    }
    if (tpl == 'sandwich') put(SpecField.openingAngle, 22);

    return SignageModelSpec(
      signageItemId: u.id,
      groupId: b.id,
      mediaCode: code,
      installationCode: installation,
      isDoubleSided: SignageCatalog.isDoubleSided(b),
      template: tpl,
      legacyMedia: media?.legacy ?? false,
      displayUnit: b.unit,
      values: values,
      sources: sources,
      mediaSelected: media != null,
      installationSelected: instSelected,
      gsbLedRear: b.gsbLedOnRear,
      nlbBoxFrame: b.isNlbBoxFrame,
      nlbSingleFrame: b.isNlbSingleFrame,
    );
  }

  static double _defaultMountFt(String installation) => switch (installation) {
    SignageCatalog.doublePole || SignageCatalog.singlePole => 9,
    SignageCatalog.wallMount => 8,
    SignageCatalog.flangeBracket => 9,
    SignageCatalog.directWall => 3,
    SignageCatalog.glassPasting => 1,
    SignageCatalog.shopFascia => 9.5,
    SignageCatalog.rooftop => 20,
    SignageCatalog.freeStanding => 0.5,
    SignageCatalog.supportPipe => 9,
    _ => 8,
  };

  /// Validation of edited values (before they are committed).
  static List<String> validate(Map<SpecField, double> values) {
    final out = <String>[];
    values.forEach((f, v) {
      if (!v.isFinite) {
        out.add('${f.label}: invalid number');
      } else if (f.kind == SpecValueKind.count &&
          (v < 1 || v != v.roundToDouble())) {
        out.add('${f.label} must be a whole number of 1 or more');
      } else if (f.kind == SpecValueKind.angle && (v <= 0 || v >= 90)) {
        out.add('${f.label} must be between 0 and 90°');
      } else if (v < 0) {
        out.add('${f.label} cannot be negative');
      } else if (v == 0 &&
          f != SpecField.mountingHeight &&
          f != SpecField.standoff &&
          f != SpecField.poleEmbedment) {
        out.add('${f.label} must be greater than zero');
      }
    });
    return out;
  }
}
