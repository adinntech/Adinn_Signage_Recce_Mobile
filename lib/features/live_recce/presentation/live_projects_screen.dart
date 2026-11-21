import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';
import 'live_shops_screen.dart';
import 'live_widgets.dart';
import 'notifications_screen.dart';

/// Assigned Projects: the shops given to this login, grouped by project.
class LiveProjectsScreen extends StatelessWidget {
  const LiveProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final list = context.watch<ShopListController>();
    final projects = list.projects;
    return Scaffold(
      appBar: AppBar(title: const Text('Assigned projects'), actions: const [NotificationBell()]),
      body: !list.loaded && list.loading
          ? const Center(child: CircularProgressIndicator())
          : !list.loaded && list.error != null
              ? ErrorRetry(message: list.error!, onRetry: list.load)
              : RefreshIndicator(
                  onRefresh: list.load,
                  color: AdinnColors.red,
                  child: projects.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 60),
                          EmptyState(icon: Icons.folder_open_outlined, title: 'No projects yet', message: 'Projects with shops assigned to you appear here.'),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: projects.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _ProjectCard(projects[i]),
                        ),
                ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard(this.p);
  final ProjectGroup p;

  @override
  Widget build(BuildContext context) {
    final total = p.shops.length;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => LiveShopsScreen(projectId: p.projectId, title: p.code)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(p.code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  const Icon(Icons.chevron_right, color: AdinnColors.muted),
                ],
              ),
              Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              if ((p.client ?? '').isNotEmpty) Text(p.client!, style: const TextStyle(color: AdinnColors.muted, fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  TagChip('$total shop${total == 1 ? '' : 's'}', icon: Icons.storefront_outlined),
                  if (p.submitted > 0) TagChip('${p.submitted} submitted', color: statusColor('SUBMITTED')),
                  if (p.done > 0) TagChip('${p.done} approved', color: statusColor('APPROVED')),
                  if (p.rework > 0) TagChip('${p.rework} rework', color: statusColor('REWORK_REQUIRED')),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : p.done / total,
                  minHeight: 6,
                  color: statusColor('APPROVED'),
                  backgroundColor: AdinnColors.line,
                ),
              ),
              if (p.expectedBy != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Expected by ${fmtDate(p.expectedBy!)}', style: const TextStyle(color: AdinnColors.muted, fontSize: 12))),
            ],
          ),
        ),
      ),
    );
  }
}
