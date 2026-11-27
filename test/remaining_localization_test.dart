import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/app.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/features/shop/shop_detail_screen.dart';
import 'package:signage_recce/l10n/l10n.dart';
import 'package:signage_recce/l10n/ta_display.dart';
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

Future<void> _toTamil(WidgetTester t) async {
  await t.tap(find.byKey(const Key('lang_switch')));
  await t.pumpAndSettle();
}

Future<void> _open(WidgetTester t, Widget screen) async {
  final nav = t.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(MaterialPageRoute<void>(builder: (_) => screen));
  await t.pumpAndSettle();
}

/// Reveal a lazily built card by dragging the main list. Never throws when
/// the finder is absent or matches more than one widget.
Future<void> _show(WidgetTester t, Finder f) async {
  for (var i = 0; i < 10 && f.evaluate().isEmpty; i++) {
    final lists = find.byType(ListView);
    if (lists.evaluate().isEmpty) break;
    await t.drag(lists.first, const Offset(0, -320));
    await t.pumpAndSettle();
  }
}

/// Scroll only the horizontal media-tab strip.
Future<void> _showTab(WidgetTester t, Finder f) async {
  final tabs = find.byKey(const Key('media_tabs'));
  final scrollables = find.descendant(
    of: tabs,
    matching: find.byType(Scrollable),
  );
  if (scrollables.evaluate().isEmpty) return;
  for (var i = 0; i < 8 && f.evaluate().isEmpty; i++) {
    await t.drag(scrollables.first, const Offset(-150, 0));
    await t.pumpAndSettle();
  }
}

MediaOption _media(String key) =>
    SignageCatalog.mediaOptions.firstWhere((o) => o.key == key);

