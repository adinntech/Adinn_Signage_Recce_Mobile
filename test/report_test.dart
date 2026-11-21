import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/report/report_data.dart';
import 'package:signage_recce/features/report/report_pdf.dart';
import 'package:signage_recce/features/report/report_service.dart';
import 'package:signage_recce/features/report/reports_screen.dart';
import 'package:signage_recce/features/survey/site_markup_painter.dart';
import 'package:signage_recce/state/app_controller.dart';

import 'helpers.dart';

/// Tiny JPEG pictures instead of decoding device files.
class FakeImages implements ReportImageLoader {
  FakeImages({this.missing = false, this.width = 40, this.height = 30});

  final bool missing;
  final int width;
  final int height;
  int photoCalls = 0;
  int annotatedCalls = 0;
  final List<String> files = [];

  ReportImage? _img() => missing
      ? null
      : ReportImage(
          img.encodeJpg(img.Image(width: width, height: height)),
          width,
          height,
        );

  @override
  Future<ReportImage?> photo(
    SitePhoto photo, {
    required bool annotated,
    MarkupLabels? labels,
  }) async {
    annotated ? annotatedCalls++ : photoCalls++;
    return _img();
  }

  @override
  Future<ReportImage?> file(String path) async {
    files.add(path);
    return _img();
  }
}

class Rig {
  Rig._(this.store, this.c, this.service, this.files, this.images);

  final MemoryLocalStore store;
  final AppController c;
  final ReportService service;
  final Map<String, Uint8List> files;
  final FakeImages images;

  static Future<Rig> create({
    FakeImages? images,
    MemoryLocalStore? store,
    bool compress = false,
  }) async {
    final s = store ?? MemoryLocalStore();
    final c = AppController(store: s);
    await c.init();
    final files = <String, Uint8List>{};
    final fake = images ?? FakeImages();
    var n = 0;
    final service = ReportService(
      images: fake,
      writer: (bytes) async {
        final path = '/reports/r${n++}.pdf';
        files[path] = bytes;
        return path;
      },
      reader: (path) async => files[path],
      clock: () => DateTime(2026, 11, 18, 10, 30 + 5 * n),
      useIsolate: false,
      compress: compress,
    );
    return Rig._(s, c, service, files, fake);
  }

  void login(String pin) {
    c.logout();
    expect(c.loginWithPin(pin), isNull);
  }
}

/// Words drawn in an uncompressed PDF (each word is a separate TJ
/// operator), joined with single spaces.
String latin1Text(Uint8List bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final words = RegExp(r'\[\((.*?)\)\]TJ')
      .allMatches(raw)
      .map((m) => m.group(1)!.replaceAll(r'\(', '(').replaceAll(r'\)', ')'));
  return words.join(' ');
}

void expectValidPdf(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  expect(text.startsWith('%PDF-'), isTrue);
  expect(text.trimRight().endsWith('%%EOF'), isTrue);
}

Map<String, dynamic> firstItem(RecceReport r) {
  final groups = r.snapshot['groups'] as List;
  return Map<String, dynamic>.from(
    (Map<String, dynamic>.from(groups.first as Map)['items'] as List).first
        as Map,
  );
}

List<Map<String, dynamic>> allItems(RecceReport r) => [
  for (final g in r.snapshot['groups'] as List)
    for (final i in (g as Map)['items'] as List) Map<String, dynamic>.from(i),
];

/// Completes the seed draft (answers, checklist, GPS) and submits v1.
void submitSriranga(AppController c) {
  final shop = c.shop('s_sriranga')!;
  for (final b in shop.boards) {
    completeAnswers(b);
  }
  c.setShopLocation(shop, gpsAt(10.86270, 78.68970));
  c.submitShop(shop.id);
}

