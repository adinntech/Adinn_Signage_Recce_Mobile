import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../live_auth/presentation/live_auth_controller.dart';
import '../data/chat_controller.dart';
import '../data/dashboard_controller.dart';
import '../data/notifications_controller.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';
import '../data/recce_api.dart' show UploadStatus;
import '../data/upload_queue.dart';
import 'dashboard_widgets.dart';
import 'live_shops_screen.dart';
import 'live_widgets.dart';
import 'notifications_screen.dart';

/// Tab numbers of the home shell, so the dashboard can jump to them ("View All", "View Timeline").
abstract final class HomeTab {
  static const home = 0;
  static const projects = 1;
  static const submitted = 2;
  static const activity = 3;
  static const profile = 4;
}

/// Home: logo header with the bell and the profile picture, a search box, the six field numbers, overall progress, the shops that
/// need attention (rework), the shops to continue, a bar per project and the recent activity. The numbers are those of
/// `GET /recce/dashboard`; when it cannot be read the counts of the shop list (`meta.summary`) are shown instead, with the reason
/// and a Retry.
class LiveDashboardScreen extends StatefulWidget {
  const LiveDashboardScreen({super.key, this.onOpenTab});

  /// Switches the home shell to another tab (see [HomeTab]); null when the screen is shown on its own.
  final ValueChanged<int>? onOpenTab;

  @override
  State<LiveDashboardScreen> createState() => _LiveDashboardScreenState();
}

class _LiveDashboardScreenState extends State<LiveDashboardScreen> {
  late final ShopListController _list = context.read<ShopListController>();
  late final FieldDashboardController _dash = context.read<FieldDashboardController>();
  Object? _lastShops;

  @override
  void initState() {
    super.initState();
    _lastShops = _list.shops;
    _list.addListener(_onShops);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _dash.load();
    });
  }

  @override
  void dispose() {
    _list.removeListener(_onShops);
    super.dispose();
  }

  /// The shop list changed (loaded, a submit, an approval): the numbers are read again, quietly.
  void _onShops() {
    if (identical(_list.shops, _lastShops)) return;
    _lastShops = _list.shops;
    if (_list.loaded) _dash.load(silent: true);
  }

  Future<void> _refresh() => Future.wait([_list.load(), _dash.load()]);

  void _open(String title, ShopFilter f) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LiveShopsScreen(title: title, initialFilter: f)));
  }

  void _openProject(ProjectProgress p) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LiveShopsScreen(projectId: p.projectId, title: p.projectCode.isEmpty ? 'Project' : p.projectCode)));
  }

  void _tab(int i) => widget.onOpenTab?.call(i);

  @override
  Widget build(BuildContext context) {
    final list = context.watch<ShopListController>();
    final dash = context.watch<FieldDashboardController>();
    final queue = context.watch<UploadQueue>();
    final notes = context.watch<NotificationsController>();
    final chat = context.watch<ChatHub>();
    final user = context.watch<LiveAuthController>().user;
    final c = list.counts;
    final attention = list.shops.where((s) => s.status == 'REWORK_REQUIRED' || s.reworkOpen).toList();
    final resume = list.shops.where((s) => ShopFilter.inProgress.matches(s.status)).toList();
    final data = dash.data;
    final n = _Numbers.of(data, c, list.shops);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(children: [
          const AdinnLogo(size: 22),
          Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 8), color: AdinnColors.line),
          const Flexible(child: Text('Signage Recce', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          if (user != null) ...[
            const SizedBox(width: 6),
            Flexible(child: TagChip(user.role.label, color: AdinnColors.red)),
          ],
        ]),
        actions: [
          const NotificationBell(),
          Padding(padding: const EdgeInsets.only(right: 12), child: Avatar(_initials(user?.name ?? '?'), size: 34)),
        ],
      ),
      body: !list.loaded && list.loading
          ? const Center(child: CircularProgressIndicator())
          : !list.loaded && list.error != null
              ? ErrorRetry(message: list.error!, onRetry: _refresh)
              : RefreshIndicator(
                  onRefresh: _refresh,
                  color: AdinnColors.red,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _SearchRow(onTap: () => _open('Assigned shops', ShopFilter.all)),
                      const SizedBox(height: 12),
                      if (queue.totalPending > 0) ...[
                        _UploadBanner(queue: queue),
                        const SizedBox(height: 12),
                      ],
                      if (dash.loading && data == null) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator(minHeight: 3)),
                      if (dash.error != null && data == null) ...[
                        DashboardErrorNotice(message: dash.error!, onRetry: dash.load),
                        const SizedBox(height: 12),
                      ],
                      DashTileGrid(tiles: [
                        DashTile('Assigned Shops', '${n.assigned}', Icons.storefront_outlined, AdinnColors.red, onTap: () => _open('All shops', ShopFilter.all)),
                        DashTile('Started', '${n.started}', Icons.play_circle_outline, AdinnColors.red, onTap: () => _open('Started shops', ShopFilter.inProgress)),
                        DashTile('Submitted', '${n.submitted}', Icons.send_outlined, AdinnColors.red, onTap: () => _open('Submitted shops', ShopFilter.submitted)),
                        DashTile('Under Review', '${n.underReview}', Icons.hourglass_top_outlined, AdinnColors.red, onTap: () => _open('Submitted shops', ShopFilter.submitted)),
                        DashTile('Approved', '${n.approved}', Icons.check_circle_outline, AdinnColors.success, onTap: () => _open('Approved shops', ShopFilter.approved)),
                        DashTile('Rework', '${n.rework}', Icons.sync, AdinnColors.red, onTap: () => _open('Rework shops', ShopFilter.rework)),
                      ]),
                      const SizedBox(height: 12),
                      OverallProgressCard(assigned: n.assigned, submitted: n.submitted, approved: data?.completed ?? n.approved),
                      if (data != null) ...[
                        const SizedBox(height: 10),
                        _ExtraNumbers(data),
                        const SizedBox(height: 10),
                        const DashboardNote('Completed = approved by both reviewers on the latest version. An approval of an older version does not count. Pending = assigned shops that are not completed yet.'),
                      ],
                      const SizedBox(height: 18),
                      if (attention.isNotEmpty) ...[
                        DashSectionHeader('Needs Your Attention', onAction: () => _open('Rework shops', ShopFilter.rework)),
                        for (final s in attention.take(3)) ...[
                          AttentionCard(shop: s, unread: shopUnreadCount(chat, notes, s.siteId), onTap: () => openShop(context, s.siteId)),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 8),
                      ] else if (c.total == 0)
                        const EmptyState(icon: Icons.inbox_outlined, title: 'No shops assigned yet', message: 'Operations will assign shops to you. Pull down to refresh.'),
                      if (resume.isNotEmpty) ...[
                        DashSectionHeader('Continue Where You Left Off', onAction: () => _open('In progress', ShopFilter.inProgress)),
                        for (final s in resume.take(3)) ...[
                          ResumeRow(shop: s, onTap: () => openShop(context, s.siteId)),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 8),
                      ],
                      if (data != null && data.projects.isNotEmpty) ...[
                        DashSectionHeader('Project-wise Progress', onAction: () => _tab(HomeTab.projects)),
                        const _BarLegend(),
                        const SizedBox(height: 8),
                        for (final p in data.projects.take(3)) ...[
                          ProjectProgressCard(project: p, onTap: () => _openProject(p)),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 8),
                      ],
                      if (notes.items.isNotEmpty) ...[
                        DashSectionHeader('Recent Activity', action: 'View Timeline', onAction: () => _tab(HomeTab.activity)),
                        ActivityTimeline(items: notes.items.take(3).toList()),
                      ],
                    ],
                  ),
                ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

