import 'dart:math' as math;
import 'dart:ui';

/// Minimal immutable 3D vector (feet). X → right, Y → up, Z → towards the
/// street / viewer.
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  static const zero = Vec3(0, 0, 0);
  static const up = Vec3(0, 1, 0);

  final double x;
  final double y;
  final double z;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator -() => Vec3(-x, -y, -z);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);

  double get length => math.sqrt(dot(this));

  Vec3 normalized() {
    final l = length;
    return l == 0 ? this : this * (1 / l);
  }

  static Vec3 average(List<Vec3> pts) {
    if (pts.isEmpty) return zero;
    var sx = 0.0, sy = 0.0, sz = 0.0;
    for (final p in pts) {
      sx += p.x;
      sy += p.y;
      sz += p.z;
    }
    final n = pts.length.toDouble();
    return Vec3(sx / n, sy / n, sz / n);
  }

  @override
  bool operator ==(Object other) =>
      other is Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() =>
      'Vec3(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}

/// A flat convex polygon with an explicit outward normal.
///
/// For labelled faces the points are ordered top-left, top-right,
/// bottom-right, bottom-left as seen from outside.
class Face {
  Face(
    this.points,
    this.color,
    this.normal, {
    this.outline = true,
    this.emissive = false,
    this.label,
    this.labelColor = const Color(0xFFFFFFFF),
    this.layer = 0,
  });

  final List<Vec3> points;
  final Color color;
  final Vec3 normal;
  final bool outline;

  /// Self-lit (e.g. the glowing face of a GSB) – ignores scene lighting.
  final bool emissive;

  /// Night View only: whether this self-lit face actually glows. Null =
  /// follows [emissive]. A self-lit face with `glow = false` looks normal
  /// by day but is NOT lit at night (e.g. the rear flex of a GSB Double
  /// whose single LED set faces the front).
  bool? glow;
  bool get glowsAtNight => glow ?? emissive;

  /// One-way-vision film: physical pitch (feet) of the perforation grid
  /// punched through this face (null = solid). Rendered as a see-through
  /// mask by the painter – never as individual mesh holes.
  double? perforationPitchFt;

  /// Hole diameter as a fraction of the pitch (illustrative preset).
  double perforationHole = 0.6;
  final String? label;
  final Color labelColor;

  /// Draw order among decals of one solid (lower first).
  final int layer;

  Vec3 get centroid => Vec3.average(points);
}

/// A convex object (box, beam, cylinder) plus optional surface decals
/// (artwork, shutters, letters) drawn right after its own faces.
class Solid {
  Solid({this.name = '', List<Face>? faces}) : faces = faces ?? <Face>[];

  final String name;
  final List<Face> faces;
  final List<Face> decals = [];

  /// Decals are only drawn while this normal faces the camera.
  Vec3? decalNormal;

  Vec3? _centroid;
  Vec3 get centroid =>
      _centroid ??= Vec3.average([for (final f in faces) ...f.points]);
}

/// A dimension line between [a] and [b], drawn [offset] away from the
/// measured edge.
class Dim3 {
  const Dim3(this.a, this.b, this.offset, this.label);

  final Vec3 a;
  final Vec3 b;
  final Vec3 offset;
  final String label;
}

class Scene {
  Scene({required this.focus});

  /// Orbit target – the centre of the signage board.
  final Vec3 focus;
  final List<Solid> solids = [];
  final List<Dim3> dims = [];

  double groundHalfSize = 20;
  double gridStep = 2;

  double _radius = 0;
  Vec3 _min = Vec3.zero;
  Vec3 _max = Vec3.zero;

  /// Radius around [focus] that contains the whole scene.
  double get radius => _radius;
  Vec3 get boundsMin => _min;
  Vec3 get boundsMax => _max;

  int get faceCount =>
      solids.fold(0, (s, e) => s + e.faces.length + e.decals.length);

  void add(Solid s) => solids.add(s);

