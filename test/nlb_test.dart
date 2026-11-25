import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/features/nlb/nlb_presentation.dart';
import 'package:signage_recce/features/nlb/nlb_rules.dart';
import 'package:signage_recce/features/preview3d/renderer_painter.dart';
import 'package:signage_recce/features/preview3d/scene3d.dart';
import 'package:signage_recce/features/preview3d/signage_scene_builder.dart';
import 'package:signage_recce/features/model3d/parametric_builder.dart';
import 'package:signage_recce/features/model3d/signage_spec.dart';
import 'package:signage_recce/features/preview_live/live_preview_controller.dart';
import 'package:signage_recce/state/app_controller.dart';

List<double>? _bays(double ft) => NlbRules.bays(ft * 12);

Board _nlb(double w, double h, {String? subtype}) {
  final b = Board(
    id: 'n',
    name: 'N',
    mediaCode: SignageCatalog.nlb,
    installationCode: SignageCatalog.shopFascia,
    width: w,
    height: h,
    nlbSubtype: subtype,
    doubleSided: subtype == 'NLB_BOX_FRAME' ? true : null,
  );
  b.photos.add(
    SitePhoto(
      id: 'ph',
      path: 'demo://2',
      label: 'p',
      capturedAt: DateTime(2026),
      width: 1200,
      height: 900,
    ),
  );
  return b;
}

