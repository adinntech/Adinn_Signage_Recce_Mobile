import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signage_recce/core/network/api_exception.dart';
import 'package:signage_recce/features/live_recce/data/recce_api.dart';
import 'package:signage_recce/features/live_recce/data/recce_controllers.dart';
import 'package:signage_recce/features/live_recce/data/recce_models.dart';
import 'package:signage_recce/features/live_recce/data/submit_validator.dart';
import 'package:signage_recce/features/live_recce/data/upload_queue.dart';
import 'package:signage_recce/features/live_recce/presentation/add_boards_screen.dart';

/// Milestone 1 of the per-board workflow: one item per physical board with its own key and number, "Add boards"
/// (media type, quantity, same or different sizes), and the seven photos of EVERY board. Fake data and fake API only.

Map<String, dynamic> _detail(List<Map<String, dynamic>> items, {bool editable = true, List<Map<String, dynamic>> photos = const []}) => {
      'siteId': 's1',
      'siteCode': 'SM-1',
      'project': {'id': 'p1', 'code': 'ADN-1', 'name': 'South', 'closed': false},
      'status': 'IN_PROGRESS',
      'editable': editable,
      'version': 0,
      'mediaItems': items,
      'photos': photos,
      'progress': {'percent': 0, 'required': 0, 'done': 0, 'missing': []},
      'reworks': [],
    };

Map<String, dynamic> _item(String key, {String type = 'GSB', int seq = 1, double w = 6, double h = 4}) =>
    {'key': key, 'name': 'GSB Board (Glow Sign Board)', 'mediaType': type, 'seq': seq, 'quantity': 1, 'width': w, 'height': h, 'unit': 'FT', 'required': <String>[]};

Map<String, dynamic> _photo(String id, String category, String mediaKey) =>
    {'id': id, 'category': category, 'state': 'DRAFT', 'mediaKey': mediaKey, 'lat': 13.04, 'lng': 80.23, 'gpsAccuracy': 8.0, 'gpsVerified': true, 'url': 'http://host/$id.jpg'};

/// Keeps what the phone sends to PUT /draft and answers like the server (the boards it was given).
class _FakeApi extends RecceApi {
  _FakeApi(this.onServer) : super(Dio());

  List<Map<String, dynamic>> onServer;
  List<Map<String, dynamic>>? sent;
  List<Map<String, dynamic>> photos = [];
  final deleted = <String>[];
  int saves = 0;
  String? failWith;
  bool editable = true;

  @override
  Future<ShopDetail> detail(String siteId) async => ShopDetail.fromJson(_detail(onServer, editable: editable, photos: photos));

  @override
  Future<void> deletePhoto(String siteId, String photoId, {String? reason}) async {
    deleted.add(photoId);
    photos = [for (final p in photos) if (p['id'] != photoId) p];
  }

  @override
  Future<ShopDetail> saveDraft(String siteId, {List<BoardItem>? mediaItems, Installation? installation, String? notes}) async {
    saves++;
    if (failWith != null) throw ApiException(code: 'BAD_REQUEST', message: failWith!);
    sent = [for (final b in mediaItems!) {...b.toJson(), 'required': <String>[]}];
    onServer = sent!;
    return ShopDetail.fromJson(_detail(onServer, editable: editable));
  }

  @override
  Future<List<RecceVersion>> versions(String siteId) async => const [];
}

