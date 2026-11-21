import 'package:flutter/material.dart';

import '../models/models.dart';

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
      thicknessMm: 5,
      shortName: 'Foam Vinyl',
      name: 'Foam Board with Vinyl',
      description: 'Printed vinyl on a thin foam / sun-board substrate.',
      icon: Icons.layers_outlined,
      depthFt: 0.02,
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
      shortName: 'One-Way',
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

  /// Visible required questions that have not been answered yet.
  static List<SiteQuestion> missingAnswers(Board board) {
    return questionsFor(board.mediaCode, board.installationCode)
        .where(
          (q) =>
              q.required &&
              q.isVisible(board.answers) &&
              !q.isAnswered(board.answers),
        )
        .toList();
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
    'Close-up',
    'Long shot',
    'Surroundings',
  ];
}
