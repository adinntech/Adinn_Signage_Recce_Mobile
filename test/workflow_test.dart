import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/core/utils/formatters.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/state/app_controller.dart';
import 'package:signage_recce/state/version_diff.dart';

import 'helpers.dart';

void main() {
  late MemoryLocalStore store;
  late AppController c;

  setUp(() async {
    store = MemoryLocalStore();
    c = AppController(store: store);
    await c.init();
  });

  group('auth', () {
    test('seed data and demo accounts are loaded', () {
      expect(c.isReady, isTrue);
      expect(c.data.users, hasLength(3));
      expect(c.data.projects.map((p) => p.name), contains('Asian Paints'));
      expect(c.isLoggedIn, isFalse);
    });

    test('PIN login picks the user by PIN alone', () {
      expect(c.loginWithPin(''), 'Enter your 4-digit PIN');
      expect(c.loginWithPin('56a8'), 'Enter your 4-digit PIN');
      expect(c.loginWithPin('56789'), 'Enter your 4-digit PIN');
      expect(c.loginWithPin('5678'), isNull);
      expect(c.currentUser!.role, UserRole.vendor);
      c.logout();
      expect(c.loginWithPin(DemoAccounts.businessPin), isNull);
      expect(c.currentUser!.role, UserRole.businessTeam);
      c.logout();
      expect(c.loginWithPin(DemoAccounts.opsPin), isNull);
      expect(c.currentUser!.role, UserRole.recceOps);
    });

    test('demo PINs are unique 4-digit PINs', () {
      final pins = c.data.users.map((u) => u.pin).toList();
      expect(pins.toSet(), hasLength(pins.length));
      expect(pins.every(AppController.isValidPin), isTrue);
    });

    test('wrong PINs count down and then lock entry', () {
      var now = DateTime(2026, 11, 17, 10);
      final locked = AppController(store: MemoryLocalStore(), clock: () => now);
      return locked.init().then((_) {
        expect(locked.loginWithPin('0000'), contains('4 attempts left'));
        for (var i = 0; i < 3; i++) {
          locked.loginWithPin('0000');
        }
        expect(locked.loginWithPin('0000'), contains('Locked for 30 seconds'));
        // Even the right PIN is refused while locked.
        expect(locked.loginWithPin('5678'), contains('Try again in'));
        expect(locked.isLoggedIn, isFalse);
        now = now.add(const Duration(seconds: 31));
        expect(locked.pinLockRemaining, isNull);
        expect(locked.loginWithPin('5678'), isNull);
      });
    });

    test('forgot PIN via registered mobile + OTP', () {
      expect(c.requestOtp('5678'), isNull); // PIN/ID is not a mobile
      expect(c.requestOtp('9000000000'), isNull);
      final otp = c.requestOtp('9876543210'); // vendor's mobile
      expect(otp, DemoAccounts.otp);
      expect(c.verifyOtp('000000'), isFalse);
      expect(c.verifyOtp(otp!), isTrue);
      expect(c.resetPin('12'), contains('4 digits'));
      expect(c.resetPin('7777'), contains('too easy'));
      // Another user's PIN can't be reused: PIN alone identifies the user.
      expect(c.resetPin(DemoAccounts.businessPin), contains('not available'));
      expect(c.resetPin('2580'), isNull);
      expect(c.loginWithPin('5678'), contains('Incorrect'));
      expect(c.loginWithPin('2580'), isNull);
      expect(c.currentUser!.role, UserRole.vendor);
    });

    test('change PIN', () {
      c.loginWithPin('5678');
      expect(c.changePin('0000', '2580'), 'Current PIN is incorrect');
      expect(c.changePin('5678', '5678'), 'New PIN must be different');
      expect(
        c.changePin('5678', DemoAccounts.opsPin),
        contains('not available'),
      );
      expect(c.changePin('5678', '2580'), isNull);
      c.logout();
      expect(c.loginWithPin('2580'), isNull);
    });

    test(
      'data saved with password login (schema 1) migrates to PINs',
      () async {
        final v1 = buildSeedData().toJson()..['schemaVersion'] = 1;
        for (final u in (v1['users'] as List).cast<Map<String, dynamic>>()) {
          u['password'] = u.remove('pin');
        }
        // Schema 1 had Business and Ops sharing password "1234".
        (v1['users'] as List).cast<Map<String, dynamic>>().last['password'] =
            '1234';
        final old = AppController(store: MemoryLocalStore(v1));
        await old.init();
        final pins = old.data.users.map((u) => u.pin).toList();
        expect(pins.toSet(), hasLength(3));
        expect(old.loginWithPin('5678'), isNull);
        expect(old.currentUser!.role, UserRole.vendor);
        old.logout();
        expect(old.loginWithPin('4321'), isNull);
        expect(old.currentUser!.role, UserRole.recceOps);
      },
    );
  });

  group('visibility', () {
    test('vendor sees assigned projects; reviewers see pending queues', () {
      c.loginWithPin('5678');
      expect(c.projects, hasLength(3));
      expect(c.visibleShops, hasLength(8));
      expect(c.pendingReviews, isEmpty);
      expect(c.mySubmissions.map((s) => s.id), contains('s_amma'));

      c.logout();
      c.loginWithPin(DemoAccounts.businessPin);
      expect(c.pendingReviews.map((s) => s.id), ['s_amma']);

      c.logout();
      c.loginWithPin(DemoAccounts.opsPin);
      expect(c.pendingReviews.map((s) => s.id), ['s_thillai_colour']);
    });

    test('task progress summary', () {
      c.loginWithPin('5678');
      final sum = c.taskSummary('t_srirangam');
      expect(sum.total, 3);
      expect(sum.inProgress, 1);
      expect(sum.notStarted, 1);
      expect(sum.pending, 1);
      expect(sum.label, 'In Progress');
    });
  });

  group('editing & validation', () {
    test('cannot submit an incomplete recce', () {
      c.loginWithPin('5678');
      final empty = c.shop('s_lakshmi')!;
      expect(c.shopIssues(empty), contains('Add at least one board'));
      expect(() => c.submitShop(empty.id), throwsStateError);

      final b = c.addBoard(empty.id);
      expect(empty.status, RecceStatus.inProgress);
      final issues = c.boardIssues(b);
      expect(issues, contains('Select a media type'));
      expect(issues, contains('Enter board width and height'));
      expect(issues, contains('Capture at least one site photo'));
    });

    test('installation must match media type', () {
      final b = Board(
        id: 'x',
        name: 'X',
        mediaCode: SignageCatalog.wallPainting,
        installationCode: SignageCatalog.doublePole,
      );
      expect(
        c.boardIssues(b),
        contains('Installation type not valid for Wall Paint'),
      );
    });

    test('dynamic questions depend on media + installation and showIf', () {
      final dp = SignageCatalog.questionsFor(
        SignageCatalog.gsb,
        SignageCatalog.doublePole,
      ).map((q) => q.id);
      expect(dp, containsAll(['pole_height', 'pole_gap', 'power_available']));
      final wall = SignageCatalog.questionsFor(
        SignageCatalog.wallPainting,
        SignageCatalog.directWall,
      ).map((q) => q.id);
      expect(wall, isNot(contains('pole_height')));
      expect(wall, contains('wall_surface'));

      final b = Board(
        id: 'y',
        name: 'Y',
        mediaCode: SignageCatalog.gsb,
        installationCode: SignageCatalog.wallMount,
      );
      completeAnswers(b);
      b.answers['power_available'] = false;
      expect(SignageCatalog.missingAnswers(b).map((q) => q.id), [
        'power_distance',
      ]);
    });

    test('catalog keeps the six original media types and adds standees', () {
      // 6 confirmed types + Single-Sided and Double-Sided Standee.
      expect(SignageCatalog.mediaTypes, hasLength(8));
      expect(SignageCatalog.mediaTypes.take(6).map((m) => m.code), [
        'GSB',
        'NLB',
        'ACP',
        'FLANGE',
        'VINYL',
        'WALL',
      ]);
      for (final m in SignageCatalog.mediaTypes) {
        expect(SignageCatalog.installationsFor(m.code), isNotEmpty);
      }
    });
  });

  group('approval workflow', () {
    test('submit → reject → resubmit → approve with versions & timeline', () {
      // Vendor completes and submits v1.
      c.loginWithPin('5678');
      final shop = c.shop('s_sriranga')!;
      final board = shop.boards.first;
      expect(c.shopIssues(shop), isNotEmpty); // seeded draft is incomplete
      completeAnswers(board);
      c.touchBoard(shop.id, board);
      expect(c.shopIssues(shop), ['Capture the shop GPS location']);
      c.setShopLocation(shop, gpsAt(10.86270, 78.68970));
      expect(c.shopIssues(shop), isEmpty);

      final v1 = c.submitShop(shop.id, remarks: 'Ready');
      expect(v1.version, 1);
      expect(shop.status, RecceStatus.pendingBusiness);
      expect(c.canEdit(shop), isFalse);
      expect(() => c.submitShop(shop.id), throwsStateError);

      // Business rejects (remarks mandatory).
      c.logout();
      c.loginWithPin(DemoAccounts.businessPin);
      expect(c.canReview(shop), isTrue);
      expect(
        () => c.reviewShop(shop.id, decision: ReviewDecision.rejected),
        throwsStateError,
      );
      c.reviewShop(
        shop.id,
        decision: ReviewDecision.rejected,
        remarks: 'Width looks wrong',
        reasons: ['Measurement mismatch'],
      );
      expect(shop.status, RecceStatus.rejectedBusiness);
      expect(v1.outcome, RecceStatus.rejectedBusiness);

      // Vendor fixes and resubmits v2.
      c.logout();
      c.loginWithPin('5678');
      expect(c.canEdit(shop), isTrue);
      board.width = 12;
      c.touchBoard(shop.id, board);
      final v2 = c.submitShop(shop.id);
      expect(v2.version, 2);
      expect(
        diffShops(v1.shopSnapshot, v2.shopSnapshot).join('\n'),
        contains('size 10 × 4 ft → 12 × 4 ft'),
      );
      // v1 snapshot is untouched by later edits.
      expect(v1.shopSnapshot.boards.first.width, 10);

      // Business approves, Ops rejects.
      c.logout();
      c.loginWithPin(DemoAccounts.businessPin);
      c.reviewShop(shop.id, decision: ReviewDecision.approved);
      expect(shop.status, RecceStatus.pendingOps);

      c.logout();
      c.loginWithPin(DemoAccounts.opsPin);
      expect(c.pendingReviews.map((s) => s.id), contains(shop.id));
      c.reviewShop(
        shop.id,
        decision: ReviewDecision.rejected,
        remarks: 'Foundation depth insufficient',
      );
      expect(shop.status, RecceStatus.rejectedOps);

      // Vendor resubmits v3 → Business → Ops final approval.
      c.logout();
      c.loginWithPin('5678');
      board.answers['foundation_depth'] = 4.0;
      c.touchBoard(shop.id, board);
      expect(c.submitShop(shop.id).version, 3);
      c.logout();
      c.loginWithPin(DemoAccounts.businessPin);
      c.reviewShop(shop.id, decision: ReviewDecision.approved);
      c.logout();
      c.loginWithPin(DemoAccounts.opsPin);
      c.reviewShop(shop.id, decision: ReviewDecision.approved, remarks: 'OK');
      expect(shop.status, RecceStatus.approved);
      expect(shop.submissions.map((s) => s.outcome), [
        RecceStatus.rejectedBusiness,
        RecceStatus.rejectedOps,
        RecceStatus.approved,
      ]);

      c.logout();
      c.loginWithPin('5678');
      expect(c.canEdit(shop), isFalse);
      final titles = c.activities(shopId: shop.id).map((e) => e.title).toList();
      expect(titles.first, 'Ops approved (v3) – Final');
      expect(titles, contains('Recce resubmitted (v2)'));
      expect(titles, contains('Business rejected (v1)'));
      expect(titles, contains('Ops rejected (v2)'));
    });

    test('vendor cannot review and reviewers cannot edit', () {
      c.loginWithPin('5678');
      final amma = c.shop('s_amma')!;
      expect(c.canReview(amma), isFalse);
      expect(
        () => c.reviewShop(amma.id, decision: ReviewDecision.approved),
        throwsStateError,
      );
      c.logout();
      c.loginWithPin(DemoAccounts.opsPin);
      expect(c.canEdit(c.shop('s_royal')!), isFalse);
      // Ops cannot act on something still with Business.
      expect(c.canReview(amma), isFalse);
    });

    test('Ops rejection goes back to the vendor for rework', () {
      c.loginWithPin(DemoAccounts.opsPin);
      final shop = c.shop('s_thillai_colour')!;
      c.reviewShop(
        shop.id,
        decision: ReviewDecision.rejected,
        remarks: 'Primer quote missing',
      );
      expect(shop.status, RecceStatus.rejectedOps);
      c.logout();
      c.loginWithPin(DemoAccounts.vendorPin);
      expect(c.canEdit(shop), isTrue);
      expect(c.mySubmissions.where((s) => s.status.isRejected), contains(shop));
      // Resubmission restarts the approval chain at Business.
      expect(c.submitShop(shop.id).version, 2);
      expect(shop.status, RecceStatus.pendingBusiness);
    });
  });

  group('GPS', () {
    test('haversine distance is accurate', () {
      // Srirangam temple → Trichy Rockfort is about 3.3 km.
      final d = GeoFix.distanceMetres(10.8627, 78.6897, 10.8329, 78.6966);
      expect(d, closeTo(3392, 60));
      expect(gpsAt(10, 78).distanceTo(gpsAt(10, 78)), 0);
    });

    test('submitted seed shops carry GPS; drafts must capture it', () {
      for (final id in [
        's_amma',
        's_royal',
        's_thillai_colour',
        's_meenakshi',
      ]) {
        expect(c.shop(id)!.geo, isNotNull, reason: id);
      }
      expect(c.shop('s_sriranga')!.geo, isNull);
      expect(
        c.shopIssues(c.shop('s_lakshmi')!),
        contains('Capture the shop GPS location'),
      );
    });

    test('setShopLocation saves, logs and makes the shop in progress', () {
      c.loginWithPin('5678');
      final shop = c.shop('s_lakshmi')!;
      c.setShopLocation(shop, gpsAt(10.8650, 78.6880, accuracy: 7));
      expect(shop.geo!.coordinates, '10.86500, 78.68800');
      expect(shop.status, RecceStatus.inProgress);
      expect(
        c.activities(shopId: shop.id).first.title,
        'GPS location captured',
      );
    });

    test('photos taken far from the shop are flagged', () {
      final shopGeo = gpsAt(10.86270, 78.68970);
      final board = Board(
        id: 'b',
        name: 'B',
        photos: [
          SitePhoto(
            id: 'near',
            path: 'demo://1',
            label: 'Front view',
            capturedAt: DateTime(2026),
            width: 1200,
            height: 900,
            geo: gpsAt(10.86280, 78.68975), // ~12 m away
          ),
          SitePhoto(
            id: 'far',
            path: 'demo://2',
            label: 'Left angle',
            capturedAt: DateTime(2026),
            width: 1200,
            height: 900,
            geo: gpsAt(10.8329, 78.6966), // Rockfort, km away
          ),
        ],
      );
      final w = c.boardWarnings(board, shopGeo);
      expect(w.where((e) => e.contains('away from the shop')), hasLength(1));
      expect(
        w.singleWhere((e) => e.contains('away')),
        contains('"Left angle"'),
      );
      // Without a shop location there is nothing to compare against.
      expect(c.boardWarnings(board).any((e) => e.contains('away')), isFalse);
      // Both photos are tagged, so no "no GPS tag" warning.
      expect(w.any((e) => e.contains('GPS tag')), isFalse);
    });

    test('photos without a GPS tag are flagged, not silently passed', () {
      SitePhoto photo(String id, {GeoFix? geo}) => SitePhoto(
        id: id,
        path: 'demo://1',
        label: id,
        capturedAt: DateTime(2026),
        width: 1200,
        height: 900,
        geo: geo,
      );
      final shopGeo = gpsAt(10.86270, 78.68970);
      final mixed = Board(
        id: 'm',
        name: 'M',
        photos: [
          photo('a', geo: shopGeo),
          photo('b'),
        ],
      );
      expect(
        c.boardWarnings(mixed, shopGeo),
        contains('1 of 2 photos have no GPS tag'),
      );
      final none = Board(id: 'n', name: 'N', photos: [photo('a'), photo('b')]);
      expect(
        c.boardWarnings(none, shopGeo).any((e) => e.startsWith('No photo')),
        isTrue,
      );
    });

    test('low GPS accuracy is a warning, not a blocker', () {
      final shop = c.shop('s_lakshmi')!
        ..geo = gpsAt(10.86, 78.69, accuracy: 85);
      expect(c.shopWarnings(shop).single, contains('±85 m'));
      expect(
        c.shopIssues(shop),
        isNot(contains('Capture the shop GPS location')),
      );
    });

    test('version diff reports GPS capture and moves', () {
      final a = Shop(id: 's', projectId: 'p', taskId: 't', name: 'S');
      final b = Shop.fromJson(a.toJson())..geo = gpsAt(10.8627, 78.6897);
      final c2 = Shop.fromJson(b.toJson())..geo = gpsAt(10.8636, 78.6897);
      expect(diffShops(a, b), contains('Shop GPS location captured'));
      expect(
        diffShops(b, c2).first,
        allOf(contains('Shop GPS location updated'), contains('100 m')),
      );
    });

    test('GPS times (UTC from the device) display in local time', () {
      final utc = DateTime.utc(2026, 11, 17, 12, 33);
      final local = utc.toLocal();
      final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
      expect(fmtDateTime(utc), fmtDateTime(local));
      // e.g. 12:33 UTC → 6:03 PM IST (+5:30, so minutes change too).
      expect(fmtDateTime(utc), contains('$h:${two(local.minute)}'));
      // Survives storage as an ISO string with "Z".
      final stored = GeoFix.fromJson(
        GeoFix(
          latitude: 10,
          longitude: 78,
          accuracyM: 5,
          capturedAt: utc,
        ).toJson(),
      )!;
      expect(fmtDateTime(stored.capturedAt), fmtDateTime(local));
    });

    test('GPS survives JSON round trip on shop and photo', () {
      final shop = c.shop('s_amma')!;
      final copy = Shop.fromJson(shop.toJson());
      expect(copy.geo!.coordinates, shop.geo!.coordinates);
      expect(copy.geo!.accuracyM, shop.geo!.accuracyM);
      expect(
        copy.boards.first.photos.first.geo!.coordinates,
        shop.boards.first.photos.first.geo!.coordinates,
      );
    });
  });

  group('persistence', () {
    test('changes survive a restart from local storage', () async {
      c.loginWithPin('5678');
      final b = c.addBoard('s_lakshmi');
      b.mediaCode = SignageCatalog.nlb;
      b.width = 6;
      b.height = 3;
      c.touchBoard('s_lakshmi', b);
      await c.flush();

      final reloaded = AppController(store: store);
      await reloaded.init();
      expect(reloaded.isLoggedIn, isTrue);
      final rb = reloaded.board('s_lakshmi', b.id)!;
      expect(rb.mediaCode, SignageCatalog.nlb);
      expect(rb.width, 6);
      expect(reloaded.shop('s_lakshmi')!.status, RecceStatus.inProgress);
    });

    test('reset demo data restores the seed', () async {
      c.loginWithPin('5678');
      await c.deleteShop('s_lakshmi');
      expect(c.shop('s_lakshmi'), isNull);
      await c.resetDemoData();
      expect(c.shop('s_lakshmi'), isNotNull);
      expect(c.isLoggedIn, isTrue);
    });

    test('JSON round trip keeps annotations and voice notes', () {
      final shop = c.shop('s_sriranga')!;
      shop.boards.first.voiceNotes.add(
        VoiceNote(
          id: 'v1',
          path: '/x.m4a',
          durationMs: 3200,
          createdAt: DateTime(2026, 11, 17),
        ),
      );
      final copy = Shop.fromJson(shop.toJson());
      final a = copy.boards.first.photos.first.annotations.first;
      expect(a.type, AnnotationType.rectangle);
      expect(a.measureW, 10);
      expect(copy.boards.first.voiceNotes.single.durationMs, 3200);
    });
  });

  test('unit conversions', () {
    expect(MeasureUnit.inch.toFeet(24), closeTo(2, 1e-9));
    expect(MeasureUnit.m.toFeet(1), closeTo(3.2808, 1e-3));
    expect(MeasureUnit.mm.fromFeet(1), closeTo(304.8, 1e-6));
    final b = Board(id: 'b', name: 'B', width: 120, height: 48)
      ..unit = MeasureUnit.inch
      ..quantity = 2;
    expect(b.areaSqFt, closeTo(80, 1e-9));
  });
}
