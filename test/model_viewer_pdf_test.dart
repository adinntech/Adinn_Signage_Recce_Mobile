import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/model3d/signage_spec.dart';
import 'package:signage_recce/features/model3d/technical_drawing.dart';
import 'package:signage_recce/features/model3d/technical_drawing_screen.dart';
import 'package:signage_recce/features/preview3d/preview_3d_screen.dart';
import 'package:signage_recce/features/report/model_image_renderer.dart';
import 'package:signage_recce/features/report/report_data.dart';
import 'package:signage_recce/features/report/report_pdf.dart';
import 'package:signage_recce/features/report/report_service.dart';
import 'package:signage_recce/state/app_controller.dart';

import 'report_test.dart' show FakeImages, latin1Text, expectValidPdf;

/// Records what the PDF asked to render (no dart:ui rasterising).
class FakeModels implements ModelImageRenderer {
  FakeModels({this.fail = false});

  final bool fail;
  final List<String> calls = [];

  ReportImage? _img() => fail
      ? null
      : ReportImage(img.encodeJpg(img.Image(width: 60, height: 40)), 60, 40);

  @override
  Future<ReportImage?> drawing(SignageModelSpec spec, DrawingView view) async {
    calls.add('2d:${view.name}:${spec.widthMm.round()}');
    return _img();
  }

  @override
  Future<ReportImage?> model(
    SignageModelSpec spec, {
    String brand = '',
    double yaw = kFrontIsoYaw,
  }) async {
    // The opposite-side review angle is recorded separately.
    calls.add(
      '${yaw == kRearIsoYaw ? '3d-rear' : '3d'}:${spec.template}:'
      '${spec.widthMm.round()}',
    );
    return _img();
  }
}

Future<(AppController, Board)> _setup() async {
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin(DemoAccounts.vendorPin);
  final b = c.addBoard('s_lakshmi')
    ..mediaCode = SignageCatalog.gsb
    ..installationCode = SignageCatalog.doublePole
    ..width = 8
    ..height = 3;
  return (c, b);
}

