import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/token_manager.dart';
import '../../../core/storage/session_store.dart';
import '../../live_auth/data/auth_repository.dart';
import '../../live_auth/presentation/live_auth_controller.dart';
import 'catalog_controller.dart';
import 'chat_controller.dart';
import 'dashboard_controller.dart';
import 'notifications_controller.dart';
import 'recce_api.dart';
import 'recce_controllers.dart';
import 'upload_queue.dart';

/// Wires the live backend: Dio + token refresh, auth, recce API, upload queue, the shop list, and the Milestone 3 parts (shop chats,
/// field dashboard, notifications). Created once in `main()` and handed to [AdinnRecceApp]; widget tests simply do not create it.
class LiveServices {
  LiveServices._({
    required this.auth,
    required this.api,
    required this.queue,
    required this.shops,
    required this.chat,
    required this.dashboard,
    required this.notifications,
    required this.catalog,
  }) {
    // The thread read in a shop also reads that shop's message notifications; new "shops added" news reads the shop list again.
    chat.onThreadRead ??= notifications.markSiteMessagesRead;
    notifications.onNewShops ??= () => shops.load(silent: true);
  }

  factory LiveServices.create({SessionStore? store}) {
    final session = store ?? SecureSessionStore();
    final tokens = TokenManager(refreshDio: createPlainDio(), store: session);
    final repo = AuthRepository(plainDio: createPlainDio(), tokens: tokens, store: session);
    final api = RecceApi(createAuthedDio(tokens));
    final queue = UploadQueue(api);
    return LiveServices.withParts(auth: LiveAuthController(repo), api: api, queue: queue, shops: ShopListController(api, queue));
  }

  /// The same wiring with parts you provide (tests use fakes: no network, no secure storage). The Milestone 3 parts are built over
  /// [api] when not given; none of them reads anything until a screen asks.
  @visibleForTesting
  LiveServices.withParts({
    required LiveAuthController auth,
    required RecceApi api,
    required UploadQueue queue,
    required ShopListController shops,
    ChatHub? chat,
    FieldDashboardController? dashboard,
    NotificationsController? notifications,
    CatalogController? catalog,
  }) : this._(
          auth: auth,
          api: api,
          queue: queue,
          shops: shops,
          chat: chat ?? ChatHub(api),
          dashboard: dashboard ?? FieldDashboardController(api),
          notifications: notifications ?? NotificationsController(api),
          catalog: catalog ?? CatalogController(api),
        );

  final LiveAuthController auth;
  final RecceApi api;
  final UploadQueue queue;
  final ShopListController shops;

  /// Open shop threads and their unread counts.
  final ChatHub chat;
  final FieldDashboardController dashboard;
  final NotificationsController notifications;

  /// The media catalog (media types, installation methods, site questions): the server's copy, saved on the phone, with the copy
  /// built into the app as the last resort. Not tied to a person, so it survives a sign out.
  final CatalogController catalog;

  static const _lastUserKey = 'live_last_user_id';
  String? _lastUser;

  /// The signed-in id whose shops this session already loaded; null while signed out. It is set before any await, so
  /// the many auth notifications of one session (busy, error, ...) can never start a second load.
  String? _activeUser;

  /// Restores the session and the saved upload queue. Never throws.
  Future<void> init() async {
    auth.addListener(_onAuth);
    await auth.restore();
    await queue.load();
    await catalog.init();
  }

  Future<void> _onAuth() async {
    final id = auth.user?.id;
    if (id == null) {
      _activeUser = null; // signed out or expired: the next sign in (even the same person) loads the shops again
      clearLive();
      return;
    }
    if (id == _activeUser) return; // same session, only a status change (busy, error ...)
    _activeUser = id;
    // A different person signed in: photos waiting for the previous login must never go to this one.
    try {
      final prefs = await SharedPreferences.getInstance();
      final previous = _lastUser ?? prefs.getString(_lastUserKey);
      if (previous != null && previous != id) await queue.clearAll();
      await prefs.setString(_lastUserKey, id);
    } catch (_) {
      // storage unavailable: keep going
    }
    _lastUser = id;
    unawaited(catalog.refresh()); // the admin may have changed it since the last sign in
    // The administrator has no shops (the phone shows only the Media catalog for that login), so nothing is read for them.
    if (_activeUser == id && auth.user?.isAdmin != true) shops.load(); // skipped when the person signed out while the queue was being cleared
  }

  /// Everything of the signed-in person is dropped: shops, open chats (their timers stop), unread counts, dashboard numbers and
  /// notifications (the poll stops). Safe to call twice.
  void clearLive() {
    shops.reset();
    chat.reset();
    dashboard.reset();
    notifications.reset();
  }

  /// Explicit sign out: the queue is emptied (the screen asks first when photos are still waiting).
  Future<void> signOut() async {
    clearLive();
    await queue.clearAll();
    await auth.logout();
  }
}
