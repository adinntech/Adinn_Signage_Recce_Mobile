import 'dart:math' as math;
import 'dart:ui';

import '../../data/catalog/measurement_fields.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../drawing/signage_geometry.dart';
import '../gsb/gsb_presentation.dart';
import '../nlb/nlb_presentation.dart';
import '../preview3d/scene3d.dart';
import '../preview3d/signage_scene_builder.dart' show SceneColors;
import 'parametric_model.dart';
import 'signage_spec.dart';

export 'parametric_model.dart';

typedef _C = ModelComponentIds;

/// Builds parametric 3D models of the 13-media signage catalog from a typed
/// [SignageModelSpec] (millimetres) for the existing pure-Dart renderer
/// (scene units: feet, +Y up, board front facing +Z at z = 0, depth towards
/// −Z).
///
/// The media template decides the board construction (GSB light box, ACP
/// tray with raised letters, A-frame…); the installation code decides the
/// support structure (poles, pipes, brackets, rooftop frame…). Both are
/// independent, so e.g. changing the pole spacing never changes the board.
/// Models are illustrative approximations, not fabrication drawings.
///
/// Dimension ids: `width`, `height`, `depth`, `material_thickness`,
/// `mounting_height`, `pole_height`, `pole_embedment`, `pole_spacing`,
/// `pipe_length`, `pipe_spacing`, `rooftop_frame_height`, `base_width`,
/// `base_depth`, `overall_height`, `letter_depth_front`,
/// `letter_depth_rear`, `mdf_thickness`, `gsb_width`, `gsb_height`,
/// `gsb_depth`, `standoff`, `spread` (sandwich footprint).
class ParametricModelBuilder {
  ParametricModelBuilder._();

  /// Media routed from [SignageSceneBuilder] to this builder (the 10 media
  /// added with catalog v2). GSB, NLB, ACP and legacy media keep the legacy
  /// scene builder there.
  static const routedMediaCodes = {
    SignageCatalog.foamVinyl,
    SignageCatalog.clearAcrylic,
    SignageCatalog.sandwichBoard,
    SignageCatalog.oneWayVision,
    SignageCatalog.plainVinyl,
    SignageCatalog.acp2d,
    SignageCatalog.acp2dDouble,
    SignageCatalog.acp3dDouble,
    SignageCatalog.mdfGsb,
    SignageCatalog.mdfGsbDouble,
  };

  /// Template id for a media code. Legacy media (empty template) fall back
  /// to the closest construction: flange → 'gsb', vinyl / wall painting →
  /// 'vinyl', standees and unknown codes → 'nonlit'.
  static String templateFor(String? mediaCode) {
    final t = SignageCatalog.media(mediaCode)?.template ?? '';
    if (t.isNotEmpty) return t;
    return switch (mediaCode) {
      SignageCatalog.flange => 'gsb',
      SignageCatalog.vinyl || SignageCatalog.wallPainting => 'vinyl',
      _ => 'nonlit',
    };
  }

  /// Reasons why [spec]'s media + installation cannot be modelled (empty
  /// when supported). Another mounting is never substituted silently.
  static List<String> unsupportedReason(SignageModelSpec spec) {
    final out = <String>[];
    final media = SignageCatalog.media(spec.mediaCode);
    final inst = SignageCatalog.installation(spec.installationCode);
    if (media == null) {
      out.add(
        'Unknown media type "${spec.mediaCode}": shown as a generic panel.',
      );
    }
    if (inst == null) {
      out.add(
        'Unknown installation "${spec.installationCode}": the board is shown '
        'without a support structure.',
      );
    } else if (media != null && !media.installations.contains(inst.code)) {
      final allowed = media.installations
          .map((c) => SignageCatalog.installation(c)?.name ?? c)
          .join(', ');
      out.add(
        '${inst.name} is not a supported installation for ${media.name} '
        '(allowed: $allowed). The board is shown without a support '
        'structure.',
      );
    }
    return out;
  }

  /// Builds the model of [spec].
  ///
  /// * [dimensions] – also push the dimension lines into `scene.dims`;
  /// * [hiddenComponents] – component ids left out of the scene (still
  ///   listed in `components` with `visible: false`);
  /// * [highlight] – component id drawn tinted (geometry unchanged);
  /// * [context] – include the surroundings ('wall', 'ground').
  static ParametricModel build(
    SignageModelSpec spec, {
    String brand = 'ADINN',
    bool dimensions = true,
    Set<String> hiddenComponents = const {},
    String? highlight,
    bool context = true,
  }) => _Build(
    spec,
    brand,
    context,
  ).run(dimensions: dimensions, hidden: hiddenComponents, highlight: highlight);

  // ---------------------------------------------------------------------------
  // Legacy SignageGeometry adapter (Live Preview / AR / 3D preview)
  // ---------------------------------------------------------------------------

  /// Whether [SignageSceneBuilder] hands geometry [g] to this builder.
  static bool routesGeometry(SignageGeometry g) =>
      routedMediaCodes.contains(g.mediaCode);

  /// Spec equivalent of a legacy [SignageGeometry]. Size, depth, mounting
  /// height, pole spacing / embedment, rooftop frame height and standee
  /// base come from [g]; everything else uses the spec's labelled defaults
  /// (geometry does not carry e.g. letter depth or GSB panel size).
  static SignageModelSpec specFromGeometry(SignageGeometry g) {
    final mm = <String, double>{'bottom_height': g.bottomFt * kMmPerFoot};
    if (g.media.depthFt >= 0.05) mm['board_depth'] = g.depthFt * kMmPerFoot;
    switch (g.installationCode) {
      case SignageCatalog.doublePole:
        mm['pole_spacing'] = g.poleGapFt * kMmPerFoot;
        mm['pole_embedment'] = g.foundationDepthFt * kMmPerFoot;
      case SignageCatalog.singlePole:
        mm['pole_embedment'] = g.foundationDepthFt * kMmPerFoot;
      case SignageCatalog.rooftop:
        mm['rooftop_frame_height'] = g.clearanceFt * kMmPerFoot;
      case SignageCatalog.freeStanding:
        if (g.baseWidthFt > 0) mm['base_width'] = g.baseWidthFt * kMmPerFoot;
        if (g.baseDepthFt > 0) mm['base_depth'] = g.baseDepthFt * kMmPerFoot;
    }
    final unit = SignageUnit(
      id: 'geometry',
      measurements: MeasurementDetails(valuesMm: mm),
    );
    final board = Board(
      id: 'geometry',
      name: 'Geometry',
      mediaCode: g.mediaCode,
      installationCode: g.installationCode,
      width: g.unit.fromFeet(g.widthFt),
      height: g.unit.fromFeet(g.heightFt),
      unit: g.unit,
      doubleSided: g.doubleSided,
      units: [unit],
    );
    return SignageModelSpec.of(board, unit);
  }

  /// Legacy-compatible scene for [g]: the parametric model with solids
  /// renamed to the legacy names ('board', 'pole', 'base', 'wall') that
  /// existing consumers (e.g. the AR pivot) look for. [modelOnly] drops the
  /// surroundings and the glass pane (photo overlays provide them).
  static Scene sceneForGeometry(
    SignageGeometry g, {
    String brand = 'ADINN',
    bool modelOnly = false,
    bool dimensions = true,
  }) {
    final model = build(
      g.spec ?? specFromGeometry(g),
      brand: brand,
      dimensions: dimensions,
      context: !modelOnly,
      hiddenComponents: modelOnly ? const {_C.glassBacking} : const {},
    );
    final scene = Scene(focus: model.scene.focus);
    for (final s in model.scene.solids) {
      final copy = Solid(
        name: legacyName(ModelComponentIds.of(s.name)),
        faces: s.faces,
      );
      copy.decals.addAll(s.decals);
      copy.decalNormal = s.decalNormal;
      scene.add(copy);
    }
    scene.dims.addAll(model.scene.dims);
    scene.finalize();
    return scene;
  }

  /// Legacy solid name of a component (board parts and wall fixings →
  /// 'board', so the AR wall pivot lands on the mounting surface).
  static String legacyName(String componentId) => switch (componentId) {
    _C.displayPanel ||
    _C.frontFace ||
    _C.backFace ||
    _C.frame ||
    _C.sideReturns ||
    _C.rearSupports ||
    _C.illuminatedSurface ||
    _C.raisedLettersFront ||
    _C.raisedLettersBack ||
    _C.vinylLayer ||
    _C.mdfBacking ||
    _C.gsbBox ||
    _C.wallBrackets ||
    _C.standoffs ||
    _C.supportPipes => 'board',
    _C.poles => 'pole',
    _C.standBase => 'base',
    _ => componentId,
  };
}

