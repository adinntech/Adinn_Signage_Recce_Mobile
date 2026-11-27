import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/language_switcher.dart';
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
    final recent = c.activities().take(4).toList();
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
                  ? context.reccesAwaitApproval(c.pendingReviews.length)
                  : context.shopsNeedFieldWork(
                      sum.notStarted + sum.inProgress + sum.rejected,
                    ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: ListTile(
                  key: const Key('dashboard_search'),
                  leading: const Icon(Icons.search),
                  title: Text(
                    context.ui('Search shops, owners, areas, projects'),
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
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _StatsGrid(
                reviewer: reviewer,
                summary: sum,
                awaiting: c.pendingReviews.length,
                reviewed: c.reviewedByMe.length,
                onTap: onOpenTab,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: SectionCard(
                title: context.ui('Overall progress'),
                icon: Icons.insights_outlined,
                child: Column(
                  children: [
                    ProgressBarLabel(
                      value: sum.submittedRatio,
                      label: context.ui('Submitted for approval'),
                      color: AdinnColors.info,
                    ),
                    const SizedBox(height: 12),
                    ProgressBarLabel(
                      value: sum.approvedRatio,
                      label: context.ui('Final approved'),
                      color: AdinnColors.success,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            sliver: SliverToBoxAdapter(
              child: _SectionTitle(
                context.ui(
                  reviewer ? 'Awaiting your approval' : 'Needs rework',
                ),
                action: attention.isEmpty ? null : context.ui('View all'),
                onAction: () => onOpenTab(2),
              ),
            ),
          ),
          if (attention.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.check_circle_outline,
                      color: AdinnColors.success,
                    ),
                    title: Text(
                      context.ui(
                        reviewer
                            ? 'No pending approvals'
                            : 'No rejected recces – great work!',
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: attention.take(3).length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) =>
                    ShopTile(shop: attention[i], showProject: true),
              ),
            ),
          if (drafts.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _SectionTitle(
                  context.ui('Continue where you left off'),
                  key: const Key('continue_drafts'),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: drafts.take(3).length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) =>
                    ShopTile(shop: drafts[i], showProject: true),
              ),
            ),
          ],
          if (!reviewer) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _SectionTitle(context.ui('My tasks')),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: tasks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _TaskCard(task: tasks[i]),
              ),
            ),
          ],
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            sliver: SliverToBoxAdapter(
              child: _SectionTitle(
                context.ui('Recent activity'),
                action: context.ui('Timeline'),
                onAction: () => onOpenTab(3),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: Column(
                  children: [
                    if (recent.isEmpty)
                      ListTile(title: Text(context.ui('No activity yet'))),
                    for (var i = 0; i < recent.length; i++)
                      ActivityTile(
                        event: recent[i],
                        isLast: i == recent.length - 1,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
                  const AdinnLogo(size: 26, light: true),
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
                        context.ui(user.role.label),
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
                  const SizedBox(width: 6),
                  const LanguageSwitcher(light: true),
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
                          '${context.ui(greeting)},',
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
                '${context.fmtDateL(DateTime.now())} • $subtitle',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.reviewer,
    required this.summary,
    required this.awaiting,
    required this.reviewed,
    required this.onTap,
  });

  final bool reviewer;
  final ProgressSummary summary;
  final int awaiting;
  final int reviewed;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final items = reviewer
        ? [
            _Stat(
              'Awaiting you',
              awaiting,
              Icons.pending_actions,
              AdinnColors.warning,
              2,
            ),
            _Stat(
              'Reviewed by you',
              reviewed,
              Icons.task_alt,
              AdinnColors.info,
              2,
            ),
            _Stat(
              'Final approved',
              summary.approved,
              Icons.verified,
              AdinnColors.success,
              1,
            ),
            _Stat(
              'Rejected',
              summary.rejected,
              Icons.report_gmailerrorred,
              AdinnColors.red,
              1,
            ),
          ]
        : [
            _Stat(
              'Assigned shops',
              summary.total,
              Icons.storefront,
              AdinnColors.ink,
              1,
            ),
            _Stat(
              'In progress',
              summary.inProgress + summary.notStarted,
              Icons.edit_note,
              AdinnColors.info,
              1,
            ),
            _Stat(
              'Pending approval',
              summary.pending,
              Icons.hourglass_top,
              AdinnColors.warning,
              2,
            ),
            _Stat(
              'Approved',
              summary.approved,
              Icons.verified,
              AdinnColors.success,
              2,
            ),
            _Stat(
              'Rejected',
              summary.rejected,
              Icons.report_gmailerrorred,
              AdinnColors.red,
              2,
            ),
            _Stat('Projects', -1, Icons.folder_open, AdinnColors.purple, 1),
          ];

    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth > 560 ? 3 : 2;
        return GridView.count(
          crossAxisCount: cols,
          // Without this, GridView adds the status-bar inset as top padding.
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          // Tamil labels need room to wrap to a second line.
          childAspectRatio: context.isTamil ? 1.5 : 2.1,
          children: [
            for (final s in items)
              _StatTile(
                stat: s,
                value: s.value >= 0
                    ? '${s.value}'
                    : '${context.read<AppController>().projects.length}',
                onTap: () => onTap(s.tab),
              ),
          ],
        );
      },
    );
  }
}

class _Stat {
  const _Stat(this.label, this.value, this.icon, this.color, this.tab);
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final int tab;
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.stat,
    required this.value,
    required this.onTap,
  });

  final _Stat stat;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: stat.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(stat.icon, color: stat.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      context.ui(stat.label),
                      maxLines: context.isTamil ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdinnColors.muted,
                      ),
                    ),
                  ],
                ),
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
                      context.taskTitle(task),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TagChip(
                    context.priorityLabel(task.priority),
                    color: task.priority == 'High'
                        ? AdinnColors.red
                        : AdinnColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${project == null ? '' : context.projectName(project.id, project.name)} • ${task.city}',
                style: const TextStyle(color: AdinnColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              ProgressBarLabel(
                value: sum.submittedRatio,
                label: context.shopsSubmittedSummary(
                  sum.pending + sum.approved,
                  sum.total,
                  sum.label,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.event, size: 14, color: dueColor),
                  const SizedBox(width: 4),
                  Text(
                    daysLeft < 0
                        ? context.uf('Overdue since {0}', [
                            context.fmtDateL(task.dueDate),
                          ])
                        : context.uf(
                            daysLeft == 1
                                ? 'Due {0} ({1} day left)'
                                : 'Due {0} ({1} days left)',
                            [context.fmtDateL(task.dueDate), daysLeft],
                          ),
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
