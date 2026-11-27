import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../../state/version_diff.dart';
import '../history/snapshot_view.dart';
import '../history/version_history_screen.dart';
import '../photos/site_photo_view.dart';
import '../review_comments/photo_comments_screen.dart';
import '../review_comments/shop_comments_screen.dart';
import '../survey/readiness.dart';
import '../../core/widgets/adinn_app_bar.dart';

/// Business Team / Recce Ops review of the latest submitted version.
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key, required this.shopId});

  final String shopId;

  Future<void> _approve(BuildContext context, Submission sub) async {
    final c = context.read<AppController>();
    final remarks = TextEditingController();
    final stage = c.reviewStage!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.uf('Approve v{0}?', [sub.version])),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stage == ReviewStage.business
                  ? 'The recce will move to Recce Operations for final approval.'
                  : 'This is the final approval. The recce will be locked.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('approve_remarks'),
              controller: remarks,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: context.ui('Remarks (optional)'),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.ui('Cancel')),
          ),
          FilledButton(
            key: const Key('approve_confirm'),
            style: FilledButton.styleFrom(backgroundColor: AdinnColors.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.ui('Approve')),
          ),
        ],
      ),
    );
    final text = remarks.text;
    remarks.dispose();
    if (ok != true || !context.mounted) return;
    c.reviewShop(shopId, decision: ReviewDecision.approved, remarks: text);
    showSnack(context, context.uf('v{0} approved', [sub.version]));
    Navigator.of(context).pop();
  }

  Future<void> _reject(BuildContext context, Submission sub) async {
    final result =
        await showModalBottomSheet<
          (String, List<String>, List<RejectionIssue>)
        >(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) =>
              _RejectSheet(version: sub.version, shop: sub.shopSnapshot),
        );
    if (result == null || !context.mounted) return;
    final c = context.read<AppController>();
    final shop = c.shop(shopId);
    // Photo comments flagged "reject this evidence" become item issues.
    final issues = [...result.$3];
    for (final i
        in shop == null ? const <RejectionIssue>[] : c.commentIssues(shop)) {
      if (!issues.any((e) => e.photoId == i.photoId && e.note == i.note)) {
        issues.add(i);
      }
    }
    c.reviewShop(
      shopId,
      decision: ReviewDecision.rejected,
      remarks: result.$1,
      reasons: result.$2,
      issues: issues,
    );
    showSnack(context, context.uf('v{0} rejected and sent back to vendor', [sub.version]));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(shopId);
    final sub = shop?.latestSubmission;
    if (shop == null || sub == null) {
      return Scaffold(
        appBar: AdinnAppBar(),
        body: EmptyState(
          icon: Icons.inbox,
          title: context.ui('Nothing to review'),
        ),
      );
    }
    final snapshot = sub.shopSnapshot;
    final previous = shop.submissions.length > 1
        ? shop.submissions[shop.submissions.length - 2]
        : null;
    final changes = diffShops(previous?.shopSnapshot, snapshot);
    final canAct = c.canReview(shop);
    final project = c.project(shop.projectId);
    final task = c.task(shop.taskId);
    final totalArea = snapshot.boards.fold(0.0, (s, b) => s + b.areaSqFt);

    return Scaffold(
      appBar: AdinnAppBar(
        title: Text(context.uf('Review v{0}', [sub.version])),
        actions: [
          IconButton(
            tooltip: context.ui('Version history'),
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => VersionHistoryScreen(shopId: shopId),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: canAct
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AdinnColors.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('reject_button'),
                        onPressed: () => _reject(context, sub),
                        icon: const Icon(Icons.close),
                        label: Text(context.ui('REJECT')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        key: const Key('approve_button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AdinnColors.success,
                        ),
                        onPressed: () => _approve(context, sub),
                        icon: const Icon(Icons.check),
                        label: Text(context.ui('APPROVE')),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: shop.name,
            icon: Icons.storefront,
            trailing: StatusChip(shop.status, compact: true),
            child: Column(
              children: [
                InfoRow(
                  context.ui('Project'),
                  project == null
                      ? ''
                      : context.projectName(project.id, project.name),
                ),
                InfoRow('Task', task?.title ?? ''),
                InfoRow('Submitted by', sub.submittedByName),
                InfoRow('Submitted on', fmtDateTime(sub.submittedAt)),
                InfoRow(
                  'Boards',
                  '${snapshot.boards.length} media group(s) • '
                      '${snapshot.unitCount} unit(s) • '
                      '${fmtNum(totalArea)} sq ft total',
                ),
                InfoRow(
                  'Media',
                  snapshot.boards
                      .map((b) => SignageCatalog.media(b.mediaCode)?.shortName)
                      .whereType<String>()
                      .toSet()
                      .join(', '),
                ),
                if (sub.vendorRemarks.isNotEmpty)
                  InfoRow(context.ui('Vendor remarks'), sub.vendorRemarks),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: context.ui('Approval trail'),
            icon: Icons.route_outlined,
            child: ReviewTrail(submission: sub),
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final checks = [
                if (snapshot.geo == null) 'Shop GPS location missing',
                ...c.shopWarnings(snapshot),
                for (final b in snapshot.boards)
                  for (final w in c.boardWarnings(b, snapshot.geo))
                    '${b.name}: $w',
              ];
              return SectionCard(
                title: context.ui('Site checks'),
                icon: Icons.rule,
                child: checks.isEmpty
                    ? Row(
                        children: [
                          Icon(
                            Icons.verified_outlined,
                            color: AdinnColors.success,
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(context.ui('GPS captured, photos geotagged near the shop, '
                              'board areas marked.'),
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      )
                    : IssueList(items: checks, warning: true),
              );
            },
          ),
          const SizedBox(height: 12),
          _PhotoCommentsCard(shop: shop, snapshot: snapshot),
          const SizedBox(height: 12),
          _UnitSummaryCard(shop: snapshot),
          if (previous != null) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: context.uf('Changes since v{0}', [previous.version]),
              icon: Icons.compare_arrows,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final ch in changes)
                    Text('• $ch', style: const TextStyle(fontSize: 13)),
                  if (previous.reviews.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Previous decision: "${previous.reviews.last.remarks}"',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdinnColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          ShopSnapshotView(
            shop: snapshot,
            liveShopId: shop.status.isPending ? shop.id : null,
            // Highlight what the previous rejection asked to correct.
            issues: previous?.reviews.lastOrNull?.issues ?? const [],
          ),
        ],
      ),
    );
  }
}

class _RejectSheet extends StatefulWidget {
  const _RejectSheet({required this.version, required this.shop});

  final int version;

  /// Submitted snapshot (to point at specific signage items).
  final Shop shop;

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _remarks = TextEditingController();
  final _reasons = <String>{};

  /// unitId → aspects flagged for that signage unit.
  final _flags = <String, Set<IssueAspect>>{};
  String? _error;

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  String _label(Board b, SignageUnit u) {
    final media = SignageCatalog.media(b.mediaCode)?.shortName ?? b.name;
    return b.quantity <= 1
        ? '${b.name} ($media)'
        : '$media • ${b.unitLabel(u)}';
  }

  List<RejectionIssue> _issues() => [
    for (final b in widget.shop.boards)
      for (final u in b.activeUnits)
        for (final a in IssueAspect.values)
          if (_flags[u.id]?.contains(a) ?? false)
            RejectionIssue(
              groupId: b.id,
              unitId: u.id,
              aspect: a,
              label: _label(b, u),
            ),
  ];

  @override
  Widget build(BuildContext context) {
    final flagged = _flags.values.fold(0, (s, e) => s + e.length);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Reject v${widget.version}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(context.ui('The vendor will rework and resubmit as a new version.'),
              style: TextStyle(color: AdinnColors.muted),
            ),
            const SizedBox(height: 12),
            Text(context.ui('Reasons'),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final r in SignageCatalog.rejectionReasons)
                  FilterChip(
                    label: Text(r),
                    selected: _reasons.contains(r),
                    onSelected: (v) => setState(
                      () => v ? _reasons.add(r) : _reasons.remove(r),
                    ),
                  ),
              ],
            ),
            if (widget.shop.boards.isNotEmpty) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                key: const Key('reject_items'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  flagged == 0
                      ? 'Specific items (optional)'
                      : 'Specific items ($flagged flagged)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(context.ui('Point at the signage item, photo, annotation, dimension '
                  'or installation detail to correct.'),
                  style: TextStyle(fontSize: 12),
                ),
                children: [
                  for (final b in widget.shop.boards)
                    for (final u in b.activeUnits)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_label(b, u)} – '
                              '${fmtSize(b.widthOf(u), b.heightOf(u), b.unit)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 2,
                              children: [
                                for (final a in IssueAspect.values)
                                  FilterChip(
                                    key: Key('issue_${u.id}_${a.name}'),
                                    visualDensity: VisualDensity.compact,
                                    label: Text(
                                      a.label,
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                    selected:
                                        _flags[u.id]?.contains(a) ?? false,
                                    onSelected: (v) => setState(() {
                                      final set = _flags.putIfAbsent(
                                        u.id,
                                        () => <IssueAspect>{},
                                      );
                                      v ? set.add(a) : set.remove(a);
                                    }),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const Key('reject_remarks'),
              controller: _remarks,
              maxLines: 3,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: context.ui('Remarks for vendor *'),
                alignLabelWithHint: true,
                errorText: _error,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('reject_confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: AdinnColors.redDark,
              ),
              onPressed: () {
                if (_remarks.text.trim().isEmpty) {
                  setState(() => _error = 'Remarks are required');
                  return;
                }
                Navigator.pop(context, (
                  _remarks.text.trim(),
                  _reasons.toList(),
                  _issues(),
                ));
              },
              icon: const Icon(Icons.close),
              label: Text(context.ui('REJECT & SEND BACK')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reviewer photo comments: per submitted photo, the number of pinned
/// comments and a button to open / add them.
class _PhotoCommentsCard extends StatelessWidget {
  const _PhotoCommentsCard({required this.shop, required this.snapshot});

  final Shop shop;
  final Shop snapshot;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final canComment = c.canComment(shop);
    final all = c.reviewComments(shop.id);
    final open = all.where((e) => e.status == CommentStatus.open).length;
    final photos = [
      for (final b in snapshot.boards)
        for (final p in b.photos) (b, p),
    ];
    return SectionCard(
      title: context.ui('Photo review comments'),
      icon: Icons.add_comment_outlined,
      trailing: TextButton(
        key: const Key('review_all_comments'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ShopCommentsScreen(shopId: shop.id),
          ),
        ),
        child: Text(context.uf('All ({0})', [all.length])),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            canComment
                ? 'Pin a comment on the exact spot of a photo that needs '
                      'correction. ${open == 0 ? '' : '$open open.'}'
                : '${all.length} comment(s) • $open open',
            style: const TextStyle(fontSize: 12.5, color: AdinnColors.muted),
          ),
          if (photos.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(context.ui('No photos in this version.')),
            ),
          for (final (b, p) in photos)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: AnnotatedPhotoView(
                      p,
                      borderRadius: 6,
                      cacheWidth: 240,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${b.name} • ${p.label}\n'
                      '${all.where((e) => e.photoId == p.id).length} '
                      'comment(s)',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  TextButton.icon(
                    key: Key('review_photo_comments_${p.id}'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PhotoCommentsScreen(
                          shopId: shop.id,
                          boardId: b.id,
                          photoId: p.id,
                          snapshot: snapshot,
                        ),
                      ),
                    ),
                    icon: Icon(
                      canComment ? Icons.add_comment : Icons.mode_comment,
                      size: 18,
                    ),
                    label: Text(context.ui(canComment ? 'Comment' : 'View')),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Signage units grouped by media type with their size, checklist and
/// readiness, so the reviewer sees unit-wise status at a glance.
class _UnitSummaryCard extends StatelessWidget {
  const _UnitSummaryCard({required this.shop});

  /// The submitted snapshot under review.
  final Shop shop;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      key: const Key('review_unit_summary'),
      title: context.ui('Units by media type'),
      icon: Icons.view_list_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in shop.boards) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                '${SignageCatalog.media(b.mediaCode)?.shortName ?? 'Media not set'}'
                '${SignageCatalog.isDoubleSided(b) ? ' (double-sided)' : ''}'
                ' – ${b.quantity} unit${b.quantity == 1 ? '' : 's'} • '
                '${SignageCatalog.installationSummary(b, empty: 'Installation not set')}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final u in b.activeUnits)
              Builder(
                builder: (context) {
                  final r = unitReadiness(shop, b, u);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${b.unitLabel(u)} • '
                                '${fmtSize(b.widthOf(u), b.heightOf(u), b.unit)}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              if (r.reasons.isNotEmpty)
                                Text(
                                  r.reasons.take(2).join(' • '),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: r.level.color,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        ReadinessChip(r.level, short: true),
                      ],
                    ),
                  );
                },
              ),
            const Divider(height: 12),
          ],
          Text(context.ui('Operational indicators from recorded data only – not a '
            'structural or electrical certification.'),
            style: TextStyle(fontSize: 11, color: AdinnColors.muted),
          ),
        ],
      ),
    );
  }
}