// -----------------------------------------------------------------------------
// Implementation
// -----------------------------------------------------------------------------

const _eps = 1e-4;
const _white = Color(0xFFFFFFFF);
const _vinylInk = Color(0xFF00897B);
const _acrylicBody = Color(0x4D9FD8E3);
const _acrylicEdge = Color(0xB34FB3BF);
const _glass = Color(0x5586B3D1);
const _mdf = Color(0xFFC49A6C);
const _logo = Color(0xFF263238);
const _rubber = Color(0xFF2B2B2B);
const _embedded = Color(0x808C939B);
const _groundTint = Color(0x336B7A5A);
const _studBody = Color(0xFF8F979F);
const _highlight = Color(0xFFFFB300);

const _componentFields = <String, List<SpecField>>{
  _C.displayPanel: [
    SpecField.width,
    SpecField.height,
    SpecField.depth,
    SpecField.materialThickness,
  ],
  _C.frontFace: [SpecField.width, SpecField.height],
  _C.backFace: [SpecField.width, SpecField.height],
  _C.frame: [
    SpecField.frameThickness,
    SpecField.openingAngle,
    SpecField.overallHeight,
  ],
  _C.sideReturns: [SpecField.depth, SpecField.materialThickness],
  _C.rearSupports: [SpecField.depth],
  _C.wallBrackets: [SpecField.mountingHeight],
  _C.standoffs: [SpecField.standoff],
  _C.poles: [
    SpecField.poleCount,
    SpecField.poleSpacing,
    SpecField.poleHeight,
    SpecField.poleEmbedment,
    SpecField.mountingHeight,
    SpecField.overallHeight,
  ],
  _C.supportPipes: [
    SpecField.pipeCount,
    SpecField.pipeSpacing,
    SpecField.pipeLength,
    SpecField.mountingHeight,
  ],
  _C.standBase: [
    SpecField.baseWidth,
    SpecField.baseDepth,
    SpecField.overallHeight,
  ],
  _C.rooftopFrame: [SpecField.rooftopFrameHeight, SpecField.mountingHeight],
  _C.illuminatedSurface: [SpecField.gsbPanelWidth, SpecField.gsbPanelHeight],
  _C.raisedLettersFront: [SpecField.letterDepthFront],
  _C.raisedLettersBack: [SpecField.letterDepthRear],
  _C.glassBacking: [SpecField.mountingHeight],
  _C.vinylLayer: [
    SpecField.width,
    SpecField.height,
    SpecField.materialThickness,
  ],
  _C.mdfBacking: [SpecField.width, SpecField.height, SpecField.mdfThickness],
  _C.gsbBox: [
    SpecField.gsbPanelWidth,
    SpecField.gsbPanelHeight,
    SpecField.gsbDepth,
  ],
  _C.wall: [],
  _C.ground: [],
};

/// Extent of the board assembly built by a template (local frame).
class _Env {
  double zFront = 0;

  /// Back of the board body (without rear letters / supports / standoffs).
  double zBodyBack = 0;

  /// Back of everything that belongs to the board (mounting surface side).
  double zBack = 0;

  /// The template already models its wall standoffs (acrylic).
  bool ownsStandoffs = false;

  /// The template already models the glass it is applied on (OWV).
  bool ownsGlass = false;

  /// Thickness of the main sheet (for the material dimension).
  double materialFt = 0;

  /// Letter row (ACP 3D) for the letter projection dimensions.
  double letterX = 0;
  double letterTop = 0;
}

class _Build {
  _Build(this.spec, String brand, this.context)
    : brand = brand.trim().isEmpty ? 'ADINN' : brand.trim().toUpperCase(),
      template = ParametricModelBuilder.templateFor(spec.mediaCode),
      unsupported = ParametricModelBuilder.unsupportedReason(spec),
      media = SignageCatalog.media(spec.mediaCode) {
    w = _ft(SpecField.width, 10 * kMmPerFoot, minMm: 10);
    h = _ft(SpecField.height, 4 * kMmPerFoot, minMm: 10);
    b = _ft(SpecField.mountingHeight, 0, minMm: 0);
    off = math.max(0.7, 0.08 * math.max(w, h));
  }

  final SignageModelSpec spec;
  final String brand;
  final bool context;
  final String template;
  final List<String> unsupported;
  final MediaType? media;

  final _solids = <Solid>[];
  final _dims = <ModelDimension>[];
  final _notes = <String>[];
  final _seq = <String, int>{};
  final env = _Env();
  Vec3? _focus;

  late final double w, h, b, off;
  double get t => b + h;
  bool get ds => spec.isDoubleSided;
  String get inst => spec.installationCode;
  double get zMid => env.zBodyBack / 2;

  // ---------------------------------------------------------------------------
  // Values
  // ---------------------------------------------------------------------------

  /// Spec value in mm: non-finite → fallback, clamped to [minMm, 1e6].
  double _mm(SpecField f, double fallbackMm, {double minMm = 1}) {
    var v = spec.values[f];
    if (v == null || !v.isFinite) v = fallbackMm;
    if (!v.isFinite) v = minMm;
    return v.clamp(minMm, 1e6).toDouble();
  }

  double _ft(SpecField f, double fallbackMm, {double minMm = 1}) =>
      _mm(f, fallbackMm, minMm: minMm) / kMmPerFoot;

  int _count(SpecField f, int fallback) {
    final v = spec.values[f];
    if (v == null || !v.isFinite) return fallback;
    return v.round().clamp(1, 12);
  }

  double get _mediaDepthMm => (media?.depthFt ?? 0.25) * kMmPerFoot;

  double _mediaThicknessMm(double fallback) {
    final t = media?.thicknessMm ?? 0;
    return t > 0 ? t : fallback;
  }

  String _fmt(double mm, {bool small = false}) {
    final u = spec.displayUnit;
    if (small && (u == MeasureUnit.ft || u == MeasureUnit.m) && mm < 100) {
      return fmtMm(mm, MeasureUnit.mm);
    }
    return fmtMm(mm, u);
  }

  // ---------------------------------------------------------------------------
  // Geometry helpers
  // ---------------------------------------------------------------------------

  /// 'frame', then 'frame:2', 'frame:3'…
  String _n(String id) {
    final n = (_seq[id] ?? 0) + 1;
    _seq[id] = n;
    return n == 1 ? id : '$id:$n';
  }

  void _add(Solid s) => _solids.add(s);

  Solid _box(
    String id,
    Vec3 min,
    Vec3 max,
    Color color, {
    Map<BoxSide, Color> sideColors = const {},
    Map<BoxSide, String> labels = const {},
    Color labelColor = _white,
    Set<BoxSide> emissive = const {},
  }) => Shapes.box(
    min,
    Vec3(
      math.max(max.x, min.x + _eps),
      math.max(max.y, min.y + _eps),
      math.max(max.z, min.z + _eps),
    ),
    color,
    name: _n(id),
    sideColors: sideColors,
    labels: labels,
    labelColor: labelColor,
    emissive: emissive,
  );

  /// Zero-thickness artwork skin on the plane z = [z] (front or back).
  Solid _skin(
    String id,
    double x0,
    double y0,
    double x1,
    double y1,
    double z,
    Color color, {
    bool back = false,
    String? label,
    Color labelColor = _white,
    bool emissive = false,
  }) {
    x1 = math.max(x1, x0 + _eps);
    y1 = math.max(y1, y0 + _eps);
    final face = back
        ? Face(
            [
              Vec3(x1, y1, z),
              Vec3(x0, y1, z),
              Vec3(x0, y0, z),
              Vec3(x1, y0, z),
            ],
            color,
            const Vec3(0, 0, -1),
            label: label,
            labelColor: labelColor,
            emissive: emissive,
          )
        : Shapes.frontQuad(
            x0,
            y0,
            x1,
            y1,
            z,
            color,
            label: label,
            labelColor: labelColor,
            emissive: emissive,
            layer: 0,
          );
    return Solid(name: _n(id), faces: [face]);
  }

