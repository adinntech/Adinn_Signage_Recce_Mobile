import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'scene3d.dart';

/// Orbit camera around the scene focus.
@immutable
class Camera3D {
  const Camera3D({
    this.yaw = 0.55,
    this.pitch = 0.28,
    this.zoom = 1,
    this.pan = Offset.zero,
    this.ortho = false,
  });

  /// Rotation around the vertical axis (radians). 0 = looking at the front.
  final double yaw;

  /// Elevation of the camera (radians). 0 = eye level, π/2 = top view.
  final double pitch;
  final double zoom;

  /// Screen-space offset in logical pixels.
  final Offset pan;
  final bool ortho;

  static const minPitch = -0.15;
  static const maxPitch = 1.55;
  static const minZoom = 0.3;
  static const maxZoom = 8.0;

  Camera3D copyWith({
    double? yaw,
    double? pitch,
    double? zoom,
    Offset? pan,
    bool? ortho,
  }) => Camera3D(
    yaw: yaw ?? this.yaw,
    pitch: (pitch ?? this.pitch).clamp(minPitch, maxPitch).toDouble(),
    zoom: (zoom ?? this.zoom).clamp(minZoom, maxZoom).toDouble(),
    pan: pan ?? this.pan,
    ortho: ortho ?? this.ortho,
  );

  /// Interpolates along the shortest yaw arc; projection snaps to [b]'s.
  static Camera3D lerp(Camera3D a, Camera3D b, double t) {
    final dy = math.atan2(math.sin(b.yaw - a.yaw), math.cos(b.yaw - a.yaw));
    return Camera3D(
      yaw: a.yaw + dy * t,
      pitch: a.pitch + (b.pitch - a.pitch) * t,
      zoom: a.zoom * math.pow(b.zoom / a.zoom, t).toDouble(),
      pan: Offset.lerp(a.pan, b.pan, t)!,
      ortho: b.ortho,
    );
  }

  /// Yaw in degrees normalised to (-180, 180].
  int get yawDegrees {
    var deg = (yaw * 180 / math.pi) % 360;
    if (deg > 180) deg -= 360;
    return deg.round();
  }

  int get pitchDegrees => (pitch * 180 / math.pi).round();

  @override
  bool operator ==(Object other) =>
      other is Camera3D &&
      other.yaw == yaw &&
      other.pitch == pitch &&
      other.zoom == zoom &&
      other.pan == pan &&
      other.ortho == ortho;

  @override
  int get hashCode => Object.hash(yaw, pitch, zoom, pan, ortho);
}

/// World → view → screen transform for one frame.
class ViewProjector {
  ViewProjector({
    required this.camera,
    required this.size,
    required this.target,
    required double radius,
  }) : _cy = math.cos(camera.yaw),
       _sy = math.sin(camera.yaw),
       _cp = math.cos(camera.pitch),
       _sp = math.sin(camera.pitch),
       distance = radius * 2.8,
       scale =
           (math.min(size.width, size.height) * 0.42 / radius) * camera.zoom,
       center = size.center(Offset.zero) + camera.pan;

  final Camera3D camera;
  final Size size;
  final Vec3 target;
  final double distance;

  /// Pixels per foot at the focus plane.
  final double scale;
  final Offset center;
  final double _cy, _sy, _cp, _sp;

  Vec3 rotate(Vec3 p) {
    final x1 = p.x * _cy - p.z * _sy;
    final z1 = p.x * _sy + p.z * _cy;
    final y2 = p.y * _cp - z1 * _sp;
    final z2 = p.y * _sp + z1 * _cp;
    return Vec3(x1, y2, z2);
  }

  /// Inverse of [rotate] (view space → world orientation).
  Vec3 unrotate(Vec3 v) {
    final y = v.y * _cp + v.z * _sp;
    final z1 = -v.y * _sp + v.z * _cp;
    final x = v.x * _cy + z1 * _sy;
    final z = -v.x * _sy + z1 * _cy;
    return Vec3(x, y, z);
  }

  /// Camera position in world space. For orthographic projection a point
  /// very far along the view axis stands in for the parallel viewer.
  Vec3 get cameraWorld =>
      target + unrotate(Vec3(0, 0, camera.ortho ? distance * 1000 : distance));

  Vec3 toView(Vec3 world) => rotate(world - target);

  /// Larger = farther from the camera.
  double depth(Vec3 view) => camera.ortho ? -view.z : distance - view.z;

  Offset? projectView(Vec3 v) {
    if (camera.ortho) {
      return center + Offset(v.x * scale, -v.y * scale);
    }
    final d = distance - v.z;
    if (d < distance * 0.05) return null;
    final f = scale * distance / d;
    return center + Offset(v.x * f, -v.y * f);
  }

