import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import 'annotation_geometry.dart';

/// Paints photo annotations (signage rectangles with measurements, arrows and
/// text labels). Annotation coordinates are in photo pixels; the painter
/// scales them to the size it is given so the same data renders identically
/// in thumbnails, review screens and the editor.
class AnnotationPainter extends CustomPainter {
  AnnotationPainter({
    required this.annotations,
    required this.imageSize,
    this.selectedId,
    this.handleScale = 1.0,
    this.showHandles = false,
    this.draft,
    this.hiddenLayers = const {},
  }) : _signature = _computeSignature(annotations, draft);

  final List<Annotation> annotations;
  final Size imageSize;
  final String? selectedId;

  /// Layers whose markings are not drawn (editor layer toggles).
  final Set<AnnotationLayer> hiddenLayers;

  /// Current zoom factor of the surrounding viewer; handles are divided by it
  /// so they keep a constant on-screen size.
  final double handleScale;
  final bool showHandles;

  /// Annotation currently being drawn (not yet committed).
  final Annotation? draft;

  final int _signature;

  static int _computeSignature(List<Annotation> items, Annotation? draft) =>
      Object.hashAll([
        for (final a in [...items, ?draft])
          Object.hash(
            a.id,
            a.type,
            a.x,
            a.y,
            a.w,
            a.h,
            a.x2,
            a.y2,
            a.rotation,
            a.label,
            a.measureW,
            a.measureH,
            a.unit,
            a.color,
            a.thickness,
            a.itemId,
            a.points.length,
            a.points.isEmpty ? 0 : Object.hashAll(a.points),
          ),
      ]);

  /// "10 × 4 ft", or empty when no measurement is set.
  static String measurementText(Annotation a) => a.hasMeasurement
      ? '${fmtNum(a.measureW!)} × ${fmtNum(a.measureH!)} ${a.unit.label}'
      : '';

