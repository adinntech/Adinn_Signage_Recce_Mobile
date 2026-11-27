import 'package:flutter/material.dart';

import '../models/models.dart';
import 'question_equivalence.dart';
import 'site_checklists.dart';

/// How many display faces a media type has.
enum MediaSidedness {
  single,
  double,

  /// The user chooses single- or double-sided per media group.
  selectable,
}

class MediaType {
  const MediaType({
    this.legacy = false,
    this.sidedness = MediaSidedness.single,
    this.template = '',
    this.thicknessMm = 0,
    required this.code,
    required this.shortName,
    required this.name,
    required this.description,
    required this.icon,
    required this.depthFt,
    required this.illuminated,
    required this.installations,
    required this.color,
  });

  final String code;
  final String shortName;
  final String name;
  final String description;
  final IconData icon;

  /// Typical physical depth of the board (used by 2D/3D drawings).
  final double depthFt;
  final bool illuminated;

  /// Installation codes allowed for this media.
  final List<String> installations;
  final Color color;

  /// Kept only so older records stay readable; not offered for new media
  /// groups (see [SignageCatalog.legacyMapping]).
  final bool legacy;
  final MediaSidedness sidedness;

  /// Parametric 3D model template id (empty = legacy scene builder).
  final String template;

  /// Typical material / panel thickness in mm (0 = not applicable).
  final double thicknessMm;
}

/// Explicit mapping options for a legacy media type.
class LegacyMediaMapping {
  const LegacyMediaMapping({
    required this.code,
    required this.candidates,
    required this.note,
  });

  final String code;

  /// Catalog media codes the record may be mapped to (user chooses).
  final List<String> candidates;
  final String note;

  bool get ambiguous => candidates.length != 1;
}

class InstallationType {
  const InstallationType({
    required this.code,
    required this.name,
    required this.description,
    required this.icon,
  });

  final String code;
  final String name;
  final String description;
  final IconData icon;
}

/// Illustration used by the small installation diagrams on the GSB Double
/// Side selection cards. Kept as data here so the catalog stays the single
/// source of truth for the option order; the painter lives in the board UI.
enum InstallationArt {
  projecting,
  doublePole,
  singlePole,
  rooftop,
  hanging,
  generic,
}

/// One selectable installation card.
///
/// [code] is null only for a presentation-only option whose backend contract
/// has not been approved yet. Such an option is never persisted.
class InstallationChoice {
  const InstallationChoice({
    required this.name,
    required this.description,
    required this.art,
    this.code,
    this.icon,
  });

  final String name;
  final String description;
  final InstallationArt art;
  final String? code;
  final IconData? icon;

  bool get canPersist => code != null;
}

class SiteQuestion {
  const SiteQuestion({
    required this.id,
    required this.label,
    required this.type,
    this.options = const [],
    this.unit,
    this.required = true,
    this.hint,
    this.showIfId,
    this.showIfValue,
  });

  final String id;
  final String label;
  final QuestionType type;
  final List<String> options;
  final String? unit;
  final bool required;
  final String? hint;

  /// Only show this question when answer[showIfId] == showIfValue.
  final String? showIfId;
  final Object? showIfValue;

  bool isVisible(Map<String, dynamic> answers) {
    if (showIfId == null) return true;
    return answers[showIfId] == showIfValue;
  }

  bool isAnswered(Map<String, dynamic> answers) {
    final v = answers[id];
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    return true;
  }
}

/// One selectable media group in the Add Media Type popup: a media code plus
/// its fabrication subtype (GSB single/double, NLB single/box frame).
class MediaOption {
  const MediaOption({
    required this.key,
    required this.label,
    required this.mediaCode,
    this.doubleSided,
    this.nlbSubtype,
  });

  /// Stable key, e.g. `GSB_SINGLE`, `NLB_BOX_FRAME`, `ACRYLIC`.
  final String key;
  final String label;
  final String mediaCode;
  final bool? doubleSided;
  final String? nlbSubtype;
}

/// A confirmed media group with its number of physical boards.
class MediaGroupPlan {
  const MediaGroupPlan(this.option, this.quantity);

  final MediaOption option;
  final int quantity;
}

/// Result of [SignageCatalog.planCommonAnswers].
class CommonAnswerPlan {
  const CommonAnswerPlan({
    required this.toCopy,
    required this.wouldOverwrite,
    required this.notCommon,
    required this.sourceUnanswered,
    this.toCopyChecklist = const [],
    this.wouldOverwriteChecklist = const [],
  });

  /// Checklist-only questions (not a Site Question) that are common.
  final List<ChecklistQuestion> toCopyChecklist;
  final List<ChecklistQuestion> wouldOverwriteChecklist;

  /// Common, answered at the source and still empty at the target.
  final List<SiteQuestion> toCopy;

  /// Common and answered at the source, but the target already has an
  /// answer (only replaced after explicit confirmation).
  final List<SiteQuestion> wouldOverwrite;

  /// Required target questions with no matching source definition.
  final List<SiteQuestion> notCommon;

  /// Matching questions the source itself has not answered.
  final List<SiteQuestion> sourceUnanswered;
}

/// Static master data for the signage media types (6 original + single /
/// double sided standees), their supported
/// installation methods and the dynamic site questions for each combination.
class SignageCatalog {
  SignageCatalog._();

  // Installation codes
  static const shopFascia = 'shop_fascia';
  static const wallMount = 'wall_mount';
  static const doublePole = 'double_pole';
  static const singlePole = 'single_pole';
  static const rooftop = 'rooftop';
  static const flangeBracket = 'flange_bracket';
  static const directWall = 'direct_wall';
  static const glassPasting = 'glass_pasting';
  static const freeStanding = 'free_standing';
  static const supportPipe = "support_pipe";

  // Media codes
  static const gsb = 'GSB';
  static const nlb = 'NLB';
  static const acp = 'ACP';
  static const flange = 'FLANGE';
  static const vinyl = 'VINYL';
  static const wallPainting = 'WALL';
  static const singleStandee = 'SSTANDEE';
  static const doubleStandee = 'DSTANDEE';
  static const foamVinyl = "FOAM_VINYL";
  static const clearAcrylic = "ACRYLIC";
  static const sandwichBoard = "SANDWICH";
  static const oneWayVision = "OWV";
  static const plainVinyl = "PLAIN_VINYL";
  static const acp2d = "ACP2D";
  static const acp2dDouble = "ACP2D_DS";
  static const acp3dDouble = "ACP3D_DS";
  static const mdfGsb = "MDF_GSB";
  static const mdfGsbDouble = "MDF_GSB_DS";

  /// Standalone MDF board. Deliberately NOT mapped to [mdfGsb]: no approved
  /// MDF-only fabrication / installation specification exists yet.
  static const mdf = 'MDF';

  /// Freestanding boards placed outside the shop.
  static bool isStandee(String? mediaCode) =>
      mediaCode == singleStandee || mediaCode == doubleStandee;

