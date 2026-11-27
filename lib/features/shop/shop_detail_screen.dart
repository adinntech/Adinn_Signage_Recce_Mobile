import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/language_switcher.dart';
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
import '../report/recce_pdf_card.dart';
import '../report/reports_screen.dart';
import '../review_comments/shop_comments_screen.dart';
import '../survey/feasibility.dart';
import '../survey/markup_entry.dart';
import '../survey/readiness.dart';
import 'add_media_sheet.dart';
import 'shop_form_screen.dart';

/// Locale-aware "17 Nov 2026, 4:05 PM" for predefined date labels.
String _fmtDateTimeL(BuildContext context, DateTime value) {
  final d = value.toLocal();
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${context.fmtDateL(d)}, $h:${two(d.minute)} '
      '${d.hour < 12 ? 'AM' : 'PM'}';
}

/// Localize each installation value separately BEFORE composing the summary.
/// Never pass a finished English sentence to an exact-match dictionary.
String _installationSummaryL(BuildContext context, Board b) {
  const empty = 'Installation not set';
  if (!context.isTamil) {
    return SignageCatalog.installationSummary(b, empty: empty);
  }
  if (SignageCatalog.hasMixedInstallations(b)) {
    final names = <String>[
      for (final u in b.activeUnits)
        context.installationLabel(
          SignageCatalog.installationNameOf(b, u, empty: empty),
        ),
    ].toSet().toList();
    return context.uf('Mixed ({0})', [names.join(' / ')]);
  }
  final first = b.activeUnits.firstOrNull;
  if (first != null &&
      SignageCatalog.isOtherInstallation(
        SignageCatalog.primaryInstallation(b),
      )) {
    return context.installationLabel(
      SignageCatalog.installationNameOf(b, first, empty: empty),
    );
  }
  return context.installationLabel(
    SignageCatalog.installation(SignageCatalog.primaryInstallation(b))?.name ??
        empty,
  );
}

/// App-generated names get a Tamil prefix; custom names stay untouched.
String _boardNameL(BuildContext context, Board b) =>
    SignageCatalog.isAutoBoardName(b.name)
    ? context.generatedBoardName(b.name)
    : b.name;

String _unitNameL(BuildContext context, Board b, SignageUnit u) {
  final name = SignageCatalog.unitName(b, u);
  return SignageCatalog.isAutoBoardName(name)
      ? context.generatedBoardName(name)
      : name;
}

class ShopDetailScreen extends StatelessWidget {
  const ShopDetailScreen({super.key, required this.shopId});

  final String shopId;