  void finalize() {
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    var r = 0.0;
    for (final s in solids) {
      for (final f in [...s.faces, ...s.decals]) {
        for (final p in f.points) {
          minX = math.min(minX, p.x);
          minY = math.min(minY, p.y);
          minZ = math.min(minZ, p.z);
          maxX = math.max(maxX, p.x);
          maxY = math.max(maxY, p.y);
          maxZ = math.max(maxZ, p.z);
          r = math.max(r, (p - focus).length);
        }
      }
    }
    if (minX == double.infinity) {
      _min = _max = focus;
      _radius = 5;
    } else {
      _min = Vec3(minX, minY, minZ);
      _max = Vec3(maxX, maxY, maxZ);
      _radius = math.max(r, 4);
    }
    groundHalfSize = math.max(_radius * 1.25, 12);
    gridStep = _radius < 18
        ? 2
        : _radius < 45
        ? 5
        : 10;
  }
}

enum BoxSide { front, back, left, right, top, bottom }

/// Geometry helpers that create solids with correct outward normals.
class Shapes {
  Shapes._();

  static List<Face> boxFaces(
    Vec3 min,
    Vec3 max,
    Color color, {
    Map<BoxSide, Color> sideColors = const {},
    Map<BoxSide, String> labels = const {},
    Color labelColor = const Color(0xFFFFFFFF),
    Set<BoxSide> emissive = const {},
    Set<BoxSide> skip = const {},
    int layer = 0,
    bool outline = true,
  }) {
    final x0 = min.x, y0 = min.y, z0 = min.z;
    final x1 = max.x, y1 = max.y, z1 = max.z;
    final defs = <BoxSide, (List<Vec3>, Vec3)>{
      BoxSide.front: (
        [
          Vec3(x0, y1, z1),
          Vec3(x1, y1, z1),
          Vec3(x1, y0, z1),
          Vec3(x0, y0, z1),
        ],
        const Vec3(0, 0, 1),
      ),
      BoxSide.back: (
        [
          Vec3(x1, y1, z0),
          Vec3(x0, y1, z0),
          Vec3(x0, y0, z0),
          Vec3(x1, y0, z0),
        ],
        const Vec3(0, 0, -1),
      ),
      BoxSide.right: (
        [
          Vec3(x1, y1, z1),
          Vec3(x1, y1, z0),
          Vec3(x1, y0, z0),
          Vec3(x1, y0, z1),
        ],
        const Vec3(1, 0, 0),
      ),
      BoxSide.left: (
        [
          Vec3(x0, y1, z0),
          Vec3(x0, y1, z1),
          Vec3(x0, y0, z1),
          Vec3(x0, y0, z0),
        ],
        const Vec3(-1, 0, 0),
      ),
      BoxSide.top: (
        [
          Vec3(x0, y1, z0),
          Vec3(x1, y1, z0),
          Vec3(x1, y1, z1),
          Vec3(x0, y1, z1),
        ],
        const Vec3(0, 1, 0),
      ),
      BoxSide.bottom: (
        [
          Vec3(x0, y0, z1),
          Vec3(x1, y0, z1),
          Vec3(x1, y0, z0),
          Vec3(x0, y0, z0),
        ],
        const Vec3(0, -1, 0),
      ),
    };
    return [
      for (final e in defs.entries)
        if (!skip.contains(e.key))
          Face(
            e.value.$1,
            sideColors[e.key] ?? color,
            e.value.$2,
            label: labels[e.key],
            labelColor: labelColor,
            emissive: emissive.contains(e.key),
            layer: layer,
            outline: outline,
          ),
    ];
  }

  static Solid box(
    Vec3 min,
    Vec3 max,
    Color color, {
    String name = '',
    Map<BoxSide, Color> sideColors = const {},
    Map<BoxSide, String> labels = const {},
    Color labelColor = const Color(0xFFFFFFFF),
    Set<BoxSide> emissive = const {},
  }) => Solid(
    name: name,
    faces: boxFaces(
      min,
      max,
      color,
      sideColors: sideColors,
      labels: labels,
      labelColor: labelColor,
      emissive: emissive,
    ),
  );

