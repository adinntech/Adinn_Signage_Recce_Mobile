import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signage_recce/core/network/token_manager.dart';
import 'package:signage_recce/core/storage/session_store.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/features/live_auth/data/auth_repository.dart';
import 'package:signage_recce/features/live_auth/domain/auth_models.dart';
import 'package:signage_recce/features/live_auth/presentation/live_auth_controller.dart';
import 'package:signage_recce/features/live_recce/data/chat_controller.dart';
import 'package:signage_recce/features/live_recce/data/dashboard_controller.dart';
import 'package:signage_recce/features/live_recce/data/live_services.dart';
import 'package:signage_recce/features/live_recce/data/notifications_controller.dart';
import 'package:signage_recce/features/live_recce/data/recce_api.dart';
import 'package:signage_recce/features/live_recce/data/recce_controllers.dart';
import 'package:signage_recce/features/live_recce/data/recce_models.dart';
import 'package:signage_recce/features/live_recce/data/rework_alert.dart';
import 'package:signage_recce/features/live_recce/data/submit_validator.dart';
import 'package:signage_recce/features/live_recce/data/upload_queue.dart';
import 'package:signage_recce/features/live_recce/presentation/boards_tab.dart';
import 'package:signage_recce/features/live_recce/presentation/live_shop_screen.dart';
import 'package:signage_recce/features/live_recce/presentation/rework_alert.dart';
import 'package:signage_recce/features/live_recce/presentation/rework_sheet.dart';

/// Reviewers can flag a board's media type, quantity and size (FIX_MEDIA_TYPE, FIX_QUANTITY, FIX_MEASUREMENT) as well as photos. The phone
/// shows every flag with the reviewer's reason, alerts the person once per rework request, shows the rejected photo next to its new
/// photo, and none of the board requests blocks the resubmit. Fake data only.

Map<String, dynamic> _photo(String id, String category, {String state = 'SUBMITTED', String? note, bool rejected = false, String? replaces, bool flagged = true}) => {
      'id': id,
      'category': category,
      'state': state,
      'mediaKey': 'b1',
      'version': state == 'DRAFT' ? null : 1,
      'lat': 13.04,
      'lng': 80.23,
      'gpsAccuracy': 8.0,
      'gpsVerified': true,
      'url': 'http://host/$id.jpg',
      'replaces': replaces,
      'review': {
        'status': flagged && note != null ? 'REWORK_REQUIRED' : 'PENDING',
        'openRework': flagged && note != null
            ? {'reworkId': 'rw1', 'itemId': 'it-$id', 'note': note, 'stage': 'OPS', 'stageLabel': 'Recce Operations', 'instructions': 'Fix these', 'requestedBy': 'Asha', 'requestedAt': '2026-11-24T08:00:00.000Z', 'rejected': rejected}
            : null,
      },
    };

Map<String, dynamic> _item(String id, String type, {String mediaKey = 'b1', String note = '', bool rejected = false, bool resolved = false, String? photo, String? category, String? categoryLabel}) => {
      'id': id,
      'type': type,
      'category': category,
      'categoryLabel': categoryLabel,
      'mediaKey': mediaKey,
      'photo': photo,
      'note': note,
      'rejected': rejected,
      'resolved': resolved,
    };

Map<String, dynamic> _detail({List<Map<String, dynamic>>? photos, List<Map<String, dynamic>>? items, String status = 'REWORK_REQUIRED', bool editable = true, String reworkId = 'rw1'}) => {
      'siteId': 's1',
      'siteCode': 'SM-1',
      'shopName': 'Sri Murugan',
      'project': {'id': 'p1', 'code': 'ADN-1', 'name': 'South', 'closed': false},
      'status': status,
      'editable': editable,
      'version': 1,
      'mediaItems': [
        {'key': 'b1', 'name': 'GSB', 'mediaType': 'GSB', 'seq': 1, 'quantity': 1, 'width': 6, 'height': 4, 'unit': 'FT'},
      ],
      'photos': photos ??
          [
            _photo('p-front', 'SHOP_FRONT', note: 'Board is cut off', rejected: true),
            _photo('p-left', 'LEFT_SIDE', note: 'Not clear'),
            _photo('p-right', 'RIGHT_SIDE', flagged: false),
          ],
      'progress': {'percent': 50, 'required': 3, 'done': 3, 'missing': []},
      'reworks': [
        {
          'id': reworkId,
          'versionNo': 1,
          'stage': 'OPS',
          'stageLabel': 'Recce Operations',
          'kind': 'REWORK',
          'status': 'OPEN',
          'instructions': 'Fix these',
          'requestedBy': 'Asha',
          'requestedAt': '2026-11-24T08:00:00.000Z',
          'items': items ??
              [
                _item('it-p-front', 'REPLACE_PHOTO', photo: 'p-front', note: 'Board is cut off', rejected: true, category: 'SHOP_FRONT', categoryLabel: 'Front View'),
                _item('it-p-left', 'REPLACE_PHOTO', photo: 'p-left', note: 'Not clear', category: 'LEFT_SIDE', categoryLabel: 'Left View'),
                _item('it-qty', 'FIX_QUANTITY', note: 'Shop has 2 boards', rejected: true),
                _item('it-type', 'FIX_MEDIA_TYPE', note: 'This is a vinyl board'),
                _item('it-size', 'FIX_MEASUREMENT', note: 'Width is 8 ft'),
              ],
        },
      ],
    };

