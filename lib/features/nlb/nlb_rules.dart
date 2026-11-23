/// NLB (Non-Lit Board) fabrication rules from the Signage Fabrication Master
/// Rulebook 1.0: Section 07 (NON_LIT = "NLB Single Frame") and Section 08
/// (NON_LIT_BOX = "NLB Box Frame"). Pure Dart, exact inches. Anything the
/// rulebook leaves open is reported as Requires Review; no geometry or
/// spacing is invented for it.
library;

import '../gsb/gsb_rules.dart' show GsbIssue, GsbIssueLevel;

const kNlbRuleVersion = 'SFR-1.0 (21 Nov 2026)';

enum NlbVariant { singleFrame, boxFrame }

extension NlbVariantX on NlbVariant {
  /// Stored subtype key (additive `Board.nlbSubtype`).
  String get key => switch (this) {
    NlbVariant.singleFrame => 'NLB_SINGLE_FRAME',
    NlbVariant.boxFrame => 'NLB_BOX_FRAME',
  };

  /// Rulebook board-type key (section 03).
  String get rulebookKey => switch (this) {
    NlbVariant.singleFrame => 'NON_LIT',
    NlbVariant.boxFrame => 'NON_LIT_BOX',
  };

  String get label => switch (this) {
    NlbVariant.singleFrame => 'NLB Single Frame',
    NlbVariant.boxFrame => 'NLB Box Frame',
  };

  static NlbVariant? fromKey(String? key) => switch (key) {
    'NLB_SINGLE_FRAME' => NlbVariant.singleFrame,
    'NLB_BOX_FRAME' => NlbVariant.boxFrame,
    _ => null,
  };
}

class NlbSpec {
  NlbSpec._();

  /// Maximum vertical-support bay (NON_LIT).
  static const double maxBayIn = 30;
  static const double oddEdgeBayIn = 24;

  /// NON_LIT_BOX overall outside depth.
  static const double boxDepthIn = 4;

  /// Height at which the common Non-Lit height separation activates.
  static const double heightSplitAboveIn = 48;

  /// Height from which the Non-Lit intermediate horizontal rule applies.
  static const double horizontalFromIn = 84;

  /// Box depth-connector span limits (section 08).
  static const double connectorMinSpanIn = 24;
  static const double connectorOneStationMaxIn = 96;
}

class NlbPlan {
  const NlbPlan({
    required this.variant,
    required this.widthIn,
    required this.heightIn,
    required this.depthIn,
    required this.bays,
    required this.widthConnectorsIn,
    required this.heightConnectorsIn,
    required this.connectorCutIn,
    required this.issues,
  });

  final NlbVariant variant;
  final double widthIn;
  final double heightIn;

  /// Single frame: nominal single-plane (not specified); box: 4 in.
  final double? depthIn;

  /// NON_LIT vertical support bays (null = review / not applicable).
  final List<double>? bays;

  /// NON_LIT_BOX depth-connector stations along the width / height axis.
  final List<double> widthConnectorsIn;
  final List<double> heightConnectorsIn;

  /// NON_LIT_BOX connector cut length (null = not resolvable → review).
  final double? connectorCutIn;
  final List<GsbIssue> issues;

  bool get requiresReview => issues.any((i) => i.level == GsbIssueLevel.review);

  bool hasIssue(String code) => issues.any((i) => i.code == code);

  /// Support positions between the stiles (cumulative bay edges).
  List<double> get supportStationsIn {
    final b = bays;
    if (b == null || b.length < 2) return const [];
    final out = <double>[];
    var x = 0.0;
    for (var i = 0; i < b.length - 1; i++) {
      x += b[i];
      out.add(x);
    }
    return out;
  }
}

class NlbRules {
  NlbRules._();

  static bool _whole(double inches) =>
      (inches / 12 - (inches / 12).roundToDouble()).abs() < 1e-6;

  /// NON_LIT vertical bays for a whole-board width.
  ///
  /// * ≤ 30 in: one bay, no internal support;
  /// * even whole feet: n equal bays, n = ceil(W / 30);
  /// * odd whole feet (≥ 5 ft): 24-in first / last bay, the centre region
  ///   split into equal bays ≤ 30 in;
  /// * anything else (fractional width, odd < 5 ft): null → review.
  static List<double>? bays(double widthIn) {
    if (!widthIn.isFinite || widthIn <= 0) return null;
    if (widthIn <= NlbSpec.maxBayIn + 1e-9) return [widthIn];
    if (!_whole(widthIn)) return null;
    final ft = (widthIn / 12).round();
    if (ft.isEven) {
      final n = (widthIn / NlbSpec.maxBayIn - 1e-9).ceil();
      return List.filled(n, widthIn / n);
    }
    if (widthIn < 60) return null;
    final mid = widthIn - 2 * NlbSpec.oddEdgeBayIn;
    final n = (mid / NlbSpec.maxBayIn - 1e-9).ceil();
    return [
      NlbSpec.oddEdgeBayIn,
      ...List.filled(n, mid / n),
      NlbSpec.oddEdgeBayIn,
    ];
  }

