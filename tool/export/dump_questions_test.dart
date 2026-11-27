// Standalone, read-only export helper (NOT part of the app).
// Dumps the runtime question resolution to build/export/questions.json:
//   flutter test tool/export/dump_questions_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/catalog/question_equivalence.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/catalog/site_checklists.dart';
import 'package:signage_recce/data/models/models.dart';

Map<String, dynamic> _site(Board b, SignageUnit u, SiteQuestion q) => {
  'id': q.id,
  'label': q.label,
  'type': q.type.name,
  'options': q.options,
  'unit': q.unit,
  'required': q.required,
  'hint': q.hint,
  'showIfId': q.showIfId,
  'showIfValue': q.showIfValue,
  'section': SignageCatalog.questionSectionFor(b, u, q),
};

Map<String, dynamic> _cl(ChecklistQuestion q) => {
  'id': q.id,
  'text': q.text,
  'type': q.type.name,
  'options': q.options,
  'required': q.required,
  'allowNa': q.allowNa,
  'unit': q.unit,
  'installations': q.installations?.toList(),
  'reviewIfYes': q.reviewIfYes,
  'reviewIfNo': q.reviewIfNo,
};

void main() {
  test('dump questions', () {
    final combos = <Map<String, dynamic>>[];
    for (final o in SignageCatalog.mediaOptions) {
      final probe = Board(
        id: 'p',
        name: 'p',
        mediaCode: o.mediaCode,
        doubleSided: o.doubleSided,
        nlbSubtype: o.nlbSubtype,
        checklistRequired: true,
      );
      final choices = SignageCatalog.choicesForBoard(probe);
      final media = SignageCatalog.media(o.mediaCode)!;
      final entries = <({String? code, String name, bool persist})>[
        for (final c in choices)
          (code: c.code, name: c.name, persist: c.canPersist),
      ];
      if (entries.isEmpty) {
        entries.add((code: null, name: '(none configured)', persist: false));
      }
      for (final e in entries) {
        final b = Board(
          id: 'b',
          name: 'b',
          mediaCode: o.mediaCode,
          doubleSided: o.doubleSided,
          nlbSubtype: o.nlbSubtype,
          installationCode: e.code,
          checklistRequired: true,
          units: [SignageUnit(id: 'b_u1')],
        );
        final u = b.units.first;
        final pairs = e.code == null && !e.persist && e.name != '(none configured)'
            ? <EquivalentPair>[]
            : QuestionEquivalence.pairsFor(b, u);
        final mapped = {for (final p in pairs) p.checklist.id: p.site.id};
        final siteQs = SignageCatalog.questionsForUnit(b, u);
        final cls = SiteChecklists.questionsFor(o.mediaCode, e.code);
        combos.add({
          'optionKey': o.key,
          'optionLabel': o.label,
          'mediaCode': o.mediaCode,
          'mediaName': media.name,
          'doubleSided': o.doubleSided,
          'nlbSubtype': o.nlbSubtype,
          'installationCode': e.code,
          'installationName': e.code == null
              ? e.name
              : SignageCatalog.installationLabel(b, e.code),
          'persistable': e.persist || e.code != null,
          'checklistDefinition': SiteChecklists.definitionFor(o.mediaCode)?.id,
          'site': [for (final q in siteQs) _site(b, u, q)],
          'checklist': [for (final q in cls) _cl(q)],
          'mapped': mapped,
          'uniqueMissingIds': [
            for (final q in SiteChecklists.uniqueMissing(b, u)) q.id,
          ],
        });
      }
    }
    final legacy = [
      for (final m in SignageCatalog.allMediaTypes)
        if (m.legacy ||
            !SignageCatalog.selectableCodes.contains(m.code))
          {
            'code': m.code,
            'name': m.name,
            'legacy': m.legacy,
            'selectable': SignageCatalog.selectableCodes.contains(m.code),
            'installations': m.installations,
            'checklist': SiteChecklists.definitionFor(m.code)?.id,
          },
    ];
    final defs = [
      for (final d in SiteChecklists.definitions)
        {
          'id': d.id,
          'title': d.title,
          'mediaCodes': d.mediaCodes.toList(),
          'questions': [for (final q in d.questions) _cl(q)],
        },
    ];
    final commonIds = {
      for (final q in SignageCatalog.questionsFor('MDF', null)) q.id,
    };
    final legacySite = <Map<String, dynamic>>[];
    for (final m in SignageCatalog.allMediaTypes) {
      if (SignageCatalog.selectableCodes.contains(m.code)) continue;
      final b = Board(
        id: 'l',
        name: 'l',
        mediaCode: m.code,
        units: [SignageUnit(id: 'l_u1')],
      );
      for (final q in SignageCatalog.questionsFor(m.code, null)) {
        if (commonIds.contains(q.id)) continue;
        legacySite.add({'media': m.code, ..._site(b, b.units.first, q)});
      }
    }
    final out = {
      'legacySite': legacySite,
      'combos': combos,
      'legacy': legacy,
      'definitions': defs,
      'rules': [
        for (final r in QuestionEquivalence.rules)
          {
            'site': r.siteId,
            'checklist': r.checklistId,
            'installations': r.installations?.toList(),
          },
      ],
      'installationNames': {
        for (final i in SignageCatalog.installationTypes) i.code: i.name,
      },
    };
    final f = File('build/export/questions.json');
    f.createSync(recursive: true);
    f.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
  });
}
