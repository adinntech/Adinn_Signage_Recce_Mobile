import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

const _shop = 's_lakshmi';

Future<AppController> _vendor() async {
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin(DemoAccounts.vendorPin);
  return c;
}

Board _group(
  AppController c,
  String media, {
  bool? dbl,
  String? nlb,
  int qty = 1,
}) {
  final b = c.addBoard(_shop)
    ..mediaCode = media
    ..doubleSided = dbl
    ..nlbSubtype = nlb
    ..width = 6
    ..height = 3;
  if (qty > 1) c.increaseQuantity(_shop, b, qty);
  return b;
}

void main() {
  group('Media-based board names', () {
    test('labels per media / subtype', () async {
      final c = await _vendor();
      expect(
        SignageCatalog.mediaNameLabel(_group(c, 'GSB', dbl: false)),
        'GSB Single',
      );
      expect(
        SignageCatalog.mediaNameLabel(_group(c, 'GSB', dbl: true)),
        'GSB Double',
      );
      expect(
        SignageCatalog.mediaNameLabel(
          _group(c, 'NLB', nlb: 'NLB_SINGLE_FRAME'),
        ),
        'NLB Single',
      );
      expect(
        SignageCatalog.mediaNameLabel(_group(c, 'NLB', nlb: 'NLB_BOX_FRAME')),
        'NLB Box',
      );
      expect(SignageCatalog.mediaNameLabel(_group(c, 'ACRYLIC')), 'Acrylic');
      expect(
        SignageCatalog.mediaNameLabel(_group(c, 'OWV')),
        'One-Way Vision',
      );
      expect(SignageCatalog.mediaNameLabel(_group(c, 'MDF')), 'MDF');
    });

    test('unit names run 01..03 per group, ids stay unique', () async {
      final c = await _vendor();
      final g = _group(c, 'GSB', dbl: false, qty: 3);
      final a = _group(c, 'ACRYLIC', qty: 2);
      expect(
        [for (final u in g.activeUnits) SignageCatalog.unitName(g, u)],
        ['GSB Single 01', 'GSB Single 02', 'GSB Single 03'],
      );
      expect(
        [for (final u in a.activeUnits) SignageCatalog.unitName(a, u)],
        ['Acrylic 01', 'Acrylic 02'],
      );
      final ids = [...g.units, ...a.units].map((u) => u.id).toSet();
      expect(ids, hasLength(5));
    });

    test('auto name replaces generic names only; manual names survive', () async {
      final c = await _vendor();
      final b = _group(c, 'ACRYLIC');
      expect(SignageCatalog.isAutoBoardName(b.name), isTrue);
      c.autoNameBoard(_shop, b);
      expect(b.name, 'Acrylic 01');

      b.name = 'Front fascia board';
      b.mediaCode = 'OWV';
      c.autoNameBoard(_shop, b);
      expect(b.name, 'Front fascia board');
    });

    test('no duplicate default names inside a shop', () async {
      final c = await _vendor();
      final a = _group(c, 'ACRYLIC');
      c.autoNameBoard(_shop, a);
      final b = _group(c, 'ACRYLIC');
      c.autoNameBoard(_shop, b);
      expect(a.name, 'Acrylic 01');
      expect(b.name, 'Acrylic 02');
      expect(a.id, isNot(b.id));
    });

    test('switching GSB single -> double renames an auto name only', () async {
      final c = await _vendor();
      final b = _group(c, 'GSB', dbl: false);
      c.autoNameBoard(_shop, b);
      expect(b.name, 'GSB Single 01');
      c.setDoubleSided(_shop, b, true);
      expect(b.name, 'GSB Double 01');
    });
  });

  group('Individual installation per board', () {
    test('each unit keeps its own installation; group is untouched', () async {
      final c = await _vendor();
      final b = _group(c, 'GSB', dbl: false, qty: 2);
      final u1 = b.activeUnits[0];
      final u2 = b.activeUnits[1];
      expect(c.setUnitInstallation(_shop, b, u1, SignageCatalog.wallMount), isTrue);
      expect(c.setUnitInstallation(_shop, b, u2, SignageCatalog.doublePole), isTrue);
      expect(b.installationCode, isNull);
      expect(b.installationOf(u1), SignageCatalog.wallMount);
      expect(b.installationOf(u2), SignageCatalog.doublePole);
      expect(SignageCatalog.hasMixedInstallations(b), isTrue);
      expect(SignageCatalog.installationComplete(b), isTrue);
      expect(SignageCatalog.installationSummary(b), startsWith('Mixed'));

      // Changing board 2 does not change board 1.
      c.setUnitInstallation(_shop, b, u2, SignageCatalog.rooftop);
      expect(b.installationOf(u1), SignageCatalog.wallMount);
    });

    test('invalid code for the media is rejected', () async {
      final c = await _vendor();
      final b = _group(c, 'ACRYLIC', qty: 2);
      expect(
        c.setUnitInstallation(_shop, b, b.activeUnits.first, 'double_pole'),
        isFalse,
      );
      expect(b.activeUnits.first.installationCode, isNull);
    });

    test('survives a save / reopen (JSON round trip)', () async {
      final c = await _vendor();
      final b = _group(c, 'GSB', dbl: false, qty: 2);
      c.setUnitInstallation(_shop, b, b.activeUnits[0], 'wall_mount');
      c.setUnitInstallation(_shop, b, b.activeUnits[1], 'double_pole');
      final copy = Board.fromJson(
        jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>,
      );
      expect(copy.installationOf(copy.activeUnits[0]), 'wall_mount');
      expect(copy.installationOf(copy.activeUnits[1]), 'double_pole');
      expect(copy.installationCode, isNull);
    });

    test('board issues name only the unit still missing an installation', () async {
      final c = await _vendor();
      final b = _group(c, 'GSB', dbl: false, qty: 2);
      c.setUnitInstallation(_shop, b, b.activeUnits[0], 'wall_mount');
      final issue = c
          .boardIssues(b)
          .firstWhere((i) => i.startsWith('Select an installation type'));
      expect(issue, contains('GSB Single 02'));
      expect(issue, isNot(contains('GSB Single 01')));
      c.setUnitInstallation(_shop, b, b.activeUnits[1], 'rooftop');
      expect(
        c.boardIssues(b).where((i) => i.contains('installation type')),
        isEmpty,
      );
    });

    test('Same Installation clears overrides explicitly', () async {
      final c = await _vendor();
      final b = _group(c, 'GSB', dbl: false, qty: 2);
      c.setUnitInstallation(_shop, b, b.activeUnits[0], 'wall_mount');
      expect(c.setSameInstallation(_shop, b, 'double_pole'), isTrue);
      expect(b.installationCode, 'double_pole');
      expect(b.activeUnits.every((u) => u.installationCode == null), isTrue);
      expect(SignageCatalog.hasMixedInstallations(b), isFalse);
    });

    test('same size does not imply same installation', () async {
      final c = await _vendor();
      final b = _group(c, 'GSB', dbl: false, qty: 2);
      expect(b.isSameSize, isTrue);
      c.setUnitInstallation(_shop, b, b.activeUnits[0], 'wall_mount');
      c.setUnitInstallation(_shop, b, b.activeUnits[1], 'rooftop');
      expect(SignageCatalog.hasMixedInstallations(b), isTrue);
    });
  });

  group('Copy common Site Question answers', () {
    Future<(AppController, Board, Board)> setup() async {
      final c = await _vendor();
      final src = _group(c, 'GSB', dbl: false)
        ..installationCode = SignageCatalog.doublePole;
      final dst = _group(c, 'ACRYLIC')
        ..installationCode = SignageCatalog.wallMount;
      return (c, src, dst);
    }

    test('only definitions that match are copied', () async {
      final (_, src, dst) = await setup();
      src.answers['access_method'] = 'Ladder';
      src.answers['owner_permission'] = true;
      src.answers['gsb_only_thing'] = 'x'; // not a real question
      final plan = SignageCatalog.planCommonAnswers(src, dst);
      final ids = plan.toCopy.map((q) => q.id).toSet();
      expect(ids, containsAll(['access_method', 'owner_permission']));
      expect(ids, isNot(contains('gsb_only_thing')));
    });

    test('same id with a different definition is not matched', () {
      const a = SiteQuestion(
        id: 'q',
        label: 'Same words',
        type: QuestionType.choice,
        options: ['A', 'B'],
      );
      const b = SiteQuestion(
        id: 'q',
        label: 'Same words',
        type: QuestionType.choice,
        options: ['A', 'C'],
      );
      const t = SiteQuestion(id: 'q', label: 'Same words', type: QuestionType.number);
      expect(SignageCatalog.sameQuestionDefinition(a, a), isTrue);
      expect(SignageCatalog.sameQuestionDefinition(a, b), isFalse);
      expect(SignageCatalog.sameQuestionDefinition(a, t), isFalse);
    });

    test('fills empty answers, keeps manual ones unless overwrite', () async {
      final (c, src, dst) = await setup();
      src.answers['access_method'] = 'Ladder';
      src.answers['owner_permission'] = true;
      dst.answers['access_method'] = 'Crane / Hydra';
      final n = c.copyCommonAnswers(_shop, src, dst);
      expect(n, greaterThan(0));
      expect(dst.answers['access_method'], 'Crane / Hydra');
      expect(dst.answers['owner_permission'], true);

      final m = c.copyCommonAnswers(_shop, src, dst, overwrite: true);
      expect(m, greaterThan(0));
      expect(dst.answers['access_method'], 'Ladder');
    });

    test('copied answers are independent values', () async {
      final (c, src, dst) = await setup();
      src.answers['owner_permission'] = true;
      c.copyCommonAnswers(_shop, src, dst);
      dst.answers['owner_permission'] = false;
      expect(src.answers['owner_permission'], true);
      src.answers['owner_permission'] = null;
      expect(dst.answers['owner_permission'], false);
    });

    test('copying never completes Site Questions by itself', () async {
      final (c, src, dst) = await setup();
      src.answers['owner_permission'] = true;
      c.copyCommonAnswers(_shop, src, dst);
      expect(SignageCatalog.missingAnswers(dst), isNotEmpty);
    });

    test('provenance stays out of the answers map', () async {
      final (c, src, dst) = await setup();
      src.answers['owner_permission'] = true;
      c.copyCommonAnswers(_shop, src, dst);
      final ids = SignageCatalog.questionsFor(
        dst.mediaCode,
        dst.installationCode,
      ).map((q) => q.id).toSet();
      expect(dst.answers.keys.every(ids.contains), isTrue);
    });

    test('source deleted after copying leaves the target intact', () async {
      final (c, src, dst) = await setup();
      src.answers['owner_permission'] = true;
      c.copyCommonAnswers(_shop, src, dst);
      await c.deleteBoard(_shop, src.id);
      expect(dst.answers['owner_permission'], true);
    });
  });

  group('Editor: Same / Different Installations', () {
    testWidgets('different installations persist per board', (tester) async {
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final c = await _vendor();
      final b = _group(c, 'GSB', dbl: false, qty: 2);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: c,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: BoardEditorScreen(
              shopId: _shop,
              boardId: b.id,
              initialStep: 2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inst_mode_selector')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('inst_mode_diff')));
      await tester.tap(find.byKey(const Key('inst_mode_diff')));
      await tester.pumpAndSettle();

      final u1 = b.activeUnits[0].id;
      final u2 = b.activeUnits[1].id;
      final wall = find.byKey(Key('unit_inst_${u1}_wall_mount'));
      await tester.ensureVisible(wall);
      await tester.tap(wall);
      await tester.pumpAndSettle();
      final pole = find.byKey(Key('unit_inst_${u2}_double_pole'));
      await tester.ensureVisible(pole);
      await tester.tap(pole);
      await tester.pumpAndSettle();

      expect(b.installationOf(b.activeUnits[0]), 'wall_mount');
      expect(b.installationOf(b.activeUnits[1]), 'double_pole');
      expect(b.installationCode, isNull);
    });

    testWidgets('single board shows no mode switch', (tester) async {
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final c = await _vendor();
      final b = _group(c, 'GSB', dbl: false);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: c,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: BoardEditorScreen(
              shopId: _shop,
              boardId: b.id,
              initialStep: 2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inst_mode_selector')), findsNothing);
    });
  });
}
