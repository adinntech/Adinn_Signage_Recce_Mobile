import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/approvals/review_screen.dart';
import 'package:signage_recce/features/review_comments/photo_comments_screen.dart';
import 'package:signage_recce/features/review_comments/shop_comments_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

import 'helpers.dart';

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget _host(AppController c, Widget child) =>
    ChangeNotifierProvider<AppController>.value(
      value: c,
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );

/// "Amma Paint House": v1 pending Business approval.
const _shopId = 's_amma';
const _boardId = 'b_amma_1';
const _photoId = 'ph_s3_1';

Future<AppController> _controller({
  String pin = DemoAccounts.businessPin,
}) async {
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  c.loginWithPin(pin);
  return c;
}

PhotoReviewComment _comment(
  AppController c, {
  bool rejects = false,
  ReviewCommentType type = ReviewCommentType.unclearPhoto,
  SurveyPoint at = const SurveyPoint(0.25, 0.6),
}) {
  final b = c.board(_shopId, _boardId)!;
  return c.addReviewComment(
    _shopId,
    groupId: _boardId,
    photoId: _photoId,
    unitId: b.units.first.id,
    type: type,
    text: 'Fascia edge not visible – retake from the left',
    position: at,
    rejectsEvidence: rejects,
  );
}

void _reject(AppController c, String remarks) {
  final s = c.shop(_shopId)!;
  c.reviewShop(
    _shopId,
    decision: ReviewDecision.rejected,
    remarks: remarks,
    issues: c.commentIssues(s),
  );
}

void _switch(AppController c, String pin) {
  c.logout();
  c.loginWithPin(pin);
}

