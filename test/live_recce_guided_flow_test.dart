import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/features/live_recce/data/recce_api.dart';
import 'package:signage_recce/features/live_recce/data/recce_controllers.dart';
import 'package:signage_recce/features/live_recce/data/recce_models.dart';
import 'package:signage_recce/features/live_recce/data/upload_queue.dart';
import 'package:signage_recce/features/live_recce/presentation/boards_tab.dart';
import 'package:signage_recce/features/live_recce/presentation/installation_tab.dart';

/// Guided flow of the shop screen (Boards, Photos, Install, Review): what makes a step "done", the media type cards on the
/// Boards tab (no dropdown), and the Continue button of the Install tab. Fake data and a fake API only.

Map<String, dynamic> _detail(List<Map<String, dynamic>> items, {List<Map<String, dynamic>> photos = const []}) => {
      'siteId': 's1',
      'siteCode': 'SM-1',
      'project': {'id': 'p1', 'code': 'ADN-1', 'name': 'South', 'closed': false},
      'status': 'IN_PROGRESS',
      'editable': true,
      'version': 0,
      'mediaItems': items,
      'photos': photos,
      'progress': {'percent': 0, 'required': 0, 'done': 0, 'missing': []},
      'reworks': [],
    };

Map<String, dynamic> _item(String key, {String? type = 'GSB', int seq = 1, int qty = 1, double? w = 6, double? h = 4, String name = 'GSB Board (Glow Sign Board)'}) => {
      'key': key,
      'name': name,
      'mediaType': ?type,
      if (type != null) 'seq': seq,
      'quantity': qty,
      'width': ?w,
      'height': ?h,
      'unit': 'FT',
      'required': <String>[],
    };

Map<String, dynamic> _photo(String id, String category, String mediaKey) =>
    {'id': id, 'category': category, 'state': 'DRAFT', 'mediaKey': mediaKey, 'lat': 13.04, 'lng': 80.23, 'gpsAccuracy': 8.0, 'gpsVerified': true, 'url': 'http://host/$id.jpg'};

class _Api extends RecceApi {
  _Api(this.items, {this.photos = const []}) : super(Dio());

  List<Map<String, dynamic>> items;
  List<Map<String, dynamic>> photos;

  @override
  Future<ShopDetail> detail(String siteId) async => ShopDetail.fromJson(_detail(items, photos: photos));

  @override
  Future<ShopDetail> saveDraft(String siteId, {List<BoardItem>? mediaItems, Installation? installation, String? notes}) async {
    items = [for (final b in mediaItems!) {...b.toJson(), 'required': <String>[]}];
    return ShopDetail.fromJson(_detail(items, photos: photos));
  }

  @override
  Future<List<RecceVersion>> versions(String siteId) async => const [];
}

Future<({_Api api, UploadQueue queue, ShopDetailController c})> _rig(List<Map<String, dynamic>> items, {List<Map<String, dynamic>> photos = const []}) async {
  final api = _Api(items, photos: photos);
  final queue = UploadQueue(api, autoRetry: false);
  final c = ShopDetailController(api, queue, 's1');
  await c.load();
  return (api: api, queue: queue, c: c);
}