/// The six numbers of the tiles: from the dashboard when it was read, else from the shop list that is already in memory.
class _Numbers {
  const _Numbers({required this.assigned, required this.started, required this.submitted, required this.underReview, required this.approved, required this.rework});

  final int assigned;
  final int started;
  final int submitted;
  final int underReview;
  final int approved;
  final int rework;

  factory _Numbers.of(FieldDashboard? d, DashboardCounts c, List<ShopSummary> shops) {
    if (d != null) {
      return _Numbers(assigned: d.assignedShops, started: d.started, submitted: d.submitted, underReview: d.underReview, approved: d.approved, rework: d.rework);
    }
    return _Numbers(
      assigned: c.total,
      started: c.total - shops.where((s) => s.status == 'NOT_STARTED').length,
      submitted: c.submitted,
      underReview: shops.where((s) => s.status == 'UNDER_REVIEW').length,
      approved: c.approved,
      rework: c.rework,
    );
  }
}

/// Search box of the home screen: a tap opens the shop list, which has the real search and the status chips.
class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: TextField(
          key: const ValueKey('home-search'),
          readOnly: true,
          onTap: onTap,
          decoration: const InputDecoration(hintText: 'Search shops, projects, areas...', prefixIcon: Icon(Icons.search)),
        ),
      ),
      const SizedBox(width: 10),
      Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AdinnColors.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: const SizedBox(width: 50, height: 50, child: Icon(Icons.tune, color: AdinnColors.ink)),
        ),
      ),
    ]);
  }
}

/// Completed, pending, average completion time and rework rate (the numbers that have no tile).
class _ExtraNumbers extends StatelessWidget {
  const _ExtraNumbers(this.d);
  final FieldDashboard d;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value, Color color) => Expanded(
          child: Column(children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color))),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: const TextStyle(fontSize: 11.5, color: AdinnColors.muted))),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(children: [
          cell('Completed', '${d.completed}', AdinnColors.success),
          cell('Pending', '${d.pending}', AdinnColors.warning),
          cell('Avg. completion', fmtHours(d.avgCompletionHours), AdinnColors.info),
          cell('Rework rate', fmtPercent(d.reworkPercent), AdinnColors.red),
        ]),
      ),
    );
  }
}

/// What the colours of a project bar mean.
class _BarLegend extends StatelessWidget {
  const _BarLegend();

  @override
  Widget build(BuildContext context) {
    Widget dot(String text, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11, color: AdinnColors.muted)),
        ]);
    return Wrap(spacing: 12, runSpacing: 4, children: [
      dot('Approved', progressBarColors.approved),
      dot('Rework', progressBarColors.rework),
      dot('Waiting for review', progressBarColors.inReview),
      dot('Started', progressBarColors.working),
      dot('Not started', progressBarColors.notStarted),
    ]);
  }
}

class _UploadBanner extends StatelessWidget {
  const _UploadBanner({required this.queue});
  final UploadQueue queue;

  @override
  Widget build(BuildContext context) {
    final failed = queue.items.where((u) => u.status == UploadStatus.failed).length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AdinnColors.redLight, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.cloud_upload_outlined, color: AdinnColors.red),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${queue.totalPending} photo${queue.totalPending == 1 ? '' : 's'} waiting to upload${failed > 0 ? ' ($failed failed, open the shop to retry)' : ''}',
            style: const TextStyle(color: AdinnColors.redDark, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}
