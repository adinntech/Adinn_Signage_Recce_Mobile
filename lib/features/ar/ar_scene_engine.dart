import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'ar_model_builder.dart';
import 'ar_session_controller.dart';

/// Preview transform of one AR scene object, relative to its anchor.
///
/// Axes are the *anchor* frame (never the camera frame):
/// * wall anchor: x = along the wall, y = up, z = out of the wall;
/// * floor / ground anchor: x = left / right, y = up, z = toward the camera
///   at placement time.
///
/// [scale] is a visual multiplier only – 1.0 is the entered physical size.
@immutable
class ArObjectTransform {
  const ArObjectTransform({
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.yaw = 0,
    this.roll = 0,
    this.scale = 1,
  });

  /// Preview scale range: 10 % – 300 %.
  static const minScale = 0.1;
  static const maxScale = 3.0;

  final double x;
  final double y;
  final double z;

  /// Turn around the vertical axis (radians) – floor / ground objects.
  final double yaw;

  /// Turn around the wall normal (radians) – wall objects (stays flat on
  /// the wall).
  final double roll;
  final double scale;

  /// Preview is not at the entered physical size.
  bool get scaleAdjusted => (scale - 1).abs() > 0.0005;

  int get scalePercent => (scale * 100).round();

  static double clampScale(double s) =>
      (s.isFinite ? s : 1.0).clamp(minScale, maxScale).toDouble();

  /// Wraps an angle into (-π, π].
  static double wrapAngle(double a) {
    if (!a.isFinite) return 0;
    var v = a % (2 * math.pi);
    if (v > math.pi) v -= 2 * math.pi;
    if (v <= -math.pi) v += 2 * math.pi;
    return v;
  }

  ArObjectTransform copyWith({
    double? x,
    double? y,
    double? z,
    double? yaw,
    double? roll,
    double? scale,
  }) => ArObjectTransform(
    x: x ?? this.x,
    y: y ?? this.y,
    z: z ?? this.z,
    yaw: wrapAngle(yaw ?? this.yaw),
    roll: wrapAngle(roll ?? this.roll),
    scale: clampScale(scale ?? this.scale),
  );

  bool get hasOffset => x != 0 || y != 0 || z != 0;
  bool get hasRotation => yaw != 0 || roll != 0;

  Map<String, double> toMap() => {
    'x': x,
    'y': y,
    'z': z,
    'yaw': yaw,
    'roll': roll,
    'scale': scale,
  };

  static ArObjectTransform fromMap(Map<String, double> m) => ArObjectTransform(
    x: m['x'] ?? 0,
    y: m['y'] ?? 0,
    z: m['z'] ?? 0,
    yaw: wrapAngle(m['yaw'] ?? 0),
    roll: wrapAngle(m['roll'] ?? 0),
    scale: clampScale(m['scale'] ?? 1),
  );

  /// Single-model engine transform (no roll axis there).
  ArModelTransform toLegacy() => ArModelTransform(
    x: x,
    y: y,
    z: z,
    yaw: yaw + roll,
    scale: scale.clamp(ArModelTransform.minScale, ArModelTransform.maxScale),
  );

  @override
  bool operator ==(Object other) =>
      other is ArObjectTransform &&
      other.x == x &&
      other.y == y &&
      other.z == z &&
      other.yaw == yaw &&
      other.roll == roll &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(x, y, z, yaw, roll, scale);

  @override
  String toString() =>
      'ArObjectTransform(x: $x, y: $y, z: $z, yaw: $yaw, roll: $roll, '
      'scale: $scale)';
}

/// Result of anchoring a scene object.
@immutable
class ArObjectPlaceResult {
  const ArObjectPlaceResult({
    required this.placed,
    this.surface,
    this.reason,
    this.pose,
  });

  final bool placed;

  /// "vertical", "horizontal" or "manual".
  final String? surface;

  /// Why placement failed: no_surface, not_tracking, no_model,
  /// anchor_failed, single_object, unsupported, timeout …
  final String? reason;

  /// World pose of the new anchor in this session (tx, ty, tz, qx, qy, qz,
  /// qw). Used for undo / redo / duplicate inside the same session only.
  final List<double>? pose;
}

