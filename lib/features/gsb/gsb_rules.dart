/// GSB Single / GSB Double fabrication rules, translated from the
/// "Signage Frame & 3D Fabrication Master Rulebook" (edition 1.0,
/// 21 Nov 2026) into a pure-Dart, renderer-independent engine.
///
/// Scope: GSB_SINGLE and GSB_DOUBLE only (rulebook sections 02, 04, 05,
/// 09–14 and 21). Lit / Non Lit / Non-Lit Box and standees are NOT handled
/// here.
///
/// Conventions (rulebook section 01):
/// * every length is in exact inches (doubles, never rounded decimal feet);
/// * X = width from the left outer steel boundary, Y = height from the
///   bottom, Z = depth with the front outer surface at Z = 0 and the rear
///   in +Z;
/// * one physical member = one stable id;
/// * cases the rulebook marks as unresolved produce a [GsbIssueLevel.review]
///   issue and NO invented geometry.
///
/// This is a software rule reference, not a structural certification.
library;

import 'dart:math' as math;

/// Rulebook edition the engine implements (persisted with overrides).
const kGsbRuleVersion = 'SFR-1.0 (21 Nov 2026)';

const double _eps = 1e-6;

// ---------------------------------------------------------------------------
// Variant
// ---------------------------------------------------------------------------

/// Physical GSB fabrication variant (rulebook section 03 canonical keys).
enum GsbVariant { single, double }

extension GsbVariantX on GsbVariant {
  /// Stable canonical key – never rewrite saved keys.
  String get key => switch (this) {
    GsbVariant.single => 'GSB_SINGLE',
    GsbVariant.double => 'GSB_DOUBLE',
  };

  String get label => switch (this) {
    GsbVariant.single => 'GSB Single Side',
    GsbVariant.double => 'GSB Double Side',
  };

  String get shortLabel => switch (this) {
    GsbVariant.single => 'Single',
    GsbVariant.double => 'Double',
  };

  bool get isDouble => this == GsbVariant.double;

  static GsbVariant? fromKey(String? key) => switch (key) {
    'GSB_SINGLE' => GsbVariant.single,
    'GSB_DOUBLE' => GsbVariant.double,
    _ => null,
  };
}

// ---------------------------------------------------------------------------
// Rule constants (SPECIFIED values only)
// ---------------------------------------------------------------------------

class GsbSpec {
  GsbSpec._();

  /// Overall outside-to-outside box depth (both variants).
  static const double depthIn = 8;

  /// Main MS SHS profile (section size, NOT wall thickness).
  static const double profileWidthIn = 1;
  static const double profileHeightIn = 1;

  /// Pipe wall thickness is not stated in the rulebook.
  static const double? wallThicknessIn = null;

  static const double singleBraceIn = 9;
  static const double doubleBraceIn = 4; // used as a 4 + 4 pair
  static const double seamBraceIn = 4;

  static const double insertSectionIn = 0.75;
  static const double insertLengthIn = 24;
  static const double insertEngagementIn = 12;

  /// Powder-coated perimeter trim.
  static const double trimFoldIn = 0.75;
  static const double trimMaxPieceIn = 99;
  static const double trimOverlapIn = 2;

  /// Rear GI (GSB Single only).
  static const List<double> giStockHeightsIn = [24, 30, 36, 48];
  static const double giOverlapIn = 6;

  /// Module triggers.
  static const double heightSplitFromIn = 60; // >= 5 ft
  static const double widthSplitAboveIn = 180; // > 15 ft
  static const double extraHorizontalAboveIn = 48; // module height > 4 ft

  /// Approved width distributions (inches) for boards above 15 ft
  /// (rulebook section 09 reference table).
  static const Map<int, List<double>> referenceColumnsIn = {
    192: [96, 96], // 16 ft
    204: [102, 102], // 17 ft
    216: [108, 108], // 18 ft
    240: [120, 120], // 20 ft
    384: [128, 128, 128], // 32 ft
    480: [180, 180, 120], // 40 ft
    600: [180, 180, 120, 120], // 50 ft (width only; heights need review)
  };

