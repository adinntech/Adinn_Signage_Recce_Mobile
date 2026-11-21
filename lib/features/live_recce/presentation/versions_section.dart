import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/live_services.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';
import 'live_widgets.dart';
import 'version_compare_screen.dart';

/// "Versions" of the Review tab: V1, V2... each with who and when it was submitted, the decision of every review stage,
/// the boards, the installation answers and the photo count. The list comes from `GET /recce/shops/:siteId/versions`.
class VersionsSection extends StatelessWidget {
  const VersionsSection({super.key, required this.ctrl});

  final ShopDetailController ctrl;

  void _compare(BuildContext context) {
    final api = context.read<LiveServices>().api;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => VersionCompareScreen(api: api, siteId: ctrl.siteId, shopTitle: ctrl.detail?.title ?? 'Shop', versions: ctrl.versionList),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final versions = ctrl.versionList;
    final submitted = (ctrl.detail?.version ?? 0) > 0;
    return SectionCard(
      title: 'Versions',
      icon: Icons.history,
      trailing: versions.length >= 2
          ? TextButton.icon(onPressed: () => _compare(context), icon: const Icon(Icons.compare_arrows, size: 18), label: const Text('Compare'))
          : null,
      child: _body(context, versions, submitted),
    );
  }

  Widget _body(BuildContext context, List<RecceVersion> versions, bool submitted) {
    if (!submitted && versions.isEmpty) return const Text('Nothing submitted yet.', style: TextStyle(color: AdinnColors.muted));
    if (ctrl.versionsLoading && versions.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    if (ctrl.versionsError != null && versions.isEmpty) {
      return Row(children: [
        Expanded(child: Text(ctrl.versionsError!, style: const TextStyle(color: AdinnColors.red))),
        TextButton.icon(onPressed: () => ctrl.loadVersions(force: true), icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]);
    }
    if (versions.isEmpty) return const Text('Nothing submitted yet.', style: TextStyle(color: AdinnColors.muted));
    return Column(children: [for (final v in versions) VersionTile(version: v, initiallyExpanded: v.current)]);
  }
}

/// One version row: "V1 - GSB 6 x 4 ft - Rework Required"; tap to see the decisions, boards, installation and photos.
class VersionTile extends StatelessWidget {
  const VersionTile({super.key, required this.version, this.initiallyExpanded = false});

  final RecceVersion version;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final v = version;
    final color = statusColor(v.status);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey('version-${v.version}'),
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 4, bottom: 10),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: CircleAvatar(radius: 15, backgroundColor: color.withValues(alpha: 0.12), child: Text('V${v.version}', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11))),
        title: Text(v.rowTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(
          [
            if (v.submittedAt != null) fmtDateTime(v.submittedAt!),
            if (v.submittedBy != null) 'by ${v.submittedBy}',
            '${v.photos.length} photo${v.photos.length == 1 ? '' : 's'}',
            if (v.current) 'Latest',
          ].join('  |  '),
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          const _Label('Review'),
          if (v.decisions.isEmpty)
            const Text('No review decisions yet.', style: TextStyle(color: AdinnColors.muted, fontSize: 13))
          else
            for (final d in v.orderedDecisions) StageDecisionTile(d, dense: true),
          const _Label('Boards'),
          if (v.mediaItems.isEmpty)
            const Text('No boards.', style: TextStyle(color: AdinnColors.muted, fontSize: 13))
          else
            for (final b in v.mediaItems) Text('${b.key}: ${boardSummaryText(b)}', style: const TextStyle(fontSize: 13)),
          const _Label('Installation'),
          Text(v.installationSummary, style: const TextStyle(fontSize: 13)),
          if (v.notes.isNotEmpty) ...[const _Label('Notes'), Text(v.notes, style: const TextStyle(fontSize: 13))],
          if (v.reworks.isNotEmpty) ...[
            const _Label('Rework requests'),
            for (final r in v.reworks)
              Text(
                '${r.stageLabel}: ${r.instructions.isEmpty ? 'rework requested' : r.instructions}${r.isOpen ? '' : ' (done)'}',
                style: const TextStyle(fontSize: 13),
              ),
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AdinnColors.muted, letterSpacing: 0.6)),
      );
}
