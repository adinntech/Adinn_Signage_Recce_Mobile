import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/catalog/site_checklists.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/annotation/annotation_editor_screen.dart';
import 'package:signage_recce/features/approvals/review_screen.dart';
import 'package:signage_recce/features/ar/ar_model_builder.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/features/home/home_shell.dart';
import 'package:signage_recce/features/home/shop_search.dart';
import 'package:signage_recce/features/model3d/signage_spec.dart';
import 'package:signage_recce/features/preview3d/preview_3d_screen.dart';
import 'package:signage_recce/features/preview3d/signage_scene_builder.dart';
import 'package:signage_recce/features/preview_live/live_preview_controller.dart'
    show unitGeometry;
import 'package:signage_recce/features/shop/shop_detail_screen.dart';
import 'package:signage_recce/features/submission/submission_screen.dart';
import 'package:signage_recce/features/survey/readiness.dart';
import 'package:signage_recce/features/survey/unit_survey_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

import 'helpers.dart';

/// A store whose writes can be made to fail (disk full, permissions…).
class FlakyStore extends MemoryLocalStore {
  bool fail = false;

  @override
  Future<void> write(Map<String, dynamic> data) async {
    if (fail) throw const FileSystemLikeException('No space left on device');
    return super.write(data);
  }
}

