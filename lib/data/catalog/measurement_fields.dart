import 'dart:math' as math;

import '../models/models.dart';
import 'signage_catalog.dart';

/// Canonical length unit for advanced measurements: millimetres.
extension MeasureUnitMm on MeasureUnit {
  /// Millimetres in one of this unit (exact by definition).
  double get mmFactor => switch (this) {
    MeasureUnit.ft => 304.8,
    MeasureUnit.inch => 25.4,
    MeasureUnit.m => 1000,
    MeasureUnit.mm => 1,
  };

  double toMm(double value) => value * mmFactor;
  double fromMm(double mm) => mm / mmFactor;

  /// Display precision used for this unit.
  int get decimals => switch (this) {
    MeasureUnit.ft => 2,
    MeasureUnit.inch => 1,
    MeasureUnit.m => 3,
    MeasureUnit.mm => 0,
  };
}

/// Rounds [mm] into [unit] at the unit's display precision (rounded once,
/// from full precision, so repeated conversions never drift).
String fmtMmValue(double mm, MeasureUnit unit) {
  final v = unit.fromMm(mm);
  final s = v.toStringAsFixed(unit.decimals);
  if (!s.contains('.')) return s == '-0' ? '0' : s;
  final trimmed = s
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return trimmed == '-0' ? '0' : trimmed;
}

/// "8.5 ft".
String fmtMm(double? mm, MeasureUnit unit) =>
    mm == null ? '—' : '${fmtMmValue(mm, unit)} ${unit.label}';

/// Parses user input in [unit] to millimetres (null when empty/invalid).
double? parseLengthMm(String text, MeasureUnit unit) {
  final v = double.tryParse(text.trim());
  if (v == null || !v.isFinite) return null;
  return unit.toMm(v);
}

enum MeasureFieldKind { length, count, text, flag }

/// Field groups shown as sections of the measurement form.
enum MeasureGroup { general, pole, pipe, standee, glass, model }

extension MeasureGroupX on MeasureGroup {
  String get label => switch (this) {
    MeasureGroup.general => 'General board measurements',
    MeasureGroup.pole => 'Pole-mounted signage',
    MeasureGroup.pipe => 'Support pipe installation',
    MeasureGroup.standee => 'Standee',
    MeasureGroup.glass => 'Glass / wall branding',
    MeasureGroup.model => 'Board construction (3D model)',
  };
}

/// One advanced measurement field. [appliesTo] decides visibility from the
/// media / installation configuration so forms only show relevant fields.
class MeasurementField {
  const MeasurementField({
    required this.id,
    required this.label,
    required this.kind,
    required this.group,
    this.hint,
    this.mustBePositive = false,
    this.installations,
    this.needsFlag,
    this.mediaCodes,
    this.unitLabel,
  });

  /// Media codes this field applies to (null = all).
  final Set<String>? mediaCodes;

  /// Non-length unit shown for count fields (e.g. "deg").
  final String? unitLabel;

  final String id;
  final String label;
  final MeasureFieldKind kind;
  final MeasureGroup group;
  final String? hint;

  /// Zero is invalid (dimensions); otherwise only negatives are invalid.
  final bool mustBePositive;

  /// Installation codes this field applies to (null = all).
  final Set<String>? installations;

  /// Shown only when this flag is switched on (or the installation always
  /// needs the group, see [MeasurementCatalog.pipeInstallations]).
  final String? needsFlag;
}

/// Configuration the measurement form is built from.
class MeasurementContext {
  const MeasurementContext({
    required this.mediaCode,
    required this.installationCode,
    this.flags = const {},
  });

  final String? mediaCode;
  final String? installationCode;
  final Map<String, bool> flags;
}

enum MeasureIssueLevel { error, warning, review }

/// A validation finding. Errors block saving / submission; warnings and
/// review flags are shown but never invent construction limits.
class MeasurementIssue {
  const MeasurementIssue(this.level, this.message, {this.fieldId});

