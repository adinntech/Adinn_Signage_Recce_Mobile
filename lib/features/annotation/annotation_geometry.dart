import 'dart:math' as math;
import 'dart:ui';

import '../../data/models/models.dart';

/// Visual radius of a selection handle, in logical screen pixels.
const double kHandleRadiusPx = 10;

/// Distance of the rotate handle above the top edge, in screen pixels.
const double kRotateHandleOffsetPx = 32;

/// Touch targets are larger than the drawn handles.
const double kHandleTouchFactor = 2.2;

enum AnnotationHandle {
  topLeft,
  topRight,
  bottomRight,
  bottomLeft,
  rotate,
  arrowStart,
  arrowEnd,
}

extension AnnotationHandleX on AnnotationHandle {
  bool get isCorner =>
      this == AnnotationHandle.topLeft ||
      this == AnnotationHandle.topRight ||
      this == AnnotationHandle.bottomRight ||
      this == AnnotationHandle.bottomLeft;
}

/// Pure geometry helpers for photo annotations. Every coordinate is in the
/// photo's own pixel space. Rectangles and text boxes are stored as centre
/// ([Annotation.x], [Annotation.y]) + size + rotation (radians, clockwise in
/// screen space); arrows as start ([Annotation.x], [Annotation.y]) and end
/// ([Annotation.x2], [Annotation.y2]).
class AnnotationGeometry {
  AnnotationGeometry._();

