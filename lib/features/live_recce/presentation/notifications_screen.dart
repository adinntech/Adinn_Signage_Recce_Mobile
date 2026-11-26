import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/notifications_controller.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';
import '../bridge/live_saran_shop_screen.dart';
import 'live_shop_screen.dart';
import 'live_widgets.dart';

/// The bell in the top bar of the home screens: the unread count, and a tap opens the notifications.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.select<NotificationsController, int>((c) => c.unread);
    return IconButton(
      key: const ValueKey('bell'),
      tooltip: unread > 0 ? 'Notifications, $unread unread' : 'Notifications',
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen())),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

Color notificationColor(NotificationType t) => switch (t) {
      NotificationType.recceSubmitted => AdinnColors.info,
      NotificationType.recceReviewed => AdinnColors.purple,
      NotificationType.recceMessage => AdinnColors.red,
      NotificationType.shopsAdded => AdinnColors.success,
      NotificationType.other => AdinnColors.muted,
    };

/// What the bell holds, grouped by day. A tap marks the item read and opens its shop (a message opens the Chat tab, a review the
/// Review tab) when the shop is on this login's list.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  Future<void> _open(BuildContext context, AppNotification n) async {
    final notes = context.read<NotificationsController>();
    final shops = context.read<ShopListController>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    notes.markRead(n.id); // the badge drops at once; the call goes on in the background
    final siteId = n.siteId;
    if (siteId == null) return;
    var known = shops.shops.any((s) => s.siteId == siteId);
    if (!known) {
      await shops.load(silent: true); // a shop that was just given to this login is not in the list yet
      known = shops.shops.any((s) => s.siteId == siteId);
    }
    if (!known) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('That shop is not on your list any more.')));
      return;
    }
    final int? tab = switch (n.kind) {
      NotificationType.recceMessage => ShopTab.chat,
      NotificationType.recceReviewed => ShopTab.review,
      _ => null, // the shop opens on the step the person is at
    };
    navigator.push(MaterialPageRoute<void>(builder: (_) => tab == null ? LiveSaranShopScreen(siteId: siteId) : LiveShopScreen(siteId: siteId, initialTab: tab)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<NotificationsController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [if (c.unread > 0) TextButton(key: const ValueKey('read-all'), onPressed: c.markAllRead, child: const Text('Read all'))],
      ),
      body: _body(context, c),
    );
  }

  Widget _body(BuildContext context, NotificationsController c) {
    if (!c.loaded && c.loading) return const Center(child: CircularProgressIndicator());
    if (!c.loaded && c.error != null) return ErrorRetry(message: c.error!, onRetry: c.load);
    if (!c.loaded) {
      // never opened before the first read finished: read now
      WidgetsBinding.instance.addPostFrameCallback((_) => c.load());
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: c.load,
      color: AdinnColors.red,
      child: c.items.isEmpty
          ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
              SizedBox(height: 60),
              EmptyState(icon: Icons.notifications_off_outlined, title: 'No notifications yet', message: 'New shops, submissions, review decisions and messages show up here.'),
            ])
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (c.error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: IssueList(items: [c.error!])),
                for (final day in groupNotificationsByDay(c.items)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Text(day.label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AdinnColors.muted, letterSpacing: 0.6)),
                  ),
                  for (final n in day.items) NotificationTile(item: n, onTap: () => _open(context, n)),
                ],
              ],
            ),
    );
  }
}

class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = notificationColor(item.kind);
    return Material(
      color: item.read ? Colors.white : AdinnColors.redLight.withValues(alpha: 0.6),
      child: InkWell(
        key: ValueKey('notification-${item.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 20, backgroundColor: color.withValues(alpha: 0.12), child: Icon(item.kind.icon, color: color, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: item.read ? FontWeight.w600 : FontWeight.w800))),
                      if (item.at != null) Text(fmtTime(item.at!), style: const TextStyle(fontSize: 12, color: AdinnColors.muted)),
                    ]),
                    if (item.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(item.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                    if (item.projectCode.isNotEmpty || item.hasShop)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(spacing: 6, children: [
                          if (item.projectCode.isNotEmpty) TagChip(item.projectCode, icon: Icons.folder_open_outlined),
                          if (item.hasShop) const TagChip('Opens the shop', icon: Icons.storefront_outlined),
                        ]),
                      ),
                  ],
                ),
              ),
              if (!item.read)
                const Padding(padding: EdgeInsets.only(left: 8, top: 6), child: Icon(Icons.circle, size: 10, color: AdinnColors.red)),
            ],
          ),
        ),
      ),
    );
  }
}
