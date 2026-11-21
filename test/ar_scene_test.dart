import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/ar/ar_model_builder.dart';
import 'package:signage_recce/features/ar/ar_preview_tab.dart';
import 'package:signage_recce/features/ar/ar_scene_controller.dart';
import 'package:signage_recce/features/ar/ar_scene_engine.dart';
import 'package:signage_recce/features/ar/ar_scene_items.dart';
import 'package:signage_recce/features/ar/ar_session_controller.dart';
import 'package:signage_recce/features/ar/camera_ar_screen.dart';
import 'package:signage_recce/features/ar/native_ar_platform.dart';
import 'package:signage_recce/state/app_controller.dart';

// -----------------------------------------------------------------------------
// Fake multi-object AR engine (no camera, no ARCore). Exercises the Dart
// state machine and UI only – never counts as device verification.
// -----------------------------------------------------------------------------

class FakeObj {
  FakeObj(this.key, this.pose, this.surface);

  String key;
  List<double> pose;
  String surface;
  ArObjectTransform transform = const ArObjectTransform();
  bool visible = true;
}

class FakeSceneAr implements ArPlatform, ArSceneEngine {
  FakeSceneAr({this.png, this.surface = 'vertical'});

  Uint8List? png;
  String surface;
  bool placeOk = true;
  String failReason = 'no_surface';
  bool registerOk = true;
  String? hitId;
  int started = 0;
  int stopped = 0;
  int poseSeq = 0;
  bool indicator = false;
  String? selected;
  final registered = <String, ArModelData>{};
  final registerCalls = <String>[];
  final objects = <String, FakeObj>{};
  final transformCalls = <String>[];
  final anchorCalls = <String>[];
  final _events = StreamController<ArEvent>.broadcast();

  void emit(String type, [Map<String, Object?> data = const {}]) =>
      _events.add(ArEvent(type, data));

  // ArPlatform ---------------------------------------------------------------
  @override
  String get engineName => 'fake-scene';
  @override
  Stream<ArEvent> get events => _events.stream;
  @override
  Future<ArSupport> checkSupport() async => ArSupport.supported;
  @override
  Future<ArInstallResult> requestInstall() async => ArInstallResult.installed;
  @override
  Future<ArPermission> requestCameraPermission() async => ArPermission.granted;
  @override
  Future<void> startSession(ArModelSpec model) async => started++;
  @override
  Future<void> stopSession() async => stopped++;
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<ArPlaceResult> placeModel(Offset p, {bool manual = false}) async =>
      const ArPlaceResult(placed: false, reason: 'unused');
  @override
  Future<void> updateTransform(ArModelTransform t) async {}
  @override
  Future<void> removePlacement() async {}
  @override
  Future<void> setPlanesVisible(bool visible) async {}
  @override
  Future<Uint8List?> captureScene() async => png;
  @override
  Widget buildView(BuildContext context) =>
      const ColoredBox(color: Colors.black, key: ValueKey('fake-ar-view'));

  // ArSceneEngine ------------------------------------------------------------
  @override
  bool get supportsMultipleObjects => true;

  @override
  Future<bool> registerModel(String key, ArModelData model) async {
    registerCalls.add(key);
    if (registerOk) registered[key] = model;
    return registerOk;
  }

  List<double> _pose() => [(++poseSeq).toDouble(), 0, 0, 0, 0, 0, 1];

  @override
  Future<ArObjectPlaceResult> placeObject(
    String id,
    String modelKey,
    Offset p, {
    bool manual = false,
  }) async {
    if (!placeOk) return ArObjectPlaceResult(placed: false, reason: failReason);
    final model = registered[modelKey];
    if (model == null) {
      return const ArObjectPlaceResult(placed: false, reason: 'no_model');
    }
    final s = manual
        ? 'manual'
        : (model.preferVertical ? surface : 'horizontal');
    final pose = _pose();
    final o = objects[id];
    if (o == null) {
      objects[id] = FakeObj(modelKey, pose, s);
    } else {
      o
        ..pose = pose
        ..surface = s;
    }
    return ArObjectPlaceResult(placed: true, surface: s, pose: pose);
  }

  @override
  Future<ArObjectPlaceResult> anchorObject(
    String id,
    String modelKey,
    List<double> pose,
    String surface,
  ) async {
    anchorCalls.add(id);
    final o = objects[id];
    if (o == null) {
      objects[id] = FakeObj(modelKey, pose, surface);
    } else {
      o.pose = pose;
    }
    return ArObjectPlaceResult(placed: true, surface: surface, pose: pose);
  }

  @override
  Future<void> setObjectTransform(String id, ArObjectTransform t) async {
    transformCalls.add(id);
    objects[id]?.transform = t;
  }

  @override
  Future<void> setObjectVisible(String id, bool visible) async =>
      objects[id]?.visible = visible;

  @override
  Future<void> selectObject(String? id) async => selected = id;

  @override
  Future<void> removeObject(String id) async => objects.remove(id);

  @override
  Future<String?> hitTestObject(Offset p) async => hitId;

  @override
  Future<void> setPlacementIndicator(
    bool active, {
    bool preferVertical = false,
  }) async => indicator = active;
}

// -----------------------------------------------------------------------------
// Fixtures
// -----------------------------------------------------------------------------

Board _board(
  String id, {
  String? media = SignageCatalog.gsb,
  String? inst = SignageCatalog.wallMount,
  double w = 8,
  double h = 3,
  int quantity = 1,
}) => Board(
  id: id,
  name: id,
  mediaCode: media,
  installationCode: inst,
  width: w,
  height: h,
  quantity: quantity,
);

ArModelSpec _spec(Board b) {
  final g = buildArModel(b, b.units.first);
  return ArModelSpec(
    mediaCode: g.mediaCode,
    installationCode: g.installationCode,
    widthFt: 8,
    heightFt: 3,
    label: 'GSB',
    unitId: g.unitId,
    geometry: g,
  );
}

class Rig {
  Rig._(this.ar, this.session, this.scene, this.gsb, this.standee, this.items);

  final FakeSceneAr ar;
  final ArSessionController session;
  final ArSceneController scene;
  final Board gsb;
  final Board standee;
  final List<ArSceneItem> items;

