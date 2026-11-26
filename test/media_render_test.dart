import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/features/model3d/parametric_builder.dart';
import 'package:signage_recce/features/model3d/signage_spec.dart';
import 'package:signage_recce/features/preview3d/renderer_painter.dart';
import 'package:signage_recce/features/preview3d/scene3d.dart';
import 'package:signage_recce/features/preview_live/live_preview_controller.dart';

Board _board(String media, {String? inst, double w = 6, double h = 3}) =>
    Board(
        id: 'b',
        name: 'B',
        mediaCode: media,
        installationCode:
            inst ?? SignageCatalog.media(media)!.installations.first,
        width: w,
        height: h,
      )
      ..photos.add(
        SitePhoto(
          id: 'ph',
          path: 'demo://2',
          label: 'p',
          capturedAt: DateTime(2026),
          width: 1200,
          height: 900,
        ),
      );

ParametricModel _model(Board b) => ParametricModelBuilder.build(
  SignageModelSpec.of(b, b.units.first),
  context: false,
);

List<Face> _faces(ParametricModel m) => [
  for (final s in m.scene.solids) ...s.faces,
  for (final s in m.scene.solids) ...s.decals,
];

void main() {
  group('Foam board vinyl', () {
    test('3 mm substrate, not 3 inches / 3 cm', () {
      expect(SignageCatalog.media(SignageCatalog.foamVinyl)!.thicknessMm, 3);
      final b = _board(SignageCatalog.foamVinyl);
      final spec = SignageModelSpec.of(b, b.units.first);
      expect(spec[SpecField.materialThickness], 3);
      final m = _model(b);
      final panel = m.solidsOf('display_panel').single;
      final zs = [
        for (final f in panel.faces)
          for (final p in f.points) p.z,
      ];
      final depthFt =
          zs.reduce((a, c) => a > c ? a : c) -
          zs.reduce((a, c) => a < c ? a : c);
      expect(depthFt * 304.8, closeTo(3, 1e-6));
    });
  });

  group('One-way vision', () {
    test('fine see-through mask, no mesh dots, thin film on glass', () {
      final b = _board(SignageCatalog.oneWayVision);
      final m = _model(b);
      final solids = m.scene.solids;
      // No per-hole geometry any more.
      expect(solids.expand((s) => s.decals), isEmpty);
      final masked = _faces(m).where((f) => f.perforationPitchFt != null);
      expect(masked, isNotEmpty);
      for (final f in masked) {
        // Pitch is fine (<= 1/100 of the width) and never below 2.5 mm.
        expect(f.perforationPitchFt!, lessThanOrEqualTo(6 / 100 + 1e-9));
        expect(f.perforationPitchFt! * 304.8, greaterThanOrEqualTo(2.5 - 1e-9));
        expect(f.perforationHole, lessThan(0.7));
      }
      // Glass pane is part of the scene; the film itself is paper-thin.
      expect(m.components.map((c) => c.id), contains('glass_backing'));
      final film = m.solidsOf('vinyl_layer').single;
      final zs = [
        for (final f in film.faces)
          for (final p in f.points) p.z,
      ];
      final t =
          zs.reduce((a, c) => a > c ? a : c) -
          zs.reduce((a, c) => a < c ? a : c);
      expect(t * 304.8, lessThan(1));
      expect(
        m.notes.any((n) => n.contains('illustrative')),
        isTrue,
      ); // not a manufacturing value
    });

    testWidgets('holes are really cleared (photo shows through)', (
      tester,
    ) async {
      final b = _board(SignageCatalog.oneWayVision);
      final scene = _model(b).scene;
      Future<double> opaqueShare(bool perforated) async {
        if (!perforated) {
          for (final s in scene.solids) {
            for (final f in s.faces) {
              f.perforationPitchFt = null;
            }
          }
        }
        final rec = ui.PictureRecorder();
        Scene3DPainter(
          scene: scene,
          camera: const Camera3D(yaw: 0, pitch: 0, ortho: true),
          paintBackground: false,
          paintGround: false,
          paintGizmo: false,
        ).paint(Canvas(rec), const Size(300, 300));
        final image = await rec.endRecording().toImage(300, 300);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        final px = data!.buffer.asUint8List();
        var covered = 0, total = 0;
        for (var i = 3; i < px.length; i += 4) {
          total++;
          if (px[i] > 200) covered++;
        }
        return covered / total;
      }

      final withHoles = (await tester.runAsync(() => opaqueShare(true)))!;
      final solid = (await tester.runAsync(() => opaqueShare(false)))!;
      expect(withHoles, lessThan(solid));
    });
  });

  group('Acrylic', () {
    test('cylindrical studs with a real wall gap and stud spacing dims', () {
      final b = _board(SignageCatalog.clearAcrylic);
      final spec = SignageModelSpec.of(b, b.units.first);
      final m = ParametricModelBuilder.build(spec, context: false);
      final studs = m.scene.solids.where((s) => s.name.startsWith('standoffs'));
      // 4 corners x (spacer + cap).
      expect(studs, hasLength(8));
      final gap = spec[SpecField.standoff];
      expect(gap, greaterThan(0));
      // Spacer reaches from the sheet back to the wall gap distance.
      final zs = [
        for (final s in studs)
          for (final f in s.faces)
            for (final p in f.points) p.z,
      ];
      expect(
        zs.reduce((a, c) => a < c ? a : c) * -304.8,
        closeTo(8 + gap, 1e-6),
      );
      expect(
        zs.reduce((a, c) => a > c ? a : c),
        greaterThan(0),
      ); // cap in front
      expect(
        m.dimensions.where((d) => d.id.startsWith('stud_spacing')),
        hasLength(2),
      );
      // Low poly: every stud <= 14 faces.
      expect(studs.every((s) => s.faces.length <= 14), isTrue);
    });

    test('no standoff configured: studs are not invented', () {
      final b = _board(SignageCatalog.clearAcrylic);
      final spec = SignageModelSpec.of(
        b,
        b.units.first,
      ).copyWith(values: {SpecField.standoff: 0});
      final m = ParametricModelBuilder.build(spec, context: false);
      expect(
        m.scene.solids.where((s) => s.name.startsWith('standoffs')),
        isEmpty,
      );
      expect(m.notes.any((n) => n.contains('Not specified')), isTrue);
    });
  });

  group('Plain vinyl', () {
    test('sticker: negligible thickness, no studs, frame or box', () {
      for (final inst in [
        SignageCatalog.directWall,
        SignageCatalog.glassPasting,
      ]) {
        final b = _board(SignageCatalog.plainVinyl, inst: inst);
        final m = _model(b);
        final ids = m.components.map((c) => c.id).toSet();
        expect(ids, isNot(contains('standoffs')));
        expect(ids, isNot(contains('frame')));
        final film = m.solidsOf('vinyl_layer').single;
        final zs = [
          for (final f in film.faces)
            for (final p in f.points) p.z,
        ];
        final t =
            zs.reduce((a, c) => a > c ? a : c) -
            zs.reduce((a, c) => a < c ? a : c);
        expect(t * 304.8, lessThan(1));
        expect(_faces(m).any((f) => f.emissive), isFalse);
      }
    });
  });

  group('Shared controls', () {
    test('every media gets the full 360° turn without distortion state', () {
      for (final media in SignageCatalog.catalogCodes) {
        final b = _board(media);
        final c = LivePreviewController(board: b, photo: b.photos.first)
          ..addUnit('b_u1');
        for (final deg in [0, 90, 180, 270, 360]) {
          c.setYaw(deg * 3.141592653589793 / 180);
          final y = c.selected!.yaw;
          expect(y.isFinite, isTrue, reason: media);
          expect(y.abs(), lessThanOrEqualTo(3.1416), reason: '$media $deg');
        }
      }
    });
  });
}
