import '../preview3d/scene3d.dart';
import 'signage_spec.dart';

/// Millimetres in one foot (scene units are feet, specs are millimetres).
const double kMmPerFoot = 304.8;

/// Ids of the selectable parts of a parametric signage model. Every [Solid]
/// of a [ParametricModel] is named with one of these ids, optionally
/// followed by `:<n>` when the component has several solids.
class ModelComponentIds {
  ModelComponentIds._();

  static const displayPanel = 'display_panel';
  static const frontFace = 'front_face';
  static const backFace = 'back_face';
  static const frame = 'frame';
  static const sideReturns = 'side_returns';
  static const rearSupports = 'rear_supports';
  static const wallBrackets = 'wall_brackets';
  static const standoffs = 'standoffs';
  static const poles = 'poles';
  static const supportPipes = 'support_pipes';
  static const standBase = 'stand_base';
  static const rooftopFrame = 'rooftop_frame';
  static const illuminatedSurface = 'illuminated_surface';
  static const raisedLettersFront = 'raised_letters_front';
  static const raisedLettersBack = 'raised_letters_back';
  static const glassBacking = 'glass_backing';
  static const vinylLayer = 'vinyl_layer';
  static const mdfBacking = 'mdf_backing';
  static const gsbBox = 'gsb_box';

  /// Surroundings (only built when `context` is requested).
  static const wall = 'wall';
  static const ground = 'ground';

  static const contextIds = {wall, ground};

  /// Component id of a solid name (`'poles:2'` → `'poles'`).
  static String of(String solidName) {
    final i = solidName.indexOf(':');
    return i < 0 ? solidName : solidName.substring(0, i);
  }
}

/// One selectable / hideable part of a parametric model.
class ModelComponent {
  const ModelComponent({
    required this.id,
    required this.label,
    this.editable = const [],
    this.visible = true,
  });

  final String id;
  final String label;

  /// Spec fields that change this component (only fields the spec has).
  final List<SpecField> editable;

  /// False when the component was hidden for this build.
  final bool visible;

  /// Surroundings (wall / ground), not part of the signage itself.
  bool get isContext => ModelComponentIds.contextIds.contains(id);

  @override
  String toString() => 'ModelComponent($id, visible: $visible)';
}

/// A labelled dimension line of the model (scene feet).
class ModelDimension {
  const ModelDimension({
    required this.id,
    required this.label,
    required this.a,
    required this.b,
    required this.offset,
    this.field,
    this.valueMm = 0,
  });

  /// e.g. 'width', 'pole_spacing' (see [ParametricModelBuilder]).
  final String id;

  /// Display text in the spec's display unit, e.g. "W 8 ft".
  final String label;
  final Vec3 a;
  final Vec3 b;
  final Vec3 offset;

  /// The editable spec field behind this dimension (null = derived).
  final SpecField? field;

  /// Modelled length in millimetres.
  final double valueMm;

  Dim3 toDim3() => Dim3(a, b, offset, label);

  @override
  String toString() => 'ModelDimension($id, $label)';
}

/// Result of [ParametricModelBuilder.build]: a renderable [Scene] plus the
/// component / dimension metadata a model viewer needs.
///
/// The model is an illustrative parametric approximation of the signage –
/// not a fabrication drawing.
class ParametricModel {
  ParametricModel({
    required this.scene,
    required this.components,
    required this.dimensions,
    required this.templateId,
    this.unsupported = const [],
    this.notes = const [],
  });

  final Scene scene;
  final List<ModelComponent> components;
  final List<ModelDimension> dimensions;

  /// Parametric template used ('gsb', 'nonlit', 'foam', …).
  final String templateId;

  /// Why the media + installation combination is not supported (empty when
  /// it is). Unsupported models show the board without a support structure.
  final List<String> unsupported;

  /// Adjustments made while modelling (clamped values etc.).
  final List<String> notes;

  bool get isSupported => unsupported.isEmpty;

  ModelComponent? component(String id) {
    for (final c in components) {
      if (c.id == id) return c;
    }
    return null;
  }

  ModelDimension? dimension(String id) {
    for (final d in dimensions) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Solids that belong to component [id].
  List<Solid> solidsOf(String id) => [
    for (final s in scene.solids)
      if (ModelComponentIds.of(s.name) == id) s,
  ];

  /// Axis-aligned bounds of the (visible) solids of component [id].
  ({Vec3 min, Vec3 max})? boundsOf(String id) {
    final solids = solidsOf(id);
    if (solids.isEmpty) return null;
    var x0 = double.infinity, y0 = double.infinity, z0 = double.infinity;
    var x1 = -double.infinity, y1 = -double.infinity, z1 = -double.infinity;
    for (final s in solids) {
      for (final f in s.faces) {
        for (final p in f.points) {
          if (p.x < x0) x0 = p.x;
          if (p.y < y0) y0 = p.y;
          if (p.z < z0) z0 = p.z;
          if (p.x > x1) x1 = p.x;
          if (p.y > y1) y1 = p.y;
          if (p.z > z1) z1 = p.z;
        }
      }
    }
    return (min: Vec3(x0, y0, z0), max: Vec3(x1, y1, z1));
  }
}
