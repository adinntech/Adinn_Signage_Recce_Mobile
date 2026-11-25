import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signage_recce/core/network/api_exception.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/features/live_recce/data/catalog_controller.dart';
import 'package:signage_recce/features/live_recce/data/catalog_data.dart';
import 'package:signage_recce/features/live_recce/data/recce_api.dart';
import 'package:signage_recce/features/live_recce/data/recce_controllers.dart';
import 'package:signage_recce/features/live_recce/data/recce_models.dart';
import 'package:signage_recce/features/live_recce/data/upload_queue.dart';
import 'package:signage_recce/features/live_recce/presentation/boards_tab.dart';

/// Per-board installation requirement (C2): the catalog (built in, then the server's), the installation method and the site questions
/// of EACH board, quantity per media type, and the Boards tab cards. Fake data and a fake API only.

Map<String, dynamic> _detail(List<Map<String, dynamic>> items, {int version = 0, List<Map<String, dynamic>> photos = const []}) => {
      'siteId': 's1',
      'siteCode': 'SM-1',
      'project': {'id': 'p1', 'code': 'ADN-1', 'name': 'South', 'closed': false},
      'status': 'IN_PROGRESS',
      'editable': true,
      'version': version,
      'mediaItems': items,
      'photos': photos,
      'progress': {'percent': 0, 'required': 0, 'done': 0, 'missing': []},
      'reworks': [],
    };

Map<String, dynamic> _gsb(String key, int seq, {Map<String, dynamic> extra = const {}}) => {
      'key': key,
      'name': 'GSB Board (Glow Sign Board)',
      'mediaType': 'GSB',
      'seq': seq,
      'mediaCode': 'GSB',
      'quantity': 1,
      'width': 6,
      'height': 4,
      'unit': 'FT',
      'required': <String>[],
      ...extra,
    };

/// Every question GSB + Shop Fascia asks that is required (the dependent ones are not visible with these answers).
const _allAnswers = <String, dynamic>{
  'fascia_material': 'Concrete',
  'shutter_height': 9.0,
  'neighbour_clearance': true,
  'power_available': true,
  'light_type': 'LED modules',
  'existing_board': false,
  'access_method': 'Ladder',
  'owner_permission': true,
};

Map<String, dynamic> _photo(String id, String category, String mediaKey) =>
    {'id': id, 'category': category, 'state': 'DRAFT', 'mediaKey': mediaKey, 'lat': 13.04, 'lng': 80.23, 'gpsAccuracy': 8.0, 'gpsVerified': true, 'url': 'http://host/$id.jpg'};

class _Api extends RecceApi {
  _Api(this.items, {this.version = 0, this.photos = const []}) : super(Dio());

  List<Map<String, dynamic>> items;
  int version;
  List<Map<String, dynamic>> photos;
  List<Map<String, dynamic>>? sent;
  int saves = 0;

  // the catalog
  CatalogData? serverCatalog;
  Object? catalogError;
  final catalogAsked = <int?>[];

  @override
  Future<ShopDetail> detail(String siteId) async => ShopDetail.fromJson(_detail(items, version: version, photos: photos));

  @override
  Future<ShopDetail> saveDraft(String siteId, {List<BoardItem>? mediaItems, Installation? installation, String? notes}) async {
    saves++;
    sent = [for (final b in mediaItems!) {...b.toJson(), 'required': <String>[]}];
    items = sent!;
    return ShopDetail.fromJson(_detail(items, version: version, photos: photos));
  }

  @override
  Future<List<RecceVersion>> versions(String siteId) async => const [];

  @override
  Future<CatalogData?> catalog({int? version}) async {
    catalogAsked.add(version);
    if (catalogError != null) throw catalogError!;
    final s = serverCatalog;
    return s == null || s.version == version ? null : s;
  }
}

