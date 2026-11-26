import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'ar_model_builder.dart';

/// Whether the device can run a world-tracking AR session.
enum ArSupport {
  unknown,
  supported,
  unsupported,

  /// ARCore-capable phone, but Google Play Services for AR is missing.
  notInstalled,

  /// Google Play Services for AR must be updated.
  apkTooOld,
}

enum ArPermission { granted, denied, permanentlyDenied }

enum ArInstallResult { installed, requested, declined, incompatible, failed }

/// Lifecycle of the Camera AR screen.
enum ArPhase {
  idle,
  checking,
  unsupported,

  /// Google Play Services for AR missing / outdated: offer installation.
  servicesMissing,
  permissionDenied,
  starting,

  /// Camera running, looking for a surface to anchor the model.
  scanning,

  /// Model anchored in the scene; can be moved / rotated / scaled.
  placed,
  capturing,
  error,
}

/// What a single-finger gesture on the camera view does.
enum ArMode { place, move, rotate, scale }

extension ArModeX on ArMode {
  String get label => switch (this) {
    ArMode.place => 'Place',
    ArMode.move => 'Move',
    ArMode.rotate => 'Rotate',
    ArMode.scale => 'Scale',
  };
}

/// The signage model the AR engine should show.
@immutable
class ArModelSpec {
  const ArModelSpec({
    required this.mediaCode,
    required this.installationCode,
    required this.widthFt,
    required this.heightFt,
    required this.label,
    this.doubleSided = false,
    this.unitId = '',
    this.geometry,
  });

  final String mediaCode;
  final String installationCode;
  final double widthFt;
  final double heightFt;
  final String label;
  final bool doubleSided;

  /// Signage Item ID ([SignageUnit.id]).
  final String unitId;

  /// Full 3D geometry for the native renderer (metres).
  final ArModelData? geometry;

  double get widthM => widthFt * kFeetToMetres;
  double get heightM => heightFt * kFeetToMetres;

  bool get preferVertical =>
      geometry?.preferVertical ?? prefersVerticalPlacement(installationCode);
}

/// Model pose relative to its anchor (metres / radians / factor).
@immutable
class ArModelTransform {
  const ArModelTransform({
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.yaw = 0,
    this.scale = 1,
  });

  static const minScale = 0.2;
  static const maxScale = 5.0;

  final double x;
  final double y;
  final double z;
  final double yaw;
  final double scale;

  /// The preview is not at the entered physical size.
  bool get scaleAdjusted => (scale - 1).abs() > 0.005;

  ArModelTransform copyWith({
    double? x,
    double? y,
    double? z,
    double? yaw,
    double? scale,
  }) => ArModelTransform(
    x: x ?? this.x,
    y: y ?? this.y,
    z: z ?? this.z,
    yaw: yaw ?? this.yaw,
    scale: (scale ?? this.scale).clamp(minScale, maxScale).toDouble(),
  );

  Map<String, double> toMap() => {
    'x': x,
    'y': y,
    'z': z,
    'yaw': yaw,
    'scale': scale,
  };

  static ArModelTransform fromMap(Map<String, double> m) => ArModelTransform(
    x: m['x'] ?? 0,
    y: m['y'] ?? 0,
    z: m['z'] ?? 0,
    yaw: m['yaw'] ?? 0,
    scale: (m['scale'] ?? 1).clamp(minScale, maxScale).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is ArModelTransform &&
      other.x == x &&
      other.y == y &&
      other.z == z &&
      other.yaw == yaw &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(x, y, z, yaw, scale);
}

/// Result of a tap-to-place hit test.
@immutable
class ArPlaceResult {
  const ArPlaceResult({required this.placed, this.surface, this.reason});

  final bool placed;

  /// "vertical", "horizontal" or "manual" (instant placement).
  final String? surface;
  final String? reason;
}

/// Event pushed by the AR engine (ready, tracking, planes, anchorLost,
/// error).
@immutable
class ArEvent {
  const ArEvent(this.type, [this.data = const {}]);

  final String type;
  final Map<String, Object?> data;

  static ArEvent fromNative(Object? raw) {
    if (raw is! Map) return const ArEvent('unknown');
    final data = raw.map((k, v) => MapEntry('$k', v));
    return ArEvent('${data['type'] ?? 'unknown'}', data);
  }
}

/// Error starting the AR session.
class ArStartException implements Exception {
  const ArStartException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Platform AR engine behind a Dart abstraction so the rest of the app never
/// depends on native details. [NativeArPlatform] is the ARCore engine;
/// [UnavailableArPlatform] is used where AR cannot run.
abstract class ArPlatform {
  String get engineName;

