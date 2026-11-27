import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';

Board _b(String media, {String? inst, bool? dbl, String? nlb}) => Board(
  id: 'b',
  name: 'Board 1',
  mediaCode: media,
  installationCode: inst,
  doubleSided: dbl,
  nlbSubtype: nlb,
);

/// Standard options: "+ Other" is the approved extra FINAL option of every
/// applicable media and is asserted separately.
List<InstallationChoice> _std(Board b) => [
  for (final c in SignageCatalog.choicesForBoard(b))
    if (c.code != SignageCatalog.otherInstallation) c,
];

List<String?> _names(Board b) => _std(b).map((c) => c.name).toList();

void main() {
  group('Add Media Type', () {
    test('exactly 7 selectable media in the requested order', () {
      expect(SignageCatalog.selectableMedia.map((m) => m.code), [
        'GSB',
        'NLB',
        'FOAM_VINYL',
        'ACRYLIC',
        'OWV',
        'PLAIN_VINYL',
        'MDF',
      ]);
    });

    test('removed types are hidden but still known', () {
      for (final c in [
        'SANDWICH',
        'ACP2D',
        'ACP2D_DS',
        'ACP',
        'ACP3D_DS',
        'MDF_GSB',
        'MDF_GSB_DS',
      ]) {
        expect(SignageCatalog.selectableCodes, isNot(contains(c)));
        expect(SignageCatalog.media(c), isNotNull, reason: c);
      }
    });

    test('One-Way Vision label changes, stored code does not', () {
      final m = SignageCatalog.media('OWV')!;
      expect(m.shortName, 'One-Way Vision');
      expect(m.code, 'OWV');
    });

    test('short subtitles', () {
      final s = {
        for (final m in SignageCatalog.selectableMedia)
          m.shortName: SignageCatalog.cardSubtitle(m),
      };
      expect(s['GSB'], 'Glow Sign Board');
      expect(s['MDF'], 'MDF Display Board');
      expect(s['One-Way Vision'], 'Perforated Glass Film');
    });

    test('MDF is not mapped to MDF+GSB and has no invented installations', () {
      final m = SignageCatalog.media('MDF')!;
      expect(m.code, isNot('MDF_GSB'));
      expect(m.installations, isEmpty);
      expect(m.template, isNot('mdfgsb'));
    });
  });

  group('Installation options', () {
    test('GSB Double: five options', () {
      expect(_names(_b('GSB', dbl: true)), [
        'Projecting Mount',
        'Double Pole',
        'Single Pole',
        'Rooftop',
        'Hanging Mount',
      ]);
    });

    test('NLB Box: four options, no Hanging Mount', () {
      final b = _b('NLB', dbl: true, nlb: 'NLB_BOX_FRAME');
      expect(_names(b), [
        'Double Pole',
        'Rooftop',
        'Projecting Mount',
        'Single Pole',
      ]);
    });

    test('NLB Single Frame unchanged', () {
      final b = _b('NLB', dbl: false, nlb: 'NLB_SINGLE_FRAME');
      expect(
        _std(b).map((c) => c.code),
        SignageCatalog.media('NLB')!.installations,
      );
    });

    test('Foam Vinyl hides Direct on Wall for new, keeps saved value', () {
      expect(_names(_b('FOAM_VINYL')), ['Wall Mount']);
      expect(SignageCatalog.media('FOAM_VINYL')!.thicknessMm, 3);
      final old = _b('FOAM_VINYL', inst: 'direct_wall');
      expect(SignageCatalog.allowsInstallation(old, 'direct_wall'), isTrue);
      expect(SignageCatalog.legacyInstallationOf(old)?.code, 'direct_wall');
      expect(
        SignageCatalog.allowsInstallation(_b('FOAM_VINYL'), 'direct_wall'),
        isFalse,
      );
    });

    test('Acrylic: Wall Mount only, dimensions config untouched', () {
      expect(_names(_b('ACRYLIC')), ['Wall Mount']);
      expect(SignageCatalog.media('ACRYLIC')!.thicknessMm, 8);
      final old = _b('ACRYLIC', inst: 'glass_pasting');
      expect(SignageCatalog.legacyInstallationOf(old)?.code, 'glass_pasting');
    });

    test('Other media keep existing mappings', () {
      expect(
        _std(_b('PLAIN_VINYL')).map((c) => c.code),
        SignageCatalog.media('PLAIN_VINYL')!.installations,
      );
      expect(_names(_b('MDF')), isEmpty);
    });
  });

  group('Installation icon mapping', () {
    test('GSB Double / NLB Box reuse the GSB Single catalog icons', () {
      final boards = [
        _b('GSB', dbl: true),
        _b('NLB', dbl: true, nlb: 'NLB_BOX_FRAME'),
      ];
      for (final b in boards) {
        for (final c in SignageCatalog.choicesForBoard(b)) {
          if (c.code == null) continue;
          expect(
            c.icon,
            SignageCatalog.installation(c.code)!.icon,
            reason: '${b.mediaCode} ${c.name}',
          );
        }
      }
    });

    test('Hanging Mount keeps the original painter illustration', () {
      final h = _std(_b('GSB', dbl: true)).last;
      expect(h.name, 'Hanging Mount');
      expect(h.icon, isNull);
      expect(h.art, InstallationArt.hanging);
      expect(h.canPersist, isFalse);
    });

    test('other media stay on the generic icon path', () {
      for (final c in _std(_b('ACRYLIC'))) {
        expect(c.art, InstallationArt.generic);
        expect(c.icon, isNotNull);
      }
    });
  });
}
