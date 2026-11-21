import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signage_recce/core/network/api_exception.dart';
import 'package:signage_recce/core/network/token_manager.dart';
import 'package:signage_recce/core/storage/session_store.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/core/utils/formatters.dart';
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
import 'package:signage_recce/features/live_recce/data/upload_queue.dart';
import 'package:signage_recce/features/live_recce/presentation/chat_bubbles.dart';
import 'package:signage_recce/features/live_recce/presentation/chat_composer.dart';
import 'package:signage_recce/features/live_recce/presentation/chat_tab.dart';
import 'package:signage_recce/features/live_recce/presentation/dashboard_widgets.dart';
import 'package:signage_recce/features/live_recce/presentation/live_dashboard_screen.dart';
import 'package:signage_recce/features/live_recce/presentation/live_shop_screen.dart';
import 'package:signage_recce/features/live_recce/presentation/notifications_screen.dart';

/// Milestone 3 (shop chat, field dashboard, notifications). Fake JSON in the exact shape of the backend (recceReview.thread.ts,
/// connect.service.ts `present`, recceReview.dashboard.ts, notification.service.ts `toItem`). No network, no emulator, no database.

/* ------------------------------------------------------------------ fake JSON */

String _id(int n) => 'c${n.toString().padLeft(23, '0')}'; // 24 characters, sortable
String _iso(DateTime d) => d.toUtc().toIso8601String();

Map<String, dynamic> _msg(
  int n, {
  String body = '',
  String author = 'u2',
  String name = 'Arvind K.',
  String role = 'OPERATIONS',
  DateTime? at,
  List<Map<String, dynamic>> refs = const [],
  List<Map<String, dynamic>> attachments = const [],
  Map<String, dynamic>? card,
}) =>
    {
      'id': _id(n),
      'channel': 'ch1',
      'author': {'id': author, 'name': name, 'role': role},
      'body': body,
      'parent': null,
      'mentions': <String>[],
      'attachments': attachments,
      'reactions': <Map<String, dynamic>>[],
      'card': card,
      'shop': 's1',
      'refs': refs,
      'replyCount': 0,
      'lastReplyAt': null,
      'edited': false,
      'deleted': false,
      'deletedAt': null,
      'pinned': false,
      'createdAt': _iso(at ?? DateTime.utc(2026, 11, 21, 10, n % 60)),
    };

Map<String, dynamic> _attachment({String? url = 'http://host/signed/lane.jpg', String? expiresAt}) => {
      'fileId': 'f1',
      'name': 'lane.jpg',
      'size': 182044,
      'mimeType': 'image/jpeg',
      'kind': 'image',
      'voice': false,
      'durationSec': null,
      'peaks': <int>[],
      'url': url,
      'expiresAt': expiresAt,
    };

Map<String, dynamic> _reviewCard() => {
      'title': 'Recce Review Update',
      'tone': 'warn',
      'path': '/recce-review/6801b2',
      'lines': [
        {'label': 'Shop', 'value': 'Shop 1'},
        {'label': 'Decision', 'value': 'Rework required'},
        {'label': 'Comments', 'value': 'Front view is blurry, please retake it'},
      ],
    };

Map<String, dynamic> _photoJson(String id, String category) => {
      'id': id,
      'category': category,
      'state': 'DRAFT',
      'mediaKey': '',
      'url': 'http://host/file/$id.jpg',
      'review': {'status': 'PENDING', 'openRework': null},
    };

Map<String, dynamic> _detailJson({bool closed = false, List<Map<String, dynamic>>? photos}) => {
      'siteId': 's1',
      'siteCode': 'SM-0234',
      'shopName': 'Sri Murugan Super Market',
      'address': 'T. Nagar, Chennai',
      'project': {'id': 'p1', 'code': 'ADN-2451', 'name': 'South Zone', 'client': 'ABC Retail', 'closed': closed},
      'status': 'IN_PROGRESS',
      'editable': true,
      'version': 0,
      'mediaItems': [
        {'key': 'b1', 'name': 'GSB', 'quantity': 1, 'width': 6, 'height': 4, 'unit': 'FT', 'required': ['SHOP_FRONT']},
      ],
      'installation': null,
      'notes': '',
      'photos': photos ?? [_photoJson('p1', 'SHOP_FRONT')],
      'progress': {'percent': 10, 'missing': []},
      'versions': [],
      'reviews': [],
      'reworks': [],
    };

Map<String, dynamic> _shopRow(String id, String status, {String project = 'p1', String code = 'P-M3'}) => {
      'siteId': id,
      'projectId': project,
      'projectCode': code,
      'projectName': 'Recce M3',
      'client': 'Amul',
      'siteCode': 'SM-$id',
      'shopName': 'Shop $id',
      'address': 'Chennai',
      'mediaTypes': [
        {'name': 'GSB', 'quantity': 1},
      ],
      'assignedAt': '2026-11-20T05:00:00.000Z',
      'status': status,
      'progress': 20,
    };

/// The payload of docs/recce-development/08-milestone3-api-payloads.md section 2.
Map<String, dynamic> _dashboardJson() => {
      'assignedProjects': 2,
      'assignedShops': 3,
      'started': 1,
      'submitted': 1,
      'underReview': 0,
      'approved': 1,
      'rework': 0,
      'completed': 1,
      'pending': 2,
      'avgCompletionHours': 26.4,
      'reworkCount': 0,
      'reworkPercent': 0,
      'projects': [
        {'projectId': '6700a1', 'projectCode': 'P-M3', 'projectName': 'Recce M3', 'assigned': 2, 'started': 1, 'submitted': 1, 'approved': 1, 'rework': 0, 'pending': 1},
        {'projectId': '6700a2', 'projectCode': 'P-M3B', 'projectName': 'Recce M3 B', 'assigned': 1, 'started': 0, 'submitted': 0, 'approved': 0, 'rework': 0, 'pending': 1},
      ],
    };

Map<String, dynamic> _note(String id, String type, {String? siteId = 's1', bool read = false, DateTime? at, String title = 'Title'}) => {
      'id': id,
      'kind': 'activity',
      'type': type,
      'title': title,
      'text': 'Text of $id',
      'at': _iso(at ?? DateTime.utc(2026, 11, 21, 10)),
      'projectId': 'p1',
      'projectCode': 'P-M3',
      'orderId': null,
      'path': '/recce-review/6801b2',
      'siteId': siteId,
      'client': 'Amul',
      'read': read,
    };

/* ------------------------------------------------------------------ fakes */

/// The server's thread paging in a few lines: newest first, `before` = an id, `nextBefore` = the oldest id of the page or null.
class _M3Api extends RecceApi {
  _M3Api() : super(Dio());

  // shop list and detail
  List<ShopSummary> shopRows = const [];
  Map<String, dynamic> detailJson = _detailJson();

  // thread
  final thread = <Map<String, dynamic>>[];
  int unreadCount = 0;
  int listCalls = 0;
  int unreadCalls = 0;
  int readCalls = 0;
  final beforeArgs = <String?>[];
  Completer<void>? hold;
  Object? messagesError;
  Object? postError;
  final posts = <({String body, List<ChatRef> refs, String? image})>[];

  // dashboard
  Map<String, dynamic>? dashboardJson;
  Object? dashboardError;
  int dashboardCalls = 0;

  // notifications
  List<Map<String, dynamic>> noteRows = [];
  int noteUnread = 0;
  Object? noteError;
  int noteCalls = 0;
  final readIds = <String>[];
  int readAllCalls = 0;

  @override
  Future<ShopListPage> shops() async => ShopListPage(items: shopRows, total: shopRows.length, summary: {for (final s in shopRows) s.status: 1});

  @override
  Future<ShopDetail> detail(String siteId) async => ShopDetail.fromJson(detailJson);

  @override
  Future<List<RecceVersion>> versions(String siteId) async => const [];

  @override
  Future<ChatPage> messages(String siteId, {int limit = chatPageSize, String? before}) async {
    listCalls++;
    beforeArgs.add(before);
    await hold?.future;
    if (messagesError != null) throw messagesError!;
    final newestFirst = thread.reversed.where((m) => before == null || (m['id'] as String).compareTo(before) < 0).toList();
    final page = newestFirst.take(limit).toList();
    final more = newestFirst.length > limit;
    return ChatPage.fromEnvelope({
      'success': true,
      'data': page,
      'meta': {'limit': limit, 'hasMore': more, 'nextBefore': more ? page.last['id'] : null},
    });
  }

