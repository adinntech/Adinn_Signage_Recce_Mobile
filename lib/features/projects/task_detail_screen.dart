import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/language_switcher.dart';
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
        body: EmptyState(
          icon: Icons.search_off,
          title: context.ui('Task not found'),
        ),
      );
    }
    final project = c.project(task.projectId);
    final all = c.shopsForTask(task.id);
    final shops = all.where(_matches).toList();
    final sum = ProgressSummary(all);
    final canAdd = c.isVendor && task.assignedVendorId == c.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.taskTitle(task)),
        actions: const [LanguageSwitcher(), SizedBox(width: 8)],
      ),
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
              label: Text(context.ui('Add Shop')),
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
                        project == null
                            ? ''
                            : context.projectName(project.id, project.name),
                        style: const TextStyle(
                          color: AdinnColors.red,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TagChip(
                      context.priorityBadge(task.priority),
                      color: task.priority == 'High'
                          ? AdinnColors.red
                          : AdinnColors.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                InfoRow(
                  context.ui('Location'),
                  '${context.locationLabel(task.location)}, ${context.locationLabel(task.city)}',
                  icon: Icons.place_outlined,
                ),
                InfoRow(
                  context.ui('Due date'),
                  context.fmtDateL(task.dueDate),
                  icon: Icons.event_outlined,
                ),
                InfoRow(
                  context.ui('Assigned to'),
                  context.personName(
                    c.userById(task.assignedVendorId)?.name ?? '—',
                  ),
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
                      '${context.ui('Instructions')}: ${task.instructions}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ProgressBarLabel(
                  value: sum.submittedRatio,
                  label: context.shopsSubmittedSummary(
                    sum.pending + sum.approved,
                    sum.total,
                    sum.label,
                  ),
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
                        _ShopFilter.all => context.uf('All ({0})', [
                          all.length,
                        ]),
                        _ShopFilter.todo => context.uf('To do ({0})', [
                          sum.notStarted + sum.inProgress,
                        ]),
                        _ShopFilter.submitted => context.uf('Submitted ({0})', [
                          sum.pending,
                        ]),
                        _ShopFilter.approved => context.uf('Approved ({0})', [
                          sum.approved,
                        ]),
                        _ShopFilter.rejected => context.uf('Rejected ({0})', [
                          sum.rejected,
                        ]),
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
              title: context.ui(
                all.isEmpty ? 'No shops yet' : 'No shops in this filter',
              ),
              message: all.isEmpty && canAdd
                  ? context.ui(
                      'Tap "Add Shop" to start a recce for this location.',
                    )
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
