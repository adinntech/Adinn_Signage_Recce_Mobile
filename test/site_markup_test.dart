import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/data/storage/media_storage.dart';
import 'package:signage_recce/features/annotation/annotation_editor_screen.dart';
import 'package:signage_recce/features/survey/feasibility.dart';
import 'package:signage_recce/features/survey/markup_entry.dart';
import 'package:signage_recce/features/survey/perspective_math.dart';
import 'package:signage_recce/features/survey/site_markup_controller.dart';
import 'package:signage_recce/features/survey/site_markup_painter.dart';
import 'package:signage_recce/features/survey/site_markup_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

/// Shop with a GSB group (2 units, photo shared by both) and a standee.
class Fixture {
  Fixture(this.c, this.store, this.shop, this.gsb, this.standee, this.photo);

  final AppController c;
  final MemoryLocalStore store;
  final Shop shop;
  final Board gsb;
  final Board standee;
  final SitePhoto photo;

  static Future<Fixture> create({int width = 1200, int height = 900}) async {
    final store = MemoryLocalStore();
    final c = AppController(store: store);
    await c.init();
    c.loginWithPin(DemoAccounts.vendorPin);
    final shop = c.shop('s_lakshmi')!;
    final gsb = c.addBoard(shop.id)
      ..mediaCode = SignageCatalog.gsb
      ..installationCode = SignageCatalog.shopFascia
      ..width = 8
      ..height = 3;
    c.increaseQuantity(shop.id, gsb, 2);
    final standee = c.addBoard(shop.id)
      ..mediaCode = SignageCatalog.doubleStandee
      ..installationCode = SignageCatalog.freeStanding
      ..width = 2
      ..height = 5;
    final photo = SitePhoto(
      id: 'ph_front',
      path: 'demo://3',
      label: 'Main frontage',
      capturedAt: DateTime(2026, 11, 18, 10),
      width: width,
      height: height,
      annotations: [
        Annotation(id: 'a_keep', type: AnnotationType.rectangle, x: 600),
      ],
    );
    c.addPhoto(shop.id, gsb.id, photo);
    return Fixture(c, store, shop, gsb, standee, photo);
  }

  SignageUnit get u1 => gsb.activeUnits[0];
  SignageUnit get u2 => gsb.activeUnits[1];
  SignageUnit get s1 => standee.activeUnits[0];

  SiteMarkupController editor() => SiteMarkupController(
    photoId: photo.id,
    initial: photo.markup,
    imageSize: Size(photo.width.toDouble(), photo.height.toDouble()),
  );

  void save(SiteMarkupController e) =>
      c.saveSiteMarkup(shop.id, gsb.id, photo.id, e.markup);

  Future<AppController> reload() async {
    await c.flush();
    final again = AppController(store: store);
    await again.init();
    return again;
  }
}

