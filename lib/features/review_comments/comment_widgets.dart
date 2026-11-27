import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';

Color commentStatusColor(CommentStatus s) => switch (s) {
  CommentStatus.open => AdinnColors.red,
  CommentStatus.addressed => AdinnColors.warning,
  CommentStatus.verified => AdinnColors.success,
};

/// A photo found for a review comment: from the live recce, or (when the
/// vendor has since replaced / removed it) from a submission snapshot.
class ResolvedPhoto {
  const ResolvedPhoto(this.board, this.photo, {this.fromVersion});

  final Board board;
  final SitePhoto photo;

  /// Submission version the photo was taken from (null = live recce).
  final int? fromVersion;
}

/// Finds [photoId] of media group [boardId]: live first, then [snapshot],
/// then the submission snapshots (preferring [version], newest first).
ResolvedPhoto? resolveCommentPhoto(
  Shop live,
  String boardId,
  String photoId, {
  Shop? snapshot,
  int? version,
}) {
  ResolvedPhoto? find(Shop s, int? v) {
    for (final b in s.boards) {
      if (b.id != boardId) continue;
      for (final p in b.photos) {
        if (p.id == photoId) return ResolvedPhoto(b, p, fromVersion: v);
      }
    }
    // The photo may have moved to another group.
    for (final b in s.boards) {
      for (final p in b.photos) {
        if (p.id == photoId) return ResolvedPhoto(b, p, fromVersion: v);
      }
    }
    return null;
  }

  final r = find(live, null);
  if (r != null) return r;
  if (snapshot != null) {
    final s = find(snapshot, live.currentVersion);
    if (s != null) return s;
  }
  final subs = [...live.submissions]
    ..sort((a, b) {
      if (a.version == version) return -1;
      if (b.version == version) return 1;
      return b.version.compareTo(a.version);
    });
  for (final sub in subs) {
    final s = find(sub.shopSnapshot, sub.version);
    if (s != null) return s;
  }
  return null;
}

/// Photo of [photoId] as submitted in [version] (null when absent).
SitePhoto? snapshotPhoto(Shop live, int version, String photoId) {
  final sub = live.submissions.where((s) => s.version == version).firstOrNull;
  if (sub == null) return null;
  for (final b in sub.shopSnapshot.boards) {
    for (final p in b.photos) {
      if (p.id == photoId) return p;
    }
  }
  return null;
}

/// "GSB – Unit 02" / board name for a comment's signage item.
String commentItemLabel(Board? b, String? unitId) {
  if (b == null) return 'Media group';
  final u = b.unitById(unitId);
  final media = SignageCatalog.media(b.mediaCode)?.shortName ?? b.name;
  if (u == null) return '${b.name} ($media)';
  return '$media – ${b.unitLabel(u)}';
}

/// Round numbered marker drawn at a comment position.
class CommentMarkerDot extends StatelessWidget {
  const CommentMarkerDot({
    super.key,
    required this.comment,
    this.size = 30,
    this.onTap,
    this.highlighted = false,
  });

