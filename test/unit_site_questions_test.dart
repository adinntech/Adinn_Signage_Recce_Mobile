import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/catalog/site_checklists.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/features/drawing/signage_geometry.dart';
import 'package:signage_recce/features/model3d/signage_spec.dart';
import 'package:signage_recce/features/report/report_data.dart';
import 'package:signage_recce/features/report/report_service.dart';
import 'package:signage_recce/state/app_controller.dart';

import 'helpers.dart';
import 'model_viewer_pdf_test.dart' show FakeModels;
import 'report_test.dart' show FakeImages;

const _shop = 's_lakshmi';

Future<AppController> _vendor() async {
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin(DemoAccounts.vendorPin);
  return c;
}

MediaOption _o(String key) =>
    SignageCatalog.mediaOptions.firstWhere((o) => o.key == key);

/// The exact scenario of the bug report: GSB Single x2, different sizes,
/// Wall Mount + Double Pole.
Future<(AppController, Board)> _gsbTwo() async {
  final c = await _vendor();
  final b = c.addMediaGroups(_shop, [
    MediaGroupPlan(_o('GSB_SINGLE'), 2),
  ]).single;
  c.setSizeMode(_shop, b, SizeMode.different);
  c.setUnitSize(_shop, b, b.units[0], width: 3, height: 4);
  c.setUnitSize(_shop, b, b.units[1], width: 5, height: 6);
  c.setUnitInstallation(_shop, b, b.units[0], 'wall_mount');
  c.setUnitInstallation(_shop, b, b.units[1], 'double_pole');
  return (c, b);
}

Widget _host(AppController c, Widget child) =>
    ChangeNotifierProvider<AppController>.value(
      value: c,
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 3200);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

SitePhoto _photo() => SitePhoto(
  id: 'ph1',
  path: 'demo://front',
  label: 'Front view',
  capturedAt: DateTime(2026, 11, 24),
  width: 100,
  height: 80,
);

/// Completes one media group through the data layer (only used for the
/// PDF-scope matrix; the visible-UI flow has its own test below).
void _complete(AppController c, Board b, {String inst = 'double_pole'}) {
  b
    ..width = 6
    ..height = 3
    ..installationCode = inst;
  for (final u in b.units) {
    u.installationCode = null;
  }
  completeAnswers(b);
  c.addPhoto(_shop, b.id, _photo());
}

