import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../photos/site_photo_view.dart';
import 'comment_widgets.dart';
import 'photo_comments_screen.dart';
import '../../core/widgets/adinn_app_bar.dart';

/// All reviewer photo comments of a shop, grouped by submission version and
/// photo. For a rejected recce it leads the vendor to each affected item.
class ShopCommentsScreen extends StatelessWidget {
  const ShopCommentsScreen({super.key, required this.shopId});

  final String shopId;

  void _openPhoto(BuildContext context, PhotoReviewComment cm) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoCommentsScreen(
          shopId: shopId,
          boardId: cm.groupId,
          photoId: cm.photoId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(shopId);
    if (shop == null) {
      return Scaffold(
        appBar: AdinnAppBar(),
        body: const EmptyState(icon: Icons.search_off, title: 'Shop not found'),
      );
    }
    final all = c.reviewComments(shop.id);
    final versions = all.map((e) => e.version).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    int count(CommentStatus s) => all.where((e) => e.status == s).length;
    final rejection = shop.status.isRejected
        ? shop.latestSubmission?.reviews.lastOrNull
        : null;

    return Scaffold(
      appBar: AdinnAppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.ui('Photo review comments'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              shop.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Wrap(
            key: const Key('rc_summary'),
            spacing: 8,
            runSpacing: 6,
            children: [
              TagChip(
                'Open ${count(CommentStatus.open)}',
                color: commentStatusColor(CommentStatus.open),
              ),
              TagChip(
                'Addressed ${count(CommentStatus.addressed)}',
                color: commentStatusColor(CommentStatus.addressed),
              ),
              TagChip(
                'Verified ${count(CommentStatus.verified)}',
                color: commentStatusColor(CommentStatus.verified),
              ),
            ],
          ),
          if (rejection != null &&
              rejection.decision == ReviewDecision.rejected) ...[
            const SizedBox(height: 12),
            SectionCard(
              key: const Key('rc_rejection'),
              title:
                  'Rejected by ${rejection.stage.label} '
                  '(v${shop.latestSubmission!.version})',
              icon: Icons.report_gmailerrorred,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rejection.remarks,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (rejection.reasons.isNotEmpty)
                    Text(
                      rejection.reasons.join(', '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdinnColors.muted,
                      ),
                    ),
                  for (final i in rejection.issues)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '• ${i.text}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AdinnColors.red,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (all.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(
                icon: Icons.mode_comment_outlined,
                title: 'No photo comments yet',
                message:
                    'Reviewers can pin comments on specific spots of the '
                    'site photos while reviewing.',
              ),
            ),
          for (final v in versions) ...[
            const SizedBox(height: 16),
            Text(
              'Version v$v${v == shop.currentVersion ? ' (latest)' : ''}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            ..._photoGroups(context, c, shop, all, v),
          ],
        ],
      ),
    );
  }

  List<Widget> _photoGroups(
    BuildContext context,
    AppController c,
    Shop shop,
    List<PhotoReviewComment> all,
    int version,
  ) {
    final inVersion = all.where((e) => e.version == version).toList();
    final photoIds = <String>[];
    for (final cm in inVersion) {
      if (!photoIds.contains(cm.photoId)) photoIds.add(cm.photoId);
    }
    return [
      for (final pid in photoIds)
        Builder(
          builder: (context) {
            final list = inVersion.where((e) => e.photoId == pid).toList();
            final first = list.first;
            final rp = resolveCommentPhoto(
              shop,
              first.groupId,
              pid,
              version: version,
            );
            return Card(
              key: Key('rc_group_${version}_$pid'),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: () => _openPhoto(context, first),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 84,
                            child: rp == null
                                ? const Icon(
                                    Icons.broken_image_outlined,
                                    color: AdinnColors.muted,
                                  )
                                : AnnotatedPhotoView(
                                    rp.photo,
                                    borderRadius: 6,
                                    cacheWidth: 300,
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rp?.photo.label ?? 'Photo removed',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${rp?.board.name ?? ''} • '
                                  '${list.length} comment(s)'
                                  '${rp?.fromVersion != null ? ' • from v${rp!.fromVersion} snapshot' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AdinnColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                    for (final cm in list)
                      ListTile(
                        key: Key('rc_list_${cm.id}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CommentMarkerDot(comment: cm, size: 28),
                        title: Text(
                          '${cm.type.label} – '
                          '${commentItemLabel(rp?.board, cm.unitId)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          cm.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: CommentStatusChip(cm.status),
                        onTap: () => showCommentDetails(
                          context,
                          shopId: shop.id,
                          commentId: cm.id,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
    ];
  }
}
