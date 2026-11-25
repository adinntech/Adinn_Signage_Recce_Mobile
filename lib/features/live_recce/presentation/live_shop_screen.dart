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
import '../data/rework_alert.dart';
import 'add_boards_screen.dart';
import 'boards_tab.dart';
import 'chat_tab.dart';
import 'installation_tab.dart';
import 'live_widgets.dart';
import 'photos_tab.dart';
import 'review_tab.dart';
import 'rework_alert.dart';
import 'rework_sheet.dart';

/// The tabs of the shop screen, in the order the work is done: the boards first (their type and size), then the photos of each
/// board, then the installation answers, then the review.
abstract final class ShopTab {
  static const boards = 0;
  static const photos = 1;
  static const install = 2;
  static const review = 3;
  static const chat = 4;
  static const count = 5;
}

/// Where the guided flow takes the person next: a tab, and on it a board (and the part of its card), [boardWork] when some board still has
/// something to do.
class _Work {
  const _Work(this.tab, {this.board, this.section, this.boardWork = false});
  final int tab;
  final String? board;
  final BoardSection? section;
  final bool boardWork;
}

/// Shop Recce Details: header + Boards / Photos / Install / Review / Chat tabs and the Save Draft / Submit bar.
class LiveShopScreen extends StatefulWidget {
  /// [assignedAt] is the "assigned on" time of the list row this screen was opened from (the shop detail the server sends does
  /// not carry it). When it is null the screen looks the row up in the shop list; with no row the "Assigned" line is hidden.
  /// [initialTab] is one of [ShopTab] (a notification about a message opens the Chat tab). Null = the screen picks: the first step
  /// that is not done yet (Boards, Photos, Install, then Review), or Photos when the shop is locked or in rework.
  const LiveShopScreen({super.key, required this.siteId, this.assignedAt, this.initialTab});

  final String siteId;
  final DateTime? assignedAt;
  final int? initialTab;

  @override
  State<LiveShopScreen> createState() => _LiveShopScreenState();
}

