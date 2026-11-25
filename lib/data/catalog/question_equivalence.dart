import '../models/models.dart';
import 'signage_catalog.dart';
import 'site_checklists.dart';

/// A Site Question and a site-checklist question that are the SAME business
/// requirement. The vendor answers the Site Question once; the checklist
/// consumers receive the same value through this mapping.
///
/// Pairs are listed explicitly (never matched by wording) and only become
/// active for a physical board when BOTH questions apply to it and their
/// answer formats are compatible (see [QuestionEquivalence.pairsFor]).
class QuestionEquivalenceRule {
  const QuestionEquivalenceRule(
    this.siteId,
    this.checklistId, {
    this.installations,
  });

  final String siteId;
  final String checklistId;

  /// Installation codes where the two questions mean the same thing
  /// (null = every installation).
  final Set<String>? installations;
}

/// An active, verified pair for one physical board.
class EquivalentPair {
  const EquivalentPair(this.site, this.checklist);

  final SiteQuestion site;
  final ChecklistQuestion checklist;
}

/// A board whose two stored answers for the same question disagree.
class EquivalenceConflict {
  const EquivalenceConflict(this.site, this.checklist, this.checklistText);

  final SiteQuestion site;
  final ChecklistQuestion checklist;
  final String checklistText;
}

class QuestionEquivalence {
  QuestionEquivalence._();

  /// Verified equivalent questions (meaning, scope, type, options, units).
  ///
  /// NOT merged on purpose (different meaning / scope):
  /// * "Electrical point available within 10 ft?" vs "Is electricity
  ///   available nearby?" / "Is there an existing electrical point?"
  /// * "Installation height measured?" (yes/no) vs "Board bottom height"
  ///   (a measured number).
  /// * Vinyl "Visibility requirement" vs "Vinyl type" (different options).
  static const rules = <QuestionEquivalenceRule>[
    QuestionEquivalenceRule('access_method', 'access_requirement'),
    QuestionEquivalenceRule(
      'wall_condition',
      'fixing_surface_condition',
      installations: {SignageCatalog.wallMount},
    ),
    QuestionEquivalenceRule(
      'wall_type',
      'wall_structure_type',
      installations: {SignageCatalog.wallMount, SignageCatalog.flangeBracket},
    ),
    QuestionEquivalenceRule(
      'fascia_material',
      'wall_structure_type',
      installations: {SignageCatalog.shopFascia},
    ),
    QuestionEquivalenceRule(
      'ground_type',
      'ground_condition',
      installations: {SignageCatalog.doublePole, SignageCatalog.singlePole},
    ),
    QuestionEquivalenceRule(
      'excavation_permission',
      'pole_excavation_allowed',
      installations: {SignageCatalog.doublePole},
    ),
    QuestionEquivalenceRule('surface_clean', 'surface_clean'),
    QuestionEquivalenceRule(
      'panel_count',
      'glass_panel_count',
      installations: {SignageCatalog.glassPasting},
    ),
    // Legacy standee media (kept readable, same meaning on both sides).
    QuestionEquivalenceRule('indoor_outdoor', 'indoor_outdoor'),
    QuestionEquivalenceRule('base_type', 'base_type'),
    QuestionEquivalenceRule(
      'pedestrian_clearance',
      'pedestrian_clearance',
      installations: {SignageCatalog.freeStanding},
    ),
  ];

  /// Answer formats are compatible: yes/no ↔ yes/no(/na), a choice whose
  /// options are all valid checklist options, number ↔ numeric.
  static bool compatible(SiteQuestion s, ChecklistQuestion c) {
    switch (s.type) {
      case QuestionType.yesNo:
        return c.type == ChecklistResponseType.yesNoNa;
      case QuestionType.choice:
        return c.type == ChecklistResponseType.dropdown &&
            s.options.every(c.options.contains);
      case QuestionType.number:
        return c.type == ChecklistResponseType.numeric;
      case QuestionType.text:
        return c.type == ChecklistResponseType.shortText;
    }
  }

  /// Active verified pairs of unit [u] (its own installation).
  static List<EquivalentPair> pairsFor(Board b, SignageUnit u) {
    final inst = b.installationOf(u);
    final sites = {for (final q in SignageCatalog.questionsForUnit(b, u)) q.id: q};
    final cls = {
      for (final q in SiteChecklists.questionsFor(b.mediaCode, inst)) q.id: q,
    };
    final out = <EquivalentPair>[];
    for (final r in rules) {
      if (r.installations != null && !r.installations!.contains(inst)) continue;
      final s = sites[r.siteId], c = cls[r.checklistId];
      if (s == null || c == null || !compatible(s, c)) continue;
      out.add(EquivalentPair(s, c));
    }
    return out;
  }

