import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/measurement_fields.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/catalog/site_checklists.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/board/units_screen.dart';
import 'package:signage_recce/features/survey/feasibility.dart';
import 'package:signage_recce/features/survey/measurement_diagram.dart';
import 'package:signage_recce/features/survey/unit_survey_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

import 'helpers.dart';
import 'support/evidence_fixture.dart';

const _shopId = 's_lakshmi';

Future<(AppController, Board, MemoryLocalStore)> _setup({
  String media = SignageCatalog.gsb,
  String? inst = SignageCatalog.wallMount,
  double? w = 8,
  double? h = 3,
  int quantity = 1,
}) async {
  final store = MemoryLocalStore();
  final c = AppController(store: store);
  await c.init();
  expect(c.loginWithPin(DemoAccounts.vendorPin), isNull);
  final b = c.addBoard(_shopId)
    ..mediaCode = media
    ..installationCode = inst
    ..width = w
    ..height = h
    ..quantity = quantity;
  b.syncUnits();
  return (c, b, store);
}

MeasurementDetails _m(Map<String, double> ft, {Map<String, double>? counts}) =>
    MeasurementDetails(
      valuesMm: {
        for (final e in ft.entries) e.key: MeasureUnit.ft.toMm(e.value),
      },
      counts: counts,
    );

List<String> _ids(List<MeasurementField> f) => f.map((e) => e.id).toList();

List<MeasurementIssue> _validate(Board b, MeasurementDetails m) =>
    MeasurementCatalog.validate(b, b.units.first, m);

bool _has(
  List<MeasurementIssue> issues,
  MeasureIssueLevel level, [
  String? fieldId,
]) => issues.any(
  (i) => i.level == level && (fieldId == null || i.fieldId == fieldId),
);

ChecklistResponse _r(String id, Object? v) =>
    ChecklistResponse(questionId: id, value: v);

