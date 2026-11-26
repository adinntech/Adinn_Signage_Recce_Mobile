import 'dart:math' as math;
import 'dart:ui';

import '../preview3d/scene3d.dart';
import 'gsb_rules.dart';

/// Powder-coated exterior (blue, matching the Signage Fabrication Designer).
const Color kGsbPowderBlue = Color(0xFF1565B8);
const Color _edgeHighlight = Color(0xFF4A92DC);
const Color _galvanised = Color(0xFFB9C0C7);
const Color _screwSilver = Color(0xFFCDD2D7);
const Color _giScrew = Color(0xFF8F989F);
const Color _screwDark = Color(0xFF6F7880);
const Color _flexRed = Color(0xFFD71920);
const Color _flexInk = Color(0xFFF7F7F7);

/// Shared finished-board (exterior only) definition for GSB Single / Double.
/// One source for Live Preview, Camera AR and the Isometric view. Presentation
/// only: no frame pipes, LEDs, wiring, nuts / bolts or couplings, and nothing
/// here feeds fabrication or the BOM.
///
/// Scene units are feet; the front is at z = 0, the rear at z = −depth, the
/// board is centred on x = 0 and spans y = [bottomFt] … [bottomFt]+[heightFt].
class GsbPresentation {
  const GsbPresentation({
    required this.widthFt,
    required this.heightFt,
    required this.depthFt,
    required this.isDouble,
    this.bottomFt = 0,
    this.brand = 'ADINN',
    this.powderColor = kGsbPowderBlue,
    this.flexColor = _flexRed,
    this.labelColor = _flexInk,
    this.screws = true,
    this.ledOnRear = false,
  });

  final double widthFt;
  final double heightFt;
  final double depthFt;
  final double bottomFt;

  /// GSB Double: rear flex. GSB Single: rear GI sheet.
  final bool isDouble;
  final String brand;
  final Color powderColor;
  final Color flexColor;
  final Color labelColor;

  /// Exterior screw heads (presentation detail only).
  final bool screws;

  /// GSB Double: the ONE physical LED set faces the rear (default front).
  /// Only that face glows in Night View.
  final bool ledOnRear;

  /// Visible powder-coat return around the flex (0.75 in).
  static const double returnFt = 0.75 / 12;

  /// Flex stands this far proud of the cover (avoids coplanar z-fighting).
  static const double flexProudFt = 0.004;

  double get widthIn => widthFt * 12;
  double get heightIn => heightFt * 12;
  double get depthIn => depthFt * 12;
}

/// Decal layers on the powder-coated body. Strips < screw heads < head
/// centres, so a head is never painted under (painter) or z-fights with
/// (GL polygon offset) the edge highlight it overlaps.
const int kEdgeStripLayer = 1;
const int kScrewHeadLayer = 3;
const int kScrewCentreLayer = 4;

enum GsbCover { top, bottom, left, right }

/// One powder-coated cover screw, in board inches.
class GsbCoverScrew {
  const GsbCoverScrew(this.cover, this.alongIn, this.depthIn);

  final GsbCover cover;

  /// Top / bottom: from the left edge. Left / right: from the bottom edge.
  final double alongIn;

  /// From the front plane (0) towards the rear.
  final double depthIn;

  @override
  bool operator ==(Object other) =>
      other is GsbCoverScrew &&
      other.cover == cover &&
      other.alongIn == alongIn &&
      other.depthIn == depthIn;

  @override
  int get hashCode => Object.hash(cover, alongIn, depthIn);
}

/// Rear GI fixing, in board inches (x from the left edge, y from the bottom).
class GsbGiScrew {
  const GsbGiScrew(this.xIn, this.yIn);

  final double xIn;
  final double yIn;
}

/// Single source of the screw positions shown in all three views
/// (rulebook sections 13 / 14; reference: 6 × 3 ft Fabrication Designer).
///
/// Powder-coated covers: the nominal 0.75 in screws sit on the front and
/// rear returns (0.375 in from each edge) at the 12-in fixing stations along
/// every edge; the shared corners belong to the left / right covers only
/// (end rows: front + middle + rear, interior rows: front + rear), so no
/// corner has two screws. This is a **presentation** layout: it neither
/// feeds nor changes any fabrication quantity or BOM line.
class GsbScrewLayout {
  GsbScrewLayout._();

  static const double stationIn = 12;
  static const double endInsetIn = 1;
  static const double returnCentreIn = GsbPresentation.returnFt * 12 / 2;

  /// Interior 12-in stations of an edge of [lengthIn] (12, 24, … up to one
  /// station short of the far end).
  static List<double> stations(double lengthIn) => [
    for (var s = stationIn; s <= lengthIn - stationIn + 1e-6; s += stationIn) s,
  ];