  ArSceneItem item(String unitId) =>
      items.firstWhere((i) => i.unitId == unitId);
  ArSceneItem get gsbItem => item(gsb.units.first.id);
  ArSceneItem get standeeItem => item(standee.units.first.id);

  Future<ArPlacement> insert(ArSceneItem i, {bool duplicate = false}) async {
    scene.armInsert(i, previewDuplicate: duplicate);
    final ok = await scene.handleTap(const Offset(0.5, 0.5));
    expect(ok, isTrue, reason: scene.message);
    return scene.selected!;
  }

  static Future<Rig> open({FakeSceneAr? engine}) async {
    final gsb = _board('gsb', quantity: 2);
    final standee = _board(
      'std',
      media: SignageCatalog.doubleStandee,
      inst: SignageCatalog.freeStanding,
      w: 3,
      h: 5,
    );
    final ar = engine ?? FakeSceneAr(png: Uint8List.fromList([1, 2, 3]));
    final session = ArSessionController(platform: ar, model: _spec(gsb));
    var n = 0;
    final scene = ArSceneController(
      engine: ar,
      session: session,
      newPlacementId: () => 'p${++n}',
      clock: () => DateTime(2026, 11, 18, 10),
    );
    final items = [
      for (final b in [gsb, standee])
        for (final u in b.activeUnits) arSceneItemFor(b, u),
    ];
    await scene.setItems(items);
    await session.open();
    return Rig._(ar, session, scene, gsb, standee, items);
  }
}

