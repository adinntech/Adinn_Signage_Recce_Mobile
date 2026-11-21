import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ar_model_builder.dart';
import 'ar_scene_engine.dart';
import 'ar_session_controller.dart';

/// ARCore engine (Android): talks to the Kotlin bridge in
/// `android/app/src/main/kotlin/.../ar/` through platform channels and shows
/// the native GL camera view with hybrid composition (the camera image,
/// detected planes and the anchored signage model are rendered natively).
class NativeArPlatform implements ArPlatform, ArSceneEngine {
  NativeArPlatform({
    MethodChannel? channel,
    EventChannel? eventChannel,
    this.startTimeout = const Duration(seconds: 20),
    this.captureTimeout = const Duration(seconds: 10),
    this.placeTimeout = const Duration(seconds: 6),
  }) : _channel = channel ?? const MethodChannel('adinn/ar'),
       _eventChannel = eventChannel ?? const EventChannel('adinn/ar/events');

  static const viewType = 'adinn/ar_view';

  final MethodChannel _channel;
  final EventChannel _eventChannel;
  final Duration startTimeout;
  final Duration captureTimeout;
  final Duration placeTimeout;

  ArModelSpec? _spec;
  bool _planesVisible = true;

  late final Stream<ArEvent> _events = _eventChannel
      .receiveBroadcastStream()
      .map(ArEvent.fromNative)
      .handleError((Object _) {})
      .asBroadcastStream();

  @override
  String get engineName => 'ARCore (com.google.ar:core 1.54.0)';

  @override
  Stream<ArEvent> get events => _events;

  /// Model passed to the native view when it is created.
  ArModelSpec? get spec => _spec;

  @override
  Future<ArSupport> checkSupport() async {
    try {
      final r = await _channel.invokeMethod<String>('checkAvailability');
      return switch (r) {
        'supported' => ArSupport.supported,
        'not_installed' => ArSupport.notInstalled,
        'apk_too_old' => ArSupport.apkTooOld,
        'unsupported' => ArSupport.unsupported,
        _ => ArSupport.unknown,
      };
    } on MissingPluginException {
      return ArSupport.unsupported;
    } on PlatformException {
      return ArSupport.unknown;
    }
  }

  @override
  Future<ArInstallResult> requestInstall() async {
    try {
      final r = await _channel.invokeMethod<String>('requestInstall');
      return switch (r) {
        'installed' => ArInstallResult.installed,
        'requested' => ArInstallResult.requested,
        'declined' => ArInstallResult.declined,
        'incompatible' => ArInstallResult.incompatible,
        _ => ArInstallResult.failed,
      };
    } catch (_) {
      return ArInstallResult.failed;
    }
  }