  /// Engine events (tracking, planes, anchor lost, errors).
  Stream<ArEvent> get events;

  Future<ArSupport> checkSupport();
  Future<ArInstallResult> requestInstall();
  Future<ArPermission> requestCameraPermission();

  /// Starts the session for [model]; completes when the camera is running.
  Future<void> startSession(ArModelSpec model);
  Future<void> stopSession();
  Future<void> pause();
  Future<void> resume();

  /// Hit-tests detected surfaces at a normalised screen point (0..1) and
  /// anchors (or re-anchors) the model there. [manual] allows ARCore
  /// instant placement when no surface is detected (e.g. glass).
  Future<ArPlaceResult> placeModel(
    Offset normalizedScreenPoint, {
    bool manual = false,
  });
  Future<void> updateTransform(ArModelTransform transform);
  Future<void> removePlacement();
  Future<void> setPlanesVisible(bool visible);

  /// PNG of the rendered AR scene *including the model* (never a plain
  /// camera frame). Null when the engine cannot capture.
  Future<Uint8List?> captureScene();

  /// Camera + model view.
  Widget buildView(BuildContext context);
}

/// Engine for platforms without ARCore (tests, non-Android hosts).
class UnavailableArPlatform implements ArPlatform {
  const UnavailableArPlatform();

  @override
  String get engineName => 'none';

  @override
  Stream<ArEvent> get events => const Stream.empty();

  @override
  Future<ArSupport> checkSupport() async => ArSupport.unsupported;

  @override
  Future<ArInstallResult> requestInstall() async =>
      ArInstallResult.incompatible;

  @override
  Future<ArPermission> requestCameraPermission() async => ArPermission.denied;

  @override
  Future<void> startSession(ArModelSpec model) async =>
      throw const ArStartException('unsupported', 'AR is not available');

  @override
  Future<void> stopSession() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<ArPlaceResult> placeModel(
    Offset normalizedScreenPoint, {
    bool manual = false,
  }) async => const ArPlaceResult(placed: false, reason: 'unsupported');

  @override
  Future<void> updateTransform(ArModelTransform transform) async {}

  @override
  Future<void> removePlacement() async {}

  @override
  Future<void> setPlanesVisible(bool visible) async {}

  @override
  Future<Uint8List?> captureScene() async => null;

  @override
  Widget buildView(BuildContext context) => const SizedBox.shrink();
}

/// Optional engine capability (GSB Render View): an illustrative night
/// grade of the live camera view and a capture of ONE camera frame rendered
/// three ways. Engines without it keep the original single capture.
abstract class ArRenderViewCapable {
  Future<void> setNightMode(bool night);

  /// `original` (camera only, no models), `day` and `night` PNGs of the
  /// same frame and pose. Null when unavailable.
  Future<Map<String, Uint8List>?> captureRenderSet();
}

/// Result of a successful AR capture.
class ArCaptureResult {
  const ArCaptureResult({
    required this.png,
    required this.transform,
    required this.capturedAt,
    this.surface,
    this.originalPng,
    this.nightPng,
  });

  /// Day render with the model(s) (the regular AR capture).
  final Uint8List png;
  final ArModelTransform transform;
  final DateTime capturedAt;
  final String? surface;

  /// Same camera frame without any model (render-set captures only).
  final Uint8List? originalPng;

  /// Same frame and pose in the illustrative night view.
  final Uint8List? nightPng;

  bool get isRenderSet => originalPng != null && nightPng != null;
}

/// State machine of the Camera AR screen. Pure Dart: unit-testable with a
/// fake [ArPlatform]; no camera or AR session is touched in tests.
class ArSessionController extends ChangeNotifier {
  ArSessionController({
    required this.platform,
    required this.model,
    DateTime Function()? clock,
    ArModelTransform? initialTransform,
  }) : _clock = clock ?? DateTime.now,
       _initial = initialTransform ?? const ArModelTransform(),
       _transform = initialTransform ?? const ArModelTransform();

  final ArPlatform platform;
  final DateTime Function() _clock;
  final ArModelTransform _initial;
  ArModelSpec model;

  ArPhase _phase = ArPhase.idle;
  ArModelTransform _transform;
  String? _error;
  String? _errorCode;
  bool _disposed = false;
  StreamSubscription<ArEvent>? _events;
  ArSupport _support = ArSupport.unknown;

