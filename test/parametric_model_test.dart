import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/features/drawing/signage_geometry.dart';
import 'package:signage_recce/features/model3d/parametric_builder.dart';
import 'package:signage_recce/features/model3d/signage_spec.dart';
import 'package:signage_recce/features/preview3d/renderer_painter.dart';
import 'package:signage_recce/features/preview3d/scene3d.dart';
import 'package:signage_recce/features/preview3d/signage_scene_builder.dart';

const _ft = 304.8;

SignageModelSpec _spec(
  String media, {
  String? inst,
  double w = 8,
  double h = 3,
  bool? ds,
  Map<String, double> mm = const {},
  Map<String, double> counts = const {},
  MeasureUnit unit = MeasureUnit.ft,
}) {
  final b = Board(
    id: 'g',
    name: 'G',
    mediaCode: media,
    installationCode: inst ?? SignageCatalog.media(media)!.installations.first,
    width: w,
    height: h,
    unit: unit,
    doubleSided: ds,
  );
  final u = b.units.first;
  u.measurements.valuesMm.addAll(mm);
  u.measurements.counts.addAll(counts);
  return SignageModelSpec.of(b, u);
}

ParametricModel _build(SignageModelSpec s, {bool context = true}) =>
    ParametricModelBuilder.build(s, context: context);

Set<String> _ids(ParametricModel m) =>
    m.scene.solids.map((s) => ModelComponentIds.of(s.name)).toSet();

({Vec3 min, Vec3 max}) _bounds(ParametricModel m, List<String> ids) {
  var x0 = double.infinity, y0 = double.infinity, z0 = double.infinity;
  var x1 = -double.infinity, y1 = -double.infinity, z1 = -double.infinity;
  for (final id in ids) {
    final bb = m.boundsOf(id)!;
    x0 = bb.min.x < x0 ? bb.min.x : x0;
    y0 = bb.min.y < y0 ? bb.min.y : y0;
    z0 = bb.min.z < z0 ? bb.min.z : z0;
    x1 = bb.max.x > x1 ? bb.max.x : x1;
    y1 = bb.max.y > y1 ? bb.max.y : y1;
    z1 = bb.max.z > z1 ? bb.max.z : z1;
  }
  return (min: Vec3(x0, y0, z0), max: Vec3(x1, y1, z1));
}

void _expectSize(
  ({Vec3 min, Vec3 max}) bb, {
  required double wMm,
  required double hMm,
  double? dMm,
  String reason = '',
}) {
  expect(bb.max.x - bb.min.x, closeTo(wMm / _ft, 1e-6), reason: reason);
  expect(bb.max.y - bb.min.y, closeTo(hMm / _ft, 1e-6), reason: reason);
  if (dMm != null) {
    expect(bb.max.z - bb.min.z, closeTo(dMm / _ft, 1e-6), reason: reason);
  }
}

/// Vertical pole shafts standing on the ground (excludes embedment / arms).
List<({Vec3 min, Vec3 max})> _poleShafts(ParametricModel m) {
  final out = <({Vec3 min, Vec3 max})>[];
  for (final s in m.solidsOf('poles')) {
    final pts = [for (final f in s.faces) ...f.points];
    final ys = pts.map((p) => p.y);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    if (minY.abs() < 1e-9 && maxY > 1) {
      final xs = pts.map((p) => p.x);
      final zs = pts.map((p) => p.z);
      out.add((
        min: Vec3(xs.reduce((a, b) => a < b ? a : b), minY, zs.first),
        max: Vec3(xs.reduce((a, b) => a > b ? a : b), maxY, zs.first),
      ));
    }
  }
  return out;
}

void _paintOnce(Scene scene) {
  for (final cam in const [
    Camera3D(),
    Camera3D(yaw: 0, pitch: 0),
    Camera3D(yaw: 3.14, pitch: 0.3),
  ]) {
    final recorder = ui.PictureRecorder();
    Scene3DPainter(
      scene: scene,
      camera: cam,
    ).paint(Canvas(recorder), const Size(240, 240));
    recorder.endRecording().dispose();
  }
}