  static List<GsbCoverScrew> cover({
    required double widthIn,
    required double heightIn,
    required double depthIn,
  }) {
    if (![widthIn, heightIn, depthIn].every((v) => v.isFinite && v > 0)) {
      return const [];
    }
    final front = math.min(returnCentreIn, depthIn / 4);
    final rear = depthIn - front;
    final mid = depthIn / 2;
    final out = <GsbCoverScrew>[];
    for (final cover in [GsbCover.left, GsbCover.right]) {
      final end = math.min(endInsetIn, heightIn / 4);
      for (final y in [end, heightIn - end]) {
        for (final z in [front, mid, rear]) {
          out.add(GsbCoverScrew(cover, y, z));
        }
      }
      for (final y in stations(heightIn)) {
        for (final z in [front, rear]) {
          out.add(GsbCoverScrew(cover, y, z));
        }
      }
    }
    for (final cover in [GsbCover.top, GsbCover.bottom]) {
      for (final x in stations(widthIn)) {
        for (final z in [front, rear]) {
          out.add(GsbCoverScrew(cover, x, z));
        }
      }
    }
    return out;
  }

  /// GSB Single rear GI: ONE shared fixing row per 6-in overlap joint, at the
  /// rear supporting-pipe stations. No other pitch is invented: boards
  /// without an approved GI tier plan or whole-foot support spacing get none.
  static List<GsbGiScrew> gi({
    required double widthIn,
    required double heightIn,
  }) {
    try {
      final plan = GsbRules.plan(
        GsbBoardInput(
          variant: GsbVariant.single,
          widthIn: widthIn,
          heightIn: heightIn,
        ),
      );
      final tiers = plan.giTiersIn;
      if (tiers == null || tiers.length < 2) return const [];
      final out = <GsbGiScrew>[];
      var bottom = 0.0;
      for (var i = 0; i + 1 < tiers.length; i++) {
        final top = bottom + tiers[i];
        final row = top - GsbSpec.giOverlapIn / 2;
        for (final m in plan.modules) {
          final st = plan.modules.length == 1
              ? GsbRules.supportStations(m.widthIn).$1
              : m.supportStationsIn;
          if (st == null) continue;
          if (m.row != 0) continue; // GI is laid on the whole board height
          for (final s in st) {
            out.add(GsbGiScrew(m.x0In + s, row));
          }
        }
        bottom = top - GsbSpec.giOverlapIn;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

class GsbFinishedBoard {
  GsbFinishedBoard._();

  /// Exterior solids: the powder-coated body (with edge highlights and the
  /// screw decals), the front flex and – GSB Double – the rear flex. GSB
  /// Single's rear GI is the body's rear face.
  static List<Solid> build(
    GsbPresentation c, {
    String bodyName = 'board',
    String frontName = 'gsb_front_flex',
    String rearName = 'gsb_rear_flex',
  }) {
    final w = _fin(c.widthFt, 0.5), h = _fin(c.heightFt, 0.5);
    final d = _fin(c.depthFt, 0.1);
    final b = c.bottomFt.isFinite ? c.bottomFt : 0.0;
    final t = b + h, x0 = -w / 2, x1 = w / 2;
    final ret = math.min(GsbPresentation.returnFt, math.min(w, h) * 0.2);

    final body = Shapes.box(
      Vec3(x0, b, -d),
      Vec3(x1, t, 0),
      c.powderColor,
      name: bodyName,
      sideColors: {BoxSide.back: c.isDouble ? c.powderColor : _galvanised},
    );
    _edgeStrips(body, x0, x1, b, t);
    if (c.screws) _screws(body, c, w, h, d, b);

    final proud = GsbPresentation.flexProudFt;
    final front = Solid(
      name: frontName,
      faces: [
        Shapes.frontQuad(
          x0 + ret,
          b + ret,
          x1 - ret,
          t - ret,
          proud,
          c.flexColor,
          label: c.brand,
          labelColor: c.labelColor,
          layer: 0,
          emissive: true,
          outline: false,
        ),
      ],
    );
    // Night View is an illustrative presentation: both flex faces of a
    // GSB Double glow softly (the physical LED set is still ONE, on
    // [GsbPresentation.ledOnRear]; optical feasibility needs review).
    front.faces.single.glow = true;
    final out = [body, front];
    if (c.isDouble) {
      final z = -d - proud;
      final rear = Face(
        [
          Vec3(x1 - ret, t - ret, z),
          Vec3(x0 + ret, t - ret, z),
          Vec3(x0 + ret, b + ret, z),
          Vec3(x1 - ret, b + ret, z),
        ],
        c.flexColor,
        const Vec3(0, 0, -1),
        label: c.brand,
        labelColor: c.labelColor,
        emissive: true,
        outline: false,
      )..glow = true;
      out.add(Solid(name: rearName, faces: [rear]));
    }
    return out;
  }

  static double _fin(double v, double min) => v.isFinite && v > min ? v : min;

  /// Soft light strip along the front edge of the four side covers.
  static void _edgeStrips(
    Solid body,
    double x0,
    double x1,
    double b,
    double t,
  ) {
    const o = 0.002, z0 = -0.012, z1 = -0.05;
    Face f(List<Vec3> p, Vec3 n) =>
        Face(p, _edgeHighlight, n, outline: false, layer: kEdgeStripLayer);
    body.decals.addAll([
      f([
        Vec3(x0 - o, t, z1),
        Vec3(x0 - o, t, z0),
        Vec3(x0 - o, b, z0),
        Vec3(x0 - o, b, z1),
      ], const Vec3(-1, 0, 0)),
      f([
        Vec3(x1 + o, t, z0),
        Vec3(x1 + o, t, z1),
        Vec3(x1 + o, b, z1),
        Vec3(x1 + o, b, z0),
      ], const Vec3(1, 0, 0)),
      f([
        Vec3(x0, t + o, z1),
        Vec3(x1, t + o, z1),
        Vec3(x1, t + o, z0),
        Vec3(x0, t + o, z0),
      ], const Vec3(0, 1, 0)),
      f([
        Vec3(x0, b - o, z0),
        Vec3(x1, b - o, z0),
        Vec3(x1, b - o, z1),
        Vec3(x0, b - o, z1),
      ], const Vec3(0, -1, 0)),
    ]);
  }

  /// Screw heads from [GsbScrewLayout]: flat hexagons (plus a darker centre
  /// while the count is small) in ONE solid's decals – no per-screw object,
  /// light or mesh. Faces carry their cover's normal, so a screw is only
  /// painted while its cover faces the camera.
  static void _screws(
    Solid body,
    GsbPresentation c,
    double w,
    double h,
    double d,
    double b,
  ) {
    // Head radius grows with the board so it stays visible in photo
    // overlays (a fixed 0.26 in head was sub-pixel on small previews).
    // Capped below half the 0.75-in return (0.375 in = 0.03125 ft) so a head
    // on the front / rear screw line never overhangs the board edge.
    final r = math.min(
      math.max(0.025, 0.0045 * math.max(w, h)),
      GsbPresentation.returnFt / 2 * 0.92,
    );
    const o = 0.002;
    final x0 = -w / 2, t = b + h;
    final cover = GsbScrewLayout.cover(
      widthIn: w * 12,
      heightIn: h * 12,
      depthIn: d * 12,
    );
    final giScrews = c.isDouble
        ? const <GsbGiScrew>[]
        : GsbScrewLayout.gi(widthIn: w * 12, heightIn: h * 12);
    final centres = cover.length + giScrews.length <= 64;
    void head(Vec3 p, Vec3 n, Vec3 u, Vec3 v, double rad, Color color) {
      body.decals.add(_disc(p, n, u, v, rad, color, kScrewHeadLayer));
      if (centres) {
        body.decals.add(
          _disc(p, n, u, v, rad * 0.42, _screwDark, kScrewCentreLayer),
        );
      }
    }

    for (final s in cover) {
      final z = -s.depthIn / 12;
      final a = s.alongIn / 12;
      switch (s.cover) {
        case GsbCover.left:
          head(
            Vec3(x0 - o, b + a, z),
            const Vec3(-1, 0, 0),
            const Vec3(0, 0, 1),
            const Vec3(0, 1, 0),
            r,
            _screwSilver,
          );
        case GsbCover.right:
          head(
            Vec3(-x0 + o, b + a, z),
            const Vec3(1, 0, 0),
            const Vec3(0, 0, 1),
            const Vec3(0, 1, 0),
            r,
            _screwSilver,
          );
        case GsbCover.top:
          head(
            Vec3(x0 + a, t + o, z),
            const Vec3(0, 1, 0),
            const Vec3(1, 0, 0),
            const Vec3(0, 0, 1),
            r,
            _screwSilver,
          );
        case GsbCover.bottom:
          head(
            Vec3(x0 + a, b - o, z),
            const Vec3(0, -1, 0),
            const Vec3(1, 0, 0),
            const Vec3(0, 0, 1),
            r,
            _screwSilver,
          );
      }
    }
    for (final g in giScrews) {
      head(
        Vec3(x0 + g.xIn / 12, b + g.yIn / 12, -d - o),
        const Vec3(0, 0, -1),
        const Vec3(1, 0, 0),
        const Vec3(0, 1, 0),
        r * 0.9,
        _giScrew,
      );
    }
  }

  static Face _disc(
    Vec3 centre,
    Vec3 normal,
    Vec3 u,
    Vec3 v,
    double r,
    Color color,
    int layer,
  ) {
    const sides = 6;
    final off = normal * (layer == kScrewCentreLayer ? 0.0008 : 0.0);
    return Face(
      [
        for (var i = 0; i < sides; i++)
          centre +
              off +
              u * (r * math.cos(2 * math.pi * i / sides)) +
              v * (r * math.sin(2 * math.pi * i / sides)),
      ],
      color,
      normal,
      outline: false,
      layer: layer,
    );
  }
}