class _Api extends RecceApi {
  _Api([Map<String, dynamic>? json]) : json = json ?? _detail(), super(Dio());
  Map<String, dynamic> json;
  @override
  Future<ShopDetail> detail(String siteId) async => ShopDetail.fromJson(json);
  @override
  Future<List<RecceVersion>> versions(String siteId) async => const [];
  @override
  Future<PhotoHistory> photoHistory(String siteId, String photoId) async => PhotoHistory.fromJson({
        'photoId': photoId,
        'revisions': [
          {..._photo('p-front', 'SHOP_FRONT', note: 'Board is cut off', rejected: true), 'revision': 1, 'current': false},
          {..._photo('p-new', 'SHOP_FRONT', state: 'DRAFT', replaces: 'p-front'), 'revision': 2, 'current': true},
        ],
      });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetReworkAlertMemory();
  });

  group('board requests parse and read', () {
    test('quantity and media type requests are board fixes, like the size request', () {
      final d = ShopDetail.fromJson(_detail());
      final items = d.reworks.single.items;
      expect(items.map((i) => i.isBoardFix), [false, false, true, true, true]);
      expect(items.where((i) => i.isBoardFix).map((i) => i.type), ['FIX_QUANTITY', 'FIX_MEDIA_TYPE', 'FIX_MEASUREMENT']);
    });

    test('a board card gets every open request of its board, each with its type, reason and rejected flag', () {
      final d = ShopDetail.fromJson(_detail());
      final notes = d.boardReworksFor('b1');
      expect(notes.map((n) => n.itemType), ['FIX_QUANTITY', 'FIX_MEDIA_TYPE', 'FIX_MEASUREMENT']);
      expect(notes.map((n) => n.reason), ['Shop has 2 boards', 'This is a vinyl board', 'Width is 8 ft']);
      expect(notes.map((n) => n.rejected), [true, false, false]);
      expect(notes.every((n) => n.by == 'Asha' && n.role == 'Recce Operations'), isTrue);
      expect(d.boardReworksFor('b2'), isEmpty);
      expect(d.boardReworksFor(''), isEmpty);
      // the older single-note reader still works and gives the first one
      expect(d.measurementReworkFor('b1')!.reason, 'Shop has 2 boards');
    });

    test('a request that names no board (or a board that is gone) goes to the general list, resolved ones never show', () {
      final d = ShopDetail.fromJson(_detail(items: [
        _item('a', 'FIX_QUANTITY', mediaKey: '', note: 'Count again'),
        _item('b', 'FIX_MEDIA_TYPE', mediaKey: 'b9', note: 'Old board'),
        _item('c', 'FIX_MEASUREMENT', note: 'on the card'),
        _item('d', 'FIX_QUANTITY', mediaKey: '', note: 'done', resolved: true),
      ]));
      final general = d.measurementReworksWithoutBoard(['b1']);
      expect(general.map((g) => g.note.reason), ['Count again', 'Old board']);
      expect(general.first.note.itemType, 'FIX_QUANTITY');
      expect(d.boardReworksFor('b1').map((n) => n.reason), ['on the card']);
    });

    test('texts name the board by its number and say Rejected when the reviewer rejected it', () {
      final d = ShopDetail.fromJson(_detail());
      final i = d.reworks.single.items;
      final labels = d.boardLabels;
      expect(labels, {'b1': 'GSB-01'});
      expect(reworkItemText(i[2], boardLabels: labels), 'Rejected: quantity of GSB-01: Shop has 2 boards');
      expect(reworkItemText(i[3], boardLabels: labels), 'Check the media type of GSB-01: This is a vinyl board');
      expect(reworkItemText(i[4], boardLabels: labels), 'Correct the size of GSB-01: Width is 8 ft');
      expect(reworkItemText(i[4]), 'Correct the size of b1: Width is 8 ft'); // without labels the key is shown (as before)
      expect(reworkItemText(ReworkItem.fromJson(_item('x', 'FIX_QUANTITY', mediaKey: '', note: 'n', resolved: true))), 'Check the quantity of a board: n (done)');
      expect(boardFixTitle('FIX_QUANTITY'), 'Check the quantity');
      expect(boardFixTitle('FIX_MEDIA_TYPE'), 'Check the media type');
      expect(boardFixTitle('FIX_MEASUREMENT'), 'Correct the size');
      expect(boardFixTitle('FIX_QUANTITY', rejected: true), 'Quantity rejected');
      expect(boardFixTitle('FIX_MEDIA_TYPE', rejected: true), 'Media type rejected');
      expect(boardFixTitle('FIX_MEASUREMENT', rejected: true), 'Size rejected');
    });
  });

  group('the alert counts', () {
    test('photos rejected, photos to redo, board details and extra photos are counted and named', () {
      final d = ShopDetail.fromJson(_detail());
      final a = ReworkAlert.of(d);
      expect(a.rejectedPhotos, 1);
      expect(a.reworkPhotos, 1);
      expect(a.boardDetails, 3);
      expect(a.extraPhotos, 0);
      expect(a.open, 5);
      expect(a.summary, '1 photo rejected, 1 photo to redo, 3 board details to correct');
      expect(a.requestKey, 'rw1');
      expect(a.photos.first.angle, 'Front View');
      expect(a.photos.first.board, 'GSB-01');
      expect(a.photos.first.reason, 'Board is cut off');
      expect(a.photos.first.rejected, isTrue);
      expect(a.boardFixes.map((f) => f.title), ['Quantity rejected', 'Check the media type', 'Correct the size']);
      expect(a.boardFixes.every((f) => f.board == 'GSB-01'), isTrue);
    });

    test('an extra photo asked for is counted, and a new picture takes a photo off the open count', () {
      final j = _detail(items: [
        _item('x', 'ADDITIONAL_PHOTO', category: 'LONG_SHOT', categoryLabel: 'Long Shot', note: 'Show the full street'),
        _item('it-p-front', 'REPLACE_PHOTO', photo: 'p-front', note: 'Board is cut off', rejected: true, category: 'SHOP_FRONT', categoryLabel: 'Front View'),
      ]);
      final d = ShopDetail.fromJson(j);
      expect(ReworkAlert.of(d).summary, '1 photo rejected, 1 photo to redo, 1 extra photo asked');
      final answered = ReworkAlert.of(d, answeredPhoto: (p) => p.id == 'p-front', answeredRequest: (_) => false);
      expect(answered.rejectedPhotos, 0);
      expect(answered.reworkPhotos, 1);
      expect(answered.photos.first.answered, isTrue);
      expect(answered.summary, '1 photo to redo, 1 extra photo asked');
      expect(answered.photosAnswered, isFalse);
      final all = ReworkAlert.of(d, answeredPhoto: (_) => true, answeredRequest: (_) => true);
      expect(all.photosAnswered, isTrue);
      expect(all.allAnswered, isTrue);
      expect(all.open, 0);
    });

    test('board details alone keep the alert open; a shop with nothing flagged has no alert', () {
      final onlyBoard = ReworkAlert.of(ShopDetail.fromJson(_detail(photos: [_photo('p-right', 'RIGHT_SIDE', flagged: false)], items: [_item('q', 'FIX_QUANTITY', note: 'Count again')])));
      expect(onlyBoard.summary, '1 board detail to correct');
      expect(onlyBoard.allAnswered, isFalse);
      final clean = _detail(status: 'UNDER_REVIEW', editable: false)..['reworks'] = <Map<String, dynamic>>[];
      (clean['photos'] as List).removeWhere((p) => (p as Map)['review']['status'] == 'REWORK_REQUIRED');
      expect(ReworkAlert.of(ShopDetail.fromJson(clean)).isEmpty, isTrue);
      expect(ReworkAlert.of(ShopDetail.fromJson(clean)).summary, '');
    });

    test('the request key changes with every new rework request, and the sheet is claimed once per key', () {
      expect(ReworkAlert.of(ShopDetail.fromJson(_detail(reworkId: 'rw1'))).requestKey, 'rw1');
      expect(ReworkAlert.of(ShopDetail.fromJson(_detail(reworkId: 'rw2'))).requestKey, 'rw2');
      expect(claimReworkAlert('rw1'), isTrue);
      expect(claimReworkAlert('rw1'), isFalse); // never again for the same request
      expect(claimReworkAlert('rw2'), isTrue);
      expect(claimReworkAlert(''), isFalse);
    });
  });

  group('the resubmit is not blocked by board requests', () {
    test('size, quantity and media type requests need no answer; a photo request still does', () {
      final d = ShopDetail.fromJson(_detail());
      final photos = d.photos;
      // the two photo items still wait for a new picture, the three board items add nothing
      expect(unansweredRework(d.reworks, photos), ['Replace the Front View the reviewer marked', 'Replace the Left View the reviewer marked']);
      final boardOnly = ShopDetail.fromJson(_detail(items: [_item('a', 'FIX_QUANTITY', note: 'x'), _item('b', 'FIX_MEDIA_TYPE', note: 'y'), _item('c', 'FIX_MEASUREMENT', note: 'z'), _item('d', 'FIX_QUANTITY', mediaKey: '', note: 'no board')]));
      expect(unansweredRework(boardOnly.reworks, boardOnly.photos), isEmpty);
      final withDraft = [...photos, ShopPhoto.fromJson(_photo('n1', 'SHOP_FRONT', state: 'DRAFT', replaces: 'p-front', flagged: false)), ShopPhoto.fromJson(_photo('n2', 'LEFT_SIDE', state: 'DRAFT', replaces: 'p-left', flagged: false))];
      expect(unansweredRework(d.reworks, withDraft), isEmpty);
    });
  });

  group('screens', () {
    testWidgets('the banner names what was flagged and opens it; it turns green when every photo has a new picture', (t) async {
      var opened = 0;
      final a = ReworkAlert.of(ShopDetail.fromJson(_detail()));
      await t.pumpWidget(MaterialApp(home: Scaffold(body: ReworkAlertBanner(alert: a, onOpen: () => opened++))));
      expect(find.text('Retake needed'), findsOneWidget);
      expect(find.text('1 photo rejected, 1 photo to redo, 3 board details to correct'), findsOneWidget);
      await t.tap(find.text('Fix now'));
      expect(opened, 1);

      final done = ReworkAlert.of(ShopDetail.fromJson(_detail(items: [_item('p', 'REPLACE_PHOTO', photo: 'p-front', note: 'cut', category: 'SHOP_FRONT')])), answeredPhoto: (_) => true);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: ReworkAlertBanner(alert: done, onOpen: () => opened++))));
      expect(find.text('New photos are ready'), findsOneWidget);
      expect(find.text('Fix now'), findsNothing);
      expect(find.text('Review'), findsOneWidget);

      await t.pumpWidget(MaterialApp(home: Scaffold(body: ReworkAlertBanner(alert: const ReworkAlert(), onOpen: () => opened++))));
      expect(find.byKey(const Key('rework-alert-banner')), findsNothing);
    });

    testWidgets('the sheet lists every flagged photo and board detail with the reason, and "Retake now" answers true', (t) async {
      t.view.physicalSize = const Size(412, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final a = ReworkAlert.of(ShopDetail.fromJson(_detail()));
      bool? result;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: Center(child: FilledButton(onPressed: () async => result = await showReworkAlertSheet(context, a), child: const Text('open')))))));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Rework requested'), findsOneWidget);
      expect(find.text('1 photo rejected, 1 photo to redo, 3 board details to correct'), findsOneWidget);
      expect(find.text('Asked by Asha (Recce Operations)'), findsOneWidget);
      expect(find.text('Front View'), findsOneWidget);
      expect(find.text('Left View'), findsOneWidget);
      expect(find.text('Reason: Board is cut off'), findsOneWidget);
      expect(find.text('Not clear'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('GSB-01  |  Quantity rejected'), findsOneWidget);
      expect(find.text('Reason: Shop has 2 boards'), findsOneWidget);
      expect(find.text('GSB-01  |  Check the media type'), findsOneWidget);
      expect(find.text('This is a vinyl board'), findsOneWidget);
      expect(find.text('GSB-01  |  Correct the size'), findsOneWidget);
      await t.tap(find.byKey(const Key('rework-alert-retake')));
      await t.pumpAndSettle();
      expect(result, isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('the banner and the sheet fit a narrow phone (360 wide) without overflow', (t) async {
      t.view.physicalSize = const Size(1080, 2400); // 360 x 800 logical
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final a = ReworkAlert.of(ShopDetail.fromJson(_detail()));
      await t.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: Column(children: [Padding(padding: const EdgeInsets.all(16), child: ReworkAlertBanner(alert: a, onOpen: () {})), FilledButton(onPressed: () => showReworkAlertSheet(context, a), child: const Text('open'))])))));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rework-alert-retake')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('the Boards tab shows each board request on its board with the reason and its own heading', (t) async {
      t.view.physicalSize = const Size(412, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = _Api();
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      c.openBoardCard('b1');
      await t.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: BoardsTab(ctrl: c))));
      await t.pump();
      expect(find.text('Quantity rejected'), findsOneWidget);
      expect(find.text('Check the media type'), findsOneWidget);
      expect(find.text('Correct the size'), findsOneWidget);
      expect(find.text('Shop has 2 boards'), findsOneWidget);
      expect(find.text('This is a vinyl board'), findsOneWidget);
      expect(find.text('Width is 8 ft'), findsOneWidget);
      expect(find.text('Reason for rejection'), findsOneWidget); // only the rejected request has this heading
      expect(find.text('Board details to correct'), findsNothing); // none is without a board
      expect(t.takeException(), isNull);
      c.dispose();
      queue.dispose();
    });

    testWidgets('a request without a board is one general banner, named by its kind', (t) async {
      t.view.physicalSize = const Size(412, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = _Api(_detail(items: [_item('q', 'FIX_QUANTITY', mediaKey: '', note: 'Count all boards again')]));
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      await t.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: BoardsTab(ctrl: c))));
      await t.pump();
      expect(find.text('Board details to correct'), findsOneWidget);
      expect(find.text('Check the quantity'), findsOneWidget);
      expect(find.text('Count all boards again'), findsOneWidget);
      expect(t.takeException(), isNull);
      c.dispose();
      queue.dispose();
    });

    testWidgets('in rework nothing is added or removed, and the hint says only red boards can be edited', (t) async {
      t.view.physicalSize = const Size(412, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      // Only a photo is flagged: no request names the board.
      final api = _Api(_detail(items: [_item('it-p-left', 'REPLACE_PHOTO', photo: 'p-left', note: 'Not clear', category: 'LEFT_SIDE', categoryLabel: 'Left View')]));
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      expect(c.inRework, isTrue);
      await t.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: BoardsTab(ctrl: c))));
      await t.pump();
      expect(find.byKey(const Key('add-boards')), findsNothing);
      expect(find.textContaining('Only the boards marked in red can be edited'), findsOneWidget);
      expect(t.takeException(), isNull);
      c.dispose();
      queue.dispose();
    });

    testWidgets('before any rework (shop still open) the Add boards button is there', (t) async {
      t.view.physicalSize = const Size(412, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = _Api(_detail(status: 'IN_PROGRESS', photos: const [], items: const []));
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      expect(c.inRework, isFalse);
      await t.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: BoardsTab(ctrl: c))));
      await t.pump();
      expect(find.byKey(const Key('add-boards')), findsOneWidget);
      expect(find.textContaining('Only the boards marked in red'), findsNothing);
      expect(t.takeException(), isNull);
      c.dispose();
      queue.dispose();
    });

    testWidgets('the rework sheet puts the rejected photo next to the new photo (labels, both tappable)', (t) async {
      t.view.physicalSize = const Size(412, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final json = _detail();
      (json['photos'] as List).add(_photo('p-new', 'SHOP_FRONT', state: 'DRAFT', replaces: 'p-front', flagged: false));
      final api = _Api(json);
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      final front = c.detail!.photos.firstWhere((p) => p.id == 'p-front');
      await t.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: ReworkSheet(ctrl: c, photo: front, api: api))));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('before-photo')), findsOneWidget);
      expect(find.byKey(const Key('after-photo')), findsOneWidget);
      expect(find.text('Rejected photo'), findsOneWidget);
      expect(find.text('New photo'), findsOneWidget);
      expect(find.text('Original photo'), findsNothing); // the side-by-side view replaces the single picture
      expect(find.textContaining('New photo is ready'), findsOneWidget);
      // the earlier pictures stay in the revisions strip
      expect(find.text('2 revisions of this photo'), findsOneWidget);
      expect(find.text('Revision 1'), findsOneWidget);
      expect(t.takeException(), isNull);
      c.dispose();
      queue.dispose();
    });

    testWidgets('without a new photo the rework sheet still shows the single original picture', (t) async {
      t.view.physicalSize = const Size(412, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = _Api();
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      final front = c.detail!.photos.firstWhere((p) => p.id == 'p-front');
      await t.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: ReworkSheet(ctrl: c, photo: front, api: api))));
      await t.pump();
      expect(find.text('Original photo'), findsOneWidget);
      expect(find.byKey(const Key('after-photo')), findsNothing);
      expect(t.takeException(), isNull);
      c.dispose();
      queue.dispose();
    });

    testWidgets('the shop screen shows the banner on top and the sheet ONCE for a rework request, not again after a rebuild', (t) async {
      t.view.physicalSize = const Size(1236, 4800); // 412 x 1600 logical, as the other screen tests
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final rig = _Rig(_Api());
      await t.pumpWidget(rig.host(const LiveShopScreen(siteId: 's1')));
      await t.pumpAndSettle();
      // the sheet came up by itself, once
      expect(find.byKey(const Key('rework-alert-retake')), findsOneWidget);
      expect(find.text('Rework requested'), findsOneWidget);
      // "Later" closes it; the banner stays in view on the shop screen
      await t.tap(find.byKey(const Key('rework-alert-later')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rework-alert-retake')), findsNothing);
      expect(find.byKey(const Key('rework-alert-banner')), findsOneWidget);
      expect(find.byKey(const Key('rework-alert-summary')), findsOneWidget);
      // refreshing the shop (the same request) never shows the sheet again
      await rig.api.detail('s1');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rework-alert-retake')), findsNothing);
      await t.pumpWidget(const SizedBox());
      rig.dispose();
    });
  });
}

