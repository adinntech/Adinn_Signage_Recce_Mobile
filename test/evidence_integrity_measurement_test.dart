import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/evidence_policy.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/models/photo_requirement.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/annotation/annotation_editor_screen.dart';
import 'package:signage_recce/features/photos/annotation_apply.dart';
import 'package:signage_recce/state/app_controller.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

void main() {
  setUp(() {
    EvidencePolicy.allowDemo = false;
    EvidencePolicy.checkFiles = true;
    EvidencePolicy.invalidateAll();
  });
  tearDown(() {
    EvidencePolicy.checkFiles = false;
    EvidencePolicy.allowDemo = true;
  });

  group('EvidencePolicy integrity', () {
    test('unknown and verifying paths never count', () async {
      final dir = await Directory.systemTemp.createTemp('evstate');
      addTearDown(() => dir.delete(recursive: true));
      final p = File('${dir.path}/a.png')..writeAsBytesSync(_png);
      expect(EvidencePolicy.stateOf(p.path), EvidenceState.unknown);
      expect(EvidencePolicy.isUsable(p.path), isFalse);

      EvidencePolicy.markVerifying([p.path]);
      expect(EvidencePolicy.hasPending, isTrue);
      expect(EvidencePolicy.isUsable(p.path), isFalse);

      await EvidencePolicy.verify([p.path]);
      expect(EvidencePolicy.stateOf(p.path), EvidenceState.valid);
      expect(EvidencePolicy.hasPending, isFalse);
      expect(EvidencePolicy.isUsable(p.path), isTrue);
    });

    test('truncated image with a valid header is invalid', () async {
      final dir = await Directory.systemTemp.createTemp('evbad');
      addTearDown(() => dir.delete(recursive: true));
      final p = File('${dir.path}/bad.png')
        ..writeAsBytesSync(_png.sublist(0, _png.length ~/ 2));
      await EvidencePolicy.verify([p.path]);
      expect(EvidencePolicy.stateOf(p.path), EvidenceState.invalid);
      expect(EvidencePolicy.isUsable(p.path), isFalse);
    });

    test(
      'missing file is invalid; restored file becomes valid again',
      () async {
        final dir = await Directory.systemTemp.createTemp('evrestore');
        addTearDown(() => dir.delete(recursive: true));
        final p = File('${dir.path}/x.png')..writeAsBytesSync(_png);
        await EvidencePolicy.verify([p.path]);
        expect(EvidencePolicy.isUsable(p.path), isTrue);

        p.deleteSync();
        EvidencePolicy.forget(p.path);
        await EvidencePolicy.verify([p.path]);
        expect(EvidencePolicy.isUsable(p.path), isFalse);

        p.writeAsBytesSync(_png);
        EvidencePolicy.forget(p.path);
        await EvidencePolicy.verify([p.path]);
        expect(EvidencePolicy.isUsable(p.path), isTrue);
      },
    );

    test('replaced file content revalidates via metadata', () async {
      final dir = await Directory.systemTemp.createTemp('evreplace');
      addTearDown(() => dir.delete(recursive: true));
      final p = File('${dir.path}/y.png')..writeAsBytesSync(_png);
      await EvidencePolicy.verify([p.path]);
      final first = EvidencePolicy.fingerprintOf(p.path);
      p.writeAsBytesSync([..._png, 0]); // different bytes, decodable
      await EvidencePolicy.verify([p.path]);
      expect(EvidencePolicy.fingerprintOf(p.path), isNot(first));
    });

    test('duplicate bytes under different names use one fingerprint', () async {
      final dir = await Directory.systemTemp.createTemp('evdup');
      addTearDown(() => dir.delete(recursive: true));
      final a = File('${dir.path}/a.png')..writeAsBytesSync(_png);
      final b = File('${dir.path}/b.png')..writeAsBytesSync(_png);
      await EvidencePolicy.verify([a.path, b.path]);
      expect(
        EvidencePolicy.fingerprintOf(a.path),
        EvidencePolicy.fingerprintOf(b.path),
      );
    });

    test('demo photos are rejected with demo mode off', () {
      expect(EvidencePolicy.isUsable('demo://1'), isFalse);
      EvidencePolicy.allowDemo = true;
      expect(EvidencePolicy.isUsable('demo://1'), isTrue);
    });

    test('verified photos feed group readiness with real files', () async {
      final dir = await Directory.systemTemp.createTemp('evgroup');
      addTearDown(() => dir.delete(recursive: true));
      final a = File('${dir.path}/a.png')..writeAsBytesSync(_png);
      final b = File('${dir.path}/b.png')
        ..writeAsBytesSync([..._png, 0]); // distinct content
      await EvidencePolicy.verify([a.path, b.path]);
      final group = Board(
        id: 'g',
        name: 'g',
        mediaCode: SignageCatalog.gsb,
        quantity: 2,
      );
      group.photos.addAll([
        SitePhoto(
          id: '1',
          path: a.path,
          label: 'Front view',
          capturedAt: DateTime(2026),
          width: 10,
          height: 10,
          annotations: [
            Annotation(
              id: 'm1',
              type: AnnotationType.rectangle,
              itemId: group.units[0].id,
              w: 4,
              h: 3,
            ),
            Annotation(
              id: 'm2',
              type: AnnotationType.rectangle,
              itemId: group.units[1].id,
              w: 4,
              h: 3,
            ),
          ],
        ),
        SitePhoto(
          id: '2',
          path: b.path,
          label: 'Left angle',
          capturedAt: DateTime(2026),
          width: 10,
          height: 10,
        ),
      ]);
      expect(group.photoRequirement.photoCount, 2);
      expect(group.photoRequirement.isComplete, isTrue);
    });
  });

  group('Board-specific measurement application', () {
    Future<AppController> c() async {
      final ctrl = AppController(store: MemoryLocalStore());
      await ctrl.init();
      ctrl.loginWithPin(DemoAccounts.vendorPin);
      return ctrl;
    }

    Board group(AppController ctrl) {
      final created = ctrl.addBoard('s_lakshmi')
        ..mediaCode = SignageCatalog.gsb
        ..sizeMode = SizeMode.different
        ..width = 3
        ..height = 4;
      ctrl.increaseQuantity('s_lakshmi', created, 2);
      ctrl.touchBoard('s_lakshmi', created);
      final b = ctrl
          .shop('s_lakshmi')!
          .boards
          .firstWhere((x) => x.id == created.id);
      b.units[0]
        ..width = 3
        ..height = 4
        ..installationCode = SignageCatalog.shopFascia;
      b.units[1]
        ..width = 6
        ..height = 2
        ..installationCode = SignageCatalog.wallMount;
      ctrl.touchBoard('s_lakshmi', b);
      return ctrl.shop('s_lakshmi')!.boards.firstWhere((x) => x.id == b.id);
    }

    test('Board 02 update leaves Board 01 untouched', () async {
      final ctrl = await c();
      final b = group(ctrl);
      final u1 = b.units[0], u2 = b.units[1];
      final changed = applyAnnotationResult(
        ctrl,
        's_lakshmi',
        b,
        'p1',
        AnnotationEditorResult(
          annotations: const [],
          applyWidth: 7,
          applyHeight: 3,
          applyUnit: MeasureUnit.ft,
          applyUnitId: u2.id,
        ),
      );
      expect(changed, isTrue);
      expect(b.widthOf(u1), 3);
      expect(b.heightOf(u1), 4);
      expect(u1.installationCode, SignageCatalog.shopFascia);
      expect(b.widthOf(u2), 7);
      expect(b.heightOf(u2), 3);
      expect(u2.installationCode, SignageCatalog.wallMount);
    });

    test('Board 01 update leaves Board 02 untouched', () async {
      final ctrl = await c();
      final b = group(ctrl);
      final u1 = b.units[0], u2 = b.units[1];
      applyAnnotationResult(
        ctrl,
        's_lakshmi',
        b,
        'p1',
        AnnotationEditorResult(
          annotations: const [],
          applyWidth: 9,
          applyHeight: 5,
          applyUnit: MeasureUnit.ft,
          applyUnitId: u1.id,
        ),
      );
      expect(b.widthOf(u1), 9);
      expect(b.heightOf(u1), 5);
      expect(b.widthOf(u2), 6);
      expect(b.heightOf(u2), 2);
    });

    test(
      'missing or deleted target board never modifies another unit',
      () async {
        final ctrl = await c();
        final b = group(ctrl);
        final before1 = b.widthOf(b.units[0]);
        final before2 = b.widthOf(b.units[1]);
        final changed = applyAnnotationResult(
          ctrl,
          's_lakshmi',
          b,
          'p1',
          AnnotationEditorResult(
            annotations: const [],
            applyWidth: 8,
            applyHeight: 2,
            applyUnit: MeasureUnit.ft,
            applyUnitId: 'deleted_unit',
          ),
        );
        expect(changed, isFalse);
        expect(b.widthOf(b.units[0]), before1);
        expect(b.widthOf(b.units[1]), before2);
      },
    );

    test('Same Size mode updates the shared group value', () async {
      final ctrl = await c();
      final b = ctrl.addBoard('s_lakshmi')
        ..mediaCode = SignageCatalog.gsb
        ..width = 3
        ..height = 4;
      b.sizeMode = SizeMode.same;
      ctrl.touchBoard('s_lakshmi', b);
      final changed = applyAnnotationResult(
        ctrl,
        's_lakshmi',
        b,
        'p1',
        AnnotationEditorResult(
          annotations: const [],
          applyWidth: 5,
          applyHeight: 6,
          applyUnit: MeasureUnit.m,
          applyUnitId: b.units.first.id,
        ),
      );
      expect(changed, isTrue);
      expect(b.width, 5);
      expect(b.height, 6);
      expect(b.unit, MeasureUnit.m);
      expect(b.widthOf(b.units.first), 5);
    });
  });
}
