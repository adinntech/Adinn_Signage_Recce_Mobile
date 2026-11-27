import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/approvals/review_screen.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/features/board/units_screen.dart';
import 'package:signage_recce/features/shop/shop_detail_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

import 'helpers.dart';
import 'support/evidence_fixture.dart';

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

Future<void> _show(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    // Lazily built list item: scroll the page until it exists.
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await _show(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);

  testWidgets('board editor: standee media, quantity and per-unit sizes', (
    tester,
  ) async {
    _phone(tester);
    final c = AppController(store: MemoryLocalStore());
    await c.init();
    c.loginWithPin('5678');
    final b = c.addBoard('s_lakshmi');
    await tester.pumpWidget(
      _host(c, BoardEditorScreen(shopId: 's_lakshmi', boardId: b.id)),
    );
    await tester.pumpAndSettle();
    // Media Type is the first step; Board Details is second.
    expect(
      tester.widget<Stepper>(find.byType(Stepper)).currentStep,
      BoardEditorScreen.mediaTypeStep,
    );
    // Catalog v2: the 13 business media are offered; legacy standees are
    // not offered for new groups but existing groups keep working.
    expect(find.text('Choose one of 7 media types'), findsOneWidget);
    expect(find.text('Standee 1S'), findsNothing);
    expect(find.byKey(const Key('media_MDF')), findsOneWidget);

    // An existing (legacy) double-sided standee group.
    b
      ..mediaCode = SignageCatalog.doubleStandee
      ..installationCode = SignageCatalog.freeStanding;
    c.touchBoard('s_lakshmi', b);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('legacy_media_card')), findsOneWidget);
    // The media-group tab now also shows the selected group's name.
    expect(find.text('Standee 2S'), findsWidgets);
    expect(b.mediaCode, SignageCatalog.doubleStandee);
    // Single installation → auto-selected.
    expect(b.installationCode, SignageCatalog.freeStanding);

    // Quantity and sizes live on the second step (Board Details).
    await _tap(tester, find.byKey(const Key('step_next_0')));
    expect(
      tester.widget<Stepper>(find.byType(Stepper)).currentStep,
      BoardEditorScreen.boardDetailsStep,
    );
    expect(find.byKey(const Key('board_details_content')), findsOneWidget);
    expect(find.text('Number of Boards'), findsOneWidget);
    // Quantity 1: no size-mode question.
    expect(find.text('Board Size'), findsOneWidget);
    expect(find.byKey(const Key('size_same')), findsNothing);
    expect(
      find.text(
        'Quantity = physical double-sided standees (each has 2 faces).',
      ),
      findsOneWidget,
    );

    await _tap(tester, find.byKey(const Key('qty_plus')));
    await _tap(tester, find.byKey(const Key('qty_plus')));
    expect(b.quantity, 3);
    expect(b.units, hasLength(3));
    expect(find.text('Board Size'), findsOneWidget);
    expect(find.byKey(const Key('size_same')), findsOneWidget);

    // Same size: one width/height for all.
    await _show(tester, find.byKey(const Key('board_width')));
    await tester.enterText(find.byKey(const Key('board_width')), '3');
    await tester.enterText(find.byKey(const Key('board_height')), '5');
    await tester.pumpAndSettle();
    expect(b.areaSqFt, closeTo(45, 1e-9));

    // Different sizes: values copied, then edited per unit.
    await _tap(tester, find.byKey(const Key('size_diff')));
    expect(b.sizeMode, SizeMode.different);
    expect(find.byKey(const Key('unit_w_2')), findsOneWidget);
    await _show(tester, find.byKey(const Key('unit_w_1')));
    await tester.enterText(find.byKey(const Key('unit_w_1')), '4');
    await tester.pumpAndSettle();
    expect(b.units[1].width, 4);
    expect(b.units[0].width, 3);
    // Zero is flagged.
    await tester.enterText(find.byKey(const Key('unit_h_2')), '0');
    await tester.pumpAndSettle();
    expect(find.text('Must be greater than 0'), findsOneWidget);
    expect(c.boardIssues(b), contains('Enter width and height for Unit 03'));

    // Reduce quantity: confirmation lists the unit to be removed.
    await _tap(tester, find.byKey(const Key('qty_minus')));
    expect(find.text('Reduce quantity to 2?'), findsOneWidget);
    expect(find.textContaining('Unit 03'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(b.quantity, 3);
    await _tap(tester, find.byKey(const Key('qty_minus')));
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(b.quantity, 2);

    // Different → same asks which size to apply.
    await _tap(tester, find.byKey(const Key('size_same')));
    expect(find.text('Apply which size to all units?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('size_from_Unit 02')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('size_from_ok')));
    await tester.pumpAndSettle();
    expect(b.sizeMode, SizeMode.same);
    expect(b.width, 4);
  });

  testWidgets('units screen edits placement / installation per unit', (
    tester,
  ) async {
    _phone(tester);
    final c = AppController(store: MemoryLocalStore());
    await c.init();
    c.loginWithPin('5678');
    final shop = c.shop('s_sriranga')!;
    final b = shop.boards.first;
    c.increaseQuantity(shop.id, b, 2);
    await tester.pumpWidget(
      _host(c, UnitsScreen(shopId: shop.id, boardId: b.id)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unit 01'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('unit_place_0')),
      'Above shutter',
    );
    await _show(tester, find.byKey(const Key('unit_place_1')));
    await tester.enterText(find.byKey(const Key('unit_place_1')), 'Side wall');
    await tester.pumpAndSettle();
    expect(b.units.map((u) => u.placement), ['Above shutter', 'Side wall']);
    await _show(tester, find.byKey(const Key('unit_notes_1')));
    await tester.enterText(
      find.byKey(const Key('unit_notes_1')),
      'Needs ladder',
    );
    await tester.pumpAndSettle();
    expect(b.units[1].notes, 'Needs ladder');
    expect(b.units[0].notes, isEmpty);
  });

  testWidgets('shop screen shows signage requirements and add media type', (
    tester,
  ) async {
    _phone(tester);
    final c = AppController(store: MemoryLocalStore());
    await c.init();
    c.loginWithPin('5678');
    final shop = c.shop('s_sriranga')!;
    c.increaseQuantity(shop.id, shop.boards.first, 3);
    await tester.pumpWidget(_host(c, ShopDetailScreen(shopId: shop.id)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Signage requirements (1)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Add media type'), findsOneWidget);
    expect(find.text('1 media type • 3 signage units'), findsOneWidget);
    await _show(tester, find.text('Qty 3'));
    expect(find.text('Qty 3'), findsOneWidget);
  });

  testWidgets('reviewer rejects a specific unit dimension', (tester) async {
    _phone(tester);
    final c = AppController(store: MemoryLocalStore());
    await c.init();
    c.loginWithPin('5678');
    final shop = c.shop('s_sriranga')!;
    final b = shop.boards.first;
    c.setShopLocation(shop, gpsAt(10.86270, 78.68970));
    c.increaseQuantity(shop.id, b, 2);
    // Each physical board answers its own questions.
    completeAnswers(b);
    ensureEvidenceForAllUnits(b);
    c.submitShop(shop.id);
    c.logout();
    c.loginWithPin(DemoAccounts.businessPin);

    await tester.pumpWidget(_host(c, ReviewScreen(shopId: shop.id)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reject_button')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('reject_items')));
    final chip = find.byKey(Key('issue_${b.units[1].id}_dimension'));
    await _tap(tester, chip);
    expect(find.text('Specific items (1 flagged)'), findsOneWidget);
    await _show(tester, find.byKey(const Key('reject_remarks')));
    await tester.enterText(find.byKey(const Key('reject_remarks')), 'Recheck');
    await _tap(tester, find.byKey(const Key('reject_confirm')));
    // Let the snack bar and the pop finish.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(shop.status, RecceStatus.rejectedBusiness);
    final issue = shop.latestSubmission!.reviews.last.issues.single;
    expect(issue.unitId, b.units[1].id);
    expect(issue.aspect, IssueAspect.dimension);
    expect(issue.groupId, b.id);
  });
}
