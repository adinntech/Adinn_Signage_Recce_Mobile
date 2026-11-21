import 'dart:math' as math;
import 'package:flutter/widgets.dart' show Matrix4, Offset, Rect, Size;

/// Projective (homography) maths for four-corner perspective placements.
///
/// A homography H (3×3, row-major, h22 normalised to 1) maps a source point
/// (x, y) to ((h0 x + h1 y + h2) / w, (h3 x + h4 y + h5) / w) with
/// w = h6 x + h7 y + h8. Unlike a rotate/stretch it maps any rectangle onto
/// any convex quadrilateral, which is what an angled shop photo needs.
class Homography {
  const Homography(this.m);

  /// 9 coefficients, row-major.
  final List<double> m;

  bool get isFinite => m.every((v) => v.isFinite);

  Offset map(Offset p) {
    final w = m[6] * p.dx + m[7] * p.dy + m[8];
    return Offset(
      (m[0] * p.dx + m[1] * p.dy + m[2]) / w,
      (m[3] * p.dx + m[4] * p.dy + m[5]) / w,
    );
  }

  /// Denominator w at [p] (must stay positive inside the source rect so
  /// the quad is not "folded" through the horizon).
  double w(Offset p) => m[6] * p.dx + m[7] * p.dy + m[8];

  /// Equivalent 4×4 matrix for [Canvas.transform] (z passes through).
  Matrix4 toMatrix4() => Matrix4(
    m[0],
    m[3],
    0,
    m[6], //
    m[1],
    m[4],
    0,
    m[7], //
    0,
    0,
    1,
    0, //
    m[2],
    m[5],
    0,
    m[8], //
  );

  /// Homography mapping the unit square (0,0)-(1,0)-(1,1)-(0,1) onto
  /// [quad] (TL, TR, BR, BL). Null for degenerate input.
  static Homography? unitSquareTo(List<Offset> quad) {
    if (quad.length != 4) return null;
    final x0 = quad[0].dx, y0 = quad[0].dy;
    final x1 = quad[1].dx, y1 = quad[1].dy;
    final x2 = quad[2].dx, y2 = quad[2].dy;
    final x3 = quad[3].dx, y3 = quad[3].dy;
    final dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
    final dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
    double a, b, c, d, e, f, g, h;
    if (dx3.abs() < 1e-12 && dy3.abs() < 1e-12) {
      // Affine (parallelogram).
      a = x1 - x0;
      b = x3 - x0;
      c = x0;
      d = y1 - y0;
      e = y3 - y0;
      f = y0;
      g = 0;
      h = 0;
    } else {
      final den = dx1 * dy2 - dx2 * dy1;
      if (den.abs() < 1e-12) return null;
      g = (dx3 * dy2 - dx2 * dy3) / den;
      h = (dx1 * dy3 - dx3 * dy1) / den;
      a = x1 - x0 + g * x1;
      b = x3 - x0 + h * x3;
      c = x0;
      d = y1 - y0 + g * y1;
      e = y3 - y0 + h * y3;
      f = y0;
    }
    // Degenerate (collinear / coincident corners): not invertible.
    final det = a * (e - f * h) - b * (d - f * g) + c * (d * h - e * g);
    if (!det.isFinite || det.abs() < 1e-9) return null;
    final hm = Homography([a, b, c, d, e, f, g, h, 1]);
    return hm.isFinite ? hm : null;
  }

  /// Homography mapping [src] onto [quad].
  static Homography? rectTo(Rect src, List<Offset> quad) {
    if (src.width <= 0 || src.height <= 0) return null;
    final u = unitSquareTo(quad);
    if (u == null) return null;
    // Compose with rect → unit square scaling: S = [1/w 0 -l/w; 0 1/h -t/h].
    final sx = 1 / src.width, sy = 1 / src.height;
    final tx = -src.left * sx, ty = -src.top * sy;
    final m = u.m;
    final r = <double>[
      m[0] * sx,
      m[1] * sy,
      m[0] * tx + m[1] * ty + m[2],
      m[3] * sx,
      m[4] * sy,
      m[3] * tx + m[4] * ty + m[5],
      m[6] * sx,
      m[7] * sy,
      m[6] * tx + m[7] * ty + m[8],
    ];
    final out = Homography(r);
    return out.isFinite ? out : null;
  }
}