  void _beam(String id, Vec3 a, Vec3 c, double thickness, Color color) {
    if ((c - a).length < _eps) return;
    _add(Shapes.beam(a, c, thickness, color, name: _n(id)));
  }

  /// Oriented box o + u·[0,du] + v·[0,dv] + n·[0,dn] (u × v = n); the
  /// outer (+n) face is ordered for labels.
  Solid _obox(
    String id,
    Vec3 o,
    Vec3 u,
    Vec3 v,
    Vec3 n,
    double du,
    double dv,
    double dn,
    Color color, {
    Color? outer,
  }) {
    Vec3 p(double a, double bb, double c) => o + u * a + v * bb + n * c;
    return Solid(
      name: _n(id),
      faces: [
        Face(
          [p(0, dv, dn), p(du, dv, dn), p(du, 0, dn), p(0, 0, dn)],
          outer ?? color,
          n,
        ),
        Face([p(du, dv, 0), p(0, dv, 0), p(0, 0, 0), p(du, 0, 0)], color, -n),
        Face(
          [p(du, dv, dn), p(du, dv, 0), p(du, 0, 0), p(du, 0, dn)],
          color,
          u,
        ),
        Face([p(0, dv, 0), p(0, dv, dn), p(0, 0, dn), p(0, 0, 0)], color, -u),
        Face(
          [p(0, dv, 0), p(du, dv, 0), p(du, dv, dn), p(0, dv, dn)],
          color,
          v,
        ),
        Face([p(0, 0, dn), p(du, 0, dn), p(du, 0, 0), p(0, 0, 0)], color, -v),
      ],
    );
  }

  /// Four bars around the board outline between z0 and z1.
  void _perimeter(String id, double band, double z0, double z1, Color c) {
    final x0 = -w / 2, x1 = w / 2;
    for (final (mn, mx) in [
      (Vec3(x0, t - band, z0), Vec3(x1, t, z1)),
      (Vec3(x0, b, z0), Vec3(x1, b + band, z1)),
      (Vec3(x0, b + band, z0), Vec3(x0 + band, t - band, z1)),
      (Vec3(x1 - band, b + band, z0), Vec3(x1, t - band, z1)),
    ]) {
      _add(_box(id, mn, mx, c));
    }
  }

  void _dim(
    String id,
    String prefix,
    Vec3 a,
    Vec3 c,
    Vec3 offset, {
    SpecField? field,
    bool small = false,
  }) {
    final mm = (c - a).length * kMmPerFoot;
    if (mm < 1e-6) return;
    _dims.add(
      ModelDimension(
        id: id,
        label: '$prefix ${_fmt(mm, small: small)}',
        a: a,
        b: c,
        offset: offset,
        field: field,
        valueMm: mm,
      ),
    );
  }

  /// Evenly spread positions across the board width.
  List<double> _spread(int n, double inset) {
    if (n <= 1) return [0];
    final half = w / 2 - inset > 0.05 ? w / 2 - inset : w * 0.3;
    return [for (var i = 0; i < n; i++) -half + 2 * half * i / (n - 1)];
  }

  // ---------------------------------------------------------------------------
  // Run
  // ---------------------------------------------------------------------------

  ParametricModel run({
    required bool dimensions,
    required Set<String> hidden,
    required String? highlight,
  }) {
    _template();
    if (template != 'sandwich') _boardDims();
    if (unsupported.isEmpty && template != 'sandwich') _installation();
    if (context) _ground();

    final focus = _focus ?? Vec3(0, b + h / 2, zMid);
    final scene = Scene(focus: focus);
    final ids = <String>[];
    for (final s in _solids) {
      final id = ModelComponentIds.of(s.name);
      if (!ids.contains(id)) ids.add(id);
      if (hidden.contains(id)) continue;
      scene.add(id == highlight ? _tinted(s) : s);
    }
    if (dimensions) scene.dims.addAll(_dims.map((d) => d.toDim3()));
    scene.finalize();
    return ParametricModel(
      scene: scene,
      components: [
        for (final id in ids)
          ModelComponent(
            id: id,
            label: _label(id),
            editable: [
              for (final f in _componentFields[id] ?? const <SpecField>[])
                if (spec.has(f)) f,
            ],
            visible: !hidden.contains(id),
          ),
      ],
      dimensions: List.unmodifiable(_dims),
      templateId: template,
      unsupported: unsupported,
      notes: List.unmodifiable(_notes),
    );
  }

  static Face _tint(Face f) =>
      Face(
          f.points,
          Color.lerp(f.color, _highlight, 0.45)!.withValues(alpha: f.color.a),
          f.normal,
          outline: true,
          emissive: f.emissive,
          label: f.label,
          labelColor: f.labelColor,
          layer: f.layer,
        )
        ..glow = f.glow
        ..perforationPitchFt = f.perforationPitchFt
        ..perforationHole = f.perforationHole;

  static Solid _tinted(Solid s) {
    final copy = Solid(name: s.name, faces: s.faces.map(_tint).toList());
    copy.decals.addAll(s.decals.map(_tint));
    copy.decalNormal = s.decalNormal;
    return copy;
  }

  String _label(String id) => switch (id) {
    _C.displayPanel => switch (template) {
      'acp2d' || 'acp3d' => 'ACP panel',
      'foam' => 'Foam board substrate',
      'acrylic' => 'Clear acrylic panel',
      'gsb' => 'Glow sign box',
      _ => 'Display panel',
    },
    _C.frontFace => 'Front artwork',
    _C.backFace => 'Rear artwork',
    _C.frame => template == 'sandwich' ? 'A-frame legs & hinge' : 'Frame',
    _C.sideReturns => 'Side returns',
    _C.rearSupports => 'Rear supports',
    _C.wallBrackets => 'Wall brackets',
    _C.standoffs => 'Standoffs',
    _C.poles => inst == SignageCatalog.freeStanding ? 'Posts' : 'Poles',
    _C.supportPipes => 'Support pipes',
    _C.standBase => template == 'sandwich' ? 'Feet' : 'Stand base',
    _C.rooftopFrame => 'Rooftop frame',
    _C.illuminatedSurface => 'Illuminated GSB face',
    _C.raisedLettersFront => 'Raised letters (front)',
    _C.raisedLettersBack => 'Raised letters (rear)',
    _C.glassBacking => 'Glass',
    _C.vinylLayer => template == 'owv' ? 'Perforated film' : 'Vinyl layer',
    _C.mdfBacking => 'MDF backing',
    _C.gsbBox => 'GSB box',
    _C.wall => inst == SignageCatalog.rooftop ? 'Building' : 'Wall',
    _C.ground => 'Ground',
    _ => id,
  };

  // ---------------------------------------------------------------------------
  // Templates
  // ---------------------------------------------------------------------------

  void _template() {
    switch (template) {
      case 'gsb':
        _boxBoard(lit: true);
      case 'foam':
        _foam();
      case 'acrylic':
        _acrylic();
      case 'sandwich':
        _sandwich();
      case 'owv':
        _film(perforated: true);
      case 'vinyl':
        _film(perforated: false);
      case 'acp2d':
        _acp(letters: false);
      case 'acp3d':
        _acp(letters: true);
      case 'mdfgsb':
        _mdfGsb();
      default: // 'nonlit'
        _boxBoard(lit: false);
    }
  }

