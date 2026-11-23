import 'dart:math' as math;
import 'dart:ui';

import '../preview3d/scene3d.dart';
import 'nlb_rules.dart';

const Color _frameSteel = Color(0xFF2B3036);
const Color _supportSteel = Color(0xFF454C54);
const Color _backingGrey = Color(0xFFC4C6C9);

/// NLB Single Frame (rulebook NON_LIT): a slim single-plane steel frame –
/// perimeter plus the vertical supports at the Section-07 bay stations – in
/// FRONT of the advertising / backing surface, so the pipes stay visible
/// (unlike the flex-covered box). The 1 in section is the app's configured
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

  double get depthFt => profileIn / 12;
}

class NlbSingleBoard {
  NlbSingleBoard._();

  /// Perimeter + vertical support members (all share [memberName]) and the
  /// backing surface ([flexName]). Front at z = 0, rear at z = −profile.
  static List<Solid> build(
    NlbSinglePresentation c, {
    String memberName = 'board',
    String flexName = 'nlb_backing',
  }) {
    double fin(double v, double min) => v.isFinite && v > min ? v : min;
    final w = fin(c.widthFt, 0.5), h = fin(c.heightFt, 0.5);
    final p = math.min(fin(c.profileIn, 0.2) / 12, math.min(w, h) / 6);
    final b = c.bottomFt.isFinite ? c.bottomFt : 0.0;
    final t = b + h, x0 = -w / 2, x1 = w / 2;
    Solid bar(Vec3 min, Vec3 max, Color color) =>
        Shapes.box(min, max, color, name: memberName);
    final out = <Solid>[
      Solid(
        name: flexName,
        faces: [
          Shapes.frontQuad(
            x0 + p,
            b + p,
            x1 - p,
            t - p,
            -p * 0.9, // behind the pipes (painter orders by centroid depth)
            c.backing,
            label: c.brand,
            labelColor: c.printColor,
            layer: 0,
            outline: false,
          ),
        ],
      ),
      bar(Vec3(x0, t - p, -p), Vec3(x1, t, 0), _frameSteel),
      bar(Vec3(x0, b, -p), Vec3(x1, b + p, 0), _frameSteel),
      bar(Vec3(x0, b + p, -p), Vec3(x0 + p, t - p, 0), _frameSteel),
      bar(Vec3(x1 - p, b + p, -p), Vec3(x1, t - p, 0), _frameSteel),
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
          Vec3(x - p * 0.4, b + p, -p),
          Vec3(x + p * 0.4, t - p, 0),
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