void main() {
  group('Reproduce the screenshot scenario', () {
    test('area, summary and per-board questions', () async {
      final (c, b) = await _gsbTwo();
      expect(b.areaSqFt, closeTo(42, 1e-9));
      expect(SignageCatalog.installationSummary(b), contains('Mixed'));
      final q1 = SignageCatalog.questionsForUnit(b, b.units[0]).map((q) => q.id);
      final q2 = SignageCatalog.questionsForUnit(b, b.units[1]).map((q) => q.id);
      expect(q1.toSet(), isNot(q2.toSet()), reason: 'own installation each');
      expect(c.siteQuestionsPendingFor(b, b.units[0]), greaterThan(0));
      expect(c.siteQuestionsPendingFor(b, b.units[1]), greaterThan(0));
    });

    test('Site Questions never claims 0 while the checklist is pending', () async {
      final (c, b) = await _gsbTwo();
      final pending = c.siteQuestionsPending(b);
      expect(pending, greaterThan(0));
      // Same total the Board checklist lists (answers + checklist).
      final listed = c
          .boardIssueDetails(b)
          .where((i) => i.section == IssueSection.questions)
          .length;
      expect(listed, greaterThan(0));
      expect(
        c.boardIssues(b).where((i) => i.contains('site checklist')),
        hasLength(2),
        reason: 'one checklist issue per physical board',
      );
    });

    test('board 01 complete, board 02 still pending', () async {
      final (c, b) = await _gsbTwo();
      _answerUnit(b, b.units[0]);
      expect(c.siteQuestionsPendingFor(b, b.units[0]), 0);
      expect(c.siteQuestionsPendingFor(b, b.units[1]), greaterThan(0));
      expect(c.siteQuestionsPending(b), greaterThan(0));
      _answerUnit(b, b.units[1]);
      expect(c.siteQuestionsPending(b), 0);
      expect(
        c.boardIssues(b).where(
          (i) => i.contains('site question') || i.contains('site checklist'),
        ),
        isEmpty,
      );
      // Real remaining requirement stays visible.
      expect(c.boardIssues(b), contains('Capture at least one site photo'));
    });

    test('issues point at the right board and section', () async {
      final (c, b) = await _gsbTwo();
      final d = c.boardIssueDetails(b);
      final u2 = d.firstWhere(
        (i) =>
            i.section == IssueSection.questions && i.unitId == b.units[1].id,
      );
      expect(u2.text, contains('Unit 02'));
      final u1 = d.firstWhere(
        (i) =>
            i.section == IssueSection.questions && i.unitId == b.units[0].id,
      );
      expect(u1.unitId, isNot(u2.unitId));
      expect(
        d.firstWhere((i) => i.section == IssueSection.photos).unitId,
        isNull,
      );
    });

    test('warnings stay advisory, not blocking', () async {
      final (c, b) = await _gsbTwo();
      _answerUnit(b, b.units[0]);
      _answerUnit(b, b.units[1]);
      c.addPhoto(_shop, b.id, _photo());
      expect(c.boardIssues(b), isEmpty);
      expect(
        c.boardWarnings(b, null),
        contains('Only one photo angle captured'),
      );
    });
  });

  group('Single board (NLB Single 9 x 3, Single Pole)', () {
    test('questions + checklist counted once, no false zero', () async {
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('NLB_SINGLE_FRAME'), 1),
      ]).single
        ..width = 9
        ..height = 3
        ..installationCode = 'single_pole';
      expect(c.siteQuestionsPending(b), greaterThan(0));
      expect(c.boardIssues(b).any((i) => i.contains('site checklist')), isTrue);
      _answerUnit(b, b.units.first);
      expect(c.siteQuestionsPending(b), 0);
      expect(c.boardIssues(b).any((i) => i.contains('site checklist')), isFalse);
    });
  });

  group('Independent data', () {
    test('answers belong to one board only', () async {
      final (c, b) = await _gsbTwo();
      final u1 = b.units[0], u2 = b.units[1];
      expect(identical(SignageCatalog.answersOf(b, u1), b.answers), isTrue);
      expect(identical(SignageCatalog.answersOf(b, u2), u2.siteAnswers), isTrue);
      c.setUnitAnswer(_shop, b, u2, 'power_available', true);
      expect(SignageCatalog.answersOf(b, u2)['power_available'], true);
      expect(SignageCatalog.answersOf(b, u1).containsKey('power_available'),
          isFalse);
      c.setUnitAnswer(_shop, b, u1, 'power_available', false);
      expect(SignageCatalog.answersOf(b, u2)['power_available'], true);
    });

    test('false and zero are valid answers', () async {
      final (c, b) = await _gsbTwo();
      final u = b.units[1];
      c.setUnitAnswer(_shop, b, u, 'power_available', false);
      final q = SignageCatalog.questionsForUnit(b, u)
          .firstWhere((x) => x.id == 'power_available');
      expect(q.isAnswered(SignageCatalog.answersOf(b, u)), isTrue);
    });

    test('save / reopen keeps every unit answer; old JSON loads', () async {
      final (c, b) = await _gsbTwo();
      _answerUnit(b, b.units[0]);
      _answerUnit(b, b.units[1]);
      final copy = Board.fromJson(
        jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>,
      );
      expect(copy.units[1].siteAnswers, b.units[1].siteAnswers);
      expect(copy.answers, b.answers);
      expect(c.siteQuestionsPending(copy), 0);
      // Older record: no siteAnswers key at all.
      final old = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(b.toJson())) as Map,
      );
      for (final u in old['units'] as List) {
        (u as Map).remove('siteAnswers');
      }
      final loaded = Board.fromJson(old);
      expect(loaded.units[1].siteAnswers, isEmpty);
      expect(loaded.answers, b.answers, reason: 'group answers untouched');
      expect(loaded.units, hasLength(2));
    });

    test('2D / 3D use the selected board size and installation', () async {
      final (_, b) = await _gsbTwo();
      final g1 = SignageGeometry.fromBoard(b, unit: b.units[0]);
      final g2 = SignageGeometry.fromBoard(b, unit: b.units[1]);
      expect((g1.widthFt, g1.heightFt), (3, 4));
      expect((g2.widthFt, g2.heightFt), (5, 6));
      expect(g1.installationCode, 'wall_mount');
      expect(g2.installationCode, 'double_pole');
      final s1 = SignageModelSpec.of(b, b.units[0]);
      final s2 = SignageModelSpec.of(b, b.units[1]);
      expect(s1.installationCode, 'wall_mount');
      expect(s2.installationCode, 'double_pole');
      expect(s1.widthMm, isNot(s2.widthMm));
    });

    test('changing board 02 installation keeps board 01 untouched', () async {
      final (c, b) = await _gsbTwo();
      _answerUnit(b, b.units[0]);
      final before = c.siteQuestionsPendingFor(b, b.units[0]);
      c.setUnitInstallation(_shop, b, b.units[1], 'rooftop');
      expect(c.siteQuestionsPendingFor(b, b.units[0]), before);
      expect(b.installationOf(b.units[0]), 'wall_mount');
    });

    test('removing the first board hands its answers to the next', () async {
      final (c, b) = await _gsbTwo();
      c.setUnitAnswer(_shop, b, b.units[1], 'power_available', true);
      final id0 = b.units[0].id;
      await c.removeUnit(_shop, b, id0);
      expect(b.units.first.id, isNot(id0));
      expect(b.answers['power_available'], true);
    });
  });

  group('Common answers between boards', () {
    test('installation-specific answers are never copied', () async {
      final (c, b) = await _gsbTwo();
      final u1 = b.units[0], u2 = b.units[1];
      c.setUnitAnswer(_shop, b, u1, 'wall_type', 'Brick');
      c.setUnitAnswer(_shop, b, u1, 'power_available', true);
      final plan = SignageCatalog.planUnitAnswers(b, u1, b, u2);
      final ids = plan.toCopy.map((q) => q.id);
      expect(ids, contains('power_available'));
      expect(ids, isNot(contains('wall_type')));
      final n = c.copyCommonAnswers(
        _shop,
        b,
        b,
        sourceUnit: u1,
        targetUnit: u2,
      );
      expect(n, greaterThan(0));
      expect(u2.siteAnswers['power_available'], true);
      expect(u2.siteAnswers.containsKey('wall_type'), isFalse);
      // Independent afterwards.
      c.setUnitAnswer(_shop, b, u2, 'power_available', false);
      expect(b.answers['power_available'], true);
    });

    test('manual answers survive; copying never completes the section', () async {
      final (c, b) = await _gsbTwo();
      final u1 = b.units[0], u2 = b.units[1];
      c.setUnitAnswer(_shop, b, u1, 'power_available', true);
      c.setUnitAnswer(_shop, b, u2, 'power_available', false);
      c.copyCommonAnswers(_shop, b, b, sourceUnit: u1, targetUnit: u2);
      expect(u2.siteAnswers['power_available'], false);
      expect(c.siteQuestionsPendingFor(b, u2), greaterThan(0));
    });

    test('works across media groups too', () async {
      final c = await _vendor();
      final g = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 1),
        MediaGroupPlan(_o('ACRYLIC'), 1),
      ]);
      g[0].installationCode = 'double_pole';
      g[1].installationCode = 'wall_mount';
      c.setUnitAnswer(_shop, g[0], g[0].units.first, 'owner_permission', true);
      final n = c.copyCommonAnswers(_shop, g[0], g[1]);
      expect(n, greaterThan(0));
      expect(g[1].answers['owner_permission'], true);
    });
  });

  group('Separate vs Combined PDF eligibility', () {
    Future<(AppController, List<Board>)> shop3() async {
      final c = await _vendor();
      final s = c.shop(_shop)!;
      // Start from an empty shop with valid shop-level details.
      s.boards.clear();
      c.setShopLocation(s, gpsAt(10.8627, 78.6897));
      final g = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 2),
        MediaGroupPlan(_o('NLB_SINGLE_FRAME'), 1),
        MediaGroupPlan(_o('ACRYLIC'), 1),
      ]);
      return (c, g);
    }

    test('all incomplete: everything disabled', () async {
      final (c, g) = await shop3();
      final s = c.shop(_shop)!;
      expect(recceComplete(c, s), isFalse);
      for (final b in g) {
        expect(groupReportReady(c, s, b), isFalse);
      }
    });

    test('one complete group is exportable alone; combined is not', () async {
      final (c, g) = await shop3();
      final s = c.shop(_shop)!;
      _complete(c, g[0]);
      expect(groupReportReady(c, s, g[0]), isTrue);
      expect(groupReportReady(c, s, g[1]), isFalse);
      expect(groupReportReady(c, s, g[2]), isFalse);
      expect(recceComplete(c, s), isFalse);
    });

    test('two boards in a group: one incomplete disables the group', () async {
      final (c, g) = await shop3();
      final s = c.shop(_shop)!;
      _complete(c, g[0]);
      // Board 02 loses its answers.
      g[0].units[1].siteAnswers.clear();
      expect(groupReportReady(c, s, g[0]), isFalse);
    });

    test('two complete groups export separately, combined still off', () async {
      final (c, g) = await shop3();
      final s = c.shop(_shop)!;
      _complete(c, g[0]);
      _complete(c, g[1], inst: 'single_pole');
      expect(groupReportReady(c, s, g[0]), isTrue);
      expect(groupReportReady(c, s, g[1]), isTrue);
      expect(recceComplete(c, s), isFalse);
    });

    test('all complete: combined on; edit makes only that group off', () async {
      final (c, g) = await shop3();
      final s = c.shop(_shop)!;
      _complete(c, g[0]);
      _complete(c, g[1], inst: 'single_pole');
      _complete(c, g[2], inst: 'wall_mount');
      expect(recceComplete(c, s), isTrue);
      g[2].photos.clear();
      expect(recceComplete(c, s), isFalse);
      expect(groupReportReady(c, s, g[2]), isFalse);
      expect(groupReportReady(c, s, g[0]), isTrue);
    });

    test('service validates scope, ids and the requested group only', () async {
      final (c, g) = await shop3();
      _complete(c, g[0]);
      final models = FakeModels();
      final files = <String, Uint8List>{};
      final service = ReportService(
        images: FakeImages(),
        models: models,
        writer: (b) async {
          files['/r.pdf'] = b;
          return '/r.pdf';
        },
        reader: (p) async => files[p],
        useIsolate: false,
        compress: false,
      );
      // Another media group is incomplete: the combined export is refused...
      await expectLater(
        service.generate(c, _shop, requireComplete: true),
        throwsA(isA<StateError>()),
      );
      // ...unknown / empty / incomplete groups are refused...
      for (final ids in [
        <String>{'nope'},
        <String>{},
        {g[1].id},
      ]) {
        await expectLater(
          service.generate(c, _shop, groupIds: ids, requireComplete: true),
          throwsA(isA<StateError>()),
          reason: '$ids',
        );
      }
      // ...but the completed group exports on its own.
      final r = await service.generate(
        c,
        _shop,
        groupIds: {g[0].id},
        requireComplete: true,
      );
      expect(r.pageCount, greaterThan(0));
      expect(models.calls.where((e) => e.startsWith('3d:')), hasLength(2));
      expect(models.calls.where((e) => e.startsWith('3d-rear:')), hasLength(2));
      // Content: only the chosen group, each board its own answers.
      final build = buildReportData(
        c,
        c.shop(_shop)!,
        now: DateTime(2026, 11, 25),
        groupIds: {g[0].id},
      );
      final groups = build.data['groups'] as List;
      expect(groups, hasLength(1));
      final overview = build.data['overview'] as Map;
      expect(overview['units'], 2);
      expect(overview['mediaGroups'], 1);
      expect(overview['shopMediaGroups'], 3);
      final answers = (groups.single as Map)['siteAnswers'] as List;
      expect(
        answers.any((a) => '${(a as List).first}'.startsWith('GSB Single 02')),
        isTrue,
      );
    });

    test('required drawing images survive the image budget', () async {
      final (c, g) = await shop3();
      _complete(c, g[0]);
      for (var i = 0; i < kMaxReportImages + 10; i++) {
        c.addPhoto(
          _shop,
          g[0].id,
          SitePhoto(
            id: 'p$i',
            path: 'demo://p$i',
            label: 'P$i',
            capturedAt: DateTime(2026, 11, 24),
            width: 10,
            height: 10,
          ),
        );
      }
      final build = buildReportData(
        c,
        c.shop(_shop)!,
        now: DateTime(2026, 11, 25),
        groupIds: {g[0].id},
      );
      final sheets = [
        for (final it in ((build.data['groups'] as List).single as Map)['items']
            as List)
          (it as Map)['sheet'] as Map,
      ];
      expect(sheets, hasLength(2));
      for (final s in sheets) {
        expect(s.keys, containsAll(['front', 'side', 'model', 'model_rear']));
      }
      expect(build.images.length, lessThanOrEqualTo(kMaxReportImages));
    });
  });

  group('Visible UI: complete the questions and see validation update', () {
    testWidgets('Board 01 then Board 02 through the Site Questions step', (
      tester,
    ) async {
      _phone(tester);
      final (c, b) = await _gsbTwo();
      await tester.pumpWidget(
        _host(
          c,
          BoardEditorScreen(
            shopId: _shop,
            boardId: b.id,
            initialStep: BoardEditorScreen.siteQuestionsStep,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unit_questions_header')), findsOneWidget);
      // Subtitle shows the real pending total, never a false zero.
      String subtitle() =>
          tester.widget<Text>(find.byKey(const Key('site_questions_subtitle'))).data!;
      expect(subtitle(), isNot('0 required pending'));
      final startTotal = c.siteQuestionsPending(b);

      await _answerThroughUi(tester, c, b, b.units[0]);
      expect(c.siteQuestionsPendingFor(b, b.units[0]), 0);
      expect(c.siteQuestionsPendingFor(b, b.units[1]), greaterThan(0));
      expect(c.siteQuestionsPending(b), lessThan(startTotal));
      expect(subtitle(), isNot('0 required pending'));
      // Answers were saved on board 01 only.
      expect(b.units[1].siteAnswers, isEmpty);

      // Move to board 02 through the visible selector.
      final chip2 = find.byKey(Key('unit_bar_${b.units[1].id}'));
      await tester.ensureVisible(chip2); // horizontal scroll bar
      await tester.pumpAndSettle();
      await tester.tap(chip2);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('unit_questions_header')).evaluate().isNotEmpty,
        isTrue,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('unit_questions_header')))
            .data,
        contains('GSB Single 02'),
      );
      expect(find.textContaining('GSB Single 02'), findsWidgets);
      await _answerThroughUi(tester, c, b, b.units[1]);

      expect(c.siteQuestionsPending(b), 0);
      expect(subtitle(), '0 required pending');
      expect(b.units[1].siteAnswers, isNotEmpty);
      // The remaining real requirement (photo) still blocks completion.
      expect(c.boardIssues(b), contains('Capture at least one site photo'));
    });
  });
}

