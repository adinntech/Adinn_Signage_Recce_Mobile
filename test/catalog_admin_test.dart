import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signage_recce/app.dart';
import 'package:signage_recce/core/network/api_exception.dart';
import 'package:signage_recce/core/network/token_manager.dart';
import 'package:signage_recce/core/storage/session_store.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/catalog_admin/admin_home_shell.dart';
import 'package:signage_recce/features/catalog_admin/catalog_admin_controller.dart';
import 'package:signage_recce/features/catalog_admin/catalog_admin_screen.dart';
import 'package:signage_recce/features/catalog_admin/installation_form_screen.dart';
import 'package:signage_recce/features/catalog_admin/media_form_screen.dart';
import 'package:signage_recce/features/catalog_admin/question_form_screen.dart';
import 'package:signage_recce/features/live_auth/data/auth_repository.dart';
import 'package:signage_recce/features/live_auth/domain/auth_models.dart';
import 'package:signage_recce/features/live_auth/presentation/live_auth_controller.dart';
import 'package:signage_recce/features/live_auth/presentation/live_login_screen.dart';
import 'package:signage_recce/features/live_recce/data/catalog_controller.dart';
import 'package:signage_recce/features/live_recce/data/catalog_data.dart';
import 'package:signage_recce/features/live_recce/data/live_services.dart';
import 'package:signage_recce/features/live_recce/data/recce_api.dart';
import 'package:signage_recce/features/live_recce/data/recce_controllers.dart';
import 'package:signage_recce/features/live_recce/data/upload_queue.dart';
import 'package:signage_recce/state/app_controller.dart';

/// The administrator's Media catalog on the phone (C4): the edit payloads, the controller, the three forms, the list screen with its
/// delete / inactive / reorder rules, and the admin sign in that leads to it. A fake API holds the catalog in memory: no network.

Map<String, dynamic> _media(String code, {String? shortName, String name = 'Board', List<String> installs = const ['wall'], bool active = true, bool legacy = false, int order = 0}) => {
      'code': code,
      'shortName': shortName ?? code,
      'name': name,
      'description': 'About $code',
      'icon': 'lightbulb_outline',
      'color': '#D71920',
      'illuminated': true,
      'sidedness': 'SELECTABLE',
      'depthFt': 0.75,
      'thicknessMm': 0,
      'template': 'gsb',
      'installations': installs,
      'legacy': legacy,
      'active': active,
      'order': order,
    };

Map<String, dynamic> _inst(String code, {String name = 'Wall mount', int order = 0, bool active = true}) =>
    {'code': code, 'name': name, 'description': 'On the wall', 'icon': 'wallpaper', 'active': active, 'order': order};

Map<String, dynamic> _q(String uid, String id, {String scope = 'COMMON', String scopeCode = '', String type = 'YES_NO', String? label, List<String> options = const [], int order = 0, bool required = true, String? showIfId, Object? showIfValue}) => {
      'uid': uid,
      'scope': scope,
      'scopeCode': scopeCode,
      'id': id,
      'label': label ?? 'Question $id',
      'type': type,
      'options': options,
      'unit': null,
      'required': required,
      'hint': null,
      'showIfId': showIfId,
      'showIfValue': showIfValue,
      'active': true,
      'order': order,
    };

/// Keeps the catalog in memory, answers like the server (a used entry is a conflict) and records every write.
class _FakeApi extends RecceApi {
  _FakeApi() : super(Dio());

  int version = 5;
  List<Map<String, dynamic>> media = [_media('GSB', shortName: 'GSB', name: 'Glow Sign Board'), _media('ACP', name: 'ACP Board', order: 1), _media('OLD', name: 'Older board', legacy: true, order: 1000)];
  List<Map<String, dynamic>> installations = [_inst('wall'), _inst('pole', name: 'Single pole', order: 1)];
  List<Map<String, dynamic>> questions = [_q('q1', 'existing_board', order: 0), _q('q2', 'fascia', scope: 'MEDIA', scopeCode: 'GSB', type: 'CHOICE', options: ['ACP', 'Wood'], order: 0), _q('q3', 'led_count', scope: 'MEDIA', scopeCode: 'GSB', type: 'NUMBER', order: 1)];
  Map<String, int> usedMedia = {'GSB': 2};
  Map<String, int> usedInstallations = {};

