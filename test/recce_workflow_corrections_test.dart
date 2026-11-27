import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/app.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/features/photos/photo_section.dart';
import 'package:signage_recce/features/projects/task_detail_screen.dart';
import 'package:signage_recce/features/shop/shop_detail_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

Future<AppController> _vendor() async {
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin(DemoAccounts.vendorPin);
  return c;
}

void _phone(WidgetTester t, {int width = 360}) {
  t.view.physicalSize = Size(width * 3, 820 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Future<void> _tamil(WidgetTester t) async {
  await t.tap(find.byKey(const Key('lang_switch')));
  await t.pumpAndSettle();
}

Future<void> _open(WidgetTester t, Widget screen) async {
  final nav = t.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute<void>(builder: (_) => screen));
  await t.pumpAndSettle();
}

Board _board(AppController c, {int quantity = 1, String? installation}) {
  final b = c.addBoard('s_lakshmi')
    ..mediaCode = SignageCatalog.gsb
    ..installationCode = installation ?? SignageCatalog.wallMount
    ..width = 3
    ..height = 4;
  if (quantity > 1) c.increaseQuantity('s_lakshmi', b, quantity);
  c.touchBoard('s_lakshmi', b);
  return b;
}

void main() {
  testWidgets('Site Questions: optional placement/notes fields removed, '
      'stored values and GST preserved', (tester) async {
    _phone(tester);
    final c = await _vendor();
    final b = _board(c);
    final u = b.activeUnits.first
      ..placement = 'Old placement'
      ..notes = 'Old note';
    c.touchBoard('s_lakshmi', b);

    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await _open(
      tester,
      BoardEditorScreen(
        shopId: 's_lakshmi',
        boardId: b.id,
        initialStep: BoardEditorScreen.siteQuestionsStep,
      ),
    );

    expect(find.text('Placement location (Optional)'), findsNothing);
    expect(find.text('Notes for this board (Optional)'), findsNothing);
    expect(find.byKey(const Key('gst_shop')), findsOneWidget);
    expect(find.textContaining('Installation Measurements'), findsWidgets);
    expect(u.placement, 'Old placement');
    expect(u.notes, 'Old note');

    await _tamil(tester);
    expect(find.text('Placement location (Optional)'), findsNothing);
    expect(find.text('Notes for this board (Optional)'), findsNothing);
    expect(find.byKey(const Key('gst_shop')), findsOneWidget);
    expect(u.placement, 'Old placement');
    expect(u.notes, 'Old note');
    expect(tester.takeException(), isNull);
  });

  testWidgets('media tab is visible for a single media group (qty 1 and 2)', (
    tester,
  ) async {
    for (final qty in <int>[1, 2]) {
      _phone(tester, width: qty == 1 ? 320 : 360);
      final c = await _vendor();
      final b = _board(c, quantity: qty);
      await tester.pumpWidget(
        AdinnRecceApp(key: ValueKey('tabs_$qty'), controller: c),
      );
      await tester.pumpAndSettle();
      await _open(
        tester,
        BoardEditorScreen(shopId: 's_lakshmi', boardId: b.id),
      );

      expect(find.byKey(const Key('media_tabs')), findsOneWidget);
      expect(find.byKey(Key('media_tab_${b.id}')), findsOneWidget);
      expect(find.byKey(const Key('media_tab_add')), findsOneWidget);
      if (qty == 2) {
        expect(find.byKey(const Key('board_unit_bar')), findsOneWidget);
      }
      expect(tester.takeException(), isNull, reason: 'qty $qty');
    }
  });

  testWidgets('media tab: read-only visible, plus hidden; Tamil switches', (
    tester,
  ) async {
    _phone(tester);
    final c = await _vendor();
    final b = _board(c);
    final shop = c.shop('s_lakshmi')!;
    shop.status = RecceStatus.approved; // read-only for the vendor
    c.touchBoard('s_lakshmi', b);

    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await _open(tester, BoardEditorScreen(shopId: 's_lakshmi', boardId: b.id));
    expect(find.byKey(Key('media_tab_${b.id}')), findsOneWidget);
    expect(find.byKey(const Key('media_tab_add')), findsNothing);

    // Tamil: selected tab keeps its identity and is localized.
    c.toggleLanguage();
    await tester.pumpAndSettle();
    expect(find.byKey(Key('media_tab_${b.id}')), findsOneWidget);
    expect(find.text('GSB ஒற்றைப் பக்கம்'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tamil shop/task/address display variants on real screens', (
    tester,
  ) async {
    _phone(tester);
    final c = await _vendor();
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await _tamil(tester);
    await _open(tester, const TaskDetailScreen(taskId: 't_erode'));

    expect(find.text('கடைத் தள ஆய்வு – ஈரோடு மார்க்கெட்'), findsOneWidget);
    expect(find.text('மார்க்கெட் சாலை, ஈரோடு'), findsOneWidget);
    expect(find.text('முருகன் K'), findsOneWidget);
    expect(find.text('ஈரோடு புரொவிஷன் ஸ்டோர்ஸ்'), findsWidgets);
    // Stored data is untouched.
    final shop = c.shop('s_erode_prov')!;
    final task = c.task('t_erode')!;
    expect(shop.name, 'Erode Provision Stores');
    expect(shop.address, '101, Market Road');
    expect(shop.area, 'Erode Market');
    expect(shop.city, 'Erode');
    expect(shop.pincode, '638001');
    expect(task.title, 'Shop Recce – Erode Market');
    expect(shop.geo, isNull);

    await _open(tester, const ShopDetailScreen(shopId: 's_erode_prov'));
    expect(
      find.text('101, மார்க்கெட் சாலை, ஈரோடு மார்க்கெட், ஈரோடு, 638001'),
      findsOneWidget,
    );
    expect(find.text('Erode Provision Stores'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edited predefined shop keeps its custom values', (tester) async {
    _phone(tester);
    final c = await _vendor();
    final s = c.shop('s_erode_prov')!
      ..name = 'My Provision Store'
      ..address = '42, New Street';
    c.touchBoard(
      's_erode_prov',
      c.shop('s_erode_prov')!.boards.firstOrNull ??
          (c.addBoard('s_erode_prov')..mediaCode = SignageCatalog.gsb),
    );
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await _tamil(tester);
    await _open(tester, const ShopDetailScreen(shopId: 's_erode_prov'));
    expect(find.text('My Provision Store'), findsOneWidget);
    expect(find.text('ஈரோடு புரொவிஷன் ஸ்டோர்ஸ்'), findsNothing);
    expect(s.name, 'My Provision Store');
  });

  testWidgets('sample photo action is absent in both locales', (tester) async {
    for (final tamil in <bool>[false, true]) {
      _phone(tester, width: 360);
      final c = await _vendor();
      final b = c.addBoard('s_lakshmi')..mediaCode = SignageCatalog.gsb;
      c.touchBoard('s_lakshmi', b);
      await tester.pumpWidget(
        AdinnRecceApp(key: ValueKey('photo_$tamil'), controller: c),
      );
      await tester.pumpAndSettle();
      if (tamil) await _tamil(tester);
      await _open(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: PhotoSection(shopId: 's_lakshmi', board: b, editable: true),
          ),
        ),
      );
      expect(find.byKey(const Key('add_sample_photo')), findsNothing);
      expect(find.text('Add sample photo (demo / no camera)'), findsNothing);
      expect(find.byKey(const Key('capture_camera')), findsOneWidget);
      expect(find.text(tamil ? 'கேலரி' : 'Gallery'), findsOneWidget);
      expect(b.photos, isEmpty);
      expect(tester.takeException(), isNull, reason: 'tamil=$tamil');
    }
  });
}
