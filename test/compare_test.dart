import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/compare/comparison_renderer.dart';
import 'package:signage_recce/features/compare/comparison_screen.dart';
import 'package:signage_recce/features/survey/site_markup_painter.dart';
import 'package:signage_recce/state/app_controller.dart';

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget _host(AppController c, Widget child) =>
    ChangeNotifierProvider<AppController>.value(
      value: c,
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );

class _FakeRenderer extends ComparisonRenderer {
  final requests = <ComparisonRenderRequest>[];

  @override
  Future<Uint8List?> render(ComparisonRenderRequest request) async {
    requests.add(request);
    return Uint8List.fromList([137, 80, 78, 71]);
  }
}

PreviewCapture _capture(
  Shop s,
  Board b,
  String id, {
  required String photoId,
  CaptureKind kind = CaptureKind.live,
  required DateTime at,
  String? unitId,
}) => PreviewCapture(
  id: id,
  kind: kind,
  projectId: s.projectId,
  taskId: s.taskId,
  shopId: s.id,
  groupId: b.id,
  unitId: unitId ?? b.units.first.id,
  photoId: photoId,
  path: '/no/such/dir/$id.png',
  createdAt: at,
);

class _Rig {
  _Rig(this.c, this.shop, this.board, this.photo);

  final AppController c;
  final Shop shop;
  final Board board;
  final SitePhoto photo;

  static Future<_Rig> create({bool previews = true}) async {
    final c = AppController(store: MemoryLocalStore());
    await c.init();
    c.loginWithPin('5678');
    final shop = c.shop('s_sriranga')!;
    final b = shop.boards.first;
    c.increaseQuantity(shop.id, b, 2);
    final photo = b.photos.first;
    b.photos.add(
      SitePhoto(
        id: 'ph_second',
        path: '${SitePhoto.demoPrefix}3',
        label: 'Left angle',
        capturedAt: DateTime(2026, 11, 18),
        width: 1200,
        height: 900,
      ),
    );
    if (previews) {
      b.previews.addAll([
        _capture(
          shop,
          b,
          'cap_1',
          photoId: photo.id,
          at: DateTime(2026, 11, 1),
        ),
        _capture(
          shop,
          b,
          'cap_2',
          photoId: photo.id,
          at: DateTime(2026, 11, 2),
          unitId: b.units[1].id,
        ),
        // AR captures are never aligned to the photo.
        _capture(
          shop,
          b,
          'cap_ar',
          photoId: photo.id,
          kind: CaptureKind.ar,
          at: DateTime(2026, 11, 3),
        ),
        // Live preview of another photo.
        _capture(
          shop,
          b,
          'cap_other',
          photoId: 'ph_second',
          at: DateTime(2026, 11, 4),
        ),
      ]);
    }
    return _Rig(c, shop, b, photo);
  }
}

