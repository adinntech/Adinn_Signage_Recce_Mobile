// Focused smoke: real Photo Editor widgets, isolated in-memory data and
// controlled photo fixtures. No emulator, camera hardware or production data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/evidence_policy.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/models/photo_requirement.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/annotation/annotation_editor_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Future<AppController> _session() async {
  EvidencePolicy.checkFiles = false;
  EvidencePolicy.allowDemo = true;
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin('5678');
  return c;
}

Board _group(AppController c) {
  final created = c.addBoard('s_lakshmi')
    ..mediaCode = SignageCatalog.gsb
    ..width = 3
    ..height = 4;
  c.increaseQuantity('s_lakshmi', created, 2);
  c.touchBoard('s_lakshmi', created);
  final b = c.shop('s_lakshmi')!.boards.firstWhere((x) => x.id == created.id);
  b.activeUnits.last
    ..width = 6
    ..height = 2
    ..installationCode = SignageCatalog.wallMount;
  b.activeUnits.first.installationCode = SignageCatalog.shopFascia;
  c.touchBoard('s_lakshmi', b);
  return b;
}

Future<void> _mark(WidgetTester t, String unitLabel) async {
  final tool = find.byKey(const ValueKey('tool-rectangle'));
  await t.tap(tool);
  await t.pumpAndSettle();
  await t.dragFrom(
    t.getCenter(find.byKey(const ValueKey('annotation-canvas'))) -
        const Offset(70, 30),
    const Offset(130, 60),
  );
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('measure-item')));
  await t.pumpAndSettle();
  await t.tap(find.textContaining(unitLabel).last);
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('measure-save')));
  await t.pumpAndSettle();
}

Future<void> _save(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('annotation-save')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('SMOKE: two boards marked on one shared photo + second photo', (
    tester,
  ) async {
    _phone(tester);
    final c = await _session();
    final b = _group(c);
    for (final (i, path) in ['demo://1', 'demo://2'].indexed) {
      c.addPhoto(
        's_lakshmi',
        b.id,
        SitePhoto(
          id: 'photo_$i',
          path: path,
          label: 'Front view',
          capturedAt: DateTime(2026),
          width: 1200,
          height: 900,
        ),
      );
    }
    AnnotationEditorResult? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: AnnotationEditorScreen(
          onSave: (r) => saved = r,
          photo: SitePhoto(
            id: 'photo_0',
            path: 'demo://1',
            label: 'Front view',
            capturedAt: DateTime(2026),
            width: 1200,
            height: 900,
          ),
          boardName: b.name,
          units: [
            for (final u in b.activeUnits)
              AnnotationUnitOption(
                id: u.id,
                label: '${b.unitLabel(u)} · ${b.widthOf(u)} × ${b.heightOf(u)}',
                width: b.widthOf(u),
                height: b.heightOf(u),
              ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _mark(tester, '01');
    await _save(tester);
    await _mark(tester, '02');
    await _save(tester);
    expect(saved, isNotNull);
    c.setAnnotations('s_lakshmi', b.id, 'photo_0', saved!.annotations);

    final fresh = c.shop('s_lakshmi')!.boards.firstWhere((x) => x.id == b.id);
    expect(fresh.photos.length, 2);
    expect(fresh.photoRequirement.photoCount, 2);
    expect(
      fresh.photoRequirement.isComplete,
      isTrue,
      reason: 'both boards marked, two shared group photos',
    );
    final ids = fresh.photos.first.annotations
        .where((a) => a.type == AnnotationType.rectangle)
        .map((a) => a.itemId)
        .toSet();
    expect(ids.length, 2, reason: 'two distinct physical board links');
    expect(tester.takeException(), isNull);
  });

  testWidgets('SMOKE: deleting one marking recalculates group readiness', (
    tester,
  ) async {
    _phone(tester);
    final c = await _session();
    final b = _group(c);
    final u1 = b.activeUnits[0].id, u2 = b.activeUnits[1].id;
    for (final (i, path) in ['demo://1', 'demo://2'].indexed) {
      c.addPhoto(
        's_lakshmi',
        b.id,
        SitePhoto(
          id: 'p$i',
          path: path,
          label: 'Front view',
          capturedAt: DateTime(2026),
          width: 1200,
          height: 900,
          annotations: [
            Annotation(
              id: 'm$i',
              type: AnnotationType.rectangle,
              itemId: i == 0 ? u1 : u2,
              w: 40,
              h: 30,
            ),
          ],
        ),
      );
    }
    final fresh = c.shop('s_lakshmi')!.boards.firstWhere((x) => x.id == b.id);
    expect(fresh.photoRequirement.isComplete, isTrue);
    fresh.photos.last.annotations.clear();
    expect(fresh.photoRequirement.isComplete, isFalse);
    expect(fresh.photoRequirement.missingUnitIds, [u2]);
    fresh.photos.last.annotations.add(
      Annotation(
        id: 'back',
        type: AnnotationType.rectangle,
        itemId: u2,
        w: 40,
        h: 30,
      ),
    );
    expect(fresh.photoRequirement.isComplete, isTrue);
  });
}