  static const List<MediaType> mediaTypes = [
    MediaType(
      code: gsb,
      sidedness: MediaSidedness.selectable,
      template: 'gsb',
      shortName: 'GSB',
      name: 'GSB Board (Glow Sign Board)',
      description: 'Back-lit flex/ACP box with LED modules inside an MS frame.',
      icon: Icons.lightbulb_outline,
      // 8 in outside-to-outside box depth (Signage Fabrication Rulebook
      // 1.0, GSB Single / Double). Was 0.75 ft (9 in) before.
      depthFt: 8 / 12,
      illuminated: true,
      installations: [
        shopFascia,
        wallMount,
        doublePole,
        singlePole,
        rooftop,
        supportPipe,
      ],
      color: Color(0xFFD71920),
    ),
    MediaType(
      code: nlb,
      sidedness: MediaSidedness.selectable,
      template: 'nonlit',
      shortName: 'NLB',
      name: 'Non-Lit Board',
      description: 'Flex or vinyl on a sun-board/MS frame, no illumination.',
      icon: Icons.crop_landscape,
      depthFt: 0.25,
      illuminated: false,
      installations: [
        shopFascia,
        wallMount,
        doublePole,
        singlePole,
        rooftop,
        supportPipe,
      ],
      color: Color(0xFF1A73E8),
    ),
    MediaType(
      code: acp,
      template: 'acp3d',
      thicknessMm: 4,
      shortName: 'ACP 3D',
      name: 'ACP 3D (Raised Letters)',
      description: 'ACP cladding with acrylic / SS raised letters.',
      icon: Icons.text_fields,
      depthFt: 0.4,
      illuminated: true,
      installations: [shopFascia, wallMount, rooftop, supportPipe],
      color: Color(0xFF455A64),
    ),
    MediaType(
      legacy: true,
      code: flange,
      shortName: 'Flange',
      name: 'Flange / Projecting Board',
      description: 'Double-sided board projecting out from the wall or pole.',
      icon: Icons.flag_outlined,
      depthFt: 0.5,
      illuminated: true,
      installations: [flangeBracket, singlePole],
      color: Color(0xFF7B1FA2),
    ),
    MediaType(
      legacy: true,
      code: vinyl,
      shortName: 'Vinyl',
      name: 'Vinyl / One-Way Vision',
      description: 'Printed vinyl pasted on glass, shutter or door.',
      icon: Icons.window_outlined,
      depthFt: 0.02,
      illuminated: false,
      installations: [glassPasting, directWall],
      color: Color(0xFF00897B),
    ),
    MediaType(
      legacy: true,
      code: wallPainting,
      shortName: 'Wall Paint',
      name: 'Wall Painting / Wall Branding',
      description: 'Hand / stencil painted branding directly on the wall.',
      icon: Icons.format_paint_outlined,
      depthFt: 0.02,
      illuminated: false,
      installations: [directWall],
      color: Color(0xFFE37400),
    ),
    MediaType(
      legacy: true,
      code: singleStandee,
      shortName: 'Standee 1S',
      name: 'Single-Sided Standee',
      description:
          'Freestanding board outside the shop with one visible advertising '
          'face, on a supporting frame and ground base.',
      icon: Icons.signpost_outlined,
      depthFt: 0.15,
      illuminated: false,
      installations: [freeStanding],
      color: Color(0xFF5D4037),
    ),
    MediaType(
      legacy: true,
      sidedness: MediaSidedness.double,
      code: doubleStandee,
      shortName: 'Standee 2S',
      name: 'Double-Sided Standee',
      description:
          'One freestanding board with artwork on both front and back faces '
          '(quantity counts physical standees, not faces).',
      icon: Icons.view_agenda_outlined,
      depthFt: 0.3,
      illuminated: false,
      installations: [freeStanding],
      color: Color(0xFF283593),
    ),
  ];

  /// Media introduced with catalog v2 (13-entry business catalog).
  static const List<MediaType> newMediaTypes = [
    MediaType(
      code: foamVinyl,
      template: 'foam',
      thicknessMm: 3, // rigid foam board: 3 mm substrate
      shortName: 'Foam Vinyl',
      name: 'Foam Board with Vinyl',
      description: 'Printed vinyl on a thin foam / sun-board substrate.',
      icon: Icons.layers_outlined,
      depthFt: 3 / 304.8,
      illuminated: false,
      installations: [wallMount, directWall],
      color: Color(0xFF6D4C41),
    ),
    MediaType(
      code: clearAcrylic,
      template: 'acrylic',
      thicknessMm: 8,
      shortName: 'Acrylic',
      name: 'Clear Acrylic',
      description: 'Transparent acrylic panel with printed / applied graphics.',
      icon: Icons.crop_square,
      depthFt: 0.03,
      illuminated: false,
      installations: [wallMount, shopFascia, glassPasting],
      color: Color(0xFF0097A7),
    ),
    MediaType(
      code: sandwichBoard,
      template: 'sandwich',
      sidedness: MediaSidedness.double,
      thicknessMm: 6,
      shortName: 'Sandwich',
      name: 'Sandwich Board (A-Frame)',
      description: 'Portable A-frame with a display panel on each side.',
      icon: Icons.change_history,
      depthFt: 0.1,
      illuminated: false,
      installations: [freeStanding],
      color: Color(0xFF8D6E63),
    ),
    MediaType(
      code: oneWayVision,
      template: 'owv',
      thicknessMm: 0.2,
      // Display label only; the stored code stays OWV.
      shortName: 'One-Way Vision',
      name: 'One-Way Vision',
      description: 'Perforated printed film applied on glass.',
      icon: Icons.blur_on,
      depthFt: 0.01,
      illuminated: false,
      installations: [glassPasting],
      color: Color(0xFF00897B),
    ),
    MediaType(
      code: plainVinyl,
      template: 'vinyl',
      thicknessMm: 0.1,
      shortName: 'Plain Vinyl',
      name: 'Plain Vinyl',
      description: 'Printed / cut vinyl applied on a wall, glass or door.',
      icon: Icons.wallpaper,
      depthFt: 0.01,
      illuminated: false,
      installations: [directWall, glassPasting],
      color: Color(0xFF43A047),
    ),
    MediaType(
      code: acp2d,
      template: 'acp2d',
      thicknessMm: 4,
      shortName: 'ACP 2D',
      name: 'ACP 2D (Flat Artwork)',
      description: 'Flat ACP panel with applied 2D artwork, no raised letters.',
      icon: Icons.rectangle_outlined,
      depthFt: 0.25,
      illuminated: false,
      installations: [shopFascia, wallMount, supportPipe, rooftop],
      color: Color(0xFF546E7A),
    ),
    MediaType(
      code: acp2dDouble,
      template: 'acp2d',
      sidedness: MediaSidedness.double,
      thicknessMm: 4,
      shortName: 'ACP 2D DS',
      name: 'ACP 2D – Double-Sided',
      description: 'ACP display with artwork on both front and rear faces.',
      icon: Icons.flip,
      depthFt: 0.3,
      illuminated: false,
      installations: [singlePole, doublePole, supportPipe, rooftop],
      color: Color(0xFF607D8B),
    ),
    MediaType(
      code: acp3dDouble,
      template: 'acp3d',
      sidedness: MediaSidedness.double,
      thicknessMm: 4,
      shortName: 'ACP 3D DS',
      name: 'ACP 3D – Double-Sided',
      description: 'ACP structure with raised letters on both faces.',
      icon: Icons.text_rotation_none,
      depthFt: 0.5,
      illuminated: true,
      installations: [singlePole, doublePole, supportPipe, rooftop],
      color: Color(0xFF37474F),
    ),
    MediaType(
      code: mdfGsb,
      template: 'mdfgsb',
      thicknessMm: 18,
      shortName: 'MDF+GSB',
      name: 'MDF Board with GSB',
      description: 'MDF backing / frame with an integrated glow sign box.',
      icon: Icons.view_quilt_outlined,
      depthFt: 0.75,
      illuminated: true,
      installations: [shopFascia, wallMount, supportPipe],
      color: Color(0xFFAD1457),
    ),
    MediaType(
      code: mdfGsbDouble,
      template: 'mdfgsb',
      sidedness: MediaSidedness.double,
      thicknessMm: 18,
      shortName: 'MDF+GSB DS',
      name: 'MDF Board with GSB – Double-Sided',
      description: 'MDF structure with glow sign faces on front and rear.',
      icon: Icons.view_agenda,
      depthFt: 0.9,
      illuminated: true,
      installations: [singlePole, doublePole, supportPipe, rooftop],
      color: Color(0xFF880E4F),
    ),
    MediaType(
      code: mdf,
      // No approved standalone-MDF template, thickness, depth or LED rule
      // yet: left unconfigured on purpose (pending review).
      shortName: 'MDF',
      name: 'MDF',
      description: 'MDF display board.',
      icon: Icons.dashboard_outlined,
      depthFt: 0,
      illuminated: false,
      installations: [],
      color: Color(0xFF8D6E3F),
    ),
  ];

  /// The 13 selectable business media entries, in catalog order.
  static const catalogCodes = [
    gsb,
    nlb,
    foamVinyl,
    clearAcrylic,
    sandwichBoard,
    oneWayVision,
    plainVinyl,
    acp2d,
    acp2dDouble,
    acp,
    acp3dDouble,
    mdfGsb,
    mdfGsbDouble,
  ];

