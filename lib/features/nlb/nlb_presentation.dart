import 'dart:math' as math;
import 'dart:ui';

import '../preview3d/scene3d.dart';
import 'nlb_rules.dart';

const Color _frameSteel = Color(0xFF2B3036);
const Color _supportSteel = Color(0xFF454C54);
const Color _backingGrey = Color(0xFFC4C6C9);

/// NLB Single Frame (rulebook NON_LIT): a slim single-plane steel frame –
/// perimeter plus the vertical supports at the Section-07 bay stations –
/// BEHIND one continuous advertising flex (viewer → print → steel → rear),
/// as in the physical installation. The 1 in section is the app's configured
/// SHS profile (illustrative until the profile is confirmed); no GSB box,
/// depth connectors, braces, GI, powder coat or LEDs. Horizontal intermediate
/// supports (>= 7 ft) are NOT drawn: their position is not specified.
class NlbSinglePresentation {
  const NlbSinglePresentation({
    required this.widthFt,
    required this.heightFt,
    this.bottomFt = 0,
    this.profileIn = 1,
    this.brand = 'ADINN',
    this.backing = _backingGrey,
    this.printColor = const Color(0xFFD71920),
  });

  final double widthFt;
  final double heightFt;
  final double bottomFt;
  final double profileIn;
  final String brand;
  final Color backing;
  final Color printColor;

  /// Visual thickness of the stretched flex sheet (≈1.2 mm). Presentation
  /// only – it is NOT a fabrication/BOM value. It keeps the printed face and
  /// the sheet's reverse surface from sharing a depth plane with the steel.
  static const double flexThicknessFt = 0.004;

  double get depthFt => profileIn / 12;
}

class NlbSingleBoard {
  NlbSingleBoard._();

  /// One continuous flex sheet ([flexName]) in front of the perimeter and
  /// vertical support members (all sharing [memberName]).
  ///
  /// Scene depth: printed face z = 0, flex reverse z = −flexThicknessFt,
  /// steel from −flexThicknessFt to −(flexThicknessFt + profile). The frame
  /// therefore cannot interrupt the print at any front angle, while from the
  /// rear the pipes remain separate solids in front of the unprinted flex
  /// reverse (open bays show flex, not a black backing panel).
  static List<Solid> build(
    NlbSinglePresentation c, {
    String memberName = 'board',
    String flexName = 'nlb_backing',
  }) {
    double fin(double v, double min) => v.isFinite && v > min ? v : min;
    final w = fin(c.widthFt, 0.5), h = fin(c.heightFt, 0.5);
    final p = math.min(fin(c.profileIn, 0.2) / 12, math.min(w, h) / 6);
    final ft = NlbSinglePresentation.flexThicknessFt;
    final b = c.bottomFt.isFinite ? c.bottomFt : 0.0;
    final t = b + h, x0 = -w / 2, x1 = w / 2;
    Solid bar(Vec3 min, Vec3 max, Color color) =>
        Shapes.box(min, max, color, name: memberName);
    final out = <Solid>[
      // Single full-size sheet: front label, plain reverse, no gaps between
      // structural members and no second printed rear surface.
      Solid(
        name: flexName,
        faces: Shapes.boxFaces(
          Vec3(x0, b, -ft),
          Vec3(x1, t, 0),
          c.backing,
          labels: {BoxSide.front: c.brand},
          labelColor: c.printColor,
          outline: false,
        ),
      ),
      bar(Vec3(x0, t - p, -ft - p), Vec3(x1, t, -ft), _frameSteel),
      bar(Vec3(x0, b, -ft - p), Vec3(x1, b + p, -ft), _frameSteel),
      bar(
        Vec3(x0, b + p, -ft - p),
        Vec3(x0 + p, t - p, -ft),
        _frameSteel,
      ),
      bar(
        Vec3(x1 - p, b + p, -ft - p),
        Vec3(x1, t - p, -ft),
        _frameSteel,
      ),
    ];
    // Vertical supports at the rulebook bay stations (none when the width
    // has no approved bay rule: reported as Requires Review, not invented).
    final stations = NlbRules.plan(
      variant: NlbVariant.singleFrame,
      widthIn: w * 12,
      heightIn: h * 12,
    ).supportStationsIn;
    for (final s in stations) {
      final x = x0 + s / 12;
      out.add(
        bar(
          Vec3(x - p * 0.4, b + p, -ft - p),
          Vec3(x + p * 0.4, t - p, -ft),
          _supportSteel,
        ),
      );
    }
    return out;
  }
}

