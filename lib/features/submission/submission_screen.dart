import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../../state/live_link.dart';
import '../../state/version_diff.dart';
import '../board/board_editor_screen.dart';
import '../shop/shop_detail_screen.dart';

/// Vendor's final check before sending a recce version for approval.
class SubmissionScreen extends StatefulWidget {
  const SubmissionScreen({super.key, required this.shopId});

  final String shopId;

  @override
  State<SubmissionScreen> createState() => _SubmissionScreenState();
}

class _SubmissionScreenState extends State<SubmissionScreen> {
  final _remarks = TextEditingController();
  bool _declared = false;

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final c = context.read<AppController>();
    final link = c.liveLink(widget.shopId);
    if (link != null) return _submitLive(link);
    try {
      final sub = c.submitShop(widget.shopId, remarks: _remarks.text);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.check_circle,
            color: AdinnColors.success,
            size: 48,
          ),
          title: Text('Submitted v${sub.version}'),
          content: const Text(
            'The recce has been sent to the Business Team for approval. '
            'You will see their decision in the Submitted tab.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on StateError catch (e) {
      if (!mounted) return;
      showSnack(context, e.message, error: true);
    }
  }

  bool _sending = false;

  /// A shop of the server: saved and submitted there; the server's own checks decide.
  Future<void> _submitLive(LiveShopLink link) async {
    if (_sending) return;
    setState(() => _sending = true);
    final out = await link.submit(_remarks.text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!out.ok) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Complete these before submitting'),
          content: SingleChildScrollView(child: Text(out.problems.map((p) => '• $p').join('\n'))),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AdinnColors.success, size: 48),
        title: Text('Submitted v${out.version ?? ''}'),
        content: const Text('The recce has been sent for approval. You will see the decision in the Submitted tab.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(widget.shopId);
    if (shop == null) {
      return const Scaffold(body: Center(child: Text('Shop not found')));
    }
    final issues = c.shopIssues(shop);
    final warnings = [
      for (final b in shop.boards)
        for (final w in c.boardWarnings(b, shop.geo)) '${b.name}: $w',
      ...c.shopWarnings(shop),
      for (final rc in c.openComments(shop.id))
        'Reviewer comment ${rc.markerLabel} (v${rc.version}, '
            '${rc.type.label}) is still open – respond or mark it addressed',
    ];
    final prev = shop.latestSubmission?.shopSnapshot;
    final changes = diffShops(prev, shop);
    // Once submitted (no longer editable) keep showing the version just sent.
    final nextVersion = shop.submissions.length + (c.canEdit(shop) ? 1 : 0);
    final canSubmit = issues.isEmpty && _declared && c.canEdit(shop);

    return Scaffold(
      appBar: AppBar(title: Text('Submit recce v$nextVersion')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (shop.status.isRejected) ...[
            StatusBanner(shop: shop),
            const SizedBox(height: 12),
          ],
          SectionCard(
            title: shop.name,
            icon: Icons.storefront_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shop.fullAddress, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    TagChip(
                      '${shop.boards.length} board${shop.boards.length == 1 ? '' : 's'}',
                      icon: Icons.dashboard_customize_outlined,
                    ),
                    if (shop.unitCount != shop.boards.length)
                      TagChip(
                        '${shop.unitCount} units',
                        icon: Icons.view_list_outlined,
                      ),
                    TagChip(
                      '${shop.photoCount} photos',
                      icon: Icons.photo_camera_outlined,
                    ),
                    TagChip(
                      '${fmtNum(shop.boards.fold(0.0, (s, b) => s + b.areaSqFt))} sq ft total',
                      icon: Icons.square_foot,
                    ),
                  ],
                ),
                const Divider(height: 24),
                for (final b in shop.boards)
                  InkWell(
                    key: Key('submit_board_${b.id}'),
                    // Quick navigation to the incomplete media group.
                    onTap: c.canEdit(shop)
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => BoardEditorScreen(
                                shopId: shop.id,
                                boardId: b.id,
                              ),
                            ),
                          )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6, top: 2),
                      child: Row(
                        children: [
                          Icon(
                            c.boardIssues(b).isEmpty
                                ? Icons.check_circle
                                : Icons.error_outline,
                            size: 18,
                            color: c.boardIssues(b).isEmpty
                                ? AdinnColors.success
                                : AdinnColors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${b.name} – ${SignageCatalog.media(b.mediaCode)?.shortName ?? '?'}'
                                  ' • ${SignageCatalog.installationSummary(b, empty: '?')}'
                                  ' • ${b.isSameSize ? fmtSize(b.width, b.height, b.unit) : 'different sizes'}'
                                  '${b.quantity > 1 ? ' • qty ${b.quantity}' : ''}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                if (c.boardIssues(b).isNotEmpty)
                                  Text(
                                    '${c.boardIssues(b).first}'
                                    '${c.boardIssues(b).length > 1 ? ' (+${c.boardIssues(b).length - 1} more)' : ''}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AdinnColors.red,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (c.canEdit(shop) && c.boardIssues(b).isNotEmpty)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Text(
                                'Fix',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AdinnColors.red,
                                ),
                              ),
                            ),
                          if (c.canEdit(shop))
                            const Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: AdinnColors.muted,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: issues.isEmpty
                ? 'Checklist complete'
                : 'Fix before submitting',
            icon: issues.isEmpty ? Icons.task_alt : Icons.rule,
            child: issues.isEmpty && warnings.isEmpty
                ? const Text('All mandatory details are captured.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IssueList(items: issues),
                      IssueList(items: warnings, warning: true),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: prev == null
                ? 'Version'
                : 'Changes since v${shop.latestSubmission!.version}',
            icon: Icons.compare_arrows,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final ch in changes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• $ch', style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('submit_remarks'),
            controller: _remarks,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Remarks for reviewers (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const Key('submit_declare'),
            value: _declared,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) => setState(() => _declared = v ?? false),
            title: const Text(
              'I confirm the photos and measurements were captured at the site.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            key: const Key('submit_button'),
            onPressed: canSubmit ? _submit : null,
            icon: const Icon(Icons.send),
            label: Text('SUBMIT v$nextVersion FOR APPROVAL'),
          ),
          if (issues.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Complete the checklist to enable submission.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AdinnColors.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
