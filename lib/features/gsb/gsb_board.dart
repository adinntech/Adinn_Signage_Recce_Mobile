import '../../data/catalog/measurement_fields.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import 'gsb_rules.dart';

/// Bridges the recce data model ([Board] / [SignageUnit]) and the GSB
/// fabrication engine. The canonical stored field stays [Board.doubleSided]
/// (existing schema); the GSB_SINGLE / GSB_DOUBLE variant is derived from it
/// so the two can never contradict each other.
class GsbBoard {
  GsbBoard._();

  /// True only for the GSB catalog media (never MDF+GSB or others).
  static bool isGsb(Board? b) => b?.mediaCode == SignageCatalog.gsb;

  /// Variant of a GSB group. Historical groups without an explicit choice
  /// (doubleSided == null) were always treated as single-sided by the app,
  /// so they map unambiguously to GSB_SINGLE; [isExplicit] tells them apart.
  static GsbVariant? variantOf(Board? b) {
    if (!isGsb(b)) return null;
    return b!.doubleSided == true ? GsbVariant.double : GsbVariant.single;
  }

  /// The vendor chose single / double explicitly.
  static bool isExplicit(Board b) => isGsb(b) && b.doubleSided != null;

  /// Active (not reverted) override of [field] for [unitId], newest wins.
  static GsbSpecOverride? activeOverride(
    Board b,
    String unitId,
    GsbOverrideField field,
  ) {
    for (final o in b.gsbOverrides.reversed) {
      if (o.unitId == unitId && o.field == field && o.isActive) return o;
    }
    return null;
  }

  static List<GsbSpecOverride> overridesOf(Board b, String unitId) => [
    for (final o in b.gsbOverrides)
      if (o.unitId == unitId) o,
  ];

  /// Recorded site measurement of the board depth (inches), if any.
  static double? recordedDepthIn(SignageUnit u) {
    final mm = u.measurements.valuesMm['board_depth'];
    return mm == null || !mm.isFinite || mm <= 0 ? null : mm / 25.4;
  }

  /// Effective board depth: active override → recorded measurement →
  /// approved 8-in default.
  static double depthIn(Board b, SignageUnit u) =>
      activeOverride(b, u.id, GsbOverrideField.depth)?.proposedIn ??
      recordedDepthIn(u) ??
      GsbSpec.depthIn;

  /// Engine input for unit [u]. Width / height may be previewed with
  /// [widthIn] / [heightIn] (uncommitted edits). Null when not GSB or the
  /// size is not entered yet.
  static GsbBoardInput? inputFor(
    Board b,
    SignageUnit u, {
    double? widthIn,
    double? heightIn,
  }) {
    final variant = variantOf(b);
    if (variant == null) return null;
    final w = widthIn ?? _toIn(b.widthOf(u), b.unit);
    final h = heightIn ?? _toIn(b.heightOf(u), b.unit);
    if (w == null || h == null) return null;
    double? ov(GsbOverrideField f) => activeOverride(b, u.id, f)?.proposedIn;
    return GsbBoardInput(
      variant: variant,
      widthIn: w,
      heightIn: h,
      depthIn: depthIn(b, u),
      profileWidthIn:
          ov(GsbOverrideField.profileWidth) ?? GsbSpec.profileWidthIn,
      profileHeightIn:
          ov(GsbOverrideField.profileHeight) ?? GsbSpec.profileHeightIn,
      wallThicknessIn:
          ov(GsbOverrideField.wallThickness) ?? GsbSpec.wallThicknessIn,
    );
  }

  /// Fabrication plan for unit [u] (null when not GSB / no size).
  static GsbFabricationPlan? planFor(
    Board b,
    SignageUnit u, {
    double? widthIn,
    double? heightIn,
  }) {
    final input = inputFor(b, u, widthIn: widthIn, heightIn: heightIn);
    if (input == null) return null;
    final plan = GsbRules.plan(input);
    final rec = recordedDepthIn(u);
    final hasDepthOverride =
        activeOverride(b, u.id, GsbOverrideField.depth) != null;
    if (!hasDepthOverride &&
        rec != null &&
        (rec - GsbSpec.depthIn).abs() > 1e-6) {
      plan.issues.add(
        GsbIssue(
          'RECORDED_DEPTH_DIFFERS',
          GsbIssueLevel.review,
          'A board depth of ${rec.toStringAsFixed(2)} in is recorded in the '
              'measurements (approved GSB default 8 in). Kept as recorded – '
              'Requires Engineering Review.',
        ),
      );
    }
    if (!isExplicit(b)) {
      plan.issues.add(
        const GsbIssue(
          'VARIANT_NOT_CONFIRMED',
          GsbIssueLevel.review,
          'Single / double side was never chosen explicitly for this older '
              'GSB record – shown as GSB Single (the previous app default). '
              'Confirm the board type.',
        ),
      );
    }
    return plan;
  }

  static double? _toIn(double? v, MeasureUnit unit) {
    if (v == null || !v.isFinite || v <= 0) return null;
    return unit.toMm(v) / 25.4;
  }
}