void main() {
  group('report data & PDF', () {
    test(
      'draft report: valid PDF, draft banner, correct header values',
      () async {
        final r = await Rig.create();
        r.login(DemoAccounts.vendorPin);
        final shop = r.c.shop('s_sriranga')!;
        final report = await r.service.generate(r.c, shop.id);

        expect(report.isDraft, isTrue);
        expect(report.status, RecceStatus.inProgress);
        expect(report.version, 0);
        expect(report.pageCount, greaterThanOrEqualTo(1));
        expect(report.generatedByName, r.c.currentUser!.name);
        final bytes = r.files[report.path]!;
        expectValidPdf(bytes);
        expect(report.sizeBytes, bytes.length);

        final banner = report.snapshot['banner'] as Map;
        expect(banner['draft'], isTrue);
        expect(banner['text'], kDraftBanner);
        final header = Map<String, dynamic>.from(
          report.snapshot['header'] as Map,
        );
        final project = r.c.project(shop.projectId)!;
        final task = r.c.task(shop.taskId)!;
        expect(header['projectId'], shop.projectId);
        expect(header['projectName'], project.name);
        expect(header['taskId'], shop.taskId);
        expect(header['taskTitle'], task.title);
        expect(header['shopId'], shop.id);
        expect(header['shopName'], shop.name);
        expect(header['brand'], project.client);
        expect(
          header['reccePerson'],
          r.c.userById(task.assignedVendorId)!.name,
        );
        expect(report.snapshot['title'], kReportTitle);
        // Draft text in the PDF itself (uncompressed in tests).
        expect(
          latin1Text(bytes),
          contains('DRAFT - NOT APPROVED FOR FABRICATION'),
        );
        expect(
          latin1Text(bytes),
          isNot(contains('APPROVED FOR FABRICATION -')),
        );
      },
    );

    test('approved report after Business + Ops approval', () async {
      final r = await Rig.create();
      r.login(DemoAccounts.vendorPin);
      submitSriranga(r.c);
      r.login(DemoAccounts.businessPin);
      r.c.reviewShop('s_sriranga', decision: ReviewDecision.approved);
      r.login(DemoAccounts.opsPin);
      r.c.reviewShop('s_sriranga', decision: ReviewDecision.approved);
      final report = await r.service.generate(r.c, 's_sriranga');

      expect(report.isDraft, isFalse);
      expect(report.status, RecceStatus.approved);
      expect(report.version, 1);
      final banner = report.snapshot['banner'] as Map;
      expect(banner['draft'], isFalse);
      expect('${banner['text']}', contains('APPROVED FOR FABRICATION'));
      expect('${banner['detail']}', contains('Approved by'));
      final header = report.snapshot['header'] as Map;
      expect('${header['source']}', contains('Submitted version v1'));
      final review = report.snapshot['review'] as Map;
      expect('${review['business']}', startsWith('Approved by'));
      expect('${review['ops']}', startsWith('Approved by'));
      expectValidPdf(r.files[report.path]!);
    });

    test('pending recce is never marked approved', () async {
      final r = await Rig.create();
      r.login(DemoAccounts.opsPin);
      final shop = r.c.shop('s_thillai_colour')!;
      expect(shop.status, RecceStatus.pendingOps);
      final report = await r.service.generate(r.c, shop.id);
      expect(report.isDraft, isTrue);
      expect((report.snapshot['banner'] as Map)['text'], kDraftBanner);
      expect(
        '${(report.snapshot['banner'] as Map)['detail']}',
        contains('Pending Ops Approval'),
      );
      // Seed approved shop → approved report.
      final done = await r.service.generate(r.c, 's_meenakshi');
      expect(done.isDraft, isFalse);
    });

    test('signage dimensions, multiple media types and quantities', () async {
      final r = await Rig.create();
      r.login(DemoAccounts.vendorPin);
      final shop = r.c.shop('s_sriranga')!;
      final gsb = r.c.addBoard(shop.id)
        ..mediaCode = SignageCatalog.gsb
        ..installationCode = SignageCatalog.doublePole
        ..width = 8
        ..height = 3;
      r.c.increaseQuantity(shop.id, gsb, 3);
      final standee = r.c.addBoard(shop.id)
        ..mediaCode = SignageCatalog.doubleStandee
        ..installationCode = SignageCatalog.freeStanding
        ..width = 2
        ..height = 5;
      r.c.touchBoard(shop.id, standee);
      final u2 = gsb.activeUnits[1];
      u2.measurements = MeasurementDetails(
        valuesMm: {
          'bottom_height': 9 * 304.8,
          'top_height': 12 * 304.8,
          'pole_spacing': 6 * 304.8,
          'pole_above_ground': 12 * 304.8,
        },
        counts: {'pole_count': 2},
      );
      final report = await r.service.generate(r.c, shop.id);

      final overview = report.snapshot['overview'] as Map;
      expect((overview['mediaTypes'] as List).length, greaterThanOrEqualTo(2));
      expect(overview['mediaGroups'], shop.boards.length);
      final items = allItems(report);
      final gsbItems = items.where((i) => i['groupId'] == gsb.id).toList();
      expect(gsbItems, hasLength(3));
      expect(gsbItems[1]['unitId'], u2.id);
      expect(gsbItems[1]['width'], '8 ft');
      expect(gsbItems[1]['height'], '3 ft');
      expect(gsbItems[1]['quantityContext'], startsWith('Unit 2 of 3'));
      expect(gsbItems[1]['installation'], 'Double Pole');
      expect((gsbItems[1]['groundClearance'] as Map)['bottom'], '9 ft');
      expect((gsbItems[1]['measurements'] as List), isNotEmpty);
      expect(gsbItems[1]['diagram'], isNotNull);
      expect(gsbItems[0]['diagram'], isNull); // nothing recorded
      final st = items.firstWhere((i) => i['groupId'] == standee.id);
      expect(st['media'], 'Double-Sided Standee');
      expect(st['width'], '2 ft');
      expectValidPdf(r.files[report.path]!);
    });

    test('pictures are kept proportional', () {
      final (w1, h1) = reportImageBox(4000, 3000, 531, 300);
      expect(w1 / h1, closeTo(4000 / 3000, 1e-9));
      expect(w1, lessThanOrEqualTo(531));
      expect(h1, lessThanOrEqualTo(300));
      final (w2, h2) = reportImageBox(900, 1600, 531, 300);
      expect(w2 / h2, closeTo(900 / 1600, 1e-9));
      expect(h2, closeTo(300, 1e-9));
      final (w3, h3) = reportImageBox(3000, 200, 531, 300);
      expect(w3, closeTo(531, 1e-9));
      expect(w3 / h3, closeTo(15, 1e-9));
    });

    test('photos, annotated photos and previews are requested', () async {
      final r = await Rig.create();
      r.login(DemoAccounts.vendorPin);
      final shop = r.c.shop('s_meenakshi')!;
      final report = await r.service.generate(r.c, shop.id);
      final photos = shop.boards.fold<int>(0, (n, b) => n + b.photos.length);
      expect(r.images.photoCalls, photos);
      final refs = report.snapshot['images'] as List;
      expect(refs.length, greaterThanOrEqualTo(photos));
      for (final g in report.snapshot['groups'] as List) {
        for (final p in (g as Map)['pictures'] as List) {
          expect('${(p as Map)['caption']}', isNotEmpty);
        }
      }
    });

    test('missing pictures become captioned placeholders', () async {
      final r = await Rig.create(images: FakeImages(missing: true));
      r.login(DemoAccounts.vendorPin);
      final report = await r.service.generate(r.c, 's_meenakshi');
      final text = latin1Text(r.files[report.path]!);
      expect(text, contains('Image not available on this device'));
      expectValidPdf(r.files[report.path]!);
    });

    test(
      'long remarks wrap and many units span pages with numbering',
      () async {
        final r = await Rig.create();
        r.login(DemoAccounts.vendorPin);
        final shop = r.c.shop('s_sriranga')!;
        final b = r.c.addBoard(shop.id)
          ..mediaCode = SignageCatalog.gsb
          ..installationCode = SignageCatalog.shopFascia
          ..width = 10
          ..height = 4;
        r.c.increaseQuantity(shop.id, b, 30);
        completeChecklists(b);
        final long = List.filled(1500, 'Long remark about fixing.').join(' ');
        b.activeUnits.first.notes = long;
        b.activeUnits.first.checklist['checklist_remarks'] = ChecklistResponse(
          questionId: 'checklist_remarks',
          value: 'see remarks',
          remarks: long,
        );
        final report = await r.service.generate(r.c, shop.id);
        expect(report.pageCount, greaterThan(5));
        final text = latin1Text(r.files[report.path]!);
        expect(text, contains('Page 1 of ${report.pageCount}'));
        expect(
          text,
          contains('Page ${report.pageCount} of ${report.pageCount}'),
        );
        expect(reportPageLabel(2, 7), 'Page 2 of 7');
        expectValidPdf(r.files[report.path]!);
      },
    );

    test('report metadata persists across a reload', () async {
      final store = MemoryLocalStore();
      final r = await Rig.create(store: store);
      r.login(DemoAccounts.vendorPin);
      final report = await r.service.generate(r.c, 's_sriranga');
      await r.c.flush();
      expect(
        r.c.activities(shopId: 's_sriranga').first.title,
        'Measurement PDF generated',
      );

      final again = AppController(store: store);
      await again.init();
      final list = again.reportsForShop('s_sriranga');
      expect(list, hasLength(1));
      final saved = list.single;
      expect(saved.id, report.id);
      expect(saved.path, report.path);
      expect(saved.pageCount, report.pageCount);
      expect(saved.sizeBytes, report.sizeBytes);
      expect(saved.isDraft, isTrue);
      expect(saved.snapshot['header'], isNotNull);
      expect(jsonEncode(saved.snapshot), jsonEncode(report.snapshot));
    });

    test('historical report snapshot is not changed by later edits', () async {
      final r = await Rig.create();
      r.login(DemoAccounts.vendorPin);
      final shop = r.c.shop('s_sriranga')!;
      final b = shop.boards.first;
      final first = await r.service.generate(r.c, shop.id);
      final before = jsonEncode(first.snapshot);
      final oldWidth = firstItem(first)['width'];

      b.width = (b.width ?? 1) + 5;
      r.c.touchBoard(shop.id, b);
      final second = await r.service.generate(r.c, shop.id);

      final stored = r.c
          .reportsForShop(shop.id)
          .firstWhere((x) => x.id == first.id);
      expect(jsonEncode(stored.snapshot), before);
      expect(firstItem(stored)['width'], oldWidth);
      expect(firstItem(second)['width'], isNot(oldWidth));
      expect(r.c.reportsForShop(shop.id).first.id, second.id); // newest first
    });

    test('submitted content comes from the snapshot, not live edits', () async {
      final r = await Rig.create();
      r.login(DemoAccounts.businessPin);
      final shop = r.c.shop('s_amma')!;
      final snapName = shop.latestSubmission!.shopSnapshot.name;
      shop.name = 'Live renamed';
      final report = await r.service.generate(r.c, shop.id);
      expect((report.snapshot['header'] as Map)['shopName'], snapName);
    });

    test('text is sanitised for the built-in PDF font', () {
      expect(
        pdfSafe('GSB – Unit 01 • 8 × 3 ft…'),
        'GSB - Unit 01 - 8 x 3 ft...',
      );
      expect(pdfSafe('“Shop’s” ₹500 ±2°'), '"Shop\'s" Rs.500 +/-2 deg');
      expect(pdfSafe('Café தமிழ் ok'), 'Café  ok');
    });

    test('PDF builds in a background isolate', () async {
      final r = await Rig.create();
      r.login(DemoAccounts.vendorPin);
      final build = buildReportData(
        r.c,
        r.c.shop('s_sriranga')!,
        now: DateTime(2026, 11, 18),
      );
      final out = await compute(buildReportPdf, ReportInput(data: build.data));
      expectValidPdf(out.bytes);
      expect(out.pageCount, greaterThanOrEqualTo(1));
    });

    test('review section lists rejections and open comments', () async {
      final r = await Rig.create();
      r.login(DemoAccounts.vendorPin);
      submitSriranga(r.c);
      r.login(DemoAccounts.businessPin);
      final shop = r.c.shop('s_sriranga')!;
      final b = shop.boards.first;
      r.c.addReviewComment(
        shop.id,
        groupId: b.id,
        photoId: b.photos.first.id,
        type: ReviewCommentType.incorrectMeasurement,
        text: 'Width looks wrong',
        position: const SurveyPoint(0.4, 0.5),
      );
      r.c.reviewShop(
        shop.id,
        decision: ReviewDecision.rejected,
        remarks: 'Please re-measure',
        reasons: ['Measurement mismatch'],
      );
      final report = await r.service.generate(r.c, shop.id);
      final review = report.snapshot['review'] as Map;
      expect(
        (review['rejections'] as List).single['remarks'],
        'Please re-measure',
      );
      expect((review['comments'] as List).single[3], 'Width looks wrong');
      expect('${review['business']}', startsWith('Rejected by'));
      expect(report.isDraft, isTrue);
    });
  });

  group('ReportsScreen', () {
    testWidgets('generate, list and delete a report', (tester) async {
      late Rig r;
      await tester.runAsync(() async {
        r = await Rig.create();
      });
      r.login(DemoAccounts.vendorPin);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: r.c,
          child: MaterialApp(
            home: ReportsScreen(shopId: 's_sriranga', service: r.service),
          ),
        ),
      );
      expect(find.text('Measurement PDF'), findsOneWidget);
      expect(find.text(kDraftBanner), findsOneWidget);
      expect(find.text('No reports yet'), findsOneWidget);

      await tester.tap(find.byKey(const Key('report_generate')));
      await tester.runAsync(() async {
        for (
          var i = 0;
          i < 50 && r.c.reportsForShop('s_sriranga').isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      final report = r.c.reportsForShop('s_sriranga').single;
      expect(find.byKey(Key('report_${report.id}')), findsOneWidget);
      expect(find.byKey(Key('report_preview_${report.id}')), findsOneWidget);
      expect(find.byKey(Key('report_share_${report.id}')), findsOneWidget);
      expect(find.text('DRAFT'), findsOneWidget);

      await tester.tap(find.byKey(Key('report_delete_${report.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(r.c.reportsForShop('s_sriranga'), isEmpty);
      expect(find.text('No reports yet'), findsOneWidget);
    });

    testWidgets('missing PDF file shows a message instead of crashing', (
      tester,
    ) async {
      late Rig r;
      await tester.runAsync(() async {
        r = await Rig.create();
        r.login(DemoAccounts.vendorPin);
        final rep = await r.service.generate(r.c, 's_sriranga');
        r.files.remove(rep.path);
      });
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: r.c,
          child: MaterialApp(
            home: ReportsScreen(shopId: 's_sriranga', service: r.service),
          ),
        ),
      );
      final rep = r.c.reportsForShop('s_sriranga').single;
      await tester.tap(find.byKey(Key('report_preview_${rep.id}')));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('PDF file not found'), findsOneWidget);
    });
  });
}