void _bigPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('which steps are done', () {
    test('Boards: needs at least one board, and each board needs its type and its size', () async {
      final r = await _rig([]);
      expect(r.c.boardsDone, isFalse); // no board yet
      r.c.boards.add(BoardItem(key: 'b1')); // a board with no size
      expect(r.c.boardsDone, isFalse);
      r.c.boards.first
        ..width = 6
        ..height = 4;
      expect(r.c.boardsDone, isTrue);
      r.c.boards.first.name = '';
      expect(r.c.boardsDone, isFalse); // no type
      r.c.dispose();
      r.queue.dispose();
    });

    test('Photos: done only when every one of the seven places of EVERY saved board has a photo', () async {
      final seven = [for (final c in boardPhotoCategories) _photo('b1_${c.key}', c.key, 'b1')];
      final noBoards = await _rig([]);
      expect(noBoards.c.photosDone, isFalse);
      noBoards.c.dispose();
      noBoards.queue.dispose();

      final six = await _rig([_item('b1')], photos: seven.take(6).toList());
      expect(six.c.photosDone, isFalse);
      six.c.dispose();
      six.queue.dispose();

      final all = await _rig([_item('b1')], photos: seven);
      expect(all.c.photosDone, isTrue);
      all.c.dispose();
      all.queue.dispose();

      // a second board has none of them yet
      final two = await _rig([_item('b1'), _item('b2', seq: 2)], photos: seven);
      expect(two.c.photosDone, isFalse);
      two.c.dispose();
      two.queue.dispose();
    });

    test('Photos: a picture that is on the phone and uploading counts, so the person is not held back by the network', () async {
      final seven = [for (final c in boardPhotoCategories) _photo('b1_${c.key}', c.key, 'b1')];
      final r = await _rig([_item('b1')], photos: seven.take(6).toList());
      expect(r.c.photosDone, isFalse);
      r.queue.add(UploadItem(id: 'c-up-00001', siteId: 's1', path: '/x.jpg', category: boardPhotoCategories.last.key, mediaKey: 'b1'));
      expect(r.c.photosDone, isTrue);
      r.c.dispose();
      r.queue.dispose();
    });

    test('Install: done when the five required answers are given; the optional fields do not matter', () async {
      final r = await _rig([_item('b1')]);
      expect(r.c.installDone, isFalse);
      r.c.installation
        ..ladderRequired = triYes
        ..scaffoldingRequired = triNo
        ..craneRequired = triNo
        ..hydraRequired = triNo;
      expect(r.c.installDone, isFalse); // one left
      r.c.installation.manualInstallationPossible = triYes;
      expect(r.c.installDone, isTrue);
      r.c.installation.installationHeightFt = 900; // above what the server accepts
      expect(r.c.installDone, isFalse);
      r.c.dispose();
      r.queue.dispose();
    });
  });

  group('board by board: which board is being photographed', () {
    List<Map<String, dynamic>> sevenOf(String board) => [for (final c in boardPhotoCategories) _photo('${board}_${c.key}', c.key, board)];

    test('the first board that still lacks photos is the one being photographed', () async {
      final r = await _rig([_item('b1'), _item('b2', seq: 2), _item('b3', seq: 3)], photos: sevenOf('b1'));
      expect(r.c.boardPhotosDone('b1'), isTrue);
      expect(r.c.boardPhotosDone('b2'), isFalse);
      expect(r.c.firstBoardWithoutPhotos!.key, 'b2');
      expect(r.c.photoBoard!.key, 'b2'); // b1 is done, so the flow stands at b2
      r.c.dispose();
      r.queue.dispose();
    });

    test('with every board done nothing is missing; the last board stays the open one', () async {
      final r = await _rig([_item('b1'), _item('b2', seq: 2)], photos: [...sevenOf('b1'), ...sevenOf('b2')]);
      expect(r.c.firstBoardWithoutPhotos, isNull);
      expect(r.c.photosDone, isTrue);
      expect(r.c.photoBoard!.key, 'b2');
      r.c.dispose();
      r.queue.dispose();
    });

    test('a photo of one board never completes another board', () async {
      final r = await _rig([_item('b1'), _item('b2', seq: 2)], photos: sevenOf('b2'));
      expect(r.c.boardPhotosDone('b1'), isFalse);
      expect(r.c.boardPhotosDone('b2'), isTrue);
      expect(r.c.photosDone, isFalse);
      expect(r.c.boardPhotosDone('nope'), isFalse); // an unknown board is never "done"
      r.c.dispose();
      r.queue.dispose();
    });

    test('the person can open another board; an unknown or removed board falls back to the flow', () async {
      final r = await _rig([_item('b1'), _item('b2', seq: 2)]);
      expect(r.c.photoBoard!.key, 'b1');
      var told = 0;
      r.c.addListener(() => told++);
      r.c.focusBoard('b2');
      expect(r.c.photoBoard!.key, 'b2');
      expect(told, 1);
      r.c.focusBoard('b2'); // no change, nobody is told again
      expect(told, 1);
      r.c.boards.removeWhere((b) => b.key == 'b2');
      expect(r.c.photoBoard!.key, 'b1');
      r.c.dispose();
      r.queue.dispose();
    });

    test('Add boards makes the first new board the one being photographed next', () async {
      final r = await _rig([_item('b1')], photos: sevenOf('b1'));
      expect(r.c.photoBoard!.key, 'b1');
      final err = await r.c.addBoardsOfType(mediaType: 'Acrylic', name: 'Clear Acrylic', unit: 'FT', sizes: [(width: 3, height: 2), (width: 4, height: 2)]);
      expect(err, isNull);
      expect(r.c.boards.map((b) => b.label), ['GSB-01', 'Acrylic-01', 'Acrylic-02']);
      expect(r.c.photoBoard!.label, 'Acrylic-01');
      expect(r.c.firstBoardWithoutPhotos!.label, 'Acrylic-01');
      r.c.dispose();
      r.queue.dispose();
    });

    test('a refused save leaves the flow where it was', () async {
      final r = await _rig([_item('b1')], photos: sevenOf('b1'));
      r.api.items = [_item('b1')];
      final err = await r.c.addBoardsOfType(mediaType: 'GSB', name: 'GSB', unit: 'FT', sizes: [(width: 0, height: 4)]);
      expect(err, isNotNull);
      expect(r.c.photoBoard!.key, 'b1');
      r.c.dispose();
      r.queue.dispose();
    });
  });

  group('change the type of an older line', () {
    test('a single older line becomes a numbered board of the new type; the key and size stay', () async {
      final r = await _rig([_item('m1', type: null, name: 'Board')]);
      r.c.changeBoardType(r.c.boards.first, mediaType: 'GSB', name: 'GSB Board (Glow Sign Board)');
      final b = r.c.boards.first;
      expect(b.key, 'm1');
      expect(b.label, 'GSB-01');
      expect(b.name, 'GSB Board (Glow Sign Board)');
      expect(b.width, 6.0);
      expect(r.c.dirty, isTrue);
      r.c.dispose();
      r.queue.dispose();
    });

    test('it takes the next free number when the shop already has boards of that type', () async {
      final r = await _rig([_item('b1'), _item('m1', type: null, name: 'Board')]);
      r.c.changeBoardType(r.c.boards[1], mediaType: 'GSB', name: 'GSB Board (Glow Sign Board)');
      expect(r.c.boards.map((b) => b.label), ['GSB-01', 'GSB-02']);
      r.c.dispose();
      r.queue.dispose();
    });

    test('a line that stands for several boards only takes the name (one number cannot name several boards)', () async {
      final r = await _rig([_item('m1', type: null, name: 'Board', qty: 3)]);
      r.c.changeBoardType(r.c.boards.first, mediaType: 'GSB', name: 'GSB Board (Glow Sign Board)');
      expect(r.c.boards.first.name, 'GSB Board (Glow Sign Board)');
      expect(r.c.boards.first.isNumbered, isFalse);
      expect(r.c.boards.first.quantity, 3);
      r.c.dispose();
      r.queue.dispose();
    });

    test('a numbered board keeps its type', () async {
      final r = await _rig([_item('b1')]);
      r.c.changeBoardType(r.c.boards.first, mediaType: 'ACP 2D', name: 'ACP 2D (Flat Artwork)');
      expect(r.c.boards.first.label, 'GSB-01');
      expect(r.c.dirty, isFalse);
      r.c.dispose();
      r.queue.dispose();
    });
  });

  group('Boards tab', () {
    Future<void> show(WidgetTester tester, ShopDetailController c, {VoidCallback? onBoardsAdded}) async {
      _bigPhone(tester);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: ListenableBuilder(listenable: c, builder: (_, _) => BoardsTab(ctrl: c, onBoardsAdded: onBoardsAdded))),
      ));
    }

    testWidgets('an older line chooses its type on the media type cards: no "Board type" dropdown and no free "Type name" box', (tester) async {
      final r = await _rig([_item('m1', type: null, name: 'Board')]);
      await show(tester, r.c);
      expect(find.text('Board type *'), findsNothing);
      expect(find.text('Type name *'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget); // only the Unit box is left
      expect(find.text('Media type *'), findsOneWidget);
      expect(find.text('Board'), findsWidgets); // the card header and the media type box both show the name

      await tester.tap(find.byKey(const Key('board-pick-type')));
      await tester.pumpAndSettle();
      expect(find.text('Choose one of 13 media types'), findsOneWidget);
      expect(find.byKey(const Key('media_GSB')), findsOneWidget);
      await tester.tap(find.byKey(const Key('media_GSB')));
      await tester.pumpAndSettle();

      expect(find.text('Choose one of 13 media types'), findsNothing); // the sheet closed
      expect(r.c.boards.first.label, 'GSB-01');
      expect(r.c.dirty, isTrue);
      expect(find.byKey(const Key('board-media-type')), findsOneWidget); // now a numbered board: its type is fixed
      expect(find.byKey(const Key('board-pick-type')), findsNothing);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('a numbered board shows its type read-only and cannot be re-typed', (tester) async {
      final r = await _rig([_item('b1')]);
      await show(tester, r.c);
      expect(find.byKey(const Key('board-media-type')), findsOneWidget);
      expect(find.byKey(const Key('board-pick-type')), findsNothing);
      r.c.dispose();
      r.queue.dispose();
    });
  });

  group('Install tab', () {
    Future<void> show(WidgetTester tester, ShopDetailController c, VoidCallback onNext) async {
      _bigPhone(tester);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: ListenableBuilder(listenable: c, builder: (_, _) => InstallationTab(ctrl: c, onNext: onNext))),
      ));
    }

    testWidgets('Continue is blocked, with the open questions named, until the five required answers are given', (tester) async {
      final r = await _rig([_item('b1')]);
      var next = 0;
      await show(tester, r.c, () => next++);
      expect(tester.widget<FilledButton>(find.byKey(const Key('install-next'))).onPressed, isNull);
      expect(tester.widget<Text>(find.byKey(const Key('install-open'), skipOffstage: false)).data, 'Still to answer: Ladder, Scaffolding, Crane, Hydra, Manual installation');

      r.c.installation
        ..ladderRequired = triYes
        ..scaffoldingRequired = triNo
        ..craneRequired = triNo
        ..hydraRequired = triNo
        ..manualInstallationPossible = triYes;
      r.c.markDirty();
      await tester.pump();
      expect(find.byKey(const Key('install-open')), findsNothing);
      await tester.tap(find.byKey(const Key('install-next')));
      expect(next, 1);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('without a next step (a screen that has none) no Continue button is drawn', (tester) async {
      final r = await _rig([_item('b1')]);
      _bigPhone(tester);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: InstallationTab(ctrl: r.c))));
      expect(find.byKey(const Key('install-next')), findsNothing);
      r.c.dispose();
      r.queue.dispose();
    });
  });
}
