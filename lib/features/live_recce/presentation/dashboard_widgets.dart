import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/recce_models.dart';
import 'live_widgets.dart';
import 'notifications_screen.dart' show notificationColor;

/// One number of the home screen: a tinted icon square, the label and the value, a chevron when it opens a list.
class DashTile extends StatelessWidget {
  const DashTile(this.label, this.value, this.icon, this.color, {super.key, this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AdinnColors.ink))),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AdinnColors.ink, height: 1.15))),
              ]),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, color: AdinnColors.muted, size: 20),
          ]),
        ),
      ),
    );
  }
}

/// Two-column grid of [DashTile]s with a fixed height that grows with the phone's text size.
class DashTileGrid extends StatelessWidget {
  const DashTileGrid({super.key, required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.6);
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 70 * scale),
      children: tiles,
    );
  }
}

/// Section title with a red "View All >" on the right.
class DashSectionHeader extends StatelessWidget {
  const DashSectionHeader(this.title, {super.key, this.action = 'View All', this.onAction});
  final String title;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
        if (onAction != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(action, style: const TextStyle(color: AdinnColors.red, fontWeight: FontWeight.w700, fontSize: 13)),
                const Icon(Icons.chevron_right, color: AdinnColors.red, size: 18),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// "Overall progress": a red bar for the submitted share and a green one for the finally approved share of the assigned shops.
class OverallProgressCard extends StatelessWidget {
  const OverallProgressCard({super.key, required this.assigned, required this.submitted, required this.approved});
  final int assigned;
  final int submitted;
  final int approved;

  static int _pct(int part, int whole) => whole <= 0 ? 0 : (part * 100 / whole).round().clamp(0, 100);

  @override
  Widget build(BuildContext context) {
    final sub = _pct(submitted, assigned);
    final app = _pct(approved, assigned);
    Widget row(String label, int pct, Color color) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
              Text('$pct%', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: pct / 100, minHeight: 7, color: color, backgroundColor: AdinnColors.line)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.bar_chart_rounded, color: AdinnColors.red, size: 24),
            SizedBox(width: 8),
            Flexible(child: Text('Overall Progress', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
          ]),
          row('Submitted Progress', sub, AdinnColors.red),
          row('Final Approved Progress', app, AdinnColors.success),
        ]),
      ),
    );
  }
}

/// A shop that needs the field person right now (rework asked): pink card, "Rework Required" pill and a Continue Rework button.
class AttentionCard extends StatelessWidget {
  const AttentionCard({super.key, required this.shop, required this.onTap, this.unread = 0});
  final ShopSummary shop;
  final VoidCallback onTap;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AdinnColors.redLight, borderRadius: BorderRadius.circular(14), border: Border.all(color: AdinnColors.red.withValues(alpha: 0.18))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _ShopIcon(AdinnColors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shop.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(_codeAndPlace(shop), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AdinnColors.muted, fontSize: 12.5)),
            ]),
          ),
          const SizedBox(width: 8),
          const TagChip('Rework Required', color: AdinnColors.red),
        ]),
        if (unread > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(key: const ValueKey('unread-chat'), children: [
              const Icon(Icons.chat_bubble, size: 15, color: AdinnColors.info),
              const SizedBox(width: 4),
              Text('$unread new message${unread == 1 ? '' : 's'}', style: const TextStyle(color: AdinnColors.info, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: onTap,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 20)),
            label: const Text('Continue Rework'),
            icon: const Icon(Icons.chevron_right),
            iconAlignment: IconAlignment.end,
          ),
        ),
      ]),
    );
  }
}

/// "Continue where you left off": a shop in progress with its status and a chevron.
class ResumeRow extends StatelessWidget {
  const ResumeRow({super.key, required this.shop, required this.onTap});
  final ShopSummary shop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            const _ShopIcon(AdinnColors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shop.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(_codeAndPlace(shop), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AdinnColors.muted, fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 8),
            StatusPill(shop.status),
            const Icon(Icons.chevron_right, color: AdinnColors.muted),
          ]),
        ),
      ),
    );
  }
}

String _codeAndPlace(ShopSummary s) => [if (s.projectCode.isNotEmpty) s.projectCode else s.siteCode, if (s.address.isNotEmpty) s.address].join('  |  ');

class _ShopIcon extends StatelessWidget {
  const _ShopIcon(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
        child: Icon(Icons.storefront_outlined, color: color, size: 22),
      );
}

/// "Recent activity": the latest notifications as a dotted timeline (what happened, which shop or project, when).
class ActivityTimeline extends StatelessWidget {
  const ActivityTimeline({super.key, required this.items, this.onTap});
  final List<AppNotification> items;
  final void Function(AppNotification)? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (var i = 0; i < items.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 18,
              child: Column(children: [
                const SizedBox(height: 16),
                Container(width: 10, height: 10, decoration: BoxDecoration(color: i == 0 ? AdinnColors.red : AdinnColors.white, shape: BoxShape.circle, border: Border.all(color: i == 0 ? AdinnColors.red : AdinnColors.muted, width: 1.5))),
                if (i < items.length - 1) Expanded(child: Container(width: 2, color: AdinnColors.line)),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(child: _ActivityItem(item: items[i], onTap: onTap == null ? null : () => onTap!(items[i]))),
          ]),
        ),
    ]);
  }
}

class _ActivityItem extends StatelessWidget {
  const _ActivityItem({required this.item, this.onTap});
  final AppNotification item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = notificationColor(item.kind);
    final sub = [if (item.text.isNotEmpty) item.text, if (item.projectCode.isNotEmpty) item.projectCode].join('  |  ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
            child: Icon(item.kind.icon, color: color, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AdinnColors.muted, fontSize: 12.5)),
            ]),
          ),
          if (item.at != null) Padding(padding: const EdgeInsets.only(left: 8, top: 2), child: Text(fmtRelative(item.at!), style: const TextStyle(fontSize: 12, color: AdinnColors.muted))),
        ]),
      ),
    );
  }
}

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
                if (p.assigned > 0) TagChip('${(p.approved * 100 / p.assigned).round()}%', color: AdinnColors.red),
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
