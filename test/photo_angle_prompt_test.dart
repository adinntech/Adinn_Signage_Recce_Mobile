import 'package:flutter/material.dart';
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

  for (final media in [SignageCatalog.gsb, SignageCatalog.nlb]) {
    testWidgets('$media: no angle popup, photo attached with a neutral label', (
      tester,
    ) async {
      final (_, b) = await boot(tester, media);
      final before = b.photos.length;
      await tester.tap(find.text('Add sample photo (demo / no camera)'));
      await tester.pumpAndSettle();
      expect(find.text('Which angle is this photo?'), findsNothing);
      expect(b.photos.length, before + 1);
      expect(b.photos.last.label, 'Site photo ${before + 1}');
      expect(b.photos.last.id, isNotEmpty);
      expect(b.photos.last.capturedAt, isNotNull);
    });
  }

  testWidgets('other media keep the angle prompt', (tester) async {
    final (_, b) = await boot(tester, SignageCatalog.acp);
    await tester.tap(find.text('Add sample photo (demo / no camera)'));
    await tester.pumpAndSettle();
    expect(find.text('Which angle is this photo?'), findsOneWidget);
    await tester.tap(find.text('Left angle'));
    await tester.pumpAndSettle();
    expect(b.photos.last.label, 'Left angle');
  });
}
