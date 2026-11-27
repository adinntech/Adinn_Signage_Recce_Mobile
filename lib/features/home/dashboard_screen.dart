import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../history/activity_screen.dart';
import '../projects/task_detail_screen.dart';
import '../shop/shop_tile.dart';
import 'shop_search.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onOpenTab});

  /// Switches the bottom navigation tab (0 Home, 1 Projects, 2 Approvals,
  /// 3 Activity, 4 Profile).
  final ValueChanged<int> onOpenTab;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final user = c.currentUser!;
    final sum = c.overallSummary;
    final reviewer = !c.isVendor;
    final attention = reviewer
        ? c.pendingReviews
        : c.visibleShops.where((s) => s.status.isRejected).toList();
    final tasks = c.visibleTasks
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final recent = c.activities().take(3).toList();
    // Field work started but not submitted yet, most recent first.
    final drafts = reviewer
        ? const <Shop>[]
        : (c.visibleShops
              .where(
                (s) =>
                    c.canEdit(s) &&
                    !s.status.isRejected &&
                    (s.status == RecceStatus.inProgress || s.boards.isNotEmpty),
              )
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _Header(
              greeting: _greeting(),
              user: user,
              subtitle: reviewer
                  ? '${c.pendingReviews.length} recce(s) awaiting your approval'
                  : '${sum.notStarted + sum.inProgress + sum.rejected} shop(s) need field work',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: ListTile(
                  key: const Key('dashboard_search'),
                  leading: const Icon(Icons.search),
                  title: const Text(
                    'Search shops, owners, areas, projects',
                    style: TextStyle(color: AdinnColors.muted, fontSize: 14),
                  ),
                  onTap: () => showSearch<void>(
                    context: context,
                    delegate: ShopSearchDelegate(c),
                  ),
                ),
              ),
            ),
          ),
          // Only what needs the person's attention, in this order: Needs rework (Awaiting your approval for a reviewer), Continue where
          // you left off (only when something is pending), My tasks, Recent activity. A section with nothing in it is not drawn.
          if (attention.isNotEmpty) ...[
            _sectionTitle(
              reviewer ? 'Awaiting your approval' : 'Needs rework',
              action: 'View all',
              onAction: () => onOpenTab(2),
            ),
            _list(attention.length.clamp(0, _maxShops), (i) => ShopTile(shop: attention[i], showProject: true, compact: true)),
          ],
          if (drafts.isNotEmpty) ...[
            _sectionTitle('Continue where you left off', key: const Key('continue_drafts')),
            _list(drafts.length.clamp(0, _maxShops), (i) => ShopTile(shop: drafts[i], showProject: true, compact: true)),
          ],
          if (!reviewer && tasks.isNotEmpty) ...[
            _sectionTitle('My tasks', action: tasks.length > _maxTasks ? 'View all' : null, onAction: () => onOpenTab(1)),
            _list(tasks.length.clamp(0, _maxTasks), (i) => _TaskCard(task: tasks[i])),
          ],
          if (recent.isNotEmpty) ...[
            _sectionTitle('Recent activity', action: 'Timeline', onAction: () => onOpenTab(3)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < recent.length; i++) ActivityTile(event: recent[i], isLast: i == recent.length - 1),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (attention.isEmpty && drafts.isEmpty && (reviewer || tasks.isEmpty) && recent.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline, color: AdinnColors.success),
                    title: Text('All caught up'),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  /// The home page stays short: at most this many rows per section; the rest is one tap away ("View all").
  static const _maxShops = 2;
  static const _maxTasks = 3;

  static Widget _sectionTitle(String text, {Key? key, String? action, VoidCallback? onAction}) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    sliver: SliverToBoxAdapter(child: _SectionTitle(text, key: key, action: action, onAction: onAction)),
  );

  static Widget _list(int count, Widget Function(int) item) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    sliver: SliverList.separated(itemCount: count, separatorBuilder: (_, _) => const SizedBox(height: 10), itemBuilder: (_, i) => item(i)),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.greeting,
    required this.user,
    required this.subtitle,
  });

  final String greeting;
  final AppUser user;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AdinnColors.red, AdinnColors.redDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const AdinnLogo(size: 30, light: true),
                  const SizedBox(width: 12),
                  const Spacer(),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        user.role.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Avatar(user.initials, size: 48, light: true),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$greeting,',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        Text(
                          user.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${fmtDate(DateTime.now())} • $subtitle',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {super.key, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final RecceTask task;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final project = c.project(task.projectId);
    final sum = c.taskSummary(task.id);
    final daysLeft = task.dueDate.difference(DateTime.now()).inDays;
    final dueColor = daysLeft < 0
        ? AdinnColors.red
        : daysLeft <= 3
        ? AdinnColors.warning
        : AdinnColors.muted;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TaskDetailScreen(taskId: task.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TagChip(
                    task.priority,
                    color: task.priority == 'High'
                        ? AdinnColors.red
                        : AdinnColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${project?.name ?? ''} • ${task.city}',
                style: const TextStyle(color: AdinnColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              ProgressBarLabel(
                value: sum.submittedRatio,
                label:
                    '${sum.pending + sum.approved}/${sum.total} shops submitted • ${sum.label}',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.event, size: 14, color: dueColor),
                  const SizedBox(width: 4),
                  Text(
                    daysLeft < 0
                        ? 'Overdue since ${fmtDate(task.dueDate)}'
                        : 'Due ${fmtDate(task.dueDate)} ($daysLeft day${daysLeft == 1 ? '' : 's'} left)',
                    style: TextStyle(fontSize: 12, color: dueColor),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
