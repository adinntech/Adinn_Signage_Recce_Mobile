import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_file_row.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/history_controllers.dart';
import '../data/live_services.dart';
import '../data/recce_api.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';
import 'capture_flow.dart';
import 'live_widgets.dart';

/// GPS first, then the camera, then queues ONLY this photo as the replacement of [old] (same category, `meta.replaces` = old id).
/// Other photos, approved or not, are not touched and not asked for again.
Future<void> replaceFlaggedPhoto(BuildContext context, ShopDetailController ctrl, ShopPhoto old) async {
  final label = photoCategoryLabel(old.category);
  final shot = await captureGeoPhoto(context, label: label);
  if (shot == null) return;
  final err = await ctrl.queueReplacement(
    old,
    path: shot.path,
    capturedAt: shot.capturedAt,
    lat: shot.lat,
    lng: shot.lng,
    accuracy: shot.accuracy,
    width: shot.width,
    height: shot.height,
    device: deviceLabel(),
  );
  if (!context.mounted) return;
  showSnack(context, err ?? '$label saved on the phone and uploading. Submit the next version when you are done.', error: err != null);
}

/// Rework detail of one flagged photo: why, who asked and when, the open rework note, the photo, its history, and "Replace photo".
Future<void> showReworkSheet(BuildContext context, {required ShopDetailController ctrl, required ShopPhoto photo}) async {
  final api = context.read<LiveServices>().api;
  final replace = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ReworkSheet(ctrl: ctrl, photo: photo, api: api),
  );
  if (replace == true && context.mounted) await replaceFlaggedPhoto(context, ctrl, photo);
}

class ReworkSheet extends StatefulWidget {
  const ReworkSheet({super.key, required this.ctrl, required this.photo, required this.api});

  final ShopDetailController ctrl;
  final ShopPhoto photo;
  final RecceApi api;

  @override
  State<ReworkSheet> createState() => _ReworkSheetState();
}

class _ReworkSheetState extends State<ReworkSheet> {
  late final PhotoHistoryController _history = PhotoHistoryController(widget.api, widget.ctrl.siteId, widget.photo.id)..load();

  @override
  void dispose() {
    _history.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return ListenableBuilder(
      listenable: Listenable.merge([ctrl, _history]),
      builder: (context, _) {
        // The same photo as the shop holds it now: its signed picture link is refreshed when the shop is read again.
        final p = ctrl.detail?.photos.where((x) => x.id == widget.photo.id).firstOrNull ?? widget.photo;
        final note = ctrl.detail?.reworkNoteFor(p);
        final draft = ctrl.draftReplacementOf(p);
        final waiting = ctrl.pendingReplacementOf(p);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(p.isRejected || (note?.rejected ?? false) ? Icons.cancel : Icons.flag, color: AdinnColors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text(p.isRejected || (note?.rejected ?? false) ? 'Rejected' : 'Rework required', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AdinnColors.red))),
                  TagChip(photoCategoryLabel(p.category), icon: Icons.photo_camera_outlined),
                ]),
                const SizedBox(height: 12),
                ReworkBox(note: note),
                const SizedBox(height: 14),
                if (waiting != null || draft != null) ...[
                  // The photo the reviewer flagged next to the one that replaces it: the person sees what changed before submitting.
                  _BeforeAfter(old: p, draft: draft, waiting: waiting, rejected: p.isRejected || (note?.rejected ?? false)),
                ] else ...[
                  const Text('Original photo', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  if (p.displayUrl != null)
                    GestureDetector(
                      onTap: () => showAppPhotoViewer(context, title: photoCategoryLabel(p.category), url: p.displayUrl),
                      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(height: 190, width: double.infinity, child: AppFileRow.image(p.displayUrl, null))),
                    ),
                ],
                const SizedBox(height: 6),
                Text(
                  [
                    if (p.capturedAt != null) 'Captured ${fmtDateTime(p.capturedAt!)}',
                    if (p.hasGps) 'GPS ${p.lat!.toStringAsFixed(5)}, ${p.lng!.toStringAsFixed(5)}' else 'No GPS',
                    if (p.version != null) 'In V${p.version}',
                  ].join('  |  '),
                  style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
                ),
                if (waiting != null || draft != null) ...[
                  const SizedBox(height: 12),
                  _ReplacementStatus(draft: draft, waiting: waiting),
                ],
                if (ctrl.canEdit) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(draft != null || waiting != null ? 'Replace again' : 'Replace photo'),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Only this photo is retaken. Your other photos stay as they are.', style: TextStyle(fontSize: 12, color: AdinnColors.muted)),
                  ),
                ],
                const SizedBox(height: 18),
                const Text('History of this photo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 6),
                HistoryBody(ctrl: _history),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReplacementStatus extends StatelessWidget {
  const _ReplacementStatus({this.draft, this.waiting});

  final ShopPhoto? draft;
  final UploadItem? waiting;

  @override
  Widget build(BuildContext context) {
    final up = waiting;
    final text = up != null
        ? switch (up.status) {
            UploadStatus.queued => 'New photo saved on the phone. Waiting to upload.',
            UploadStatus.uploading => 'Uploading the new photo ${(up.progress * 100).round()}%',
            UploadStatus.failed => 'New photo upload failed: ${up.error ?? 'try again'}',
          }
        : 'New photo is ready. It goes for review when you submit the next version.';
    final bad = up?.status == UploadStatus.failed;
    final color = bad ? AdinnColors.red : (up != null ? AdinnColors.info : AdinnColors.success);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.35))),
      child: Row(children: [
        Icon(bad ? Icons.error_outline : (up != null ? Icons.cloud_upload_outlined : Icons.check_circle), color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13))),
      ]),
    );
  }
}