  final MeasureIssueLevel level;
  final String message;
  final String? fieldId;

  bool get isError => level == MeasureIssueLevel.error;

  @override
  String toString() => '${level.name}: $message';
}

class MeasurementCatalog {
  MeasurementCatalog._();

  static const _wallLike = {
    SignageCatalog.shopFascia,
    SignageCatalog.wallMount,
    SignageCatalog.directWall,
  };
  static const _poles = {SignageCatalog.singlePole, SignageCatalog.doublePole};

  /// Installations that always use support pipes.
  static const pipeInstallations = {
    SignageCatalog.rooftop,
    SignageCatalog.flangeBracket,
    SignageCatalog.supportPipe,
  };

  /// Installations where support pipes are optional (switch shown).
  static const optionalPipeInstallations = {
    SignageCatalog.shopFascia,
    SignageCatalog.wallMount,
  };

  static const pipesUsedFlag = 'pipes_used';

  static const fields = <MeasurementField>[
    // General
    MeasurementField(
      id: 'bottom_height',
      label: 'Installation bottom height from ground',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.general,
      hint: 'Ground clearance below the board',
    ),
    MeasurementField(
      id: 'top_height',
      label: 'Installation top height from ground',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.general,
      hint: 'Normally bottom height + board height',
    ),
    MeasurementField(
      id: 'wall_width',
      label: 'Available wall width',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.general,
      mustBePositive: true,
      installations: _wallLike,
    ),
    MeasurementField(
      id: 'wall_height',
      label: 'Available wall height',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.general,
      mustBePositive: true,
      installations: _wallLike,
    ),
    MeasurementField(
      id: 'clear_left',
      label: 'Left clearance',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.general,
      installations: _wallLike,
    ),
    MeasurementField(
      id: 'clear_right',
      label: 'Right clearance',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.general,
      installations: _wallLike,
    ),
    MeasurementField(
      id: 'clear_top',
      label: 'Top clearance',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.general,
      installations: _wallLike,
    ),
    MeasurementField(
      id: 'clear_bottom',
      label: 'Bottom clearance',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.general,
      installations: _wallLike,
    ),
    // Poles
    MeasurementField(
      id: 'pole_count',
      label: 'Pole count',
      kind: MeasureFieldKind.count,
      group: MeasureGroup.pole,
      installations: _poles,
    ),
    MeasurementField(
      id: 'pole_length_total',
      label: 'Total pole length',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.pole,
      mustBePositive: true,
      installations: _poles,
    ),
    MeasurementField(
      id: 'pole_above_ground',
      label: 'Above-ground pole height',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.pole,
      mustBePositive: true,
      installations: _poles,
    ),
    MeasurementField(
      id: 'pole_embedment',
      label: 'Ground embedment depth',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.pole,
      installations: _poles,
    ),
    MeasurementField(
      id: 'pole_spacing',
      label: 'Pole spacing (centre to centre)',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.pole,
      mustBePositive: true,
      installations: {SignageCatalog.doublePole},
    ),
    MeasurementField(
      id: 'pole_position',
      label: 'Pole position',
      kind: MeasureFieldKind.text,
      group: MeasureGroup.pole,
      hint: 'e.g. Footpath edge, 2 ft left of gate',
      installations: _poles,
    ),
    // Support pipes
    MeasurementField(
      id: pipesUsedFlag,
      label: 'Support pipes used',
      kind: MeasureFieldKind.flag,
      group: MeasureGroup.pipe,
      installations: optionalPipeInstallations,
    ),
    MeasurementField(
      id: 'pipe_count',
      label: 'Pipe count',
      kind: MeasureFieldKind.count,
      group: MeasureGroup.pipe,
      needsFlag: pipesUsedFlag,
    ),
    MeasurementField(
      id: 'pipe_length',
      label: 'Pipe length',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.pipe,
      mustBePositive: true,
      needsFlag: pipesUsedFlag,
    ),
    MeasurementField(
      id: 'pipe_spacing',
      label: 'Distance between pipes',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.pipe,
      mustBePositive: true,
      needsFlag: pipesUsedFlag,
    ),
    MeasurementField(
      id: 'pipe_fixing_position',
      label: 'Fixing position',
      kind: MeasureFieldKind.text,
      group: MeasureGroup.pipe,
      needsFlag: pipesUsedFlag,
    ),
    MeasurementField(
      id: 'pipe_mount_height',
      label: 'Mounting height',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.pipe,
      needsFlag: pipesUsedFlag,
    ),
    // Standee
    MeasurementField(
      id: 'standee_overall_height',
      label: 'Overall standee height',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.standee,
      mustBePositive: true,
      installations: {SignageCatalog.freeStanding},
    ),
    MeasurementField(
      id: 'panel_width',
      label: 'Display panel width',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.standee,
      mustBePositive: true,
      installations: {SignageCatalog.freeStanding},
    ),
    MeasurementField(
      id: 'panel_height',
      label: 'Display panel height',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.standee,
      mustBePositive: true,
      installations: {SignageCatalog.freeStanding},
    ),
    MeasurementField(
      id: 'base_width',
      label: 'Base width',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.standee,
      mustBePositive: true,
      installations: {SignageCatalog.freeStanding},
    ),
    MeasurementField(
      id: 'base_depth',
      label: 'Base depth',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.standee,
      mustBePositive: true,
      installations: {SignageCatalog.freeStanding},
    ),
    MeasurementField(
      id: 'ground_surface',
      label: 'Ground placement surface',
      kind: MeasureFieldKind.text,
      group: MeasureGroup.standee,
      hint: 'e.g. Footpath tiles, concrete',
      installations: {SignageCatalog.freeStanding},
    ),
    // Glass / wall branding
    MeasurementField(
      id: 'glass_width',
      label: 'Available glass width',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.glass,
      mustBePositive: true,
      installations: {SignageCatalog.glassPasting},
    ),
    MeasurementField(
      id: 'glass_height',
      label: 'Available glass height',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.glass,
      mustBePositive: true,
      installations: {SignageCatalog.glassPasting},
    ),
    MeasurementField(
      id: 'glass_panel_width',
      label: 'Individual glass panel width',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.glass,
      mustBePositive: true,
      installations: {SignageCatalog.glassPasting},
    ),
    MeasurementField(
      id: 'glass_panel_height',
      label: 'Individual glass panel height',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.glass,
      mustBePositive: true,
      installations: {SignageCatalog.glassPasting},
    ),
    MeasurementField(
      id: 'glass_panel_count',
      label: 'Number of panels',
      kind: MeasureFieldKind.count,
      group: MeasureGroup.glass,
      installations: {SignageCatalog.glassPasting},
    ),
    MeasurementField(
      id: 'glass_edge_clearance',
      label: 'Required edge clearance',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.glass,
      installations: {SignageCatalog.glassPasting},
    ),
    // Board construction (drives the parametric 3D model / 2D drawing).
    MeasurementField(
      id: 'board_depth',
      label: 'Board / box depth',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.model,
      mustBePositive: true,
      mediaCodes: {
        SignageCatalog.gsb,
        SignageCatalog.nlb,
        SignageCatalog.acp,
        SignageCatalog.acp2d,
        SignageCatalog.acp2dDouble,
        SignageCatalog.acp3dDouble,
      },
    ),
    MeasurementField(
      id: 'frame_thickness',
      label: 'Frame thickness',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.model,
      mustBePositive: true,
      mediaCodes: {
        SignageCatalog.gsb,
        SignageCatalog.nlb,
        SignageCatalog.sandwichBoard,
      },
    ),
    MeasurementField(
      id: 'material_thickness',
      label: 'Material / panel thickness',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.model,
      mustBePositive: true,
      mediaCodes: {
        SignageCatalog.foamVinyl,
        SignageCatalog.clearAcrylic,
        SignageCatalog.acp,
        SignageCatalog.acp2d,
        SignageCatalog.acp2dDouble,
        SignageCatalog.acp3dDouble,
        SignageCatalog.sandwichBoard,
      },
    ),
    MeasurementField(
      id: 'standoff_offset',
      label: 'Standoff offset from wall',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.model,
      mediaCodes: {SignageCatalog.clearAcrylic},
    ),
    MeasurementField(
      id: 'letter_depth_front',
      label: 'Letter projection (front)',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.model,
      mustBePositive: true,
      mediaCodes: {SignageCatalog.acp, SignageCatalog.acp3dDouble},
    ),
    MeasurementField(
      id: 'letter_depth_rear',
      label: 'Letter projection (rear)',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.model,
      mustBePositive: true,
      mediaCodes: {SignageCatalog.acp3dDouble},
    ),
    MeasurementField(
      id: 'mdf_thickness',
      label: 'MDF thickness',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.model,
      mustBePositive: true,
      mediaCodes: {SignageCatalog.mdfGsb, SignageCatalog.mdfGsbDouble},
    ),
    MeasurementField(
      id: 'gsb_panel_width',
      label: 'GSB panel width',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.model,
      mustBePositive: true,
      mediaCodes: {SignageCatalog.mdfGsb, SignageCatalog.mdfGsbDouble},
    ),
    MeasurementField(
      id: 'gsb_panel_height',
      label: 'GSB panel height',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.model,
      mustBePositive: true,
      mediaCodes: {SignageCatalog.mdfGsb, SignageCatalog.mdfGsbDouble},
    ),
    MeasurementField(
      id: 'gsb_depth',
      label: 'GSB box depth',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.model,
      mustBePositive: true,
      mediaCodes: {SignageCatalog.mdfGsb, SignageCatalog.mdfGsbDouble},
    ),
    MeasurementField(
      id: 'opening_angle',
      label: 'A-frame opening angle',
      kind: MeasureFieldKind.count,
      group: MeasureGroup.model,
      unitLabel: 'deg',
      mediaCodes: {SignageCatalog.sandwichBoard},
    ),
    MeasurementField(
      id: 'rooftop_frame_height',
      label: 'Rooftop frame height (roof to board bottom)',
      kind: MeasureFieldKind.length,
      group: MeasureGroup.model,
      installations: {SignageCatalog.rooftop},
    ),
  ];

