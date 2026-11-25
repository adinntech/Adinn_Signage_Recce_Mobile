import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/features/report/recce_pdf_card.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/report/report_service.dart';
import 'package:signage_recce/state/app_controller.dart';

import 'helpers.dart';
import 'model_viewer_pdf_test.dart' show FakeModels;
import 'report_test.dart' show FakeImages;

const _shop = 's_lakshmi';

Future<(AppController, Board)> _done() async {
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin(DemoAccounts.vendorPin);
  final s = c.shop(_shop)!..boards.clear();
  c.setShopLocation(s, gpsAt(10.8627, 78.6897));
  final b = c.addMediaGroups(_shop, [
    MediaGroupPlan(
      SignageCatalog.mediaOptions.firstWhere((o) => o.key == 'GSB_SINGLE'),
      1,
    ),
  ]).single
    ..width = 3
    ..height = 2
    ..installationCode = 'wall_mount';
  completeAnswers(b);
  c.addPhoto(
    _shop,
    b.id,
    SitePhoto(
      id: 'p',
      path: 'demo://x',
      label: 'Front view',
      capturedAt: DateTime(2026, 11, 26),
      width: 10,
      height: 10,
      geo: gpsAt(10.8627, 78.6897),
    ),
  );
  return (c, b);
}

ReportService _svc(Map<String, Uint8List> files, {bool isolate = true}) =>
    ReportService(
      images: FakeImages(),
      models: FakeModels(),
      writer: (b) async {
        files['/r.pdf'] = b;
        return '/r.pdf';
      },
      reader: (p) async => files[p],
      useIsolate: isolate,
    );

void main() {
  test('real PDF bytes through the isolate path (as on device)', () async {
    final (c, _) = await _done();
    expect(c.boardIssues(c.shop(_shop)!.boards.single), isEmpty);
    final files = <String, Uint8List>{};
    final r = await _svc(files).generate(c, _shop, requireComplete: true);
    final bytes = (await _svc(files).read(r))!;
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(r.pageCount, greaterThan(0));
  });

  test('generation failure surfaces and a retry succeeds', () async {
    final (c, _) = await _done();
    final files = <String, Uint8List>{};
    var fail = true;
    final svc = ReportService(
      images: FakeImages(),
      models: FakeModels(),
      writer: (b) async {
        if (fail) throw StateError('disk full');
        files['/r.pdf'] = b;
        return '/r.pdf';
      },
      reader: (p) async => files[p],
      useIsolate: false,
    );
    await expectLater(
      svc.generate(c, _shop, requireComplete: true),
      throwsA(isA<StateError>()),
    );
    fail = false;
    final r = await svc.generate(c, _shop, requireComplete: true);
    expect((await svc.read(r))!.isNotEmpty, isTrue);
  });

  Future<void> pumpCard(
    WidgetTester t,
    AppController c,
    ReportService svc,
  ) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecceReportCard(shopId: _shop, service: svc),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('single board: Download acts directly (no scope popup), '
      'writes a real PDF and resets the loading state', (tester) async {
    final (c, _) = await _done();
    final files = <String, Uint8List>{};
    await pumpCard(tester, c, _svc(files, isolate: false));
    await tester.tap(find.byKey(const Key('recce_pdf_download')));
    // Let the real async generation run (the share sheet itself needs the
    // device plugin, which a widget test does not have).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pump();
    expect(find.text('Download Recce Report'), findsNothing);
    expect(files['/r.pdf'], isNotNull);
    expect(String.fromCharCodes(files['/r.pdf']!.take(5)), '%PDF-');
  });

  testWidgets('one media group with two boards: also direct', (tester) async {
    final (c, b) = await _done();
    c.increaseQuantity(_shop, b, 2);
    completeAnswers(b);
    final files = <String, Uint8List>{};
    await pumpCard(tester, c, _svc(files, isolate: false));
    await tester.tap(find.byKey(const Key('recce_pdf_preview')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pump();
    expect(find.text('Download Recce Report'), findsNothing);
    expect(files['/r.pdf'], isNotNull);
  });

  testWidgets('several media groups keep the Combined / Separate choice', (
    tester,
  ) async {
    final (c, b) = await _done();
    final other = c.addMediaGroups(_shop, [
      MediaGroupPlan(
        SignageCatalog.mediaOptions.firstWhere((o) => o.key == 'ACRYLIC'),
        1,
      ),
    ]).single;
    final files = <String, Uint8List>{};
    await pumpCard(tester, c, _svc(files, isolate: false));
    await tester.tap(find.byKey(const Key('recce_pdf_download')));
    await tester.pumpAndSettle();
    expect(find.text('Download Recce Report'), findsOneWidget);
    // Completed group is exportable alone; the incomplete one and Combined
    // are not.
    expect(find.byKey(Key('scope_${b.id}')), findsOneWidget);
    expect(find.byKey(Key('scope_${other.id}')), findsOneWidget);
    expect(files, isEmpty);
  });

  test('a real installation constraint stays in the report data', () async {
    final (c, b) = await _done();
    final files = <String, Uint8List>{};
    final r = await _svc(files, isolate: false)
        .generate(c, _shop, requireComplete: true);
    expect(r.isDraft, isTrue, reason: 'never marked approved');
    expect(c.shop(_shop)!.status, isNot(RecceStatus.approved));
    expect(b.units, isNotEmpty);
  });
}
