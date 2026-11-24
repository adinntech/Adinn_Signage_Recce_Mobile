import 'package:flutter/material.dart';

import '../../../data/catalog/signage_catalog.dart';
import '../../../data/models/enums.dart' show QuestionType;

/// The media catalog as the server sends it (`GET /api/v1/catalog`): media types, installation methods and the site questions.
/// The server is the master (the admin edits it); [CatalogData.builtIn] is the copy shipped inside the app, used until the first read
/// succeeds and whenever the phone has never been online.

/// Icon names the catalog may use. The server accepts exactly these; the admin screens offer them; an unknown name shows a plain icon.
const catalogIcons = <String, IconData>{
  'lightbulb_outline': Icons.lightbulb_outline,
  'crop_landscape': Icons.crop_landscape,
  'crop_square': Icons.crop_square,
  'rectangle_outlined': Icons.rectangle_outlined,
  'layers_outlined': Icons.layers_outlined,
  'text_fields': Icons.text_fields,
  'text_rotation_none': Icons.text_rotation_none,
  'flip': Icons.flip,
  'flag_outlined': Icons.flag_outlined,
  'blur_on': Icons.blur_on,
  'change_history': Icons.change_history,
  'window_outlined': Icons.window_outlined,
  'door_sliding_outlined': Icons.door_sliding_outlined,
  'storefront_outlined': Icons.storefront_outlined,
  'wallpaper': Icons.wallpaper,
  'wallpaper_outlined': Icons.wallpaper_outlined,
  'format_paint_outlined': Icons.format_paint_outlined,
  'signpost_outlined': Icons.signpost_outlined,
  'roofing_outlined': Icons.roofing_outlined,
  'open_in_full': Icons.open_in_full,
  'view_week_outlined': Icons.view_week_outlined,
  'view_quilt_outlined': Icons.view_quilt_outlined,
  'view_column_outlined': Icons.view_column_outlined,
  'view_agenda': Icons.view_agenda,
  'view_agenda_outlined': Icons.view_agenda_outlined,
  'handyman_outlined': Icons.handyman_outlined,
  'construction': Icons.construction,
  'straighten': Icons.straighten,
  'inventory_2_outlined': Icons.inventory_2_outlined,
  'category_outlined': Icons.category_outlined,
  'light_mode_outlined': Icons.light_mode_outlined,
  'architecture': Icons.architecture,
};

IconData catalogIcon(String key) => catalogIcons[key] ?? Icons.category_outlined;

String _iconKeyOf(IconData d) => catalogIcons.entries.firstWhere((e) => e.value.codePoint == d.codePoint, orElse: () => const MapEntry('category_outlined', Icons.category_outlined)).key;

Color hexColor(String hex) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return v == null ? const Color(0xFF455A64) : Color(0xFF000000 | v);
}

String colorHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