  static MeasurementField? field(String id) {
    for (final f in fields) {
      if (f.id == id) return f;
    }
    return null;
  }

  static bool _pipesVisible(MeasurementContext c) =>
      pipeInstallations.contains(c.installationCode) ||
      (optionalPipeInstallations.contains(c.installationCode) &&
          c.flags[pipesUsedFlag] == true);

  /// Fields relevant to [c] (in display order).
  static List<MeasurementField> fieldsFor(MeasurementContext c) => [
    for (final f in fields)
      if (c.installationCode != null &&
          (f.installations == null ||
              f.installations!.contains(c.installationCode)) &&
          (f.needsFlag == null || _pipesVisible(c)) &&
          (f.mediaCodes == null || f.mediaCodes!.contains(c.mediaCode)))
        f,
  ];

  static MeasurementContext contextOf(
    Board b,
    SignageUnit u, [
    MeasurementDetails? m,
  ]) => MeasurementContext(
    mediaCode: b.mediaCode,
    installationCode: b.installationOf(u),
    flags: (m ?? u.measurements).flags,
  );

  /// Validates [m] for unit [u] of [b]. Board width/height come from the
  /// existing size fields (never from photos).
  static List<MeasurementIssue> validate(
    Board b,
    SignageUnit u,
    MeasurementDetails m,
  ) {
    final c = contextOf(b, u, m);
    final visible = {for (final f in fieldsFor(c)) f.id};
    final issues = <MeasurementIssue>[];
    double? v(String id) => visible.contains(id) ? m.valuesMm[id] : null;
    double? n(String id) => visible.contains(id) ? m.counts[id] : null;
    final unit = m.unit;
    String len(double mm) => fmtMm(mm, unit);

    // Per-field sign / range checks.
    for (final f in fieldsFor(c)) {
      if (f.kind == MeasureFieldKind.length) {
        final x = m.valuesMm[f.id];
        if (x == null) continue;
        if (!x.isFinite) {
          issues.add(
            MeasurementIssue(
              MeasureIssueLevel.error,
              '${f.label}: invalid number',
              fieldId: f.id,
            ),
          );
        } else if (x < 0) {
          issues.add(
            MeasurementIssue(
              MeasureIssueLevel.error,
              '${f.label} cannot be negative',
              fieldId: f.id,
            ),
          );
        } else if (f.mustBePositive && x == 0) {
          issues.add(
            MeasurementIssue(
              MeasureIssueLevel.error,
              '${f.label} must be greater than zero',
              fieldId: f.id,
            ),
          );
        } else if (x > unusualMm) {
          issues.add(
            MeasurementIssue(
              MeasureIssueLevel.review,
              '${f.label} (${len(x)}) is unusually large – please double-check',
              fieldId: f.id,
            ),
          );
        }
      } else if (f.kind == MeasureFieldKind.count) {
        final x = m.counts[f.id];
        if (x == null) continue;
        if (f.unitLabel != null) {
          if (x <= 0 || x >= 90) {
            issues.add(
              MeasurementIssue(
                MeasureIssueLevel.error,
                '${f.label} must be between 0 and 90 ${f.unitLabel}',
                fieldId: f.id,
              ),
            );
          }
        } else if (x < 1 || x != x.roundToDouble()) {
          issues.add(
            MeasurementIssue(
              MeasureIssueLevel.error,
              '${f.label} must be a whole number of 1 or more',
              fieldId: f.id,
            ),
          );
        }
      }
    }

    final boardW = b.widthOf(u);
    final boardH = b.heightOf(u);
    final wMm = (boardW ?? 0) > 0 ? b.unit.toMm(boardW!) : null;
    final hMm = (boardH ?? 0) > 0 ? b.unit.toMm(boardH!) : null;
    double tol(double ref) => math.max(25, ref.abs() * 0.02);

    // Top = bottom + board height.
    final bottom = v('bottom_height');
    final top = v('top_height');
    if (bottom != null && top != null && bottom >= 0 && top >= 0) {
      if (top <= bottom) {
        issues.add(
          const MeasurementIssue(
            MeasureIssueLevel.error,
            'Top height must be above the bottom height',
            fieldId: 'top_height',
          ),
        );
      } else if (hMm != null) {
        final expected = bottom + hMm;
        if ((top - expected).abs() > tol(expected)) {
          issues.add(
            MeasurementIssue(
              MeasureIssueLevel.warning,
              'Top height (${len(top)}) does not match bottom height + board '
              'height (${len(expected)})',
              fieldId: 'top_height',
            ),
          );
        }
      }
    }

    // Board vs available surface.
    final wallW = v('wall_width');
    final wallH = v('wall_height');
    if (wMm != null && wallW != null && wallW > 0 && wMm > wallW + 1) {
      issues.add(
        MeasurementIssue(
          MeasureIssueLevel.warning,
          'Board width (${len(wMm)}) exceeds the available wall width '
          '(${len(wallW)})',
          fieldId: 'wall_width',
        ),
      );
    }
    if (hMm != null && wallH != null && wallH > 0 && hMm > wallH + 1) {
      issues.add(
        MeasurementIssue(
          MeasureIssueLevel.warning,
          'Board height (${len(hMm)}) exceeds the available wall height '
          '(${len(wallH)})',
          fieldId: 'wall_height',
        ),
      );
    }
    final cl = v('clear_left'), cr = v('clear_right');
    if (wMm != null &&
        wallW != null &&
        wallW > 0 &&
        (cl ?? 0) + (cr ?? 0) > 0) {
      final need = wMm + (cl ?? 0) + (cr ?? 0);
      if (need > wallW + 1 && wMm <= wallW + 1) {
        issues.add(
          MeasurementIssue(
            MeasureIssueLevel.warning,
            'Board width + left/right clearance (${len(need)}) exceeds the '
            'available wall width (${len(wallW)})',
            fieldId: 'clear_left',
          ),
        );
      }
    }
    final ct = v('clear_top'), cb = v('clear_bottom');
    if (hMm != null &&
        wallH != null &&
        wallH > 0 &&
        (ct ?? 0) + (cb ?? 0) > 0) {
      final need = hMm + (ct ?? 0) + (cb ?? 0);
      if (need > wallH + 1 && hMm <= wallH + 1) {
        issues.add(
          MeasurementIssue(
            MeasureIssueLevel.warning,
            'Board height + top/bottom clearance (${len(need)}) exceeds the '
            'available wall height (${len(wallH)})',
            fieldId: 'clear_top',
          ),
        );
      }
    }

    // Poles.
    final total = v('pole_length_total');
    final above = v('pole_above_ground');
    final embed = v('pole_embedment');
    if (total != null && embed != null && total > 0 && embed >= total) {
      issues.add(
        const MeasurementIssue(
          MeasureIssueLevel.error,
          'Embedment depth must be less than the total pole length',
          fieldId: 'pole_embedment',
        ),
      );
    } else if (total != null && above != null && embed != null) {
      final sum = above + embed;
      if ((total - sum).abs() > tol(total)) {
        issues.add(
          MeasurementIssue(
            MeasureIssueLevel.warning,
            'Above-ground height + embedment (${len(sum)}) does not match the '
            'total pole length (${len(total)})',
            fieldId: 'pole_length_total',
          ),
        );
      }
    }
    if (above != null && bottom != null && bottom > above + 1) {
      issues.add(
        MeasurementIssue(
          MeasureIssueLevel.warning,
          'Board bottom height (${len(bottom)}) is above the pole top '
          '(${len(above)})',
          fieldId: 'bottom_height',
        ),
      );
    }
    final poles = n('pole_count');
    if (poles != null && poles >= 1) {
      final expected = c.installationCode == SignageCatalog.doublePole ? 2 : 1;
      if (poles != expected) {
        issues.add(
          MeasurementIssue(
            MeasureIssueLevel.review,
            '${poles.toInt()} pole(s) recorded for a '
            '${expected == 2 ? 'double' : 'single'}-pole installation – '
            'please confirm',
            fieldId: 'pole_count',
          ),
        );
      }
    }
    final spacing = v('pole_spacing');
    if (spacing != null && spacing > 0 && wMm != null && spacing > wMm + 1) {
      issues.add(
        MeasurementIssue(
          MeasureIssueLevel.warning,
          'Pole spacing (${len(spacing)}) is wider than the board '
          '(${len(wMm)})',
          fieldId: 'pole_spacing',
        ),
      );
    }

    // Support pipes.
    final pipeSpacing = v('pipe_spacing');
    final pipes = n('pipe_count');
    if (pipes != null && pipes < 2 && pipeSpacing != null) {
      issues.add(
        const MeasurementIssue(
          MeasureIssueLevel.review,
          'Distance between pipes recorded for a single pipe – please confirm',
          fieldId: 'pipe_spacing',
        ),
      );
    }
    if (pipeSpacing != null && wMm != null && pipeSpacing > wMm + 1) {
      issues.add(
        MeasurementIssue(
          MeasureIssueLevel.warning,
          'Distance between pipes (${len(pipeSpacing)}) is wider than the '
          'board (${len(wMm)})',
          fieldId: 'pipe_spacing',
        ),
      );
    }

    // Standee.
    final overall = v('standee_overall_height');
    final panelH = v('panel_height');
    if (overall != null && panelH != null && panelH > overall + 1) {
      issues.add(
        const MeasurementIssue(
          MeasureIssueLevel.warning,
          'Display panel height exceeds the overall standee height',
          fieldId: 'panel_height',
        ),
      );
    }
    if (overall != null && panelH != null && bottom != null) {
      if (bottom + panelH > overall + tol(overall)) {
        issues.add(
          const MeasurementIssue(
            MeasureIssueLevel.warning,
            'Panel bottom height + panel height exceeds the overall standee '
            'height',
            fieldId: 'standee_overall_height',
          ),
        );
      }
    }

    // Glass.
    final glassW = v('glass_width');
    final glassH = v('glass_height');
    if (wMm != null && glassW != null && glassW > 0 && wMm > glassW + 1) {
      issues.add(
        MeasurementIssue(
          MeasureIssueLevel.warning,
          'Artwork width (${len(wMm)}) exceeds the available glass width '
          '(${len(glassW)})',
          fieldId: 'glass_width',
        ),
      );
    }
    if (hMm != null && glassH != null && glassH > 0 && hMm > glassH + 1) {
      issues.add(
        MeasurementIssue(
          MeasureIssueLevel.warning,
          'Artwork height (${len(hMm)}) exceeds the available glass height '
          '(${len(glassH)})',
          fieldId: 'glass_height',
        ),
      );
    }
    final panelW = v('glass_panel_width');
    final panelCount = n('glass_panel_count');
    if (panelW != null && panelCount != null && glassW != null && glassW > 0) {
      final sum = panelW * panelCount;
      if (sum > glassW + tol(glassW)) {
        issues.add(
          MeasurementIssue(
            MeasureIssueLevel.warning,
            '${panelCount.toInt()} panels × ${len(panelW)} exceed the '
            'available glass width (${len(glassW)})',
            fieldId: 'glass_panel_width',
          ),
        );
      }
    }
    return issues;
  }