  String _tracking = 'none';
  String _trackingReason = 'NONE';
  int _horizontalPlanes = 0;
  int _verticalPlanes = 0;
  String? _surface;
  ArMode _mode = ArMode.place;
  bool _planesVisible = true;
  bool _manualPlacement = false;
  bool _installRequested = false;

  ArPhase get phase => _phase;
  ArModelTransform get transform => _transform;
  String? get error => _error;
  String? get errorCode => _errorCode;
  ArSupport get support => _support;
  String get tracking => _tracking;
  String get trackingReason => _trackingReason;
  int get horizontalPlanes => _horizontalPlanes;
  int get verticalPlanes => _verticalPlanes;
  String? get surface => _surface;
  ArMode get mode => _mode;
  bool get planesVisible => _planesVisible;
  bool get manualPlacement => _manualPlacement;
  bool get installRequested => _installRequested;

  /// Restored orientation / scale from an earlier capture (the world anchor
  /// itself is not persisted, so the model must be placed again).
  bool get restored => _initial != const ArModelTransform();

  bool get isPlaced => _phase == ArPhase.placed;
  bool get canCapture => _phase == ArPhase.placed && !trackingLost;
  bool get isUnsupported => _phase == ArPhase.unsupported;
  bool get sessionRunning =>
      _phase == ArPhase.scanning ||
      _phase == ArPhase.placed ||
      _phase == ArPhase.capturing;

  /// 'none' = the engine has not reported tracking yet.
  bool get trackingLost =>
      sessionRunning && _tracking != 'tracking' && _tracking != 'none';

  /// Contextual instruction for the camera screen (null = nothing to say).
  String? get guidance {
    if (!sessionRunning) return null;
    if (_tracking != 'tracking' && _tracking != 'none') {
      final why = switch (_trackingReason) {
        'INSUFFICIENT_LIGHT' => ' More light is needed.',
        'EXCESSIVE_MOTION' => ' Moving too fast.',
        'INSUFFICIENT_FEATURES' => ' Point at a textured surface.',
        'CAMERA_UNAVAILABLE' => ' Camera is in use by another app.',
        _ => '',
      };
      return 'Tracking lost. Move the phone slowly.$why';
    }
    if (_phase == ArPhase.placed) return null;
    final wanted = model.preferVertical ? _verticalPlanes : _horizontalPlanes;
    if (wanted == 0 && _horizontalPlanes + _verticalPlanes == 0) {
      return 'Move your phone slowly to scan the area. '
          '${model.preferVertical ? 'Point your camera toward the wall.' : 'Point your camera toward the ground.'}';
    }
    if (wanted == 0) {
      return model.preferVertical
          ? 'Point your camera toward the wall.'
          : 'Point your camera toward the ground.';
    }
    return 'Tap a detected surface to place the signage.';
  }

  void _set(ArPhase p, {String? error, String? code}) {
    final started = p == ArPhase.scanning && _phase == ArPhase.starting;
    _phase = p;
    _error = error;
    _errorCode = code;
    // A (re)started native view begins in day mode: re-apply night.
    if (started && _night) _applyNight();
    if (!_disposed) notifyListeners();
  }

  bool _night = false;

  /// Illustrative night view of the live camera (GSB Render View).
  bool get nightMode => _night;

  bool get supportsRenderView => platform is ArRenderViewCapable;

  ArRenderViewCapable? get _renderView {
    final Object p = platform;
    return p is ArRenderViewCapable ? p : null;
  }

  void _applyNight() {
    _renderView?.setNightMode(_night).catchError((Object _) {});
  }

