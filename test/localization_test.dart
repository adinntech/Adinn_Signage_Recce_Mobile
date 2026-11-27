import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/app.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/l10n/ta_catalog.dart';
import 'package:signage_recce/state/app_controller.dart';

const _shop = 's_lakshmi';

Future<AppController> _vendor([MemoryLocalStore? store]) async {
  final c = AppController(store: store ?? MemoryLocalStore());
  await c.init();
  c.loginWithPin(DemoAccounts.vendorPin);
  return c;
}

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  test('English by default; the preference persists across restarts', () async {
    final store = MemoryLocalStore();
    final c = await _vendor(store);
    expect(c.isTamil, isFalse);
    expect(c.locale.languageCode, 'en');
    c.toggleLanguage();
    await c.flush();
    final r = AppController(store: store);
    await r.init();
    expect(r.isTamil, isTrue);
    expect(r.locale.languageCode, 'ta');
    r.toggleLanguage();
    await r.flush();
    final r2 = AppController(store: store);
    await r2.init();
    expect(r2.isTamil, isFalse);
  });

  test('Tamil catalog covers the active media, installations and options', () {
    for (final o in SignageCatalog.mediaOptions) {
      expect(TaCatalog.media.containsKey(o.label), isTrue, reason: o.label);
    }
    for (final i in [
      'Shop Fascia',
      'Wall Mount',
      'Double Pole',
      'Single Pole',
      'Rooftop',
      'Support Pipe',
      'Projecting Mount',
      'Direct on Wall',
      'Glass / Shutter Pasting',
    ]) {
      expect(TaCatalog.installations.containsKey(i), isTrue, reason: i);
    }
    expect(
      TaCatalog.questions['Is there an existing board at this location?'],
      'இந்த இடத்தில் ஏற்கனவே பலகை உள்ளதா?',
    );
  });

  testWidgets('ENG / அ switcher on Projects updates the screen immediately', (
    tester,
  ) async {
    _phone(tester);
    final c = await _vendor();
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lang_switch')), findsOneWidget);
    expect(find.text('ENG'), findsOneWidget);
    expect(find.text('Search project, code or region'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lang_switch')));
    await tester.pumpAndSettle();
    expect(find.text('அ'), findsOneWidget);
    // The toggle keeps both labels visible; the active one is highlighted.
    expect(c.isTamil, isTrue);
    expect(find.text('திட்டங்கள்'), findsWidgets);
    expect(tester.takeException(), isNull, reason: 'no overflow');

    await tester.tap(find.byKey(const Key('lang_switch')));
    await tester.pumpAndSettle();
    expect(find.text('ENG'), findsOneWidget);
  });

  testWidgets('ENG / அ is on every main tab and fits a 320 px phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 1920); // 320 x 640 dp
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = await _vendor();
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    for (final tab in [
      'Home',
      'Projects',
      'Submitted',
      'Activity',
      'Profile',
    ]) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lang_switch')), findsOneWidget, reason: tab);
      expect(tester.takeException(), isNull, reason: 'no overflow on $tab');
    }
    // Tamil on every tab: no overflow either.
    await tester.tap(find.byKey(const Key('lang_switch')));
    await tester.pumpAndSettle();
    for (final tab in [
      'முகப்பு',
      'திட்டங்கள்',
      'சமர்ப்பிப்பு',
      'செயல்பாடு',
      'சுயவிவரம்',
    ]) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lang_switch')), findsOneWidget, reason: tab);
      expect(tester.takeException(), isNull, reason: 'no overflow on $tab');
    }
  });

  testWidgets('switching language keeps typed input, step, ids and answers', (
    tester,
  ) async {
    _phone(tester);
    final c = await _vendor();
    final s = c.shop(_shop)!..boards.clear();
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
    c.setUnitAnswer(_shop, b, b.units.first, 'existing_board', true);
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => BoardEditorScreen(
          shopId: _shop,
          boardId: b.id,
          initialStep: BoardEditorScreen.siteQuestionsStep,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Site Questions'), findsWidgets);
    await tester.enterText(find.byKey(const Key('gst_field')), '33AAAAA');
    await tester.pump();
    final before = Map<String, dynamic>.from(b.answers);

    await tester.tap(find.byKey(const Key('lang_switch')));
    await tester.pumpAndSettle();
    // Tamil headings, question wording and Yes/No; same stable keys.
    expect(find.text('தளக் கேள்விகள்'), findsWidgets);
    expect(
      find.textContaining('ஏற்கனவே பலகை', findRichText: true),
      findsWidgets,
    );
    expect(find.byKey(const Key('q_existing_board_true')), findsOneWidget);
    expect(find.text('ஆம்'), findsWidgets);
    // Unsaved typed text and the current step survive; nothing stored changed.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('gst_field')))
          .controller!
          .text,
      '33AAAAA',
    );
    expect(b.answers, before);
    expect(b.mediaCode, 'GSB');
    expect(b.installationCode, 'shop_fascia');
    expect(s.gstNumber, '', reason: 'invalid draft never stored');
    expect(tester.takeException(), isNull);
  });
}
