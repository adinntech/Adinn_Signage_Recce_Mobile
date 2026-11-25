import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

void _phone(WidgetTester tester, {double width = 360, double height = 800}) {
  tester.view.physicalSize = Size(width * 3, height * 3);
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

Future<AppController> _controller() async {
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin('5678');
  return c;
}

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);

  testWidgets('new board opens Media Type first, Board Details second', (
    tester,
  ) async {
    _phone(tester);
    final c = await _controller();
    final b = c.addBoard('s_lakshmi');
    await tester.pumpWidget(
      _host(
        c,
        BoardEditorScreen(shopId: 's_lakshmi', boardId: b.id),
      ),
    );
    await tester.pumpAndSettle();

    final stepper = tester.widget<Stepper>(find.byType(Stepper));
    expect(stepper.currentStep, BoardEditorScreen.mediaTypeStep);
    expect(find.byKey(const Key('media_MDF')), findsOneWidget);
    expect(
      stepper.steps.map((s) => (s.title as Text).data).toList(),
      const [
        'Media Type',
        'Board Details',
        'Installation Type',
        'Site Questions',
        'Site Photos & Annotation',
        'Voice & Text Notes',
        '2D Drawing & 3D Preview',
      ],
    );

    await _tap(tester, find.byKey(const Key('step_next_0')));
    expect(
      tester.widget<Stepper>(find.byType(Stepper)).currentStep,
      BoardEditorScreen.boardDetailsStep,
    );
    expect(find.byKey(const Key('board_details_content')), findsOneWidget);
    expect(find.byKey(const Key('board_name')), findsOneWidget);
    expect(find.text('Number of Boards'), findsOneWidget);

    await _tap(tester, find.byKey(const Key('step_back_1')));
    expect(
      tester.widget<Stepper>(find.byType(Stepper)).currentStep,
      BoardEditorScreen.mediaTypeStep,
    );
  });

  testWidgets('board with media already chosen opens Board Details', (
    tester,
  ) async {
    _phone(tester);
    final c = await _controller();
    final b = c.addBoard('s_lakshmi')..mediaCode = SignageCatalog.clearAcrylic;
    await tester.pumpWidget(
      _host(c, BoardEditorScreen(shopId: 's_lakshmi', boardId: b.id)),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Stepper>(find.byType(Stepper)).currentStep,
      BoardEditorScreen.boardDetailsStep,
    );
    expect(find.byKey(const Key('board_name')), findsOneWidget);
  });

  testWidgets('quantity, size modes and total area stay in sync', (tester) async {
    _phone(tester);
    final c = await _controller();
    final b = c.addBoard('s_lakshmi');
    await tester.pumpWidget(
      _host(
        c,
        BoardEditorScreen(
          shopId: 's_lakshmi',
          boardId: b.id,
          initialStep: BoardEditorScreen.boardDetailsStep,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('board_width')), '6');
    await tester.enterText(find.byKey(const Key('board_height')), '3');
    await tester.pumpAndSettle();
    expect(b.areaSqFt, closeTo(18, 1e-9));
    expect(
      (tester.widget<Text>(find.byKey(const Key('total_area_value')))).data,
      '18 sq ft',
    );

    await _tap(tester, find.byKey(const Key('qty_plus')));
    expect(b.quantity, 2);
    expect(
      find.text('Unit details (2) — placement, installation, notes'),
      findsOneWidget,
    );
    expect(b.areaSqFt, closeTo(36, 1e-9));
    expect(
      (tester.widget<Text>(find.byKey(const Key('total_area_value')))).data,
      '36 sq ft',
    );

    await _tap(tester, find.byKey(const Key('size_diff')));
    expect(b.sizeMode, SizeMode.different);
    expect(find.byKey(const Key('unit_w_1')), findsOneWidget);
    await _show(tester, find.byKey(const Key('unit_w_1')));
    await tester.enterText(find.byKey(const Key('unit_w_1')), '8');
    await tester.enterText(find.byKey(const Key('unit_h_1')), '4');
    await tester.pumpAndSettle();
    expect(b.activeUnits[1].width, 8);
    expect(b.activeUnits[1].height, 4);
    expect(b.areaSqFt, closeTo(50, 1e-9));
    expect(
      (tester.widget<Text>(find.byKey(const Key('total_area_value')))).data,
      '50 sq ft',
    );
  });

  testWidgets('unit switch converts dimensions without changing area', (
    tester,
  ) async {
    _phone(tester);
    final c = await _controller();
    final b = c.addBoard('s_lakshmi');
    await tester.pumpWidget(
      _host(
        c,
        BoardEditorScreen(
          shopId: 's_lakshmi',
          boardId: b.id,
          initialStep: BoardEditorScreen.boardDetailsStep,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('board_width')), '6');
    await tester.enterText(find.byKey(const Key('board_height')), '3');
    await tester.pumpAndSettle();
    expect(b.areaSqFt, closeTo(18, 1e-9));

    await _tap(tester, find.byKey(const Key('unit_m')));
    expect(b.unit, MeasureUnit.m);
    expect(b.width, closeTo(1.8288, 1e-4));
    expect(b.height, closeTo(0.9144, 1e-4));
    expect(b.areaSqFt, closeTo(18, 1e-9));

    await _tap(tester, find.byKey(const Key('unit_ft')));
    expect(b.unit, MeasureUnit.ft);
    expect(b.width, closeTo(6, 1e-6));
    expect(b.height, closeTo(3, 1e-6));
    expect(b.areaSqFt, closeTo(18, 1e-9));
  });

  testWidgets('narrow screen keeps board details accessible', (tester) async {
    _phone(tester, width: 320, height: 720);
    final c = await _controller();
    final b = c.addBoard('s_lakshmi')
      ..name = 'A very long board name for the narrow screen test';
    c.increaseQuantity('s_lakshmi', b, 3);
    c.setSizeMode('s_lakshmi', b, SizeMode.different);
    await tester.pumpWidget(
      _host(
        c,
        BoardEditorScreen(
          shopId: 's_lakshmi',
          boardId: b.id,
          initialStep: BoardEditorScreen.boardDetailsStep,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('board_name')), findsOneWidget);
    expect(find.byKey(const Key('unit_mm')), findsOneWidget);
    expect(find.byKey(const Key('unit_w_2')), findsOneWidget);
    await _show(tester, find.byKey(const Key('open_units')));
    expect(find.byKey(const Key('open_units')), findsOneWidget);
    expect(
      (tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('open_units')),
          matching: find.byType(Text),
        ),
      )).data,
      'Unit details (3) — placement, installation, notes',
    );
  });

  testWidgets('restored compact measurements styling', (tester) async {
    _phone(tester);
    final c = await _controller();
    final b = c.addBoard('s_lakshmi');
    await tester.pumpWidget(
      _host(
        c,
        BoardEditorScreen(
          shopId: 's_lakshmi',
          boardId: b.id,
          initialStep: BoardEditorScreen.boardDetailsStep,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Connected four-part unit control (not four separate buttons).
    expect(find.byKey(const Key('measurement_unit_selector')), findsOneWidget);
    expect(tester.widget<SegmentedButton<MeasureUnit>>(
      find.byKey(const Key('measurement_unit_selector')),
    ).segments, hasLength(4));
    expect(find.byKey(const Key('unit_ft')), findsOneWidget);
    expect(find.byKey(const Key('unit_mm')), findsOneWidget);
    expect(find.text('Board Name'), findsOneWidget);
    expect(find.text('Number of Boards'), findsOneWidget);
    expect(find.text('Width *'), findsOneWidget);
    expect(find.text('Height *'), findsOneWidget);
    expect(find.text('Unit details — placement, installation, notes'),
        findsOneWidget);
    // No duplicate red heading inside the expanded form.
    expect(find.byKey(const Key('board_details_content')), findsOneWidget);
  });

  testWidgets('common phone widths render without overflow', (tester) async {
    for (final width in [320, 360, 393, 412, 430]) {
      _phone(tester, width: width.toDouble(), height: 800);
      final c = await _controller();
      final b = c.addBoard('s_lakshmi')
        ..mediaCode = SignageCatalog.gsb
        ..doubleSided = true;
      c.increaseQuantity('s_lakshmi', b, 3);
      await tester.pumpWidget(
        _host(
          c,
          BoardEditorScreen(
            shopId: 's_lakshmi',
            boardId: b.id,
            initialStep: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$width dp');
      expect(find.byKey(const Key('board_width')), findsOneWidget);
      expect(find.byKey(const Key('size_mode_selector')), findsOneWidget);
      expect(find.byKey(const Key('inst_hanging_mount')), findsOneWidget);
      expect(find.byKey(const Key('inst_double_pole')), findsOneWidget);
    }
  });
}
