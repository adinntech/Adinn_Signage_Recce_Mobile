// Focused widget-level smoke: real production widgets, isolated in-memory
// data and mocked adapters. No emulator, no APK install, no device camera.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/app.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/features/projects/project_detail_screen.dart';
import 'package:signage_recce/features/projects/task_detail_screen.dart';
import 'package:signage_recce/features/shop/shop_detail_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Future<AppController> _session() async {
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin(DemoAccounts.vendorPin);
  return c;
}

Future<void> _push(WidgetTester t, Widget screen) async {
  final nav = t.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute<void>(builder: (_) => screen));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('SMOKE 1+3: Projects → Sakthi → Erode task → Shop → Editor, '
      'then ENG/அ round-trip', (tester) async {
    _phone(tester);
    final c = await _session();
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    await _push(tester, const ProjectDetailScreen(projectId: 'p_sakthi'));
    expect(find.text('Sakthi Masala'), findsOneWidget);
    await _push(tester, const TaskDetailScreen(taskId: 't_erode'));
    expect(find.text('Shop Recce – Erode Market'), findsOneWidget);
    await _push(tester, const ShopDetailScreen(shopId: 's_erode_prov'));
    expect(find.text('Erode Provision Stores'), findsOneWidget);

    final b = c.addBoard('s_erode_prov')
      ..mediaCode = SignageCatalog.gsb
      ..installationCode = SignageCatalog.wallMount
      ..width = 3
      ..height = 4;
    c.touchBoard('s_erode_prov', b);
    await _push(
      tester,
      BoardEditorScreen(
        shopId: 's_erode_prov',
        boardId: b.id,
        initialStep: BoardEditorScreen.siteQuestionsStep,
      ),
    );
    expect(find.byKey(Key('media_tab_${b.id}')), findsOneWidget);
    expect(find.byKey(const Key('media_tab_add')), findsOneWidget);
    expect(find.text('Placement location (Optional)'), findsNothing);
    expect(find.text('Notes for this board (Optional)'), findsNothing);
    expect(find.byKey(const Key('gst_shop')), findsOneWidget);

    // Switch to Tamil without leaving the screen or losing selection.
    await tester.tap(find.byKey(const Key('lang_switch')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('media_tab_${b.id}')), findsOneWidget);
    expect(find.text('GSB ஒற்றைப் பக்கம்'), findsWidgets);
    expect(find.text('Placement location (Optional)'), findsNothing);
    expect(find.byKey(const Key('gst_shop')), findsOneWidget);
    expect(c.project('p_sakthi')!.name, 'Sakthi Masala');

    await tester.tap(find.byKey(const Key('lang_switch')));
    await tester.pumpAndSettle();
    expect(c.project('p_sakthi')!.name, 'Sakthi Masala');
    expect(c.shop('s_erode_prov')!.name, 'Erode Provision Stores');
    expect(tester.takeException(), isNull);
  });

  testWidgets('SMOKE 2: one group / two boards keeps both physical tabs '
      'and independent data', (tester) async {
    _phone(tester);
    final c = await _session();
    final b = c.addBoard('s_lakshmi')
      ..mediaCode = SignageCatalog.nlb
      ..width = 3
      ..height = 6;
    c.increaseQuantity('s_lakshmi', b, 2);
    final fresh = c.shop('s_lakshmi')!.boards.firstWhere((x) => x.id == b.id);
    fresh.activeUnits.first.installationCode = SignageCatalog.doublePole;
    fresh.activeUnits.last
      ..installationCode = SignageCatalog.wallMount
      ..width = 12
      ..height = 6;
    c.touchBoard('s_lakshmi', fresh);

    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await _push(
      tester,
      BoardEditorScreen(shopId: 's_lakshmi', boardId: fresh.id),
    );
    expect(find.byKey(Key('media_tab_${fresh.id}')), findsOneWidget);
    expect(find.byKey(const Key('board_unit_bar')), findsOneWidget);
    expect(
      find.byKey(Key('unit_bar_${fresh.activeUnits.first.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('unit_bar_${fresh.activeUnits.last.id}')),
      findsOneWidget,
    );
    expect(fresh.activeUnits.first.installationCode, SignageCatalog.doublePole);
    expect(fresh.activeUnits.last.installationCode, SignageCatalog.wallMount);
    expect(fresh.activeUnits.last.width, 12);
    expect(tester.takeException(), isNull);
  });
}
