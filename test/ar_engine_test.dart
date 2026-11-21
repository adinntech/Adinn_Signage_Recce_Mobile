import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/ar/ar_model_builder.dart';
import 'package:signage_recce/features/ar/ar_session_controller.dart';
import 'package:signage_recce/features/ar/camera_ar_screen.dart';
import 'package:signage_recce/features/ar/native_ar_platform.dart';
import 'package:signage_recce/features/photos/photo_workspace_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

/// In-memory AR engine: no camera, no ARCore. Never counts as device
/// verification – it only exercises the Dart state machine and UI.
class FakeAr implements ArPlatform {
  FakeAr({
    this.support = ArSupport.supported,
    this.permission = ArPermission.granted,
    this.place = const ArPlaceResult(placed: true, surface: 'vertical'),
    this.png,
    this.startError,
    this.install = ArInstallResult.installed,
  });

  ArSupport support;
  ArPermission permission;
  ArPlaceResult place;
  Uint8List? png;
  Object? startError;
  ArInstallResult install;

  final _events = StreamController<ArEvent>.broadcast();
  int started = 0;
  int stopped = 0;
  int removed = 0;
  int installs = 0;
  bool? planesVisible;
  bool lastManual = false;
  ArModelSpec? model;
  final transforms = <ArModelTransform>[];

  void emit(String type, [Map<String, Object?> data = const {}]) =>
      _events.add(ArEvent(type, data));

  @override
  String get engineName => 'fake';

  @override
  Stream<ArEvent> get events => _events.stream;

  @override
  Future<ArSupport> checkSupport() async => support;

  @override
  Future<ArInstallResult> requestInstall() async {
    installs++;
    if (install == ArInstallResult.installed) {
      support = ArSupport.supported;
    }
    return install;
  }

  @override
  Future<ArPermission> requestCameraPermission() async => permission;

  @override
  Future<void> startSession(ArModelSpec model) async {
    final e = startError;
    if (e != null) throw e;
    started++;
    this.model = model;
  }

  @override
  Future<void> stopSession() async => stopped++;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<ArPlaceResult> placeModel(Offset p, {bool manual = false}) async {
    lastManual = manual;
    return place;
  }

  @override
  Future<void> updateTransform(ArModelTransform t) async => transforms.add(t);

  @override
  Future<void> removePlacement() async => removed++;

  @override
  Future<void> setPlanesVisible(bool visible) async => planesVisible = visible;

  @override
  Future<Uint8List?> captureScene() async => png;

  @override
  Widget buildView(BuildContext context) =>
      const ColoredBox(color: Colors.black, key: ValueKey('fake-ar-view'));
}

Board _board({
  String media = SignageCatalog.gsb,
  String inst = SignageCatalog.wallMount,
  double w = 8,
  double h = 3,
  Map<String, dynamic>? answers,
}) => Board(
  id: 'g',
  name: 'G',
  mediaCode: media,
  installationCode: inst,
  width: w,
  height: h,
  answers: answers,
);

ArModelSpec _spec(Board b) {
  final g = buildArModel(b, b.units.first);
  return ArModelSpec(
    mediaCode: g.mediaCode,
    installationCode: g.installationCode,
    widthFt: g.widthM / kFeetToMetres,
    heightFt: g.heightM / kFeetToMetres,
    label: 'GSB Unit 01',
    unitId: g.unitId,
    geometry: g,
  );
}