  /// Approved height partitions (inches) for boards of 5 ft and above.
  static const Map<int, List<double>> referenceRowsIn = {
    84: [42, 42], // 7 ft
    96: [48, 48], // 8 ft (40 x 8 reference: 4 / 4 ft)
    120: [60, 60], // 10 ft
    192: [64, 64, 64], // 16 ft (32 x 16: 5 ft 4 in)
  };

  /// GI tier references (bottom → top) keyed by installed height.
  static const Map<int, List<double>> referenceGiTiersIn = {
    60: [30, 36], // 8 x 5 ft
    84: [30, 30, 36], // 21 x 7 ft
  };
}

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------

/// Board parameters for the engine. Defaults are the approved rulebook
/// values; any other depth / profile is an override that needs review.
class GsbBoardInput {
  const GsbBoardInput({
    required this.variant,
    required this.widthIn,
    required this.heightIn,
    this.depthIn = GsbSpec.depthIn,
    this.profileWidthIn = GsbSpec.profileWidthIn,
    this.profileHeightIn = GsbSpec.profileHeightIn,
    this.wallThicknessIn,
    this.ledSide = GsbLedSide.front,
  });

  final GsbVariant variant;
  final double widthIn;
  final double heightIn;
  final double depthIn;
  final double profileWidthIn;
  final double profileHeightIn;

  /// Null = not specified (requires engineering confirmation).
  final double? wallThicknessIn;

  /// GSB Double: the ONE physical LED set is on the front OR the rear.
  final GsbLedSide ledSide;

  bool get usesDefaultDepth => (depthIn - GsbSpec.depthIn).abs() < _eps;
  bool get usesDefaultProfile =>
      (profileWidthIn - GsbSpec.profileWidthIn).abs() < _eps &&
      (profileHeightIn - GsbSpec.profileHeightIn).abs() < _eps;
}

enum GsbLedSide { front, rear }

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

enum GsbIssueLevel { error, review, info }

/// Rule status legend (rulebook "Rule status legend").
enum GsbRuleStatus { specified, example, derived, review }

class GsbIssue {
  const GsbIssue(this.code, this.level, this.message);

  final String code;
  final GsbIssueLevel level;
  final String message;

  @override
  String toString() => '${level.name.toUpperCase()} $code: $message';
}

