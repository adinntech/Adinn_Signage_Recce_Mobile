import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
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
        body: const EmptyState(
          icon: Icons.folder_off_outlined,
          title: 'Project not found',
        ),
      );
    }
    final tasks = c.tasksForProject(projectId);
    final sum = c.projectSummary(projectId);

    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'Project details',
            icon: Icons.info_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(project.description),
                const SizedBox(height: 10),
                InfoRow('Client', project.client),
                InfoRow('Project code', project.code),
                InfoRow('Region', project.region),
                InfoRow(
                  'Duration',
                  '${fmtDate(project.startDate)} – ${fmtDate(project.endDate)}',
                ),
                InfoRow('Coordinator', project.coordinatorName),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () =>
                      dialNumber(context, project.coordinatorPhone),
                  icon: const Icon(Icons.call_outlined),
                  label: Text('Call coordinator (${project.coordinatorPhone})'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Shop status',
            icon: Icons.pie_chart_outline,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Count('Total', sum.total, AdinnColors.ink),
                _Count('Not started', sum.notStarted, AdinnColors.muted),
                _Count('In progress', sum.inProgress, AdinnColors.info),
                _Count('Pending', sum.pending, AdinnColors.warning),
                _Count('Approved', sum.approved, AdinnColors.success),
                _Count('Rejected', sum.rejected, AdinnColors.red),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Recce tasks',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (tasks.isEmpty)
            const EmptyState(
              icon: Icons.assignment_outlined,
              title: 'No tasks assigned',
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
                                  t.title,
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
                            '${t.location}, ${t.city} • Due ${fmtDate(t.dueDate)}',
                            style: const TextStyle(
                              color: AdinnColors.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ProgressBarLabel(
                            value: ts.submittedRatio,
                            label: '${ts.total} shops • ${ts.label}',
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
      width: 96,
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
            style: const TextStyle(fontSize: 11, color: AdinnColors.muted),
          ),
        ],
      ),
    );
  }
}