  static Offset rotatePoint(Offset p, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c);
  }

  static Offset centre(Annotation a) => Offset(a.x, a.y);

  /// World (photo) point → the annotation's unrotated local frame,
  /// origin at the centre.
  static Offset toLocal(Annotation a, Offset world) =>
      rotatePoint(world - centre(a), -a.rotation);

  /// Local frame point → world (photo) coordinates.
  static Offset toWorld(Annotation a, Offset local) =>
      rotatePoint(local, a.rotation) + centre(a);

  static bool isBox(Annotation a) => a.type.isBox;

  static bool rotatedRectContains({
    required Offset centre,
    required Size size,
    required double rotation,
    required Offset point,
    double tolerance = 0,
  }) {
    final local = rotatePoint(point - centre, -rotation);
    return local.dx.abs() <= size.width / 2 + tolerance &&
        local.dy.abs() <= size.height / 2 + tolerance;
  }

  static double distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }

  /// Approximate box for a text label at [fontSize] (photo pixels).
  static Size estimateTextSize(String text, double fontSize) {
    final chars = math.max(text.trim().length, 1);
    return Size(chars * fontSize * 0.6 + fontSize * 1.2, fontSize * 1.7);
  }

  /// Freehand points as offsets (photo pixels).
  static List<Offset> pathPoints(Annotation a) => [
    for (var i = 0; i + 1 < a.points.length; i += 2)
      Offset(a.points[i], a.points[i + 1]),
  ];

  static double distanceToPolyline(Offset p, List<Offset> pts) {
    if (pts.isEmpty) return double.infinity;
    if (pts.length == 1) return (p - pts.first).distance;
    var best = double.infinity;
    for (var i = 0; i + 1 < pts.length; i++) {
      best = math.min(best, distanceToSegment(p, pts[i], pts[i + 1]));
    }
    return best;
  }

  static bool hitBody(Annotation a, Offset p, {double tolerance = 0}) {
    if (a.type.isTwoPoint) {
      return distanceToSegment(p, Offset(a.x, a.y), Offset(a.x2, a.y2)) <=
          math.max(tolerance, 1);
    }
    if (a.type.isFreehand) {
      return distanceToPolyline(p, pathPoints(a)) <= math.max(tolerance, 1);
    }
    return rotatedRectContains(
      centre: centre(a),
      size: Size(a.w, a.h),
      rotation: a.rotation,
      point: p,
      tolerance: tolerance,
    );
  }

  /// Like [topmostAt] but skips annotations on hidden layers.
  static Annotation? topmostVisibleAt(
    List<Annotation> items,
    Offset p,
    Set<AnnotationLayer> hidden, {
    double tolerance = 0,
  }) {
    for (var i = items.length - 1; i >= 0; i--) {
      final a = items[i];
      if (hidden.contains(a.type.layer)) continue;
      if (hitBody(a, p, tolerance: tolerance)) return a;
    }
    return null;
  }

  /// Appends a freehand point unless it is closer than [minStep] to the
  /// previous one (keeps stored paths small).
  static void addPathPoint(Annotation a, Offset p, {double minStep = 2}) {
    final n = a.points.length;
    if (n >= 2) {
      final last = Offset(a.points[n - 2], a.points[n - 1]);
      if ((p - last).distance < minStep) return;
    }
    a.points
      ..add(p.dx)
      ..add(p.dy);
  }

  /// Image pixel ↔ displayed (fitted) position. [displayScale] is displayed
  /// pixels per image pixel, [origin] the top-left of the photo on screen.
  static Offset imageToDisplay(
    Offset image,
    double displayScale,
    Offset origin,
  ) => origin + image * displayScale;

  static Offset displayToImage(
    Offset display,
    double displayScale,
    Offset origin,
  ) => (display - origin) / displayScale;

  /// Top-most (last drawn) annotation under [p], or null.
  static Annotation? topmostAt(
    List<Annotation> items,
    Offset p, {
    double tolerance = 0,
  }) {
    for (var i = items.length - 1; i >= 0; i--) {
      if (hitBody(items[i], p, tolerance: tolerance)) return items[i];
    }
    return null;
  }

  /// Handle positions in photo space. [rotateOffset] is the distance of the
  /// rotate handle above the top edge (photo pixels).
  static Map<AnnotationHandle, Offset> handlePositions(
    Annotation a, {
    required double rotateOffset,
  }) {
    if (a.type.isTwoPoint) {
      return {
        AnnotationHandle.arrowStart: Offset(a.x, a.y),
        AnnotationHandle.arrowEnd: Offset(a.x2, a.y2),
      };
    }
    // Freehand strokes are moved as a whole (no resize / rotate handles).
    if (a.type.isFreehand) return const {};
    final hw = a.w / 2;
    final hh = a.h / 2;
    return {
      AnnotationHandle.topLeft: toWorld(a, Offset(-hw, -hh)),
      AnnotationHandle.topRight: toWorld(a, Offset(hw, -hh)),
      AnnotationHandle.bottomRight: toWorld(a, Offset(hw, hh)),
      AnnotationHandle.bottomLeft: toWorld(a, Offset(-hw, hh)),
      AnnotationHandle.rotate: toWorld(a, Offset(0, -hh - rotateOffset)),
    };
  }

  /// Closest handle within [radius] of [p], or null.
  static AnnotationHandle? hitHandle(
    Annotation a,
    Offset p, {
    required double radius,
    required double rotateOffset,
  }) {
    AnnotationHandle? best;
    var bestDistance = radius;
    handlePositions(a, rotateOffset: rotateOffset).forEach((handle, pos) {
      final d = (pos - p).distance;
      if (d <= bestDistance) {
        best = handle;
        bestDistance = d;
      }
    });
    return best;
  }

  static Offset _cornerSign(AnnotationHandle h) => switch (h) {
    AnnotationHandle.topLeft => const Offset(-1, -1),
    AnnotationHandle.topRight => const Offset(1, -1),
    AnnotationHandle.bottomRight => const Offset(1, 1),
    AnnotationHandle.bottomLeft => const Offset(-1, 1),
    _ => Offset.zero,
  };

  /// Resizes a rectangle/text box by dragging [corner] to [pointer] while the
  /// opposite corner stays fixed in the rotated frame.
  static void resizeFromCorner(
    Annotation a,
    AnnotationHandle corner,
    Offset pointer, {
    double minSize = 8,
  }) {
    final sign = _cornerSign(corner);
    if (sign == Offset.zero) return;
    final opposite = toWorld(a, Offset(-sign.dx * a.w / 2, -sign.dy * a.h / 2));
    final d = rotatePoint(pointer - opposite, -a.rotation);
    final w = math.max(minSize, d.dx * sign.dx);
    final h = math.max(minSize, d.dy * sign.dy);
    final newCentre =
        opposite +
        rotatePoint(Offset(sign.dx * w / 2, sign.dy * h / 2), a.rotation);
    a
      ..w = w
      ..h = h
      ..x = newCentre.dx
      ..y = newCentre.dy;
  }

  /// Rotation that puts the rotate handle (above the top edge) under
  /// [pointer]. 0 when the pointer is straight above the centre.
  static double rotationFromPointer(Offset centre, Offset pointer) =>
      normalizeAngle(
        math.atan2(pointer.dy - centre.dy, pointer.dx - centre.dx) +
            math.pi / 2,
      );

  /// Normalises to (-π, π].
  static double normalizeAngle(double angle) {
    var r = angle % (2 * math.pi);
    if (r > math.pi) r -= 2 * math.pi;
    return r;
  }

  /// Snaps to the nearest multiple of [step] when within [threshold].
  static double snapAngle(
    double angle, {
    double step = math.pi / 4,
    double threshold = 4 * math.pi / 180,
  }) {
    final nearest = (angle / step).round() * step;
    return (angle - nearest).abs() <= threshold
        ? normalizeAngle(nearest)
        : angle;
  }

  static void translate(Annotation a, Offset delta) {
    a
      ..x += delta.dx
      ..y += delta.dy;
    if (a.type.isTwoPoint) {
      a
        ..x2 += delta.dx
        ..y2 += delta.dy;
    }
    if (a.type.isFreehand) {
      for (var i = 0; i + 1 < a.points.length; i += 2) {
        a.points[i] += delta.dx;
        a.points[i + 1] += delta.dy;
      }
    }
  }

  static void moveArrowEndpoint(
    Annotation a,
    AnnotationHandle handle,
    Offset p,
  ) {
    if (handle == AnnotationHandle.arrowStart) {
      a
        ..x = p.dx
        ..y = p.dy;
    } else if (handle == AnnotationHandle.arrowEnd) {
      a
        ..x2 = p.dx
        ..y2 = p.dy;
    }
  }

  /// Axis-aligned bounds in photo space.
  static Rect bounds(Annotation a) {
    if (a.type.isTwoPoint) {
      return Rect.fromPoints(Offset(a.x, a.y), Offset(a.x2, a.y2));
    }
    if (a.type.isFreehand) {
      final pts = pathPoints(a);
      if (pts.isEmpty) return Rect.fromLTWH(a.x, a.y, 0, 0);
      return Rect.fromLTRB(
        pts.map((p) => p.dx).reduce(math.min),
        pts.map((p) => p.dy).reduce(math.min),
        pts.map((p) => p.dx).reduce(math.max),
        pts.map((p) => p.dy).reduce(math.max),
      );
    }
    final pts = handlePositions(a, rotateOffset: 0)
      ..remove(AnnotationHandle.rotate);
    final xs = pts.values.map((p) => p.dx);
    final ys = pts.values.map((p) => p.dy);
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  /// Axis-aligned rectangle (centre + size) spanning two drag points.
  static void setRectFromPoints(Annotation a, Offset p1, Offset p2) {
    a
      ..x = (p1.dx + p2.dx) / 2
      ..y = (p1.dy + p2.dy) / 2
      ..w = (p2.dx - p1.dx).abs()
      ..h = (p2.dy - p1.dy).abs()
      ..rotation = 0;
  }

  static double arrowLength(Annotation a) =>
      (Offset(a.x2, a.y2) - Offset(a.x, a.y)).distance;
}