  final calls = <String>[];
  Map<String, dynamic>? lastBody;
  List<String>? lastOrder;
  String? failWith;
  bool failLoad = false;
  int loads = 0;

  Map<String, dynamic> get _json => {'version': version, 'media': media, 'installations': installations, 'questions': questions};

  void _check() {
    if (failWith != null) throw ApiException(code: 'CONFLICT', message: failWith!, statusCode: 409);
  }

  @override
  Future<CatalogData> catalogFull() async {
    loads++;
    if (failLoad) throw const ApiException(code: 'NETWORK_ERROR', message: 'Cannot reach the server. Check your connection.');
    return CatalogData.fromJson(_json);
  }

  @override
  Future<CatalogData?> catalog({int? version}) async => version == this.version ? null : CatalogData.fromJson(_json);

  @override
  Future<CatalogUsage> catalogUsage() async => CatalogUsage(media: usedMedia, installations: usedInstallations);

  @override
  Future<void> catalogCreate(String kind, Map<String, dynamic> body) async {
    calls.add('create $kind');
    lastBody = body;
    _check();
    version++;
    (kind == 'media' ? media : kind == 'installations' ? installations : questions).add({...body, if (kind == 'questions') 'uid': 'n${questions.length}'});
  }

  @override
  Future<void> catalogUpdate(String kind, String id, Map<String, dynamic> body) async {
    calls.add('update $kind $id');
    lastBody = body;
    _check();
    version++;
    final list = kind == 'media' ? media : kind == 'installations' ? installations : questions;
    final at = list.indexWhere((e) => (kind == 'questions' ? e['uid'] : e['code']) == id);
    list[at] = {...list[at], ...body};
  }

  @override
  Future<void> catalogDelete(String kind, String id) async {
    calls.add('delete $kind $id');
    _check();
    version++;
    (kind == 'media' ? media : kind == 'installations' ? installations : questions).removeWhere((e) => (kind == 'questions' ? e['uid'] : e['code']) == id);
  }

  @override
  Future<void> catalogReorder(String kind, List<String> ids) async {
    calls.add('reorder $kind');
    lastOrder = ids;
    _check();
    version++;
  }

  @override
  Future<Map<String, int>> catalogLoadDefaults() async {
    calls.add('defaults');
    _check();
    return {'media': 0, 'installations': 1, 'questions': 2};
  }
}

class _SpyShared extends CatalogController {
  _SpyShared(super.api);
  int refreshes = 0;

  @override
  Future<bool> refresh() async {
    refreshes++;
    return true;
  }
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
  _FakeAuthRepo(this.signedIn) : super(plainDio: Dio(), tokens: TokenManager(refreshDio: Dio(), store: _MemoryStore()), store: _MemoryStore());

  final LiveUser signedIn;
  String? loginRole;

  @override
  Future<LiveUser> login(String identifier, AuthCredential credential, {String? loginRole}) async {
    this.loginRole = loginRole;
    return signedIn;
  }

  @override
  Future<void> logout() async {}
}

/// A tall phone-shaped surface (the test font is much wider than the real one, so the width is generous and the height holds a whole list).
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<({_FakeApi api, CatalogAdminController ctrl, _SpyShared shared})> _rig() async {
  final api = _FakeApi();
  final shared = _SpyShared(api);
  final ctrl = CatalogAdminController(api, shared: shared);
  await ctrl.load();
  return (api: api, ctrl: ctrl, shared: shared);
}

