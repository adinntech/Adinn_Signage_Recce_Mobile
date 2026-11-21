import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_file_row.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/chat_controller.dart';
import '../data/live_services.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';
import 'chat_bubbles.dart';
import 'chat_composer.dart';
import 'live_widgets.dart';
import 'rework_sheet.dart';
import 'version_compare_screen.dart';
import 'versions_section.dart';

/// Chat: the communication thread of this shop between the field person and the reviewers. System cards (submitted, reviewed,
/// rework asked, reopened) and people's messages in one list, oldest at the top, "Load older" above, pull down to read again.
class ChatTab extends StatefulWidget {
  const ChatTab({super.key, required this.shop, required this.chat, required this.onOpenBoards, this.picker = pickChatImage});

  final ShopDetailController shop;
  final ShopChatController chat;

  /// A BOARD reference was tapped: the shop screen shows its Boards tab.
  final VoidCallback onOpenBoards;
  final ChatImagePicker picker;

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _scroll = ScrollController();
  var _nearBottom = true;
  var _wasLoaded = false;
  String _tail = '';

  ShopChatController get chat => widget.chat;

  @override
  void initState() {
    super.initState();
    _wasLoaded = chat.loaded;
    _tail = _tailOf();
    chat.addListener(_onChat);
    if (chat.loaded) _toEnd(animate: false);
  }

  @override
  void dispose() {
    chat.removeListener(_onChat);
    _scroll.dispose();
    super.dispose();
  }

  String _tailOf() => '${chat.messages.isEmpty ? '' : chat.messages.last.id}|${chat.pending.length}';

  /// The thread got something new at its end (a message of the other side, or our own): stay at the bottom when we were there.
  void _onChat() {
    final tail = _tailOf();
    final justLoaded = chat.loaded && !_wasLoaded;
    _wasLoaded = chat.loaded;
    final grew = tail != _tail;
    _tail = tail;
    if (justLoaded) {
      _toEnd(animate: false);
    } else if (grew && (_nearBottom || chat.pending.isNotEmpty)) {
      _toEnd();
    }
  }

