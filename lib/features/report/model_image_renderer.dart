import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model3d/parametric_builder.dart';
import '../model3d/signage_spec.dart';
import '../model3d/technical_drawing.dart';
import '../preview3d/renderer_painter.dart';
import 'report_pdf.dart';

/// Produces 2D drawing and 3D model pictures for the measurement PDF.
///
/// Renderer-independent: the PDF never screenshots a live view (a native
/// surface cannot always be captured). The default implementation paints
/// the pure-Dart renderer straight into an offscreen picture. When an image
/// cannot be produced, null is returned and the PDF says so instead of
/// inserting a wrong or generic model.
abstract class ModelImageRenderer {
  Future<ReportImage?> drawing(SignageModelSpec spec, DrawingView view);
  Future<ReportImage?> model(SignageModelSpec spec, {String brand = 'ADINN'});
}

/// Offscreen dart:ui rendering (no device surface involved).
class OffscreenModelImageRenderer implements ModelImageRenderer {
  const OffscreenModelImageRenderer({this.size = const Size(1200, 800)});

  final Size size;

  Future<ReportImage?> _png(void Function(Canvas canvas) paint) async {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder));
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.round(),
      size.height.round(),
    );
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return ReportImage(
        Uint8List.view(data.buffer),
        image.width,
        image.height,
      );
    } finally {
      image.dispose();
    }
  }

  @override
  Future<ReportImage?> drawing(SignageModelSpec spec, DrawingView view) => _png(
    (c) => TechnicalDrawingPainter(spec: spec, view: view).paint(c, size),
  );

  @override
  Future<ReportImage?> model(SignageModelSpec spec, {String brand = 'ADINN'}) {
    final model = ParametricModelBuilder.build(spec, brand: brand);
    return _png((c) {
      c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
      Scene3DPainter(
        scene: model.scene,
        camera: const Camera3D(yaw: 0.6, pitch: 0.22),
        paintGizmo: false,
      ).paint(c, size);
    });
  }
}