  /// GSB (lit) / Non-Lit board: box + perimeter frame (+ rear supports).
  void _boxBoard({required bool lit}) {
    final d = _ft(SpecField.depth, _mediaDepthMm, minMm: 5);
    if (!lit && spec.mediaCode == SignageCatalog.nlb && spec.nlbSingleFrame) {
      // NLB Single Frame: open steel frame with visible pipes.
      for (final s in NlbSingleBoard.build(
        NlbSinglePresentation(
          widthFt: w,
          heightFt: h,
          bottomFt: b,
          profileIn: d * 12,
          brand: brand,
        ),
        memberName: _C.frame,
        flexName: _C.frontFace,
      )) {
        _add(s);
      }
      env
        ..zFront = 0
        ..zBodyBack = -d
        ..zBack = -d;
      return;
    }
    if (!lit && spec.mediaCode == SignageCatalog.nlb && spec.nlbBoxFrame) {
      // NLB Box Frame: six flex surfaces, frame hidden, not lit.
      for (final s in NlbBoxBoard.build(
        NlbBoxPresentation(
          widthFt: w,
          heightFt: h,
          depthFt: d,
          bottomFt: b,
          brand: brand,
        ),
        bodyName: _n(_C.displayPanel),
        frontName: _n(_C.frontFace),
        rearName: _n(_C.backFace),
      )) {
        _add(s);
      }
      env
        ..zFront = 0
        ..zBodyBack = -d
        ..zBack = -d;
      return;
    }
    if (lit && spec.mediaCode == SignageCatalog.gsb) {
      // Finished GSB exterior (same builder as Live Preview / AR). The
      // fabrication structure stays in the engine; it is only drawn in the
      // opt-in "Fabrication frame" view.
      for (final s in GsbFinishedBoard.build(
        GsbPresentation(
          widthFt: w,
          heightFt: h,
          depthFt: d,
          bottomFt: b,
          isDouble: ds,
          brand: brand,
          ledOnRear: spec.gsbLedRear,
        ),
        bodyName: _n(_C.displayPanel),
        frontName: _n(_C.frontFace),
        rearName: _n(_C.backFace),
      )) {
        _add(s);
      }
      env
        ..zFront = 0
        ..zBodyBack = -d
        ..zBack = -d;
      return;
    }
    final band = math.min(
      _ft(SpecField.frameThickness, 40),
      math.min(w, h) * 0.25,
    );
    final lip = math.min(band * 0.5, 0.06);
    final face = lit ? SceneColors.red : SceneColors.white;
    final ink = lit ? SceneColors.white : SceneColors.red;
    _add(
      _box(
        _C.displayPanel,
        Vec3(-w / 2, b, -d),
        Vec3(w / 2, t, 0),
        SceneColors.frame,
        sideColors: {
          BoxSide.front: face,
          BoxSide.back: ds ? face : SceneColors.steel,
        },
      ),
    );
    _add(
      _skin(
        _C.frontFace,
        -w / 2 + band,
        b + band,
        w / 2 - band,
        t - band,
        0,
        face,
        label: brand,
        labelColor: ink,
        emissive: lit,
      ),
    );
    _perimeter(_C.frame, band, 0, lip, SceneColors.frame);
    env
      ..zFront = lip
      ..zBodyBack = -d
      ..zBack = -d;
    if (ds) {
      _add(
        _skin(
          _C.backFace,
          -w / 2 + band,
          b + band,
          w / 2 - band,
          t - band,
          -d,
          face,
          back: true,
          label: brand,
          labelColor: ink,
          emissive: lit,
        ),
      );
      _perimeter(_C.frame, band, -d - lip, -d, SceneColors.frame);
      env.zBack = -d - lip;
    } else if (lit) {
      // MS angle members behind the light box.
      final s = math.min(0.12, w / 4);
      for (final x in _spread(math.max(2, (w / 4).ceil() + 1), s / 2)) {
        _add(
          _box(
            _C.rearSupports,
            Vec3(x - s / 2, b, -d - s),
            Vec3(x + s / 2, t, -d),
            SceneColors.steel,
          ),
        );
      }
      env.zBack = -d - s;
    }
  }

  void _foam() {
    final th = _ft(
      SpecField.materialThickness,
      _mediaThicknessMm(5),
      minMm: 0.5,
    );
    _add(
      _box(
        _C.displayPanel,
        Vec3(-w / 2, b, -th),
        Vec3(w / 2, t, 0),
        SceneColors.white,
      ),
    );
    _add(_skin(_C.vinylLayer, -w / 2, b, w / 2, t, 0, _vinylInk, label: brand));
    if (ds) {
      _add(
        _skin(
          _C.backFace,
          -w / 2,
          b,
          w / 2,
          t,
          -th,
          _vinylInk,
          back: true,
          label: brand,
        ),
      );
    }
    env
      ..zBodyBack = -th
      ..zBack = -th
      ..materialFt = th;
  }

  void _acrylic() {
    final th = _ft(
      SpecField.materialThickness,
      _mediaThicknessMm(8),
      minMm: 0.5,
    );
    final s = _ft(SpecField.standoff, 0, minMm: 0);
    _add(
      _box(
        _C.displayPanel,
        Vec3(-w / 2, b, -th),
        Vec3(w / 2, t, 0),
        _acrylicEdge,
        sideColors: {BoxSide.front: _acrylicBody, BoxSide.back: _acrylicBody},
      ),
    );
    _add(
      _skin(
        _C.frontFace,
        -w * 0.35,
        b + h * 0.25,
        w * 0.35,
        t - h * 0.25,
        0,
        SceneColors.red,
        label: brand,
      ),
    );
    if (ds) {
      _add(
        _skin(
          _C.backFace,
          -w * 0.35,
          b + h * 0.25,
          w * 0.35,
          t - h * 0.25,
          -th,
          SceneColors.red,
          back: true,
          label: brand,
        ),
      );
    }
    env
      ..zBodyBack = -th
      ..zBack = -th - s
      ..materialFt = th
      ..ownsStandoffs = true;
    if (s * kMmPerFoot > 1e-6) {
      final small = math.min(w, h);
      final m = math.min(math.max(0.15, small * 0.1), small * 0.4);
      final r = math.min(0.04, small * 0.08);
      const cap = 0.02; // cap stands ~6 mm proud of the sheet
      // Four corner studs: low-poly cylinders (spacer behind the sheet,
      // brushed-steel cap in front). Layout is derived from the board size
      // (illustrative setback) – not a manufacturer-approved pattern.
      for (final x in [-w / 2 + m, w / 2 - m]) {
        for (final y in [b + m, t - m]) {
          _add(
            Shapes.zCylinder(
              x,
              y,
              -th - s,
              -th,
              r * 0.7,
              SceneColors.steel,
              name: _n(_C.standoffs),
            ),
          );
          _add(
            Shapes.zCylinder(
              x,
              y,
              0,
              cap,
              r * 1.35,
              _studBody,
              sides: 12,
              capColor: SceneColors.silver,
              name: _n(_C.standoffs),
            ),
          );
        }
      }
      env.zFront = cap;
      _dim(
        'stud_spacing_h',
        'Stud c/c',
        Vec3(-w / 2 + m, b + m, cap),
        Vec3(w / 2 - m, b + m, cap),
        Vec3(0, -off * 0.45, 0),
      );
      _dim(
        'stud_spacing_v',
        'Stud c/c',
        Vec3(-w / 2 + m, b + m, cap),
        Vec3(-w / 2 + m, t - m, cap),
        Vec3(-off * 0.45, 0, 0),
      );
      _notes.add(
        'Stud positions are illustrative (edge setback ${_fmt(m * kMmPerFoot)}); '
        'stud size and spacing are not manufacturer-approved values.',
      );
    } else {
      _notes.add('Standoff (wall gap) is Not specified: no studs drawn.');
    }
  }

  /// One-way vision (perforated film on glass) / plain vinyl.
  void _film({required bool perforated}) {
    final th = _ft(
      SpecField.materialThickness,
      _mediaThicknessMm(perforated ? 0.2 : 0.1),
      minMm: 0.05,
    );
    final film = _box(
      _C.vinylLayer,
      Vec3(-w / 2, b, -th),
      Vec3(w / 2, t, 0),
      _vinylInk,
      labels: {BoxSide.front: brand},
    );
    if (perforated) {
      // Fine perforation as a see-through MASK on the film faces (holes
      // are cleared by the painter, no mesh holes). The pitch is an
      // illustrative display preset (~100 holes across the width, never
      // finer than the 2.5 mm of typical film), NOT a manufacturing
      // specification and never a BOM value.
      final pitch = math.max(w / 100, 2.5 / kMmPerFoot);
      for (final f in film.faces.where((f) => f.normal.z.abs() > 0.5)) {
        f.perforationPitchFt = pitch;
        f.perforationHole = 0.55;
      }
      _notes.add(
        'Perforation is shown as an illustrative pattern: film pitch and '
        'open-area ratio are not specified.',
      );
    }
    _add(film);
    if (ds) {
      _add(
        _skin(
          _C.backFace,
          -w / 2,
          b,
          w / 2,
          t,
          -th,
          _vinylInk,
          back: true,
          label: brand,
        ),
      );
    }
    env
      ..zBodyBack = -th
      ..zBack = -th;
    if (perforated) {
      _glassPane(-th);
      env.ownsGlass = true;
    }
  }