  Offset? project(Vec3 world) => projectView(toView(world));

  /// Whether a face with world [normal] through view-space point [viewPoint]
  /// faces the camera.
  bool facesCamera(Vec3 normal, Vec3 viewPoint) {
    final n = rotate(normal);
    if (camera.ortho) return n.z > 1e-6;
    final toCam = Vec3(-viewPoint.x, -viewPoint.y, distance - viewPoint.z);
    return n.dot(toCam) > 1e-6;
  }
}

/// Software renderer: back-face culling, painter's-algorithm ordering of
/// convex solids, Lambert flat shading, outlines, labels and dimensions.
class Scene3DPainter extends CustomPainter {
  Scene3DPainter({
    required this.scene,
    required this.camera,
    this.showDimensions = true,
    this.paintBackground = true,
    this.paintGround = true,
    this.paintGizmo = true,
  });

  final Scene scene;
  final Camera3D camera;
  final bool showDimensions;

  /// Sky gradient behind the scene. Off for photo overlays (Live Preview),
  /// where only the model is drawn on a transparent canvas.
  final bool paintBackground;
  final bool paintGround;
  final bool paintGizmo;

  static final Vec3 _light = const Vec3(-0.45, 0.8, 0.55).normalized();
  static const _ink = Color(0xFF1D1D1F);
  static const _red = Color(0xFFD71920);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final proj = ViewProjector(
      camera: camera,
      size: size,
      target: scene.focus,
      radius: scene.radius,
    );

