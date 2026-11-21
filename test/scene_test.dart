import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/drawing/drawing_2d_painter.dart';
import 'package:signage_recce/features/drawing/drawing_2d_screen.dart';
import 'package:signage_recce/features/drawing/signage_geometry.dart';
import 'package:signage_recce/features/preview3d/preview_3d_screen.dart';
import 'package:signage_recce/features/preview3d/renderer_painter.dart';
import 'package:signage_recce/features/preview3d/scene3d.dart';
import 'package:signage_recce/features/preview3d/signage_scene_builder.dart';
import 'package:signage_recce/state/app_controller.dart';

Board _board({
  String? media = SignageCatalog.gsb,
  String? installation = SignageCatalog.doublePole,
  double? width = 10,
  double? height = 4,
  Map<String, dynamic>? answers,
  MeasureUnit unit = MeasureUnit.ft,
}) => Board(
  id: 'b1',
  name: 'Test Board',
  mediaCode: media,
  installationCode: installation,
  width: width,
  height: height,
  unit: unit,
  answers: answers,
);

void _paintOnce(CustomPainter painter, Size size) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  recorder.endRecording().dispose();
}

void main() {
  group('SignageGeometry', () {
    test('double pole uses answers and clamps pole gap', () {
      final g = SignageGeometry.fromBoard(
        _board(answers: {'pole_height': 12, 'pole_gap': 50}),
      );
      expect(g.widthFt, 10);
      expect(g.heightFt, 4);
      expect(g.clearanceFt, 12);
      expect(g.bottomFt, 12);
      expect(g.topFt, 16);
      expect(g.poleGapFt, 10, reason: 'gap cannot exceed board width');
      expect(g.depthFt, 0.75);
      expect(g.usingDefaults, isFalse);
    });

    test('defaults per installation', () {
      double bottom(String inst) => SignageGeometry.fromBoard(
        _board(
          media: inst == SignageCatalog.directWall
              ? SignageCatalog.wallPainting
              : SignageCatalog.gsb,
          installation: inst,
        ),
      ).bottomFt;
      expect(bottom(SignageCatalog.doublePole), 9);
      expect(bottom(SignageCatalog.singlePole), 9);
      expect(bottom(SignageCatalog.wallMount), 8);
      expect(bottom(SignageCatalog.flangeBracket), 9);
      expect(bottom(SignageCatalog.directWall), 3);
      expect(bottom(SignageCatalog.glassPasting), 1);
      expect(bottom(SignageCatalog.shopFascia), 9.5);
      expect(bottom(SignageCatalog.rooftop), 24); // 2 floors × 10 + 4
    });

    test('rooftop uses floors + structure height', () {
      final g = SignageGeometry.fromBoard(
        _board(
          installation: SignageCatalog.rooftop,
          answers: {'building_floors': 3, 'structure_height': 5},
        ),
      );
      expect(g.buildingHeightFt, 30);
      expect(g.baseLevelFt, 30);
      expect(g.bottomFt, 35);
    });

    test('units are converted to feet', () {
      final g = SignageGeometry.fromBoard(
        _board(width: 120, height: 48, unit: MeasureUnit.inch),
      );
      expect(g.widthFt, closeTo(10, 1e-9));
      expect(g.heightFt, closeTo(4, 1e-9));
    });

    test('missing size / selections fall back to defaults', () {
      final g = SignageGeometry.fromBoard(
        _board(media: null, installation: null, width: null, height: null),
      );
      expect(g.usingDefaults, isTrue);
      expect(g.mediaSelected, isFalse);
      expect(g.installationSelected, isFalse);
      expect(g.widthFt, SignageGeometry.defaultWidthFt);
      expect(g.heightFt, SignageGeometry.defaultHeightFt);
      expect(g.mediaCode, SignageCatalog.gsb);
    });

    test('overrides win over board values', () {
      final g = SignageGeometry.fromBoard(
        _board(answers: {'pole_height': 12}),
        widthFt: 20,
        heightFt: 6,
        clearanceFt: 7,
      );
      expect(g.widthFt, 20);
      expect(g.heightFt, 6);
      expect(g.bottomFt, 7);
      expect(g.usingDefaults, isFalse);
    });

    test('clearance keys', () {
      expect(
        SignageGeometry.clearanceKey(SignageCatalog.doublePole),
        'pole_height',
      );
      expect(
        SignageGeometry.clearanceKey(SignageCatalog.shopFascia),
        'shutter_height',
      );
      expect(
        SignageGeometry.clearanceKey(SignageCatalog.rooftop),
        'structure_height',
      );
      expect(
        SignageGeometry.clearanceKey(SignageCatalog.wallMount),
        'mount_height',
      );
      expect(SignageGeometry.clearanceKey(null), isNull);
    });

    test('flange is double sided unless single side answered', () {
      expect(
        SignageGeometry.fromBoard(
          _board(
            media: SignageCatalog.flange,
            installation: SignageCatalog.flangeBracket,
          ),
        ).doubleSided,
        isTrue,
      );
      expect(
        SignageGeometry.fromBoard(
          _board(
            media: SignageCatalog.flange,
            installation: SignageCatalog.flangeBracket,
            answers: {'sides': 'Single side'},
          ),
        ).doubleSided,
        isFalse,
      );
    });
  });

  group('Scene builder & renderer', () {
    test('every media × allowed installation builds a non-empty scene', () {
      for (final m in SignageCatalog.mediaTypes) {
        for (final inst in m.installations) {
          final g = SignageGeometry.fromBoard(
            _board(media: m.code, installation: inst),
          );
          final scene = SignageSceneBuilder.build(g, brand: 'Asian Paints');
          expect(scene.solids, isNotEmpty, reason: '${m.code}/$inst');
          expect(scene.faceCount, greaterThan(12), reason: '${m.code}/$inst');
          expect(scene.dims.length, greaterThanOrEqualTo(2));
          expect(scene.radius, greaterThan(0));
          // Renders from several angles without throwing.
          for (final cam in const [
            Camera3D(),
            Camera3D(yaw: 0, pitch: 0),
            Camera3D(yaw: 1.57, pitch: 0, ortho: true),
            Camera3D(yaw: 0, pitch: 1.55),
            Camera3D(yaw: 3.14, pitch: -0.1, zoom: 3),
          ]) {
            _paintOnce(
              Scene3DPainter(scene: scene, camera: cam),
              const Size(360, 400),
            );
          }
        }
      }
    });

    test('2D drawing paints for every media × allowed installation', () {
      for (final m in SignageCatalog.mediaTypes) {
        for (final inst in m.installations) {
          final g = SignageGeometry.fromBoard(
            _board(media: m.code, installation: inst),
          );
          _paintOnce(
            Drawing2DPainter(
              geo: g,
              info: const DrawingInfo(
                projectName: 'Asian Paints',
                shopName: 'Shop',
                shopAddress: 'Srirangam',
                boardName: 'Board 1',
                drawnBy: 'Tester',
                date: '17 Nov 2026',
                notes: ['Ground type: Concrete'],
              ),
            ),
            Drawing2DPainter.sheet,
          );
        }
      }
    });

    test('front view projects the board centre to the viewport centre', () {
      final g = SignageGeometry.fromBoard(_board());
      final scene = SignageSceneBuilder.build(g);
      const size = Size(400, 600);
      for (final ortho in [false, true]) {
        final proj = ViewProjector(
          camera: Camera3D(yaw: 0, pitch: 0, ortho: ortho),
          size: size,
          target: scene.focus,
          radius: scene.radius,
        );
        final centre = Vec3(0, g.bottomFt + g.heightFt / 2, -g.depthFt / 2);
        final p = proj.project(centre)!;
        expect(p.dx, closeTo(200, 0.01));
        expect(p.dy, closeTo(300, 0.01));
        // Board width maps left/right symmetrically in the front view.
        final left = proj.project(Vec3(-g.widthFt / 2, centre.y, centre.z))!;
        final right = proj.project(Vec3(g.widthFt / 2, centre.y, centre.z))!;
        expect(left.dx, lessThan(p.dx));
        expect(right.dx - p.dx, closeTo(p.dx - left.dx, 0.01));
        // Front face visible, back face culled.
        final front = proj.toView(Vec3(0, centre.y, 0));
        expect(proj.facesCamera(const Vec3(0, 0, 1), front), isTrue);
        final back = proj.toView(Vec3(0, centre.y, -g.depthFt));
        expect(proj.facesCamera(const Vec3(0, 0, -1), back), isFalse);
      }
    });

    test('side view (yaw 90°) sees the right face', () {
      final scene = SignageSceneBuilder.build(
        SignageGeometry.fromBoard(_board()),
      );
      final proj = ViewProjector(
        camera: const Camera3D(yaw: 1.5707963, pitch: 0),
        size: const Size(400, 400),
        target: scene.focus,
        radius: scene.radius,
      );
      final pt = proj.toView(Vec3(5, scene.focus.y, scene.focus.z));
      expect(proj.facesCamera(const Vec3(1, 0, 0), pt), isTrue);
      expect(proj.facesCamera(const Vec3(-1, 0, 0), pt), isFalse);
    });

    test('unrotate inverts rotate', () {
      final proj = ViewProjector(
        camera: const Camera3D(yaw: 0.7, pitch: -0.3),
        size: const Size(400, 400),
        target: Vec3.zero,
        radius: 10,
      );
      const p = Vec3(1.5, -2, 3.25);
      final back = proj.unrotate(proj.rotate(p));
      expect(back.x, closeTo(p.x, 1e-9));
      expect(back.y, closeTo(p.y, 1e-9));
      expect(back.z, closeTo(p.z, 1e-9));
    });

    // Regression: at low pitch, centroid sorting drew a pole (which stands
    // behind the board) over the board face on the emulator.
    test('poles behind a wide board are drawn before the board', () {
      for (final width in [10.0, 33.25]) {
        final scene = SignageSceneBuilder.build(
          SignageGeometry.fromBoard(_board(width: width)),
        );
        final board = scene.solids.firstWhere((s) => s.name == 'board');
        double zMax(Solid s) => [
          for (final f in s.faces)
            for (final p in f.points) p.z,
        ].reduce((a, b) => a > b ? a : b);
        double zMin(Solid s) => [
          for (final f in s.faces)
            for (final p in f.points) p.z,
        ].reduce((a, b) => a < b ? a : b);
        final behind = scene.solids
            .where((s) => s != board && zMax(s) <= zMin(board))
            .toList();
        expect(behind, isNotEmpty);
        for (final cam in const [
          Camera3D(yaw: -0.087, pitch: -0.14), // the failing emulator angle
          Camera3D(yaw: 0.55, pitch: 0.28),
          Camera3D(yaw: 0, pitch: -0.2, ortho: true),
        ]) {
          final proj = ViewProjector(
            camera: cam,
            size: const Size(400, 600),
            target: scene.focus,
            radius: scene.radius,
          );
          final order = Scene3DPainter.orderSolids(scene.solids, proj);
          final boardIndex = order.indexOf(board);
          for (final s in behind) {
            expect(
              order.indexOf(s),
              lessThan(boardIndex),
              reason: '${s.name} must be painted before the board',
            );
          }
          expect(order.toSet().length, scene.solids.length);
        }
      }
    });

    test('camera lerp takes the shortest yaw arc', () {
      const a = Camera3D(yaw: 3.0);
      const b = Camera3D(yaw: -3.0);
      final mid = Camera3D.lerp(a, b, 0.5);
      // Shortest path crosses ±π, not 0.
      expect(mid.yaw.abs(), greaterThan(3.0));
    });
  });

  group('Screens', () {
    late AppController controller;

    setUp(() async {
      controller = AppController(store: MemoryLocalStore());
      await controller.init();
      expect(controller.loginWithPin('5678'), isNull);
    });

    Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(1080, 2070); // 360 × 690 dp
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: controller,
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('3D preview rotates, snaps to presets and applies size', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const Preview3DScreen(shopId: 's_sriranga', boardId: 'b_sriranga_1'),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);

      String hud() =>
          tester.widget<Text>(find.byKey(const Key('preview3d-hud'))).data!;
      final before = hud();

      await tester.drag(
        find.byKey(const Key('preview3d-viewport')),
        const Offset(120, 40),
      );
      await tester.pump();
      expect(hud(), isNot(before));

      await tester.tap(find.text('Front'));
      await tester.pumpAndSettle();
      expect(hud(), startsWith('Yaw 0° · Pitch 0°'));

      await tester.tap(find.text('Side'));
      await tester.pumpAndSettle();
      expect(hud(), startsWith('Yaw 90° · Pitch 0°'));

      await tester.ensureVisible(find.text('Isometric'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Isometric'));
      await tester.pumpAndSettle();
      expect(hud(), contains('Ortho'));

      // Live dimension change then apply to the board.
      final board = controller.board('s_sriranga', 'b_sriranga_1')!;
      expect(board.width, 10);
      await tester.drag(
        find.byKey(const Key('width-slider')),
        const Offset(60, 0),
      );
      await tester.pump();
      await tester.tap(find.text('Apply to board'));
      await tester.pumpAndSettle();
      expect(board.width, isNot(10));
      expect(board.width, greaterThan(10));
      expect(tester.takeException(), isNull);
    });

    testWidgets('3D preview is read-only for reviewers', (tester) async {
      controller.logout();
      expect(controller.loginWithPin('1234'), isNull);
      await pumpScreen(
        tester,
        const Preview3DScreen(shopId: 's_amma', boardId: 'b_amma_1'),
      );
      expect(find.text('Apply to board'), findsNothing);
      expect(find.textContaining('View only'), findsOneWidget);
    });

    testWidgets('2D drawing renders, fits and reports missing storage', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const Drawing2DScreen(shopId: 's_sriranga', boardId: 'b_sriranga_1'),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('drawing2d-viewer')), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);

      await tester.tap(find.byTooltip('Fit to screen'));
      await tester.pump();

      // MemoryLocalStore controller has no MediaStorage → graceful message.
      await tester.tap(find.byTooltip('Save PNG'));
      await tester.pump();
      expect(find.textContaining('Local storage is not available'), findsOne);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('2D drawing asks for media/installation when missing', (
      tester,
    ) async {
      final b = controller.addBoard('s_lakshmi');
      await pumpScreen(
        tester,
        Drawing2DScreen(shopId: 's_lakshmi', boardId: b.id),
      );
      expect(find.text('Drawing needs board details'), findsOneWidget);
      await tester.tap(find.text('Preview with defaults'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
