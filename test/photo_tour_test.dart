import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/features/annotation/annotation_editor_screen.dart';
import 'package:signage_recce/features/annotation/photo_tour.dart';
import 'package:signage_recce/l10n/l10n.dart';

SitePhoto _ph(
  String id,
  String path, {
  List<Annotation>? marks,
  List<String>? units,
}) => SitePhoto(
  id: id,
  path: path,
  label: 'Front view',
  capturedAt: DateTime(2026),
  width: 1200,
  height: 900,
  annotations: marks,
  unitIds: units,
);

Annotation _mark(String id, String unit) => Annotation(
  id: id,
  type: AnnotationType.rectangle,
  itemId: unit,
  w: 100,
  h: 50,
);

Board _board({int qty = 1}) =>
    Board(id: 'b', name: 'b', mediaCode: SignageCatalog.gsb, quantity: qty);

PhotoTour _tourFor(Board b, SitePhoto added, [int unit = 0]) {
  b.photos.add(added);
  return PhotoTour.forNewPhoto(b, b.units[unit], added);
}

void _phone(WidgetTester t) {
  addTearDown(t.view.reset);
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 3;
}

void main() {
  group('Tour skip rules come from saved evidence', () {
    test('first photo: Skip allowed', () {
      final b = _board();
      expect(_tourFor(b, _ph('1', 'a.jpg')).canSkip, isTrue);
    });

    test('second photo without a marking: not skippable', () {
      final b = _board();
      b.photos.add(_ph('1', 'a.jpg')); // first photo skipped, unmarked
      expect(_tourFor(b, _ph('2', 'b.jpg')).canSkip, isFalse);
    });

    test('second photo after a saved marking: skippable', () {
      final b = _board();
      b.photos.add(_ph('1', 'a.jpg', marks: [_mark('m', b.units.first.id)]));
      expect(_tourFor(b, _ph('2', 'b.jpg')).canSkip, isTrue);
    });

    test('third and later photos follow the same saved-marking rule', () {
      final b = _board();
      b.photos
        ..add(_ph('1', 'a.jpg'))
        ..add(_ph('2', 'b.jpg'));
      expect(_tourFor(b, _ph('3', 'c.jpg')).canSkip, isFalse);
      b.photos.first.annotations.add(_mark('m', b.units.first.id));
      expect(
        PhotoTour.forNewPhoto(b, b.units.first, _ph('4', 'd.jpg')).canSkip,
        isTrue,
      );
      // The last valid marking is deleted: the next tour is compulsory again.
      b.photos.first.annotations.clear();
      expect(
        PhotoTour.forNewPhoto(b, b.units.first, _ph('5', 'e.jpg')).canSkip,
        isFalse,
      );
    });

    test('group rule: every active board must be marked before later Skip', () {
      final b = _board(qty: 2);
      final u1 = b.units[0].id, u2 = b.units[1].id;
      b.photos
        ..add(_ph('1', 'a.jpg', units: [u1, u2], marks: [_mark('m', u1)]))
        ..add(_ph('2', 'b.jpg', units: [u1, u2]));
      final new1 = _ph('3', 'c.jpg', units: [u1]);
      final new2 = _ph('4', 'd.jpg', units: [u2]);
      b.photos.addAll([new1, new2]);
      // Board 01 is covered but Board 02 is not: no silent bypass for either.
      expect(PhotoTour.forNewPhoto(b, b.units[0], new1).canSkip, isFalse);
      expect(PhotoTour.forNewPhoto(b, b.units[1], new2).canSkip, isFalse);
      // Marking Board 02 on ANY valid photo unlocks later Skip for the group.
      b.photos[1].annotations.add(_mark('m2', u2));
      expect(PhotoTour.forNewPhoto(b, b.units[1], new2).canSkip, isTrue);
      // A fresh tour object every time: nothing is remembered.
      expect(PhotoTour.forNewPhoto(b, b.units[1], new2).active, isTrue);
    });
  });

  group('Tour in the Photo Editor', () {
    Future<PhotoTour> pump(
      WidgetTester tester, {
      required bool canSkip,
      AnnotationEditorResult? Function()? out,
      void Function(AnnotationEditorResult)? onSave,
    }) async {
      _phone(tester);
      final tour = PhotoTour(canSkip: canSkip);
      await tester.pumpWidget(
        MaterialApp(
          home: AnnotationEditorScreen(
            photo: _ph('p', 'demo://3'),
            boardName: 'GSB',
            tour: tour,
            units: const [
              AnnotationUnitOption(
                id: 'u1',
                label: 'GSB – Unit 01',
                width: 8,
                height: 3,
              ),
            ],
            onSave: onSave ?? (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tour;
    }

    testWidgets(
      'first photo: steps run Signage -> canvas -> Save and Skip exists',
      (tester) async {
        AnnotationEditorResult? saved;
        final tour = await pump(
          tester,
          canSkip: true,
          onSave: (r) => saved = r,
        );
        expect(find.byKey(const Key('photo_tour')), findsOneWidget);
        expect(find.byKey(const Key('tour_skip')), findsOneWidget);
        expect(
          find.text('Open the photo to mark the proposed signage board.'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('tour_next')));
        await tester.pumpAndSettle();
        expect(
          find.text('Tap Signage to mark the board area.'),
          findsOneWidget,
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('tool-rectangle')),
        );
        await tester.tap(find.byKey(const ValueKey('tool-rectangle')));
        await tester.pumpAndSettle();
        expect(tour.step, 2);
        expect(
          find.text(
            'Mark the exact area where the signage board will be installed.',
          ),
          findsOneWidget,
        );

        await tester.dragFrom(
          tester.getCenter(find.byKey(const ValueKey('annotation-canvas'))) -
              const Offset(80, 30),
          const Offset(160, 60),
        );
        await tester.pumpAndSettle();
        expect(tour.step, 3);
        expect(find.text('Tap Save to keep the marking.'), findsOneWidget);
        expect(
          tour.active,
          isTrue,
          reason: 'not complete before the marking is saved',
        );
        await tester.tap(find.byKey(const ValueKey('measure-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('annotation-save')));
        await tester.pumpAndSettle();
        expect(saved!.annotations.single.itemId, 'u1');
        expect(
          tour.active,
          isFalse,
          reason: 'completed only by a saved marking',
        );
        expect(find.byKey(const Key('photo_tour')), findsNothing);
      },
    );

    testWidgets('Skip ends the first-photo tour without creating a marking', (
      tester,
    ) async {
      AnnotationEditorResult? saved;
      final tour = await pump(tester, canSkip: true, onSave: (r) => saved = r);
      await tester.tap(find.byKey(const Key('tour_skip')));
      await tester.pumpAndSettle();
      expect(tour.active, isFalse);
      expect(saved, isNull);
      expect(find.text('1 marking'), findsNothing, reason: 'no fake marking');
    });

    testWidgets(
      'second photo without a marking has no Skip and stays until saved',
      (tester) async {
        final tour = await pump(tester, canSkip: false);
        expect(find.byKey(const Key('tour_skip')), findsNothing);
        expect(tour.skip(), isFalse);
        expect(tour.active, isTrue);
        await tester.tap(find.byKey(const Key('tour_next')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('tour_required')), findsOneWidget);
        // The editor stays fully usable underneath (not trapped).
        await tester.ensureVisible(
          find.byKey(const ValueKey('tool-rectangle')),
        );
        await tester.tap(find.byKey(const ValueKey('tool-rectangle')));
        await tester.pumpAndSettle();
        expect(tour.step, 2);
      },
    );

    testWidgets('tour text is Tamil in Tamil mode', (tester) async {
      _phone(tester);
      final tour = PhotoTour(canSkip: true);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ta'),
          supportedLocales: const [Locale('en'), Locale('ta')],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: AnnotationEditorScreen(
            photo: _ph('p', 'demo://3'),
            boardName: 'GSB',
            tour: tour,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'பலகை பொருத்த வேண்டிய இடத்தைக் குறிக்க புகைப்படத்தைத் திறக்கவும்.',
        ),
        findsOneWidget,
      );
    });
  });
}
