import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/core/utils/gst.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/catalog/site_checklists.dart';
import 'package:signage_recce/data/catalog/vendor_question_policy.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/models/photo_requirement.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/report/report_data.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

import 'helpers.dart';
import 'support/evidence_fixture.dart';

const _shop = 's_lakshmi';

Future<AppController> _vendor() async {
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin(DemoAccounts.vendorPin);
  return c;
}

MediaOption _o(String key) =>
    SignageCatalog.mediaOptions.firstWhere((o) => o.key == key);

SitePhoto _ph(
  String id,
  String path, {
  List<Annotation>? marks,
  List<String>? units,
}) => SitePhoto(
  id: id,
  path: path,
  label: 'Front view',
  capturedAt: DateTime(2026, 11, 26),
  width: 100,
  height: 80,
  annotations: marks,
  unitIds: units,
);

Annotation _rect(String id, String? itemId, {double w = 40, double h = 20}) =>
    Annotation(
      id: id,
      type: AnnotationType.rectangle,
      itemId: itemId,
      x: 50,
      y: 40,
      w: w,
      h: h,
    );

void main() {
  group('Photo requirement: two photos + one board-linked signage marking', () {
    Board board({int qty = 1}) =>
        Board(id: 'b', name: 'b', mediaCode: SignageCatalog.gsb, quantity: qty);

    PhotoRequirement req(Board b, [int unit = 0]) =>
        b.photoRequirementOf(b.units[unit]);

    test('zero / one / two photos matrix', () {
      final b = board();
      final u = b.units.first.id;
      expect(req(b).isComplete, isFalse);
      expect(req(b).messages, hasLength(2));

      b.photos.add(_ph('p1', 'a.jpg'));
      expect(req(b).isComplete, isFalse, reason: 'one unmarked');

      b.photos.first.annotations.add(_rect('m', u));
      expect(req(b).isComplete, isFalse, reason: 'one photo, one marking');
      expect(req(b).needsPhotos, isTrue);
      expect(req(b).needsMarking, isFalse);

      b.photos.first.annotations.clear();
      b.photos.add(_ph('p2', 'b.jpg'));
      expect(req(b).isComplete, isFalse, reason: 'two photos, no marking');
      expect(req(b).messages, ['Signage marking is missing']);

      b.photos.last.annotations.add(_rect('m2', u));
      expect(req(b).isComplete, isTrue, reason: 'marking on any valid photo');

      b.photos.add(_ph('p3', 'c.jpg'));
      expect(req(b).isComplete, isTrue, reason: 'three photos');
    });

    test(
      'generic annotations, unlinked and zero-size rectangles never count',
      () {
        final b = board(qty: 2);
        final u = b.units.first.id;
        b.photos
          ..add(
            _ph(
              'p1',
              'a.jpg',
              units: [u],
              marks: [
                Annotation(id: 'a1', type: AnnotationType.arrow, itemId: u),
                Annotation(id: 'a2', type: AnnotationType.text, itemId: u),
                _rect('r1', null), // not linked to any board of a 2-board group
                _rect('r2', u, w: 0, h: 0), // no area
              ],
            ),
          )
          ..add(_ph('p2', 'b.jpg', units: [u]));
        expect(req(b).markingCount, 0);
        expect(req(b).isComplete, isFalse);
      },
    );

    test('a single-board group accepts its own unlinked Signage rectangle', () {
      final b = board();
      b.photos
        ..add(_ph('p1', 'a.jpg', marks: [_rect('r1', null)]))
        ..add(_ph('p2', 'b.jpg'));
      expect(req(b).isComplete, isTrue);
    });

    test('a marking of another board never satisfies this board', () {
      final b = board(qty: 2);
      final u1 = b.units[0].id, u2 = b.units[1].id;
      b.photos
        ..add(_ph('p1', 'a.jpg', units: [u1, u2], marks: [_rect('m', u2)]))
        ..add(_ph('p2', 'b.jpg', units: [u1, u2]));
      expect(req(b, 1).isComplete, isTrue);
      expect(req(b, 0).isComplete, isFalse);
      expect(req(b, 0).needsMarking, isTrue);
    });

    test('two group photos are shared; markings stay board-specific', () {
      final b = board(qty: 2);
      b.photos
        ..add(_ph('p1', 'a.jpg', marks: [_rect('m', b.units[0].id)]))
        ..add(_ph('p2', 'b.jpg'));
      // Shared group photos count for both boards (no per-photo link needed).
      expect(b.photoRequirement.photoCount, 2);
      expect(req(b, 0).photoCount, 2);
      expect(req(b, 1).photoCount, 2);
      expect(req(b, 0).isComplete, isTrue);
      expect(req(b, 1).isComplete, isFalse);
    });

    test(
      'duplicate references to one file count once and keep the marking',
      () {
        final b = board();
        final u = b.units.first.id;
        b.photos
          ..add(_ph('p1', 'same.jpg'))
          ..add(_ph('p2', 'same.jpg', marks: [_rect('m', u)]));
        final r = req(b);
        expect(r.photoCount, 1);
        expect(
          r.markingCount,
          1,
          reason: 'the marked duplicate is the one kept',
        );
        expect(r.isComplete, isFalse);
      },
    );

    test('deleting a required photo or the last marking recalculates', () {
      final b = board();
      final u = b.units.first.id;
      b.photos
        ..add(_ph('p1', 'a.jpg', marks: [_rect('m', u)]))
        ..add(_ph('p2', 'b.jpg'));
      expect(req(b).isComplete, isTrue);
      b.photos.last.path = ''; // missing file never counts
      expect(req(b).isComplete, isFalse);
      b.photos.last.path = 'b.jpg';
      b.photos.first.annotations.clear();
      expect(req(b).isComplete, isFalse);
      expect(req(b).needsMarking, isTrue);
    });

    test('perspective placement needs valid geometry on its own photo', () {
      final b = board();
      final u = b.units.first.id;
      final p1 = _ph('p1', 'a.jpg'), p2 = _ph('p2', 'b.jpg');
      b.photos.addAll([p1, p2]);
      p1.markup.perspectives.add(
        PerspectivePlacement(
          id: 'x',
          photoId: 'other',
          unitId: u,
          corners: PerspectivePlacement.defaultCorners(),
        ),
      );
      expect(req(b).markingCount, 0, reason: 'belongs to another photo');
      p1.markup.perspectives.clear();
      p1.markup.perspectives.add(
        PerspectivePlacement(
          id: 'y',
          photoId: 'p1',
          unitId: u,
          corners: const [
            SurveyPoint(0.2, 0.2),
            SurveyPoint(0.2, 0.2),
            SurveyPoint(0.2, 0.2),
            SurveyPoint(0.2, 0.2),
          ],
        ),
      );
      expect(req(b).markingCount, 0, reason: 'degenerate quad');
      p1.markup.perspectives.clear();
      p1.markup.perspectives.add(
        PerspectivePlacement(
          id: 'z',
          photoId: 'p1',
          unitId: u,
          corners: PerspectivePlacement.defaultCorners(),
        ),
      );
      expect(req(b).isComplete, isTrue);
    });

    test(
      'same rule feeds the board issues, readiness gate and PDF gate',
      () async {
        final c = await _vendor();
        final b =
            c.addMediaGroups(_shop, [
                MediaGroupPlan(_o('GSB_SINGLE'), 1),
              ]).single
              ..width = 5
              ..height = 3
              ..installationCode = 'wall_mount';
        completeAnswers(b);
        expect(c.boardIssues(b), contains('Capture at least two site photos'));
        b.photos.add(validEvidence(b).first);
        expect(c.boardIssues(b), contains('1 more valid site photo required'));
        b.photos
          ..clear()
          ..addAll(validEvidence(b));
        expect(c.boardIssues(b), isEmpty);
        // Remove the signage marking: the requirement comes back at once.
        b.photos.first.annotations.clear();
        expect(
          c.boardIssues(b).any((i) => i.contains('signage marking is missing')),
          isTrue,
        );
      },
    );
  });

  group('Active vendor question policy', () {
    List<String> siteIds(Board b) => [
      for (final q in SignageCatalog.questionsForUnit(b, b.units.first)) q.id,
    ];
    List<String> clIds(Board b) => [
      for (final q in SiteChecklists.questionsFor(
        b.mediaCode,
        b.installationCode,
      ))
        q.id,
    ];

    Board make(MediaOption o, String? inst) => Board(
      id: 'x_${o.key}_$inst',
      name: 'x',
      mediaCode: o.mediaCode,
      doubleSided: o.doubleSided,
      nlbSubtype: o.nlbSubtype,
      installationCode: inst,
    );

    test(
      'every combination keeps the common + retained questions, no duplicates',
      () {
        for (final o in SignageCatalog.mediaOptions) {
          final probe = make(o, null);
          final codes = [
            for (final ch in SignageCatalog.choicesForBoard(probe))
              if (ch.code != null) ch.code,
            if (SignageCatalog.choicesForBoard(probe).isEmpty) null,
          ];
          for (final inst in codes) {
            final b = make(o, inst);
            final site = siteIds(b);
            expect(
              site,
              containsAll(['existing_board', 'remove_existing']),
              reason: '${o.key}/$inst',
            );
            expect(site.toSet(), hasLength(site.length), reason: 'dup site');
            final cl = clIds(b);
            expect(cl.toSet(), hasLength(cl.length), reason: 'dup checklist');
            // Only policy-approved ids reach the vendor.
            for (final id in site) {
              expect(VendorQuestionPolicy.siteActive(b.mediaCode, id), isTrue);
            }
            // No question twice across the two lists.
            expect(
              site.toSet().intersection(cl.toSet()),
              isEmpty,
              reason: '${o.key}/$inst',
            );
            if (SiteChecklists.definitionFor(o.mediaCode) != null) {
              expect(
                cl,
                contains('checklist_remarks'),
                reason: '${o.key}/$inst',
              );
            }
          }
        }
      },
    );

    test('remove_existing is conditional on existing_board = Yes', () {
      final b = make(_o('GSB_SINGLE'), 'wall_mount');
      final q = SignageCatalog.questionsForUnit(
        b,
        b.units.first,
      ).firstWhere((e) => e.id == 'remove_existing');
      expect(q.isVisible({}), isFalse);
      expect(q.isVisible({'existing_board': false}), isFalse);
      expect(q.isVisible({'existing_board': true}), isTrue);
      // "No" never leaves removal pending.
      final a = {'existing_board': false};
      expect(
        SignageCatalog.questionsForUnit(b, b.units.first).where(
          (e) => e.id == 'remove_existing' && e.required && e.isVisible(a),
        ),
        isEmpty,
      );
    });

    test('power_distance depends on power_available = No (GSB)', () {
      final b = make(_o('GSB_SINGLE'), 'shop_fascia');
      final q = SignageCatalog.questionsForUnit(
        b,
        b.units.first,
      ).firstWhere((e) => e.id == 'power_distance');
      expect(q.showIfId, 'power_available');
      expect(q.showIfValue, false);
      expect(q.unit, 'ft');
    });

    test(
      'green overrides stay: electricity_nearby (GSB), existing_stickers (OWV)',
      () {
        for (final inst in [
          'shop_fascia',
          'wall_mount',
          'double_pole',
          'rooftop',
        ]) {
          expect(
            clIds(make(_o('GSB_SINGLE'), inst)),
            contains('electricity_nearby'),
            reason: inst,
          );
        }
        expect(
          clIds(make(_o('OWV'), 'glass_pasting')),
          contains('existing_stickers'),
        );
        expect(
          clIds(make(_o('PLAIN_VINYL'), 'direct_wall')),
          contains('existing_stickers'),
        );
        expect(
          clIds(make(_o('GSB_SINGLE'), 'shop_fascia')),
          containsAll(['visible_wires', 'checklist_remarks']),
        );
      },
    );

    test(
      'installation-specific retained questions stay with their installation',
      () {
        expect(
          siteIds(make(_o('GSB_SINGLE'), 'shop_fascia')),
          containsAll(['shutter_height', 'fascia_material']),
        );
        expect(
          siteIds(make(_o('GSB_SINGLE'), 'rooftop')),
          contains('terrace_access'),
        );
        expect(
          siteIds(make(_o('GSB_SINGLE'), 'support_pipe')),
          containsAll(['pipe_count', 'pipe_length']),
        );
        expect(
          siteIds(make(_o('FOAM_VINYL'), 'wall_mount')),
          contains('wall_type'),
        );
        expect(
          siteIds(make(_o('OWV'), 'glass_pasting')),
          contains('panel_count'),
        );
        expect(
          siteIds(make(_o('GSB_SINGLE'), 'wall_mount')),
          isNot(contains('shutter_height')),
        );
        expect(
          siteIds(make(_o('GSB_SINGLE'), 'double_pole')),
          isNot(contains('terrace_access')),
        );
        expect(
          clIds(make(_o('NLB_SINGLE_FRAME'), 'shop_fascia')),
          contains('support_pipe_required'),
        );
      },
    );

    test('hidden questions leave no mandatory validator behind', () {
      for (final o in SignageCatalog.mediaOptions) {
        final probe = make(o, null);
        for (final ch in SignageCatalog.choicesForBoard(probe)) {
          if (ch.code == null) continue;
          final b = make(o, ch.code)
            ..width = 5
            ..height = 3;
          completeAnswers(b);
          final u = b.units.first;
          expect(
            SignageCatalog.missingAnswersFor(b, u),
            isEmpty,
            reason: '${o.key}/${ch.code}',
          );
          expect(SignageCatalog.missingMeasurementsFor(b, u), isEmpty);
          expect(
            SiteChecklists.uniqueMissing(b, u),
            isEmpty,
            reason: '${o.key}/${ch.code}',
          );
        }
      }
    });

    test(
      'legacy media keep every question (policy applies to active media only)',
      () {
        final acp = Board(
          id: 'l',
          name: 'l',
          mediaCode: SignageCatalog.acp,
          installationCode: 'wall_mount',
        );
        final ids = siteIds(acp);
        expect(
          ids,
          containsAll(['owner_permission', 'access_method', 'wall_condition']),
        );
      },
    );

    test('NLB Single / Double Side: new names, same retained media policy', () {
      final labels = SignageCatalog.mediaOptions.map((o) => o.label).toList();
      expect(labels, containsAll(['NLB Single Side', 'NLB Double Side']));
      expect(labels.any((l) => l.contains('Frame')), isFalse);
      final single = make(_o('NLB_SINGLE_FRAME'), 'single_pole');
      final dbl = make(_o('NLB_BOX_FRAME'), 'single_pole');
      expect(siteIds(single), siteIds(dbl));
      expect(clIds(single), clIds(dbl));
      // Subtype codes (stored data) are untouched.
      expect(_o('NLB_BOX_FRAME').nlbSubtype, 'NLB_BOX_FRAME');
      // Projecting mount exists only for the double (box) variant.
      expect([
        for (final c in SignageCatalog.choicesForBoard(
          make(_o('NLB_SINGLE_FRAME'), null),
        ))
          c.code,
      ], isNot(contains('flange_bracket')));
      expect([
        for (final c in SignageCatalog.choicesForBoard(
          make(_o('NLB_BOX_FRAME'), null),
        ))
          c.code,
      ], contains('flange_bracket'));
      // Old auto names stay recognised as auto names.
      expect(SignageCatalog.isAutoBoardName('NLB Box 01'), isTrue);
      expect(SignageCatalog.isAutoBoardName('NLB Double 01'), isTrue);
    });
  });

  group('Installation measurements are separate from Site Questions', () {
    test('geometry answers keep their keys, mirrors and validators', () {
      final b = Board(
        id: 'p',
        name: 'p',
        mediaCode: SignageCatalog.gsb,
        installationCode: 'double_pole',
        width: 5,
        height: 3,
      );
      final u = b.units.first;
      final meas = SignageCatalog.measurementQuestionsFor(
        b,
        u,
      ).map((q) => q.id);
      expect(
        meas,
        containsAll(['pole_height', 'pole_gap', 'foundation_depth']),
      );
      expect(
        SignageCatalog.missingAnswersFor(b, u).map((q) => q.id),
        isNot(contains('pole_height')),
      );
      expect(
        SignageCatalog.missingMeasurementsFor(b, u).map((q) => q.id),
        contains('pole_height'),
      );
      // Rooftop / projecting have their own fields; wall mount only mount_height.
      b.installationCode = 'rooftop';
      expect(
        SignageCatalog.measurementQuestionsFor(b, u).map((q) => q.id),
        containsAll(['building_floors', 'structure_height']),
      );
      b.installationCode = 'flange_bracket';
      expect(
        SignageCatalog.measurementQuestionsFor(b, u).map((q) => q.id),
        containsAll(['mount_height', 'projection']),
      );
    });

    test(
      'pending measurements are a visible, actionable board issue',
      () async {
        final c = await _vendor();
        final b =
            c.addMediaGroups(_shop, [
                MediaGroupPlan(_o('GSB_SINGLE'), 1),
              ]).single
              ..width = 5
              ..height = 3
              ..installationCode = 'double_pole';
        expect(
          c
              .boardIssues(b)
              .any(
                (i) =>
                    i.startsWith('Complete') &&
                    i.contains('installation detail'),
              ),
          isTrue,
        );
        final u = b.units.first;
        for (final q in SignageCatalog.missingMeasurementsFor(b, u)) {
          c.setUnitAnswer(_shop, b, u, q.id, 5.0);
        }
        expect(
          c.boardIssues(b).any((i) => i.contains('installation detail')),
          isFalse,
        );
        // Same value feeds the existing canonical measurement mirror.
        expect(u.measurements.mm('bottom_height'), isNotNull);
      },
    );

    testWidgets(
      'editor shows Installation Measurements once, not in the list',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 3200);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final c = await _vendor();
        final b =
            c.addMediaGroups(_shop, [
                MediaGroupPlan(_o('GSB_SINGLE'), 1),
              ]).single
              ..width = 5
              ..height = 3
              ..installationCode = 'double_pole';
        await tester.pumpWidget(
          ChangeNotifierProvider<AppController>.value(
            value: c,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: BoardEditorScreen(
                shopId: _shop,
                boardId: b.id,
                initialStep: BoardEditorScreen.siteQuestionsStep,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Installation Measurements'), findsOneWidget);
        expect(find.byKey(const Key('q_pole_height')), findsOneWidget);
        expect(find.byKey(const Key('gst_field')), findsOneWidget);
        // Placement location / per-board notes are no longer part of Site
        // Questions (their stored values are untouched).
        expect(
          find.byKey(Key('unit_placement_${b.units.first.id}')),
          findsNothing,
        );
        expect(find.text('Placement location (Optional)'), findsNothing);
        expect(find.text('Notes for this board (Optional)'), findsNothing);
      },
    );
  });

  group('Optional shop GST number', () {
    test('format check only; empty is always acceptable', () {
      expect(Gst.isAcceptable(''), isTrue);
      expect(Gst.isAcceptable('   '), isTrue);
      expect(Gst.isAcceptable('33aaaaa0000a1z5'), isTrue);
      expect(Gst.isAcceptable(' 33AAAAA 0000A 1Z5 '), isTrue);
      expect(Gst.isAcceptable('33AAAAA0000A1Z'), isFalse);
      expect(Gst.isAcceptable('XX'), isFalse);
      expect(Gst.normalize(' 33aaaaa 0000a1z5 '), '33AAAAA0000A1Z5');
    });

    test('saved at shop level, optional for completion, round-trips', () async {
      final c = await _vendor();
      final s = c.shop(_shop)!;
      expect(s.gstNumber, '');
      expect(c.setShopGst(s, 'bad'), isFalse);
      expect(s.gstNumber, '');
      expect(c.setShopGst(s, '33aaaaa0000a1z5'), isTrue);
      expect(s.gstNumber, '33AAAAA0000A1Z5');
      final copy = Shop.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      expect(copy.gstNumber, '33AAAAA0000A1Z5');
      // Older record without the field.
      final old = s.toJson()..remove('gstNumber');
      expect(Shop.fromJson(old).gstNumber, '');
      // Clearing is allowed and never blocks the shop.
      expect(c.setShopGst(s, ''), isTrue);
      expect(s.gstNumber, '');
      expect(
        c.shopIssues(s).any((i) => i.toLowerCase().contains('gst')),
        isFalse,
      );
    });
  });

  group('Site Details Summary in the report', () {
    test(
      'shows GST (when entered), the board\'s own answers and no hidden ones',
      () async {
        final c = await _vendor();
        final s = c.shop(_shop)!..boards.clear();
        c.setShopLocation(s, gpsAt(10.8627, 78.6897));
        final b =
            c.addMediaGroups(_shop, [
                MediaGroupPlan(_o('GSB_SINGLE'), 1),
              ]).single
              ..width = 5
              ..height = 3
              ..installationCode = 'shop_fascia';
        completeAnswers(b);
        addValidEvidence(c, _shop, b);
        c.setUnitAnswer(_shop, b, b.units.first, 'existing_board', true);
        c.setUnitAnswer(_shop, b, b.units.first, 'remove_existing', false);
        Map<dynamic, dynamic> group() {
          final r = buildReportData(
            c,
            s,
            now: DateTime(2026, 11, 26),
            groupIds: {b.id},
          );
          return (r.data['groups'] as List).single as Map;
        }

        expect(group().containsKey('gst'), isFalse, reason: 'never invented');
        c.setShopGst(s, '33AAAAA0000A1Z5');
        final g = group();
        expect(g['gst'], '33AAAAA0000A1Z5');
        final labels = [
          for (final r in g['siteAnswers'] as List) (r as List).first,
        ];
        expect(
          labels,
          contains('Is there an existing board at this location?'),
        );
        expect(labels, contains('Shutter top height from ground'));
        expect(
          labels,
          isNot(contains('Shop owner permission obtained?')),
          reason: 'hidden question is not reported',
        );
        expect(
          labels.toSet(),
          hasLength(labels.length),
          reason: 'no duplicate rows',
        );
      },
    );
  });

  group('Remove Media Type', () {
    testWidgets('removes only the selected media after confirmation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final c = await _vendor();
      final s = c.shop(_shop)!..boards.clear();
      final g = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 1),
        MediaGroupPlan(_o('NLB_BOX_FRAME'), 2),
      ]);
      final keep = g[0].id, gone = g[1].id;
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: c,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: BoardEditorScreen(shopId: _shop, boardId: gone),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Cancel keeps everything.
      await tester.tap(find.byKey(const Key('remove_media')));
      await tester.pumpAndSettle();
      expect(find.text('Remove media type?'), findsOneWidget);
      expect(find.textContaining('Physical boards: 2'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(s.boards, hasLength(2));
      // Confirm removes only NLB Double and opens the remaining media.
      await tester.tap(find.byKey(const Key('remove_media')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(s.boards.map((b) => b.id), [keep]);
      expect(c.board(_shop, gone), isNull);
      expect(find.byType(BoardEditorScreen), findsOneWidget);
    });

    testWidgets('removing the last media returns to the previous screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final c = await _vendor();
      final s = c.shop(_shop)!..boards.clear();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(_o('GSB_SINGLE'), 1),
      ]).single;
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: c,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('go'),
                    onPressed: () => Navigator.of(ctx).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            BoardEditorScreen(shopId: _shop, boardId: b.id),
                      ),
                    ),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove_media')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(s.boards, isEmpty);
      expect(find.byType(BoardEditorScreen), findsNothing);
      expect(find.byKey(const Key('go')), findsOneWidget);
    });
  });
}
