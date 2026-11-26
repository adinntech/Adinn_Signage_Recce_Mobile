import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/ar/ar_session_controller.dart';
import 'package:signage_recce/features/gsb/gsb_comparison_pdf.dart';
import 'package:signage_recce/features/photos/photo_workspace_screen.dart';
import 'package:signage_recce/features/preview3d/preview_3d_screen.dart';
import 'package:signage_recce/features/preview3d/renderer_painter.dart';
import 'package:signage_recce/features/preview_live/live_preview_controller.dart';
import 'package:signage_recce/features/preview_live/live_preview_render.dart';
import 'package:signage_recce/state/app_controller.dart';

SitePhoto _photo() => SitePhoto(
  id: 'ph',
  path: 'demo://2',
  label: 'Front view',
  capturedAt: DateTime(2026),
  width: 1200,
  height: 900,
);

Board _gsb() {
  final b = Board(
    id: 'g',
    name: 'Group',
    mediaCode: SignageCatalog.gsb,
    installationCode: SignageCatalog.shopFascia,
    width: 8,
    height: 3,
    doubleSided: false,
  );
  b.photos.add(_photo());
  return b;
}

Offset _map(List<double> m, double u, double v) {
  final w = m[6] * u + m[7] * v + 1;
  return Offset(
    (m[0] * u + m[1] * v + m[2]) / w,
    (m[3] * u + m[4] * v + m[5]) / w,
  );
}

class _FakeRenderViewAr extends UnavailableArPlatform
    implements ArRenderViewCapable {
  final nights = <bool>[];

  @override
  Future<void> setNightMode(bool night) async => nights.add(night);

  @override
  Future<Map<String, Uint8List>?> captureRenderSet() async => null;
}

