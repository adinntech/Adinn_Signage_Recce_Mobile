import '../models/models.dart';
import 'question_equivalence.dart';
import 'signage_catalog.dart';

/// How a checklist question is answered.
enum ChecklistResponseType {
  yesNoNa,
  dropdown,
  numeric,
  shortText,
  longText,
  photoEvidence,
}

/// One configurable checklist question. Questions are data, not widgets:
/// the UI and validation are generated from these definitions.
class ChecklistQuestion {
  const ChecklistQuestion({
    required this.id,
    required this.text,
    required this.type,
    this.options = const [],
    this.required = true,
    this.allowNa = false,
    this.unit,
    this.installations,
    this.reviewIfYes = false,
    this.reviewIfNo = false,
  });

  /// Checklist ID (stable; responses are stored under it).
  final String id;
  final String text;
  final ChecklistResponseType type;
  final List<String> options;
  final bool required;

  /// "Not Applicable" may be chosen.
  final bool allowNa;
  final String? unit;

  /// Installation codes the question applies to (null = all).
  final Set<String>? installations;

  /// A "Yes" / "No" answer flags the item for technical review (site
  /// feasibility indicator). Operational only – never a certification.
  final bool reviewIfYes;
  final bool reviewIfNo;

  bool appliesTo(String? installationCode) =>
      installations == null || installations!.contains(installationCode);

  /// True when [r] fully answers this question.
  bool isAnswered(ChecklistResponse? r) {
    if (r == null) return false;
    if (r.isNa) return allowNa;
    if (type == ChecklistResponseType.photoEvidence) {
      return r.evidencePhotoIds.isNotEmpty;
    }
    if (!r.hasValue) return false;
    final v = r.value;
    return switch (type) {
      ChecklistResponseType.yesNoNa => v == 'yes' || v == 'no',
      ChecklistResponseType.dropdown => v is String && options.contains(v),
      ChecklistResponseType.numeric =>
        v is num || (v is String && double.tryParse(v) != null),
      _ => true,
    };
  }

  /// Display text of a response.
  String answerText(ChecklistResponse? r) {
    if (r == null) return '—';
    if (r.isNa) return 'Not applicable';
    if (type == ChecklistResponseType.photoEvidence) {
      final n = r.evidencePhotoIds.length;
      return n == 0 ? '—' : '$n photo${n == 1 ? '' : 's'}';
    }
    final v = r.value;
    if (v == null) return '—';
    if (v == 'yes') return 'Yes';
    if (v == 'no') return 'No';
    if (v is num) {
      final s = v == v.roundToDouble()
          ? v.toInt().toString()
          : v.toStringAsFixed(2);
      return unit == null ? s : '$s $unit';
    }
    return '$v';
  }
}

/// A named list of questions for one or more media types.
class ChecklistDefinition {
  const ChecklistDefinition({
    required this.id,
    required this.title,
    required this.mediaCodes,
    required this.questions,
  });

  final String id;
  final String title;
  final Set<String> mediaCodes;
  final List<ChecklistQuestion> questions;
}

/// Checklist completion of one signage item.
class ChecklistStatus {
  const ChecklistStatus({
    required this.applicable,
    required this.answered,
    required this.missingRequired,
  });

  final List<ChecklistQuestion> applicable;
  final int answered;
  final List<ChecklistQuestion> missingRequired;

  int get total => applicable.length;
  bool get isComplete => missingRequired.isEmpty;
  bool get isStarted => answered > 0;
}

class SiteChecklists {
  SiteChecklists._();

  static const _poles = {SignageCatalog.singlePole, SignageCatalog.doublePole};

  static const _evidence = ChecklistQuestion(
    id: 'site_evidence_photo',
    text: 'Site evidence photo',
    type: ChecklistResponseType.photoEvidence,
    required: false,
  );

  static const _remarks = ChecklistQuestion(
    id: 'checklist_remarks',
    text: 'Additional site remarks',
    type: ChecklistResponseType.longText,
    required: false,
  );

  static const _access = ChecklistQuestion(
    id: 'access_requirement',
    text: 'Access requirement for installation',
    type: ChecklistResponseType.dropdown,
    options: ['Direct reach', 'Ladder', 'Scaffolding', 'Crane / Hydra'],
  );

  static const _surfaceCondition = ChecklistQuestion(
    id: 'fixing_surface_condition',
    text: 'Fixing surface condition',
    type: ChecklistResponseType.dropdown,
    options: ['Good', 'Average', 'Poor'],
  );

  static const _wallType = ChecklistQuestion(
    id: 'wall_structure_type',
    text: 'Wall / structure type',
    type: ChecklistResponseType.dropdown,
    options: ['Brick', 'Concrete', 'Metal sheet', 'Stone', 'Wooden', 'Other'],
    allowNa: true,
  );