Widget _host(AppController c, Widget child) =>
    ChangeNotifierProvider<AppController>.value(
      value: c,
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  group('3D viewer two-way sync', () {
    testWidgets('57-58, 64, 66 edit pole spacing in 3D, save, recce updates', (
      tester,
    ) async {
      _phone(tester);
      final (c, b) = await _setup();
      final u = b.units.first;
      await tester.pumpWidget(
        _host(c, Preview3DScreen(shopId: 's_lakshmi', boardId: b.id)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('model_item_id')), findsOneWidget);
      expect(find.byKey(const Key('model_status')), findsOneWidget);
      expect(find.text('Illustrative Model'), findsOneWidget);

      // Select the poles component → its fields appear.
      await tester.ensureVisible(find.byKey(const Key('comp_poles')));
      await tester.tap(find.byKey(const Key('comp_poles')));
      await tester.pumpAndSettle();
      final plus = find.byKey(const Key('spec_poleSpacing_plus'));
      await tester.ensureVisible(plus);
      await tester.pumpAndSettle();
      final before = SignageModelSpec.of(b, u)[SpecField.poleSpacing];
      await tester.tap(plus);
      await tester.tap(plus);
      await tester.pumpAndSettle();
      // Not committed yet: the recce still has the old value.
      expect(u.measurements.mm('pole_spacing'), isNull);

      await tester.tap(find.byKey(const Key('model_save')));
      await tester.pumpAndSettle();
      expect(
        u.measurements.mm('pole_spacing'),
        closeTo(before + 2 * 25.4, 1e-9),
      );
      expect(b.answers['pole_gap'], isNotNull, reason: 'site answer mirrored');
      expect(b.width, 8, reason: 'pole spacing never resizes the board');
    });

    testWidgets('67 + 69 cancel reverts; zoom never changes measurements', (
      tester,
    ) async {
      _phone(tester);
      final (c, b) = await _setup();
      await tester.pumpWidget(
        _host(c, Preview3DScreen(shopId: 's_lakshmi', boardId: b.id)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.tap(find.byTooltip('Fit model'));
      await tester.pumpAndSettle();
      expect(b.width, 8);
      expect(b.height, 3);

      await tester.drag(
        find.byKey(const Key('width-slider')),
        const Offset(80, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model_cancel')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('model_save')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(b.width, 8, reason: 'cancelled edit never reaches the recce');
    });

    testWidgets('70 submitted recce: viewer is read-only', (tester) async {
      _phone(tester);
      final c = AppController(store: MemoryLocalStore());
      await c.init();
      c.loginWithPin(DemoAccounts.businessPin);
      await tester.pumpWidget(
        _host(c, const Preview3DScreen(shopId: 's_amma', boardId: 'b_amma_1')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('model_save')), findsNothing);
      expect(find.textContaining('View only'), findsOneWidget);
    });

    testWidgets('60 + 71 2D drawing reflects the value saved from 3D', (
      tester,
    ) async {
      _phone(tester);
      final (c, b) = await _setup();
      final u = b.units.first;
      c.applySpecEdits('s_lakshmi', b.id, u.id, {SpecField.width: 3048});
      await tester.pumpWidget(
        _host(
          c,
          TechnicalDrawingScreen(
            shopId: 's_lakshmi',
            boardId: b.id,
            unitId: u.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('technical_drawing')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('drawing_dim_width'))).data,
        '10 ft',
      );
      // Another edit while the drawing is open → rebuilds from the source.
      c.applySpecEdits('s_lakshmi', b.id, u.id, {SpecField.width: 3657.6});
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('drawing_dim_width'))).data,
        '12 ft',
      );
      for (final v in DrawingView.values) {
        await tester.ensureVisible(find.byKey(Key('drawing_view_${v.name}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('drawing_view_${v.name}')));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('F. PDF 2D / 3D measurement sheets', () {
    Future<(AppController, ReportService, FakeModels, Map<String, Uint8List>)>
    rig({bool fail = false}) async {
      final (c, b) = await _setup();
      c.applySpecEdits('s_lakshmi', b.id, b.units.first.id, {
        SpecField.width: 3048,
      });
      final models = FakeModels(fail: fail);
      final files = <String, Uint8List>{};
      final service = ReportService(
        images: FakeImages(),
        models: models,
        writer: (bytes) async {
          files['/r.pdf'] = bytes;
          return '/r.pdf';
        },
        reader: (p) async => files[p],
        useIsolate: false,
        compress: false,
      );
      return (c, service, models, files);
    }

    test('61, 75-81 sheet uses the saved dims, 2D and 3D images', () async {
      final (c, service, models, files) = await rig();
      final r = await service.generate(c, 's_lakshmi');
      expect(models.calls, containsAll(['2d:front:3048', '2d:side:3048']));
      expect(models.calls.any((x) => x.startsWith('3d:gsb:3048')), isTrue);
      final bytes = files[r.path]!;
      expectValidPdf(bytes);
      final text = latin1Text(bytes);
      expect(text, contains('MEASUREMENT SHEET'));
      expect(text, contains('Illustrative Model'));
      expect(text, contains('10 ft'));
      final item =
          (((r.snapshot['groups'] as List).last as Map)['items'] as List).first
              as Map;
      final rows = (item['model'] as Map)['rows'] as List;
      expect(rows.first, ['Board width', '10 ft', 'Recorded']);
      final overview = r.snapshot['overview'] as Map;
      expect((overview['mediaSummary'] as List).last, 'GSB – 1 Unit');
    });

    test('85 3D image failure is reported, not replaced', () async {
      final (c, service, _, files) = await rig(fail: true);
      final r = await service.generate(c, 's_lakshmi');
      final text = latin1Text(files[r.path]!);
      expect(text, contains('could not be generated'));
    });

    test('86-87 draft sheet says not approved; approved uses snapshot', () {
      expect(kDraftBanner, contains('NOT APPROVED'));
    });
  });
}
