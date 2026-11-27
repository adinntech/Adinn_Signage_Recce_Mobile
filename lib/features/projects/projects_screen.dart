import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/language_switcher.dart';
import '../../l10n/l10n.dart';
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
    final projects = c.projects.where((p) {
      if (q.isEmpty) return true;
      // Search keeps matching the original stored name/code/region and also
      // accepts an approved Tamil display name/region. Record identity does
      // not change.
      return p.name.toLowerCase().contains(q) ||
          context.projectName(p.id, p.name).toLowerCase().contains(q) ||
          p.code.toLowerCase().contains(q) ||
          p.region.toLowerCase().contains(q) ||
          context.regionLabel(p.region).toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t.projectsTitle),
        actions: const [LanguageSwitcher(), SizedBox(width: 8)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: context.t.searchProjects,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: projects.isEmpty
                ? EmptyState(
                    icon: Icons.folder_off_outlined,
                    title: context.ui('No projects found'),
                    message: context.ui('Projects assigned to you will appear here.'),
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
                      context.projectName(project.id, project.name).substring(0, 1),
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
                          context.projectName(project.id, project.name),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${project.code} • ${context.regionLabel(project.region)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AdinnColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TagChip(
                    context.statusSingular(sum.label),
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
                context.projectDescription(project.id, project.description),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              ProgressBarLabel(
                value: sum.approvedRatio,
                label: context.shopsApproved(sum.approved, sum.total),
                color: AdinnColors.success,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  TagChip(
                    context.taskCount(tasks.length),
                    icon: Icons.assignment_outlined,
                  ),
                  TagChip(
                    context.shopCount(sum.total),
                    icon: Icons.storefront,
                  ),
                  TagChip(
                    context.endsOn(project.endDate),
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
