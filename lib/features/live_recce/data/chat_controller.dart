import 'dart:async';
import 'dart:math' show max;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';

import 'notifications_controller.dart';
import 'recce_api.dart';
import 'recce_controllers.dart' show errorText;
import 'recce_models.dart';

/// Where a message we are sending stands. A sent message leaves this list and comes back from the server as a [ChatMessage].
enum ChatSendState { sending, failed }

/// A message on its way to the server: shown as the person's own bubble with its state, and kept when sending failed so the
/// person can retry (nothing disappears silently).
class PendingChatMessage {
  PendingChatMessage({required this.localId, required this.body, this.refs = const [], this.imagePath, this.imageName, this.imageSize, required this.createdAt});

  final String localId;
  final String body;
  final List<ChatRef> refs;
  final String? imagePath;
  final String? imageName;
  final int? imageSize;
  final DateTime createdAt;

  ChatSendState state = ChatSendState.sending;
  double progress = 0;
  String? error;
  CancelToken? _cancel;

  bool get hasImage => imagePath != null;
  bool get failed => state == ChatSendState.failed;
}

/// Knows every open shop thread: the unread counts that were read (for the shop rows), and the open controllers, so a sign out can
/// stop every timer and drop every message.
class ChatHub extends ChangeNotifier {
  ChatHub(this._api, {this.onThreadRead});

  final RecceApi _api;

  /// Called when a thread was marked read, so the bell's message count for that shop drops with it.
  void Function(String siteId)? onThreadRead;

  final Map<String, int> _unread = {};
  final Set<ShopChatController> _open = {};
  var _disposed = false;

  /// The unread messages of a shop, as far as we have read them (0 when we never asked: no extra call is made per shop).
  int unreadFor(String siteId) => _unread[siteId] ?? 0;

  /// The thread of one shop. The shop screen owns it and disposes it.
  ShopChatController open(String siteId, {required String myId, Duration pollEvery = ShopChatController.pollInterval}) {
    final c = ShopChatController(_api, siteId, myId: myId, hub: this, pollEvery: pollEvery);
    _open.add(c);
    return c;
  }

  void _setUnread(String siteId, int n) {
    final v = n < 0 ? 0 : n;
    if (_unread[siteId] == v) return;
    _unread[siteId] = v;
    _notify();
  }

  void _read(String siteId) {
    _setUnread(siteId, 0);
    onThreadRead?.call(siteId);
  }