/// A point in board coordinates (inches).
class In3 {
  const In3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  double distanceTo(In3 o) {
    final dx = x - o.x, dy = y - o.y, dz = z - o.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  @override
  String toString() =>
      '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}

enum GsbMemberRole {
  frontRail,
  rearRail,
  frontStile,
  rearStile,
  depthConnector,
  internalVertical,
  extraHorizontal,
  brace,
  seamBrace,
}

extension GsbMemberRoleX on GsbMemberRole {
  String get label => switch (this) {
    GsbMemberRole.frontRail => 'Front frame rail',
    GsbMemberRole.rearRail => 'Rear frame rail',
    GsbMemberRole.frontStile => 'Front frame stile',
    GsbMemberRole.rearStile => 'Rear frame stile',
    GsbMemberRole.depthConnector => 'Depth connector',
    GsbMemberRole.internalVertical => 'Internal vertical support',
    GsbMemberRole.extraHorizontal => 'Additional horizontal support',
    GsbMemberRole.brace => 'Triangular brace',
    GsbMemberRole.seamBrace => 'Modular seam brace',
  };

  bool get isBrace =>
      this == GsbMemberRole.brace || this == GsbMemberRole.seamBrace;
}

/// One physical steel member (centre line + section).
class GsbMember {
  const GsbMember({
    required this.id,
    required this.moduleId,
    required this.role,
    required this.start,
    required this.end,
    required this.sectionIn,
    this.nominalIn,
    this.status = GsbRuleStatus.specified,
  });

  final String id;
  final String moduleId;
  final GsbMemberRole role;
  final In3 start;
  final In3 end;

  /// Square / rectangular section size used for rendering (inches).
  final double sectionIn;

  /// Nominal catalogue length (braces: 9 / 4 in) when it differs from the
  /// centre-line length.
  final double? nominalIn;
  final GsbRuleStatus status;

  double get lengthIn => start.distanceTo(end);
}

/// Physical fabrication module (rulebook section 09).
class GsbModule {
  const GsbModule({
    required this.id,
    required this.row,
    required this.column,
    required this.x0In,
    required this.y0In,
    required this.widthIn,
    required this.heightIn,
    required this.supportStationsIn,
    required this.supportStatus,
    required this.depthStationsIn,
    required this.extraHorizontal,
  });

  final String id;
  final int row;
  final int column;
  final double x0In;
  final double y0In;
  final double widthIn;
  final double heightIn;

  /// Internal vertical support stations, module-local X (null = no
  /// approved rule → review, nothing generated).
  final List<double>? supportStationsIn;
  final GsbRuleStatus supportStatus;

  /// Intermediate front-to-rear connector levels, module-local Y.
  final List<double> depthStationsIn;

  /// Additional width-spanning horizontal support (module height > 4 ft).
  final bool extraHorizontal;

  /// Bay widths between left stile, supports and right stile.
  List<double>? get baysIn {
    final s = supportStationsIn;
    if (s == null) return null;
    final edges = [0.0, ...s, widthIn];
    return [for (var i = 1; i < edges.length; i++) edges[i] - edges[i - 1]];
  }
}

/// 0.75 × 0.75-in internal coupling insert at a module seam.
class GsbCouplingInsert {
  const GsbCouplingInsert({
    required this.id,
    required this.ownerModuleId,
    required this.neighbourModuleId,
    required this.axis,
    required this.centre,
  });

  final String id;

  /// Left / lower module owns the insert (moves with it in Separated View).
  final String ownerModuleId;
  final String neighbourModuleId;

  /// 'x' (along a rail across a width seam) or 'y' (along a stile across a
  /// height seam).
  final String axis;
  final In3 centre;
  double get lengthIn => GsbSpec.insertLengthIn;
  double get engagementIn => GsbSpec.insertEngagementIn;
}

/// Complete deterministic fabrication result for one GSB board.
class GsbFabricationPlan {
  GsbFabricationPlan({
    required this.input,
    required this.columnsIn,
    required this.rowsIn,
    required this.modules,
    required this.members,
    required this.inserts,
    required this.trimPiecesIn,
    required this.giTiersIn,
    required this.issues,
  });

  final GsbBoardInput input;

  /// Width distribution (null = unresolved → review).
  final List<double>? columnsIn;

  /// Height distribution (null = unresolved → review).
  final List<double>? rowsIn;
  final List<GsbModule> modules;
  final List<GsbMember> members;
  final List<GsbCouplingInsert> inserts;

  /// Powder-coated trim pieces per side: top, bottom, left, right.
  final Map<String, List<double>> trimPiecesIn;

  /// Rear GI tiers bottom → top (GSB Single; null = not applicable or
  /// needs review).
  final List<double>? giTiersIn;
  final List<GsbIssue> issues;

  GsbVariant get variant => input.variant;
  bool get isModular => modules.length > 1;
  bool get widthSplit => (columnsIn?.length ?? 1) > 1;
  bool get heightSplit =>
      (rowsIn?.length ?? 1) > 1 ||
      input.heightIn >= GsbSpec.heightSplitFromIn - _eps;

  bool get hasErrors => issues.any((i) => i.level == GsbIssueLevel.error);
  bool get requiresReview => issues.any((i) => i.level == GsbIssueLevel.review);

  int count(GsbMemberRole role) => members.where((m) => m.role == role).length;

  int get trimPieceCount => trimPiecesIn.values.fold(0, (s, l) => s + l.length);

  /// Rear GI applies to GSB Single only.
  bool get hasRearGi => variant == GsbVariant.single;

  /// Front print flex always; rear print flex only for GSB Double.
  int get printFlexFaces => variant == GsbVariant.double ? 2 : 1;

  /// One physical LED installation set for both variants (never doubled).
  int get physicalLedSets => 1;

  /// Installed GI height (sum of tiers minus 6-in laps).
  double? get giInstalledHeightIn {
    final t = giTiersIn;
    if (t == null || t.isEmpty) return null;
    return t.fold<double>(0, (s, v) => s + v) -
        GsbSpec.giOverlapIn * (t.length - 1);
  }

  Iterable<GsbIssue> get reviewItems =>
      issues.where((i) => i.level == GsbIssueLevel.review);
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

class GsbRules {
  GsbRules._();

  static bool _whole(double inches) =>
      (inches / 12 - (inches / 12).roundToDouble()).abs() < _eps;

  static int? _intKey(double v) {
    final r = v.roundToDouble();
    return (v - r).abs() < _eps ? r.toInt() : null;
  }

  /// Width columns (left → right). Null = above 15 ft without an approved
  /// reference layout (never a naive ceil(width / 15) split).
  static List<double>? widthColumns(double widthIn) {
    if (widthIn <= GsbSpec.widthSplitAboveIn + _eps) return [widthIn];
    final k = _intKey(widthIn);
    final ref = k == null ? null : GsbSpec.referenceColumnsIn[k];
    return ref == null ? null : List.of(ref);
  }

  /// Height rows (bottom → top). Null = 5 ft or more without an approved
  /// partition (rulebook section 21: "Exact height partition for arbitrary
  /// height").
  static List<double>? heightRows(double heightIn) {
    if (heightIn < GsbSpec.heightSplitFromIn - _eps) return [heightIn];
    final k = _intKey(heightIn);
    final ref = k == null ? null : GsbSpec.referenceRowsIn[k];
    return ref == null ? null : List.of(ref);
  }

  /// Internal vertical support stations (local X) of a module.
  ///
  /// * whole-foot even width → 24-in bays;
  /// * whole-foot odd width → 18-in first / last bays, 24-in interior;
  /// * 8.5-ft modules of a 2-column board → the approved mirrored 17 × 7
  ///   pattern (left 1.5+2+2+2+1, right 1+2+2+2+1.5);
  /// * anything else (e.g. 10 ft 8 in) → null (review).
  static (List<double>?, GsbRuleStatus) supportStations(
    double moduleWidthIn, {
    int column = 0,
    int columns = 1,
  }) {
    if (columns == 2 && (moduleWidthIn - 102).abs() < _eps) {
      final left = column == 0;
      return (
        left ? [18.0, 42.0, 66.0, 90.0] : [12.0, 36.0, 60.0, 84.0],
        GsbRuleStatus.example,
      );
    }
    if (!_whole(moduleWidthIn)) return (null, GsbRuleStatus.review);
    final ft = (moduleWidthIn / 12).round();
    final status = columns == 1
        ? GsbRuleStatus.specified
        : (ft == 10 || ft == 9 ? GsbRuleStatus.example : GsbRuleStatus.derived);
    if (ft <= 2) return (<double>[], status);
    final out = <double>[];
    if (ft.isEven) {
      for (var x = 24.0; x < moduleWidthIn - _eps; x += 24) {
        out.add(x);
      }
    } else {
      for (var x = 18.0; x < moduleWidthIn - 18 + _eps; x += 24) {
        out.add(x);
      }
    }
    return (out, status);
  }

  /// Intermediate front-to-rear connector levels for a height H (local Y):
  /// H < 3 ft → none; 3 ft ≤ H < 8 ft → H/2; H ≥ 8 ft → H/3 and 2H/3.
  static List<double> depthStations(double heightIn) {
    if (heightIn < 36 - _eps) return const [];
    if (heightIn < 96 - _eps) return [heightIn / 2];
    return [heightIn / 3, 2 * heightIn / 3];
  }

  /// Powder-coated trim pieces for one perimeter side: 99-in maximum
  /// pieces joined with 2-in overlaps (installed = sum − 2 × joints).
  static List<double> trimPieces(double sideIn) {
    if (sideIn <= 0 || !sideIn.isFinite) return const [];
    if (sideIn <= GsbSpec.trimMaxPieceIn + _eps) return [sideIn];
    const step = GsbSpec.trimMaxPieceIn - GsbSpec.trimOverlapIn;
    final out = <double>[];
    var remaining = sideIn;
    while (remaining > GsbSpec.trimMaxPieceIn + _eps) {
      out.add(GsbSpec.trimMaxPieceIn);
      remaining -= step;
    }
    out.add(remaining);
    return out;
  }

  /// Validation of the raw input (errors stop geometry generation).
  static List<GsbIssue> validate(GsbBoardInput i) {
    final out = <GsbIssue>[];
    void err(String code, String msg) =>
        out.add(GsbIssue(code, GsbIssueLevel.error, msg));
    if (!i.widthIn.isFinite || i.widthIn <= 0) {
      err('WIDTH_INVALID', 'Width must be a positive number.');
    }
    if (!i.heightIn.isFinite || i.heightIn <= 0) {
      err('HEIGHT_INVALID', 'Height must be a positive number.');
    }
    if (!i.profileWidthIn.isFinite ||
        i.profileWidthIn <= 0 ||
        !i.profileHeightIn.isFinite ||
        i.profileHeightIn <= 0) {
      err('PROFILE_INVALID', 'Frame profile must be a positive size.');
    }
    if (!i.depthIn.isFinite || i.depthIn <= 0) {
      err('DEPTH_INVALID', 'Board depth must be a positive number.');
    } else if (i.depthIn <= 2 * i.profileWidthIn + _eps) {
      err(
        'DEPTH_TOO_SMALL',
        'Board depth must exceed the front + rear frame profile '
            '(${_n(2 * i.profileWidthIn)} in).',
      );
    }
    final wall = i.wallThicknessIn;
    if (wall != null &&
        (!wall.isFinite ||
            wall <= 0 ||
            wall * 2 >= math.min(i.profileWidthIn, i.profileHeightIn))) {
      err(
        'WALL_INVALID',
        'Wall thickness must be positive and less than half the profile.',
      );
    }
    final minSide = 2 * math.max(i.profileWidthIn, i.profileHeightIn);
    if (i.widthIn.isFinite && i.widthIn > 0 && i.widthIn <= minSide) {
      err('WIDTH_TOO_SMALL', 'Width is smaller than two frame profiles.');
    }
    if (i.heightIn.isFinite && i.heightIn > 0 && i.heightIn <= minSide) {
      err('HEIGHT_TOO_SMALL', 'Height is smaller than two frame profiles.');
    }
    return out;
  }

  static String _n(double v) {
    var s = v.toStringAsFixed(2);
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  /// Builds the deterministic fabrication plan.
  static GsbFabricationPlan plan(GsbBoardInput input) {
    final issues = validate(input);
    if (issues.isNotEmpty) {
      return GsbFabricationPlan(
        input: input,
        columnsIn: null,
        rowsIn: null,
        modules: const [],
        members: const [],
        inserts: const [],
        trimPiecesIn: const {},
        giTiersIn: null,
        issues: issues,
      );
    }
    final w = input.widthIn, h = input.heightIn;
    final isDouble = input.variant == GsbVariant.double;
    void review(String code, String msg) =>
        issues.add(GsbIssue(code, GsbIssueLevel.review, msg));
    void info(String code, String msg) =>
        issues.add(GsbIssue(code, GsbIssueLevel.info, msg));

    // --- Module division (section 09) -------------------------------------
    final cols = widthColumns(w);
    final rows = heightRows(h);
    if (cols == null) {
      review(
        'WIDTH_SPLIT_REVIEW',
        'Width ${_n(w)} in is above 15 ft and has no approved reference '
            'module layout. Module columns are not generated.',
      );
    }
    if (rows == null) {
      review(
        'HEIGHT_SPLIT_REVIEW',
        'Height ${_n(h)} in triggers the GSB height split (>= 5 ft) but has '
            'no approved height partition. Module rows are not generated.',
      );
    }
    final resolved = cols != null && rows != null;
    final colList = resolved ? cols : [w];
    final rowList = resolved ? rows : [h];

    final modules = <GsbModule>[];
    var x0 = 0.0;
    for (var c = 0; c < colList.length; c++) {
      var y0 = 0.0;
      for (var r = 0; r < rowList.length; r++) {
        final mw = colList[c], mh = rowList[r];
        final (stations, status) = resolved
            ? supportStations(mw, column: c, columns: colList.length)
            : (null, GsbRuleStatus.review);
        modules.add(
          GsbModule(
            id: 'M${c * rowList.length + r + 1}',
            row: r,
            column: c,
            x0In: x0,
            y0In: y0,
            widthIn: mw,
            heightIn: mh,
            supportStationsIn: stations,
            supportStatus: status,
            depthStationsIn: depthStations(mh),
            extraHorizontal:
                resolved && mh > GsbSpec.extraHorizontalAboveIn + _eps,
          ),
        );
        y0 += mh;
      }
      x0 += colList[c];
    }
    if (resolved) {
      for (final m in modules) {
        if (m.supportStationsIn == null) {
          review(
            'SUPPORT_SPACING_REVIEW',
            '${m.id}: module width ${_n(m.widthIn)} in has no approved '
                'support bay rule (fractional width). Internal verticals are '
                'not generated.',
          );
        }
      }
    } else {
      info(
        'OUTER_FRAME_ONLY',
        'Only the outer front / rear frame and depth connectors are shown '
            'until the module layout is approved.',
      );
    }

    // --- Members -----------------------------------------------------------
    final members = <GsbMember>[];
    final p = input.profileWidthIn; // in-plane section
    final ph = input.profileHeightIn;
    final d = input.depthIn;
    final zF = p / 2, zR = d - p / 2, zMid = d / 2;
    final section = math.max(p, ph);

    void add(
      String id,
      String mod,
      GsbMemberRole role,
      In3 a,
      In3 b, {
      double? sectionIn,
      double? nominal,
      GsbRuleStatus status = GsbRuleStatus.specified,
    }) {
      if (a.distanceTo(b) < _eps) return;
      members.add(
        GsbMember(
          id: id,
          moduleId: mod,
          role: role,
          start: a,
          end: b,
          sectionIn: sectionIn ?? section,
          nominalIn: nominal,
          status: status,
        ),
      );
    }

    final topY = h, bottomY = 0.0;
    var hasExtra = false;
    for (final m in modules) {
      final id = m.id;
      final mx0 = m.x0In, mx1 = m.x0In + m.widthIn;
      final my0 = m.y0In, my1 = m.y0In + m.heightIn;
      final yT = my1 - ph / 2, yB = my0 + ph / 2;
      final xL = mx0 + p / 2, xR = mx1 - p / 2;

      // Front + rear rectangular frames (each module keeps its own stiles).
      for (final (plane, z, rail, stile) in [
        ('F', zF, GsbMemberRole.frontRail, GsbMemberRole.frontStile),
        ('R', zR, GsbMemberRole.rearRail, GsbMemberRole.rearStile),
      ]) {
        add('$id.$plane.top', id, rail, In3(mx0, yT, z), In3(mx1, yT, z));
        add('$id.$plane.bottom', id, rail, In3(mx0, yB, z), In3(mx1, yB, z));
        add(
          '$id.$plane.left',
          id,
          stile,
          In3(xL, my0 + ph, z),
          In3(xL, my1 - ph, z),
        );
        add(
          '$id.$plane.right',
          id,
          stile,
          In3(xR, my0 + ph, z),
          In3(xR, my1 - ph, z),
        );
      }

      // Corner depth connectors (cut length = depth − 2 profiles).
      for (final (tag, x, y) in [
        ('TL', xL, yT),
        ('TR', xR, yT),
        ('BL', xL, yB),
        ('BR', xR, yB),
      ]) {
        add(
          '$id.D.$tag',
          id,
          GsbMemberRole.depthConnector,
          In3(x, y, p),
          In3(x, y, d - p),
        );
      }

      // Height-dependent intermediate depth stations on both stiles.
      for (var k = 0; k < m.depthStationsIn.length; k++) {
        final y = my0 + m.depthStationsIn[k];
        for (final (tag, x) in [('L', xL), ('R', xR)]) {
          add(
            '$id.D.$tag${k + 1}',
            id,
            GsbMemberRole.depthConnector,
            In3(x, y, p),
            In3(x, y, d - p),
          );
        }
      }

      // Internal verticals: rear plane (Single) / centre depth (Double).
      final stations = m.supportStationsIn ?? const <double>[];
      final zS = isDouble ? zMid : zR;
      final atBoardTop = (my1 - topY).abs() < _eps;
      final atBoardBottom = (my0 - bottomY).abs() < _eps;
      for (var k = 0; k < stations.length; k++) {
        final x = mx0 + stations[k];
        final vId = '$id.V${k + 1}';
        add(
          vId,
          id,
          GsbMemberRole.internalVertical,
          In3(x, my0 + ph, zS),
          In3(x, my1 - ph, zS),
          status: m.supportStatus,
        );
        if (isDouble) {
          // Centre posts connect to the front / rear rails through real
          // depth connectors at top and bottom (no floating posts).
          add(
            '$vId.DT',
            id,
            GsbMemberRole.depthConnector,
            In3(x, yT, p),
            In3(x, yT, d - p),
          );
          add(
            '$vId.DB',
            id,
            GsbMemberRole.depthConnector,
            In3(x, yB, p),
            In3(x, yB, d - p),
          );
        }

        // Junction braces: board-outer rails get the standard brace,
        // module seam rails get the 4-in seam brace.
        for (final top in [true, false]) {
          final outer = top ? atBoardTop : atBoardBottom;
          final railY = top ? yT : yB;
          final dir = top ? -1.0 : 1.0; // from the rail into the module
          final yRailFace = railY + dir * ph / 2;
          final tag = top ? 'T' : 'B';
          if (outer && isDouble) {
            // Paired 4 + 4 in braces in the depth plane (towards front and
            // rear), anchored on the centre post and the depth connector.
            final a = GsbSpec.doubleBraceIn / math.sqrt2;
            for (final (side, sz) in [('f', -1.0), ('r', 1.0)]) {
              add(
                '$vId.BR$tag$side',
                id,
                GsbMemberRole.brace,
                In3(x, yRailFace + dir * a, zS),
                In3(x, yRailFace, zS + sz * a),
                sectionIn: section * 0.75,
                nominal: GsbSpec.doubleBraceIn,
                status: GsbRuleStatus.review,
              );
            }
          } else if (outer) {
            final a = GsbSpec.singleBraceIn / math.sqrt2;
            add(
              '$vId.BR$tag',
              id,
              GsbMemberRole.brace,
              In3(x, yRailFace + dir * a, zS),
              In3(x + a, yRailFace, zS),
              sectionIn: section * 0.75,
              nominal: GsbSpec.singleBraceIn,
              status: GsbRuleStatus.review,
            );
          } else {
            final a = GsbSpec.seamBraceIn / math.sqrt2;
            add(
              '$vId.SB$tag',
              id,
              GsbMemberRole.seamBrace,
              In3(x, yRailFace + dir * a, zS),
              isDouble ? In3(x, yRailFace, zS - a) : In3(x + a, yRailFace, zS),
              sectionIn: section * 0.75,
              nominal: GsbSpec.seamBraceIn,
              status: GsbRuleStatus.review,
            );
          }
        }
      }

      // Additional width-spanning horizontal support (module H > 4 ft), on
      // the support plane at the module depth-station level so both ends
      // meet a real host (stile / depth connector).
      if (m.extraHorizontal) {
        hasExtra = true;
        final local = m.depthStationsIn.length == 1
            ? m.depthStationsIn.first
            : m.heightIn / 2;
        final y = my0 + local;
        add(
          '$id.H1',
          id,
          GsbMemberRole.extraHorizontal,
          In3(mx0 + p, y, zS),
          In3(mx1 - p, y, zS),
          status: GsbRuleStatus.review,
        );
      }
    }

    // --- Coupling inserts at module seams (section 12) ---------------------
    final inserts = <GsbCouplingInsert>[];
    if (resolved && modules.length > 1) {
      GsbModule at(int c, int r) =>
          modules.firstWhere((m) => m.column == c && m.row == r);
      for (var c = 0; c + 1 < colList.length; c++) {
        for (var r = 0; r < rowList.length; r++) {
          final a = at(c, r), b = at(c + 1, r);
          final xs = b.x0In;
          for (final (tag, y) in [
            ('T', a.y0In + a.heightIn - ph / 2),
            ('B', a.y0In + ph / 2),
          ]) {
            for (final (plane, z) in [('F', zF), ('R', zR)]) {
              inserts.add(
                GsbCouplingInsert(
                  id: '${a.id}-${b.id}.$plane$tag',
                  ownerModuleId: a.id,
                  neighbourModuleId: b.id,
                  axis: 'x',
                  centre: In3(xs, y, z),
                ),
              );
            }
          }
        }
      }
      for (var c = 0; c < colList.length; c++) {
        for (var r = 0; r + 1 < rowList.length; r++) {
          final a = at(c, r), b = at(c, r + 1);
          final ys = b.y0In;
          for (final (tag, x) in [
            ('L', a.x0In + p / 2),
            ('R', a.x0In + a.widthIn - p / 2),
          ]) {
            for (final (plane, z) in [('F', zF), ('R', zR)]) {
              inserts.add(
                GsbCouplingInsert(
                  id: '${a.id}-${b.id}.$plane$tag',
                  ownerModuleId: a.id,
                  neighbourModuleId: b.id,
                  axis: 'y',
                  centre: In3(x, ys, z),
                ),
              );
            }
          }
        }
      }
      final wall = input.wallThicknessIn;
      final clear = wall == null
          ? null
          : math.min(p, ph) - 2 * wall; // internal clear opening
      if (clear == null) {
        review(
          'INSERT_FIT_REVIEW',
          'Coupling insert 0.75 × 0.75 in × 24 in (12 in each side): host '
              'pipe wall thickness is not specified, so the physical fit '
              'inside the ${_n(p)} × ${_n(ph)} in SHS cannot be confirmed.',
        );
      } else if (clear < GsbSpec.insertSectionIn - _eps) {
        issues.add(
          GsbIssue(
            'INSERT_CLASH',
            GsbIssueLevel.error,
            'Internal clear opening ${_n(clear)} in is smaller than the '
                '0.75 in coupling insert.',
          ),
        );
      }
    }

    // --- Braces / horizontals / optics review items ------------------------
    if (members.any((m) => m.role.isBrace)) {
      review(
        'BRACE_BASIS_REVIEW',
        'Brace size basis (diagonal cut length vs leg) is not defined in the '
            'rulebook; braces are drawn with the nominal size as diagonal. '
            'Orientation is illustrative.',
      );
    }
    if (input.variant == GsbVariant.single) {
      info(
        'SINGLE_SIDE_DEPTH_BRACES',
        'Additional 9-in braces at separately specified side-depth and '
            'width-support joints are not generated (locations not '
            'specified).',
      );
    }
    if (hasExtra) {
      review(
        'EDGE_BAY_HORIZONTAL_REVIEW',
        'Module height above 4 ft: edge-bay horizontal bracing station '
            'elevation is not approved. Additional horizontal support is '
            'drawn at the module depth-station level (provisional).',
      );
    }
    if (isDouble) {
      info(
        'DOUBLE_SINGLE_LED_SET',
        'One physical LED installation set on the '
            '${input.ledSide.name} side; LED material is not doubled.',
      );
      review(
        'DOUBLE_OPTICS_REVIEW',
        'Night render glow on both faces from one LED set is illustrative; '
            'optical performance requires fixture / flex confirmation.',
      );
    }

    // --- Overrides ---------------------------------------------------------
    if (!input.usesDefaultDepth) {
      review(
        'DEPTH_OVERRIDE_REVIEW',
        'Board depth ${_n(d)} in differs from the approved 8 in default – '
            'Requires Engineering Review (connectors, braces, trim and '
            'hardware fit re-check).',
      );
    }
    if (!input.usesDefaultProfile) {
      review(
        'PROFILE_OVERRIDE_REVIEW',
        'Frame profile ${_n(p)} × ${_n(ph)} in differs from the approved '
            '1 × 1 in SHS – Requires Engineering Review.',
      );
    }
    if (input.wallThicknessIn == null) {
      info(
        'WALL_UNSPECIFIED',
        'Pipe wall thickness: not specified – requires engineering '
            'confirmation.',
      );
    }

    // --- Finishing: powder-coated trim + rear GI ---------------------------
    final trim = {
      'top': trimPieces(w),
      'bottom': trimPieces(w),
      'left': trimPieces(h),
      'right': trimPieces(h),
    };
    List<double>? gi;
    if (input.variant == GsbVariant.single) {
      final k = _intKey(h);
      final ref = k == null ? null : GsbSpec.referenceGiTiersIn[k];
      if (ref != null) {
        gi = List.of(ref);
      } else if (h <= 48 + _eps &&
          GsbSpec.giStockHeightsIn.any((s) => (s - h).abs() < _eps)) {
        gi = [h]; // one stock sheet of exactly the board height, no lap
      } else {
        review(
          'GI_PLAN_REVIEW',
          'Rear GI tier plan for ${_n(h)} in height is not in the approved '
              'references (stock 24/30/36/48 in, 6-in laps).',
        );
      }
    }

    return GsbFabricationPlan(
      input: input,
      columnsIn: cols,
      rowsIn: rows,
      modules: modules,
      members: members,
      inserts: inserts,
      trimPiecesIn: trim,
      giTiersIn: gi,
      issues: issues,
    );
  }
}
