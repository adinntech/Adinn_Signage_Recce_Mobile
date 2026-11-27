import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/catalog/measurement_fields.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/catalog/site_checklists.dart';
import '../../data/models/models.dart';
import '../../data/models/photo_requirement.dart';
import 'feasibility.dart';

/// Operational readiness of a signage item for review. Built only from
/// recorded data; never a structural / electrical certification.
enum RecceReadiness {
  readyForReview,
  needsClarification,
  installationConstraint,
}

extension RecceReadinessX on RecceReadiness {
  String get label => switch (this) {
    RecceReadiness.readyForReview => 'Ready for Review',
    RecceReadiness.needsClarification => 'Needs Clarification',
    RecceReadiness.installationConstraint =>
      'Installation Constraint Identified',
  };

  String get shortLabel => switch (this) {
    RecceReadiness.readyForReview => 'Ready',
    RecceReadiness.needsClarification => 'Needs info',
    RecceReadiness.installationConstraint => 'Constraint',
  };

  Color get color => switch (this) {
    RecceReadiness.readyForReview => AdinnColors.success,
    RecceReadiness.needsClarification => AdinnColors.warning,
    RecceReadiness.installationConstraint => AdinnColors.red,
  };

  IconData get icon => switch (this) {
    RecceReadiness.readyForReview => Icons.task_alt,
    RecceReadiness.needsClarification => Icons.help_outline,
    RecceReadiness.installationConstraint => Icons.report_problem_outlined,
  };
}

class ReadinessResult {
  const ReadinessResult(this.level, this.missing, this.constraints);

  final RecceReadiness level;

  /// Data still to capture / clarify.
  final List<String> missing;

  /// Recorded site constraints (obstructions, electrical, checklist flags).
  final List<String> constraints;

  List<String> get reasons => [...constraints, ...missing];
}

/// Readiness of unit [u] of [b] in [shop].
ReadinessResult unitReadiness(Shop shop, Board b, SignageUnit u) {
  final missing = <String>[];
  final media = SignageCatalog.media(b.mediaCode);
  final inst = b.installationOf(u);
  if (media == null) missing.add('Media type not selected');
  if (inst == null) {
    missing.add('Installation type not selected');
  } else if (media != null && !SignageCatalog.allowsInstallation(b, inst)) {
    missing.add('Installation not valid for ${media.shortName}');
  }
  if (!b.unitHasSize(u)) missing.add('Width / height not entered');
  final evidence = b.photoRequirement;
  if (evidence.needsPhotos) missing.add(evidence.photoMessage);
  if (evidence.missingUnitIds.contains(u.id)) {
    missing.add('${b.unitLabel(u)} signage marking is missing');
  }
  // This physical board's own Site Questions (own installation + answers).
  final q = media == null || b.installationOf(u) == null
      ? 0
      : SignageCatalog.missingAnswersFor(b, u).length;
  if (q > 0) missing.add('$q site question(s) unanswered');
  final mm = media == null || b.installationOf(u) == null
      ? 0
      : SignageCatalog.missingMeasurementsFor(b, u).length;
  if (mm > 0) missing.add('$mm installation detail(s) missing');
  // Checklist-only questions (equivalents are counted as site questions).
  final cl = SiteChecklists.uniqueMissing(b, u);
  if (cl.isNotEmpty) {
    missing.add('Checklist: ${cl.length} required left');
  }
  final errors = MeasurementCatalog.errors(b, u);
  if (errors.isNotEmpty) missing.add('Measurement: ${errors.first.message}');
  final open = shop.reviewComments.where(
    (c) =>
        c.status == CommentStatus.open &&
        c.groupId == b.id &&
        (c.unitId == null || c.unitId == u.id),
  );
  if (open.isNotEmpty) {
    missing.add('${open.length} reviewer comment(s) open');
  }
  final f = feasibilityOf(b, u, shop: shop);
  final constraints = f.level == SiteFeasibility.noKnownObstruction
      ? const <String>[]
      : f.reasons;
  final level = constraints.isNotEmpty
      ? RecceReadiness.installationConstraint
      : missing.isNotEmpty
      ? RecceReadiness.needsClarification
      : RecceReadiness.readyForReview;
  return ReadinessResult(level, missing, constraints);
}

/// Worst readiness across every unit of [shop] (ready when it has none).
RecceReadiness shopReadiness(Shop shop) {
  var level = RecceReadiness.readyForReview;
  for (final b in shop.boards) {
    for (final u in b.activeUnits) {
      final r = unitReadiness(shop, b, u).level;
      if (r.index > level.index) level = r;
    }
  }
  return level;
}

/// Ready units / all units of [shop].
(int, int) readyUnitCount(Shop shop) {
  var ready = 0, total = 0;
  for (final b in shop.boards) {
    for (final u in b.activeUnits) {
      total++;
      if (unitReadiness(shop, b, u).level == RecceReadiness.readyForReview) {
        ready++;
      }
    }
  }
  return (ready, total);
}

class ReadinessChip extends StatelessWidget {
  const ReadinessChip(this.level, {super.key, this.short = false});

  final RecceReadiness level;
  final bool short;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: level.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: level.color.withValues(alpha: 0.5)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(level.icon, size: 13, color: level.color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            context.ui(short ? level.shortLabel : level.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: level.color,
            ),
          ),
        ),
      ],
    ),
  );
}
