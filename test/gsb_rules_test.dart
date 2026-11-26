import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/core/utils/length_input.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/gsb/gsb_board.dart';
import 'package:signage_recce/features/gsb/gsb_rules.dart';
import 'package:signage_recce/state/app_controller.dart';

GsbFabricationPlan _plan(
  double wFt,
  double hFt, {
  GsbVariant v = GsbVariant.single,
  double depthIn = 8,
  double? wallIn,
}) => GsbRules.plan(
  GsbBoardInput(
    variant: v,
    widthIn: wFt * 12,
    heightIn: hFt * 12,
    depthIn: depthIn,
    wallThicknessIn: wallIn,
  ),
);

bool _has(GsbFabricationPlan p, String code) =>
    p.issues.any((i) => i.code == code);

void main() {
  group('GSB module division', () {
    test('no split below 5 ft and up to 15 ft', () {
      for (final (w, h) in [(6.0, 3.0), (8.0, 3.0), (10.0, 4.0), (13.0, 4.0)]) {
        final p = _plan(w, h);
        expect(p.modules, hasLength(1), reason: '$w x $h');
        expect(p.columnsIn, [w * 12]);
        expect(p.rowsIn, [h * 12]);
        expect(p.requiresReview, isTrue); // brace basis is always review
        expect(_has(p, 'HEIGHT_SPLIT_REVIEW'), isFalse);
      }
    });

    test('reference layouts', () {
      final cases = <(double, double, int, double, double)>[
        (16, 7, 4, 96, 42),
        (17, 7, 4, 102, 42),
        (18, 7, 4, 108, 42),
        (20, 7, 4, 120, 42),
        (20, 10, 4, 120, 60),
        (32, 10, 6, 128, 60),
      ];
      for (final (w, h, n, mw, mh) in cases) {
        final p = _plan(w, h);
        expect(p.modules, hasLength(n), reason: '$w x $h');
        for (final m in p.modules) {
          expect(m.widthIn, mw, reason: '$w x $h ${m.id}');
          expect(m.heightIn, mh, reason: '$w x $h ${m.id}');
        }
      }
      final big = _plan(40, 8);
      expect(big.columnsIn, [180, 180, 120]);
      expect(big.rowsIn, [48, 48]);
      expect(big.modules, hasLength(6));
    });

    test('module ids bottom-left first with stored row / column', () {
      final p = _plan(16, 7);
      final m1 = p.modules.firstWhere((m) => m.id == 'M1');
      final m2 = p.modules.firstWhere((m) => m.id == 'M2');
      final m3 = p.modules.firstWhere((m) => m.id == 'M3');
      expect((m1.row, m1.column, m1.x0In, m1.y0In), (0, 0, 0.0, 0.0));
      expect((m2.row, m2.column, m2.y0In), (1, 0, 42.0));
      expect((m3.row, m3.column, m3.x0In), (0, 1, 96.0));
    });

    test('unapproved partitions are flagged, never invented', () {
      final h5 = _plan(8, 5);
      expect(h5.heightSplit, isTrue);
      expect(h5.rowsIn, isNull);
      expect(_has(h5, 'HEIGHT_SPLIT_REVIEW'), isTrue);
      expect(h5.count(GsbMemberRole.internalVertical), 0);
      expect(h5.modules, hasLength(1)); // outer frame only

      final w22 = _plan(22, 4);
      expect(w22.columnsIn, isNull);
      expect(_has(w22, 'WIDTH_SPLIT_REVIEW'), isTrue);

      final f15 = _plan(50, 15);
      expect(_has(f15, 'HEIGHT_SPLIT_REVIEW'), isTrue);
    });
  });

  group('GSB support spacing', () {
    test('whole-board even widths use 24-in bays', () {
      expect(_plan(8, 3).modules.single.baysIn, [24, 24, 24, 24]);
      expect(_plan(10, 4).modules.single.baysIn, [24, 24, 24, 24, 24]);
      expect(_plan(6, 3).modules.single.supportStationsIn, [24, 48]);
    });

    test('whole-board odd widths use 18-in edge bays', () {
      expect(_plan(13, 4).modules.single.baysIn, [18, 24, 24, 24, 24, 24, 18]);
    });

    test('17 x 7 keeps the approved mirrored pattern (no 0.5 ft bay)', () {
      final p = _plan(17, 7);
      for (final m in p.modules) {
        final bays = m.baysIn!;
        expect(bays.any((b) => b < 12), isFalse, reason: m.id);
        if (m.column == 0) {
          expect(bays, [18, 24, 24, 24, 12]);
          expect(m.supportStationsIn, [18, 42, 66, 90]);
        } else {
          expect(bays, [12, 24, 24, 24, 18]);
          expect(m.supportStationsIn, [12, 36, 60, 84]);
          // Global stations 9.5, 11.5, 13.5, 15.5 ft.
          expect(m.supportStationsIn!.map((x) => (m.x0In + x) / 12).toList(), [
            9.5,
            11.5,
            13.5,
            15.5,
          ]);
        }
      }
    });

    test('18 x 7 and 20 x 7 module bays', () {
      for (final m in _plan(18, 7).modules) {
        expect(m.baysIn, [18, 24, 24, 24, 18]);
      }
      for (final m in _plan(20, 7).modules) {
        expect(m.baysIn, [24, 24, 24, 24, 24]);
      }
      for (final m in _plan(16, 7).modules) {
        expect(m.baysIn, [24, 24, 24, 24]);
      }
    });

    test('fractional module width (10 ft 8 in) needs review', () {
      final p = _plan(32, 10);
      expect(p.modules.every((m) => m.supportStationsIn == null), isTrue);
      expect(_has(p, 'SUPPORT_SPACING_REVIEW'), isTrue);
      expect(p.count(GsbMemberRole.internalVertical), 0);
    });
  });

  group('GSB horizontal and depth supports', () {
    test('depth station levels', () {
      expect(GsbRules.depthStations(35), isEmpty);
      expect(GsbRules.depthStations(36), [18]);
      expect(GsbRules.depthStations(42), [21]); // 1.75 ft in 3.5 ft module
      expect(GsbRules.depthStations(95), [47.5]);
      expect(GsbRules.depthStations(96), [32, 64]);
    });

    test('additional horizontal only when module height > 4 ft', () {
      expect(_plan(10, 4).modules.single.extraHorizontal, isFalse);
      expect(_plan(16, 7).modules.every((m) => !m.extraHorizontal), isTrue);
      final p = _plan(20, 10);
      expect(p.modules.every((m) => m.extraHorizontal), isTrue);
      expect(p.count(GsbMemberRole.extraHorizontal), 4);
      expect(_has(p, 'EDGE_BAY_HORIZONTAL_REVIEW'), isTrue);
    });
  });

  group('GSB Single vs Double', () {
    test('support plane, braces, cladding and LED set', () {
      final s = _plan(8, 3);
      final d = _plan(8, 3, v: GsbVariant.double);
      final sv = s.members.where(
        (m) => m.role == GsbMemberRole.internalVertical,
      );
      final dv = d.members.where(
        (m) => m.role == GsbMemberRole.internalVertical,
      );
      expect(sv.every((m) => m.start.z == 7.5), isTrue); // rear plane
      expect(dv.every((m) => m.start.z == 4), isTrue); // centre depth
      expect(sv, hasLength(3));
      expect(dv, hasLength(3)); // not duplicated front + rear
      // Single: one 9-in brace per top / bottom junction.
      final sb = s.members.where((m) => m.role == GsbMemberRole.brace);
      expect(sb, hasLength(6));
      expect(sb.every((m) => m.nominalIn == 9), isTrue);
      expect(sb.every((m) => (m.lengthIn - 9).abs() < 1e-9), isTrue);
      // Double: paired 4 + 4 in braces.
      final db = d.members.where((m) => m.role == GsbMemberRole.brace);
      expect(db, hasLength(12));
      expect(db.every((m) => m.nominalIn == 4), isTrue);
      expect(s.hasRearGi, isTrue);
      expect(d.hasRearGi, isFalse);
      expect(d.giTiersIn, isNull);
      expect(s.printFlexFaces, 1);
      expect(d.printFlexFaces, 2);
      expect(s.physicalLedSets, 1);
      expect(d.physicalLedSets, 1);
      expect(_has(d, 'DOUBLE_OPTICS_REVIEW'), isTrue);
    });

    test('double centre posts are connected, never floating', () {
      final d = _plan(16, 7, v: GsbVariant.double);
      final ids = d.members.map((m) => m.id).toSet();
      for (final v in d.members.where(
        (m) => m.role == GsbMemberRole.internalVertical,
      )) {
        expect(ids.contains('${v.id}.DT'), isTrue);
        expect(ids.contains('${v.id}.DB'), isTrue);
      }
    });

    test('modular seams use 4-in seam braces, outer rails standard', () {
      final p = _plan(16, 7);
      final seam = p.members.where((m) => m.role == GsbMemberRole.seamBrace);
      // 2 columns x 3 verticals x (lower-module top + upper-module bottom).
      expect(seam, hasLength(12));
      expect(seam.every((m) => m.nominalIn == 4), isTrue);
      final outer = p.members.where((m) => m.role == GsbMemberRole.brace);
      expect(outer, hasLength(12));
      expect(outer.every((m) => m.nominalIn == 9), isTrue);
    });

    test('8-in depth with 1 x 1 SHS: 6-in connector cut length', () {
      final p = _plan(8, 3);
      final c = p.members.where((m) => m.role == GsbMemberRole.depthConnector);
      expect(c, isNotEmpty);
      expect(c.every((m) => (m.lengthIn - 6).abs() < 1e-9), isTrue);
      // Corners (4) + one H/2 station on each stile (2).
      expect(c, hasLength(6));
    });

    test('all members finite, non-zero and inside the board box', () {
      for (final (w, h) in [
        (6.0, 3.0),
        (13.0, 4.0),
        (17.0, 7.0),
        (20.0, 10.0),
        (40.0, 8.0),
      ]) {
        for (final v in GsbVariant.values) {
          final p = _plan(w, h, v: v);
          for (final m in p.members) {
            expect(m.start.isFinite && m.end.isFinite, isTrue);
            expect(m.lengthIn, greaterThan(0));
            for (final pt in [m.start, m.end]) {
              expect(pt.x, inInclusiveRange(-1e-9, w * 12 + 1e-9));
              expect(pt.y, inInclusiveRange(-1e-9, h * 12 + 1e-9));
              expect(pt.z, inInclusiveRange(-1e-9, 8 + 1e-9));
            }
          }
          expect(
            p.members.map((m) => m.id).toSet().length,
            p.members.length,
            reason: 'stable unique member ids',
          );
        }
      }
    });
  });

  group('GSB coupling, trim and GI', () {
    test('coupling inserts at seams need a fit review', () {
      final p = _plan(16, 7);
      expect(p.inserts, hasLength(16));
      expect(p.inserts.every((i) => i.lengthIn == 24), isTrue);
      expect(p.inserts.every((i) => i.engagementIn == 12), isTrue);
      expect(_has(p, 'INSERT_FIT_REVIEW'), isTrue);
      final thin = _plan(16, 7, wallIn: 0.06);
      expect(_has(thin, 'INSERT_FIT_REVIEW'), isFalse);
      expect(_has(thin, 'INSERT_CLASH'), isFalse); // 0.88 in clear
      final thick = _plan(16, 7, wallIn: 0.2);
      expect(_has(thick, 'INSERT_CLASH'), isTrue); // 0.6 in clear
      expect(_plan(10, 4).inserts, isEmpty);
    });

    test('powder-coated trim pieces (99-in max, 2-in overlap)', () {
      expect(GsbRules.trimPieces(96), [96]);
      expect(GsbRules.trimPieces(108), [99, 11]);
      expect(GsbRules.trimPieces(120), [99, 23]);
      expect(_plan(8, 3).trimPieceCount, 4);
      expect(_plan(9, 3).trimPieceCount, 6);
      expect(_plan(8, 10).trimPieceCount, 6);
      for (final len in <double>[96, 108, 120, 250, 480]) {
        final pieces = GsbRules.trimPieces(len);
        final installed =
            pieces.fold<double>(0, (s, v) => s + v) - 2 * (pieces.length - 1);
        expect(installed, closeTo(len, 1e-9));
        expect(pieces.every((p) => p <= 99), isTrue);
      }
    });

    test('rear GI tiers (GSB Single only)', () {
      final p85 = _plan(8, 5);
      expect(p85.giTiersIn, [30, 36]);
      expect(p85.giInstalledHeightIn, 60);
      final p217 = _plan(21, 7);
      expect(p217.giTiersIn, [30, 30, 36]);
      expect(p217.giInstalledHeightIn, 84);
      expect(_has(_plan(12, 8), 'GI_PLAN_REVIEW'), isTrue);
    });
  });

  group('GSB validation and overrides', () {
    test('invalid sizes produce errors and no geometry', () {
      for (final input in [
        const GsbBoardInput(
          variant: GsbVariant.single,
          widthIn: 0,
          heightIn: 36,
        ),
        const GsbBoardInput(
          variant: GsbVariant.single,
          widthIn: -12,
          heightIn: 36,
        ),
        const GsbBoardInput(
          variant: GsbVariant.single,
          widthIn: double.nan,
          heightIn: 36,
        ),
        const GsbBoardInput(
          variant: GsbVariant.single,
          widthIn: 96,
          heightIn: 36,
          depthIn: 2,
        ),
      ]) {
        final p = GsbRules.plan(input);
        expect(p.hasErrors, isTrue);
        expect(p.members, isEmpty);
      }
    });

    test('depth override recomputes geometry and needs review', () {
      final p = _plan(8, 3, depthIn: 6);
      expect(_has(p, 'DEPTH_OVERRIDE_REVIEW'), isTrue);
      final c = p.members.where((m) => m.role == GsbMemberRole.depthConnector);
      expect(c.every((m) => (m.lengthIn - 4).abs() < 1e-9), isTrue);
      final v = p.members.where(
        (m) => m.role == GsbMemberRole.internalVertical,
      );
      expect(v.every((m) => m.start.z == 5.5), isTrue);
      expect(_has(_plan(8, 3), 'DEPTH_OVERRIDE_REVIEW'), isFalse);
    });
  });

  group('exact length input', () {
    test('feet and inches parsing', () {
      const ft = MeasureUnit.ft;
      expect(parseLengthToFeet('5 ft 6 in', ft), 5.5);
      expect(parseLengthToFeet('5\' 6"', ft), 5.5);
      expect(parseLengthToFeet("5'6", ft), 5.5);
      expect(parseLengthToFeet('5ft6in', ft), 5.5);
      expect(parseLengthToFeet('66 in', ft), 5.5);
      expect(parseLengthToFeet('66"', ft), 5.5);
      expect(parseLengthToFeet('5.5', ft), 5.5);
      expect(parseLengthToFeet('66', MeasureUnit.inch), 5.5);
      expect(parseLengthToFeet('2 ft 3 in', ft), 2.25);
      expect(parseLengthToFeet('10 ft 6 in', ft), 10.5);
      expect(parseLengthToFeet('2 ft 3 1/2 in', ft), closeTo(27.5 / 12, 1e-12));
      expect(parseLengthToFeet('1/2', ft), 0.5);
      expect(parseLengthToFeet('1.5 m', ft), closeTo(1500 / 304.8, 1e-12));
      expect(parseLengthToFeet('1524 mm', ft), closeTo(5, 1e-12));
      expect(parseLengthToFeet('-5', ft), -5);
      expect(parseLengthToFeet('0', ft), 0);
      for (final bad in ['', 'abc', '5 ft x', '1/0', "'", '5..5']) {
        expect(parseLengthToFeet(bad, ft), isNull, reason: bad);
      }
    });

    test('validation and formatting', () {
      expect(validateLengthFeet(null, label: 'Width'), isNotNull);
      expect(validateLengthFeet(0, label: 'Width'), isNotNull);
      expect(validateLengthFeet(-1, label: 'Width'), isNotNull);
      expect(validateLengthFeet(0, label: 'Mount', allowZero: true), isNull);
      expect(validateLengthFeet(500, label: 'Width', maxFt: 200), isNotNull);
      expect(validateLengthFeet(5.5, label: 'Width'), isNull);
      expect(fmtFeetInches(5.5), '5 ft 6 in');
      expect(fmtFeetInches(10), '10 ft');
      expect(fmtFeetInches(0.75), '9 in');
      expect(fmtFeetInches(27.5 / 12), '2 ft 3.5 in');
      // Round trip without drift.
      final ft = parseLengthToFeet('10 ft 7 in', MeasureUnit.ft)!;
      expect(fmtFeetInches(ft), '10 ft 7 in');
      expect(ft * 12, closeTo(127, 1e-9));
    });
  });

  group('GSB board data', () {
    test('variant mapping and backward-compatible JSON', () {
      final b = Board(id: 'b1', name: 'B', mediaCode: SignageCatalog.gsb);
      expect(GsbBoard.variantOf(b), GsbVariant.single);
      expect(GsbBoard.isExplicit(b), isFalse);
      expect(b.toJson().containsKey('boardVariant'), isFalse);
      b.doubleSided = true;
      expect(GsbBoard.variantOf(b), GsbVariant.double);
      expect(b.toJson()['boardVariant'], 'GSB_DOUBLE');
      final mdf = Board(
        id: 'b2',
        name: 'M',
        mediaCode: SignageCatalog.mdfGsb,
        doubleSided: true,
      );
      expect(GsbBoard.variantOf(mdf), isNull);
      expect(mdf.gsbVariantKey, isNull);

      // An older record (no new fields) still parses.
      final legacy = Board.fromJson({
        'id': 'old',
        'name': 'Old',
        'mediaCode': 'GSB',
        'doubleSided': false,
      });
      expect(legacy.gsbOverrides, isEmpty);
      expect(legacy.gsbVariantKey, 'GSB_SINGLE');
    });

    test('overrides: validation, persistence, revert', () async {
      final c = AppController(store: MemoryLocalStore());
      await c.init();
      c.loginWithPin('5678');
      final b = c.addBoard('s_lakshmi')
        ..mediaCode = SignageCatalog.gsb
        ..doubleSided = false
        ..width = 16
        ..height = 7;
      final u = b.units.first;
      expect(GsbBoard.depthIn(b, u), 8);
      String? add(double v, String reason) => c.addGsbOverride(
        's_lakshmi',
        b,
        unitId: u.id,
        field: GsbOverrideField.depth,
        originalIn: 8,
        proposedIn: v,
        reason: reason,
        ruleVersion: kGsbRuleVersion,
      );
      expect(add(6, '   '), isNotNull); // blank reason
      expect(add(8, 'Site clearance restriction'), isNotNull); // same value
      expect(add(-2, 'Site clearance restriction'), isNotNull);
      expect(b.gsbOverrides, isEmpty);
      expect(add(6, 'Site clearance restriction'), isNull);
      final o = b.gsbOverrides.single;
      expect(o.status, GsbOverrideStatus.requiresReview);
      expect(o.userId, isNotEmpty);
      expect(o.ruleVersion, kGsbRuleVersion);
      expect(GsbBoard.depthIn(b, u), 6);
      final plan = GsbBoard.planFor(b, u)!;
      expect(plan.input.depthIn, 6);
      expect(_has(plan, 'DEPTH_OVERRIDE_REVIEW'), isTrue);

      // Round trip through JSON keeps the history.
      final copy = Board.fromJson(
        jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>,
      );
      expect(copy.gsbOverrides.single.reason, 'Site clearance restriction');
      expect(copy.gsbOverrides.single.proposedIn, 6);

      c.revertGsbOverride('s_lakshmi', b, o.id);
      expect(o.status, GsbOverrideStatus.reverted);
      expect(b.gsbOverrides, hasLength(1)); // history kept
      expect(GsbBoard.depthIn(b, u), 8);

      // Other boards are unaffected.
      final other = c.addBoard('s_lakshmi')..mediaCode = SignageCatalog.gsb;
      expect(GsbBoard.depthIn(other, other.units.first), 8);
    });
  });
}