void main() {
  testWidgets('Projects: verified Tamil display names and data integrity', (
    tester,
  ) async {
    _phone(tester);
    final c = await _vendor();
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    expect(find.text('Asian Paints'), findsOneWidget);

    await _toTamil(tester);
    expect(find.text('ஏசியன் பெயிண்ட்ஸ்'), findsOneWidget);
    expect(find.text('ராம்கோ சிமெண்ட்ஸ்'), findsOneWidget);
    await _show(tester, find.text('சக்தி மசாலா'));
    expect(find.text('சக்தி மசாலா'), findsOneWidget);
    expect(find.textContaining('திருச்சி மற்றும் டெல்டா'), findsWidgets);
    expect(find.textContaining('மதுரை'), findsWidgets);
    expect(find.textContaining('ஈரோடு'), findsWidgets);
    expect(find.textContaining('மத்திய தமிழ்நாட்டில்'), findsOneWidget);
    expect(find.textContaining('விற்பனையாளர் பலகைகளை'), findsOneWidget);
    expect(find.textContaining('கடைகளின் விளம்பரத் தெரிவுநிலையை'), findsOneWidget);

    // Stored values are untouched.
    expect(c.project('p_asian')!.name, 'Asian Paints');
    expect(c.project('p_sakthi')!.description,
        'Retail visibility – flange boards and shutter vinyl.');
    expect(c.project('p_ramco')!.code, 'RC-MDU-2026');

    await _toTamil(tester); // back to English
    expect(find.text('Asian Paints'), findsOneWidget);
    expect(find.text('ஏசியன் பெயிண்ட்ஸ்'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('user-edited project name/description are never relabelled', (
    tester,
  ) async {
    _phone(tester);
    final c = await _vendor();
    final p = c.project('p_sakthi')!;
    p.name = 'My Own Masala';
    p.description = 'My own description';
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await _toTamil(tester);
    await tester.tap(find.text('திட்டங்கள்').last);
    await tester.pumpAndSettle();
    await _show(tester, find.text('My Own Masala'));
    expect(find.text('My Own Masala'), findsOneWidget);
    expect(find.text('My own description'), findsOneWidget);
    expect(find.text('சக்தி மசாலா'), findsNothing);
    expect(p.id, 'p_sakthi');
    expect(p.name, 'My Own Masala');
  });

  testWidgets('Shop Details: progress, requirements and actions are Tamil', (
    tester,
  ) async {
    _phone(tester);
    final c = await _vendor();
    c.addMediaGroups('s_lakshmi', [
      MediaGroupPlan(_media('GSB_SINGLE'), 2),
      MediaGroupPlan(_media('NLB_BOX_FRAME'), 1),
      MediaGroupPlan(_media(SignageCatalog.foamVinyl), 1),
    ]);
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await _toTamil(tester);
    await _open(tester, const ShopDetailScreen(shopId: 's_lakshmi'));

    await _show(tester, find.text('தள ஆய்வு மற்றும் ஆவணங்கள்'));
    expect(find.text('தள ஆய்வு மற்றும் ஆவணங்கள்'), findsOneWidget);
    await _show(tester, find.text('இன்னும் உருவாக்கப்படவில்லை'));
    expect(find.text('இன்னும் உருவாக்கப்படவில்லை'), findsOneWidget);
    expect(find.textContaining('விருப்பத்திற்குரியது'), findsOneWidget);
    await _show(tester, find.text('தள ஆய்வு முன்னேற்றம்'));
    expect(find.text('தள ஆய்வு முன்னேற்றம்'), findsOneWidget);
    expect(
      find.textContaining('பலகைகளில் 0 பலகைகள் மதிப்பாய்வுக்குத் தயார்'),
      findsOneWidget,
    );
    await _show(tester, find.text('விளம்பரப் பலகை தேவைகள் (3)'));
    expect(find.text('விளம்பரப் பலகை தேவைகள் (3)'), findsOneWidget);
    expect(find.text('3 பலகை வகைகள் · 4 பலகைகள்'), findsOneWidget);
    await _show(tester, find.textContaining('எண்ணிக்கை 2'));
    expect(find.textContaining('எண்ணிக்கை 2'), findsWidgets);
    expect(find.textContaining('நிலுவையில்'), findsWidgets);
    await _show(tester, find.text('GSB ஒற்றைப் பக்கம் 01'));
    expect(find.text('GSB ஒற்றைப் பக்கம் 01'), findsWidgets);
    expect(find.text('சரிபார்த்து சமர்ப்பிக்கவும்'), findsOneWidget);

    // Originals are gone from these UI elements.
    expect(find.text('Recce progress'), findsNothing);
    expect(find.textContaining('Signage requirements'), findsNothing);
    expect(find.text('REVIEW & SUBMIT'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Board Editor: localized media tabs, units and installation', (
    tester,
  ) async {
    _phone(tester);
    final c = await _vendor();
    final boards = c.addMediaGroups('s_lakshmi', [
      MediaGroupPlan(_media('GSB_SINGLE'), 2),
      MediaGroupPlan(_media('NLB_BOX_FRAME'), 1),
      MediaGroupPlan(_media(SignageCatalog.foamVinyl), 1),
    ]);
    final gsb = boards.first;
    // Per-board independent installations.
    gsb.activeUnits.first.installationCode = SignageCatalog.shopFascia;
    gsb.activeUnits.last.installationCode = SignageCatalog.wallMount;
    c.touchBoard('s_lakshmi', gsb);

    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await _toTamil(tester);
    await _open(
      tester,
      BoardEditorScreen(
        shopId: 's_lakshmi',
        boardId: gsb.id,
        initialStep: 2,
      ),
    );

    await _showTab(tester, find.text('GSB ஒற்றைப் பக்கம் (2)'));
    expect(find.text('GSB ஒற்றைப் பக்கம் (2)'), findsOneWidget);
    await _showTab(tester, find.text('NLB பெட்டி வகை'));
    expect(find.text('NLB பெட்டி வகை'), findsWidgets);
    await _showTab(tester, find.text('ஃபோம் வினைல்'));
    expect(find.text('ஃபோம் வினைல்'), findsWidgets);
    expect(find.text('நடைபெறுகிறது'), findsWidgets);
    expect(find.text('GSB ஒற்றைப் பக்கம் 01'), findsWidgets);
    expect(find.text('GSB ஒற்றைப் பக்கம் 02'), findsWidgets);
    expect(
      find.textContaining('கலப்பு (கடை முகப்புப் பொருத்தம் / சுவரில் பொருத்துதல்)'),
      findsOneWidget,
    );
    expect(find.textContaining('கடை முகப்புப் பொருத்தம்'), findsWidgets);
    expect(find.textContaining('சுவரில் பொருத்துதல்'), findsWidgets);
    // Canonical ids were never swapped by translation.
    expect(gsb.activeUnits.first.installationCode, SignageCatalog.shopFascia);
    expect(gsb.activeUnits.last.installationCode, SignageCatalog.wallMount);
    expect(gsb.mediaCode, SignageCatalog.gsb);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom board name survives Tamil and language switching', (
    tester,
  ) async {
    _phone(tester);
    final c = await _vendor();
    final b = c.addBoard('s_lakshmi')
      ..name = 'Front'
      ..mediaCode = SignageCatalog.gsb
      ..installationCode = SignageCatalog.shopFascia;
    c.touchBoard('s_lakshmi', b);
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await _toTamil(tester);
    await _open(
      tester,
      BoardEditorScreen(shopId: 's_lakshmi', boardId: b.id),
    );
    expect(find.text('Front'), findsWidgets);
    await _toTamil(tester); // English
    await _toTamil(tester); // Tamil again
    expect(b.name, 'Front');
    expect(find.text('Front'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uf never re-scans placeholders injected inside user values', (
    tester,
  ) async {
    late String rendered;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ta'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) {
        rendered = context.uf('Submitted by {0}', ['User {1} literal']);
        return const SizedBox.shrink();
      }),
    ));
    expect(rendered, 'User {1} literal சமர்ப்பித்தார்');
  });

  testWidgets('responsive Tamil shop details and media tabs', (tester) async {
    for (final width in <int>[320, 360, 400]) {
      _phone(tester, width: width);
      final c = await _vendor();
      final boards = c.addMediaGroups('s_lakshmi', [
        MediaGroupPlan(_media('GSB_SINGLE'), 2),
        MediaGroupPlan(_media('NLB_BOX_FRAME'), 1),
      ]);
      await tester.pumpWidget(
        AdinnRecceApp(key: ValueKey('responsive_$width'), controller: c),
      );
      await tester.pumpAndSettle();
      await _toTamil(tester);
      await _open(tester, const ShopDetailScreen(shopId: 's_lakshmi'));
      // Force the lazily built lower cards to render before checking layout.
      await tester.drag(
        find.byType(ListView).first,
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'shop $width');

      await _open(
        tester,
        BoardEditorScreen(shopId: 's_lakshmi', boardId: boards.first.id),
      );
      expect(find.byKey(const Key('media_tabs')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'editor $width');
    }
  });

  testWidgets('every supported installation name has a Tamil display variant', (
    tester,
  ) async {
    final labels = <String>[];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ta'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) {
        labels.addAll([
          'Shop Fascia',
          'Wall Mount',
          'Double Pole',
          'Single Pole',
          'Rooftop',
          'Support Pipe',
          'Projecting Mount',
          'Hanging Mount',
          'Direct on Wall',
          'Other',
        ].map(context.installationLabel));
        return const SizedBox.shrink();
      }),
    ));
    for (final value in labels) {
      expect(value.contains(RegExp(r'[஀-௿]')), isTrue, reason: value);
    }
  });

  test('display helpers use ids and verified originals only', () {
    expect(TaDisplay.projects['p_sakthi']!.nameTa, 'சக்தி மசாலா');
    expect(TaDisplay.media['GSB Single'], 'GSB ஒற்றைப் பக்கம்');
    expect(
      TaDisplay.installations['Shop Fascia'],
      'கடை முகப்புப் பொருத்தம்',
    );
  });
}