void main() {
  group('NON_LIT vertical bays (rulebook section 07)', () {
    test('approved examples', () {
      expect(_bays(6), [24, 24, 24]);
      expect(_bays(8), [24, 24, 24, 24]);
      expect(_bays(10), [30, 30, 30, 30]);
      expect(_bays(13), [24, 27, 27, 27, 27, 24]);
      final b15 = _bays(15)!;
      expect(b15.length, 7);
      expect(b15.first, 24);
      expect(b15.last, 24);
      for (final x in b15.sublist(1, 6)) {
        expect(x, closeTo(26.4, 1e-9));
      }
      final b16 = _bays(16)!;
      expect(b16, hasLength(7));
      for (final x in b16) {
        expect(x, closeTo(192 / 7, 1e-9));
      }
    });

    test('every layout sums to the width and respects the 30-in maximum', () {
      for (var ft = 2; ft <= 40; ft++) {
        final b = _bays(ft.toDouble());
        if (b == null) {
          expect(ft.isOdd && ft < 5, isTrue, reason: '$ft ft');
          continue;
        }
        expect(b.fold<double>(0, (s, x) => s + x), closeTo(ft * 12, 1e-9));
        expect(b.every((x) => x <= 30 + 1e-9), isTrue, reason: '$ft ft');
      }
    });

    test('fractional width is never invented', () {
      expect(NlbRules.bays(102), isNull);
      final p = NlbRules.plan(
        variant: NlbVariant.singleFrame,
        widthIn: 102,
        heightIn: 36,
      );
      expect(p.hasIssue('NL_BAY_REVIEW'), isTrue);
    });

    test('horizontal and module rules need review, not invention', () {
      final tall = NlbRules.plan(
        variant: NlbVariant.singleFrame,
        widthIn: 180,
        heightIn: 84,
      );
      expect(tall.hasIssue('NL_HORIZONTAL_REVIEW'), isTrue);
      expect(tall.hasIssue('NL_MODULE_REVIEW'), isTrue);
      final small = NlbRules.plan(
        variant: NlbVariant.singleFrame,
        widthIn: 96,
        heightIn: 36,
      );
      expect(small.hasIssue('NL_HORIZONTAL_REVIEW'), isFalse);
      expect(small.hasIssue('NL_MODULE_REVIEW'), isFalse);
      expect(small.supportStationsIn, [24, 48, 72]);
    });
  });

  group('NON_LIT_BOX (rulebook section 08)', () {
    test('connector stations on the width and height axes', () {
      expect(NlbRules.connectorStations(60), [30]); // 5 ft
      expect(NlbRules.connectorStations(36), [18]); // 3 ft
      expect(NlbRules.connectorStations(96), [48]); // 8 ft: one
      final ten = NlbRules.connectorStations(120);
      expect(ten, hasLength(2));
      expect(ten[0], closeTo(40, 1e-9));
      expect(ten[1], closeTo(80, 1e-9));
      expect(NlbRules.connectorStations(12), isEmpty);
      final p = NlbRules.plan(
        variant: NlbVariant.boxFrame,
        widthIn: 60,
        heightIn: 36,
      );
      expect(p.widthConnectorsIn, [30]);
      expect(p.heightConnectorsIn, [18]);
      expect(p.depthIn, 4);
    });

    test('connector cut comes from contact geometry, never the 4-in depth', () {
      final p = NlbRules.plan(
        variant: NlbVariant.boxFrame,
        widthIn: 96,
        heightIn: 36,
      );
      expect(p.connectorCutIn, isNull);
      expect(p.hasIssue('BOX_CONNECTOR_REVIEW'), isTrue);
      expect(p.hasIssue('BOX_TOP_JOINT_REVIEW'), isTrue);
      expect(NlbRules.connectorCutIn(4, 2), isNull); // 2 x 2 leaves no span
      expect(NlbRules.connectorCutIn(4, 1), 2);
      expect(NlbRules.connectorCutIn(4, null), isNull);
    });

    test('variant keys map to the rulebook board types', () {
      expect(NlbVariant.singleFrame.rulebookKey, 'NON_LIT');
      expect(NlbVariant.boxFrame.rulebookKey, 'NON_LIT_BOX');
      expect(NlbVariantX.fromKey('NLB_BOX_FRAME'), NlbVariant.boxFrame);
      expect(NlbVariantX.fromKey('x'), isNull);
    });
  });

  group('NLB Box finished board', () {
    List<Face> all(List<Solid> s) => [
      for (final x in s) ...x.faces,
      for (final x in s) ...x.decals,
    ];

    test('six covered faces, printed front and rear, no GSB parts', () {
      for (final (w, h) in [(5.0, 3.0), (8.0, 3.0), (10.0, 5.0)]) {
        final s = NlbBoxBoard.build(
          NlbBoxPresentation(
            widthFt: w,
            heightFt: h,
            depthFt: 4 / 12,
            bottomFt: 6.5,
            brand: 'SAKTHI MASALA',
          ),
        );
        final body = s.first;
        expect(body.faces, hasLength(6));
        final zs = [
          for (final f in body.faces)
            for (final p in f.points) p.z,
        ];
        expect(zs.reduce((a, b) => a < b ? a : b), closeTo(-4 / 12, 1e-9));
        // Only body + front print + rear print: no pipes, bulbs or bolts.
        expect(s, hasLength(3));
        final faces = all(s);
        expect(faces.where((f) => f.label != null), hasLength(2));
        expect(faces.any((f) => f.emissive), isFalse); // not lit
        expect(body.decals, isEmpty); // no screws, no powder coat strips
        // Rear print faces backwards with a non-mirrored label.
        final rear = s.last.faces.single;
        expect(rear.normal, const Vec3(0, 0, -1));
        expect(rear.points[0].x, greaterThan(rear.points[1].x));
        expect(rear.points[0].y, greaterThan(rear.points[3].y));
        // Not the GSB blue powder coat.
        expect(
          body.faces.every((f) => f.color.b * 255 < 250 || f.color.r > 0.9),
          isTrue,
        );
        for (final f in body.faces) {
          expect(f.color.r, greaterThan(0.85)); // white flex, not blue
        }
      }
    });
  });

  group('NLB model wiring', () {
    test('subtype storage is additive and legacy-safe', () {
      final legacy = _nlb(6, 3);
      expect(legacy.nlbSubtype, isNull);
      expect(legacy.toJson().containsKey('nlbSubtype'), isFalse);
      final box = _nlb(6, 3, subtype: 'NLB_BOX_FRAME');
      final back = Board.fromJson(box.toJson());
      expect(back.nlbSubtype, 'NLB_BOX_FRAME');
      expect(back.isNlbBoxFrame, isTrue);
      expect(back.mediaCode, SignageCatalog.nlb); // category unchanged
      expect(
        Board.fromJson({
          'id': 'x',
          'name': 'x',
          'mediaCode': 'NLB',
          'nlbSubtype': 'bogus',
        }).nlbSubtype,
        isNull,
      );
      // GSB is untouched.
      final gsb = Board(
        id: 'g',
        name: 'g',
        mediaCode: 'GSB',
        doubleSided: true,
      );
      expect(gsb.gsbVariantKey, 'GSB_DOUBLE');
      expect(gsb.isNlb, isFalse);
    });

    test('box frame: 4-in depth and rear print in every view builder', () {
      final b = _nlb(6, 3, subtype: 'NLB_BOX_FRAME');
      final u = b.units.first;
      final g = unitGeometry(b, u);
      expect(g.nlbBoxFrame, isTrue);
      expect(g.depthFt, closeTo(4 / 12, 1e-9));
      final live = SignageSceneBuilder.buildModel(g, brand: 'X');
      expect(live.solids.where((s) => s.name == 'board'), hasLength(1));
      expect(
        [for (final s in live.solids) ...s.faces].where((f) => f.label != null),
        hasLength(2),
      );
      final spec = SignageModelSpec.of(b, u);
      expect(spec.nlbBoxFrame, isTrue);
      expect(spec.depthMm, closeTo(4 * 25.4, 1e-9));
      final model = ParametricModelBuilder.build(spec, context: false);
      final labelled = [
        for (final s in model.scene.solids) ...s.faces,
      ].where((f) => f.label != null);
      expect(labelled, hasLength(2));
      expect(
        [for (final s in model.scene.solids) ...s.faces].any((f) => f.emissive),
        isFalse,
      );
    });

    test('legacy NLB (no subtype) keeps the previous rendering', () {
      final b = _nlb(6, 3);
      final g = unitGeometry(b, b.units.first);
      expect(g.nlbBoxFrame, isFalse);
      expect(g.nlbSingleFrame, isFalse);
      expect(g.depthFt, closeTo(0.25, 1e-9)); // previous catalog depth
      final live = SignageSceneBuilder.buildModel(g, brand: 'X');
      final labelled = [
        for (final s in live.solids) ...s.faces,
      ].where((f) => f.label != null);
      expect(labelled, hasLength(1)); // front only
    });

    test(
      'NLB Single Frame shows perimeter + vertical pipes (all builders)',
      () {
        for (final (wFt, bays) in [(6.0, 3), (8.0, 4), (10.0, 4), (13.0, 6)]) {
          final b = _nlb(wFt, 3, subtype: 'NLB_SINGLE_FRAME');
          final u = b.units.first;
          final g = unitGeometry(b, u);
          expect(g.nlbSingleFrame, isTrue);
          expect(g.depthFt, closeTo(1 / 12, 1e-9)); // slim single plane
          final live = SignageSceneBuilder.buildModel(g, brand: 'X');
          // 4 perimeter pipes + (bays - 1) vertical supports + backing.
          final pipes = live.solids.where((s) => s.name == 'board');
          expect(pipes, hasLength(4 + bays - 1), reason: '$wFt ft');
          final model = ParametricModelBuilder.build(
            SignageModelSpec.of(b, u),
            context: false,
          );
          expect(
            model.scene.solids.where((s) => s.name.startsWith('frame')),
            hasLength(4 + bays - 1),
          );
          // Not the GSB box: no depth beyond the pipe section, no emission.
          final faces = [for (final s in model.scene.solids) ...s.faces];
          expect(faces.any((f) => f.emissive), isFalse);
          // Only the frame itself (not wall brackets of the installation).
          final zs = [
            for (final s in model.scene.solids)
              if (s.name.startsWith('frame') || s.name.startsWith('front_face'))
                for (final f in s.faces)
                  for (final p in f.points) p.z,
          ];
          expect(zs.reduce((a, c) => a < c ? a : c), greaterThan(-0.09));
        }
      },
    );

    test('Live Preview shows only board width / height (GSB and NLB)', () {
      for (final media in [SignageCatalog.gsb, SignageCatalog.nlb]) {
        final b = _nlb(6, 3)..mediaCode = media;
        final c = LivePreviewController(board: b, photo: b.photos.first)
          ..addUnit('n_u1');
        final dims = c.sceneFor(c.selected!).dims;
        expect(dims.map((d) => d.label), ['W 6 ft', 'H 3 ft'], reason: media);
        // The recce data keeps its mounting / clearance values.
        expect(b.installationCode, SignageCatalog.shopFascia);
      }
      // Other media keep their dimension set (not in scope).
      final acp = _nlb(6, 3)..mediaCode = SignageCatalog.acp;
      final c = LivePreviewController(board: acp, photo: acp.photos.first)
        ..addUnit('n_u1');
      expect(c.sceneFor(c.selected!).dims.length, greaterThanOrEqualTo(2));
    });
  });

  group('NLB selection sheet', () {
    Widget host(AppController c, Widget child) =>
        ChangeNotifierProvider<AppController>.value(
          value: c,
          child: MaterialApp(theme: AppTheme.light(), home: child),
        );

    testWidgets('NLB asks for the frame type; cancel changes nothing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final c = AppController(store: MemoryLocalStore());
      await c.init();
      c.loginWithPin('5678');
      final b = c.addBoard('s_lakshmi');
      await tester.pumpWidget(
        host(c, BoardEditorScreen(shopId: 's_lakshmi', boardId: b.id)),
      );
      await tester.pumpAndSettle();

      // Board Details opens first; move to the media catalog.
      await tester.scrollUntilVisible(
        find.byKey(const Key('step_next_0')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('step_next_0')));
      await tester.pumpAndSettle();
      tester
          .widget<InkWell>(find.byKey(const Key('media_NLB')))
          .onTap!();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nlb_type_title')), findsOneWidget);
      expect(find.text('Select NLB Board Type'), findsOneWidget);
      // Compact cards: name only, no description bullets.
      // (Scoped to the sheet: the editor behind it shows '•' summaries.)
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.byKey(const Key('nlb_type_title')),
            matching: find.byType(Column),
          ).first,
          matching: find.textContaining('•'),
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('nlb_type_continue')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('nlb_type_cancel')));
      await tester.pumpAndSettle();
      expect(b.mediaCode, isNull);

      tester
          .widget<InkWell>(find.byKey(const Key('media_NLB')))
          .onTap!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nlb_type_box')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('nlb_type_continue')));
      await tester.pumpAndSettle();
      expect(b.mediaCode, SignageCatalog.nlb);
      expect(b.nlbSubtype, 'NLB_BOX_FRAME');
      expect(b.doubleSided, isTrue);

      // Switch subtype; GSB remains unaffected.
      c.setNlbSubtype('s_lakshmi', b, 'NLB_SINGLE_FRAME');
      expect(b.nlbSubtype, 'NLB_SINGLE_FRAME');
      expect(b.doubleSided, isFalse);
      expect(b.gsbVariantKey, isNull);
    });
  });

  group('NLB Single Frame — flex in front, steel behind', () {
    const ft = NlbSinglePresentation.flexThicknessFt;
    const preset = NlbSinglePresentation(
      widthFt: 6,
      heightFt: 3,
      bottomFt: 6.5,
      profileIn: 1,
      brand: 'SAKTHI MASALA',
    );

    test('one continuous full-size flex with a plain reverse surface', () {
      final solids = NlbSingleBoard.build(preset);
      final flex = solids.singleWhere((s) => s.name == 'nlb_backing');
      // A thin sheet has front + reverse + four wrap edges; only the front
      // face is printed. It is never split into panels between the pipes.
      expect(flex.faces, hasLength(6));
      final printed = flex.faces.where((f) => f.label != null).toList();
      expect(printed, hasLength(1));
      expect(printed.single.normal, const Vec3(0, 0, 1));
      expect(printed.single.label, 'SAKTHI MASALA');
      final reverse = flex.faces.where((f) => f.normal == const Vec3(0, 0, -1));
      expect(reverse, hasLength(1));
      expect(reverse.single.label, isNull); // no mirrored rear advertising
      expect(reverse.single.points.every((p) => (p.z - -ft).abs() < 1e-9), isTrue);

      for (final face in [printed.single, reverse.single]) {
        final xs = face.points.map((p) => p.x).toList();
        final ys = face.points.map((p) => p.y).toList();
        expect(xs.reduce((a, c) => a < c ? a : c), closeTo(-3, 1e-9));
        expect(xs.reduce((a, c) => a > c ? a : c), closeTo(3, 1e-9));
        expect(ys.reduce((a, c) => a < c ? a : c), closeTo(6.5, 1e-9));
        expect(ys.reduce((a, c) => a > c ? a : c), closeTo(9.5, 1e-9));
      }
      expect(printed.single.points.every((p) => p.z == 0), isTrue);
    });

    test('all steel is behind the flex, with open bays at the rear', () {
      final solids = NlbSingleBoard.build(preset);
      final frame = solids.where((s) => s.name == 'board').toList();
      final flex = solids.singleWhere((s) => s.name == 'nlb_backing');
      expect(frame, hasLength(6)); // 4 perimeter + 2 internal supports (6 ft)
      final ft = NlbSinglePresentation.flexThicknessFt;
      for (final s in frame) {
        final zs = [for (final f in s.faces) for (final p in f.points) p.z];
        final front = zs.reduce((a, c) => a > c ? a : c);
        final back = zs.reduce((a, c) => a < c ? a : c);
        expect(front, closeTo(-ft, 1e-9), reason: s.name);
        expect(back, closeTo(-ft - 1 / 12, 1e-9), reason: s.name);
        // Every pipe has a rear-facing surface that can be inspected.
        expect(s.faces.any((f) => f.normal == const Vec3(0, 0, -1)), isTrue);
      }
      final flexZ = [
        for (final f in flex.faces) for (final p in f.points) p.z,
      ];
      expect(flexZ.reduce((a, c) => a > c ? a : c), 0);
      // No artificial solid dark backing board behind the frame.
      for (final s in frame) {
        final xs = [for (final f in s.faces) for (final p in f.points) p.x];
        final ys = [for (final f in s.faces) for (final p in f.points) p.y];
        final fullWidth =
            (xs.reduce((a, c) => a < c ? a : c) - 3).abs() < 1e-9 &&
            (xs.reduce((a, c) => a > c ? a : c) - 3).abs() < 1e-9;
        final fullHeight =
            (ys.reduce((a, c) => a < c ? a : c) - 6.5).abs() < 1e-9 &&
            (ys.reduce((a, c) => a > c ? a : c) - 9.5).abs() < 1e-9;
        expect(fullWidth && fullHeight, isFalse, reason: 'solid rear panel');
      }
      // Approved 24 + 24 + 24 bays → internal supports at x = ±1 ft.
      final supports = frame
          .where(
            (s) =>
                (s.centroid.x - -1).abs() < 1e-9 ||
                (s.centroid.x - 1).abs() < 1e-9,
          )
          .toList();
      expect(supports, hasLength(2));
    });

    test('shared geometry in live preview, isometric and parametric model', () {
      final b = _nlb(6, 3, subtype: 'NLB_SINGLE_FRAME');
      final u = b.units.first;
      final g = unitGeometry(b, u);
      final live = SignageSceneBuilder.buildModel(g, brand: 'X');
      final liveFlex = live.solids.singleWhere((s) => s.name == 'nlb_backing');
      expect(
        liveFlex.faces.any(
          (f) =>
              f.normal == const Vec3(0, 0, 1) &&
              f.label == 'X' &&
              f.points.every((p) => p.z == 0),
        ),
        isTrue,
      );
      expect(
        liveFlex.faces.any(
          (f) =>
              f.normal == const Vec3(0, 0, -1) &&
              f.points.every((p) => (p.z + ft).abs() < 1e-9),
        ),
        isTrue,
      );
      final model = ParametricModelBuilder.build(
        SignageModelSpec.of(b, u),
        context: false,
      );
      final modelFlex = model.scene.solids.singleWhere(
        (s) => s.name.startsWith('front_face'),
      );
      expect(
        modelFlex.faces.any(
          (f) =>
              f.normal == const Vec3(0, 0, 1) &&
              f.points.every((p) => p.z == 0),
        ),
        isTrue,
      );
      expect(
        modelFlex.faces.any(
          (f) =>
              f.normal == const Vec3(0, 0, -1) &&
              f.points.every((p) => (p.z + ft).abs() < 1e-9),
        ),
        isTrue,
      );
      // Saved / reopened board data still resolves to the same subtype and
      // therefore the same physical layering.
      final reopened = Board.fromJson(b.toJson());
      final g2 = unitGeometry(reopened, reopened.units.first);
      expect(g2.nlbSingleFrame, isTrue);
      final scene2 = SignageSceneBuilder.buildModel(g2, brand: 'X');
      expect(
        scene2.solids.singleWhere((s) => s.name == 'nlb_backing').faces.length,
        6,
      );
    });
  });

  group('NLB Single Frame — full turn visibility', () {
    ViewProjector projector(Scene scene, double degrees, {double factor = 2.8}) =>
        ViewProjector(
          camera: Camera3D(yaw: degrees * math.pi / 180),
          size: const Size(800, 600),
          target: scene.focus,
          radius: scene.radius,
          distanceFactor: factor,
        );

    bool visible(ViewProjector p, Face f) =>
        p.facesCamera(f.normal, p.toView(f.centroid));

    test('0 / 45 / 90 / 130 / 180 / 270 / 360 degrees', () {
      final solids = NlbSingleBoard.build(
        const NlbSinglePresentation(widthFt: 6, heightFt: 3),
      );
      final scene = Scene(focus: const Vec3(0, 1.5, -0.04))
        ..solids.addAll(solids)
        ..finalize();
      final flex = solids.singleWhere((s) => s.name == 'nlb_backing');
      final frame = solids.where((s) => s.name == 'board').toList();
      final front = flex.faces.singleWhere((f) => f.label != null);
      final rear = flex.faces.singleWhere((f) => f.normal.z < -0.5);

      for (final factor in const [2.8, 4.0]) {
        for (final (deg, expectFront, expectRear) in const [
          (0.0, true, false),
          (45.0, true, false),
          (90.0, null, null), // edge-on: only a sliver of one sheet side
          (130.0, false, true),
          (180.0, false, true),
          (270.0, null, null), // opposite edge-on profile
          (360.0, true, false),
        ]) {
          final p = projector(scene, deg, factor: factor);
          if (expectFront != null) {
            expect(visible(p, front), expectFront, reason: '$deg° front');
          }
          if (expectRear != null) {
            expect(visible(p, rear), expectRear, reason: '$deg° flex reverse');
          }
          if (deg == 90 || deg == 270) {
            // A true side profile: the frame's side walls, not the print,
            // carry the silhouette at both side angles.
            expect(
              frame.any(
                (s) => s.faces.any(
                  (f) => f.normal.x.abs() > 0.5 && visible(p, f),
                ),
              ),
              isTrue,
              reason: '$deg° side profile',
            );
          }
          // A single assembly is reused: no angle swaps in another model.
          expect(scene.solids, hasLength(solids.length));
          final order = Scene3DPainter.orderSolids(scene.solids, p);
          final flexAt = order.indexOf(flex);
          final frameAt = [for (final s in frame) order.indexOf(s)];
          if (deg == 0 || deg == 45 || deg == 360) {
            expect(
              frameAt.every((i) => flexAt > i),
              isTrue,
              reason: '$deg° flex must cover the pipes',
            );
          } else if (deg == 130 || deg == 180) {
            expect(
              frameAt.every((i) => flexAt < i),
              isTrue,
              reason: '$deg° pipes must be inspectable from the rear',
            );
            for (final s in frame) {
              expect(
                s.faces.any(
                  (f) =>
                      f.normal == const Vec3(0, 0, -1) && visible(p, f),
                ),
                isTrue,
                reason: '$deg° pipe rear face',
              );
            }
          }
        }
      }
    });

    test('rear render shows dark pipes over the unprinted flex, no black bay', () async {
      const size = Size(600, 400);
      const ft = NlbSinglePresentation.flexThicknessFt;
      final solids = NlbSingleBoard.build(
        const NlbSinglePresentation(widthFt: 6, heightFt: 3),
      );
      final scene = Scene(focus: Vec3(0, 1.5, -(ft + 1 / 12) / 2))
        ..solids.addAll(solids)
        ..finalize();

      late Uint8List bytes;
      Color pixelAt(Camera3D camera, Vec3 world) {
        final proj = ViewProjector(
          camera: camera,
          size: size,
          target: scene.focus,
          radius: scene.radius,
        );
        final o = proj.project(world)!;
        final x = o.dx.round().clamp(0, size.width.toInt() - 1);
        final y = o.dy.round().clamp(0, size.height.toInt() - 1);
        final i = (y * size.width.toInt() + x) * 4;
        return Color.fromARGB(
          bytes[i + 3],
          bytes[i],
          bytes[i + 1],
          bytes[i + 2],
        );
      }

      Future<void> render(Camera3D camera) async {
        final recorder = ui.PictureRecorder();
        Scene3DPainter(
          scene: scene,
          camera: camera,
          showDimensions: false,
          paintBackground: false,
          paintGround: false,
          paintGizmo: false,
        ).paint(Canvas(recorder), size);
        final image = await recorder.endRecording().toImage(
          size.width.toInt(),
          size.height.toInt(),
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        bytes = data!.buffer.asUint8List();
        image.dispose();
      }

      // Rear: a bay is the flex reverse (not a hole / black panel), while a
      // support station reads as dark steel in front of that same sheet.
      await render(const Camera3D(yaw: math.pi, ortho: true));
      final bay = pixelAt(const Camera3D(yaw: math.pi, ortho: true),
          const Vec3(-2, 1.5, -ft));
      final pipe = pixelAt(const Camera3D(yaw: math.pi, ortho: true),
          const Vec3(-1, 1.5, -ft - 1 / 12));
      expect(bay.r * 255, greaterThan(55), reason: 'bay shows flex reverse');
      expect(pipe.r * 255, lessThan(55), reason: 'rear pipe is dark steel');

      // Front: no internal pipe interrupts the printed surface.
      await render(const Camera3D(yaw: 0, ortho: true));
      final print = pixelAt(
        const Camera3D(yaw: 0, ortho: true),
        const Vec3(-1, 1.32, 0),
      );
      expect(print.r * 255, greaterThan(55), reason: 'print is not covered');
    });

    test('360 degrees projects identically to 0 degrees', () {
      final scene = Scene(focus: Vec3.zero)
        ..solids.addAll(
          NlbSingleBoard.build(
            const NlbSinglePresentation(widthFt: 6, heightFt: 3),
          ),
        )
        ..finalize();
      final a = projector(scene, 0);
      final b = projector(scene, 360);
      final point = const Vec3(1, 1, -0.04);
      final pa = a.project(point)!;
      final pb = b.project(point)!;
      expect((pa - pb).distance, lessThan(1e-6));
      expect((a.cameraWorld - b.cameraWorld).length, lessThan(1e-6));
    });
  });
}
