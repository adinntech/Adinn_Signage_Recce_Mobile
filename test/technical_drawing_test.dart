import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/features/model3d/signage_spec.dart';
import 'package:signage_recce/features/model3d/technical_drawing.dart';

SignageModelSpec _spec(String media, String inst, {bool ds = false}) {
  final b = Board(
    id: 'b',
    name: 'B',
    mediaCode: media,
    installationCode: inst,
    width: 8,
    height: 3,
    doubleSided: ds,
  );
  return SignageModelSpec.of(b, b.units.first);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every catalog media × installation × view paints', () {
    for (final m in SignageCatalog.catalogMedia) {
      for (final inst in m.installations) {
        final spec = _spec(m.code, inst);
        for (final v in DrawingView.values) {
          final r = ui.PictureRecorder();
          TechnicalDrawingPainter(
            spec: spec,
            view: v,
          ).paint(Canvas(r), const Size(600, 400));
          r.endRecording().dispose();
          expect(drawingDimensions(spec, v), isNotEmpty, reason: '$m $inst $v');
        }
      }
    }
  });

  test('2D dimensions read the same canonical values as the spec', () {
    final b = Board(
      id: 'b',
      name: 'B',
      mediaCode: SignageCatalog.gsb,
      installationCode: SignageCatalog.doublePole,
      width: 10,
      height: 4,
    );
    final u = b.units.first;
    u.measurements.valuesMm['pole_spacing'] = 2000;
    u.measurements.valuesMm['bottom_height'] = 2743.2;
    final spec = SignageModelSpec.of(b, u);
    final front = {
      for (final d in drawingDimensions(spec, DrawingView.front)) d.id: d,
    };
    expect(front['width']!.valueMm, closeTo(3048, 1e-9));
    expect(front['height']!.valueMm, closeTo(1219.2, 1e-9));
    expect(front['pole_spacing']!.valueMm, 2000);
    expect(front['mounting']!.valueMm, 2743.2);
    expect(spec.sources[SpecField.poleSpacing], SpecSource.recorded);
    expect(spec.isAssumed(SpecField.poleEmbedment), isTrue);
  });

  testWidgets('renders a PNG for the PDF', (tester) async {
    final png = await tester.runAsync(
      () => renderTechnicalDrawingPng(
        _spec(SignageCatalog.mdfGsbDouble, SignageCatalog.doublePole),
        DrawingView.front,
        size: const Size(300, 200),
      ),
    );
    expect(png, isNotNull);
    expect(png!.sublist(1, 4), [0x50, 0x4E, 0x47]);
  });
}
