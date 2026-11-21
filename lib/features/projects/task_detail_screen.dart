import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../shop/shop_form_screen.dart';
import '../shop/shop_tile.dart';

enum _ShopFilter { all, todo, submitted, approved, rejected }

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  _ShopFilter _filter = _ShopFilter.all;

  bool _matches(Shop s) => switch (_filter) {
    _ShopFilter.all => true,
    _ShopFilter.todo =>
      s.status == RecceStatus.notStarted || s.status == RecceStatus.inProgress,
    _ShopFilter.submitted => s.status.isPending,
    _ShopFilter.approved => s.status == RecceStatus.approved,
    _ShopFilter.rejected => s.status.isRejected,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final task = c.task(widget.taskId);
    if (task == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.search_off, title: 'Task not found'),
      );
    }
    final project = c.project(task.projectId);
    final all = c.shopsForTask(task.id);
    final shops = all.where(_matches).toList();
    final sum = ProgressSummary(all);
    final canAdd = c.isVendor && task.assignedVendorId == c.currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: Text(task.title)),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              heroTag: 'add_shop',
              backgroundColor: AdinnColors.red,
              foregroundColor: Colors.white,
              onPressed: () async {
                final created = await Navigator.of(context).push<Shop>(
                  MaterialPageRoute(
                    builder: (_) => ShopFormScreen(taskId: task.id),
                  ),
                );
                if (created != null && context.mounted) {
                  openShop(context, created.id);
                }
              },
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Add Shop'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        project?.name ?? '',
                        style: const TextStyle(
                          color: AdinnColors.red,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TagChip(
                      '${task.priority} priority',
                      color: task.priority == 'High'
                          ? AdinnColors.red
                          : AdinnColors.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                InfoRow(
                  'Location',
                  '${task.location}, ${task.city}',
                  icon: Icons.place_outlined,
                ),
                InfoRow(
                  'Due date',
                  fmtDate(task.dueDate),
                  icon: Icons.event_outlined,
                ),
                InfoRow(
                  'Assigned to',
                  c.userById(task.assignedVendorId)?.name ?? '—',
                  icon: Icons.engineering_outlined,
                ),
                if (task.instructions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Instructions: ${task.instructions}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ProgressBarLabel(
                  value: sum.submittedRatio,
                  label:
                      '${sum.pending + sum.approved}/${sum.total} shops submitted • ${sum.label}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in _ShopFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(switch (f) {
                        _ShopFilter.all => 'All (${all.length})',
                        _ShopFilter.todo =>
                          'To do (${sum.notStarted + sum.inProgress})',
                        _ShopFilter.submitted => 'Submitted (${sum.pending})',
                        _ShopFilter.approved => 'Approved (${sum.approved})',
                        _ShopFilter.rejected => 'Rejected (${sum.rejected})',
                      }),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (shops.isEmpty)
            EmptyState(
              icon: Icons.storefront_outlined,
              title: all.isEmpty ? 'No shops yet' : 'No shops in this filter',
              message: all.isEmpty && canAdd
                  ? 'Tap "Add Shop" to start a recce for this location.'
                  : null,
            ),
          for (final s in shops) ...[
            ShopTile(shop: s),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
