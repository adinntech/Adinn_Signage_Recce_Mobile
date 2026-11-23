import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/recce_models.dart';

/// One number of the dashboard: label with icon, the value big, an optional line under it. Tappable only when [onTap] is given.
class KpiCard extends StatelessWidget {
  const KpiCard(this.label, this.value, this.icon, this.color, {super.key, this.subtitle, this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 6),
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AdinnColors.muted, fontWeight: FontWeight.w600))),
              ]),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color))),
              if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AdinnColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card height at the normal text size: 28 px padding + label row + the 28 px value + a one-line subtitle, with a few px to spare
/// (102 was 2 px short and showed the "BOTTOM OVERFLOWED" stripes).
const kpiCardHeight = 112.0;

/// A two-column grid of [KpiCard]s. The card height is fixed, so a longer line never changes the layout, and it grows with the
/// phone's text-size setting (up to 1.6 x) so a person with large text does not see an overflow either.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.cards});
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.6);
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: kpiCardHeight * scale),
      children: cards,
    );
  }
}

/// The colours of the project bar parts, and what they mean.
const progressBarColors = (
  approved: AdinnColors.success,
  rework: AdinnColors.warning,
  inReview: AdinnColors.info,
  working: AdinnColors.purple,
  notStarted: AdinnColors.line,
);

/// One horizontal bar: approved, rework, waiting for a reviewer, started, not started (see [ProgressBar]).
class ProgressBarView extends StatelessWidget {
  const ProgressBarView(this.bar, {super.key});
  final ProgressBar bar;

  @override
  Widget build(BuildContext context) {
    final parts = [
      (bar.approved, progressBarColors.approved),
      (bar.rework, progressBarColors.rework),
      (bar.inReview, progressBarColors.inReview),
      (bar.working, progressBarColors.working),
      (bar.notStarted, progressBarColors.notStarted),
    ].where((p) => p.$1 > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 10,
        child: parts.isEmpty
            ? const ColoredBox(color: AdinnColors.line)
            : Row(children: [for (final p in parts) Expanded(flex: p.$1, child: ColoredBox(color: p.$2))]),
      ),
    );
  }
}

/// A project of the dashboard: its code and name, the bar, and the six counts.
class ProjectProgressCard extends StatelessWidget {
  const ProjectProgressCard({super.key, required this.project, required this.onTap});

  final ProjectProgress project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = project;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(p.projectCode.isEmpty ? 'Project' : p.projectCode, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                const Icon(Icons.chevron_right, color: AdinnColors.muted),
              ]),
              if (p.projectName.isNotEmpty) Text(p.projectName, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              ProgressBarView(p.bar),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  TagChip('Assigned ${p.assigned}', icon: Icons.storefront_outlined),
                  TagChip('Started ${p.started}', color: progressBarColors.working),
                  TagChip('Submitted ${p.submitted}', color: progressBarColors.inReview),
                  TagChip('Approved ${p.approved}', color: progressBarColors.approved),
                  TagChip('Rework ${p.rework}', color: progressBarColors.rework),
                  TagChip('Pending ${p.pending}', icon: Icons.pending_actions_outlined),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A blue note line with an info icon (the meaning of "Completed").
class DashboardNote extends StatelessWidget {
  const DashboardNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AdinnColors.info.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 18, color: AdinnColors.info),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

/// The dashboard could not be read: the message and a Retry, above the shop counts that are still shown.
class DashboardErrorNotice extends StatelessWidget {
  const DashboardErrorNotice({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('dashboard-error'),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: AdinnColors.redLight, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.cloud_off_outlined, color: AdinnColors.red, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('Could not load the full dashboard. $message', style: const TextStyle(color: AdinnColors.redDark, fontSize: 13, fontWeight: FontWeight.w600))),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }
}
