import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../shop/shop_tile.dart';

/// Activity timeline – everything, or filtered to one shop.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, this.shopId});

  final String? shopId;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _kind = 'all';

  static const _filters = {
    'all': 'All',
    'submitted': 'Submissions',
    'approved': 'Approvals',
    'rejected': 'Rejections',
    'updated': 'Edits',
  };

  bool _match(ActivityEvent e) {
    if (_kind == 'all') return true;
    if (_kind == 'updated') {
      return e.kind == 'updated' ||
          e.kind == 'created' ||
          e.kind == 'photo' ||
          e.kind == 'note';
    }
    return e.kind == _kind;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final events = c.activities(shopId: widget.shopId).where(_match).toList();
    final shop = widget.shopId == null ? null : c.shop(widget.shopId!);

    // Group by calendar day.
    final groups = <String, List<ActivityEvent>>{};
    for (final e in events) {
      groups.putIfAbsent(fmtDate(e.at), () => []).add(e);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          shop == null ? 'Activity Timeline' : 'Timeline • ${shop.name}',
        ),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                for (final f in _filters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.value),
                      selected: _kind == f.key,
                      onSelected: (_) => setState(() => _kind = f.key),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: events.isEmpty
                ? const EmptyState(
                    icon: Icons.timeline,
                    title: 'No activity yet',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      for (final g in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                          child: Text(
                            g.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AdinnColors.muted,
                            ),
                          ),
                        ),
                        Card(
                          child: Column(
                            children: [
                              for (var i = 0; i < g.value.length; i++)
                                ActivityTile(
                                  event: g.value[i],
                                  isLast: i == g.value.length - 1,
                                  openShop: widget.shopId == null,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class ActivityTile extends StatelessWidget {
  const ActivityTile({
    super.key,
    required this.event,
    this.isLast = false,
    this.openShop = true,
  });

  final ActivityEvent event;
  final bool isLast;
  final bool openShop;

  (IconData, Color) get _style => switch (event.kind) {
    'submitted' => (Icons.send, AdinnColors.info),
    'approved' => (Icons.verified, AdinnColors.success),
    'rejected' => (Icons.cancel, AdinnColors.red),
    'created' => (Icons.add_circle_outline, AdinnColors.purple),
    'auth' => (Icons.lock_outline, AdinnColors.muted),
    _ => (Icons.edit_outlined, AdinnColors.warning),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _style;
    final shopId = event.shopId;
    final canOpen =
        openShop &&
        shopId != null &&
        context.read<AppController>().shop(shopId) != null;
    return InkWell(
      onTap: canOpen ? () => openShopById(context, shopId) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(icon, size: 16, color: color),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: AdinnColors.line,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(event.message, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        '${event.actorName}${event.actorRole == null ? '' : ' (${event.actorRole!.label})'} • ${fmtRelative(event.at)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AdinnColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void openShopById(BuildContext context, String shopId) =>
    openShop(context, shopId);
