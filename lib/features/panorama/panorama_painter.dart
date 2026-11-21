import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import 'panorama_view_state.dart';

/// How a placement looks: label and board aspect ratio (width / height).
class PlacementStyle {
  const PlacementStyle({required this.label, this.aspect = 2});

  final String label;
  final double aspect;
}

/// Geometry of one placement on screen.
class PlacementBox {
  const PlacementBox(this.center, this.size, this.rotationRad);

  final Offset center;
  final Size size;
  final double rotationRad;
}

PlacementBox placementBox(
  PanoramaPlacement p,
  PanoramaViewState view,
  Size viewSize, {
  double aspect = 2,
}) {
  final k = view.degPerPx(viewSize);
  final w = k == 0 ? 0.0 : p.widthDeg / k;
  final a = aspect.isFinite && aspect > 0.05 ? aspect : 2.0;
  return PlacementBox(
    view.screenOf(p.yawDeg, p.pitchDeg, viewSize),
    Size(w, w / a),
    p.rotationDeg * math.pi / 180,
  );
}

/// Draws the visible window of an equirectangular panorama (approximate
/// flat projection) and, for exported previews, the placements.
class PanoramaPainter extends CustomPainter {
  PanoramaPainter({
    required this.image,
    required this.view,
    this.placements = const [],
    this.styles = const {},
    this.selectedId,
    this.drawPlacements = false,
    this.revision = 0,
  });

  final ui.Image? image;
  final PanoramaViewState view;
  final List<PanoramaPlacement> placements;

  /// By unit id.
  final Map<String, PlacementStyle> styles;
  final String? selectedId;

  /// On screen the placements are interactive widgets; previews draw them.
  final bool drawPlacements;

  /// Bumped by the viewer whenever the (mutable) view state changes.
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF202124),
    );
    final img = image;
    if (img == null) {
      _grid(canvas, size);
    } else {
      _image(canvas, size, img);
    }
    if (drawPlacements) {
      for (final p in placements) {
        _placement(canvas, size, p);
      }
    }
  }

  void _image(Canvas canvas, Size size, ui.Image img) {
    final w = img.width.toDouble();
    final h = img.height.toDouble();
    final fovV = view.fovV(size);
    final left = view.yawDeg - view.fovH / 2;
    final top = view.pitchDeg + fovV / 2;
    var x0 = PanoramaViewState.imageX(left, w) % w;
    final sw = view.fovH / 360 * w;
    final y0 = PanoramaViewState.imageY(top, h);
    final sh = fovV / 180 * h;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (x0 < 0) x0 += w;
    if (x0 + sw <= w) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(x0, y0, sw, sh),
        Offset.zero & size,
        paint,
      );
    } else {
      // Wrap-around: the window crosses the image's right edge.
      final first = w - x0;
      final split = first / sw * size.width;
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(x0, y0, first, sh),
        Rect.fromLTWH(0, 0, split, size.height),
        paint,
      );
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, y0, sw - first, sh),
        Rect.fromLTWH(split, 0, size.width - split, size.height),
        paint,
      );
    }
  }

  /// Placeholder when the image is not loaded: a yaw / pitch grid.
  void _grid(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (var yaw = 0; yaw < 360; yaw += 30) {
      final x = view.screenOf(yaw.toDouble(), 0, size).dx;
      if (x >= 0 && x <= size.width) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      }
    }
    for (var pitch = -60; pitch <= 60; pitch += 30) {
      final y = view.screenOf(view.yawDeg, pitch.toDouble(), size).dy;
      if (y >= 0 && y <= size.height) {
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          pitch == 0 ? (Paint()..color = Colors.white54) : line,
        );
      }
    }
  }

  void _placement(Canvas canvas, Size size, PanoramaPlacement p) {
    final style = styles[p.unitId];
    if (!view.isVisible(p.yawDeg, p.pitchDeg, size, marginDeg: p.widthDeg)) {
      return;
    }
    final box = placementBox(p, view, size, aspect: style?.aspect ?? 2);
    final selected = p.id == selectedId;
    canvas.save();
    canvas.translate(box.center.dx, box.center.dy);
    canvas.rotate(box.rotationRad);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: box.size.width,
      height: box.size.height,
    );
    canvas.drawRect(
      rect,
      Paint()..color = AdinnColors.red.withValues(alpha: 0.28),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = selected ? Colors.white : AdinnColors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 2,
    );
    final label = style?.label ?? 'Removed item';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(40, box.size.width + 80));
    tp.paint(canvas, Offset(-tp.width / 2, rect.top - tp.height - 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(PanoramaPainter old) =>
      old.image != image ||
      old.revision != revision ||
      old.selectedId != selectedId ||
      old.placements != placements ||
      old.drawPlacements != drawPlacements;
}
