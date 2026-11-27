import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/features/annotation/annotation_editor_screen.dart';
import 'package:signage_recce/l10n/l10n.dart';

SitePhoto _photo() => SitePhoto(
  id: 'p',
  path: 'demo://3',
  label: 'Front view',
  capturedAt: DateTime(2026),
  width: 1200,
  height: 900,
);

void main() {
  testWidgets('PROBE text annotation repeated', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: AnnotationEditorScreen(photo: _photo(), boardName: 'Board 1'),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('tool-text')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('annotation-canvas')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('annotation-text-field')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('annotation-text-field')),
        'Note $i',
      );
      await tester.pump();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
