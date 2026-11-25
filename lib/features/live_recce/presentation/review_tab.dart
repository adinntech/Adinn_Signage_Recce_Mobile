import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/live_services.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';
import '../data/rework_alert.dart' show FlaggedSection;
import 'approval_history_screen.dart';
import 'live_widgets.dart';
import 'rework_alert.dart' show SectionReworkBanner;
import 'versions_section.dart';

/// Review: notes for the reviewer, what is still missing, and the reviews / reworks / versions of this shop.
class ReviewTab extends StatefulWidget {
  const ReviewTab({super.key, required this.ctrl});

  final ShopDetailController ctrl;

  @override
  State<ReviewTab> createState() => _ReviewTabState();
}

class _ReviewTabState extends State<ReviewTab> {
  late final _notes = TextEditingController(text: widget.ctrl.notes);

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _openHistory(BuildContext context) {
    final d = widget.ctrl.detail!;
    final api = context.read<LiveServices>().api;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ApprovalHistoryScreen(api: api, detail: d, versions: widget.ctrl.versionList)));
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    final d = ctrl.detail!;
    final problems = ctrl.canEdit ? ctrl.problems() : const <String>[];
    final openReworks = d.reworks.where((r) => r.isOpen).toList();
    return RefreshIndicator(
      onRefresh: ctrl.refreshAll, // fresh photo links for the versions list too
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          ReviewStatusHeader(detail: d),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => _openHistory(context), icon: const Icon(Icons.timeline), label: const Text('Approval history')),
          ),
          const SizedBox(height: 4),
          // Checklist items about the shop as a whole (for example "Correct shop"), with the reviewer's own remark for each.
          SectionReworkBanner(items: FlaggedSection.of(d, section: 'SHOP'), title: 'Reviewer asked for changes to the shop'),
          for (final r in openReworks) ...[_ReworkCard(r, boardLabels: d.boardLabels), const SizedBox(height: 12)],
          if (ctrl.canEdit)
            SectionCard(
              title: 'Before you submit',
              icon: Icons.fact_check_outlined,
              child: problems.isEmpty
                  ? const Row(children: [
                      Icon(Icons.check_circle, color: AdinnColors.success),
                      SizedBox(width: 8),
                      Expanded(child: Text('Everything required is filled. You can submit.')),
                    ])
                  : IssueList(items: problems, warning: true),
            ),
          if (ctrl.canEdit) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'Notes for the reviewer',
              icon: Icons.notes_outlined,
              child: TextField(
                controller: _notes,
                maxLength: 2000,
                maxLines: 4,
                inputFormatters: [LengthLimitingTextInputFormatter(2000)],
                decoration: const InputDecoration(hintText: 'Optional. Example: shop opens at 9 am'),
                onChanged: ctrl.setNotes,
              ),
            ),
          ],
          const SizedBox(height: 12),
          VersionsSection(ctrl: ctrl),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Reviews',
            icon: Icons.rate_review_outlined,
            child: d.reviews.isEmpty
                ? const Text('No reviews yet.', style: TextStyle(color: AdinnColors.muted))
                : Column(children: [for (final r in d.reviews) _ReviewRow(r)]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Reworks',
            icon: Icons.flag_outlined,
            child: d.reworks.isEmpty
                ? const Text('No reworks requested.', style: TextStyle(color: AdinnColors.muted))
                : Column(children: [for (final r in d.reworks) _ReworkCard(r, compact: true, boardLabels: d.boardLabels)]),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.r);
  final ReviewEntry r;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Row(children: [
        Expanded(child: Text('${r.stageLabel}  (v${r.versionNo})', style: const TextStyle(fontWeight: FontWeight.w600))),
        Text(decisionLabel(r.decision), style: TextStyle(color: decisionColor(r.decision), fontWeight: FontWeight.w700)),
      ]),
      subtitle: Text([
        if (r.reviewer != null) r.reviewer!,
        if (r.decidedAt != null) fmtDateTime(r.decidedAt!),
        if (r.comment.isNotEmpty) r.comment,
      ].join('\n')),
    );
  }
}

class _ReworkCard extends StatelessWidget {
  const _ReworkCard(this.r, {this.compact = false, this.boardLabels = const {}});
  final ReworkEntry r;
  final bool compact;

  /// Board key to "GSB-01", so a board request names the board by its number.
  final Map<String, String> boardLabels;

  @override
  Widget build(BuildContext context) {
    final open = r.isOpen;
    final color = open ? AdinnColors.red : AdinnColors.muted;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: compact ? 8 : 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: open ? AdinnColors.redLight : AdinnColors.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: open ? AdinnColors.red.withValues(alpha: 0.3) : AdinnColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${r.kind == 'ADDITIONAL' ? 'More photos requested' : 'Rework'} by ${r.stageLabel}${open ? '' : ' (done)'}',
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
          if (r.instructions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(r.instructions)),
          for (final i in r.items)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '- ${reworkItemText(i, boardLabels: boardLabels)}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          if (r.requestedBy != null || r.requestedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text([if (r.requestedBy != null) r.requestedBy!, if (r.requestedAt != null) fmtDateTime(r.requestedAt!)].join('  |  '), style: const TextStyle(fontSize: 12, color: AdinnColors.muted)),
            ),
        ],
      ),
    );
  }
}
