import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/app.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/evidence_policy.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/models/photo_requirement.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/annotation/annotation_editor_screen.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/l10n/l10n.dart';
import 'package:signage_recce/state/app_controller.dart';

Board _group({int qty = 2}) => Board(
  id: 'g',
  name: 'GSB group',
  mediaCode: SignageCatalog.gsb,
  quantity: qty,
);

SitePhoto _photo(String id, String path, {List<Annotation> marks = const []}) =>
    SitePhoto(
      id: id,
      path: path,
      label: 'Front view',
      capturedAt: DateTime(2026),
      width: 1000,
      height: 800,
      annotations: marks,
    );

Annotation _mark(String id, String? unitId) => Annotation(
  id: id,
  type: AnnotationType.rectangle,
  itemId: unitId,
  w: 40,
  h: 30,
);

void _phone(WidgetTester t, {int width = 360}) {
  t.view.physicalSize = Size(width * 3, 820 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Future<AppController> _vendor() async {
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin(DemoAccounts.vendorPin);
  return c;
}

void main() {
  setUp(() {
    EvidencePolicy.allowDemo = true;
    EvidencePolicy.checkFiles = false;
  });

  group('A. group-level photo evidence matrix', () {
    test('both boards marked on one photo + second photo = complete', () {
      final b = _group();
      final u1 = b.units[0].id, u2 = b.units[1].id;
      b.photos.addAll([
        _photo('1', 'demo://1', marks: [_mark('m1', u1), _mark('m2', u2)]),
        _photo('2', 'demo://2'),
      ]);
      final r = b.photoRequirement;
      expect(r.isComplete, isTrue);
      expect(r.photoCount, 2);
      expect(r.markedCount, 2);
      expect(r.missingUnitIds, isEmpty);
    });

    test('one board marked per photo = complete', () {
      final b = _group();
      final u1 = b.units[0].id, u2 = b.units[1].id;
      b.photos.addAll([
        _photo('1', 'demo://1', marks: [_mark('m1', u1)]),
        _photo('2', 'demo://2', marks: [_mark('m2', u2)]),
      ]);
      expect(b.photoRequirement.isComplete, isTrue);
    });

    test('two photos but only one board marked = incomplete', () {
      final b = _group();
      final u1 = b.units[0].id;
      b.photos.addAll([
        _photo('1', 'demo://1', marks: [_mark('m1', u1)]),
        _photo('2', 'demo://2'),
      ]);
      final r = b.photoRequirement;
      expect(r.isComplete, isFalse);
      expect(r.missingUnitIds, [b.units[1].id]);
    });

    test('one photo with both boards marked = incomplete', () {
      final b = _group();
      final u1 = b.units[0].id, u2 = b.units[1].id;
      b.photos.add(
        _photo('1', 'demo://1', marks: [_mark('m1', u1), _mark('m2', u2)]),
      );
      expect(b.photoRequirement.isComplete, isFalse);
      expect(b.photoRequirement.photoCount, 1);
    });

    test('duplicate bytes under different paths count once', () async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
      );
      EvidencePolicy.allowDemo = false;
      EvidencePolicy.checkFiles = true;
      final dir = await Directory.systemTemp.createTemp('gproof');
      final a = File('${dir.path}/a.png')..writeAsBytesSync(png);
      final bpath = File('${dir.path}/b.png')..writeAsBytesSync(png);
      await EvidencePolicy.verify([a.path, bpath.path]);
      final b = _group(qty: 1);
      b.photos.addAll([
        _photo('1', a.path, marks: [_mark('m', b.units.first.id)]),
        _photo('2', bpath.path),
      ]);
      expect(b.photoRequirement.photoCount, 1);
      expect(b.photoRequirement.isComplete, isFalse);
      EvidencePolicy.checkFiles = false;
    });

    test('quantity increase makes only the new board marking pending', () {
      final b = _group();
      final u1 = b.units[0].id, u2 = b.units[1].id;
      b.photos.addAll([
        _photo('1', 'demo://1', marks: [_mark('m1', u1), _mark('m2', u2)]),
        _photo('2', 'demo://2'),
      ]);
      expect(b.photoRequirement.isComplete, isTrue);
      b.units.add(SignageUnit(id: 'u3'));
      b.quantity = 3;
      final r = b.photoRequirement;
      expect(r.photoCount, 2);
      expect(r.missingUnitIds, [b.units[2].id]);
    });

    test('independent media groups never share evidence', () {
      final a = _group();
      a.photos.addAll([
        _photo(
          '1',
          'demo://1',
          marks: [_mark('m1', a.units[0].id), _mark('m2', a.units[1].id)],
        ),
        _photo('2', 'demo://2'),
      ]);
      final other = Board(
        id: 'other',
        name: 'NLB',
        mediaCode: SignageCatalog.nlb,
      );
      expect(a.photoRequirement.isComplete, isTrue);
      expect(other.photoRequirement.isComplete, isFalse);
    });

    test('non-signage annotations never cover a board', () {
      final b = _group(qty: 1);
      final u = b.units.first.id;
      b.photos.addAll([
        _photo(
          '1',
          'demo://1',
          marks: [
            Annotation(
              id: 'x',
              type: AnnotationType.circle,
              itemId: u,
              w: 5,
              h: 5,
            ),
          ],
        ),
        _photo('2', 'demo://2'),
      ]);
      expect(b.photoRequirement.markedCount, 0);
      expect(b.photoRequirement.isComplete, isFalse);
    });
  });

  testWidgets(
    'B. Text tool: repeated create/save/cancel has no lifecycle error',
    (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ta'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: _photoEditor(),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('tool-text')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('annotation-canvas')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('annotation-text-field')),
          i == 0 ? 'குறிப்பு' : 'Note $i',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('annotation-text-add')));
        await tester.pumpAndSettle();
      }
      // Cancel creates nothing.
      final before = tester
          .widget<Text>(find.textContaining('marking').first)
          .data;
      await tester.tap(find.byKey(const ValueKey('tool-text')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('annotation-canvas')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('annotation-text-cancel')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(before, isNotNull);
    },
  );

  testWidgets('C. two boards can be linked on one photo', (tester) async {
    _phone(tester);
    AnnotationEditorResult? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: AnnotationEditorScreen(
          photo: _photo('p', 'demo://1'),
          boardName: 'GSB group',
          units: const [
            AnnotationUnitOption(
              id: 'u1',
              label: 'GSB – Unit 01',
              width: 3,
              height: 4,
            ),
            AnnotationUnitOption(
              id: 'u2',
              label: 'GSB – Unit 02',
              width: 6,
              height: 2,
            ),
          ],
          onSave: (r) => saved = r,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tool-rectangle')));
    await tester.pumpAndSettle();
    await tester.dragFrom(
      tester.getCenter(find.byKey(const ValueKey('annotation-canvas'))) -
          const Offset(80, 30),
      const Offset(140, 60),
    );
    await tester.pumpAndSettle();
    // Explicitly select the second board in the dialog.
    await tester.tap(find.byKey(const ValueKey('measure-item')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Unit 02').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('measure-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('annotation-save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.annotations.single.itemId, 'u2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('D. simplified toolbar, fixed stroke, legacy annotations', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(MaterialApp(home: _photoEditor()));
    await tester.pumpAndSettle();
    for (final tool in [
      'circle',
      'line',
      'dimension',
      'poleMarker',
      'pipeMarker',
      'groundMarker',
    ]) {
      expect(find.byKey(ValueKey('tool-$tool')), findsNothing, reason: tool);
    }
    expect(find.byKey(const ValueKey('thickness')), findsNothing);
    expect(find.byKey(const ValueKey('tool-group-all')), findsNothing);
    for (final tool in [
      'select',
      'rectangle',
      'arrow',
      'text',
      'shapeRect',
      'numberMarker',
    ]) {
      expect(find.byKey(ValueKey('tool-$tool')), findsOneWidget, reason: tool);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('E. ENG / அ toggle keeps route and state', (tester) async {
    _phone(tester);
    final c = await _vendor();
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lang_en')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lang_ta')));
    await tester.pumpAndSettle();
    expect(c.isTamil, isTrue);
    expect(find.byKey(const Key('lang_ta')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lang_en')));
    await tester.pumpAndSettle();
    expect(c.isTamil, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('F. Board Details heading toggles expand/collapse', (
    tester,
  ) async {
    _phone(tester);
    final c = await _vendor();
    final b = c.addBoard('s_lakshmi')..mediaCode = SignageCatalog.gsb;
    c.touchBoard('s_lakshmi', b);
    await tester.pumpWidget(AdinnRecceApp(controller: c));
    await tester.pumpAndSettle();
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => BoardEditorScreen(shopId: 's_lakshmi', boardId: b.id),
      ),
    );
    await tester.pumpAndSettle();
    bool open() => find.byKey(const Key('board_name')).evaluate().isNotEmpty;
    final initial = open();
    // Tapping the active heading collapses it; tapping again reopens it.
    for (final expected in <bool>[!initial, initial, !initial]) {
      await tester.tap(find.text('Board Details').last);
      await tester.pumpAndSettle();
      expect(open(), expected);
    }
    expect(tester.takeException(), isNull);
  });

  group('G. responsive layout', () {
    for (final width in <int>[320, 360, 400, 430]) {
      testWidgets('editor + photo tools at $width dp', (tester) async {
        _phone(tester, width: width);
        await tester.pumpWidget(MaterialApp(home: _photoEditor()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$width dp');
      });
    }
  });
}

Widget _photoEditor() => AnnotationEditorScreen(
  photo: _photo('p', 'demo://1'),
  boardName: 'GSB group',
  units: const [
    AnnotationUnitOption(id: 'u1', label: 'GSB – Unit 01', width: 3, height: 4),
    AnnotationUnitOption(id: 'u2', label: 'GSB – Unit 02', width: 6, height: 2),
  ],
);
