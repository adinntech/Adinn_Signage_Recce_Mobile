import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../data/models/models.dart';
import '../../data/storage/media_storage.dart';
import '../annotation/annotation_painter.dart';
import '../photos/site_photo_view.dart';

/// PNG of what a [RepaintBoundary] currently shows.
Future<Uint8List?> captureBoundary(
  GlobalKey key, {
  double pixelRatio = 2,
}) async {
  final obj = key.currentContext?.findRenderObject();
  if (obj is! RenderRepaintBoundary) return null;
  final image = await obj.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Writes [png] to a new file in [folder] of the app's media storage.
Future<String> writePng(
  MediaStorage media,
  Uint8List png,
  String folder,
) async {
  final path = await media.newFilePath(folder, 'png');
  await File(path).writeAsBytes(png, flush: true);
  return path;
}

/// Renders the original photo plus its markings into a new PNG (the
/// original file is only read, never modified). Long side ≤ [maxSide].
Future<Uint8List?> renderAnnotatedPhoto(
  SitePhoto photo, {
  int maxSide = 2048,
  Set<AnnotationLayer> hiddenLayers = const {},
}) async {
  final iw = photo.width.toDouble(), ih = photo.height.toDouble();
  if (iw <= 0 || ih <= 0) return null;
  final k = math.min(1.0, maxSide / math.max(iw, ih));
  final size = Size(iw * k, ih * k);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final dst = Offset.zero & size;
  if (photo.isDemo) {
    DemoShopfrontPainter(photo.demoSeed).paint(canvas, size);
  } else {
    final raw = await readPhotoBytes(photo.path);
    if (raw == null) return null;
    final codec = await ui.instantiateImageCodec(raw);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    img.dispose();
    codec.dispose();
  }
  AnnotationPainter(
    annotations: photo.annotations,
    imageSize: Size(iw, ih),
    hiddenLayers: hiddenLayers,
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  final out = await picture.toImage(size.width.round(), size.height.round());
  picture.dispose();
  try {
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    out.dispose();
  }
}
