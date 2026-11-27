import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/language_switcher.dart';
import '../../state/app_controller.dart';
import 'task_detail_screen.dart';

class ProjectDetailScreen extends StatelessWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final project = c.project(projectId);
    if (project == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.folder_off_outlined,
          title: context.ui('Project not found'),
        ),
      );
    }
    final tasks = c.tasksForProject(projectId);
    final sum = c.projectSummary(projectId);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.projectName(project.id, project.name)),
        actions: const [LanguageSwitcher(), SizedBox(width: 8)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: context.ui('Project details'),
            icon: Icons.info_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.projectDescription(project.id, project.description),
                ),
                const SizedBox(height: 10),
                InfoRow(context.ui('Client'), project.client),
                InfoRow(context.ui('Project code'), project.code),
                InfoRow(
                  context.ui('Region'),
                  context.regionLabel(project.region),
                ),
                InfoRow(
                  context.ui('Duration'),
                  context.dateRange(project.startDate, project.endDate),
                ),
                InfoRow(context.ui('Coordinator'), project.coordinatorName),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () =>
                      dialNumber(context, project.coordinatorPhone),
                  icon: const Icon(Icons.call_outlined),
                  label: Text(
                    context.uf('Call coordinator ({0})', [
                      project.coordinatorPhone,
                    ]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: context.ui('Shop status'),
            icon: Icons.pie_chart_outline,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Count(context.ui('Total'), sum.total, AdinnColors.ink),
                _Count(
                  context.ui('Not started'),
                  sum.notStarted,
                  AdinnColors.muted,
                ),
                _Count(
                  context.ui('In progress'),
                  sum.inProgress,
                  AdinnColors.info,
                ),
                _Count(context.ui('Pending'), sum.pending, AdinnColors.warning),
                _Count(
                  context.ui('Approved'),
                  sum.approved,
                  AdinnColors.success,
                ),
                _Count(context.ui('Rejected'), sum.rejected, AdinnColors.red),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            context.ui('Recce tasks'),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (tasks.isEmpty)
            EmptyState(
              icon: Icons.assignment_outlined,
              title: context.ui('No tasks assigned'),
            ),
          for (final t in tasks) ...[
            Builder(
              builder: (context) {
                final ts = c.taskSummary(t.id);
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TaskDetailScreen(taskId: t.id),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.assignment_outlined,
                                color: AdinnColors.red,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  context.taskTitle(t),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${t.location}, ${t.city} • ${context.dueOn(t.dueDate)}',
                            style: const TextStyle(
                              color: AdinnColors.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ProgressBarLabel(
                            value: ts.submittedRatio,
                            label: context.shopsWithStatus(ts.total, ts.label),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.isTamil ? 108 : 96,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 11, color: AdinnColors.muted),
          ),
        ],
      ),
    );
  }
}