Widget _host(Widget child, CatalogAdminController ctrl) => ChangeNotifierProvider<CatalogAdminController>.value(value: ctrl, child: MaterialApp(home: child));

/// Opens [page] from a button so that Navigator.pop(result) has somewhere to go; returns what the page came back with.
Future<void> _openForm(WidgetTester tester, CatalogAdminController ctrl, Widget page, {required List<bool?> results}) async {
  _phone(tester);
  await tester.pumpWidget(_host(
    Builder(builder: (context) => Scaffold(body: Center(child: FilledButton(key: const Key('open'), onPressed: () async => results.add(await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => page))), child: const Text('open'))))),
    ctrl,
  ));
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('form-save')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('edit payloads', () {
    test('an edit carries only the fields that changed; a cleared optional value goes as null', () {
      final before = {'label': 'A', 'options': <String>['x', 'y'], 'unit': 'ft', 'required': true, 'hint': null, 'showIfId': 'q', 'showIfValue': true, 'active': true, 'scope': 'MEDIA'};
      final after = {...before, 'label': 'B', 'unit': null, 'showIfId': null, 'showIfValue': null, 'scope': 'COMMON'};
      expect(changedFields(before, after, questionEditable), {'label': 'B', 'unit': null, 'showIfId': null, 'showIfValue': null}); // scope is not editable, never sent
    });

    test('nothing changed gives an empty body; lists and numbers compare by value', () {
      final m = {'depthFt': 1, 'installations': ['a', 'b'], 'name': 'N'};
      expect(changedFields(m, {'depthFt': 1.0, 'installations': ['a', 'b'], 'name': 'N'}, mediaEditable), isEmpty);
      expect(changedFields(m, {'installations': ['b', 'a']}, mediaEditable), {'installations': ['b', 'a']}); // the order matters
    });

    test('a new entry drops the empty optional values but keeps false and 0', () {
      expect(newEntryBody({'code': 'ABC', 'name': 'N', 'description': '  ', 'unit': null, 'illuminated': false, 'depthFt': 0.0, 'installations': <String>[]}), {'code': 'ABC', 'name': 'N', 'illuminated': false, 'depthFt': 0.0, 'installations': <String>[]});
    });

    test('moving one place up or down', () {
      expect(movedIds(['a', 'b', 'c'], 1, -1), ['b', 'a', 'c']);
      expect(movedIds(['a', 'b', 'c'], 1, 1), ['a', 'c', 'b']);
      expect(movedIds(['a', 'b', 'c'], 0, -1), ['a', 'b', 'c']);
      expect(movedIds(['a', 'b', 'c'], 2, 1), ['a', 'b', 'c']);
    });
  });

  group('controller', () {
    test('reads the catalog and the usage counts; the older media types are listed apart', () async {
      final r = await _rig();
      expect(r.ctrl.loaded, isTrue);
      expect(r.ctrl.data.version, 5);
      expect([for (final m in r.ctrl.currentMedia) m.code], ['GSB', 'ACP']);
      expect([for (final m in r.ctrl.legacyMedia) m.code], ['OLD']);
      expect(r.ctrl.usage.ofMedia('GSB'), 2);
      expect([for (final q in r.ctrl.questionsOf('MEDIA', 'GSB')) q.id], ['fascia', 'led_count']);
      expect([for (final q in r.ctrl.questionsOf('COMMON', '')) q.id], ['existing_board']);
    });

    test('a load that fails shows the error; a second silent failure keeps what is on screen', () async {
      final api = _FakeApi()..failLoad = true;
      final ctrl = CatalogAdminController(api);
      await ctrl.load();
      expect(ctrl.loaded, isFalse);
      expect(ctrl.error, contains('Cannot reach'));
      api.failLoad = false;
      await ctrl.load();
      expect(ctrl.loaded, isTrue);
      api.failLoad = true;
      await ctrl.load(silent: true);
      expect(ctrl.loaded, isTrue);
      expect(ctrl.data.media, isNotEmpty);
    });

    test('a change is sent, the lists are read again and the copy used by the field screens is refreshed', () async {
      final r = await _rig();
      final before = r.api.loads;
      expect(await r.ctrl.update(CatalogKind.media, 'ACP', {'name': 'ACP 2D'}), isNull);
      expect(r.api.calls, ['update media ACP']);
      expect(r.api.lastBody, {'name': 'ACP 2D'});
      expect(r.ctrl.data.mediaByCode('ACP')!.name, 'ACP 2D');
      expect(r.api.loads, before + 1);
      expect(r.shared.refreshes, 1);
    });

    test('an update with nothing changed sends nothing', () async {
      final r = await _rig();
      expect(await r.ctrl.update(CatalogKind.media, 'ACP', {}), isNull);
      expect(r.api.calls, isEmpty);
      expect(r.shared.refreshes, 0);
    });

    test('the text of a refused change comes back, and nothing is refreshed', () async {
      final r = await _rig();
      r.api.failWith = 'GSB is used by 2 boards already. Mark it inactive instead of deleting it.';
      expect(await r.ctrl.delete(CatalogKind.media, 'GSB'), contains('Mark it inactive'));
      expect(r.shared.refreshes, 0);
      expect(r.ctrl.busy, isFalse);
    });

    test('defaults: the count of entries added back is kept', () async {
      final r = await _rig();
      expect(await r.ctrl.loadDefaults(), isNull);
      expect(r.ctrl.lastDefaultsAdded, 3);
    });
  });

  group('media form', () {
    testWidgets('a new media type: the code is capitalised as typed, inline errors stop an empty form, and the body is complete', (tester) async {
      final r = await _rig();
      final results = <bool?>[];
      await _openForm(tester, r.ctrl, MediaFormScreen(ctrl: r.ctrl), results: results);

      await _save(tester);
      expect(find.text('Code: 2 to 30 capital letters, digits or _'), findsOneWidget);
      expect(find.text('Enter the short name'), findsOneWidget);
      expect(find.text('Enter the name'), findsOneWidget);
      expect(r.api.calls, isEmpty);

      await _type(tester, 'f-code', 'led-box 2d');
      expect((tester.widget<TextFormField>(find.byKey(const Key('f-code'))).controller!).text, 'LEDBOX2D'); // upper case, no space, no dash
      await _type(tester, 'f-short', 'LB<2D>');
      expect(tester.widget<TextFormField>(find.byKey(const Key('f-short'))).controller!.text, 'LB2D'); // no angle brackets
      await _type(tester, 'f-name', 'LED box 2D');
      await _type(tester, 'f-depth', '1.2345');
      expect(tester.widget<TextFormField>(find.byKey(const Key('f-depth'))).controller!.text, '1.23'); // 2 decimals, 5 characters
      await tester.tap(find.byKey(const Key('inst-pole')));
      await tester.tap(find.byKey(const Key('inst-wall')));
      await tester.tap(find.byKey(const Key('swatch-#1A73E8')));
      await tester.tap(find.byKey(const Key('icon-wallpaper')));
      await tester.pump();
      await _save(tester);

      expect(r.api.calls, ['create media']);
      expect(r.api.lastBody, {
        'code': 'LEDBOX2D',
        'shortName': 'LB2D',
        'name': 'LED box 2D',
        'icon': 'wallpaper',
        'color': '#1A73E8',
        'illuminated': false,
        'sidedness': 'SINGLE',
        'depthFt': 1.23,
        'thicknessMm': 0.0,
        'installations': ['pole', 'wall'], // the order they were ticked
        'active': true,
      });
      expect(results, [true]);
      expect(r.ctrl.data.mediaByCode('LEDBOX2D'), isNotNull);
    });

    testWidgets('an edit sends only what changed, the code cannot be typed, and no change means no call', (tester) async {
      final r = await _rig();
      final results = <bool?>[];
      await _openForm(tester, r.ctrl, MediaFormScreen(ctrl: r.ctrl, media: r.ctrl.data.mediaByCode('GSB')), results: results);
      expect(tester.widget<TextFormField>(find.byKey(const Key('f-code'))).enabled, isFalse);

      await _type(tester, 'f-name', 'Glow Sign Board 2');
      await tester.tap(find.byKey(const Key('f-active')));
      await tester.pump();
      await _save(tester);
      expect(r.api.calls, ['update media GSB']);
      expect(r.api.lastBody, {'name': 'Glow Sign Board 2', 'active': false});
      expect(results, [true]);

      // open again and save without a change
      final again = <bool?>[];
      await _openForm(tester, r.ctrl, MediaFormScreen(ctrl: r.ctrl, media: r.ctrl.data.mediaByCode('ACP')), results: again);
      await _save(tester);
      expect(r.api.calls.length, 1);
      expect(again, [false]);
    });

    testWidgets('the answer of the server stays on the form (a used entry, a repeated code)', (tester) async {
      final r = await _rig();
      r.api.failWith = 'A media type with code GSB already exists';
      final results = <bool?>[];
      await _openForm(tester, r.ctrl, MediaFormScreen(ctrl: r.ctrl), results: results);
      await _type(tester, 'f-code', 'gsb');
      await _type(tester, 'f-short', 'GSB');
      await _type(tester, 'f-name', 'Again');
      await _save(tester);
      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(find.text('A media type with code GSB already exists'), findsOneWidget);
      expect(results, isEmpty); // still open
    });
  });

  group('installation form', () {
    testWidgets('a new installation type needs a small-letter code and a name', (tester) async {
      final r = await _rig();
      final results = <bool?>[];
      await _openForm(tester, r.ctrl, InstallationFormScreen(ctrl: r.ctrl), results: results);
      await _save(tester);
      expect(find.text('Code: 2 to 40 small letters, digits or _'), findsOneWidget);
      await _type(tester, 'f-code', 'Roof Top!');
      expect(tester.widget<TextFormField>(find.byKey(const Key('f-code'))).controller!.text, 'rooftop');
      await _type(tester, 'f-name', 'Rooftop');
      await _save(tester);
      expect(r.api.lastBody, {'code': 'rooftop', 'name': 'Rooftop', 'icon': 'category_outlined', 'active': true});
      expect(results, [true]);
    });
  });

  group('question form', () {
    testWidgets('a choice question needs two options; a typed duplicate is refused; the body names its group', (tester) async {
      final r = await _rig();
      final results = <bool?>[];
      await _openForm(tester, r.ctrl, QuestionFormScreen(ctrl: r.ctrl, scope: 'MEDIA', scopeCode: 'GSB'), results: results);
      await _type(tester, 'f-key', 'Led Colour');
      expect(tester.widget<TextFormField>(find.byKey(const Key('f-key'))).controller!.text, 'ledcolour');
      await _type(tester, 'f-label', 'LED colour');
      await tester.tap(find.byKey(const Key('type-CHOICE')));
      await tester.pump();

      await _type(tester, 'f-option', 'White');
      await tester.tap(find.byKey(const Key('add-option')));
      await tester.pump();
      await _type(tester, 'f-option', 'white');
      await tester.tap(find.byKey(const Key('add-option')));
      await tester.pump();
      expect(find.text('This option is already in the list'), findsOneWidget);
      await _save(tester);
      expect(find.text('A choice question needs at least two options.'), findsOneWidget);
      expect(r.api.calls, isEmpty);

      await _type(tester, 'f-option', 'Warm white');
      await tester.tap(find.byKey(const Key('add-option')));
      await tester.pump();
      await _save(tester);
      expect(r.api.calls, ['create questions']);
      expect(r.api.lastBody, {'scope': 'MEDIA', 'scopeCode': 'GSB', 'id': 'ledcolour', 'label': 'LED colour', 'type': 'CHOICE', 'options': ['White', 'Warm white'], 'required': true, 'active': true});
      expect(results, [true]);
    });

    testWidgets('"show only if" takes the answer in the form of the other question (Yes / No)', (tester) async {
      final r = await _rig();
      final results = <bool?>[];
      await _openForm(tester, r.ctrl, QuestionFormScreen(ctrl: r.ctrl, scope: 'COMMON', scopeCode: ''), results: results);
      await _type(tester, 'f-key', 'remove_old');
      await _type(tester, 'f-label', 'Remove the old board?');
      await tester.ensureVisible(find.byKey(const Key('f-showid')));
      await tester.tap(find.byKey(const Key('f-showid')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Question existing_board').last);
      await tester.pumpAndSettle();
      await _save(tester);
      expect(find.text('Say which answer shows this question.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('show-true')));
      await tester.pump();
      await _save(tester);
      expect(r.api.lastBody!['showIfId'], 'existing_board');
      expect(r.api.lastBody!['showIfValue'], true);
      expect(r.api.lastBody!.containsKey('scopeCode'), isFalse); // a question for every board has no media or installation
    });

    testWidgets('an edit: the key and the type are fixed, only changed fields go, a cleared dependency goes as null', (tester) async {
      final r = await _rig();
      r.api.questions.add(_q('q9', 'remove_old', showIfId: 'existing_board', showIfValue: true, order: 1));
      await r.ctrl.load();
      final results = <bool?>[];
      await _openForm(tester, r.ctrl, QuestionFormScreen(ctrl: r.ctrl, scope: 'COMMON', scopeCode: '', question: r.ctrl.data.questions.firstWhere((q) => q.uid == 'q9')), results: results);
      expect(tester.widget<TextFormField>(find.byKey(const Key('f-key'))).enabled, isFalse);
      expect(find.byKey(const Key('type-CHOICE')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('f-showid')));
      await tester.tap(find.byKey(const Key('f-showid')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Always ask').last);
      await tester.pumpAndSettle();
      await _save(tester);
      expect(r.api.calls, ['update questions q9']);
      expect(r.api.lastBody, {'showIfId': null, 'showIfValue': null});
    });
  });

  group('catalog screen', () {
    Future<void> openScreen(WidgetTester tester, CatalogAdminController ctrl) async {
      _phone(tester);
      await tester.pumpWidget(_host(const CatalogAdminScreen(), ctrl));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the version, the media types with their counts, and the older types apart', (tester) async {
      final r = await _rig();
      await openScreen(tester, r.ctrl);
      expect(find.text('v5'), findsOneWidget);
      expect(find.text('GSB  Glow Sign Board'), findsOneWidget);
      expect(find.text('2 boards'), findsOneWidget);
      expect(find.text('2 questions'), findsOneWidget); // GSB has two questions of its own
      expect(find.text('Older media types'), findsOneWidget);
      expect(find.byKey(const Key('tile-OLD')), findsOneWidget);
    });

    testWidgets('a load that fails shows a retry instead of an empty list', (tester) async {
      final api = _FakeApi()..failLoad = true;
      final ctrl = CatalogAdminController(api);
      await ctrl.load();
      await openScreen(tester, ctrl);
      expect(find.text('Could not load the catalog'), findsOneWidget);
      api.failLoad = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('GSB  Glow Sign Board'), findsOneWidget);
    });

    testWidgets('the switch makes a media type inactive and sends only that', (tester) async {
      final r = await _rig();
      await openScreen(tester, r.ctrl);
      await tester.tap(find.byKey(const Key('active-ACP')));
      await tester.pumpAndSettle();
      expect(r.api.calls, ['update media ACP']);
      expect(r.api.lastBody, {'active': false});
      expect(find.text('Inactive'), findsOneWidget);
    });

    testWidgets('a media type that boards use is not deleted: the person is offered "Mark inactive"', (tester) async {
      final r = await _rig();
      await openScreen(tester, r.ctrl);
      await tester.tap(find.byKey(const Key('menu-GSB')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('In use: cannot delete'), findsOneWidget);
      expect(find.textContaining('used by 2 boards'), findsOneWidget);
      await tester.tap(find.text('Mark inactive'));
      await tester.pumpAndSettle();
      expect(r.api.calls, ['update media GSB']); // never a delete
      expect(r.api.lastBody, {'active': false});
    });

    testWidgets('an unused media type is deleted after a confirmation that says what goes with it', (tester) async {
      final r = await _rig();
      await openScreen(tester, r.ctrl);
      await tester.tap(find.byKey(const Key('menu-ACP')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete ACP?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(r.api.calls, isEmpty);

      await tester.tap(find.byKey(const Key('menu-ACP')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(r.api.calls, ['delete media ACP']);
      expect(find.byKey(const Key('tile-ACP')), findsNothing);
    });

    testWidgets('move down sends the new order of the offered media types only', (tester) async {
      final r = await _rig();
      await openScreen(tester, r.ctrl);
      await tester.tap(find.byKey(const Key('menu-GSB')));
      await tester.pumpAndSettle();
      expect(find.text('Move up'), findsNothing); // the first one cannot go up
      await tester.tap(find.text('Move down'));
      await tester.pumpAndSettle();
      expect(r.api.calls, ['reorder media']);
      expect(r.api.lastOrder, ['ACP', 'GSB']); // the older type OLD is not part of the order
    });

    testWidgets('the Installation tab counts the media types and questions of each entry; a server refusal is shown', (tester) async {
      final r = await _rig();
      r.api.usedInstallations = {'wall': 3};
      await r.ctrl.load();
      await openScreen(tester, r.ctrl);
      await tester.tap(find.text('Installation'));
      await tester.pumpAndSettle();
      expect(find.text('Wall mount'), findsOneWidget);
      expect(find.text('3 media types'), findsNWidgets(1)); // GSB, ACP and the older OLD offer it; 'pole' is offered by none
      expect(find.text('0 media types'), findsOneWidget);
      expect(find.text('3 boards'), findsOneWidget);
      r.api.failWith = 'Something is wrong';
      await tester.tap(find.byKey(const Key('active-pole')));
      await tester.pumpAndSettle();
      expect(find.text('Something is wrong'), findsOneWidget);
    });

    testWidgets('the Questions tab lists one group at a time, and the group menu changes it', (tester) async {
      final r = await _rig();
      await openScreen(tester, r.ctrl);
      await tester.tap(find.text('Questions'));
      await tester.pumpAndSettle();
      expect(find.text('Question existing_board'), findsOneWidget);
      expect(find.text('Question fascia'), findsNothing);

      await tester.tap(find.text('Media type'));
      await tester.pumpAndSettle();
      expect(find.text('Question fascia'), findsOneWidget); // the first media type, GSB
      expect(find.text('Question led_count'), findsOneWidget);
      expect(find.text('Question existing_board'), findsNothing);

      await tester.tap(find.byKey(const Key('menu-q3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move up'));
      await tester.pumpAndSettle();
      expect(r.api.lastOrder, ['q3', 'q2']); // the question ids of this one group, in the new order
    });

    testWidgets('"Load built-in defaults" asks first, then says how many entries came back', (tester) async {
      final r = await _rig();
      await openScreen(tester, r.ctrl);
      await tester.tap(find.byKey(const Key('catalog-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load built-in defaults'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Load'));
      await tester.pumpAndSettle();
      expect(r.api.calls, ['defaults']);
      expect(find.text('3 built-in entries added back.'), findsOneWidget);
    });
  });

  group('administrator sign in on the phone', () {
    LiveUser admin() => const LiveUser(id: 'a1', name: 'Admin One', email: 'admin@x.com', role: LiveRole.admin);

    test('the administrator role is accepted on the phone but is not field staff', () {
      expect(LiveRole.parse('SUPER_ADMIN'), LiveRole.admin);
      expect(LiveRole.admin.signsInOnPhone, isTrue);
      expect(LiveRole.admin.isFieldStaff, isFalse);
      expect(LiveRole.recceExecutive.isFieldStaff, isTrue);
      expect(LiveRole.vendor.signsInOnPhone, isTrue);
      expect(LiveRole.parse('OPERATIONS'), LiveRole.other);
      expect(LiveRole.other.signsInOnPhone, isFalse); // a web role is still refused
      expect(admin().isAdmin, isTrue);
    });

    test('the controller keeps an administrator signed in, and still refuses a web role', () async {
      final repo = _FakeAuthRepo(admin());
      final auth = LiveAuthController(repo);
      expect(await auth.login('admin@x.com', const MpinCredential('4829'), loginRole: 'ADMIN'), isTrue);
      expect(auth.user!.isAdmin, isTrue);
      expect(repo.loginRole, 'ADMIN');

      final web = LiveAuthController(_FakeAuthRepo(const LiveUser(id: 'o1', name: 'Ops', email: 'o@x.com', role: LiveRole.other)));
      expect(await web.login('o@x.com', const MpinCredential('4829'), loginRole: 'ADMIN'), isFalse);
      expect(web.error!.code, 'PLATFORM_NOT_ALLOWED');
      auth.dispose();
      web.dispose();
    });

    testWidgets('the login screen has an Admin card: it hides "Create an account" and signs in under the ADMIN card', (tester) async {
      _phone(tester);
      final repo = _FakeAuthRepo(admin());
      final auth = LiveAuthController(repo);
      await tester.pumpWidget(ChangeNotifierProvider<LiveAuthController>.value(value: auth, child: const MaterialApp(home: LiveLoginScreen())));
      expect(find.text('Create an account'), findsOneWidget); // the Recce card
      await tester.tap(find.text('Admin'));
      await tester.pumpAndSettle();
      expect(find.text('Create an account'), findsNothing); // an administrator account is made on the web
      expect(find.text('Administrator sign in: manage the media catalog'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Email / Employee ID'), 'admin@x.com');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'Passw0rd!x');
      await tester.tap(find.widgetWithText(FilledButton, 'Login'));
      await tester.pumpAndSettle();
      expect(repo.loginRole, 'ADMIN');
      expect(auth.user?.isAdmin, isTrue);
      auth.dispose();
    });

    testWidgets('after an administrator signs in the phone shows the Media catalog, not the field screens, and reads no shops', (tester) async {
      _phone(tester);
      final api = _FakeApi();
      final queue = UploadQueue(api, autoRetry: false);
      final shops = ShopListController(api, queue);
      final repo = _FakeAuthRepo(admin());
      final auth = LiveAuthController(repo);
      final services = LiveServices.withParts(auth: auth, api: api, queue: queue, shops: shops);
      final app = AppController(store: MemoryLocalStore());
      await app.init();
      await tester.pumpWidget(AdinnRecceApp(controller: app, live: services));
      await tester.pumpAndSettle();
      expect(find.byType(LiveLoginScreen), findsOneWidget);

      await auth.login('admin@x.com', const MpinCredential('4829'), loginRole: 'ADMIN');
      await tester.pumpAndSettle();
      expect(find.byType(AdminHomeShell), findsOneWidget);
      expect(find.text('Media catalog'), findsOneWidget);
      expect(find.text('GSB  Glow Sign Board'), findsOneWidget); // read from the server
      expect(find.text('Projects'), findsNothing);
      expect(find.text('Dashboard'), findsNothing);
      expect(shops.loaded, isFalse); // no shops are read for an administrator

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Admin One'), findsOneWidget);
      expect(find.text('Administrator'), findsOneWidget);
      expect(find.byKey(const Key('admin-signout')), findsOneWidget);
      auth.dispose();
      shops.dispose();
      queue.dispose();
    });
  });
}
