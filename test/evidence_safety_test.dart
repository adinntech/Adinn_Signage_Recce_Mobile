import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/evidence_policy.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/models/photo_requirement.dart';
import 'package:signage_recce/features/survey/feasibility.dart';

import 'support/evidence_fixture.dart';

Board _board() => Board(
  id: 'b',
  name: 'b',
  mediaCode: SignageCatalog.gsb,
  installationCode: 'double_pole',
);

void main() {
  tearDown(() {
    EvidencePolicy.allowDemo = true; // test default (flutter_test_config)
    EvidencePolicy.checkFiles = false;
  });

  group('Production evidence', () {
    test('demo photos complete a recce only in explicit demo / test mode', () {
      final b = _board();
      b.photos.addAll(validEvidence(b)); // demo:// photos + a real marking
      expect(b.photoRequirementOf(b.units.first).isComplete, isTrue);
      EvidencePolicy.allowDemo = false; // production
      final r = b.photoRequirementOf(b.units.first);
      expect(r.isComplete, isFalse);
      expect(r.photoCount, 0);
      expect(r.messages, contains('Capture at least two site photos'));
    });

    // 1x1 PNG.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
    );

    testWidgets(
      'missing / empty / corrupt files never count; checks are cached, not per rebuild',
      (tester) async {
        await tester.runAsync(() async {
          EvidencePolicy.allowDemo = false;
          EvidencePolicy.checkFiles = true;
          final dir = await Directory.systemTemp.createTemp('ev');
          addTearDown(() => dir.delete(recursive: true));
          final good1 = File('${dir.path}/a.png')..writeAsBytesSync(png);
          // Distinct content (trailing byte after IEND is ignored by decoders):
          // identical bytes under different filenames count only once.
          final good2 = File('${dir.path}/b.png')
            ..writeAsBytesSync([...png, 0]);
          final empty = File('${dir.path}/c.jpg')..writeAsBytesSync([]);
          final corrupt = File('${dir.path}/d.jpg')
            ..writeAsBytesSync(List.filled(200, 7));
          final b = _board();
          final u = b.units.first;
          SitePhoto ph(String id, String path, {bool mark = false}) =>
              SitePhoto(
                id: id,
                path: path,
                label: 'Front view',
                capturedAt: DateTime(2026),
                width: 10,
                height: 10,
                annotations: mark
                    ? [
                        Annotation(
                          id: 'm$id',
                          type: AnnotationType.rectangle,
                          itemId: u.id,
                          w: 10,
                          h: 5,
                        ),
                      ]
                    : null,
              );
          b.photos.addAll([
            ph('1', good1.path, mark: true),
            ph('2', good2.path),
            ph('3', empty.path),
            ph('4', '${dir.path}/gone.jpg'),
            ph('5', corrupt.path),
          ]);
          await EvidencePolicy.verify(b.photos.map((p) => p.path));
          expect(EvidencePolicy.isUsable(good1.path), isTrue);
          expect(EvidencePolicy.isUsable(empty.path), isFalse);
          expect(
            EvidencePolicy.isUsable(corrupt.path),
            isFalse,
            reason: 'unreadable / corrupt image',
          );
          expect(EvidencePolicy.isUsable('${dir.path}/gone.jpg'), isFalse);
          final r = b.photoRequirementOf(u);
          expect(r.photoCount, 2, reason: 'only the two readable originals');
          expect(r.isComplete, isTrue);
          // The marked photo disappears from disk: requirement is back at once.
          good1.deleteSync();
          EvidencePolicy.forget(good1.path);
          await EvidencePolicy.verify([good1.path]);
          expect(b.photoRequirementOf(u).isComplete, isFalse);
        });
      },
    );
  });

  group('Signage marking identity and deletion', () {
    test(
      'only the Signage tool type counts: Rect / circle / arrow / text never do',
      () {
        final b = Board(id: 'b', name: 'b', mediaCode: SignageCatalog.gsb);
        final u = b.units.first;
        SitePhoto ph(String id, String path, List<Annotation> a) => SitePhoto(
          id: id,
          path: path,
          label: 'x',
          capturedAt: DateTime(2026),
          width: 10,
          height: 10,
          annotations: a,
        );
        b.photos.addAll([
          ph('1', 'demo://1', [
            for (final t in [
              AnnotationType.shapeRect,
              AnnotationType.circle,
              AnnotationType.arrow,
              AnnotationType.text,
              AnnotationType.freehand,
              AnnotationType.numberMarker,
            ])
              Annotation(id: 'a${t.name}', type: t, itemId: u.id, w: 50, h: 30),
          ]),
          ph('2', 'demo://2', const []),
        ]);
        expect(b.photoRequirementOf(u).markingCount, 0);
        b.photos.first.annotations.add(
          Annotation(id: 's', type: AnnotationType.rectangle, w: 50, h: 30),
        );
        expect(
          b.photoRequirementOf(u).isComplete,
          isTrue,
          reason: 'the Signage rectangle of a single-board group',
        );
      },
    );

    test('generated previews / AR shots are never original site photos', () {
      final b = Board(id: 'b', name: 'b', mediaCode: SignageCatalog.gsb);
      b.previews.add(
        PreviewCapture(
          id: 'pv',
          kind: CaptureKind.live,
          projectId: 'p',
          taskId: 't',
          shopId: 's',
          groupId: b.id,
          unitId: b.units.first.id,
          path: 'demo://9',
          createdAt: DateTime(2026),
        ),
      );
      expect(b.photoRequirementOf(b.units.first).photoCount, 0);
    });
  });

  group('Installation safety', () {
    test('Not Assessed is never treated as safe', () {
      final b = _board();
      final u = b.units.first;
      expect(feasibilityOf(b, u).level, SiteFeasibility.noKnownObstruction);
      u.checklist['underground_utilities'] = ChecklistResponse(
        questionId: 'underground_utilities',
        value: 'na',
      );
      final f = feasibilityOf(b, u);
      expect(f.level, SiteFeasibility.requiresReview);
      expect(f.reasons.single, contains('not assessed'));
    });

    test('safety checks share one Installation Safety section', () {
      final b = _board();
      final q = SignageCatalog.questionsForUnit(
        b,
        b.units.first,
      ).firstWhere((e) => e.id == 'excavation_permission');
      expect(
        SignageCatalog.questionSectionFor(b, b.units.first, q),
        'Installation Safety',
      );
    });
  });
}