const Color _flexWhite = Color(0xFFF7F7F7);
const Color _sideFlex = Color(0xFFF0F0F2);
const Color _printInk = Color(0xFFD71920);

/// Finished NLB Box Frame (rulebook NON_LIT_BOX): a fully flex-covered box,
/// 4 in deep by default – printed front, printed rear, white top / bottom /
/// left / right. The steel frame, vertical / horizontal pipes, connectors and
/// bolts exist only in the fabrication data and are never drawn here. Not
/// lit: no emission, no powder coat, no screws, no GI.
///
/// Scene units are feet; front at z = 0, rear at z = −depth, centred on x = 0,
/// y from [bottomFt].
class NlbBoxPresentation {
  const NlbBoxPresentation({
    required this.widthFt,
    required this.heightFt,
    required this.depthFt,
    this.bottomFt = 0,
    this.brand = 'ADINN',
    this.flexColor = _flexWhite,
    this.printColor = _printInk,
  });

  final double widthFt;
  final double heightFt;
  final double depthFt;
  final double bottomFt;
  final String brand;
  final Color flexColor;
  final Color printColor;

  /// Print stands this far proud of the cover (avoids coplanar z-fighting).
  static const double printProudFt = 0.004;
}

class NlbBoxBoard {
  NlbBoxBoard._();

  static List<Solid> build(
    NlbBoxPresentation c, {
    String bodyName = 'board',
    String frontName = 'nlb_front_print',
    String rearName = 'nlb_rear_print',
  }) {
    double fin(double v, double min) => v.isFinite && v > min ? v : min;
    final w = fin(c.widthFt, 0.5), h = fin(c.heightFt, 0.5);
    final d = fin(c.depthFt, 0.1);
    final b = c.bottomFt.isFinite ? c.bottomFt : 0.0;
    final t = b + h, x0 = -w / 2, x1 = w / 2;
    // Print inset so the white flex wraps the edges (about 0.5 in).
    final ins = math.min(0.04, math.min(w, h) * 0.1);
    final proud = NlbBoxPresentation.printProudFt;

    final body = Shapes.box(
      Vec3(x0, b, -d),
      Vec3(x1, t, 0),
      _sideFlex,
      name: bodyName,
      sideColors: {BoxSide.front: c.flexColor, BoxSide.back: c.flexColor},
    );
    final front = Solid(
      name: frontName,
      faces: [
        Shapes.frontQuad(
          x0 + ins,
          b + ins,
          x1 - ins,
          t - ins,
          proud,
          c.flexColor,
          label: c.brand,
          labelColor: c.printColor,
          layer: 0,
          outline: false,
        ),
      ],
    );
    final z = -d - proud;
    // Seen from behind the label's top-left corner is the board's +x end,
    // so the rear text reads normally (not mirrored).
    final rear = Solid(
      name: rearName,
      faces: [
        Face(
          [
            Vec3(x1 - ins, t - ins, z),
            Vec3(x0 + ins, t - ins, z),
            Vec3(x0 + ins, b + ins, z),
            Vec3(x1 - ins, b + ins, z),
          ],
          c.flexColor,
          const Vec3(0, 0, -1),
          label: c.brand,
          labelColor: c.printColor,
          outline: false,
        ),
      ],
    );
    return [body, front, rear];
  }
}