  void _toEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(end, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(end);
      }
    });
  }

  /// Older messages are added ABOVE what is on screen: keep the same message under the thumb.
  Future<void> _loadOlder() async {
    final had = _scroll.hasClients;
    final before = had ? _scroll.position.maxScrollExtent : 0.0;
    final offset = had ? _scroll.position.pixels : 0.0;
    await chat.loadOlder();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || !had) return;
      _scroll.jumpTo(offset + (_scroll.position.maxScrollExtent - before));
    });
  }

  Future<void> _refresh() async {
    final err = await chat.refresh(markRead: true);
    if (err != null && mounted) showSnack(context, err, error: true);
  }

  /* -------------------------------------------------------------- references */

  Future<void> _openRef(ChatRef r) async {
    switch (r.type) {
      case ChatRefType.board:
        widget.onOpenBoards();
      case ChatRefType.photo:
        await _openPhoto(r.id);
      case ChatRefType.version:
        await _openVersion(int.tryParse(r.id) ?? 0);
    }
  }

  Future<void> _openPhoto(String id) async {
    final shop = widget.shop;
    if (shop.urlsStale) await shop.refreshAll(); // the photo links of an old read may have run out
    if (!mounted) return;
    final live = shop.detail?.photos.where((p) => p.id == id).firstOrNull;
    ShopPhoto? photo = live;
    for (final v in shop.versionList) {
      photo ??= v.photos.where((p) => p.id == id).firstOrNull; // a photo of an earlier version
    }
    if (photo == null) return showSnack(context, 'This photo is not on the shop any more.');
    if (live != null && live.needsRework) return showReworkSheet(context, ctrl: shop, photo: live);
    final url = photo.displayUrl;
    if (url == null) return showSnack(context, 'This photo has no picture link. Pull down to refresh.', error: true);
    final title = shop.detail?.categoryLabel(photo.category) ?? photoCategoryLabel(photo.category);
    await showAppPhotoViewer(context, title: title, url: url);
  }

  Future<void> _openVersion(int n) async {
    final shop = widget.shop;
    if (shop.versionList.isEmpty) await shop.loadVersions(force: true);
    if (!mounted) return;
    final v = shop.versionList.where((x) => x.version == n).firstOrNull;
    if (v == null) return showSnack(context, 'Version $n details are not available.', error: true);
    final api = context.read<LiveServices>().api;
    final versions = shop.versionList;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              VersionTile(version: v, initiallyExpanded: true),
              if (versions.length >= 2)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => VersionCompareScreen(api: api, siteId: shop.siteId, shopTitle: shop.detail?.title ?? 'Shop', versions: versions),
                      ));
                    },
                    icon: const Icon(Icons.compare_arrows),
                    label: const Text('Compare versions'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /* -------------------------------------------------------------- build */

  @override
  Widget build(BuildContext context) {
    final closed = widget.shop.detail?.project.closed == true;
    return Column(
      children: [
        Expanded(child: ListenableBuilder(listenable: chat, builder: (context, _) => _body(context))),
        if (closed)
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.all(14),
            child: const SafeArea(top: false, child: Text('This project is closed. No more messages.', textAlign: TextAlign.center, style: TextStyle(color: AdinnColors.muted, fontWeight: FontWeight.w600))),
          )
        else
          ChatComposer(chat: chat, shop: widget.shop, picker: widget.picker),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (!chat.loaded && chat.loading) return const Center(child: CircularProgressIndicator());
    if (!chat.loaded && chat.error != null) return ErrorRetry(message: chat.error!, onRetry: chat.load);
    if (!chat.loaded) return const SizedBox.shrink();
    if (chat.messages.isEmpty && chat.pending.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        color: AdinnColors.red,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
          SizedBox(height: 40),
          EmptyState(icon: Icons.forum_outlined, title: 'No messages yet', message: 'Write to the reviewers about this shop. Submissions and review decisions also appear here.'),
        ]),
      );
    }
    final detail = widget.shop.detail;
    final versions = widget.shop.versionList;
    String labelOf(ChatRef r) => chatRefLabel(r, detail: detail, versions: versions);
    final me = chat.myId;
    final items = <Widget>[if (chat.hasMore || chat.olderError != null) _olderBar()];
    DateTime? lastDay;
    for (final m in chat.messages) {
      final at = m.createdAt;
      if (at != null) {
        final d = at.toLocal();
        final day = DateTime(d.year, d.month, d.day);
        if (day != lastDay) {
          items.add(ChatDayChip(fmtDayLabel(d)));
          lastDay = day;
        }
      }
      items.add(
        m.isSystem
            ? ChatSystemCard(message: m, labelOf: labelOf, onRef: _openRef)
            : ChatBubble(message: m, mine: m.isMine(me), labelOf: labelOf, onRef: _openRef, onImageFailed: chat.imageFailed),
      );
    }
    for (final p in chat.pending) {
      items.add(PendingChatBubble(message: p, labelOf: labelOf, onRetry: () => chat.retry(p), onDiscard: () => chat.discard(p)));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AdinnColors.red,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth == 0) _nearBottom = n.metrics.extentAfter < 120; // the thread's own scroll, not a text field inside it
          return false;
        },
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
        ),
      ),
    );
  }

  Widget _olderBar() {
    if (chat.loadingOlder) {
      return const Padding(padding: EdgeInsets.all(8), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    if (chat.olderError != null) {
      return Row(children: [
        Expanded(child: Text(chat.olderError!, style: const TextStyle(color: AdinnColors.red, fontSize: 13))),
        TextButton.icon(onPressed: _loadOlder, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]);
    }
    return Center(child: TextButton.icon(key: const ValueKey('load-older'), onPressed: _loadOlder, icon: const Icon(Icons.expand_less), label: const Text('Load older messages')));
  }
}

/// The label of the Chat tab: "Chat" with the unread count as a badge. Rebuilds on its own, not the whole shop screen.
class ChatTabLabel extends StatelessWidget {
  const ChatTabLabel({super.key, required this.chat});
  final ShopChatController chat;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) => Badge(
        isLabelVisible: chat.unread > 0,
        label: Text(chat.unread > 99 ? '99+' : '${chat.unread}'),
        offset: const Offset(10, -6),
        child: const Text('Chat'),
      ),
    );
  }
}
