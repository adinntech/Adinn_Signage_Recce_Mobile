import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/models/photo_requirement.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/features/drawing/drawing_2d_screen.dart';
import 'package:signage_recce/features/photos/photo_workspace_screen.dart';
import 'package:signage_recce/features/photos/photo_section.dart';
import 'package:signage_recce/features/report/recce_pdf_card.dart';
import 'package:signage_recce/features/report/report_service.dart';
import 'package:signage_recce/features/shop/shop_detail_screen.dart';
import 'package:signage_recce/l10n/l10n.dart';
import 'package:signage_recce/state/app_controller.dart';

import 'helpers.dart';
import 'model_viewer_pdf_test.dart' show FakeModels;
import 'report_test.dart' show FakeImages;

const _shop = 's_lakshmi';

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 3200);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Future<void> _pump(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 300));
  await t.pumpAndSettle();
}

void main() {
  tearDown(() => PhotoSection.testCapture = null);

  testWidgets(
    'Capture -> angle -> tile tour -> Signage marking -> Save -> 2nd photo -> '
    'completion -> drawing -> PDF eligibility, all through the real UI',
    (tester) async {
      _phone(tester);
      var shots = 0;
      PhotoSection.testCapture = (source) async => SitePhoto(
        id: 'fixture',
        path: 'demo://${shots++ % 2}', // two DISTINCT original files
        label: '',
        capturedAt: DateTime(2026, 11, 26),
        width: 1200,
        height: 900,
        geo: gpsAt(10.8627, 78.6897),
      );
      final c = AppController(store: MemoryLocalStore());
      await c.init();
      c.loginWithPin(DemoAccounts.vendorPin);
      final s = c.shop(_shop)!..boards.clear();
      c.setShopLocation(s, gpsAt(10.8627, 78.6897));
      final b =
          c.addMediaGroups(_shop, [
              MediaGroupPlan(
                SignageCatalog.mediaOptions.firstWhere(
                  (o) => o.key == 'GSB_SINGLE',
                ),
                1,
              ),
            ]).single
            ..width = 5
            ..height = 3
            ..installationCode = 'shop_fascia';
      completeAnswers(b); // only questions: evidence is NOT injected
      expect(b.photos, isEmpty);
      expect(c.boardIssues(b), contains('Capture at least two site photos'));

      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: c,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: BoardEditorScreen(
              shopId: _shop,
              boardId: b.id,
              initialStep: BoardEditorScreen.siteQuestionsStep + 1,
            ),
          ),
        ),
      );
      await _pump(tester);

      // 1. Capture (camera) through the visible button, pick the angle.
      await tester.ensureVisible(find.text('Camera'));
      await tester.tap(find.text('Camera'));
      await _pump(tester);
      expect(find.text('Which angle is this photo?'), findsOneWidget);
      await tester.tap(find.text('Front view').last);
      await _pump(tester);
      expect(b.photos, hasLength(1));
      expect(b.photos.single.label, 'Front view');

      // 2. The captured tile is highlighted; first photo may be skipped.
      expect(find.byKey(const Key('photo_tour_tile')), findsOneWidget);
      expect(find.byKey(const Key('tour_skip')), findsOneWidget);
      expect(
        find.text('Open the photo to mark the proposed signage board.'),
        findsOneWidget,
      );
      expect(
        c.boardIssues(b).any((i) => i.contains('signage marking is missing')),
        isTrue,
      );

      // 3. Tap the highlighted tile itself -> Photo Editor with the tour.
      await tester.tap(find.byKey(Key('photo_tile_${b.photos.single.id}')));
      await _pump(tester);
      expect(find.byType(PhotoWorkspaceScreen), findsOneWidget);
      expect(find.text('Tap Signage to mark the board area.'), findsOneWidget);

      // 4. Signage tool -> mark the board area -> measurement sheet -> Save.
      await tester.ensureVisible(find.byKey(const ValueKey('tool-rectangle')));
      await tester.tap(find.byKey(const ValueKey('tool-rectangle')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Mark the exact area where the signage board will be installed.',
        ),
        findsOneWidget,
      );
      await tester.dragFrom(
        tester.getCenter(find.byKey(const ValueKey('annotation-canvas'))) -
            const Offset(80, 30),
        const Offset(160, 60),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tap Save to keep the marking.'), findsOneWidget);
      // Not complete until the marking is SAVED.
      expect(
        c.boardIssues(b).any((i) => i.contains('signage marking is missing')),
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('measure-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('annotation-save')));
      await tester.pumpAndSettle();
      expect(b.photos.single.annotations.single.itemId, b.units.first.id);
      expect(
        find.byKey(const Key('photo_tour')),
        findsNothing,
        reason: 'tour completes on save',
      );
      expect(
        c.boardIssues(b).any((i) => i.contains('signage marking is missing')),
        isFalse,
      );
      expect(c.boardIssues(b), contains('1 more valid site photo required'));

      // 5. Back to the section; second photo (gallery) with a saved marking
      //    -> Skip is allowed.
      await tester.pageBack();
      await _pump(tester);
      await tester.ensureVisible(find.text('Gallery'));
      await tester.tap(find.text('Gallery'));
      await _pump(tester);
      await tester.tap(find.text('Left angle').last);
      await _pump(tester);
      expect(b.photos, hasLength(2));
      expect(find.byKey(const Key('tour_skip')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tour_skip')));
      await _pump(tester);
      expect(find.byKey(const Key('photo_tour_tile')), findsNothing);

      // 6. Completion: 2 distinct photos + 1 saved marking.
      expect(b.photoRequirementOf(b.units.first).isComplete, isTrue);
      expect(c.boardIssues(b), isEmpty);

      // 7. Drawing opens (its own prerequisites), PDF becomes eligible.
      expect(SignageCatalog.unitDrawingBlocker(b, b.units.first), isNull);
      expect(groupReportReady(c, s, b), isTrue);
      expect(recceComplete(c, s), isTrue);
      await tester.tap(find.byKey(const Key('step_next_4')));
      await _pump(tester);
      await tester.tap(find.byKey(const Key('step_next_5')));
      await _pump(tester);
      await tester.ensureVisible(find.byKey(const Key('open_2d')));
      await tester.tap(find.byKey(const Key('open_2d')));
      await _pump(tester);
      expect(find.byType(Drawing2DScreen), findsOneWidget);
      await tester.pageBack();
      await _pump(tester);

      // 8. Shop Details: Preview and Download through the visible buttons
      //    (only storage / viewer / share-sheet plugins are injected).
      final files = <String, Uint8List>{};
      Uint8List? viewed, shared;
      RecceReportCard.testService = ReportService(
        images: FakeImages(),
        models: FakeModels(),
        writer: (bytes) async {
          files['r'] = bytes;
          return '/r.pdf';
        },
        reader: (p) async => files['r'],
        useIsolate: false,
      );
      RecceReportCard.testViewer = (bytes, name) async => viewed = bytes;
      RecceReportCard.testShare = (bytes, name) async => shared = bytes;
      addTearDown(() {
        RecceReportCard.testService = null;
        RecceReportCard.testViewer = null;
        RecceReportCard.testShare = null;
      });
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: c,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ShopDetailScreen(shopId: _shop),
          ),
        ),
      );
      await _pump(tester);
      for (final key in ['recce_pdf_preview', 'recce_pdf_download']) {
        await tester.scrollUntilVisible(
          find.byKey(Key(key)),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(key)));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 800)),
        );
        await tester.pump();
      }
      for (final bytes in [viewed, shared]) {
        expect(bytes, isNotNull);
        expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
      }
      // Scope = the single media group of this shop; status stays Draft.
      final made = c.reportsForShop(_shop);
      expect(made, hasLength(2), reason: 'one for Preview, one for Download');
      expect(
        made.every((r) => r.isDraft),
        isTrue,
        reason: 'never marked approved',
      );
    },
  );

  testWidgets(
    'multi-board: Board 01 marked does not enable Skip for Board 02',
    (tester) async {
      _phone(tester);
      PhotoSection.testCapture = (source) async => SitePhoto(
        id: 'f',
        path: 'demo://5',
        label: '',
        capturedAt: DateTime(2026),
        width: 1200,
        height: 900,
      );
      final c = AppController(store: MemoryLocalStore());
      await c.init();
      c.loginWithPin(DemoAccounts.vendorPin);
      c.shop(_shop)!.boards.clear();
      final b =
          c.addMediaGroups(_shop, [
              MediaGroupPlan(
                SignageCatalog.mediaOptions.firstWhere(
                  (o) => o.key == 'GSB_SINGLE',
                ),
                1,
              ),
            ]).single
            ..width = 5
            ..height = 3
            ..installationCode = 'shop_fascia';
      c.increaseQuantity(_shop, b, 2);
      final u1 = b.units[0], u2 = b.units[1];
      // Board 01 already has two photos and a saved signage marking.
      b.photos.addAll([
        SitePhoto(
          id: 'e1',
          path: 'demo://1',
          label: 'Front view',
          capturedAt: DateTime(2026),
          width: 10,
          height: 10,
          unitIds: [u1.id],
          annotations: [
            Annotation(
              id: 'm',
              type: AnnotationType.rectangle,
              itemId: u1.id,
              w: 5,
              h: 3,
            ),
          ],
        ),
        SitePhoto(
          id: 'e2',
          path: 'demo://2',
          label: 'Left angle',
          capturedAt: DateTime(2026),
          width: 10,
          height: 10,
          unitIds: [u1.id],
        ),
      ]);
      // Board 02 has one earlier photo (skipped, no marking).
      b.photos.add(
        SitePhoto(
          id: 'e3',
          path: 'demo://3',
          label: 'Front view',
          capturedAt: DateTime(2026),
          width: 10,
          height: 10,
          unitIds: [u2.id],
        ),
      );
      // Group photos are shared; only the marking is board-specific.
      expect(b.photoRequirement.photoCount, 3);
      expect(b.photoRequirement.missingUnitIds, [u2.id]);
      expect(b.photoRequirementOf(u2).markingCount, 0);

      Future<void> capture(SignageUnit u) async {
        c.editorUnit[b.id] = u.id;
        await tester.pumpWidget(
          ChangeNotifierProvider<AppController>.value(
            value: c,
            child: MaterialApp(
              theme: AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: BoardEditorScreen(
                key: UniqueKey(),
                shopId: _shop,
                boardId: b.id,
                initialStep: BoardEditorScreen.siteQuestionsStep + 1,
              ),
            ),
          ),
        );
        await _pump(tester);
        await tester.ensureVisible(find.text('Camera'));
        await tester.tap(find.text('Camera'));
        await _pump(tester);
        await tester.tap(find.text('Front view').last);
        await _pump(tester);
      }

      // Board 02 (no marking): the new photo belongs to it and is compulsory.
      await capture(u2);
      expect(b.photos.last.unitIds, [u2.id]);
      expect(find.byKey(const Key('photo_tour_tile')), findsOneWidget);
      expect(find.byKey(const Key('tour_skip')), findsNothing);
      expect(b.photoRequirementOf(u2).isComplete, isFalse);

      // Board 02 is still unmarked, so later group photos remain compulsory
      // even when the captured photo belongs to Board 01.
      await capture(u1);
      expect(b.photos.last.unitIds, [u1.id]);
      expect(find.byKey(const Key('tour_skip')), findsNothing);
    },
  );

  testWidgets('second photo without a saved marking has no Skip (UI)', (
    tester,
  ) async {
    _phone(tester);
    PhotoSection.testCapture = (source) async => SitePhoto(
      id: 'f',
      path: 'demo://0',
      label: '',
      capturedAt: DateTime(2026),
      width: 1200,
      height: 900,
    );
    final c = AppController(store: MemoryLocalStore());
    await c.init();
    c.loginWithPin(DemoAccounts.vendorPin);
    c.shop(_shop)!.boards.clear();
    final b =
        c.addMediaGroups(_shop, [
            MediaGroupPlan(
              SignageCatalog.mediaOptions.firstWhere(
                (o) => o.key == 'GSB_SINGLE',
              ),
              1,
            ),
          ]).single
          ..width = 5
          ..height = 3
          ..installationCode = 'shop_fascia';
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BoardEditorScreen(
            shopId: _shop,
            boardId: b.id,
            initialStep: BoardEditorScreen.siteQuestionsStep + 1,
          ),
        ),
      ),
    );
    await _pump(tester);
    // First photo, skipped without marking.
    await tester.ensureVisible(find.text('Camera'));
    await tester.tap(find.text('Camera'));
    await _pump(tester);
    await tester.tap(find.text('Front view').last);
    await _pump(tester);
    await tester.tap(find.byKey(const Key('tour_skip')));
    await _pump(tester);
    // Second photo: nothing saved -> compulsory, no Skip.
    await tester.tap(find.text('Camera'));
    await _pump(tester);
    await tester.tap(find.text('Left angle').last);
    await _pump(tester);
    expect(find.byKey(const Key('photo_tour_tile')), findsOneWidget);
    expect(find.byKey(const Key('tour_skip')), findsNothing);
    expect(find.byKey(const Key('tour_open')), findsOneWidget);
    // Deleting the photo and its tour state leaves nothing falsely complete.
    expect(b.photoRequirementOf(b.units.first).isComplete, isFalse);
  });
}
