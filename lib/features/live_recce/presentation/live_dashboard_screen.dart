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

/// Dashboard: the field numbers of `GET /recce/dashboard` (assigned, started, submitted, under review, approved, rework, completed,
/// pending, average time, rework rate) with a bar per project, and the shops that need attention. When the dashboard cannot be read
/// the counts of the shop list (`meta.summary`) are shown instead, with the reason and a Retry.
class LiveDashboardScreen extends StatefulWidget {
  const LiveDashboardScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final list = context.watch<ShopListController>();
    final dash = context.watch<FieldDashboardController>();
    final queue = context.watch<UploadQueue>();
    final notes = context.watch<NotificationsController>();
    final chat = context.watch<ChatHub>();
    final user = context.watch<LiveAuthController>().user;
    final c = list.counts;
    final attention = list.shops.where((s) => s.status == 'REWORK_REQUIRED' || s.reworkOpen).take(5).toList();
    final data = dash.data;
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard'), actions: const [NotificationBell()]),
      body: !list.loaded && list.loading
          ? const Center(child: CircularProgressIndicator())
          : !list.loaded && list.error != null
              ? ErrorRetry(message: list.error!, onRetry: _refresh)
              : RefreshIndicator(
                  onRefresh: _refresh,
                  color: AdinnColors.red,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Hello, ${user?.name.split(' ').first ?? ''}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      Text(user?.vendorName ?? user?.role.label ?? '', style: const TextStyle(color: AdinnColors.muted)),
                      const SizedBox(height: 14),
                      if (notes.unread > 0) ...[
                        _UnreadBanner(unread: notes.unread, messages: notes.unreadMessages),
                        const SizedBox(height: 12),
                      ],
                      if (queue.totalPending > 0) ...[
                        _UploadBanner(queue: queue),
                        const SizedBox(height: 12),
                      ],
                      if (dash.loading && data == null) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator(minHeight: 3)),
                      if (dash.error != null && data == null) ...[
                        DashboardErrorNotice(message: dash.error!, onRetry: dash.load),
                        const SizedBox(height: 12),
                      ],
                      if (data != null) ..._fieldNumbers(data) else _shopCounts(c),
                      const SizedBox(height: 18),
                      if (data != null && data.projects.isNotEmpty) ...[
                        const Text('Project-wise progress', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 4),
                        const _BarLegend(),
                        const SizedBox(height: 8),
                        for (final p in data.projects) ...[
                          ProjectProgressCard(project: p, onTap: () => _openProject(p)),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 8),
                      ],
                      if (attention.isNotEmpty) ...[
                        const Text('Needs your attention', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 8),
                        for (final s in attention) ...[
                          ShopCard(shop: s, unread: shopUnreadCount(chat, notes, s.siteId), onTap: () => openShop(context, s.siteId)),
                          const SizedBox(height: 10),
                        ],
                      ] else if (c.total == 0)
                        const EmptyState(icon: Icons.inbox_outlined, title: 'No shops assigned yet', message: 'Operations will assign shops to you. Pull down to refresh.'),
                    ],
                  ),
                ),
    );
  }

  /// The numbers of `GET /recce/dashboard`, and what "Completed" means.
  List<Widget> _fieldNumbers(FieldDashboard d) => [
        KpiGrid(cards: [
          KpiCard('Assigned shops', '${d.assignedShops}', Icons.storefront_outlined, AdinnColors.ink, subtitle: '${d.assignedProjects} project${d.assignedProjects == 1 ? '' : 's'}', onTap: () => _open('All shops', ShopFilter.all)),
          KpiCard('Started', '${d.started}', Icons.play_circle_outline, statusColor('IN_PROGRESS'), subtitle: 'visit started'),
          KpiCard('Submitted', '${d.submitted}', Icons.send_outlined, statusColor('SUBMITTED'), subtitle: 'at least once', onTap: () => _open('Submitted shops', ShopFilter.submitted)),
          KpiCard('Under review', '${d.underReview}', Icons.hourglass_top_outlined, statusColor('UNDER_REVIEW'), subtitle: 'waiting for a reviewer', onTap: () => _open('Submitted shops', ShopFilter.submitted)),
          KpiCard('Approved', '${d.approved}', Icons.verified_outlined, statusColor('APPROVED'), onTap: () => _open('Approved shops', ShopFilter.approved)),
          KpiCard('Rework', '${d.rework}', Icons.flag_outlined, statusColor('REWORK_REQUIRED'), subtitle: 'asked right now', onTap: () => _open('Rework shops', ShopFilter.rework)),
          KpiCard('Completed', '${d.completed}', Icons.task_alt, AdinnColors.success, subtitle: 'approved by all reviewers'),
          KpiCard('Pending', '${d.pending}', Icons.pending_actions_outlined, AdinnColors.warning, subtitle: 'assigned, not completed'),
          KpiCard('Avg. completion', fmtHours(d.avgCompletionHours), Icons.timer_outlined, AdinnColors.info, subtitle: d.avgCompletionHours == null ? 'no completed shop yet' : 'visit start to final approval'),
          KpiCard('Rework rate', fmtPercent(d.reworkPercent), Icons.loop, AdinnColors.red, subtitle: '${d.reworkCount} of ${d.submitted} submitted'),
        ]),
        const SizedBox(height: 12),
        const DashboardNote('Completed = approved by both reviewers on the latest version. An approval of an older version does not count. Pending = assigned shops that are not completed yet.'),
      ];

  /// What the shop list already knows (the counts of `meta.summary`): shown while the dashboard loads and when it cannot be read.
  Widget _shopCounts(DashboardCounts c) => KpiGrid(cards: [
        KpiCard('Total', '${c.total}', Icons.storefront_outlined, AdinnColors.ink, onTap: () => _open('All shops', ShopFilter.all)),
        KpiCard('Pending', '${c.pending}', Icons.pending_actions_outlined, statusColor('IN_PROGRESS'), onTap: () => _open('Pending shops', ShopFilter.inProgress)),
        KpiCard('Submitted', '${c.submitted}', Icons.send_outlined, statusColor('SUBMITTED'), onTap: () => _open('Submitted shops', ShopFilter.submitted)),
        KpiCard('Approved', '${c.approved}', Icons.verified_outlined, statusColor('APPROVED'), onTap: () => _open('Approved shops', ShopFilter.approved)),
        KpiCard('Rework', '${c.rework}', Icons.flag_outlined, statusColor('REWORK_REQUIRED'), onTap: () => _open('Rework shops', ShopFilter.rework)),
      ]);
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

/// "3 unread notifications, 2 new messages": a tap opens the bell. Both numbers come from the one notifications read.
class _UnreadBanner extends StatelessWidget {
  const _UnreadBanner({required this.unread, required this.messages});
  final int unread;
  final int messages;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('unread-banner'),
      color: AdinnColors.info.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen())),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.notifications_active_outlined, color: AdinnColors.info),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$unread unread notification${unread == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (messages > 0) Text('$messages new message${messages == 1 ? '' : 's'} in your shops', style: const TextStyle(fontSize: 12, color: AdinnColors.muted)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: AdinnColors.muted),
          ]),
        ),
      ),
    );
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