  @override
  Future<int> messagesUnread(String siteId) async {
    unreadCalls++;
    return unreadCount;
  }

  @override
  Future<void> markMessagesRead(String siteId) async {
    readCalls++;
    unreadCount = 0;
  }

  @override
  Future<ChatMessage> postMessage(
    String siteId, {
    String body = '',
    List<ChatRef> refs = const [],
    String? imagePath,
    String? imageName,
    void Function(double)? onProgress,
    CancelToken? cancel,
  }) async {
    posts.add((body: body, refs: refs, image: imageName));
    onProgress?.call(0.5);
    if (postError != null) throw postError!;
    final json = _msg(900 + posts.length, body: body, author: 'u1', name: 'Siva', role: 'RECCE_EXECUTIVE', at: DateTime.now().toUtc(), refs: [for (final r in refs) r.toJson()]);
    thread.add(json);
    return ChatMessage.fromJson(json);
  }

  @override
  Future<FieldDashboard> dashboard() async {
    dashboardCalls++;
    if (dashboardError != null) throw dashboardError!;
    return FieldDashboard.fromJson(dashboardJson ?? _dashboardJson());
  }

  @override
  Future<NotificationFeed> notifications() async {
    noteCalls++;
    if (noteError != null) throw noteError!;
    return NotificationFeed.fromEnvelope({
      'success': true,
      'data': {'unread': noteUnread, 'items': noteRows},
    });
  }

  @override
  Future<void> markNotificationRead(String id) async => readIds.add(id);

  @override
  Future<void> markAllNotificationsRead() async => readAllCalls++;
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
  _FakeAuthRepo({this.signedIn}) : super(plainDio: Dio(), tokens: TokenManager(refreshDio: Dio(), store: _MemoryStore()), store: _MemoryStore());

  final LiveUser? signedIn;

  @override
  Future<LiveUser> login(String identifier, AuthCredential credential, {String? loginRole}) async => signedIn!;

  @override
  Future<void> logout() async {}
}

LiveUser _user([String id = 'u1']) => LiveUser(id: id, name: 'Siva Kumar', email: 'siva@x.com', role: LiveRole.recceExecutive);

/// Every part the live screens read, over one fake API, provided the way app.dart provides them.
class _Rig {
  _Rig([_M3Api? fake])
      : api = fake ?? _M3Api(),
        auth = LiveAuthController(_FakeAuthRepo(signedIn: _user())) {
    queue = UploadQueue(api, autoRetry: false);
    shops = ShopListController(api, queue);
    services = LiveServices.withParts(auth: auth, api: api, queue: queue, shops: shops);
  }

