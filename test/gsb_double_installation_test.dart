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

Future<AppController> _controller() async {
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin('5678');
  return c;
}

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

Future<(AppController, Board)> _gsbDouble(WidgetTester tester) async {
  final c = await _controller();
  final b = c.addBoard('s_lakshmi')
    ..mediaCode = SignageCatalog.gsb
    ..doubleSided = true;
  c.touchBoard('s_lakshmi', b);
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
  return (c, b);
}

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);

  test('GSB Double Side has exactly five scoped choices in order', () {
    final b = Board(id: 'b', name: 'Board 1')
      ..mediaCode = SignageCatalog.gsb
      ..doubleSided = true;
    final choices = SignageCatalog.choicesForBoard(b);
    expect(
      choices.map((c) => c.name).toList(),
      const [
        'Projecting Mount',
        'Double Pole',
        'Single Pole',
        'Rooftop',
        'Hanging Mount',
      ],
    );
    expect(
      choices.map((c) => c.description).toList(),
      const [
        'Projects outwards from a wall.',
        'Supported by two ground-mounted poles.',
        'Supported by one central pole.',
        'Mounted on a roof or terrace.',
        'Suspended from an overhead structure.',
      ],
    );
    expect(
      choices.map((c) => c.art).toList(),
      const [
        InstallationArt.projecting,
        InstallationArt.doublePole,
        InstallationArt.singlePole,
        InstallationArt.rooftop,
        InstallationArt.hanging,
      ],
    );
    expect(
      choices.map((c) => c.code).toList(),
      const [
        SignageCatalog.flangeBracket,
        SignageCatalog.doublePole,
        SignageCatalog.singlePole,
        SignageCatalog.rooftop,
        null,
      ],
    );
    // Shop Fascia / Wall Mount / Support Pipe are not offered for NEW
    // GSB Double Side selections, but other media keep their own options.
    final nlb = Board(id: 'n', name: 'Board 2')..mediaCode = SignageCatalog.nlb;
    expect(
      SignageCatalog.choicesForBoard(nlb).map((c) => c.code).toList(),
      SignageCatalog.media(SignageCatalog.nlb)!.installations,
    );
  });

  testWidgets('selection persists, restores and keeps a single radio', (
    tester,
  ) async {
    _phone(tester);
    final (c, b) = await _gsbDouble(tester);

    for (final key in [
      'inst_flange_bracket',
      'inst_double_pole',
      'inst_single_pole',
      'inst_rooftop',
      'inst_hanging_mount',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(find.text('Projecting Mount'), findsOneWidget);
    expect(find.text('Supported by two ground-mounted poles.'), findsOneWidget);
    expect(find.text('Suspended from an overhead structure.'), findsOneWidget);

    await _tap(tester, find.byKey(const Key('inst_double_pole')));
    expect(b.installationCode, SignageCatalog.doublePole);
    // Only one card is selected: the stored value is the single source of
    // truth for every radio indicator on this step.
    expect(b.installationCode, SignageCatalog.doublePole);

    // BACK keeps the value and the selection is restored on the card.
    tester.widget<Stepper>(find.byType(Stepper)).onStepCancel?.call();
    await tester.pumpAndSettle();
    expect(b.installationCode, SignageCatalog.doublePole);
    expect(find.byKey(const Key('inst_double_pole')), findsOneWidget);

    await _tap(tester, find.byKey(const Key('inst_single_pole')));
    expect(b.installationCode, SignageCatalog.singlePole);
    expect(c.board('s_lakshmi', b.id)!.installationCode,
        SignageCatalog.singlePole);
  });

  testWidgets('legacy values stay readable and valid', (tester) async {
    _phone(tester);
    final c = await _controller();
    final b = c.addBoard('s_lakshmi')
      ..mediaCode = SignageCatalog.gsb
      ..doubleSided = true
      ..installationCode = SignageCatalog.shopFascia;
    c.touchBoard('s_lakshmi', b);
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

    expect(find.byKey(const Key('inst_legacy_shop_fascia')), findsOneWidget);
    expect(b.installationCode, SignageCatalog.shopFascia);
    expect(
      c.boardIssues(b).any((e) => e.contains('Installation type not valid')),
      isFalse,
    );
  });

  testWidgets('hanging mount is shown but never persisted', (tester) async {
    _phone(tester);
    final (c, b) = await _gsbDouble(tester);
    b.installationCode = SignageCatalog.rooftop;
    c.touchBoard('s_lakshmi', b);
    await tester.pumpAndSettle();

    await _tap(tester, find.byKey(const Key('inst_hanging_mount')));
    expect(b.installationCode, SignageCatalog.rooftop);
    expect(find.textContaining('approved backend installation code'),
        findsWidgets);
  });
}
