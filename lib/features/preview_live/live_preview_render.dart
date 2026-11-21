import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../photos/site_photo_view.dart';
import '../preview3d/renderer_painter.dart';
import '../preview3d/scene3d.dart';

/// Render view of a GSB preview. Day = the photo as captured; Night = an
/// illustrative evening simulation (never a measured lighting result).
enum RenderView { day, night }

extension RenderViewX on RenderView {
  String get label => switch (this) {
    RenderView.day => 'Day View',
    RenderView.night => 'Night View',
  };

  IconData get icon => switch (this) {
    RenderView.day => Icons.wb_sunny_outlined,
    RenderView.night => Icons.nightlight_round,
  };
}

/// Camera distance (scene radii) for models placed on photos: a longer,
/// photographic distance than the orbit preview, so turning the board shows
/// natural foreshortening instead of exaggerated keystone stretching.
const double kOverlayDistanceFactor = 4.0;

/// Soft-blue evening grade for the site photo (offsets in 0..255). Keeps
/// building and shop visible: white → light blue, mid-grey → ~30 %.
const List<double> kNightPhotoMatrix = [
  0.36, 0.07, 0.03, 0, 6, //
  0.06, 0.46, 0.06, 0, 10, //
  0.07, 0.14, 0.68, 0, 30, //
  0, 0, 0, 1, 0,
];

const ColorFilter kNightPhotoFilter = ColorFilter.matrix(kNightPhotoMatrix);

const kNightDisclaimer =
    'Night View is an illustrative visual simulation, not a measured '
    'lighting or illumination guarantee.';

/// Slightly darker sky: a navy gradient over the top of the photo.
void paintNightSky(Canvas canvas, Size size) {
  final rect = Offset.zero & size;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0, 0.45, 1],
        colors: [Color(0x661A2547), Color(0x001A2547), Color(0x14000814)],
      ).createShader(rect),
  );
}

class NightSkyPainter extends CustomPainter {
  const NightSkyPainter();

  @override
  void paint(Canvas canvas, Size size) => paintNightSky(canvas, size);

  @override
  bool shouldRepaint(covariant NightSkyPainter oldDelegate) => false;
}

/// Decodes the site photo once (null for demo photos / missing files).
Future<ui.Image?> loadPhotoImage(SitePhoto photo) async {
  if (photo.isDemo) return null;
  final file = File(photo.path);
  if (!await file.exists()) return null;
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// Offscreen composition of a Live Preview: the SAME photo-relative overlay
/// transforms the editor shows, rendered at photo resolution. Day and night
/// differ only in colour grading and render-only glow – the board position,
/// size, turn, perspective and rotation come from one saved placement.
class LivePreviewComposer {
  LivePreviewComposer({
    required this.photo,
    required this.image,
    required this.overlays,
    required this.sceneFor,
    this.logicalWidth = 400,
  });

  final SitePhoto photo;

  /// Decoded photo ([loadPhotoImage]); null = demo photo painter.
  final ui.Image? image;
  final List<PreviewOverlay> overlays;
  final Scene Function(PreviewOverlay o) sceneFor;

  /// Width the overlay math is evaluated at (≈ on-screen stage width) so
  /// outlines and labels keep their on-screen proportions.
  final double logicalWidth;

  Size get _logical {
    final iw = math.max(1, photo.width).toDouble();
    final ih = math.max(1, photo.height).toDouble();
    return Size(logicalWidth, logicalWidth * ih / iw);
  }

  /// PNG of the composition. [models] false = original photo only.
  Future<Uint8List?> render({
    RenderView view = RenderView.day,
    bool models = true,
    bool dimensions = false,
    int maxSide = 2048,
  }) async {
    final iw = photo.width.toDouble(), ih = photo.height.toDouble();
    if (iw <= 0 || ih <= 0) return null;
    final k = math.min(1.0, maxSide / math.max(iw, ih));
    final outW = math.max(1, (iw * k).round());
    final outH = math.max(1, (ih * k).round());
    final logical = _logical;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(outW / logical.width, outH / logical.height);
    paint(canvas, logical, view: view, models: models, dimensions: dimensions);
    final picture = recorder.endRecording();
    final out = await picture.toImage(outW, outH);
    picture.dispose();
    try {
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      out.dispose();
    }
  }

  void paint(
    Canvas canvas,
    Size size, {
    required RenderView view,
    bool models = true,
    bool dimensions = false,
  }) {
    final night = view == RenderView.night;
    final rect = Offset.zero & size;
    if (night) {
      canvas.saveLayer(rect, Paint()..colorFilter = kNightPhotoFilter);
    }
    final img = image;
    if (img == null) {
      DemoShopfrontPainter(photo.demoSeed).paint(canvas, size);
    } else {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    if (night) {
      canvas.restore();
      paintNightSky(canvas, size);
    }
    if (!models) return;
    for (final o in overlays) {
      final side = math.max(o.scale * size.width, 1.0);
      canvas.save();
      canvas.translate(o.cx * size.width, o.cy * size.height);
      canvas.rotate(o.rotation);
      canvas.translate(-side / 2, -side / 2);
      final box = Rect.fromLTWH(0, 0, side, side);
      final faded = o.opacity < 1;
      if (faded) {
        canvas.saveLayer(
          box,
          Paint()..color = Color.fromRGBO(0, 0, 0, o.opacity),
        );
      }
      Scene3DPainter(
        scene: sceneFor(o),
        camera: Camera3D(yaw: o.yaw, pitch: o.pitch),
        showDimensions: dimensions,
        paintBackground: false,
        paintGround: false,
        paintGizmo: false,
        night: night,
        distanceFactor: kOverlayDistanceFactor,
      ).paint(canvas, Size(side, side));
      if (faded) canvas.restore();
      canvas.restore();
    }
  }
}