class FileSystemLikeException implements Exception {
  const FileSystemLikeException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<AppController> _vendor([LocalStore? store]) async {
  final c = AppController(store: store ?? MemoryLocalStore());
  await c.init();
  c.loginWithPin(DemoAccounts.vendorPin);
  return c;
}

Widget _host(AppController c, Widget child) =>
    ChangeNotifierProvider<AppController>.value(
      value: c,
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Board _gsb(AppController c) => c.addBoard('s_lakshmi')
  ..mediaCode = SignageCatalog.gsb
  ..installationCode = SignageCatalog.wallMount
  ..width = 8
  ..height = 3;

SitePhoto _photo(String id) => SitePhoto(
  id: id,
  path: 'demo://2',
  label: 'Front view',
  capturedAt: DateTime(2026, 11, 19),
  width: 1200,
  height: 900,
);

void main() {
  group('readiness indicator', () {
    test('needs clarification → ready → installation constraint', () async {
      final c = await _vendor();
      final shop = c.shop('s_lakshmi')!;
      final b = c.addBoard(shop.id)..mediaCode = SignageCatalog.gsb;
      final u = b.units.first;
      var r = unitReadiness(shop, b, u);
      expect(r.level, RecceReadiness.needsClarification);
      expect(r.missing, contains('Installation type not selected'));
      expect(r.missing, contains('Width / height not entered'));

      b
        ..installationCode = SignageCatalog.wallMount
        ..width = 8
        ..height = 3;
      c.addPhoto(shop.id, b.id, _photo('p1'));
      completeAnswers(b);
      // The helper answers "Yes" everywhere; answers that flag a site
      // constraint (visible wires, AC unit…) are set to "No" here.
      for (final q in SiteChecklists.questionsFor(
        b.mediaCode,
        b.installationCode,
      )) {
        if (q.reviewIfYes) {
          u.checklist[q.id] = ChecklistResponse(questionId: q.id, value: 'no');
        }
      }
      r = unitReadiness(shop, b, u);
      expect(r.level, RecceReadiness.readyForReview, reason: '${r.reasons}');
      expect(readyUnitCount(shop), (1, 1));

      final p = b.photos.first;
      p.markup.obstructions.add(
        ObstructionMark(
          id: 'o1',
          photoId: p.id,
          type: ObstructionType.acUnit,
          shape: ObstructionShape.point,
          number: 1,
          points: const [SurveyPoint(0.5, 0.5)],
          severity: Severity.high,
          unitIds: [u.id],
        ),
      );
      r = unitReadiness(shop, b, u);
      expect(r.level, RecceReadiness.installationConstraint);
      expect(r.constraints.single, contains('AC Outdoor Unit'));
      expect(shopReadiness(shop), RecceReadiness.installationConstraint);
    });
  });

  group('single source of truth in Live Preview / AR', () {
    test('new media models use recorded letter depth', () async {
      final c = await _vendor();
      final b = c.addBoard('s_lakshmi')
        ..mediaCode = SignageCatalog.acp3dDouble
        ..installationCode = SignageCatalog.doublePole
        ..width = 8
        ..height = 3;
      final u = b.units.first;
      final g1 = unitGeometry(b, u);
      expect(g1.spec, isNotNull);
      expect(g1.spec![SpecField.letterDepthFront], 50, reason: 'default');
      double depth(Board b) {
        final s = SignageSceneBuilder.buildModel(unitGeometry(b, u));
        return s.boundsMax.z - s.boundsMin.z;
      }

      final before = depth(b);
      c.applySpecEdits('s_lakshmi', b.id, u.id, {
        SpecField.letterDepthFront: 300,
      });
      final g2 = unitGeometry(b, u);
      expect(g2.spec![SpecField.letterDepthFront], 300);
      expect(g2 == g1, isFalse, reason: 'model cache refreshes');
      expect(depth(b), greaterThan(before));
      // GSB keeps the legacy builder (no spec attached).
      expect(unitGeometry(_gsb(c), _gsb(c).units.first).spec, isNull);
    });

    test('support-pipe boards prefer vertical AR surfaces', () {
      expect(prefersVerticalPlacement(SignageCatalog.supportPipe), isTrue);
      expect(prefersVerticalPlacement(SignageCatalog.doublePole), isFalse);
    });
  });

  group('validation & recovery', () {
    test('possible duplicate media groups are flagged, not blocked', () async {
      final c = await _vendor();
      final shop = c.shop('s_lakshmi')!;
      _gsb(c);
      expect(c.shopWarnings(shop), isEmpty);
      _gsb(c);
      expect(
        c.shopWarnings(shop).single,
        contains('check they are not entered twice'),
      );
      final third = _gsb(c)..installationCode = SignageCatalog.shopFascia;
      expect(c.shopWarnings(shop), hasLength(1), reason: '$third differs');
    });

    test('storage write failure is surfaced and retried', () async {
      final store = FlakyStore();
      final c = await _vendor(store);
      store.fail = true;
      c.touchShop(c.shop('s_lakshmi')!);
      await c.flush();
      expect(c.storageError, contains('No space left'));
      store.fail = false;
      await c.retrySave();
      expect(c.storageError, isNull);
      expect(store.writes, greaterThan(0));
    });

    test('form drafts persist across an app restart', () async {
      final store = MemoryLocalStore();
      final c = await _vendor(store);
      c.saveFormDraft('measure:u1', {
        'valuesMm': {'bottom_height': 2743.2},
        'unit': 'ft',
      });
      await c.flush();
      final again = AppController(store: MemoryLocalStore(store.data));
      await again.init();
      expect(again.formDraft('measure:u1')!['valuesMm'], {
        'bottom_height': 2743.2,
      });
      again.clearFormDraft('measure:u1');
      expect(again.formDraft('measure:u1'), isNull);
    });

    testWidgets('home shows the storage error banner with Retry', (
      tester,
    ) async {
      _phone(tester);
      final store = FlakyStore();
      final c = await _vendor(store);
      store.fail = true;
      c.touchShop(c.shop('s_lakshmi')!);
      await tester.runAsync(c.flush);
      await tester.pumpWidget(_host(c, const HomeShell()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('storage_error')), findsOneWidget);
      store.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.runAsync(c.flush);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('storage_error')), findsNothing);
    });

    testWidgets('interrupted measurement entry is restored, then discarded', (
      tester,
    ) async {
      _phone(tester);
      final store = MemoryLocalStore();
      final c = await _vendor(store);
      final b = _gsb(c);
      final u = b.units.first;
      await tester.pumpWidget(
        _host(
          c,
          UnitSurveyScreen(shopId: 's_lakshmi', boardId: b.id, unitId: u.id),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('m_bottom_height')), '9');
      await tester.pumpAndSettle();
      await tester.runAsync(c.flush);
      expect(c.formDraft('measure:${u.id}'), isNotNull, reason: 'auto-saved');
      // "App killed": take the stored data without leaving the screen.
      await tester.runAsync(c.flush);
      final killed = jsonDecode(jsonEncode(store.data)) as Map<String, dynamic>;
      expect(u.measurements.mm('bottom_height'), isNull, reason: 'not saved');

      final c2 = AppController(store: MemoryLocalStore(killed));
      await tester.runAsync(c2.init);
      c2.loginWithPin(DemoAccounts.vendorPin);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _host(
          c2,
          UnitSurveyScreen(shopId: 's_lakshmi', boardId: b.id, unitId: u.id),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('m_draft_restored')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('m_bottom_height')))
            .controller!
            .text,
        '9',
      );
      await tester.tap(find.byKey(const Key('m_draft_discard')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('m_draft_restored')), findsNothing);
      expect(c2.formDraft('measure:${u.id}'), isNull);
    });
  });

  group('screens', () {
    testWidgets('dashboard: search shops and continue drafts', (tester) async {
      _phone(tester);
      final c = await _vendor();
      expect(
        searchShops(c, 'srirangam').map((s) => s.id),
        contains('s_sriranga'),
      );
      expect(searchShops(c, 'zzz'), isEmpty);
      await tester.pumpWidget(_host(c, const HomeShell()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dashboard_search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Sri Ranga');
      await tester.pumpAndSettle();
      expect(find.text('Sri Ranga Paints & Hardwares'), findsWidgets);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('continue_drafts')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('continue_drafts')), findsOneWidget);
    });

    testWidgets('shop progress card continues the first incomplete group', (
      tester,
    ) async {
      _phone(tester);
      final c = await _vendor();
      await tester.pumpWidget(
        _host(c, const ShopDetailScreen(shopId: 's_sriranga')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('recce_progress')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('recce_progress')), findsOneWidget);
      final cont = find.byKey(const Key('continue_recce'));
      if (cont.evaluate().isNotEmpty) {
        await tester.ensureVisible(cont);
        await tester.pumpAndSettle();
        await tester.tap(cont);
        await tester.pumpAndSettle();
        expect(find.byType(BoardEditorScreen), findsOneWidget);
      }
    });

    testWidgets('submit screen: tap a media group to fix it', (tester) async {
      _phone(tester);
      final c = await _vendor();
      final b = c.board('s_sriranga', c.shop('s_sriranga')!.boards.first.id)!;
      await tester.pumpWidget(
        _host(c, const SubmissionScreen(shopId: 's_sriranga')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('submit_board_${b.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(BoardEditorScreen), findsOneWidget);
    });

    testWidgets('reviewer sees units grouped by media type', (tester) async {
      _phone(tester);
      final c = AppController(store: MemoryLocalStore());
      await c.init();
      c.loginWithPin(DemoAccounts.businessPin);
      await tester.pumpWidget(_host(c, const ReviewScreen(shopId: 's_amma')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('review_unit_summary')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('review_unit_summary')), findsOneWidget);
      expect(find.textContaining('GSB'), findsWidgets);
    });

    testWidgets('3D view options never change measurements', (tester) async {
      _phone(tester);
      final c = await _vendor();
      final b = c.addBoard('s_lakshmi')
        ..mediaCode = SignageCatalog.mdfGsbDouble
        ..installationCode = SignageCatalog.doublePole
        ..width = 8
        ..height = 3;
      final before = jsonEncode(b.toJson());
      await tester.pumpWidget(
        _host(c, Preview3DScreen(shopId: 's_lakshmi', boardId: b.id)),
      );
      await tester.pumpAndSettle();
      for (final k in [
        'view_xray',
        'view_night',
        'view_context',
        'view_selected_dims',
      ]) {
        await tester.ensureVisible(find.byKey(Key(k)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(k)));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(const Key('comp_gsb_box')));
      await tester.tap(find.byKey(const Key('comp_gsb_box')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('model_error')), findsNothing);
      expect(jsonEncode(b.toJson()), before);
    });

    testWidgets('legacy media: 3D clearance edit updates the measurement', (
      tester,
    ) async {
      _phone(tester);
      final c = await _vendor();
      final b = c.addBoard('s_lakshmi')
        ..mediaCode = SignageCatalog.vinyl
        ..installationCode = SignageCatalog.directWall
        ..width = 6
        ..height = 3;
      final u = b.units.first;
      u.measurements.valuesMm['bottom_height'] = 3 * 304.8;
      await tester.pumpWidget(
        _host(c, Preview3DScreen(shopId: 's_lakshmi', boardId: b.id)),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('clearance-slider')),
        const Offset(80, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply to board'));
      await tester.pumpAndSettle();
      final answer = (b.answers['mount_height'] as num).toDouble();
      expect(answer, isNot(3));
      expect(u.measurements.mm('bottom_height'), closeTo(answer * 304.8, 1e-6));
    });

    testWidgets('photo editor tool categories filter the tool bar', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: AnnotationEditorScreen(
            photo: _photo('p'),
            boardName: 'GSB',
            extraTools: [
              AnnotationExtraTool(
                id: 'perspective',
                icon: Icons.crop_rotate,
                label: 'Perspective',
                onTap: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tool-arrow')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tool-group-measure')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tool-arrow')), findsNothing);
      expect(find.byKey(const ValueKey('tool-dimension')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('tool-group-site')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tool-group-site')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('tool-extra-perspective')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('tool-group-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tool-group-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tool-arrow')), findsOneWidget);
    });
  });
}