  @override
  Future<ArPermission> requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) return ArPermission.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return ArPermission.permanentlyDenied;
    }
    return ArPermission.denied;
  }

  /// The view is built by the AR screen once the phase is "starting"; the
  /// native view creates and resumes the ARCore session and reports
  /// "ready" (or an error) on the event channel.
  @override
  Future<void> startSession(ArModelSpec model) async {
    _spec = model;
    final done = Completer<void>();
    final sub = _events.listen((e) {
      if (done.isCompleted) return;
      if (e.type == 'ready') done.complete();
      if (e.type == 'error') {
        done.completeError(
          ArStartException(
            '${e.data['code'] ?? 'session'}',
            '${e.data['message'] ?? 'Could not start AR'}',
          ),
        );
      }
    });
    try {
      await done.future.timeout(
        startTimeout,
        onTimeout: () => throw const ArStartException(
          'timeout',
          'AR did not start in time. Close other camera apps and retry.',
        ),
      );
    } finally {
      await sub.cancel();
    }
  }

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> stopSession() => _call<void>('stopSession');

  @override
  Future<void> pause() => _call<void>('pause');

  @override
  Future<void> resume() => _call<void>('resume');

  @override
  Future<ArPlaceResult> placeModel(
    Offset normalizedScreenPoint, {
    bool manual = false,
  }) async {
    final r = await _call<Map<Object?, Object?>>('placeAt', {
      'x': normalizedScreenPoint.dx,
      'y': normalizedScreenPoint.dy,
      'manual': manual,
    });
    if (r == null) {
      return const ArPlaceResult(placed: false, reason: 'no_engine');
    }
    return ArPlaceResult(
      placed: r['placed'] == true,
      surface: r['surface'] as String?,
      reason: r['reason'] as String?,
    );
  }

  @override
  Future<void> updateTransform(ArModelTransform t) =>
      _call<void>('setTransform', t.toMap());

  @override
  Future<void> removePlacement() => _call<void>('removePlacement');

  @override
  Future<void> setPlanesVisible(bool visible) {
    _planesVisible = visible;
    return _call<void>('setPlanesVisible', {'visible': visible});
  }

  @override
  Future<Uint8List?> captureScene() =>
      _call<Uint8List>('capture').timeout(captureTimeout);

  // ---------------------------------------------------------------------------
  // Multi-object scene (ArSceneEngine)
  // ---------------------------------------------------------------------------

  @override
  bool get supportsMultipleObjects => true;

  @override
  Future<bool> registerModel(String key, ArModelData model) async {
    try {
      final r = await _call<bool>('registerModel', {
        'key': key,
        'model': model.toMap(),
      });
      return r == true;
    } on PlatformException {
      return false;
    }
  }

  static ArObjectPlaceResult _placeResult(Map<Object?, Object?>? r) {
    if (r == null) {
      return const ArObjectPlaceResult(placed: false, reason: 'no_engine');
    }
    final pose = r['pose'];
    return ArObjectPlaceResult(
      placed: r['placed'] == true,
      surface: r['surface'] as String?,
      reason: r['reason'] as String?,
      pose: pose is List && pose.length == 7
          ? [for (final v in pose) (v as num).toDouble()]
          : null,
    );
  }

  Future<ArObjectPlaceResult> _place(
    String method,
    Map<String, Object?> args,
  ) => _call<Map<Object?, Object?>>(method, args)
      .then(_placeResult)
      .timeout(
        placeTimeout,
        onTimeout: () =>
            const ArObjectPlaceResult(placed: false, reason: 'timeout'),
      )
      .catchError(
        (Object _) => const ArObjectPlaceResult(placed: false, reason: 'error'),
      );

  @override
  Future<ArObjectPlaceResult> placeObject(
    String id,
    String modelKey,
    Offset normalizedScreenPoint, {
    bool manual = false,
  }) => _place('placeObject', {
    'id': id,
    'key': modelKey,
    'x': normalizedScreenPoint.dx,
    'y': normalizedScreenPoint.dy,
    'manual': manual,
  });

  @override
  Future<ArObjectPlaceResult> anchorObject(
    String id,
    String modelKey,
    List<double> pose,
    String surface,
  ) => _place('anchorObject', {
    'id': id,
    'key': modelKey,
    'pose': pose,
    'surface': surface,
  });

  @override
  Future<void> setObjectTransform(String id, ArObjectTransform t) =>
      _call<void>('setObjectTransform', {'id': id, ...t.toMap()});

  @override
  Future<void> setObjectVisible(String id, bool visible) =>
      _call<void>('setObjectVisible', {'id': id, 'visible': visible});

  @override
  Future<void> selectObject(String? id) =>
      _call<void>('selectObject', {'id': id});

  @override
  Future<void> removeObject(String id) =>
      _call<void>('removeObject', {'id': id});

  @override
  Future<String?> hitTestObject(Offset p) => _call<String>(
    'hitTestObject',
    {'x': p.dx, 'y': p.dy},
  ).timeout(placeTimeout, onTimeout: () => null).catchError((Object _) => null);

  @override
  Future<void> setPlacementIndicator(
    bool active, {
    bool preferVertical = false,
  }) => _call<void>('setPlacementIndicator', {
    'active': active,
    'vertical': preferVertical,
  });

  @override
  Widget buildView(BuildContext context) {
    final params = <String, Object?>{
      'model': _spec?.geometry?.toMap(),
      'planesVisible': _planesVisible,
    };
    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        // Touches are handled by the Flutter overlay (tap / pinch / rotate)
        // and forwarded through the method channel.
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      onCreatePlatformView: (p) =>
          // Hybrid composition: required for the native GLSurfaceView.
          PlatformViewsService.initExpensiveAndroidView(
              id: p.id,
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
              creationParams: params,
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () => p.onFocusChanged(true),
            )
            ..addOnPlatformViewCreatedListener(p.onPlatformViewCreated)
            ..create(),
    );
  }
}
