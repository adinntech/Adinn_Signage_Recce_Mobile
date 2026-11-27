import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/catalog/site_checklists.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/state/app_controller.dart';

/// Fills every missing required question of [u] by tapping / typing in the
/// visible unified Site Questions form (Site Questions + the remaining
/// checklist-only questions). Verified equivalents are answered once, as Site
/// Questions; evidence photos live in Site Photos & Annotation.
Future<void> answerThroughUi(
  WidgetTester tester,
  AppController c,
  Board b,
  SignageUnit u,
) async {
  Future<void> show(Finder f) async {
    expect(f, findsOneWidget, reason: 'widget for ${f.description}');
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  // Geometry inputs are entered in the Installation step (Installation
  // Measurements, covered by its own widget test); here they are completed
  // through the same controller call that form uses.
  for (final q in SignageCatalog.missingMeasurementsFor(b, u)) {
    c.setUnitAnswer('s_lakshmi', b, u, q.id, 5.0);
  }
  for (var guard = 0; guard < 8; guard++) {
    final qs = SignageCatalog.missingAnswersFor(b, u);
    final cl = SiteChecklists.uniqueMissing(b, u);
    if (qs.isEmpty && cl.isEmpty) break;
    for (final q in qs) {
      switch (q.type) {
        case QuestionType.yesNo:
          final f = find.byKey(Key('q_${q.id}_true'));
          await show(f);
          await tester.tap(f);
        case QuestionType.choice:
          final f = find.byKey(Key('q_${q.id}_${q.options.first}'));
          await show(f);
          await tester.tap(f);
        case QuestionType.number:
          final f = find.byKey(Key('q_${q.id}'));
          await show(f);
          await tester.enterText(f, '5');
        case QuestionType.text:
          final f = find.byKey(Key('q_${q.id}'));
          await show(f);
          await tester.enterText(f, 'ok');
      }
      await tester.pumpAndSettle();
    }
    for (final q in cl) {
      switch (q.type) {
        case ChecklistResponseType.yesNoNa:
          final f = find.byKey(Key('cl_${q.id}_yes'));
          await show(f);
          await tester.tap(f);
        case ChecklistResponseType.dropdown:
          final f = find.byKey(Key('cl_${q.id}'));
          await show(f);
          await tester.tap(f);
          await tester.pumpAndSettle();
          await tester.tap(find.text(q.options.first).last);
        case ChecklistResponseType.numeric:
          final f = find.byKey(Key('cl_${q.id}'));
          await show(f);
          await tester.enterText(f, '2');
        case ChecklistResponseType.shortText:
        case ChecklistResponseType.longText:
          final f = find.byKey(Key('cl_${q.id}'));
          await show(f);
          await tester.enterText(f, 'ok');
        case ChecklistResponseType.photoEvidence:
          break;
      }
      await tester.pumpAndSettle();
    }
  }
}