void main() {
  group('AR model selection & geometry (metres)', () {
    test('GSB wall fit: vertical placement, pivot on the board back', () {
      final g = buildArModel(_board(), _board().units.first);
      expect(g.preferVertical, isTrue);
      expect(g.widthM, closeTo(8 * 0.3048, 1e-9));
      expect(g.heightM, closeTo(3 * 0.3048, 1e-9));
      expect(g.widthM / g.heightM, closeTo(8 / 3, 1e-9));
      // Board depth for GSB = 8 in (rulebook) → back at z = -0.2032 m.
      expect(g.pivotWall[2], closeTo(-8 * 0.0254, 1e-9));
      final labelled = g.faces.where((f) => f.label != null).toList();
      expect(labelled, hasLength(1));
      expect(labelled.single.normal, [0, 0, 1]);
      // Every vertex is in metres (8 ft wide board spans ±1.22 m).
      final xs = [
        for (final f in g.faces)
          for (var i = 0; i < f.points.length; i += 3) f.points[i],
      ];
      expect(xs.reduce((a, b) => a > b ? a : b), closeTo(1.2192, 1e-6));
    });

    test('pole, standee and rooftop items prefer ground placement', () {
      for (final (media, inst) in [
        (SignageCatalog.gsb, SignageCatalog.singlePole),
        (SignageCatalog.gsb, SignageCatalog.doublePole),
        (SignageCatalog.singleStandee, SignageCatalog.freeStanding),
        (SignageCatalog.doubleStandee, SignageCatalog.freeStanding),
        (SignageCatalog.gsb, SignageCatalog.rooftop),
      ]) {
        final b = _board(media: media, inst: inst);
        final g = buildArModel(b, b.units.first);
        expect(g.preferVertical, isFalse, reason: '$media/$inst');
      }
      // Rooftop structures stand on the roof, not on the street.
      final roof = _board(
        inst: SignageCatalog.rooftop,
        answers: {'building_floors': 2},
      );
      final g = buildArModel(roof, roof.units.first);
      expect(g.pivotGround[1], closeTo(20 * 0.3048, 1e-9));
    });

    test('double-sided standee has front and back artwork', () {
      final b = _board(
        media: SignageCatalog.doubleStandee,
        inst: SignageCatalog.freeStanding,
      );
      final g = buildArModel(b, b.units.first);
      expect(g.doubleSided, isTrue);
      final normals = g.faces
          .where((f) => f.label != null)
          .map((f) => f.normal[2])
          .toSet();
      expect(normals, {1.0, -1.0});
      expect(g.pivotGround[1], 0);
    });

    test('vinyl / one-way vision on glass: vertical + manual fallback', () {
      final b = _board(
        media: SignageCatalog.vinyl,
        inst: SignageCatalog.glassPasting,
      );
      final g = buildArModel(b, b.units.first);
      expect(g.preferVertical, isTrue);
      expect(mayNeedManualPlacement(g.installationCode), isTrue);
      expect(g.faces, isNotEmpty);
    });

    test('every media × installation builds a usable AR model', () {
      for (final m in SignageCatalog.mediaTypes) {
        for (final inst in m.installations) {
          final b = _board(media: m.code, inst: inst);
          final g = buildArModel(b, b.units.first);
          expect(g.faces, isNotEmpty, reason: '${m.code}/$inst');
          for (final f in g.faces) {
            expect(f.points.length % 3, 0);
            expect(f.points.length, greaterThanOrEqualTo(9));
            expect(f.points.every((v) => v.isFinite), isTrue);
          }
          expect(g.pivotWall.every((v) => v.isFinite), isTrue);
          final map = g.toMap();
          expect((map['faces'] as List).length, g.faces.length);
        }
      }
    });

    test('item id mapping and per-unit sizes', () {
      final b = _board()
        ..quantity = 2
        ..syncUnits()
        ..sizeMode = SizeMode.different;
      b.units[0]
        ..width = 8
        ..height = 3;
      b.units[1]
        ..width = 12
        ..height = 4;
      final g1 = buildArModel(b, b.units[0]);
      final g2 = buildArModel(b, b.units[1]);
      expect(g1.unitId, b.units[0].id);
      expect(g2.unitId, b.units[1].id);
      expect(g2.widthM, closeTo(12 * 0.3048, 1e-9));
      expect(g2.widthM / g2.heightM, closeTo(3, 1e-9));
    });

    test('inch / metre units convert consistently', () {
      final b = Board(
        id: 'g',
        name: 'G',
        mediaCode: SignageCatalog.gsb,
        installationCode: SignageCatalog.wallMount,
        width: 96,
        height: 36,
        unit: MeasureUnit.inch,
      );
      expect(buildArModel(b, b.units.first).widthM, closeTo(2.4384, 1e-6));
    });
  });

  group('ArSessionController (fake engine, no hardware)', () {
    ArSessionController make(FakeAr p, {ArModelTransform? initial}) =>
        ArSessionController(
          platform: p,
          model: _spec(_board()),
          initialTransform: initial,
          clock: () => DateTime(2026, 11, 18, 9),
        );

    test('supported → scanning with guidance for walls', () async {
      final p = FakeAr();
      final c = make(p);
      await c.open();
      expect(c.phase, ArPhase.scanning);
      expect(p.started, 1);
      expect(p.model!.geometry!.preferVertical, isTrue);
      expect(c.guidance, contains('scan the area'));
      expect(c.guidance, contains('toward the wall'));
      p.emit('planes', {'horizontal': 1, 'vertical': 0});
      await pumpEventQueue();
      expect(c.guidance, 'Point your camera toward the wall.');
      p.emit('planes', {'horizontal': 1, 'vertical': 2});
      await pumpEventQueue();
      expect(c.guidance, 'Tap a detected surface to place the signage.');
      c.dispose();
    });

    test('unsupported device: no session', () async {
      final p = FakeAr(support: ArSupport.unsupported);
      final c = make(p);
      await c.open();
      expect(c.phase, ArPhase.unsupported);
      expect(p.started, 0);
    });

    test('bundled fallback engine reports unsupported', () async {
      final c = ArSessionController(
        platform: const UnavailableArPlatform(),
        model: _spec(_board()),
      );
      await c.open();
      expect(c.isUnsupported, isTrue);
    });

    test('AR services missing → install → session starts', () async {
      final p = FakeAr(support: ArSupport.notInstalled);
      final c = make(p);
      await c.open();
      expect(c.phase, ArPhase.servicesMissing);
      expect(c.errorCode, 'not_installed');
      await c.installServices();
      expect(p.installs, 1);
      expect(c.phase, ArPhase.scanning);
    });

    test('install handed to Play Store resumes on app return', () async {
      final p = FakeAr(
        support: ArSupport.apkTooOld,
        install: ArInstallResult.requested,
      );
      final c = make(p);
      await c.open();
      expect(c.errorCode, 'apk_too_old');
      await c.installServices();
      expect(c.installRequested, isTrue);
      p.support = ArSupport.supported;
      await c.onAppResumed();
      expect(c.phase, ArPhase.scanning);
    });

    test('install declined stays in services-missing state', () async {
      final p = FakeAr(
        support: ArSupport.notInstalled,
        install: ArInstallResult.declined,
      );
      final c = make(p);
      await c.open();
      await c.installServices();
      expect(c.phase, ArPhase.servicesMissing);
      expect(c.error, contains('declined'));
    });

    test('camera permission denied', () async {
      final p = FakeAr(permission: ArPermission.denied);
      final c = make(p);
      await c.open();
      expect(c.phase, ArPhase.permissionDenied);
      expect(p.started, 0);
    });

    test('initialisation / rendering errors map to clear states', () async {
      final p = FakeAr(
        startError: const ArStartException('render_init', 'GL failed'),
      );
      final c = make(p);
      await c.open();
      expect(c.phase, ArPhase.error);
      expect(c.error, 'GL failed');
      p.startError = const ArStartException('not_installed', 'missing');
      await c.open();
      expect(c.phase, ArPhase.servicesMissing);
      p.startError = StateError('boom');
      await c.open();
      expect(c.phase, ArPhase.error);
      expect(c.error, contains('Could not start AR'));
      // Retry after the problem is fixed.
      p.startError = null;
      await c.open();
      expect(c.phase, ArPhase.scanning);
    });

    test('place, move (re-anchor), rotate, scale, reset, remove', () async {
      final p = FakeAr();
      final c = make(p);
      await c.open();
      // Transforms are refused before placement.
      await c.rotateBy(1);
      expect(c.transform.yaw, 0);
      expect(await c.placeAt(const Offset(0.5, 0.5)), isTrue);
      expect(c.phase, ArPhase.placed);
      expect(c.surface, 'vertical');
      // Move = place again elsewhere.
      p.place = const ArPlaceResult(placed: true, surface: 'vertical');
      expect(await c.placeAt(const Offset(0.2, 0.6)), isTrue);
      await c.rotateBy(0.5);
      await c.scaleBy(1.5);
      expect(c.transform.yaw, closeTo(0.5, 1e-9));
      expect(c.transform.scale, 1.5);
      expect(c.transform.scaleAdjusted, isTrue);
      await c.setScale(100);
      expect(c.transform.scale, ArModelTransform.maxScale);
      await c.resetScale();
      expect(c.transform.scaleAdjusted, isFalse);
      await c.resetPlacement();
      expect(c.transform, const ArModelTransform());
      expect(p.transforms.last, const ArModelTransform());
      await c.removePlacement();
      expect(p.removed, 1);
      expect(c.phase, ArPhase.scanning);
    });

    test('failed hit test explains what to point at', () async {
      final p = FakeAr(place: const ArPlaceResult(placed: false));
      final c = make(p);
      await c.open();
      expect(await c.placeAt(const Offset(0.5, 0.5)), isFalse);
      expect(c.error, contains('toward the wall'));
      c.setManualPlacement(true);
      await c.placeAt(const Offset(0.5, 0.5));
      expect(p.lastManual, isTrue);
    });

    test('tracking loss / anchor loss / reinitialisation', () async {
      final p = FakeAr(png: Uint8List.fromList([1, 2, 3]));
      final c = make(p);
      await c.open();
      await c.placeAt(const Offset(0.5, 0.5));
      p.emit('tracking', {'state': 'paused', 'reason': 'EXCESSIVE_MOTION'});
      await pumpEventQueue();
      expect(c.trackingLost, isTrue);
      expect(c.guidance, contains('Tracking lost'));
      expect(c.guidance, contains('too fast'));
      expect(c.canCapture, isFalse);
      expect(await c.capture(), isNull);
      p.emit('tracking', {'state': 'tracking', 'reason': 'NONE'});
      await pumpEventQueue();
      expect(c.canCapture, isTrue);
      p.emit('anchorLost');
      await pumpEventQueue();
      expect(c.phase, ArPhase.scanning);
      expect(c.error, contains('place the signage again'));
      // A runtime engine error (e.g. camera taken) → error state + retry.
      p.emit('error', {'code': 'camera', 'message': 'Camera in use'});
      await pumpEventQueue();
      expect(c.phase, ArPhase.error);
      await c.open();
      expect(c.phase, ArPhase.scanning);
      expect(p.started, 2);
    });

    test('capture: refused before placement, metadata after', () async {
      final png = Uint8List.fromList(List.filled(16, 9));
      final p = FakeAr(png: png);
      final c = make(p);
      await c.open();
      expect(await c.capture(), isNull);
      expect(c.error, contains('Place the signage'));
      await c.placeAt(const Offset(0.5, 0.5));
      await c.rotateBy(0.25);
      final r = await c.capture();
      expect(r!.png, png);
      expect(r.transform.yaw, closeTo(0.25, 1e-9));
      expect(r.surface, 'vertical');
      expect(r.capturedAt, DateTime(2026, 11, 18, 9));
      expect(c.phase, ArPhase.placed);
    });

    test('capture failure keeps the session usable', () async {
      final p = FakeAr();
      final c = make(p);
      await c.open();
      await c.placeAt(const Offset(0.5, 0.5));
      expect(await c.capture(), isNull);
      expect(c.error, contains('could not capture'));
      expect(c.phase, ArPhase.placed);
    });

    test('restored orientation / scale; dispose stops the session', () async {
      final p = FakeAr();
      final c = make(p, initial: const ArModelTransform(yaw: 0.4, scale: 2));
      expect(c.restored, isTrue);
      await c.open();
      expect(p.transforms.first.scale, 2);
      c.dispose();
      expect(p.stopped, 1);
    });

    test('planes indicator toggle', () async {
      final p = FakeAr();
      final c = make(p);
      await c.open();
      await c.setPlanesVisible(false);
      expect(p.planesVisible, isFalse);
      expect(c.planesVisible, isFalse);
    });
  });

  group('NativeArPlatform channel contract (mocked)', () {
    const channel = MethodChannel('adinn/ar');
    final calls = <MethodCall>[];

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      calls.clear();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void mock(Object? Function(MethodCall c) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
            calls.add(c);
            return handler(c);
          });
    }

    test('availability values map to support states', () async {
      final p = NativeArPlatform();
      for (final (raw, want) in [
        ('supported', ArSupport.supported),
        ('not_installed', ArSupport.notInstalled),
        ('apk_too_old', ArSupport.apkTooOld),
        ('unsupported', ArSupport.unsupported),
        ('weird', ArSupport.unknown),
      ]) {
        mock((_) => raw);
        expect(await p.checkSupport(), want);
      }
    });

    test('no native engine (MissingPlugin) → unsupported', () async {
      expect(await NativeArPlatform().checkSupport(), ArSupport.unsupported);
    });

    test('placement, transform, capture and install calls', () async {
      final png = Uint8List.fromList([7, 7, 7]);
      mock(
        (c) => switch (c.method) {
          'placeAt' => {'placed': true, 'surface': 'horizontal'},
          'capture' => png,
          'requestInstall' => 'requested',
          _ => null,
        },
      );
      final p = NativeArPlatform();
      final r = await p.placeModel(const Offset(0.25, 0.75), manual: true);
      expect(r.placed, isTrue);
      expect(r.surface, 'horizontal');
      expect(calls.last.arguments, {'x': 0.25, 'y': 0.75, 'manual': true});
      await p.updateTransform(const ArModelTransform(yaw: 1, scale: 2));
      expect(calls.last.method, 'setTransform');
      expect((calls.last.arguments as Map)['scale'], 2);
      expect(await p.captureScene(), png);
      expect(await p.requestInstall(), ArInstallResult.requested);
      await p.removePlacement();
      await p.setPlanesVisible(false);
      expect(calls.last.arguments, {'visible': false});
    });

    test('capture error surfaces as an exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
            throw PlatformException(code: 'capture', message: 'black');
          });
      await expectLater(
        NativeArPlatform().captureScene(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('session start times out with a clear error', () async {
      final p = NativeArPlatform(
        startTimeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        p.startSession(_spec(_board())),
        throwsA(
          isA<ArStartException>().having((e) => e.code, 'code', 'timeout'),
        ),
      );
      expect(p.spec!.geometry, isNotNull);
    });

    test('model geometry is sent as plain codec data', () {
      final map = _spec(_board()).geometry!.toMap();
      // Must be encodable by the StandardMessageCodec used for the view.
      expect(
        () => const StandardMessageCodec().encodeMessage(map),
        returnsNormally,
      );
    });
  });

  group('Camera AR screens (widgets, fake engine)', () {
    Future<AppController> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final c = AppController(store: MemoryLocalStore());
      await c.init();
      c.loginWithPin('5678');
      return c;
    }

    Widget host(AppController c, Widget child) =>
        ChangeNotifierProvider<AppController>.value(
          value: c,
          child: MaterialApp(theme: AppTheme.light(), home: child),
        );

    testWidgets('place, capture twice, view gallery, delete one', (
      tester,
    ) async {
      final c = await boot(tester);
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      final photosBefore = b.photos.length;
      final ar = FakeAr(png: Uint8List.fromList(List.filled(10, 7)));
      var n = 0;
      await tester.pumpWidget(
        host(
          c,
          CameraArScreen(
            shopId: shop.id,
            boardId: b.id,
            unitId: b.units.first.id,
            platform: ar,
            writer: (png, folder) async => '/fake/$folder/${n++}.png',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(shop.name), findsOneWidget);
      expect(find.textContaining('ID ${b.units.first.id}'), findsWidgets);
      expect(find.byKey(const ValueKey('fake-ar-view')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('ar_capture')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('ar-gesture-layer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ar_capture')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ar_capture')));
      await tester.pumpAndSettle();

      final ars = b.previews.where((p) => p.kind == CaptureKind.ar).toList();
      expect(ars, hasLength(2));
      expect(ars.map((p) => p.id).toSet(), hasLength(2));
      expect(ars.map((p) => p.path).toSet(), hasLength(2));
      final first = ars.first;
      expect(first.projectId, shop.projectId);
      expect(first.taskId, shop.taskId);
      expect(first.shopId, shop.id);
      expect(first.groupId, b.id);
      expect(first.unitId, b.units.first.id);
      expect(first.info['mediaCode'], b.mediaCode);
      expect(first.info['surface'], 'vertical');
      expect(first.info['arSupport'], 'supported');
      expect(first.arTransform['scale'], 1);

      // Delete one capture: the other capture and the photos stay.
      await c.removePreview(shop.id, b.id, first.id);
      expect(b.previews.where((p) => p.kind == CaptureKind.ar), hasLength(1));
      expect(b.photos, hasLength(photosBefore));

      // Leaving the screen stops the AR session.
      await tester.pumpWidget(const SizedBox());
      expect(ar.stopped, 1);
    });

    testWidgets('AR records survive an app restart', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = MemoryLocalStore();
      final c = AppController(store: store);
      await c.init();
      c.loginWithPin('5678');
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      await tester.pumpWidget(
        host(
          c,
          CameraArScreen(
            shopId: shop.id,
            boardId: b.id,
            unitId: b.units.first.id,
            platform: FakeAr(png: Uint8List.fromList([1, 2])),
            writer: (png, folder) async => '/fake/$folder/x.png',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ar-gesture-layer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ar_capture')));
      await tester.pumpAndSettle();
      await c.flush();
      final again = AppController(store: store);
      await again.init();
      final saved = again.board(shop.id, b.id)!.previews.single;
      expect(saved.kind, CaptureKind.ar);
      expect(saved.info['mediaCode'], b.mediaCode);
      expect(saved.path, '/fake/ar/x.png');
    });

    testWidgets('unsupported device opens Live Preview (or explains)', (
      tester,
    ) async {
      final c = await boot(tester);
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      await tester.pumpWidget(
        host(
          c,
          CameraArScreen(
            shopId: shop.id,
            boardId: b.id,
            unitId: b.units.first.id,
            platform: FakeAr(support: ArSupport.unsupported),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Camera AR is not supported on this device.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('ar_open_live')));
      await tester.pumpAndSettle();
      // The seeded board has a photo → photo workspace on Live Preview.
      expect(find.byType(PhotoWorkspaceScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('save_live_preview')), findsOneWidget);
    });

    testWidgets('no site photos: clear message instead of Live Preview', (
      tester,
    ) async {
      final c = await boot(tester);
      final shop = c.shop('s_lakshmi')!;
      final b = c.addBoard(shop.id)
        ..mediaCode = SignageCatalog.singleStandee
        ..installationCode = SignageCatalog.freeStanding
        ..width = 3
        ..height = 5;
      await tester.pumpWidget(
        host(
          c,
          CameraArScreen(
            shopId: shop.id,
            boardId: b.id,
            unitId: b.units.first.id,
            platform: FakeAr(support: ArSupport.unsupported),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ar_open_live')));
      await tester.pump();
      expect(
        find.text(
          'No site photos available. Capture a site photo to continue.',
        ),
        findsOneWidget,
      );
      expect(find.byType(PhotoWorkspaceScreen), findsNothing);
    });

    testWidgets('services missing → install button → AR starts', (
      tester,
    ) async {
      final c = await boot(tester);
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      final ar = FakeAr(support: ArSupport.notInstalled);
      await tester.pumpWidget(
        host(
          c,
          CameraArScreen(
            shopId: shop.id,
            boardId: b.id,
            unitId: b.units.first.id,
            platform: ar,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ar-services-missing')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ar_install')));
      await tester.pumpAndSettle();
      expect(ar.installs, 1);
      expect(find.byKey(const ValueKey('fake-ar-view')), findsOneWidget);
    });

    testWidgets('permission denied and engine errors are explained', (
      tester,
    ) async {
      final c = await boot(tester);
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      final ar = FakeAr(permission: ArPermission.permanentlyDenied);
      await tester.pumpWidget(
        host(
          c,
          CameraArScreen(
            shopId: shop.id,
            boardId: b.id,
            unitId: b.units.first.id,
            platform: ar,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ar-permission')), findsOneWidget);
      expect(find.text('Open app settings'), findsOneWidget);

      ar
        ..permission = ArPermission.granted
        ..startError = const ArStartException('model', 'Model failed');
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ar-error')), findsOneWidget);
      expect(find.text('Model failed'), findsOneWidget);
      ar.startError = null;
      await tester.tap(find.byKey(const ValueKey('ar_retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fake-ar-view')), findsOneWidget);
    });

    testWidgets('workspace AR tab still works with a fake engine', (
      tester,
    ) async {
      final c = await boot(tester);
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      await tester.pumpWidget(
        host(
          c,
          PhotoWorkspaceScreen(
            shopId: shop.id,
            boardId: b.id,
            photoId: b.photos.first.id,
            initialTab: 2,
            arPlatform: FakeAr(png: Uint8List.fromList([5])),
            writer: (png, folder) async => '/fake/$folder/w.png',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ar-gesture-layer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ar_capture')));
      await tester.pumpAndSettle();
      final rec = b.previews.single;
      expect(rec.kind, CaptureKind.ar);
      expect(rec.photoId, b.photos.first.id);
    });
  });
}
