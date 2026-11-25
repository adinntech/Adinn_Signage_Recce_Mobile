import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_file_row.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/history_controllers.dart';
import '../data/recce_api.dart';
import '../data/recce_models.dart';
import 'live_widgets.dart';

/// Approval History: the shop's timeline from `GET /recce/shops/:siteId/activity`, in the phone's local time.
/// Oldest first by default (Submitted V1 -> Client Servicing approved -> Recce Operations requested rework -> Resubmitted V2 ...),
/// with a toggle for newest first and a switch to see every event, not only the approval steps.
class ApprovalHistoryScreen extends StatefulWidget {
  const ApprovalHistoryScreen({super.key, required this.api, required this.detail, this.versions = const []});

  final RecceApi api;
  final ShopDetail detail;
  final List<RecceVersion> versions;

  @override
  State<ApprovalHistoryScreen> createState() => _ApprovalHistoryScreenState();
}

class _ApprovalHistoryScreenState extends State<ApprovalHistoryScreen> {
  /// Loads the timeline and reads the shop and its versions again, so the photo pictures have fresh signed links every time the
  /// screen is opened or pulled down (the links given by the shop screen may have expired by then).
  late final ActivityController _ctrl = ActivityController(widget.api, widget.detail.siteId, detail: widget.detail, versions: widget.versions)..load();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Approval history')),
      body: ListenableBuilder(
        listenable: _ctrl,
        builder: (context, _) {
          if (_ctrl.loading && _ctrl.events.isEmpty) return const Center(child: CircularProgressIndicator());
          if (_ctrl.error != null && _ctrl.events.isEmpty) return ErrorRetry(message: _ctrl.error!, onRetry: _ctrl.load);
          final list = _ctrl.visible;
          final d = _ctrl.detail ?? widget.detail;
          final photos = _ctrl.photos;
          return RefreshIndicator(
            onRefresh: _ctrl.load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Row(children: [
                  Expanded(child: Text(d.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  StatusPill(d.status),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [ButtonSegment(value: false, label: Text('Oldest first')), ButtonSegment(value: true, label: Text('Newest first'))],
                      selected: {_ctrl.newestFirst},
                      onSelectionChanged: (s) => _ctrl.setNewestFirst(s.first),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  ChoiceChip(label: const Text('Approval steps'), selected: !_ctrl.showAll, onSelected: (_) => _ctrl.setShowAll(false)),
                  ChoiceChip(label: Text(_ctrl.hiddenCount > 0 ? 'All activity (+${_ctrl.hiddenCount})' : 'All activity'), selected: _ctrl.showAll, onSelected: (_) => _ctrl.setShowAll(true)),
                ]),
                const SizedBox(height: 14),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: EmptyState(icon: Icons.history, title: 'No history yet', message: 'Submissions and review decisions of this shop appear here.'),
                  )
                else
                  for (var i = 0; i < list.length; i++)
                    ActivityTile(
                      event: list[i],
                      last: i == list.length - 1,
                      photo: list[i].photo == null ? null : photos[list[i].photo],
                      rework: reworkForEvent(list[i], d.reworks),
                      boardLabels: d.boardLabels,
                      board: list[i].mediaKey == null ? null : _boardText(d, list[i].mediaKey!),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }

  String? _boardText(ShopDetail d, String key) {
    for (final b in d.mediaItems) {
      if (b.key == key) return '$key: ${boardSummaryText(b)}';
    }
    return 'Board $key';
  }
}

IconData _iconOf(String type) => switch (type) {
      'SUBMISSION_CREATED' || 'REWORK_SUBMITTED' => Icons.send_outlined,
      'REVIEW_APPROVED' => Icons.check_circle,
      'FINAL_APPROVAL' => Icons.verified,
      'REWORK_REQUESTED' || 'ADDITIONAL_PHOTOS_REQUESTED' => Icons.flag,
      'REVIEW_REJECTED' => Icons.cancel,
      'REOPENED' => Icons.lock_open,
      'PHOTO_CAPTURED' || 'PHOTO_REPLACED' || 'PHOTO_ANNOTATED' => Icons.photo_camera_outlined,
      'COMMENT_ADDED' => Icons.chat_bubble_outline,
      _ => Icons.circle,
    };

Color _colorOf(String type) => switch (type) {
      'REVIEW_APPROVED' || 'FINAL_APPROVAL' => statusColor('APPROVED'),
      'REWORK_REQUESTED' || 'ADDITIONAL_PHOTOS_REQUESTED' => statusColor('REWORK_REQUIRED'),
      'REVIEW_REJECTED' => statusColor('REJECTED'),
      'SUBMISSION_CREATED' || 'REWORK_SUBMITTED' => AdinnColors.info,
      _ => AdinnColors.muted,
    };

/// One event of the history: what happened, who did it (and their role), when (local time), the version, the comment, and the
/// related photo or board when the event names one.
class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.event, this.last = false, this.photo, this.rework, this.board, this.boardLabels = const {}});

  final ActivityEvent event;
  final bool last;
  final ShopPhoto? photo;
  final ReworkEntry? rework;
  final String? board;

  /// Board key to "GSB-01", so a board request names the board by its number.
  final Map<String, String> boardLabels;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final color = _colorOf(e.type);
    final changes = e.isApproval ? const <FieldChange>[] : e.detailChanges;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 30,
          child: Column(children: [
            Icon(_iconOf(e.type), size: 20, color: color),
            if (!last) Expanded(child: Container(width: 2, color: AdinnColors.line)),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(e.title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: e.isApproval ? color : AdinnColors.ink))),
                if (e.version != null) TagChip('V${e.version}', icon: Icons.history),
              ]),
              Text(
                [e.who, if (e.at != null) fmtDateTime(e.at!)].join('  |  '),
                style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
              ),
              if (e.reason.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8)),
                  child: Text(e.reason),
                ),
              if (rework != null)
                for (final i in rework!.items) Padding(padding: const EdgeInsets.only(top: 4), child: Text('- ${reworkItemText(i, boardLabels: boardLabels)}', style: const TextStyle(fontSize: 13))),
              if (board != null) Padding(padding: const EdgeInsets.only(top: 6), child: TagChip(board!, icon: Icons.view_in_ar_outlined)),
              if (e.photo != null) Padding(padding: const EdgeInsets.only(top: 6), child: _PhotoRef(photo: photo)),
              for (final c in changes.take(4)) Padding(padding: const EdgeInsets.only(top: 3), child: Text(c.text, style: const TextStyle(fontSize: 12, color: AdinnColors.muted))),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _PhotoRef extends StatelessWidget {
  const _PhotoRef({this.photo});
  final ShopPhoto? photo;

  @override
  Widget build(BuildContext context) {
    final p = photo;
    if (p == null) return const TagChip('Photo (no longer listed)', icon: Icons.photo_outlined);
    return InkWell(
      onTap: p.displayUrl == null ? null : () => showAppPhotoViewer(context, title: photoCategoryLabel(p.category), url: p.displayUrl),
      child: Row(children: [
        SizedBox(width: 44, height: 44, child: ClipRRect(borderRadius: BorderRadius.circular(6), child: AppFileRow.image(p.displayUrl, null, cacheWidth: 150))),
        const SizedBox(width: 8),
        Text(photoCategoryLabel(p.category), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );
  }
}