class _LiveShopScreenState extends State<LiveShopScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final ShopDetailController _ctrl;
  late final ShopChatController _chat;
  late final TabController _tabs;
  late final DateTime? _assignedAt;
  var _onChatTab = false;

  // Guided flow, board by board: add boards (media types, sizes), then for each board its photos and its installation requirement
  // (installation method and site questions), then the site installation, then review. The screen moves on by itself when the person
  // finishes a photo step, and on "Next" at the end of a board card.
  Timer? _advanceTimer;
  var _alertOpen = false; // the rework sheet is on screen right now
  var _stepsSeeded = false; // the first read of the shop only records where it stands: it never moves the person
  final _announced = <String>{}; // boards whose photos were complete when seen: each is announced once, never again

  @override
  void initState() {
    super.initState();
    final s = context.read<LiveServices>();
    _assignedAt = widget.assignedAt ?? _rowAssignedAt(s.shops);
    _ctrl = ShopDetailController(s.api, s.queue, widget.siteId, catalog: s.catalog);
    unawaited(s.catalog.refresh()); // the admin may have changed the media types or questions since the phone last asked
    _tabs = TabController(length: ShopTab.count, vsync: this, initialIndex: (widget.initialTab ?? ShopTab.boards).clamp(0, ShopTab.count - 1))..addListener(_onTab);
    _ctrl.addListener(_watchSteps);
    _ctrl.addListener(_watchAlert);
    unawaited(_ctrl.load().then((_) => _landOnFirstStep()));
    _chat = s.chat.open(widget.siteId, myId: context.read<LiveAuthController>().user?.id ?? '')..start();
    _onChatTab = _tabs.index == ShopTab.chat;
    if (_onChatTab) _chat.setVisible(true);
    WidgetsBinding.instance.addObserver(this);
  }

  /// What the person does next, in the order of the work: the boards' sizes, then board by board its photos and its installation
  /// requirement, then the site installation, then the review. `board` / `section` say where on that tab; `boardWork` is true while
  /// some board still has something to do.
  _Work _nextWork() {
    final c = _ctrl;
    for (final b in c.boards) {
      if (!b.hasSize || b.name.trim().isEmpty) return _Work(ShopTab.boards, board: b.key, section: BoardSection.size);
    }
    if (c.boards.isEmpty) return const _Work(ShopTab.boards, boardWork: true);
    for (final b in c.boards) {
      if (c.isSaved(b.key) && !c.boardPhotosDone(b.key)) return _Work(ShopTab.photos, board: b.key);
      if (!c.boardInstallDone(b)) return _Work(ShopTab.boards, board: b.key, section: BoardSection.installation);
    }
    if (!c.installDone) return const _Work(ShopTab.install, boardWork: false);
    return const _Work(ShopTab.review, boardWork: false);
  }

  /// Takes the person to [w]: the tab, with the board opened (and its section in view) where that applies.
  void _go(_Work w) {
    final key = w.board;
    if (key != null && w.tab == ShopTab.photos) _ctrl.focusBoard(key);
    if (key != null && w.tab == ShopTab.boards) _ctrl.openBoardCard(key, section: w.section);
    _tabs.animateTo(w.tab);
  }

  /// Opens on the step the person is at (see [_nextWork]). A locked shop or one in rework opens on Photos (the flagged ones). A tab
  /// asked for (a notification) stays.
  void _landOnFirstStep() {
    if (!mounted || widget.initialTab != null || _ctrl.detail == null) return;
    if (!_ctrl.canEdit || _ctrl.inRework) {
      _tabs.index = ShopTab.photos;
      return;
    }
    final w = _nextWork();
    final key = w.board;
    if (key != null && w.tab == ShopTab.photos) _ctrl.focusBoard(key);
    if (key != null && w.tab == ShopTab.boards) _ctrl.openBoardCard(key, section: w.section);
    _tabs.index = w.tab;
  }

  /// Watches the shop for the moment the last photo of ONE board is taken (stored or uploading) and then moves on.
  void _watchSteps() {
    final d = _ctrl.detail;
    if (!mounted || d == null) return;
    final done = {for (final b in d.mediaItems) if (_ctrl.boardPhotosDone(b.key)) b.key};
    final fresh = done.difference(_announced);
    _announced.addAll(done);
    final seeded = _stepsSeeded;
    _stepsSeeded = true;
    // Rework only fixes what the reviewer flagged: the person is not pushed around the steps then.
    if (seeded && fresh.isNotEmpty && _ctrl.canEdit && !_ctrl.inRework && _tabs.index == ShopTab.photos) _boardPhotosFinished(fresh.first);
  }

  /// Tells the person what the reviewers flagged: ONE sheet per rework request (remembered for the session, so it never comes back
  /// for the same request), then the banner on top of the screen stays. "Retake now" opens the first flagged photo.
  void _watchAlert() {
    if (!mounted || _alertOpen || !_ctrl.canEdit) return;
    final alert = reworkAlertOf(_ctrl);
    if (alert.isEmpty || !claimReworkAlert(alert.requestKey)) return;
    _alertOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final retake = await showReworkAlertSheet(context, alert);
      _alertOpen = false;
      if (retake == true && mounted) await _retakeNow(alert);
    });
  }

  /// Takes the person to what is flagged: the Photos tab (the board of the first flagged photo opened) while a photo is still waiting for
  /// a new picture, else the Boards tab (the board whose detail was flagged), else the tab of the first checklist item sent back
  /// (Photos, Boards, Install or, for the shop as a whole, Review).
  void _goAlert(ReworkAlert a) {
    final photo = a.photos.where((p) => !p.answered).firstOrNull ?? a.photos.firstOrNull;
    if (a.rejectedPhotos + a.reworkPhotos + a.extraPhotos > 0 || (a.boardFixes.isEmpty && a.sections.isEmpty)) {
      final key = photo?.photo.mediaKey ?? '';
      if (key.isNotEmpty) _ctrl.focusBoard(key);
      _tabs.animateTo(ShopTab.photos);
    } else if (a.boardFixes.isNotEmpty) {
      final key = a.boardFixes.first.mediaKey;
      if (key.isNotEmpty) _ctrl.openBoardCard(key);
      _tabs.animateTo(ShopTab.boards);
    } else {
      _tabs.animateTo(switch (a.sections.first.section) {
        'PHOTOS' => ShopTab.photos,
        'BOARDS' => ShopTab.boards,
        'INSTALLATION' => ShopTab.install,
        _ => ShopTab.review,
      });
    }
  }

  Future<void> _retakeNow(ReworkAlert a) async {
    _goAlert(a);
    final next = a.photos.where((p) => !p.answered).firstOrNull;
    if (next != null && mounted) await showReworkSheet(context, ctrl: _ctrl, photo: next.photo);
  }

  /// A short pause (the person sees the last tile fill up), then: that board's installation requirement when it has one to fill, or
  /// the next board's photos, or, when every board is complete, the question whether there is another board.
  void _boardPhotosFinished(String key) {
    if (_advanceTimer?.isActive ?? false) return;
    _advanceTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || _tabs.index != ShopTab.photos) return; // the person already went somewhere else
      final label = _ctrl.boards.where((b) => b.key == key).firstOrNull?.label ?? 'Board';
      _continueFrom(label, 'photos done.', 'photos complete');
    });
  }

  /// "Next" at the end of a board card: saves what was typed (so nothing is lost if the app closes), then goes on.
  Future<void> _afterBoard(BoardItem b) async {
    if (_ctrl.dirty) {
      final err = await _ctrl.saveDraft();
      if (!mounted) return;
      if (err != null) {
        showSnack(context, err, error: true);
        return;
      }
    }
    _continueFrom(b.label, 'done.', 'complete');
  }

  /// Goes to what comes next after a board's step. While some board still has work it goes there with a short message; when every
  /// board is complete it asks whether there is another board ([doneWhat] names what was just completed in the question).
  void _continueFrom(String label, String said, String doneWhat) {
    final w = _nextWork();
    if (w.boardWork || w.board != null) {
      final b = _ctrl.boards.where((x) => x.key == w.board).firstOrNull;
      final who = b?.label ?? 'the board';
      final what = w.tab == ShopTab.photos ? 'photos of $who' : (w.section == BoardSection.installation ? 'installation of $who' : 'size of $who');
      _go(w);
      showSnack(context, '$label $said Next: $what.');
      return;
    }
    unawaited(_askWhatNext(label, doneWhat));
  }

  /// Every board is complete: add another board (media types, sizes, then its photos) or go on to the installation.
  Future<void> _askWhatNext(String label, String doneWhat) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      // A small window (or a big font) must never cut the buttons off: the sheet may use the whole height and scrolls when needed.
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle, color: AdinnColors.success, size: 40),
              const SizedBox(height: 8),
              Text('$label $doneWhat', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Every board is complete. Is there another board in this shop?', textAlign: TextAlign.center, style: TextStyle(color: AdinnColors.muted)),
              const SizedBox(height: 16),
              FilledButton.icon(key: const Key('photos-add-another'), onPressed: () => Navigator.pop(ctx, 'add'), icon: const Icon(Icons.add), label: const Text('Add another board')),
              const SizedBox(height: 8),
              OutlinedButton.icon(key: const Key('photos-continue'), onPressed: () => Navigator.pop(ctx, 'next'), icon: const Icon(Icons.arrow_forward), label: const Text('No more boards. Continue')),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return; // closed without choosing: the person stays where they are
    if (choice == 'add') {
      final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AddBoardsScreen(ctrl: _ctrl)));
      if (added == true && mounted) _tabs.animateTo(ShopTab.photos); // the controller already opened the first new board's photos
    } else {
      _go(_nextWork());
    }
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
    _advanceTimer?.cancel();
    _ctrl.removeListener(_watchSteps);
    _ctrl.removeListener(_watchAlert);
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
        isScrollControlled: true, // several boards make a long list (seven photo lines each): it scrolls instead of overflowing
        useSafeArea: true,
        builder: (_) => SafeArea(
          child: SingleChildScrollView(
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
    final alert = reworkAlertOf(_ctrl);
    return NestedScrollView(
      headerSliverBuilder: (context, _) => [
        // On the Chat tab the shop card shrinks to one line, so the thread and the box keep the room (also with the keyboard open).
        SliverToBoxAdapter(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _onChatTab ? _ChatStrip(d: d) : _Header(d: d, locked: !_ctrl.canEdit, assignedAt: d.assignedAt ?? _assignedAt),
              // What the reviewers flagged stays in view on every tab until it is fixed and resubmitted.
              if (!alert.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: ReworkAlertBanner(alert: alert, compact: _onChatTab, onOpen: () => _goAlert(alert))),
            ]),
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
              tabs: [const Tab(text: 'Boards'), const Tab(text: 'Photos'), const Tab(text: 'Install'), const Tab(text: 'Review'), Tab(child: ChatTabLabel(chat: _chat))],
            ),
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabs,
        children: [
          BoardsTab(
            ctrl: _ctrl,
            onBoardsAdded: () => _tabs.animateTo(ShopTab.photos), // the controller already opened the first new board's photos
            onNextBoard: _afterBoard,
            onOpenPhotos: (b) {
              _ctrl.focusBoard(b.key);
              _tabs.animateTo(ShopTab.photos);
            },
          ),
          PhotosTab(ctrl: _ctrl, onAddBoards: () => _tabs.animateTo(ShopTab.boards)),
          InstallationTab(ctrl: _ctrl, onNext: () => _tabs.animateTo(ShopTab.review)),
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
