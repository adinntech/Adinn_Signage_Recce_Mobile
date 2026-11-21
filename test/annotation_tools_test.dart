import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/features/annotation/annotation_editor_screen.dart';
import 'package:signage_recce/features/annotation/annotation_geometry.dart';
import 'package:signage_recce/features/annotation/annotation_painter.dart';

SitePhoto _photo({int w = 1200, int h = 900, List<Annotation>? items}) =>
    SitePhoto(
      id: 'p',
      path: 'demo://3',
      label: 'Front view',
      capturedAt: DateTime(2026),
      width: w,
      height: h,
      annotations: items,
    );

void _phone(WidgetTester tester) {
  addTearDown(tester.view.reset);
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
}

Future<void> _tool(WidgetTester tester, String name) async {
  final f = find.byKey(ValueKey('tool-$name'));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pump();
}

Offset _canvasCentre(WidgetTester tester) =>
    tester.getCenter(find.byKey(const ValueKey('annotation-canvas')));

void main() {
  group('annotation model & geometry (new tools)', () {
    test('type families and layers', () {
      expect(AnnotationType.line.isTwoPoint, isTrue);
      expect(AnnotationType.dimension.isTwoPoint, isTrue);
      expect(AnnotationType.freehand.isFreehand, isTrue);
      expect(AnnotationType.circle.isBox, isTrue);
      expect(AnnotationType.numberMarker.isMarker, isTrue);
      expect(AnnotationType.text.layer, AnnotationLayer.text);
      expect(AnnotationType.dimension.layer, AnnotationLayer.measurements);
      expect(AnnotationType.measureLabel.layer, AnnotationLayer.measurements);
      expect(AnnotationType.rectangle.layer, AnnotationLayer.placement);
      expect(AnnotationType.poleMarker.layer, AnnotationLayer.placement);
      expect(AnnotationType.freehand.layer, AnnotationLayer.drawing);
      expect(AnnotationType.arrow.layer, AnnotationLayer.drawing);
    });

    test('JSON round trip keeps thickness, item link and freehand path', () {
      final a = Annotation(
        id: 'f',
        type: AnnotationType.freehand,
        thickness: 2,
        itemId: 'b_u2',
        points: [1, 2, 3, 4.5],
        color: 0xFF1A73E8,
      );
      final back = Annotation.fromJson(a.toJson());
      expect(back.type, AnnotationType.freehand);
      expect(back.thickness, 2);
      expect(back.itemId, 'b_u2');
      expect(back.points, [1, 2, 3, 4.5]);
      // Defaults are not written (old readers see the same keys as before).
      final plain = Annotation(
        id: 'r',
        type: AnnotationType.rectangle,
      ).toJson();
      expect(plain.containsKey('thickness'), isFalse);
      expect(plain.containsKey('itemId'), isFalse);
      expect(plain.containsKey('points'), isFalse);
    });

    test('freehand hit test, move and bounds', () {
      final f = Annotation(
        id: 'f',
        type: AnnotationType.freehand,
        points: [100, 100, 200, 100, 200, 200],
      );
      expect(
        AnnotationGeometry.hitBody(f, const Offset(150, 102), tolerance: 4),
        isTrue,
      );
      expect(
        AnnotationGeometry.hitBody(f, const Offset(150, 150), tolerance: 4),
        isFalse,
      );
      AnnotationGeometry.translate(f, const Offset(10, -5));
      expect(f.points, [110, 95, 210, 95, 210, 195]);
      expect(
        AnnotationGeometry.bounds(f),
        const Rect.fromLTRB(110, 95, 210, 195),
      );
      expect(AnnotationGeometry.handlePositions(f, rotateOffset: 10), isEmpty);
    });

    test('addPathPoint skips points closer than minStep', () {
      final f = Annotation(id: 'f', type: AnnotationType.freehand);
      AnnotationGeometry.addPathPoint(f, const Offset(0, 0));
      AnnotationGeometry.addPathPoint(f, const Offset(1, 0), minStep: 2);
      AnnotationGeometry.addPathPoint(f, const Offset(3, 0), minStep: 2);
      expect(f.points, [0, 0, 3, 0]);
    });

    test('line / dimension use endpoint handles and move both ends', () {
      for (final t in [AnnotationType.line, AnnotationType.dimension]) {
        final a = Annotation(id: 'l', type: t, x: 10, y: 10, x2: 110, y2: 10);
        final h = AnnotationGeometry.handlePositions(a, rotateOffset: 5);
        expect(h.keys, [
          AnnotationHandle.arrowStart,
          AnnotationHandle.arrowEnd,
        ]);
        AnnotationGeometry.translate(a, const Offset(5, 5));
        expect((a.x, a.y, a.x2, a.y2), (15.0, 15.0, 115.0, 15.0));
        AnnotationGeometry.moveArrowEndpoint(
          a,
          AnnotationHandle.arrowEnd,
          const Offset(200, 50),
        );
        expect((a.x2, a.y2), (200.0, 50.0));
      }
    });

    test('markers and shapes resize and rotate like boxes', () {
      final m = Annotation(
        id: 'm',
        type: AnnotationType.poleMarker,
        x: 100,
        y: 100,
        w: 40,
        h: 40,
      );
      AnnotationGeometry.resizeFromCorner(
        m,
        AnnotationHandle.bottomRight,
        const Offset(150, 150),
      );
      expect(m.w, closeTo(70, 1e-9));
      expect(m.h, closeTo(70, 1e-9));
      expect(
        AnnotationGeometry.handlePositions(m, rotateOffset: 10).keys,
        contains(AnnotationHandle.rotate),
      );
    });

    test('hidden layers are skipped by hit testing', () {
      final items = [
        Annotation(
          id: 'rect',
          type: AnnotationType.rectangle,
          x: 100,
          y: 100,
          w: 100,
          h: 100,
        ),
        Annotation(
          id: 'txt',
          type: AnnotationType.text,
          x: 100,
          y: 100,
          w: 60,
          h: 20,
          label: 'Hi',
        ),
      ];
      expect(
        AnnotationGeometry.topmostVisibleAt(
          items,
          const Offset(100, 100),
          {},
        )?.id,
        'txt',
      );
      expect(
        AnnotationGeometry.topmostVisibleAt(items, const Offset(100, 100), {
          AnnotationLayer.text,
        })?.id,
        'rect',
      );
    });

    test('image-relative coordinates survive any display size', () {
      // Same photo pixel maps back exactly from different display scales
      // (zoom, rotation to landscape, thumbnail).
      const p = Offset(600, 450);
      for (final scale in [0.3, 1.0, 2.7]) {
        const origin = Offset(28, 40);
        final shown = AnnotationGeometry.imageToDisplay(p, scale, origin);
        final back = AnnotationGeometry.displayToImage(shown, scale, origin);
        expect(back.dx, closeTo(p.dx, 1e-9));
        expect(back.dy, closeTo(p.dy, 1e-9));
      }
    });

    test('painter draws every type (portrait & landscape) without errors', () {
      for (final size in const [Size(1200, 900), Size(900, 1600)]) {
        final items = [
          for (final t in AnnotationType.values)
            Annotation(
              id: t.name,
              type: t,
              x: 300,
              y: 300,
              w: 200,
              h: 80,
              x2: 600,
              y2: 500,
              label: t == AnnotationType.numberMarker ? '3' : 'Label',
              measureW: 8,
              measureH: 3,
              points: t == AnnotationType.freehand
                  ? [10, 10, 80, 90, 160, 40]
                  : null,
              thickness: 2,
            ),
        ];
        final painter = AnnotationPainter(
          annotations: items,
          imageSize: size,
          selectedId: 'freehand',
          showHandles: true,
          hiddenLayers: const {AnnotationLayer.text},
        );
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), const Size(400, 300));
        recorder.endRecording().dispose();
      }
      expect(
        AnnotationPainter.valueText(
          Annotation(
            id: 'd',
            type: AnnotationType.dimension,
            measureW: 12.5,
            label: 'Gap',
          ),
        ),
        'Gap: 12.5 ft',
      );
    });
  });

  group('advanced editor', () {
    testWidgets('circle, freehand pen, undo and redo', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: AnnotationEditorScreen(photo: _photo(), boardName: 'Board 1'),
        ),
      );
      await _tool(tester, 'circle');
      await tester.dragFrom(_canvasCentre(tester), const Offset(90, 60));
      await tester.pumpAndSettle();
      expect(find.text('1 marking'), findsOneWidget);

      await _tool(tester, 'freehand');
      final g = await tester.startGesture(
        _canvasCentre(tester) + const Offset(-80, -60),
      );
      for (var i = 1; i <= 8; i++) {
        await g.moveBy(const Offset(12, 6));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('2 markings'), findsOneWidget);

      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('1 marking'), findsOneWidget);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      expect(find.text('2 markings'), findsOneWidget);
    });

    testWidgets('numbered markers auto-increment; layers hide markings', (
      tester,
    ) async {
      _phone(tester);
      AnnotationEditorResult? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: AnnotationEditorScreen(
            photo: _photo(),
            boardName: 'Board 1',
            onSave: (r) => saved = r,
          ),
        ),
      );
      await _tool(tester, 'numberMarker');
      final c = _canvasCentre(tester);
      await tester.tapAt(c - const Offset(60, 0));
      await tester.pumpAndSettle();
      await tester.tapAt(c + const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 markings'), findsOneWidget);

      // Hide the placement layer (markers live there).
      await tester.tap(find.byKey(const ValueKey('layers')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('layer-placement')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // dismiss sheet
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.layers_clear_outlined), findsOneWidget);

      // Embedded save hands the data back without closing.
      await tester.tap(find.byKey(const ValueKey('annotation-save')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      final labels = saved!.annotations.map((a) => a.label).toList();
      expect(labels, ['1', '2']);
      expect(
        saved!.annotations.every((a) => a.type == AnnotationType.numberMarker),
        isTrue,
      );
      expect(find.text('Annotate photo'), findsOneWidget); // still open
    });

    testWidgets('placement rectangle links to the active signage unit', (
      tester,
    ) async {
      _phone(tester);
      AnnotationEditorResult? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: AnnotationEditorScreen(
            photo: _photo(),
            boardName: 'GSB group',
            units: const [
              AnnotationUnitOption(
                id: 'b_u1',
                label: 'GSB – Unit 01',
                width: 8,
                height: 3,
              ),
              AnnotationUnitOption(
                id: 'b_u2',
                label: 'GSB – Unit 02',
                width: 10,
                height: 4,
              ),
            ],
            activeUnitId: 'b_u2',
            onSave: (r) => saved = r,
          ),
        ),
      );
      await _tool(tester, 'rectangle');
      await tester.dragFrom(
        _canvasCentre(tester) - const Offset(80, 30),
        const Offset(160, 60),
      );
      await tester.pumpAndSettle();
      // Sheet opens prefilled from the unit.
      expect(find.text('Signage measurement'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('measure-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('annotation-save')));
      await tester.pumpAndSettle();
      final a = saved!.annotations.single;
      expect(a.itemId, 'b_u2');
      expect(a.label, 'GSB – Unit 02');
      expect((a.measureW, a.measureH), (10.0, 4.0));
    });

    testWidgets('dimension line asks for the measured value', (tester) async {
      _phone(tester);
      AnnotationEditorResult? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: AnnotationEditorScreen(
            photo: _photo(),
            boardName: 'B',
            onSave: (r) => saved = r,
          ),
        ),
      );
      await _tool(tester, 'dimension');
      await tester.dragFrom(_canvasCentre(tester), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(find.text('Dimension value'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('measure-value')),
        '6.5',
      );
      await tester.tap(find.byKey(const ValueKey('measure-save')));
      await tester.pumpAndSettle();
      // Thickness applies to the selected marking.
      await tester.tap(find.byKey(const ValueKey('thickness')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('annotation-save')));
      await tester.pumpAndSettle();
      final d = saved!.annotations.single;
      expect(d.type, AnnotationType.dimension);
      expect(d.measureW, 6.5);
      expect(d.thickness, 2);
    });
  });
}