  // MDF is selectable ([selectableCodes]) but deliberately not part of
  // [catalogCodes] until an approved reference / template exists.

  /// Media offered when adding NEW media to a recce, in display order.
  /// The other catalog entries stay known (serialization, history, editing
  /// of saved items) but are no longer selectable.
  static const selectableCodes = [
    gsb,
    nlb,
    foamVinyl,
    clearAcrylic,
    oneWayVision,
    plainVinyl,
    mdf,
  ];

  static List<MediaType> get selectableMedia => [
    for (final c in selectableCodes) media(c)!,
  ];

  /// Distinct media groups offered by the Add Media Type popup (the seven
  /// approved media, with GSB / NLB split into their fabrication subtypes).
  static const mediaOptions = <MediaOption>[
    MediaOption(
      key: 'GSB_SINGLE',
      label: 'GSB Single Side',
      mediaCode: gsb,
      doubleSided: false,
    ),
    MediaOption(
      key: 'GSB_DOUBLE',
      label: 'GSB Double Side',
      mediaCode: gsb,
      doubleSided: true,
    ),
    MediaOption(
      key: 'NLB_SINGLE_FRAME',
      label: 'NLB Single Frame',
      mediaCode: nlb,
      doubleSided: false,
      nlbSubtype: 'NLB_SINGLE_FRAME',
    ),
    MediaOption(
      key: 'NLB_BOX_FRAME',
      label: 'NLB Box Frame',
      mediaCode: nlb,
      doubleSided: true,
      nlbSubtype: 'NLB_BOX_FRAME',
    ),
    MediaOption(key: foamVinyl, label: 'Foam Vinyl', mediaCode: foamVinyl),
    MediaOption(key: clearAcrylic, label: 'Acrylic', mediaCode: clearAcrylic),
    MediaOption(
      key: oneWayVision,
      label: 'One-Way Vision',
      mediaCode: oneWayVision,
    ),
    MediaOption(key: plainVinyl, label: 'Plain Vinyl', mediaCode: plainVinyl),
    MediaOption(key: mdf, label: 'MDF', mediaCode: mdf),
  ];

  /// Validates a popup configuration. Returns an error message or null.
  static String? validateGroupPlans(int totalBoards, List<MediaGroupPlan> p) {
    if (totalBoards < 1) return 'At least one board is required.';
    if (p.isEmpty) return 'Select at least one media type.';
    if (p.length > totalBoards) {
      return 'Media types cannot exceed the number of boards.';
    }
    if (p.map((e) => e.option.key).toSet().length != p.length) {
      return 'Each media type can be selected only once.';
    }
    if (p.any((e) => e.quantity < 1)) {
      return 'Every media type needs at least one board.';
    }
    final sum = p.fold<int>(0, (s, e) => s + e.quantity);
    if (sum != totalBoards) {
      return 'Allocated boards ($sum) must equal the total ($totalBoards).';
    }
    return null;
  }

  /// Default allocation: one board each, the remainder on the first group.
  static List<int> defaultAllocation(int totalBoards, int groups) {
    if (groups < 1) return const [];
    return [
      for (var i = 0; i < groups; i++)
        i == 0 ? totalBoards - (groups - 1) : 1,
    ];
  }

  /// Short card subtitle for the Add Media Type screen.
  static const _cardSubtitles = {
    gsb: 'Glow Sign Board',
    nlb: 'Non-Lit Board',
    foamVinyl: 'Foam Board with Vinyl',
    clearAcrylic: 'Clear Acrylic Board',
    oneWayVision: 'Perforated Glass Film',
    plainVinyl: 'Printed Vinyl Sticker',
    mdf: 'MDF Display Board',
  };

  static String cardSubtitle(MediaType m) =>
      _cardSubtitles[m.code] ?? m.description;

  /// Catalog version recorded when a legacy media type is mapped.
  static const catalogVersion = 2;

  /// Every known media type (current + legacy) for lookups.
  static const List<MediaType> allMediaTypes = [
    ...mediaTypes,
    ...newMediaTypes,
  ];

  /// Media offered for new media groups (exactly the 13 catalog entries).
  static List<MediaType> get catalogMedia => [
    for (final c in catalogCodes) media(c)!,
  ];

  static bool isLegacy(String? code) => media(code)?.legacy ?? false;

  /// Explicit, never-automatic mapping of a legacy media type to catalog
  /// entries. Ambiguous types list candidates; the user must choose.
  static LegacyMediaMapping? legacyMapping(String? code) => switch (code) {
    flange => const LegacyMediaMapping(
      code: flange,
      candidates: [gsb, nlb, acp2dDouble, acp3dDouble],
      note:
          'Flange boards were double-sided projecting boards. Choose the '
          'catalog media that matches the actual board.',
    ),
    vinyl => const LegacyMediaMapping(
      code: vinyl,
      candidates: [oneWayVision, plainVinyl],
      note: 'The old Vinyl type covered both one-way vision and plain vinyl.',
    ),
    wallPainting => const LegacyMediaMapping(
      code: wallPainting,
      candidates: [],
      note:
          'Wall painting has no equivalent in the 13-media catalog. The '
          'record stays readable as a legacy media type.',
    ),
    singleStandee || doubleStandee => LegacyMediaMapping(
      code: code!,
      candidates: const [sandwichBoard],
      note:
          'A standee is not always an A-frame sandwich board. Map only if '
          'the actual board is an A-frame.',
    ),
    _ => null,
  };

  /// Explicit sidedness of [b] (double-sided = two display faces on one
  /// physical unit; quantity still counts physical units).
  static bool isDoubleSided(Board b) {
    final m = media(b.mediaCode);
    if (m == null) return false;
    return switch (m.sidedness) {
      MediaSidedness.single =>
        m.code == flange && b.answers['sides'] != 'Single side',
      MediaSidedness.double => true,
      MediaSidedness.selectable => b.doubleSided ?? false,
    };
  }

  static const List<InstallationType> installationTypes = [
    InstallationType(
      code: shopFascia,
      name: 'Shop Fascia',
      description: 'Fixed on the shop front elevation above the shutter.',
      icon: Icons.storefront_outlined,
    ),
    InstallationType(
      code: wallMount,
      name: 'Wall Mount',
      description: 'Fixed on a side / compound wall with anchors.',
      icon: Icons.wallpaper_outlined,
    ),
    InstallationType(
      code: doublePole,
      name: 'Double Pole',
      description: 'Free-standing board on two MS/GI poles with footing.',
      icon: Icons.view_column_outlined,
    ),
    InstallationType(
      code: singlePole,
      name: 'Single Pole',
      description: 'Free-standing board on a single central pole.',
      icon: Icons.signpost_outlined,
    ),
    InstallationType(
      code: rooftop,
      name: 'Rooftop',
      description: 'MS structure erected on the terrace / roof.',
      icon: Icons.roofing_outlined,
    ),
    InstallationType(
      code: flangeBracket,
      name: 'Flange Bracket',
      description: 'Projecting board on wall brackets.',
      icon: Icons.open_in_full,
    ),
    InstallationType(
      code: directWall,
      name: 'Direct on Wall',
      description: 'Painted / pasted directly on the wall surface.',
      icon: Icons.format_paint_outlined,
    ),
    InstallationType(
      code: glassPasting,
      name: 'Glass / Shutter Pasting',
      description: 'Pasted on glass panels, doors or rolling shutters.',
      icon: Icons.door_sliding_outlined,
    ),
    InstallationType(
      code: freeStanding,
      name: 'Free Standing (Ground)',
      description: 'Standee placed on the ground outside / inside the shop.',
      icon: Icons.signpost_outlined,
    ),
    InstallationType(
      code: supportPipe,
      name: "Support Pipe",
      description: "Board held off the wall / parapet on MS support pipes.",
      icon: Icons.view_week_outlined,
    ),
  ];

  // ---------------------------------------------------------------------------
  // GSB Double Side installation options
  // ---------------------------------------------------------------------------