void main() {
  group('proposed options', () {
    test('73-74: only live previews of the same photo, numbered', () async {
      final r = await _Rig.create();
      final opts = ProposedOption.forPhoto(r.board, r.photo);
      expect(opts.map((o) => o.key), ['live:cap_1', 'live:cap_2']);
      expect(opts.first.label, startsWith('Live preview 1 of 2 • '));
      expect(opts.last.label, startsWith('Live preview 2 of 2 • '));
      expect(opts.every((o) => o.source == ProposedSource.livePreview), isTrue);

      final other = r.board.photos.last;
      expect(ProposedOption.forPhoto(r.board, other).map((o) => o.key), [
        'live:cap_other',
      ]);
    });

    test('perspective placement adds a live-render option', () async {
      final r = await _Rig.create(previews: false);
      expect(ProposedOption.forPhoto(r.board, r.photo), isEmpty);
      r.photo.markup.perspectives.add(
        PerspectivePlacement(
          id: 'pp1',
          photoId: r.photo.id,
          unitId: r.board.units.first.id,
          corners: PerspectivePlacement.defaultCorners(),
        ),
      );
      final opts = ProposedOption.forPhoto(r.board, r.photo);
      expect(opts.single.source, ProposedSource.perspective);
    });
  });

  group('comparison screen', () {
    testWidgets('75: side-by-side boxes share the photo aspect', (
      tester,
    ) async {
      _phone(tester);
      final r = await _Rig.create();
      await tester.pumpWidget(
        _host(
          r.c,
          ComparisonScreen(
            shopId: r.shop.id,
            boardId: r.board.id,
            photoId: r.photo.id,
            imageSize: (_) async => const Size(1200, 900),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getSize(find.byKey(const Key('cmp_before_box')));
      final proposed = tester.getSize(
        find.byKey(const Key('cmp_proposed_box')),
      );
      expect(before, proposed);
      expect(before.width / before.height, closeTo(r.photo.aspectRatio, 0.01));
      // Latest live preview selected by default and named.
      expect(find.textContaining('Live preview 2 of 2'), findsWidgets);
      expect(find.byKey(const Key('cmp_aspect_warning')), findsNothing);
      // Photo selector shown (two photos).
      expect(find.byKey(const Key('cmp_photo')), findsOneWidget);
    });

    testWidgets('76: slider divider reveals before / proposed', (tester) async {
      _phone(tester);
      final r = await _Rig.create();
      await tester.pumpWidget(
        _host(
          r.c,
          ComparisonScreen(
            shopId: r.shop.id,
            boardId: r.board.id,
            imageSize: (_) async => const Size(1200, 900),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cmp_mode_slider')));
      await tester.pumpAndSettle();
      expect(find.text('Before 50% | Proposed 50%'), findsOneWidget);
      final slider = find.byKey(const Key('cmp_slider'));
      final box = tester.getRect(slider);
      await tester.tapAt(Offset(box.left + box.width * 0.25, box.center.dy));
      await tester.pumpAndSettle();
      expect(find.text('Before 25% | Proposed 75%'), findsOneWidget);
      await tester.drag(slider, Offset(box.width * 0.5, 0));
      await tester.pumpAndSettle();
      expect(find.text('Before 100% | Proposed 0%'), findsOneWidget);
    });

    testWidgets('77: toggle and full-screen original / proposed', (
      tester,
    ) async {
      _phone(tester);
      final r = await _Rig.create();
      await tester.pumpWidget(
        _host(
          r.c,
          ComparisonScreen(
            shopId: r.shop.id,
            boardId: r.board.id,
            imageSize: (_) async => const Size(1200, 900),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cmp_mode_toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cmp_showing_proposed')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cmp_toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cmp_showing_before')), findsOneWidget);

      await tester.tap(find.byKey(const Key('cmp_fullscreen')));
      await tester.pumpAndSettle();
      expect(find.text('Original'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cmp_fs_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Proposed'), findsWidgets);
    });

    testWidgets('78-80: save stores the comparison against the item + version; '
        'original photo untouched', (tester) async {
      _phone(tester);
      final r = await _Rig.create();
      final photoJson = jsonEncode(r.photo.toJson());
      final renderer = _FakeRenderer();
      final written = <Uint8List>[];
      await tester.pumpWidget(
        _host(
          r.c,
          ComparisonScreen(
            shopId: r.shop.id,
            boardId: r.board.id,
            photoId: r.photo.id,
            renderer: renderer,
            writer: (png) async {
              written.add(png);
              return '/fake/comparisons/1.png';
            },
            imageSize: (_) async => const Size(1200, 900),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('cmp_save')));
      await tester.tap(find.byKey(const Key('cmp_save')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(written, hasLength(1));
      final rec = r.board.comparisons.single;
      // Latest live preview (cap_2) belongs to unit 2.
      expect(rec.previewId, 'cap_2');
      expect(rec.unitId, r.board.units[1].id);
      expect(rec.photoId, r.photo.id);
      expect(rec.groupId, r.board.id);
      expect(rec.source, ProposedSource.livePreview);
      expect(rec.versionLabel, startsWith('Live preview 2 of 2'));
      expect(rec.path, '/fake/comparisons/1.png');
      final req = renderer.requests.single;
      expect(req.shopName, r.shop.name);
      expect(req.itemLabel, contains('Unit 02'));
      expect(req.footer, contains('not an as-built photo'));
      // The original photo record is unchanged.
      expect(jsonEncode(r.photo.toJson()), photoJson);
      expect(r.c.activities(shopId: r.shop.id).first.title, 'Comparison saved');
      // Persisted and reloaded.
      await r.c.flush();
      final again = AppController(store: r.c.store);
      await again.init();
      expect(
        again.board(r.shop.id, r.board.id)!.comparisons.single.previewId,
        'cap_2',
      );

      // Saved list + delete (after the snack bar has gone).
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(Key('cmp_delete_${rec.id}')));
      await tester.tap(find.byKey(Key('cmp_delete_${rec.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(r.board.comparisons, isEmpty);
      expect(r.board.photos, contains(r.photo));
    });

    testWidgets('81: no proposed preview → explanation, no save', (
      tester,
    ) async {
      _phone(tester);
      final r = await _Rig.create(previews: false);
      await tester.pumpWidget(
        _host(r.c, ComparisonScreen(shopId: r.shop.id, boardId: r.board.id)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cmp_empty')), findsOneWidget);
      expect(find.byKey(const Key('cmp_save')), findsNothing);
    });

    testWidgets('82: different aspect ratio is flagged, never stretched', (
      tester,
    ) async {
      _phone(tester);
      final r = await _Rig.create();
      await tester.pumpWidget(
        _host(
          r.c,
          ComparisonScreen(
            shopId: r.shop.id,
            boardId: r.board.id,
            imageSize: (_) async => const Size(1000, 1000),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cmp_aspect_warning')), findsOneWidget);
      final img = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const Key('cmp_proposed_box')),
          matching: find.byType(Image),
        ),
      );
      expect(img.fit, BoxFit.contain);
    });

    testWidgets('reviewers (read-only) cannot save comparisons', (
      tester,
    ) async {
      _phone(tester);
      final r = await _Rig.create();
      r.c.logout();
      r.c.loginWithPin('1234');
      await tester.pumpWidget(
        _host(
          r.c,
          ComparisonScreen(
            shopId: r.shop.id,
            boardId: r.board.id,
            imageSize: (_) async => const Size(1200, 900),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cmp_save')), findsNothing);
    });
  });

  testWidgets('81: default renderer handles a missing proposed file', (
    tester,
  ) async {
    final r = await _Rig.create();
    final png = await tester.runAsync(
      () => const DefaultComparisonRenderer(panelLongSide: 120).render(
        ComparisonRenderRequest(
          photo: r.photo,
          source: ProposedSource.livePreview,
          capture: r.board.previews.first,
          labels: MarkupLabels.forShop(r.shop),
          shopName: r.shop.name,
          itemLabel: 'GSB – Unit 01',
          mediaName: 'Glow Sign Board',
          versionLabel: 'Live preview 1 of 2',
          date: DateTime(2026, 11, 18, 10, 30),
        ),
      ),
    );
    expect(png, isNotNull);
    expect(png!.sublist(0, 4), [137, 80, 78, 71]);
  });
}
