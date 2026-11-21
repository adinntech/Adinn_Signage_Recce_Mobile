import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../live_auth/presentation/live_auth_controller.dart';
import '../data/chat_controller.dart';
import '../data/live_services.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';
import 'boards_tab.dart';
import 'chat_tab.dart';
import 'installation_tab.dart';
import 'live_widgets.dart';
import 'photos_tab.dart';
import 'review_tab.dart';

/// The tabs of the shop screen, in order.
abstract final class ShopTab {
  static const photos = 0;
  static const boards = 1;
  static const install = 2;
  static const review = 3;
  static const chat = 4;
  static const count = 5;
}

/// Shop Recce Details: header + Photos / Boards / Installation / Review / Chat tabs and the Save Draft / Submit bar.
class LiveShopScreen extends StatefulWidget {
  /// [assignedAt] is the "assigned on" time of the list row this screen was opened from (the shop detail the server sends does
  /// not carry it). When it is null the screen looks the row up in the shop list; with no row the "Assigned" line is hidden.
  /// [initialTab] is one of [ShopTab] (a notification about a message opens the Chat tab).
  const LiveShopScreen({super.key, required this.siteId, this.assignedAt, this.initialTab = ShopTab.photos});

  final String siteId;
  final DateTime? assignedAt;
  final int initialTab;

  @override
  State<LiveShopScreen> createState() => _LiveShopScreenState();
}

