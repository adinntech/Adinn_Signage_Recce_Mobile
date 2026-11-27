import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import 'shop_detail_screen.dart';

void openShop(BuildContext context, String shopId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ShopDetailScreen(shopId: shopId)),
  );
}

/// Compact card for a shop used in task lists, approvals and dashboard.
class ShopTile extends StatelessWidget {
  const ShopTile({super.key, required this.shop, this.showProject = false, this.compact = false});

  final Shop shop;
  final bool showProject;

  /// Home page version: name, project line, status and board count only (no media chips, no version chip).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.read<AppController>();
    final project = c.project(shop.projectId);
    final task = c.task(shop.taskId);
    final medias = shop.boards
        .map((b) => SignageCatalog.media(b.mediaCode)?.shortName)
        .whereType<String>()
        .toSet();
    final sub = shop.latestSubmission;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openShop(context, shop.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AdinnColors.redLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.storefront, color: AdinnColors.red),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shop.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          showProject
                              ? '${project?.name ?? ''} • ${task?.title ?? ''}'
                              : shop.fullAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AdinnColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AdinnColors.muted),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusChip(shop.status, compact: true),
                  TagChip(
                    '${shop.boards.length} board${shop.boards.length == 1 ? '' : 's'}',
                    icon: Icons.dashboard_customize_outlined,
                  ),
                  if (!compact)
                    for (final m in medias) TagChip(m, color: AdinnColors.red),
                  if (!compact && sub != null)
                    TagChip(
                      'v${sub.version} • ${fmtRelative(sub.submittedAt)}',
                      icon: Icons.history,
                      color: AdinnColors.info,
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
