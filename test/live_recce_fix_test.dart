import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signage_recce/core/network/api_exception.dart';
import 'package:signage_recce/features/live_recce/data/recce_api.dart';
import 'package:signage_recce/features/live_recce/data/recce_controllers.dart';
import 'package:signage_recce/features/live_recce/data/recce_models.dart';
import 'package:signage_recce/features/live_recce/data/submit_validator.dart';
import 'package:signage_recce/features/live_recce/data/upload_queue.dart';

/// Fixes of the confirmed review findings (required photos from the server, cleared height, empty boards, stale list load,
/// measurement rework without a board, readable change values, retake order). Fake data and fake API only.

Map<String, dynamic> _photo(String id, String category, {String state = 'DRAFT', String mediaKey = '', String? replaces}) => {
      'id': id,
      'category': category,
      'state': state,
      'mediaKey': mediaKey,
      'lat': 13.04,
      'lng': 80.23,
      'gpsAccuracy': 8.0,
      'gpsVerified': true,
      'url': 'http://host/$id.jpg',
      'replaces': replaces,
    };

Map<String, dynamic> _detail({
  List<Map<String, dynamic>> photos = const [],
  List<Map<String, dynamic>> missing = const [],
  List<Map<String, dynamic>> reworks = const [],
  List<String> required = const ['SHOP_FRONT', 'NAME_BOARD'],
  String status = 'IN_PROGRESS',
}) =>
    {
      'siteId': 's1',
      'siteCode': 'SM-1',
      'project': {'id': 'p1', 'code': 'ADN-1', 'name': 'South', 'closed': false},
      'status': status,
      'editable': true,
      'version': 0,
      'mediaItems': [
        {'key': 'b1', 'name': 'GSB', 'quantity': 1, 'width': 6, 'height': 4, 'unit': 'FT', 'required': required},
      ],
      'categories': [
        {'key': 'SHOP_FRONT', 'label': 'Full Shop Front View'},
        {'key': 'NAME_BOARD', 'label': 'Shop Name Board'},
        {'key': 'MEASUREMENT', 'label': 'Measurement View'},
      ],
      'photos': photos,
      'progress': {'percent': 10, 'required': 2, 'done': 1, 'missing': missing},
      'reworks': reworks,
    };

Map<String, dynamic> _missing(String category, {String label = '', String mediaKey = 'b1'}) =>
    {'mediaKey': mediaKey, 'mediaName': 'GSB', 'category': category, 'label': label};

Map<String, dynamic> _rework(List<Map<String, dynamic>> items, {String status = 'OPEN'}) => {
      'id': 'rw1',
      'versionNo': 1,
      'stage': 'OPS',
      'stageLabel': 'Recce Operations',
      'kind': 'REWORK',
      'status': status,
      'instructions': 'Please fix',
      'requestedBy': 'Asha',
      'requestedAt': '2026-11-22T08:00:00.000Z',
      'items': items,
    };

List<ShopPhoto> _six({String state = 'SUBMITTED'}) => [for (final c in requiredPhotoCategories) ShopPhoto.fromJson(_photo('ph-${c.key}', c.key, state: state))];

Installation _answered() => Installation(ladderRequired: triYes, scaffoldingRequired: triNo, craneRequired: triNo, hydraRequired: triNo, manualInstallationPossible: triYes);

/// RecceApi with no network: every call the tests need is answered by a closure.
class _FakeApi extends RecceApi {
  _FakeApi() : super(Dio());

  Future<ShopListPage> Function()? onShops;
  Future<ShopDetail> Function()? onDetail;
  int saveCalls = 0;
  final deleted = <String>[];

  @override
  Future<ShopListPage> shops() => onShops!();

  @override
  Future<ShopDetail> detail(String siteId) => onDetail!();

  @override
  Future<ShopDetail> saveDraft(String siteId, {List<BoardItem>? mediaItems, Installation? installation, String? notes}) async {
    saveCalls++;
    return onDetail!();
  }

  @override
  Future<void> deletePhoto(String siteId, String photoId, {String? reason}) async => deleted.add(photoId);

  @override
  Future<void> uploadPhoto(UploadItem u, {required void Function(double) onProgress, CancelToken? cancel}) async {
    throw const ApiException(code: 'NETWORK_ERROR', message: 'offline');
  }

  @override
  Future<List<RecceVersion>> versions(String siteId) async => const [];
}

