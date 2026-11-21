import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../approvals/review_screen.dart';
import '../board/board_editor_screen.dart';
import '../board/units_screen.dart';
import '../history/activity_screen.dart';
import '../history/version_history_screen.dart';
import '../location/gps_widgets.dart';
import '../panorama/panorama_list_screen.dart';
import '../photos/site_photo_view.dart';
import '../submission/submission_screen.dart';
import '../report/reports_screen.dart';
import '../review_comments/shop_comments_screen.dart';
import '../survey/feasibility.dart';
import '../survey/markup_entry.dart';
import '../survey/readiness.dart';
import 'shop_form_screen.dart';

class ShopDetailScreen extends StatelessWidget {
  const ShopDetailScreen({super.key, required this.shopId});

  final String shopId;

  void _openBoard(BuildContext context, String boardId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BoardEditorScreen(shopId: shopId, boardId: boardId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(shopId);
    if (shop == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.search_off, title: 'Shop not found'),
      );
    }
    final editable = c.canEdit(shop);
    final project = c.project(shop.projectId);
    final task = c.task(shop.taskId);

    return Scaffold(
      appBar: AppBar(
        title: Text(shop.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (editable)
            IconButton(
              tooltip: 'Edit shop details',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ShopFormScreen(taskId: shop.taskId, shopId: shop.id),
                ),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'history':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VersionHistoryScreen(shopId: shop.id),
                    ),
                  );
                case 'timeline':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ActivityScreen(shopId: shop.id),
                    ),
                  );
                case 'delete':
                  final ok = await confirmDialog(
                    context,
                    title: 'Delete shop?',
                    message:
                        'This removes ${shop.name} and all its boards, photos '
                        'and notes from this device.',
                    confirmText: 'Delete',
                    destructive: true,
                  );
                  if (ok && context.mounted) {
                    await context.read<AppController>().deleteShop(shop.id);
                    if (context.mounted) Navigator.of(context).pop();
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'history',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Version history'),
                ),
              ),
              const PopupMenuItem(
                value: 'timeline',
                child: ListTile(
                  leading: Icon(Icons.timeline),
                  title: Text('Activity timeline'),
                ),
              ),
              if (c.canDeleteShop(shop))
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete shop'),
                  ),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: _BottomAction(shop: shop),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          StatusBanner(shop: shop),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Shop details',
            icon: Icons.storefront_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow('Project', project?.name ?? ''),
                InfoRow('Task', task?.title ?? ''),
                InfoRow('Owner', shop.ownerName),
                InfoRow('Phone', shop.phone),
                InfoRow('Address', shop.fullAddress),
                InfoRow('Landmark', shop.landmark),
                if (shop.remarks.isNotEmpty) InfoRow('Remarks', shop.remarks),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => dialNumber(context, shop.phone),
                        icon: const Icon(Icons.call),
                        label: const Text('Call shop'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                VersionHistoryScreen(shopId: shop.id),
                          ),
                        ),
                        icon: const Icon(Icons.history),
                        label: Text('Versions (${shop.submissions.length})'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ShopLocationCard(shop: shop, editable: editable),
          const SizedBox(height: 12),
          _SurveyDocsCard(shop: shop),
          if (shop.boards.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ProgressCard(
              shop: shop,
              editable: editable,
              onContinue: (boardId) => _openBoard(context, boardId),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Signage requirements (${shop.boards.length})',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (shop.boards.isNotEmpty)
                      Text(
                        '${shop.boards.map((b) => b.mediaCode).whereType<String>().toSet().length} media type(s) • '
                        '${shop.unitCount} signage unit${shop.unitCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdinnColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (editable)
                TextButton.icon(
                  key: const Key('add_board'),
                  onPressed: () {
                    final b = context.read<AppController>().addBoard(shop.id);
                    _openBoard(context, b.id);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add media type'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (shop.boards.isEmpty)
            EmptyState(
              icon: Icons.dashboard_customize_outlined,
              title: 'No signage added',
              message: editable
                  ? 'Add every media type needed at this shop – shop-name '
                        'board, standees, glass branding… Each can have its '
                        'own quantity.'
                  : null,
            ),
          for (final b in shop.boards) ...[
            _BoardCard(
              shop: shop,
              board: b,
              editable: editable,
              onOpen: () => _openBoard(context, b.id),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// Coloured banner explaining where the recce is in the approval flow.
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    final sub = shop.latestSubmission;
    final status = shop.status;
    String title;
    String? body;
    ReviewRecord? rejection;
    switch (status) {
      case RecceStatus.notStarted:
        title = 'Recce not started';
        body = 'Add boards, capture photos and submit for approval.';
      case RecceStatus.inProgress:
        title = sub == null
            ? 'Draft in progress'
            : 'Draft in progress (next: v${sub.version + 1})';
        body = 'Complete all boards, then submit for Business approval.';
      case RecceStatus.pendingBusiness:
        title = 'v${sub?.version ?? 1} waiting for Business Team approval';
        body = sub == null ? null : 'Submitted ${fmtDateTime(sub.submittedAt)}';
      case RecceStatus.pendingOps:
        title = 'v${sub?.version ?? 1} waiting for Recce Ops approval';
        body = 'Business Team approved. Final technical check pending.';
      case RecceStatus.approved:
        title = 'v${sub?.version ?? 1} final approved';
        body = 'Approved by Business Team and Recce Operations.';
      case RecceStatus.rejectedBusiness:
      case RecceStatus.rejectedOps:
        rejection = sub?.reviews.lastOrNull;
        title =
            'v${sub?.version ?? 1} rejected by ${rejection?.stage.label ?? 'reviewer'}';
        body =
            'Fix the issues below and resubmit as v${(sub?.version ?? 1) + 1}.';
    }
    final color = status.color;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(status.icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (body != null) ...[
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(fontSize: 13)),
          ],
          if (rejection != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${rejection.reviewerName} • ${fmtDateTime(rejection.at)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdinnColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('"${rejection.remarks}"'),
                  if (rejection.reasons.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final r in rejection.reasons)
                          TagChip(r, color: AdinnColors.red),
                      ],
                    ),
                  ],
                  if (rejection.issues.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Items to correct',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final i in rejection.issues)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.subdirectory_arrow_right,
                              size: 16,
                              color: AdinnColors.red,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                i.text,
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.shop,
    required this.board,
    required this.editable,
    required this.onOpen,
  });

  final Shop shop;
  final Board board;
  final bool editable;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.read<AppController>();
    final media = SignageCatalog.media(board.mediaCode);
    final inst = SignageCatalog.installation(board.installationCode);
    final issues = c.boardIssues(board);
    final rejected = c
        .openIssues(shop)
        .where((i) => i.groupId == board.id)
        .length;
    final firstPhoto = board.photos.firstOrNull;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                child: firstPhoto != null
                    ? AnnotatedPhotoView(firstPhoto, cacheWidth: 300)
                    : Container(
                        height: 69,
                        decoration: BoxDecoration(
                          color: AdinnColors.canvas,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AdinnColors.line),
                        ),
                        child: Icon(
                          media?.icon ?? Icons.add_a_photo_outlined,
                          color: AdinnColors.muted,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      board.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        media?.shortName ?? 'Media not set',
                        inst?.name ?? 'Installation not set',
                      ].join(' • '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdinnColors.muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        TagChip(
                          'Qty ${board.quantity}',
                          icon: Icons.format_list_numbered,
                        ),
                        TagChip(
                          board.isSameSize
                              ? fmtSize(board.width, board.height, board.unit)
                              : 'Varied sizes',
                          icon: Icons.straighten,
                        ),
                        if (board.quantity > 1)
                          TagChip(
                            board.isSameSize
                                ? 'Same size'
                                : '${board.activeUnits.where(board.unitHasSize).length}/${board.quantity} sized',
                            icon: Icons.view_list_outlined,
                          ),
                        TagChip(
                          '${board.photos.length} photo${board.photos.length == 1 ? '' : 's'}',
                          icon: Icons.photo_camera_outlined,
                        ),
                        if (board.previews.isNotEmpty)
                          TagChip(
                            '${board.previews.length} preview${board.previews.length == 1 ? '' : 's'}',
                            icon: Icons.layers_outlined,
                          ),
                        if (board.voiceNotes.isNotEmpty)
                          TagChip(
                            '${board.voiceNotes.length} voice',
                            icon: Icons.mic_none,
                          ),
                        if (rejected > 0)
                          TagChip(
                            '$rejected to correct',
                            icon: Icons.report_gmailerrorred,
                            color: AdinnColors.red,
                          ),
                        issues.isEmpty
                            ? const TagChip(
                                'Complete',
                                icon: Icons.check_circle,
                                color: AdinnColors.success,
                              )
                            : TagChip(
                                '${issues.length} pending',
                                icon: Icons.error_outline,
                                color: AdinnColors.warning,
                              ),
                      ],
                    ),
                    if (board.mediaCode != null) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final u in board.activeUnits.take(12))
                            Tooltip(
                              message: unitReadiness(
                                shop,
                                board,
                                u,
                              ).reasons.take(3).join('\n'),
                              child: Row(
                                key: Key('unit_ready_${u.id}'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'U${board.unitLabel(u).substring(5)} ',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AdinnColors.muted,
                                    ),
                                  ),
                                  Flexible(
                                    child: ReadinessChip(
                                      unitReadiness(shop, board, u).level,
                                      short: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (board.activeUnits.length > 12)
                            Text(
                              '+${board.activeUnits.length - 12} more',
                              style: const TextStyle(fontSize: 11),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (editable)
                PopupMenuButton<String>(
                  tooltip: 'Board options',
                  onSelected: (v) async {
                    final ctrl = context.read<AppController>();
                    if (v == 'edit') {
                      onOpen();
                    } else if (v == 'qty') {
                      ctrl.increaseQuantity(shop.id, board, board.quantity + 1);
                      showSnack(
                        context,
                        '${board.name}: quantity ${board.quantity}',
                      );
                    } else if (v == 'units') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => UnitsScreen(
                            shopId: shop.id,
                            boardId: board.id,
                            onOpenPhotoMarkup: (ctx, p) =>
                                openPhotoMarkup(ctx, shop.id, p),
                          ),
                        ),
                      );
                    } else if (v == 'dup') {
                      ctrl.duplicateBoard(shop.id, board.id);
                      showSnack(context, 'Board duplicated');
                    } else if (v == 'del') {
                      final submitted = shop.submissions.any(
                        (s) => (s.snapshot['boards'] as List? ?? const [])
                            .whereType<Map>()
                            .any((m) => m['id'] == board.id),
                      );
                      final ok = await confirmDialog(
                        context,
                        title: 'Delete ${board.name}?',
                        message:
                            'Photos, drawings and voice notes of this board '
                            'will be removed.'
                            '${submitted ? ' Earlier submitted versions keep their copy in version history.' : ''}',
                        confirmText: 'Delete',
                        destructive: true,
                      );
                      if (ok) await ctrl.deleteBoard(shop.id, board.id);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit media')),
                    PopupMenuItem(value: 'qty', child: Text('Add quantity')),
                    PopupMenuItem(
                      value: 'units',
                      child: Text('View individual units'),
                    ),
                    PopupMenuItem(
                      value: 'dup',
                      child: Text('Duplicate configuration'),
                    ),
                    PopupMenuItem(value: 'del', child: Text('Delete')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    Widget? button;
    if (c.canEdit(shop)) {
      final next = shop.submissions.length + 1;
      button = ElevatedButton.icon(
        key: const Key('open_submit'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SubmissionScreen(shopId: shop.id),
          ),
        ),
        icon: const Icon(Icons.send_outlined),
        label: Text(
          next == 1 ? 'REVIEW & SUBMIT' : 'REVIEW & RESUBMIT (v$next)',
        ),
      );
    } else if (c.canReview(shop)) {
      button = ElevatedButton.icon(
        key: const Key('open_review'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReviewScreen(shopId: shop.id),
          ),
        ),
        icon: const Icon(Icons.fact_check_outlined),
        label: Text('REVIEW v${shop.latestSubmission?.version ?? 1}'),
      );
    }
    if (button == null) return const SizedBox.shrink();
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AdinnColors.line)),
        ),
        child: button,
      ),
    );
  }
}