  /// Checklist question ids answered through a Site Question of unit [u].
  static Set<String> mappedChecklistIds(Board b, SignageUnit u) => {
    for (final p in pairsFor(b, u)) p.checklist.id,
  };

  static Object? _toChecklistValue(SiteQuestion s, Object? v) {
    if (v == null) return null;
    if (v is bool) return v ? 'yes' : 'no';
    return v;
  }

  static Object? _toSiteValue(SiteQuestion s, ChecklistResponse? r) {
    if (r == null || !r.hasValue) return null;
    final v = r.value;
    switch (s.type) {
      case QuestionType.yesNo:
        return v == 'yes'
            ? true
            : v == 'no'
            ? false
            : null; // 'na' has no Site Question equivalent
      case QuestionType.choice:
        return v is String && s.options.contains(v) ? v : null;
      case QuestionType.number:
        return v is num ? v.toDouble() : double.tryParse('$v');
      case QuestionType.text:
        return v is String ? v : null;
    }
  }

  static bool _same(Object? a, Object? b) {
    if (a is num && b is num) return (a - b).abs() < 1e-9;
    return a == b;
  }

  /// Site answers of unit [u] as validation sees them: the stored Site
  /// Question answers, completed by an earlier checklist answer of the same
  /// question when the Site Question is still empty (read-time only, nothing
  /// is rewritten). On a conflict the Site Question answer wins; the
  /// checklist value is kept untouched and reported by [conflicts].
  static Map<String, dynamic> effectiveSiteAnswers(Board b, SignageUnit u) {
    final stored = SignageCatalog.answersOf(b, u);
    final out = Map<String, dynamic>.from(stored);
    for (final p in pairsFor(b, u)) {
      if (p.site.isAnswered(stored)) continue;
      final v = _toSiteValue(p.site, u.checklist[p.checklist.id]);
      if (v != null) out[p.site.id] = v;
    }
    return out;
  }

  /// Checklist responses of unit [u] as validation sees them: a mapped
  /// question answered through its Site Question counts as answered.
  static Map<String, ChecklistResponse> projectedChecklist(
    Board b,
    SignageUnit u,
  ) {
    final out = Map<String, ChecklistResponse>.of(u.checklist);
    final stored = SignageCatalog.answersOf(b, u);
    for (final p in pairsFor(b, u)) {
      if (p.checklist.isAnswered(u.checklist[p.checklist.id])) continue;
      if (!p.site.isAnswered(stored)) continue;
      out[p.checklist.id] = ChecklistResponse(
        questionId: p.checklist.id,
        value: _toChecklistValue(p.site, stored[p.site.id]),
      );
    }
    return out;
  }

  /// Writes the Site Question answer [siteId] of unit [u] to the matching
  /// checklist question (explicit user edit, so the checklist follows it).
  static void syncToChecklist(Board b, SignageUnit u, String siteId) {
    final stored = SignageCatalog.answersOf(b, u);
    for (final p in pairsFor(b, u)) {
      if (p.site.id != siteId) continue;
      final cur = u.checklist[p.checklist.id];
      final v = _toChecklistValue(p.site, stored[siteId]);
      final next = (cur ?? ChecklistResponse(questionId: p.checklist.id));
      final updated = v == null
          ? next.copyWith(clearValue: true)
          : next.copyWith(value: v);
      if (!updated.hasValue &&
          updated.remarks.isEmpty &&
          updated.evidencePhotoIds.isEmpty) {
        u.checklist.remove(p.checklist.id);
      } else {
        u.checklist[p.checklist.id] = updated;
      }
    }
  }

  /// Questions answered differently in the two legacy maps (never resolved
  /// silently).
  static List<EquivalenceConflict> conflicts(Board b, SignageUnit u) {
    final stored = SignageCatalog.answersOf(b, u);
    final out = <EquivalenceConflict>[];
    for (final p in pairsFor(b, u)) {
      if (!p.site.isAnswered(stored)) continue;
      final r = u.checklist[p.checklist.id];
      if (!p.checklist.isAnswered(r) || r!.isNa) continue;
      final cv = _toSiteValue(p.site, r);
      if (cv != null && !_same(cv, stored[p.site.id])) {
        out.add(EquivalenceConflict(p.site, p.checklist, p.checklist.answerText(r)));
      }
    }
    return out;
  }
}
