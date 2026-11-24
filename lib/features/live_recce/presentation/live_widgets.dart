import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/recce_models.dart';

/// Status chip of a shop (same pill look as the offline screens).
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(statusLabel(status), style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: AdinnColors.muted),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// A shop in a list: title, status, project, address, boards and progress.
class ShopCard extends StatelessWidget {
  const ShopCard({super.key, required this.shop, required this.onTap, this.showProject = true, this.unread = 0});

  final ShopSummary shop;
  final VoidCallback onTap;
  final bool showProject;

  /// Unread chat messages of this shop, as far as they are known without an extra call (see `shopUnreadCount`); 0 shows nothing.
  final int unread;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(shop.status);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(shop.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(shop.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [shop.siteCode, if (showProject) shop.projectCode].where((e) => e.isNotEmpty).join('  |  '),
                style: const TextStyle(color: AdinnColors.muted, fontSize: 13),
              ),
              if (shop.address.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(shop.address, maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (shop.mediaTypes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(shop.mediaTypes.join(', '), style: const TextStyle(fontSize: 13))),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: shop.progress.clamp(0, 100) / 100, minHeight: 7, color: color, backgroundColor: AdinnColors.line),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${shop.progress}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              if (shop.expectedBy != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Expected by ${fmtDate(shop.expectedBy!)}', style: const TextStyle(color: AdinnColors.muted, fontSize: 12))),
              if (shop.reworkOpen)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Icon(Icons.flag, size: 16, color: AdinnColors.red),
                    SizedBox(width: 4),
                    Text('Reviewer asked for changes', style: TextStyle(color: AdinnColors.red, fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                ),
              if (unread > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(key: const ValueKey('unread-chat'), children: [
                    const Icon(Icons.chat_bubble, size: 15, color: AdinnColors.info),
                    const SizedBox(width: 4),
                    Text('$unread new message${unread == 1 ? '' : 's'}', style: const TextStyle(color: AdinnColors.info, fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Red box with what the reviewer asked for: their note on this photo, the overall instructions, who and when.
class ReworkBox extends StatelessWidget {
  const ReworkBox({super.key, required this.note, this.fallback = 'The reviewer asked for this photo to be replaced.'});

  final ReworkNote? note;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final n = note;
    final who = [if (n?.by != null) n!.by!, if (n?.role != null) '(${n!.role})'].join(' ');
    final rejected = n?.rejected == true;
    final main = n == null || n.reason.isEmpty ? (rejected ? 'The reviewer rejected this photo.' : fallback) : n.reason;
    final extra = n != null && n.note.isNotEmpty && n.instructions.isNotEmpty && n.instructions != n.note ? n.instructions : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AdinnColors.redLight, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A rejected photo says so first, then the reason the reviewer wrote.
          if (rejected) const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('Reason for rejection', style: TextStyle(color: AdinnColors.redDark, fontWeight: FontWeight.w800, fontSize: 12))),
          Text(main, style: const TextStyle(color: AdinnColors.redDark, fontWeight: FontWeight.w600)),
          if (extra != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Instructions: $extra', style: const TextStyle(color: AdinnColors.redDark, fontSize: 13))),
          if (who.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${rejected ? 'Rejected' : 'Requested'} by $who', style: const TextStyle(fontSize: 12, color: AdinnColors.muted))),
          if (n?.at != null) Text(fmtDateTime(n!.at!), style: const TextStyle(fontSize: 12, color: AdinnColors.muted)),
        ],
      ),
    );
  }
}

/// Small red "Rework required" tag with a flag, for photo rows and board cards.
class ReworkTag extends StatelessWidget {
  const ReworkTag({super.key, this.text = 'Rework required'});
  final String text;

  @override
  Widget build(BuildContext context) => TagChip(text, icon: Icons.flag, color: AdinnColors.red);
}

/// One review stage and its decision: "Recce Operations - Approved", with the reviewer, time and comment when decided.
class StageDecisionTile extends StatelessWidget {
  const StageDecisionTile(this.d, {super.key, this.dense = false});

  final StageDecision d;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = decisionColor(d.decision);
    final meta = [if (d.reviewer != null) d.reviewer!, if (d.decidedAt != null) fmtDateTime(d.decidedAt!)].join('  |  ');
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 3 : 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(switch (d.decision) { 'APPROVED' => Icons.check_circle, 'REWORK' => Icons.flag, 'REJECTED' => Icons.cancel, 'VOID' => Icons.remove_circle_outline, _ => Icons.hourglass_empty }, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(d.stageLabel, style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text(decisionLabel(d.decision), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
                ]),
                if (meta.isNotEmpty) Text(meta, style: const TextStyle(fontSize: 12, color: AdinnColors.muted)),
                if (d.comment.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(d.comment, style: const TextStyle(fontSize: 13))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Status header of the Review tab: the shop's status exactly as the server sent it (UNDER_REVIEW / REWORK_REQUIRED /
/// APPROVED ...) and the decision of every review stage on the CURRENT version. Nothing is worked out on the phone.
class ReviewStatusHeader extends StatelessWidget {
  const ReviewStatusHeader({super.key, required this.detail});

  final ShopDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final stages = StageDecision.forVersion(d.reviews, d.version);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.fact_check_outlined, color: AdinnColors.red),
              const SizedBox(width: 8),
              const Expanded(child: Text('Review status', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              if (d.version > 0) Padding(padding: const EdgeInsets.only(right: 8), child: TagChip('Version ${d.version}', icon: Icons.history)),
              StatusPill(d.status),
            ]),
            if (d.version == 0)
              const Padding(padding: EdgeInsets.only(top: 8), child: Text('Not submitted yet. Reviewers see this shop after you submit.', style: TextStyle(color: AdinnColors.muted)))
            else if (stages.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 8), child: Text('Waiting for the review to start.', style: TextStyle(color: AdinnColors.muted)))
            else ...[
              const SizedBox(height: 6),
              for (final s in stages) StageDecisionTile(s),
            ],
          ],
        ),
      ),
    );
  }
}