Future<({_Api api, UploadQueue queue, ShopDetailController c})> _rig(List<Map<String, dynamic>> items, {int version = 0, List<Map<String, dynamic>> photos = const [], CatalogController? catalog}) async {
  final api = _Api(items, version: version, photos: photos);
  final queue = UploadQueue(api, autoRetry: false);
  final c = ShopDetailController(api, queue, 's1', catalog: catalog);
  await c.load();
  return (api: api, queue: queue, c: c);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the built-in catalog', () {
    final cat = CatalogData.builtIn();

    test('is the same list the older editor uses: 13 media types offered, 5 legacy kept, 10 installation methods', () {
      expect(cat.isBuiltIn, isTrue);
      expect(cat.offered, hasLength(13));
      expect(cat.media.where((m) => m.legacy), hasLength(5));
      expect(cat.installations, hasLength(10));
      expect(cat.offered.first.code, 'GSB'); // the catalog order
    });

    test('offers a media type exactly the installation methods the older editor offers, and asks exactly the same questions', () {
      for (final m in SignageCatalog.catalogMedia) {
        expect(cat.installationsFor(m.code).map((i) => i.code), SignageCatalog.installationsFor(m.code).map((i) => i.code), reason: m.code);
        for (final i in m.installations) {
          expect(cat.questionsFor(m.code, i).map((q) => q.id), SignageCatalog.questionsFor(m.code, i).map((q) => q.id), reason: '${m.code}/$i');
        }
      }
    });

    test('the questions of GSB with Shop Fascia: installation first, then the media, then the common ones', () {
      final ids = cat.questionsFor('GSB', 'shop_fascia').map((q) => q.id).toList();
      expect(ids.take(3), ['fascia_material', 'shutter_height', 'neighbour_clearance']);
      expect(ids, containsAll(['power_available', 'light_type', 'existing_board', 'access_method']));
      expect(cat.questionsFor('GSB', null).map((q) => q.id), isNot(contains('fascia_material'))); // no installation yet
    });

    test('a dependent question is only required when it shows', () {
      expect(cat.missingAnswers('GSB', 'shop_fascia', {..._allAnswers}), isEmpty);
      final dependent = cat.missingAnswers('GSB', 'shop_fascia', {..._allAnswers, 'power_available': false});
      expect(dependent.map((q) => q.id), ['power_distance']); // "no power point within 10 ft" now asks the distance
      expect(cat.missingAnswers('GSB', 'shop_fascia', {..._allAnswers, 'existing_board': true}).map((q) => q.id), ['remove_existing']);
    });

    test('survives a trip through JSON, which is how it is kept on the phone', () {
      final back = CatalogData.fromJson(Map<String, dynamic>.from(jsonDecode(jsonEncode(CatalogData(version: 7, media: cat.media, installations: cat.installations, questions: cat.questions).toJson())) as Map));
      expect(back.version, 7);
      expect(back.media.length, cat.media.length);
      expect(back.questionsFor('GSB', 'shop_fascia').map((q) => q.id), cat.questionsFor('GSB', 'shop_fascia').map((q) => q.id));
      final dep = back.questions.firstWhere((q) => q.id == 'remove_existing');
      expect((dep.showIfId, dep.showIfValue), ('existing_board', true));
    });

    test('an inactive media type is not offered; an inactive installation or question is not asked; the admin order wins', () {
      final edited = CatalogData(
        version: 2,
        media: [const CatalogMedia(code: 'AAA', shortName: 'A', name: 'A board', installations: ['i2', 'i1'], order: 1), const CatalogMedia(code: 'BBB', shortName: 'B', name: 'B board', active: false, order: 0)],
        installations: [const CatalogInstallation(code: 'i1', name: 'One', order: 0), const CatalogInstallation(code: 'i2', name: 'Two', order: 1, active: false)],
        questions: [
          const CatalogQuestion(id: 'q_b', label: 'B', type: 'TEXT', scope: 'MEDIA', scopeCode: 'AAA', order: 1),
          const CatalogQuestion(id: 'q_a', label: 'A', type: 'TEXT', scope: 'MEDIA', scopeCode: 'AAA', order: 0),
          const CatalogQuestion(id: 'q_off', label: 'Off', type: 'TEXT', scope: 'COMMON', active: false),
        ],
      );
      expect(edited.offered.map((m) => m.code), ['AAA']);
      expect(edited.installationsFor('AAA').map((i) => i.code), ['i1']); // i2 is inactive
      expect(edited.questionsFor('AAA', null).map((q) => q.id), ['q_a', 'q_b']);
    });
  });

  group('the catalog on the phone', () {
    final server = CatalogData(version: 5, media: const [CatalogMedia(code: 'NEW', shortName: 'New', name: 'New board')], installations: const [CatalogInstallation(code: 'x', name: 'X')]);

    test('starts as the built-in copy, takes the server\'s when it is newer, and keeps it on the phone for next time', () async {
      final api = _Api([])..serverCatalog = server;
      final c = CatalogController(api);
      expect(c.data.isBuiltIn, isTrue);
      expect(await c.refresh(), isTrue);
      expect(c.data.version, 5);
      expect(c.data.offered.map((m) => m.code), ['NEW']);
      expect(api.catalogAsked, [null]); // never read yet: asked without a version

      final again = CatalogController(api);
      await again.init(); // the next start: the saved copy, before any network
      expect(again.data.version, 5);
      expect(await again.refresh(), isFalse); // "unchanged"
      expect(api.catalogAsked, [null, 5]); // now it asks "since version 5"
    });

    test('a read that fails keeps what the phone has (offline never leaves it without a catalog)', () async {
      final api = _Api([])..catalogError = const ApiException(code: 'NETWORK_ERROR', message: 'Cannot reach the server.');
      final c = CatalogController(api);
      expect(await c.refresh(), isFalse);
      expect(c.data.isBuiltIn, isTrue);
      expect(c.data.offered, hasLength(13));
      expect(c.lastError, isNotNull);
    });

    test('a damaged saved copy is ignored', () async {
      SharedPreferences.setMockInitialValues({CatalogController.cacheKey: '{not json'});
      final c = CatalogController(_Api([]));
      await c.init();
      expect(c.data.isBuiltIn, isTrue);
    });

    test('a board screen sees the new catalog the moment it arrives', () async {
      final api = _Api([_gsb('b1', 1)])..serverCatalog = server;
      final cc = CatalogController(api);
      final r = await _rig([_gsb('b1', 1)], catalog: cc);
      var told = 0;
      r.c.addListener(() => told++);
      expect(r.c.catalog.offered, hasLength(13));
      await cc.refresh();
      expect(r.c.catalog.offered.map((m) => m.code), ['NEW']);
      expect(told, greaterThan(0));
      r.c.dispose();
      r.queue.dispose();
    });
  });

  group('a board keeps its own installation requirement', () {
    test('the three fields survive the trip to the server and back; an older board has none', () {
      final b = BoardItem.fromJson(_gsb('b1', 1, extra: {'installationType': 'shop_fascia', 'answers': {'fascia_material': 'Brick', 'shutter_height': 9.5, 'neighbour_clearance': true}}));
      expect((b.mediaCode, b.installationType), ('GSB', 'shop_fascia'));
      expect(b.answers['shutter_height'], 9.5);
      final j = b.toJson();
      expect(j['mediaCode'], 'GSB');
      expect(j['installationType'], 'shop_fascia');
      expect(j['answers'], {'fascia_material': 'Brick', 'shutter_height': 9.5, 'neighbour_clearance': true});
      final copy = b.copy();
      copy.answers['fascia_material'] = 'Wooden';
      expect(b.answers['fascia_material'], 'Brick'); // a copy never shares the answers

      final old = BoardItem.fromJson({'key': 'm1', 'name': 'GSB Single Side', 'quantity': 2, 'width': 6, 'height': 4});
      expect(old.mediaCode, '');
      expect(old.installationType, isNull);
      expect(old.answers, isEmpty);
      expect(old.toJson().keys, isNot(containsAll(['mediaCode', 'installationType', 'answers'])));
    });

    test('the media of a board: by its code, by name for a numbered board made before codes, none for an older line', () async {
      final r = await _rig([
        _gsb('b1', 1),
        _gsb('b2', 2, extra: {'mediaCode': ''}), // numbered, no code stored
        {'key': 'm1', 'name': 'GSB Single Side', 'quantity': 1, 'width': 6, 'height': 4, 'unit': 'FT', 'required': <String>[]},
      ]);
      expect(r.c.mediaOf(r.c.boards[0])!.code, 'GSB');
      expect(r.c.mediaOf(r.c.boards[1])!.code, 'GSB'); // found by its name
      expect(r.c.mediaOf(r.c.boards[2]), isNull);
      expect(r.c.installationsOf(r.c.boards[0]).map((i) => i.code), ['shop_fascia', 'wall_mount', 'double_pole', 'single_pole', 'rooftop', 'support_pipe']);
      expect(r.c.installationsOf(r.c.boards[2]), isEmpty);
      r.c.dispose();
      r.queue.dispose();
    });

    test('who must fill it: a first submit of a board made from the catalog; never an older line and never a resubmission', () async {
      final first = await _rig([_gsb('b1', 1), {'key': 'm1', 'name': 'GSB Single Side', 'quantity': 1, 'width': 6, 'height': 4, 'unit': 'FT', 'required': <String>[]}]);
      expect(first.c.needsInstallation(first.c.boards[0]), isTrue);
      expect(first.c.needsInstallation(first.c.boards[1]), isFalse);
      first.c.dispose();
      first.queue.dispose();

      final rework = await _rig([_gsb('b1', 1)], version: 1); // already submitted once
      expect(rework.c.needsInstallation(rework.c.boards[0]), isFalse);
      expect(rework.c.problems().where((p) => p.contains('choose the installation type') || p.contains('answer "')), isEmpty);
      rework.c.dispose();
      rework.queue.dispose();
    });

    test('what is missing, board by board: first the method, then each required question; dependent ones only when shown', () async {
      final r = await _rig([_gsb('b1', 1), _gsb('b2', 2)]);
      final b1 = r.c.boards[0];
      expect(r.c.installationProblems(b1), ['GSB-01: choose the installation type']);
      expect(r.c.boardInstallDone(b1), isFalse);

      r.c.setInstallation(b1, 'shop_fascia');
      expect(r.c.dirty, isTrue);
      expect(r.c.installationProblems(b1), hasLength(8));
      expect(r.c.installationProblems(b1).first, 'GSB-01: answer "Fascia material"');

      for (final e in _allAnswers.entries) {
        r.c.setAnswer(b1, e.key, e.value);
      }
      expect(r.c.installationProblems(b1), isEmpty);
      expect(r.c.boardInstallDone(b1), isTrue);
      expect(r.c.boardInstallDone(r.c.boards[1]), isFalse); // the other board is its own business

      r.c.setAnswer(b1, 'power_available', false); // now the distance is asked
      expect(r.c.installationProblems(b1), ['GSB-01: answer "Distance to nearest power point"']);
      r.c.setAnswer(b1, 'power_available', null); // clearing removes the answer
      expect(b1.answers.containsKey('power_available'), isFalse);
      r.c.dispose();
      r.queue.dispose();
    });

    test('with ONE board the lines carry no board name; the submit check lists every board\'s lines', () async {
      final one = await _rig([_gsb('b1', 1)]);
      expect(one.c.installationProblems(one.c.boards.first), ['choose the installation type']);
      one.c.dispose();
      one.queue.dispose();

      final two = await _rig([_gsb('b1', 1), _gsb('b2', 2)]);
      final lines = two.c.problems().where((p) => p.endsWith('choose the installation type')).toList();
      expect(lines, ['GSB-01: choose the installation type', 'GSB-02: choose the installation type']);
      two.c.dispose();
      two.queue.dispose();
    });

    test('a save tidies answers: one that belongs to another installation of this catalog goes, one this phone does not know stays', () async {
      final r = await _rig([_gsb('b1', 1, extra: {'installationType': 'shop_fascia', 'answers': {..._allAnswers, 'ground_type': 'Concrete', 'custom_server_question': 'kept'}})]);
      final b = r.c.boards.first;
      expect(b.answers.containsKey('ground_type'), isTrue);
      r.c.markDirty();
      expect(await r.c.saveDraft(), isNull);
      final sent = (r.api.sent!.first['answers'] as Map);
      expect(sent.containsKey('ground_type'), isFalse); // a double-pole question: not asked for a shop fascia
      expect(sent['custom_server_question'], 'kept'); // not in this catalog: never thrown away
      expect(sent['fascia_material'], 'Concrete');
      expect(r.api.sent!.first['installationType'], 'shop_fascia');
      expect(r.api.sent!.first['mediaCode'], 'GSB');
      r.c.dispose();
      r.queue.dispose();
    });
  });

  group('quantity per media type', () {
    test('"+" adds a board like the last one of its type: same size, installation and answers; its own number and no photos; saved at once', () async {
      final r = await _rig([_gsb('b1', 1, extra: {'width': 8, 'installationType': 'shop_fascia', 'answers': {'fascia_material': 'Brick'}})]);
      final err = await r.c.addBoardLike(r.c.boards.first);
      expect(err, isNull);
      expect(r.api.saves, 1);
      expect(r.c.boards.map((b) => b.label), ['GSB-01', 'GSB-02']);
      final b2 = r.c.boards[1];
      expect((b2.width, b2.installationType, b2.answers['fascia_material']), (8.0, 'shop_fascia', 'Brick'));
      b2.answers['fascia_material'] = 'Wooden'; // its own answers
      expect(r.c.boards[0].answers['fascia_material'], 'Brick');
      expect(r.c.boardHasPhotos(b2.key), isFalse);
      expect(r.c.photoBoard!.key, b2.key); // the new board's photos come next
      r.c.dispose();
      r.queue.dispose();
    });

    test('"-" removes the highest-numbered board of the type; it keeps one; it will not remove a board that has photos', () async {
      final r = await _rig([_gsb('b1', 1), _gsb('b2', 2), _gsb('b3', 3)], photos: [_photo('p1', 'SHOP_FRONT', 'b3')]);
      expect(r.c.boardsOfType('GSB').map((b) => b.label), ['GSB-01', 'GSB-02', 'GSB-03']);
      expect(r.c.removeLastOfType('GSB'), contains('GSB-03 has photos'));
      expect(r.c.boards, hasLength(3));

      final free = await _rig([_gsb('b1', 1), _gsb('b2', 2)]);
      expect(free.c.removeLastOfType('GSB'), isNull);
      expect(free.c.boards.map((b) => b.label), ['GSB-01']);
      expect(free.c.dirty, isTrue); // saved with the draft
      expect(free.c.removeLastOfType('GSB'), contains('keeps at least one board'));
      r.c.dispose();
      r.queue.dispose();
      free.c.dispose();
      free.queue.dispose();
    });

    test('another media type is counted on its own', () async {
      final r = await _rig([_gsb('b1', 1), _gsb('b2', 2), {..._gsb('b3', 1), 'name': 'Clear Acrylic', 'mediaType': 'Acrylic', 'mediaCode': 'ACRYLIC'}]);
      expect(r.c.boardsOfType('GSB'), hasLength(2));
      expect(r.c.boardsOfType('Acrylic'), hasLength(1));
      expect(r.c.removeLastOfType('Acrylic'), contains('keeps at least one'));
      r.c.dispose();
      r.queue.dispose();
    });
  });

  group('the Boards tab', () {
    Future<void> show(WidgetTester tester, ShopDetailController c, {ValueChanged<BoardItem>? onNext, ValueChanged<BoardItem>? onPhotos}) async {
      tester.view.physicalSize = const Size(1320, 21000); // tall: a card with its questions is long and the list builds only what is near the screen
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: ListenableBuilder(listenable: c, builder: (_, _) => BoardsTab(ctrl: c, onNextBoard: onNext, onOpenPhotos: onPhotos))),
      ));
    }

    testWidgets('boards of one media type sit under one header with the quantity; every card is folded to one line', (tester) async {
      final r = await _rig([_gsb('b1', 1), _gsb('b2', 2), {..._gsb('b3', 1), 'name': 'Clear Acrylic', 'mediaType': 'Acrylic', 'mediaCode': 'ACRYLIC'}]);
      await show(tester, r.c);
      expect(find.byKey(const Key('group-GSB')), findsOneWidget);
      expect(find.byKey(const Key('group-Acrylic')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('group-count-GSB'))).data, '2');
      expect(tester.widget<Text>(find.byKey(const Key('group-count-Acrylic'))).data, '1');
      for (final k in ['b1', 'b2', 'b3']) {
        expect(find.byKey(Key('bcard-$k')), findsOneWidget);
      }
      expect(find.byKey(const Key('btab-size-b1')), findsNothing); // no card is open: its tabs are not drawn
      expect(find.byKey(const Key('inst_b1_shop_fascia')), findsNothing);
      expect(tester.widget<IconButton>(find.byKey(const Key('group-minus-Acrylic'))).onPressed, isNull); // one board: "-" is off
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('a card opens to two tabs, Size & details and Installation (with its questions); opening another closes the first', (tester) async {
      final r = await _rig([_gsb('b1', 1), _gsb('b2', 2)]);
      await show(tester, r.c);
      await tester.tap(find.byKey(const Key('bcard-b1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('btab-size-b1')), findsOneWidget);
      expect(find.byKey(const Key('btab-install-b1')), findsOneWidget);
      // left to right: Size & details, then Installation
      expect(tester.getTopLeft(find.byKey(const Key('btab-size-b1'))).dx, lessThan(tester.getTopLeft(find.byKey(const Key('btab-install-b1'))).dx));
      // The card opens on the part still to do (the size is entered, the installation is not): one tab at a time.
      expect(find.byKey(const Key('board-media-type')), findsNothing);
      await tester.tap(find.byKey(const Key('btab-size-b1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('board-media-type')), findsOneWidget);
      expect(find.byKey(const Key('inst_b1_shop_fascia')), findsNothing);
      await tester.tap(find.byKey(const Key('btab-install-b1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('board-media-type')), findsNothing);
      expect(find.byKey(const Key('inst_b1_shop_fascia')), findsOneWidget);
      expect(find.byKey(const Key('inst_b1_rooftop')), findsOneWidget);
      expect(find.textContaining('Fascia material'), findsNothing); // the questions come with the method
      expect(find.text('Choose the installation method to get its questions.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('inst_b1_shop_fascia')));
      await tester.pumpAndSettle();
      expect(r.c.boards[0].installationType, 'shop_fascia');
      expect(r.c.dirty, isTrue);
      expect(find.textContaining('Fascia material'), findsOneWidget);
      expect(find.textContaining('Shutter top height'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bcard-b2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inst_b1_shop_fascia')), findsNothing); // b1 folded
      expect(find.byKey(const Key('inst_b2_shop_fascia')), findsOneWidget);
      expect(find.byKey(const Key('inst_b2_rooftop')), findsOneWidget);
      expect(find.textContaining('Fascia material'), findsNothing); // b2 has no method yet: its own questions are not asked
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('the site questions fold: open while something is unanswered; a tap folds them and opens them again, the count stays in the header', (tester) async {
      final r = await _rig([_gsb('b1', 1, extra: {'installationType': 'shop_fascia'})]);
      await show(tester, r.c); // one board: its card is open, on the Installation tab (the part still to do)
      expect(tester.widget<Text>(find.byKey(const Key('answers-count'))).data, startsWith('0/'));
      expect(find.textContaining('Fascia material'), findsOneWidget);
      await tester.tap(find.byKey(const Key('answers-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Fascia material'), findsNothing);
      expect(find.byKey(const Key('answers-count')), findsOneWidget);
      await tester.tap(find.byKey(const Key('answers-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Fascia material'), findsOneWidget);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('a board whose questions are all answered shows them folded, with "n/n answered" in the header', (tester) async {
      final r = await _rig([_gsb('b1', 1, extra: {'installationType': 'shop_fascia', 'answers': _allAnswers})]);
      await show(tester, r.c);
      await tester.tap(find.byKey(const Key('btab-install-b1')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('answers-count'))).data, matches(RegExp(r'^(\d+)/\1 answered$')));
      expect(find.textContaining('Fascia material'), findsNothing); // everything is answered: folded
      await tester.tap(find.byKey(const Key('answers-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Fascia material'), findsOneWidget);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('the Size and Installation chips of a folded card open it on that tab', (tester) async {
      final r = await _rig([_gsb('b1', 1), _gsb('b2', 2)]);
      await show(tester, r.c);
      await tester.tap(find.byKey(const Key('chip-install-b2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('inst_b2_shop_fascia')), findsOneWidget);
      await tester.tap(find.byKey(const Key('chip-size-b1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('board-media-type')), findsOneWidget); // b1 opened on Size, b2 folded
      expect(find.byKey(const Key('inst_b2_shop_fascia')), findsNothing);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('each board has its own method: the choice on one board never changes another', (tester) async {
      final r = await _rig([_gsb('b1', 1), _gsb('b2', 2)]);
      await show(tester, r.c);
      await tester.tap(find.byKey(const Key('bcard-b1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inst_b1_rooftop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bcard-b2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inst_b2_wall_mount')));
      await tester.pumpAndSettle();
      expect(r.c.boards.map((b) => b.installationType), ['rooftop', 'wall_mount']);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('the status chips say what each board still needs; Next opens only when size and installation are complete', (tester) async {
      final r = await _rig([_gsb('b1', 1, extra: {'installationType': 'shop_fascia'})]);
      var next = 0;
      await show(tester, r.c, onNext: (_) => next++);
      // a shop with one board shows it open
      expect(find.byKey(const Key('chip-size-b1')), findsOneWidget);
      expect(find.byKey(const Key('chip-install-b1')), findsOneWidget);
      expect(find.byKey(const Key('chip-photos-b1')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('bnext-b1'))).onPressed, isNull); // eight questions open
      expect(find.text('Photos 0/7'), findsWidgets);

      for (final e in _allAnswers.entries) {
        r.c.setAnswer(r.c.boards.first, e.key, e.value);
      }
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const Key('bnext-b1'))).onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('bnext-b1')));
      expect(next, 1);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('the Photos chip and button open the photos of that board', (tester) async {
      final r = await _rig([_gsb('b1', 1)]);
      final opened = <String>[];
      await show(tester, r.c, onPhotos: (b) => opened.add(b.key));
      await tester.tap(find.byKey(const Key('chip-photos-b1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('bphotos-b1')));
      await tester.pump();
      expect(opened, ['b1', 'b1']);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('+ adds a board like the last one and says so; - asks first and removes the last of the type', (tester) async {
      final r = await _rig([_gsb('b1', 1), _gsb('b2', 2)]);
      await show(tester, r.c);
      await tester.tap(find.byKey(const Key('group-plus-GSB')));
      await tester.pumpAndSettle();
      expect(r.api.saves, 1);
      expect(r.c.boards.map((b) => b.label), ['GSB-01', 'GSB-02', 'GSB-03']);
      expect(tester.widget<Text>(find.byKey(const Key('group-count-GSB'))).data, '3');
      expect(find.byKey(const Key('bcard-b3')), findsOneWidget);

      await tester.tap(find.byKey(const Key('group-minus-GSB')));
      await tester.pumpAndSettle();
      expect(find.text('Remove GSB-03?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(r.c.boards.map((b) => b.label), ['GSB-01', 'GSB-02']);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('the bin on a media type header removes the whole type after one confirmation; the other type stays', (tester) async {
      final r = await _rig([_gsb('b1', 1), _gsb('b2', 2), {..._gsb('b3', 1), 'name': 'Clear Acrylic', 'mediaType': 'Acrylic', 'mediaCode': 'ACRYLIC'}]);
      await show(tester, r.c);
      await tester.tap(find.byKey(const Key('group-remove-Acrylic'))); // a one-board type too: "-" is off there, the bin is not
      await tester.pumpAndSettle();
      expect(find.text('Remove Clear Acrylic?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(r.c.boards, hasLength(3)); // cancelled: nothing changed

      await tester.tap(find.byKey(const Key('group-remove-GSB')));
      await tester.pumpAndSettle();
      expect(find.textContaining('all 2 boards'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(r.c.boards.map((b) => b.label), ['Acrylic-01']);
      expect(find.byKey(const Key('group-GSB')), findsNothing);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('a locked shop can be read: the method tiles do nothing and there is no Next or bin', (tester) async {
      final r = await _rig([_gsb('b1', 1, extra: {'installationType': 'shop_fascia'})]);
      r.c.detail = ShopDetail.fromJson({..._detail([_gsb('b1', 1)]), 'editable': false});
      await show(tester, r.c);
      expect(find.byKey(const Key('inst_b1_rooftop')), findsOneWidget);
      await tester.tap(find.byKey(const Key('inst_b1_rooftop')));
      await tester.pump();
      expect(r.c.boards.first.installationType, 'shop_fascia'); // unchanged
      expect(find.byKey(const Key('bnext-b1')), findsNothing);
      expect(find.byKey(const Key('bremove-b1')), findsNothing);
      expect(find.byKey(const Key('group-plus-GSB')), findsNothing);
      r.c.dispose();
      r.queue.dispose();
    });
  });
}
