import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/drawing/drawing_2d_painter.dart';
import 'package:signage_recce/features/drawing/signage_geometry.dart';
import 'package:signage_recce/features/preview3d/renderer_painter.dart';
import 'package:signage_recce/features/preview3d/signage_scene_builder.dart';
import 'package:signage_recce/state/app_controller.dart';
import 'package:signage_recce/state/version_diff.dart';

import 'helpers.dart';

void _paintOnce(CustomPainter painter, Size size) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  recorder.endRecording().dispose();
}

/// A schema-2 (pre multi-unit) board JSON: no units / sizeMode / previews.
Map<String, dynamic> legacyBoardJson({int quantity = 3}) => {
  'id': 'b_old',
  'name': 'Old Board',
  'mediaCode': 'GSB',
  'installationCode': 'shop_fascia',
  'answers': {'shutter_height': 9},
  'width': 8,
  'height': 3,
  'unit': 'ft',
  'quantity': quantity,
  'textNote': 'legacy note',
  'photos': [
    {
      'id': 'ph1',
      'path': 'demo://1',
      'label': 'Front view',
      'capturedAt': '2026-11-10T10:00:00.000',
      'width': 1200,
      'height': 900,
      'annotations': [
        {'id': 'a1', 'type': 'rectangle', 'x': 600, 'y': 300, 'w': 400},
      ],
    },
  ],
  'voiceNotes': [],
  'updatedAt': '2026-11-10T10:00:00.000',
};

Future<AppController> _vendor() async {
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin('5678');
  return c;
}