void main() {
  group('templates', () {
    test('every catalog media maps to its template', () {
      const expected = {
        SignageCatalog.gsb: 'gsb',
        SignageCatalog.nlb: 'nonlit',
        SignageCatalog.foamVinyl: 'foam',
        SignageCatalog.clearAcrylic: 'acrylic',
        SignageCatalog.sandwichBoard: 'sandwich',
        SignageCatalog.oneWayVision: 'owv',
        SignageCatalog.plainVinyl: 'vinyl',
        SignageCatalog.acp2d: 'acp2d',
        SignageCatalog.acp2dDouble: 'acp2d',
        SignageCatalog.acp: 'acp3d',
        SignageCatalog.acp3dDouble: 'acp3d',
        SignageCatalog.mdfGsb: 'mdfgsb',
        SignageCatalog.mdfGsbDouble: 'mdfgsb',
      };
      expect(expected.keys.toSet(), SignageCatalog.catalogCodes.toSet());
      for (final e in expected.entries) {
        final m = _build(_spec(e.key));
        expect(m.templateId, e.value, reason: e.key);
        expect(m.isSupported, isTrue, reason: e.key);
      }
    });

    test('templates are visibly distinct', () {
      Set<String> ids(String media) =>
          _ids(_build(_spec(media), context: false));
      // Finished exterior only: no internal frame / rear support pipes.
      expect(
        ids(SignageCatalog.gsb),
        containsAll(['display_panel', 'front_face']),
      );
      expect(ids(SignageCatalog.gsb), isNot(contains('rear_supports')));
      expect(ids(SignageCatalog.gsb), isNot(contains('frame')));
      expect(
        _build(
          _spec(SignageCatalog.gsb),
        ).solidsOf('front_face').single.faces.single.emissive,
        isTrue,
      );
      final nlb = _build(_spec(SignageCatalog.nlb));
      expect(_ids(nlb), contains('frame'));
      expect(_ids(nlb), isNot(contains('rear_supports')));
      expect(
        nlb.scene.solids
            .expand((s) => [...s.faces, ...s.decals])
            .where((f) => f.emissive),
        isEmpty,
        reason: 'non-lit board has no emissive face',
      );
      final foam = ids(SignageCatalog.foamVinyl);
      expect(foam, containsAll(['display_panel', 'vinyl_layer']));
      expect(foam, isNot(contains('frame')));
      expect(foam, isNot(contains('poles')));
      expect(ids(SignageCatalog.plainVinyl), {'vinyl_layer'});
      expect(
        ids(SignageCatalog.oneWayVision),
        containsAll(['vinyl_layer', 'glass_backing']),
      );
      expect(ids(SignageCatalog.acp2d), contains('front_face'));
      expect(
        ids(SignageCatalog.acp2d),
        isNot(contains('raised_letters_front')),
      );
      expect(ids(SignageCatalog.acp), contains('raised_letters_front'));
      expect(
        ids(SignageCatalog.mdfGsb),
        containsAll(['mdf_backing', 'gsb_box', 'illuminated_surface']),
      );
      expect(
        ids(SignageCatalog.sandwichBoard),
        containsAll(['display_panel', 'frame', 'stand_base', 'back_face']),
      );
    });

    test('panel width / height / depth match the spec', () {
      final mm = {'board_depth': 200.0};
      for (final code in [SignageCatalog.gsb, SignageCatalog.nlb]) {
        final s = _spec(code, mm: mm);
        _expectSize(
          _build(s).boundsOf('display_panel')!,
          wMm: s.widthMm,
          hMm: s.heightMm,
          dMm: 200,
          reason: code,
        );
      }
      for (final code in [
        SignageCatalog.foamVinyl,
        SignageCatalog.clearAcrylic,
      ]) {
        final s = _spec(code, mm: {'material_thickness': 6});
        _expectSize(
          _build(s).boundsOf('display_panel')!,
          wMm: s.widthMm,
          hMm: s.heightMm,
          dMm: 6,
          reason: code,
        );
      }
      for (final code in [
        SignageCatalog.acp2d,
        SignageCatalog.acp2dDouble,
        SignageCatalog.acp,
        SignageCatalog.acp3dDouble,
      ]) {
        final s = _spec(code, mm: mm);
        final m = _build(s);
        _expectSize(
          _bounds(m, ['display_panel', 'side_returns']),
          wMm: s.widthMm,
          hMm: s.heightMm,
          dMm: 200,
          reason: code,
        );
      }
      for (final code in [
        SignageCatalog.oneWayVision,
        SignageCatalog.plainVinyl,
      ]) {
        final s = _spec(code);
        _expectSize(
          _build(s).boundsOf('vinyl_layer')!,
          wMm: s.widthMm,
          hMm: s.heightMm,
          dMm: SignageCatalog.media(code)!.thicknessMm,
          reason: code,
        );
      }
      final mdf = _spec(
        SignageCatalog.mdfGsb,
        mm: {
          'gsb_panel_width': 1500,
          'gsb_panel_height': 600,
          'gsb_depth': 120,
          'mdf_thickness': 25,
        },
      );
      final mm2 = _build(mdf);
      _expectSize(mm2.boundsOf('gsb_box')!, wMm: 1500, hMm: 600, dMm: 120);
      _expectSize(
        mm2.boundsOf('mdf_backing')!,
        wMm: mdf.widthMm,
        hMm: mdf.heightMm,
        dMm: 25,
      );
    });

    test('units: inch spec gives the same model, labels in inches', () {
      final ft = _build(_spec(SignageCatalog.gsb));
      final inch = _build(
        _spec(SignageCatalog.gsb, w: 96, h: 36, unit: MeasureUnit.inch),
      );
      final a = ft.boundsOf('display_panel')!,
          b = inch.boundsOf('display_panel')!;
      expect(b.max.x - b.min.x, closeTo(a.max.x - a.min.x, 1e-9));
      expect(ft.dimension('width')!.label, 'W 8 ft');
      expect(inch.dimension('width')!.label, 'W 96 in');
      expect(ft.dimension('height')!.label, 'H 3 ft');
    });
  });

  group('sidedness', () {
    bool rearEmissive(ParametricModel m) => m.scene.solids
        .expand((s) => [...s.faces, ...s.decals])
        .any((f) => f.emissive && f.normal.z < -0.5);

    test('back face / rear glow only for double-sided', () {
      for (final code in [SignageCatalog.gsb, SignageCatalog.nlb]) {
        final single = _build(_spec(code, ds: false));
        final double = _build(
          _spec(code, ds: true, inst: SignageCatalog.doublePole),
        );
        expect(_ids(single), isNot(contains('back_face')), reason: code);
        expect(_ids(double), contains('back_face'), reason: code);
        expect(
          double.scene.faceCount,
          isNot(single.scene.faceCount),
          reason: code,
        );
      }
      expect(
        rearEmissive(_build(_spec(SignageCatalog.gsb, ds: false))),
        isFalse,
      );
      expect(rearEmissive(_build(_spec(SignageCatalog.gsb, ds: true))), isTrue);

      for (final (s, d) in [
        (SignageCatalog.acp2d, SignageCatalog.acp2dDouble),
        (SignageCatalog.acp, SignageCatalog.acp3dDouble),
        (SignageCatalog.mdfGsb, SignageCatalog.mdfGsbDouble),
      ]) {
        final inst = SignageCatalog.supportPipe; // allowed for both
        final single = _build(_spec(s, inst: inst));
        final double = _build(_spec(d, inst: inst));
        expect(_ids(single), isNot(contains('back_face')), reason: s);
        // Rear display: flat artwork / rear glow, or rear raised letters.
        expect(
          _ids(double).intersection({'back_face', 'raised_letters_back'}),
          isNotEmpty,
          reason: d,
        );
        expect(
          _ids(single).intersection({'back_face', 'raised_letters_back'}),
          isEmpty,
          reason: s,
        );
        expect(
          double.solidsOf('display_panel').length +
              double.solidsOf('gsb_box').length,
          greaterThan(
            single.solidsOf('display_panel').length +
                single.solidsOf('gsb_box').length,
          ),
          reason: d,
        );
      }
      expect(rearEmissive(_build(_spec(SignageCatalog.mdfGsbDouble))), isTrue);
      expect(rearEmissive(_build(_spec(SignageCatalog.mdfGsb))), isFalse);
      expect(
        _ids(
          _build(_spec(SignageCatalog.acp, inst: SignageCatalog.supportPipe)),
        ),
        isNot(contains('raised_letters_back')),
      );
      expect(
        _ids(_build(_spec(SignageCatalog.acp3dDouble))),
        contains('raised_letters_back'),
      );
    });
  });

  group('installations', () {
    test('support structure follows the installation', () {
      const expected = {
        SignageCatalog.shopFascia: ['wall_brackets', 'wall'],
        SignageCatalog.wallMount: ['wall_brackets', 'wall'],
        SignageCatalog.supportPipe: ['support_pipes', 'wall'],
        SignageCatalog.singlePole: ['poles', 'ground'],
        SignageCatalog.doublePole: ['poles', 'ground'],
        SignageCatalog.rooftop: ['rooftop_frame', 'wall'],
      };
      for (final e in expected.entries) {
        final m = _build(_spec(SignageCatalog.gsb, inst: e.key));
        expect(_ids(m), containsAll(e.value), reason: e.key);
        for (final other in ['poles', 'support_pipes', 'rooftop_frame']) {
          if (e.value.contains(other)) continue;
          expect(_ids(m), isNot(contains(other)), reason: e.key);
        }
      }
      final direct = _build(
        _spec(SignageCatalog.plainVinyl, inst: SignageCatalog.directWall),
      );
      expect(_ids(direct), containsAll(['vinyl_layer', 'wall']));
      expect(_ids(direct), isNot(contains('wall_brackets')));
      final glass = _build(
        _spec(SignageCatalog.plainVinyl, inst: SignageCatalog.glassPasting),
      );
      expect(_ids(glass), contains('glass_backing'));
      final sandwich = _build(_spec(SignageCatalog.sandwichBoard));
      expect(_ids(sandwich), containsAll(['frame', 'stand_base']));
    });

    test('single vs double pole count and centre spacing', () {
      final one = _build(
        _spec(SignageCatalog.gsb, inst: SignageCatalog.singlePole),
      );
      expect(_poleShafts(one), hasLength(1));
      final s = _spec(
        SignageCatalog.gsb,
        inst: SignageCatalog.doublePole,
        mm: {'pole_spacing': 1500},
      );
      final two = _build(s);
      final shafts = _poleShafts(two);
      expect(shafts, hasLength(2));
      double cx(({Vec3 min, Vec3 max}) b) => (b.min.x + b.max.x) / 2;
      expect((cx(shafts[1]) - cx(shafts[0])).abs(), closeTo(1500 / _ft, 1e-6));
      expect(two.dimension('pole_spacing')!.valueMm, closeTo(1500, 1e-6));
      expect(two.dimension('pole_spacing')!.field, SpecField.poleSpacing);

      // Changing the pole spacing moves the poles only.
      final wider = _build(s.copyWith(values: {SpecField.poleSpacing: 2000}));
      final a = two.boundsOf('display_panel')!,
          b = wider.boundsOf('display_panel')!;
      expect(b.min, a.min);
      expect(b.max, a.max);
      final shafts2 = _poleShafts(wider);
      expect(
        (cx(shafts2[1]) - cx(shafts2[0])).abs(),
        closeTo(2000 / _ft, 1e-6),
      );
    });

    test('pole height and embedment below ground', () {
      final s = _spec(
        SignageCatalog.acp2dDouble,
        inst: SignageCatalog.singlePole,
        mm: {'pole_embedment': 1200},
      );
      final m = _build(s);
      final poles = m.boundsOf('poles')!;
      expect(poles.min.y, closeTo(-1200 / _ft, 1e-9));
      expect(m.dimension('pole_embedment')!.valueMm, closeTo(1200, 1e-6));
      expect(
        m.dimension('pole_height')!.valueMm,
        closeTo(s[SpecField.poleHeight], 1e-6),
      );
      final embedded = m
          .solidsOf('poles')
          .where(
            (p) => p.faces.every((f) => f.points.every((q) => q.y <= 1e-9)),
          );
      expect(embedded, isNotEmpty);
      expect(
        embedded.every((p) => p.faces.every((f) => f.color.a < 1)),
        isTrue,
        reason: 'embedment is translucent',
      );
    });

    test('mounting height = panel bottom; changes move the board', () {
      for (final (code, inst, id) in [
        (SignageCatalog.gsb, SignageCatalog.wallMount, 'display_panel'),
        (SignageCatalog.nlb, SignageCatalog.doublePole, 'display_panel'),
        (
          SignageCatalog.clearAcrylic,
          SignageCatalog.shopFascia,
          'display_panel',
        ),
        (SignageCatalog.mdfGsb, SignageCatalog.supportPipe, 'mdf_backing'),
        (
          SignageCatalog.sandwichBoard,
          SignageCatalog.freeStanding,
          'display_panel',
        ),
        (
          SignageCatalog.oneWayVision,
          SignageCatalog.glassPasting,
          'vinyl_layer',
        ),
      ]) {
        final s = _spec(code, inst: inst, mm: {'bottom_height': 2500});
        final m = _build(s);
        expect(m.boundsOf(id)!.min.y, closeTo(2500 / _ft, 1e-9), reason: code);
        final up = _build(s.copyWith(values: {SpecField.mountingHeight: 3000}));
        expect(up.boundsOf(id)!.min.y, closeTo(3000 / _ft, 1e-9), reason: code);
        final a = m.boundsOf(id)!, b = up.boundsOf(id)!;
        expect(b.max.x - b.min.x, closeTo(a.max.x - a.min.x, 1e-9));
      }
    });

    test('rooftop: roof level = mounting height − frame height', () {
      final s = _spec(
        SignageCatalog.gsb,
        inst: SignageCatalog.rooftop,
        mm: {'bottom_height': 20 * _ft, 'rooftop_frame_height': 5 * _ft},
      );
      final m = _build(s);
      expect(m.boundsOf('rooftop_frame')!.min.y, closeTo(15, 1e-9));
      expect(m.boundsOf('wall')!.max.y, closeTo(15, 1e-9));
      expect(
        m.dimension('rooftop_frame_height')!.valueMm,
        closeTo(5 * _ft, 1e-6),
      );
    });

    test('support pipes: count, length and spacing clamped to the width', () {
      final s = _spec(
        SignageCatalog.acp2d,
        inst: SignageCatalog.supportPipe,
        mm: {'pipe_length': 600, 'pipe_spacing': 3000},
        counts: {'pipe_count': 3},
        w: 4,
      );
      final m = _build(s);
      final pipes = m.boundsOf('support_pipes')!;
      expect(pipes.min.x, greaterThanOrEqualTo(-2 - 1e-9));
      expect(pipes.max.x, lessThanOrEqualTo(2 + 1e-9));
      expect(m.dimension('pipe_length')!.valueMm, closeTo(600, 1e-6));
      expect(m.dimension('pipe_spacing')!.valueMm, lessThan(3000));
      expect(m.notes, isNotEmpty);
      final pipeBeams = m
          .solidsOf('support_pipes')
          .where((p) => p.faces.length == 6);
      expect(pipeBeams.length, 6, reason: '3 pipes + 3 wall plates');
      // A wider board spreads the pipes to the requested spacing.
      final wide = _build(s.copyWith(values: {SpecField.width: 30 * _ft}));
      expect(wide.dimension('pipe_spacing')!.valueMm, closeTo(3000, 1e-6));
    });

    test('free-standing: sandwich A-frame touches the ground', () {
      final s = _spec(SignageCatalog.sandwichBoard, w: 2, h: 3);
      final m = _build(s);
      expect(m.boundsOf('stand_base')!.min.y, closeTo(0, 1e-9));
      expect(m.boundsOf('frame')!.min.y, greaterThanOrEqualTo(0));
      expect(_ids(m), containsAll(['front_face', 'back_face']));
      expect(
        m.boundsOf('display_panel')!.max.x - m.boundsOf('display_panel')!.min.x,
        closeTo(2, 1e-9),
      );
      // A wider opening angle spreads the legs further.
      final wide = _build(s.copyWith(values: {SpecField.openingAngle: 40}));
      expect(
        wide.dimension('spread')!.valueMm,
        greaterThan(m.dimension('spread')!.valueMm),
      );
      // Generic stand base for a free-standing rigid board.
      final nlb = SignageModelSpec(
        signageItemId: 'u',
        groupId: 'g',
        mediaCode: SignageCatalog.singleStandee,
        installationCode: SignageCatalog.freeStanding,
        isDoubleSided: false,
        template: '',
        legacyMedia: true,
        displayUnit: MeasureUnit.ft,
        values: {
          SpecField.width: 3 * _ft,
          SpecField.height: 4 * _ft,
          SpecField.mountingHeight: 2 * _ft,
          SpecField.baseWidth: 4 * _ft,
          SpecField.baseDepth: 2 * _ft,
        },
        sources: const {},
      );
      final st = _build(nlb);
      _expectSize(
        _bounds(st, ['stand_base']),
        wMm: 4 * _ft,
        hMm: 0.2 * _ft,
        dMm: 2 * _ft,
      );
      expect(st.dimension('base_width')!.label, 'Base W 4 ft');
    });
  });

  group('materials & letters', () {
    test('ACP 3D letter projection front / rear', () {
      final s = _spec(
        SignageCatalog.acp3dDouble,
        mm: {
          'board_depth': 150,
          'letter_depth_front': 60,
          'letter_depth_rear': 40,
        },
      );
      final m = _build(s);
      final front = m.boundsOf('raised_letters_front')!;
      expect(front.min.z, closeTo(0, 1e-9));
      expect(front.max.z, closeTo(60 / _ft, 1e-9));
      final back = m.boundsOf('raised_letters_back')!;
      expect(back.max.z, closeTo(-150 / _ft, 1e-9));
      expect(back.min.z, closeTo(-190 / _ft, 1e-9));
      expect(m.dimension('letter_depth_front')!.valueMm, closeTo(60, 1e-6));
      expect(m.dimension('letter_depth_rear')!.valueMm, closeTo(40, 1e-6));
      // Placeholder letters only (never the brand / a client logo).
      final labels = m
          .solidsOf('raised_letters_front')
          .expand((s) => s.faces)
          .map((f) => f.label)
          .whereType<String>()
          .toSet();
      expect(labels, isNotEmpty);
      expect('ABCDEFGH'.split('').toSet().containsAll(labels), isTrue);
    });

    test('acrylic is translucent; OWV film is perforated', () {
      final acrylic = _build(_spec(SignageCatalog.clearAcrylic));
      final panel = acrylic.solidsOf('display_panel').single;
      expect(panel.faces.every((f) => f.color.a < 1), isTrue);
      expect(
        panel.faces.map((f) => (f.color.a * 255).round()).every((a) => a < 255),
        isTrue,
      );
      final owv = _build(_spec(SignageCatalog.oneWayVision));
      final film = owv.solidsOf('vinyl_layer').single;
      // Perforation is a see-through mask on the film faces now (no mesh
      // dots): front and rear carry the pattern.
      expect(film.decals, isEmpty);
      expect(
        film.faces.where((f) => f.perforationPitchFt != null).length,
        greaterThanOrEqualTo(2),
      );
      expect(
        owv.solidsOf('glass_backing').single.faces.first.color.a,
        lessThan(1),
      );
    });

    test('acrylic standoffs only when the standoff is > 0', () {
      final s = _spec(SignageCatalog.clearAcrylic, mm: {'standoff_offset': 30});
      final m = _build(s);
      expect(_ids(m), contains('standoffs'));
      expect(_ids(m), isNot(contains('wall_brackets')));
      expect(m.dimension('standoff')!.valueMm, closeTo(30, 1e-6));
      expect(
        m.boundsOf('wall')!.max.z,
        closeTo(m.boundsOf('standoffs')!.min.z, 1e-9),
      );
      final flush = _build(s.copyWith(values: {SpecField.standoff: 0}));
      expect(_ids(flush), isNot(contains('standoffs')));
    });
  });

  group('robustness', () {
    test('every media × allowed installation × sidedness is finite', () {
      for (final code in SignageCatalog.catalogCodes) {
        final media = SignageCatalog.media(code)!;
        final sides = media.sidedness == MediaSidedness.selectable
            ? [false, true]
            : [null];
        for (final inst in media.installations) {
          for (final ds in sides) {
            final s = _spec(code, inst: inst, ds: ds);
            final m = _build(s);
            final why = '$code/$inst/$ds';
            expect(m.isSupported, isTrue, reason: why);
            expect(m.scene.solids, isNotEmpty, reason: why);
            final emb = s.has(SpecField.poleEmbedment)
                ? s[SpecField.poleEmbedment] / _ft
                : 0.0;
            for (final solid in m.scene.solids) {
              for (final f in [...solid.faces, ...solid.decals]) {
                expect(f.points.length, greaterThanOrEqualTo(3), reason: why);
                for (final p in f.points) {
                  expect(
                    p.x.isFinite && p.y.isFinite && p.z.isFinite,
                    isTrue,
                    reason: why,
                  );
                  expect(p.y, greaterThanOrEqualTo(-emb - 1e-9), reason: why);
                }
                expect(f.normal.length, closeTo(1, 1e-6), reason: why);
              }
            }
            for (final d in m.dimensions) {
              expect(d.valueMm.isFinite && d.valueMm > 0, isTrue, reason: why);
            }
            expect(m.scene.radius.isFinite, isTrue, reason: why);
            expect(m.scene.radius, greaterThan(0), reason: why);
            expect(m.scene.dims, hasLength(m.dimensions.length), reason: why);
            _paintOnce(m.scene);
          }
        }
      }
    });

    test('degenerate values are clamped, never NaN', () {
      final s = _spec(SignageCatalog.gsb, inst: SignageCatalog.doublePole)
          .copyWith(
            values: {
              SpecField.width: 0,
              SpecField.height: double.nan,
              SpecField.depth: -5,
              SpecField.poleSpacing: double.infinity,
              SpecField.mountingHeight: -100,
            },
          );
      final m = _build(s);
      for (final solid in m.scene.solids) {
        for (final f in solid.faces) {
          for (final p in f.points) {
            expect(p.x.isFinite && p.y.isFinite && p.z.isFinite, isTrue);
          }
        }
      }
      final bb = m.boundsOf('display_panel')!;
      expect(bb.max.x - bb.min.x, greaterThan(0));
      expect(bb.min.y, greaterThanOrEqualTo(0));
    });

    test('unsupported combination: message, no structure, no crash', () {
      final s = _spec(
        SignageCatalog.clearAcrylic,
        inst: SignageCatalog.singlePole,
      );
      // SignageModelSpec.of keeps the recorded installation as is.
      expect(s.installationCode, SignageCatalog.singlePole);
      final why = ParametricModelBuilder.unsupportedReason(s);
      expect(why, hasLength(1));
      expect(why.single, contains('not a supported installation'));
      expect(why.single, contains('Clear Acrylic'));
      final m = _build(s);
      expect(m.isSupported, isFalse);
      expect(m.unsupported, why);
      expect(_ids(m), contains('display_panel'));
      expect(_ids(m), isNot(contains('poles')));
      expect(_ids(m), isNot(contains('wall_brackets')));
      expect(
        ParametricModelBuilder.unsupportedReason(
          _spec(SignageCatalog.clearAcrylic, inst: SignageCatalog.wallMount),
        ),
        isEmpty,
      );
    });

    test('hidden components are omitted; highlight keeps geometry', () {
      final s = _spec(SignageCatalog.gsb, inst: SignageCatalog.doublePole);
      final plain = ParametricModelBuilder.build(s);
      final hidden = ParametricModelBuilder.build(
        s,
        hiddenComponents: {'front_face', 'poles'},
      );
      expect(_ids(hidden), isNot(contains('front_face')));
      expect(_ids(hidden), isNot(contains('poles')));
      expect(hidden.component('front_face')!.visible, isFalse);
      expect(hidden.component('display_panel')!.visible, isTrue);
      expect(
        hidden.components.map((c) => c.id),
        plain.components.map((c) => c.id),
      );

      final lit = ParametricModelBuilder.build(s, highlight: 'display_panel');
      final a = plain.solidsOf('display_panel').single;
      final b = lit.solidsOf('display_panel').single;
      for (var i = 0; i < a.faces.length; i++) {
        expect(b.faces[i].points, a.faces[i].points);
      }
      expect(b.faces.map((f) => f.color), isNot(a.faces.map((f) => f.color)));
      expect(lit.scene.solids.length, plain.scene.solids.length);

      // Editable fields come from the spec.
      expect(
        plain.component('poles')!.editable,
        containsAll([
          SpecField.poleSpacing,
          SpecField.poleHeight,
          SpecField.poleEmbedment,
        ]),
      );
      expect(
        plain.component('display_panel')!.editable,
        contains(SpecField.width),
      );
    });

    test('context and dimensions are optional; solids are named by id', () {
      final s = _spec(SignageCatalog.foamVinyl);
      final bare = ParametricModelBuilder.build(
        s,
        context: false,
        dimensions: false,
      );
      expect(_ids(bare).intersection(ModelComponentIds.contextIds), isEmpty);
      expect(bare.scene.dims, isEmpty);
      expect(bare.dimensions, isNotEmpty);
      const known = {
        'display_panel',
        'front_face',
        'back_face',
        'frame',
        'side_returns',
        'rear_supports',
        'wall_brackets',
        'standoffs',
        'poles',
        'support_pipes',
        'stand_base',
        'rooftop_frame',
        'illuminated_surface',
        'raised_letters_front',
        'raised_letters_back',
        'glass_backing',
        'vinyl_layer',
        'mdf_backing',
        'gsb_box',
        'wall',
        'ground',
      };
      for (final code in SignageCatalog.catalogCodes) {
        for (final inst in SignageCatalog.media(code)!.installations) {
          final m = _build(_spec(code, inst: inst));
          expect(known.containsAll(_ids(m)), isTrue, reason: '$code/$inst');
          for (final solid in m.scene.solids) {
            expect(
              RegExp(r'^[a-z_]+(:\d+)?$').hasMatch(solid.name),
              isTrue,
              reason: solid.name,
            );
          }
        }
      }
    });

    test('deterministic output', () {
      final s = _spec(
        SignageCatalog.acp3dDouble,
        inst: SignageCatalog.doublePole,
      );
      final a = _build(s), b = _build(s);
      expect(a.scene.faceCount, b.scene.faceCount);
      for (var i = 0; i < a.scene.solids.length; i++) {
        expect(a.scene.solids[i].name, b.scene.solids[i].name);
        expect(
          a.scene.solids[i].faces.first.points,
          b.scene.solids[i].faces.first.points,
        );
      }
    });
  });

  group('legacy scene builder routing', () {
    SignageGeometry geo(String media, [String? inst]) =>
        SignageGeometry.fromBoard(
          Board(
            id: 'b',
            name: 'B',
            mediaCode: media,
            installationCode:
                inst ?? SignageCatalog.media(media)!.installations.first,
            width: 8,
            height: 3,
          ),
        );

    test('GSB / NLB / ACP and legacy media keep the legacy builder', () {
      for (final code in [
        SignageCatalog.gsb,
        SignageCatalog.nlb,
        SignageCatalog.acp,
        SignageCatalog.flange,
        SignageCatalog.vinyl,
        SignageCatalog.singleStandee,
      ]) {
        final g = geo(code);
        expect(ParametricModelBuilder.routesGeometry(g), isFalse, reason: code);
        final names = SignageSceneBuilder.build(
          g,
        ).solids.map((s) => s.name).toSet();
        if (code != SignageCatalog.vinyl) {
          expect(names, contains('board'), reason: code); // vinyl = decal
        }
        expect(names, contains('person'), reason: code);
        expect(names, isNot(contains('display_panel')), reason: code);
      }
      final pole = SignageSceneBuilder.buildModel(
        geo(SignageCatalog.gsb, SignageCatalog.doublePole),
      ).solids.map((s) => s.name).toSet();
      expect(pole, containsAll(['board', 'pole']));
    });

    test('new media are routed to the parametric templates', () {
      for (final code in ParametricModelBuilder.routedMediaCodes) {
        for (final inst in SignageCatalog.media(code)!.installations) {
          final g = geo(code, inst);
          expect(ParametricModelBuilder.routesGeometry(g), isTrue);
          final model = SignageSceneBuilder.buildModel(g, dimensions: true);
          final names = model.solids.map((s) => s.name).toSet();
          expect(names, contains('board'), reason: '$code/$inst');
          expect(
            names.intersection(SignageSceneBuilder.contextSolids),
            isEmpty,
            reason: '$code/$inst',
          );
          expect(names, isNot(contains('ground')));
          expect(names, isNot(contains('glass_backing')));
          expect(model.dims, isNotEmpty);
          final full = SignageSceneBuilder.build(g);
          expect(full.solids.map((s) => s.name), contains('person'));
          _paintOnce(full);
        }
      }
      // The geometry adapter keeps size, mounting height and pole spacing.
      final g = SignageGeometry.fromBoard(
        Board(
          id: 'b',
          name: 'B',
          mediaCode: SignageCatalog.acp2dDouble,
          installationCode: SignageCatalog.doublePole,
          width: 10,
          height: 4,
          answers: {'pole_height': 12, 'pole_gap': 6},
        ),
      );
      final spec = ParametricModelBuilder.specFromGeometry(g);
      expect(spec.widthMm, closeTo(10 * _ft, 1e-6));
      expect(spec.mountingHeightMm, closeTo(12 * _ft, 1e-6));
      expect(spec[SpecField.poleSpacing], closeTo(6 * _ft, 1e-6));
      expect(spec.isDoubleSided, isTrue);
      final board = SignageSceneBuilder.buildModel(g).solids
          .where((s) => s.name == 'board')
          .expand((s) => s.faces)
          .expand((f) => f.points)
          .map((p) => p.y);
      expect(board.reduce((a, b) => a < b ? a : b), closeTo(12, 1e-9));
    });
  });
}