void main() {
  group('review comments (controller)', () {
    test(
      '83-86: comment links to photo + item, normalised position persists',
      () async {
        final c = await _controller();
        final s = c.shop(_shopId)!;
        final cm = _comment(c);
        expect(cm.projectId, s.projectId);
        expect(cm.taskId, s.taskId);
        expect(cm.shopId, s.id);
        expect(cm.groupId, _boardId);
        expect(cm.photoId, _photoId);
        expect(cm.unitId, s.boards.first.units.first.id);
        expect(cm.version, 1);
        expect(cm.reviewerRole, UserRole.businessTeam);
        expect(cm.reviewerName, isNotEmpty);
        expect(cm.status, CommentStatus.open);
        expect(cm.markerLabel, 'B1');
        expect(_comment(c).markerLabel, 'B2');
        expect(c.activities(shopId: s.id).first.title, 'Photo comment added');

        // Reload from storage (87: reopen).
        await c.flush();
        final again = AppController(store: c.store);
        await again.init();
        final loaded = again.reviewComments(_shopId, photoId: _photoId).first;
        expect(loaded.position, const SurveyPoint(0.25, 0.6));
        expect(loaded.text, cm.text);
        expect(loaded.type, ReviewCommentType.unclearPhoto);
      },
    );

    test('comments never touch staff annotations or the v1 snapshot', () async {
      final c = await _controller();
      final s = c.shop(_shopId)!;
      final photo = s.boards.first.photos.first;
      final annotations = jsonEncode(
        photo.annotations.map((a) => a.toJson()).toList(),
      );
      final snapshot = jsonEncode(s.submissions.first.snapshot);
      _comment(c);
      expect(
        jsonEncode(photo.annotations.map((a) => a.toJson()).toList()),
        annotations,
      );
      expect(jsonEncode(s.submissions.first.snapshot), snapshot);
      expect(s.toSnapshotJson().containsKey('reviewComments'), isFalse);
    });

    test('only the reviewer awaiting the recce can comment', () async {
      final c = await _controller(pin: DemoAccounts.vendorPin);
      expect(() => _comment(c), throwsStateError);
      _switch(c, DemoAccounts.opsPin); // Ops is not awaiting v1 yet.
      expect(() => _comment(c), throwsStateError);
      _switch(c, DemoAccounts.businessPin);
      expect(
        () => c.addReviewComment(
          _shopId,
          groupId: _boardId,
          photoId: _photoId,
          type: ReviewCommentType.general,
          text: '   ',
          position: const SurveyPoint(0.5, 0.5),
        ),
        throwsStateError,
      );
    });

    test(
      '88-95: reject evidence → respond → addressed → resubmit v2 → verify',
      () async {
        final c = await _controller();
        final s = c.shop(_shopId)!;
        final v1Snapshot = jsonEncode(s.submissions.first.snapshot);
        final rejecting = _comment(c, rejects: true);
        final note = _comment(c, type: ReviewCommentType.general);
        // 88: only evidence-rejecting comments become rejection issues.
        final issues = c.commentIssues(s);
        expect(issues, hasLength(1));
        expect(issues.single.photoId, _photoId);
        expect(issues.single.aspect, IssueAspect.photo);
        expect(issues.single.note, contains('B1'));
        _reject(c, 'Retake the photo');
        expect(s.status, RecceStatus.rejectedBusiness);

        // 89: the vendor sees the rejection reason on the photo.
        _switch(c, DemoAccounts.vendorPin);
        final open = c.openIssues(s);
        expect(open.single.photoId, _photoId);
        expect(open.single.text, contains('Fascia edge'));

        // 94: staff can never verify (no self-approval).
        expect(c.canVerifyComment(s, rejecting), isFalse);
        expect(() => c.verifyComment(_shopId, rejecting.id), throwsStateError);

        // 90-91: respond and mark addressed.
        c.respondToComment(_shopId, rejecting.id, 'Retook from the left');
        expect(rejecting.responses.single.text, 'Retook from the left');
        expect(rejecting.status, CommentStatus.open);
        c.respondToComment(_shopId, rejecting.id, '', markAddressed: true);
        expect(rejecting.status, CommentStatus.addressed);
        expect(
          c.activities(shopId: s.id).first.title,
          'Photo correction submitted',
        );
        expect(() => c.verifyComment(_shopId, rejecting.id), throwsStateError);

        // Resubmit as v2.
        completeAnswers(s.boards.first);
        c.submitShop(_shopId, remarks: 'Photo retaken');
        expect(s.currentVersion, 2);
        // Addressed is not approval.
        expect(s.status, RecceStatus.pendingBusiness);

        // 92: the Business reviewer verifies.
        _switch(c, DemoAccounts.businessPin);
        expect(c.canVerifyComment(s, rejecting), isTrue);
        expect(c.canVerifyComment(s, note), isFalse); // still open
        c.verifyComment(_shopId, rejecting.id);
        expect(rejecting.status, CommentStatus.verified);
        expect(rejecting.verifiedByName, isNotEmpty);

        // 93: V1 comments stay attached to v1 and visible in v2.
        expect(c.reviewComments(_shopId, version: 1), hasLength(2));
        expect(c.reviewComments(_shopId, version: 2), isEmpty);
        // v1 comments cannot be deleted any more; new v2 ones can.
        expect(c.canDeleteComment(s, note), isFalse);
        final v2 = _comment(c);
        expect(v2.version, 2);
        expect(v2.markerLabel, 'B3');
        expect(c.canDeleteComment(s, v2), isTrue);
        c.deleteReviewComment(_shopId, v2.id);
        expect(c.reviewComments(_shopId, version: 2), isEmpty);
        // Evidence comments from v1 are not re-used as v2 issues.
        expect(c.commentIssues(s), isEmpty);

        // Reopen.
        c.reopenComment(_shopId, rejecting.id);
        expect(rejecting.status, CommentStatus.open);

        // 95: the v1 snapshot is untouched.
        expect(jsonEncode(s.submissions.first.snapshot), v1Snapshot);

        // Ops cannot verify Business comments.
        c.approveForTest();
        _switch(c, DemoAccounts.opsPin);
        expect(c.canVerifyComment(s, rejecting), isFalse);
        expect(() => c.reopenComment(_shopId, rejecting.id), throwsStateError);
      },
    );
  });

  group('review comments (screens)', () {
    testWidgets('reviewer pins a comment exactly where tapped', (tester) async {
      _phone(tester);
      final c = await _controller();
      await tester.pumpWidget(
        _host(
          c,
          const PhotoCommentsScreen(
            shopId: _shopId,
            boardId: _boardId,
            photoId: _photoId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rc_add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rc_place_hint')), findsOneWidget);
      final photo = tester.getRect(find.byKey(const Key('rc_photo')));
      await tester.tapAt(
        photo.topLeft + Offset(photo.width * 0.3, photo.height * 0.7),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('rc_type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Incorrect Measurement').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('rc_text')),
        'Width is 12 ft?',
      );
      await tester.tap(find.byKey(const Key('rc_reject')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rc_save')));
      await tester.pumpAndSettle();

      final cm = c.reviewComments(_shopId).single;
      expect(cm.type, ReviewCommentType.incorrectMeasurement);
      expect(cm.rejectsEvidence, isTrue);
      expect(cm.position.x, closeTo(0.3, 0.01));
      expect(cm.position.y, closeTo(0.7, 0.01));
      expect(cm.unitId, c.board(_shopId, _boardId)!.units.first.id);
      // Marker drawn at the same photo-relative spot.
      // (The photo box moved up once the placing hint closed.)
      final now = tester.getRect(find.byKey(const Key('rc_photo')));
      final marker = tester.getCenter(find.byKey(Key('rc_marker_${cm.id}')));
      expect(marker.dx, closeTo(now.left + now.width * 0.3, 1));
      expect(marker.dy, closeTo(now.top + now.height * 0.7, 1));

      // Tap the marker → exact comment text.
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byKey(Key('rc_marker_${cm.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('rc_detail_${cm.id}')), findsOneWidget);
      expect(find.text('Width is 12 ft?'), findsWidgets);
      expect(find.byKey(const Key('rc_delete')), findsOneWidget);
      expect(find.byKey(const Key('rc_respond')), findsNothing);
    });

    testWidgets('reject from the review screen carries photo comments', (
      tester,
    ) async {
      _phone(tester);
      final c = await _controller();
      final cm = _comment(c, rejects: true);
      await tester.pumpWidget(_host(c, const ReviewScreen(shopId: _shopId)));
      await tester.pumpAndSettle();
      final btn = find.byKey(const Key('review_photo_comments_$_photoId'));
      await tester.scrollUntilVisible(
        btn,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(btn, findsOneWidget);
      expect(find.text('All (1)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reject_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('reject_remarks')),
        'See photo comments',
      );
      await tester.ensureVisible(find.byKey(const Key('reject_confirm')));
      await tester.tap(find.byKey(const Key('reject_confirm')));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      final s = c.shop(_shopId)!;
      expect(s.status, RecceStatus.rejectedBusiness);
      final issue = s.latestSubmission!.reviews.last.issues.single;
      expect(issue.photoId, _photoId);
      expect(issue.note, contains(cm.markerLabel));
    });

    testWidgets('vendor sees the rejection, responds and marks addressed', (
      tester,
    ) async {
      _phone(tester);
      final c = await _controller();
      final cm = _comment(c, rejects: true);
      _reject(c, 'Retake the front photo');
      _switch(c, DemoAccounts.vendorPin);

      await tester.pumpWidget(
        _host(c, const ShopCommentsScreen(shopId: _shopId)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rc_rejection')), findsOneWidget);
      expect(find.text('Retake the front photo'), findsOneWidget);
      expect(find.text('Open 1'), findsOneWidget);

      await tester.tap(find.byKey(Key('rc_list_${cm.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rc_verify')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('rc_response')),
        'Retaken from the left side',
      );
      await tester.tap(find.byKey(const Key('rc_addressed')));
      await tester.pumpAndSettle();
      expect(cm.status, CommentStatus.addressed);
      expect(cm.responses.single.text, 'Retaken from the left side');
      expect(find.byKey(const Key('rc_verify')), findsNothing);
    });

    testWidgets('a replaced photo falls back to the v1 snapshot photo', (
      tester,
    ) async {
      _phone(tester);
      final c = await _controller();
      final cm = _comment(c, rejects: true);
      _reject(c, 'Retake');
      _switch(c, DemoAccounts.vendorPin);
      await c.removePhoto(_shopId, _boardId, _photoId);
      // The seeded board now carries a second photo; drop it as well.
      for (final p in [...c.board(_shopId, _boardId)!.photos]) {
        await c.removePhoto(_shopId, _boardId, p.id);
      }
      expect(c.board(_shopId, _boardId)!.photos, isEmpty);

      await tester.pumpWidget(
        _host(
          c,
          const PhotoCommentsScreen(
            shopId: _shopId,
            boardId: _boardId,
            photoId: _photoId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rc_snapshot_banner')), findsOneWidget);
      expect(
        find.text(
          'Photo from v1 submission (no longer in the current '
          'recce)',
        ),
        findsOneWidget,
      );
      expect(find.byKey(Key('rc_marker_${cm.id}')), findsOneWidget);
      // Reviewer-only action hidden for the vendor.
      expect(find.byKey(const Key('rc_add')), findsNothing);
    });
  });
}

extension on AppController {
  /// Business + Ops approval of the current version (test shortcut).
  void approveForTest() {
    reviewShop(_shopId, decision: ReviewDecision.approved);
  }
}
