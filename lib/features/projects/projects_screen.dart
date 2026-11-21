import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import 'project_detail_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final q = _query.toLowerCase();
    final projects = c.projects
        .where(
          (p) =>
              q.isEmpty ||
              p.name.toLowerCase().contains(q) ||
              p.code.toLowerCase().contains(q) ||
              p.region.toLowerCase().contains(q),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search project, code or region',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: projects.isEmpty
                ? const EmptyState(
                    icon: Icons.folder_off_outlined,
                    title: 'No projects found',
                    message: 'Projects assigned to you will appear here.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: projects.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => ProjectCard(project: projects[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final sum = c.projectSummary(project.id);
    final tasks = c.tasksForProject(project.id);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProjectDetailScreen(projectId: project.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AdinnColors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      project.name.substring(0, 1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${project.code} • ${project.region}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AdinnColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TagChip(
                    sum.label,
                    color: sum.rejected > 0
                        ? AdinnColors.red
                        : sum.approved == sum.total && sum.total > 0
                        ? AdinnColors.success
                        : AdinnColors.info,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                project.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              ProgressBarLabel(
                value: sum.approvedRatio,
                label: '${sum.approved}/${sum.total} shops approved',
                color: AdinnColors.success,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  TagChip(
                    '${tasks.length} task${tasks.length == 1 ? '' : 's'}',
                    icon: Icons.assignment_outlined,
                  ),
                  TagChip(
                    '${sum.total} shop${sum.total == 1 ? '' : 's'}',
                    icon: Icons.storefront,
                  ),
                  TagChip(
                    'Ends ${fmtDate(project.endDate)}',
                    icon: Icons.event,
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