  /// Glass pane behind the board, front at [zFront].
  void _glassPane(double zFront) {
    const m = 0.3;
    const gt = 10 / kMmPerFoot;
    _add(
      _box(
        _C.glassBacking,
        Vec3(-w / 2 - m, math.max(0, b - m), zFront - gt),
        Vec3(w / 2 + m, t + m, zFront),
        _glass,
      ),
    );
    env.zBack = zFront - gt;
  }

  /// ACP tray (front sheet + side returns [+ rear sheet]) with flat
  /// artwork (2D) or raised placeholder letters (3D).
  void _acp({required bool letters}) {
    final d = _ft(SpecField.depth, _mediaDepthMm, minMm: 5);
    final th = math.min(
      _ft(SpecField.materialThickness, _mediaThicknessMm(4), minMm: 0.5),
      d / 3,
    );
    _add(
      _box(
        _C.displayPanel,
        Vec3(-w / 2, b, -th),
        Vec3(w / 2, t, 0),
        SceneColors.silver,
      ),
    );
    final rb = ds ? -d + th : -d;
    final rt = math.min(th, math.min(w, h) / 4);
    if (-th - rb > _eps) {
      for (final (mn, mx) in [
        (Vec3(-w / 2, t - rt, rb), Vec3(w / 2, t, -th)),
        (Vec3(-w / 2, b, rb), Vec3(w / 2, b + rt, -th)),
        (Vec3(-w / 2, b + rt, rb), Vec3(-w / 2 + rt, t - rt, -th)),
        (Vec3(w / 2 - rt, b + rt, rb), Vec3(w / 2, t - rt, -th)),
      ]) {
        _add(_box(_C.sideReturns, mn, mx, SceneColors.steel));
      }
    }
    if (ds) {
      _add(
        _box(
          _C.displayPanel,
          Vec3(-w / 2, b, -d),
          Vec3(w / 2, t, -d + th),
          SceneColors.silver,
        ),
      );
    }
    env
      ..zBodyBack = -d
      ..zBack = -d
      ..materialFt = th;

    final m = math.min(w, h) * 0.05;
    if (!letters) {
      _add(
        _skin(
          _C.frontFace,
          -w / 2 + m,
          b + m,
          w / 2 - m,
          t - m,
          0,
          SceneColors.red,
          label: brand,
        ),
      );
      if (ds) {
        _add(
          _skin(
            _C.backFace,
            -w / 2 + m,
            b + m,
            w / 2 - m,
            t - m,
            -d,
            SceneColors.red,
            back: true,
            label: brand,
          ),
        );
      }
      return;
    }

    // Placeholder raised letters: a generic logo block + sample letters
    // ("ABC…") – never a real client logo.
    final front = _ft(SpecField.letterDepthFront, 50, minMm: 1);
    final rear = _ft(SpecField.letterDepthRear, 50, minMm: 1);
    var lh = h * 0.55, pitch = lh * 0.8, gap = lh * 0.3;
    final avail = w * 0.9;
    final n = ((avail - lh - gap) / pitch).floor().clamp(1, 8);
    var rowW = lh + gap + n * pitch;
    if (rowW > avail) {
      final k = avail / rowW;
      lh *= k;
      pitch *= k;
      gap *= k;
      rowW = avail;
    }
    final x0 = -rowW / 2;
    final cy = b + h / 2;
    final slots = <(double, double, String?)>[
      (x0, x0 + lh, null),
      for (var i = 0; i < n; i++)
        (
          x0 + lh + gap + (i + 0.1) * pitch,
          x0 + lh + gap + (i + 0.9) * pitch,
          'ABCDEFGH'[i],
        ),
    ];
    for (final (a, c, ch) in slots) {
      final color = ch == null ? _logo : SceneColors.red;
      _add(
        _box(
          _C.raisedLettersFront,
          Vec3(a, cy - lh / 2, 0),
          Vec3(c, cy + lh / 2, front),
          color,
          labels: {BoxSide.front: ?ch},
          emissive: {BoxSide.front},
        ),
      );
      if (ds) {
        _add(
          _box(
            _C.raisedLettersBack,
            Vec3(-c, cy - lh / 2, -d - rear),
            Vec3(-a, cy + lh / 2, -d),
            color,
            labels: {BoxSide.back: ?ch},
            emissive: {BoxSide.back},
          ),
        );
      }
    }
    env
      ..zFront = front
      ..zBack = ds ? -d - rear : -d
      ..letterX = slots.last.$2
      ..letterTop = cy + lh / 2;
  }

  /// MDF backing with an inset GSB box (both faces when double-sided).
  void _mdfGsb() {
    final mdfT = _ft(SpecField.mdfThickness, 18, minMm: 1);
    var gw = _ft(SpecField.gsbPanelWidth, w * kMmPerFoot * 0.8, minMm: 10);
    var gh = _ft(SpecField.gsbPanelHeight, h * kMmPerFoot * 0.6, minMm: 10);
    final gd = _ft(SpecField.gsbDepth, 150, minMm: 5);
    if (gw > w) {
      _notes.add('GSB panel width limited to the board width.');
      gw = w;
    }
    if (gh > h) {
      _notes.add('GSB panel height limited to the board height.');
      gh = h;
    }
    var dTot = math.max(mdfT, gd);
    if (ds) {
      final d = _ft(SpecField.depth, _mediaDepthMm, minMm: 5);
      dTot = math.max(d, 2 * gd);
      if (2 * gd > d + 1e-9) {
        _notes.add(
          'Board depth shown as ${_fmt(dTot * kMmPerFoot)} to fit both GSB '
          'boxes.',
        );
      }
    }
    final cy = b + h / 2;
    final gy0 = cy - gh / 2, gy1 = cy + gh / 2;

    void mdfFrame(double z0, double z1) {
      for (final (mn, mx) in [
        (Vec3(-w / 2, gy1, z0), Vec3(w / 2, t, z1)),
        (Vec3(-w / 2, b, z0), Vec3(w / 2, gy0, z1)),
        (Vec3(-w / 2, gy0, z0), Vec3(-gw / 2, gy1, z1)),
        (Vec3(gw / 2, gy0, z0), Vec3(w / 2, gy1, z1)),
      ]) {
        if (mx.x - mn.x > 1e-6 && mx.y - mn.y > 1e-6) {
          _add(_box(_C.mdfBacking, mn, mx, _mdf));
        }
      }
    }

    mdfFrame(-mdfT, 0);
    _add(
      _box(
        _C.gsbBox,
        Vec3(-gw / 2, gy0, -gd),
        Vec3(gw / 2, gy1, 0),
        SceneColors.frame,
        sideColors: {BoxSide.front: SceneColors.red},
      ),
    );
    _add(
      _skin(
        _C.illuminatedSurface,
        -gw / 2,
        gy0,
        gw / 2,
        gy1,
        0,
        SceneColors.red,
        label: brand,
        emissive: true,
      ),
    );
    if (ds) {
      mdfFrame(-dTot, -dTot + mdfT);
      _add(
        _box(
          _C.gsbBox,
          Vec3(-gw / 2, gy0, -dTot),
          Vec3(gw / 2, gy1, -dTot + gd),
          SceneColors.frame,
          sideColors: {BoxSide.back: SceneColors.red},
        ),
      );
      _add(
        _skin(
          _C.backFace,
          -gw / 2,
          gy0,
          gw / 2,
          gy1,
          -dTot,
          SceneColors.red,
          back: true,
          label: brand,
          emissive: true,
        ),
      );
      final z0 = -dTot + mdfT, z1 = -mdfT;
      final rt = math.min(mdfT, math.min(w, h) / 4);
      if (z1 - z0 > _eps) {
        for (final (mn, mx) in [
          (Vec3(-w / 2, t - rt, z0), Vec3(w / 2, t, z1)),
          (Vec3(-w / 2, b, z0), Vec3(w / 2, b + rt, z1)),
          (Vec3(-w / 2, b + rt, z0), Vec3(-w / 2 + rt, t - rt, z1)),
          (Vec3(w / 2 - rt, b + rt, z0), Vec3(w / 2, t - rt, z1)),
        ]) {
          _add(_box(_C.sideReturns, mn, mx, _mdf));
        }
      }
    }
    env
      ..zBodyBack = -dTot
      ..zBack = -dTot;

    // GSB dimensions (inside the board face).
    final o = off * 0.35;
    _dim(
      'gsb_width',
      'GSB W',
      Vec3(-gw / 2, gy0, 0),
      Vec3(gw / 2, gy0, 0),
      Vec3(0, -o, 0),
      field: SpecField.gsbPanelWidth,
    );
    _dim(
      'gsb_height',
      'GSB H',
      Vec3(-gw / 2, gy0, 0),
      Vec3(-gw / 2, gy1, 0),
      Vec3(o, 0, 0),
      field: SpecField.gsbPanelHeight,
    );
    _dim(
      'gsb_depth',
      'GSB D',
      Vec3(gw / 2, gy1, 0),
      Vec3(gw / 2, gy1, -gd),
      Vec3(0, o, 0),
      field: SpecField.gsbDepth,
      small: true,
    );
    _dim(
      'mdf_thickness',
      'MDF',
      Vec3(-w / 2, t, 0),
      Vec3(-w / 2, t, -mdfT),
      Vec3(0, o, 0),
      field: SpecField.mdfThickness,
      small: true,
    );
  }