  /// Square-section member between two arbitrary points.
  static Solid beam(
    Vec3 a,
    Vec3 b,
    double thickness,
    Color color, {
    String name = 'beam',
  }) {
    final u = (b - a).normalized();
    final ref = u.y.abs() < 0.95 ? Vec3.up : const Vec3(1, 0, 0);
    final w = u.cross(ref).normalized();
    final v = w.cross(u).normalized();
    final h = thickness / 2;
    Vec3 c(Vec3 base, double sv, double sw) =>
        base + v * (sv * h) + w * (sw * h);
    final a1 = c(a, 1, 1),
        a2 = c(a, 1, -1),
        a3 = c(a, -1, -1),
        a4 = c(a, -1, 1);
    final b1 = c(b, 1, 1),
        b2 = c(b, 1, -1),
        b3 = c(b, -1, -1),
        b4 = c(b, -1, 1);
    return Solid(
      name: name,
      faces: [
        Face([a1, b1, b2, a2], color, v),
        Face([a3, b3, b4, a4], color, -v),
        Face([a4, b4, b1, a1], color, w),
        Face([a2, b2, b3, a3], color, -w),
        Face([a1, a2, a3, a4], color, -u),
        Face([b1, b4, b3, b2], color, u),
      ],
    );
  }

  /// Low-poly cylinder along the Z axis from [z0] to [z1] (studs, standoffs).
  /// The cap at the larger z faces +Z (or the Z of the front cap colour
  /// [capColor]); the smaller-z end faces −Z.
  static Solid zCylinder(
    double cx,
    double cy,
    double z0,
    double z1,
    double radius,
    Color color, {
    int sides = 10,
    String name = 'stud',
    Color? capColor,
  }) {
    final lo = math.min(z0, z1), hi = math.max(z0, z1);
    final ring = <Vec3>[
      for (var i = 0; i < sides; i++)
        Vec3(
          cx + radius * math.cos(2 * math.pi * i / sides),
          cy + radius * math.sin(2 * math.pi * i / sides),
          0,
        ),
    ];
    final faces = <Face>[];
    for (var i = 0; i < sides; i++) {
      final j = (i + 1) % sides;
      final mid = 2 * math.pi * (i + 0.5) / sides;
      faces.add(
        Face(
          [
            Vec3(ring[i].x, ring[i].y, hi),
            Vec3(ring[j].x, ring[j].y, hi),
            Vec3(ring[j].x, ring[j].y, lo),
            Vec3(ring[i].x, ring[i].y, lo),
          ],
          color,
          Vec3(math.cos(mid), math.sin(mid), 0),
          outline: false,
        ),
      );
    }
    faces.add(
      Face(
        [for (final p in ring) Vec3(p.x, p.y, hi)],
        capColor ?? color,
        const Vec3(0, 0, 1),
        outline: false,
      ),
    );
    faces.add(
      Face(
        [for (final p in ring.reversed) Vec3(p.x, p.y, lo)],
        color,
        const Vec3(0, 0, -1),
        outline: false,
      ),
    );
    return Solid(name: name, faces: faces);
  }

  /// Vertical n-sided prism approximating a round pole.
  static Solid cylinder(
    Vec3 base,
    double radius,
    double height,
    Color color, {
    int sides = 12,
    String name = 'pole',
  }) {
    final faces = <Face>[];
    final bottom = <Vec3>[];
    final top = <Vec3>[];
    for (var i = 0; i < sides; i++) {
      final t = 2 * math.pi * i / sides;
      final p = Vec3(
        base.x + radius * math.cos(t),
        base.y,
        base.z + radius * math.sin(t),
      );
      bottom.add(p);
      top.add(Vec3(p.x, base.y + height, p.z));
    }
    for (var i = 0; i < sides; i++) {
      final j = (i + 1) % sides;
      final mid = 2 * math.pi * (i + 0.5) / sides;
      faces.add(
        Face(
          [top[i], top[j], bottom[j], bottom[i]],
          color,
          Vec3(math.cos(mid), 0, math.sin(mid)),
          outline: false,
        ),
      );
    }
    faces.add(Face(top, color, Vec3.up));
    faces.add(Face(bottom.reversed.toList(), color, const Vec3(0, -1, 0)));
    return Solid(name: name, faces: faces);
  }

  /// Axis-aligned rectangle lying on the plane z = [z], facing +Z.
  static Face frontQuad(
    double x0,
    double y0,
    double x1,
    double y1,
    double z,
    Color color, {
    String? label,
    Color labelColor = const Color(0xFFFFFFFF),
    int layer = 1,
    bool emissive = false,
    bool outline = true,
  }) => Face(
    [Vec3(x0, y1, z), Vec3(x1, y1, z), Vec3(x1, y0, z), Vec3(x0, y0, z)],
    color,
    const Vec3(0, 0, 1),
    label: label,
    labelColor: labelColor,
    layer: layer,
    emissive: emissive,
    outline: outline,
  );
}
