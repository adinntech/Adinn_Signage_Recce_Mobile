import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/catalog/site_checklists.dart';
import '../../data/models/models.dart';

/// Operational site indicator built only from explicit user responses.
/// It never certifies structural, electrical or municipal compliance.
enum SiteFeasibility { noKnownObstruction, requiresReview, blocked }

extension SiteFeasibilityX on SiteFeasibility {
  String get label => switch (this) {
    SiteFeasibility.noKnownObstruction => 'No Known Obstruction',
    SiteFeasibility.requiresReview => 'Requires Review',
    SiteFeasibility.blocked => 'Blocked / Needs Site Revision',
  };

  Color get color => switch (this) {
    SiteFeasibility.noKnownObstruction => AdinnColors.success,
    SiteFeasibility.requiresReview => AdinnColors.warning,
    SiteFeasibility.blocked => AdinnColors.red,
  };

  IconData get icon => switch (this) {
    SiteFeasibility.noKnownObstruction => Icons.check_circle_outline,
    SiteFeasibility.requiresReview => Icons.report_problem_outlined,
    SiteFeasibility.blocked => Icons.block,
  };
}

class FeasibilityResult {
  const FeasibilityResult(this.level, this.reasons);

  final SiteFeasibility level;
  final List<String> reasons;
}

/// Obstructions that concern unit [u]: linked to it explicitly, or drawn
/// without links on a photo that shows it.
List<(SitePhoto, ObstructionMark)> obstructionsFor(
  Board b,
  SignageUnit u, {
  Shop? shop,
}) {
  final out = <(SitePhoto, ObstructionMark)>[];
  final shows = b.photosOf(u).map((p) => p.id).toSet();
  // With [shop], photos of other media groups that link this unit count too
  // (one frontage photo may show several media types).
  final photos = shop == null
      ? b.photos
      : [for (final g in shop.boards) ...g.photos];
  for (final p in photos) {
    for (final o in p.markup.obstructions) {
      if (o.unitIds.contains(u.id) ||
          (o.unitIds.isEmpty && shows.contains(p.id))) {
        out.add((p, o));
      }
    }
  }
  return out;
}

FeasibilityResult feasibilityOf(Board b, SignageUnit u, {Shop? shop}) {
  final reasons = <String>[];
  var level = SiteFeasibility.noKnownObstruction;
  void raise(SiteFeasibility l) {
    if (l.index > level.index) level = l;
  }

  for (final (photo, o) in obstructionsFor(b, u, shop: shop)) {
    reasons.add(
      '${o.code} ${o.type.label} (${o.severity.label}) on "${photo.label}"'
      '${o.remarks.trim().isEmpty ? '' : ' – ${o.remarks.trim()}'}',
    );
    raise(
      o.severity == Severity.high
          ? SiteFeasibility.blocked
          : SiteFeasibility.requiresReview,
    );
  }
  final media = SignageCatalog.media(b.mediaCode);
  final e = u.electrical;
  if (media?.illuminated == true &&
      (e.electricityAvailable == TriState.no ||
          e.electricityAvailable == TriState.unknown)) {
    reasons.add(
      'Electricity availability: ${e.electricityAvailable!.label} '
      '(illuminated media)',
    );
    raise(SiteFeasibility.requiresReview);
  }
  // Explicit "Not Assessed" (N/A) on a safety check is never treated as
  // safe: it needs technical review. (An unanswered check is already a
  // missing required answer.)
  for (final id in const ['underground_utilities', 'pole_excavation_allowed']) {
    final r = u.checklist[id];
    final q = SiteChecklists.question(b.mediaCode, id);
    if (q != null && r != null && r.isNa) {
      reasons.add('${q.text} – not assessed (requires review)');
      raise(SiteFeasibility.requiresReview);
    }
  }
  final flags = SiteChecklists.reviewFlags(b, u);
  if (flags.isNotEmpty) {
    reasons.addAll(flags);
    raise(SiteFeasibility.requiresReview);
  }
  return FeasibilityResult(level, reasons);
}

/// Worst feasibility across a shop (for review / report summaries).
SiteFeasibility shopFeasibility(Shop s) {
  var level = SiteFeasibility.noKnownObstruction;
  for (final b in s.boards) {
    for (final u in b.activeUnits) {
      final f = feasibilityOf(b, u, shop: s).level;
      if (f.index > level.index) level = f;
    }
  }
  return level;
}

/// Compact chip showing the feasibility indicator.
class FeasibilityChip extends StatelessWidget {
  const FeasibilityChip(this.level, {super.key, this.compact = false});

  final SiteFeasibility level;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 3),
    decoration: BoxDecoration(
      color: level.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: level.color.withValues(alpha: 0.5)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(level.icon, size: compact ? 13 : 15, color: level.color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(context.ui(level.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: level.color,
            ),
          ),
        ),
      ],
    ),
  );
}
