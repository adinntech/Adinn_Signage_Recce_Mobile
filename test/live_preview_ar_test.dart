import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/photos/photo_workspace_screen.dart';
import 'package:signage_recce/features/preview_live/live_preview_controller.dart';
import 'package:signage_recce/state/app_controller.dart';

SitePhoto _photo({List<Annotation>? items}) => SitePhoto(
  id: 'ph',
  path: 'demo://2',
  label: 'Front view',
  capturedAt: DateTime(2026),
  width: 1200,
  height: 900,
  annotations: items,
);

Board _group({String media = SignageCatalog.gsb, String? inst, int qty = 1}) {
  final b = Board(
    id: 'g',
    name: 'Group',
    mediaCode: media,
    installationCode: inst ?? SignageCatalog.media(media)!.installations.first,
    width: 8,
    height: 3,
    quantity: qty,
  );
  b.photos.add(_photo());
  return b;
}

void main() {
  group('LivePreviewController', () {
    test('selected media type controls the model', () {
      final c = LivePreviewController(
        board: _group(inst: SignageCatalog.doublePole),
        photo: _photo(),
      )..addUnit('g_u1');
      final names = c.sceneFor(c.selected!).solids.map((s) => s.name).toSet();
      expect(names, containsAll(['board', 'pole']));
      expect(names, isNot(contains('wall')));

      final st = LivePreviewController(
        board: _group(media: SignageCatalog.doubleStandee),
        photo: _photo(),
      )..addUnit('g_u1');
      final sn = st.sceneFor(st.selected!).solids.map((s) => s.name).toSet();
      expect(sn, containsAll(['board', 'base']));
    });

    test('unit dimensions drive the model proportions', () {
      final b = _group(qty: 2)..sizeMode = SizeMode.different;
      b.units[0]
        ..width = 8
        ..height = 3;
      b.units[1]
        ..width = 16
        ..height = 3;
      expect(unitGeometry(b, b.units[0]).widthFt, 8);
      expect(unitGeometry(b, b.units[1]).widthFt, 16);
      // A per-unit installation override is respected.
      b.units[1].installationCode = SignageCatalog.singlePole;
      expect(
        unitGeometry(b, b.units[1]).installationCode,
        SignageCatalog.singlePole,
      );
    });

    test('position / scale / rotation / perspective / opacity updates', () {
      final c = LivePreviewController(board: _group(), photo: _photo())
        ..addUnit('g_u1');
      c.moveBy(const Offset(0.1, -0.05));
      c.setScale(0.8);
      c.setRotation(0.5);
      c.setYaw(0.3);
      c.setPitch(5); // clamped
      c.setOpacity(0.01); // clamped
      final o = c.selected!;
      expect(o.cx, closeTo(0.6, 1e-9));
      expect(o.cy, closeTo(0.40, 1e-9));
      expect(o.scale, 0.8);
      expect(o.rotation, 0.5);
      expect(o.yaw, 0.3);
      expect(o.pitch, LivePreviewController.maxPitch);
      expect(o.opacity, 0.1);
      c.setScale(100);
      expect(c.selected!.scale, LivePreviewController.maxScale);
      c.resetSelected();
      expect(c.selected!.cx, 0.5);
    });

    test('fit to a marked placement rectangle matches its width', () {
      final b = _group();
      final photo = _photo(
        items: [
          Annotation(
            id: 'r',
            type: AnnotationType.rectangle,
            x: 600,
            y: 300,
            w: 480,
            h: 180,
            itemId: 'g_u1',
          ),
        ],
      );
      final c = LivePreviewController(board: b, photo: photo)..addUnit('g_u1');
      final o = c.selected!;
      expect(o.cx, closeTo(0.5, 1e-9));
      expect(o.cy, closeTo(300 / 900, 1e-9));
      // Board front width on screen = box * 0.42 / radius * widthFt.
      final scene = c.sceneFor(o);
      final boxPx = o.scale * 1200;
      final boardPx = boxPx * kRendererFill / scene.radius * 8;
      expect(boardPx, closeTo(480, 1e-6));
    });

    test('several signage items move independently', () {
      final b = _group(qty: 2);
      final c = LivePreviewController(board: b, photo: _photo())
        ..addUnit('g_u1')
        ..addUnit('g_u2');
      expect(c.selectedIndex, 1);
      c.setPosition(0.8, 0.2);
      c.select(0);
      c.setPosition(0.2, 0.7);
      expect(c.overlays[0].cx, 0.2);
      expect(c.overlays[1].cx, 0.8);
      expect(
        c.overlayAt(const Offset(0.8 * 400, 0.2 * 300), const Size(400, 300)),
        1,
      );
      c.removeSelected();
      expect(c.overlays.single.unitId, 'g_u2');
    });

    test('save metadata carries project / task / shop / group / unit ids', () {
      final b = _group(qty: 2);
      final shop = Shop(
        id: 's1',
        projectId: 'p1',
        taskId: 't1',
        name: 'Shop',
        boards: [b],
      );
      final c = LivePreviewController(board: b, photo: b.photos.first)
        ..addUnit('g_u2');
      final cap = c.toCapture(
        id: 'pv',
        shop: shop,
        path: '/x.png',
        at: DateTime(2026, 11, 18),
      );
      expect(cap.kind, CaptureKind.live);
      expect(
        (cap.projectId, cap.taskId, cap.shopId, cap.groupId, cap.unitId),
        ('p1', 't1', 's1', 'g', 'g_u2'),
      );
      expect(cap.photoId, 'ph');
      expect(cap.overlays.single.unitId, 'g_u2');
      // Restore uses the latest saved preview of the photo.
      b.previews.add(cap);
      final restored = LivePreviewController.restoreFrom(b, b.photos.first)!;
      expect(restored.single.unitId, 'g_u2');
      expect(identical(restored.single, cap.overlays.single), isFalse);
    });
  });

  group('photo workspace (widgets)', () {
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

    testWidgets('three tabs; AR unsupported falls back to Live Preview', (
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
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Photo Editor'), findsOneWidget);
      expect(find.text('Live Preview'), findsOneWidget);
      expect(find.text('Camera AR'), findsOneWidget);
      expect(find.text('Annotate photo'), findsOneWidget);

      await tester.tap(find.text('Camera AR'));
      await tester.pumpAndSettle();
      expect(
        find.text('Camera AR is not supported on this device.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('ar_open_live')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('save_live_preview')), findsOneWidget);
      expect(
        find.byKey(ValueKey('live-model-${b.units.first.id}')),
        findsOneWidget,
      );
    });

    testWidgets('Save Live Preview stores the composed image + metadata', (
      tester,
    ) async {
      final c = await boot(tester);
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      final photo = b.photos.first;
      final written = <String, int>{};
      await tester.pumpWidget(
        host(
          c,
          PhotoWorkspaceScreen(
            shopId: shop.id,
            boardId: b.id,
            photoId: photo.id,
            initialTab: 1,
            writer: (png, folder) async {
              written[folder] = png.length;
              return '/fake/$folder/live.png';
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Drag the model on the photo.
      final stage = find.byKey(const ValueKey('live-stage'));
      await tester.drag(stage, const Offset(40, -20));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('save_live_preview')));
        for (var i = 0; i < 50 && b.previews.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      expect(written['previews'], greaterThan(0));
      final saved = b.previews.single;
      expect(saved.kind, CaptureKind.live);
      expect(saved.path, '/fake/previews/live.png');
      expect(saved.photoId, photo.id);
      expect(saved.groupId, b.id);
      expect(saved.shopId, shop.id);
      expect(saved.taskId, shop.taskId);
      expect(saved.projectId, shop.projectId);
      expect(saved.overlays.single.cx, greaterThan(0.5));
      // Original photo untouched.
      expect(b.photos.first.path, photo.path);
      expect(c.data.activities.last.title, 'Live preview saved');
    });
  });
}
