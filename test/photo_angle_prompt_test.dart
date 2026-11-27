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
    final created = c.addBoard('s_lakshmi')..mediaCode = media;
    c.touchBoard('s_lakshmi', created);
    c.addPhoto(
      's_lakshmi',
      created.id,
      SitePhoto(
        id: 'angle_$media',
        path: 'demo://angle_test',
        label: 'Front view',
        capturedAt: DateTime(2026, 11, 24),
        width: 100,
        height: 80,
        unitIds: [for (final u in created.activeUnits) u.id],
      ),
    );
    final b = c.shop('s_lakshmi')!.boards.firstWhere((x) => x.id == created.id);
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
      // The vendor-facing demo button is gone. Tests inject a controlled
      // fixture photo and open the existing angle-picker through its menu.
      await tester.longPress(find.byKey(Key('photo_tile_angle_$media')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Change angle label'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change angle label'));
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
        expect(find.text(l), findsWidgets, reason: l);
      }
      await tester.tap(find.text('Back view'));
      await tester.pumpAndSettle();
      expect(b.photos.length, 1);
      expect(b.photos.first.label, 'Back view');
    });
  }

  test('initial orientation follows the photo angle', () {
    expect(viewForAngleLabel('Front view')!.baseYaw, 0);
    expect(
      viewForAngleLabel('Left angle')!.baseYaw,
      closeTo(-math.pi / 2, 1e-9),
    );
    expect(
      viewForAngleLabel('Right angle')!.baseYaw,
      closeTo(math.pi / 2, 1e-9),
    );
    expect(viewForAngleLabel('Back view')!.baseYaw, closeTo(math.pi, 1e-9));
    // Other categories / historical labels stay neutral.
    for (final l in ['Close-up', 'Long shot', 'Surroundings', 'Site photo 1']) {
      expect(viewForAngleLabel(l), isNull, reason: l);
    }
  });
}