  /// Readable text colour on top of [background].
  static Color contrastOn(Color background) =>
      background.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width <= 0 || imageSize.height <= 0 || size.isEmpty) return;
    final sx = size.width / imageSize.width;
    final sy = size.height / imageSize.height;
    final stroke = imageSize.width / 250;
    final font = imageSize.width / 38;

    canvas.save();
    canvas.scale(sx, sy);

    Annotation? selected;
    for (final a in annotations) {
      if (hiddenLayers.contains(a.type.layer)) continue;
      final isSelected = showHandles && a.id == selectedId;
      if (isSelected) selected = a;
      _paintAnnotation(canvas, a, stroke, font, highlighted: isSelected);
    }
    final d = draft;
    if (d != null) _paintAnnotation(canvas, d, stroke, font, highlighted: true);
    if (selected != null) _paintHandles(canvas, selected, sx);

    canvas.restore();
  }

  void _paintAnnotation(
    Canvas canvas,
    Annotation a,
    double stroke,
    double font, {
    required bool highlighted,
  }) {
    final s = stroke * a.thickness;
    switch (a.type) {
      case AnnotationType.rectangle:
        _paintRect(canvas, a, s, font, highlighted);
      case AnnotationType.arrow:
        _paintArrow(canvas, a, s, font, highlighted);
      case AnnotationType.text:
        _paintText(canvas, a, s, highlighted);
      case AnnotationType.shapeRect:
      case AnnotationType.circle:
        _paintShape(canvas, a, s, font, highlighted);
      case AnnotationType.line:
        _paintLine(canvas, a, s, font, highlighted);
      case AnnotationType.freehand:
        _paintFreehand(canvas, a, s, highlighted);
      case AnnotationType.dimension:
        _paintDimensionAnnotation(canvas, a, s, font, highlighted);
      case AnnotationType.measureLabel:
        _paintMeasureLabel(canvas, a, s, highlighted);
      case AnnotationType.poleMarker:
      case AnnotationType.pipeMarker:
      case AnnotationType.numberMarker:
        _paintBadgeMarker(canvas, a, s, highlighted);
      case AnnotationType.groundMarker:
        _paintGroundMarker(canvas, a, s, font, highlighted);
    }
  }

  /// Text shown for a dimension line / measurement label.
  static String valueText(Annotation a) {
    final value = a.hasValue ? '${fmtNum(a.measureW!)} ${a.unit.label}' : '';
    final label = a.label.trim();
    if (label.isEmpty) return value.isEmpty ? '— ${a.unit.label}' : value;
    return value.isEmpty ? label : '$label: $value';
  }

  // ---------------------------------------------------------------------------
  // Advanced tools
  // ---------------------------------------------------------------------------

  void _highlightPath(Canvas canvas, Path path, double stroke) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  void _paintShape(
    Canvas canvas,
    Annotation a,
    double stroke,
    double font,
    bool highlighted,
  ) {
    final color = Color(a.color);
    canvas.save();
    canvas.translate(a.x, a.y);
    canvas.rotate(a.rotation);
    final r = Rect.fromCenter(center: Offset.zero, width: a.w, height: a.h);
    final path = a.type == AnnotationType.circle
        ? (Path()..addOval(r))
        : (Path()..addRect(r));
    if (highlighted) _highlightPath(canvas, path, stroke);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color,
    );
    if (a.label.trim().isNotEmpty) {
      _pill(
        canvas,
        a.label.trim(),
        Offset(0, r.top - font * 0.6),
        font * 0.65,
        background: color,
        foreground: contrastOn(color),
      );
    }
    canvas.restore();
  }

  void _paintLine(
    Canvas canvas,
    Annotation a,
    double stroke,
    double font,
    bool highlighted,
  ) {
    final color = Color(a.color);
    final p1 = Offset(a.x, a.y), p2 = Offset(a.x2, a.y2);
    if ((p2 - p1).distance < 0.5) return;
    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy);
    if (highlighted) _highlightPath(canvas, path, stroke);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 1.2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    if (a.label.trim().isNotEmpty) {
      _pill(
        canvas,
        a.label.trim(),
        (p1 + p2) / 2,
        font * 0.65,
        background: color,
        foreground: contrastOn(color),
      );
    }
  }

  void _paintFreehand(
    Canvas canvas,
    Annotation a,
    double stroke,
    bool highlighted,
  ) {
    final pts = AnnotationGeometry.pathPoints(a);
    if (pts.isEmpty) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    if (pts.length == 1) path.lineTo(pts.first.dx + 0.01, pts.first.dy);
    if (highlighted) _highlightPath(canvas, path, stroke);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 1.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Color(a.color),
    );
  }

  void _paintDimensionAnnotation(
    Canvas canvas,
    Annotation a,
    double stroke,
    double font,
    bool highlighted,
  ) {
    final color = Color(a.color);
    final p1 = Offset(a.x, a.y), p2 = Offset(a.x2, a.y2);
    final len = (p2 - p1).distance;
    if (len < 0.5) return;
    final u = (p2 - p1) / len;
    final n = Offset(-u.dy, u.dx) * (stroke * 4);
    if (highlighted) {
      _highlightPath(
        canvas,
        Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy),
        stroke,
      );
    }
    final tick = Paint()
      ..color = color
      ..strokeWidth = stroke * 0.8;
    canvas.drawLine(p1 - n, p1 + n, tick);
    canvas.drawLine(p2 - n, p2 + n, tick);
    _dimensionLine(canvas, p1, p2, color, stroke);
    _pill(
      canvas,
      valueText(a),
      (p1 + p2) / 2,
      font * 0.72,
      background: Colors.white,
      foreground: Colors.black87,
      border: color,
    );
  }

  void _paintMeasureLabel(
    Canvas canvas,
    Annotation a,
    double stroke,
    bool highlighted,
  ) {
    final color = Color(a.color);
    final text = valueText(a);
    canvas.save();
    canvas.translate(a.x, a.y);
    canvas.rotate(a.rotation);
    final box = Rect.fromCenter(center: Offset.zero, width: a.w, height: a.h);
    final rrect = RRect.fromRectAndRadius(box, Radius.circular(a.h * 0.2));
    canvas.drawRRect(rrect, Paint()..color = Colors.white);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(stroke, a.h * 0.06)
        ..color = highlighted ? Colors.black : color,
    );
    var fontSize = math.max(a.h / 1.9, 1.0);
    var tp = _layout(text, fontSize, Colors.black87, bold: true);
    final maxWidth = a.w * 0.9;
    if (tp.width > maxWidth && tp.width > 0) {
      fontSize = math.max(fontSize * maxWidth / tp.width, 1.0);
      tp = _layout(text, fontSize, Colors.black87, bold: true);
    }
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  /// Short code drawn inside a marker badge.
  static String markerGlyph(Annotation a) => switch (a.type) {
    AnnotationType.poleMarker => 'P',
    AnnotationType.pipeMarker => 'SP',
    AnnotationType.numberMarker => a.label.trim().isEmpty ? '#' : a.label,
    _ => '',
  };

  void _paintBadgeMarker(
    Canvas canvas,
    Annotation a,
    double stroke,
    bool highlighted,
  ) {
    final color = Color(a.color);
    final r = math.max(math.min(a.w, a.h) / 2, 1.0);
    canvas.save();
    canvas.translate(a.x, a.y);
    canvas.rotate(a.rotation);
    if (a.type == AnnotationType.poleMarker ||
        a.type == AnnotationType.pipeMarker) {
      // Stem pointing down to the exact location.
      canvas.drawLine(
        Offset(0, r * 0.6),
        Offset(0, a.h / 2 + r * 0.9),
        Paint()
          ..color = color
          ..strokeWidth = math.max(stroke * 1.2, r * 0.18),
      );
    }
    final c = a.type == AnnotationType.numberMarker
        ? Offset.zero
        : Offset(0, -r * 0.1);
    if (highlighted) {
      canvas.drawCircle(c, r * 1.12, Paint()..color = Colors.white);
    }
    canvas.drawCircle(c, r, Paint()..color = color);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = Colors.white,
    );
    final glyph = markerGlyph(a);
    final tp = _layout(
      glyph,
      r * (glyph.length > 1 ? 0.8 : 1.1),
      contrastOn(color),
      bold: true,
    );
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    if (a.type != AnnotationType.numberMarker && a.label.trim().isNotEmpty) {
      _pill(
        canvas,
        a.label.trim(),
        Offset(0, -r * 1.7),
        r * 0.7,
        background: Colors.white,
        foreground: Colors.black87,
        border: color,
      );
    }
    canvas.restore();
  }

  void _paintGroundMarker(
    Canvas canvas,
    Annotation a,
    double stroke,
    double font,
    bool highlighted,
  ) {
    final color = Color(a.color);
    canvas.save();
    canvas.translate(a.x, a.y);
    canvas.rotate(a.rotation);
    final half = a.w / 2;
    final line = Paint()
      ..color = color
      ..strokeWidth = stroke * 1.4
      ..strokeCap = StrokeCap.round;
    if (highlighted) {
      canvas.drawLine(
        Offset(-half, 0),
        Offset(half, 0),
        Paint()
          ..color = Colors.white
          ..strokeWidth = stroke * 3,
      );
    }
    canvas.drawLine(Offset(-half, 0), Offset(half, 0), line);
    // Hatching below the ground line.
    final hatch = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = stroke * 0.6;
    final step = math.max(a.h * 0.6, stroke * 4);
    for (var x = -half; x < half; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x - step * 0.7, a.h / 2), hatch);
    }
    _pill(
      canvas,
      a.label.trim().isEmpty ? 'GL' : 'GL • ${a.label.trim()}',
      Offset(-half + font * 1.4, -font * 0.6),
      font * 0.6,
      background: color,
      foreground: contrastOn(color),
    );
    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // Rectangle
  // ---------------------------------------------------------------------------

  void _paintRect(
    Canvas canvas,
    Annotation a,
    double stroke,
    double font,
    bool highlighted,
  ) {
    final color = Color(a.color);
    canvas.save();
    canvas.translate(a.x, a.y);
    canvas.rotate(a.rotation);
    final r = Rect.fromCenter(center: Offset.zero, width: a.w, height: a.h);

    canvas.drawRect(r, Paint()..color = color.withValues(alpha: 0.16));
    if (highlighted) {
      canvas.drawRect(
        r.inflate(stroke * 1.4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.6
          ..color = Colors.white.withValues(alpha: 0.9),
      );
    }
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color,
    );

    var chipBottom = r.top - stroke;
    if (a.hasMeasurement) {
      final gap = stroke * 5;
      final dimFont = font * 0.72;

      // Width dimension above the top edge.
      final y = r.top - gap;
      _extensionLine(
        canvas,
        Offset(r.left, r.top - stroke),
        Offset(r.left, y - stroke * 2),
        color,
        stroke,
      );
      _extensionLine(
        canvas,
        Offset(r.right, r.top - stroke),
        Offset(r.right, y - stroke * 2),
        color,
        stroke,
      );
      _dimensionLine(
        canvas,
        Offset(r.left, y),
        Offset(r.right, y),
        color,
        stroke,
      );
      _pill(
        canvas,
        '${fmtNum(a.measureW!)} ${a.unit.label}',
        Offset(0, y),
        dimFont,
        background: Colors.white,
        foreground: Colors.black87,
        border: color,
      );

      // Height dimension right of the right edge.
      final x = r.right + gap;
      _extensionLine(
        canvas,
        Offset(r.right + stroke, r.top),
        Offset(x + stroke * 2, r.top),
        color,
        stroke,
      );
      _extensionLine(
        canvas,
        Offset(r.right + stroke, r.bottom),
        Offset(x + stroke * 2, r.bottom),
        color,
        stroke,
      );
      _dimensionLine(
        canvas,
        Offset(x, r.top),
        Offset(x, r.bottom),
        color,
        stroke,
      );
      canvas.save();
      canvas.translate(x, 0);
      canvas.rotate(-math.pi / 2);
      _pill(
        canvas,
        '${fmtNum(a.measureH!)} ${a.unit.label}',
        Offset.zero,
        dimFont,
        background: Colors.white,
        foreground: Colors.black87,
        border: color,
      );
      canvas.restore();

      chipBottom = y - dimFont * 0.9;
    }

    final text = [
      if (a.label.trim().isNotEmpty) a.label.trim(),
      if (a.hasMeasurement) measurementText(a),
    ].join(' • ');
    if (text.isNotEmpty) {
      final tp = _layout(text, font * 0.75, contrastOn(color), bold: true);
      final pad = font * 0.3;
      final chip = Rect.fromLTWH(
        r.left,
        chipBottom - tp.height - pad * 2,
        tp.width + pad * 2.4,
        tp.height + pad * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(chip, Radius.circular(font * 0.25)),
        Paint()..color = color,
      );
      tp.paint(canvas, chip.topLeft + Offset(pad * 1.2, pad));
    }
    canvas.restore();
  }

  void _extensionLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Color color,
    double stroke,
  ) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color.withValues(alpha: 0.8)
        ..strokeWidth = stroke * 0.45,
    );
  }

  void _dimensionLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Color color,
    double stroke,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke * 0.7;
    canvas.drawLine(a, b, paint);
    final dir = b - a;
    final len = dir.distance;
    if (len == 0) return;
    final u = dir / len;
    final head = math.min(stroke * 3.5, len / 3);
    _arrowHead(canvas, b, u, head, color);
    _arrowHead(canvas, a, -u, head, color);
  }

  void _arrowHead(
    Canvas canvas,
    Offset tip,
    Offset unitDir,
    double size,
    Color color,
  ) {
    final back = tip - unitDir * size;
    final normal = Offset(-unitDir.dy, unitDir.dx) * (size * 0.55);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + normal.dx, back.dy + normal.dy)
      ..lineTo(back.dx - normal.dx, back.dy - normal.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  // ---------------------------------------------------------------------------
  // Arrow
  // ---------------------------------------------------------------------------

  void _paintArrow(
    Canvas canvas,
    Annotation a,
    double stroke,
    double font,
    bool highlighted,
  ) {
    final color = Color(a.color);
    final start = Offset(a.x, a.y);
    final end = Offset(a.x2, a.y2);
    final len = (end - start).distance;
    if (len < 0.5) return;
    final u = (end - start) / len;
    final head = math.min(stroke * 6, len * 0.6);
    final lineEnd = end - u * head * 0.8;

    if (highlighted) {
      canvas.drawLine(
        start,
        lineEnd,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..strokeWidth = stroke * 2.6
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawLine(
      start,
      lineEnd,
      Paint()
        ..color = color
        ..strokeWidth = stroke * 1.3
        ..strokeCap = StrokeCap.round,
    );
    _arrowHead(canvas, end, u, head, color);

    if (a.label.trim().isNotEmpty) {
      _pill(
        canvas,
        a.label.trim(),
        start - u * font * 0.9,
        font * 0.7,
        background: color,
        foreground: contrastOn(color),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------------

  void _paintText(
    Canvas canvas,
    Annotation a,
    double stroke,
    bool highlighted,
  ) {
    final color = Color(a.color);
    final text = a.label.trim().isEmpty ? 'Text' : a.label.trim();
    canvas.save();
    canvas.translate(a.x, a.y);
    canvas.rotate(a.rotation);
    final box = Rect.fromCenter(center: Offset.zero, width: a.w, height: a.h);
    final rrect = RRect.fromRectAndRadius(box, Radius.circular(a.h * 0.3));
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.92));
    if (highlighted) {
      canvas.drawRRect(
        rrect.inflate(stroke),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.6
          ..color = Colors.white,
      );
    }
    var fontSize = math.max(a.h / 1.7, 1.0);
    var tp = _layout(text, fontSize, contrastOn(color), bold: true);
    final maxWidth = a.w * 0.92;
    if (tp.width > maxWidth && tp.width > 0) {
      fontSize = math.max(fontSize * maxWidth / tp.width, 1.0);
      tp = _layout(text, fontSize, contrastOn(color), bold: true);
    }
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // Handles & helpers
  // ---------------------------------------------------------------------------

  void _paintHandles(Canvas canvas, Annotation a, double displayScale) {
    final zoom = math.max(displayScale * handleScale, 1e-6);
    final r = kHandleRadiusPx / zoom;
    final rotateOffset = kRotateHandleOffsetPx / zoom;
    final color = Color(a.color);
    final accent = color.computeLuminance() > 0.7 ? Colors.black87 : color;
    final fill = Paint()..color = Colors.white;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.35
      ..color = accent;

    final handles = AnnotationGeometry.handlePositions(
      a,
      rotateOffset: rotateOffset,
    );

    if (a.type.isTwoPoint) {
      for (final p in handles.values) {
        canvas.drawCircle(p, r, fill);
        canvas.drawCircle(p, r, ring);
      }
      return;
    }
    if (a.type.isFreehand) {
      // Dashed-looking selection box around the stroke (move only).
      canvas.drawRect(
        AnnotationGeometry.bounds(a).inflate(r),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.25
          ..color = accent,
      );
      return;
    }

    final topMid = AnnotationGeometry.toWorld(a, Offset(0, -a.h / 2));
    final rotatePos = handles[AnnotationHandle.rotate]!;
    canvas.drawLine(
      topMid,
      rotatePos,
      Paint()
        ..color = accent
        ..strokeWidth = r * 0.25,
    );
    for (final entry in handles.entries) {
      if (entry.key == AnnotationHandle.rotate) continue;
      canvas.save();
      canvas.translate(entry.value.dx, entry.value.dy);
      canvas.rotate(a.rotation);
      final sq = Rect.fromCenter(
        center: Offset.zero,
        width: r * 1.7,
        height: r * 1.7,
      );
      canvas.drawRect(sq, fill);
      canvas.drawRect(sq, ring);
      canvas.restore();
    }
    canvas.drawCircle(rotatePos, r * 1.1, fill);
    canvas.drawCircle(rotatePos, r * 1.1, ring);
    // Small curved-arrow glyph inside the rotate handle.
    canvas.drawArc(
      Rect.fromCircle(center: rotatePos, radius: r * 0.55),
      -math.pi * 0.9,
      math.pi * 1.4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.22
        ..color = accent,
    );
  }

  TextPainter _layout(
    String text,
    double fontSize,
    Color color, {
    bool bold = false,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
  }

  /// Rounded label centred on [centre].
  void _pill(
    Canvas canvas,
    String text,
    Offset centre,
    double fontSize, {
    required Color background,
    required Color foreground,
    Color? border,
  }) {
    final tp = _layout(text, fontSize, foreground, bold: true);
    final pad = fontSize * 0.35;
    final rect = Rect.fromCenter(
      center: centre,
      width: tp.width + pad * 2.4,
      height: tp.height + pad * 1.4,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.height / 2),
    );
    canvas.drawRRect(rrect, Paint()..color = background);
    if (border != null) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = fontSize * 0.08
          ..color = border,
      );
    }
    tp.paint(
      canvas,
      Offset(centre.dx - tp.width / 2, centre.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter old) =>
      old._signature != _signature ||
      old.annotations.length != annotations.length ||
      old.imageSize != imageSize ||
      old.selectedId != selectedId ||
      old.handleScale != handleScale ||
      old.showHandles != showHandles ||
      !setEquals(old.hiddenLayers, hiddenLayers) ||
      (old.draft == null) != (draft == null);
}