  /// Sandwich board: two panels hinged at the top on an A-frame.
  void _sandwich() {
    final th = _ft(
      SpecField.materialThickness,
      _mediaThicknessMm(6),
      minMm: 0.5,
    );
    final rail = math.max(_ft(SpecField.frameThickness, 25, minMm: 5), 0.04);
    var deg = spec.values[SpecField.openingAngle] ?? 22;
    if (!deg.isFinite) deg = 22;
    final alpha = deg.clamp(2.0, 89.0) / 2 * math.pi / 180;
    final sa = math.sin(alpha), ca = math.cos(alpha), ta = math.tan(alpha);
    const pad = 0.04;
    final need = b + h * ca + rail;
    var ho = _ft(SpecField.overallHeight, (b + h) * kMmPerFoot, minMm: 10);
    if (ho < need - 1e-9) {
      if (spec.has(SpecField.overallHeight)) {
        _notes.add(
          'Overall height shown as ${_fmt(need * kMmPerFoot)} so the panels '
          'fit below the hinge.',
        );
      }
      ho = need;
    }

    // Front panel (faces +Z, tilted back by alpha).
    const ux = Vec3(1, 0, 0);
    final v = Vec3(0, ca, -sa);
    final n = Vec3(0, sa, ca);
    final o = Vec3(-w / 2, b, (ho - b) * ta);
    _add(_obox(_C.displayPanel, o, ux, v, n, w, h, th, SceneColors.white));
    // Rear panel (faces −Z): u = −X so its artwork reads from behind.
    const ux2 = Vec3(-1, 0, 0);
    final v2 = Vec3(0, ca, sa);
    final n2 = Vec3(0, sa, -ca);
    final o2 = Vec3(w / 2, b, -(ho - b) * ta);
    _add(_obox(_C.displayPanel, o2, ux2, v2, n2, w, h, th, SceneColors.white));

    Solid skin(String id, Vec3 o, Vec3 u, Vec3 v, Vec3 n) {
      final m = math.min(w, h) * 0.04;
      final e = th + 0.01;
      Vec3 p(double a, double c) => o + u * a + v * c + n * e;
      return Solid(
        name: _n(id),
        faces: [
          Face(
            [p(m, h - m), p(w - m, h - m), p(w - m, m), p(m, m)],
            SceneColors.red,
            n,
            label: brand,
          ),
        ],
      );
    }

    _add(skin(_C.frontFace, o, ux, v, n));
    _add(skin(_C.backFace, o2, ux2, v2, n2));

    // A-frame legs, hinge bar, spreaders and feet.
    final xl = w / 2 + rail / 2 + 0.01;
    final zf = (ho - pad) * ta;
    for (final x in [-xl, xl]) {
      _beam(
        _C.frame,
        Vec3(x, pad, zf),
        Vec3(x, ho, 0),
        rail,
        SceneColors.frame,
      );
      _beam(
        _C.frame,
        Vec3(x, pad, -zf),
        Vec3(x, ho, 0),
        rail,
        SceneColors.frame,
      );
      if (b > 0.3) {
        final ys = b * 0.5;
        final zs = (ho - ys) * ta;
        _beam(
          _C.frame,
          Vec3(x, ys, zs),
          Vec3(x, ys, -zs),
          rail * 0.6,
          SceneColors.steel,
        );
      }
      for (final z in [zf, -zf]) {
        _add(
          _box(
            _C.standBase,
            Vec3(x - 0.1, 0, z - 0.1),
            Vec3(x + 0.1, pad, z + 0.1),
            _rubber,
          ),
        );
      }
    }
    _beam(
      _C.frame,
      Vec3(-xl - rail / 2, ho, 0),
      Vec3(xl + rail / 2, ho, 0),
      rail,
      SceneColors.frame,
    );
    _focus = Vec3(0, ho / 2, 0);

    // Dimensions.
    final topL = o + v * h + n * th;
    _dim(
      'width',
      'W',
      topL,
      topL + ux * w,
      Vec3(0, off * 0.6, 0),
      field: SpecField.width,
    );
    final botR = o + ux * w + n * th;
    _dim(
      'height',
      'H',
      botR,
      botR + v * h,
      Vec3(off, 0, 0),
      field: SpecField.height,
    );
    if (b > 0.01) {
      _dim(
        'mounting_height',
        'Clr',
        Vec3(-w / 2, 0, o.z),
        Vec3(-w / 2, b, o.z),
        Vec3(-off * 0.6, 0, 0),
        field: SpecField.mountingHeight,
      );
    }
    _dim(
      'overall_height',
      'Overall',
      Vec3(-xl - off * 0.3, 0, 0),
      Vec3(-xl - off * 0.3, ho, 0),
      Vec3(-off, 0, 0),
      field: SpecField.overallHeight,
    );
    _dim(
      'spread',
      'Spread',
      Vec3(xl, 0, zf),
      Vec3(xl, 0, -zf),
      Vec3(off * 0.6, 0, 0),
    );
  }

  // ---------------------------------------------------------------------------
  // Board dimensions (local frame, before any flange rotation)
  // ---------------------------------------------------------------------------