  /// Canonical backend codes offered for a NEW GSB Double Side board.
  ///
  /// "Projecting Mount" reuses the existing approved [flangeBracket] code
  /// (a double-sided board projecting from a wall). There is deliberately no
  /// code for Hanging Mount: no backend-supported value exists yet, so it is
  /// shown as a presentation-only card and is never written to [Board].
  static const gsbDoubleInstallationCodes = [
    flangeBracket,
    doublePole,
    singlePole,
    rooftop,
  ];

  /// Exact five-card order for new GSB Double Side selections.
  static const gsbDoubleChoices = <InstallationChoice>[
    InstallationChoice(
      name: 'Projecting Mount',
      description: 'Projects outwards from a wall.',
      art: InstallationArt.projecting,
      icon: Icons.open_in_full,
      code: flangeBracket,
    ),
    InstallationChoice(
      name: 'Double Pole',
      description: 'Supported by two ground-mounted poles.',
      art: InstallationArt.doublePole,
      icon: Icons.view_column_outlined,
      code: doublePole,
    ),
    InstallationChoice(
      name: 'Single Pole',
      description: 'Supported by one central pole.',
      art: InstallationArt.singlePole,
      icon: Icons.signpost_outlined,
      code: singlePole,
    ),
    InstallationChoice(
      name: 'Rooftop',
      description: 'Mounted on a roof or terrace.',
      art: InstallationArt.rooftop,
      icon: Icons.roofing_outlined,
      code: rooftop,
    ),
    InstallationChoice(
      name: 'Hanging Mount',
      description: 'Suspended from an overhead structure.',
      // No GSB Single icon exists: keeps the original hanging illustration
      // (InstallationArtPainter) because no icon is set.
      art: InstallationArt.hanging,
    ),
  ];

  /// True when [b] is a GSB Double Side board (the only scoped variant).
  static bool isGsbDouble(Board? b) =>
      b != null && b.mediaCode == gsb && b.doubleSided == true;

  /// Installation choices offered for [b].
  ///
  /// Every other media type keeps its existing catalog options unchanged.
  static List<InstallationChoice> choicesForBoard(Board b) {
    if (isGsbDouble(b)) return gsbDoubleChoices;
    if (isNlbBox(b)) return nlbBoxChoices;
    return [
      for (final i in installationsFor(b.mediaCode))
        if (newInstallationCodes(b).contains(i.code))
        InstallationChoice(
          name: i.name,
          description: i.description,
          art: InstallationArt.generic,
          code: i.code,
          icon: i.icon,
        ),
    ];
  }

  // ---------------------------------------------------------------------------
  // NLB Box Frame / Foam Vinyl / Acrylic installation options
  // ---------------------------------------------------------------------------

  /// NLB Box Frame (NON_LIT_BOX) installation codes for NEW selections.
  /// "Projecting Mount" reuses the approved [flangeBracket] code. Hanging
  /// Mount is intentionally absent.
  static const nlbBoxInstallationCodes = [
    doublePole,
    rooftop,
    flangeBracket,
    singlePole,
  ];

  static const nlbBoxChoices = <InstallationChoice>[
    InstallationChoice(
      name: 'Double Pole',
      description: 'Supported by two ground-mounted poles.',
      art: InstallationArt.doublePole,
      icon: Icons.view_column_outlined,
      code: doublePole,
    ),
    InstallationChoice(
      name: 'Rooftop',
      description: 'Mounted on a roof or terrace.',
      art: InstallationArt.rooftop,
      icon: Icons.roofing_outlined,
      code: rooftop,
    ),
    InstallationChoice(
      name: 'Projecting Mount',
      description: 'Projects outwards from a wall.',
      art: InstallationArt.projecting,
      icon: Icons.open_in_full,
      code: flangeBracket,
    ),
    InstallationChoice(
      name: 'Single Pole',
      description: 'Supported by one central pole.',
      art: InstallationArt.singlePole,
      icon: Icons.signpost_outlined,
      code: singlePole,
    ),
  ];

  static bool isNlbBox(Board? b) => b != null && b.isNlbBoxFrame;

  /// Codes hidden from NEW selections of a media type (still valid on a saved
  /// record that already carries them).
  static const _hiddenForNew = <String, Set<String>>{
    foamVinyl: {directWall},
  };

  /// Acrylic offers Wall Mount only.
  static const _onlyForNew = <String, List<String>>{
    clearAcrylic: [wallMount],
  };

  /// Installation codes offered when choosing for [b] now.
  static List<String> newInstallationCodes(Board b) {
    if (isGsbDouble(b)) return gsbDoubleInstallationCodes;
    if (isNlbBox(b)) return nlbBoxInstallationCodes;
    final only = _onlyForNew[b.mediaCode];
    if (only != null) return only;
    final m = media(b.mediaCode);
    if (m == null) return const [];
    final hidden = _hiddenForNew[b.mediaCode] ?? const <String>{};
    return [for (final c in m.installations) if (!hidden.contains(c)) c];
  }

  /// Same list as [newInstallationCodes] but as [InstallationType]s, for
  /// screens that still render the generic list.
  static List<InstallationType> selectableInstallations(Board b) => [
    for (final c in newInstallationCodes(b))
      if (installation(c) != null) installation(c)!,
  ];

  /// Historic values kept readable on old records; never offered for a new
  /// selection and never converted automatically.
  static const gsbLegacyInstallationCodes = {
    shopFascia,
    wallMount,
    supportPipe,
  };

  /// Validation helper: a historic GSB value stays valid only on the very
  /// record that already carries it; every other combination follows the
  /// normal media contract.
  static bool allowsInstallation(Board b, String? code) {
    if (code == null) return false;
    if (installation(code) == null) return false;
    if (newInstallationCodes(b).contains(code)) return true;
    // A historic value stays valid only on the record that carries it.
    final m = media(b.mediaCode);
    return code == b.installationCode &&
        m != null &&
        m.installations.contains(code);
  }

  /// Label shown in the Installation Type step header. GSB Double Side uses
  /// the five-card wording; every other combination keeps the catalog name.
  static String installationLabel(Board b, String? code) {
    if (isGsbDouble(b)) {
      for (final choice in gsbDoubleChoices) {
        if (choice.code != null && choice.code == code) return choice.name;
      }
    }
    if (isNlbBox(b)) {
      for (final choice in nlbBoxChoices) {
        if (choice.code != null && choice.code == code) return choice.name;
      }
    }
    final legacy = legacyInstallationOf(b);
    if (legacy != null && legacy.code == code) {
      return '${legacy.name} (saved earlier)';
    }
    return installation(code)?.name ?? 'Depends on media';
  }

  /// Historic selection no longer offered among the new cards, if any.
  static InstallationType? legacyInstallationOf(Board b) {
    final code = b.installationCode;
    if (code == null) return null;
    final m = media(b.mediaCode);
    if (m == null || !m.installations.contains(code)) return null;
    if (newInstallationCodes(b).contains(code)) return null;
    return installation(code);
  }

  static MediaType? media(String? code) {
    for (final m in allMediaTypes) {
      if (m.code == code) return m;
    }
    return null;
  }

  static InstallationType? installation(String? code) {
    for (final i in installationTypes) {
      if (i.code == code) return i;
    }
    return null;
  }