/// Answers every required question of [u] directly in the data (only for
/// the unit-level assertions above; the UI test uses _answerThroughUi).
void _answerUnit(Board b, SignageUnit u) {
  final a = SignageCatalog.answersOf(b, u);
  for (var guard = 0; guard < 5; guard++) {
    final missing = SignageCatalog.missingAnswersFor(b, u);
    if (missing.isEmpty) break;
    for (final q in missing) {
      a[q.id] = switch (q.type) {
        QuestionType.yesNo => true,
        QuestionType.choice => q.options.first,
        QuestionType.number => 5.0,
        QuestionType.text => 'ok',
      };
    }
  }
  for (final q in SiteChecklists.questionsFor(b.mediaCode, b.installationOf(u))) {
    if (!q.required || q.isAnswered(u.checklist[q.id])) continue;
    u.checklist[q.id] = ChecklistResponse(
      questionId: q.id,
      value: switch (q.type) {
        ChecklistResponseType.yesNoNa => 'yes',
        ChecklistResponseType.dropdown => q.options.first,
        ChecklistResponseType.numeric => 2,
        _ => 'ok',
      },
    );
  }
}

/// Fills every missing required question of [u] by tapping / typing in the
/// visible Site Questions + checklist widgets.
Future<void> _answerThroughUi(
  WidgetTester tester,
  AppController c,
  Board b,
  SignageUnit u,
) async {
  Future<void> show(Finder f) async {
    expect(f, findsOneWidget, reason: 'widget for ${f.description}');
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  for (var guard = 0; guard < 6; guard++) {
    final qs = SignageCatalog.missingAnswersFor(b, u);
    // Checklist-only questions (equivalents are answered above, once).
    final cl = SiteChecklists.uniqueMissing(b, u);
    if (qs.isEmpty && cl.isEmpty) break;
    for (final q in qs) {
      switch (q.type) {
        case QuestionType.yesNo:
          final f = find.byKey(Key('q_${q.id}_true'));
          await show(f);
          await tester.tap(f);
        case QuestionType.choice:
          final f = find.byKey(Key('q_${q.id}_${q.options.first}'));
          await show(f);
          await tester.tap(f);
        case QuestionType.number:
          final f = find.byKey(Key('q_${q.id}'));
          await show(f);
          await tester.enterText(f, '5');
        case QuestionType.text:
          final f = find.byKey(Key('q_${q.id}'));
          await show(f);
          await tester.enterText(f, 'ok');
      }
      await tester.pumpAndSettle();
    }
    for (final q in cl) {
      switch (q.type) {
        case ChecklistResponseType.yesNoNa:
          final f = find.byKey(Key('cl_${q.id}_yes'));
          await show(f);
          await tester.tap(f);
        case ChecklistResponseType.dropdown:
          final f = find.byKey(Key('cl_${q.id}'));
          await show(f);
          await tester.tap(f);
          await tester.pumpAndSettle();
          await tester.tap(find.text(q.options.first).last);
        case ChecklistResponseType.numeric:
          final f = find.byKey(Key('cl_${q.id}'));
          await show(f);
          await tester.enterText(f, '2');
        case ChecklistResponseType.shortText:
        case ChecklistResponseType.longText:
          final f = find.byKey(Key('cl_${q.id}'));
          await show(f);
          await tester.enterText(f, 'ok');
        case ChecklistResponseType.photoEvidence:
          break;
      }
      await tester.pumpAndSettle();
    }
  }
}