void main() {
  group('Live Preview distortion fixes', () {
    test('perspective label mapping hits all four projected corners', () {
      const quads = [
        [Offset(0, 0), Offset(100, 0), Offset(100, 40), Offset(0, 40)],
        // Turned board: right edge nearer (taller) – a true trapezoid.
        [Offset(10, 20), Offset(120, 5), Offset(120, 75), Offset(10, 60)],
      ];
      for (final q in quads) {
        final m = Scene3DPainter.squareToQuad(q)!;
        const uv = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)];
        for (var i = 0; i < 4; i++) {
          final p = _map(m, uv[i].$1, uv[i].$2);
          expect((p - q[i]).distance, lessThan(1e-6));
        }
      }
      // Mirrored (flipped) and collapsed quads are rejected.
      expect(
        Scene3DPainter.squareToQuad(const [
          Offset(100, 0),
          Offset(0, 0),
          Offset(0, 40),
          Offset(100, 40),
        ]),
        isNull,
      );
      expect(
        Scene3DPainter.squareToQuad(const [
          Offset(0, 0),
          Offset(50, 0),
          Offset(100, 0),
          Offset(150, 0),
        ]),
        isNull,
      );
    });

    test('non-finite transforms are rejected, valid state kept', () {
      final c = LivePreviewController(board: _gsb(), photo: _photo())
        ..addUnit('g_u1');
      c.setScale(0.6);
      c.setPosition(0.4, 0.3);
      c.setScale(double.nan);
      c.setPosition(double.infinity, 0.5);
      c.setRotation(double.nan);
      c.setYaw(double.nan);
      final o = c.selected!;
      expect(o.scale, 0.6);
      expect((o.cx, o.cy), (0.4, 0.3));
      expect(o.rotation.isFinite && o.yaw.isFinite, isTrue);
    });

    test('perspective range is symmetric (view from below reachable)', () {
      expect(LivePreviewController.minPitch, -LivePreviewController.maxPitch);
      final c = LivePreviewController(board: _gsb(), photo: _photo())
        ..addUnit('g_u1');
      c.setPitch(-0.4);
      expect(c.selected!.pitch, -0.4);
    });

    test('day / night switch never touches the placement', () {
      final c = LivePreviewController(board: _gsb(), photo: _photo())
        ..addUnit('g_u1');
      c
        ..setPosition(0.3, 0.6)
        ..setScale(0.7)
        ..setYaw(0.4)
        ..setPitch(-0.2)
        ..setRotation(0.1);
      final before = jsonEncode(c.selected!.toJson());
      c.setView(RenderView.night);
      expect(c.view, RenderView.night);
      expect(jsonEncode(c.selected!.toJson()), before);
      c.setView(RenderView.day);
      expect(jsonEncode(c.selected!.toJson()), before);
    });

    testWidgets('composer renders original / day / night at photo aspect', (
      tester,
    ) async {
      final b = _gsb();
      final c = LivePreviewController(board: b, photo: b.photos.first)
        ..addUnit('g_u1');
      final comp = LivePreviewComposer(
        photo: b.photos.first,
        image: null,
        overlays: c.overlays,
        sceneFor: c.sceneFor,
      );
      final out = await tester.runAsync(() async {
        return [
          await comp.render(models: false, maxSide: 400),
          await comp.render(maxSide: 400),
          await comp.render(view: RenderView.night, maxSide: 400),
        ];
      });
      final pngs = out!.cast<Uint8List?>();
      expect(pngs.every((p) => p != null && p.isNotEmpty), isTrue);
      final decoded = [for (final p in pngs) img.decodePng(p!)!];
      for (final d in decoded) {
        expect((d.width, d.height), (400, 300)); // 4:3, never stretched
      }
      // Original ≠ day (board added), day ≠ night (grade applied).
      expect(base64Encode(pngs[0]!) == base64Encode(pngs[1]!), isFalse);
      expect(base64Encode(pngs[1]!) == base64Encode(pngs[2]!), isFalse);
      // Night is darker on average than day.
      double mean(img.Image i) {
        var s = 0.0;
        for (final p in i) {
          s += p.luminanceNormalized;
        }
        return s / (i.width * i.height);
      }

      expect(mean(decoded[2]), lessThan(mean(decoded[1])));
    });
  });

  group('GSB comparison PDF', () {
    PdfPicture pic(int w, int h) =>
        PdfPicture(img.encodePng(img.Image(width: w, height: h)), w, h);

    test(
      'four pages with long shop name and portrait / landscape images',
      () async {
        final bytes = await buildGsbComparisonPdf(
          GsbComparisonData(
            source: 'Live Preview',
            projectName: 'Asian Paints',
            shopName:
                'Sri Ranga Paints & Hardwares – a very long shop name that '
                'keeps going to test wrapping × “quotes” • bullets',
            boardName: 'Main Board',
            unitLabel: 'Unit 01',
            variantLabel: 'GSB Double Side',
            sizeText: 'W 10 ft x H 4 ft',
            capturedAt: DateTime(2026, 11, 21, 10, 30),
            original: pic(30, 40),
            day: pic(40, 30),
            night: pic(40, 30),
            mountingText: '9 ft 6 in',
            depthText: '8 in',
            reviewNotes: const ['Night glow on both faces is illustrative.'],
            ruleVersion: 'SFR-1.0',
          ),
        );
        expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
        final text = latin1.decode(bytes);
        expect(RegExp(r'/Type\s*/Page[^s]').allMatches(text).length, 4);
      },
    );
  });

  group('Camera AR render view', () {
    test('night mode forwards only to capable engines', () {
      final fake = _FakeRenderViewAr();
      final ar = ArSessionController(
        platform: fake,
        model: const ArModelSpec(
          mediaCode: 'GSB',
          installationCode: 'shop_fascia',
          widthFt: 8,
          heightFt: 3,
          label: 'GSB',
        ),
      );
      expect(ar.supportsRenderView, isTrue);
      ar.setNightMode(true);
      expect(ar.nightMode, isTrue);
      expect(fake.nights, [true]);
      ar.setNightMode(true); // no duplicate call
      expect(fake.nights, [true]);
      ar.dispose();

      final plain = ArSessionController(
        platform: const UnavailableArPlatform(),
        model: const ArModelSpec(
          mediaCode: 'NLB',
          installationCode: 'shop_fascia',
          widthFt: 8,
          heightFt: 3,
          label: 'NLB',
        ),
      );
      expect(plain.supportsRenderView, isFalse);
      plain.dispose();
    });

    test('render-set capture refuses without a placed model', () async {
      final ar = ArSessionController(
        platform: _FakeRenderViewAr(),
        model: const ArModelSpec(
          mediaCode: 'GSB',
          installationCode: 'shop_fascia',
          widthFt: 8,
          heightFt: 3,
          label: 'GSB',
        ),
      );
      expect(await ar.captureRenderSet(), isNull);
      expect(ar.error, isNotNull);
      ar.dispose();
    });
  });

  group('screens', () {
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

    testWidgets('Render View only for GSB; night keeps the placement', (
      tester,
    ) async {
      final c = await boot(tester);
      final shop = c.shop('s_sriranga')!;
      final b = shop.boards.first;
      expect(b.mediaCode, SignageCatalog.gsb);
      Future<void> open() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          host(
            c,
            PhotoWorkspaceScreen(
              shopId: shop.id,
              boardId: b.id,
              photoId: b.photos.first.id,
              initialTab: 1,
              writer: (png, folder) async => '/fake/$folder.png',
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await open();
      expect(find.byKey(const ValueKey('live_render_view')), findsOneWidget);
      expect(find.byKey(const ValueKey('live_add_item')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('live_render_view')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('render_view_night')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live_night_badge')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Other media types never get the control.
      b.mediaCode = SignageCatalog.nlb;
      await open();
      expect(find.byKey(const ValueKey('live_render_view')), findsNothing);
      expect(find.byKey(const ValueKey('live_night_badge')), findsNothing);
      b.mediaCode = SignageCatalog.mdfGsb;
      await open();
      expect(find.byKey(const ValueKey('live_render_view')), findsNothing);
    });

    testWidgets('3D preview: exact width entry, invalid text ignored', (
      tester,
    ) async {
      final c = await boot(tester);
      final b = c.board('s_sriranga', 'b_sriranga_1')!;
      expect(b.width, 10);
      await tester.pumpWidget(
        host(
          c,
          const Preview3DScreen(shopId: 's_sriranga', boardId: 'b_sriranga_1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gsb_fab_panel')), findsOneWidget);
      expect(find.byKey(const Key('gsb_render_view')), findsOneWidget);
      final field = find.byKey(const Key('width-exact'));
      expect(field, findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: field, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        '10 ft',
      );

      // Invalid text: nothing changes.
      await tester.enterText(field, 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Apply to board'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Apply to board'),
                matching: find.byWidgetPredicate((w) => w is FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );

      // Exact feet + inches beyond the old slider steps.
      await tester.enterText(field, '12 ft 7 in');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(
        find.byKey(const Key('width-slider')),
      );
      expect(slider.value * 12, closeTo(151, 1e-9));
      await tester.tap(find.text('Apply to board'));
      await tester.pumpAndSettle();
      expect(b.width! * 12, closeTo(151, 1e-6));
      expect(tester.takeException(), isNull);
    });
  });
}