  final PhotoReviewComment comment;
  final double size;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = commentStatusColor(comment.status);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: highlighted ? Colors.yellowAccent : Colors.white,
            width: highlighted ? 3 : 2,
          ),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
        ),
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Text(
              comment.markerLabel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CommentStatusChip extends StatelessWidget {
  const CommentStatusChip(this.status, {super.key});

  final CommentStatus status;

  @override
  Widget build(BuildContext context) => TagChip(
    status.label,
    color: commentStatusColor(status),
    icon: switch (status) {
      CommentStatus.open => Icons.error_outline,
      CommentStatus.addressed => Icons.build_circle_outlined,
      CommentStatus.verified => Icons.verified_outlined,
    },
  );
}

/// Shows one comment with the actions the current user may take: recce
/// staff respond / mark addressed; the reviewer of the same stage verifies,
/// reopens or deletes.
Future<void> showCommentDetails(
  BuildContext context, {
  required String shopId,
  required String commentId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => CommentDetailSheet(shopId: shopId, commentId: commentId),
);

class CommentDetailSheet extends StatefulWidget {
  const CommentDetailSheet({
    super.key,
    required this.shopId,
    required this.commentId,
  });

  final String shopId;
  final String commentId;

  @override
  State<CommentDetailSheet> createState() => _CommentDetailSheetState();
}

class _CommentDetailSheetState extends State<CommentDetailSheet> {
  final _response = TextEditingController();

  @override
  void dispose() {
    _response.dispose();
    super.dispose();
  }

  void _run(void Function() action, String done, {bool close = false}) {
    try {
      action();
      _response.clear();
      showSnack(context, done);
      if (close) Navigator.of(context).pop();
    } on StateError catch (e) {
      showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(widget.shopId);
    final cm = shop?.reviewComments
        .where((e) => e.id == widget.commentId)
        .firstOrNull;
    if (shop == null || cm == null) {
      return SizedBox(
        height: 120,
        child: Center(child: Text(context.ui('Comment not found'))),
      );
    }
    final board = shop.boards.where((b) => b.id == cm.groupId).firstOrNull;
    final canRespond = c.canEdit(shop);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          key: Key('rc_detail_${cm.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CommentMarkerDot(comment: cm, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(context.ui(cm.type.label),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                CommentStatusChip(cm.status),
              ],
            ),
            const SizedBox(height: 10),
            Text(cm.text, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                TagChip('Raised in v${cm.version}', icon: Icons.history),
                TagChip(
                  commentItemLabel(board, cm.unitId),
                  icon: Icons.crop_landscape,
                ),
                if (cm.rejectsEvidence)
                  const TagChip(
                    'Evidence rejected',
                    color: AdinnColors.red,
                    icon: Icons.report_gmailerrorred,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${cm.reviewerName} (${cm.reviewerRole.label}) • '
              '${fmtDateTime(cm.createdAt)}',
              style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
            ),
            if (cm.verifiedAt != null)
              Text(
                'Verified by ${cm.verifiedByName ?? 'reviewer'} • '
                '${fmtDateTime(cm.verifiedAt!)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AdinnColors.success,
                ),
              ),
            if (cm.responses.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(context.ui('Responses'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final r in cm.responses)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AdinnColors.canvas,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.text),
                        const SizedBox(height: 2),
                        Text(
                          '${r.byName}'
                          '${r.version == null ? '' : ' • v${r.version}'} • '
                          '${fmtDateTime(r.at)}',
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
            if (canRespond) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('rc_response'),
                controller: _response,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: context.ui('Your response / correction made'),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('rc_respond'),
                      onPressed: () => _run(
                        () =>
                            c.respondToComment(shop.id, cm.id, _response.text),
                        'Response saved',
                      ),
                      child: Text(context.ui('Respond')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (cm.status == CommentStatus.open)
                    Expanded(
                      child: FilledButton(
                        key: const Key('rc_addressed'),
                        onPressed: () => _run(
                          () => c.respondToComment(
                            shop.id,
                            cm.id,
                            _response.text,
                            markAddressed: true,
                          ),
                          'Marked as addressed',
                        ),
                        child: Text(context.ui('Mark Addressed')),
                      ),
                    ),
                ],
              ),
              if (cm.status == CommentStatus.addressed)
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(context.ui('Addressed – waiting for the reviewer to verify. '
                    'Addressed is not an approval.'),
                    style: TextStyle(fontSize: 12, color: AdinnColors.muted),
                  ),
                ),
            ],
            if (c.currentUser?.role.isReviewer == true) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (c.canVerifyComment(shop, cm))
                    FilledButton.icon(
                      key: const Key('rc_verify'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AdinnColors.success,
                      ),
                      onPressed: () => _run(
                        () => c.verifyComment(shop.id, cm.id),
                        'Comment verified',
                      ),
                      icon: const Icon(Icons.verified_outlined),
                      label: Text(context.ui('Verify')),
                    ),
                  if (cm.status != CommentStatus.open &&
                      c.currentUser?.role == cm.reviewerRole &&
                      c.canReview(shop))
                    OutlinedButton(
                      key: const Key('rc_reopen'),
                      onPressed: () => _run(
                        () => c.reopenComment(shop.id, cm.id),
                        'Comment reopened',
                      ),
                      child: Text(context.ui('Reopen')),
                    ),
                  if (c.canDeleteComment(shop, cm))
                    TextButton.icon(
                      key: const Key('rc_delete'),
                      onPressed: () => _run(
                        () => c.deleteReviewComment(shop.id, cm.id),
                        'Comment deleted',
                        close: true,
                      ),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AdinnColors.red,
                      ),
                      label: Text(context.ui('Delete'),
                        style: TextStyle(color: AdinnColors.red),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
