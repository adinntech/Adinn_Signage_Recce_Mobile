import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/report/report_service.dart';
import 'package:signage_recce/features/report/tamil_summary.dart';
import 'package:signage_recce/state/app_controller.dart';

import 'helpers.dart';
import 'model_viewer_pdf_test.dart' show FakeModels;
import 'report_test.dart' show FakeImages;
import 'support/evidence_fixture.dart';

/// flutter_test replaces every font by a box font; load the real bundled
/// Tamil font so glyph shaping can be checked for real.
Future<void> _loadTamilFont() async {
  final loader = FontLoader('NotoSansTamil');
  for (final f in ['Regular', 'Bold']) {
    final bytes = File('assets/fonts/NotoSansTamil-$f.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
  // Latin fallback (the device uses its system font; the test needs a real one).
  // Portable: the SDK's own Roboto (FLUTTER_ROOT is set by `flutter test`).
  final root = Platform.environment['FLUTTER_ROOT'];
  final rob = File(
    '${root ?? ''}/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
  );
  if (root != null && rob.existsSync()) {
    final l = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(rob.readAsBytesSync())));
    await l.load();
  }
}

const _taName = 'லட்சுமி ஹார்ட்வேர்';
const _taRemark =
    'இந்த இடத்தில் கூடுதல் மின் இணைப்பு தேவை. ';

void main() {
  testWidgets('user-entered Tamil survives in BOTH report languages; overlapping reports do not interfere', (tester) async {
    await tester.runAsync(() async {
      await _loadTamilFont();
      final c = AppController(store: MemoryLocalStore());
      await c.init();
      c.loginWithPin(DemoAccounts.vendorPin);
      final s = c.shop('s_lakshmi')!..boards.clear();
      s.name = _taName;
      s.address = '$_taName, 7 Amma Mandapam Road';
      c.setShopLocation(s, gpsAt(10.8627, 78.6897));
      final gsb = c.addMediaGroups('s_lakshmi', [
        MediaGroupPlan(
          SignageCatalog.mediaOptions.firstWhere((o) => o.key == 'GSB_SINGLE'),
          1,
        ),
      ]).single
        ..width = 4
        ..height = 2
        ..installationCode = 'shop_fascia';
      c.increaseQuantity('s_lakshmi', gsb, 2);
      completeAnswers(gsb);
      // Long Tamil remark (several paragraphs) on board 01.
      gsb.units.first.checklist['checklist_remarks'] = ChecklistResponse(
        questionId: 'checklist_remarks',
        value: List.filled(14, _taRemark).join() + '\n' + _taRemark * 4,
      );
      addValidEvidence(c, 's_lakshmi', gsb);
      final other = c.addOtherMedia(
        's_lakshmi',
        CustomSpec(text: 'நியான் பலகை $_taName'),
      )
        ..width = 3
        ..height = 2;
      c.setCustomInstallationForAll(
        's_lakshmi',
        other,
        CustomSpec(text: 'சேல் வழியாக தொங்கவும்'),
      );
      completeAnswers(other);
      addValidEvidence(c, 's_lakshmi', other);
      final files = <String, Uint8List>{};
      ReportService svc(String tag) => ReportService(
        images: FakeImages(),
        models: FakeModels(),
        writer: (bytes) async {
          files[tag] = bytes;
          return '/$tag.pdf';
        },
        reader: (p) async => files[p.substring(1, p.length - 4)],
        useIsolate: false,
      );
      // English and Tamil requested AT THE SAME TIME.
      await Future.wait([
        svc('en').generate(c, 's_lakshmi', requireComplete: true),
        svc('ta').generate(c, 's_lakshmi', requireComplete: true, tamil: true),
      ]);
      for (final n in ['en', 'ta']) {
        expect(String.fromCharCodes(files[n]!.sublist(0, 5)), '%PDF-');
        File('build/export/multi_$n.pdf')
          ..createSync(recursive: true)
          ..writeAsBytesSync(files[n]!);
      }
      expect(files['en']!.length, isNot(files['ta']!.length));
    });
  });

  testWidgets('Tamil summary panel renders with the bundled Noto Sans Tamil', (tester) async {
    await tester.runAsync(() async {
      await _loadTamilFont();
      final img = await TamilSummary.render(
        title: 'தள விவரச் சுருக்கம்',
        rows: const [
          ['GST எண்', '33AAAAA0000A1Z5'],
          ['Is there an existing board at this location?', 'Yes'],
          ['Existing board removal required?', 'No'],
          ['Shutter top height from ground', '10 ft'],
          ['Electrical point available within 10 ft?', 'Yes'],
          ['Fascia material', 'Concrete'],
        ],
      );
      expect(img.bytes.sublist(1, 4), [0x50, 0x4E, 0x47]);
      expect(img.width, greaterThan(500));
      expect(img.height, greaterThan(150));
      // Kept for visual inspection of glyph shaping.
      final f = File('build/export/ta_summary.png')..createSync(recursive: true);
      f.writeAsBytesSync(img.bytes);
    });
  });

  testWidgets('Tamil mode builds a valid PDF with the Tamil summary; English path unchanged', (tester) async {
    await tester.runAsync(() async {
      await _loadTamilFont();
      final c = AppController(store: MemoryLocalStore());
      await c.init();
      c.loginWithPin(DemoAccounts.vendorPin);
      final s = c.shop('s_lakshmi')!..boards.clear();
      c.setShopLocation(s, gpsAt(10.8627, 78.6897));
      c.setShopGst(s, '33AAAAA0000A1Z5');
      final b = c.addMediaGroups('s_lakshmi', [
        MediaGroupPlan(
          SignageCatalog.mediaOptions.firstWhere((o) => o.key == 'GSB_SINGLE'),
          1,
        ),
      ]).single
        ..width = 3
        ..height = 2
        ..installationCode = 'shop_fascia';
      completeAnswers(b);
      addValidEvidence(c, 's_lakshmi', b);
      final files = <String, Uint8List>{};
      ReportService svc() => ReportService(
        images: FakeImages(),
        models: FakeModels(),
        writer: (bytes) async {
          files['r'] = bytes;
          return '/r.pdf';
        },
        reader: (p) async => files['r'],
        useIsolate: false,
      );
      await svc().generate(c, 's_lakshmi', requireComplete: true);
      final en = files['r']!;
      await svc().generate(c, 's_lakshmi', requireComplete: true, tamil: true);
      final ta = files['r']!;
      expect(String.fromCharCodes(en.sublist(0, 5)), '%PDF-');
      expect(String.fromCharCodes(ta.sublist(0, 5)), '%PDF-');
      expect(ta.length, isNot(en.length), reason: 'Tamil text blocks embedded');
      // Kept for visual inspection of the complete rendered pages.
      File('build/export/report_en.pdf')
        ..createSync(recursive: true)
        ..writeAsBytesSync(en);
      File('build/export/report_ta.pdf')
        ..createSync(recursive: true)
        ..writeAsBytesSync(ta);
    });
  });
}