void main() {
  // -------------------------------------------------------------------------
  // C. Measurements (33–42)
  // -------------------------------------------------------------------------
  group('C. measurements', () {
    test(
      '33 width/height: board size must be positive; dimensions too',
      () async {
        final (c, b, _) = await _setup(w: null, h: null);
        expect(c.boardIssues(b), contains('Enter board width and height'));
        b
          ..width = 8
          ..height = 3;
        expect(
          c.boardIssues(b),
          isNot(contains('Enter board width and height')),
        );
        final issues = _validate(b, _m({'wall_width': 0, 'wall_height': -2}));
        expect(_has(issues, MeasureIssueLevel.error, 'wall_width'), isTrue);
        expect(_has(issues, MeasureIssueLevel.error, 'wall_height'), isTrue);
      },
    );

    test('34 ground clearance cannot be negative and blocks saving', () async {
      final (c, b, _) = await _setup();
      final u = b.units.first;
      final bad = _m({'bottom_height': -1});
      final issues = c.saveMeasurements(_shopId, b, u.id, bad);
      expect(issues.first.isError, isTrue);
      expect(issues.first.message, contains('cannot be negative'));
      expect(u.measurements.isEmpty, isTrue, reason: 'nothing saved');
      final ok = c.saveMeasurements(_shopId, b, u.id, _m({'bottom_height': 0}));
      expect(ok.where((i) => i.isError), isEmpty);
      expect(u.measurements.mm('bottom_height'), 0);
      expect(c.boardIssues(b).where((i) => i.contains('measurement')), isEmpty);
    });

    test('35 top height = bottom height + board height', () async {
      final (_, b, _) = await _setup(); // 8 × 3 ft
      expect(_validate(b, _m({'bottom_height': 9, 'top_height': 12})), isEmpty);
      expect(
        _has(
          _validate(b, _m({'bottom_height': 9, 'top_height': 14})),
          MeasureIssueLevel.warning,
          'top_height',
        ),
        isTrue,
      );
      expect(
        _has(
          _validate(b, _m({'bottom_height': 9, 'top_height': 8})),
          MeasureIssueLevel.error,
          'top_height',
        ),
        isTrue,
      );
    });

    test('36 feet / inch / mm conversion is exact and does not drift', () {
      expect(MeasureUnit.ft.toMm(1), 304.8);
      expect(MeasureUnit.inch.toMm(1), 25.4);
      expect(MeasureUnit.m.toMm(1), 1000);
      expect(MeasureUnit.mm.toMm(1), 1);
      expect(fmtMmValue(304.8, MeasureUnit.ft), '1');
      expect(fmtMmValue(304.8, MeasureUnit.inch), '12');
      expect(fmtMmValue(304.8, MeasureUnit.mm), '305');
      expect(fmtMmValue(304.8, MeasureUnit.m), '0.305');
      expect(fmtMm(2590.8, MeasureUnit.ft), '8.5 ft');
      final mm = parseLengthMm('8.5', MeasureUnit.ft)!;
      expect(mm, closeTo(2590.8, 1e-9));
      // Display in other units repeatedly; the stored value never changes.
      var stored = mm;
      for (var i = 0; i < 50; i++) {
        for (final u in MeasureUnit.values) {
          fmtMmValue(stored, u);
        }
      }
      expect(stored, mm);
      // Re-entering the displayed value gives the same millimetres back.
      stored = parseLengthMm(
        fmtMmValue(mm, MeasureUnit.inch),
        MeasureUnit.inch,
      )!;
      expect(stored, closeTo(mm, 1e-9));
      expect(parseLengthMm('abc', MeasureUnit.ft), isNull);
      expect(parseLengthMm('', MeasureUnit.ft), isNull);
    });

    test('37 double-pole spacing validation', () async {
      final (_, b, _) = await _setup(inst: SignageCatalog.doublePole);
      final ctx = MeasurementCatalog.contextOf(b, b.units.first);
      expect(_ids(MeasurementCatalog.fieldsFor(ctx)), contains('pole_spacing'));
      expect(
        _has(
          _validate(b, _m({'pole_spacing': 0})),
          MeasureIssueLevel.error,
          'pole_spacing',
        ),
        isTrue,
      );
      expect(
        _has(
          _validate(b, _m({'pole_spacing': 10})),
          MeasureIssueLevel.warning,
          'pole_spacing',
        ),
        isTrue,
        reason: 'wider than the 8 ft board',
      );
      expect(_validate(b, _m({'pole_spacing': 6})), isEmpty);
      final pole = _validate(
        b,
        _m(
          {
            'pole_length_total': 15,
            'pole_above_ground': 12,
            'pole_embedment': 3,
          },
          counts: {'pole_count': 2},
        ),
      );
      expect(pole, isEmpty);
      expect(
        _has(
          _validate(b, _m({'pole_length_total': 15, 'pole_embedment': 16})),
          MeasureIssueLevel.error,
          'pole_embedment',
        ),
        isTrue,
      );
      expect(
        _has(
          _validate(b, _m({}, counts: {'pole_count': 1})),
          MeasureIssueLevel.review,
          'pole_count',
        ),
        isTrue,
      );
      // Single pole has no spacing field.
      b.installationCode = SignageCatalog.singlePole;
      expect(
        _ids(
          MeasurementCatalog.fieldsFor(
            MeasurementCatalog.contextOf(b, b.units.first),
          ),
        ),
        isNot(contains('pole_spacing')),
      );
    });

    test(
      '38 support pipe fields only with rooftop/flange or the switch',
      () async {
        final (_, b, _) = await _setup();
        final u = b.units.first;
        List<String> ids([Map<String, bool> flags = const {}]) => _ids(
          MeasurementCatalog.fieldsFor(
            MeasurementContext(
              mediaCode: b.mediaCode,
              installationCode: b.installationOf(u),
              flags: flags,
            ),
          ),
        );
        expect(ids(), contains('pipes_used'));
        expect(ids(), isNot(contains('pipe_length')));
        expect(
          ids({'pipes_used': true}),
          containsAll([
            'pipe_count',
            'pipe_length',
            'pipe_spacing',
            'pipe_fixing_position',
            'pipe_mount_height',
          ]),
        );
        b.installationCode = SignageCatalog.rooftop;
        expect(ids(), contains('pipe_length'));
        expect(ids(), isNot(contains('pipes_used')));
        b.installationCode = SignageCatalog.directWall;
        expect(ids({'pipes_used': true}), isNot(contains('pipe_length')));
        final m = _m({'pipe_spacing': 4}, counts: {'pipe_count': 1})
          ..flags['pipes_used'] = true;
        b.installationCode = SignageCatalog.wallMount;
        expect(
          _has(_validate(b, m), MeasureIssueLevel.review, 'pipe_spacing'),
          isTrue,
        );
      },
    );

    test('39 standee base dimensions', () async {
      final (_, b, _) = await _setup(
        media: SignageCatalog.singleStandee,
        inst: SignageCatalog.freeStanding,
        w: 2,
        h: 4,
      );
      final ids = _ids(
        MeasurementCatalog.fieldsFor(
          MeasurementCatalog.contextOf(b, b.units.first),
        ),
      );
      expect(
        ids,
        containsAll([
          'standee_overall_height',
          'panel_width',
          'panel_height',
          'base_width',
          'base_depth',
          'ground_surface',
        ]),
      );
      expect(ids, isNot(contains('wall_width')));
      expect(
        _has(
          _validate(b, _m({'base_width': 0})),
          MeasureIssueLevel.error,
          'base_width',
        ),
        isTrue,
      );
      expect(
        _has(
          _validate(b, _m({'standee_overall_height': 5, 'panel_height': 6})),
          MeasureIssueLevel.warning,
          'panel_height',
        ),
        isTrue,
      );
      expect(
        _validate(
          b,
          _m({
            'standee_overall_height': 6,
            'panel_height': 4,
            'base_width': 2,
            'base_depth': 1.5,
          }),
        ),
        isEmpty,
      );
    });

    test('40 available space warnings (wall and glass)', () async {
      final (_, b, _) = await _setup(); // 8 × 3 ft
      final wide = _validate(b, _m({'wall_width': 6, 'wall_height': 2}));
      expect(_has(wide, MeasureIssueLevel.warning, 'wall_width'), isTrue);
      expect(_has(wide, MeasureIssueLevel.warning, 'wall_height'), isTrue);
      final clear = _validate(
        b,
        _m({'wall_width': 9, 'clear_left': 1, 'clear_right': 1}),
      );
      expect(_has(clear, MeasureIssueLevel.warning, 'clear_left'), isTrue);
      expect(_validate(b, _m({'wall_width': 12, 'wall_height': 6})), isEmpty);
      // Unusual values are flagged for review, not rejected.
      expect(
        _has(_validate(b, _m({'wall_width': 200})), MeasureIssueLevel.review),
        isTrue,
      );
      b
        ..mediaCode = SignageCatalog.vinyl
        ..installationCode = SignageCatalog.glassPasting;
      final glass = _validate(
        b,
        _m(
          {'glass_width': 6, 'glass_panel_width': 3},
          counts: {'glass_panel_count': 3},
        ),
      );
      expect(_has(glass, MeasureIssueLevel.warning, 'glass_width'), isTrue);
      expect(
        _has(glass, MeasureIssueLevel.warning, 'glass_panel_width'),
        isTrue,
      );
    });

    test('41 conditional field visibility per installation', () async {
      final (_, b, _) = await _setup();
      List<String> idsFor(String? inst) {
        b.installationCode = inst;
        return _ids(
          MeasurementCatalog.fieldsFor(
            MeasurementCatalog.contextOf(b, b.units.first),
          ),
        );
      }

      expect(idsFor(null), isEmpty);
      final wall = idsFor(SignageCatalog.shopFascia);
      expect(
        wall,
        containsAll([
          'bottom_height',
          'top_height',
          'wall_width',
          'clear_left',
        ]),
      );
      expect(wall, isNot(contains('pole_count')));
      expect(wall, isNot(contains('glass_width')));
      final pole = idsFor(SignageCatalog.doublePole);
      expect(
        pole,
        containsAll(['pole_count', 'pole_embedment', 'pole_spacing']),
      );
      expect(pole, isNot(contains('wall_width')));
      final glass = idsFor(SignageCatalog.glassPasting);
      expect(glass, contains('glass_panel_count'));
      expect(glass, isNot(contains('base_width')));
      // Hidden fields are never validated.
      b.installationCode = SignageCatalog.doublePole;
      expect(_validate(b, _m({'wall_width': -5})), isEmpty);
    });

    test('42 measurements save and reload from local storage', () async {
      final (c, b, store) = await _setup(inst: SignageCatalog.doublePole);
      final u = b.units.first;
      final m =
          _m(
              {'bottom_height': 9.25, 'pole_spacing': 6.5, 'pole_embedment': 3},
              counts: {'pole_count': 2},
            )
            ..texts['pole_position'] = 'Footpath edge'
            ..unit = MeasureUnit.inch;
      expect(
        c.saveMeasurements(_shopId, b, u.id, m).where((i) => i.isError),
        isEmpty,
      );
      await c.flush();
      final again = AppController(store: store);
      await again.init();
      final u2 = again.board(_shopId, b.id)!.unitById(u.id)!;
      expect(u2.measurements.mm('bottom_height'), MeasureUnit.ft.toMm(9.25));
      expect(u2.measurements.mm('pole_spacing'), MeasureUnit.ft.toMm(6.5));
      expect(u2.measurements.counts['pole_count'], 2);
      expect(u2.measurements.texts['pole_position'], 'Footpath edge');
      expect(u2.measurements.unit, MeasureUnit.inch);
      expect(u2.measurements.updatedAt, isNotNull);
      expect(
        again.activities(shopId: _shopId).first.title,
        'Measurements updated',
      );
    });

    test('diagram data follows the draft and repaints on change', () async {
      final (_, b, _) = await _setup(inst: SignageCatalog.doublePole);
      final u = b.units.first;
      final d1 = MeasurementDiagramData.of(b, u, _m({'pole_spacing': 6}));
      final d2 = MeasurementDiagramData.of(b, u, _m({'pole_spacing': 7}));
      expect(d1.boardW, MeasureUnit.ft.toMm(8));
      expect(d1.isDoublePole, isTrue);
      expect(
        MeasurementDiagramPainter(
          d2,
        ).shouldRepaint(MeasurementDiagramPainter(d1)),
        isTrue,
      );
      expect(
        MeasurementDiagramPainter(d1).shouldRepaint(
          MeasurementDiagramPainter(
            MeasurementDiagramData.of(b, u, _m({'pole_spacing': 6})),
          ),
        ),
        isFalse,
      );
    });
  });

  // -------------------------------------------------------------------------
  // E. Checklist (53–62)
  // -------------------------------------------------------------------------
  group('E. checklist', () {
    List<String> qids(String media, String inst) =>
        SiteChecklists.questionsFor(media, inst).map((q) => q.id).toList();

    test('53 GSB checklist (definition kept; active set follows the vendor policy)',
        () {
      // Active GSB: only the vendor-approved checklist questions are asked.
      final active = qids(SignageCatalog.gsb, SignageCatalog.shopFascia);
      expect(
        active,
        containsAll(['electricity_nearby', 'visible_wires', 'checklist_remarks']),
      );
      // Feasibility-flag questions stay (Review: removal needs approval)...
      expect(
        active,
        containsAll([
          'structure_accessible',
          'fixing_surface_available',
          'ac_or_obstruction',
          'location_approved_by_shop',
        ]),
      );
      // ...while the plain vendor-rejected ones are hidden.
      expect(
        active,
        isNot(
          anyOf(
            contains('existing_electrical_point'),
            contains('night_visibility'),
            contains('installation_height_measured'),
            contains('access_equipment'),
          ),
        ),
      );
      // The DEFINITION itself is untouched (history / reviewer / legacy MDF+GSB).
      final ids = [
        for (final q in SiteChecklists.definitionFor(SignageCatalog.gsb)!.questions)
          q.id,
      ];
      expect(
        ids,
        containsAll([
          'structure_accessible',
          'fixing_surface_available',
          'electricity_nearby',
          'existing_electrical_point',
          'installation_height_measured',
          'visible_wires',
          'ac_or_obstruction',
          'night_visibility',
          'access_equipment',
          'location_approved_by_shop',
        ]),
      );
      expect(
        SiteChecklists.definitionFor(SignageCatalog.gsb)!.title,
        contains('GSB'),
      );
    });

    test(
      '54 wall-fit checklists (shop fascia / wall mount) have no pole questions',
      () {
        for (final inst in [
          SignageCatalog.shopFascia,
          SignageCatalog.wallMount,
        ]) {
          expect(
            qids(SignageCatalog.mdfGsb, inst),
            isNot(contains('ground_condition')),
          );
          // ACP / legacy standard-board media keep the full standard list.
          final std = qids(SignageCatalog.acp, inst);
          expect(
            std,
            containsAll([
              'wall_structure_type',
              'fixing_surface_condition',
              'area_free_of_obstruction',
              'support_pipe_required',
              'access_requirement',
            ]),
          );
          expect(std, isNot(contains('pole_configuration_confirmed')));
          // Active NLB: only the retained support-pipe + remarks questions.
          expect(
            qids(SignageCatalog.nlb, inst),
            containsAll(['support_pipe_required', 'checklist_remarks']),
          );
        }
      },
    );

    test('55 pole installations add ground / pole questions', () {
      for (final inst in [
        SignageCatalog.singlePole,
        SignageCatalog.doublePole,
      ]) {
        expect(
          qids(SignageCatalog.mdfGsbDouble, inst),
          containsAll([
            'ground_condition',
            'underground_utilities',
            'pole_excavation_allowed',
          ]),
        );
        expect(
          qids(SignageCatalog.acp2dDouble, inst),
          contains('pole_configuration_confirmed'),
        );
        // Active media keep only the retained safety checks.
        expect(
          qids(SignageCatalog.gsb, inst),
          containsAll(['underground_utilities', 'pole_excavation_allowed']),
        );
        expect(qids(SignageCatalog.gsb, inst), isNot(contains('ground_condition')));
      }
    });

    test('56 standee checklists', () {
      final single = qids(
        SignageCatalog.singleStandee,
        SignageCatalog.freeStanding,
      );
      expect(
        single,
        containsAll([
          'placement_surface',
          'ground_space_available',
          'pedestrian_obstruction',
          'door_shutter_clearance',
          'roadside_exposure',
          'base_type',
          'stability_review',
          'indoor_outdoor',
        ]),
      );
      final double = qids(
        SignageCatalog.doubleStandee,
        SignageCatalog.freeStanding,
      );
      expect(
        double,
        containsAll([
          'front_visibility',
          'back_visibility',
          'placement_surface',
          'pedestrian_clearance',
          'door_shutter_obstruction',
          'base_configuration',
          'technical_review',
        ]),
      );
      expect(double, isNot(contains('stability_review')));
    });

    test('57 one-way vision / vinyl checklist depends on the surface', () {
      final glass = qids(SignageCatalog.vinyl, SignageCatalog.glassPasting);
      expect(
        glass,
        containsAll([
          'glass_panels_measured',
          'glass_panel_count',
          'glass_condition',
          'surface_clean',
          'door_opening_clearance',
          'existing_stickers',
          'panel_divisions',
          'visibility_requirement',
        ]),
      );
      expect(glass, isNot(contains('wall_surface_type')));
      final wall = qids(SignageCatalog.vinyl, SignageCatalog.directWall);
      expect(wall, contains('wall_surface_type'));
      expect(wall, isNot(contains('glass_panel_count')));
      // Wall painting has its own definition, unknown media none.
      expect(
        SiteChecklists.definitionFor(SignageCatalog.wallPainting),
        isNotNull,
      );
      expect(SiteChecklists.questionsFor('UNKNOWN', null), isEmpty);
    });

    test(
      '58 required checklist blocks submission of new media groups',
      () async {
        final (c, b, _) = await _setup(quantity: 2);
        completeAnswers(b);
        completeChecklists(b);
        addValidEvidence(c, _shopId, b);
        final u2 = b.units[1];
        u2.checklist.remove('electricity_nearby');
        final issues = c.boardIssues(b);
        expect(
          issues.where(
            (i) => i.startsWith('Complete the site checklist for Unit 02'),
          ),
          hasLength(1),
        );
        expect(issues.where((i) => i.contains('Unit 01')), isEmpty);
        u2.checklist['electricity_nearby'] = _r('electricity_nearby', 'no');
        expect(issues.length - 1, c.boardIssues(b).length);
        // "No" is a valid answer but flags the item for review.
        expect(feasibilityOf(b, u2).level, SiteFeasibility.requiresReview);
      },
    );

    test('59 N/A only where the question allows it', () {
      final q = SiteChecklists.question(
        SignageCatalog.mdfGsb,
        'structure_accessible',
      )!;
      final na = SiteChecklists.question(
        SignageCatalog.gsb,
        'night_visibility',
      )!;
      expect(q.allowNa, isFalse);
      expect(q.isAnswered(_r(q.id, 'na')), isFalse);
      expect(na.isAnswered(_r(na.id, 'na')), isTrue);
      expect(na.answerText(_r(na.id, 'na')), 'Not applicable');
      final dd = SiteChecklists.question(
        SignageCatalog.nlb,
        'fixing_surface_condition',
      )!;
      expect(dd.isAnswered(_r(dd.id, 'Good')), isTrue);
      expect(dd.isAnswered(_r(dd.id, 'Excellent')), isFalse);
      final numQ = SiteChecklists.question(
        SignageCatalog.vinyl,
        'glass_panel_count',
      )!;
      expect(numQ.isAnswered(_r(numQ.id, 3)), isTrue);
      expect(numQ.isAnswered(_r(numQ.id, 'three')), isFalse);
      final photo = SiteChecklists.question(
        SignageCatalog.gsb,
        'site_evidence_photo',
      )!;
      expect(photo.isAnswered(_r(photo.id, null)), isFalse);
      expect(
        photo.isAnswered(
          ChecklistResponse(questionId: photo.id, evidencePhotoIds: ['p1']),
        ),
        isTrue,
      );
    });

    test(
      '60/61 configuration change keeps applicable and other answers',
      () async {
        final (c, b, _) = await _setup(media: SignageCatalog.mdfGsb);
        final u = b.units.first;
        c.saveChecklist(_shopId, b, u.id, {
          'installation_height_measured': _r(
            'installation_height_measured',
            'yes',
          ),
          'visible_wires': _r('visible_wires', 'no'),
        });
        final gsb = SiteChecklists.statusOf(b, u);
        expect(gsb.answered, 2);
        // GSB → NLB: the shared question stays answered, the GSB-only answer
        // is kept (not erased) but no longer counted; new questions incomplete.
        b.mediaCode = SignageCatalog.acp;
        final nlb = SiteChecklists.statusOf(b, u);
        expect(nlb.answered, 1);
        expect(u.checklist.containsKey('visible_wires'), isTrue);
        expect(
          nlb.missingRequired.map((q) => q.id),
          contains('wall_structure_type'),
        );
        expect(nlb.isComplete, isFalse);
        // Back to GSB: the kept answer applies again.
        b.mediaCode = SignageCatalog.mdfGsb;
        expect(SiteChecklists.statusOf(b, u).answered, 2);
      },
    );

    test('62 legacy media groups are not blocked by the checklist', () async {
      final (c, b, _) = await _setup();
      completeAnswers(b);
      completeChecklists(b);
      b.units.first.checklist.clear();
      expect(
        c.boardIssues(b).where((i) => i.contains('checklist')),
        isNotEmpty,
      );
      b.checklistRequired = false;
      expect(c.boardIssues(b).where((i) => i.contains('checklist')), isEmpty);
      // Legacy JSON without the flag parses as not required.
      final legacy = Board.fromJson(b.toJson()..remove('checklistRequired'));
      expect(legacy.checklistRequired, isFalse);
      expect(
        SiteChecklists.statusOf(legacy, legacy.units.first).isStarted,
        isFalse,
      );
    });

    test('checklist completion is logged once and copy to all units', () async {
      final (c, b, _) = await _setup(quantity: 3);
      final u = b.units.first;
      final all = {
        for (final q in SiteChecklists.questionsFor(
          b.mediaCode,
          b.installationCode,
        ))
          if (q.required)
            q.id: _r(
              q.id,
              q.type == ChecklistResponseType.yesNoNa ? 'yes' : q.options.first,
            ),
      };
      c.saveChecklist(_shopId, b, u.id, all);
      expect(c.activities(shopId: _shopId).first.title, 'Checklist completed');
      final before = c.activities(shopId: _shopId).length;
      c.saveChecklist(_shopId, b, u.id, all);
      expect(
        c.activities(shopId: _shopId).length,
        before,
        reason: 'no duplicate log when already complete',
      );
      expect(c.copyChecklistToOtherUnits(_shopId, b, u.id), 2);
      for (final x in b.units) {
        expect(SiteChecklists.statusOf(b, x).isComplete, isTrue);
      }
    });
  });

  // -------------------------------------------------------------------------
  // F. Electrical & feasibility
  // -------------------------------------------------------------------------
  group('F. electrical & feasibility', () {
    test('electrical survey saves and reloads', () async {
      final (c, b, store) = await _setup();
      final u = b.units.first;
      c.saveElectrical(
        _shopId,
        b,
        u.id,
        ElectricalSurvey(
          electricityAvailable: TriState.yes,
          pointAvailable: TriState.no,
          pointLocation: 'Left pillar',
          distanceMm: MeasureUnit.ft.toMm(12),
          cableRouteNotes: 'Along the sunshade',
          switchLocation: 'Inside shop',
          remarks: 'Single phase',
          evidencePhotoIds: const ['p_x'],
        ),
      );
      await c.flush();
      final again = AppController(store: store);
      await again.init();
      final e = again.board(_shopId, b.id)!.unitById(u.id)!.electrical;
      expect(e.electricityAvailable, TriState.yes);
      expect(e.pointAvailable, TriState.no);
      expect(e.distanceMm, closeTo(3657.6, 1e-9));
      expect(e.pointLocation, 'Left pillar');
      expect(e.evidencePhotoIds, ['p_x']);
      expect(e.updatedAt, isNotNull);
    });

    test(
      'feasibility indicator from obstructions and electrical answers',
      () async {
        final (_, b, _) = await _setup(quantity: 2);
        final u1 = b.units[0], u2 = b.units[1];
        final photo = SitePhoto(
          id: 'ph1',
          path: '${SitePhoto.demoPrefix}1',
          label: 'Front view',
          capturedAt: DateTime(2026),
          width: 1200,
          height: 900,
          unitIds: [u1.id],
        );
        b.photos.add(photo);
        expect(feasibilityOf(b, u1).level, SiteFeasibility.noKnownObstruction);
        ObstructionMark ob(String id, Severity s, List<String> units) =>
            ObstructionMark(
              id: id,
              photoId: 'ph1',
              type: ObstructionType.acUnit,
              shape: ObstructionShape.point,
              number: 1,
              points: const [SurveyPoint(0.5, 0.5)],
              severity: s,
              unitIds: units,
            );
        photo.markup.obstructions.add(ob('o1', Severity.medium, [u1.id]));
        expect(feasibilityOf(b, u1).level, SiteFeasibility.requiresReview);
        expect(feasibilityOf(b, u2).level, SiteFeasibility.noKnownObstruction);
        photo.markup.obstructions.add(ob('o2', Severity.high, [u2.id]));
        expect(feasibilityOf(b, u2).level, SiteFeasibility.blocked);
        expect(feasibilityOf(b, u2).reasons.first, contains('AC Outdoor Unit'));
        // Unlinked obstruction applies to the units the photo shows.
        photo.markup.obstructions
          ..clear()
          ..add(ob('o3', Severity.high, const []));
        expect(feasibilityOf(b, u1).level, SiteFeasibility.blocked);
        expect(feasibilityOf(b, u2).level, SiteFeasibility.noKnownObstruction);
        // Illuminated media without electricity → review.
        u2.electrical = ElectricalSurvey(electricityAvailable: TriState.no);
        expect(feasibilityOf(b, u2).level, SiteFeasibility.requiresReview);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Widgets
  // -------------------------------------------------------------------------
  group('unit survey screen', () {
    setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);

    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    Widget host(AppController c, Widget child) =>
        ChangeNotifierProvider<AppController>.value(
          value: c,
          child: MaterialApp(theme: AppTheme.light(), home: child),
        );

    Future<void> show(
      WidgetTester tester,
      Finder f,
      String list, {
      double delta = 200,
    }) async {
      final scrollable = find
          .descendant(
            of: find.byKey(PageStorageKey<String>(list)),
            matching: find.byType(Scrollable),
          )
          .first;
      if (f.evaluate().isEmpty) {
        try {
          await tester.scrollUntilVisible(f, delta, scrollable: scrollable);
        } on StateError {
          // Target is on the other side of the viewport: search back.
          await tester.scrollUntilVisible(f, -delta, scrollable: scrollable);
        }
      }
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
    }

    testWidgets('measurements: enter, convert units, diagram, save', (
      tester,
    ) async {
      phone(tester);
      final (c, b, _) = await _setup();
      final u = b.units.first;
      await tester.pumpWidget(
        host(c, UnitSurveyScreen(shopId: _shopId, boardId: b.id, unitId: u.id)),
      );
      await tester.pumpAndSettle();
      expect(find.text('GSB – Unit 01'), findsOneWidget);
      expect(find.byKey(const Key('m_pipe_length')), findsNothing);
      expect(find.byKey(const Key('m_pole_count')), findsNothing);

      await tester.enterText(find.byKey(const Key('m_bottom_height')), '9');
      await tester.enterText(find.byKey(const Key('m_top_height')), '12');
      await tester.pumpAndSettle();

      // Unit switch re-displays from millimetres.
      await tester.tap(find.byKey(const Key('m_unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('in').last);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const Key('m_bottom_height')),
      );
      expect(field.controller!.text, '108');

      // Invalid (negative) value disables Save.
      await tester.enterText(find.byKey(const Key('m_wall_width')), '-1');
      await tester.pumpAndSettle();
      await show(
        tester,
        find.byKey(const Key('m_save')),
        'survey_measure_list',
      );
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('m_save'))).onPressed,
        isNull,
      );
      await show(
        tester,
        find.byKey(const Key('m_wall_width')),
        'survey_measure_list',
        delta: -200,
      );
      await tester.enterText(find.byKey(const Key('m_wall_width')), '120');
      await tester.pumpAndSettle();

      await show(
        tester,
        find.byKey(const Key('m_diagram')),
        'survey_measure_list',
      );
      expect(find.byKey(const Key('m_diagram')), findsOneWidget);
      // Pipes switch shows the pipe fields.
      await show(
        tester,
        find.byKey(const Key('m_pipes_used')),
        'survey_measure_list',
      );
      await tester.tap(find.byKey(const Key('m_pipes_used')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('m_pipe_length')), findsOneWidget);

      await show(
        tester,
        find.byKey(const Key('m_save')),
        'survey_measure_list',
      );
      await tester.tap(find.byKey(const Key('m_save')));
      await tester.pumpAndSettle();
      expect(u.measurements.mm('bottom_height'), MeasureUnit.ft.toMm(9));
      expect(u.measurements.mm('wall_width'), MeasureUnit.inch.toMm(120));
      expect(u.measurements.unit, MeasureUnit.inch);
      expect(u.measurements.flags['pipes_used'], isTrue);
      // Saved: back navigation is not blocked.
      expect(find.text('Measurements saved'), findsOneWidget);
    });

    testWidgets('checklist: answer, save, unsaved guard, electrical', (
      tester,
    ) async {
      phone(tester);
      // MDF+GSB keeps the full GSB checklist (not filtered by the policy).
      final (c, b, _) = await _setup(media: SignageCatalog.mdfGsb);
      final u = b.units.first;
      await tester.pumpWidget(
        host(
          c,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => UnitSurveyScreen(
                        shopId: _shopId,
                        boardId: b.id,
                        unitId: u.id,
                        initialTab: 1,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cl_progress')), findsOneWidget);
      // N/A only offered where allowed.
      expect(find.byKey(const Key('cl_structure_accessible_na')), findsNothing);
      await tester.tap(find.byKey(const Key('cl_structure_accessible_yes')));
      await tester.pumpAndSettle();
      await show(
        tester,
        find.byKey(const Key('cl_night_visibility_na')),
        'survey_checklist_list',
      );
      await tester.tap(find.byKey(const Key('cl_night_visibility_na')));
      await tester.pumpAndSettle();

      // Unsaved → back asks to discard.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await show(
        tester,
        find.byKey(const Key('cl_save')),
        'survey_checklist_list',
      );
      await tester.tap(find.byKey(const Key('cl_save')));
      await tester.pumpAndSettle();
      expect(u.checklist['structure_accessible']!.value, 'yes');
      expect(u.checklist['night_visibility']!.isNa, isTrue);
      ScaffoldMessenger.of(
        tester.element(find.byType(TabBarView)),
      ).clearSnackBars();
      await tester.pumpAndSettle();

      // Electrical tab.
      await tester.tap(find.byKey(const Key('survey_tab_electrical')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('not an electrical safety certification'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('el_available_no')));
      await tester.enterText(find.byKey(const Key('el_distance')), '15');
      await tester.pumpAndSettle();
      await show(
        tester,
        find.byKey(const Key('el_save')),
        'survey_electrical_list',
      );
      await tester.tap(find.byKey(const Key('el_save')));
      await tester.pumpAndSettle();
      expect(u.electrical.electricityAvailable, TriState.no);
      expect(u.electrical.distanceMm, MeasureUnit.ft.toMm(15));

      // Obstructions tab shows the feasibility indicator.
      await tester.ensureVisible(
        find.byKey(const Key('survey_tab_obstructions')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('survey_tab_obstructions')));
      await tester.pumpAndSettle();
      expect(find.text('Requires Review'), findsOneWidget);
      expect(find.textContaining('Operational indicator only'), findsOneWidget);

      // Everything saved → back pops without a prompt.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('read-only for reviewers: no save buttons, fields disabled', (
      tester,
    ) async {
      phone(tester);
      final (c, b, _) = await _setup();
      final u = b.units.first;
      c.logout();
      expect(c.loginWithPin(DemoAccounts.businessPin), isNull);
      await tester.pumpWidget(
        host(c, UnitSurveyScreen(shopId: _shopId, boardId: b.id, unitId: u.id)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Read only'), findsOneWidget);
      expect(find.byKey(const Key('m_save')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('m_bottom_height')))
            .enabled,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('survey_tab_checklist')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cl_save')), findsNothing);
      await tester.tap(find.byKey(const Key('survey_tab_electrical')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('el_save')), findsNothing);
    });

    testWidgets('units screen shows survey status and opens the survey', (
      tester,
    ) async {
      phone(tester);
      final (c, b, _) = await _setup(quantity: 2);
      await tester.pumpWidget(
        host(c, UnitsScreen(shopId: _shopId, boardId: b.id)),
      );
      await tester.pumpAndSettle();
      final open = find.byKey(const Key('unit_survey_0'));
      await tester.ensureVisible(open);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unit_survey_block_0')), findsOneWidget);
      expect(find.textContaining('required left'), findsWidgets);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(UnitSurveyScreen), findsOneWidget);
      expect(find.text('GSB – Unit 01'), findsOneWidget);
    });
  });
}
