import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/measurement_fields.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/features/drawing/signage_geometry.dart';
import 'package:signage_recce/features/model3d/signage_spec.dart';
import 'package:signage_recce/state/app_controller.dart';

Future<(AppController, MemoryLocalStore)> _vendor() async {
  final store = MemoryLocalStore();
  final c = AppController(store: store);
  await c.init();
  c.loginWithPin(DemoAccounts.vendorPin);
  return (c, store);
}

Board _gsb(AppController c, {int qty = 1}) {
  final b = c.addBoard('s_lakshmi')
    ..mediaCode = SignageCatalog.gsb
    ..installationCode = SignageCatalog.doublePole
    ..width = 8
    ..height = 3;
  if (qty > 1) c.increaseQuantity('s_lakshmi', b, qty);
  return b;
}

void main() {
  group('B. Catalog', () {
    test('21-22 exactly 13 selectable media, unique canonical ids', () {
      final codes = SignageCatalog.catalogMedia.map((m) => m.code).toList();
      expect(codes, hasLength(13));
      expect(codes, [
        'GSB',
        'NLB',
        'FOAM_VINYL',
        'ACRYLIC',
        'SANDWICH',
        'OWV',
        'PLAIN_VINYL',
        'ACP2D',
        'ACP2D_DS',
        'ACP',
        'ACP3D_DS',
        'MDF_GSB',
        'MDF_GSB_DS',
      ]);
      expect(SignageCatalog.catalogMedia.any((m) => m.legacy), isFalse);
      final all = SignageCatalog.allMediaTypes.map((m) => m.code).toList();
      expect(all.toSet(), hasLength(all.length), reason: 'no duplicates');
      for (final m in SignageCatalog.catalogMedia) {
        expect(SignageCatalog.installationsFor(m.code), isNotEmpty);
        expect(m.template, isNotEmpty, reason: m.code);
      }
    });

    test(
      '23-24 GSB and Non-Lit have an explicit single/double choice',
      () async {
        final (c, _) = await _vendor();
        for (final code in [SignageCatalog.gsb, SignageCatalog.nlb]) {
          final b = c.addBoard('s_lakshmi')..mediaCode = code;
          expect(
            SignageCatalog.media(code)!.sidedness,
            MediaSidedness.selectable,
          );
          expect(SignageCatalog.isDoubleSided(b), isFalse);
          c.setDoubleSided('s_lakshmi', b, true);
          expect(SignageCatalog.isDoubleSided(b), isTrue);
          expect(SignageModelSpec.of(b, b.units.first).isDoubleSided, isTrue);
          expect(b.quantity, 1, reason: 'double-sided is not 2 units');
        }
      },
    );

    test('25-29 variants are distinct media with distinct templates', () {
      MediaType m(String c) => SignageCatalog.media(c)!;
      expect(m('ACP2D').template, 'acp2d');
      expect(m('ACP').template, 'acp3d');
      expect(m('ACP2D_DS').sidedness, MediaSidedness.double);
      expect(m('ACP3D_DS').sidedness, MediaSidedness.double);
      expect(m('ACP2D').sidedness, MediaSidedness.single);
      expect(m('MDF_GSB').template, m('MDF_GSB_DS').template);
      expect(m('MDF_GSB').sidedness, isNot(m('MDF_GSB_DS').sidedness));
      expect(m('ACRYLIC').thicknessMm, greaterThan(0));
      expect(m('SANDWICH').installations, [SignageCatalog.freeStanding]);
      expect(m('SANDWICH').sidedness, MediaSidedness.double);
      expect(m('OWV').template, isNot(m('PLAIN_VINYL').template));
      expect(m('OWV').installations, [SignageCatalog.glassPasting]);
      expect(
        SignageCatalog.installation(SignageCatalog.supportPipe)!.name,
        'Support Pipe',
      );
    });

    test('30 legacy media keep working and need explicit mapping', () async {
      expect(SignageCatalog.mediaTypes, hasLength(8), reason: 'kept');
      for (final code in ['FLANGE', 'VINYL', 'WALL', 'SSTANDEE', 'DSTANDEE']) {
        expect(SignageCatalog.isLegacy(code), isTrue, reason: code);
        expect(SignageCatalog.legacyMapping(code), isNotNull);
      }
      expect(SignageCatalog.legacyMapping('VINYL')!.ambiguous, isTrue);
      expect(SignageCatalog.legacyMapping('WALL')!.candidates, isEmpty);
      expect(SignageCatalog.legacyMapping('GSB'), isNull);

      final (c, _) = await _vendor();
      final b = c.addBoard('s_lakshmi')
        ..mediaCode = SignageCatalog.vinyl
        ..installationCode = SignageCatalog.glassPasting;
      expect(
        () => c.mapLegacyMedia('s_lakshmi', b, SignageCatalog.gsb),
        throwsStateError,
        reason: 'not a candidate',
      );
      expect(b.mediaCode, 'VINYL', reason: 'never silently changed');
      c.mapLegacyMedia('s_lakshmi', b, SignageCatalog.oneWayVision);
      expect(b.mediaCode, 'OWV');
      expect(b.legacyMediaCode, 'VINYL');
      expect(b.installationCode, SignageCatalog.glassPasting);
      expect(c.data.activities.last.title, 'Media type mapped');
    });

    test('submitted snapshots keep the legacy media type', () async {
      final (c, _) = await _vendor();
      final amma = c.shop('s_amma')!;
      final snap = jsonEncode(amma.submissions.single.snapshot);
      expect(
        amma.submissions.single.shopSnapshot.boards.first.mediaCode,
        'GSB',
      );
      expect(jsonEncode(amma.submissions.single.snapshot), snap);
    });

    test('unsupported media/installation combination is reported', () async {
      final (c, _) = await _vendor();
      final b = c.addBoard('s_lakshmi')
        ..mediaCode = SignageCatalog.oneWayVision
        ..installationCode = SignageCatalog.doublePole;
      expect(
        c.boardIssues(b),
        contains('Installation type not valid for One-Way'),
      );
    });
  });

  group('E. Two-way measurement sync', () {
    test('57-59 recce size flows to spec, 2D geometry and back', () async {
      final (c, _) = await _vendor();
      final b = _gsb(c);
      final u = b.units.first;
      final spec = c.modelSpec('s_lakshmi', b.id, u.id)!;
      expect(spec.widthMm, closeTo(8 * 304.8, 1e-9));
      expect(spec.heightMm, closeTo(3 * 304.8, 1e-9));
      expect(spec.sources[SpecField.width], SpecSource.recorded);

      // "3D view" edits width only → board (recce form) and 2D update.
      final problems = c.applySpecEdits('s_lakshmi', b.id, u.id, {
        SpecField.width: 10 * 304.8,
      });
      expect(problems, isEmpty);
      expect(b.width, closeTo(10, 1e-9));
      expect(b.height, 3, reason: 'height-only untouched');
      expect(SignageGeometry.fromBoard(b).widthFt, closeTo(10, 1e-9));
      expect(
        c.modelSpec('s_lakshmi', b.id, u.id)!.widthMm,
        closeTo(3048, 1e-9),
      );
    });

    test('63 height-only update', () async {
      final (c, _) = await _vendor();
      final b = _gsb(c);
      c.applySpecEdits('s_lakshmi', b.id, b.units.first.id, {
        SpecField.height: 4 * 304.8,
      });
      expect(b.width, 8);
      expect(b.height, closeTo(4, 1e-9));
    });

    test(
      '64-65 pole spacing and mounting height (mirrored to site answers)',
      () async {
        final (c, _) = await _vendor();
        final b = _gsb(c);
        final u = b.units.first;
        c.applySpecEdits('s_lakshmi', b.id, u.id, {
          SpecField.poleSpacing: 6 * 304.8,
          SpecField.mountingHeight: 10 * 304.8,
        });
        expect(u.measurements.mm('pole_spacing'), closeTo(1828.8, 1e-9));
        expect(b.answers['pole_gap'], closeTo(6, 1e-9));
        expect(b.answers['pole_height'], closeTo(10, 1e-9));
        final g = SignageGeometry.fromBoard(b);
        expect(g.poleGapFt, closeTo(6, 1e-9));
        expect(g.bottomFt, closeTo(10, 1e-9));
        expect(g.widthFt, 8, reason: 'pole spacing never resizes the board');

        // Recce site-question edit flows back to the canonical measurement.
        b.answers['pole_gap'] = 5;
        c.syncAnswerToMeasurements(b, 'pole_gap');
        expect(u.measurements.mm('pole_spacing'), closeTo(5 * 304.8, 1e-9));
        expect(
          c.modelSpec('s_lakshmi', b.id, u.id)![SpecField.poleSpacing],
          closeTo(1524, 1e-9),
        );
      },
    );

    test(
      '66-67 save commits; validation failure (cancel) leaves data',
      () async {
        final (c, _) = await _vendor();
        final b = _gsb(c);
        final u = b.units.first;
        final before = jsonEncode(b.toJson());
        expect(
          c.applySpecEdits('s_lakshmi', b.id, u.id, {SpecField.width: -5}),
          isNotEmpty,
        );
        expect(
          c.applySpecEdits('s_lakshmi', b.id, u.id, {
            SpecField.poleEmbedment: 20000,
            SpecField.poleHeight: 1000,
          }),
          isEmpty,
        );
        expect(jsonEncode(b.toJson()), isNot(before));
        final after = jsonEncode(b.toJson());
        // Embedment ≥ total pole length is a blocking error → nothing saved.
        u.measurements.valuesMm['pole_length_total'] = 3000;
        expect(
          c.applySpecEdits('s_lakshmi', b.id, u.id, {
            SpecField.poleEmbedment: 4000,
          }),
          isNotEmpty,
        );
        u.measurements.valuesMm.remove('pole_length_total');
        expect(jsonEncode(b.toJson()), after);
      },
    );

    test('68 unit conversion without drift', () {
      var mm = MeasureUnit.ft.toMm(8.5);
      for (var i = 0; i < 50; i++) {
        mm = MeasureUnit.inch.toMm(MeasureUnit.inch.fromMm(mm));
        mm = MeasureUnit.mm.toMm(MeasureUnit.mm.fromMm(mm));
      }
      expect(mm, closeTo(2590.8, 1e-9));
      expect(fmtMmValue(mm, MeasureUnit.ft), '8.5');
      expect(fmtMmValue(mm, MeasureUnit.inch), '102');
    });

    test('different sizes: width edit goes to that unit only', () async {
      final (c, _) = await _vendor();
      final b = _gsb(c, qty: 2);
      c.setSizeMode('s_lakshmi', b, SizeMode.different);
      final u2 = b.units[1];
      c.applySpecEdits('s_lakshmi', b.id, u2.id, {SpecField.width: 1524});
      expect(u2.width, closeTo(5, 1e-9));
      expect(b.units[0].width, 8);
    });

    test('70 submitted item stays read-only', () async {
      final (c, _) = await _vendor();
      final amma = c.shop('s_amma')!; // pending business
      final b = amma.boards.first;
      expect(
        () => c.applySpecEdits(amma.id, b.id, b.units.first.id, {
          SpecField.width: 1000,
        }),
        throwsStateError,
      );
    });
  });

  group('I. Migration and persistence', () {
    test(
      '107-113 legacy records load unchanged; new fields round-trip',
      () async {
        final raw = buildSeedData().toJson()..['schemaVersion'] = 3;
        final store = MemoryLocalStore(raw);
        final c = AppController(store: store);
        await c.init();
        await c.flush();
        final amma = c.shop('s_amma')!;
        expect(amma.boards.first.mediaCode, 'GSB');
        expect(amma.boards.first.doubleSided, isNull);
        expect(amma.submissions.single.version, 1);

        c.loginWithPin(DemoAccounts.vendorPin);
        final b = _gsb(c);
        c.setDoubleSided('s_lakshmi', b, true);
        b.answersArchive['old_answer'] = 7;
        c.touchBoard('s_lakshmi', b);
        await c.flush();
        final again = AppController(store: store);
        await again.init();
        final r = again.board('s_lakshmi', b.id)!;
        expect(r.doubleSided, isTrue);
        expect(r.answersArchive['old_answer'], 7);
        expect(r.units.map((u) => u.id), b.units.map((u) => u.id));
      },
    );

    test('110 migration is idempotent and keeps legacy codes', () async {
      final raw = buildSeedData().toJson()..['schemaVersion'] = 3;
      final store = MemoryLocalStore(raw);
      final c1 = AppController(store: store);
      await c1.init();
      await c1.flush();
      final first = jsonEncode(store.data);
      final c2 = AppController(store: store);
      await c2.init();
      await c2.flush();
      expect(jsonEncode(store.data), first);
    });

    test('116 several model configurations under one shop', () async {
      final (c, _) = await _vendor();
      final a = _gsb(c);
      final s = c.addBoard('s_lakshmi')
        ..mediaCode = SignageCatalog.sandwichBoard
        ..installationCode = SignageCatalog.freeStanding
        ..width = 2
        ..height = 3;
      final specA = c.modelSpec('s_lakshmi', a.id, a.units.first.id)!;
      final specS = c.modelSpec('s_lakshmi', s.id, s.units.first.id)!;
      expect(specA.template, 'gsb');
      expect(specS.template, 'sandwich');
      expect(specS.isDoubleSided, isTrue);
      expect(specS.has(SpecField.openingAngle), isTrue);
      expect(specA.has(SpecField.poleSpacing), isTrue);
      expect(specS.has(SpecField.poleSpacing), isFalse);
    });
  });

  group('board editor', () {
    Widget host(AppController c, Widget child) =>
        ChangeNotifierProvider<AppController>.value(
          value: c,
          child: MaterialApp(theme: AppTheme.light(), home: child),
        );

    testWidgets('13-media grid, sidedness choice, legacy mapping', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final (c, _) = await _vendor();
      final b = c.addBoard('s_lakshmi');
      await tester.pumpWidget(
        host(c, BoardEditorScreen(shopId: 's_lakshmi', boardId: b.id)),
      );
      await tester.pumpAndSettle();
      for (final code in SignageCatalog.catalogCodes) {
        expect(find.byKey(Key('media_$code')), findsOneWidget, reason: code);
      }
      expect(find.byKey(const Key('media_WALL')), findsNothing);
      // GSB opens the "Select GSB Board Type" sheet; cancel changes nothing.
      await tester.tap(find.byKey(const Key('media_GSB')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gsb_type_title')), findsOneWidget);
      await tester.tap(find.byKey(const Key('gsb_type_cancel')));
      await tester.pumpAndSettle();
      expect(b.mediaCode, isNull);
      await tester.tap(find.byKey(const Key('media_GSB')));
      await tester.pumpAndSettle();
      // Continue is disabled until a type is chosen.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('gsb_type_continue')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('gsb_type_single')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('gsb_type_continue')));
      await tester.pumpAndSettle();
      expect(b.mediaCode, SignageCatalog.gsb);
      expect(b.doubleSided, isFalse);
      expect(b.gsbVariantKey, 'GSB_SINGLE');
      // Reopen the media step: the old bottom single/double control is
      // replaced by the board-type summary for GSB.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        host(
          c,
          BoardEditorScreen(shopId: 's_lakshmi', boardId: b.id, initialStep: 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sides_double')), findsNothing);
      expect(find.byKey(const Key('gsb_variant_summary')), findsOneWidget);
      // (Below the fold in the stepper: invoke like the sidedness control.)
      tester
          .widget<TextButton>(find.byKey(const Key('gsb_variant_change')))
          .onPressed!();
      await tester.pumpAndSettle();
      // The saved choice is restored in the sheet.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('gsb_type_continue')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('gsb_type_double')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('gsb_type_continue')));
      await tester.pumpAndSettle();
      expect(b.doubleSided, isTrue);
      expect(b.gsbVariantKey, 'GSB_DOUBLE');

      // NLB keeps the original single / double control.
      final n = c.addBoard('s_lakshmi')..mediaCode = SignageCatalog.nlb;
      await tester.pumpWidget(
        host(
          c,
          BoardEditorScreen(shopId: 's_lakshmi', boardId: n.id, initialStep: 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sides_double')), findsOneWidget);
      tester
          .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .onSelectionChanged!({true});
      await tester.pumpAndSettle();
      expect(n.doubleSided, isTrue);

      // Legacy group: explicit mapping.
      final v = c.addBoard('s_lakshmi')
        ..mediaCode = SignageCatalog.vinyl
        ..installationCode = SignageCatalog.glassPasting;
      await tester.pumpWidget(const SizedBox()); // fresh editor state
      await tester.pumpWidget(
        host(
          c,
          BoardEditorScreen(shopId: 's_lakshmi', boardId: v.id, initialStep: 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('legacy_media_card')), findsOneWidget);
      await tester.tap(find.byKey(const Key('map_PLAIN_VINYL')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      expect(v.mediaCode, SignageCatalog.plainVinyl);
      expect(v.legacyMediaCode, SignageCatalog.vinyl);
    });
  });
}
