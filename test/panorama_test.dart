import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/data/storage/media_storage.dart';
import 'package:signage_recce/features/panorama/panorama_io.dart';
import 'package:signage_recce/features/panorama/panorama_list_screen.dart';
import 'package:signage_recce/features/panorama/panorama_view_state.dart';
import 'package:signage_recce/features/panorama/panorama_viewer_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

const _shopId = 's_sriranga'; // in progress, assigned to the demo vendor
const _readOnlyShopId = 's_amma'; // pending business approval

class FakeProbe implements PanoramaImageProbe {
  FakeProbe(this.width, this.height, {this.fail = false});

  int width;
  int height;
  bool fail;

  @override
  Future<PanoramaImageInfo> probe(Uint8List bytes) async {
    if (fail) throw const FormatException('not an image');
    return PanoramaImageInfo(width, height);
  }
}

class FakePicker implements PanoramaPicker {
  FakePicker({this.result, this.error});

  PickedPanorama? result;
  PanoramaPickerException? error;
  int calls = 0;

  @override
  Future<PickedPanorama?> pickFromGallery() async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}

class RecordingWriter {
  final written = <String>[];

  Future<String> call(Uint8List bytes, String extension) async {
    final path = '/fake/panoramas/${written.length}.$extension';
    written.add(path);
    return path;
  }
}

class _RecordingMedia extends MediaStorage {
  final deleted = <String>[];

  @override
  Future<void> deleteIfExists(String? path) async {
    if (path != null) deleted.add(path);
  }
}

final _picked = PickedPanorama(
  bytes: Uint8List.fromList([1, 2, 3, 4]),
  name: 'site_360.jpg',
);

Future<AppController> _controller({
  MemoryLocalStore? store,
  MediaStorage? media,
  String pin = DemoAccounts.vendorPin,
}) async {
  final c = AppController(store: store ?? MemoryLocalStore(), media: media);
  await c.init();
  c.loginWithPin(pin);
  return c;
}