Future<({_FakeApi api, UploadQueue queue, ShopDetailController c})> _rig(List<Map<String, dynamic>> items) async {
  final api = _FakeApi(items);
  final queue = UploadQueue(api, autoRetry: false);
  final c = ShopDetailController(api, queue, 's1');
  await c.load();
  return (api: api, queue: queue, c: c);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('board identity', () {
    test('a numbered board reads GSB-01 and sends its media type and number; an older line has neither', () {
      final b = BoardItem(key: 'b1', name: 'GSB Board (Glow Sign Board)', mediaType: 'GSB', seq: 1, width: 6, height: 4);
      expect(b.isNumbered, isTrue);
      expect(b.label, 'GSB-01');
      expect(b.toJson()['mediaType'], 'GSB');
      expect(b.toJson()['seq'], 1);
      expect(BoardItem(key: 'b2', mediaType: 'ACP 2D', seq: 12).label, 'ACP 2D-12');

      final old = BoardItem.fromJson({'key': 'm1', 'name': 'GSB Single Side', 'quantity': 2, 'width': 6, 'height': 4});
      expect(old.isNumbered, isFalse);
      expect(old.label, 'GSB Single Side (m1)');
      expect(old.quantity, 2); // an older line may still stand for several identical boards
      expect(old.toJson().containsKey('mediaType'), isFalse);
      expect(old.toJson().containsKey('seq'), isFalse);
    });

    test('the key never changes and the server-only list of required photos is not sent back', () {
      final b = BoardItem.fromJson({..._item('b7', seq: 3), 'required': ['SHOP_FRONT', 'NAME_BOARD']});
      expect(b.requiredPhotos, ['SHOP_FRONT', 'NAME_BOARD']);
      expect(b.toJson().containsKey('required'), isFalse);
      expect(b.copy().key, 'b7');
      expect(b.copy().requiredPhotos, ['SHOP_FRONT', 'NAME_BOARD']);
    });

    test('the next number follows the highest one of that media type', () {
      final boards = [BoardItem(key: 'b1', mediaType: 'GSB', seq: 1), BoardItem(key: 'b2', mediaType: 'GSB', seq: 3), BoardItem(key: 'b3', mediaType: 'Acrylic', seq: 1)];
      expect(nextBoardSeq(boards, 'GSB'), 4);
      expect(nextBoardSeq(boards, 'Acrylic'), 2);
      expect(nextBoardSeq(boards, 'NLB'), 1);
      expect(nextBoardSeq(const [], 'GSB'), 1);
    });
  });

  group('photos belong to one board', () {
    final d = ShopDetail.fromJson(_detail(
      [_item('b1'), _item('b2', seq: 2)],
      photos: [_photo('p1', 'SHOP_FRONT', 'b1'), _photo('p2', 'SHOP_FRONT', ''), _photo('p3', 'LEFT_SIDE', 'b2')],
    ));

    test('a board photo wins; a photo with no board stands in for every board; another board photo never counts', () {
      expect(d.photoOf('SHOP_FRONT', 'b1')!.id, 'p1');
      expect(d.photoOf('SHOP_FRONT', 'b2')!.id, 'p2'); // the old shared photo
      expect(d.photoOf('LEFT_SIDE', 'b2')!.id, 'p3');
      expect(d.photoOf('LEFT_SIDE', 'b1'), isNull); // p3 is GSB-02's
      expect(d.photoOf('RIGHT_SIDE', 'b1'), isNull);
    });

    test('the seven standard photos are the existing server categories, none renamed', () {
      expect(boardPhotoCategories.map((c) => c.key), ['SHOP_FRONT', 'LEFT_SIDE', 'RIGHT_SIDE', 'LONG_SHOT', 'ANNOTATED_VIEW', 'LOCATION_VIEW', 'ACCESS_PATH']);
      expect(boardPhotoCategories.map((c) => c.label), ['Front View', 'Left View', 'Right View', 'Long Shot', 'Annotated View', 'Location View', 'Access Path']);
      expect(photoCategoryLabel('LEFT_SIDE'), 'Left View');
      expect(photoCategoryLabel('SIDE_VIEW'), 'Side View'); // the earlier six keep their names
    });

    test('a category the server requires beyond the seven gets its own tile, only on the board that needs it', () {
      final more = ShopDetail.fromJson({
        ..._detail([
          {..._item('b1'), 'required': ['SHOP_FRONT', 'NAME_BOARD']},
          _item('b2', seq: 2),
        ]),
        'categories': [
          {'key': 'NAME_BOARD', 'label': 'Shop Name Board'},
        ],
      });
      expect(more.extraTilesFor(more.mediaItems[0]).map((c) => c.key), ['NAME_BOARD']);
      expect(more.extraTilesFor(more.mediaItems[0]).single.label, 'Shop Name Board');
      expect(more.extraTilesFor(more.mediaItems[1]), isEmpty);
    });
  });

  group('submit validator: every board has its own photos', () {
    List<ShopPhoto> allFor(String board) => [for (final c in boardPhotoCategories) ShopPhoto.fromJson(_photo('${board}_${c.key}', c.key, board))];
    Installation answered() => Installation(ladderRequired: triYes, scaffoldingRequired: triNo, craneRequired: triNo, hydraRequired: triNo, manualInstallationPossible: triYes);
    final two = [BoardItem(key: 'b1', mediaType: 'GSB', seq: 1, width: 6, height: 4), BoardItem(key: 'b2', mediaType: 'GSB', seq: 2, width: 8, height: 4)];

    test('GSB-01 complete, GSB-02 untouched: every missing line names GSB-02 and none names GSB-01', () {
      final p = validateForSubmit(photos: allFor('b1'), boards: two, installation: answered());
      expect(p, hasLength(7));
      expect(p.every((e) => e.startsWith('GSB-02: ') && e.endsWith('photo is missing')), isTrue);
      expect(p, contains('GSB-02: Front View photo is missing'));
    });

    test('the first board is not satisfied by the second board photos', () {
      final p = validateForSubmit(photos: allFor('b2'), boards: two, installation: answered());
      expect(p.every((e) => e.startsWith('GSB-01: ')), isTrue);
      expect(p, hasLength(7));
    });

    test('both boards complete passes; a board photo without GPS blocks only its board', () {
      expect(validateForSubmit(photos: [...allFor('b1'), ...allFor('b2')], boards: two, installation: answered()), isEmpty);
      final noGps = [
        ...allFor('b1'),
        for (final c in boardPhotoCategories) ShopPhoto.fromJson({..._photo('x_${c.key}', c.key, 'b2'), 'lat': null, 'lng': null}),
      ];
      final p = validateForSubmit(photos: noGps, boards: two, installation: answered());
      expect(p, hasLength(7));
      expect(p.every((e) => e.startsWith('GSB-02: ') && e.contains('GPS')), isTrue);
    });

    test('one board keeps the short lines without a board name', () {
      final p = validateForSubmit(photos: const [], boards: [two.first], installation: answered());
      expect(p, contains('Front View photo is missing'));
      expect(p.any((e) => e.contains('GSB-01')), isFalse);
    });
  });

  group('Add boards (controller)', () {
    test('quantity 2 with different sizes makes GSB-01 6x4 and GSB-02 8x4, each with its own key, saved at once', () async {
      final r = await _rig([]);
      final err = await r.c.addBoardsOfType(mediaType: 'GSB', name: 'GSB Board (Glow Sign Board)', unit: 'FT', sizes: [(width: 6, height: 4), (width: 8, height: 4)]);
      expect(err, isNull);
      expect(r.api.saves, 1);
      expect(r.api.sent!.map((b) => b['key']), ['b1', 'b2']);
      expect(r.api.sent!.map((b) => '${b['mediaType']}-${b['seq']}'), ['GSB-1', 'GSB-2']);
      expect(r.api.sent!.map((b) => b['quantity']), [1, 1]); // one physical board per item
      expect(r.api.sent!.map((b) => b['width']), [6.0, 8.0]);
      expect(r.c.boards.map((b) => b.label), ['GSB-01', 'GSB-02']);
      expect(r.c.dirty, isFalse);
      r.c.dispose();
      r.queue.dispose();
    });

    test('the same size for both boards: both get the one size, but still two boards', () async {
      final r = await _rig([]);
      await r.c.addBoardsOfType(mediaType: 'GSB', name: 'GSB', unit: 'FT', sizes: [(width: 6, height: 4), (width: 6, height: 4)]);
      expect(r.c.boards, hasLength(2));
      expect(r.c.boards.map((b) => b.width), [6.0, 6.0]);
      expect(r.c.boards.map((b) => b.key).toSet(), hasLength(2));
      r.c.dispose();
      r.queue.dispose();
    });

    test('a second media type is numbered from 1 and the first keeps its numbers (Acrylic rejected never touches GSB)', () async {
      final r = await _rig([_item('b1'), _item('b2', seq: 2, w: 8)]);
      await r.c.addBoardsOfType(mediaType: 'Acrylic', name: 'Clear Acrylic', unit: 'FT', sizes: [(width: 3, height: 2)]);
      expect(r.c.boards.map((b) => b.label), ['GSB-01', 'GSB-02', 'Acrylic-01']);
      expect(r.c.boards.map((b) => b.key), ['b1', 'b2', 'b3']);
      await r.c.addBoardsOfType(mediaType: 'GSB', name: 'GSB', unit: 'FT', sizes: [(width: 5, height: 3)]);
      expect(r.c.boards.last.label, 'GSB-03');
      r.c.dispose();
      r.queue.dispose();
    });

    test('a refused save leaves the boards as they were and is told to the person', () async {
      final r = await _rig([_item('b1')]);
      r.api.failWith = 'Two boards have the same number';
      final err = await r.c.addBoardsOfType(mediaType: 'GSB', name: 'GSB', unit: 'FT', sizes: [(width: 6, height: 4)]);
      expect(err, 'Two boards have the same number');
      expect(r.c.boards.map((b) => b.key), ['b1']);
      expect(r.c.dirty, isFalse);
      r.c.dispose();
      r.queue.dispose();
    });

    test('nothing is added for a locked shop, a missing size or when the shop is full', () async {
      final locked = await _rig([_item('b1')]);
      locked.api.editable = false;
      await locked.c.load();
      expect(await locked.c.addBoardsOfType(mediaType: 'GSB', name: 'GSB', unit: 'FT', sizes: [(width: 6, height: 4)]), contains('locked'));
      expect(locked.api.saves, 0);
      locked.c.dispose();
      locked.queue.dispose();

      final r = await _rig([_item('b1')]);
      expect(await r.c.addBoardsOfType(mediaType: 'GSB', name: 'GSB', unit: 'FT', sizes: [(width: 6, height: 0)]), contains('width and height'));
      expect(await r.c.addBoardsOfType(mediaType: 'GSB', name: 'GSB', unit: 'FT', sizes: [for (var i = 0; i < maxBoardItems; i++) (width: 1.0, height: 1.0)]), contains('hold $maxBoardItems'));
      expect(r.api.saves, 0);
      r.c.dispose();
      r.queue.dispose();
    });

    test('a board with photos cannot be removed and one without can', () async {
      final r = await _rig([_item('b1'), _item('b2', seq: 2)]);
      r.api.onServer = [_item('b1'), _item('b2', seq: 2)];
      r.c.detail = ShopDetail.fromJson(_detail([_item('b1'), _item('b2', seq: 2)], photos: [_photo('p1', 'SHOP_FRONT', 'b1')]));
      expect(r.c.boardHasPhotos('b1'), isTrue);
      expect(r.c.boardHasPhotos('b2'), isFalse);
      r.queue.add(UploadItem(id: 'c-up-00001', siteId: 's1', path: '/x.jpg', category: 'LEFT_SIDE', mediaKey: 'b2'));
      expect(r.c.boardHasPhotos('b2'), isTrue); // an upload on its way counts too
      r.c.dispose();
      r.queue.dispose();
    });

    test('a media type added by mistake: every board of it goes, with its draft photos and its waiting uploads; other types stay', () async {
      final r = await _rig([_item('b1'), _item('b2', seq: 2), _item('b3', type: 'ACP')]);
      r.api.photos = [_photo('p1', 'SHOP_FRONT', 'b1'), _photo('p2', 'LEFT_SIDE', 'b2'), _photo('p3', 'SHOP_FRONT', 'b3')];
      await r.c.refresh();
      r.queue.add(UploadItem(id: 'c-up-00002', siteId: 's1', path: '/x.jpg', category: 'RIGHT_SIDE', mediaKey: 'b2'));
      expect(r.c.photosOfType('GSB'), (drafts: 2, submitted: 0, waiting: 1));
      expect(await r.c.removeMediaType('GSB'), isNull);
      expect(r.api.deleted, unorderedEquals(['p1', 'p2'])); // its draft photos go with it, the other type's photo stays
      expect(r.queue.forShop('s1').where((u) => u.mediaKey == 'b2'), isEmpty);
      expect(r.c.boards.map((b) => b.key), ['b3']);
      expect(r.c.dirty, isTrue); // like every board change, saved with the draft
      r.c.dispose();
      r.queue.dispose();
    });

    test('a media type with submitted photos cannot be removed, and nothing is touched', () async {
      final r = await _rig([_item('b1'), _item('b2', type: 'ACP')]);
      r.api.photos = [{..._photo('p1', 'SHOP_FRONT', 'b1'), 'state': 'SUBMITTED'}, _photo('p2', 'SHOP_FRONT', 'b2')];
      await r.c.refresh();
      expect(await r.c.removeMediaType('GSB'), contains('already submitted'));
      expect(r.api.deleted, isEmpty);
      expect(r.c.boards, hasLength(2));
      expect(await r.c.removeMediaType('ACP'), isNull); // the other type has only a draft photo
      expect(r.c.boards.map((b) => b.key), ['b1']);
      r.c.dispose();
      r.queue.dispose();
    });

    test('photo places: seven per board, in board order', () async {
      final r = await _rig([_item('b1'), _item('b2', seq: 2)]);
      final slots = r.c.photoSlots();
      expect(slots, hasLength(14));
      expect(slots.first.mediaKey, 'b1');
      expect(slots[7].mediaKey, 'b2');
      expect(slots.map((s) => s.category).toSet(), boardPhotoCategories.map((c) => c.key).toSet());
      r.c.dispose();
      r.queue.dispose();
    });
  });

  group('Add boards (screen)', () {
    Future<void> open(WidgetTester tester, ShopDetailController c) async {
      tester.view.physicalSize = const Size(420, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: AddBoardsScreen(ctrl: c)));
    }

    Future<void> tick(WidgetTester tester, String code) async {
      await tester.tap(find.byKey(Key('media_$code')));
      await tester.pump();
    }

    testWidgets('shows the media type cards first; quantity and sizes appear after a type is ticked', (tester) async {
      final r = await _rig([]);
      await open(tester, r.c);
      expect(find.text('Media types'), findsOneWidget);
      expect(find.text('Choose one or more media types'), findsOneWidget);
      expect(find.byKey(const Key('media_GSB')), findsOneWidget);
      expect(find.text('GSB Board (Glow Sign Board)'), findsOneWidget);
      expect(find.byKey(const Key('qty-plus-GSB')), findsNothing);
      await tick(tester, 'GSB');
      expect(find.byKey(const Key('qty-plus-GSB')), findsOneWidget);
      expect(find.byKey(const Key('same-size-GSB')), findsNothing); // one board: no same / different question
      expect(find.text('Add GSB-01'), findsOneWidget);
      await tick(tester, 'GSB'); // a second tap un-ticks it again
      expect(find.byKey(const Key('qty-plus-GSB')), findsNothing);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('quantity 2, different sizes: one width and height row per board, then both boards are saved', (tester) async {
      final r = await _rig([]);
      await open(tester, r.c);
      await tick(tester, 'GSB');
      await tester.tap(find.byKey(const Key('qty-plus-GSB')));
      await tester.pump();
      expect(find.text('2'), findsWidgets);
      expect(find.byKey(const Key('same-size-GSB')), findsOneWidget);
      expect(find.byKey(const Key('width-GSB-1')), findsNothing); // same size is the default: one row
      await tester.tap(find.text('Different sizes'));
      await tester.pump();
      expect(find.text('GSB-01'), findsOneWidget);
      expect(find.text('GSB-02'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('width-GSB-0')), '6');
      await tester.enterText(find.byKey(const Key('height-GSB-0')), '4');
      await tester.enterText(find.byKey(const Key('width-GSB-1')), '8');
      await tester.enterText(find.byKey(const Key('height-GSB-1')), '4');
      await tester.tap(find.byKey(const Key('add-boards-save')));
      await tester.pumpAndSettle();
      expect(r.c.boards.map((b) => b.label), ['GSB-01', 'GSB-02']);
      expect(r.c.boards.map((b) => b.width), [6.0, 8.0]);
      expect(r.c.boards.map((b) => b.mediaCode), ['GSB', 'GSB']); // the catalog code is kept on each board
      expect(r.api.saves, 1);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('same size for all: one width and height is applied to both boards', (tester) async {
      final r = await _rig([]);
      await open(tester, r.c);
      await tick(tester, 'GSB');
      await tester.tap(find.byKey(const Key('qty-plus-GSB')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('width-GSB-0')), '6');
      await tester.enterText(find.byKey(const Key('height-GSB-0')), '4');
      await tester.tap(find.byKey(const Key('add-boards-save')));
      await tester.pumpAndSettle();
      expect(r.c.boards.map((b) => b.label), ['GSB-01', 'GSB-02']);
      expect(r.c.boards.map((b) => '${b.width}x${b.height}'), ['6.0x4.0', '6.0x4.0']);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('several media types in one go: each has its own quantity and size, all saved in ONE save, numbered per type', (tester) async {
      final r = await _rig([]);
      await open(tester, r.c);
      await tick(tester, 'GSB');
      await tick(tester, 'ACRYLIC');
      expect(find.byKey(const Key('type-card-GSB')), findsOneWidget);
      expect(find.byKey(const Key('type-card-ACRYLIC')), findsOneWidget);
      expect(find.text('Add 2 boards'), findsOneWidget);
      await tester.tap(find.byKey(const Key('qty-plus-GSB'))); // GSB: two boards, Acrylic: one
      await tester.pump();
      expect(find.text('Add 3 boards'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('width-GSB-0')), '6');
      await tester.enterText(find.byKey(const Key('height-GSB-0')), '4');
      await tester.enterText(find.byKey(const Key('width-ACRYLIC-0')), '3');
      await tester.enterText(find.byKey(const Key('height-ACRYLIC-0')), '2');
      await tester.tap(find.byKey(const Key('add-boards-save')));
      await tester.pumpAndSettle();
      expect(r.api.saves, 1);
      expect(r.c.boards.map((b) => b.label), ['GSB-01', 'GSB-02', 'Acrylic-01']);
      expect(r.c.boards.map((b) => b.mediaCode), ['GSB', 'GSB', 'ACRYLIC']);
      expect(r.c.boards.map((b) => b.width), [6.0, 6.0, 3.0]);
      expect(r.c.photoBoard!.label, 'GSB-01'); // the first new board is the one photographed first
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('a missing size names the type that lacks it and nothing is saved', (tester) async {
      final r = await _rig([]);
      await open(tester, r.c);
      await tick(tester, 'GSB');
      await tick(tester, 'ACRYLIC');
      await tester.enterText(find.byKey(const Key('width-GSB-0')), '6');
      await tester.enterText(find.byKey(const Key('height-GSB-0')), '4'); // Acrylic has no size
      await tester.tap(find.byKey(const Key('add-boards-save')));
      await tester.pump();
      expect(find.text('Enter the width and height of Acrylic.'), findsOneWidget);
      expect(r.api.saves, 0);
      expect(r.c.boards, isEmpty);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('the shop limit is shared by all ticked types: + stops when the shop is full', (tester) async {
      final r = await _rig([for (var i = 1; i <= 10; i++) _item('b$i', seq: i)]); // 10 of 12 boards used
      await open(tester, r.c);
      await tick(tester, 'GSB');
      await tester.tap(find.byKey(const Key('qty-plus-GSB')));
      await tester.pump();
      expect(find.byKey(const Key('qty-value-GSB')), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const Key('qty-plus-GSB'))).onPressed, isNull); // 10 + 2 = 12
      await tick(tester, 'ACRYLIC'); // a third board would be the 13th
      expect(find.byKey(const Key('type-card-ACRYLIC')), findsNothing);
      expect(find.byKey(const Key('add-boards-error')), findsOneWidget);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('a missing size is explained and nothing is saved', (tester) async {
      final r = await _rig([]);
      await open(tester, r.c);
      await tick(tester, 'GSB');
      await tester.tap(find.byKey(const Key('add-boards-save')));
      await tester.pump();
      expect(find.byKey(const Key('add-boards-error')), findsOneWidget);
      expect(r.api.saves, 0);
      expect(r.c.boards, isEmpty);
      r.c.dispose();
      r.queue.dispose();
    });
  });
}
