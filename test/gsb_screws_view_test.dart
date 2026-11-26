import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/features/gsb/gsb_presentation.dart';
import 'package:signage_recce/features/gsb/gsb_view.dart';
import 'package:signage_recce/features/preview3d/renderer_painter.dart';
import 'package:signage_recce/features/preview3d/scene3d.dart';
import 'package:signage_recce/features/preview_live/live_preview_controller.dart';

List<GsbCoverScrew> _cover(double wFt, double hFt) =>
    GsbScrewLayout.cover(widthIn: wFt * 12, heightIn: hFt * 12, depthIn: 8);

SitePhoto _photo() => SitePhoto(
  id: 'ph',
  path: 'demo://2',
  label: 'p',
  capturedAt: DateTime(2026),
  width: 1200,
  height: 900,
);

Board _gsb({bool dbl = false}) => Board(
  id: 'g',
  name: 'G',
  mediaCode: SignageCatalog.gsb,
  installationCode: SignageCatalog.shopFascia,
  width: 6,
  height: 3,
  doubleSided: dbl,
)..photos.add(_photo());

void main() {
  group('cover screws (6 x 3 ft reference)', () {
    test('stations on the 12-in grid, corners not duplicated', () {
      expect(GsbScrewLayout.stations(72), [12, 24, 36, 48, 60]);
      expect(GsbScrewLayout.stations(36), [12, 24]);
      final s = _cover(6, 3);
      List<GsbCoverScrew> on(GsbCover c) => [
        for (final x in s)
          if (x.cover == c) x,
      ];
      // Long edges: 5 stations x front + rear row.
      for (final c in [GsbCover.top, GsbCover.bottom]) {
        final e = on(c);
        expect(e, hasLength(10));
        expect({for (final x in e) x.alongIn}, {12, 24, 36, 48, 60});
        expect({for (final x in e) x.depthIn}, {0.375, 7.625});
      }
      // Short edges: end rows (front, middle, rear) + 12 / 24 rows.
      for (final c in [GsbCover.left, GsbCover.right]) {
        final e = on(c);
        expect(e, hasLength(2 * 3 + 2 * 2));
        expect({for (final x in e) x.alongIn}, {1, 12, 24, 35});
        expect(e.where((x) => x.alongIn == 1).map((x) => x.depthIn), [
          0.375,
          4,
          7.625,
        ]);
      }
      expect(s, hasLength(40));
      expect(s.toSet(), hasLength(s.length)); // no duplicate screw
    });

    test(
      'generated from inches for other sizes, all on the 0.75-in returns',
      () {
        for (final (w, h) in [
          (8.0, 3.0),
          (8.0, 5.0),
          (10.0, 4.0),
          (13.0, 4.0),
          (16.0, 7.0),
        ]) {
          final s = _cover(w, h);
          expect(s.toSet(), hasLength(s.length), reason: '$w x $h');
          for (final x in s) {
            expect(x.depthIn, inInclusiveRange(0.375, 7.625));
            final len = (x.cover == GsbCover.top || x.cover == GsbCover.bottom)
                ? w * 12
                : h * 12;
            expect(x.alongIn, inInclusiveRange(1, len - 1));
          }
          // Every 12-in station of the long edge is present.
          final top = [
            for (final x in s)
              if (x.cover == GsbCover.top) x.alongIn,
          ];
          for (final st in GsbScrewLayout.stations(w * 12)) {
            expect(top, contains(st));
          }
        }
        expect(
          GsbScrewLayout.cover(widthIn: double.nan, heightIn: 36, depthIn: 8),
          isEmpty,
        );
      },
    );

    test('screw heads follow the layout and sit on their cover', () {
      final body = GsbFinishedBoard.build(
        const GsbPresentation(
          widthFt: 6,
          heightFt: 3,
          depthFt: 8 / 12,
          isDouble: false,
        ),
      ).first;
      final heads = body.decals.where(
        (f) => f.points.length == 6 && f.layer == kScrewHeadLayer,
      );
      expect(heads.length, 40); // 6 x 3 ft: no GI joint, so cover only
      for (final f in heads) {
        final c = Vec3.average(f.points);
        final n = f.normal;
        // Position along the normal is the cover plane (± 3 mm).
        if (n.x != 0) expect(c.x.abs(), closeTo(3, 0.003));
        if (n.y > 0) expect(c.y, closeTo(3, 0.003));
        if (n.y < 0) expect(c.y, closeTo(0, 0.003));
        // Whole head stays on the cover: never past the front / rear edge.
        for (final p in f.points) {
          expect(p.z, inInclusiveRange(-8 / 12, 0));
        }
      }
    });
  });

  group('GI screws (GSB Single only)', () {
    test('one shared row per 6-in overlap at the support stations', () {
      // 21 x 7 style heights have two joints; 8 x 5 has one (30 + 36).
      final one = GsbScrewLayout.gi(widthIn: 96, heightIn: 60);
      expect(one, isNotEmpty);
      expect({for (final g in one) g.yIn}, {27}); // overlap [24, 30] centre
      expect({for (final g in one) g.xIn}, {24, 48, 72});
      final two = GsbScrewLayout.gi(widthIn: 96, heightIn: 84);
      expect({for (final g in two) g.yIn}, {27, 51}); // 30-3, 54-3
      // No approved tier plan → no invented pitch.
      expect(GsbScrewLayout.gi(widthIn: 96, heightIn: 36), isEmpty);
    });

    test('Double has no GI screws; Single GI screws face the rear', () {
      Iterable<Face> gi(bool dbl) => GsbFinishedBoard.build(
        GsbPresentation(
          widthFt: 8,
          heightFt: 5,
          depthFt: 8 / 12,
          isDouble: dbl,
        ),
      ).first.decals.where((f) => f.normal == const Vec3(0, 0, -1));
      expect(gi(false), isNotEmpty);
      expect(gi(true), isEmpty);
    });
  });

  group('360° turn and photo views', () {
    test('yaw wraps through a full circle without jumps', () {
      final c = LivePreviewController(board: _gsb(), photo: _photo())
        ..addUnit('g_u1');
      for (final deg in [0, 45, 90, 135, 180, 225, 270, 315, 360]) {
        c.setYaw(deg * math.pi / 180);
        final y = c.selected!.yaw;
        expect(y, inInclusiveRange(-math.pi, math.pi), reason: '$deg');
        expect(math.cos(y), closeTo(math.cos(deg * math.pi / 180), 1e-9));
        expect(math.sin(y), closeTo(math.sin(deg * math.pi / 180), 1e-9));
      }
      expect(yawDegreesLabel(-math.pi / 2), '270°');
      expect(yawDegreesLabel(2 * math.pi), '0°');
    });

    test('presets: right = +90 shows the right cover, left = -90 the left', () {
      expect(GsbPhotoView.right.baseYaw, math.pi / 2);
      expect(GsbPhotoView.left.baseYaw, -math.pi / 2);
      expect(GsbPhotoView.back.baseYaw, math.pi);
      final solids = GsbFinishedBoard.build(
        const GsbPresentation(
          widthFt: 6,
          heightFt: 3,
          depthFt: 8 / 12,
          isDouble: false,
          bottomFt: 5,
        ),
      );
      final scene = Scene(focus: const Vec3(0, 6.5, -0.33));
      solids.forEach(scene.add);
      scene.finalize();
      Set<Vec3> visible(double yaw) {
        final p = ViewProjector(
          camera: Camera3D(yaw: yaw, pitch: 0),
          size: const Size(400, 400),
          target: scene.focus,
          radius: scene.radius,
        );
        return {
          for (final f in solids.first.faces)
            if (p.facesCamera(
              f.normal,
              Vec3.average(f.points.map(p.toView).toList()),
            ))
              f.normal,
        };
      }

      expect(
        visible(GsbPhotoView.right.baseYaw),
        contains(const Vec3(1, 0, 0)),
      );
      expect(
        visible(GsbPhotoView.left.baseYaw),
        contains(const Vec3(-1, 0, 0)),
      );
      expect(
        visible(GsbPhotoView.back.baseYaw),
        contains(const Vec3(0, 0, -1)),
      );
      expect(visible(0), contains(const Vec3(0, 0, 1)));
    });

    test('switching preset keeps the manual adjustment; custom keeps yaw', () {
      final c = LivePreviewController(board: _gsb(), photo: _photo())
        ..addUnit('g_u1');
      c.setPhotoView(GsbPhotoView.left);
      expect(c.selected!.yaw, closeTo(-math.pi / 2, 1e-9));
      c.setYaw(-math.pi / 2 + 0.2); // vendor adjustment +0.2 rad
      c.setPhotoView(GsbPhotoView.right);
      expect(c.selected!.yaw, closeTo(math.pi / 2 + 0.2, 1e-9));
      c.setPhotoView(GsbPhotoView.back);
      expect(c.selected!.yaw, closeTo(wrapYaw(math.pi + 0.2), 1e-9));
      final before = c.selected!.yaw;
      c.setPhotoView(GsbPhotoView.custom);
      expect(c.selected!.yaw, before);
    });

    test('a photo with a saved view starts the board at its yaw', () {
      final b = _gsb();
      b.photos.first.gsbView = 'left';
      final c = LivePreviewController(board: b, photo: b.photos.first)
        ..photoView = GsbPhotoViewX.fromKey(b.photos.first.gsbView)
        ..addUnit('g_u1');
      expect(c.selected!.yaw, closeTo(-math.pi / 2, 1e-9));
      // JSON round trip keeps the view; older photos have none.
      final j = SitePhoto.fromJson(b.photos.first.toJson());
      expect(j.gsbView, 'left');
      expect(SitePhoto.fromJson(_photo().toJson()).gsbView, isNull);
    });
  });

  group('GSB Double rear flex and LED side', () {
    test('rear flex is a separate, un-mirrored, outward-facing surface', () {
      final s = GsbFinishedBoard.build(
        const GsbPresentation(
          widthFt: 6,
          heightFt: 3,
          depthFt: 8 / 12,
          isDouble: true,
        ),
      );
      final rear = s.last.faces.single;
      final front = s
          .firstWhere((x) => x.name == 'gsb_front_flex')
          .faces
          .single;
      expect(rear.normal, const Vec3(0, 0, -1));
      expect(front.normal, const Vec3(0, 0, 1));
      // Seen from behind the label's top-left corner is the board's +x end
      // (not mirrored text).
      expect(rear.points[0].x, greaterThan(rear.points[1].x));
      expect(rear.points[0].y, greaterThan(rear.points[3].y));
      expect(rear.label, front.label);
    });

    test('screw heads are layered above the edge strips (never hidden)', () {
      final body = GsbFinishedBoard.build(
        const GsbPresentation(
          widthFt: 6,
          heightFt: 3,
          depthFt: 8 / 12,
          isDouble: false,
        ),
      ).first;
      final strips = body.decals.where((f) => f.points.length == 4);
      final heads = body.decals.where((f) => f.points.length == 6);
      expect(strips, isNotEmpty);
      expect(strips.every((f) => f.layer == kEdgeStripLayer), isTrue);
      expect(heads.every((f) => f.layer > kEdgeStripLayer), isTrue);
      expect(kScrewCentreLayer, greaterThan(kScrewHeadLayer));
    });

    test('both flex faces glow at night whichever side the LED set is', () {
      bool glows(bool ledRear, bool rearFace) {
        final s = GsbFinishedBoard.build(
          GsbPresentation(
            widthFt: 6,
            heightFt: 3,
            depthFt: 8 / 12,
            isDouble: true,
            ledOnRear: ledRear,
          ),
        );
        final f = rearFace
            ? s.last.faces.single
            : s.firstWhere((x) => x.name == 'gsb_front_flex').faces.single;
        return f.emissive && f.glowsAtNight;
      }

      for (final led in [false, true]) {
        expect(glows(led, false), isTrue, reason: 'front, LED rear=$led');
        expect(glows(led, true), isTrue, reason: 'rear, LED rear=$led');
      }
      // Single: the front always glows; the LED count stays one.
      final single = GsbFinishedBoard.build(
        const GsbPresentation(
          widthFt: 6,
          heightFt: 3,
          depthFt: 8 / 12,
          isDouble: false,
          ledOnRear: true,
        ),
      );
      expect(single[1].faces.single.glowsAtNight, isTrue);
    });

    test('LED side persists and defaults to front', () {
      final b = _gsb(dbl: true);
      expect(b.gsbLedOnRear, isFalse);
      expect(b.toJson().containsKey('gsbLedSide'), isFalse);
      b.gsbLedSide = 'rear';
      final c = Board.fromJson(b.toJson());
      expect(c.gsbLedOnRear, isTrue);
      expect(c.gsbVariantKey, 'GSB_DOUBLE');
    });
  });
}