List<Offset> px(PerspectivePlacement p, Size s) => [
  for (final c in p.corners) c.toPixels(s),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B. Perspective drawing', () {
    test('21-24 create, move each corner, move whole shape, reset', () async {
      final f = await Fixture.create();
      final e = f.editor();
      final p = e.addPerspective(f.u1.id, centre: const SurveyPoint(0.5, 0.4));
      expect(e.markup.perspectives, hasLength(1));
      expect(p.corners, hasLength(4));
      expect(e.problemOf(p), QuadProblem.none);

      const targets = [
        SurveyPoint(0.20, 0.25),
        SurveyPoint(0.78, 0.30),
        SurveyPoint(0.80, 0.52),
        SurveyPoint(0.22, 0.60),
      ];
      for (var i = 0; i < 4; i++) {
        e.beginGesture();
        e.moveCorner(p.id, i, targets[i]);
        e.endGesture();
      }
      expect(e.perspective(p.id)!.corners, targets);
      expect(e.problems, isEmpty, reason: 'a trapezoid is a valid board');

      e.select(p.id);
      e.beginGesture();
      e.translateSelected(const SurveyPoint(0.05, -0.02));
      e.endGesture();
      final moved = e.perspective(p.id)!.corners;
      for (var i = 0; i < 4; i++) {
        expect(moved[i].x, closeTo(targets[i].x + 0.05, 1e-9));
        expect(moved[i].y, closeTo(targets[i].y - 0.02, 1e-9));
      }

      e.resetCorners(p.id, aspect: 8 / 3);
      final reset = e.perspective(p.id)!;
      final q = px(reset, e.imageSize);
      expect(q[0].dy, closeTo(q[1].dy, 1e-6), reason: 'upright again');
      expect((q[1].dx - q[0].dx) / (q[3].dy - q[0].dy), closeTo(8 / 3, 1e-6));
    });

    test('25 undo / redo groups a whole drag into one step', () async {
      final f = await Fixture.create();
      final e = f.editor();
      final p = e.addPerspective(f.u1.id);
      final before = e.perspective(p.id)!.corners;
      e.beginGesture();
      for (var k = 1; k <= 10; k++) {
        e.moveCorner(p.id, 2, SurveyPoint(0.7 + k * 0.005, 0.5 + k * 0.004));
      }
      e.endGesture();
      final after = e.perspective(p.id)!.corners;
      e.undo();
      expect(e.perspective(p.id)!.corners, before);
      e.redo();
      expect(e.perspective(p.id)!.corners, after);
      e.undo();
      e.undo();
      expect(e.markup.perspectives, isEmpty, reason: 'undo the add');
      expect(e.canUndo, isFalse);
    });

    test(
      '26 + 32 save / reload normalised coordinates; measurements kept',
      () async {
        final f = await Fixture.create();
        final e = f.editor();
        final p = e.addPerspective(f.u1.id);
        e.moveCorner(p.id, 1, const SurveyPoint(0.83, 0.21));
        final corners = e.perspective(p.id)!.corners;
        f.save(e);

        final again = await f.reload();
        final photo = again.photo(f.shop.id, f.gsb.id, f.photo.id)!;
        expect(photo.markup.perspectives.single.corners, corners);
        expect(photo.markup.perspectives.single.unitId, f.u1.id);
        final b = again.board(f.shop.id, f.gsb.id)!;
        expect(b.width, 8, reason: 'corners never change measured width');
        expect(b.height, 3);
        expect(photo.annotations.single.id, 'a_keep');
        final json = jsonEncode(f.store.data);
        expect(json, contains('"perspectives"'));
        expect(corners.every((c) => c.x >= 0 && c.x <= 1), isTrue);
      },
    );

    test('27 portrait and landscape photos map corners identically', () {
      for (final size in const [Size(1200, 900), Size(900, 1600)]) {
        const corners = [
          SurveyPoint(0.1, 0.2),
          SurveyPoint(0.8, 0.25),
          SurveyPoint(0.75, 0.6),
          SurveyPoint(0.15, 0.7),
        ];
        final quad = [for (final c in corners) c.toPixels(size)];
        final h = Homography.unitSquareTo(quad)!;
        const unit = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
        for (var i = 0; i < 4; i++) {
          final m = h.map(unit[i]);
          expect(m.dx, closeTo(quad[i].dx, 1e-6));
          expect(m.dy, closeTo(quad[i].dy, 1e-6));
          final back = SurveyPoint.fromPixels(m, size);
          expect(back.x, closeTo(corners[i].x, 1e-9));
          expect(back.y, closeTo(corners[i].y, 1e-9));
        }
        expect(
          QuadGeometry.validate(quad, size),
          QuadProblem.none,
          reason: '$size',
        );
      }
    });

    test(
      '29-30 self-intersecting and degenerate shapes cannot be saved',
      () async {
        final f = await Fixture.create();
        final e = f.editor();
        final p = e.addPerspective(f.u1.id);
        // Swap TR and BR → bow-tie.
        final c = e.perspective(p.id)!.corners;
        e.moveCorner(p.id, 1, c[2]);
        e.moveCorner(p.id, 2, c[1]);
        expect(e.problems[p.id], QuadProblem.selfIntersecting);
        expect(e.canSave, isFalse);
        expect(e.saveBlockedReason, contains('cross'));

        e.resetCorners(p.id);
        expect(e.canSave, isTrue);
        // Collapse to a sliver.
        final r = e.perspective(p.id)!.corners;
        e.moveCorner(p.id, 2, SurveyPoint(r[1].x, r[1].y + 0.001));
        e.moveCorner(p.id, 3, SurveyPoint(r[0].x, r[0].y + 0.001));
        expect(e.problems[p.id], QuadProblem.tooSmall);

        // Caved-in (concave) and mirrored shapes.
        expect(
          QuadGeometry.validate(const [
            Offset(100, 100),
            Offset(500, 100),
            Offset(300, 150),
            Offset(100, 400),
          ], const Size(1200, 900)),
          QuadProblem.notConvex,
        );
        expect(
          QuadGeometry.validate(const [
            Offset(500, 100),
            Offset(100, 100),
            Offset(100, 400),
            Offset(500, 400),
          ], const Size(1200, 900)),
          QuadProblem.wrongOrder,
        );
        expect(
          QuadGeometry.validate(const [
            Offset(double.nan, 100),
            Offset(500, 100),
            Offset(500, 400),
            Offset(100, 400),
          ], const Size(1200, 900)),
          QuadProblem.notFinite,
        );
        expect(
          QuadGeometry.validate(const [
            Offset(100, 100),
            Offset(5000, 100),
            Offset(500, 400),
            Offset(100, 400),
          ], const Size(1200, 900)),
          QuadProblem.outOfBounds,
        );
      },
    );

    test('31 homography is a true projective map (not a stretch)', () {
      const quad = [
        Offset(100, 120),
        Offset(700, 200),
        Offset(680, 420),
        Offset(120, 520),
      ];
      final h = Homography.rectTo(const Rect.fromLTWH(0, 0, 300, 100), quad)!;
      expect(h.isFinite, isTrue);
      const src = [
        Offset(0, 0),
        Offset(300, 0),
        Offset(300, 100),
        Offset(0, 100),
      ];
      for (var i = 0; i < 4; i++) {
        expect(h.map(src[i]).dx, closeTo(quad[i].dx, 1e-6));
        expect(h.map(src[i]).dy, closeTo(quad[i].dy, 1e-6));
      }
      // Perspective: the source centre does NOT map to the quad's vertex
      // average (an affine stretch would), but to the diagonals' crossing.
      final centre = h.map(const Offset(150, 50));
      final avg = QuadGeometry.centroid(quad);
      expect((centre - avg).distance, greaterThan(1));
      // The diagonals' intersection.
      Offset cross(Offset a, Offset b, Offset c, Offset d) {
        final t =
            ((c.dx - a.dx) * (d.dy - c.dy) - (c.dy - a.dy) * (d.dx - c.dx)) /
            ((b.dx - a.dx) * (d.dy - c.dy) - (b.dy - a.dy) * (d.dx - c.dx));
        return a + (b - a) * t;
      }

      final x = cross(quad[0], quad[2], quad[1], quad[3]);
      expect(centre.dx, closeTo(x.dx, 1e-6));
      expect(centre.dy, closeTo(x.dy, 1e-6));
      // Matrix4 used for canvas drawing applies the same mapping.
      final pt = MatrixUtils.transformPoint(
        h.toMatrix4(),
        const Offset(150, 50),
      );
      expect(pt.dx, closeTo(centre.dx, 1e-6));
      expect(pt.dy, closeTo(centre.dy, 1e-6));
      expect(
        Homography.unitSquareTo(const [
          Offset(0, 0),
          Offset(0, 0),
          Offset(0, 0),
          Offset(0, 0),
        ]),
        isNull,
      );
    });

    test('perspective artwork paints without errors at any aspect', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      paintBoardArtwork(
        canvas,
        const [
          Offset(10, 10),
          Offset(200, 30),
          Offset(190, 90),
          Offset(15, 120),
        ],
        const MarkupItemInfo(
          unitId: 'u',
          label: 'GSB – Unit 01',
          mediaShortName: 'GSB',
          color: AdinnColors.red,
          widthFt: 8,
          heightFt: 3,
        ),
        'Asian Paints',
      );
      recorder.endRecording().dispose();
    });
  });

  group('D. Placement markers', () {
    test('43-49 add, link, select, edit, delete preserves others', () async {
      final f = await Fixture.create();
      final e = f.editor();
      expect(
        e.addMarker(f.u1.id, const SurveyPoint(0.3, 0.3)),
        MarkerAddResult.added,
      );
      expect(
        e.addMarker(f.u2.id, const SurveyPoint(0.6, 0.3)),
        MarkerAddResult.added,
      );
      expect(
        e.addMarker(f.s1.id, const SurveyPoint(0.5, 0.8)),
        MarkerAddResult.added,
      );
      final ms = e.markup.markers;
      expect(ms.map((m) => m.number), [1, 2, 3]);
      expect(ms.map((m) => m.unitId), [f.u1.id, f.u2.id, f.s1.id]);
      expect(ms.map((m) => m.photoId).toSet(), {f.photo.id});

      const box = Size(400, 300);
      final hit = e.hitTest(const Offset(240, 90), box, 14);
      expect(hit, ms[1].id);
      e.select(hit);
      e.updateMarker(hit!, notes: 'Above shutter, left half');
      expect(e.marker(hit)!.notes, 'Above shutter, left half');

      e.select(ms[0].id);
      e.deleteSelected();
      expect(e.markup.markers.map((m) => m.number), [2, 3]);
      expect(e.marker(hit)!.notes, 'Above shutter, left half');
    });

    test('50 duplicate primary marker needs an explicit alternative', () async {
      final f = await Fixture.create();
      final e = f.editor();
      e.addMarker(f.u1.id, const SurveyPoint(0.3, 0.3));
      expect(
        e.addMarker(f.u1.id, const SurveyPoint(0.4, 0.3)),
        MarkerAddResult.duplicatePrimary,
      );
      expect(e.markup.markers, hasLength(1));
      e.addMarker(f.u1.id, const SurveyPoint(0.4, 0.3), alternative: true);
      expect(e.markup.markers, hasLength(2));
      expect(e.markup.markers.last.isAlternative, isTrue);
      expect(e.markup.markers.last.placementNo, 2);
    });

    test(
      '51 numbers stay stable after save / reload; reorder is explicit',
      () async {
        final f = await Fixture.create();
        final e = f.editor();
        e.addMarker(f.u1.id, const SurveyPoint(0.2, 0.3));
        e.addMarker(f.u2.id, const SurveyPoint(0.5, 0.3));
        e.addMarker(f.s1.id, const SurveyPoint(0.8, 0.7));
        e.select(e.markup.markers.first.id);
        e.deleteSelected();
        f.save(e);
        final again = await f.reload();
        final saved = again.photo(f.shop.id, f.gsb.id, f.photo.id)!.markup;
        expect(saved.markers.map((m) => m.number), [2, 3]);
        final e2 = SiteMarkupController(
          photoId: f.photo.id,
          initial: saved,
          imageSize: const Size(1200, 900),
        );
        e2.addMarker(f.u1.id, const SurveyPoint(0.2, 0.3));
        expect(e2.markup.markers.last.number, 4, reason: 'no re-use / regen');
        e2.setMarkerNumber(e2.markup.markers.last.id, 2);
        expect(
          {for (final m in e2.markup.markers) m.unitId: m.number},
          {f.u2.id: 4, f.s1.id: 3, f.u1.id: 2},
        );
      },
    );

    test('52 shared photo is referenced, never duplicated', () async {
      final f = await Fixture.create();
      final e = f.editor();
      e.addMarker(f.u1.id, const SurveyPoint(0.2, 0.3));
      e.addMarker(f.s1.id, const SurveyPoint(0.8, 0.7));
      f.save(e);
      final shop = f.c.shop(f.shop.id)!;
      final allPhotos = [for (final b in shop.boards) ...b.photos];
      expect(allPhotos.where((p) => p.path == 'demo://3'), hasLength(1));
      expect(f.gsb.photosOf(f.u1).single.id, f.photo.id);
      expect(f.photo.markup.unitIds, containsAll([f.u1.id, f.s1.id]));
    });

    test('removing a unit removes only its markers; photo stays', () async {
      final f = await Fixture.create();
      final e = f.editor();
      e.addMarker(f.u1.id, const SurveyPoint(0.2, 0.3));
      e.addMarker(f.u2.id, const SurveyPoint(0.5, 0.3));
      e.addPerspective(f.u2.id);
      f.save(e);
      await f.c.removeUnit(f.shop.id, f.gsb, f.u2.id);
      final p = f.c.photo(f.shop.id, f.gsb.id, f.photo.id)!;
      expect(p.markup.markers.map((m) => m.unitId), [f.gsb.units.first.id]);
      expect(p.markup.perspectives, isEmpty);
      expect(p.path, 'demo://3');
      expect(p.annotations.single.id, 'a_keep');
    });
  });

  group('F. Electrical and obstructions', () {
    test(
      '63-70 markers, cable route, obstruction, severity, links, evidence',
      () async {
        final f = await Fixture.create();
        final evidence = SitePhoto(
          id: 'ph_close',
          path: 'demo://4',
          label: 'Close-up',
          capturedAt: DateTime(2026, 11, 18),
          width: 1200,
          height: 900,
        );
        f.c.addPhoto(f.shop.id, f.gsb.id, evidence);
        final e = f.editor();
        final ep = e.addElectrical(
          ElectricalMarkKind.point,
          const SurveyPoint(0.1, 0.5),
          unitIds: [f.u1.id],
        );
        expect(ep.code, 'EP-01');
        e.addElectrical(ElectricalMarkKind.point, const SurveyPoint(0.15, 0.5));
        expect(e.markup.electrical.last.code, 'EP-02');
        e.addElectrical(
          ElectricalMarkKind.switchPoint,
          const SurveyPoint(0.2, 0.6),
        );
        expect(e.markup.electrical.last.code, 'SW-01');

        e.setTool(SiteMarkupTool.cableRoute);
        e.addDraftPoint(const SurveyPoint(0.1, 0.5));
        expect(e.finishCableRoute(), isNull, reason: 'needs two points');
        e.addDraftPoint(const SurveyPoint(0.4, 0.45));
        final cr = e.finishCableRoute(unitIds: [f.u1.id])!;
        expect(cr.code, 'CR-01');
        expect(cr.points, hasLength(2));

        e.obstructionType = ObstructionType.acUnit;
        e.obstructionShape = ObstructionShape.rect;
        final ob = e.addObstruction(const [
          SurveyPoint(0.6, 0.2),
          SurveyPoint(0.7, 0.35),
        ])!;
        expect(ob.type, ObstructionType.acUnit);
        expect(ob.severity, Severity.medium);
        e.updateObstruction(
          ob.id,
          severity: Severity.high,
          unitIds: [f.u1.id],
          evidencePhotoId: evidence.id,
          remarks: 'Blocks left half of fascia',
        );
        expect(
          e.addObstruction(const [
            SurveyPoint(0.5, 0.5),
            SurveyPoint(0.5, 0.5),
          ]),
          isNull,
          reason: 'degenerate rectangle',
        );
        f.save(e);

        final again = await f.reload();
        final m = again.photo(f.shop.id, f.gsb.id, f.photo.id)!.markup;
        expect(m.electrical.map((x) => x.code), ['EP-01', 'EP-02', 'SW-01']);
        expect(m.electrical.first.unitIds, [f.u1.id]);
        expect(m.cableRoutes.single.unitIds, [f.u1.id]);
        final o = m.obstructions.single;
        expect(o.severity, Severity.high);
        expect(o.unitIds, [f.u1.id]);
        expect(o.evidencePhotoId, 'ph_close');
        expect(o.remarks, 'Blocks left half of fascia');
      },
    );

    test('71 feasibility indicator follows explicit records only', () async {
      final f = await Fixture.create();
      expect(
        feasibilityOf(f.gsb, f.u1).level,
        SiteFeasibility.noKnownObstruction,
      );
      final e = f.editor();
      e.obstructionShape = ObstructionShape.point;
      e.addObstruction(const [SurveyPoint(0.5, 0.5)], unitIds: [f.u1.id]);
      f.save(e);
      expect(feasibilityOf(f.gsb, f.u1).level, SiteFeasibility.requiresReview);
      expect(
        feasibilityOf(f.gsb, f.u2).level,
        SiteFeasibility.noKnownObstruction,
      );

      final e2 = f.editor();
      e2.updateObstruction(
        e2.markup.obstructions.single.id,
        severity: Severity.high,
      );
      f.save(e2);
      final r = feasibilityOf(f.gsb, f.u1);
      expect(r.level, SiteFeasibility.blocked);
      expect(r.reasons.single, contains('AC Outdoor Unit'));
      expect(
        f.c.boardWarnings(f.gsb).any((w) => w.contains('Blocked')),
        isTrue,
        reason: 'flagged prominently for review',
      );
      // Standee unit linked from the GSB photo (shop-wide lookup).
      final e3 = f.editor();
      e3.addObstruction(const [SurveyPoint(0.4, 0.8)], unitIds: [f.s1.id]);
      f.save(e3);
      expect(
        feasibilityOf(f.standee, f.s1).level,
        SiteFeasibility.noKnownObstruction,
      );
      expect(
        feasibilityOf(f.standee, f.s1, shop: f.shop).level,
        SiteFeasibility.requiresReview,
      );
    });

    test('72 saving markup never touches existing annotations', () async {
      final f = await Fixture.create();
      final before = jsonEncode(
        f.photo.annotations.map((a) => a.toJson()).toList(),
      );
      final e = f.editor();
      e.addPerspective(f.u1.id);
      e.addMarker(f.u1.id, const SurveyPoint(0.3, 0.3));
      f.save(e);
      expect(
        jsonEncode(f.photo.annotations.map((a) => a.toJson()).toList()),
        before,
      );
    });

    test(
      'activity log: one entry per meaningful change, none for no-op',
      () async {
        final f = await Fixture.create();
        final count = f.c.data.activities.length;
        final e = f.editor();
        e.addPerspective(f.u1.id);
        e.obstructionShape = ObstructionShape.point;
        e.addObstruction(const [SurveyPoint(0.5, 0.5)]);
        f.save(e);
        final titles = f.c.data.activities
            .skip(count)
            .map((a) => a.title)
            .toList();
        expect(
          titles,
          containsAll(['Perspective placement saved', 'Obstruction added']),
        );
        final n = f.c.data.activities.length;
        f.save(f.editor()); // nothing changed
        expect(f.c.data.activities.length, n);
      },
    );
  });

  group('J. Migration and persistence', () {
    Map<String, dynamic> v3() {
      final json = buildSeedData().toJson();
      json['schemaVersion'] = 3;
      return json;
    }

    test(
      '111 + 113 + 114 + 116 old v3 data loads with safe defaults',
      () async {
        final raw = v3();
        final store = MemoryLocalStore(raw);
        final c = AppController(store: store);
        await c.init();
        await c.flush();
        final amma = c.shop('s_amma')!;
        final b = amma.boards.first;
        expect(b.checklistRequired, isFalse, reason: 'legacy: not blocking');
        expect(b.photos.first.markup.isEmpty, isTrue);
        expect(b.photos.first.annotations, isNotEmpty);
        expect(b.units.first.measurements.isEmpty, isTrue);
        expect(b.units.first.checklist, isEmpty);
        expect(
          SiteFeasibility.noKnownObstruction,
          feasibilityOf(b, b.units.first).level,
        );
        expect(amma.submissions.single.version, 1);
        expect(amma.status, RecceStatus.pendingBusiness);
        expect(store.backups.single.$1, 'v3', reason: 'original kept');
        expect(store.data!['schemaVersion'], AppData.schemaVersion);
        expect(c.recoveryNotice, isNull);
      },
    );

    test('112 + 118 + 119 new records round-trip with stable ids', () async {
      final f = await Fixture.create();
      final e = f.editor();
      final p = e.addPerspective(f.u1.id);
      e.addMarker(f.u1.id, const SurveyPoint(0.3, 0.3));
      f.save(e);
      f.u1.measurements = MeasurementDetails(
        valuesMm: {'bottom_height': 2743.2},
      );
      f.c.touchBoard(f.shop.id, f.gsb);
      final again = await f.reload();
      final b = again.board(f.shop.id, f.gsb.id)!;
      expect(b.units.map((u) => u.id), f.gsb.units.map((u) => u.id));
      expect(b.checklistRequired, isTrue);
      expect(b.units.first.measurements.valuesMm['bottom_height'], 2743.2);
      expect(b.photos.single.markup.perspectives.single.id, p.id);
      expect(
        jsonEncode(again.data.toJson()['shops']),
        jsonEncode(f.c.data.toJson()['shops']),
      );
    });

    test('115 migration is idempotent', () async {
      final store = MemoryLocalStore(v3());
      final c1 = AppController(store: store);
      await c1.init();
      await c1.flush();
      final first = jsonEncode(store.data);
      final c2 = AppController(store: store);
      await c2.init();
      await c2.flush();
      expect(jsonEncode(store.data), first);
      expect(store.backups, hasLength(1), reason: 'no second upgrade');
    });

    test('117 malformed records are skipped, original backed up', () async {
      final raw = v3();
      final shops = raw['shops'] as List;
      final amma = shops.firstWhere((s) => s['id'] == 's_amma') as Map;
      final photo = (amma['boards'] as List).first['photos'][0] as Map;
      photo['markup'] = {
        'markers': [
          {
            'id': 'ok',
            'unitId': 'u',
            'number': 1,
            'position': [0.5, 0.5],
          },
          {'id': 'bad', 'number': 'x', 'position': 'nope', 'createdAt': 7},
        ],
        'obstructions': [
          {
            'id': 'o1',
            'shape': 'rect',
            'points': [
              [0.1, 0.1],
            ],
          },
        ],
        'perspectives': [
          {
            'id': 'p1',
            'corners': [
              [0, 0],
              [1, 0],
            ],
          },
        ],
      };
      // An enum value from the future and a broken activity entry.
      (amma['boards'] as List).first['units'][0]['checklist'] = [
        {'questionId': 'q1', 'value': 'yes'},
        'garbage',
      ];
      (raw['activities'] as List).add({'id': 'e', 'version': 'not-a-number'});
      raw['schemaVersion'] = AppData.schemaVersion;
      final store = MemoryLocalStore(raw);
      final c = AppController(store: store);
      await c.init();
      final m = c.shop('s_amma')!.boards.first.photos.first.markup;
      expect(m.markers.map((x) => x.id), contains('ok'));
      expect(m.obstructions, isEmpty, reason: 'rect needs 2 points');
      expect(m.perspectives, isEmpty, reason: 'needs 4 corners');
      expect(c.recoveryNotice, isNotNull);
      expect(store.backups.single.$1, 'repair');
      expect(
        jsonEncode(store.backups.single.$2),
        contains('not-a-number'),
        reason: 'original preserved',
      );
      final s = c.shop('s_amma')!;
      expect(s.boards.first.units.first.checklist.keys, ['q1']);
    });

    test('unknown enum names fall back safely', () {
      final o = ObstructionMark.fromJson({
        'id': 'x',
        'type': 'spaceship',
        'shape': 'hexagon',
        'severity': 'catastrophic',
        'points': [
          [0.2, 0.2],
        ],
      });
      expect(o.type, ObstructionType.other);
      expect(o.shape, ObstructionShape.point);
      expect(o.severity, Severity.medium);
      final c = PhotoReviewComment.fromJson({'type': '??', 'status': '??'});
      expect(c.type, ReviewCommentType.general);
      expect(c.status, CommentStatus.open);
    });

    test('120 cleanup never deletes shared photos', () async {
      final media = _RecordingMedia();
      final store = MemoryLocalStore();
      final c = AppController(store: store, media: media);
      await c.init();
      c.loginWithPin(DemoAccounts.vendorPin);
      final shop = c.shop('s_lakshmi')!;
      final b = c.addBoard(shop.id)..mediaCode = SignageCatalog.gsb;
      c.addPhoto(
        shop.id,
        b.id,
        SitePhoto(
          id: 'p',
          path: '/files/photo.jpg',
          label: 'Front',
          capturedAt: DateTime(2026),
          width: 1200,
          height: 900,
        ),
      );
      final e = SiteMarkupController(
        photoId: 'p',
        initial: SiteMarkup(),
        imageSize: const Size(1200, 900),
      );
      e.addMarker(b.units.first.id, const SurveyPoint(0.5, 0.5));
      c.saveSiteMarkup(shop.id, b.id, 'p', e.markup);
      e.select(e.markup.markers.single.id);
      e.deleteSelected();
      c.saveSiteMarkup(shop.id, b.id, 'p', e.markup);
      c.addComparison(
        shop.id,
        b.id,
        ComparisonRecord(
          id: 'cmp',
          groupId: b.id,
          unitId: b.units.first.id,
          photoId: 'p',
          source: ProposedSource.perspective,
          versionLabel: 'Perspective',
          path: '/files/cmp.png',
          createdAt: DateTime(2026),
        ),
      );
      await c.removeComparison(shop.id, b.id, 'cmp');
      expect(media.deleted, ['/files/cmp.png']);
      expect(c.board(shop.id, b.id)!.photos.single.path, '/files/photo.jpg');
    });
  });

  group('editor screen', () {
    Widget host(AppController c, Widget child) =>
        ChangeNotifierProvider<AppController>.value(
          value: c,
          child: MaterialApp(theme: AppTheme.light(), home: child),
        );

    testWidgets('perspective tool, invalid shape blocks save, marker dialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final f = await Fixture.create();
      await tester.pumpWidget(
        host(
          f.c,
          SiteMarkupScreen(
            shopId: f.shop.id,
            boardId: f.gsb.id,
            photoId: f.photo.id,
            activeUnitId: f.u1.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mtool_perspective')));
      await tester.pump();
      final canvas = find.byKey(const ValueKey('markup_canvas'));
      await tester.tap(canvas);
      await tester.pumpAndSettle();
      expect(find.text('Perspective • GSB – Unit 01'), findsOneWidget);
      expect(find.byKey(const ValueKey('markup_invalid')), findsNothing);

      // Save → stored on the photo.
      await tester.tap(find.byKey(const ValueKey('markup_save')));
      await tester.pumpAndSettle();
      expect(f.photo.markup.perspectives, hasLength(1));
      ScaffoldMessenger.of(tester.element(canvas)).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      // Marker twice for the same item → duplicate dialog.
      await tester.tap(find.byKey(const ValueKey('mtool_marker')));
      await tester.pump();
      final box = tester.getRect(canvas);
      await tester.tapAt(box.topLeft + const Offset(80, 80));
      await tester.pumpAndSettle();
      await tester.tapAt(box.topLeft + const Offset(140, 90));
      await tester.pumpAndSettle();
      expect(find.text('Item already marked'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mk_dup_alt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('markup_save')));
      await tester.pumpAndSettle();
      expect(f.photo.markup.markers, hasLength(2));
      expect(f.photo.markup.markers.last.isAlternative, isTrue);
    });

    testWidgets('28 taps map to the same photo point at any zoom / pan', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final f = await Fixture.create();
      await tester.pumpWidget(
        host(
          f.c,
          SiteMarkupScreen(
            shopId: f.shop.id,
            boardId: f.gsb.id,
            photoId: f.photo.id,
            activeUnitId: f.u1.id,
            initialTool: SiteMarkupTool.marker,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      viewer.transformationController!.value = Matrix4.identity()
        ..translateByDouble(-60, -250, 0, 1)
        ..scaleByDouble(2, 2, 1, 1);
      await tester.pumpAndSettle();
      // Global position of photo point (0.25, 0.5) under the zoom.
      final canvas = find.byKey(const ValueKey('markup_canvas'));
      final ro = tester.renderObject<RenderBox>(canvas);
      const margin = 28.0;
      final photoW = ro.size.width - margin * 2;
      final photoH = ro.size.height - margin * 2;
      final local = Offset(margin + photoW * 0.25, margin + photoH * 0.5);
      final viewport = tester.getRect(find.byType(InteractiveViewer));
      expect(viewport.contains(ro.localToGlobal(local)), isTrue);
      await tester.tapAt(ro.localToGlobal(local));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('markup_save')));
      await tester.pumpAndSettle();
      final m = f.photo.markup.markers.single;
      expect(m.position.x, closeTo(0.25, 0.002));
      expect(m.position.y, closeTo(0.5, 0.002));
    });

    testWidgets('read-only recce shows markup without editing tools', (
      tester,
    ) async {
      final store = MemoryLocalStore();
      final c = AppController(store: store);
      await c.init();
      c.loginWithPin(DemoAccounts.vendorPin);
      final amma = c.shop('s_amma')!; // pending business → read-only
      final b = amma.boards.first;
      await tester.pumpWidget(
        host(
          c,
          SiteMarkupScreen(
            shopId: amma.id,
            boardId: b.id,
            photoId: b.photos.first.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('markup_save')), findsNothing);
      expect(find.byKey(const ValueKey('mtool_perspective')), findsNothing);
      expect(find.byKey(const ValueKey('mtool_select')), findsOneWidget);
      expect(find.textContaining('Read-only'), findsOneWidget);
    });

    testWidgets('classic editor offers the site markup tools', (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final f = await Fixture.create();
      await tester.pumpWidget(
        host(
          f.c,
          Builder(
            builder: (context) => AnnotationEditorScreen(
              photo: f.photo,
              boardName: f.gsb.name,
              extraTools: siteMarkupTools(
                context,
                shopId: f.shop.id,
                boardId: f.gsb.id,
                photoId: f.photo.id,
                activeUnitId: f.u1.id,
              ),
              underlay: LiveMarkupUnderlay(
                controller: f.c,
                shopId: f.shop.id,
                photo: f.photo,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('annotation-underlay')), findsOneWidget);
      final tool = find.byKey(const ValueKey('tool-extra-perspective'));
      await tester.scrollUntilVisible(
        tool,
        200,
        scrollable: find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.tap(tool);
      await tester.pumpAndSettle();
      expect(find.byType(SiteMarkupScreen), findsOneWidget);
      expect(find.text('Site markup'), findsOneWidget);
    });
  });
}

class _RecordingMedia extends MediaStorage {
  final deleted = <String>[];

  @override
  Future<void> deleteIfExists(String? path) async {
    if (path != null) deleted.add(path);
  }
}
