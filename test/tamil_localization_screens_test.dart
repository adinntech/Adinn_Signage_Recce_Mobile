import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/app.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/projects/project_detail_screen.dart';
import 'package:signage_recce/features/projects/task_detail_screen.dart';
import 'package:signage_recce/l10n/l10n.dart';
import 'package:signage_recce/l10n/ta_ui.dart';
import 'package:signage_recce/state/app_controller.dart';

Future<AppController> _vendor() async {
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin(DemoAccounts.vendorPin);
  return c;
}

void _phone(WidgetTester t, {int width = 360}) {
  t.view.physicalSize = Size(width * 3, 800 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Future<void> _toTamil(WidgetTester t) async {
  await t.tap(find.byKey(const Key('lang_switch')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('dashboard predefined + dynamic content is Tamil', (tester) async {
    _phone(tester);
    final c = await _vendor();
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();

    // English baseline.
    expect(find.textContaining('shop(s) need field work'), findsOneWidget);
    await _toTamil(tester);

    expect(find.textContaining('வணக்கம்,'), findsOneWidget);
    expect(find.text('ஒதுக்கப்பட்ட கடைகள்'), findsOneWidget);
    expect(find.text('நடைபெறுகிறது'), findsWidgets);
    expect(find.text('ஒப்புதல் நிலுவையில்'), findsOneWidget);
    expect(find.text('ஒப்புதல் பெற்றவை'), findsWidgets);
    expect(find.text('நிராகரிக்கப்பட்டவை'), findsWidgets);
    expect(find.text('திட்டங்கள்'), findsWidgets);
    expect(
      find.text('கடைகள், உரிமையாளர்கள், பகுதிகள், திட்டங்களைத் தேடுக'),
      findsOneWidget,
    );
    expect(find.text('மொத்த முன்னேற்றம்'), findsOneWidget);
    expect(find.text('ஒப்புதலுக்குச் சமர்ப்பிக்கப்பட்டவை'), findsOneWidget);
    expect(find.text('இறுதி ஒப்புதல் பெற்றவை'), findsOneWidget);
    expect(find.textContaining('கடைகளில் களப்பணி தேவை'), findsOneWidget);
    // User data is untouched.
    expect(find.text(c.currentUser!.name), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('projects list: status, counts and deadline in Tamil', (tester) async {
    _phone(tester);
    final c = await _vendor();
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await _toTamil(tester);
    await tester.tap(find.text('திட்டங்கள்').last);
    await tester.pumpAndSettle();

    expect(
      find.text('திட்டம், குறியீடு அல்லது பகுதியைத் தேடுக'),
      findsOneWidget,
    );
    // Company names / codes are business data and must stay as-is.
    expect(find.text('ஏசியன் பெயிண்ட்ஸ்'), findsOneWidget);
    expect(find.textContaining('AP-TN-2026'), findsOneWidget);
    expect(c.project('p_asian')!.name, 'Asian Paints');
    expect(find.textContaining('பணிகள்'), findsWidgets);
    expect(find.textContaining('கடைகள்'), findsWidgets);
    expect(find.textContaining('முடிவு நாள்:'), findsWidgets);
    expect(find.textContaining('கடைகளுக்கு ஒப்புதல்'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('project details: headings, labels and date range', (tester) async {
    _phone(tester);
    final c = await _vendor();
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await _toTamil(tester);

    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(
      builder: (_) => const ProjectDetailScreen(projectId: 'p_asian'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('திட்ட விவரங்கள்'), findsOneWidget);
    expect(find.text('வாடிக்கையாளர்'), findsOneWidget);
    expect(find.text('திட்டக் குறியீடு'), findsOneWidget);
    expect(find.text('பகுதி'), findsOneWidget);
    expect(find.text('கால அளவு'), findsOneWidget);
    expect(find.text('ஒருங்கிணைப்பாளர்'), findsOneWidget);
    expect(find.textContaining('ஒருங்கிணைப்பாளரை அழைக்கவும்'), findsOneWidget);
    expect(find.text('கடைகளின் நிலை'), findsOneWidget);
    expect(find.text('மொத்தம்'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('தள ஆய்வுப் பணிகள்'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('தள ஆய்வுப் பணிகள்'), findsOneWidget);
    expect(find.textContaining('கடைசி நாள்:'), findsWidgets);
    // Preserved business data.
    expect(find.text('Priya Shankar'), findsOneWidget);
    expect(find.textContaining('9840011223'), findsOneWidget);
    expect(find.text('ஏசியன் பெயிண்ட்ஸ்'), findsOneWidget);
    expect(c.project('p_asian')!.name, 'Asian Paints');
    expect(tester.takeException(), isNull);
  });

  testWidgets('task details: priority, filters, counts and Add Shop', (tester) async {
    _phone(tester);
    final c = await _vendor();
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await _toTamil(tester);

    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(
      builder: (_) => const TaskDetailScreen(taskId: 't_srirangam'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('அதிக முன்னுரிமை'), findsOneWidget);
    expect(find.text('இடம்'), findsOneWidget);
    expect(find.text('கடைசி தேதி'), findsOneWidget);
    expect(find.text('பொறுப்பாளர்'), findsOneWidget);
    expect(find.textContaining('அனைத்தும் ('), findsOneWidget);
    expect(find.textContaining('செய்ய வேண்டியவை ('), findsOneWidget);
    expect(find.textContaining('சமர்ப்பிக்கப்பட்டவை ('), findsOneWidget);
    expect(find.text('கடையைச் சேர்க்கவும்'), findsOneWidget);
    expect(find.textContaining('சமர்ப்பிக்கப்பட்டுள்ளன'), findsOneWidget);
    // Preserved business data.
    expect(find.text('சிரிரங்கம், திருச்சிராப்பள்ளி'), findsOneWidget);
    expect(c.task('t_srirangam')!.location, 'Srirangam');
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation fits at 320/360/400dp in Tamil', (tester) async {
    for (final width in <int>[320, 360, 400]) {
      _phone(tester, width: width);
      final c = await _vendor();
      await tester.pumpWidget(AdinnRecceApp(controller: c));
      await tester.pumpAndSettle();
      await _toTamil(tester);
      for (final label in ['முகப்பு', 'திட்டங்கள்', 'சமர்ப்பிப்பு', 'செயல்பாடு', 'சுயவிவரம்']) {
        expect(find.text(label), findsWidgets, reason: '$width dp: $label');
      }
      expect(tester.takeException(), isNull, reason: '$width dp overflow');
    }
  });

  testWidgets('language switch keeps typed input and navigation state', (tester) async {
    _phone(tester);
    final c = await _vendor();
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();

    final field = find.byType(TextField).first;
    await tester.enterText(field, 'Ramco');
    await tester.pump();
    await _toTamil(tester);
    expect(
      tester.widget<EditableText>(find.byType(EditableText).first).controller.text,
      'Ramco',
    );
    // Still on the Projects tab after the switch.
    expect(find.text('திட்டம், குறியீடு அல்லது பகுதியைத் தேடுக'), findsOneWidget);
    await _toTamil(tester);
    expect(find.text('ENG'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status labels, unknown fallback and dates use the active locale',
      (tester) async {
    Widget probe(Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Text(
        '${context.statusLabel(RecceStatus.approved)}|'
        '${context.statusShortLabel(RecceStatus.rejectedOps)}|'
        '${context.statusPlural('Approved')}|'
        '${context.statusSingular('Approved')}|'
        '${context.statusPlural('UNKNOWN_STATUS')}|'
        '${context.fmtDateL(DateTime(2026, 11, 27))}|'
        '${context.shopsSubmittedSummary(0, 1, 'In Progress')}|'
        '${context.boardCount(1)}',
      )),
    );

    await tester.pumpWidget(probe(const Locale('en')));
    expect(
      find.text('Approved|Rejected|Approved|Approved|UNKNOWN_STATUS|'
          '27 Nov 2026|0/1 shops submitted • In Progress|1 board'),
      findsOneWidget,
    );
    await tester.pumpWidget(probe(const Locale('ta')));
    expect(
      find.text('ஒப்புதல் பெற்றது|நிராகரிக்கப்பட்டது|ஒப்புதல் பெற்றவை|'
          'ஒப்புதல் பெற்றது|UNKNOWN_STATUS|27 நவம்பர் 2026|'
          '1 கடையில் 0 கடைகள் சமர்ப்பிக்கப்பட்டுள்ளன • நடைபெறுகிறது|1 பலகை'),
      findsOneWidget,
    );
  });

  test('count helpers handle zero, one and many without changing values', () {
    // Pure checks of the canonical templates used by the helpers.
    expect(TaUi.tr('{0} task(s)'), '{0} பணிகள்');
    expect(TaUi.tr('{0}/{1} shops approved'),
        '{1} கடைகளில் {0} கடைகளுக்கு ஒப்புதல்');
    expect(TaUi.tr('Ends {0}'), 'முடிவு நாள்: {0}');
    expect(TaUi.tr('Due {0}'), 'கடைசி நாள்: {0}');
    expect(TaUi.tr('{0} shop(s) need field work'),
        '{0} கடைகளில் களப்பணி தேவை');
  });
}
