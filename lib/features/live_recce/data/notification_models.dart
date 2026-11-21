part of 'recce_models.dart';

/// Milestone 3 models: the bell. Contract: `GET /notifications` -> `{unread, items[]}` (backend notification.service.ts `toItem`).
/// `type` is the stored kind; `siteId` is the shop to open (null when the event is not about one shop). `path` is a web path and is
/// not used here.

enum NotificationType {
  recceSubmitted('RECCE_SUBMITTED', Icons.upload_file_outlined),
  recceReviewed('RECCE_REVIEWED', Icons.fact_check_outlined),
  recceMessage('RECCE_MESSAGE', Icons.chat_bubble_outline),
  shopsAdded('SHOPS_ADDED', Icons.add_business_outlined),
  other('', Icons.notifications_none);

  const NotificationType(this.code, this.icon);
  final String code;
  final IconData icon;

  static NotificationType parse(String? code) {
    for (final t in values) {
      if (t.code.isNotEmpty && t.code == code) return t;
    }
    return other;
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    this.type = '',
    this.title = '',
    this.text = '',
    this.at,
    this.projectId = '',
    this.projectCode = '',
    this.siteId,
    this.read = false,
  });

  final String id;

  /// RECCE_SUBMITTED | RECCE_REVIEWED | RECCE_MESSAGE | SHOPS_ADDED | ...
  final String type;
  final String title;
  final String text;

  /// Local time (the server sends UTC); null when the server sent none.
  final DateTime? at;
  final String projectId;
  final String projectCode;
  final String? siteId;
  final bool read;

  NotificationType get kind => NotificationType.parse(type);
  bool get isMessage => kind == NotificationType.recceMessage;
  bool get hasShop => siteId != null;

  AppNotification asRead() => AppNotification(id: id, type: type, title: title, text: text, at: at, projectId: projectId, projectCode: projectCode, siteId: siteId, read: true);

  factory AppNotification.fromJson(Json j) => AppNotification(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        text: (j['text'] ?? '').toString(),
        at: _dt(j['at']),
        projectId: (j['projectId'] ?? '').toString(),
        projectCode: (j['projectCode'] ?? '').toString(),
        siteId: _s(j['siteId']),
        read: j['read'] == true,
      );
}

/// One answer of `GET /notifications`: the newest items and the total unread count (which can be larger than the list).
class NotificationFeed {
  const NotificationFeed({this.items = const [], this.unread = 0});

  final List<AppNotification> items;
  final int unread;

  factory NotificationFeed.fromEnvelope(dynamic body) {
    final data = _m(body is Map ? body['data'] : null);
    final items = [
      for (final e in _ml(data['items']))
        if (_s(e['id']) != null) AppNotification.fromJson(e),
    ];
    final unread = _i(data['unread'], items.where((n) => !n.read).length);
    return NotificationFeed(items: items, unread: unread < 0 ? 0 : unread);
  }
}
