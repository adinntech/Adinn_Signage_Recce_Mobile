import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';
import 'recce_api.dart';
import 'recce_controllers.dart' show errorText;
import 'recce_models.dart';

/// The notifications of one calendar day, newest first (the order the server sends).
class NotificationDay {
  const NotificationDay(this.label, this.items);
  final String label;
  final List<AppNotification> items;
}

/// Groups [items] (newest first) under "Today", "Yesterday" and then one heading per date. An item with no time goes last under
/// "Earlier". Days are the device's local days.
List<NotificationDay> groupNotificationsByDay(List<AppNotification> items, {DateTime? now}) {
  final labels = <String>[];
  final buckets = <List<AppNotification>>[];
  final undated = <AppNotification>[];
  String? lastKey;
  for (final n in items) {
    final at = n.at;
    if (at == null) {
      undated.add(n);
      continue;
    }
    final d = at.toLocal();
    final key = '${d.year}-${d.month}-${d.day}';
    if (key != lastKey) {
      labels.add(fmtDayLabel(d, now));
      buckets.add([n]);
      lastKey = key;
    } else {
      buckets.last.add(n);
    }
  }
  if (undated.isNotEmpty) {
    labels.add('Earlier');
    buckets.add(undated);
  }
  return [for (var i = 0; i < labels.length; i++) NotificationDay(labels[i], buckets[i])];
}

/// The bell: the newest notifications and the unread total. The total is refreshed about every minute while the home screen is in
/// front ([startPolling] / [stopPolling]); no live stream is used.
class NotificationsController extends ChangeNotifier {
  NotificationsController(this._api, {this.pollEvery = pollInterval});

  static const pollInterval = Duration(seconds: 60);

  final RecceApi _api;
  final Duration pollEvery;

  /// Called when a poll brings a new "shops added" notification, so the shop list is read again.
  VoidCallback? onNewShops;

  List<AppNotification> items = const [];
  int unread = 0;
  bool loading = false;
  bool loaded = false;
  String? error;

  Timer? _timer;
  final Set<String> _seen = {};
  var _first = true;
  var _gen = 0;
  var _disposed = false;

  bool get polling => _timer != null;

  /// Unread "new message" notifications of one shop (the count shown on its row).
  int unreadMessagesFor(String siteId) => items.where((n) => !n.read && n.isMessage && n.siteId == siteId).length;

  /// Unread "new message" notifications of all shops.
  int get unreadMessages => items.where((n) => !n.read && n.isMessage).length;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Reads the list. A silent read (the poll) keeps what is shown when it fails.
  Future<void> load({bool silent = false}) async {
    if (loading || _disposed) return;
    final gen = ++_gen;
    loading = true;
    if (!silent) {
      error = null;
      _notify();
    }
    try {
      final feed = await _api.notifications();
      if (gen != _gen || _disposed) return; // reset() happened while the answer was on its way
      final fresh = _first ? const <AppNotification>[] : [for (final n in feed.items) if (!n.read && !_seen.contains(n.id)) n];
      _seen.addAll(feed.items.map((n) => n.id));
      _first = false;
      items = feed.items;
      unread = feed.unread;
      error = null;
      loaded = true;
      if (fresh.any((n) => n.kind == NotificationType.shopsAdded)) onNewShops?.call();
    } catch (e) {
      if (gen == _gen && (!silent || !loaded)) error = errorText(e);
    } finally {
      if (gen == _gen) {
        loading = false;
        _notify();
      }
    }
  }

  /// Marks one notification read at once (the badge drops) and tells the server; a failed call is not shown, the next read sets it right.
  Future<void> markRead(String id) async {
    final i = items.indexWhere((n) => n.id == id);
    if (i < 0 || items[i].read) return;
    items = [for (final n in items) n.id == id ? n.asRead() : n];
    unread = unread > 0 ? unread - 1 : 0;
    _notify();
    try {
      await _api.markNotificationRead(id);
    } catch (_) {
      // it stays read on the phone; the next read of the list shows what the server has
    }
  }

  Future<void> markAllRead() async {
    items = [for (final n in items) n.asRead()];
    unread = 0;
    _notify();
    try {
      await _api.markAllNotificationsRead();
    } catch (_) {
      // see markRead
    }
  }

  /// The thread of a shop was read: its message notifications are read on the server too, so they are read here (no call).
  void markSiteMessagesRead(String siteId) {
    final flipped = items.where((n) => !n.read && n.isMessage && n.siteId == siteId).length;
    if (flipped == 0) return;
    items = [for (final n in items) !n.read && n.isMessage && n.siteId == siteId ? n.asRead() : n];
    unread = unread >= flipped ? unread - flipped : 0;
    _notify();
  }

  void startPolling() {
    if (_disposed) return;
    _timer ??= Timer.periodic(pollEvery, (_) => unawaited(load(silent: true)));
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  /// Sign out: the timer stops, the list and the count are dropped, a read that is still on its way is ignored.
  void reset() {
    stopPolling();
    _gen++;
    items = const [];
    unread = 0;
    loading = false;
    loaded = false;
    error = null;
    _first = true;
    _seen.clear();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }
}
