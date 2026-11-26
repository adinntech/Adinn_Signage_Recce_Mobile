import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/features/report/report_data.dart';
import 'package:signage_recce/features/report/report_service.dart';
import 'package:signage_recce/features/shop/add_media_sheet.dart';
import 'package:signage_recce/features/shop/shop_detail_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

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

Widget _host(AppController c, Widget child) =>
    ChangeNotifierProvider<AppController>.value(
      value: c,
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );

void _phone(WidgetTester t, {double h = 900}) {
  t.view.physicalSize = Size(1080, h * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

/// Opens the sheet from a plain button and records the result.
Future<List<AddMediaResult?>> _openSheet(WidgetTester tester) async {
  final results = <AddMediaResult?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('open'),
              onPressed: () async => results.add(await showAddMediaSheet(ctx)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return results;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('Configuration rules', () {
    test('nine distinct media groups from the seven approved media', () {
      final o = SignageCatalog.mediaOptions;
      expect(o.map((e) => e.key).toSet(), hasLength(9));
      expect(
        o.map((e) => e.mediaCode).toSet(),
        SignageCatalog.selectableCodes.toSet(),
      );
    });

    test('allocation validation', () {
      final gsb = _o('GSB_SINGLE'), acr = _o('ACRYLIC'), owv = _o('OWV');
      expect(
        SignageCatalog.validateGroupPlans(1, [MediaGroupPlan(gsb, 1)]),
        isNull,
      );
      expect(
        SignageCatalog.validateGroupPlans(3, [MediaGroupPlan(gsb, 3)]),
        isNull,
      );
      expect(
        SignageCatalog.validateGroupPlans(4, [
          MediaGroupPlan(gsb, 2),
          MediaGroupPlan(acr, 1),
          MediaGroupPlan(owv, 1),
        ]),
        isNull,
      );
      // Sum mismatch, zero board, duplicates, more groups than boards.
      expect(
        SignageCatalog.validateGroupPlans(4, [
          MediaGroupPlan(gsb, 1),
          MediaGroupPlan(acr, 1),
        ]),
        isNotNull,
      );
      expect(
        SignageCatalog.validateGroupPlans(1, [MediaGroupPlan(gsb, 0)]),
        isNotNull,
      );
      expect(
        SignageCatalog.validateGroupPlans(2, [
          MediaGroupPlan(gsb, 1),
          MediaGroupPlan(gsb, 1),
        ]),
        isNotNull,
      );
      expect(
        SignageCatalog.validateGroupPlans(1, [
          MediaGroupPlan(gsb, 1),
          MediaGroupPlan(acr, 1),
        ]),
        isNotNull,
      );
    });

    test('default allocation', () {
      expect(SignageCatalog.defaultAllocation(3, 3), [1, 1, 1]);
      expect(SignageCatalog.defaultAllocation(3, 1), [3]);
      expect(SignageCatalog.defaultAllocation(4, 3), [2, 1, 1]);
    });
  });

  group('addMediaGroups', () {
    test('creates the groups once, existing boards untouched', () async {
      final c = await _vendor();
      final before = [...c.shop(_shop)!.boards];
      final names = before.map((b) => b.name).toList();
      final created = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 2),
        MediaGroupPlan(_o('ACRYLIC'), 1),
        MediaGroupPlan(_o('OWV'), 1),
      ]);
      final s = c.shop(_shop)!;
      expect(s.boards, hasLength(before.length + 3));
      expect(before.map((b) => b.name).toList(), names);
      expect(created.map((b) => b.quantity), [2, 1, 1]);
      expect(created[0].mediaCode, 'GSB');
      expect(created[0].doubleSided, isFalse);
      expect(created[0].name, startsWith('GSB Single'));
      expect(created[1].name, startsWith('Acrylic'));
      expect(created[2].name, startsWith('One-Way Vision'));
      expect(created[0].activeUnits, hasLength(2));
      expect(
        [for (final u in created[0].activeUnits)
          SignageCatalog.unitName(created[0], u)],
        ['GSB Single 01', 'GSB Single 02'],
      );
      final ids = {for (final b in created) b.id};
      expect(ids, hasLength(3));
    });

    test('NLB box frame keeps its subtype', () async {
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('NLB_BOX_FRAME'), 1),
      ]).single;
      expect(b.isNlbBoxFrame, isTrue);
      expect(b.doubleSided, isTrue);
      expect(b.name, 'NLB Box 01');
    });

    test('invalid plan creates nothing', () async {
      final c = await _vendor();
      final n = c.shop(_shop)!.boards.length;
      expect(
        () => c.addMediaGroups(_shop, [
          MediaGroupPlan(_o('GSB_SINGLE'), 1),
          MediaGroupPlan(_o('GSB_SINGLE'), 1),
        ]),
        throwsArgumentError,
      );
      expect(c.shop(_shop)!.boards, hasLength(n));
    });
  });

  group('Add Media Type: direct selection', () {
    testWidgets('opens media selection, no quantity / media-count popup', (
      tester,
    ) async {
      _phone(tester, h: 1400);
      await _openSheet(tester);
      expect(find.text('Select the media type'), findsOneWidget);
      expect(find.text('How many boards are required?'), findsNothing);
      expect(find.byKey(const Key('sheet_qty_plus')), findsNothing);
      for (final o in SignageCatalog.mediaOptions) {
        expect(find.byKey(Key('opt_${o.key}')), findsOneWidget, reason: o.key);
      }
      // Continue needs a selection.
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('sheet_next'))).onPressed,
        isNull,
      );
    });

    testWidgets('cancel returns nothing', (tester) async {
      _phone(tester, h: 1400);
      final r = await _openSheet(tester);
      await _tap(tester, 'opt_ACRYLIC');
      await _tap(tester, 'sheet_cancel');
      expect(r, [null]);
    });

    testWidgets('several media: one board per subtype', (tester) async {
      _phone(tester, h: 1400);
      final r = await _openSheet(tester);
      await _tap(tester, 'opt_GSB_SINGLE');
      await _tap(tester, 'opt_GSB_DOUBLE');
      await _tap(tester, 'opt_OWV');
      await _tap(tester, 'sheet_next');
      final res = r.single!;
      expect(res.selectInEditor, isFalse);
      expect(res.plans.map((p) => p.option.key), [
        'GSB_SINGLE',
        'GSB_DOUBLE',
        'OWV',
      ]);
      expect(res.plans.every((p) => p.quantity == 1), isTrue);
    });

    testWidgets('"Select in editor" skips selection (single board)', (
      tester,
    ) async {
      _phone(tester, h: 1400);
      final r = await _openSheet(tester);
      await _tap(tester, 'sheet_in_editor');
      expect(r.single!.selectInEditor, isTrue);
      expect(r.single!.plans, isEmpty);
    });

    testWidgets('a subtype already in the shop is not offered again', (
      tester,
    ) async {
      _phone(tester, h: 1400);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (ctx) => TextButton(
              key: const Key('open'),
              onPressed: () =>
                  showAddMediaSheet(ctx, existing: const {'ACRYLIC'}),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(find.textContaining('already added'), findsOneWidget);
      await tester.tap(find.byKey(const Key('opt_ACRYLIC')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('sheet_next'))).onPressed,
        isNull,
        reason: 'not selectable',
      );
    });

    test('existing subtype detection', () async {
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [MediaGroupPlan(_o('GSB_DOUBLE'), 1)])
          .single;
      final keys = existingMediaKeys(c.shop(_shop)!);
      expect(keys, contains('GSB_DOUBLE'));
      expect(keys, isNot(contains('GSB_SINGLE')));
      expect(b.mediaCode, 'GSB');
    });

    testWidgets('Shop Details button opens selection; cancel creates nothing', (
      tester,
    ) async {
      _phone(tester, h: 1600);
      final c = await _vendor();
      final n = c.shop(_shop)!.boards.length;
      await tester.pumpWidget(_host(c, const ShopDetailScreen(shopId: _shop)));
      await tester.pumpAndSettle();
      await _tap(tester, 'add_board');
      expect(find.text('Select the media type'), findsOneWidget);
      expect(find.text('How many boards are required?'), findsNothing);
      await _tap(tester, 'sheet_cancel');
      expect(c.shop(_shop)!.boards, hasLength(n));
      expect(find.byType(BoardEditorScreen), findsNothing);
    });

    testWidgets('Shop Details: choose media, board opens; same-media '
        'quantity stays in Number of Boards', (tester) async {
      _phone(tester, h: 1600);
      final c = await _vendor();
      await tester.pumpWidget(_host(c, const ShopDetailScreen(shopId: _shop)));
      await tester.pumpAndSettle();
      final n = c.shop(_shop)!.boards.length;
      await _tap(tester, 'add_board');
      await _tap(tester, 'opt_NLB_BOX_FRAME');
      await _tap(tester, 'opt_FOAM_VINYL');
      await _tap(tester, 'sheet_next');
      expect(find.byType(BoardEditorScreen), findsOneWidget);
      final boards = c.shop(_shop)!.boards;
      expect(boards, hasLength(n + 2));
      final box = boards[n];
      expect(box.isNlbBoxFrame, isTrue);
      expect(box.quantity, 1);
      c.increaseQuantity(_shop, box, 2);
      expect(box.activeUnits, hasLength(2));
    });

    testWidgets('+ beside the media tabs adds media and opens it', (
      tester,
    ) async {
      _phone(tester, h: 1400);
      final c = await _vendor();
      final s = c.shop(_shop)!..boards.clear();
      final first = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 1),
        MediaGroupPlan(_o('ACRYLIC'), 1),
      ]);
      await c.saveDraft(_shop, first[0]);
      await tester.pumpWidget(
        _host(c, BoardEditorScreen(shopId: _shop, boardId: first[0].id)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('media_tab_add')), findsOneWidget);
      await _tap(tester, 'media_tab_add');
      expect(find.text('Select the media type'), findsOneWidget);
      expect(find.textContaining('already added'), findsNWidgets(2));
      await _tap(tester, 'opt_GSB_DOUBLE');
      // Rapid second tap on Continue must not create twice.
      final next = find.byKey(const Key('sheet_next'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.tap(next, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(s.boards, hasLength(3));
      expect(first.map((b) => b.id), everyElement(isIn(s.boards.map((b) => b.id))));
      // The new media is open and the tabs include it.
      expect(find.textContaining('GSB Double'), findsWidgets);
    });

    testWidgets('+ asks to save an unsaved incomplete board as draft first', (
      tester,
    ) async {
      _phone(tester, h: 1400);
      final c = await _vendor();
      c.shop(_shop)!.boards.clear();
      final first = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 1),
        MediaGroupPlan(_o('ACRYLIC'), 1),
      ]);
      await tester.pumpWidget(
        _host(c, BoardEditorScreen(shopId: _shop, boardId: first[0].id)),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'media_tab_add');
      expect(find.text('Save as Draft?'), findsOneWidget);
      await _tap(tester, 'draft_stay');
      expect(find.text('Select the media type'), findsNothing);
      expect(c.shop(_shop)!.boards, hasLength(2));
    });
  });

  group('Draft and media tabs', () {
    test('draft prompt only when incomplete and changed', () async {
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('ACRYLIC'), 1),
      ]).single;
      expect(c.needsDraftPrompt(b), isTrue);
      expect(await c.saveDraft(_shop, b), isTrue);
      expect(c.isDraftSaved(b), isTrue);
      expect(c.needsDraftPrompt(b), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      b.width = 4;
      c.touchBoard(_shop, b);
      expect(c.needsDraftPrompt(b), isTrue);
      expect(c.boardIssues(b), isNotEmpty, reason: 'draft is not completion');
    });

    testWidgets('switching tab: Stay Here keeps the board, Save & Continue '
        'switches', (tester) async {
      _phone(tester, h: 1200);
      final c = await _vendor();
      final groups = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 2),
        MediaGroupPlan(_o('ACRYLIC'), 1),
      ]);
      final gsb = groups[0], acr = groups[1];
      await tester.pumpWidget(
        _host(c, BoardEditorScreen(shopId: _shop, boardId: gsb.id)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('media_tabs')), findsOneWidget);

      await _tap(tester, 'media_tab_${acr.id}');
      expect(find.text('Save as Draft?'), findsOneWidget);
      await _tap(tester, 'draft_stay');
      expect(find.text(gsb.name), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(gsb.name),
        ),
        findsOneWidget,
      );

      await _tap(tester, 'media_tab_${acr.id}');
      await _tap(tester, 'draft_save');
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(acr.name),
        ),
        findsOneWidget,
      );
      expect(c.isDraftSaved(gsb), isTrue);
      expect(c.boardIssues(gsb), isNotEmpty);
    });

    testWidgets('saved, unchanged draft switches without asking', (
      tester,
    ) async {
      _phone(tester, h: 1200);
      final c = await _vendor();
      final groups = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 1),
        MediaGroupPlan(_o('ACRYLIC'), 1),
      ]);
      await c.saveDraft(_shop, groups[0]);
      await tester.pumpWidget(
        _host(c, BoardEditorScreen(shopId: _shop, boardId: groups[0].id)),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'media_tab_${groups[1].id}');
      expect(find.text('Save as Draft?'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(groups[1].name),
        ),
        findsOneWidget,
      );
    });

    test('step is remembered per board', () async {
      final c = await _vendor();
      c.editorStep['x'] = 3;
      expect(c.editorStep['x'], 3);
    });
  });

  group('Common answers auto-fill', () {
    test('single compatible source is picked', () async {
      final c = await _vendor();
      final g = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 1),
        MediaGroupPlan(_o('ACRYLIC'), 1),
      ]);
      g[0]
        ..installationCode = 'double_pole'
        ..answers['owner_permission'] = true;
      g[1].installationCode = 'wall_mount';
      final r = SignageCatalog.autoFillSource(g[1], c.shop(_shop)!.boards);
      expect(r.source?.id, g[0].id);
      expect(r.conflicting, isEmpty);
    });

    test('conflicting sources are never auto-picked', () async {
      final c = await _vendor();
      final g = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 1),
        MediaGroupPlan(_o('OWV'), 1),
        MediaGroupPlan(_o('ACRYLIC'), 1),
      ]);
      g[0]
        ..installationCode = 'double_pole'
        ..answers['owner_permission'] = true;
      g[1]
        ..installationCode = 'glass_pasting'
        ..answers['owner_permission'] = false;
      g[2].installationCode = 'wall_mount';
      final r = SignageCatalog.autoFillSource(g[2], c.shop(_shop)!.boards);
      expect(r.source, isNull);
      expect(r.conflicting.map((b) => b.id), containsAll([g[0].id, g[1].id]));
    });

    test('target with its own common answers is left alone', () async {
      final c = await _vendor();
      final g = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 1),
        MediaGroupPlan(_o('ACRYLIC'), 1),
      ]);
      g[0]
        ..installationCode = 'double_pole'
        ..answers['owner_permission'] = true;
      g[1]
        ..installationCode = 'wall_mount'
        ..answers['owner_permission'] = false;
      final r = SignageCatalog.autoFillSource(g[1], c.shop(_shop)!.boards);
      expect(r.source, isNull);
    });

    test('questions are grouped into three sections', () async {
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 1),
      ]).single..installationCode = 'double_pole';
      final sections = {
        for (final q in SignageCatalog.questionsFor(b.mediaCode, 'double_pole'))
          SignageCatalog.questionSection(b, q),
      };
      expect(sections, contains('Common Site Questions'));
      expect(sections, contains('Installation-Specific Questions'));
    });
  });

  group('Recce PDF', () {
    Future<(AppController, ReportService, FakeModels)> setup() async {
      final c = await _vendor();
      final models = FakeModels();
      final files = <String, Uint8List>{};
      final service = ReportService(
        images: FakeImages(),
        models: models,
        writer: (bytes) async {
          files['/r.pdf'] = bytes;
          return '/r.pdf';
        },
        reader: (p) async => files[p],
        useIsolate: false,
        compress: false,
      );
      return (c, service, models);
    }

    test('incomplete shop: export refused with the exact message', () async {
      final (c, service, _) = await setup();
      c.addMediaGroups(_shop, [MediaGroupPlan(_o('ACRYLIC'), 1)]);
      expect(recceComplete(c, c.shop(_shop)!), isFalse);
      await expectLater(
        service.generate(c, _shop, requireComplete: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            kRecceIncompleteMessage,
          ),
        ),
      );
    });

    test('separate report contains only the chosen media group', () async {
      final (c, _, _) = await setup();
      final g = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 2),
        MediaGroupPlan(_o('ACRYLIC'), 1),
      ]);
      final build = buildReportData(
        c,
        c.shop(_shop)!,
        now: DateTime(2026, 11, 24),
        groupIds: {g[0].id},
      );
      final groups = build.data['groups'] as List;
      expect(groups, hasLength(1));
      final gm = groups.single as Map;
      expect(gm['groupId'], g[0].id);
      expect(gm['items'] as List, hasLength(2), reason: 'both boards');
      final all = buildReportData(
        c,
        c.shop(_shop)!,
        now: DateTime(2026, 11, 24),
      );
      expect(
        (all.data['groups'] as List).length,
        c.shop(_shop)!.boards.length,
      );
    });

    test('every board gets front + opposite-side 3D views', () async {
      final (c, service, models) = await setup();
      final g = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_DOUBLE'), 2),
      ]).single;
      g
        ..installationCode = 'double_pole'
        ..width = 8
        ..height = 3;
      await service.generate(c, _shop, groupIds: {g.id});
      expect(models.calls.where((e) => e.startsWith('3d:')), hasLength(2));
      expect(
        models.calls.where((e) => e.startsWith('3d-rear:')),
        hasLength(2),
      );
      final build = buildReportData(
        c,
        c.shop(_shop)!,
        now: DateTime(2026, 11, 24),
        groupIds: {g.id},
      );
      for (final it in ((build.data['groups'] as List).single as Map)['items']
          as List) {
        final sheet = (it as Map)['sheet'] as Map;
        expect(sheet.keys, containsAll(['front', 'side', 'model', 'model_rear']));
      }
    });
  });
}