/// Advanced site survey summary: feasibility, reviewer photo comments and
/// measurement PDF reports of the shop.
class _SurveyDocsCard extends StatelessWidget {
  const _SurveyDocsCard({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final comments = c.reviewComments(shop.id);
    final open = comments.where((x) => x.status == CommentStatus.open).length;
    final addressed = comments
        .where((x) => x.status == CommentStatus.addressed)
        .length;
    final verified = comments
        .where((x) => x.status == CommentStatus.verified)
        .length;
    final reports = c.reportsForShop(shop.id);
    final feasibility = shopFeasibility(shop);
    return SectionCard(
      title: 'Site survey & documents',
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Site feasibility',
                style: TextStyle(fontSize: 13, color: AdinnColors.muted),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FeasibilityChip(
                  feasibility,
                  key: const Key('shop_feasibility'),
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Operational indicator from recorded obstructions, electrical and '
            'checklist answers – not a structural, electrical or municipal '
            'certification.',
            style: TextStyle(fontSize: 11, color: AdinnColors.muted),
          ),
          const Divider(height: 18),
          ListTile(
            key: const Key('open_shop_comments'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.mode_comment_outlined,
              color: open > 0 ? AdinnColors.red : AdinnColors.ink,
            ),
            title: const Text('Photo review comments'),
            subtitle: Text(
              comments.isEmpty
                  ? 'No reviewer comments'
                  : '$open open • $addressed addressed • $verified verified',
              style: TextStyle(
                color: open > 0 && shop.status.isRejected
                    ? AdinnColors.red
                    : AdinnColors.muted,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ShopCommentsScreen(shopId: shop.id),
              ),
            ),
          ),
          ListTile(
            key: const Key('open_reports'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Measurement PDF report'),
            subtitle: Text(
              reports.isEmpty
                  ? 'Not generated yet'
                  : '${reports.length} report(s) • latest '
                        '${fmtDateTime(reports.first.generatedAt)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReportsScreen(shopId: shop.id),
              ),
            ),
          ),
          ListTile(
            key: const Key('open_panoramas'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.panorama_photosphere_outlined),
            title: const Text('360° site panorama'),
            subtitle: Text(
              c.panoramasForShop(shop.id).isEmpty
                  ? 'Optional – none imported'
                  : '${c.panoramasForShop(shop.id).length} panorama(s)',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PanoramaListScreen(shopId: shop.id),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recce progress: ready units, overall readiness and a shortcut to the
/// first media group that still needs work.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.shop,
    required this.editable,
    required this.onContinue,
  });

  final Shop shop;
  final bool editable;
  final ValueChanged<String> onContinue;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final (ready, total) = readyUnitCount(shop);
    final level = shopReadiness(shop);
    final pending = shop.boards
        .where((b) => c.boardIssues(b).isNotEmpty)
        .toList();
    return SectionCard(
      key: const Key('recce_progress'),
      title: 'Recce progress',
      icon: Icons.donut_large_outlined,
      trailing: ReadinessChip(level, short: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProgressBarLabel(
            value: total == 0 ? 0 : ready / total,
            label:
                '$ready of $total signage unit${total == 1 ? '' : 's'} '
                'ready for review',
            color: AdinnColors.success,
          ),
          const SizedBox(height: 6),
          Text(
            level.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: level.color,
            ),
          ),
          if (editable && pending.isNotEmpty) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('continue_recce'),
              onPressed: () => onContinue(pending.first.id),
              icon: const Icon(Icons.play_arrow),
              label: Text(
                'Continue: ${pending.first.name} – '
                '${c.boardIssues(pending.first).first}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