  void _closed(ShopChatController c) => _open.remove(c);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Sign out: every open thread stops and is emptied, every remembered count is dropped.
  void reset() {
    for (final c in _open.toList()) {
      c.shutdown();
    }
    _unread.clear();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The unread messages to show on a shop row: what the thread itself reported, or the bell's unread message notifications of that
/// shop, whichever is larger. Both are already in memory, so a list of shops makes no extra call.
int shopUnreadCount(ChatHub chat, NotificationsController notes, String siteId) => max(chat.unreadFor(siteId), notes.unreadMessagesFor(siteId));

/// The communication thread of ONE shop (`GET/POST /recce/shops/:siteId/messages`): newest page first, "Load older", a light poll
/// while the screen is in front, sending with progress and retry, and the unread count / mark-read calls.
class ShopChatController extends ChangeNotifier {
  ShopChatController(this._api, this.siteId, {required this.myId, this.hub, DateTime Function()? clock, this.pollEvery = pollInterval}) : _clock = clock ?? DateTime.now;

  /// How often the thread (chat tab in front) or only its unread count (another tab) is read while the screen is in front.
  static const pollInterval = Duration(seconds: 15);
  static const _imageRefreshGap = Duration(seconds: 20);

  final RecceApi _api;
  final ChatHub? hub;
  final DateTime Function() _clock;
  final String siteId;

  /// The signed-in person: own messages sit on the right.
  final String myId;
  final Duration pollEvery;

  /// Messages we hold, oldest first (a page is newest first on the wire).
  List<ChatMessage> messages = const [];
  final List<PendingChatMessage> _pending = [];
  bool loading = false;
  bool loaded = false;
  String? error;
  bool loadingOlder = false;
  String? olderError;
  int unread = 0;

  String? _nextBefore;
  Timer? _timer;
  var _visible = false;
  var _foreground = false;
  var _refreshing = false;
  var _marking = false;
  var _stopped = false;
  var _disposed = false;
  var _gen = 0;
  DateTime? _lastImageRefresh;

  /// What the composer holds. It lives here, so a draft survives a change of tab.
  String draftBody = '';
  List<ChatRef> draftRefs = [];
  String? draftImagePath;
  String? draftImageName;
  int? draftImageSize;

  bool get hasMore => _nextBefore != null;
  List<PendingChatMessage> get pending => List.unmodifiable(_pending);
  bool get polling => _timer != null;

  bool _stale(int gen) => _disposed || gen != _gen;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /* -------------------------------------------------------------- life */

  /// The shop screen is in front: read the unread count and start the poll.
  void start() {
    if (_stopped || _disposed) return;
    _foreground = true;
    _syncTimer();
    unawaited(loadUnread());
  }

  /// The chat tab is (not) the tab in front. Showing it reads the thread and marks it read.
  void setVisible(bool v) {
    if (_stopped || _disposed || _visible == v) return;
    _visible = v;
    if (v) unawaited(loaded ? refresh(markRead: true) : load());
  }

  /// The app went to the background (false) or came back (true). Nothing polls in the background.
  void setForeground(bool v) {
    if (_stopped || _disposed || _foreground == v) return;
    _foreground = v;
    _syncTimer();
    if (v) unawaited(_visible && loaded ? refresh() : loadUnread());
  }

  void _syncTimer() {
    if (_foreground && !_stopped && !_disposed) {
      _timer ??= Timer.periodic(pollEvery, (_) => unawaited(tick()));
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// What one poll does: the newest page while the chat tab is in front, only the unread count otherwise.
  @visibleForTesting
  Future<void> tick() => _visible ? refresh() : loadUnread();

  /// Sign out: stop everything, drop every message and every unsent draft. The controller is not used again.
  void shutdown() {
    _stopped = true;
    _gen++;
    _timer?.cancel();
    _timer = null;
    for (final p in _pending) {
      p._cancel?.cancel('signed out');
    }
    _pending.clear();
    messages = const [];
    _nextBefore = null;
    loading = loadingOlder = loaded = false;
    error = olderError = null;
    unread = 0;
    draftBody = '';
    draftRefs = [];
    draftImagePath = draftImageName = null;
    draftImageSize = null;
    _notify();
  }

  /* -------------------------------------------------------------- read */

  Future<void> loadUnread() async {
    if (_stopped || _disposed) return;
    final gen = _gen;
    try {
      final n = await _api.messagesUnread(siteId);
      if (_stale(gen)) return;
      unread = n;
      hub?._setUnread(siteId, n);
      _notify();
    } catch (_) {
      // a badge only: the next poll tries again
    }
  }

  /// The first page of the thread (the newest [chatPageSize] messages).
  Future<void> load() async {
    if (_stopped || _disposed || loading) return;
    final gen = _gen;
    loading = true;
    error = null;
    _notify();
    try {
      final page = await _api.messages(siteId, limit: chatPageSize);
      if (_stale(gen)) return;
      messages = mergeLatest(messages, page);
      _nextBefore = page.nextBefore;
      loaded = true;
      if (_visible) unawaited(markRead());
    } catch (e) {
      if (!_stale(gen)) error = errorText(e);
    } finally {
      if (!_stale(gen)) {
        loading = false;
        _notify();
      }
    }
  }

  /// The newest page again: the poll, the pull-to-refresh and the answer to a picture whose signed link ran out all use this. New
  /// messages join, older ones we loaded stay, and the pictures get fresh links. Returns the error text, or null.
  Future<String?> refresh({bool markRead = false}) async {
    if (_stopped || _disposed) return null;
    if (!loaded) {
      await load();
      return error;
    }
    if (_refreshing) return null;
    _refreshing = true;
    final gen = _gen;
    try {
      final page = await _api.messages(siteId, limit: chatPageSize);
      if (_stale(gen)) return null;
      final known = {for (final m in messages) m.id};
      messages = mergeLatest(messages, page);
      if (!page.hasMore) _nextBefore = null; // the page holds the whole thread
      final fromOthers = messages.any((m) => !known.contains(m.id) && !m.isMine(myId));
      if (_visible && (markRead || fromOthers || unread > 0)) unawaited(this.markRead());
      _notify();
      return null;
    } catch (e) {
      return _stale(gen) ? null : errorText(e);
    } finally {
      _refreshing = false;
    }
  }

  /// The next, older page ("Load older").
  Future<void> loadOlder() async {
    final cursor = _nextBefore;
    if (cursor == null || loadingOlder || _stopped || _disposed) return;
    final gen = _gen;
    loadingOlder = true;
    olderError = null;
    _notify();
    try {
      final page = await _api.messages(siteId, limit: chatPageSize, before: cursor);
      if (_stale(gen)) return;
      messages = mergeOlder(messages, page);
      _nextBefore = page.nextBefore;
    } catch (e) {
      if (!_stale(gen)) olderError = errorText(e);
    } finally {
      if (!_stale(gen)) {
        loadingOlder = false;
        _notify();
      }
    }
  }

  /// The thread was read by the person: the server clears the count (and this shop's message notifications).
  Future<void> markRead() async {
    if (_stopped || _disposed || _marking) return;
    _marking = true;
    final gen = _gen;
    try {
      await _api.markMessagesRead(siteId);
      if (_stale(gen)) return;
      unread = 0;
      hub?._read(siteId);
      _notify();
    } catch (_) {
      // tried again at the next poll or the next time the tab is opened
    } finally {
      _marking = false;
    }
  }

  /// A picture failed to load (an expired signed link is the usual reason): read the thread again, at most once per 20 seconds.
  void imageFailed() {
    if (_stopped || _disposed || !loaded) return;
    final now = _clock();
    final last = _lastImageRefresh;
    if (last != null && now.difference(last) < _imageRefreshGap) return;
    _lastImageRefresh = now;
    unawaited(refresh());
  }

  /// True when a picture of the thread has a link that has run out (or none), so a fresh read is due.
  bool get linksExpired {
    final now = _clock();
    return messages.any((m) => m.hasExpiredLinks(now));
  }

  /* -------------------------------------------------------------- draft */

  void setDraftRefs(Iterable<ChatRef> refs) {
    draftRefs = uniqueRefs(refs).take(maxChatRefs).toList();
    _notify();
  }

  void setDraftImage(String path, String name, int? size) {
    draftImagePath = path;
    draftImageName = name;
    draftImageSize = size;
    _notify();
  }

  void clearDraftImage() {
    draftImagePath = draftImageName = null;
    draftImageSize = null;
    _notify();
  }

  /// Why the draft cannot be sent, or null.
  String? get draftProblem => validateChatDraft(body: draftBody, refs: draftRefs, hasImage: draftImagePath != null);

  /* -------------------------------------------------------------- send */

  /// Sends the draft. Returns why it cannot be sent (nothing is sent then), or null when it is on its way.
  String? sendDraft() {
    final problem = draftProblem;
    if (problem != null || _stopped || _disposed) return problem ?? 'Sign in again to send messages.';
    final p = PendingChatMessage(
      localId: newClientId(),
      body: draftBody.trim(),
      refs: uniqueRefs(draftRefs),
      imagePath: draftImagePath,
      imageName: draftImageName,
      imageSize: draftImageSize,
      createdAt: _clock(),
    );
    draftBody = '';
    draftRefs = [];
    draftImagePath = draftImageName = null;
    draftImageSize = null;
    _pending.add(p);
    _notify();
    unawaited(_post(p));
    return null;
  }

  Future<void> _post(PendingChatMessage p) async {
    final gen = _gen;
    p
      ..state = ChatSendState.sending
      ..error = null
      ..progress = 0
      .._cancel = CancelToken();
    _notify();
    try {
      final sent = await _api.postMessage(
        siteId,
        body: p.body,
        refs: p.refs,
        imagePath: p.imagePath,
        imageName: p.imageName,
        cancel: p._cancel,
        onProgress: (v) {
          p.progress = v;
          _notify();
        },
      );
      if (_stale(gen) || !_pending.contains(p)) return;
      _pending.remove(p);
      messages = withSent(messages, sent);
    } catch (e) {
      if (_stale(gen) || !_pending.contains(p)) return; // discarded or signed out meanwhile
      p
        ..state = ChatSendState.failed
        ..error = errorText(e);
    } finally {
      _notify();
    }
  }

  /// Sends a failed message again.
  void retry(PendingChatMessage p) {
    if (_stopped || _disposed || !_pending.contains(p) || !p.failed) return;
    unawaited(_post(p));
  }

  /// Drops a message that is sending (the upload is cancelled) or failed.
  void discard(PendingChatMessage p) {
    if (!_pending.remove(p)) return;
    p._cancel?.cancel('discarded');
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    for (final p in _pending) {
      p._cancel?.cancel('closed');
    }
    hub?._closed(this);
    super.dispose();
  }
}