String _s(dynamic v, [String d = '']) => v == null ? d : v.toString();
double _d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
int _i(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
List<String> _sl(dynamic v) => v is List ? [for (final e in v) e.toString()] : const [];

class CatalogMedia {
  const CatalogMedia({
    required this.code,
    required this.shortName,
    required this.name,
    this.description = '',
    this.icon = 'category_outlined',
    this.color = '#455A64',
    this.illuminated = false,
    this.sidedness = 'SINGLE',
    this.depthFt = 0,
    this.thicknessMm = 0,
    this.template = '',
    this.installations = const [],
    this.legacy = false,
    this.active = true,
    this.order = 0,
  });

  final String code;
  final String shortName;
  final String name;
  final String description;
  final String icon;
  final String color;
  final bool illuminated;
  final String sidedness; // SINGLE | DOUBLE | SELECTABLE
  final double depthFt;
  final double thicknessMm;
  final String template;
  final List<String> installations;
  final bool legacy;
  final bool active;
  final int order;

  /// Offered for a new board.
  bool get offered => active && !legacy;

  factory CatalogMedia.fromJson(Map<String, dynamic> j) => CatalogMedia(
        code: _s(j['code']),
        shortName: _s(j['shortName']),
        name: _s(j['name']),
        description: _s(j['description']),
        icon: _s(j['icon'], 'category_outlined'),
        color: _s(j['color'], '#455A64'),
        illuminated: j['illuminated'] == true,
        sidedness: _s(j['sidedness'], 'SINGLE'),
        depthFt: _d(j['depthFt']),
        thicknessMm: _d(j['thicknessMm']),
        template: _s(j['template']),
        installations: _sl(j['installations']),
        legacy: j['legacy'] == true,
        active: j['active'] != false,
        order: _i(j['order']),
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'shortName': shortName,
        'name': name,
        'description': description,
        'icon': icon,
        'color': color,
        'illuminated': illuminated,
        'sidedness': sidedness,
        'depthFt': depthFt,
        'thicknessMm': thicknessMm,
        'template': template,
        'installations': installations,
        'legacy': legacy,
        'active': active,
        'order': order,
      };

  /// The card the media type grid draws.
  MediaType toMediaType() => MediaType(
        code: code,
        shortName: shortName,
        name: name,
        description: description,
        icon: catalogIcon(icon),
        depthFt: depthFt,
        illuminated: illuminated,
        installations: installations,
        color: hexColor(color),
        legacy: legacy,
        sidedness: switch (sidedness) {
          'DOUBLE' => MediaSidedness.double,
          'SELECTABLE' => MediaSidedness.selectable,
          _ => MediaSidedness.single,
        },
        template: template,
        thicknessMm: thicknessMm,
      );
}

class CatalogInstallation {
  const CatalogInstallation({required this.code, required this.name, this.description = '', this.icon = 'category_outlined', this.active = true, this.order = 0});

  final String code;
  final String name;
  final String description;
  final String icon;
  final bool active;
  final int order;

  factory CatalogInstallation.fromJson(Map<String, dynamic> j) => CatalogInstallation(
        code: _s(j['code']),
        name: _s(j['name']),
        description: _s(j['description']),
        icon: _s(j['icon'], 'category_outlined'),
        active: j['active'] != false,
        order: _i(j['order']),
      );

  Map<String, dynamic> toJson() => {'code': code, 'name': name, 'description': description, 'icon': icon, 'active': active, 'order': order};

  InstallationType toInstallationType() => InstallationType(code: code, name: name, description: description, icon: catalogIcon(icon));
}

class CatalogQuestion {
  const CatalogQuestion({
    required this.id,
    required this.label,
    required this.type,
    this.uid = '',
    this.scope = 'COMMON',
    this.scopeCode = '',
    this.options = const [],
    this.unit,
    this.required = true,
    this.hint,
    this.showIfId,
    this.showIfValue,
    this.active = true,
    this.order = 0,
  });

  final String uid;
  final String scope; // COMMON | MEDIA | INSTALLATION
  final String scopeCode;
  final String id;
  final String label;
  final String type; // TEXT | NUMBER | YES_NO | CHOICE
  final List<String> options;
  final String? unit;
  final bool required;
  final String? hint;
  final String? showIfId;
  final Object? showIfValue;
  final bool active;
  final int order;

  factory CatalogQuestion.fromJson(Map<String, dynamic> j) => CatalogQuestion(
        uid: _s(j['uid']),
        scope: _s(j['scope'], 'COMMON'),
        scopeCode: _s(j['scopeCode']),
        id: _s(j['id']),
        label: _s(j['label']),
        type: _s(j['type'], 'TEXT'),
        options: _sl(j['options']),
        unit: j['unit'] == null ? null : _s(j['unit']),
        required: j['required'] != false,
        hint: j['hint'] == null ? null : _s(j['hint']),
        showIfId: j['showIfId'] == null ? null : _s(j['showIfId']),
        showIfValue: j['showIfValue'],
        active: j['active'] != false,
        order: _i(j['order']),
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'scope': scope,
        'scopeCode': scopeCode,
        'id': id,
        'label': label,
        'type': type,
        'options': options,
        'unit': unit,
        'required': required,
        'hint': hint,
        'showIfId': showIfId,
        'showIfValue': showIfValue,
        'active': active,
        'order': order,
      };

  QuestionType get kind => switch (type) {
        'NUMBER' => QuestionType.number,
        'YES_NO' => QuestionType.yesNo,
        'CHOICE' => QuestionType.choice,
        _ => QuestionType.text,
      };

  /// The form field the board editor draws (the same widget the older editor uses).
  SiteQuestion toSiteQuestion() => SiteQuestion(id: id, label: label, type: kind, options: options, unit: unit, required: required, hint: hint, showIfId: showIfId, showIfValue: showIfValue);
}

/// `GET /catalog/usage`: boards per media code and per installation code (the admin screens show it and block a delete).
class CatalogUsage {
  const CatalogUsage({this.media = const {}, this.installations = const {}});

  final Map<String, int> media;
  final Map<String, int> installations;

  factory CatalogUsage.fromJson(Map<String, dynamic> j) {
    Map<String, int> counts(dynamic v) => v is Map ? {for (final e in v.entries) e.key.toString(): _i(e.value)} : const {};
    return CatalogUsage(media: counts(j['media']), installations: counts(j['installations']));
  }

  int ofMedia(String code) => media[code] ?? 0;
  int ofInstallation(String code) => installations[code] ?? 0;
}

class CatalogData {
  CatalogData({this.version = 0, List<CatalogMedia> media = const [], List<CatalogInstallation> installations = const [], List<CatalogQuestion> questions = const []})
      : media = List.unmodifiable([...media]..sort((a, b) => a.order.compareTo(b.order))),
        installations = List.unmodifiable([...installations]..sort((a, b) => a.order.compareTo(b.order))),
        questions = List.unmodifiable([...questions]..sort((a, b) => a.order.compareTo(b.order)));

  /// 0 = the copy built into the app (never read from the server).
  final int version;
  final List<CatalogMedia> media;
  final List<CatalogInstallation> installations;
  final List<CatalogQuestion> questions;

  bool get isBuiltIn => version == 0;

  factory CatalogData.fromJson(Map<String, dynamic> j) => CatalogData(
        version: _i(j['version']),
        media: [for (final e in (j['media'] as List? ?? const [])) CatalogMedia.fromJson(Map<String, dynamic>.from(e as Map))],
        installations: [for (final e in (j['installations'] as List? ?? const [])) CatalogInstallation.fromJson(Map<String, dynamic>.from(e as Map))],
        questions: [for (final e in (j['questions'] as List? ?? const [])) CatalogQuestion.fromJson(Map<String, dynamic>.from(e as Map))],
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'media': [for (final m in media) m.toJson()],
        'installations': [for (final i in installations) i.toJson()],
        'questions': [for (final q in questions) q.toJson()],
      };

  /// The catalog shipped inside the app (the same entries the server is seeded with).
  factory CatalogData.builtIn() {
    final common = SignageCatalog.questionsFor(null, null);
    bool isCommon(SiteQuestion q) => common.any((c) => identical(c, q));
    CatalogQuestion q(SiteQuestion s, String scope, String scopeCode, int order) => CatalogQuestion(
          id: s.id,
          label: s.label,
          type: switch (s.type) { QuestionType.number => 'NUMBER', QuestionType.yesNo => 'YES_NO', QuestionType.choice => 'CHOICE', _ => 'TEXT' },
          scope: scope,
          scopeCode: scopeCode,
          options: s.options,
          unit: s.unit,
          required: s.required,
          hint: s.hint,
          showIfId: s.showIfId,
          showIfValue: s.showIfValue,
          order: order,
        );
    final questions = <CatalogQuestion>[
      for (var i = 0; i < common.length; i++) q(common[i], 'COMMON', '', i),
      for (final inst in SignageCatalog.installationTypes) ...[
        for (final (i, s) in SignageCatalog.questionsFor(null, inst.code).where((s) => !isCommon(s)).indexed) q(s, 'INSTALLATION', inst.code, i),
      ],
      for (final m in SignageCatalog.allMediaTypes) ...[
        for (final (i, s) in SignageCatalog.questionsFor(m.code, null).where((s) => !isCommon(s)).indexed) q(s, 'MEDIA', m.code, i),
      ],
    ];
    return CatalogData(
      media: [
        for (final m in SignageCatalog.allMediaTypes)
          CatalogMedia(
            code: m.code,
            shortName: m.shortName,
            name: m.name,
            description: m.description,
            icon: _iconKeyOf(m.icon),
            color: colorHex(m.color),
            illuminated: m.illuminated,
            sidedness: m.sidedness.name.toUpperCase(),
            depthFt: m.depthFt,
            thicknessMm: m.thicknessMm,
            template: m.template,
            installations: m.installations,
            legacy: m.legacy,
            order: m.legacy ? 1000 + SignageCatalog.allMediaTypes.indexOf(m) : SignageCatalog.catalogCodes.indexOf(m.code),
          ),
      ],
      installations: [
        for (final (i, t) in SignageCatalog.installationTypes.indexed)
          CatalogInstallation(code: t.code, name: t.name, description: t.description, icon: _iconKeyOf(t.icon), order: i),
      ],
      questions: questions,
    );
  }

  /* ---- lookups ---- */

  CatalogMedia? mediaByCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final m in media) {
      if (m.code == code) return m;
    }
    return null;
  }

  CatalogMedia? mediaByName(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return null;
    for (final m in media) {
      if (m.name.toLowerCase() == n) return m;
    }
    return null;
  }

  /// The media types offered for a new board, in the admin's order.
  List<CatalogMedia> get offered => [for (final m in media) if (m.offered) m];

  /// The active installation methods of [mediaCode], in the order the media lists them.
  List<CatalogInstallation> installationsFor(String? mediaCode) {
    final m = mediaByCode(mediaCode);
    if (m == null) return const [];
    return [
      for (final code in m.installations)
        for (final i in installations)
          if (i.code == code && i.active) i,
    ];
  }

  CatalogInstallation? installationByCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final i in installations) {
      if (i.code == code) return i;
    }
    return null;
  }

  /// The questions asked for a board of [mediaCode] with [installationCode]: the installation's own, then the media's, then the
  /// common ones; the first of a key wins (the same rule as the older editor). Inactive questions are not asked.
  List<SiteQuestion> questionsFor(String? mediaCode, String? installationCode) {
    final seen = <String>{};
    final out = <SiteQuestion>[];
    void add(String scope, String? code) {
      for (final q in questions) {
        if (q.active && q.scope == scope && (scope == 'COMMON' || q.scopeCode == code) && seen.add(q.id)) out.add(q.toSiteQuestion());
      }
    }

    if (installationCode != null && installationCode.isNotEmpty) add('INSTALLATION', installationCode);
    if (mediaCode != null && mediaCode.isNotEmpty) add('MEDIA', mediaCode);
    add('COMMON', null);
    return out;
  }

  /// Visible required questions that [answers] does not answer yet.
  List<SiteQuestion> missingAnswers(String? mediaCode, String? installationCode, Map<String, dynamic> answers) =>
      [for (final q in questionsFor(mediaCode, installationCode)) if (q.required && q.isVisible(answers) && !q.isAnswered(answers)) q];
}