  /// Lengths above this are flagged for review (not rejected).
  static const unusualMm = 30000.0;

  /// Blocking errors of a saved measurement record.
  static List<MeasurementIssue> errors(Board b, SignageUnit u) =>
      validate(b, u, u.measurements).where((i) => i.isError).toList();

  /// Human-readable value of a stored field.
  static String display(MeasurementField f, MeasurementDetails m) =>
      switch (f.kind) {
        MeasureFieldKind.length => fmtMm(m.valuesMm[f.id], m.unit),
        MeasureFieldKind.count =>
          m.counts[f.id] == null
              ? '—'
              : f.unitLabel != null
              ? '${m.counts[f.id]} ${f.unitLabel}'
              : '${m.counts[f.id]!.toInt()}',
        MeasureFieldKind.text =>
          (m.texts[f.id] ?? '').trim().isEmpty ? '—' : m.texts[f.id]!.trim(),
        MeasureFieldKind.flag => m.flags[f.id] == true ? 'Yes' : 'No',
      };

  /// Recorded values relevant to [u] ("label: value"), for reports and the
  /// photo dimension picker.
  static List<(MeasurementField, String)> recorded(Board b, SignageUnit u) {
    final m = u.measurements;
    return [
      for (final f in fieldsFor(contextOf(b, u)))
        if ((f.kind == MeasureFieldKind.length &&
                m.valuesMm.containsKey(f.id)) ||
            (f.kind == MeasureFieldKind.count && m.counts.containsKey(f.id)) ||
            (f.kind == MeasureFieldKind.text &&
                (m.texts[f.id] ?? '').trim().isNotEmpty) ||
            (f.kind == MeasureFieldKind.flag && m.flags.containsKey(f.id)))
          (f, display(f, m)),
    ];
  }
}