/// Multi-object AR scene API on top of an [ArPlatform]. The ARCore engine
/// ([NativeArPlatform]) implements it natively; [LegacyArSceneEngine]
/// adapts engines that only know one model.
abstract class ArSceneEngine {
  /// False for single-model engines.
  bool get supportsMultipleObjects;

  /// Uploads a model under [key] (one per Signage Item). Placements and
  /// preview duplicates of the same item share the GPU geometry. Calling it
  /// again with the same key replaces the geometry of every placement.
  Future<bool> registerModel(String key, ArModelData model);

  /// Hit-tests detected surfaces at a normalised screen point and anchors
  /// object [id] (creating it, or re-anchoring = moving it).
  Future<ArObjectPlaceResult> placeObject(
    String id,
    String modelKey,
    Offset normalizedScreenPoint, {
    bool manual = false,
  });

  /// Anchors object [id] at a world pose from this session (undo / redo /
  /// duplicate).
  Future<ArObjectPlaceResult> anchorObject(
    String id,
    String modelKey,
    List<double> pose,
    String surface,
  );

  Future<void> setObjectTransform(String id, ArObjectTransform transform);
  Future<void> setObjectVisible(String id, bool visible);

  /// Highlights one object (null = none). The highlight is never captured.
  Future<void> selectObject(String? id);
  Future<void> removeObject(String id);

  /// Placement id of the visible object under a normalised screen point.
  Future<String?> hitTestObject(Offset normalizedScreenPoint);

  /// Shows / hides the surface placement indicator (reticle).
  Future<void> setPlacementIndicator(
    bool active, {
    bool preferVertical = false,
  });
}

/// Scene API for engines that only support one anchored model (e.g. test
/// fakes of the original Camera AR engine). The model the session was
/// started with is the only one it can show.
class LegacyArSceneEngine implements ArSceneEngine {
  LegacyArSceneEngine(this.platform, {this.sessionModelKey});

  final ArPlatform platform;

  /// Model key of the session's model (the only one this engine can draw).
  final String? sessionModelKey;
  String? _objectId;

  String? get objectId => _objectId;

  @override
  bool get supportsMultipleObjects => false;

  @override
  Future<bool> registerModel(String key, ArModelData model) async =>
      sessionModelKey == null || key == sessionModelKey;

  @override
  Future<ArObjectPlaceResult> placeObject(
    String id,
    String modelKey,
    Offset normalizedScreenPoint, {
    bool manual = false,
  }) async {
    if ((_objectId != null && _objectId != id) ||
        (sessionModelKey != null && modelKey != sessionModelKey)) {
      return const ArObjectPlaceResult(placed: false, reason: 'single_object');
    }
    final r = await platform.placeModel(normalizedScreenPoint, manual: manual);
    if (r.placed) _objectId = id;
    return ArObjectPlaceResult(
      placed: r.placed,
      surface: r.surface,
      reason: r.reason,
    );
  }

  @override
  Future<ArObjectPlaceResult> anchorObject(
    String id,
    String modelKey,
    List<double> pose,
    String surface,
  ) async => const ArObjectPlaceResult(placed: false, reason: 'unsupported');

  @override
  Future<void> setObjectTransform(String id, ArObjectTransform t) async {
    if (id == _objectId) await platform.updateTransform(t.toLegacy());
  }

  @override
  Future<void> setObjectVisible(String id, bool visible) async {}

  @override
  Future<void> selectObject(String? id) async {}

  @override
  Future<void> removeObject(String id) async {
    if (id != _objectId) return;
    _objectId = null;
    await platform.removePlacement();
  }

  @override
  Future<String?> hitTestObject(Offset normalizedScreenPoint) async => null;

  @override
  Future<void> setPlacementIndicator(
    bool active, {
    bool preferVertical = false,
  }) async {}
}

/// Scene API for [platform]: native multi-object support when available.
ArSceneEngine sceneEngineFor(ArPlatform platform, {String? sessionModelKey}) {
  final p = platform;
  if (p is ArSceneEngine) return p as ArSceneEngine;
  return LegacyArSceneEngine(p, sessionModelKey: sessionModelKey);
}
