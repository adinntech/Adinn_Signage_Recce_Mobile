import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../annotation/annotation_painter.dart';
import '../photos/site_photo_view.dart';
import 'site_markup_painter.dart';

/// Decodes an image file downscaled so its long side is ≤ [maxSide]
/// (decoding at the target size keeps memory low for large camera photos).
/// Returns null when the file is missing or unreadable.
Future<ui.Image?> decodeImageFile(String path, {int maxSide = 2048}) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return decodeImageBytes(bytes, maxSide: maxSide);
  } catch (_) {
    return null;
  }
}

Future<ui.Image?> decodeImageBytes(
  Uint8List bytes, {
  int maxSide = 2048,
}) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width, h = descriptor.height;
    final k = math.min(1.0, maxSide / math.max(w, h));
    final codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (w * k).round()),
      targetHeight: math.max(1, (h * k).round()),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  } catch (_) {
    return null;
  }
}

/// Size a photo is rendered at with its long side ≤ [maxSide].
Size renderSizeOf(SitePhoto photo, int maxSide) {
  final iw = photo.width <= 0 ? 1200.0 : photo.width.toDouble();
  final ih = photo.height <= 0 ? 900.0 : photo.height.toDouble();
  final k = math.min(1.0, maxSide / math.max(iw, ih));
  return Size((iw * k).roundToDouble(), (ih * k).roundToDouble());
}

/// Renders a site photo (file or built-in demo photo) with optional classic
/// annotations and advanced markup into a new image. The original photo
/// file is only read, never modified. Returns null if the photo is missing.
Future<ui.Image?> renderPhotoComposite(
  SitePhoto photo, {
  int maxSide = 1600,
  bool annotations = false,
  SiteMarkup? markup,
  MarkupLabels? labels,
  Set<MarkupLayer> hiddenLayers = const {},
}) async {
  final size = renderSizeOf(photo, maxSide);
  ui.Image? source;
  if (!photo.isDemo) {
    source = await decodeImageFile(photo.path, maxSide: maxSide);
    if (source == null) return null;
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final dst = Offset.zero & size;
  if (source == null) {
    DemoShopfrontPainter(photo.demoSeed).paint(canvas, size);
  } else {
    canvas.drawImageRect(
      source,
      Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    source.dispose();
  }
  if (annotations) {
    AnnotationPainter(
      annotations: photo.annotations,
      imageSize: Size(photo.width.toDouble(), photo.height.toDouble()),
    ).paint(canvas, size);
  }
  if (markup != null && !markup.isEmpty) {
    SiteMarkupPainter(
      markup: markup,
      labels: labels ?? MarkupLabels(const {}),
      hiddenLayers: hiddenLayers,
    ).paint(canvas, size);
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(size.width.round(), size.height.round());
  } finally {
    picture.dispose();
  }
}

/// PNG bytes of [image] (the image is not disposed).
Future<Uint8List?> encodePng(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

/// Raw RGBA bytes of [image] (for JPEG compression off the UI isolate).
Future<Uint8List?> rgbaBytes(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data?.buffer.asUint8List();
}