  static const _poleQuestions = [
    ChecklistQuestion(
      id: 'ground_condition',
      text: 'Ground condition at pole location',
      type: ChecklistResponseType.dropdown,
      options: ['Soil', 'Concrete', 'Tar road', 'Footpath tiles'],
      installations: _poles,
    ),
    ChecklistQuestion(
      id: 'underground_utilities',
      text: 'Any underground cables / pipes suspected at pole location?',
      type: ChecklistResponseType.yesNoNa,
      allowNa: true,
      installations: _poles,
      reviewIfYes: true,
    ),
    ChecklistQuestion(
      id: 'pole_excavation_allowed',
      text: 'Is excavation for the pole footing permitted?',
      type: ChecklistResponseType.yesNoNa,
      installations: _poles,
      reviewIfNo: true,
    ),
  ];

  static const definitions = <ChecklistDefinition>[
    ChecklistDefinition(
      id: 'gsb',
      title: 'GSB site checklist',
      mediaCodes: {
        SignageCatalog.gsb,
        SignageCatalog.mdfGsb,
        SignageCatalog.mdfGsbDouble,
      },
      questions: [
        ChecklistQuestion(
          id: 'structure_accessible',
          text: 'Is the proposed wall / structure accessible?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfNo: true,
        ),
        ChecklistQuestion(
          id: 'fixing_surface_available',
          text: 'Is a suitable fixing surface available?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfNo: true,
        ),
        ChecklistQuestion(
          id: 'electricity_nearby',
          text: 'Is electricity available nearby?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfNo: true,
        ),
        ChecklistQuestion(
          id: 'existing_electrical_point',
          text: 'Is there an existing electrical point?',
          type: ChecklistResponseType.yesNoNa,
        ),
        ChecklistQuestion(
          id: 'installation_height_measured',
          text: 'Is the installation height measured?',
          type: ChecklistResponseType.yesNoNa,
        ),
        ChecklistQuestion(
          id: 'visible_wires',
          text: 'Are there visible electrical wires near the board area?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfYes: true,
        ),
        ChecklistQuestion(
          id: 'ac_or_obstruction',
          text: 'Is there any AC unit or other obstruction?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfYes: true,
        ),
        ChecklistQuestion(
          id: 'night_visibility',
          text: 'Is night visibility relevant?',
          type: ChecklistResponseType.yesNoNa,
          allowNa: true,
        ),
        ChecklistQuestion(
          id: 'access_equipment',
          text: 'Is additional access equipment likely to be required?',
          type: ChecklistResponseType.yesNoNa,
        ),
        ChecklistQuestion(
          id: 'location_approved_by_shop',
          text: 'Is the proposed location approved by the shop representative?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfNo: true,
        ),
        ..._poleQuestions,
        _evidence,
        _remarks,
      ],
    ),
    ChecklistDefinition(
      id: 'standard_board',
      title: 'Signage board site checklist',
      mediaCodes: {
        SignageCatalog.nlb,
        SignageCatalog.acp,
        SignageCatalog.flange,
        SignageCatalog.acp2d,
        SignageCatalog.acp2dDouble,
        SignageCatalog.acp3dDouble,
        SignageCatalog.clearAcrylic,
        SignageCatalog.foamVinyl,
      },
      questions: [
        _wallType,
        _surfaceCondition,
        ChecklistQuestion(
          id: 'installation_height_measured',
          text: 'Is the installation height measured?',
          type: ChecklistResponseType.yesNoNa,
        ),
        ChecklistQuestion(
          id: 'area_free_of_obstruction',
          text: 'Is the board area free of obstructions?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfNo: true,
        ),
        ChecklistQuestion(
          id: 'support_pipe_required',
          text: 'Are support pipes required?',
          type: ChecklistResponseType.yesNoNa,
          allowNa: true,
        ),
        ChecklistQuestion(
          id: 'pole_configuration_confirmed',
          text: 'Is the pole configuration confirmed on site?',
          type: ChecklistResponseType.yesNoNa,
          installations: _poles,
          reviewIfNo: true,
        ),
        ..._poleQuestions,
        _access,
        _evidence,
        _remarks,
      ],
    ),
    ChecklistDefinition(
      id: 'wall_branding',
      title: 'Wall branding site checklist',
      mediaCodes: {SignageCatalog.wallPainting},
      questions: [
        _wallType,
        ChecklistQuestion(
          id: 'surface_condition',
          text: 'Wall surface condition',
          type: ChecklistResponseType.dropdown,
          options: ['Plastered', 'Unplastered', 'Old paint', 'Damp / seepage'],
        ),
        ChecklistQuestion(
          id: 'wall_area_measured',
          text: 'Is the available wall area measured?',
          type: ChecklistResponseType.yesNoNa,
        ),
        ChecklistQuestion(
          id: 'area_free_of_obstruction',
          text: 'Is the wall free of pipes / wires / obstructions?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfNo: true,
        ),
        ChecklistQuestion(
          id: 'moisture_exposure',
          text: 'Is the wall exposed to moisture / seepage?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfYes: true,
        ),
        _access,
        _evidence,
        _remarks,
      ],
    ),
    ChecklistDefinition(
      id: 'single_standee',
      title: 'Single-sided standee checklist',
      mediaCodes: {SignageCatalog.singleStandee, SignageCatalog.sandwichBoard},
      questions: [
        ChecklistQuestion(
          id: 'placement_surface',
          text: 'Placement surface type',
          type: ChecklistResponseType.dropdown,
          options: [
            'Footpath tiles',
            'Concrete',
            'Soil',
            'Tar road',
            'Shop floor',
          ],
        ),
        ChecklistQuestion(
          id: 'ground_space_available',
          text: 'Is enough ground space available?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfNo: true,
        ),
        ChecklistQuestion(
          id: 'pedestrian_obstruction',
          text: 'Will the standee obstruct pedestrians?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfYes: true,
        ),
        ChecklistQuestion(
          id: 'door_shutter_clearance',
          text: 'Is there clearance from doors / shutters?',
          type: ChecklistResponseType.yesNoNa,
          allowNa: true,
          reviewIfNo: true,
        ),
        ChecklistQuestion(
          id: 'roadside_exposure',
          text: 'Is the standee exposed to roadside traffic?',
          type: ChecklistResponseType.yesNoNa,
        ),
        ChecklistQuestion(
          id: 'base_type',
          text: 'Base type',
          type: ChecklistResponseType.dropdown,
          options: [
            'Flat MS base plate',
            'Weighted / sand base',
            'Water-fill base',
            'Ground-fixed (bolted / embedded)',
          ],
        ),
        ChecklistQuestion(
          id: 'stability_review',
          text: 'Any stability concerns requiring technical review?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfYes: true,
        ),
        ChecklistQuestion(
          id: 'indoor_outdoor',
          text: 'Indoor / outdoor placement',
          type: ChecklistResponseType.dropdown,
          options: ['Outdoor', 'Indoor'],
        ),
        _evidence,
        _remarks,
      ],
    ),
    ChecklistDefinition(
      id: 'double_standee',
      title: 'Double-sided standee checklist',
      mediaCodes: {SignageCatalog.doubleStandee},
      questions: [
        ChecklistQuestion(
          id: 'front_visibility',
          text: 'Is the front face clearly visible to the target traffic?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfNo: true,
        ),
        ChecklistQuestion(
          id: 'back_visibility',
          text: 'Is the back face clearly visible to the target traffic?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfNo: true,
        ),
        ChecklistQuestion(
          id: 'placement_surface',
          text: 'Placement surface type',
          type: ChecklistResponseType.dropdown,
          options: [
            'Footpath tiles',
            'Concrete',
            'Soil',
            'Tar road',
            'Shop floor',
          ],
        ),
        ChecklistQuestion(
          id: 'pedestrian_clearance',
          text: 'Does it leave enough pedestrian clearance?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfNo: true,
        ),
        ChecklistQuestion(
          id: 'door_shutter_obstruction',
          text: 'Does it obstruct any door / shutter?',
          type: ChecklistResponseType.yesNoNa,
          allowNa: true,
          reviewIfYes: true,
        ),
        ChecklistQuestion(
          id: 'base_configuration',
          text: 'Base configuration',
          type: ChecklistResponseType.dropdown,
          options: [
            'Flat MS base plate',
            'Weighted / sand base',
            'Water-fill base',
            'Ground-fixed (bolted / embedded)',
          ],
        ),
        ChecklistQuestion(
          id: 'roadside_exposure',
          text: 'Is the standee exposed to roadside traffic?',
          type: ChecklistResponseType.yesNoNa,
        ),
        ChecklistQuestion(
          id: 'technical_review',
          text: 'Is a technical review required?',
          type: ChecklistResponseType.yesNoNa,
          reviewIfYes: true,
        ),
        _evidence,
        _remarks,
      ],
    ),
    // Existing catalog maps One-Way Vision to the Vinyl media type.
    ChecklistDefinition(
      id: 'vinyl_owv',
      title: 'One Way Vision / Vinyl checklist',
      mediaCodes: {
        SignageCatalog.vinyl,
        SignageCatalog.oneWayVision,
        SignageCatalog.plainVinyl,
      },
      questions: [
        ChecklistQuestion(
          id: 'glass_panels_measured',
          text: 'Are the glass panel dimensions measured?',
          type: ChecklistResponseType.yesNoNa,
          installations: {SignageCatalog.glassPasting},
        ),
        ChecklistQuestion(
          id: 'glass_panel_count',
          text: 'Number of panels',
          type: ChecklistResponseType.numeric,
          installations: {SignageCatalog.glassPasting},
        ),
        ChecklistQuestion(
          id: 'glass_condition',
          text: 'Glass condition',
          type: ChecklistResponseType.dropdown,
          options: ['Good', 'Scratched', 'Cracked'],
          installations: {SignageCatalog.glassPasting},
        ),
        ChecklistQuestion(
          id: 'surface_clean',
          text: 'Is the surface clean and dry?',
          type: ChecklistResponseType.yesNoNa,
        ),
        ChecklistQuestion(
          id: 'door_opening_clearance',
          text: 'Is there clearance for door opening?',
          type: ChecklistResponseType.yesNoNa,
          allowNa: true,
          reviewIfNo: true,
        ),
        ChecklistQuestion(
          id: 'existing_stickers',
          text: 'Are there existing stickers to remove?',
          type: ChecklistResponseType.yesNoNa,
        ),
        ChecklistQuestion(
          id: 'panel_divisions',
          text: 'Panel divisions (frames / joints)',
          type: ChecklistResponseType.shortText,
          required: false,
          installations: {SignageCatalog.glassPasting},
        ),
        ChecklistQuestion(
          id: 'visibility_requirement',
          text: 'Visibility requirement',
          type: ChecklistResponseType.dropdown,
          options: [
            'See-through from inside (one-way)',
            'Fully opaque',
            'Frosted / privacy',
          ],
        ),
        ChecklistQuestion(
          id: 'wall_surface_type',
          text: 'Surface type',
          type: ChecklistResponseType.dropdown,
          options: ['Painted wall', 'Plastered', 'Shutter', 'Door', 'Other'],
          installations: {SignageCatalog.directWall},
        ),
        ChecklistQuestion(
          id: 'moisture_exposure',
          text: 'Is the surface exposed to moisture?',
          type: ChecklistResponseType.yesNoNa,
          installations: {SignageCatalog.directWall},
          reviewIfYes: true,
        ),
        _evidence,
        _remarks,
      ],
    ),
  ];