/// The flagged photo and its replacement side by side ("Rejected photo" / "New photo"); tap either to zoom.
class _BeforeAfter extends StatelessWidget {
  const _BeforeAfter({required this.old, required this.draft, required this.waiting, required this.rejected});

  final ShopPhoto old;
  final ShopPhoto? draft;
  final UploadItem? waiting;
  final bool rejected;

  @override
  Widget build(BuildContext context) {
    final title = photoCategoryLabel(old.category);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: _PhotoSide(key: const Key('before-photo'), label: rejected ? 'Rejected photo' : 'Earlier photo', color: AdinnColors.red, title: title, url: old.displayUrl)),
      const SizedBox(width: 10),
      Expanded(child: _PhotoSide(key: const Key('after-photo'), label: 'New photo', color: AdinnColors.success, title: title, url: draft?.displayUrl, localPath: waiting?.path)),
    ]);
  }
}

class _PhotoSide extends StatelessWidget {
  const _PhotoSide({super.key, required this.label, required this.color, required this.title, this.url, this.localPath});

  final String label;
  final Color color;
  final String title;
  final String? url;
  final String? localPath;

  @override
  Widget build(BuildContext context) {
    final has = url != null || localPath != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: has ? () => showAppPhotoViewer(context, title: '$label: $title', url: url, localPath: localPath) : null,
        child: Container(
          height: 150,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: has ? AppFileRow.image(url, localPath) : const ColoredBox(color: AdinnColors.canvas, child: Center(child: Icon(Icons.hourglass_empty, color: AdinnColors.muted))),
          ),
        ),
      ),
    ]);
  }
}

/// "History of this photo" for a photo that replaced an earlier one (shown from the photo's own sheet after the new version went
/// for review): every revision as a thumbnail (tap to zoom) and the timeline of who rejected / replaced it and when. It reads the
/// photo's history from the server, so the earlier pictures stay viewable after the next version is submitted.
class PhotoHistorySection extends StatefulWidget {
  const PhotoHistorySection({super.key, required this.api, required this.siteId, required this.photoId});

  final RecceApi api;
  final String siteId;
  final String photoId;

  @override
  State<PhotoHistorySection> createState() => _PhotoHistorySectionState();
}

class _PhotoHistorySectionState extends State<PhotoHistorySection> {
  late final PhotoHistoryController _ctrl = PhotoHistoryController(widget.api, widget.siteId, widget.photoId)..load();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Earlier photos and history', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 6),
          ListenableBuilder(listenable: _ctrl, builder: (context, _) => HistoryBody(ctrl: _ctrl)),
        ],
      );
}

class HistoryBody extends StatelessWidget {
  const HistoryBody({super.key, required this.ctrl});
  final PhotoHistoryController ctrl;

  @override
  Widget build(BuildContext context) {
    if (ctrl.loading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    if (ctrl.error != null) {
      return Row(children: [
        Expanded(child: Text(ctrl.error!, style: const TextStyle(color: AdinnColors.red))),
        TextButton.icon(onPressed: ctrl.load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]);
    }
    final h = ctrl.history;
    if (h == null) return const SizedBox.shrink();
    final lines = h.timeline;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (h.revisions.length > 1) ...[
        Text('${h.revisions.length} revisions of this photo', style: const TextStyle(color: AdinnColors.muted, fontSize: 13)),
        const SizedBox(height: 6),
        SizedBox(
          height: 92,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final r in h.revisions) _RevisionThumb(r),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      if (lines.isEmpty)
        const Text('No earlier history.', style: TextStyle(color: AdinnColors.muted))
      else
        for (var i = 0; i < lines.length; i++) PhotoHistoryRow(line: lines[i], last: i == lines.length - 1),
    ]);
  }
}

class _RevisionThumb extends StatelessWidget {
  const _RevisionThumb(this.r);
  final PhotoRevision r;

  @override
  Widget build(BuildContext context) {
    final p = r.photo;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: p.displayUrl == null ? null : () => showAppPhotoViewer(context, title: 'Revision ${r.revision}', url: p.displayUrl),
        child: Column(children: [
          SizedBox(
            width: 84,
            height: 62,
            child: ClipRRect(borderRadius: BorderRadius.circular(8), child: AppFileRow.image(p.displayUrl, null)),
          ),
          const SizedBox(height: 2),
          Text(r.current ? 'Revision ${r.revision} (latest)' : 'Revision ${r.revision}', style: const TextStyle(fontSize: 10, color: AdinnColors.muted)),
        ]),
      ),
    );
  }
}

/// One line of a vertical, time-ordered list (dot and rail on the left).
class PhotoHistoryRow extends StatelessWidget {
  const PhotoHistoryRow({super.key, required this.line, this.last = false});

  final PhotoHistoryLine line;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = line.kind == 'rework' ? AdinnColors.red : AdinnColors.info;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 22,
          child: Column(children: [
            const SizedBox(height: 4),
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            if (!last) Expanded(child: Container(width: 2, color: AdinnColors.line)),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                [if (line.at != null) fmtDateTime(line.at!), if (line.who.isNotEmpty) line.who, if (line.version != null) 'V${line.version}'].join('  |  '),
                style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
              ),
              if (line.detail.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(line.detail, style: const TextStyle(fontSize: 13))),
            ]),
          ),
        ),
      ]),
    );
  }
}