ShopSummary _row(String id) => ShopSummary.fromJson({'siteId': id, 'projectId': 'p', 'projectCode': 'C', 'projectName': 'N', 'siteCode': 'S$id', 'status': 'NOT_STARTED'});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('1. required photos come from the server on top of the six', () {
    test('a category in progress.missing that is not one of the six gets an extra tile with the server label', () {
      final d = ShopDetail.fromJson(_detail(missing: [_missing('NAME_BOARD', label: 'Shop Name Board'), _missing('SHOP_FRONT'), _missing('DIMENSIONS')]));
      expect(d.extraPhotoSlots.map((s) => s.category), ['NAME_BOARD']);
      expect(d.extraPhotoSlots.single.label, 'Shop Name Board');
    });

    test('the tile stays after the photo is taken (the board still lists the category as required)', () {
      final d = ShopDetail.fromJson(_detail(photos: [_photo('n1', 'NAME_BOARD')], required: ['SHOP_FRONT', 'NAME_BOARD', 'MEASUREMENT']));
      expect(d.extraPhotoSlots.map((s) => s.category), ['NAME_BOARD', 'MEASUREMENT']);
      expect(d.extraPhotoSlots.last.label, 'Measurement View');
      expect(d.photoFor('NAME_BOARD'), isNotNull);
    });

    test('a shop that needs nothing beyond the six shows no extra tile', () {
      expect(ShopDetail.fromJson(_detail(required: ['SHOP_FRONT'])).extraPhotoSlots, isEmpty);
    });

    test('validator requires the six PLUS what the server reports missing, and nothing else', () {
      final missing = [MissingEvidence.fromJson(_missing('NAME_BOARD', label: 'Shop Name Board')), MissingEvidence.fromJson(_missing('DIMENSIONS'))];
      final boards = [BoardItem(key: 'b1', width: 6, height: 4)];
      expect(validateForSubmit(photos: _six(), boards: boards, installation: _answered(), serverMissing: missing), ['Shop Name Board photo is missing']);
      expect(validateForSubmit(photos: _six(), boards: boards, installation: _answered()), isEmpty); // server needs nothing more
      final withNameBoard = [..._six(), ShopPhoto.fromJson(_photo('n1', 'NAME_BOARD'))];
      expect(validateForSubmit(photos: withNameBoard, boards: boards, installation: _answered(), serverMissing: missing), isEmpty);
    });

    test('a server-missing entry of one of the six is not repeated', () {
      final missing = [MissingEvidence.fromJson(_missing('SHOP_FRONT'))];
      final photos = _six().where((p) => p.category != 'SHOP_FRONT').toList();
      final p = validateForSubmit(photos: photos, boards: [BoardItem(key: 'b1', width: 6, height: 4)], installation: _answered(), serverMissing: missing);
      expect(p, ['Front View photo is missing']);
    });

    test('ADDITIONAL_PHOTO shows an "additional photo" request with the reviewer note, answered by a new draft of that category', () {
      final rw = _rework([
        {'id': 'i1', 'type': 'ADDITIONAL_PHOTO', 'category': 'NAME_BOARD', 'categoryLabel': 'Shop Name Board', 'mediaKey': '', 'note': 'Show the sign', 'resolved': false},
      ]);
      final d = ShopDetail.fromJson(_detail(reworks: [rw], photos: [_photo('ph1', 'SHOP_FRONT', state: 'SUBMITTED')]));
      final req = d.requestedPhotos.single;
      expect(req.label, 'Shop Name Board');
      expect(req.note.note, 'Show the sign');
      expect(req.note.by, 'Asha');
      expect(req.answer(d.photos), isNull);
      final entries = d.reworks;
      expect(unansweredRework(entries, d.photos), ['Add the Shop Name Board photo the reviewer asked for']);
      final answered = [...d.photos, ShopPhoto.fromJson(_photo('n1', 'NAME_BOARD'))];
      expect(unansweredRework(entries, answered), isEmpty);
      expect(req.answer(answered)!.id, 'n1');
    });

    test('REPLACE_PHOTO with a category but no photo id is answered by a new draft of the category; with a photo id it is not a request card', () {
      final rw = _rework([
        {'id': 'i1', 'type': 'REPLACE_PHOTO', 'category': 'SIDE_VIEW', 'categoryLabel': 'Side View', 'photo': null, 'note': 'Blurry', 'resolved': false},
        {'id': 'i2', 'type': 'REPLACE_PHOTO', 'category': 'SHOP_FRONT', 'photo': 'ph-SHOP_FRONT', 'resolved': false},
      ]);
      final d = ShopDetail.fromJson(_detail(reworks: [rw]));
      expect(d.requestedPhotos.map((r) => r.category), ['SIDE_VIEW']);
      final entries = d.reworks;
      expect(unansweredRework(entries, [ShopPhoto.fromJson(_photo('a', 'SHOP_FRONT', replaces: 'ph-SHOP_FRONT'))]), ['Add the Side View photo the reviewer asked for']);
      expect(unansweredRework(entries, [ShopPhoto.fromJson(_photo('a', 'SHOP_FRONT', replaces: 'ph-SHOP_FRONT')), ShopPhoto.fromJson(_photo('b', 'SIDE_VIEW'))]), isEmpty);
    });

    test('an item tied to a board needs a photo of that board', () {
      final rw = _rework([
        {'id': 'i1', 'type': 'ADDITIONAL_PHOTO', 'category': 'NAME_BOARD', 'mediaKey': 'b1', 'resolved': false},
      ]);
      final entries = ShopDetail.fromJson(_detail(reworks: [rw])).reworks;
      expect(unansweredRework(entries, [ShopPhoto.fromJson(_photo('x', 'NAME_BOARD', mediaKey: 'b2'))]), isNotEmpty);
      expect(unansweredRework(entries, [ShopPhoto.fromJson(_photo('x', 'NAME_BOARD', mediaKey: 'b1'))]), isEmpty);
    });
  });

  group('2. installation height can be cleared and is capped at 500', () {
    test('a cleared height is an explicit null in the draft body; toJson still omits it', () {
      final i = _answered()..installationHeightFt = 12;
      expect(i.toDraftJson()['installationHeightFt'], 12.0);
      i.installationHeightFt = null;
      final j = i.toDraftJson();
      expect(j.containsKey('installationHeightFt'), isTrue);
      expect(j['installationHeightFt'], isNull);
      expect(i.toJson().containsKey('installationHeightFt'), isFalse);
    });

    test('above 500 ft is a problem for save and submit; 500 is fine', () {
      expect(Installation(installationHeightFt: 500).heightProblem, isNull);
      expect(Installation(installationHeightFt: 500.5).heightProblem, contains('500'));
      final p = validateForSubmit(photos: _six(), boards: [BoardItem(key: 'b1', width: 6, height: 4)], installation: _answered()..installationHeightFt = 900);
      expect(p, hasLength(1));
      expect(p.single, contains('500'));
    });
  });

  group('3. no boards: nothing is sent and the message is clear', () {
    test('RecceApi refuses an empty board list instead of dropping it from the body', () async {
      expect(() => RecceApi(Dio()).saveDraft('s1', mediaItems: const []), throwsA(isA<RecceInputException>()));
    });

    test('saveDraft with zero boards returns the message and never calls the server', () async {
      final api = _FakeApi()..onDetail = () async => ShopDetail.fromJson(_detail());
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      c.removeBoard(c.boards.single);
      expect(await c.saveDraft(), noBoardsSaveMessage);
      expect(api.saveCalls, 0);
      c.addBoard();
      c.boards.single
        ..width = 6
        ..height = 4;
      expect(await c.saveDraft(), isNull);
      expect(api.saveCalls, 1);
      c.dispose();
      queue.dispose();
    });
  });

  group('4 and 6. notes and dispose', () {
    test('typing only reviewer notes makes the screen dirty and tells listeners once', () async {
      final api = _FakeApi()..onDetail = () async => ShopDetail.fromJson(_detail());
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      var calls = 0;
      c.addListener(() => calls++);
      c.setNotes('a');
      c.setNotes('ab');
      expect(c.dirty, isTrue);
      expect(calls, 1);
      c.dispose();
      queue.dispose();
    });

    test('an answer that arrives after dispose does not notify or throw', () async {
      final api = _FakeApi();
      final gate = Completer<ShopDetail>();
      api.onDetail = () => gate.future;
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      final loading = c.load();
      c.dispose();
      gate.complete(ShopDetail.fromJson(_detail()));
      await loading; // would throw "used after being disposed" without the guard
      expect(c.detail, isNull);
      queue.dispose();
    });
  });

  group('7. reset drops a load that is still running', () {
    test('the previous login\'s shops do not come back after reset()', () async {
      final api = _FakeApi();
      final first = Completer<ShopListPage>();
      api.onShops = () => first.future;
      final queue = UploadQueue(api, autoRetry: false);
      final list = ShopListController(api, queue);
      final running = list.load();
      expect(list.loading, isTrue);
      list.reset();
      expect(list.loading, isFalse);
      first.complete(ShopListPage(items: [_row('old')], total: 1, summary: const {'NOT_STARTED': 1}));
      await running;
      expect(list.shops, isEmpty);
      expect(list.loaded, isFalse);

      // the new login loads normally, and the stale answer cannot clobber the loading flag of the new load
      api.onShops = () async => ShopListPage(items: [_row('new')], total: 1, summary: const {'NOT_STARTED': 1});
      await list.load();
      expect(list.shops.single.siteId, 'new');
      expect(list.loaded, isTrue);
      list.dispose();
      queue.dispose();
    });
  });

  group('8. measurement rework without a board', () {
    test('FIX_MEASUREMENT without mediaKey (or for a board that is gone) is a general banner item, a named board keeps its card', () {
      final rw = _rework([
        {'id': 'i1', 'type': 'FIX_MEASUREMENT', 'mediaKey': '', 'note': 'Re-measure everything', 'resolved': false},
        {'id': 'i2', 'type': 'FIX_MEASUREMENT', 'mediaKey': 'b1', 'note': 'Width is 8 ft', 'resolved': false},
        {'id': 'i3', 'type': 'FIX_MEASUREMENT', 'mediaKey': 'b9', 'note': 'Old board', 'resolved': false},
        {'id': 'i4', 'type': 'FIX_MEASUREMENT', 'mediaKey': '', 'note': 'done already', 'resolved': true},
      ]);
      final d = ShopDetail.fromJson(_detail(reworks: [rw]));
      final general = d.measurementReworksWithoutBoard(['b1']);
      expect(general.map((g) => g.note.note), ['Re-measure everything', 'Old board']);
      expect(general.map((g) => g.forBoard), ['', 'b9']);
      expect(general.first.note.by, 'Asha');
      expect(d.measurementReworkFor('b1')!.note, 'Width is 8 ft');
      expect(d.measurementReworkFor(''), isNull);
    });

    test('a closed rework request produces no banner', () {
      final rw = _rework([
        {'id': 'i1', 'type': 'FIX_MEASUREMENT', 'mediaKey': '', 'note': 'x', 'resolved': false},
      ], status: 'RESOLVED');
      expect(ShopDetail.fromJson(_detail(reworks: [rw])).measurementReworksWithoutBoard(['b1']), isEmpty);
    });
  });

  group('11. change values read as words', () {
    test('a board object reads "GSB 6 x 4 ft"; lists of boards join', () {
      expect(fieldValueText({'key': 'b1', 'name': 'GSB', 'width': 6, 'height': 4, 'unit': 'FT', 'quantity': 1}), 'GSB 6 x 4 ft');
      expect(
        fieldValueText([
          {'name': 'GSB', 'width': 6, 'height': 4, 'unit': 'FT', 'quantity': 2, '_id': 'x'},
          {'name': 'ACP', 'width': 4.5, 'height': 3, 'unit': 'FT', 'quantity': 1},
        ]),
        'GSB 6 x 4 ft x2, ACP 4.5 x 3 ft',
      );
    });

    test('another object becomes compact label: value lines, never a raw map dump', () {
      final t = fieldValueText({
        'mediaItems': [
          {'name': 'GSB', 'width': 6, 'height': 4, 'unit': 'FT', 'quantity': 1},
        ],
        'notes': 'Open at 9',
      });
      expect(t, 'Boards: GSB 6 x 4 ft\nNotes: Open at 9');
      expect(t, isNot(contains('{')));
      expect(fieldValueText(<String, dynamic>{}), 'not set');
    });

    test('FieldChange.text keeps one line for simple values and uses Before / After blocks for objects', () {
      expect(const FieldChange(field: 'installation.craneRequired', from: 'NO', to: 'YES').text, 'Crane: No -> Yes');
      final t = FieldChange(
        field: 'draft',
        from: {
          'mediaItems': [
            {'name': 'GSB', 'width': 6, 'height': 4, 'unit': 'FT', 'quantity': 1},
          ],
          'notes': '',
        },
        to: {
          'mediaItems': [
            {'name': 'GSB', 'width': 8, 'height': 4, 'unit': 'FT', 'quantity': 1},
          ],
          'notes': 'x',
        },
      ).text;
      expect(t, contains('Draft'));
      expect(t, contains('Before: Boards: GSB 6 x 4 ft'));
      expect(t, contains('After: Boards: GSB 8 x 4 ft'));
      expect(t, isNot(contains('{')));
    });
  });

  group('13. testing switch: the first photo is used for all types', () {
    ShopDetail detailWith(List<Map<String, dynamic>> photos, {bool editable = true}) => ShopDetail.fromJson({..._detail(photos: photos), 'editable': editable});

    UploadItem first() => UploadItem(
          id: 'c-first-0001',
          siteId: 's1',
          path: '/shots/first.jpg',
          category: 'SIDE_VIEW',
          capturedAt: DateTime.utc(2026, 11, 23, 9),
          lat: 13.04,
          lng: 80.23,
          accuracy: 7,
          width: 1600,
          height: 1200,
          device: 'web / test',
        );

    test('queues one copy, with its own file and the same capture details, for every type that is still empty', () async {
      final api = _FakeApi()..onDetail = () async => detailWith([_photo('ph-front', 'SHOP_FRONT')]);
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      queue.add(UploadItem(id: 'c-wait-0001', siteId: 's1', path: '/shots/wait.jpg', category: 'LONG_SHOT')); // already waiting
      final f = first();
      queue.add(f);
      var n = 0;
      final copied = await c.queueFirstPhotoForAll(f, requiredPhotoCategories, (path) async => '$path.copy${++n}');
      await Future<void>.delayed(Duration.zero);

      // SHOP_FRONT has a stored photo, SIDE_VIEW is the one taken, LONG_SHOT already waits: three types remain.
      expect(copied, 3);
      final made = queue.forShop('s1').where((u) => u.id != 'c-wait-0001' && u.id != f.id).toList();
      expect(made.map((u) => u.category).toSet(), {'ANNOTATED_VIEW', 'LOCATION_VIEW', 'ACCESS_PATH'});
      expect(made.map((u) => u.path).toSet(), hasLength(3)); // a file each: the queue deletes a file once it is uploaded
      expect(made.every((u) => u.path.startsWith('/shots/first.jpg.copy')), isTrue);
      expect(made.map((u) => u.id).toSet(), hasLength(3)); // a client id each, so the server stores each one
      expect(made.every((u) => u.lat == 13.04 && u.lng == 80.23 && u.accuracy == 7 && u.width == 1600 && u.capturedAt == f.capturedAt && u.device == 'web / test'), isTrue);
      c.dispose();
      queue.dispose();
    });

    test('nothing is queued for a locked shop', () async {
      final api = _FakeApi()..onDetail = () async => detailWith(const [], editable: false);
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      expect(await c.queueFirstPhotoForAll(first(), requiredPhotoCategories, (p) async => '$p.copy'), 0);
      expect(queue.forShop('s1'), isEmpty);
      c.dispose();
      queue.dispose();
    });

    test('the switch is off at the start and tells listeners only when it changes', () async {
      final api = _FakeApi()..onDetail = () async => detailWith(const []);
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      expect(c.useFirstPhotoForAll, isFalse);
      var calls = 0;
      c.addListener(() => calls++);
      c.setUseFirstPhotoForAll(true);
      c.setUseFirstPhotoForAll(true);
      expect(c.useFirstPhotoForAll, isTrue);
      expect(calls, 1);
      c.dispose();
      queue.dispose();
    });
  });

  group('12. retake queues the new photo first', () {
    ShopDetail detailWith(List<Map<String, dynamic>> photos) => ShopDetail.fromJson(_detail(photos: photos));

    test('the old draft is deleted only after the new photo is on the server', () async {
      final api = _FakeApi();
      var photos = [_photo('old', 'SIDE_VIEW')];
      api.onDetail = () async => detailWith(photos);
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      final old = c.detail!.photos.single;
      c.queueSwap(UploadItem(id: 'c-new-0001', siteId: 's1', path: '/x.jpg', category: 'SIDE_VIEW'), stale: old);
      await Future<void>.delayed(Duration.zero);
      expect(queue.forShop('s1'), hasLength(1)); // the new photo is queued, the old draft is untouched
      expect(api.deleted, isEmpty);
      await c.refresh(); // still uploading: the old draft stays
      expect(api.deleted, isEmpty);
      // the upload finishes: the server now holds both drafts, the queue no longer has the item
      photos = [_photo('old', 'SIDE_VIEW'), _photo('new', 'SIDE_VIEW')];
      queue.cancel('c-new-0001'); // leaves the queue like a finished upload does
      await c.refresh();
      expect(api.deleted, ['old']);
      c.dispose();
      queue.dispose();
    });

    test('a cancelled new photo keeps the old draft', () async {
      final api = _FakeApi();
      api.onDetail = () async => detailWith([_photo('old', 'SIDE_VIEW')]);
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      c.queueSwap(UploadItem(id: 'c-new-0002', siteId: 's1', path: '/x.jpg', category: 'SIDE_VIEW'), stale: c.detail!.photos.single);
      queue.cancel('c-new-0002');
      await c.refresh();
      expect(api.deleted, isEmpty);
      c.dispose();
      queue.dispose();
    });
  });
}