class _MemoryStore implements SessionStore {
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<String?> readUserJson() async => null;
  @override
  Future<void> save({required String refreshToken, required String userJson}) async {}
  @override
  Future<void> clear() async {}
}

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(plainDio: Dio(), tokens: TokenManager(refreshDio: Dio(), store: _MemoryStore()), store: _MemoryStore());
  @override
  Future<LiveUser> login(String identifier, AuthCredential credential, {String? loginRole}) async => _user;
  @override
  Future<void> logout() async {}
}

final _user = LiveUser(id: 'u1', name: 'Siva Kumar', email: 'siva@x.com', role: LiveRole.recceExecutive);

/// Every part the shop screen reads, over one fake API, provided the way app.dart provides them.
class _Rig {
  _Rig(this.api) : auth = LiveAuthController(_FakeAuthRepo()) {
    queue = UploadQueue(api, autoRetry: false);
    shops = ShopListController(api, queue);
    services = LiveServices.withParts(auth: auth, api: api, queue: queue, shops: shops);
  }

  final _Api api;
  final LiveAuthController auth;
  late final UploadQueue queue;
  late final ShopListController shops;
  late final LiveServices services;

  Widget host(Widget home) => MultiProvider(
        providers: [
          Provider<LiveServices>.value(value: services),
          ChangeNotifierProvider<LiveAuthController>.value(value: auth),
          ChangeNotifierProvider<UploadQueue>.value(value: queue),
          ChangeNotifierProvider<ShopListController>.value(value: shops),
          ChangeNotifierProvider<ChatHub>.value(value: services.chat),
          ChangeNotifierProvider<FieldDashboardController>.value(value: services.dashboard),
          ChangeNotifierProvider<NotificationsController>.value(value: services.notifications),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      );

  void dispose() {
    services.chat.dispose();
    services.dashboard.dispose();
    services.notifications.dispose();
    shops.dispose();
    queue.dispose();
    auth.dispose();
  }
}
