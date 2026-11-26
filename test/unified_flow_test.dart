import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/question_equivalence.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/catalog/site_checklists.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/features/board/board_picker.dart';
import 'package:signage_recce/features/drawing/drawing_2d_screen.dart';
import 'package:signage_recce/features/report/report_service.dart';
import 'package:signage_recce/features/shop/shop_detail_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

import 'helpers.dart';
import 'ui_helpers.dart';

const _shop = 's_lakshmi';

Future<AppController> _vendor() async {
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin(DemoAccounts.vendorPin);
  return c;
}

MediaOption _o(String key) =>
    SignageCatalog.mediaOptions.firstWhere((o) => o.key == key);

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
  capturedAt: DateTime(2026, 11, 25),
  width: 100,
  height: 80,
  // GPS-tagged like a real camera photo.
  geo: gpsAt(10.8627, 78.6897),
);

Board _single(AppController c, String key, {String? inst}) {
  final b = c.addMediaGroups(_shop, [MediaGroupPlan(_o(key), 1)]).single
    ..width = 9
    ..height = 3
    ..installationCode = inst;
  return b;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  if (f.evaluate().isEmpty) {
    // Lazy lists build only what is near the viewport.
    await tester.scrollUntilVisible(
      f,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  expect(f, findsOneWidget, reason: key);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

int _step(WidgetTester t) => t.widget<Stepper>(find.byType(Stepper)).currentStep;

String _title(WidgetTester t) => t
    .widget<Text>(
      find.descendant(of: find.byType(AppBar), matching: find.byType(Text)).first,
    )
    .data!;

void main() {
  group('Drawing readiness uses each board\'s own installation', () {
    test('screenshot scenario: Shop Fascia + Wall Mount, group code empty', () async {
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 2),
      ]).single;
      c.setSizeMode(_shop, b, SizeMode.different);
      c.setUnitSize(_shop, b, b.units[0], width: 5, height: 3);
      c.setUnitSize(_shop, b, b.units[1], width: 6, height: 4);
      c.setUnitInstallation(_shop, b, b.units[0], 'shop_fascia');
      c.setUnitInstallation(_shop, b, b.units[1], 'wall_mount');
      expect(b.installationCode, isNull, reason: 'group level is empty');
      expect(SignageCatalog.installationSummary(b), contains('Mixed'));
      expect(SignageCatalog.drawingReadyUnits(b), hasLength(2));
      expect(SignageCatalog.unitDrawingBlocker(b, b.units[0]), isNull);
    });

    test('blockers are per board and name the actual reason', () async {
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 2),
      ]).single
        ..width = 6
        ..height = 3;
      c.setUnitInstallation(_shop, b, b.units[0], 'wall_mount');
      expect(SignageCatalog.unitDrawingBlocker(b, b.units[0]), isNull);
      expect(
        SignageCatalog.unitDrawingBlocker(b, b.units[1]),
        contains('GSB Single 02'),
      );
      expect(SignageCatalog.drawingReadyUnits(b), [b.units[0]]);
      // Missing size blocks only that board.
      c.setSizeMode(_shop, b, SizeMode.different);
      c.setUnitSize(_shop, b, b.units[0], width: null, height: null);
      expect(SignageCatalog.unitDrawingBlocker(b, b.units[0]),
          contains('width and height'));
    });

    test('questions / suggestions never block drawing', () async {
      final c = await _vendor();
      final b = _single(c, 'GSB_SINGLE', inst: 'wall_mount');
      expect(c.boardIssues(b), isNotEmpty);
      expect(SignageCatalog.unitDrawingBlocker(b, b.units.first), isNull);
    });

    testWidgets('workflow buttons are enabled with Different Installations', (
      tester,
    ) async {
      _phone(tester);
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 2),
      ]).single
        ..width = 5
        ..height = 3;
      c.setUnitInstallation(_shop, b, b.units[0], 'shop_fascia');
      c.setUnitInstallation(_shop, b, b.units[1], 'wall_mount');
      await tester.pumpWidget(
        _host(
          c,
          BoardEditorScreen(
            shopId: _shop,
            boardId: b.id,
            initialStep: BoardEditorScreen.stepCount - 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final k in ['open_2d', 'open_3d', 'open_camera_ar']) {
        final f = find.byKey(Key(k));
        await tester.ensureVisible(f);
        expect(
          tester.widget<OutlinedButton>(f).onPressed,
          isNotNull,
          reason: k,
        );
      }
      expect(find.byKey(const Key('drawings_blocker')), findsNothing);
    });

    testWidgets('missing installation keeps them disabled with the reason', (
      tester,
    ) async {
      _phone(tester);
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 2),
      ]).single
        ..width = 5
        ..height = 3;
      await tester.pumpWidget(
        _host(
          c,
          BoardEditorScreen(
            shopId: _shop,
            boardId: b.id,
            initialStep: BoardEditorScreen.stepCount - 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final f = find.byKey(const Key('open_2d'));
      await tester.ensureVisible(f);
      expect(tester.widget<OutlinedButton>(f).onPressed, isNull);
      expect(find.byKey(const Key('drawings_blocker')), findsOneWidget);
    });
  });

  group('Board selection', () {
    Future<Board> two(AppController c) async {
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 2),
      ]).single;
      c.setSizeMode(_shop, b, SizeMode.different);
      c.setUnitSize(_shop, b, b.units[0], width: 5, height: 3);
      c.setUnitSize(_shop, b, b.units[1], width: 6, height: 4);
      c.setUnitInstallation(_shop, b, b.units[0], 'shop_fascia');
      c.setUnitInstallation(_shop, b, b.units[1], 'wall_mount');
      return b;
    }

    Future<void> openEditor(WidgetTester t, AppController c, Board b) async {
      await t.pumpWidget(
        _host(
          c,
          BoardEditorScreen(
            shopId: _shop,
            boardId: b.id,
            initialStep: BoardEditorScreen.stepCount - 1,
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('single board opens directly, no popup', (tester) async {
      _phone(tester);
      final c = await _vendor();
      final b = _single(c, 'GSB_SINGLE', inst: 'wall_mount');
      await openEditor(tester, c, b);
      await _tap(tester, 'open_2d');
      expect(find.byKey(const Key('board_picker_title')), findsNothing);
      expect(find.byType(Drawing2DScreen), findsOneWidget);
    });

    testWidgets('two boards: names, sizes, Both Boards; cancel is harmless', (
      tester,
    ) async {
      _phone(tester);
      final c = await _vendor();
      final b = await two(c);
      final before = b.toJson().toString();
      await openEditor(tester, c, b);
      await _tap(tester, 'open_2d');
      expect(find.text('Select Boards for 2D Drawing'), findsOneWidget);
      expect(find.text('GSB Single 01'), findsWidgets);
      expect(find.text('GSB Single 02'), findsWidgets);
      expect(find.textContaining('5 × 3'), findsWidgets);
      expect(find.textContaining('Shop Fascia'), findsWidgets);
      expect(find.textContaining('Wall Mount'), findsWidgets);
      expect(find.text('Both Boards'), findsOneWidget);
      await _tap(tester, 'pick_cancel');
      expect(find.byType(Drawing2DScreen), findsNothing);
      expect(b.toJson().toString(), before, reason: 'cancel changes nothing');
    });

    testWidgets('individual board opens its own geometry inputs', (
      tester,
    ) async {
      _phone(tester);
      final c = await _vendor();
      final b = await two(c);
      await openEditor(tester, c, b);
      await _tap(tester, 'open_2d');
      await _tap(tester, 'pick_unit_${b.units[1].id}');
      await _tap(tester, 'pick_go');
      final s = tester.widget<Drawing2DScreen>(find.byType(Drawing2DScreen));
      expect(s.unitId, b.units[1].id);
    });

    testWidgets('Both Boards: one viewer with a selector, board by board', (
      tester,
    ) async {
      _phone(tester);
      final c = await _vendor();
      final b = await two(c);
      await openEditor(tester, c, b);
      await _tap(tester, 'open_2d');
      await _tap(tester, 'pick_all');
      await _tap(tester, 'pick_go');
      expect(find.byType(BoardViewerShell), findsOneWidget);
      expect(
        tester.widget<Drawing2DScreen>(find.byType(Drawing2DScreen)).unitId,
        b.units[0].id,
      );
      await _tap(tester, 'viewer_chip_${b.units[1].id}');
      // Only the active board's viewer exists.
      expect(find.byType(Drawing2DScreen), findsOneWidget);
      expect(
        tester.widget<Drawing2DScreen>(find.byType(Drawing2DScreen)).unitId,
        b.units[1].id,
      );
    });

    testWidgets('incomplete board is disabled with its reason; others stay '
        'selectable; Both is off', (tester) async {
      _phone(tester);
      final c = await _vendor();
      final b = await two(c);
      c.setUnitInstallation(_shop, b, b.units[1], null);
      await openEditor(tester, c, b);
      await _tap(tester, 'open_3d');
      expect(find.text('Select Boards for 3D Preview'), findsOneWidget);
      expect(find.textContaining('select the installation type'), findsOneWidget);
      expect(
        tester
            .widget<RadioListTile<String>>(find.byKey(const Key('pick_all')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<RadioListTile<String>>(
              find.byKey(Key('pick_unit_${b.units[0].id}')),
            )
            .enabled,
        isTrue,
      );
      await _tap(tester, 'pick_cancel');
    });

    testWidgets('three boards: dynamic names and All Boards; Camera AR has '
        'no All option', (tester) async {
      _phone(tester);
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 3),
      ]).single
        ..width = 5
        ..height = 3
        ..installationCode = 'wall_mount';
      await openEditor(tester, c, b);
      await _tap(tester, 'open_2d');
      for (final n in ['GSB Single 01', 'GSB Single 02', 'GSB Single 03']) {
        expect(find.text(n), findsWidgets);
      }
      expect(find.text('All Boards'), findsOneWidget);
      await _tap(tester, 'pick_cancel');
      await _tap(tester, 'open_camera_ar');
      expect(find.text('Which board for Camera AR?'), findsOneWidget);
      expect(find.byKey(const Key('pick_all')), findsNothing);
    });
  });

  group('Unified Site Questions', () {
    List<EquivalentPair> pairs(AppController c, String key, String inst) {
      final b = _single(c, key, inst: inst);
      return QuestionEquivalence.pairsFor(b, b.units.first);
    }

    test('every verified rule is active for some media / installation', () async {
      final c = await _vendor();
      final active = <String>{};
      for (final m in SignageCatalog.allMediaTypes) {
        for (final inst in SignageCatalog.installationTypes) {
          final b = Board(
            id: 'x${m.code}${inst.code}',
            name: 'x',
            mediaCode: m.code,
            installationCode: inst.code,
          );
          for (final p in QuestionEquivalence.pairsFor(b, b.units.first)) {
            active.add('${p.site.id}>${p.checklist.id}');
          }
        }
      }
      for (final r in QuestionEquivalence.rules) {
        expect(active, contains('${r.siteId}>${r.checklistId}'),
            reason: 'rule ${r.siteId} is never active');
      }
      expect(c, isNotNull);
    });

    test('answer once: equivalent question counted and stored once', () async {
      final c = await _vendor();
      final b = _single(c, 'NLB_SINGLE_FRAME', inst: 'single_pole');
      final u = b.units.first;
      final mapped = QuestionEquivalence.mappedChecklistIds(b, u);
      expect(mapped, contains('ground_condition'));
      final before = c.siteQuestionsPendingFor(b, u);
      c.setUnitAnswer(_shop, b, u, 'ground_type', 'Concrete');
      // Site question answered => the checklist side is satisfied too.
      expect(c.siteQuestionsPendingFor(b, u), before - 1);
      expect(u.checklist['ground_condition']?.value, 'Concrete');
      expect(
        SiteChecklists.uniqueMissing(b, u).map((q) => q.id),
        isNot(contains('ground_condition')),
      );
      // Never counted twice while unanswered.
      c.setUnitAnswer(_shop, b, u, 'ground_type', null);
      expect(c.siteQuestionsPendingFor(b, u), before);
      expect(u.checklist.containsKey('ground_condition'), isFalse);
    });

    test('similar wording but different meaning stays separate (GSB)', () async {
      final c = await _vendor();
      final b = _single(c, 'GSB_SINGLE', inst: 'wall_mount');
      final u = b.units.first;
      final mapped = QuestionEquivalence.mappedChecklistIds(b, u);
      expect(mapped, isNot(contains('electricity_nearby')));
      expect(mapped, isNot(contains('existing_electrical_point')));
      final siteIds = SignageCatalog.questionsForUnit(b, u).map((q) => q.id);
      expect(siteIds, contains('power_available'));
      expect(
        SiteChecklists.uniqueMissing(b, u).map((q) => q.id),
        containsAll(['electricity_nearby', 'existing_electrical_point']),
      );
    });

    test('No / false answers are valid and reach the checklist', () async {
      final c = await _vendor();
      final b = _single(c, 'NLB_SINGLE_FRAME', inst: 'double_pole');
      final u = b.units.first;
      c.setUnitAnswer(_shop, b, u, 'excavation_permission', false);
      expect(u.checklist['pole_excavation_allowed']?.value, 'no');
      expect(
        SignageCatalog.missingAnswersFor(b, u).map((q) => q.id),
        isNot(contains('excavation_permission')),
      );
    });

    test('legacy checklist-only answers count; conflicts are reported, '
        'never overwritten', () async {
      final c = await _vendor();
      final b = _single(c, 'NLB_SINGLE_FRAME', inst: 'single_pole');
      final u = b.units.first;
      u.checklist['ground_condition'] = ChecklistResponse(
        questionId: 'ground_condition',
        value: 'Soil',
      );
      expect(
        SignageCatalog.missingAnswersFor(b, u).map((q) => q.id),
        isNot(contains('ground_type')),
        reason: 'earlier answer is used',
      );
      expect(QuestionEquivalence.conflicts(b, u), isEmpty);
      // Site answer disagrees with the legacy checklist answer.
      SignageCatalog.answersOf(b, u)['ground_type'] = 'Concrete';
      final cf = QuestionEquivalence.conflicts(b, u);
      expect(cf, hasLength(1));
      expect(u.checklist['ground_condition']!.value, 'Soil',
          reason: 'nothing rewritten silently');
      // An explicit edit makes both agree.
      c.setUnitAnswer(_shop, b, u, 'ground_type', 'Concrete');
      expect(QuestionEquivalence.conflicts(b, u), isEmpty);
    });

    test('equivalence pairs differ per installation', () async {
      final c = await _vendor();
      final wall = pairs(c, 'NLB_SINGLE_FRAME', 'wall_mount')
          .map((p) => p.site.id);
      final pole = pairs(c, 'NLB_SINGLE_FRAME', 'single_pole')
          .map((p) => p.site.id);
      expect(wall, containsAll(['access_method', 'wall_type', 'wall_condition']));
      expect(wall, isNot(contains('ground_type')));
      expect(pole, contains('ground_type'));
      expect(pole, isNot(contains('wall_type')));
    });

    test('copy-all never clones across installations or overwrites', () async {
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('NLB_SINGLE_FRAME'), 2),
      ]).single;
      c.setUnitInstallation(_shop, b, b.units[0], 'double_pole');
      c.setUnitInstallation(_shop, b, b.units[1], 'wall_mount');
      b.units[0].checklist['underground_utilities'] = ChecklistResponse(
        questionId: 'underground_utilities',
        value: 'no',
      );
      b.units[0].checklist['installation_height_measured'] = ChecklistResponse(
        questionId: 'installation_height_measured',
        value: 'yes',
      );
      b.units[1].checklist['installation_height_measured'] = ChecklistResponse(
        questionId: 'installation_height_measured',
        value: 'no',
      );
      c.copyChecklistToOtherUnits(_shop, b, b.units[0].id);
      expect(b.units[1].checklist.containsKey('underground_utilities'), isFalse,
          reason: 'pole question does not apply to a wall board');
      expect(b.units[1].checklist['installation_height_measured']!.value, 'no',
          reason: 'existing answer kept');
    });

    test('common checklist-only answers are copied via Copy Common Answers', () async {
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 2),
      ]).single;
      c.setUnitInstallation(_shop, b, b.units[0], 'shop_fascia');
      c.setUnitInstallation(_shop, b, b.units[1], 'wall_mount');
      b.units[0].checklist['night_visibility'] = ChecklistResponse(
        questionId: 'night_visibility',
        value: 'yes',
      );
      final plan = SignageCatalog.planUnitAnswers(
        b, b.units[0], b, b.units[1],
      );
      expect(plan.toCopyChecklist.map((q) => q.id), contains('night_visibility'));
      expect(
        plan.toCopyChecklist.map((q) => q.id),
        isNot(contains('site_evidence_photo')),
      );
      c.copyCommonAnswers(
        _shop, b, b,
        sourceUnit: b.units[0],
        targetUnit: b.units[1],
      );
      expect(b.units[1].checklist['night_visibility']!.value, 'yes');
    });

    testWidgets('one form: no second checklist, no evidence photo, remarks kept', (
      tester,
    ) async {
      _phone(tester);
      final c = await _vendor();
      final b = _single(c, 'NLB_SINGLE_FRAME', inst: 'single_pole');
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
      expect(find.text('Board Checklist Questions'), findsNothing);
      expect(find.text('GSB site checklist'), findsNothing);
      // Equivalent checklist question is not shown a second time.
      expect(find.byKey(const Key('cl_ground_condition')), findsNothing);
      expect(find.byKey(const Key('q_ground_type_Soil')), findsOneWidget);
      // Evidence photos are collected in Site Photos & Annotation only.
      expect(find.byKey(const Key('cl_site_evidence_photo_photos')), findsNothing);
      // Additional Site Remarks stays.
      expect(find.text('Additional Site Remarks'), findsOneWidget);
      expect(find.byKey(const Key('cl_q_checklist_remarks')), findsOneWidget);
    });
  });

  group('Shop-level requirements for PDFs', () {
    test('optional phone / address / GPS never block a separate PDF', () async {
      final c = await _vendor();
      final s = c.shop(_shop)!;
      s.boards.clear();
      s.phone = '';
      s.address = '';
      s.geo = null;
      final b = _single(c, 'GSB_SINGLE', inst: 'wall_mount');
      completeAnswers(b);
      c.addPhoto(_shop, b.id, _photo());
      expect(groupReportReady(c, s, b), isTrue);
      // The combined report still needs the shop-level mandatory details.
      expect(recceComplete(c, s), isFalse);
      expect(shopLevelBlockers(s), isNotEmpty);
    });
  });

  group('DONE navigation', () {
    Future<(AppController, Board)> pair(WidgetTester tester) async {
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 2),
      ]).single;
      c.setSizeMode(_shop, b, SizeMode.different);
      c.setUnitSize(_shop, b, b.units[0], width: 5, height: 3);
      c.setUnitSize(_shop, b, b.units[1], width: 6, height: 4);
      c.setUnitInstallation(_shop, b, b.units[0], 'shop_fascia');
      c.setUnitInstallation(_shop, b, b.units[1], 'wall_mount');
      c.addPhoto(_shop, b.id, _photo());
      return (c, b);
    }

    Future<void> pump(WidgetTester tester, AppController c, Board b) async {
      await tester.pumpWidget(
        _host(
          c,
          Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('go'),
                  onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BoardEditorScreen(
                        shopId: _shop,
                        boardId: b.id,
                        initialStep: BoardEditorScreen.stepCount - 1,
                      ),
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
    }

    testWidgets('incomplete board: DONE shows pending, does not navigate', (
      tester,
    ) async {
      _phone(tester);
      final (c, b) = await pair(tester);
      await pump(tester, c, b);
      await _tap(tester, 'step_next_6');
      expect(find.byKey(const Key('done_pending_sheet')), findsOneWidget);
      expect(find.textContaining('GSB Single 01 is not complete'), findsOneWidget);
      expect(find.byType(BoardEditorScreen), findsOneWidget);
    });

    testWidgets('board 01 done -> board 02 opens at its first blocker; '
        'final board returns; rapid DONE taps do not double navigate', (
      tester,
    ) async {
      _phone(tester);
      final (c, b) = await pair(tester);
      completeAnswers(b);
      // Board 02 loses its answers; board 01 stays complete.
      b.units[1].siteAnswers.clear();
      b.units[1].checklist.clear();
      await pump(tester, c, b);
      expect(_title(tester), 'GSB Single 01');
      await _tap(tester, 'step_next_6');
      expect(find.byType(BoardEditorScreen), findsOneWidget);
      expect(_title(tester), 'GSB Single 02');
      expect(_step(tester), BoardEditorScreen.siteQuestionsStep);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('unit_questions_header')))
            .data,
        contains('GSB Single 02'),
      );
      // Finish board 02 through the visible form, then DONE twice, quickly.
      await answerThroughUi(tester, c, b, b.units[1]);
      expect(c.boardIssues(b), isEmpty);
      for (var i = 0; i < 3; i++) {
        await _tap(tester, 'step_next_${BoardEditorScreen.siteQuestionsStep + i}');
      }
      final done = find.byKey(const Key('step_next_6'));
      await tester.ensureVisible(done);
      await tester.pumpAndSettle();
      await tester.tap(done);
      await tester.tap(done, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(BoardEditorScreen), findsNothing);
      expect(find.byKey(const Key('go')), findsOneWidget);
    });

    testWidgets('three boards: next incomplete is opened, completed one is '
        'skipped', (tester) async {
      _phone(tester);
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 3),
      ]).single
        ..width = 5
        ..height = 3
        ..installationCode = 'wall_mount';
      c.addPhoto(_shop, b.id, _photo());
      completeAnswers(b);
      b.units[2].siteAnswers.clear();
      b.units[2].checklist.clear();
      await pump(tester, c, b);
      await _tap(tester, 'step_next_6');
      // Board 02 is already complete: board 03 opens.
      expect(_title(tester), 'GSB Single 03');
    });

    testWidgets('failed save keeps the board and shows an error', (
      tester,
    ) async {
      _phone(tester);
      final store = _FailingStore();
      final c = AppController(store: store);
      await c.init();
      c.loginWithPin(DemoAccounts.vendorPin);
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 1),
      ]).single
        ..width = 5
        ..height = 3
        ..installationCode = 'wall_mount';
      c.addPhoto(_shop, b.id, _photo());
      completeAnswers(b);
      await c.flush();
      store.fail = true;
      await pump(tester, c, b);
      await _tap(tester, 'step_next_6');
      expect(find.byType(BoardEditorScreen), findsOneWidget);
      expect(find.textContaining('Could not save'), findsOneWidget);
      store.fail = false;
      await _tap(tester, 'step_next_6');
      expect(find.byType(BoardEditorScreen), findsNothing);
    });
  });

  group('End to end: two boards -> Separate PDF', () {
    testWidgets('different installations, unified questions, evidence, 2D/3D '
        'selection, DONE, Shop Details, Separate PDF', (tester) async {
      _phone(tester);
      final c = await _vendor();
      final s = c.shop(_shop)!;
      s.boards.clear();
      // GSB Single x2 (the group under test) + an unrelated incomplete group.
      final made = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 2),
        MediaGroupPlan(_o('ACRYLIC'), 1),
      ]);
      final b = made[0], acrylic = made[1];
      c.setSizeMode(_shop, b, SizeMode.different);
      c.setUnitSize(_shop, b, b.units[0], width: 5, height: 3);
      c.setUnitSize(_shop, b, b.units[1], width: 6, height: 4);

      await tester.pumpWidget(_host(c, const ShopDetailScreen(shopId: _shop)));
      await tester.pumpAndSettle();
      // Continue goes to the first pending thing: the installation.
      await _tap(tester, 'continue_recce');
      expect(find.byType(BoardEditorScreen), findsOneWidget);
      expect(_step(tester), BoardEditorScreen.installationStep);

      // 1. Different installations through the visible UI.
      await _tap(tester, 'inst_mode_diff');
      await _tap(tester, 'unit_inst_${b.units[0].id}_shop_fascia');
      await _tap(tester, 'unit_inst_${b.units[1].id}_wall_mount');
      expect(b.installationOf(b.units[0]), 'shop_fascia');
      expect(b.installationOf(b.units[1]), 'wall_mount');
      expect(b.installationCode, isNull);

      // 2. Unified questions through the visible form, board by board.
      await _tap(tester, 'step_next_2');
      expect(_step(tester), BoardEditorScreen.siteQuestionsStep);
      final startPending = c.siteQuestionsPending(b);
      expect(startPending, greaterThan(0));
      await answerThroughUi(tester, c, b, b.units[0]);
      expect(c.siteQuestionsPendingFor(b, b.units[0]), 0);
      expect(c.siteQuestionsPending(b), lessThan(startPending));
      await tester.ensureVisible(find.byKey(Key('unit_chip_${b.units[1].id}')));
      await _tap(tester, 'unit_chip_${b.units[1].id}');
      await answerThroughUi(tester, c, b, b.units[1]);
      expect(c.siteQuestionsPending(b), 0);
      expect(find.byKey(const Key('cl_site_evidence_photo_photos')), findsNothing);

      // 3. Qualifying site evidence (supported flow: Site Photos).
      c.addPhoto(_shop, b.id, _photo());
      await tester.pumpAndSettle();
      expect(c.boardIssues(b), isEmpty);

      // 4. Drawings step: buttons enabled, board selection popup.
      for (var i = 0; i < 3; i++) {
        await _tap(tester, 'step_next_${BoardEditorScreen.siteQuestionsStep + i}');
      }
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('open_2d')))
            .onPressed,
        isNotNull,
      );
      await _tap(tester, 'open_3d');
      expect(find.text('Select Boards for 3D Preview'), findsOneWidget);
      await _tap(tester, 'pick_cancel');
      await _tap(tester, 'open_2d');
      await _tap(tester, 'pick_unit_${b.units[0].id}');
      await _tap(tester, 'pick_go');
      expect(
        tester.widget<Drawing2DScreen>(find.byType(Drawing2DScreen)).unitId,
        b.units[0].id,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      // 5. DONE: both boards complete -> back to Shop Details.
      await _tap(tester, 'step_next_6');
      expect(find.byType(BoardEditorScreen), findsNothing);
      expect(find.byType(ShopDetailScreen), findsOneWidget);

      // 6. Separate PDF eligibility; the other group is still incomplete.
      expect(groupReportReady(c, c.shop(_shop)!, b), isTrue);
      expect(groupReportReady(c, c.shop(_shop)!, acrylic), isFalse);
      expect(recceComplete(c, c.shop(_shop)!), isFalse);
      await tester.scrollUntilVisible(
        find.byKey(const Key('recce_pdf_download')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('recce_pdf_download')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('recce_pdf_preview')))
            .onPressed,
        isNotNull,
        reason: 'Preview and Download share one rule',
      );
    });
  });
}

/// Local store whose writes can be made to fail.
class _FailingStore extends MemoryLocalStore {
  bool fail = false;

  @override
  Future<void> write(Map<String, dynamic> json) async {
    if (fail) throw StateError('disk full');
    return super.write(json);
  }
}