class _LiveShopScreenState extends State<LiveShopScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final ShopDetailController _ctrl;
  late final ShopChatController _chat;
  late final TabController _tabs;
  late final DateTime? _assignedAt;
  var _onChatTab = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<LiveServices>();
    _assignedAt = widget.assignedAt ?? _rowAssignedAt(s.shops);
    _ctrl = ShopDetailController(s.api, s.queue, widget.siteId)..load();
    _tabs = TabController(length: ShopTab.count, vsync: this, initialIndex: widget.initialTab.clamp(0, ShopTab.count - 1))..addListener(_onTab);
    _chat = s.chat.open(widget.siteId, myId: context.read<LiveAuthController>().user?.id ?? '')..start();
    _onChatTab = _tabs.index == ShopTab.chat;
    if (_onChatTab) _chat.setVisible(true);
    WidgetsBinding.instance.addObserver(this);
  }

  /// The Chat tab in front reads the thread and marks it read; leaving it goes back to reading only the unread count.
  void _onTab() {
    final onChat = _tabs.index == ShopTab.chat;
    if (onChat == _onChatTab) return;
    _onChatTab = onChat;
    _chat.setVisible(onChat);
    if (mounted) setState(() {});
  }

  DateTime? _rowAssignedAt(ShopListController list) {
    for (final row in list.shops) {
      if (row.siteId == widget.siteId) return row.assignedAt;
    }
    return null;
  }

  /// Signed photo links expire after about 10 minutes: when the app comes back after a while, read the shop again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final front = state == AppLifecycleState.resumed;
    _chat.setForeground(front); // nothing is polled while the app is in the background
    if (front) {
      unawaited(_ctrl.refreshIfStale());
      if (_onChatTab && _chat.linksExpired) unawaited(_chat.refresh()); // the picture links of the thread run out too
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabs.dispose();
    _chat.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final err = await _ctrl.saveDraft();
    if (!mounted) return;
    if (err != null) {
      showSnack(context, err, error: true);
    } else {
      showSnack(context, 'Draft saved.');
      context.read<ShopListController>().load(silent: true);
    }
  }

  Future<void> _submit() async {
    final out = await _ctrl.submit();
    if (!mounted) return;
    if (out.problems.isNotEmpty) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Complete these before submitting', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                IssueList(items: out.problems, warning: true),
              ],
            ),
          ),
        ),
      );
    } else if (out.serverError != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.error_outline, color: AdinnColors.red, size: 32),
          title: const Text('Could not submit'),
          content: Text(out.serverError!),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } else {
      showSnack(context, '${out.version == 1 ? 'Submitted' : 'Resubmitted'} as version ${out.version}.');
      context.read<ShopListController>().load(silent: true);
    }
  }

  Future<void> _confirmLeave() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save your boards and installation answers as a draft before leaving?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'stay'), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save draft')),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'stay') return;
    if (choice == 'save') {
      final err = await _ctrl.saveDraft();
      if (!mounted) return;
      if (err != null) {
        showSnack(context, err, error: true);
        return;
      }
    }
    if (!mounted) return;
    _ctrl.dirty = false;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        final d = _ctrl.detail;
        return PopScope(
          canPop: !_ctrl.dirty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmLeave();
          },
          child: Scaffold(
            appBar: AppBar(title: Text(d?.title ?? 'Shop')),
            body: _body(d),
            // The Chat tab has its own box at the bottom (the keyboard pushes it up); Save / Submit belong to the other tabs.
            bottomNavigationBar: d == null || _onChatTab ? null : _bottomBar(d),
          ),
        );
      },
    );
  }

  Widget _body(ShopDetail? d) {
    if (_ctrl.loading && d == null) return const Center(child: CircularProgressIndicator());
    if (d == null) return ErrorRetry(message: _ctrl.loadError ?? 'Could not load this shop.', onRetry: _ctrl.load);
    return NestedScrollView(
      headerSliverBuilder: (context, _) => [
        // On the Chat tab the shop card shrinks to one line, so the thread and the box keep the room (also with the keyboard open).
        SliverToBoxAdapter(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _onChatTab ? _ChatStrip(d: d) : _Header(d: d, locked: !_ctrl.canEdit, assignedAt: d.assignedAt ?? _assignedAt),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarDelegate(
            TabBar(
              controller: _tabs,
              isScrollable: false,
              labelColor: AdinnColors.red,
              indicatorColor: AdinnColors.red,
              unselectedLabelColor: AdinnColors.muted,
              labelPadding: const EdgeInsets.symmetric(horizontal: 2),
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              tabs: [const Tab(text: 'Photos'), const Tab(text: 'Boards'), const Tab(text: 'Install'), const Tab(text: 'Review'), Tab(child: ChatTabLabel(chat: _chat))],
            ),
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabs,
        children: [
          PhotosTab(ctrl: _ctrl),
          BoardsTab(ctrl: _ctrl),
          InstallationTab(ctrl: _ctrl),
          ReviewTab(ctrl: _ctrl),
          ChatTab(shop: _ctrl, chat: _chat, onOpenBoards: () => _tabs.animateTo(ShopTab.boards)),
        ],
      ),
    );
  }

  Widget _bottomBar(ShopDetail d) {
    if (!_ctrl.canEdit) {
      return SafeArea(
        child: Container(
          padding: const EdgeInsets.all(14),
          color: Colors.white,
          child: Text(
            d.project.closed ? 'This project is closed. No more changes.' : _lockedText(d),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AdinnColors.muted, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
    final busy = _ctrl.busy;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AdinnColors.line))),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_ctrl.dirty ? 'Save draft *' : 'Save draft'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : _submit,
                icon: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_outlined),
                label: Text('${_ctrl.inRework ? 'Resubmit' : 'Submit'} V${d.version + 1}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _lockedText(ShopDetail d) => switch (d.status) {
        'SUBMITTED' || 'UNDER_REVIEW' => 'Sent for verification (version ${d.version}). Editing is locked.',
        'APPROVED' => 'Approved. This shop is complete.',
        'REJECTED' => 'Rejected. Contact the office if another attempt is allowed.',
        _ => 'Editing is locked.',
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.d, required this.locked, this.assignedAt});

  final ShopDetail d;
  final bool locked;

  /// From the shop list row; null hides the "Assigned" line.
  final DateTime? assignedAt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(d.project.code, style: const TextStyle(fontWeight: FontWeight.w800, color: AdinnColors.red))),
                if (d.version > 0) Padding(padding: const EdgeInsets.only(right: 8), child: TagChip('Version ${d.version}', icon: Icons.history)),
                StatusPill(d.status),
              ]),
              if ((d.project.client ?? '').isNotEmpty) Text(d.project.client!, style: const TextStyle(color: AdinnColors.muted)),
              const SizedBox(height: 6),
              Text(d.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(d.siteCode, style: const TextStyle(color: AdinnColors.muted, fontSize: 13)),
              if (d.address.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(d.address)),
              const SizedBox(height: 8),
              Wrap(spacing: 16, runSpacing: 4, children: [
                if (assignedAt != null) _Meta(Icons.assignment_ind_outlined, 'Assigned ${fmtDate(assignedAt!)}'),
                if (d.project.expectedBy != null) _Meta(Icons.event_outlined, 'Expected ${fmtDate(d.project.expectedBy!)}'),
                if (d.contactPerson != null) _Meta(Icons.person_outline, d.contactPerson!),
              ]),
              if (locked) const Padding(padding: EdgeInsets.only(top: 8), child: TagChip('Read only', icon: Icons.lock_outline)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line standing in for the shop card while the Chat tab is open.
class _ChatStrip extends StatelessWidget {
  const _ChatStrip({required this.d});
  final ShopDetail d;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(children: [
        Expanded(child: Text('${d.title}  |  ${d.project.code}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
        const SizedBox(width: 8),
        StatusPill(d.status),
      ]),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 15, color: AdinnColors.muted), const SizedBox(width: 4), Text(text, style: const TextStyle(fontSize: 13, color: AdinnColors.muted))],
      );
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarDelegate(this.bar);
  final TabBar bar;

  @override
  double get minExtent => bar.preferredSize.height;
  @override
  double get maxExtent => bar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(color: AdinnColors.canvas, child: bar);

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}
