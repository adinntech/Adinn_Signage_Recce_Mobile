import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:signage_recce/features/gsb/gsb_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/photos/photo_section.dart';
import 'package:signage_recce/state/app_controller.dart';

void main() {
  Future<(AppController, Board)> boot(WidgetTester tester, String media) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = AppController(store: MemoryLocalStore());
    await c.init();
    c.loginWithPin('5678');
    final b = c.addBoard('s_lakshmi')..mediaCode = media;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PhotoSection(
                shopId: 's_lakshmi',
                board: b,
                editable: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (c, b);
  }

  // Every media type asks for the angle and stores it on the photo.
  for (final media in [
    SignageCatalog.gsb,
    SignageCatalog.nlb,
    SignageCatalog.foamVinyl,
    SignageCatalog.clearAcrylic,
    SignageCatalog.oneWayVision,
    SignageCatalog.plainVinyl,
    SignageCatalog.mdf,
  ]) {
    testWidgets('$media: angle popup lists the 7 angles and saves the pick', (
      tester,
    ) async {
      final (_, b) = await boot(tester, media);
      final before = b.photos.length;
      await tester.tap(find.text('Add sample photo (demo / no camera)'));
      await tester.pumpAndSettle();
      expect(find.text('Which angle is this photo?'), findsOneWidget);
      for (final l in [
        'Front view',
        'Left angle',
        'Right angle',
        'Back view',
        'Close-up',
        'Long shot',
        'Surroundings',
      ]) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      await tester.tap(find.text('Back view'));
      await tester.pumpAndSettle();
      expect(b.photos.length, before + 1);
      expect(b.photos.last.label, 'Back view');
    });
  }

  test('initial orientation follows the photo angle', () {
    expect(viewForAngleLabel('Front view')!.baseYaw, 0);
    expect(viewForAngleLabel('Left angle')!.baseYaw, closeTo(-math.pi / 2, 1e-9));
    expect(viewForAngleLabel('Right angle')!.baseYaw, closeTo(math.pi / 2, 1e-9));
    expect(viewForAngleLabel('Back view')!.baseYaw, closeTo(math.pi, 1e-9));
    // Other categories / historical labels stay neutral.
    for (final l in ['Close-up', 'Long shot', 'Surroundings', 'Site photo 1']) {
      expect(viewForAngleLabel(l), isNull, reason: l);
    }
  });
}