/// Why a quadrilateral cannot be saved.
enum QuadProblem {
  none,
  notFinite,
  tooSmall,
  selfIntersecting,
  notConvex,
  wrongOrder,
  outOfBounds,
}

extension QuadProblemX on QuadProblem {
  String get message => switch (this) {
    QuadProblem.none => '',
    QuadProblem.notFinite => 'Corner positions are invalid. Reset the corners.',
    QuadProblem.tooSmall =>
      'The board shape is too small. Drag the corners further apart.',
    QuadProblem.selfIntersecting =>
      'The edges cross each other. Drag the corners so the shape does not '
          'twist.',
    QuadProblem.notConvex =>
      'The shape is caved in. Move the inner corner outwards so all four '
          'corners form a board.',
    QuadProblem.wrongOrder =>
      'Corners are flipped. Keep top-left, top-right, bottom-right and '
          'bottom-left in order.',
    QuadProblem.outOfBounds =>
      'A corner is too far outside the photo. Drag it back onto the photo.',
  };
}

class QuadGeometry {
  QuadGeometry._();

  /// Signed area (shoelace). Positive = clockwise on screen (y down).
  static double signedArea(List<Offset> p) {
    var s = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i], b = p[(i + 1) % p.length];
      s += a.dx * b.dy - b.dx * a.dy;
    }
    return s / 2;
  }

  static double _cross(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

  /// Proper intersection of segments ab and cd.
  static bool segmentsCross(Offset a, Offset b, Offset c, Offset d) {
    final d1 = _cross(c, d, a), d2 = _cross(c, d, b);
    final d3 = _cross(a, b, c), d4 = _cross(a, b, d);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  static bool isSelfIntersecting(List<Offset> q) =>
      segmentsCross(q[0], q[1], q[2], q[3]) ||
      segmentsCross(q[1], q[2], q[3], q[0]);

  static bool isConvex(List<Offset> q) {
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final c = _cross(q[i], q[(i + 1) % 4], q[(i + 2) % 4]);
      if (c.abs() < 1e-9) return false;
      final s = c > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }

  static bool contains(List<Offset> poly, Offset p) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  static Offset centroid(List<Offset> q) {
    var x = 0.0, y = 0.0;
    for (final p in q) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / q.length, y / q.length);
  }

  /// Validates a placement quad given in photo pixels (TL, TR, BR, BL).
  /// [margin] = fraction of the photo a corner may lie outside it.
  static QuadProblem validate(
    List<Offset> q,
    Size image, {
    double minAreaFraction = 0.0004,
    double minSideFraction = 0.01,
    double margin = 0.25,
  }) {
    if (q.length != 4 || q.any((p) => !p.dx.isFinite || !p.dy.isFinite)) {
      return QuadProblem.notFinite;
    }
    final minX = -margin * image.width, maxX = (1 + margin) * image.width;
    final minY = -margin * image.height, maxY = (1 + margin) * image.height;
    if (q.any(
      (p) => p.dx < minX || p.dx > maxX || p.dy < minY || p.dy > maxY,
    )) {
      return QuadProblem.outOfBounds;
    }
    if (isSelfIntersecting(q)) return QuadProblem.selfIntersecting;
    final area = signedArea(q);
    final imageArea = image.width * image.height;
    final minSide = minSideFraction * math.min(image.width, image.height);
    for (var i = 0; i < 4; i++) {
      if ((q[i] - q[(i + 1) % 4]).distance < minSide) {
        return QuadProblem.tooSmall;
      }
    }
    if (area.abs() < minAreaFraction * imageArea) return QuadProblem.tooSmall;
    if (area < 0) return QuadProblem.wrongOrder;
    if (!isConvex(q)) return QuadProblem.notConvex;
    final h = Homography.unitSquareTo(q);
    if (h == null) return QuadProblem.notFinite;
    // w must keep one sign over the unit square (no fold through infinity).
    const corners = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
    final ws = corners.map(h.w).toList();
    if (ws.any((w) => !w.isFinite || w <= 1e-9)) return QuadProblem.notFinite;
    return QuadProblem.none;
  }
}