  /// Switches day / night. Only the presentation changes: anchors, model
  /// transforms and dimensions are untouched.
  void setNightMode(bool night) {
    if (_night == night) return;
    _night = night;
    _applyNight();
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _onEvent(ArEvent e) {
    switch (e.type) {
      case 'tracking':
        _tracking = '${e.data['state'] ?? 'none'}';
        _trackingReason = '${e.data['reason'] ?? 'NONE'}';
        _changed();
      case 'planes':
        _horizontalPlanes = (e.data['horizontal'] as num?)?.toInt() ?? 0;
        _verticalPlanes = (e.data['vertical'] as num?)?.toInt() ?? 0;
        _changed();
      case 'anchorLost':
        if (_phase == ArPhase.placed) {
          _set(
            ArPhase.scanning,
            error: 'Tracking lost. Tap a surface to place the signage again.',
          );
        }
      case 'error':
        if (_phase == ArPhase.starting) return; // handled by startSession
        _handleError(
          '${e.data['code'] ?? 'session'}',
          '${e.data['message'] ?? 'AR error'}',
        );
    }
  }

  void _handleError(String code, String message) {
    switch (code) {
      case 'not_installed':
      case 'apk_too_old':
        _set(ArPhase.servicesMissing, error: message, code: code);
      case 'unsupported':
      case 'sdk_too_old':
        _set(ArPhase.unsupported, error: message, code: code);
      case 'permission':
        _set(ArPhase.permissionDenied, error: message, code: code);
      default:
        _set(ArPhase.error, error: message, code: code);
    }
  }

  /// Checks support → services → camera permission → starts the session.
  Future<void> open() async {
    if (_phase == ArPhase.checking || _phase == ArPhase.starting) return;
    _events ??= platform.events.listen(_onEvent);
    _set(ArPhase.checking);
    try {
      _support = await platform.checkSupport();
    } catch (e) {
      _support = ArSupport.unsupported;
    }
    switch (_support) {
      case ArSupport.supported:
        break;
      case ArSupport.notInstalled:
        _set(
          ArPhase.servicesMissing,
          error: 'Google Play Services for AR is not installed.',
          code: 'not_installed',
        );
        return;
      case ArSupport.apkTooOld:
        _set(
          ArPhase.servicesMissing,
          error: 'Google Play Services for AR needs an update.',
          code: 'apk_too_old',
        );
        return;
      case ArSupport.unsupported:
      case ArSupport.unknown:
        _set(ArPhase.unsupported);
        return;
    }
    final permission = await platform.requestCameraPermission();
    if (permission != ArPermission.granted) {
      _set(
        ArPhase.permissionDenied,
        error: permission == ArPermission.permanentlyDenied
            ? 'Camera blocked. Enable it in app settings.'
            : 'Camera permission is needed for AR preview.',
        code: 'permission',
      );
      return;
    }
    _set(ArPhase.starting);
    try {
      await platform.startSession(model);
      if (_disposed) return;
      _tracking = 'none';
      _transform = _initial;
      _surface = null;
      await platform.updateTransform(_transform);
      await platform.setPlanesVisible(_planesVisible);
      _set(ArPhase.scanning);
    } on ArStartException catch (e) {
      _handleError(e.code, e.message);
    } catch (e) {
      _set(ArPhase.error, error: 'Could not start AR: $e', code: 'session');
    }
  }

  /// Opens the system flow to install / update Google Play Services for AR.
  Future<ArInstallResult> installServices() async {
    final r = await platform.requestInstall();
    switch (r) {
      case ArInstallResult.installed:
        _installRequested = false;
        await open();
      case ArInstallResult.requested:
        // The Play Store opens; [open] runs again when the app resumes.
        _installRequested = true;
        _changed();
      case ArInstallResult.declined:
        _set(
          ArPhase.servicesMissing,
          error:
              'Installation declined. Camera AR needs Google Play '
              'Services for AR.',
          code: 'declined',
        );
      case ArInstallResult.incompatible:
        _set(ArPhase.unsupported, code: 'unsupported');
      case ArInstallResult.failed:
        _set(
          ArPhase.servicesMissing,
          error: 'Could not start the installation. Try again.',
          code: 'install_failed',
        );
    }
    return r;
  }

  /// App came back to the foreground (e.g. after installing ARCore).
  Future<void> onAppResumed() async {
    if (_installRequested && _phase == ArPhase.servicesMissing) {
      _installRequested = false;
      await open();
    }
  }

  void setMode(ArMode m) {
    _mode = m;
    _changed();
  }

  void setManualPlacement(bool v) {
    _manualPlacement = v;
    _changed();
  }

  Future<void> setPlanesVisible(bool v) async {
    _planesVisible = v;
    await platform.setPlanesVisible(v);
    _changed();
  }

  /// Anchors (or re-anchors = moves) the model at a tapped screen point.
  Future<bool> placeAt(Offset normalizedScreenPoint) async {
    if (_phase != ArPhase.scanning && _phase != ArPhase.placed) return false;
    final r = await platform.placeModel(
      normalizedScreenPoint,
      manual: _manualPlacement,
    );
    if (_disposed) return r.placed;
    if (r.placed) {
      _surface = r.surface;
      _set(ArPhase.placed);
    } else if (r.reason == 'not_tracking') {
      _error = 'Tracking lost. Move the phone slowly.';
      _changed();
    } else if (_phase != ArPhase.placed) {
      _error = model.preferVertical
          ? 'No wall found there. Point your camera toward the wall and '
                'move slowly.'
          : 'No floor found there. Point your camera toward the ground '
                'and move slowly.';
      _changed();
    }
    return r.placed;
  }

  Future<void> _apply(ArModelTransform t) async {
    if (!isPlaced) return;
    _transform = t;
    await platform.updateTransform(t);
    _changed();
  }

  Future<void> moveBy(double dx, double dz) =>
      _apply(_transform.copyWith(x: _transform.x + dx, z: _transform.z + dz));

  Future<void> raiseBy(double dy) =>
      _apply(_transform.copyWith(y: _transform.y + dy));

  Future<void> rotateBy(double radians) => setYaw(_transform.yaw + radians);

  Future<void> setYaw(double radians) {
    var yaw = radians % (2 * math.pi);
    if (yaw > math.pi) yaw -= 2 * math.pi;
    return _apply(_transform.copyWith(yaw: yaw));
  }

  Future<void> scaleBy(double factor) => setScale(_transform.scale * factor);

  Future<void> setScale(double scale) =>
      _apply(_transform.copyWith(scale: scale));

  /// Back to the entered physical size.
  Future<void> resetScale() => setScale(1);

  /// Resets orientation / size / offsets (anchor kept).
  Future<void> resetPlacement() async {
    if (!sessionRunning) return;
    _transform = const ArModelTransform();
    await platform.updateTransform(_transform);
    _changed();
  }

  /// Multi-object scene ([ArSceneController]) owns the anchors: the phase
  /// follows whether at least one visible object is anchored, so capture is
  /// only possible with a model in view. No engine call is made.
  void syncScenePlaced(bool anyPlaced, {String? surface}) {
    if (_disposed) return;
    if (anyPlaced && _phase == ArPhase.scanning) {
      _surface = surface;
      _set(ArPhase.placed);
    } else if (anyPlaced && _phase == ArPhase.placed) {
      if (_surface != surface) {
        _surface = surface;
        _changed();
      }
    } else if (!anyPlaced && _phase == ArPhase.placed) {
      _surface = null;
      _set(ArPhase.scanning);
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _changed();
  }

  /// Removes the anchored model; the session keeps running.
  Future<void> removePlacement() async {
    if (_phase != ArPhase.placed) return;
    await platform.removePlacement();
    _surface = null;
    _set(ArPhase.scanning);
  }

  /// Captures the rendered AR scene with the model. Refused unless a model
  /// is placed and tracked, so a camera-only frame is never saved as an AR
  /// screenshot.
  Future<ArCaptureResult?> capture() async {
    if (!canCapture) {
      _error = isPlaced
          ? 'Tracking lost. Move the phone slowly, then capture.'
          : 'Place the signage before capturing.';
      _changed();
      return null;
    }
    _set(ArPhase.capturing);
    try {
      final png = await platform.captureScene();
      if (_disposed) return null;
      if (png == null || png.isEmpty) {
        _set(ArPhase.placed, error: 'The AR engine could not capture.');
        return null;
      }
      _set(ArPhase.placed);
      return ArCaptureResult(
        png: png,
        transform: _transform,
        capturedAt: _clock(),
        surface: _surface,
      );
    } catch (e) {
      if (!_disposed) _set(ArPhase.placed, error: 'Capture failed: $e');
      return null;
    }
  }

  /// GSB capture: original frame, day and night of the SAME camera frame
  /// and pose. Falls back to [capture] when the engine cannot render sets.
  Future<ArCaptureResult?> captureRenderSet() async {
    final p = _renderView;
    if (p == null) return capture();
    if (!canCapture) return capture(); // reports the reason
    _set(ArPhase.capturing);
    try {
      final set = await p.captureRenderSet();
      if (_disposed) return null;
      final day = set?['day'], original = set?['original'];
      final night = set?['night'];
      if (day == null || original == null || night == null) {
        _set(ArPhase.placed, error: 'The AR engine could not capture.');
        return null;
      }
      _set(ArPhase.placed);
      return ArCaptureResult(
        png: day,
        originalPng: original,
        nightPng: night,
        transform: _transform,
        capturedAt: _clock(),
        surface: _surface,
      );
    } catch (e) {
      if (!_disposed) _set(ArPhase.placed, error: 'Capture failed: $e');
      return null;
    }
  }

  Future<void> close() async {
    if (sessionRunning || _phase == ArPhase.starting) {
      await platform.stopSession();
    }
    _set(ArPhase.idle);
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    if (sessionRunning || _phase == ArPhase.starting) platform.stopSession();
    super.dispose();
  }
}