void main() {
  group('Panorama import validation', () {
    test('99 – aspect ratio 2:1 ± 10 % and minimum width', () async {
      expect(panoramaSizeProblem(4000, 2000), isNull);
      expect(panoramaSizeProblem(2000, 1000), isNull);
      expect(panoramaSizeProblem(4400, 2000), isNull); // 2.2:1
      expect(panoramaSizeProblem(3600, 2000), isNull); // 1.8:1
      expect(panoramaSizeProblem(4500, 2000), contains('2:1'));
      expect(panoramaSizeProblem(3000, 2000), contains('equirectangular'));
      expect(panoramaSizeProblem(1800, 900), contains('too small'));
      expect(panoramaSizeProblem(0, 0), isNotNull);

      final c = await _controller();
      final writer = RecordingWriter();
      final probe = FakeProbe(1200, 900);
      final importer = PanoramaImporter(probe: probe, writer: writer.call);
      await expectLater(
        importer.importInto(c, _shopId, _picked),
        throwsA(
          isA<PanoramaImportException>().having(
            (e) => e.message,
            'message',
            contains('Not a 360°'),
          ),
        ),
      );
      expect(writer.written, isEmpty, reason: 'nothing stored when invalid');
      expect(c.panoramasForShop(_shopId), isEmpty);

      probe
        ..width = 6000
        ..height = 3000;
      final p = await importer.importInto(c, _shopId, _picked);
      expect(writer.written, ['/fake/panoramas/0.jpg']);
      expect(p.path, '/fake/panoramas/0.jpg');
      expect(p.width, 6000);
      expect(p.height, 3000);
      expect(p.shopId, _shopId);
      expect(p.projectId, c.shop(_shopId)!.projectId);
      expect(c.panoramasForShop(_shopId).single.id, p.id);
      // The controller refuses an invalid size even without the importer.
      expect(
        () =>
            c.addPanorama(shopId: _shopId, path: '/x', width: 100, height: 50),
        throwsArgumentError,
      );
    });

    test('100 – an unreadable image gives a clear error, no crash', () async {
      final c = await _controller();
      final writer = RecordingWriter();
      final importer = PanoramaImporter(
        probe: FakeProbe(0, 0, fail: true),
        writer: writer.call,
      );
      await expectLater(
        importer.importInto(c, _shopId, _picked),
        throwsA(
          isA<PanoramaImportException>().having(
            (e) => e.message,
            'message',
            'The selected file is not a readable image.',
          ),
        ),
      );
      expect(writer.written, isEmpty);

      // Real dart:ui probe: garbage and empty bytes are rejected.
      const real = PanoramaImporter(writer: _noWrite);
      await expectLater(
        real.validate(Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7])),
        throwsA(isA<PanoramaImportException>()),
      );
      await expectLater(
        real.validate(Uint8List(0)),
        throwsA(isA<PanoramaImportException>()),
      );
      // A real (small) PNG decodes but is too small.
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 64, 32),
        Paint()..color = const Color(0xFF3366CC),
      );
      final img = await recorder.endRecording().toImage(64, 32);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      final info = await const DartUiPanoramaProbe().probe(
        png!.buffer.asUint8List(),
      );
      expect((info.width, info.height), (64, 32));
      await expectLater(
        real.validate(png.buffer.asUint8List()),
        throwsA(
          isA<PanoramaImportException>().having(
            (e) => e.message,
            'message',
            contains('too small'),
          ),
        ),
      );
    });

    test('read-only recce cannot import', () async {
      final c = await _controller();
      expect(c.canEditPanoramas(_readOnlyShopId), isFalse);
      final importer = PanoramaImporter(
        probe: FakeProbe(4000, 2000),
        writer: RecordingWriter().call,
      );
      await expectLater(
        importer.importInto(c, _readOnlyShopId, _picked),
        throwsA(isA<PanoramaImportException>()),
      );
      expect(
        () => c.addPanorama(
          shopId: _readOnlyShopId,
          path: '/x',
          width: 4000,
          height: 2000,
        ),
        throwsStateError,
      );
    });
  });

  group('Viewer state', () {
    const size = Size(400, 300);

    test('101 – pan / wrap-around / pitch clamp / zoom / reset', () {
      final v = PanoramaViewState(yawDeg: 350)..clamp(size);
      expect(v.fovH, 90);
      expect(v.degPerPx(size), closeTo(0.225, 1e-9));
      // Drag left by 100 px → turn right by 22.5°, wrapping past 360.
      v.panByPixels(const Offset(-100, 0), size);
      expect(v.yawDeg, closeTo(12.5, 1e-9));
      v.panByPixels(const Offset(200, 0), size);
      expect(v.yawDeg, closeTo(327.5, 1e-9));
      // Pitch never shows past the poles.
      v.panByPixels(const Offset(0, 5000), size);
      expect(v.pitchDeg, closeTo(90 - v.fovV(size) / 2, 1e-9));
      v.panByPixels(const Offset(0, -10000), size);
      expect(v.pitchDeg, closeTo(-(90 - v.fovV(size) / 2), 1e-9));
      // Zoom limits.
      v.zoomTo(100, size);
      expect(v.zoom, PanoramaViewState.maxZoom);
      v.zoomTo(0.01, size);
      expect(v.zoom, PanoramaViewState.minZoom);
      v.zoomBy(2, size);
      expect(v.zoom, closeTo(1.5, 1e-9));
      v.reset(size);
      expect(v.yawDeg, 350);
      expect(v.pitchDeg, 0);
      expect(v.zoom, 1);
      // Tall views raise the minimum zoom (≤ 180° vertically).
      final tall = PanoramaViewState(zoom: 0.75)..clamp(const Size(100, 400));
      expect(tall.fovV(const Size(100, 400)), lessThanOrEqualTo(180 + 1e-9));
    });

    test('101b – screen ↔ direction round trip and direction presets', () {
      final v = PanoramaViewState(yawDeg: 10)..clamp(size);
      expect(v.screenOf(10, 0, size), const Offset(200, 150));
      final p = v.screenOf(355, 5, size); // across the 0° seam
      expect(p.dx, closeTo(200 - 15 / 0.225, 1e-6));
      final (yaw, pitch) = v.directionAt(p, size);
      expect(yaw, closeTo(355, 1e-6));
      expect(pitch, closeTo(5, 1e-6));
      expect(PanoramaViewState.wrapDelta(350), -10);
      expect(PanoramaViewState.wrapDelta(-190), 170);
      expect(PanoramaDirection.e.yawFor(300), 30);
      expect(PanoramaDirection.s.yawFor(0), 180);
      v.lookAt(PanoramaDirection.w.yawFor(0), size);
      expect(v.yawDeg, 270);
    });
  });

  group('Placements', () {
    test('102 – yaw / pitch placements survive a reload and zoom', () async {
      final store = MemoryLocalStore();
      final c = await _controller(store: store);
      final shop = c.shop(_shopId)!;
      final unit = shop.boards.first.units.first;
      final p = c.addPanorama(
        shopId: _shopId,
        path: '/fake/p.jpg',
        width: 4096,
        height: 2048,
      );
      final placement = PanoramaPlacement(
        id: 'pp_1',
        unitId: unit.id,
        yawDeg: 372, // normalised to 12
        pitchDeg: -8.5,
        scale: 1.6,
        rotationDeg: 12,
        createdAt: DateTime(2026, 11, 18, 9),
      );
      c.savePanoramaPlacements(p.id, [placement]);
      c.setPanoramaNorth(p.id, -30);
      await c.flush();

      final again = await _controller(store: store);
      final back = again.panorama(p.id)!;
      expect(back.northYawDeg, 330);
      final q = back.placements.single;
      expect(q.id, 'pp_1');
      expect(q.unitId, unit.id);
      expect(q.yawDeg, 12);
      expect(q.pitchDeg, -8.5);
      expect(q.scale, 1.6);
      expect(q.rotationDeg, 12);
      expect(q.createdAt, DateTime(2026, 11, 18, 9));
      // Looking at the placement centres it at every zoom level.
      const size = Size(400, 300);
      for (final z in [0.8, 1.0, 2.5]) {
        final v = PanoramaViewState(yawDeg: q.yawDeg, zoom: z)..clamp(size);
        v.pitchDeg = q.pitchDeg;
        expect(v.screenOf(q.yawDeg, q.pitchDeg, size), const Offset(200, 150));
      }
      // Malformed placements are skipped, not fatal.
      final parsed = PanoramaRecord.fromJson({
        ...back.toJson(),
        'placements': [
          {'id': '', 'unitId': 'x'},
          q.toJson(),
        ],
      });
      expect(parsed.placements.map((e) => e.id), ['pp_1']);
    });

    test('deleting the shop removes its panoramas and files', () async {
      final media = _RecordingMedia();
      final c = await _controller(media: media);
      final draft = Shop(id: 'tmp', projectId: '', taskId: '', name: 'Temp');
      final task = c.visibleTasks.first;
      final s = c.createShop(task, draft);
      final p = c.addPanorama(
        shopId: s.id,
        path: '/fake/p.jpg',
        width: 4000,
        height: 2000,
      );
      c.addPanoramaPreview(p.id, '/fake/preview.png');
      await c.deleteShop(s.id);
      expect(c.panorama(p.id), isNull);
      expect(media.deleted, containsAll(['/fake/p.jpg', '/fake/preview.png']));
    });
  });

  group('Panorama screens', () {
    Widget host(AppController c, Widget child) =>
        ChangeNotifierProvider<AppController>.value(
          value: c,
          child: MaterialApp(theme: AppTheme.light(), home: child),
        );

    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    testWidgets('103/105 – empty list, guided capture unsupported card', (
      tester,
    ) async {
      phone(tester);
      final c = await _controller();
      await tester.pumpWidget(
        host(c, const PanoramaListScreen(shopId: _shopId)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pano_guided_unsupported')), findsOneWidget);
      expect(
        find.textContaining('not supported on this build'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Live Preview remain available'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pano_empty')), findsOneWidget);
      expect(find.byKey(const Key('pano_import')), findsOneWidget);
    });

    testWidgets('104 – permission denied from the picker is explained', (
      tester,
    ) async {
      phone(tester);
      final c = await _controller();
      final picker = FakePicker(
        error: const PanoramaPickerException(
          PanoramaPickerFailure.permissionDenied,
          'Photo access was denied.',
        ),
      );
      await tester.pumpWidget(
        host(c, PanoramaListScreen(shopId: _shopId, picker: picker)),
      );
      await tester.tap(find.byKey(const Key('pano_import')));
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(find.byKey(const Key('pano_import_error')), findsOneWidget);
      expect(find.text('Photo access was denied.'), findsOneWidget);
      expect(find.byKey(const Key('pano_open_settings')), findsOneWidget);
      expect(c.panoramasForShop(_shopId), isEmpty);

      // Cancelled picking: no error, nothing stored.
      picker
        ..error = null
        ..result = null;
      await tester.tap(find.byKey(const Key('pano_import')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pano_import_error')), findsNothing);
      expect(c.panoramasForShop(_shopId), isEmpty);
    });

    testWidgets('105 – viewer without a panorama / with a broken file', (
      tester,
    ) async {
      phone(tester);
      final c = await _controller();
      await tester.pumpWidget(
        host(
          c,
          const PanoramaViewerScreen(shopId: _shopId, panoramaId: 'missing'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pano_missing')), findsOneWidget);

      final p = c.addPanorama(
        shopId: _shopId,
        path: '/nowhere.jpg',
        width: 4000,
        height: 2000,
      );
      await tester.pumpWidget(
        host(
          c,
          PanoramaViewerScreen(
            key: const Key('second'),
            shopId: _shopId,
            panoramaId: p.id,
            imageLoader: (_) async => throw Exception('missing file'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pano_load_error')), findsOneWidget);
      // Still usable (grid placeholder): panning does not crash.
      await tester.drag(
        find.byKey(const Key('pano_canvas')),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('106 – import, view, pan, zoom, place and save', (
      tester,
    ) async {
      phone(tester);
      final store = MemoryLocalStore();
      final c = await _controller(store: store);
      final image = (await tester.runAsync(
        () => createTestImage(width: 400, height: 200, cache: false),
      ))!;
      addTearDown(image.dispose);
      final writer = RecordingWriter();
      final previews = <Uint8List>[];
      await tester.pumpWidget(
        host(
          c,
          PanoramaListScreen(
            shopId: _shopId,
            picker: FakePicker(result: _picked),
            probe: FakeProbe(4000, 2000),
            writer: writer.call,
            imageLoader: (_) async => image.clone(),
            previewWriter: (png) async {
              previews.add(png);
              return '/fake/panoramas/preview.png';
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('pano_import')));
      await tester.pumpAndSettle();
      // Let the "Panorama imported" snackbar time out (it covers the
      // bottom placement panel).
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final pano = c.panoramasForShop(_shopId).single;
      expect(find.byKey(Key('pano_${pano.id}')), findsOneWidget);
      expect(find.byKey(const Key('pano_empty')), findsNothing);

      await tester.tap(find.byKey(Key('pano_${pano.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pano_canvas')), findsOneWidget);
      expect(find.byKey(const Key('pano_honesty')), findsOneWidget);
      String readout() =>
          tester.widget<Text>(find.byKey(const Key('pano_readout'))).data!;
      expect(readout(), startsWith('Yaw 0°'));

      await tester.drag(
        find.byKey(const Key('pano_canvas')),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();
      expect(readout(), isNot(startsWith('Yaw 0°')));
      await tester.tap(find.byKey(const Key('pano_zoom_in')));
      await tester.pumpAndSettle();
      expect(readout(), isNot(endsWith('1.0×')));
      await tester.tap(find.byKey(const Key('pano_reset')));
      await tester.pumpAndSettle();
      expect(readout(), 'Yaw 0° • Pitch 0° • 1.0×');
      await tester.tap(find.byKey(const Key('pano_dir_e')));
      await tester.pumpAndSettle();
      expect(readout(), startsWith('Yaw 90°'));

      // Place the first signage item at the view centre.
      await tester.tap(find.byKey(const Key('pano_place')));
      await tester.pumpAndSettle();
      final markers = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('pano_mark_'),
      );
      expect(markers, findsOneWidget);
      await tester.drag(markers, const Offset(40, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pano_save')));
      await tester.pumpAndSettle();
      final saved = c.panorama(pano.id)!.placements.single;
      expect(saved.unitId, c.shop(_shopId)!.boards.first.units.first.id);
      expect(saved.yawDeg, greaterThan(90));
      expect(saved.pitchDeg, closeTo(0, 1e-9));

      await tester.pump(const Duration(seconds: 5)); // snackbar gone
      await tester.pumpAndSettle();
      // Preview rendering needs the real engine (runAsync).
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('pano_save_preview')));
        for (var i = 0; i < 20 && previews.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();
      expect(previews, hasLength(1));
      expect(previews.single.sublist(1, 4), [0x50, 0x4E, 0x47]); // "PNG"
      expect(c.panorama(pano.id)!.previews, ['/fake/panoramas/preview.png']);
      // Let the "Preview saved" snackbar finish before the test ends.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('106b – read-only recce: view only', (tester) async {
      phone(tester);
      final vendor = await _controller();
      // Read-only shop with a panorama (inserted directly as stored data).
      final shop = vendor.shop(_readOnlyShopId)!;
      vendor.data.panoramas.add(
        PanoramaRecord(
          id: 'pano_ro',
          shopId: shop.id,
          projectId: shop.projectId,
          taskId: shop.taskId,
          path: '/fake/ro.jpg',
          width: 4000,
          height: 2000,
          importedAt: DateTime(2026, 11, 18),
          placements: [
            PanoramaPlacement(
              id: 'pp_ro',
              unitId: shop.boards.first.units.first.id,
              yawDeg: 0,
              pitchDeg: 0,
              createdAt: DateTime(2026, 11, 18),
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        host(vendor, const PanoramaListScreen(shopId: _readOnlyShopId)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pano_import')), findsNothing);
      expect(find.byKey(const Key('pano_read_only')), findsOneWidget);
      expect(find.byKey(const Key('pano_delete_pano_ro')), findsNothing);
      await tester.pumpWidget(
        host(
          vendor,
          PanoramaViewerScreen(
            shopId: _readOnlyShopId,
            panoramaId: 'pano_ro',
            imageLoader: (_) async => throw Exception('no file in tests'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pano_mark_pp_ro')), findsOneWidget);
      expect(find.byKey(const Key('pano_place')), findsNothing);
      expect(find.byKey(const Key('pano_save')), findsNothing);
      expect(find.byKey(const Key('pano_save_preview')), findsNothing);
      await tester.drag(
        find.byKey(const Key('pano_mark_pp_ro')),
        const Offset(50, 0),
      );
      await tester.pumpAndSettle();
      expect(vendor.panorama('pano_ro')!.placements.single.yawDeg, 0);
    });
  });
}

Future<String> _noWrite(Uint8List bytes, String extension) async =>
    throw StateError('must not write');
