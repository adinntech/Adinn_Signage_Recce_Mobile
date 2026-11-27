import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../../state/version_diff.dart';
import 'activity_screen.dart';
import 'snapshot_view.dart';
import '../../core/widgets/adinn_app_bar.dart';

/// All submitted versions of a shop recce with their review outcome.
class VersionHistoryScreen extends StatelessWidget {
  const VersionHistoryScreen({super.key, required this.shopId});

  final String shopId;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(shopId);
    if (shop == null) {
      return Scaffold(
        appBar: AdinnAppBar(),
        body: EmptyState(
          icon: Icons.search_off,
          title: context.ui('Shop not found'),
        ),
      );
    }
    final versions = shop.submissions.reversed.toList();

    return Scaffold(
      appBar: AdinnAppBar(
        title: Text(context.ui('Version History')),
        actions: [
          IconButton(
            tooltip: context.ui('Activity timeline'),
            icon: const Icon(Icons.timeline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ActivityScreen(shopId: shopId),
              ),
            ),
          ),
        ],
      ),
      body: versions.isEmpty
          ? EmptyState(
              icon: Icons.history_toggle_off,
              title: context.ui('Not submitted yet'),
              message: context.ui('Each submission creates a new locked version here.'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: versions.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Text(
                    '${shop.name} • ${context.uf('{0} version(s)', [versions.length])} • '
                    '${context.ui('current')}: ${context.statusLabel(shop.status)}',
                    style: const TextStyle(color: AdinnColors.muted),
                  );
                }
                final sub = versions[i - 1];
                final idx = shop.submissions.indexOf(sub);
                final prev = idx > 0 ? shop.submissions[idx - 1] : null;
                return _VersionCard(
                  shopId: shopId,
                  submission: sub,
                  previous: prev,
                  isLatest: i == 1,
                );
              },
            ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.shopId,
    required this.submission,
    required this.previous,
    required this.isLatest,
  });

  final String shopId;
  final Submission submission;
  final Submission? previous;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final outcome = submission.outcome;
    final changes = diffShops(previous?.shopSnapshot, submission.shopSnapshot);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VersionDetailScreen(
              shopId: shopId,
              version: submission.version,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AdinnColors.ink,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'v${submission.version}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isLatest)
                    const TagChip('Latest', color: AdinnColors.info),
                  const Spacer(),
                  StatusChip(outcome, compact: true),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Submitted ${fmtDateTime(submission.submittedAt)} by ${submission.submittedByName}',
                style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
              ),
              const SizedBox(height: 8),
              for (final ch in changes.take(4))
                Text('• $ch', style: const TextStyle(fontSize: 13)),
              if (changes.length > 4)
                Text(
                  '+${changes.length - 4} more change(s)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdinnColors.muted,
                  ),
                ),
              for (final r in submission.reviews) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        (r.decision == ReviewDecision.approved
                                ? AdinnColors.success
                                : AdinnColors.red)
                            .withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${r.stage.label} ${r.decision == ReviewDecision.approved ? 'approved' : 'rejected'} – ${r.reviewerName}'
                    '${r.remarks.isEmpty ? '' : ': "${r.remarks}"'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(context.ui('View snapshot ›'),
                  style: TextStyle(
                    color: AdinnColors.red,
                    fontWeight: FontWeight.w700,
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

/// Read-only view of exactly what was submitted in one version.
class VersionDetailScreen extends StatelessWidget {
  const VersionDetailScreen({
    super.key,
    required this.shopId,
    required this.version,
  });

  final String shopId;
  final int version;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final sub = c
        .shop(shopId)
        ?.submissions
        .where((s) => s.version == version)
        .firstOrNull;
    if (sub == null) {
      return Scaffold(
        appBar: AdinnAppBar(),
        body: EmptyState(
          icon: Icons.search_off,
          title: context.ui('Version not found'),
        ),
      );
    }
    return Scaffold(
      appBar: AdinnAppBar(title: Text(context.uf('Version v{0} (locked)', [version]))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: context.ui('Approval trail'),
            icon: Icons.route_outlined,
            trailing: StatusChip(sub.outcome, compact: true),
            child: ReviewTrail(submission: sub),
          ),
          const SizedBox(height: 12),
          ShopSnapshotView(shop: sub.shopSnapshot),
        ],
      ),
    );
  }
}