  /// NON_LIT_BOX depth-connector stations for a span: 2–8 ft → midpoint;
  /// above 8 ft → thirds; below 2 ft → none.
  static List<double> connectorStations(double spanIn) {
    if (!spanIn.isFinite || spanIn < NlbSpec.connectorMinSpanIn - 1e-9) {
      return const [];
    }
    if (spanIn <= NlbSpec.connectorOneStationMaxIn + 1e-9) {
      return [spanIn / 2];
    }
    return [spanIn / 3, 2 * spanIn / 3];
  }

  /// Connector cut length from real contact geometry: depth minus the front
  /// and rear frame section depth. Null when the section is unknown or
  /// leaves no clear span (never assumed to equal the 4-in depth).
  static double? connectorCutIn(double depthIn, double? profileDepthIn) {
    if (profileDepthIn == null || !profileDepthIn.isFinite) return null;
    final cut = depthIn - 2 * profileDepthIn;
    return cut > 1e-9 ? cut : null;
  }

  static NlbPlan plan({
    required NlbVariant variant,
    required double widthIn,
    required double heightIn,
    double? depthIn,
    double? boxProfileDepthIn,
  }) {
    final issues = <GsbIssue>[];
    void review(String c, String m) =>
        issues.add(GsbIssue(c, GsbIssueLevel.review, m));
    void err(String c, String m) =>
        issues.add(GsbIssue(c, GsbIssueLevel.error, m));
    if (!widthIn.isFinite ||
        widthIn <= 0 ||
        !heightIn.isFinite ||
        heightIn <= 0) {
      err('SIZE_INVALID', 'Width and height must be positive numbers.');
      return NlbPlan(
        variant: variant,
        widthIn: widthIn,
        heightIn: heightIn,
        depthIn: depthIn,
        bays: null,
        widthConnectorsIn: const [],
        heightConnectorsIn: const [],
        connectorCutIn: null,
        issues: issues,
      );
    }
    final tall = heightIn > NlbSpec.heightSplitAboveIn + 1e-9;
    if (tall) {
      review(
        'NL_MODULE_REVIEW',
        'Height above 4 ft activates the Non-Lit height separation, but no '
            'approved module layout exists for ${variant.label}. Modules are '
            'not generated.',
      );
    }
    List<double>? bays;
    var widthStations = const <double>[];
    var heightStations = const <double>[];
    double? cut;
    var depth = depthIn;
    if (variant == NlbVariant.singleFrame) {
      bays = NlbRules.bays(widthIn);
      if (bays == null) {
        review(
          'NL_BAY_REVIEW',
          'No approved vertical-support bay rule for a ${widthIn.toStringAsFixed(2)}'
              ' in width (fractional or odd width under 5 ft).',
        );
      }
      if (heightIn >= NlbSpec.horizontalFromIn - 1e-9) {
        review(
          'NL_HORIZONTAL_REVIEW',
          'Height of 7 ft or more applies the Non-Lit intermediate '
              'horizontal support, but its position is not specified in the '
              'rulebook. Not generated; do not copy the GSB rule.',
        );
      }
    } else {
      depth ??= NlbSpec.boxDepthIn;
      widthStations = connectorStations(widthIn);
      heightStations = connectorStations(heightIn);
      cut = connectorCutIn(depth, boxProfileDepthIn);
      review(
        'BOX_TOP_JOINT_REVIEW',
        'Top-width joint 2 × 1 in SHS (1 in section height): seating and '
            'clearance inside the ${depth.toStringAsFixed(0)}-in box need '
            'engineering confirmation.',
      );
      if (cut == null) {
        review(
          'BOX_CONNECTOR_REVIEW',
          'Depth-connector cut length cannot be resolved: the front / rear '
              'frame section depth is not specified, and it is not assumed '
              'to equal the ${depth.toStringAsFixed(0)}-in outside depth.',
        );
      }
    }
    return NlbPlan(
      variant: variant,
      widthIn: widthIn,
      heightIn: heightIn,
      depthIn: depth,
      bays: bays,
      widthConnectorsIn: widthStations,
      heightConnectorsIn: heightStations,
      connectorCutIn: cut,
      issues: issues,
    );
  }
}