  /// Definition for [mediaCode] (null when the media type has none).
  static ChecklistDefinition? definitionFor(String? mediaCode) {
    for (final d in definitions) {
      if (d.mediaCodes.contains(mediaCode)) return d;
    }
    return null;
  }

  /// Questions applicable to a media + installation configuration.
  static List<ChecklistQuestion> questionsFor(
    String? mediaCode,
    String? installationCode,
  ) =>
      definitionFor(
        mediaCode,
      )?.questions.where((q) => q.appliesTo(installationCode)).toList() ??
      const [];

  static ChecklistQuestion? question(String? mediaCode, String id) {
    for (final q in definitionFor(mediaCode)?.questions ?? const []) {
      if (q.id == id) return q;
    }
    return null;
  }

  /// Completion of unit [u] of [b] for the current configuration.
  /// Responses to questions that no longer apply are kept but ignored.
  static ChecklistStatus statusOf(Board b, SignageUnit u) => statusFor(
    b.mediaCode,
    b.installationOf(u),
    // A question answered through its (verified equivalent) Site Question
    // counts as answered here too.
    QuestionEquivalence.projectedChecklist(b, u),
  );

  /// Required checklist questions still open that are NOT also a Site
  /// Question (those are counted once, as Site Questions).
  static List<ChecklistQuestion> uniqueMissing(Board b, SignageUnit u) {
    final mapped = QuestionEquivalence.mappedChecklistIds(b, u);
    return [
      for (final q in statusOf(b, u).missingRequired)
        if (!mapped.contains(q.id)) q,
    ];
  }

  static ChecklistStatus statusFor(
    String? mediaCode,
    String? installationCode,
    Map<String, ChecklistResponse> responses,
  ) {
    final qs = questionsFor(mediaCode, installationCode);
    var answered = 0;
    final missing = <ChecklistQuestion>[];
    for (final q in qs) {
      final ok = q.isAnswered(responses[q.id]);
      if (ok) answered++;
      if (q.required && !ok) missing.add(q);
    }
    return ChecklistStatus(
      applicable: qs,
      answered: answered,
      missingRequired: missing,
    );
  }

  /// Answers that flag the item for technical review ("question → answer").
  static List<String> reviewFlags(Board b, SignageUnit u) {
    final out = <String>[];
    for (final q in questionsFor(b.mediaCode, b.installationOf(u))) {
      final r = u.checklist[q.id];
      if (r == null) continue;
      if ((q.reviewIfYes && r.value == 'yes') ||
          (q.reviewIfNo && r.value == 'no')) {
        out.add('${q.text} – ${q.answerText(r)}');
      }
    }
    return out;
  }
}
