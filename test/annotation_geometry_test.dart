import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/features/annotation/annotation_editor_screen.dart';
import 'package:signage_recce/features/annotation/annotation_geometry.dart';

Annotation rect({
  double x = 100,
  double y = 100,
  double w = 100,
  double h = 50,
  double rotation = 0,
}) => Annotation(
  id: 'r',
  type: AnnotationType.rectangle,
  x: x,
  y: y,
  w: w,
  h: h,
  rotation: rotation,
);

void expectOffset(Offset actual, Offset expected, {double eps = 1e-6}) {
  expect(actual.dx, closeTo(expected.dx, eps));
  expect(actual.dy, closeTo(expected.dy, eps));
}

void main() {
  group('AnnotationGeometry', () {
    test('rotated rect hit test follows rotation', () {
      // 100Ã—20 bar rotated 90Â° becomes vertical.
      bool hit(Offset p) => AnnotationGeometry.rotatedRectContains(
        centre: const Offset(100, 100),
        size: const Size(100, 20),
        rotation: math.pi / 2,
        point: p,
      );
      expect(hit(const Offset(100, 140)), isTrue);
      expect(hit(const Offset(140, 100)), isFalse);
      expect(hit(const Offset(100, 100)), isTrue);
    });

    test('hitBody uses tolerance', () {
      final a = rect();
      expect(AnnotationGeometry.hitBody(a, const Offset(152, 100)), isFalse);
      expect(
        AnnotationGeometry.hitBody(a, const Offset(152, 100), tolerance: 4),
        isTrue,
      );
    });

    test('resize keeps the opposite corner fixed (axis aligned)', () {
      final a = rect();
      AnnotationGeometry.resizeFromCorner(
        a,
        AnnotationHandle.bottomRight,
        const Offset(200, 160),
      );
      final tl = AnnotationGeometry.handlePositions(
        a,
        rotateOffset: 0,
      )[AnnotationHandle.topLeft]!;
      expectOffset(tl, const Offset(50, 75));
      expect(a.w, closeTo(150, 1e-9));
      expect(a.h, closeTo(85, 1e-9));
    });

    test('resize keeps the opposite corner fixed (rotated)', () {
      final a = rect(rotation: math.pi / 6);
      final before = AnnotationGeometry.handlePositions(a, rotateOffset: 0);
      final fixed = before[AnnotationHandle.topLeft]!;
      // Drag bottom-right outward along the box diagonal.
      final pointer =
          before[AnnotationHandle.bottomRight]! + const Offset(30, 40);
      AnnotationGeometry.resizeFromCorner(
        a,
        AnnotationHandle.bottomRight,
        pointer,
      );
      final after = AnnotationGeometry.handlePositions(a, rotateOffset: 0);
      expectOffset(after[AnnotationHandle.topLeft]!, fixed);
      expect(a.rotation, closeTo(math.pi / 6, 1e-12));
      expect(a.w, greaterThan(100));
      expect(a.h, greaterThan(50));
      // The dragged corner lands on the pointer when the pointer is valid.
      expectOffset(after[AnnotationHandle.bottomRight]!, pointer, eps: 1e-6);
    });

    test('resize enforces minimum size when dragged past the anchor', () {
      final a = rect();
      AnnotationGeometry.resizeFromCorner(
        a,
        AnnotationHandle.topLeft,
        const Offset(400, 400),
        minSize: 10,
      );
      expect(a.w, 10);
      expect(a.h, 10);
      final br = AnnotationGeometry.handlePositions(
        a,
        rotateOffset: 0,
      )[AnnotationHandle.bottomRight]!;
      expectOffset(br, const Offset(150, 125));
    });

    test('rotation from pointer is 0 straight above the centre', () {
      const c = Offset.zero;
      expect(
        AnnotationGeometry.rotationFromPointer(c, const Offset(0, -10)),
        closeTo(0, 1e-12),
      );
      expect(
        AnnotationGeometry.rotationFromPointer(c, const Offset(10, 0)),
        closeTo(math.pi / 2, 1e-12),
      );
      expect(
        AnnotationGeometry.rotationFromPointer(c, const Offset(0, 10)).abs(),
        closeTo(math.pi, 1e-12),
      );
      expect(
        AnnotationGeometry.rotationFromPointer(c, const Offset(-10, 0)),
        closeTo(-math.pi / 2, 1e-12),
      );
    });

    test('snapAngle snaps near multiples of 45Â°', () {
      expect(
        AnnotationGeometry.snapAngle(math.pi / 4 + 0.02),
        closeTo(math.pi / 4, 1e-12),
      );
      expect(AnnotationGeometry.snapAngle(0.3), closeTo(0.3, 1e-12));
    });

    test('arrow hit test is distance to the segment', () {
      final a = Annotation(
        id: 'a',
        type: AnnotationType.arrow,
        x: 0,
        y: 0,
        x2: 100,
        y2: 0,
      );
      expect(
        AnnotationGeometry.hitBody(a, const Offset(50, 3), tolerance: 5),
        isTrue,
      );
      expect(
        AnnotationGeometry.hitBody(a, const Offset(50, 10), tolerance: 5),
        isFalse,
      );
      expect(
        AnnotationGeometry.hitBody(a, const Offset(110, 0), tolerance: 5),
        isFalse,
      );
    });

    test('hitHandle finds rotate handle above the top edge', () {
      final a = rect();
      final h = AnnotationGeometry.hitHandle(
        a,
        const Offset(100, 75 - 30),
        radius: 6,
        rotateOffset: 30,
      );
      expect(h, AnnotationHandle.rotate);
      expect(
        AnnotationGeometry.hitHandle(
          a,
          const Offset(100, 100),
          radius: 6,
          rotateOffset: 30,
        ),
        isNull,
      );
    });

    test('translate moves both arrow ends', () {
      final a = Annotation(
        id: 'a',
        type: AnnotationType.arrow,
        x: 1,
        y: 2,
        x2: 3,
        y2: 4,
      );
      AnnotationGeometry.translate(a, const Offset(10, 20));
      expect([a.x, a.y, a.x2, a.y2], [11, 22, 13, 24]);
    });
  });

  group('AnnotationEditorScreen', () {
    testWidgets('draw a measured rectangle and save it', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;

      AnnotationEditorResult? result;
      final photo = SitePhoto(
        id: 'p',
        path: 'demo://1',
        label: 'Front view',
        capturedAt: DateTime(2026),
        width: 1200,
        height: 900,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(ctx).push(
                      MaterialPageRoute<AnnotationEditorResult>(
                        builder: (_) => AnnotationEditorScreen(
                          photo: photo,
                          boardName: 'Board 1',
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Annotate photo'), findsOneWidget);
      expect(find.text('0 markings'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tool-rectangle')));
      await tester.pump();

      final centre = tester.getCenter(
        find.byKey(const ValueKey('annotation-canvas')),
      );
      await tester.dragFrom(
        centre - const Offset(100, 50),
        const Offset(200, 110),
      );
      await tester.pumpAndSettle();

      // Measurement sheet opens for the new rectangle.
      expect(find.text('Signage measurement'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('measure-width')), '10');
      await tester.enterText(find.byKey(const ValueKey('measure-height')), '4');
      await tester.tap(find.byKey(const ValueKey('measure-save')));
      await tester.pumpAndSettle();

      expect(find.text('1 marking'), findsOneWidget);
      // Selected rectangle exposes the "Use as board size" action.
      final useSize = find.byKey(const ValueKey('action-board-size'));
      await tester.ensureVisible(useSize);
      await tester.pumpAndSettle();
      await tester.tap(useSize);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('annotation-save')));
      await tester.pumpAndSettle();
      // Let the "board size" snack bar time out so no timers stay pending.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.annotations, hasLength(1));
      final a = result!.annotations.single;
      expect(a.type, AnnotationType.rectangle);
      expect(a.label, 'Board 1');
      expect(a.measureW, 10);
      expect(a.measureH, 4);
      expect(a.w, greaterThan(100));
      expect(a.h, greaterThan(50));
      expect(result!.applyWidth, 10);
      expect(result!.applyHeight, 4);
      expect(result!.applyUnit, MeasureUnit.ft);
      // Original photo is untouched (editor works on copies).
      expect(photo.annotations, isEmpty);
    });

    testWidgets('undo removes the last marking', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(1080, 2070);
      tester.view.devicePixelRatio = 3;

      await tester.pumpWidget(
        MaterialApp(
          home: AnnotationEditorScreen(
            photo: SitePhoto(
              id: 'p',
              path: 'demo://2',
              label: 'Front view',
              capturedAt: DateTime(2026),
              width: 1200,
              height: 900,
            ),
            boardName: 'Board 1',
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('tool-arrow')));
      await tester.pump();
      final centre = tester.getCenter(
        find.byKey(const ValueKey('annotation-canvas')),
      );
      await tester.dragFrom(centre, const Offset(120, -60));
      await tester.pumpAndSettle();
      expect(find.text('1 marking'), findsOneWidget);

      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('0 markings'), findsOneWidget);
    });
  });
}