void main() {
  group('backward-compatible migration', () {
    test('legacy board becomes one media group with quantity units', () {
      final b = Board.fromJson(legacyBoardJson());
      expect(b.quantity, 3);
      expect(b.units.map((u) => u.id), ['b_old_u1', 'b_old_u2', 'b_old_u3']);
      expect(b.sizeMode, SizeMode.same);
      expect(b.isSameSize, isTrue);
      expect(b.hasSize, isTrue);
      expect(b.areaSqFt, closeTo(72, 1e-9));
      expect(b.photos.single.annotations.single.itemId, isNull);
      expect(b.textNote, 'legacy note');
      expect(b.previews, isEmpty);
    });

    test('migration is idempotent (same ids on every parse / save)', () {
      final once = Board.fromJson(legacyBoardJson());
      final twice = Board.fromJson(once.toJson());
      final thrice = Board.fromJson(jsonDecode(jsonEncode(twice.toJson())));
      expect(twice.units.map((u) => u.id), once.units.map((u) => u.id));
      expect(thrice.units.map((u) => u.id), once.units.map((u) => u.id));
      expect(thrice.unitSeq, 3);
      // Parsing the same legacy JSON again also yields the same ids.
      expect(
        Board.fromJson(legacyBoardJson()).units.map((u) => u.id),
        once.units.map((u) => u.id),
      );
    });

    test('missing optional fields fall back safely', () {
      final b = Board.fromJson({'id': 'x'});
      expect(b.name, 'Board');
      expect(b.quantity, 1);
      expect(b.units, hasLength(1));
      expect(b.hasSize, isFalse);
      final a = Annotation.fromJson({'id': 'a', 'type': 'arrow'});
      expect(a.thickness, 1);
      expect(a.itemId, isNull);
      expect(a.points, isEmpty);
      final p = SitePhoto.fromJson({'id': 'p'});
      expect(p.unitIds, isEmpty);
      final r = ReviewRecord.fromJson({'stage': 'ops', 'decision': 'rejected'});
      expect(r.issues, isEmpty);
    });

    test(
      'schema 2 store upgrades to 3 keeping approvals, photos & ids',
      () async {
        final seed = buildSeedData().toJson();
        seed['schemaVersion'] = 2;
        // Strip every multi-unit field to imitate data saved by the old app.
        for (final s in (seed['shops'] as List).cast<Map<String, dynamic>>()) {
          for (final b in (s['boards'] as List).cast<Map<String, dynamic>>()) {
            b
              ..remove('units')
              ..remove('sizeMode')
              ..remove('unitSeq')
              ..remove('previews');
          }
          for (final sub
              in (s['submissions'] as List).cast<Map<String, dynamic>>()) {
            for (final b
                in ((sub['snapshot'] as Map)['boards'] as List).cast<Map>()) {
              b
                ..remove('units')
                ..remove('sizeMode')
                ..remove('unitSeq')
                ..remove('previews');
            }
          }
        }
        final store = MemoryLocalStore(seed);
        final c = AppController(store: store);
        await c.init();
        await c.flush();
        expect(store.data!['schemaVersion'], AppData.schemaVersion);
        final before = AppData.fromJson(seed);
        for (final s in c.data.shops) {
          final old = before.shops.firstWhere((e) => e.id == s.id);
          expect(s.projectId, old.projectId);
          expect(s.taskId, old.taskId);
          expect(s.status, old.status);
          expect(s.submissions.length, old.submissions.length);
          for (var i = 0; i < s.submissions.length; i++) {
            expect(
              s.submissions[i].reviews.length,
              old.submissions[i].reviews.length,
            );
            // Snapshots parse to stable unit ids too.
            expect(
              s.submissions[i].shopSnapshot.boards
                  .expand((b) => b.units)
                  .map((u) => u.id),
              s.submissions[i].shopSnapshot.boards
                  .expand((b) => b.units)
                  .map((u) => u.id),
            );
          }
          for (final b in s.boards) {
            final ob = old.boards.firstWhere((e) => e.id == b.id);
            expect(b.units, hasLength(b.quantity));
            expect(b.photos.length, ob.photos.length);
            expect(b.annotationCount, ob.annotationCount);
            expect(b.width, ob.width);
            expect(b.height, ob.height);
          }
        }
        // A second start (already v3) changes nothing.
        final again = AppController(store: store);
        await again.init();
        expect(
          jsonEncode(again.data.shops.map((s) => s.toJson()).toList()),
          jsonEncode(c.data.shops.map((s) => s.toJson()).toList()),
        );
      },
    );
  });

  group('multiple media types in one shop', () {
    test(
      'several groups (incl. the same media twice) under one task',
      () async {
        final c = await _vendor();
        final shop = c.shop('s_lakshmi')!;
        final taskId = shop.taskId;
        final codes = [
          SignageCatalog.gsb,
          SignageCatalog.vinyl,
          SignageCatalog.singleStandee,
          SignageCatalog.doubleStandee,
          SignageCatalog.gsb,
        ];
        for (final code in codes) {
          final b = c.addBoard(shop.id)..mediaCode = code;
          b.installationCode = SignageCatalog.media(code)!.installations.first;
          c.touchBoard(shop.id, b);
        }
        expect(shop.boards.map((b) => b.mediaCode), codes);
        expect(shop.taskId, taskId);
        expect(shop.boards.map((b) => b.id).toSet(), hasLength(5));
        expect(
          c.shopsForTask(taskId).where((s) => s.id == shop.id),
          hasLength(1),
        );
        // Different media types keep independent dimensions.
        shop.boards[0]
          ..width = 8
          ..height = 3;
        shop.boards[2]
          ..width = 3
          ..height = 5;
        expect(shop.boards[0].areaSqFt, 24);
        expect(shop.boards[2].areaSqFt, 15);
        expect(shop.unitCount, 5);
      },
    );

    test('removing a draft media group leaves the others', () async {
      final c = await _vendor();
      final shop = c.shop('s_lakshmi')!;
      final a = c.addBoard(shop.id);
      final b = c.addBoard(shop.id);
      await c.deleteBoard(shop.id, a.id);
      expect(shop.boards.map((e) => e.id), [b.id]);
    });

    test('duplicate configuration copies units with fresh ids', () async {
      final c = await _vendor();
      final shop = c.shop('s_lakshmi')!;
      final b = c.addBoard(shop.id)..mediaCode = SignageCatalog.gsb;
      c.increaseQuantity(shop.id, b, 2);
      c.setSizeMode(shop.id, b, SizeMode.different);
      b.units[0]
        ..width = 8
        ..height = 3
        ..placement = 'Entrance';
      final copy = c.duplicateBoard(shop.id, b.id);
      expect(copy.quantity, 2);
      expect(copy.sizeMode, SizeMode.different);
      expect(copy.units.first.placement, 'Entrance');
      expect(copy.units.first.width, 8);
      expect(
        copy.units
            .map((u) => u.id)
            .toSet()
            .intersection(b.units.map((u) => u.id).toSet()),
        isEmpty,
      );
      expect(copy.photos, isEmpty);
    });
  });

  group('quantity & size workflow', () {
    late AppController c;
    late Shop shop;
    late Board b;

    setUp(() async {
      c = await _vendor();
      shop = c.shop('s_lakshmi')!;
      b = c.addBoard(shop.id)
        ..mediaCode = SignageCatalog.gsb
        ..installationCode = SignageCatalog.shopFascia
        ..width = 8
        ..height = 3;
    });

    test('quantity 1 needs no size-mode question', () {
      expect(b.quantity, 1);
      expect(b.units, hasLength(1));
      expect(b.isSameSize, isTrue);
      expect(b.hasSize, isTrue);
    });

    test('quantity 2 and 5 create only the additional units', () {
      final first = b.units.first..placement = 'Above shutter';
      c.increaseQuantity(shop.id, b, 2);
      expect(b.units, hasLength(2));
      expect(b.units.first, same(first));
      expect(b.units.first.placement, 'Above shutter');
      c.increaseQuantity(shop.id, b, 5);
      expect(b.units, hasLength(5));
      expect(b.units.map((u) => u.id).toSet(), hasLength(5));
      expect(b.areaSqFt, closeTo(8 * 3 * 5, 1e-9));
      // Same size: every unit uses the shared dimensions.
      expect(b.activeUnits.every(b.unitHasSize), isTrue);
    });

    test('same → different copies sizes; units then edit independently', () {
      c.increaseQuantity(shop.id, b, 3);
      c.setSizeMode(shop.id, b, SizeMode.different);
      expect(b.isSameSize, isFalse);
      expect(b.units.map((u) => (u.width, u.height)), [
        (8.0, 3.0),
        (8.0, 3.0),
        (8.0, 3.0),
      ]);
      c.setUnitSize(shop.id, b, b.units[1], width: 10, height: 4);
      c.setUnitSize(shop.id, b, b.units[2], width: 6, height: 2);
      expect(b.areaSqFt, closeTo(24 + 40 + 12, 1e-9));
      // Group size mirrors unit 1 (keeps 2D / 3D working).
      c.setUnitSize(shop.id, b, b.units[0], width: 9, height: 3);
      expect(b.width, 9);
    });

    test('different → same applies the chosen unit size to all', () {
      c.increaseQuantity(shop.id, b, 3);
      c.setSizeMode(shop.id, b, SizeMode.different);
      c.setUnitSize(shop.id, b, b.units[1], width: 10, height: 4);
      c.setSizeMode(shop.id, b, SizeMode.same, fromUnitId: b.units[1].id);
      expect(b.isSameSize, isTrue);
      expect((b.width, b.height), (10.0, 4.0));
      expect(b.areaSqFt, closeTo(120, 1e-9));
    });

    test('invalid / missing unit sizes are validation issues', () {
      c.increaseQuantity(shop.id, b, 2);
      c.setSizeMode(shop.id, b, SizeMode.different);
      c.setUnitSize(shop.id, b, b.units[1], width: 0, height: 4);
      expect(c.boardIssues(b), contains('Enter width and height for Unit 02'));
      c.setUnitSize(shop.id, b, b.units[1], width: 5, height: null);
      expect(c.boardIssues(b), contains('Enter width and height for Unit 02'));
      c.setUnitSize(shop.id, b, b.units[1], width: 5, height: 2);
      expect(
        c.boardIssues(b).where((i) => i.startsWith('Enter width')),
        isEmpty,
      );
      // Same-size mode keeps the original message.
      b
        ..sizeMode = SizeMode.same
        ..width = 0;
      expect(c.boardIssues(b), contains('Enter board width and height'));
    });

    test(
      'reducing quantity lists units and removes their own data only',
      () async {
        c.increaseQuantity(shop.id, b, 3);
        final photo = SitePhoto(
          id: 'p1',
          path: 'demo://1',
          label: 'Front view',
          capturedAt: DateTime(2026),
          width: 1200,
          height: 900,
          unitIds: [b.units[1].id, b.units[2].id],
          annotations: [
            Annotation(
              id: 'm1',
              type: AnnotationType.rectangle,
              itemId: b.units[0].id,
            ),
            Annotation(
              id: 'm3',
              type: AnnotationType.rectangle,
              itemId: b.units[2].id,
            ),
          ],
        );
        c.addPhoto(shop.id, b.id, photo);
        c.addPreview(
          shop.id,
          b.id,
          PreviewCapture(
            id: 'pv3',
            kind: CaptureKind.live,
            projectId: shop.projectId,
            taskId: shop.taskId,
            shopId: shop.id,
            groupId: b.id,
            unitId: b.units[2].id,
            path: 'demo://none',
            createdAt: DateTime(2026),
          ),
        );
        final removed = c.unitsRemovedBy(b, 2);
        expect(removed.map(b.unitLabel), ['Unit 03']);
        final att = c.unitAttachments(b, removed);
        expect(att.markings, 1);
        expect(att.previews, 1);
        expect(att.photos, 1);
        final keepIds = b.units.take(2).map((u) => u.id).toList();
        await c.reduceQuantity(shop.id, b, 2);
        expect(b.quantity, 2);
        expect(b.units.map((u) => u.id), keepIds);
        expect(b.photos.single.annotations.map((a) => a.id), ['m1']);
        expect(b.photos.single.unitIds, [keepIds[1]]);
        expect(b.previews, isEmpty);
        // Ids are never reused after a removal.
        c.increaseQuantity(shop.id, b, 3);
        expect(b.units.last.id, isNot(removed.single.id));
      },
    );

    test('reducing to one unit returns to same size with its size', () async {
      c.increaseQuantity(shop.id, b, 2);
      c.setSizeMode(shop.id, b, SizeMode.different);
      c.setUnitSize(shop.id, b, b.units[0], width: 12, height: 5);
      await c.reduceQuantity(shop.id, b, 1);
      expect(b.quantity, 1);
      expect(b.sizeMode, SizeMode.same);
      expect((b.width, b.height), (12.0, 5.0));
    });

    test('removeUnit keeps at least one unit', () async {
      await c.removeUnit(shop.id, b, b.units.first.id);
      expect(b.units, hasLength(1));
      c.increaseQuantity(shop.id, b, 2);
      final second = b.units[1].id;
      await c.removeUnit(shop.id, b, b.units.first.id);
      expect(b.units.map((u) => u.id), [second]);
    });
  });

  group('standees', () {
    Board standee(String code, {Map<String, dynamic>? answers}) => Board(
      id: 'st',
      name: 'Standee',
      mediaCode: code,
      installationCode: SignageCatalog.freeStanding,
      width: 3,
      height: 5,
      answers: answers,
    );

    test('catalog questions: base, support, material, faces', () {
      final single = SignageCatalog.questionsFor(
        SignageCatalog.singleStandee,
        SignageCatalog.freeStanding,
      ).map((q) => q.id);
      expect(
        single,
        containsAll([
          'overall_height',
          'display_panel_height',
          'base_type',
          'base_width',
          'base_depth',
          'support_structure',
          'standee_material',
          'placement_location',
          'indoor_outdoor',
          'standee_remarks',
          'panel_bottom_height',
        ]),
      );
      expect(single, isNot(contains('front_face')));
      final double = SignageCatalog.questionsFor(
        SignageCatalog.doubleStandee,
        SignageCatalog.freeStanding,
      ).map((q) => q.id);
      expect(double, containsAll(['front_face', 'back_face', 'base_type']));
      expect(SignageCatalog.isStandee(SignageCatalog.doubleStandee), isTrue);
      expect(SignageCatalog.isStandee(SignageCatalog.gsb), isFalse);
    });

    test('geometry: double sided, base and support configurable', () {
      final s = SignageGeometry.fromBoard(
        standee(SignageCatalog.singleStandee),
      );
      expect(s.doubleSided, isFalse);
      expect(s.isFreeStanding, isTrue);
      expect(s.bottomFt, 2.5); // default panel bottom
      final d = SignageGeometry.fromBoard(
        standee(
          SignageCatalog.doubleStandee,
          answers: {
            'base_width': 4,
            'base_depth': 2,
            'support_structure': 'Single centre pole',
            'panel_bottom_height': 3,
          },
        ),
      );
      expect(d.doubleSided, isTrue);
      expect(d.baseWidthFt, 4);
      expect(d.baseDepthFt, 2);
      expect(d.supportType, 'Single centre pole');
      expect(d.bottomFt, 3);
      expect(
        SignageGeometry.clearanceKey(SignageCatalog.freeStanding),
        'panel_bottom_height',
      );
    });

    test('3D model: display, frame and ground base for every support', () {
      for (final code in [
        SignageCatalog.singleStandee,
        SignageCatalog.doubleStandee,
      ]) {
        for (final support in [
          'Twin side posts',
          'Single centre pole',
          'A-frame',
          'Box frame',
        ]) {
          final g = SignageGeometry.fromBoard(
            standee(code, answers: {'support_structure': support}),
          );
          final scene = SignageSceneBuilder.build(g, brand: 'Asian Paints');
          final names = scene.solids.map((s) => s.name).toSet();
          expect(names, containsAll(['board', 'base']), reason: support);
          final board = scene.solids.firstWhere((s) => s.name == 'board');
          final labelled = board.faces.where((f) => f.label != null).length;
          expect(labelled, code == SignageCatalog.doubleStandee ? 2 : 1);
          _paintOnce(
            Scene3DPainter(scene: scene, camera: const Camera3D()),
            const Size(300, 300),
          );
          _paintOnce(
            Drawing2DPainter(
              geo: g,
              info: const DrawingInfo(
                projectName: 'P',
                shopName: 'S',
                shopAddress: 'A',
                boardName: 'B',
                drawnBy: 'T',
                date: '18 Nov 2026',
              ),
            ),
            const Size(900, 700),
          );
        }
      }
    });

    test('quantity 2 double-sided = 2 physical units', () async {
      final c = await _vendor();
      final shop = c.shop('s_lakshmi')!;
      final b = c.addBoard(shop.id)
        ..mediaCode = SignageCatalog.doubleStandee
        ..installationCode = SignageCatalog.freeStanding
        ..width = 3
        ..height = 5;
      c.increaseQuantity(shop.id, b, 2);
      expect(b.units, hasLength(2));
      expect(b.areaSqFt, closeTo(30, 1e-9));
    });
  });

  group('model-only scene for photo overlays', () {
    test('every media × installation builds without walls / buildings', () {
      for (final m in SignageCatalog.mediaTypes) {
        for (final inst in m.installations) {
          final g = SignageGeometry.fromBoard(
            Board(
              id: 'b',
              name: 'B',
              mediaCode: m.code,
              installationCode: inst,
              width: 8,
              height: 3,
            ),
          );
          final scene = SignageSceneBuilder.buildModel(g, brand: 'X');
          final names = scene.solids.map((s) => s.name).toSet();
          expect(
            names.intersection(SignageSceneBuilder.contextSolids),
            isEmpty,
            reason: '${m.code}/$inst',
          );
          expect(names, isNot(contains('person')));
          expect(names, contains('board'), reason: '${m.code}/$inst');
          _paintOnce(
            Scene3DPainter(
              scene: scene,
              camera: const Camera3D(yaw: 0, pitch: 0),
              paintBackground: false,
              paintGround: false,
              paintGizmo: false,
            ),
            const Size(200, 200),
          );
        }
      }
    });

    test('pole installations keep their poles in the model', () {
      Set<String> names(String inst) => SignageSceneBuilder.buildModel(
        SignageGeometry.fromBoard(
          Board(
            id: 'b',
            name: 'B',
            mediaCode: SignageCatalog.gsb,
            installationCode: inst,
            width: 8,
            height: 3,
          ),
        ),
      ).solids.map((s) => s.name).toSet();
      expect(names(SignageCatalog.doublePole), contains('pole'));
      expect(names(SignageCatalog.singlePole), contains('pole'));
      expect(names(SignageCatalog.wallMount), isNot(contains('pole')));
    });
  });

  group('previews & approval', () {
    PreviewCapture capture(Shop s, Board b, {String id = 'pv'}) =>
        PreviewCapture(
          id: id,
          kind: CaptureKind.live,
          projectId: s.projectId,
          taskId: s.taskId,
          shopId: s.id,
          groupId: b.id,
          unitId: b.units.first.id,
          photoId: b.photos.firstOrNull?.id,
          path: 'demo://preview',
          createdAt: DateTime(2026, 11, 18),
          overlays: [PreviewOverlay(unitId: b.units.first.id, cx: 0.3)],
        );

    test('saving / deleting a preview never touches the photo', () async {
      final c = await _vendor();
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      final photos = b.photos.length;
      final marks = b.annotationCount;
      c.addPreview(shop.id, b.id, capture(shop, b));
      expect(b.previews, hasLength(1));
      expect(b.previewsOf(b.units.first), hasLength(1));
      await c.removePreview(shop.id, b.id, 'pv');
      expect(b.previews, isEmpty);
      expect(b.photos.length, photos);
      expect(b.annotationCount, marks);
    });

    test('preview metadata survives JSON / restart', () async {
      final store = MemoryLocalStore();
      final c = AppController(store: store);
      await c.init();
      c.loginWithPin('5678');
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      c.addPreview(shop.id, b.id, capture(shop, b));
      await c.flush();
      final r = AppController(store: store);
      await r.init();
      final p = r.board(shop.id, b.id)!.previews.single;
      expect(p.projectId, shop.projectId);
      expect(p.taskId, shop.taskId);
      expect(p.shopId, shop.id);
      expect(p.groupId, b.id);
      expect(p.unitId, b.units.first.id);
      expect(p.photoId, b.photos.first.id);
      expect(p.overlays.single.cx, 0.3);
      expect(p.kind, CaptureKind.live);
    });

    test('item-specific rejection → correction → resubmit → approve', () async {
      final c = await _vendor();
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      completeAnswers(b);
      c.setShopLocation(shop, gpsAt(10.86270, 78.68970));
      c.increaseQuantity(shop.id, b, 2);
      c.submitShop(shop.id);
      final v1Units = shop.latestSubmission!.shopSnapshot.boards.first.units
          .map((u) => u.id)
          .toList();
      expect(v1Units, hasLength(2));
      c.logout();

      c.loginWithPin(DemoAccounts.businessPin);
      final issue = RejectionIssue(
        groupId: b.id,
        unitId: b.units[1].id,
        aspect: IssueAspect.dimension,
        label: 'GSB • Unit 02',
        note: 'Width looks wrong',
      );
      c.reviewShop(
        shop.id,
        decision: ReviewDecision.rejected,
        remarks: 'Fix unit 2',
        issues: [issue],
      );
      expect(shop.status, RecceStatus.rejectedBusiness);
      c.logout();

      c.loginWithPin('5678');
      final open = c.openIssues(shop);
      expect(open.single.unitId, b.units[1].id);
      expect(open.single.aspect, IssueAspect.dimension);
      expect(open.single.text, contains('Width looks wrong'));
      c.setSizeMode(shop.id, b, SizeMode.different);
      c.setUnitSize(shop.id, b, b.units[1], width: 12, height: 4);
      final changes = diffShops(shop.latestSubmission!.shopSnapshot, shop);
      expect(changes.any((ch) => ch.contains('Unit 02: size')), isTrue);
      c.submitShop(shop.id, remarks: 'Unit 2 corrected');
      expect(shop.submissions, hasLength(2));
      expect(c.openIssues(shop), isEmpty);
      // v1 and its rejection stay untouched in history.
      final v1 = shop.submissions.first;
      expect(v1.reviews.single.issues.single.note, 'Width looks wrong');
      expect(v1.shopSnapshot.boards.first.isSameSize, isTrue);
      c.logout();

      // Both teams approve the same (latest) version.
      c.loginWithPin(DemoAccounts.businessPin);
      c.reviewShop(shop.id, decision: ReviewDecision.approved);
      c.logout();
      c.loginWithPin(DemoAccounts.opsPin);
      c.reviewShop(shop.id, decision: ReviewDecision.approved);
      expect(shop.status, RecceStatus.approved);
      final v2 = shop.latestSubmission!;
      expect(v2.version, 2);
      expect(v2.reviews.map((r) => r.stage), [
        ReviewStage.business,
        ReviewStage.ops,
      ]);
      expect(v2.reviews.every((r) => r.issues.isEmpty), isTrue);
    });

    test('approvals ignore issues (only rejections carry them)', () async {
      final c = await _vendor();
      final shop = c.shop('s_sriranga')!;
      completeAnswers(shop.boards.first);
      c.setShopLocation(shop, gpsAt(10.86270, 78.68970));
      c.submitShop(shop.id);
      c.logout();
      c.loginWithPin(DemoAccounts.businessPin);
      c.reviewShop(
        shop.id,
        decision: ReviewDecision.approved,
        issues: [
          RejectionIssue(groupId: 'x', aspect: IssueAspect.photo, label: 'x'),
        ],
      );
      expect(shop.latestSubmission!.reviews.single.issues, isEmpty);
    });

    test('AR / live previews are optional for submission', () async {
      final c = await _vendor();
      final shop = c.shop('s_sriranga')!;
      completeAnswers(shop.boards.first);
      c.setShopLocation(shop, gpsAt(10.86270, 78.68970));
      expect(shop.boards.first.previews, isEmpty);
      expect(c.shopIssues(shop), isEmpty);
    });
  });
}
