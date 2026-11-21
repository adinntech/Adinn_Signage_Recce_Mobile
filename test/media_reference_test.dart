import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/data/storage/media_storage.dart';
import 'package:signage_recce/features/model3d/signage_spec.dart';
import 'package:signage_recce/features/references/media_reference_detail_screen.dart';
import 'package:signage_recce/features/references/media_reference_library_screen.dart';
import 'package:signage_recce/features/references/reference_image_picker.dart';
import 'package:signage_recce/features/references/reference_rules.dart';
import 'package:signage_recce/state/app_controller.dart';

Future<AppController> _controller({
  MemoryLocalStore? store,
  String pin = DemoAccounts.vendorPin,
}) async {
  final c = AppController(store: store ?? MemoryLocalStore());
  await c.init();
  c.loginWithPin(pin);
  return c;
}

void _tickAll(AppController c, String id) {
  for (final check in TechnicalCheck.values) {
    c.setReferenceCheck(id, check, true);
  }
}

class _FakePicker implements ReferenceImagePicker {
  _FakePicker(this.path);

  final String? path;
  int calls = 0;

  @override
  Future<String?> pickAndStore(MediaStorage? media) async {
    calls++;
    return path;
  }
}

void main() {
  const gsb = SignageCatalog.gsb;
  const acp = SignageCatalog.acp;

  group('Media reference library', () {
    test('91 – every catalog media starts as Pending Reference', () async {
      final c = await _controller();
      expect(SignageCatalog.catalogCodes, hasLength(13));
      expect(c.mediaReferences, isEmpty);
      for (final code in SignageCatalog.catalogCodes) {
        expect(
          c.referenceLibraryStatus(code),
          ReferenceStatus.pendingReference,
        );
        expect(c.modelStatus(code), ModelStatus.illustrative);
        expect(c.referencesFor(code), isEmpty);
      }
    });

    test('92 – factory registration (collected, never approved)', () async {
      final c = await _controller();
      final before = c.data.activities.length;
      final r = c.registerReference(
        mediaCode: gsb,
        sourceCategory: ReferenceSourceCategory.factory,
        localPath: '/refs/gsb_front.jpg',
        owner: 'Factory QA',
        installationCode: SignageCatalog.shopFascia,
      );
      expect(r.status, ReferenceStatus.collected);
      expect(r.usageRights, ReferenceUsageRights.unknown);
      expect(r.isApproved, isFalse);
      expect(r.approvedByName, isNull);
      expect(r.approvedAt, isNull);
      expect(r.createdByName, c.currentUser!.name);
      expect(c.referenceLibraryStatus(gsb), ReferenceStatus.collected);
      expect(c.modelStatus(gsb), ModelStatus.referencePending);
      expect(c.data.activities.length, before + 1);
      expect(c.data.activities.last.title, 'Media reference registered');

      // A factory reference without a photo yet is just "pending".
      final placeholder = c.registerReference(
        mediaCode: acp,
        sourceCategory: ReferenceSourceCategory.factory,
      );
      expect(placeholder.status, ReferenceStatus.pendingReference);
      expect(
        () => c.submitReferenceForReview(placeholder.id),
        throwsStateError,
      );
      // Only catalog media can get references.
      expect(
        () => c.registerReference(
          mediaCode: 'not_a_media',
          sourceCategory: ReferenceSourceCategory.factory,
        ),
        throwsArgumentError,
      );
    });

    test('93 – external reference needs a URL; unknown rights block '
        'approval', () async {
      final store = MemoryLocalStore();
      final vendor = await _controller(store: store);
      expect(
        () => vendor.registerReference(
          mediaCode: gsb,
          sourceCategory: ReferenceSourceCategory.external,
        ),
        throwsArgumentError,
      );
      expect(
        () => vendor.registerReference(
          mediaCode: gsb,
          sourceCategory: ReferenceSourceCategory.external,
          sourceUrl: 'not a link',
        ),
        throwsArgumentError,
      );
      expect(vendor.mediaReferences, isEmpty);
      final r = vendor.registerReference(
        mediaCode: gsb,
        sourceCategory: ReferenceSourceCategory.external,
        sourceUrl: 'https://example.com/gsb-board.jpg',
      );
      expect(r.usageRights, ReferenceUsageRights.unknown);
      expect(r.localPath, isNull, reason: 'web images are never downloaded');
      expect(r.status, ReferenceStatus.collected);
      vendor.submitReferenceForReview(r.id);
      expect(r.status, ReferenceStatus.awaitingTechnicalReview);
      await vendor.flush();

      final biz = await _controller(
        store: store,
        pin: DemoAccounts.businessPin,
      );
      _tickAll(biz, r.id);
      expect(
        () => biz.approveReference(r.id),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('usage rights'),
          ),
        ),
      );
      biz.updateReference(r.id, usageRights: ReferenceUsageRights.notAllowed);
      expect(() => biz.approveReference(r.id), throwsStateError);
      biz.updateReference(
        r.id,
        usageRights: ReferenceUsageRights.permissionGranted,
      );
      biz.approveReference(r.id);
      expect(biz.mediaReference(r.id)!.isApproved, isTrue);
    });

    test('94 – approval metadata is set only by a reviewer approval', () async {
      final store = MemoryLocalStore();
      final vendor = await _controller(store: store);
      final r = vendor.registerReference(
        mediaCode: gsb,
        sourceCategory: ReferenceSourceCategory.internalSample,
        localPath: '/refs/sample.jpg',
        usageRights: ReferenceUsageRights.internalOwned,
      );
      vendor.submitReferenceForReview(r.id);
      expect(r.approvedByName, isNull);
      expect(r.approvedByRole, isNull);
      expect(r.approvedAt, isNull);
      await vendor.flush();

      final ops = await _controller(store: store, pin: DemoAccounts.opsPin);
      final id = r.id;
      _tickAll(ops, id);
      // Ticking checks alone never approves.
      expect(
        ops.mediaReference(id)!.status,
        ReferenceStatus.awaitingTechnicalReview,
      );
      expect(ops.mediaReference(id)!.approvedAt, isNull);
      ops.approveReference(id);
      final a = ops.mediaReference(id)!;
      expect(a.status, ReferenceStatus.approved);
      expect(a.approvedByName, ops.currentUser!.name);
      expect(a.approvedByRole, UserRole.recceOps);
      expect(a.approvedAt, isNotNull);
      expect(ops.modelStatus(gsb), ModelStatus.technicallyReviewed);
      expect(ops.referenceLibraryStatus(gsb), ReferenceStatus.approved);
      expect(ops.data.activities.last.kind, 'approved');
    });

    test(
      '95 – vendor cannot approve, check or reject; 7 checks needed',
      () async {
        final store = MemoryLocalStore();
        final vendor = await _controller(store: store);
        final r = vendor.registerReference(
          mediaCode: acp,
          sourceCategory: ReferenceSourceCategory.factory,
          localPath: '/refs/acp.jpg',
          usageRights: ReferenceUsageRights.licensed,
        );
        vendor.submitReferenceForReview(r.id);
        expect(vendor.canReviewReferences, isFalse);
        expect(() => vendor.approveReference(r.id), throwsStateError);
        expect(
          () => vendor.setReferenceCheck(r.id, TechnicalCheck.material, true),
          throwsStateError,
        );
        expect(() => vendor.rejectReference(r.id, 'no'), throwsStateError);
        expect(r.status, ReferenceStatus.awaitingTechnicalReview);
        expect(r.approvedByName, isNull);
        await vendor.flush();

        final biz = await _controller(
          store: store,
          pin: DemoAccounts.businessPin,
        );
        expect(biz.canReviewReferences, isTrue);
        for (final check in TechnicalCheck.values.skip(1)) {
          biz.setReferenceCheck(r.id, check, true);
        }
        expect(TechnicalCheck.values, hasLength(7));
        expect(
          () => biz.approveReference(r.id),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('6/7'),
            ),
          ),
        );
        biz.setReferenceCheck(r.id, TechnicalCheck.mediaType, true);
        biz.approveReference(r.id);
        expect(biz.mediaReference(r.id)!.isApproved, isTrue);
        expect(biz.mediaReference(r.id)!.approvedByRole, UserRole.businessTeam);
      },
    );

    test('96 – rejection keeps the reason; vendor may resubmit', () async {
      final store = MemoryLocalStore();
      final vendor = await _controller(store: store);
      final r = vendor.registerReference(
        mediaCode: gsb,
        sourceCategory: ReferenceSourceCategory.factory,
        localPath: '/refs/gsb.jpg',
        usageRights: ReferenceUsageRights.internalOwned,
      );
      vendor.submitReferenceForReview(r.id);
      await vendor.flush();

      final biz = await _controller(
        store: store,
        pin: DemoAccounts.businessPin,
      );
      expect(() => biz.rejectReference(r.id, '  '), throwsArgumentError);
      biz.setReferenceCheck(r.id, TechnicalCheck.material, true);
      biz.rejectReference(r.id, 'Frame not visible');
      final rej = biz.mediaReference(r.id)!;
      expect(rej.status, ReferenceStatus.rejected);
      expect(rej.rejectionReason, 'Frame not visible');
      expect(rej.rejectedByName, biz.currentUser!.name);
      expect(rej.rejectedAt, isNotNull);
      expect(rej.isApproved, isFalse);
      expect(biz.modelStatus(gsb), ModelStatus.referencePending);
      expect(biz.referenceLibraryStatus(gsb), ReferenceStatus.rejected);
      expect(biz.data.activities.last.kind, 'rejected');
      expect(biz.data.activities.last.message, contains('Frame not visible'));
      // A rejected reference cannot be approved.
      expect(() => biz.approveReference(r.id), throwsStateError);
      await biz.flush();

      final again = await _controller(store: store);
      final back = again.mediaReference(r.id)!;
      expect(back.rejectionReason, 'Frame not visible');
      again.submitReferenceForReview(r.id);
      expect(back.status, ReferenceStatus.awaitingTechnicalReview);
      expect(back.technicalChecks, isEmpty, reason: 'fresh review');
    });

    test('97 – missing reference falls back to the illustrative model', () {
      expect(modelStatusFor(const [], gsb), ModelStatus.illustrative);
      final other = MediaReference(
        id: 'mr_1',
        mediaCode: acp,
        sourceCategory: ReferenceSourceCategory.factory,
        createdAt: DateTime(2026, 11, 18),
        localPath: '/x.jpg',
        status: ReferenceStatus.collected,
      );
      expect(modelStatusFor([other], gsb), ModelStatus.illustrative);
      expect(modelStatusFor([other], acp), ModelStatus.referencePending);
      expect(modelStatusFor([other], 'unknown_code'), ModelStatus.illustrative);
      expect(libraryStatusFor([other], gsb), ReferenceStatus.pendingReference);
    });

    test('97b – no fabricated approvals in seed or parsed data', () async {
      final seed = buildSeedData();
      expect(seed.mediaReferences, isEmpty);
      expect(seed.toJson().containsKey('mediaReferences'), isFalse);

      // "approved" without approver name/time is read as awaiting review.
      final fake = MediaReference.fromJson({
        'id': 'mr_fake',
        'mediaCode': gsb,
        'status': 'approved',
        'sourceCategory': 'factory',
        'localPath': '/x.jpg',
      });
      expect(fake.status, ReferenceStatus.awaitingTechnicalReview);
      expect(fake.isApproved, isFalse);
      expect(modelStatusFor([fake], gsb), ModelStatus.referencePending);

      // Unknown enum names fall back safely; malformed entries are skipped.
      final odd = MediaReference.fromJson({
        'id': 'mr_odd',
        'mediaCode': gsb,
        'status': 'superApproved',
        'sourceCategory': 'satellite',
        'usageRights': 'whatever',
        'technicalChecks': {
          'material': true,
          'bogus': true,
          'frameAppearance': 1,
        },
      });
      expect(odd.status, ReferenceStatus.pendingReference);
      expect(odd.sourceCategory, ReferenceSourceCategory.internalSample);
      expect(odd.usageRights, ReferenceUsageRights.unknown);
      expect(odd.technicalChecks, {TechnicalCheck.material: true});
      final list = MediaReference.listFromJson([
        {'id': '', 'mediaCode': gsb},
        'garbage',
        odd.toJson(),
      ]);
      expect(list.map((r) => r.id), ['mr_odd']);
    });

    test('98 – replacing keeps the old record (superseded)', () async {
      final store = MemoryLocalStore();
      final vendor = await _controller(store: store);
      final old = vendor.registerReference(
        mediaCode: gsb,
        sourceCategory: ReferenceSourceCategory.factory,
        localPath: '/refs/old.jpg',
        usageRights: ReferenceUsageRights.internalOwned,
        owner: 'Old photographer',
      );
      vendor.submitReferenceForReview(old.id);
      await vendor.flush();
      final biz = await _controller(
        store: store,
        pin: DemoAccounts.businessPin,
      );
      _tickAll(biz, old.id);
      biz.approveReference(old.id);
      expect(biz.modelStatus(gsb), ModelStatus.technicallyReviewed);
      // Approved references are locked: edit is refused, replace allowed.
      expect(() => biz.updateReference(old.id, owner: 'x'), throwsStateError);
      await biz.flush();

      final v2 = await _controller(store: store);
      final fresh = v2.replaceReference(
        old.id,
        sourceCategory: ReferenceSourceCategory.factory,
        localPath: '/refs/new.jpg',
      );
      final kept = v2.mediaReference(old.id)!;
      expect(v2.referencesFor(gsb), hasLength(2));
      expect(kept.isSuperseded, isTrue);
      expect(kept.replacedById, fresh.id);
      expect(kept.owner, 'Old photographer');
      expect(kept.localPath, '/refs/old.jpg');
      expect(kept.approvedByName, isNotNull, reason: 'history kept');
      expect(fresh.supersedes, old.id);
      expect(fresh.status, ReferenceStatus.collected);
      expect(fresh.installationCode, kept.installationCode);
      // The replaced approval no longer counts.
      expect(v2.modelStatus(gsb), ModelStatus.referencePending);
      expect(v2.referencesFor(gsb, includeSuperseded: false), [fresh]);
      expect(
        () => v2.replaceReference(
          old.id,
          sourceCategory: ReferenceSourceCategory.factory,
        ),
        throwsStateError,
      );
    });

    test('98b – references persist through a controller reload', () async {
      final store = MemoryLocalStore();
      final vendor = await _controller(store: store);
      final ext = vendor.registerReference(
        mediaCode: SignageCatalog.nlb,
        sourceCategory: ReferenceSourceCategory.external,
        sourceUrl: 'https://example.com/nlb',
        owner: 'Web',
        label: 'NLB example',
        technicalNotes: 'Check frame depth',
      );
      vendor.submitReferenceForReview(ext.id);
      await vendor.flush();
      final biz = await _controller(
        store: store,
        pin: DemoAccounts.businessPin,
      );
      biz.updateReference(ext.id, usageRights: ReferenceUsageRights.licensed);
      _tickAll(biz, ext.id);
      biz.approveReference(ext.id);
      await biz.flush();

      final reloaded = await _controller(store: store);
      final r = reloaded.mediaReference(ext.id)!;
      expect(r.sourceCategory, ReferenceSourceCategory.external);
      expect(r.sourceUrl, 'https://example.com/nlb');
      expect(r.owner, 'Web');
      expect(r.label, 'NLB example');
      expect(r.usageRights, ReferenceUsageRights.licensed);
      expect(r.status, ReferenceStatus.approved);
      expect(r.allChecksPassed, isTrue);
      expect(r.approvedByRole, UserRole.businessTeam);
      expect(
        r.approvedAt!.toIso8601String(),
        biz.mediaReference(ext.id)!.approvedAt!.toIso8601String(),
      );
      expect(
        reloaded.modelStatus(SignageCatalog.nlb),
        ModelStatus.technicallyReviewed,
      );
      expect(store.data!['mediaReferences'], isA<List<dynamic>>());
    });
  });

  group('Media reference screens', () {
    Widget host(AppController c, Widget child) =>
        ChangeNotifierProvider<AppController>.value(
          value: c,
          child: MaterialApp(theme: AppTheme.light(), home: child),
        );

    testWidgets('library lists 13 media as Pending Reference', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final c = await _controller();
      await tester.pumpWidget(host(c, const MediaReferenceLibraryScreen()));
      await tester.pumpAndSettle();
      for (final code in SignageCatalog.catalogCodes) {
        await tester.scrollUntilVisible(
          find.byKey(Key('ref_media_$code')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(Key('ref_media_$code')), findsOneWidget);
      }
      expect(find.text('Pending Reference'), findsWidgets);
      expect(find.text('Approved'), findsNothing);
    });

    testWidgets('vendor adds an external link and a gallery photo; reviewer '
        'approves', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = MemoryLocalStore();
      final c = await _controller(store: store);
      final picker = _FakePicker('/app/references/pic.jpg');
      await tester.pumpWidget(
        host(c, MediaReferenceDetailScreen(mediaCode: gsb, picker: picker)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pending Reference'), findsWidgets);

      // External without URL → form error, nothing saved.
      await _tap(tester, const Key('ref_add'));
      await tester.pumpAndSettle();
      await _tap(tester, const Key('ref_source_external'));
      await tester.pumpAndSettle();
      await _tap(tester, const Key('ref_save'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ref_form_error')), findsOneWidget);
      expect(c.mediaReferences, isEmpty);
      await tester.enterText(
        find.byKey(const Key('ref_url')),
        'https://example.com/gsb.jpg',
      );
      await _tap(tester, const Key('ref_save'));
      await tester.pumpAndSettle();
      final ext = c.mediaReferences.single;
      expect(ext.sourceCategory, ReferenceSourceCategory.external);
      expect(ext.usageRights, ReferenceUsageRights.unknown);
      expect(find.byKey(Key('ref_card_${ext.id}')), findsOneWidget);

      // Factory photo from the (fake) gallery.
      await _tap(tester, const Key('ref_add'));
      await tester.pumpAndSettle();
      await _tap(tester, const Key('ref_source_factory'));
      await _tap(tester, const Key('ref_pick_image'));
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      await _tap(tester, const Key('ref_save'));
      await tester.pumpAndSettle();
      final photo = c.mediaReferences.firstWhere((r) => r.hasImage);
      expect(photo.localPath, '/app/references/pic.jpg');
      expect(photo.sourceCategory, ReferenceSourceCategory.factory);

      await tester.ensureVisible(find.byKey(Key('ref_submit_${photo.id}')));
      await tester.tap(find.byKey(Key('ref_submit_${photo.id}')));
      await tester.pumpAndSettle();
      expect(photo.status, ReferenceStatus.awaitingTechnicalReview);
      // Vendor sees no approve button.
      expect(find.byKey(Key('ref_approve_${photo.id}')), findsNothing);

      // Reviewer: record rights, tick 7 checks, approve.
      c.logout();
      c.loginWithPin(DemoAccounts.businessPin);
      c.updateReference(
        photo.id,
        usageRights: ReferenceUsageRights.internalOwned,
      );
      await tester.pumpAndSettle();
      final approve = find.byKey(Key('ref_approve_${photo.id}'));
      await tester.ensureVisible(approve);
      expect(tester.widget<FilledButton>(approve).onPressed, isNull);
      for (var n = 0; n < TechnicalCheck.values.length; n++) {
        final box = find.byKey(Key('ref_check_${n}_${photo.id}'));
        await tester.ensureVisible(box);
        await tester.tap(box);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(approve);
      expect(tester.widget<FilledButton>(approve).onPressed, isNotNull);
      await tester.tap(approve);
      await tester.pumpAndSettle();
      expect(c.mediaReference(photo.id)!.isApproved, isTrue);
      expect(c.modelStatus(gsb), ModelStatus.technicallyReviewed);
      await tester.fling(find.byType(ListView), const Offset(0, 3000), 3000);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('ref_model_status')),
          matching: find.text('Technically Reviewed'),
        ),
        findsOneWidget,
      );
    });
  });
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
}
