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

  /// [yaw] picks the review angle (radians). The default is the existing
  /// front isometric view; [kRearIsoYaw] shows the opposite side.
  Future<ReportImage?> model(
    SignageModelSpec spec, {
    String brand = 'ADINN',
    double yaw = kFrontIsoYaw,
  });
}

/// Front isometric review angle used by the measurement sheet.
const kFrontIsoYaw = 0.6;

/// Opposite-side isometric angle (front + 180 degrees), so the rear face of a
/// double-sided board is visible. Rendering is offscreen: the user's own 3D
/// camera is never touched.
const kRearIsoYaw = kFrontIsoYaw + 3.141592653589793;

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
  Future<ReportImage?> model(
    SignageModelSpec spec, {
    String brand = 'ADINN',
    double yaw = kFrontIsoYaw,
  }) {
    final model = ParametricModelBuilder.build(spec, brand: brand);
    return _png((c) {
      c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
      Scene3DPainter(
        scene: model.scene,
        camera: Camera3D(yaw: yaw, pitch: 0.22),
        paintGizmo: false,
      ).paint(c, size);
    });
  }
}