    if (paintBackground) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE3EEF8), Color(0xFFF9FAFB)],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    if (paintGround) _paintGround(canvas, proj);

    final ordered = orderSolids(scene.solids, proj);
    for (final solid in ordered) {
      for (final f in solid.faces) {
        _paintFace(canvas, proj, f);
      }
      if (solid.decals.isEmpty) continue;
      final dn = solid.decalNormal;
      if (dn != null) {
        final anchor = proj.toView(Vec3.average(solid.decals.first.points));
        if (!proj.facesCamera(dn, anchor)) continue;
      }
      final decals = [...solid.decals]
        ..sort((a, b) {
          final byLayer = a.layer.compareTo(b.layer);
          if (byLayer != 0) return byLayer;
          return proj
              .depth(proj.toView(b.centroid))
              .compareTo(proj.depth(proj.toView(a.centroid)));
        });
      for (final f in decals) {
        _paintFace(canvas, proj, f);
      }
    }

    if (showDimensions) {
      for (final d in scene.dims) {
        _paintDim(canvas, proj, d);
      }
    }
    canvas.restore();
    if (paintGizmo) _paintGizmo(canvas, proj, size);
  }

  /// Back-to-front drawing order for convex solids.
  ///
  /// For pairs whose screen footprints overlap: when their bounding boxes are
  /// separated along an axis, the one on the camera's side of that gap can
  /// never be hidden by the other, so it is drawn later (exact, unlike
  /// centroid depth which fails for e.g. a tall pole just behind a wide board
  /// at low pitch). Pairs that touch or interpenetrate fall back to centroid
  /// depth via a topological sort.
  static List<Solid> orderSolids(List<Solid> solids, ViewProjector proj) {
    final n = solids.length;
    if (n < 2) return [...solids];
    final cam = proj.cameraWorld;
    final camK = [cam.x, cam.y, cam.z];
    final lo = <List<double>>[];
    final hi = <List<double>>[];
    final depth = <double>[];
    final screen = <Rect?>[]; // null = partly behind camera (overlaps all)
    for (final s in solids) {
      final mn = [double.infinity, double.infinity, double.infinity];
      final mx = [-double.infinity, -double.infinity, -double.infinity];
      var sMin = const Offset(double.infinity, double.infinity);
      var sMax = const Offset(-double.infinity, -double.infinity);
      var clipped = false;
      for (final f in s.faces) {
        for (final p in f.points) {
          final c = [p.x, p.y, p.z];
          for (var k = 0; k < 3; k++) {
            if (c[k] < mn[k]) mn[k] = c[k];
            if (c[k] > mx[k]) mx[k] = c[k];
          }
          final o = proj.project(p);
          if (o == null) {
            clipped = true;
          } else {
            sMin = Offset(math.min(sMin.dx, o.dx), math.min(sMin.dy, o.dy));
            sMax = Offset(math.max(sMax.dx, o.dx), math.max(sMax.dy, o.dy));
          }
        }
      }
      lo.add(mn);
      hi.add(mx);
      depth.add(proj.depth(proj.toView(s.centroid)));
      screen.add(clipped ? null : Rect.fromPoints(sMin, sMax));
    }

    bool overlapOnScreen(int i, int j) {
      final a = screen[i], b = screen[j];
      if (a == null || b == null) return true;
      return a.inflate(0.5).overlaps(b);
    }

    // -1: i must be drawn before j, 1: j before i, 0: undecided.
    int relation(int i, int j) {
      const eps = 1e-6;
      for (var k = 0; k < 3; k++) {
        if (hi[i][k] <= lo[j][k] + eps) {
          if (camK[k] >= lo[j][k]) return -1; // j faces the camera
          if (camK[k] <= hi[i][k]) return 1;
        } else if (hi[j][k] <= lo[i][k] + eps) {
          if (camK[k] >= lo[i][k]) return 1;
          if (camK[k] <= hi[j][k]) return -1;
        }
      }
      return 0;
    }

    final after = List.generate(n, (_) => <int>[]);
    final indegree = List.filled(n, 0);
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        // Only pairs that can hide each other need an order; constraining
        // non-overlapping pairs just creates spurious cycles.
        if (!overlapOnScreen(i, j)) continue;
        final r = relation(i, j);
        if (r < 0) {
          after[i].add(j);
          indegree[j]++;
        } else if (r > 0) {
          after[j].add(i);
          indegree[i]++;
        }
      }
    }

    // Kahn's algorithm, farthest-first among the ready solids. A cycle (rare
    // for disjoint boxes) is broken by taking the farthest remaining solid.
    final done = List.filled(n, false);
    final result = <Solid>[];
    for (var step = 0; step < n; step++) {
      var pick = -1;
      for (var pass = 0; pass < 2 && pick < 0; pass++) {
        for (var i = 0; i < n; i++) {
          if (done[i] || (pass == 0 && indegree[i] > 0)) continue;
          if (pick < 0 || depth[i] > depth[pick]) pick = i;
        }
      }
      done[pick] = true;
      result.add(solids[pick]);
      for (final j in after[pick]) {
        indegree[j]--;
      }
    }
    return result;
  }

  void _paintGround(Canvas canvas, ViewProjector proj) {
    final g = scene.groundHalfSize;
    final cx = scene.focus.x, cz = scene.focus.z;
    final corners = [
      Vec3(cx - g, 0, cz - g),
      Vec3(cx + g, 0, cz - g),
      Vec3(cx + g, 0, cz + g),
      Vec3(cx - g, 0, cz + g),
    ];
    final viewCentre = proj.toView(Vec3(cx, 0, cz));
    if (!proj.facesCamera(Vec3.up, viewCentre)) return;
    final pts = corners.map(proj.project).toList();
    if (pts.any((p) => p == null)) return;
    canvas.drawPath(
      Path()..addPolygon(pts.cast<Offset>(), true),
      Paint()..color = const Color(0xFFE6E9E2),
    );
    final grid = Paint()
      ..color = const Color(0x1F000000)
      ..strokeWidth = 0.8;
    final step = scene.gridStep;
    final n = (g / step).floor();
    for (var i = -n; i <= n; i++) {
      final o = i * step;
      final a1 = proj.project(Vec3(cx + o, 0, cz - g));
      final b1 = proj.project(Vec3(cx + o, 0, cz + g));
      final a2 = proj.project(Vec3(cx - g, 0, cz + o));
      final b2 = proj.project(Vec3(cx + g, 0, cz + o));
      if (a1 != null && b1 != null) canvas.drawLine(a1, b1, grid);
      if (a2 != null && b2 != null) canvas.drawLine(a2, b2, grid);
    }
  }

  static Color shade(Color c, double k) => Color.from(
    alpha: c.a,
    red: (c.r * k).clamp(0.0, 1.0),
    green: (c.g * k).clamp(0.0, 1.0),
    blue: (c.b * k).clamp(0.0, 1.0),
  );

  void _paintFace(Canvas canvas, ViewProjector proj, Face face) {
    final view = face.points.map(proj.toView).toList();
    if (!proj.facesCamera(face.normal, Vec3.average(view))) return;
    final pts = <Offset>[];
    for (final v in view) {
      final p = proj.projectView(v);
      if (p == null) return;
      pts.add(p);
    }
    final k = face.emissive
        ? 1.0
        : 0.5 + 0.5 * math.max(0.0, face.normal.dot(_light));
    final fill = shade(face.color, k);
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(path, Paint()..color = fill);
    if (face.outline) {
      canvas.drawPath(
        path,
        Paint()
          ..color = shade(face.color, k * 0.55).withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }
    if (face.label != null && pts.length >= 4) {
      _paintFaceLabel(canvas, face, pts);
    }
  }

  /// Draws text on a face using an affine map of its projected corners.
  void _paintFaceLabel(Canvas canvas, Face face, List<Offset> pts) {
    final p0 = pts[0], p1 = pts[1], p3 = pts[3];
    final ax = p1 - p0;
    final ay = p3 - p0;
    if (ax.distance < 18 || ay.distance < 6) return;
    final det = ax.dx * ay.dy - ax.dy * ay.dx;
    if (det <= 1) return; // edge-on or mirrored
    final wWorld = (face.points[1] - face.points[0]).length;
    final hWorld = (face.points[3] - face.points[0]).length;
    if (wWorld <= 0 || hWorld <= 0) return;
    const boxH = 100.0;
    final boxW = boxH * wWorld / hWorld;
    final tp = TextPainter(
      text: TextSpan(
        text: face.label,
        style: TextStyle(
          color: face.labelColor,
          fontSize: 56,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (tp.width <= 0 || tp.height <= 0) return;
    final s = math.min(boxW * 0.86 / tp.width, boxH * 0.62 / tp.height);
    canvas.save();
    canvas.transform(
      Float64List.fromList([
        ax.dx / boxW, ax.dy / boxW, 0, 0, //
        ay.dx / boxH, ay.dy / boxH, 0, 0, //
        0, 0, 1, 0, //
        p0.dx, p0.dy, 0, 1,
      ]),
    );
    canvas.translate(boxW / 2, boxH / 2);
    canvas.scale(s);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
    tp.dispose();
  }

  void _paintDim(Canvas canvas, ViewProjector proj, Dim3 d) {
    final pa = proj.project(d.a);
    final pb = proj.project(d.b);
    final qa = proj.project(d.a + d.offset);
    final qb = proj.project(d.b + d.offset);
    if (pa == null || pb == null || qa == null || qb == null) return;
    final len = (qb - qa).distance;
    if (len < 6) return;

    final ext = Paint()
      ..color = _ink.withValues(alpha: 0.45)
      ..strokeWidth = 0.8;
    canvas.drawLine(pa, _extend(pa, qa, 4), ext);
    canvas.drawLine(pb, _extend(pb, qb, 4), ext);

    final line = Paint()
      ..color = _red
      ..strokeWidth = 1.4;
    canvas.drawLine(qa, qb, line);
    final dir = (qb - qa) / len;
    _arrow(canvas, qa, dir, line.color);
    _arrow(canvas, qb, -dir, line.color);

    final tp = TextPainter(
      text: TextSpan(
        text: d.label,
        style: const TextStyle(
          color: _ink,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final mid = (qa + qb) / 2;
    final rect = Rect.fromCenter(
      center: mid,
      width: tp.width + 10,
      height: tp.height + 4,
    );
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas.drawRRect(rr, Paint()..color = Colors.white.withValues(alpha: 0.92));
    canvas.drawRRect(
      rr,
      Paint()
        ..color = _red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    tp.paint(canvas, rect.topLeft + const Offset(5, 2));
    tp.dispose();
  }

  static Offset _extend(Offset from, Offset to, double extra) {
    final v = to - from;
    final l = v.distance;
    if (l == 0) return to;
    return to + v / l * extra;
  }

  static void _arrow(Canvas canvas, Offset tip, Offset dir, Color color) {
    final n = Offset(-dir.dy, dir.dx);
    final base = tip + dir * 7;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(base.dx + n.dx * 3, base.dy + n.dy * 3)
        ..lineTo(base.dx - n.dx * 3, base.dy - n.dy * 3)
        ..close(),
      Paint()..color = color,
    );
  }

  void _paintGizmo(Canvas canvas, ViewProjector proj, Size size) {
    final origin = Offset(30, size.height - 30);
    const axes = [
      (Vec3(1, 0, 0), 'X', Color(0xFFD32F2F)),
      (Vec3(0, 1, 0), 'Y', Color(0xFF388E3C)),
      (Vec3(0, 0, 1), 'Z', Color(0xFF1976D2)),
    ];
    for (final (v, name, color) in axes) {
      final r = proj.rotate(v);
      final end = origin + Offset(r.x, -r.y) * 18;
      canvas.drawLine(
        origin,
        end,
        Paint()
          ..color = color
          ..strokeWidth = 2,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        origin + Offset(r.x, -r.y) * 25 - Offset(tp.width / 2, tp.height / 2),
      );
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant Scene3DPainter old) =>
      old.scene != scene ||
      old.camera != camera ||
      old.showDimensions != showDimensions ||
      old.paintBackground != paintBackground ||
      old.paintGround != paintGround ||
      old.paintGizmo != paintGizmo;
}