  static List<InstallationType> installationsFor(String? mediaCode) {
    final m = media(mediaCode);
    if (m == null) return const [];
    return m.installations
        .map(installation)
        .whereType<InstallationType>()
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Dynamic questions
  // ---------------------------------------------------------------------------

  static const _common = <SiteQuestion>[
    SiteQuestion(
      id: 'existing_board',
      label: 'Is there an existing board at this location?',
      type: QuestionType.yesNo,
    ),
    SiteQuestion(
      id: 'remove_existing',
      label: 'Existing board removal required?',
      type: QuestionType.yesNo,
      showIfId: 'existing_board',
      showIfValue: true,
    ),
    SiteQuestion(
      id: 'access_method',
      label: 'Access method for installation',
      type: QuestionType.choice,
      options: ['Ladder', 'Scaffolding', 'Crane / Hydra', 'Direct reach'],
    ),
    SiteQuestion(
      id: 'owner_permission',
      label: 'Shop owner permission obtained?',
      type: QuestionType.yesNo,
    ),
  ];

  /// Fabrication questions shared by single- and double-sided standees.
  /// Kept configurable: not every standee uses the same base or support.
  static const _standeeCommon = <SiteQuestion>[
    SiteQuestion(
      id: 'base_type',
      label: 'Base type',
      type: QuestionType.choice,
      options: [
        'Flat MS base plate',
        'Weighted / sand base',
        'Water-fill base',
        'Ground-fixed (bolted / embedded)',
      ],
    ),
    SiteQuestion(
      id: 'base_width',
      label: 'Base width',
      type: QuestionType.number,
      unit: 'ft',
    ),
    SiteQuestion(
      id: 'base_depth',
      label: 'Base depth',
      type: QuestionType.number,
      unit: 'ft',
    ),
    SiteQuestion(
      id: 'support_structure',
      label: 'Support structure',
      type: QuestionType.choice,
      options: [
        'Twin side posts',
        'Single centre pole',
        'A-frame',
        'Box frame',
      ],
    ),
    SiteQuestion(
      id: 'standee_material',
      label: 'Board material',
      type: QuestionType.choice,
      options: [
        'Flex on MS frame',
        'ACP sheet',
        'Sunboard',
        'GI sheet',
        'Acrylic',
      ],
    ),
    SiteQuestion(
      id: 'placement_location',
      label: 'Placement location',
      type: QuestionType.text,
      hint: 'e.g. Footpath, left of shop entrance',
    ),
    SiteQuestion(
      id: 'indoor_outdoor',
      label: 'Indoor / Outdoor',
      type: QuestionType.choice,
      options: ['Outdoor', 'Indoor'],
    ),
    SiteQuestion(
      id: 'standee_remarks',
      label: 'Standee remarks',
      type: QuestionType.text,
      required: false,
    ),
  ];

  static const _media = <String, List<SiteQuestion>>{
    gsb: [
      SiteQuestion(
        id: 'power_available',
        label: 'Electrical point available within 10 ft?',
        type: QuestionType.yesNo,
      ),
      SiteQuestion(
        id: 'power_distance',
        label: 'Distance to nearest power point',
        type: QuestionType.number,
        unit: 'ft',
        showIfId: 'power_available',
        showIfValue: false,
      ),
      SiteQuestion(
        id: 'light_type',
        label: 'Illumination type',
        type: QuestionType.choice,
        options: ['LED modules', 'LED strip', 'Tube lights'],
      ),
      SiteQuestion(
        id: 'timer_required',
        label: 'Timer switch required?',
        type: QuestionType.yesNo,
        required: false,
      ),
    ],
    nlb: [
      SiteQuestion(
        id: 'front_light',
        label: 'Front focus lights required?',
        type: QuestionType.yesNo,
      ),
      SiteQuestion(
        id: 'frame_material',
        label: 'Frame material',
        type: QuestionType.choice,
        options: ['MS square tube', 'Aluminium', 'Wooden'],
      ),
    ],
    acp: [
      SiteQuestion(
        id: 'letter_type',
        label: '3D letter type',
        type: QuestionType.choice,
        options: ['Acrylic LED letters', 'Non-lit acrylic', 'SS letters'],
      ),
      SiteQuestion(
        id: 'letter_height',
        label: 'Main letter height',
        type: QuestionType.number,
        unit: 'in',
      ),
      SiteQuestion(
        id: 'acp_colour',
        label: 'ACP base colour',
        type: QuestionType.choice,
        options: ['Brand red', 'White', 'Silver', 'Black'],
      ),
    ],
    flange: [
      SiteQuestion(
        id: 'sides',
        label: 'Board sides',
        type: QuestionType.choice,
        options: ['Single side', 'Double side'],
      ),
      SiteQuestion(
        id: 'power_available',
        label: 'Electrical point available within 10 ft?',
        type: QuestionType.yesNo,
      ),
    ],
    vinyl: [
      SiteQuestion(
        id: 'surface',
        label: 'Pasting surface',
        type: QuestionType.choice,
        options: ['Glass', 'Rolling shutter', 'Door', 'Wall'],
      ),
      SiteQuestion(
        id: 'vinyl_type',
        label: 'Vinyl type',
        type: QuestionType.choice,
        options: ['One-way vision', 'Opaque vinyl', 'Frosted film'],
      ),
      SiteQuestion(
        id: 'surface_clean',
        label: 'Surface clean and dry?',
        type: QuestionType.yesNo,
      ),
    ],
    wallPainting: [
      SiteQuestion(
        id: 'wall_surface',
        label: 'Wall surface condition',
        type: QuestionType.choice,
        options: ['Plastered', 'Unplastered', 'Old paint', 'Damp / seepage'],
      ),
      SiteQuestion(
        id: 'primer_required',
        label: 'Putty / primer required?',
        type: QuestionType.yesNo,
      ),
    ],
    singleStandee: [
      SiteQuestion(
        id: 'overall_height',
        label: 'Overall standee height (ground to top)',
        type: QuestionType.number,
        unit: 'ft',
      ),
      SiteQuestion(
        id: 'display_panel_height',
        label: 'Display panel (artwork) height',
        type: QuestionType.number,
        unit: 'ft',
        required: false,
        hint: 'Leave empty when it equals the standee height',
      ),
      ..._standeeCommon,
    ],
    doubleStandee: [
      SiteQuestion(
        id: 'overall_height',
        label: 'Overall standee height (ground to top)',
        type: QuestionType.number,
        unit: 'ft',
      ),
      ..._standeeCommon,
      SiteQuestion(
        id: 'front_face',
        label: 'Front face details (artwork / brand / direction)',
        type: QuestionType.text,
      ),
      SiteQuestion(
        id: 'back_face',
        label: 'Back face details (artwork / brand / direction)',
        type: QuestionType.text,
      ),
    ],
    foamVinyl: [
      SiteQuestion(
        id: 'surface',
        label: 'Mounting surface',
        type: QuestionType.choice,
        options: ['Wall', 'Glass', 'Door', 'Shutter'],
      ),
      SiteQuestion(
        id: 'indoor_outdoor',
        label: 'Indoor / Outdoor',
        type: QuestionType.choice,
        options: ['Indoor', 'Outdoor'],
      ),
    ],
    clearAcrylic: [
      SiteQuestion(
        id: 'standoff_mounting',
        label: 'Standoff (spacer) mounting?',
        type: QuestionType.yesNo,
      ),
      SiteQuestion(
        id: 'graphics_type',
        label: 'Graphics',
        type: QuestionType.choice,
        options: ['Reverse printed', 'Vinyl applied', 'Plain / etched'],
      ),
    ],
    sandwichBoard: [
      SiteQuestion(
        id: 'placement_location',
        label: 'Placement location',
        type: QuestionType.text,
        hint: 'e.g. Footpath, left of shop entrance',
      ),
      SiteQuestion(
        id: 'indoor_outdoor',
        label: 'Indoor / Outdoor',
        type: QuestionType.choice,
        options: ['Outdoor', 'Indoor'],
      ),
    ],
    oneWayVision: [
      SiteQuestion(
        id: 'surface_clean',
        label: 'Glass clean and dry?',
        type: QuestionType.yesNo,
      ),
    ],
    plainVinyl: [
      SiteQuestion(
        id: 'surface',
        label: 'Pasting surface',
        type: QuestionType.choice,
        options: ['Glass', 'Rolling shutter', 'Door', 'Wall'],
      ),
      SiteQuestion(
        id: 'surface_clean',
        label: 'Surface clean and dry?',
        type: QuestionType.yesNo,
      ),
    ],
    acp2d: [
      SiteQuestion(
        id: 'acp_colour',
        label: 'ACP base colour',
        type: QuestionType.choice,
        options: ['Brand red', 'White', 'Silver', 'Black'],
      ),
    ],
    acp2dDouble: [
      SiteQuestion(
        id: 'acp_colour',
        label: 'ACP base colour',
        type: QuestionType.choice,
        options: ['Brand red', 'White', 'Silver', 'Black'],
      ),
    ],
    acp3dDouble: [
      SiteQuestion(
        id: 'letter_type',
        label: '3D letter type',
        type: QuestionType.choice,
        options: ['Acrylic LED letters', 'Non-lit acrylic', 'SS letters'],
      ),
      SiteQuestion(
        id: 'letter_height',
        label: 'Main letter height',
        type: QuestionType.number,
        unit: 'in',
      ),
    ],
    mdfGsb: [
      SiteQuestion(
        id: 'power_available',
        label: 'Electrical point available within 10 ft?',
        type: QuestionType.yesNo,
      ),
      SiteQuestion(
        id: 'indoor_outdoor',
        label: 'Indoor / Outdoor (MDF needs site review outdoors)',
        type: QuestionType.choice,
        options: ['Indoor', 'Outdoor - covered', 'Outdoor - exposed'],
      ),
    ],
    mdfGsbDouble: [
      SiteQuestion(
        id: 'power_available',
        label: 'Electrical point available within 10 ft?',
        type: QuestionType.yesNo,
      ),
      SiteQuestion(
        id: 'indoor_outdoor',
        label: 'Indoor / Outdoor (MDF needs site review outdoors)',
        type: QuestionType.choice,
        options: ['Indoor', 'Outdoor - covered', 'Outdoor - exposed'],
      ),
    ],
  };

  static const _installation = <String, List<SiteQuestion>>{
    supportPipe: [
      SiteQuestion(
        id: 'mount_height',
        label: 'Board bottom height from ground',
        type: QuestionType.number,
        unit: 'ft',
      ),
      SiteQuestion(
        id: 'pipe_count',
        label: 'Number of support pipes',
        type: QuestionType.number,
      ),
      SiteQuestion(
        id: 'pipe_length',
        label: 'Support pipe length',
        type: QuestionType.number,
        unit: 'ft',
      ),
    ],
    shopFascia: [
      SiteQuestion(
        id: 'fascia_material',
        label: 'Fascia material',
        type: QuestionType.choice,
        options: ['Concrete', 'Brick', 'Metal sheet', 'Wooden'],
      ),
      SiteQuestion(
        id: 'shutter_height',
        label: 'Shutter top height from ground',
        type: QuestionType.number,
        unit: 'ft',
      ),
      SiteQuestion(
        id: 'neighbour_clearance',
        label: 'Clear of neighbouring boards?',
        type: QuestionType.yesNo,
      ),
    ],
    wallMount: [
      SiteQuestion(
        id: 'wall_type',
        label: 'Wall type',
        type: QuestionType.choice,
        options: ['Brick', 'Concrete', 'Metal sheet', 'Stone'],
      ),
      SiteQuestion(
        id: 'wall_condition',
        label: 'Wall condition',
        type: QuestionType.choice,
        options: ['Good', 'Average', 'Poor'],
      ),
      SiteQuestion(
        id: 'mount_height',
        label: 'Board bottom height from ground',
        type: QuestionType.number,
        unit: 'ft',
      ),
    ],
    doublePole: [
      SiteQuestion(
        id: 'pole_height',
        label: 'Clear height below board (pole height)',
        type: QuestionType.number,
        unit: 'ft',
        hint: 'Ground to board bottom',
      ),
      SiteQuestion(
        id: 'pole_gap',
        label: 'Distance between poles',
        type: QuestionType.number,
        unit: 'ft',
      ),
      SiteQuestion(
        id: 'ground_type',
        label: 'Ground type at pole location',
        type: QuestionType.choice,
        options: ['Soil', 'Concrete', 'Tar road', 'Footpath tiles'],
      ),
      SiteQuestion(
        id: 'foundation_depth',
        label: 'Foundation pit depth possible',
        type: QuestionType.number,
        unit: 'ft',
      ),
      SiteQuestion(
        id: 'pole_material',
        label: 'Pole material',
        type: QuestionType.choice,
        options: ['MS pipe', 'GI pipe', 'MS channel'],
      ),
      SiteQuestion(
        id: 'excavation_permission',
        label: 'Excavation permission available?',
        type: QuestionType.yesNo,
      ),
    ],
    singlePole: [
      SiteQuestion(
        id: 'pole_height',
        label: 'Clear height below board (pole height)',
        type: QuestionType.number,
        unit: 'ft',
      ),
      SiteQuestion(
        id: 'pole_diameter',
        label: 'Pole diameter',
        type: QuestionType.choice,
        options: ['4 inch', '6 inch', '8 inch'],
      ),
      SiteQuestion(
        id: 'ground_type',
        label: 'Ground type at pole location',
        type: QuestionType.choice,
        options: ['Soil', 'Concrete', 'Tar road', 'Footpath tiles'],
      ),
      SiteQuestion(
        id: 'foundation_depth',
        label: 'Foundation pit depth possible',
        type: QuestionType.number,
        unit: 'ft',
      ),
    ],
    rooftop: [
      SiteQuestion(
        id: 'building_floors',
        label: 'Number of floors (incl. ground)',
        type: QuestionType.number,
      ),
      SiteQuestion(
        id: 'roof_type',
        label: 'Roof type',
        type: QuestionType.choice,
        options: ['RCC slab', 'Metal sheet', 'Tiles'],
      ),
      SiteQuestion(
        id: 'structure_height',
        label: 'Structure height above roof',
        type: QuestionType.number,
        unit: 'ft',
      ),
      SiteQuestion(
        id: 'terrace_access',
        label: 'Terrace access available?',
        type: QuestionType.yesNo,
      ),
      SiteQuestion(
        id: 'wind_exposure',
        label: 'Wind exposure',
        type: QuestionType.choice,
        options: ['Low', 'Medium', 'High'],
      ),
      SiteQuestion(
        id: 'building_noc',
        label: 'Building owner NOC available?',
        type: QuestionType.yesNo,
      ),
    ],
    flangeBracket: [
      SiteQuestion(
        id: 'mount_height',
        label: 'Board bottom height from ground',
        type: QuestionType.number,
        unit: 'ft',
      ),
      SiteQuestion(
        id: 'projection',
        label: 'Projection from wall',
        type: QuestionType.number,
        unit: 'ft',
      ),
      SiteQuestion(
        id: 'wall_type',
        label: 'Wall type',
        type: QuestionType.choice,
        options: ['Brick', 'Concrete', 'Metal sheet', 'Stone'],
      ),
    ],
    directWall: [
      SiteQuestion(
        id: 'mount_height',
        label: 'Artwork bottom height from ground',
        type: QuestionType.number,
        unit: 'ft',
      ),
      SiteQuestion(
        id: 'wall_obstruction',
        label: 'Wall free of pipes / wires / obstructions?',
        type: QuestionType.yesNo,
      ),
    ],
    glassPasting: [
      SiteQuestion(
        id: 'panel_count',
        label: 'Number of glass / shutter panels',
        type: QuestionType.number,
      ),
      SiteQuestion(
        id: 'mount_height',
        label: 'Artwork bottom height from ground',
        type: QuestionType.number,
        unit: 'ft',
        required: false,
      ),
    ],
    freeStanding: [
      SiteQuestion(
        id: 'panel_bottom_height',
        label: 'Display panel bottom height from ground',
        type: QuestionType.number,
        unit: 'ft',
        hint: 'Clear height below the board',
      ),
      SiteQuestion(
        id: 'standee_surface',
        label: 'Ground surface at standee location',
        type: QuestionType.choice,
        options: [
          'Footpath tiles',
          'Concrete',
          'Soil',
          'Tar road',
          'Shop floor',
        ],
      ),
      SiteQuestion(
        id: 'pedestrian_clearance',
        label: 'Leaves walking space / does not block entry?',
        type: QuestionType.yesNo,
      ),
    ],
  };

  /// Questions for a media + installation combination (deduplicated by id,
  /// installation-specific first so the structure questions lead).
  static List<SiteQuestion> questionsFor(
    String? mediaCode,
    String? installationCode,
  ) {
    final result = <SiteQuestion>[];
    final seen = <String>{};
    void addAll(Iterable<SiteQuestion> qs) {
      for (final q in qs) {
        if (seen.add(q.id)) result.add(q);
      }
    }

    addAll(_installation[installationCode] ?? const []);
    addAll(_media[mediaCode] ?? const []);
    addAll(_common);
    return result;
  }

  // ---------------------------------------------------------------------------
  // Per-unit installation (reuses SignageUnit.installationCode overrides)
  // ---------------------------------------------------------------------------

  /// Installation used for group-level questions and summaries: the group's
  /// own code, else the first unit's effective code. Never written anywhere.
  static String? primaryInstallation(Board b) {
    if (b.installationCode != null) return b.installationCode;
    for (final u in b.activeUnits) {
      final c = b.installationOf(u);
      if (c != null) return c;
    }
    return null;
  }

  /// True when the active units of [b] do not all share one installation.
  static bool hasMixedInstallations(Board b) {
    if (b.activeUnits.length < 2) return false;
    final codes = {for (final u in b.activeUnits) b.installationOf(u)};
    return codes.length > 1;
  }

  /// Every active unit resolves to an installation valid for the media.
  static bool installationComplete(Board b) {
    if (media(b.mediaCode) == null) return false;
    final units = b.activeUnits;
    if (units.isEmpty) return allowsInstallation(b, b.installationCode);
    return units.every((u) {
      final c = b.installationOf(u);
      if (c == null) return false;
      // A historic value is valid on the record that already carries it.
      return allowsInstallation(b, c) ||
          (u.installationCode == c &&
              (media(b.mediaCode)?.installations.contains(c) ?? false));
    });
  }

  /// Why physical board [u] cannot be drawn / previewed yet (null = ready).
  ///
  /// Illustrative drawing readiness depends only on THIS board: the media,
  /// its own effective installation (unit override, else the group's) and its
  /// own size. Site questions, photos, suggestions and other boards / media
  /// groups never block it.
  static String? unitDrawingBlocker(Board b, SignageUnit u) {
    final name = unitName(b, u);
    if (media(b.mediaCode) == null) return 'Select the media type';
    final inst = b.installationOf(u);
    if (inst == null) return '$name: select the installation type';
    if (!allowsInstallation(b, inst) &&
        !(media(b.mediaCode)?.installations.contains(inst) ?? false)) {
      return '$name: installation not valid for this media';
    }
    if (!b.unitHasSize(u)) return '$name: enter width and height';
    return null;
  }

  /// Boards of [b] that can be drawn / previewed.
  static List<SignageUnit> drawingReadyUnits(Board b) => [
    for (final u in b.activeUnits)
      if (unitDrawingBlocker(b, u) == null) u,
  ];

  /// Display text for lists / reports: one name, or "Mixed".
  static String installationSummary(Board b, {String empty = 'Not set'}) {
    if (hasMixedInstallations(b)) {
      final names = [
        for (final c in {for (final u in b.activeUnits) b.installationOf(u)})
          installation(c)?.name ?? 'Not set',
      ];
      return 'Mixed (${names.join(' / ')})';
    }
    return installation(primaryInstallation(b))?.name ?? empty;
  }

  // ---------------------------------------------------------------------------
  // Media-based board names (display only; identity is always the id)
  // ---------------------------------------------------------------------------

  /// "GSB Single", "GSB Double", "NLB Single", "NLB Box", "Acrylic", ...
  static String mediaNameLabel(Board b) {
    final m = media(b.mediaCode);
    if (m == null) return 'Board';
    if (m.code == gsb) return b.doubleSided == true ? 'GSB Double' : 'GSB Single';
    if (m.code == nlb) {
      if (b.isNlbBoxFrame) return 'NLB Box';
      if (b.isNlbSingleFrame) return 'NLB Single';
      return 'NLB';
    }
    return m.shortName;
  }

  /// "GSB Single 01" for the unit at its position in the group.
  static String unitName(Board b, SignageUnit u) {
    if (media(b.mediaCode) == null) return b.unitLabel(u);
    final i = b.units.indexWhere((e) => e.id == u.id);
    return '${mediaNameLabel(b)} ${(i < 0 ? 1 : i + 1).toString().padLeft(2, '0')}';
  }

  /// True for a name the app generated itself (never a manual edit).
  static bool isAutoBoardName(String name) {
    final n = name.trim();
    if (n.isEmpty || RegExp(r'^Board \d+$').hasMatch(n)) return true;
    final labels = {
      'GSB Single',
      'GSB Double',
      'NLB Single',
      'NLB Box',
      'NLB',
      for (final m in allMediaTypes) m.shortName,
    };
    final m = RegExp(r'^(.+) (\d{2})$').firstMatch(n);
    return m != null && labels.contains(m.group(1));
  }

  /// First free "<media label> NN" among [others] (names, not identities).
  static String nextBoardName(Board b, Iterable<Board> others) {
    final label = mediaNameLabel(b);
    final used = {
      for (final o in others)
        if (o.id != b.id) o.name.trim(),
    };
    for (var n = 1; ; n++) {
      final name = '$label ${n.toString().padLeft(2, '0')}';
      if (!used.contains(name)) return name;
    }
  }

  // ---------------------------------------------------------------------------
  // Per physical board Site Question answers
  // ---------------------------------------------------------------------------

  /// First active unit of [b] (owner of the historical [Board.answers]).
  static SignageUnit? firstUnit(Board b) =>
      b.activeUnits.isEmpty ? null : b.activeUnits.first;

  /// The ONE answer map of unit [u] (single source of truth per unit):
  /// the group's first unit keeps using [Board.answers] (historical storage,
  /// also read by older records / single-board groups and the legacy 2D
  /// geometry), every other unit uses its own [SignageUnit.siteAnswers].
  /// Answers are therefore never shared between two physical boards.
  static Map<String, dynamic> answersOf(Board b, SignageUnit? u) {
    if (u == null) return b.answers;
    final first = firstUnit(b);
    if (first == null || first.id == u.id) return b.answers;
    return u.siteAnswers;
  }

  /// Questions of unit [u] for its OWN effective installation.
  static List<SiteQuestion> questionsForUnit(Board b, SignageUnit u) =>
      questionsFor(b.mediaCode, b.installationOf(u));

  /// Visible required questions of unit [u] that are not answered yet.
  static List<SiteQuestion> missingAnswersFor(Board b, SignageUnit u) {
    // Effective answers: an earlier checklist answer of the SAME (verified
    // equivalent) question counts, so nothing is asked twice.
    final a = QuestionEquivalence.effectiveSiteAnswers(b, u);
    return [
      for (final q in questionsForUnit(b, u))
        if (q.required && q.isVisible(a) && !q.isAnswered(a)) q,
    ];
  }

  /// True when [q] is installation-specific for installation [inst].
  static bool isInstallationSpecific(String? inst, String id) =>
      (_installation[inst] ?? const []).any((e) => e.id == id);

  /// Section of [q] for unit [u] (its own installation).
  static String questionSectionFor(Board b, SignageUnit u, SiteQuestion q) {
    if (isInstallationSpecific(b.installationOf(u), q.id)) {
      return 'Installation-Specific Questions';
    }
    if ((_media[b.mediaCode] ?? const []).any((e) => e.id == q.id)) {
      return 'Media-Specific Questions';
    }
    return 'Common Site Questions';
  }

  // ---------------------------------------------------------------------------
  // Copy common Site Question answers
  // ---------------------------------------------------------------------------

  /// A question may be carried to another board only when it is genuinely
  /// common: not installation-specific on either side (mounting / structure
  /// details belong to one board) and not a measured value (numbers with a
  /// unit are board-specific dimensions).
  static bool _copyable(
    Board sb,
    SignageUnit su,
    Board tb,
    SignageUnit tu,
    SiteQuestion q,
  ) =>
      // Two units of the SAME board (the quantity entered, e.g. GSB Single 01 and 02) fixed the SAME way are the same kind of
      // job: every answer, installation-specific and measured ones too, is carried over (the person can still change it).
      (sb.id == tb.id && sb.installationOf(su) == tb.installationOf(tu)) ||
      (!isInstallationSpecific(sb.installationOf(su), q.id) &&
          !isInstallationSpecific(tb.installationOf(tu), q.id) &&
          !(q.type == QuestionType.number && q.unit != null));

  /// Same canonical id AND same definition (type, unit, choices, condition).
  static bool sameQuestionDefinition(SiteQuestion a, SiteQuestion b) =>
      a.id == b.id &&
      a.type == b.type &&
      a.unit == b.unit &&
      a.showIfId == b.showIfId &&
      a.showIfValue == b.showIfValue &&
      a.options.length == b.options.length &&
      [for (var i = 0; i < a.options.length; i++) a.options[i] == b.options[i]]
          .every((e) => e);

  /// Section of a question for [b]: installation-specific, media-specific
  /// or common (same precedence as [questionsFor]).
  static String questionSection(Board b, SiteQuestion q) {
    final inst = primaryInstallation(b);
    if ((_installation[inst] ?? const []).any((e) => e.id == q.id)) {
      return 'Installation-Specific Questions';
    }
    if ((_media[b.mediaCode] ?? const []).any((e) => e.id == q.id)) {
      return 'Media-Specific Questions';
    }
    return 'Common Site Questions';
  }

  /// Picks the source unit for automatic carry-over of common answers into
  /// unit [tu] of [tb]: only when the target has not answered any common
  /// question yet, and every candidate source agrees on the shared values.
  /// Conflicting sources are returned (never auto-picked).
  static ({
    Board? board,
    SignageUnit? unit,
    List<(Board, SignageUnit)> conflicting,
  })
  autoFillSourceForUnit(Board tb, SignageUnit tu, Iterable<Board> boards) {
    const none = (
      board: null,
      unit: null,
      conflicting: <(Board, SignageUnit)>[],
    );
    final cands = <(Board, SignageUnit), CommonAnswerPlan>{};
    for (final ob in boards) {
      if (media(ob.mediaCode) == null) continue;
      for (final ou in ob.activeUnits) {
        if (ob.id == tb.id && ou.id == tu.id) continue;
        final p = planUnitAnswers(ob, ou, tb, tu);
        // Target already has common answers of its own: never auto-fill.
        if (p.wouldOverwrite.isNotEmpty) return none;
        if (p.toCopy.isNotEmpty) cands[(ob, ou)] = p;
      }
    }
    if (cands.isEmpty) return none;
    final seen = <String, Object?>{};
    final owner = <String, (Board, SignageUnit)>{};
    final conflicting = <(Board, SignageUnit)>{};
    for (final e in cands.entries) {
      final a = answersOf(e.key.$1, e.key.$2);
      for (final q in e.value.toCopy) {
        final v = a[q.id];
        if (seen.containsKey(q.id) && '${seen[q.id]}' != '$v') {
          conflicting
            ..add(owner[q.id]!)
            ..add(e.key);
        } else {
          seen[q.id] = v;
          owner[q.id] = e.key;
        }
      }
    }
    if (conflicting.isNotEmpty) {
      return (board: null, unit: null, conflicting: conflicting.toList());
    }
    final best = cands.entries.reduce(
      (a, b) => b.value.toCopy.length > a.value.toCopy.length ? b : a,
    );
    return (
      board: best.key.$1,
      unit: best.key.$2,
      conflicting: const <(Board, SignageUnit)>[],
    );
  }

  /// Board-level wrapper (first units) kept for existing callers.
  static ({Board? source, List<Board> conflicting}) autoFillSource(
    Board target,
    Iterable<Board> others,
  ) {
    final tu = firstUnit(target);
    if (tu == null) return (source: null, conflicting: const []);
    final r = autoFillSourceForUnit(
      target,
      tu,
      others.where((o) => o.id != target.id),
    );
    return (
      source: r.board,
      conflicting: [
        for (final b in {for (final c in r.conflicting) c.$1}) b,
      ],
    );
  }

  /// Plan for copying answers from unit [su] of [sb] to unit [tu] of [tb].
  /// Matches by canonical id AND identical definition, for the units' own
  /// installations; installation-specific and measured questions are never
  /// common. Nothing is written.
  static CommonAnswerPlan planUnitAnswers(
    Board sb,
    SignageUnit su,
    Board tb,
    SignageUnit tu,
  ) {
    final copy = <SiteQuestion>[];
    final overwrite = <SiteQuestion>[];
    final notCommon = <SiteQuestion>[];
    final manual = <SiteQuestion>[];
    final sa = answersOf(sb, su);
    final ta = answersOf(tb, tu);
    final sourceQs = {for (final q in questionsForUnit(sb, su)) q.id: q};
    for (final tq in questionsForUnit(tb, tu)) {
      if (!tq.isVisible(ta)) continue;
      final sq = sourceQs[tq.id];
      if (sq == null ||
          !sameQuestionDefinition(sq, tq) ||
          !_copyable(sb, su, tb, tu, tq)) {
        if (tq.required && !tq.isAnswered(ta)) notCommon.add(tq);
        continue;
      }
      if (!sq.isVisible(sa) || !sq.isAnswered(sa)) {
        if (tq.required && !tq.isAnswered(ta)) manual.add(tq);
        continue;
      }
      (tq.isAnswered(ta) ? overwrite : copy).add(tq);
    }
    // Checklist-only questions that are common to both boards: same id and
    // answer format, not installation specific, not evidence, not already a
    // Site Question (those are handled above).
    final cCopy = <ChecklistQuestion>[];
    final cOver = <ChecklistQuestion>[];
    final srcCl = {
      for (final q in SiteChecklists.questionsFor(
        sb.mediaCode,
        sb.installationOf(su),
      ))
        q.id: q,
    };
    final mapped = QuestionEquivalence.mappedChecklistIds(tb, tu);
    for (final tq in SiteChecklists.questionsFor(
      tb.mediaCode,
      tb.installationOf(tu),
    )) {
      if (mapped.contains(tq.id) ||
          tq.installations != null ||
          tq.type == ChecklistResponseType.photoEvidence) {
        continue;
      }
      final sq = srcCl[tq.id];
      if (sq == null ||
          sq.installations != null ||
          sq.type != tq.type ||
          sq.options.length != tq.options.length ||
          !sq.options.every(tq.options.contains)) {
        continue;
      }
      final sr = su.checklist[tq.id];
      if (!sq.isAnswered(sr) || (sr?.isNa ?? false) && !tq.allowNa) continue;
      (tq.isAnswered(tu.checklist[tq.id]) ? cOver : cCopy).add(tq);
    }
    return CommonAnswerPlan(
      toCopy: copy,
      wouldOverwrite: overwrite,
      notCommon: notCommon,
      sourceUnanswered: manual,
      toCopyChecklist: cCopy,
      wouldOverwriteChecklist: cOver,
    );
  }

  /// Board-level wrapper (first units) kept for existing callers.
  static CommonAnswerPlan planCommonAnswers(Board source, Board target) {
    final su = firstUnit(source), tu = firstUnit(target);
    if (su == null || tu == null) {
      return const CommonAnswerPlan(
        toCopy: [],
        wouldOverwrite: [],
        notCommon: [],
        sourceUnanswered: [],
      );
    }
    return planUnitAnswers(source, su, target, tu);
  }

  /// Visible required questions not answered yet, over EVERY active
  /// physical board of [board] (each with its own installation and its own
  /// answers). A question missing on two boards is listed twice.
  static List<SiteQuestion> missingAnswers(Board board) {
    if (board.activeUnits.isEmpty) {
      return questionsFor(board.mediaCode, primaryInstallation(board))
          .where(
            (q) =>
                q.required &&
                q.isVisible(board.answers) &&
                !q.isAnswered(board.answers),
          )
          .toList();
    }
    return [
      for (final u in board.activeUnits) ...missingAnswersFor(board, u),
    ];
  }

  static String answerText(SiteQuestion q, Object? value) {
    if (value == null) return '—';
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is num) {
      final s = value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toStringAsFixed(2);
      return q.unit == null ? s : '$s ${q.unit}';
    }
    return '$value';
  }

  /// Rejection reasons offered to reviewers.
  static const rejectionReasons = [
    'Photos unclear / insufficient',
    'Measurement mismatch',
    'Wrong media type',
    'Installation not feasible',
    'Missing site details',
    'Permission / NOC issue',
  ];

  static const photoLabels = [
    'Front view',
    'Left angle',
    'Right angle',
    'Back view',
    'Close-up',
    'Long shot',
    'Surroundings',
  ];
}