  final _M3Api api;
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

void _phone(WidgetTester tester, {double height = 2400}) {
  tester.view.physicalSize = Size(1080, height); // 360 x (height / 3) logical
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  /* ================================================================ messages */

  group('message parsing', () {
    test('the documented list answer: author, refs, attachment, system card, meta', () {
      final page = ChatPage.fromEnvelope({
        'success': true,
        'data': [
          {
            'id': '6810c5',
            'channel': '6801d1',
            'author': {'id': '66f01', 'name': 'Siva Creations', 'role': 'VENDOR'},
            'body': 'Board is faded, photo attached',
            'parent': null,
            'mentions': [],
            'attachments': [_attachment(url: 'https://x/signed', expiresAt: '2026-11-21T10:30:00.000Z')],
            'reactions': [],
            'card': null,
            'shop': '67f0a1',
            'refs': [
              {'type': 'PHOTO', 'id': '6800e1'},
              {'type': 'BOARD', 'id': 'b1'},
              {'type': 'VERSION', 'id': '2'},
            ],
            'edited': false,
            'deleted': false,
            'createdAt': '2026-11-21T10:15:00.000Z',
          },
          {
            'id': '6810c4',
            'author': {'id': '66f09', 'name': 'Arvind K.', 'role': 'OPERATIONS'},
            'body': '',
            'attachments': [],
            'refs': [
              {'type': 'PHOTO', 'id': '6800e1'},
              {'type': 'VERSION', 'id': '1'},
            ],
            'card': _reviewCard(),
            'createdAt': '2026-11-21T10:10:00.000Z',
          },
        ],
        'meta': {'limit': 2, 'hasMore': true, 'nextBefore': '6810c4'},
      });
      expect(page.items, hasLength(2));
      expect(page.nextBefore, '6810c4');
      expect(page.hasMore, isTrue);

      final person = page.items[0];
      expect(person.isSystem, isFalse);
      expect(person.author.displayName, 'Siva Creations');
      expect(person.author.role, 'VENDOR');
      expect(person.author.roleLabel, 'Vendor');
      expect(person.refs.map((r) => r.key), ['PHOTO:6800e1', 'BOARD:b1', 'VERSION:2']);
      final a = person.attachments.single;
      expect(a.isImage, isTrue);
      expect(a.name, 'lane.jpg');
      expect(a.size, 182044);
      expect(a.url, 'https://x/signed');
      expect(a.expiresAt!.toUtc(), DateTime.utc(2026, 11, 21, 10, 30));
      expect(person.createdAt!.toUtc(), DateTime.utc(2026, 11, 21, 10, 15));

      final system = page.items[1];
      expect(system.isSystem, isTrue);
      expect(system.card!.title, 'Recce Review Update');
      expect(system.card!.tone, 'warn');
      expect(system.card!.lines.map((l) => '${l.label}=${l.value}'), ['Shop=Shop 1', 'Decision=Rework required', 'Comments=Front view is blurry, please retake it']);
      expect(system.refs.map((r) => r.type), [ChatRefType.photo, ChatRefType.version]);
    });

    test('a missing field is a safe default, never a thrown cast', () {
      final m = ChatMessage.fromJson({'id': 'x1', 'author': null, 'body': null, 'attachments': null, 'refs': 'nope', 'card': 'nope', 'createdAt': null});
      expect(m.id, 'x1');
      expect(m.author.displayName, 'Former member');
      expect(m.body, '');
      expect(m.attachments, isEmpty);
      expect(m.refs, isEmpty);
      expect(m.card, isNull);
      expect(m.createdAt, isNull);
      final a = ChatAttachment.fromJson({'fileId': null, 'name': null, 'size': 'big', 'url': null, 'expiresAt': 5});
      expect(a.name, 'file');
      expect(a.size, 0);
      expect(a.url, isNull);
      expect(a.expiresAt, isNull);
      expect(a.isImage, isFalse);
      expect(a.linkExpired(DateTime.now()), isTrue); // no link at all
      expect(ChatPage.fromEnvelope(null).items, isEmpty);
      expect(ChatPage.fromEnvelope({'data': 'nope'}).items, isEmpty);
    });

    test('an unknown ref type is dropped, a row without an id or a deleted one is left out', () {
      final list = ChatMessage.listFrom([
        {'id': 'a', 'refs': [{'type': 'PHOTO', 'id': 'p'}, {'type': 'NOTE', 'id': 'n'}, {'type': 'BOARD', 'id': ''}, {'type': 'board', 'id': 'b2'}]},
        {'body': 'no id'},
        {'id': 'gone', 'deleted': true},
      ]);
      expect(list.map((m) => m.id), ['a']);
      expect(list.single.refs.map((r) => r.key), ['PHOTO:p', 'BOARD:b2']);
    });

    test('a signed link past its end time is expired, one in the future is not', () {
      final now = DateTime.utc(2026, 11, 21, 10, 20);
      final gone = ChatAttachment.fromJson(_attachment(expiresAt: '2026-11-21T10:10:00.000Z'));
      final fresh = ChatAttachment.fromJson(_attachment(expiresAt: '2026-11-21T10:30:00.000Z'));
      expect(gone.linkExpired(now), isTrue);
      expect(fresh.linkExpired(now), isFalse);
      expect(ChatMessage.fromJson(_msg(1, attachments: [_attachment(expiresAt: '2026-11-21T10:10:00.000Z')])).hasExpiredLinks(now), isTrue);
    });

    test('own and others: mine only for a person who wrote it', () {
      final mine = ChatMessage.fromJson(_msg(1, author: 'u1'));
      final card = ChatMessage.fromJson(_msg(2, author: 'u1', card: _reviewCard()));
      expect(mine.isMine('u1'), isTrue);
      expect(mine.isMine('u9'), isFalse);
      expect(mine.isMine(''), isFalse);
      expect(card.isMine('u1'), isFalse); // a system card is never a person's bubble
    });
  });

  /* ================================================================ pagination */

  group('pagination merge', () {
    ChatMessage m(int n) => ChatMessage.fromJson(_msg(n, at: DateTime.utc(2026, 11, 21, 8, n)));
    ChatPage page(List<int> newestFirst, {String? next}) => ChatPage(items: [for (final n in newestFirst) m(n)], nextBefore: next);
    List<String> ids(List<ChatMessage> l) => [for (final x in l) x.id];

    test('an older page is put in front, oldest first, with no duplicate', () {
      final current = [m(4), m(5), m(6)];
      final merged = mergeOlder(current, page([4, 3, 2], next: _id(2))); // the page overlaps message 4
      expect(ids(merged), [_id(2), _id(3), _id(4), _id(5), _id(6)]);
      expect(merged.map((x) => x.id).toSet(), hasLength(5));
    });

    test('the newest page replaces the newest part and keeps the older messages we loaded', () {
      final current = [m(1), m(2), m(3), m(4)];
      final refreshed = mergeLatest(current, page([5, 4, 3], next: _id(3)));
      expect(ids(refreshed), [_id(1), _id(2), _id(3), _id(4), _id(5)]);
    });

    test('a page with nothing older holds the whole thread and replaces it (a deleted message goes)', () {
      final refreshed = mergeLatest([m(1), m(2), m(3)], page([3, 1]));
      expect(ids(refreshed), [_id(1), _id(3)]);
      expect(mergeLatest([m(1)], const ChatPage()), isEmpty);
    });

    test('a message we sent joins once, even when a refresh already brought it', () {
      expect(ids(withSent([m(1), m(2)], m(3))), [_id(1), _id(2), _id(3)]);
      expect(ids(withSent([m(1), m(2)], m(2))), [_id(1), _id(2)]);
    });

    test('the controller: first page is the newest 30, Load older adds the rest, and a null nextBefore ends it', () async {
      final api = _M3Api();
      for (var i = 1; i <= 35; i++) {
        api.thread.add(_msg(i, body: 'm$i', at: DateTime.utc(2026, 11, 21, 8, i)));
      }
      final hub = ChatHub(api);
      final chat = hub.open('s1', myId: 'u1');
      await chat.load();
      expect(chat.loaded, isTrue);
      expect(chat.messages, hasLength(30));
      expect(chat.messages.first.id, _id(6));
      expect(chat.messages.last.id, _id(35));
      expect(chat.hasMore, isTrue);
      expect(api.beforeArgs, [null]);

      await chat.loadOlder();
      expect(api.beforeArgs, [null, _id(6)]); // the cursor of the next page is the oldest id we hold
      expect(chat.messages, hasLength(35));
      expect(chat.messages.first.id, _id(1));
      expect(chat.messages.map((x) => x.id).toSet(), hasLength(35));
      expect(chat.hasMore, isFalse);

      await chat.loadOlder(); // nothing older: no call at all
      expect(api.listCalls, 2);

      await chat.refresh(); // the poll keeps the older ones and adds nothing twice
      expect(chat.messages, hasLength(35));
      chat.dispose();
    });

    test('a failed Load older keeps the thread and the cursor, and can be tried again', () async {
      final api = _M3Api();
      for (var i = 1; i <= 35; i++) {
        api.thread.add(_msg(i, at: DateTime.utc(2026, 11, 21, 8, i)));
      }
      final chat = ChatHub(api).open('s1', myId: 'u1');
      await chat.load();
      api.messagesError = const ApiException(code: 'NETWORK_ERROR', message: 'Cannot reach the server. Check your connection.');
      await chat.loadOlder();
      expect(chat.olderError, contains('Cannot reach the server'));
      expect(chat.messages, hasLength(30));
      expect(chat.hasMore, isTrue);
      api.messagesError = null;
      await chat.loadOlder();
      expect(chat.olderError, isNull);
      expect(chat.messages, hasLength(35));
      chat.dispose();
    });
  });

  /* ================================================================ unread */

  group('unread', () {
    test('the count is read from data.unread, never negative, 0 for anything else', () {
      expect(parseUnread({'success': true, 'data': {'unread': 3}}), 3);
      expect(parseUnread({'data': {'unread': '4'}}), 4);
      expect(parseUnread({'data': {'unread': -2}}), 0);
      expect(parseUnread({'data': {}}), 0);
      expect(parseUnread({'data': null}), 0);
      expect(parseUnread(null), 0);
    });

    test('reading the count fills the badge; opening the chat marks the thread read and clears it', () async {
      final api = _M3Api()..unreadCount = 3;
      for (var i = 1; i <= 3; i++) {
        api.thread.add(_msg(i, body: 'm$i'));
      }
      final readSites = <String>[];
      final hub = ChatHub(api, onThreadRead: readSites.add);
      final chat = hub.open('s1', myId: 'u1');
      await chat.loadUnread();
      expect(chat.unread, 3);
      expect(hub.unreadFor('s1'), 3);
      expect(hub.unreadFor('s2'), 0); // a shop nobody asked about is 0, and no call was made for it
      expect(api.unreadCalls, 1);

      chat.setVisible(true); // the Chat tab comes to the front
      await pumpEventQueue();
      expect(chat.loaded, isTrue);
      expect(api.readCalls, 1);
      expect(chat.unread, 0);
      expect(hub.unreadFor('s1'), 0);
      expect(readSites, ['s1']);
      chat.dispose();
    });

    test('while the chat is in front a message of the other side is marked read, one of our own is not', () async {
      final api = _M3Api();
      api.thread.add(_msg(1, body: 'hello'));
      final chat = ChatHub(api).open('s1', myId: 'u1');
      chat.setVisible(true);
      await pumpEventQueue();
      expect(api.readCalls, 1);

      await chat.tick(); // nothing new
      expect(api.readCalls, 1);

      api.thread.add(_msg(2, body: 'my own', author: 'u1', name: 'Siva'));
      await chat.tick();
      expect(chat.messages, hasLength(2));
      expect(api.readCalls, 1);

      api.thread.add(_msg(3, body: 'new from the reviewer'));
      await chat.tick();
      await pumpEventQueue();
      expect(chat.messages, hasLength(3));
      expect(api.readCalls, 2);
      chat.dispose();
    });

    test('a shop row shows the larger of the thread count and the bell\'s unread message notifications', () async {
      final api = _M3Api()
        ..noteUnread = 3
        ..noteRows = [
          _note('n1', 'RECCE_MESSAGE', siteId: 's1'),
          _note('n2', 'RECCE_MESSAGE', siteId: 's1'),
          _note('n3', 'RECCE_MESSAGE', siteId: 's2', read: true),
          _note('n4', 'RECCE_REVIEWED', siteId: 's1'),
        ];
      final hub = ChatHub(api);
      final notes = NotificationsController(api);
      await notes.load();
      expect(shopUnreadCount(hub, notes, 's1'), 2);
      expect(shopUnreadCount(hub, notes, 's2'), 0);
      hub.open('s1', myId: 'u1');
      api.unreadCount = 5;
      await hub.open('s1', myId: 'u1').loadUnread();
      expect(shopUnreadCount(hub, notes, 's1'), 5);
      notes.dispose();
    });
  });

  /* ================================================================ dashboard */

  group('dashboard', () {
    test('the documented payload is parsed', () {
      final d = FieldDashboard.fromJson(_dashboardJson());
      expect(d.assignedProjects, 2);
      expect(d.assignedShops, 3);
      expect(d.started, 1);
      expect(d.submitted, 1);
      expect(d.underReview, 0);
      expect(d.approved, 1);
      expect(d.rework, 0);
      expect(d.completed, 1);
      expect(d.pending, 2);
      expect(d.avgCompletionHours, 26.4);
      expect(d.reworkCount, 0);
      expect(d.reworkPercent, 0);
      expect(d.projects.map((p) => p.projectCode), ['P-M3', 'P-M3B']);
      final p = d.projects.first;
      expect([p.assigned, p.started, p.submitted, p.approved, p.rework, p.pending], [2, 1, 1, 1, 0, 1]);
    });

    test('no completed shop is a null average; missing fields are 0; a text number still parses', () {
      final d = FieldDashboard.fromJson({'avgCompletionHours': null, 'reworkPercent': '12.5', 'projects': 'nope'});
      expect(d.avgCompletionHours, isNull);
      expect(d.reworkPercent, 12.5);
      expect(d.assignedShops, 0);
      expect(d.projects, isEmpty);
    });

    test('hours: one decimal below a day, days and hours from a day on', () {
      expect(fmtHours(null), '-');
      expect(fmtHours(0), '0.0 h');
      expect(fmtHours(3.14), '3.1 h');
      expect(fmtHours(12.5), '12.5 h');
      expect(fmtHours(23.9), '23.9 h');
      expect(fmtHours(23.96), '1 d'); // rounds up to a whole day, never "24.0 h"
      expect(fmtHours(24), '1 d');
      expect(fmtHours(26.4), '1 d 2 h');
      expect(fmtHours(49.6), '2 d 2 h');
      expect(fmtHours(47.7), '2 d'); // 23.7 h rounds to 24 h
    });

    test('percent: one decimal', () {
      expect(fmtPercent(0), '0.0%');
      expect(fmtPercent(33.333), '33.3%');
      expect(fmtPercent(50), '50.0%');
      expect(fmtPercent(null), '0.0%');
    });

    test('a project bar: the five parts add up to the assigned shops', () {
      final p = ProjectProgress.fromJson({'assigned': 10, 'started': 8, 'submitted': 6, 'approved': 2, 'rework': 1, 'pending': 8});
      final b = p.bar;
      expect([b.approved, b.rework, b.inReview, b.working, b.notStarted], [2, 1, 3, 2, 2]);
      expect(b.total, 10);
      expect(ProjectProgress.fromJson(const {'assigned': 0}).bar.total, 0);
      // a number the server could not make consistent never goes negative
      expect(ProjectProgress.fromJson(const {'assigned': 1, 'started': 0, 'submitted': 2, 'approved': 3}).bar.inReview, 0);
    });

    test('the shop-summary counts still work (the fallback)', () {
      final c = DashboardCounts.fromSummary({'NOT_STARTED': 2, 'IN_PROGRESS': 1, 'SUBMITTED': 1, 'UNDER_REVIEW': 1, 'APPROVED': 3, 'REWORK_REQUIRED': 1});
      expect([c.total, c.pending, c.submitted, c.approved, c.rework], [9, 3, 2, 3, 1]);
    });

    test('the controller keeps no numbers and shows the error when the read fails, and a silent read never wipes numbers', () async {
      final api = _M3Api();
      final dash = FieldDashboardController(api);
      api.dashboardError = const ApiException(code: 'FORBIDDEN', message: 'Not allowed', statusCode: 403);
      await dash.load();
      expect(dash.data, isNull);
      expect(dash.error, 'Not allowed');
      expect(dash.loading, isFalse); // never stuck

      api.dashboardError = null;
      await dash.load();
      expect(dash.data!.completed, 1);
      expect(dash.error, isNull);

      api.dashboardError = const ApiException(code: 'NETWORK_ERROR', message: 'Cannot reach the server.');
      await dash.load(silent: true);
      expect(dash.data!.completed, 1);
      expect(dash.error, isNull);
      dash.dispose();
    });
  });

  /* ================================================================ notifications */

  group('notifications', () {
    test('the documented item is parsed, with type and siteId', () {
      final feed = NotificationFeed.fromEnvelope({
        'success': true,
        'data': {
          'unread': 2,
          'items': [
            {
              'id': '6820a1',
              'kind': 'activity',
              'type': 'RECCE_REVIEWED',
              'title': 'Rework required',
              'text': 'Shop 1: Arvind K. - rework',
              'at': '2026-11-21T10:10:00.000Z',
              'projectId': '6700a1',
              'projectCode': 'P-M3',
              'orderId': null,
              'path': '/recce-review/6801b2',
              'siteId': '67f0a1',
              'client': 'Amul',
              'read': false,
            },
          ],
        },
      });
      expect(feed.unread, 2);
      final n = feed.items.single;
      expect(n.id, '6820a1');
      expect(n.type, 'RECCE_REVIEWED');
      expect(n.kind, NotificationType.recceReviewed);
      expect(n.title, 'Rework required');
      expect(n.siteId, '67f0a1');
      expect(n.hasShop, isTrue);
      expect(n.projectCode, 'P-M3');
      expect(n.read, isFalse);
      expect(n.at!.toUtc(), DateTime.utc(2026, 11, 21, 10, 10));
    });

    test('the four types have their own kind and icon; an unknown or missing one is "other"; no siteId opens nothing', () {
      expect(NotificationType.parse('RECCE_SUBMITTED'), NotificationType.recceSubmitted);
      expect(NotificationType.parse('RECCE_REVIEWED'), NotificationType.recceReviewed);
      expect(NotificationType.parse('RECCE_MESSAGE'), NotificationType.recceMessage);
      expect(NotificationType.parse('SHOPS_ADDED'), NotificationType.shopsAdded);
      expect(NotificationType.parse('PROJECT_ASSIGNED'), NotificationType.other);
      expect(NotificationType.parse(null), NotificationType.other);
      expect(NotificationType.values.map((t) => t.icon).toSet(), hasLength(NotificationType.values.length));
      final n = AppNotification.fromJson({'id': 'x', 'type': null, 'title': null, 'at': 'garbage', 'siteId': null, 'read': null});
      expect(n.hasShop, isFalse);
      expect(n.at, isNull);
      expect(n.read, isFalse);
      expect(n.title, '');
      // a row without an id is dropped; unread falls back to counting the unread rows
      final feed = NotificationFeed.fromEnvelope({
        'data': {'items': [_note('a', 'SHOPS_ADDED'), {'title': 'no id'}, _note('b', 'RECCE_MESSAGE', read: true)]},
      });
      expect(feed.items, hasLength(2));
      expect(feed.unread, 1);
      expect(NotificationFeed.fromEnvelope(null).items, isEmpty);
    });

    test('grouped by day: Today, Yesterday, then dates; no time goes last under Earlier', () {
      final now = DateTime(2026, 11, 21, 15);
      AppNotification at(String id, DateTime local) => AppNotification.fromJson(_note(id, 'RECCE_MESSAGE', at: local));
      final items = [
        at('a', DateTime(2026, 11, 21, 14)),
        at('b', DateTime(2026, 11, 21, 9)),
        at('c', DateTime(2026, 11, 20, 23, 30)),
        at('d', DateTime(2026, 11, 18, 8)),
        const AppNotification(id: 'e'),
      ];
      final days = groupNotificationsByDay(items, now: now);
      expect(days.map((d) => d.label), ['Today', 'Yesterday', fmtDate(DateTime(2026, 11, 18)), 'Earlier']);
      expect(days.map((d) => d.items.map((n) => n.id).toList()).toList(), [['a', 'b'], ['c'], ['d'], ['e']]);
      expect(groupNotificationsByDay(const []), isEmpty);
    });

    test('unread badge: a tap on one drops it by one, Read all drops it to 0, the server is told', () async {
      final api = _M3Api()
        ..noteUnread = 3
        ..noteRows = [_note('n1', 'RECCE_MESSAGE'), _note('n2', 'RECCE_REVIEWED'), _note('n3', 'SHOPS_ADDED'), _note('n4', 'RECCE_SUBMITTED', read: true)];
      final c = NotificationsController(api);
      await c.load();
      expect(c.loaded, isTrue);
      expect(c.unread, 3);

      await c.markRead('n1');
      expect(c.unread, 2);
      expect(c.items.firstWhere((n) => n.id == 'n1').read, isTrue);
      expect(api.readIds, ['n1']);
      await c.markRead('n1'); // already read: nothing to do
      await c.markRead('n4');
      expect(c.unread, 2);
      expect(api.readIds, ['n1']);

      await c.markAllRead();
      expect(c.unread, 0);
      expect(c.items.every((n) => n.read), isTrue);
      expect(api.readAllCalls, 1);
      c.dispose();
    });

    test('reading the thread of a shop reads its message notifications too (no call), and only those', () async {
      final api = _M3Api()
        ..noteUnread = 4
        ..noteRows = [_note('n1', 'RECCE_MESSAGE', siteId: 's1'), _note('n2', 'RECCE_MESSAGE', siteId: 's1'), _note('n3', 'RECCE_MESSAGE', siteId: 's2'), _note('n4', 'RECCE_REVIEWED', siteId: 's1')];
      final c = NotificationsController(api);
      await c.load();
      expect(c.unreadMessagesFor('s1'), 2);
      expect(c.unreadMessages, 3);
      c.markSiteMessagesRead('s1');
      expect(c.unreadMessagesFor('s1'), 0);
      expect(c.unreadMessagesFor('s2'), 1);
      expect(c.unread, 2);
      expect(c.items.firstWhere((n) => n.id == 'n4').read, isFalse);
      expect(api.readIds, isEmpty);
      c.dispose();
    });

    test('a failed first read shows the error, a failed poll keeps what is on screen, news of added shops reads the shop list', () async {
      final api = _M3Api()..noteError = const ApiException(code: 'NETWORK_ERROR', message: 'Cannot reach the server.');
      final c = NotificationsController(api);
      await c.load();
      expect(c.loaded, isFalse);
      expect(c.error, 'Cannot reach the server.');
      expect(c.loading, isFalse);

      api
        ..noteError = null
        ..noteUnread = 1
        ..noteRows = [_note('n1', 'RECCE_MESSAGE')];
      var shopReads = 0;
      c.onNewShops = () => shopReads++;
      await c.load();
      expect(c.error, isNull);
      expect(shopReads, 0); // the first read never counts as news

      api.noteError = const ApiException(code: 'X', message: 'down');
      await c.load(silent: true);
      expect(c.items, hasLength(1));
      expect(c.error, isNull);

      api
        ..noteError = null
        ..noteUnread = 2
        ..noteRows = [_note('n2', 'SHOPS_ADDED'), _note('n1', 'RECCE_MESSAGE')];
      await c.load(silent: true);
      expect(shopReads, 1);
      await c.load(silent: true); // the same news again is not news
      expect(shopReads, 1);
      c.dispose();
    });
  });

  /* ================================================================ composer rules */

  group('composer validation', () {
    const ref = ChatRef(ChatRefType.board, 'b1');

    test('an empty message, or spaces only, cannot be sent; a picture alone can', () {
      expect(validateChatDraft(body: '', refs: const [], hasImage: false), isNotNull);
      expect(validateChatDraft(body: '   \n ', refs: const [], hasImage: false), isNotNull);
      expect(validateChatDraft(body: '', refs: const [ref], hasImage: false), isNotNull); // a reference alone is not a message
      expect(validateChatDraft(body: '', refs: const [], hasImage: true), isNull);
      expect(validateChatDraft(body: ' hello ', refs: const [], hasImage: false), isNull);
    });

    test('2000 characters are allowed (counted after trimming), 2001 are not', () {
      expect(validateChatDraft(body: 'a' * 2000, refs: const [], hasImage: false), isNull);
      expect(validateChatDraft(body: '  ${'a' * 2000}  ', refs: const [], hasImage: false), isNull);
      final tooLong = validateChatDraft(body: 'a' * 2001, refs: const [], hasImage: false);
      expect(tooLong, contains('2000'));
      expect(validateChatDraft(body: 'a' * 2001, refs: const [], hasImage: true), isNotNull); // a picture does not lift the limit
    });

    test('at most 10 references; a duplicate counts once', () {
      List<ChatRef> refs(int n) => [for (var i = 0; i < n; i++) ChatRef(ChatRefType.version, '$i')];
      expect(validateChatDraft(body: 'x', refs: refs(10), hasImage: false), isNull);
      expect(validateChatDraft(body: 'x', refs: refs(11), hasImage: false), contains('10'));
      expect(validateChatDraft(body: 'x', refs: [...refs(10), refs(10).first], hasImage: false), isNull);
      expect(uniqueRefs([ref, ref, const ChatRef(ChatRefType.photo, 'p')]), hasLength(2));
      expect(const ChatRef(ChatRefType.board, 'b1'), const ChatRef(ChatRefType.board, 'b1'));
      expect(ref.toJson(), {'type': 'BOARD', 'id': 'b1'});
    });

    test('the picture file name always carries the extension of its real content (the server checks name against content)', () {
      expect(sniffImageExtension([0xff, 0xd8, 0xff, 0xe0]), '.jpg');
      expect(sniffImageExtension([0x89, 0x50, 0x4e, 0x47, 0x0d]), '.png');
      expect(sniffImageExtension([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]), '.webp');
      expect(sniffImageExtension([1, 2, 3]), isNull);
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe1]);
      expect(chatImageName('IMG_001.HEIC', jpeg), 'IMG_001.jpg'); // re-encoded by the picker
      expect(chatImageName('C:\\pics\\lane one.png', Uint8List.fromList([0x89, 0x50, 0x4e, 0x47])), 'lane_one.png');
      expect(chatImageName(null, [9, 9, 9]), 'photo.jpg');
      expect(chatImageName('shot.webp', [9, 9, 9]), 'shot.webp');
      expect(chatImageName('/cache/blob', jpeg), 'blob.jpg');
    });
  });

  /* ================================================================ sending */

  group('sending', () {
    test('a sent message leaves the sending list and joins the thread; the box is empty again', () async {
      final api = _M3Api();
      api.thread.add(_msg(1, body: 'hello'));
      final chat = ChatHub(api).open('s1', myId: 'u1');
      await chat.load();
      chat.draftBody = '  Board is faded  ';
      chat.setDraftRefs(const [ChatRef(ChatRefType.board, 'b1'), ChatRef(ChatRefType.board, 'b1'), ChatRef(ChatRefType.version, '2')]);
      expect(chat.sendDraft(), isNull);
      expect(chat.pending, hasLength(1));
      expect(chat.pending.single.state, ChatSendState.sending);
      expect(chat.draftBody, '');
      expect(chat.draftRefs, isEmpty);
      await pumpEventQueue();
      expect(chat.pending, isEmpty);
      expect(chat.messages, hasLength(2));
      expect(chat.messages.last.body, 'Board is faded');
      expect(api.posts.single.body, 'Board is faded'); // trimmed
      expect(api.posts.single.refs.map((r) => r.key), ['BOARD:b1', 'VERSION:2']); // no duplicate
      chat.dispose();
    });

    test('nothing is sent for an empty, a too long or a too many-refs draft', () {
      final api = _M3Api();
      final chat = ChatHub(api).open('s1', myId: 'u1');
      expect(chat.sendDraft(), isNotNull);
      chat.draftBody = 'a' * 2001;
      expect(chat.sendDraft(), contains('2000'));
      chat.draftBody = 'ok';
      chat.draftRefs = [for (var i = 0; i < 11; i++) ChatRef(ChatRefType.version, '$i')];
      expect(chat.sendDraft(), contains('10'));
      expect(api.posts, isEmpty);
      expect(chat.pending, isEmpty);
      chat.dispose();
    });

    test('a failed send stays listed with the reason, Retry sends it again, Discard drops it', () async {
      final api = _M3Api()..postError = const ApiException(code: 'CONFLICT', message: 'The message could not be sent. Try again.', statusCode: 409);
      final chat = ChatHub(api).open('s1', myId: 'u1');
      chat.draftBody = 'Retaking now';
      chat.sendDraft();
      await pumpEventQueue();
      final p = chat.pending.single;
      expect(p.failed, isTrue);
      expect(p.error, 'The message could not be sent. Try again.');
      expect(chat.messages, isEmpty);

      api.postError = null;
      chat.retry(p);
      await pumpEventQueue();
      expect(chat.pending, isEmpty);
      expect(chat.messages.single.body, 'Retaking now');
      expect(api.posts, hasLength(2));

      api.postError = const ApiException(code: 'X', message: 'down');
      chat.draftBody = 'second';
      chat.sendDraft();
      await pumpEventQueue();
      chat.discard(chat.pending.single);
      expect(chat.pending, isEmpty);
      chat.dispose();
    });

    test('one picture: the draft keeps its name and size, and goes with the message', () async {
      final api = _M3Api();
      final chat = ChatHub(api).open('s1', myId: 'u1');
      chat.setDraftImage('memory/lane.jpg', 'lane.jpg', 182044);
      expect(chat.draftProblem, isNull); // a picture alone is a message
      chat.sendDraft();
      expect(chat.draftImagePath, isNull);
      expect(chat.pending.single.hasImage, isTrue);
      expect(chat.pending.single.imageSize, 182044);
      await pumpEventQueue();
      expect(api.posts.single.image, 'lane.jpg');
      chat.dispose();
    });
  });

  /* ================================================================ polling and sign out */

  group('polling and sign out', () {
    testWidgets('the poll runs every 15 s only while the screen is in front, and stops at once in the background and on dispose', (tester) async {
      final api = _M3Api();
      api.thread.add(_msg(1, body: 'hello'));
      final hub = ChatHub(api);
      final chat = hub.open('s1', myId: 'u1');
      chat.start();
      await tester.pump();
      expect(chat.polling, isTrue);
      expect(api.unreadCalls, 1);

      await tester.pump(const Duration(seconds: 15)); // another tab: only the unread count
      expect(api.unreadCalls, 2);
      expect(api.listCalls, 0);

      chat.setVisible(true);
      await tester.pump();
      final lists = api.listCalls;
      await tester.pump(const Duration(seconds: 15)); // the Chat tab: the thread
      expect(api.listCalls, lists + 1);

      chat.setForeground(false); // the app went to the background
      expect(chat.polling, isFalse);
      final calls = api.listCalls + api.unreadCalls;
      await tester.pump(const Duration(seconds: 60));
      expect(api.listCalls + api.unreadCalls, calls);

      chat.setForeground(true);
      expect(chat.polling, isTrue);
      await tester.pump();

      chat.dispose();
      expect(chat.polling, isFalse);
      await tester.pump(const Duration(seconds: 60));
      expect(hub.unreadFor('s1'), 0);
    });

    testWidgets('the bell polls every 60 s until stopped', (tester) async {
      final api = _M3Api();
      final c = NotificationsController(api);
      c.startPolling();
      c.startPolling(); // a second start is not a second timer
      await tester.pump(const Duration(seconds: 60));
      expect(api.noteCalls, 1);
      await tester.pump(const Duration(seconds: 60));
      expect(api.noteCalls, 2);
      c.stopPolling();
      await tester.pump(const Duration(seconds: 120));
      expect(api.noteCalls, 2);
      c.dispose();
    });

    test('a picture whose signed link ran out refreshes the thread, at most once per 20 seconds', () async {
      var now = DateTime(2026, 11, 21, 10);
      final api = _M3Api();
      api.thread.add(_msg(1, attachments: [_attachment()]));
      final chat = ShopChatController(api, 's1', myId: 'u1', clock: () => now);
      await chat.load();
      final base = api.listCalls;
      chat.imageFailed();
      chat.imageFailed();
      await pumpEventQueue();
      expect(api.listCalls, base + 1);
      now = now.add(const Duration(seconds: 21));
      chat.imageFailed();
      await pumpEventQueue();
      expect(api.listCalls, base + 2);
      chat.dispose();
    });

    test('sign out stops every timer and clears the chat, the bell and the dashboard; a late answer is dropped', () async {
      SharedPreferences.setMockInitialValues({});
      final rig = _Rig();
      final api = rig.api;
      api.thread.add(_msg(1, body: 'hello'));
      api
        ..unreadCount = 2
        ..noteUnread = 1
        ..noteRows = [_note('n1', 'RECCE_MESSAGE')];
      await rig.services.init();
      await rig.auth.login('siva@x.com', const MpinCredential('4829'), loginRole: 'RECCE');
      await pumpEventQueue();

      final chat = rig.services.chat.open('s1', myId: 'u1')..start();
      chat.setVisible(true);
      await pumpEventQueue();
      rig.services.notifications.startPolling();
      await rig.services.notifications.load();
      await rig.services.dashboard.load();
      expect(chat.polling, isTrue);
      expect(chat.messages, hasLength(1));
      expect(rig.services.notifications.polling, isTrue);
      expect(rig.services.notifications.unread, 1);
      expect(rig.services.dashboard.data, isNotNull);

      // a read that is still on its way when the person signs out
      api.hold = Completer<void>();
      final late = chat.refresh();
      final lateDash = rig.services.dashboard.load();
      await rig.services.signOut();
      api.hold!.complete();
      await late;
      await lateDash;
      await pumpEventQueue();

      expect(chat.polling, isFalse);
      expect(chat.messages, isEmpty);
      expect(chat.loaded, isFalse);
      expect(chat.unread, 0);
      expect(rig.services.chat.unreadFor('s1'), 0);
      expect(rig.services.notifications.polling, isFalse);
      expect(rig.services.notifications.items, isEmpty);
      expect(rig.services.notifications.unread, 0);
      expect(rig.services.notifications.loaded, isFalse);
      expect(rig.services.dashboard.data, isNull);
      expect(rig.services.dashboard.loaded, isFalse);
      expect(rig.shops.loaded, isFalse);
      expect(await chat.refresh(), isNull); // a thread of the old login is not read again
      expect(chat.sendDraft(), isNotNull);

      chat.dispose();
      rig.dispose();
    });

    test('LiveServices.withParts builds the Milestone 3 parts over the api and reads nothing by itself', () async {
      final rig = _Rig();
      await rig.services.init();
      expect(rig.api.noteCalls + rig.api.dashboardCalls + rig.api.listCalls + rig.api.unreadCalls, 0);
      rig.dispose();
    });
  });

  /* ================================================================ screens */

  group('chat tab', () {
    Future<(_Rig, ShopDetailController, ShopChatController)> pumpChat(WidgetTester tester, {ChatImagePicker? picker, VoidCallback? onBoards, bool closed = false, _M3Api? fake}) async {
      _phone(tester);
      final rig = _Rig(fake);
      final shop = ShopDetailController(rig.api, rig.queue, 's1')..detail = ShopDetail.fromJson(_detailJson(closed: closed));
      final chat = rig.services.chat.open('s1', myId: 'u1');
      await chat.load();
      await tester.pumpWidget(rig.host(Scaffold(body: ChatTab(shop: shop, chat: chat, onOpenBoards: onBoards ?? () {}, picker: picker ?? pickChatImage))));
      await tester.pump();
      addTearDown(() {
        chat.dispose();
        shop.dispose();
        rig.dispose();
      });
      return (rig, shop, chat);
    }

    testWidgets('own bubbles on the right, the others on the left with name and role, system cards apart, day headings, refs as chips', (tester) async {
      final api = _M3Api();
      final now = DateTime.now();
      api.thread
        ..add(_msg(1, card: {'title': 'Shop Recce Submitted', 'tone': 'info', 'lines': [{'label': 'Version', 'value': 'V1'}]}, refs: [{'type': 'VERSION', 'id': '1'}], at: now.subtract(const Duration(days: 3))))
        ..add(_msg(2, body: 'Front view is blurry', refs: [{'type': 'PHOTO', 'id': 'p1'}, {'type': 'BOARD', 'id': 'b1'}], at: now.subtract(const Duration(days: 3, minutes: -5))))
        ..add(_msg(3, body: 'Retaking it now', author: 'u1', name: 'Siva', role: 'RECCE_EXECUTIVE', at: now.subtract(const Duration(minutes: 2))))
        ..add(_msg(4, card: _reviewCard(), at: now.subtract(const Duration(minutes: 1))));
      await pumpChat(tester, fake: api);

      expect(find.byKey(ValueKey('card-${_id(1)}')), findsOneWidget);
      expect(find.text('Shop Recce Submitted'), findsOneWidget);
      expect(find.text('Recce Review Update'), findsOneWidget);
      expect(find.text('Rework required'), findsOneWidget); // a line of the card
      expect(find.text('Decision'), findsOneWidget);

      final other = find.descendant(of: find.byKey(ValueKey('msg-${_id(2)}')), matching: find.byType(Container)).first;
      final mine = find.descendant(of: find.byKey(ValueKey('msg-${_id(3)}')), matching: find.byType(Container)).first;
      expect(tester.getRect(other).left, lessThan(24));
      expect(tester.getRect(mine).right, greaterThan(360 - 24));
      expect(find.text('Arvind K.'), findsOneWidget);
      expect(find.text('Operations'), findsOneWidget); // the role of the other side
      expect(find.text('Siva'), findsNothing); // our own name is not repeated on our own bubble

      expect(find.byType(ChatDayChip), findsNWidgets(2));
      expect(find.text('Today'), findsOneWidget);

      expect(find.text('Photo: Front View'), findsOneWidget);
      expect(find.text('Board b1 (GSB 6 x 4 ft)'), findsOneWidget);
      expect(find.text('Version 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a BOARD chip jumps to the Boards tab', (tester) async {
      final api = _M3Api();
      api.thread.add(_msg(1, body: 'About the board', refs: [{'type': 'BOARD', 'id': 'b1'}]));
      var jumped = 0;
      await pumpChat(tester, fake: api, onBoards: () => jumped++);
      await tester.tap(find.byKey(const ValueKey('ref-BOARD:b1')));
      await tester.pump();
      expect(jumped, 1);
    });

    testWidgets('empty, loading and error states', (tester) async {
      await pumpChat(tester);
      expect(find.text('No messages yet'), findsOneWidget);

      // loading
      _phone(tester);
      final api = _M3Api()..hold = Completer<void>();
      final rig = _Rig(api);
      final shop = ShopDetailController(api, rig.queue, 's1')..detail = ShopDetail.fromJson(_detailJson());
      final chat = rig.services.chat.open('s1', myId: 'u1');
      unawaited(chat.load());
      await tester.pumpWidget(rig.host(Scaffold(body: ChatTab(shop: shop, chat: chat, onOpenBoards: () {}))));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // error, then Retry
      api
        ..messagesError = const ApiException(code: 'NETWORK_ERROR', message: 'Cannot reach the server. Check your connection.')
        ..hold!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Cannot reach the server. Check your connection.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      api.messagesError = null;
      api.thread.add(_msg(1, body: 'back again'));
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(find.text('back again'), findsOneWidget);
      chat.dispose();
      shop.dispose();
      rig.dispose();
    });

    testWidgets('Load older appears while there is an older page, adds it above, and disappears at the end', (tester) async {
      final api = _M3Api();
      for (var i = 1; i <= 33; i++) {
        api.thread.add(_msg(i, body: 'message $i', at: DateTime.now().subtract(Duration(minutes: 40 - i))));
      }
      final (_, _, chat) = await pumpChat(tester, fake: api);
      expect(find.byKey(const ValueKey('load-older')), findsOneWidget);
      expect(find.text('message 1'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('load-older')));
      await tester.tap(find.byKey(const ValueKey('load-older')));
      await tester.pump();
      await tester.pump();
      expect(chat.messages, hasLength(33));
      expect(find.byKey(const ValueKey('load-older')), findsNothing);
      expect(find.text('message 1', skipOffstage: false), findsOneWidget);
    });

    testWidgets('pull down reads the thread again; a picture with no link asks for a fresh read', (tester) async {
      final api = _M3Api();
      api.thread.add(_msg(1, body: 'hello', attachments: [_attachment(url: null)]));
      await pumpChat(tester, fake: api);
      expect(find.textContaining('Picture link expired'), findsOneWidget);
      final base = api.listCalls;
      await tester.tap(find.textContaining('Picture link expired'));
      await tester.pump();
      expect(api.listCalls, base + 1);

      api.thread.add(_msg(2, body: 'new one'));
      await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('new one', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the composer: Send is off until there is text or a picture, the box holds 2000 characters, Send puts the message in the thread', (tester) async {
      final api = _M3Api();
      await pumpChat(tester, fake: api);
      IconButton send() => tester.widget<IconButton>(find.byKey(const ValueKey('send-message')));
      expect(send().onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('chat-text')), '   ');
      await tester.pump();
      expect(send().onPressed, isNull); // spaces only

      await tester.enterText(find.byKey(const ValueKey('chat-text')), 'a' * 2300);
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('chat-text'))).controller!.text.length, 2000);
      expect(find.text('2000 / 2000'), findsOneWidget);
      expect(send().onPressed, isNotNull);

      await tester.enterText(find.byKey(const ValueKey('chat-text')), 'Is this board allowed?');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send-message')));
      await tester.pump();
      await tester.pump();
      expect(api.posts.single.body, 'Is this board allowed?');
      expect(find.text('Is this board allowed?'), findsOneWidget); // in the thread now
      expect(tester.widget<TextField>(find.byKey(const ValueKey('chat-text'))).controller!.text, '');
      expect(send().onPressed, isNull);
    });

    testWidgets('a failed send shows the reason with Retry and Discard', (tester) async {
      final api = _M3Api()..postError = const ApiException(code: 'CONFLICT', message: 'The message could not be sent. Try again.', statusCode: 409);
      await pumpChat(tester, fake: api);
      await tester.enterText(find.byKey(const ValueKey('chat-text')), 'hello');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send-message')));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Not sent: The message could not be sent'), findsOneWidget);
      api.postError = null;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Not sent'), findsNothing);
      expect(api.posts, hasLength(2));
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('one picture can be attached, shows as a file row, can be removed, and goes with the message', (tester) async {
      final api = _M3Api();
      Future<XFile?> picker(source) async => XFile.fromData(Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]), name: 'lane.jpg', path: 'memory/lane.jpg');
      await pumpChat(tester, fake: api, picker: picker);
      await tester.tap(find.byKey(const ValueKey('attach-photo')));
      await tester.pumpAndSettle();
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('draft-image')), findsOneWidget);
      expect(find.text('lane.jpg'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('attach-photo'))).onPressed, isNull); // only ONE picture

      await tester.tap(find.byTooltip('Remove')); // the AppFileRow remove button
      await tester.pump();
      expect(find.byKey(const ValueKey('draft-image')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('attach-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('send-message')));
      await tester.pump();
      expect(api.posts.single.image, 'lane.jpg');
    });

    testWidgets('references are picked from the shop (photos, boards, versions), shown as chips, removed again, at most 10', (tester) async {
      final api = _M3Api();
      await pumpChat(tester, fake: api);
      await tester.tap(find.byKey(const ValueKey('attach-ref')));
      await tester.pumpAndSettle();
      expect(find.text('Refer to'), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-PHOTO:p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-BOARD:b1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pick-PHOTO:p1')));
      await tester.tap(find.byKey(const ValueKey('pick-BOARD:b1')));
      await tester.pump();
      expect(find.text('2/10'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('draft-ref-PHOTO:p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('draft-ref-BOARD:b1')), findsOneWidget);

      // a reference alone is not a message
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('send-message'))).onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('chat-text')), 'About these');
      await tester.pump();
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('draft-ref-BOARD:b1')), matching: find.byIcon(Icons.cancel))); // delete icon of the chip
      await tester.pump();
      expect(find.byKey(const ValueKey('draft-ref-BOARD:b1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('send-message')));
      await tester.pump();
      expect(api.posts.single.refs.map((r) => r.key), ['PHOTO:p1']);
    });

    testWidgets('a closed project shows a note instead of the box', (tester) async {
      await pumpChat(tester, closed: true);
      expect(find.byKey(const ValueKey('chat-text')), findsNothing);
      expect(find.text('This project is closed. No more messages.'), findsOneWidget);
    });
  });

  group('shop screen', () {
    testWidgets('five tabs, the Chat tab carries the unread badge, opening it loads the thread, marks it read, hides Save / Submit and keeps the box above the keyboard', (tester) async {
      _phone(tester, height: 2400);
      final api = _M3Api()..unreadCount = 2;
      api.thread
        ..add(_msg(1, card: {'title': 'Shop Recce Submitted', 'tone': 'info', 'lines': []}))
        ..add(_msg(2, body: 'Please retake the front view'));
      final rig = _Rig(api);
      await tester.pumpWidget(rig.host(const LiveShopScreen(siteId: 's1')));
      await tester.pump();
      await tester.pump();
      for (final t in ['Photos', 'Boards', 'Install', 'Review', 'Chat']) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.text('2'), findsOneWidget); // the badge on the Chat tab
      expect(find.text('Save draft'), findsOneWidget);
      expect(api.listCalls, 0); // the thread is read when the tab is opened, not before

      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      expect(api.listCalls, 1);
      expect(api.readCalls, 1);
      expect(find.text('Please retake the front view'), findsOneWidget);
      expect(find.text('Shop Recce Submitted'), findsOneWidget);
      expect(find.text('Save draft'), findsNothing);
      expect(find.byKey(const ValueKey('chat-text')), findsOneWidget);
      expect(find.text('2'), findsNothing); // the badge is gone once read
      expect(tester.takeException(), isNull);

      // the keyboard comes up: the box moves up with it and nothing overflows
      tester.view.viewInsets = const FakeViewPadding(bottom: 900); // 300 logical
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.pump();
      final boxBottom = tester.getBottomLeft(find.byKey(const ValueKey('chat-text'))).dy;
      expect(boxBottom, lessThanOrEqualTo(800 - 300));
      expect(tester.takeException(), isNull);

      // back to another tab: Save / Submit are there again, the thread stops being read
      tester.view.resetViewInsets();
      await tester.pump();
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      expect(find.text('Save draft'), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // the screen goes: its poll stops
      rig.dispose();
    });

    testWidgets('a notification about a message opens the shop on its Chat tab', (tester) async {
      _phone(tester);
      final api = _M3Api()
        ..shopRows = [ShopSummary.fromJson(_shopRow('s1', 'IN_PROGRESS'))]
        ..noteUnread = 1
        ..noteRows = [_note('n1', 'RECCE_MESSAGE', siteId: 's1', title: 'New message: Shop 1')];
      api.thread.add(_msg(1, body: 'Reviewer wrote this'));
      final rig = _Rig(api);
      await rig.shops.load();
      await rig.services.notifications.load();
      await tester.pumpWidget(rig.host(const NotificationsScreen()));
      await tester.pump();
      expect(find.text('New message: Shop 1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notification-n1')));
      await tester.pumpAndSettle();
      expect(find.byType(LiveShopScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-text')), findsOneWidget);
      expect(find.text('Reviewer wrote this'), findsOneWidget);
      expect(rig.services.notifications.unread, 0);
      expect(api.readIds, ['n1']);

      await tester.pumpWidget(const SizedBox());
      rig.dispose();
    });
  });

  group('notifications screen', () {
    testWidgets('the bell shows the unread count; the screen groups by day with type icons, Read all marks everything', (tester) async {
      _phone(tester);
      final api = _M3Api()
        ..noteUnread = 3
        ..noteRows = [
          _note('n1', 'RECCE_MESSAGE', at: DateTime.now(), title: 'New message: Shop 1'),
          _note('n2', 'RECCE_REVIEWED', at: DateTime.now().subtract(const Duration(minutes: 5)), title: 'Rework required'),
          _note('n3', 'SHOPS_ADDED', siteId: null, at: DateTime.now().subtract(const Duration(days: 1)), title: '2 shops added'),
          _note('n4', 'RECCE_SUBMITTED', read: true, at: DateTime.now().subtract(const Duration(days: 5)), title: 'Shop 4 submitted'),
        ];
      final rig = _Rig(api);
      await rig.services.notifications.load();
      await tester.pumpWidget(rig.host(Scaffold(appBar: AppBar(actions: const [NotificationBell()]), body: const SizedBox())));
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bell')));
      await tester.pumpAndSettle();

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('YESTERDAY'), findsOneWidget);
      expect(find.text('New message: Shop 1'), findsOneWidget);
      expect(find.text('2 shops added'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(find.byIcon(Icons.fact_check_outlined), findsOneWidget);
      expect(find.byIcon(Icons.add_business_outlined), findsOneWidget);
      expect(find.byIcon(Icons.upload_file_outlined), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('read-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('read-all')), findsNothing);
      expect(api.readAllCalls, 1);
      expect(rig.services.notifications.unread, 0);
      await tester.pumpWidget(const SizedBox());
      rig.dispose();
    });

    testWidgets('a notification of a shop that is not on the list stays on the screen with a note', (tester) async {
      _phone(tester);
      final api = _M3Api()..noteRows = [_note('n1', 'RECCE_REVIEWED', siteId: 'gone', title: 'Approved')];
      final rig = _Rig(api);
      await rig.services.notifications.load();
      await tester.pumpWidget(rig.host(const NotificationsScreen()));
      await tester.tap(find.byKey(const ValueKey('notification-n1')));
      await tester.pumpAndSettle();
      expect(find.byType(LiveShopScreen), findsNothing);
      expect(find.text('That shop is not on your list any more.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      rig.dispose();
    });

    testWidgets('empty and error states, and pull down reads again', (tester) async {
      _phone(tester);
      final api = _M3Api()..noteError = const ApiException(code: 'NETWORK_ERROR', message: 'Cannot reach the server.');
      final rig = _Rig(api);
      await rig.services.notifications.load();
      await tester.pumpWidget(rig.host(const NotificationsScreen()));
      expect(find.text('Cannot reach the server.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      api.noteError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No notifications yet'), findsOneWidget);

      api.noteRows = [_note('n1', 'RECCE_REVIEWED', title: 'Approved')];
      api.noteUnread = 1;
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Approved'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      rig.dispose();
    });
  });

  group('dashboard screen', () {
    Future<_Rig> pumpDashboard(WidgetTester tester, _M3Api api) async {
      _phone(tester, height: 4200);
      api.shopRows = [ShopSummary.fromJson(_shopRow('s1', 'IN_PROGRESS')), ShopSummary.fromJson(_shopRow('s2', 'REWORK_REQUIRED'))];
      final rig = _Rig(api);
      await rig.shops.load();
      await tester.pumpWidget(rig.host(const LiveDashboardScreen()));
      await tester.pump();
      await tester.pump();
      addTearDown(() async {
        rig.dispose();
      });
      return rig;
    }

    testWidgets('the numbers, the average as days and hours, the rate with one decimal, the note and a bar per project', (tester) async {
      final api = _M3Api()..noteUnread = 2;
      await pumpDashboard(tester, api);
      for (final label in ['Assigned shops', 'Started', 'Submitted', 'Under review', 'Approved', 'Rework', 'Completed', 'Pending', 'Avg. completion', 'Rework rate']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('1 d 2 h'), findsOneWidget); // 26.4 hours
      expect(find.text('0.0%'), findsOneWidget);
      expect(find.text('0 of 1 submitted'), findsOneWidget);
      expect(find.textContaining('Completed = approved by both reviewers on the latest version'), findsOneWidget);
      expect(find.text('Project-wise progress'), findsOneWidget);
      expect(find.text('P-M3'), findsWidgets);
      expect(find.text('P-M3B'), findsOneWidget);
      expect(find.text('Assigned 2'), findsOneWidget);
      expect(find.text('Approved 1'), findsOneWidget);
      expect(find.byType(ProgressBarView), findsNWidgets(2));
      expect(find.byKey(const ValueKey('dashboard-error')), findsNothing);
      expect(api.dashboardCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('when the dashboard cannot be read the shop counts stay, with the reason and a Retry; no endless spinner', (tester) async {
      final api = _M3Api()..dashboardError = const ApiException(code: 'FORBIDDEN', message: 'Not allowed for this login', statusCode: 403);
      await pumpDashboard(tester, api);
      expect(find.byKey(const ValueKey('dashboard-error')), findsOneWidget);
      expect(find.textContaining('Not allowed for this login'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget); // the existing five cards
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Rework'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('Completed = approved'), findsNothing);

      api.dashboardError = null;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('dashboard-error')), findsNothing);
      expect(find.text('Assigned shops'), findsOneWidget);
      expect(find.text('Total'), findsNothing);
      expect(api.dashboardCalls, 2);
    });

    testWidgets('pull down reads the shops and the dashboard again', (tester) async {
      final api = _M3Api();
      await pumpDashboard(tester, api);
      expect(api.dashboardCalls, 1);
      api.dashboardJson = {..._dashboardJson(), 'completed': 7, 'avgCompletionHours': 5.25};
      await tester.fling(find.byType(ListView).first, const Offset(0, 500), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(api.dashboardCalls, 2);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('5.3 h'), findsOneWidget);
    });

    testWidgets('the unread banner shows the total from the one notifications read, and the bell the same count', (tester) async {
      final api = _M3Api()
        ..noteUnread = 3
        ..noteRows = [_note('n1', 'RECCE_MESSAGE', siteId: 's1'), _note('n2', 'RECCE_MESSAGE', siteId: 's2'), _note('n3', 'RECCE_REVIEWED')];
      final rig = await pumpDashboard(tester, api);
      await rig.services.notifications.load();
      await tester.pump();
      expect(find.text('3 unread notifications'), findsOneWidget);
      expect(find.text('2 new messages in your shops'), findsOneWidget);
      expect(find.byKey(const ValueKey('bell')), findsOneWidget);
      // the attention list shows the unread messages of a shop with rework, from what is already in memory
      expect(find.byKey(const ValueKey('unread-chat')), findsOneWidget);
    });

    testWidgets('KpiCard and the project card show their numbers', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView(children: [
            SizedBox(height: 110, child: KpiCard('Completed', '5', Icons.task_alt, Colors.green, subtitle: 'all reviewers', onTap: () {})),
            ProjectProgressCard(project: ProjectProgress.fromJson(const {'projectCode': 'P-1', 'projectName': 'Name', 'assigned': 4, 'started': 3, 'submitted': 2, 'approved': 1, 'rework': 1, 'pending': 3}), onTap: () {}),
          ]),
        ),
      ));
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      for (final t in ['Assigned 4', 'Started 3', 'Submitted 2', 'Approved 1', 'Rework 1', 'Pending 3']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });
  });

  test('formatter helpers: time, day label', () {
    expect(fmtTime(DateTime(2026, 11, 21, 16, 5)), '4:05 PM');
    expect(fmtTime(DateTime(2026, 11, 21, 0, 7)), '12:07 AM');
    final now = DateTime(2026, 11, 21, 1);
    expect(fmtDayLabel(DateTime(2026, 11, 21, 23), now), 'Today');
    expect(fmtDayLabel(DateTime(2026, 11, 20, 23, 59), now), 'Yesterday');
    expect(fmtDayLabel(DateTime(2026, 11, 19, 12), now), '19 Nov 2026');
  });
}