  void _openBoard(BuildContext context, String boardId, {BoardIssue? issue}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BoardEditorScreen(
          shopId: shopId,
          boardId: boardId,
          initialUnitId: issue?.unitId,
          initialStep: issue == null
              ? null
              : BoardEditorScreen.stepFor(issue.section),
        ),
      ),
    );
  }

  /// "+ Add media type": board-count popup first; boards are created only
  /// after the vendor confirms the whole configuration.
  Future<void> _addMedia(BuildContext context) async {
    final c = context.read<AppController>();
    final created = await runAddMedia(context, c, shopId);
    if (created.isNotEmpty && context.mounted) {
      _openBoard(context, created.first.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(shopId);
    if (shop == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.search_off,
          title: context.ui('Shop not found'),
        ),
      );
    }
    final editable = c.canEdit(shop);
    final project = c.project(shop.projectId);
    final task = c.task(shop.taskId);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.shopName(shop), overflow: TextOverflow.ellipsis),
        actions: [
          const LanguageSwitcher(),
          if (editable)
            IconButton(
              tooltip: context.ui('Edit shop details'),
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
                    title: context.ui('Delete shop?'),
                    message: context.uf(
                      'This removes {0} and all its boards, photos '
                      'and notes from this device.',
                      [shop.name],
                    ),
                    confirmText: context.ui('Delete'),
                    destructive: true,
                  );
                  if (ok && context.mounted) {
                    await context.read<AppController>().deleteShop(shop.id);
                    if (context.mounted) Navigator.of(context).pop();
                  }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'history',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text(context.ui('Version history')),
                ),
              ),
              PopupMenuItem(
                value: 'timeline',
                child: ListTile(
                  leading: Icon(Icons.timeline),
                  title: Text(context.ui('Activity timeline')),
                ),
              ),
              if (c.canDeleteShop(shop))
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text(context.ui('Delete shop')),
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
            title: context.ui('Shop details'),
            icon: Icons.storefront_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(
                  context.ui('Project'),
                  project == null
                      ? ''
                      : context.projectName(project.id, project.name),
                ),
                InfoRow(context.ui('Task'), task?.title ?? ''),
                InfoRow(context.ui('Owner'), context.shopOwner(shop)),
                InfoRow(context.ui('Phone'), shop.phone),
                InfoRow(context.ui('Address'), context.shopFullAddress(shop)),
                InfoRow(context.ui('Landmark'), shop.landmark),
                if (shop.remarks.isNotEmpty)
                  InfoRow(context.ui('Remarks'), shop.remarks),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => dialNumber(context, shop.phone),
                        icon: const Icon(Icons.call),
                        label: Text(context.ui('Call shop')),
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
                        label: Text(
                          context.uf('Versions ({0})', [
                            shop.submissions.length,
                          ]),
                        ),
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
              onContinue: (boardId, issue) =>
                  _openBoard(context, boardId, issue: issue),
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
                      context.uf('Signage requirements ({0})', [
                        shop.boards.length,
                      ]),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (shop.boards.isNotEmpty)
                      Text(
                        context.mediaBoardSummary(
                          shop.boards
                              .map((b) => b.mediaCode)
                              .whereType<String>()
                              .toSet()
                              .length,
                          shop.unitCount,
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdinnColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (editable)
                Flexible(
                  child: TextButton.icon(
                    key: const Key('add_board'),
                    onPressed: () => _addMedia(context),
                    icon: const Icon(Icons.add),
                    label: Text(
                      context.ui('Add media type'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (shop.boards.isEmpty)
            EmptyState(
              icon: Icons.dashboard_customize_outlined,
              title: context.ui('No signage added'),
              message: editable
                  ? context.ui(
                      'Add every media type needed at this shop – shop-name '
                      'board, standees, glass branding… Each can have its '
                      'own quantity.',
                    )
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
          if (shop.boards.isNotEmpty) ...[
            const SizedBox(height: 4),
            RecceReportCard(shopId: shop.id),
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
        title = context.ui('Recce not started');
        body = context.ui(
          'Add boards, capture photos and submit for approval.',
        );
      case RecceStatus.inProgress:
        title = sub == null
            ? context.ui('Draft in progress')
            : context.uf('Draft in progress (next: v{0})', [sub.version + 1]);
        body = context.ui(
          'Complete all boards, then submit for Business approval.',
        );
      case RecceStatus.pendingBusiness:
        title = context.uf('v{0} waiting for Business Team approval', [
          sub?.version ?? 1,
        ]);
        body = sub == null
            ? null
            : context.uf('Submitted {0}', [
                _fmtDateTimeL(context, sub.submittedAt),
              ]);
      case RecceStatus.pendingOps:
        title = context.uf('v{0} waiting for Recce Ops approval', [
          sub?.version ?? 1,
        ]);
        body = context.ui(
          'Business Team approved. Final technical check pending.',
        );
      case RecceStatus.approved:
        title = context.uf('v{0} final approved', [sub?.version ?? 1]);
        body = context.ui('Approved by Business Team and Recce Operations.');
      case RecceStatus.rejectedBusiness:
      case RecceStatus.rejectedOps:
        rejection = sub?.reviews.lastOrNull;
        title = context.uf('v{0} rejected by {1}', [
          sub?.version ?? 1,
          context.ui(rejection?.stage.label ?? 'reviewer'),
        ]);
        body = context.uf('Fix the issues below and resubmit as v{0}.', [
          (sub?.version ?? 1) + 1,
        ]);
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
                    '${rejection.reviewerName} • ${_fmtDateTimeL(context, rejection.at)}',
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
                    Text(
                      context.ui('Items to correct'),
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
                      _boardNameL(context, board),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        context.mediaLabel(
                          media?.shortName ?? context.ui('Media not set'),
                        ),
                        _installationSummaryL(context, board),
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
                          context.uf('Qty {0}', [board.quantity]),
                          icon: Icons.format_list_numbered,
                        ),
                        TagChip(
                          board.isSameSize
                              ? fmtSize(board.width, board.height, board.unit)
                              : context.ui('Varied sizes'),
                          icon: Icons.straighten,
                        ),
                        if (board.quantity > 1)
                          TagChip(
                            board.isSameSize
                                ? context.ui('Same size')
                                : context.uf('{0}/{1} sized', [
                                    board.activeUnits
                                        .where(board.unitHasSize)
                                        .length,
                                    board.quantity,
                                  ]),
                            icon: Icons.view_list_outlined,
                          ),
                        TagChip(
                          context.countLabel(
                            board.photos.length,
                            'photo',
                            'photos',
                            context.ui('Photos'),
                          ),
                          icon: Icons.photo_camera_outlined,
                        ),
                        if (board.previews.isNotEmpty)
                          TagChip(
                            context.countLabel(
                              board.previews.length,
                              'preview',
                              'previews',
                              context.ui('Preview'),
                            ),
                            icon: Icons.layers_outlined,
                          ),
                        if (board.voiceNotes.isNotEmpty)
                          TagChip(
                            context.uf('{0} voice', [board.voiceNotes.length]),
                            icon: Icons.mic_none,
                          ),
                        if (rejected > 0)
                          TagChip(
                            context.uf('{0} to correct', [rejected]),
                            icon: Icons.report_gmailerrorred,
                            color: AdinnColors.red,
                          ),
                        issues.isEmpty
                            ? TagChip(
                                context.ui('Complete'),
                                icon: Icons.check_circle,
                                color: AdinnColors.success,
                              )
                            : TagChip(
                                context.uf('{0} pending', [issues.length]),
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
                              context.uf('+{0} more', [
                                board.activeUnits.length - 12,
                              ]),
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
                  tooltip: context.ui('Board options'),
                  onSelected: (v) async {
                    final ctrl = context.read<AppController>();
                    if (v == 'edit') {
                      onOpen();
                    } else if (v == 'qty') {
                      ctrl.increaseQuantity(shop.id, board, board.quantity + 1);
                      showSnack(
                        context,
                        context.uf('{0}: quantity {1}', [
                          board.name,
                          board.quantity,
                        ]),
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
                      showSnack(context, context.ui('Board duplicated'));
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
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(context.ui('Edit media')),
                    ),
                    PopupMenuItem(
                      value: 'qty',
                      child: Text(context.ui('Add quantity')),
                    ),
                    PopupMenuItem(
                      value: 'units',
                      child: Text(context.ui('View individual units')),
                    ),
                    PopupMenuItem(
                      value: 'dup',
                      child: Text(context.ui('Duplicate configuration')),
                    ),
                    PopupMenuItem(
                      value: 'del',
                      child: Text(context.ui('Delete')),
                    ),
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
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SubmissionScreen(shopId: shop.id),
          ),
        ),
        icon: const Icon(Icons.send_outlined),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Text(
            next == 1
                ? context.ui('REVIEW & SUBMIT')
                : context.uf('REVIEW & RESUBMIT (v{0})', [next]),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    } else if (c.canReview(shop)) {
      button = ElevatedButton.icon(
        key: const Key('open_review'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReviewScreen(shopId: shop.id),
          ),
        ),
        icon: const Icon(Icons.fact_check_outlined),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Text(
            context.uf('REVIEW v{0}', [shop.latestSubmission?.version ?? 1]),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
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
      title: context.ui('Site survey & documents'),
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                context.ui('Site feasibility'),
                style: TextStyle(fontSize: 13, color: AdinnColors.muted),
              ),
              FeasibilityChip(
                feasibility,
                key: const Key('shop_feasibility'),
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            context.ui(
              'Operational indicator from recorded obstructions, electrical and '
              'checklist answers – not a structural, electrical or municipal '
              'certification.',
            ),
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
            title: Text(context.ui('Photo review comments')),
            subtitle: Text(
              comments.isEmpty
                  ? context.ui('No reviewer comments')
                  : context.uf('{0} open • {1} addressed • {2} verified', [
                      open,
                      addressed,
                      verified,
                    ]),
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
            title: Text(context.ui('Measurement PDF report')),
            subtitle: Text(
              reports.isEmpty
                  ? context.ui('Not generated yet')
                  : context.uf('{0} report(s) • latest {1}', [
                      reports.length,
                      _fmtDateTimeL(context, reports.first.generatedAt),
                    ]),
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
            title: Text(context.ui('360° site panorama')),
            subtitle: Text(
              c.panoramasForShop(shop.id).isEmpty
                  ? context.ui('Optional – none imported')
                  : context.uf('{0} panorama(s)', [
                      c.panoramasForShop(shop.id).length,
                    ]),
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

  /// Opens the pending media group at the physical board + section of
  /// [BoardIssue].
  final void Function(String boardId, BoardIssue? issue) onContinue;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final (ready, total) = readyUnitCount(shop);
    final level = shopReadiness(shop);
    final pending = shop.boards
        .where((b) => c.boardIssues(b).isNotEmpty)
        .toList();
    // First pending issue (its physical board + section) to continue at.
    final next = pending.isEmpty
        ? null
        : c.boardIssueDetails(pending.first).first;
    return SectionCard(
      key: const Key('recce_progress'),
      title: context.ui('Recce progress'),
      icon: Icons.donut_large_outlined,
      trailing: ReadinessChip(level, short: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProgressBarLabel(
            value: total == 0 ? 0 : ready / total,
            label: context.readyUnitsSummary(ready, total),
            color: AdinnColors.success,
          ),
          const SizedBox(height: 6),
          Text(
            context.ui(level.label),
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
              onPressed: () => onContinue(pending.first.id, next),
              icon: const Icon(Icons.play_arrow),
              label: Text(
                context.continueAction(
                  pending.first.unitById(next?.unitId) != null &&
                          pending.first.activeUnits.length > 1
                      ? _unitNameL(
                          context,
                          pending.first,
                          pending.first.unitById(next!.unitId)!,
                        )
                      : _boardNameL(context, pending.first),
                  context.ui(next?.text ?? ''),
                ),
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