  void _boardDims() {
    _dim(
      'width',
      'W',
      Vec3(-w / 2, t, 0),
      Vec3(w / 2, t, 0),
      Vec3(0, off, 0),
      field: SpecField.width,
    );
    _dim(
      'height',
      'H',
      Vec3(w / 2, b, 0),
      Vec3(w / 2, t, 0),
      Vec3(off, 0, 0),
      field: SpecField.height,
    );
    final hasDepth = switch (template) {
      'gsb' || 'nonlit' || 'acp2d' || 'acp3d' => true,
      'mdfgsb' => ds,
      _ => false,
    };
    if (hasDepth) {
      _dim(
        'depth',
        'D',
        Vec3(-w / 2, b, 0),
        Vec3(-w / 2, b, env.zBodyBack),
        Vec3(0, -off * 0.5, 0),
        field: SpecField.depth,
        small: true,
      );
    }
    if (env.materialFt > 0) {
      _dim(
        'material_thickness',
        'Mat',
        Vec3(w / 2, b, 0),
        Vec3(w / 2, b, -env.materialFt),
        Vec3(0, -off * 0.5, 0),
        field: SpecField.materialThickness,
        small: true,
      );
    }
    if (template == 'acp3d') {
      final x = env.letterX, y = env.letterTop;
      _dim(
        'letter_depth_front',
        'Proj',
        Vec3(x, y, 0),
        Vec3(x, y, env.zFront),
        Vec3(0, off * 0.4, 0),
        field: SpecField.letterDepthFront,
        small: true,
      );
      if (ds) {
        _dim(
          'letter_depth_rear',
          'Proj',
          Vec3(-x, y, env.zBodyBack),
          Vec3(-x, y, env.zBack),
          Vec3(0, off * 0.4, 0),
          field: SpecField.letterDepthRear,
          small: true,
        );
      }
    }
    if (b > 0.01) {
      final rooftop = inst == SignageCatalog.rooftop && unsupported.isEmpty;
      _dim(
        'mounting_height',
        'Clr',
        Vec3(-w / 2, 0, 0),
        Vec3(-w / 2, b, 0),
        Vec3(-off * (rooftop ? 2.2 : 1), 0, 0),
        field: SpecField.mountingHeight,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Installations
  // ---------------------------------------------------------------------------

  void _installation() {
    switch (inst) {
      case SignageCatalog.shopFascia:
        _wallInstall(gapMm: 25, fascia: true);
      case SignageCatalog.wallMount:
        _wallInstall(gapMm: 50);
      case SignageCatalog.directWall:
        _wallInstall(gapMm: 0);
      case SignageCatalog.glassPasting:
        if (!env.ownsGlass) _glassPane(env.zBack);
      case SignageCatalog.supportPipe:
        _supportPipes();
      case SignageCatalog.singlePole:
        _poles(twin: false);
      case SignageCatalog.doublePole:
        _poles(twin: true);
      case SignageCatalog.rooftop:
        _rooftop();
      case SignageCatalog.freeStanding:
        _standBase();
      case SignageCatalog.flangeBracket:
        _flange();
    }
  }

  void _wallInstall({required double gapMm, bool fascia = false}) {
    final bodyBack = env.zBack;
    double zWall;
    double gap;
    if (env.ownsStandoffs) {
      gap = env.zBodyBack - env.zBack;
      zWall = env.zBack;
    } else {
      gap = gapMm / kMmPerFoot;
      zWall = bodyBack - gap;
      if (gap > 0) {
        final s = math.min(0.16, math.min(w, h) / 4);
        final inset = math.min(0.3, h * 0.2);
        final rows = h < 0.6 ? [b + h / 2] : [b + inset, t - inset];
        for (final y in rows) {
          for (final x in _spread(math.max(2, (w / 4).ceil() + 1), 0.3)) {
            _add(
              _box(
                _C.wallBrackets,
                Vec3(x - s / 2, y - s / 2, zWall),
                Vec3(x + s / 2, y + s / 2, bodyBack),
                SceneColors.steel,
              ),
            );
          }
        }
      }
    }
    if (gap > 1e-6) {
      _dim(
        'standoff',
        'Offset',
        Vec3(w / 2, b, zWall + gap),
        Vec3(w / 2, b, zWall),
        Vec3(0, -off * 0.5, 0),
        field: env.ownsStandoffs ? SpecField.standoff : null,
        small: true,
      );
    }
    if (!context) return;
    if (fascia) {
      final half = w / 2 + 2;
      final wall = _box(
        _C.wall,
        Vec3(-half, 0, zWall - 1),
        Vec3(half, t + 2, zWall),
        SceneColors.building,
      );
      // Rolling shutters below the board.
      final top = math.max(0.5, b - 0.5);
      for (final (a, c) in [(-half + 0.5, -0.5), (0.5, half - 0.5)]) {
        if (c - a < 0.5) continue;
        wall.decals.add(
          Shapes.frontQuad(a, 0, c, top, zWall, SceneColors.shutter),
        );
        final slats = math.min(14, (top / 0.6).floor());
        for (var i = 1; i <= slats; i++) {
          final y = top * i / (slats + 1);
          wall.decals.add(
            Shapes.frontQuad(
              a,
              y - 0.03,
              c,
              y + 0.03,
              zWall,
              SceneColors.slat,
              layer: 2,
              outline: false,
            ),
          );
        }
      }
      wall.decalNormal = const Vec3(0, 0, 1);
      _add(wall);
    } else {
      _add(
        _box(
          _C.wall,
          Vec3(-(w / 2 + 3), 0, zWall - 0.75),
          Vec3(w / 2 + 3, math.max(t + 2, 10), zWall),
          SceneColors.wall,
        ),
      );
    }
  }

  void _supportPipes() {
    final n = _count(SpecField.pipeCount, 2);
    final len = _ft(SpecField.pipeLength, 2 * kMmPerFoot, minMm: 10);
    final sp = _ft(SpecField.pipeSpacing, w * kMmPerFoot * 0.6);
    final margin = math.min(0.25, w * 0.1);
    final maxSp = n > 1 ? math.max(0.0, (w - 2 * margin) / (n - 1)) : 0.0;
    final spEff = n > 1 ? math.min(sp, maxSp) : 0.0;
    if (n > 1 && sp > maxSp + 1e-9) {
      _notes.add(
        'Pipe spacing shown as ${_fmt(spEff * kMmPerFoot)} to keep the pipes '
        'within the board width.',
      );
    }
    final yc = b + h / 2;
    final zb = env.zBack, zw = env.zBack - len;
    final pr = math.min(0.15, h * 0.3);
    final xs = [for (var i = 0; i < n; i++) -spEff * (n - 1) / 2 + i * spEff];
    for (final x in xs) {
      _beam(
        _C.supportPipes,
        Vec3(x, yc, zb),
        Vec3(x, yc, zw),
        pr,
        SceneColors.steel,
      );
      _add(
        _box(
          _C.supportPipes,
          Vec3(x - pr * 1.4, yc - pr * 1.4, zw),
          Vec3(x + pr * 1.4, yc + pr * 1.4, zw + 0.03),
          SceneColors.frame,
        ),
      );
    }
    _dim(
      'pipe_length',
      'Pipe',
      Vec3(xs.last, yc, zb),
      Vec3(xs.last, yc, zw),
      Vec3(0, off * 0.6, 0),
      field: SpecField.pipeLength,
    );
    if (n > 1) {
      final zm = (zb + zw) / 2;
      _dim(
        'pipe_spacing',
        'Pipe c/c',
        Vec3(xs[0], yc, zm),
        Vec3(xs[1], yc, zm),
        Vec3(0, -off * 0.6, 0),
        field: SpecField.pipeSpacing,
      );
    }
    if (context) {
      _add(
        _box(
          _C.wall,
          Vec3(-(w / 2 + 3), 0, zw - 0.75),
          Vec3(w / 2 + 3, math.max(t + 2, 10), zw),
          SceneColors.wall,
        ),
      );
    }
  }

  void _poles({required bool twin}) {
    final count = twin ? math.max(2, _count(SpecField.poleCount, 2)) : 1;
    final r = math.min(twin ? 0.2 : 0.25, w / 4);
    final emb = _ft(SpecField.poleEmbedment, 3 * kMmPerFoot, minMm: 0);
    var top = _ft(SpecField.poleHeight, t * kMmPerFoot, minMm: 10);
    final zp = ds ? zMid : env.zBack - 0.12 - r;

    var xs = const [0.0];
    if (twin) {
      final sp = _ft(SpecField.poleSpacing, w * kMmPerFoot * 0.7);
      final maxSp = w / (count - 1);
      final minSp = math.min(2 * r + 0.05, maxSp);
      final spEff = sp.clamp(minSp, maxSp).toDouble();
      if ((spEff - sp).abs() > 1e-9) {
        _notes.add(
          'Pole spacing shown as ${_fmt(spEff * kMmPerFoot)} (limited to the '
          'board width).',
        );
      }
      xs = [
        for (var i = 0; i < count; i++) -spEff * (count - 1) / 2 + i * spEff,
      ];
    }

    double shaft;
    if (ds) {
      // Double-sided: poles stand in the board's mid-plane below it.
      if (top < b - 1e-9) {
        _notes.add('Pole height is below the board bottom.');
      }
      shaft = b;
    } else {
      final minTop = b + math.min(h * 0.5, 1.0);
      if (top < minTop) {
        _notes.add(
          'Pole height shown as ${_fmt(minTop * kMmPerFoot)} so the pole '
          'reaches the board.',
        );
        top = minTop;
      }
      shaft = top;
    }

    for (final x in xs) {
      if (shaft > 1e-3) {
        _add(
          Shapes.cylinder(
            Vec3(x, 0, zp),
            r,
            shaft,
            SceneColors.steel,
            name: _n(_C.poles),
          ),
        );
      }
      if (emb > 1e-6) {
        _add(
          Shapes.cylinder(
            Vec3(x, -emb, zp),
            r,
            emb,
            _embedded,
            name: _n(_C.poles),
          ),
        );
      }
    }
    if (!ds) {
      final xa = twin ? xs.first - r : -w * 0.35;
      final xb = twin ? xs.last + r : w * 0.35;
      for (final y in [b + h * 0.2, b + h * 0.8]) {
        if (y > top - 0.05) continue;
        _beam(
          _C.poles,
          Vec3(xa, y, env.zBack - 0.06),
          Vec3(xb, y, env.zBack - 0.06),
          0.12,
          SceneColors.steel,
        );
      }
    }

    final xr = xs.last + r;
    _dim(
      'pole_height',
      'Pole',
      Vec3(xr, 0, zp),
      Vec3(xr, top, zp),
      Vec3(off * 1.6, 0, 0),
      field: SpecField.poleHeight,
    );
    if (emb > 1e-6) {
      _dim(
        'pole_embedment',
        'Emb',
        Vec3(xr, -emb, zp),
        Vec3(xr, 0, zp),
        Vec3(off * 1.6, 0, 0),
        field: SpecField.poleEmbedment,
      );
    }
    if (twin) {
      final ys = math.max(b * 0.5, 0.2);
      _dim(
        'pole_spacing',
        'Poles c/c',
        Vec3(xs[0], ys, zp),
        Vec3(xs[1], ys, zp),
        Vec3(0, 0, off * 0.5),
        field: SpecField.poleSpacing,
      );
    }
  }

  void _rooftop() {
    final fh = _ft(SpecField.rooftopFrameHeight, 4 * kMmPerFoot, minMm: 0);
    var roof = b - fh;
    if (roof < 0) {
      _notes.add(
        'Mounting height is lower than the rooftop frame height: roof shown '
        'at ground level.',
      );
      roof = 0;
    }
    final legs = math.max(2, (w / 8).ceil() + 1);
    final legT = math.min(0.25, w / (2 * legs));
    final zf = ds ? zMid : env.zBack - legT / 2 - 0.02;
    final legTop = ds ? b : t;
    final stay = math.max(1.5, h * 0.6);
    for (final x in _spread(legs, 0.3)) {
      if (legTop - roof > 1e-3) {
        _beam(
          _C.rooftopFrame,
          Vec3(x, roof, zf),
          Vec3(x, legTop, zf),
          legT,
          SceneColors.steel,
        );
      }
      if (ds) {
        for (final s in [-1.0, 1.0]) {
          _beam(
            _C.rooftopFrame,
            Vec3(x, b, zf),
            Vec3(x, roof + legT * 0.35, zf + s * stay),
            legT * 0.7,
            SceneColors.steel,
          );
        }
      } else {
        _beam(
          _C.rooftopFrame,
          Vec3(x, t - h * 0.2, zf),
          Vec3(x, roof + legT * 0.35, zf - stay),
          legT * 0.7,
          SceneColors.steel,
        );
      }
    }
    if (!ds && w > 0.5) {
      _beam(
        _C.rooftopFrame,
        Vec3(-w / 2 + 0.2, b, zf),
        Vec3(w / 2 - 0.2, b, zf),
        legT * 0.8,
        SceneColors.steel,
      );
    }
    if (fh > 1e-6) {
      _dim(
        'rooftop_frame_height',
        'Frame',
        Vec3(-w / 2, roof, 0),
        Vec3(-w / 2, b, 0),
        Vec3(-off, 0, 0),
        field: SpecField.rooftopFrameHeight,
      );
    }
    if (context && roof > 0.05) {
      final depth = math.max(10.0, stay + 3);
      _add(
        _box(
          _C.wall,
          Vec3(-(w / 2 + 3), 0, zf - depth),
          Vec3(w / 2 + 3, roof, math.max(env.zFront, 0) + 3),
          SceneColors.building,
        ),
      );
    }
  }

  void _standBase() {
    final bw = _ft(
      SpecField.baseWidth,
      math.max(1.5 * kMmPerFoot, w * kMmPerFoot * 0.7),
      minMm: 10,
    );
    final bd = _ft(SpecField.baseDepth, 1.5 * kMmPerFoot, minMm: 10);
    final overall = _ft(SpecField.overallHeight, t * kMmPerFoot, minMm: 10);
    const baseH = 0.2;
    final zc = zMid;
    _add(
      _box(
        _C.standBase,
        Vec3(-bw / 2, 0, zc - bd / 2),
        Vec3(bw / 2, baseH, zc + bd / 2),
        SceneColors.frame,
      ),
    );
    final postX = w / 2 + 0.08;
    final postTop = math.max(t, overall);
    for (final x in [-postX, postX]) {
      _beam(
        _C.poles,
        Vec3(x, baseH, zc),
        Vec3(x, postTop, zc),
        0.16,
        SceneColors.steel,
      );
      if (bw < w) {
        _add(
          _box(
            _C.standBase,
            Vec3(x - 0.3, 0, zc - bd / 2),
            Vec3(x + 0.3, baseH, zc + bd / 2),
            SceneColors.frame,
          ),
        );
      }
    }
    _dim(
      'base_width',
      'Base W',
      Vec3(-bw / 2, 0, zc + bd / 2),
      Vec3(bw / 2, 0, zc + bd / 2),
      Vec3(0, 0, off * 0.6),
      field: SpecField.baseWidth,
    );
    _dim(
      'base_depth',
      'Base D',
      Vec3(bw / 2, 0, zc - bd / 2),
      Vec3(bw / 2, 0, zc + bd / 2),
      Vec3(off * 0.6, 0, 0),
      field: SpecField.baseDepth,
    );
    _dim(
      'overall_height',
      'Overall',
      Vec3(postX, 0, zc),
      Vec3(postX, postTop, zc),
      Vec3(off * 1.6, 0, 0),
      field: SpecField.overallHeight,
    );
  }

  /// Legacy flange: the board is turned to project perpendicular from the
  /// wall (front face → −X) on top / bottom brackets.
  void _flange() {
    const p = 1.0; // projection from the wall (no spec field yet)
    final zc = (env.zFront + env.zBodyBack) / 2;
    Vec3 mp(Vec3 q) => Vec3(-(q.z - zc), q.y, q.x + w / 2 + p);
    Vec3 mn(Vec3 n) => Vec3(-n.z, n.y, n.x);
    Face mf(Face f) => Face(
      f.points.map(mp).toList(),
      f.color,
      mn(f.normal),
      outline: f.outline,
      emissive: f.emissive,
      label: f.label,
      labelColor: f.labelColor,
      layer: f.layer,
    );
    for (var i = 0; i < _solids.length; i++) {
      final s = _solids[i];
      final copy = Solid(name: s.name, faces: s.faces.map(mf).toList());
      copy.decals.addAll(s.decals.map(mf));
      if (s.decalNormal != null) copy.decalNormal = mn(s.decalNormal!);
      _solids[i] = copy;
    }
    for (var i = 0; i < _dims.length; i++) {
      final d = _dims[i];
      _dims[i] = ModelDimension(
        id: d.id,
        label: d.label,
        a: mp(d.a),
        b: mp(d.b),
        offset: mn(d.offset),
        field: d.field,
        valueMm: d.valueMm,
      );
    }
    _beam(
      _C.wallBrackets,
      Vec3(0, t + 0.15, 0),
      Vec3(0, t + 0.15, p + w),
      0.15,
      SceneColors.steel,
    );
    _beam(
      _C.wallBrackets,
      Vec3(0, t + 1.5, 0),
      Vec3(0, t + 0.15, p + w * 0.7),
      0.12,
      SceneColors.steel,
    );
    _beam(
      _C.wallBrackets,
      Vec3(0, b - 0.15, 0),
      Vec3(0, b - 0.15, p + 0.6),
      0.12,
      SceneColors.steel,
    );
    if (context) {
      final half = 6 + w * 0.3;
      _add(
        _box(
          _C.wall,
          Vec3(-half, 0, -0.75),
          Vec3(half, math.max(t + 3, 10), 0),
          SceneColors.wall,
        ),
      );
    }
    _focus = Vec3(0, b + h / 2, p + w / 2);
  }

  /// Translucent ground plane (single face at y = 0) under the model.
  void _ground() {
    var x0 = double.infinity, z0 = double.infinity;
    var x1 = -double.infinity, z1 = -double.infinity;
    for (final s in _solids) {
      for (final f in s.faces) {
        for (final q in f.points) {
          x0 = math.min(x0, q.x);
          x1 = math.max(x1, q.x);
          z0 = math.min(z0, q.z);
          z1 = math.max(z1, q.z);
        }
      }
    }
    if (!x0.isFinite) return;
    x0 -= 2;
    z0 -= 2;
    x1 += 2;
    z1 += 2;
    _add(
      Solid(
        name: _n(_C.ground),
        faces: [
          Face(
            [
              Vec3(x0, 0, z0),
              Vec3(x1, 0, z0),
              Vec3(x1, 0, z1),
              Vec3(x0, 0, z1),
            ],
            _groundTint,
            Vec3.up,
            outline: false,
          ),
        ],
      ),
    );
  }
}
