import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/features/gsb/gsb_presentation.dart';
import 'package:signage_recce/features/preview3d/renderer_painter.dart';
import 'package:signage_recce/features/preview3d/scene3d.dart';

List<Face> _all(List<Solid> s) => [
  for (final x in s) ...x.faces,
  for (final x in s) ...x.decals,
];

GsbPresentation _cfg(double w, double h, {bool dbl = false}) => GsbPresentation(
  widthFt: w,
  heightFt: h,
  depthFt: 8 / 12,
  bottomFt: 6.5,
  isDouble: dbl,
  brand: 'SAKTHI MASALA',
);

void main() {
  const sizes = [
    (5.0, 2.0),
    (6.0, 3.0),
    (8.0, 3.0),
    (8.0, 5.0),
    (10.0, 4.0),
    (13.0, 4.0),
    (16.0, 7.0),
    (17.0, 7.0),
    (20.0, 10.0),
  ];

  test('exterior only: six real faces, flex, no internal parts', () {
    for (final (w, h) in sizes) {
      for (final dbl in [false, true]) {
        final solids = GsbFinishedBoard.build(_cfg(w, h, dbl: dbl));
        final body = solids.first;
        expect(body.faces, hasLength(6), reason: '$w x $h');
        // Real depth: front z = 0, rear z = -8 in.
        final zs = [
          for (final f in body.faces)
            for (final p in f.points) p.z,
        ];
        expect(zs.reduce((a, b) => a < b ? a : b), closeTo(-8 / 12, 1e-9));
        expect(zs.reduce((a, b) => a > b ? a : b), 0);
        // Only body + flex(es): no pipes, bulbs, nuts, wiring solids.
        expect(solids, hasLength(dbl ? 3 : 2));
        final labelled = _all(solids).where((f) => f.label != null);
        expect(labelled, hasLength(dbl ? 2 : 1));
        // Flex quad keeps the board aspect ratio (no stretching).
        final q = labelled.first.points;
        final fw = (q[1] - q[0]).length, fh = (q[3] - q[0]).length;
        final ret = 2 * GsbPresentation.returnFt;
        expect(fw, closeTo(w - ret, 1e-9));
        expect(fh, closeTo(h - ret, 1e-9));
      }
    }
  });

  test('single rear = GI, double rear = flex facing backwards', () {
    final s = GsbFinishedBoard.build(_cfg(8, 3));
    final back = s.first.faces.firstWhere(
      (f) => f.normal == const Vec3(0, 0, -1),
    );
    expect(back.color, isNot(kGsbPowderBlue));
    expect(back.label, isNull);
    final d = GsbFinishedBoard.build(_cfg(8, 3, dbl: true));
    final rear = d.last.faces.single;
    expect(rear.normal, const Vec3(0, 0, -1));
    expect(rear.label, 'SAKTHI MASALA');
    final backD = d.first.faces.firstWhere(
      (f) => f.normal == const Vec3(0, 0, -1),
    );
    expect(backD.color, kGsbPowderBlue);
  });

  test('powder-coated covers and a small screw budget', () {
    for (final (w, h) in sizes) {
      final body = GsbFinishedBoard.build(_cfg(w, h)).first;
      final sides = body.faces.where((f) => f.normal.z == 0);
      expect(sides.every((f) => f.color == kGsbPowderBlue), isTrue);
      // One head per layout position (+ GI on Single), 1–2 faces each.
      final hex = body.decals.where((f) => f.points.length == 6).length;
      final heads =
          GsbScrewLayout.cover(
            widthIn: w * 12,
            heightIn: h * 12,
            depthIn: 8,
          ).length +
          GsbScrewLayout.gi(widthIn: w * 12, heightIn: h * 12).length;
      expect(hex, inInclusiveRange(heads, 2 * heads), reason: '$w x $h');
      // Every screw sits on a cover surface (outside the box by ≤ 3 mm).
      for (final f in body.decals) {
        for (final p in f.points) {
          expect(p.x.abs(), lessThanOrEqualTo(w / 2 + 0.003));
          expect(p.y, inInclusiveRange(6.5 - 0.003, 6.5 + h + 0.003));
        }
      }
    }
    final off = GsbFinishedBoard.build(
      GsbPresentation(
        widthFt: 8,
        heightFt: 3,
        depthFt: 0.6,
        isDouble: false,
        screws: false,
      ),
    ).first;
    expect(off.decals.where((f) => f.points.length == 6), isEmpty);
  });

  test('invalid sizes never produce non-finite geometry', () {
    final s = GsbFinishedBoard.build(
      const GsbPresentation(
        widthFt: double.nan,
        heightFt: -3,
        depthFt: 0,
        isDouble: true,
      ),
    );
    for (final f in _all(s)) {
      for (final p in f.points) {
        expect(p.x.isFinite && p.y.isFinite && p.z.isFinite, isTrue);
      }
    }
  });

  testWidgets('turned board shows top and side covers; night keeps geometry', (
    tester,
  ) async {
    final solids = GsbFinishedBoard.build(_cfg(8, 3));
    final scene = Scene(focus: const Vec3(0, 8, -0.33));
    solids.forEach(scene.add);
    scene.finalize();
    final proj = ViewProjector(
      camera: const Camera3D(yaw: 0.7, pitch: 0.3),
      size: const Size(400, 400),
      target: scene.focus,
      radius: scene.radius,
    );
    final visible = <Vec3>{
      for (final f in solids.first.faces)
        if (proj.facesCamera(
          f.normal,
          Vec3.average(f.points.map(proj.toView).toList()),
        ))
          f.normal,
    };
    // Front, one side and the top are visible: a solid box, not a flat card.
    expect(visible.length, 3);
    expect(visible.contains(const Vec3(0, 1, 0)), isTrue);

    for (final night in [false, true]) {
      final recorder = PictureRecorder();
      Scene3DPainter(
        scene: scene,
        camera: const Camera3D(yaw: 0.7, pitch: 0.3),
        paintBackground: false,
        paintGround: false,
        paintGizmo: false,
        night: night,
      ).paint(Canvas(recorder), const Size(400, 400));
      recorder.endRecording().dispose();
    }
  });
}
