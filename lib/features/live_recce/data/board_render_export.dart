import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../drawing/drawing_2d_painter.dart';
import '../../drawing/signage_geometry.dart';
import '../../preview3d/renderer_painter.dart';
import '../../preview3d/signage_scene_builder.dart';

/// Draws a painter to a PNG picture without putting it on the screen (so a board's 2D drawing and 3D preview can be sent to the server).
Future<Uint8List> paintToPng(CustomPainter painter, Size size, {double pixelRatio = 1.5, Color background = Colors.white}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  canvas.drawRect(Offset.zero & size, Paint()..color = background);
  painter.paint(canvas, size);
  final image = await recorder.endRecording().toImage((size.width * pixelRatio).round(), (size.height * pixelRatio).round());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('The picture could not be made');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// The technical drawing sheet of one board, as PNG.
Future<Uint8List> drawing2dPng(SignageGeometry geo, DrawingInfo info) {
  const sheet = Drawing2DPainter.sheet;
  return paintToPng(Drawing2DPainter(geo: geo, info: info, brand: info.projectName), sheet, pixelRatio: 1600 / sheet.width);
}

/// The 3D preview of one board from the usual start view (slightly from the side and above), as PNG.
Future<Uint8List> view3dPng(SignageGeometry geo, {required String brand}) {
  final scene = SignageSceneBuilder.build(geo, brand: brand);
  final face = geo.isFlangeBracket ? math.pi / 2 : 0.0;
  const size = Size(1200, 800);
  return paintToPng(Scene3DPainter(scene: scene, camera: Camera3D(yaw: face + 0.55, pitch: 0.28)), size, pixelRatio: 1.0, background: const Color(0xFFF4F5F7));
}