void main() {
  // ---------------------------------------------------------------------------
  group('B. Model insertion', () {
    test('16/20/21 insert GSB: wall surface, item + placement ids', () async {
      final r = await Rig.open();
      final p = await r.insert(r.gsbItem);
      expect(p.unitId, r.gsb.units.first.id);
      expect(p.groupId, 'gsb');
      expect(p.placementId, 'p1');
      expect(p.placementId, isNot(p.unitId));
      expect(p.surface, 'vertical');
      expect(p.rotationAxis, ArRotationAxis.roll);
      expect(r.ar.objects.keys, ['p1']);
      expect(r.ar.registered.keys, [r.gsb.units.first.id]);
      expect(r.session.phase, ArPhase.placed);
      expect(r.scene.status, ArSceneStatus.modelSelected);
    });

    test('17 insert standee: horizontal surface, yaw rotation', () async {
      final r = await Rig.open();
      final p = await r.insert(r.standeeItem);
      expect(p.surface, 'horizontal');
      expect(p.rotationAxis, ArRotationAxis.yaw);
      expect(p.doubleSided, isTrue);
      expect(r.standeeItem.preferVertical, isFalse);
    });

    test('18/19 two media types and several items in one scene', () async {
      final r = await Rig.open();
      final a = await r.insert(r.gsbItem);
      final b = await r.insert(r.standeeItem);
      final c = await r.insert(r.item(r.gsb.units[1].id));
      expect(r.scene.placements.map((p) => p.placementId), ['p1', 'p2', 'p3']);
      expect({a.unitId, b.unitId, c.unitId}, hasLength(3));
      expect(r.ar.objects, hasLength(3));
      // One shared model per signage item; never per placement.
      expect(r.ar.registered, hasLength(3));
      expect(r.scene.physicalUnitCount, 3);
    });

    test('22 unsupported media: no 3D model, insert refused', () async {
      final b = _board('x', media: null, inst: null);
      final item = arSceneItemFor(b, b.units.first);
      expect(item.modelAvailable, isFalse);
      expect(item.unavailableReason, 'Media type not selected');
      final r = await Rig.open();
      expect(r.scene.checkInsert(item), ArInsertCheck.unavailable);
    });

    test('23 duplicate insertion prevention', () async {
      final r = await Rig.open();
      expect(r.scene.checkInsert(r.gsbItem), ArInsertCheck.ok);
      await r.insert(r.gsbItem);
      expect(r.scene.checkInsert(r.gsbItem), ArInsertCheck.alreadyPlaced);
      // Explicit preview duplicate is allowed and does not count as a unit.
      final d = await r.insert(r.gsbItem, duplicate: true);
      expect(d.previewDuplicate, isTrue);
      expect(d.duplicateOf, 'p1');
      expect(r.scene.physicalUnitCount, 1);
      expect(r.gsb.quantity, 2);
    });

    test('failed placement explains and offers the fallback', () async {
      final r = await Rig.open();
      r.ar.placeOk = false;
      r.scene.armInsert(r.gsbItem);
      expect(await r.scene.handleTap(const Offset(0.5, 0.5)), isFalse);
      expect(r.scene.message, contains('No wall found'));
      expect(r.scene.message, contains('Live Preview'));
      expect(r.scene.lastPlaceFailure, 'no_surface');
      expect(r.scene.placements, isEmpty);
      expect(r.scene.awaitingPlacement, isTrue);
      // Manual (instant) placement for glass.
      r.ar.placeOk = true;
      r.session.setManualPlacement(true);
      await r.scene.handleTap(const Offset(0.5, 0.5));
      expect(r.scene.selected!.surface, 'manual');
    });

    test('model load failure is reported, not silently placed', () async {
      final r = await Rig.open();
      r.ar.registerOk = false;
      r.scene.armInsert(r.gsbItem);
      expect(await r.scene.handleTap(const Offset(0.5, 0.5)), isFalse);
      expect(r.scene.message, contains('could not be loaded'));
    });

    test('placement indicator follows insert / cancel', () async {
      final r = await Rig.open();
      r.scene.armInsert(r.gsbItem);
      await pumpEventQueue();
      expect(r.ar.indicator, isTrue);
      expect(r.scene.status, ArSceneStatus.scanning);
      r.ar.emit('reticle', {'hit': true, 'surface': 'vertical'});
      await pumpEventQueue();
      expect(r.scene.status, ArSceneStatus.readyToPlace);
      r.scene.cancelPlacement();
      await pumpEventQueue();
      expect(r.ar.indicator, isFalse);
    });

    test('single-model engines: one model only', () async {
      final b = _board('g');
      final legacy = LegacyArSceneEngine(
        const UnavailableArPlatform(),
        sessionModelKey: b.units.first.id,
      );
      expect(legacy.supportsMultipleObjects, isFalse);
      expect(
        await legacy.registerModel('other', buildArModel(b, b.units.first)),
        isFalse,
      );
      final r = await legacy.placeObject('p', 'other', Offset.zero);
      expect(r.reason, 'single_object');
    });
  });

  // ---------------------------------------------------------------------------
  group('C. Scaling', () {
    late Rig r;
    setUp(() async {
      r = await Rig.open();
      await r.insert(r.gsbItem);
    });

    double scale() => r.scene.selected!.transform.scale;

    test('24–29 default 100 %, 50 / 150 / 300 %, bounds', () async {
      expect(scale(), 1);
      expect(r.scene.selected!.transform.scalePercent, 100);
      await r.scene.setScale(0.5);
      expect(scale(), 0.5);
      await r.scene.setScale(1.5);
      expect(scale(), 1.5);
      expect(r.ar.objects['p1']!.transform.scale, 1.5);
      await r.scene.setScale(3);
      expect(scale(), 3);
      await r.scene.setScale(0.01);
      expect(scale(), ArObjectTransform.minScale);
      expect(ArObjectTransform.minScale, 0.1);
      await r.scene.setScale(9);
      expect(scale(), ArObjectTransform.maxScale);
      expect(ArObjectTransform.maxScale, 3.0);
    });

    test('30/61 pinch updates scale; one gesture = one undo step', () async {
      r.scene.beginGesture();
      for (var i = 0; i < 10; i++) {
        await r.scene.scaleBy(1.05);
      }
      r.scene.endGesture('Scale');
      expect(scale(), closeTo(1.6289, 1e-3));
      expect(r.ar.objects['p1']!.transform.scale, closeTo(1.6289, 1e-3));
      expect(r.scene.history.map((e) => e.label), [
        'Insert GSB – Unit 01',
        'Scale',
      ]);
    });

    test('31 slider updates the rendered model', () async {
      r.scene.beginGesture();
      await r.scene.setScale(1.2);
      await r.scene.setScale(1.4);
      r.scene.endGesture('Scale');
      expect(r.ar.objects['p1']!.transform.scale, 1.4);
      expect(r.scene.history, hasLength(2));
    });

    test('32 plus / minus steps (5 %, fine 1 %)', () async {
      await r.scene.stepScale(1);
      expect(scale(), closeTo(1.05, 1e-9));
      await r.scene.stepScale(-1);
      await r.scene.stepScale(-1);
      expect(scale(), closeTo(0.95, 1e-9));
      r.scene.setFineSteps(true);
      await r.scene.stepScale(1);
      expect(scale(), closeTo(0.96, 1e-9));
    });

    test('33 numeric input validation', () async {
      expect(ArSceneController.validateScaleInput('abc'), isNotNull);
      expect(ArSceneController.validateScaleInput('5'), contains('10–300'));
      expect(ArSceneController.validateScaleInput('301'), isNotNull);
      expect(ArSceneController.validateScaleInput('120%'), isNull);
      expect(await r.scene.setScalePercentText('400'), isNotNull);
      expect(scale(), 1);
      expect(await r.scene.setScalePercentText('125'), isNull);
      expect(scale(), 1.25);
    });

    test(
      '34/35 reset scale keeps position + rotation; dimensions untouched',
      () async {
        await r.scene.nudge(ArMoveAxis.lateral, 1);
        await r.scene.rotateByDegrees(10);
        await r.scene.setScale(1.5);
        expect(r.scene.selected!.transform.scaleAdjusted, isTrue);
        await r.scene.resetScale();
        final t = r.scene.selected!.transform;
        expect(t.scale, 1);
        expect(t.x, closeTo(0.05, 1e-9));
        expect(t.roll, closeTo(10 * 3.141592653589793 / 180, 1e-9));
        // Recce measurements never change through preview scale.
        expect(r.gsb.width, 8);
        expect(r.gsb.height, 3);
        expect(r.gsbItem.sizeText, '8 × 3 ft');
        expect(r.scene.selected!.sizeText, '8 × 3 ft');
      },
    );

    test('36 scale is independent per object', () async {
      await r.insert(r.standeeItem);
      await r.scene.setScale(2);
      expect(r.scene.byId('p2')!.transform.scale, 2);
      expect(r.scene.byId('p1')!.transform.scale, 1);
      expect(r.ar.objects['p1']!.transform.scale, 1);
    });

    test('fit to entered dimensions regenerates the model at 100 %', () async {
      await r.scene.setScale(2);
      await r.scene.fitToDimensions();
      expect(scale(), 1);
    });
  });

  // ---------------------------------------------------------------------------
  group('D. Move & rotate', () {
    late Rig r;
    setUp(() async {
      r = await Rig.open();
      await r.insert(r.gsbItem); // p1: wall
      await r.insert(r.standeeItem); // p2: ground
    });

    test('37/41/44 fine move of the selected object only', () async {
      r.scene.select('p1');
      r.scene.setMoveStep(0.10);
      await r.scene.nudge(ArMoveAxis.lateral, 1);
      await r.scene.nudge(ArMoveAxis.vertical, -1);
      final t = r.scene.byId('p1')!.transform;
      expect(t.x, closeTo(0.1, 1e-9));
      expect(t.y, closeTo(-0.1, 1e-9));
      expect(r.scene.byId('p2')!.transform, const ArObjectTransform());
      expect(r.ar.objects['p1']!.transform.x, closeTo(0.1, 1e-9));
    });

    test('wall signs stay on the wall unless free adjustment', () async {
      r.scene.select('p1');
      expect(await r.scene.nudge(ArMoveAxis.depth, 1), isFalse);
      expect(r.scene.message, contains('Free adjustment'));
      r.scene.setFreeAdjust(true);
      expect(await r.scene.nudge(ArMoveAxis.depth, 1), isTrue);
      // Ground sign: no lifting without free adjustment.
      r.scene
        ..setFreeAdjust(false)
        ..select('p2');
      expect(r.scene.allowedMoveAxes(), {ArMoveAxis.lateral, ArMoveAxis.depth});
    });

    test('38/50/51 lock prevents move, rotate, scale; unlock allows', () async {
      r.scene.select('p2');
      r.scene.setLocked('p2', true);
      expect(await r.scene.nudge(ArMoveAxis.lateral, 1), isFalse);
      expect(await r.scene.rotateByDegrees(10), isFalse);
      expect(await r.scene.setScale(2), isFalse);
      expect(r.scene.beginDrag(), isFalse);
      expect(await r.scene.remove('p2'), isFalse);
      expect(r.scene.message, contains('locked'));
      expect(r.scene.byId('p2')!.transform, const ArObjectTransform());
      r.scene.setLocked('p2', false);
      expect(await r.scene.setScale(2), isTrue);
    });

    test('39/40 rotate (5° / fine 1°), numeric, reset', () async {
      r.scene.select('p2');
      await r.scene.stepRotation(-1); // counter-clockwise
      expect(r.scene.selected!.rotationDeg, closeTo(5, 1e-9));
      r.scene.setFineSteps(true);
      await r.scene.stepRotation(1);
      expect(r.scene.selected!.rotationDeg, closeTo(4, 1e-9));
      expect(await r.scene.setRotationText('200'), isNotNull);
      expect(await r.scene.setRotationText('-90'), isNull);
      expect(r.scene.selected!.rotationDeg, closeTo(-90, 1e-9));
      expect(r.ar.objects['p2']!.transform.yaw, closeTo(-1.5708, 1e-4));
      await r.scene.resetRotation();
      expect(r.scene.selected!.transform.yaw, 0);
    });

    test('double-sided standee: view the other face', () async {
      r.scene.select('p2');
      await r.scene.flipFace();
      expect(r.scene.selected!.rotationDeg.abs(), closeTo(180, 1e-9));
      r.scene.select('p1');
      expect(await r.scene.flipFace(), isFalse);
    });

    test('wall sign rotates flat on the wall (roll), not yaw', () async {
      r.scene.select('p1');
      await r.scene.rotateByDegrees(15);
      expect(r.scene.selected!.transform.yaw, 0);
      expect(r.scene.selected!.transform.roll, isNot(0));
    });

    test('flange boards cannot rotate', () async {
      final b = _board(
        'f',
        media: SignageCatalog.flange,
        inst: SignageCatalog.flangeBracket,
      );
      final item = arSceneItemFor(b, b.units.first);
      await r.scene.setItems([...r.items, item]);
      await r.insert(item);
      expect(r.scene.selected!.rotationAxis, ArRotationAxis.none);
      expect(await r.scene.rotateByDegrees(10), isFalse);
    });

    test('42/43 re-anchor request and reset position', () async {
      r.scene.select('p1');
      await r.scene.nudge(ArMoveAxis.lateral, 1);
      final oldPose = r.scene.selected!.pose;
      expect(r.scene.requestReanchor(), isTrue);
      expect(r.scene.awaitingPlacement, isTrue);
      await r.scene.handleTap(const Offset(0.2, 0.3));
      expect(r.scene.selected!.pose, isNot(oldPose));
      expect(r.scene.awaitingPlacement, isFalse);
      // Offsets survive re-anchoring; reset position clears them only.
      expect(r.scene.selected!.transform.x, closeTo(0.05, 1e-9));
      await r.scene.setScale(1.5);
      await r.scene.resetPosition();
      expect(r.scene.selected!.transform.x, 0);
      expect(r.scene.selected!.transform.scale, 1.5);
    });

    test('drag-to-move re-anchors via hit test as one undo step', () async {
      r.scene.select('p2');
      final before = r.scene.selected!.pose;
      expect(r.scene.beginDrag(), isTrue);
      expect(r.scene.status, ArSceneStatus.modelMoving);
      await r.scene.dragTo(const Offset(0.4, 0.6));
      await r.scene.dragTo(const Offset(0.5, 0.7));
      r.scene.endDrag();
      expect(r.scene.selected!.pose, isNot(before));
      expect(r.scene.history.last.label, 'Move');
      // Undo restores the previous anchor pose.
      await r.scene.undo();
      expect(r.scene.byId('p2')!.pose, before);
      expect(r.ar.objects['p2']!.pose, before);
    });

    test('Move tool: tap on empty surface re-anchors the selection', () async {
      r.scene.select('p2');
      r.scene.setTool(ArTool.move);
      final before = r.scene.selected!.pose;
      expect(await r.scene.handleTap(const Offset(0.1, 0.9)), isTrue);
      expect(r.scene.selected!.pose, isNot(before));
    });
  });

  // ---------------------------------------------------------------------------
  group('E. Multiple objects', () {
    late Rig r;
    setUp(() async {
      r = await Rig.open();
      await r.insert(r.gsbItem);
      await r.insert(r.standeeItem);
    });

    test('45/46/47 select A / B by tapping; edit A independently', () async {
      r.ar.hitId = 'p1';
      await r.scene.handleTap(const Offset(0.3, 0.3));
      expect(r.scene.selectedId, 'p1');
      expect(r.ar.selected, 'p1');
      r.ar.hitId = 'p2';
      await r.scene.handleTap(const Offset(0.7, 0.7));
      expect(r.scene.selectedId, 'p2');
      r.scene.select('p1');
      await r.scene.setScale(0.5);
      expect(r.scene.byId('p2')!.transform.scale, 1);
    });

    test('48/49 hide / show (engine + capture visibility)', () async {
      await r.scene.setVisible('p1', false);
      expect(r.ar.objects['p1']!.visible, isFalse);
      expect(r.scene.visibleAnchored.map((p) => p.placementId), ['p2']);
      await r.scene.setVisible('p2', false);
      expect(r.session.phase, ArPhase.scanning);
      expect(r.session.canCapture, isFalse);
      await r.scene.setVisible('p1', true);
      expect(r.session.canCapture, isTrue);
    });

    test('52/54 duplicate preview keeps quantity / records', () async {
      r.scene.select('p1');
      final qty = r.gsb.quantity;
      final units = r.gsb.units.length;
      await r.scene.duplicateSelected();
      final d = r.scene.selected!;
      expect(d.previewDuplicate, isTrue);
      expect(d.displayName, contains('Preview Duplicate'));
      expect(d.unitId, r.gsb.units.first.id);
      expect(d.placementId, isNot('p1'));
      expect(d.isAnchored, isTrue);
      expect(r.ar.anchorCalls, [d.placementId]);
      expect(d.transform.x, greaterThan(2.4)); // beside the original
      expect(r.gsb.quantity, qty);
      expect(r.gsb.units.length, units);
      expect(r.scene.physicalUnitCount, 2);
      // Duplicates can be deleted individually.
      await r.scene.remove(d.placementId);
      expect(r.scene.placements.map((p) => p.placementId), ['p1', 'p2']);
    });

    test('53 delete the selected placement only', () async {
      r.scene.select('p2');
      await r.scene.removeSelected();
      expect(r.scene.placements.map((p) => p.placementId), ['p1']);
      expect(r.ar.objects.keys, ['p1']);
      expect(r.scene.selected, isNull);
      // Signage item itself is untouched.
      expect(r.standee.units, hasLength(1));
    });

    test('no selection: transform controls refuse with a hint', () async {
      r.scene.select(null);
      expect(r.scene.canEditSelected, isFalse);
      expect(await r.scene.setScale(2), isFalse);
      expect(r.scene.message, contains('Select a model'));
    });

    test('switching tools never modifies the model', () async {
      r.scene.select('p1');
      final before = r.scene.selected!.transform;
      for (final t in ArTool.values) {
        r.scene.setTool(t);
      }
      expect(r.scene.selected!.transform, before);
      expect(r.scene.history, hasLength(2));
    });
  });

  // ---------------------------------------------------------------------------
  group('F. Undo / redo', () {
    late Rig r;
    setUp(() async {
      r = await Rig.open();
      await r.insert(r.gsbItem);
    });

    test('55 undo / redo insertion', () async {
      await r.scene.undo();
      expect(r.scene.placements, isEmpty);
      expect(r.ar.objects, isEmpty);
      expect(r.session.phase, ArPhase.scanning);
      await r.scene.redo();
      expect(r.scene.placements.single.placementId, 'p1');
      expect(r.ar.objects.keys, ['p1']);
      expect(r.session.phase, ArPhase.placed);
    });

    test('56/60 undo / redo movement', () async {
      await r.scene.nudge(ArMoveAxis.lateral, 1);
      await r.scene.undo();
      expect(r.scene.selected!.transform.x, 0);
      expect(r.ar.objects['p1']!.transform.x, 0);
      await r.scene.redo();
      expect(r.scene.selected!.transform.x, closeTo(0.05, 1e-9));
    });

    test('57 undo rotation', () async {
      await r.scene.rotateByDegrees(30);
      await r.scene.undo();
      expect(r.scene.selected!.rotationDeg, 0);
    });

    test('58/59 undo / redo scaling', () async {
      await r.scene.setScale(2);
      await r.scene.undo();
      expect(r.scene.selected!.transform.scale, 1);
      await r.scene.redo();
      expect(r.scene.selected!.transform.scale, 2);
      expect(r.ar.objects['p1']!.transform.scale, 2);
    });

    test('62 a new edit clears redo', () async {
      await r.scene.setScale(2);
      await r.scene.undo();
      expect(r.scene.canRedo, isTrue);
      await r.scene.rotateByDegrees(5);
      expect(r.scene.canRedo, isFalse);
    });

    test('undo removal re-creates the object at its pose', () async {
      final pose = r.scene.selected!.pose;
      await r.scene.removeSelected();
      await r.scene.undo();
      expect(r.scene.byId('p1')!.isAnchored, isTrue);
      expect(r.ar.objects['p1']!.pose, pose);
    });

    test('undo / redo of duplicate', () async {
      await r.scene.duplicateSelected();
      expect(r.scene.placements, hasLength(2));
      await r.scene.undo();
      expect(r.scene.placements, hasLength(1));
      await r.scene.redo();
      expect(r.scene.placements.last.previewDuplicate, isTrue);
    });

    test('AR edit history is separate from the recce activity log', () async {
      final c = AppController(store: MemoryLocalStore());
      await c.init();
      final before = c.data.activities.length;
      await r.scene.setScale(2);
      await r.scene.undo();
      expect(c.data.activities.length, before);
    });
  });

  // ---------------------------------------------------------------------------
  group('G. Layouts & captures (data)', () {
    test('63/64/65/74 save layout, reload after restart', () async {
      final store = MemoryLocalStore();
      final c = AppController(store: store);
      await c.init();
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      final r = await Rig.open();
      final items = arSceneItemsForShop(shop);
      await r.scene.setItems(items);
      await r.insert(items.first);
      await r.scene.setScale(1.5);
      await r.scene.rotateByDegrees(20);
      r.scene.setLocked('p1', true);
      final layout = r.scene.toLayout(id: 'L1', name: 'Front view', shop: shop);
      c.saveArLayout(layout);
      await c.flush();

      final again = AppController(store: store);
      await again.init();
      final saved = again.arLayoutsForShop(shop.id).single;
      expect(saved.name, 'Front view');
      expect(saved.projectId, shop.projectId);
      expect(saved.taskId, shop.taskId);
      expect(saved.shopId, shop.id);
      final o = saved.objects.single;
      expect(o.placementId, 'p1');
      expect(o.signageItemId, b.units.first.id);
      expect(o.groupId, b.id);
      expect(o.mediaCode, b.mediaCode);
      expect(o.scaleMultiplier, 1.5);
      expect(o.transform['yaw'], closeTo(20 * 3.141592653589793 / 180, 1e-9));
      expect(o.locked, isTrue);
      expect(o.visible, isTrue);
      expect(o.modelConfig['widthFt'], isNotNull);
      expect(o.savedAt, DateTime(2026, 11, 18, 10));
      // Business data untouched.
      expect(again.board(shop.id, b.id)!.units.length, b.units.length);
    });

    test('multiple layouts per shop; update in place', () async {
      final c = AppController(store: MemoryLocalStore());
      await c.init();
      final shop = c.shop('s_sriranga')!;
      for (final id in ['A', 'B']) {
        c.saveArLayout(
          ArLayout(
            id: id,
            name: id,
            projectId: shop.projectId,
            taskId: shop.taskId,
            shopId: shop.id,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026, 1, id == 'A' ? 1 : 2),
          ),
        );
      }
      expect(c.arLayoutsForShop(shop.id).map((l) => l.id), ['B', 'A']);
      c.saveArLayout(c.arLayout('A')!..updatedAt = DateTime(2026, 2));
      expect(c.arLayoutsForShop(shop.id).map((l) => l.id), ['A', 'B']);
      c.deleteArLayout('B');
      expect(c.arLayoutsForShop(shop.id), hasLength(1));
    });

    test('reopen layout: objects need re-anchoring, one by one', () async {
      final r = await Rig.open();
      await r.insert(r.gsbItem);
      await r.insert(r.standeeItem);
      await r.scene.setScale(2);
      final shop = Shop(id: 's', projectId: 'pr', taskId: 't', name: 'S');
      final layout = r.scene.toLayout(id: 'L', name: 'L', shop: shop);

      final r2 = await Rig.open();
      final res = await r2.scene.loadLayout(layout);
      expect(res.loaded, 2);
      expect(res.missing, isEmpty);
      expect(r2.scene.placements.every((p) => !p.isAnchored), isTrue);
      expect(r2.scene.reanchorId, 'p1');
      expect(r2.scene.message, contains('re-anchor'));
      expect(r2.session.canCapture, isFalse);
      await r2.scene.handleTap(const Offset(0.5, 0.5));
      expect(r2.scene.byId('p1')!.isAnchored, isTrue);
      expect(r2.scene.reanchorId, 'p2'); // next one armed automatically
      await r2.scene.handleTap(const Offset(0.5, 0.6));
      expect(r2.scene.byId('p2')!.transform.scale, 2);
      expect(r2.ar.objects['p2']!.transform.scale, 2);
      expect(r2.scene.awaitingPlacement, isFalse);
      expect(r2.scene.layoutId, 'L');
    });

    test('66 missing item references are skipped safely', () async {
      final r = await Rig.open();
      final layout = ArLayout(
        id: 'L',
        name: 'L',
        projectId: 'p',
        taskId: 't',
        shopId: 's',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        objects: [
          ArLayoutObject(
            placementId: 'x1',
            signageItemId: 'deleted_unit',
            groupId: 'g',
            mediaCode: 'GSB',
            installationCode: 'wall_mount',
            savedAt: DateTime(2026),
          ),
          ArLayoutObject(
            placementId: 'x2',
            signageItemId: r.gsb.units.first.id,
            groupId: 'gsb',
            mediaCode: 'GSB',
            installationCode: 'wall_mount',
            savedAt: DateTime(2026),
          ),
        ],
      );
      final res = await r.scene.loadLayout(layout);
      expect(res.missing, ['deleted_unit']);
      expect(r.scene.placements.single.placementId, 'x2');
    });

    test('older data (no AR layouts / new capture fields) loads', () {
      final c = PreviewCapture.fromJson({
        'id': 'c',
        'kind': 'ar',
        'unitId': 'u',
        'arTransform': {'yaw': 0.5, 'scale': 2},
      });
      expect(c.visibleUnitIds, isEmpty);
      expect(c.layoutId, isNull);
      expect(c.toJson().containsKey('visibleUnitIds'), isFalse);
      final o = ArLayoutObject.fromJson({
        'placementId': 'p',
        'signageItemId': 'u',
        'scaleMultiplier': 1.5,
      });
      expect(o.scaleMultiplier, 1.5);
      expect(o.visible, isTrue);
      expect(o.locked, isFalse);
      final data = AppData.fromJson({'users': [], 'shops': []});
      expect(data.arLayouts, isEmpty);
      expect(data.toJson().containsKey('arLayouts'), isFalse);
      final l = ArLayout.fromJson(jsonDecode(jsonEncode({'id': 'x'})));
      expect(l.objects, isEmpty);
    });

    test('deleting a unit / board prunes layouts and capture links', () async {
      final c = AppController(store: MemoryLocalStore());
      await c.init();
      c.loginWithPin('5678');
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      c.increaseQuantity(shop.id, b, 2);
      final u2 = b.units[1];
      c.saveArLayout(
        ArLayout(
          id: 'L',
          name: 'L',
          projectId: shop.projectId,
          taskId: shop.taskId,
          shopId: shop.id,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          objects: [
            for (final u in b.units)
              ArLayoutObject(
                placementId: 'p_${u.id}',
                signageItemId: u.id,
                groupId: b.id,
                mediaCode: 'GSB',
                installationCode: 'double_pole',
                savedAt: DateTime(2026),
              ),
          ],
        ),
      );
      c.addPreview(
        shop.id,
        b.id,
        PreviewCapture(
          id: 'cap',
          kind: CaptureKind.ar,
          projectId: shop.projectId,
          taskId: shop.taskId,
          shopId: shop.id,
          groupId: b.id,
          unitId: b.units.first.id,
          path: '/x.png',
          createdAt: DateTime(2026),
          visibleUnitIds: [b.units.first.id, u2.id],
        ),
      );
      await c.removeUnit(shop.id, b, u2.id);
      expect(c.arLayout('L')!.signageItemIds, {b.units.first.id});
      expect(b.previews.single.visibleUnitIds, [b.units.first.id]);
    });
  });

  // ---------------------------------------------------------------------------
  group('H. Tracking & lifecycle', () {
    test('78/79 tracking lost blocks placement and edits; recovers', () async {
      final r = await Rig.open();
      await r.insert(r.gsbItem);
      await r.scene.setScale(1.5);
      r.ar.emit('tracking', {'state': 'paused', 'reason': 'EXCESSIVE_MOTION'});
      await pumpEventQueue();
      expect(r.scene.status, ArSceneStatus.trackingLost);
      expect(r.scene.guidance, contains('Tracking lost'));
      expect(await r.scene.setScale(2), isFalse);
      r.scene.armInsert(r.standeeItem);
      expect(await r.scene.handleTap(const Offset(0.5, 0.5)), isFalse);
      // Last valid transform is preserved.
      expect(r.scene.byId('p1')!.transform.scale, 1.5);
      r.ar.emit('tracking', {'state': 'tracking', 'reason': 'NONE'});
      await pumpEventQueue();
      expect(await r.scene.handleTap(const Offset(0.5, 0.5)), isTrue);
      expect(r.scene.placements, hasLength(2));
    });

    test('anchor lost: object kept with its transform, re-anchor', () async {
      final r = await Rig.open();
      await r.insert(r.gsbItem);
      await r.scene.setScale(2);
      r.ar.emit('objectLost', {'id': 'p1'});
      await pumpEventQueue();
      final p = r.scene.byId('p1')!;
      expect(p.status, ArAnchorStatus.lost);
      expect(p.transform.scale, 2);
      expect(r.session.canCapture, isFalse);
      expect(r.scene.requestReanchor('p1'), isTrue);
      await r.scene.handleTap(const Offset(0.5, 0.5));
      expect(r.scene.byId('p1')!.isAnchored, isTrue);
      expect(r.session.canCapture, isTrue);
    });

    test('session restart: placements must be re-anchored', () async {
      final r = await Rig.open();
      await r.insert(r.gsbItem);
      r.ar.emit('error', {'code': 'camera', 'message': 'Camera in use'});
      await pumpEventQueue();
      expect(r.session.phase, ArPhase.error);
      await r.session.open();
      expect(r.scene.byId('p1')!.status, ArAnchorStatus.pending);
      expect(r.scene.reanchorId, 'p1');
    });

    test('item deleted from the draft: its placements are removed', () async {
      final r = await Rig.open();
      await r.insert(r.gsbItem);
      await r.insert(r.standeeItem);
      await r.scene.setItems([r.gsbItem]);
      expect(r.scene.placements.map((p) => p.unitId), [r.gsbItem.unitId]);
      expect(r.ar.objects.keys, ['p1']);
      expect(r.scene.message, contains('no longer exists'));
      expect(r.scene.canUndo, isFalse);
    });

    test('dimension change regenerates only that item\'s model', () async {
      final r = await Rig.open();
      await r.insert(r.gsbItem);
      await r.insert(r.standeeItem);
      r.ar.registerCalls.clear();
      r.standee.width = 4;
      await r.scene.setItems([
        for (final b in [r.gsb, r.standee])
          for (final u in b.activeUnits) arSceneItemFor(b, u),
      ]);
      expect(r.ar.registerCalls, [r.standee.units.first.id]);
      expect(r.scene.byId('p2')!.widthFt, 4);
      expect(r.scene.byId('p1')!.widthFt, 8);
    });

    test('80/82 dispose: no stale updates afterwards', () async {
      final r = await Rig.open();
      await r.insert(r.gsbItem);
      var notified = 0;
      r.scene.addListener(() => notified++);
      r.scene.dispose();
      r.ar.emit('objectLost', {'id': 'p1'});
      r.ar.emit('reticle', {'hit': true});
      await pumpEventQueue();
      expect(notified, 0);
      r.session.dispose();
      expect(r.ar.stopped, 1);
    });
  });

  // ---------------------------------------------------------------------------
  group('Native scene channel contract (mocked)', () {
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

    test('multi-object calls carry ids, transforms and poses', () async {
      mock(
        (c) => switch (c.method) {
          'registerModel' => true,
          'placeObject' => {
            'placed': true,
            'surface': 'vertical',
            'pose': [1, 2, 3, 0, 0, 0, 1],
          },
          'anchorObject' => {'placed': true, 'surface': 'horizontal'},
          'hitTestObject' => 'p9',
          _ => null,
        },
      );
      final p = NativeArPlatform();
      expect(sceneEngineFor(p), same(p));
      final b = _board('g');
      expect(
        await p.registerModel('u1', buildArModel(b, b.units.first)),
        isTrue,
      );
      expect((calls.last.arguments as Map)['key'], 'u1');
      expect(
        () => const StandardMessageCodec().encodeMessage(calls.last.arguments),
        returnsNormally,
      );
      final r = await p.placeObject('p1', 'u1', const Offset(0.2, 0.4));
      expect(r.placed, isTrue);
      expect(r.pose, [1, 2, 3, 0, 0, 0, 1]);
      expect(calls.last.arguments, {
        'id': 'p1',
        'key': 'u1',
        'x': 0.2,
        'y': 0.4,
        'manual': false,
      });
      final a = await p.anchorObject('p2', 'u1', [
        1,
        2,
        3,
        0,
        0,
        0,
        1,
      ], 'horizontal');
      expect(a.placed, isTrue);
      await p.setObjectTransform(
        'p1',
        const ArObjectTransform(x: 0.1, roll: 0.2, scale: 1.5),
      );
      expect(calls.last.arguments, {
        'id': 'p1',
        'x': 0.1,
        'y': 0.0,
        'z': 0.0,
        'yaw': 0.0,
        'roll': 0.2,
        'scale': 1.5,
      });
      await p.setObjectVisible('p1', false);
      expect(calls.last.arguments, {'id': 'p1', 'visible': false});
      await p.selectObject(null);
      expect(calls.last.arguments, {'id': null});
      expect(await p.hitTestObject(const Offset(0.5, 0.5)), 'p9');
      await p.setPlacementIndicator(true, preferVertical: true);
      expect(calls.last.arguments, {'active': true, 'vertical': true});
      await p.removeObject('p1');
      expect(calls.last.method, 'removeObject');
    });

    test('placement times out / no engine → clear failure', () async {
      final missing = await NativeArPlatform().placeObject(
        'p',
        'k',
        Offset.zero,
      );
      expect(missing.placed, isFalse);
      expect(missing.reason, 'no_engine');
      mock((c) => Completer<Object?>().future);
      final slow = NativeArPlatform(
        placeTimeout: const Duration(milliseconds: 30),
      );
      final r = await slow.placeObject('p', 'k', Offset.zero);
      expect(r.reason, 'timeout');
    });
  });

  // ---------------------------------------------------------------------------
  group('Camera AR editor (widgets, fake multi-object engine)', () {
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

    Future<void> tapCenter(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('ar-gesture-layer')));
      await tester.pumpAndSettle();
    }

    testWidgets('insert two media types, scale, capture, save layout', (
      tester,
    ) async {
      final c = await boot(tester);
      final shop = c.shop('s_sriranga')!;
      final gsb = shop.boards.first;
      final standee = c.addBoard(shop.id)
        ..mediaCode = SignageCatalog.singleStandee
        ..installationCode = SignageCatalog.freeStanding
        ..width = 3
        ..height = 5;
      final ar = FakeSceneAr(png: Uint8List.fromList([9, 9]));
      final paths = <String>[];
      await tester.pumpWidget(
        host(
          c,
          CameraArScreen(
            shopId: shop.id,
            boardId: gsb.id,
            unitId: gsb.units.first.id,
            platform: ar,
            writer: (png, folder) async {
              paths.add('/fake/$folder/${paths.length}.png');
              return paths.last;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ar_project_task')), findsOneWidget);
      expect(find.byKey(const ValueKey('ar_status')), findsOneWidget);
      expect(find.text('No model selected'), findsNothing);

      // The opened item is armed: one tap places it.
      await tapCenter(tester);
      expect(ar.objects, hasLength(1));
      expect(find.textContaining('GSB – Unit 01'), findsWidgets);

      // Insert Media → standee.
      await tester.tap(find.byKey(const ValueKey('ar_tool_insert')));
      await tester.pumpAndSettle();
      expect(find.text('Insert Media'), findsOneWidget);
      expect(find.text('Single-Sided Standee'), findsOneWidget);
      await tester.tap(
        find.byKey(ValueKey('ar_insert_${standee.units.first.id}')),
      );
      await tester.pumpAndSettle();
      await tapCenter(tester);
      expect(ar.objects, hasLength(2));

      // Re-inserting the GSB asks before making a preview duplicate.
      await tester.tap(find.byKey(const ValueKey('ar_tool_insert')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('ar_insert_${gsb.units.first.id}')));
      await tester.pumpAndSettle();
      expect(find.textContaining('already placed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ar_insert_duplicate')));
      await tester.pumpAndSettle();
      await tapCenter(tester);
      expect(ar.objects, hasLength(3));
      expect(gsb.quantity, 1);

      // Scale tool: plus button changes the rendered model.
      await tester.tap(find.byKey(const ValueKey('ar_tool_scale')));
      await tester.pumpAndSettle();
      expect(find.text('Scale: 100%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ar_scale_plus')));
      await tester.pumpAndSettle();
      expect(find.text('Scale: 105%'), findsOneWidget);
      expect(find.byKey(const ValueKey('ar_scale_warning')), findsOneWidget);
      expect(ar.objects.values.last.transform.scale, closeTo(1.05, 1e-9));
      expect(gsb.width, isNot(1.05)); // recce size untouched
      await tester.tap(find.byKey(const ValueKey('ar_scale_reset')));
      await tester.pumpAndSettle();
      expect(find.text('Scale: 100%'), findsOneWidget);

      // Undo restores 105 %.
      await tester.tap(find.byKey(const ValueKey('ar_undo')));
      await tester.pumpAndSettle();
      expect(find.text('Scale: 105%'), findsOneWidget);

      // Capture: all visible objects are linked.
      await tester.tap(find.byKey(const ValueKey('ar_capture')));
      await tester.pumpAndSettle();
      final cap = gsb.previews.singleWhere((p) => p.kind == CaptureKind.ar);
      expect(cap.visibleUnitIds.toSet(), {
        gsb.units.first.id,
        standee.units.first.id,
      });
      expect(cap.placementIds, hasLength(3));
      expect(cap.info['objectCount'], '3');
      expect(cap.shopId, shop.id);
      expect(cap.unitId, gsb.units.first.id);
      expect(find.byKey(const ValueKey('ar_saved')), findsOneWidget);

      // Second capture keeps the first.
      await tester.tap(find.byKey(const ValueKey('ar_capture')));
      await tester.pumpAndSettle();
      expect(gsb.previews.where((p) => p.kind == CaptureKind.ar), hasLength(2));

      // Save layout.
      await tester.tap(find.byKey(const ValueKey('ar_save_layout')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ar_layout_name')),
        'Entrance',
      );
      await tester.tap(find.byKey(const ValueKey('ar_layout_save')));
      await tester.pumpAndSettle();
      final layout = c.arLayoutsForShop(shop.id).single;
      expect(layout.name, 'Entrance');
      expect(layout.objects, hasLength(3));
      expect(layout.objects.where((o) => o.previewDuplicate), hasLength(1));

      // A later capture is linked to the saved layout.
      await tester.tap(find.byKey(const ValueKey('ar_capture')));
      await tester.pumpAndSettle();
      expect(gsb.previews.last.layoutId, layout.id);

      // Objects panel: hide one object.
      await tester.tap(find.byKey(const ValueKey('ar_objects')));
      await tester.pumpAndSettle();
      expect(find.text('Objects in AR scene (3)'), findsOneWidget);
      final firstId = ar.objects.keys.first;
      await tester.tap(find.byKey(ValueKey('ar_obj_vis_$firstId')));
      await tester.pumpAndSettle();
      expect(ar.objects[firstId]!.visible, isFalse);
      expect(find.textContaining('Hidden'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      expect(ar.stopped, 1);
    });

    testWidgets('capture failure keeps the scene and saves nothing', (
      tester,
    ) async {
      final c = await boot(tester);
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      final ar = FakeSceneAr();
      await tester.pumpWidget(
        host(
          c,
          CameraArScreen(
            shopId: shop.id,
            boardId: b.id,
            unitId: b.units.first.id,
            platform: ar,
            writer: (png, folder) async => '/fake/x.png',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapCenter(tester);
      await tester.tap(find.byKey(const ValueKey('ar_capture')));
      await tester.pumpAndSettle();
      expect(b.previews.where((p) => p.kind == CaptureKind.ar), isEmpty);
      expect(find.textContaining('could not capture'), findsWidgets);
      expect(ar.objects, hasLength(1));
    });

    testWidgets('read-only recce: preview editing only, no save / capture', (
      tester,
    ) async {
      final c = await boot(tester);
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      final ar = FakeSceneAr(png: Uint8List.fromList([1]));
      await tester.pumpWidget(
        host(
          c,
          Scaffold(
            body: ArPreviewTab(
              shopId: shop.id,
              boardId: b.id,
              unitId: b.units.first.id,
              platform: ar,
              editable: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapCenter(tester);
      expect(ar.objects, hasLength(1));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('ar_capture')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('ar_save_layout')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('ar_tool_dimensions')));
      await tester.pumpAndSettle();
      expect(find.text('Actual Dimensions (signage item)'), findsOneWidget);
      expect(find.text('Media Type'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('ar_edit_dimensions')),
            )
            .onPressed,
        isNull,
      );
    });
  });
}
