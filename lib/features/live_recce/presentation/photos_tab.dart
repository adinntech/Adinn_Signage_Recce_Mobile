import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_file_row.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../live_auth/presentation/live_auth_controller.dart';
import '../data/recce_api.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';
import 'board_views_screen.dart';
import 'capture_flow.dart';
import 'live_widgets.dart';
import 'rework_sheet.dart';

/// Photos: the six live-flow categories as a checklist grid, then the extra categories the server requires, and the photos a
/// reviewer asked for. Tap a box to capture (GPS first, then camera). Pull down to read the shop again (fresh photo links).
class PhotosTab extends StatelessWidget {
  const PhotosTab({super.key, required this.ctrl});

  final ShopDetailController ctrl;

  /// GPS first, then the camera, then the picture is queued. Retaking a DRAFT photo queues the new picture FIRST: the old draft
  /// is deleted from the server only after the new one is stored there (see [ShopDetailController.queueSwap]), so a failed delete
  /// or no network can never lose the new photo. [mediaKey] ties a requested photo to its board (empty = the whole shop).
  Future<void> _capture(BuildContext context, PhotoCategoryDef cat, {ShopPhoto? replacing, String mediaKey = ''}) async {
    final shot = await captureGeoPhoto(context, label: cat.label);
    if (shot == null) return;
    final item = UploadItem(
      id: newClientId(),
      siteId: ctrl.siteId,
      path: shot.path,
      category: cat.key,
      mediaKey: replacing?.mediaKey ?? mediaKey,
      capturedAt: shot.capturedAt,
      lat: shot.lat,
      lng: shot.lng,
      accuracy: shot.accuracy,
      width: shot.width,
      height: shot.height,
      // A submitted photo is replaced through `replaces`. Retaking a draft that itself replaces an older photo keeps that link.
      replaces: replacing == null ? null : (replacing.state != 'DRAFT' ? replacing.id : replacing.replaces),
      device: deviceLabel(),
    );
    ctrl.queueSwap(item, stale: replacing);
    // TESTING ONLY: the same picture for every other empty photo type of the checklist.
    var copies = 0;
    if (showPhotoTestTools && ctrl.useFirstPhotoForAll && replacing == null && mediaKey.isEmpty) {
      copies = await ctrl.queueFirstPhotoForAll(item, _checklist(ctrl.detail!), keepPhotoCopy);
    }
    if (context.mounted) {
      showSnack(context, copies == 0 ? '${cat.label} saved on the phone and uploading.' : '${cat.label} saved and also queued for $copies other photo types (testing).');
    }
  }

  /// The six live-flow photo types plus the extra ones the server requires for this shop.
  List<PhotoCategoryDef> _checklist(ShopDetail d) =>
      [...requiredPhotoCategories, for (final s in d.extraPhotoSlots) PhotoCategoryDef(s.category, s.label, Icons.add_a_photo_outlined)];

  /// Capture for a photo the reviewer asked for. A second take swaps the draft that already answers the request.
  void _captureRequested(BuildContext context, RequestedPhoto req, ShopPhoto? answer) {
    if (!ctrl.canEdit) return showSnack(context, 'This shop is locked. Photos cannot be added now.');
    _capture(context, PhotoCategoryDef(req.category, req.label, Icons.add_a_photo_outlined), replacing: answer, mediaKey: req.mediaKey);
  }

  void _openTile(BuildContext context, PhotoCategoryDef cat, ShopPhoto? photo, UploadItem? pending) {
    if (pending != null) return _pendingSheet(context, cat, pending);
    if (photo != null && photo.needsRework) return _openRework(context, photo);
    if (photo != null) return _photoSheet(context, cat, photo);
    if (ctrl.canEdit) {
      _capture(context, cat);
    } else {
      showSnack(context, 'This shop is locked. Photos cannot be added now.');
    }
  }

  void _pendingSheet(BuildContext context, PhotoCategoryDef cat, UploadItem u) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: ctrl.queue,
        builder: (_, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cat.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(switch (u.status) {
                  UploadStatus.queued => 'Waiting to upload',
                  UploadStatus.uploading => 'Uploading ${(u.progress * 100).round()}%',
                  UploadStatus.failed => 'Failed: ${u.error ?? 'upload failed'}',
                }),
                const SizedBox(height: 14),
                Row(children: [
                  if (u.status == UploadStatus.failed)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          ctrl.queue.retry(u.id);
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ),
                  if (u.status == UploadStatus.failed) const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ctrl.queue.cancel(u.id);
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.close),
                      label: Text(u.status == UploadStatus.failed ? 'Discard' : 'Cancel'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _photoSheet(BuildContext context, PhotoCategoryDef cat, ShopPhoto p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cat.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (p.displayUrl != null)
                GestureDetector(
                  onTap: () => _viewFull(ctx, p),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(height: 180, width: double.infinity, child: _NetImage(p.displayUrl!, onError: ctrl.imageFailed)),
                  ),
                ),
              const SizedBox(height: 10),
              _GpsLine(p),
              Text('Review: ${_reviewLabel(p.review.status)}', style: const TextStyle(color: AdinnColors.muted)),
              if (p.capturedAt != null) Text('Captured ${fmtDateTime(p.capturedAt!)}', style: const TextStyle(color: AdinnColors.muted)),
              if (p.replaces != null) const Padding(padding: EdgeInsets.only(top: 4), child: Text('This photo replaces an earlier one. It goes for review when you submit.', style: TextStyle(color: AdinnColors.info, fontSize: 13))),
              const SizedBox(height: 14),
              if (ctrl.canEdit)
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _capture(context, cat, replacing: p);
                      },
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(p.state == 'DRAFT' ? 'Retake' : 'Replace'),
                    ),
                  ),
                  if (p.state == 'DRAFT') ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await confirmDialog(ctx, title: 'Delete photo?', message: 'This draft photo will be deleted.', confirmText: 'Delete', destructive: true);
                          if (!ok) return;
                          final err = await ctrl.deletePhoto(p);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (err != null && context.mounted) showSnack(context, err, error: true);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ),
                  ],
                ]),
            ],
          ),
        ),
      ),
    );
  }

  void _openRework(BuildContext context, ShopPhoto p) => showReworkSheet(context, ctrl: ctrl, photo: p);

  void _viewFull(BuildContext context, ShopPhoto p) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(children: [
          Positioned.fill(child: InteractiveViewer(child: _NetImage(p.displayUrl!, fit: BoxFit.contain, onError: ctrl.imageFailed))),
          SafeArea(child: IconButton(color: Colors.white, icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop())),
        ]),
      ),
    );
  }

  Widget _grid(BuildContext context, ShopDetail d, List<PhotoCategoryDef> cats) {
    final pending = ctrl.pending;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.92,
      children: [
        for (final c in cats)
          _CategoryTile(
            cat: c,
            photo: d.photoFor(c.key),
            pending: pending.where((u) => u.category == c.key).fold<UploadItem?>(null, (_, u) => u),
            onTap: (photo, pend) => _openTile(context, c, photo, pend),
            onFlag: (photo) => _openRework(context, photo),
            onImageError: ctrl.imageFailed,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = ctrl.detail!;
    final pending = ctrl.pending;
    // The six are the checklist; the server may require more (progress.missing), each with its own tile.
    final tiles = _checklist(d);
    final extras = tiles.sublist(requiredPhotoCategories.length);
    final done = tiles.where((c) => d.photoFor(c.key) != null).length;
    final requested = d.requestedPhotos;
    return RefreshIndicator(
      onRefresh: ctrl.refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (showPhotoTestTools && ctrl.canEdit) _UseFirstPhotoBox(value: ctrl.useFirstPhotoForAll, onChanged: ctrl.setUseFirstPhotoForAll),
          Row(children: [
            Expanded(child: Text('Required photos $done of ${tiles.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            if (pending.isNotEmpty) TagChip('${pending.length} uploading', icon: Icons.cloud_upload_outlined, color: AdinnColors.info),
          ]),
          const SizedBox(height: 4),
          const Text('Tap a box to capture. Your location is read first, then the camera opens.', style: TextStyle(color: AdinnColors.muted, fontSize: 13)),
          const SizedBox(height: 12),
          if (requested.isNotEmpty) ...[
            for (final r in requested) ...[
              _RequestedCard(
                key: ValueKey('req-${r.key}'),
                req: r,
                answer: r.answer(d.photos),
                pending: ctrl.pending.where((u) => u.category == r.category && (r.mediaKey.isEmpty || u.mediaKey == r.mediaKey)).fold<UploadItem?>(null, (_, u) => u),
                enabled: ctrl.canEdit,
                onCapture: (answer) => _captureRequested(context, r, answer),
                onManageUpload: (u) => _pendingSheet(context, PhotoCategoryDef(r.category, r.label, Icons.add_a_photo_outlined), u),
                onImageError: ctrl.imageFailed,
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 2),
          ],
          _grid(context, d, requiredPhotoCategories),
          if (extras.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Also required for this shop', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            const Text('The office needs these photos before the shop can be submitted.', style: TextStyle(color: AdinnColors.muted, fontSize: 13)),
            const SizedBox(height: 10),
            _grid(context, d, extras),
          ],
          _FilesSection(ctrl: ctrl, onOpenRework: (p) => _openRework(context, p), onRemoveDraft: (p) => _confirmRemove(context, p)),
          // Extra, shown only after photos are uploaded: the boards of this shop as a 2D drawing and a 3D model.
          if (d.photos.any((p) => p.displayUrl != null)) ...[
            const SizedBox(height: 16),
            _BoardViewsCard(
              onOpen: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => BoardViewsScreen(detail: d, boards: ctrl.boards, drawnBy: context.read<LiveAuthController>().user?.name ?? '-')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, ShopPhoto p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this photo?'),
        content: const Text('The draft photo will be deleted from the server.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true) return;
    final err = await ctrl.deletePhoto(p);
    if (err != null && context.mounted) showSnack(context, err, error: true);
  }
}

/// The testing tools of the Photos tab are for debug and profile builds only: a release build never shows them.
const showPhotoTestTools = !kReleaseMode;

/// TESTING ONLY. Ticked: the first picture taken is also saved for every other empty photo type of this shop.
class _UseFirstPhotoBox extends StatelessWidget {
  const _UseFirstPhotoBox({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AdinnColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdinnColors.warning.withValues(alpha: 0.45)),
      ),
      child: CheckboxListTile(
        key: const Key('test-first-photo-for-all'),
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: AdinnColors.warning,
        dense: true,
        title: const Text('Use the first photo for all types', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: const Text('For testing only. The first photo you take is also saved for every empty photo type of this shop.', style: TextStyle(fontSize: 12.5)),
      ),
    );
  }
}

/// Entry to the 2D drawing and 3D model of the shop's boards (see [BoardViewsScreen]).
class _BoardViewsCard extends StatelessWidget {
  const _BoardViewsCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AdinnColors.line)),
      child: ListTile(
        key: const Key('open-2d-3d-view'),
        onTap: onOpen,
        leading: const Icon(Icons.view_in_ar_outlined, color: AdinnColors.red, size: 30),
        title: const Text('2D and 3D view', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: const Text('See the boards of this shop as a drawing and a 3D model.'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

String _reviewLabel(String s) => switch (s) {
      'APPROVED' => 'Approved',
      'REJECTED' => 'Rejected',
      'REWORK_REQUIRED' => 'Rework required',
      _ => 'Pending review',
    };

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.cat, required this.photo, required this.pending, required this.onTap, required this.onFlag, this.onImageError});

  final PhotoCategoryDef cat;
  final ShopPhoto? photo;
  final UploadItem? pending;
  final void Function(ShopPhoto? photo, UploadItem? pending) onTap;
  final void Function(ShopPhoto photo) onFlag;

  /// The picture failed to load (usually an expired signed link): the screen reads the shop again for fresh links.
  final VoidCallback? onImageError;

  @override
  Widget build(BuildContext context) {
    final p = photo;
    final u = pending;
    final has = p != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p?.needsRework == true ? AdinnColors.red : (has ? AdinnColors.success.withValues(alpha: 0.5) : AdinnColors.line), width: p?.needsRework == true ? 1.6 : 1),
      ),
      child: InkWell(
        onTap: () => onTap(p, u),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (u != null)
                    _LocalThumb(u)
                  else if (p?.displayUrl != null)
                    _NetImage(p!.displayUrl!, onError: onImageError)
                  else
                    Container(color: AdinnColors.canvas, child: Icon(cat.icon, size: 40, color: AdinnColors.muted)),
                  if (p != null && u == null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _Badge(
                        icon: p.locationUnverified ? Icons.wrong_location_outlined : Icons.location_on,
                        color: p.locationUnverified ? AdinnColors.warning : AdinnColors.success,
                      ),
                    ),
                  if (p != null && p.needsRework && u == null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: GestureDetector(onTap: () => onFlag(p), child: const _Badge(icon: Icons.flag, color: AdinnColors.red)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cat.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(_caption(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: _captionColor())),
                      ],
                    ),
                  ),
                  Icon(has && u == null ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: has && u == null ? AdinnColors.success : AdinnColors.line),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _caption() {
    final u = pending;
    if (u != null) {
      return switch (u.status) {
        UploadStatus.queued => 'Waiting to upload',
        UploadStatus.uploading => 'Uploading ${(u.progress * 100).round()}%',
        UploadStatus.failed => 'Upload failed. Tap',
      };
    }
    final p = photo;
    if (p == null) return 'Tap to capture';
    if (p.needsRework) return 'Rework required';
    if (p.locationUnverified) return 'Location unverified';
    return _reviewLabel(p.review.status);
  }

  Color _captionColor() {
    final u = pending;
    if (u != null) return u.status == UploadStatus.failed ? AdinnColors.red : AdinnColors.info;
    final p = photo;
    if (p == null) return AdinnColors.muted;
    if (p.needsRework) return AdinnColors.red;
    if (p.locationUnverified) return AdinnColors.warning;
    return AdinnColors.muted;
  }
}

/// "Additional photo requested": a reviewer asked for a new photo of a category (an ADDITIONAL_PHOTO item, or a REPLACE_PHOTO that
/// names a category but no photo). Shows their note and opens the same GPS-first capture for that category and board. Once a new
/// draft photo of the category exists the request is answered (the submit check agrees) and the card turns green.
class _RequestedCard extends StatelessWidget {
  const _RequestedCard({
    super.key,
    required this.req,
    required this.answer,
    required this.pending,
    required this.enabled,
    required this.onCapture,
    required this.onManageUpload,
    this.onImageError,
  });

  final RequestedPhoto req;
  final ShopPhoto? answer;
  final UploadItem? pending;
  final bool enabled;
  final void Function(ShopPhoto? answer) onCapture;
  final void Function(UploadItem upload) onManageUpload;
  final VoidCallback? onImageError;

  @override
  Widget build(BuildContext context) {
    final u = pending;
    final a = answer;
    final answered = a != null || u != null;
    final color = answered ? AdinnColors.success : AdinnColors.red;
    final status = u != null
        ? switch (u.status) {
            UploadStatus.queued => 'New photo saved on the phone. Waiting to upload.',
            UploadStatus.uploading => 'Uploading the new photo ${(u.progress * 100).round()}%',
            UploadStatus.failed => 'Upload failed: ${u.error ?? 'try again'}',
          }
        : (a != null ? 'New photo is ready. It goes for review when you submit.' : 'Tap Capture. Your location is read first, then the camera opens.');
    final failed = u?.status == UploadStatus.failed;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: failed ? AdinnColors.red : color.withValues(alpha: 0.6), width: 1.4)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(answered ? Icons.check_circle : Icons.flag, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Additional photo requested', style: TextStyle(fontWeight: FontWeight.w800, color: color))),
              TagChip(req.label, icon: Icons.photo_camera_outlined),
            ]),
            const SizedBox(height: 8),
            ReworkBox(note: req.note, fallback: 'The reviewer asked for another photo: ${req.label}.'),
            const SizedBox(height: 10),
            Row(children: [
              SizedBox(
                width: 56,
                height: 56,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: u != null
                      ? _LocalThumb(u)
                      : (a?.displayUrl != null
                          ? _NetImage(a!.displayUrl!, onError: onImageError)
                          : Container(color: AdinnColors.canvas, child: const Icon(Icons.add_a_photo_outlined, color: AdinnColors.muted))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(status, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: failed ? AdinnColors.red : (answered ? AdinnColors.muted : AdinnColors.ink)))),
            ]),
            if (enabled) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: u != null
                    ? OutlinedButton.icon(onPressed: () => onManageUpload(u), icon: const Icon(Icons.cloud_upload_outlined), label: Text(failed ? 'Retry or discard' : 'Cancel upload'))
                    : FilledButton.icon(
                        onPressed: () => onCapture(a),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(a != null ? 'Retake' : 'Capture'),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)]),
      child: Icon(icon, size: 16, color: color),
    );
  }
}

class _LocalThumb extends StatelessWidget {
  const _LocalThumb(this.u);
  final UploadItem u;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AppFileRow.image(null, u.path),
        Container(
          color: Colors.black38,
          alignment: Alignment.center,
          child: u.status == UploadStatus.failed
              ? const Icon(Icons.error_outline, color: Colors.white, size: 34)
              : SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(value: u.status == UploadStatus.uploading && u.progress > 0 ? u.progress : null, color: Colors.white, strokeWidth: 3),
                ),
        ),
      ],
    );
  }
}

class _NetImage extends StatelessWidget {
  const _NetImage(this.url, {this.fit = BoxFit.cover, this.onError});
  final String url;
  final BoxFit fit;

  /// Called (after the frame) when the picture cannot be loaded. A signed photo link runs out after about 10 minutes, so the
  /// usual cure is a fresh shop read, not a permanently broken picture.
  final VoidCallback? onError;

  @override
  Widget build(BuildContext context) {
    return appNetworkImage(
      url,
      fit: fit,
      loadingBuilder: (_, child, progress) => progress == null ? child : Container(color: AdinnColors.canvas, alignment: Alignment.center, child: const CircularProgressIndicator(strokeWidth: 2)),
      errorBuilder: (_, _, _) {
        if (onError != null) WidgetsBinding.instance.addPostFrameCallback((_) => onError!());
        return Container(color: AdinnColors.canvas, alignment: Alignment.center, child: const Icon(Icons.broken_image_outlined, color: AdinnColors.muted));
      },
    );
  }
}

class _GpsLine extends StatelessWidget {
  const _GpsLine(this.p);
  final ShopPhoto p;

  @override
  Widget build(BuildContext context) {
    if (!p.hasGps) {
      return const Text('No GPS location on this photo', style: TextStyle(color: AdinnColors.red, fontWeight: FontWeight.w700));
    }
    final acc = p.gpsAccuracy == null ? '' : '  (accuracy ${p.gpsAccuracy!.toStringAsFixed(0)} m)';
    return Text(
      '${p.locationUnverified ? 'Location unverified: ' : 'GPS: '}${p.lat!.toStringAsFixed(5)}, ${p.lng!.toStringAsFixed(5)}$acc',
      style: TextStyle(color: p.locationUnverified ? AdinnColors.warning : AdinnColors.success, fontWeight: FontWeight.w600),
    );
  }
}

/// "Files": photos still uploading and the stored photos in one list, with the filter chips
/// All / Pending / Approved / Rework Required / Previous Versions. A flagged row opens the rework sheet.
class _FilesSection extends StatefulWidget {
  const _FilesSection({required this.ctrl, required this.onOpenRework, required this.onRemoveDraft});

  final ShopDetailController ctrl;
  final void Function(ShopPhoto) onOpenRework;
  final void Function(ShopPhoto) onRemoveDraft;

  @override
  State<_FilesSection> createState() => _FilesSectionState();
}

class _FilesSectionState extends State<_FilesSection> {
  PhotoFilter _filter = PhotoFilter.all;

  ShopDetailController get ctrl => widget.ctrl;

  int _count(PhotoFilter f, ShopDetail d) {
    if (f == PhotoFilter.previous) return ctrl.previousPhotos.length;
    return d.photos.where((p) => p.displayUrl != null && f.matches(p)).length + (f.includesUploads ? ctrl.pending.length : 0);
  }

  @override
  Widget build(BuildContext context) {
    final d = ctrl.detail!;
    final pending = ctrl.pending;
    final previous = ctrl.previousPhotos;
    if (pending.isEmpty && d.photos.isEmpty && previous.isEmpty && d.version == 0) return const SizedBox.shrink();
    final live = [for (final p in d.photos) if (p.displayUrl != null && _filter.matches(p)) p];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        const Text('Files', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final f in PhotoFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${f.label} (${_count(f, d)})'),
                    selected: _filter == f,
                    selectedColor: AdinnColors.redLight,
                    labelStyle: TextStyle(fontWeight: FontWeight.w600, color: _filter == f ? AdinnColors.red : AdinnColors.ink),
                    side: BorderSide(color: _filter == f ? AdinnColors.red : AdinnColors.line),
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_filter == PhotoFilter.previous)
          ..._previousRows(previous)
        else ...[
          if (_filter.includesUploads)
            for (final u in pending)
              AppFileRow(
                key: ValueKey('up-${u.id}'),
                name: photoCategoryLabel(u.category),
                subtitle: u.replaces != null ? 'Replacement' : null,
                localPath: u.path,
                state: switch (u.status) {
                  UploadStatus.queued => AppFileState.waiting,
                  UploadStatus.uploading => AppFileState.uploading,
                  UploadStatus.failed => AppFileState.failed,
                },
                progress: u.progress,
                message: u.error,
                onCancel: () => ctrl.queue.cancel(u.id),
                onRetry: () => ctrl.queue.retry(u.id),
                onRemove: () => ctrl.queue.cancel(u.id),
              ),
          for (final p in live) _row(p),
          if (live.isEmpty && (!_filter.includesUploads || pending.isEmpty))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('No ${_filter.label.toLowerCase()} photos.', style: const TextStyle(color: AdinnColors.muted)),
            ),
        ],
      ],
    );
  }

  Widget _row(ShopPhoto p) {
    final hasNew = p.needsRework && (ctrl.draftReplacementOf(p) != null || ctrl.pendingReplacementOf(p) != null);
    final subtitle = [
      if (p.isDraft) 'Draft' else if (p.version != null) 'V${p.version}',
      if (p.replaces != null) 'Replacement',
    ].join(' | ');
    return AppFileRow(
      key: ValueKey('ph-${p.id}'),
      name: photoCategoryLabel(p.category),
      url: p.displayUrl,
      subtitle: subtitle.isEmpty ? null : subtitle,
      flagged: p.needsRework,
      badge: p.needsRework
          ? (hasNew ? const TagChip('New photo ready', icon: Icons.check_circle, color: AdinnColors.success) : const ReworkTag())
          : (p.isApproved ? const TagChip('Approved', icon: Icons.check_circle, color: AdinnColors.success) : null),
      onTap: p.needsRework ? () => widget.onOpenRework(p) : null,
      onRemove: ctrl.canEdit && p.isDraft ? () => widget.onRemoveDraft(p) : null,
    );
  }

  List<Widget> _previousRows(List<PreviousPhoto> previous) {
    if (ctrl.versionsLoading && previous.isEmpty) {
      return const [Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))];
    }
    if (ctrl.versionsError != null && previous.isEmpty) {
      return [
        Row(children: [
          Expanded(child: Text(ctrl.versionsError!, style: const TextStyle(color: AdinnColors.red))),
          TextButton.icon(onPressed: () => ctrl.loadVersions(force: true), icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ]),
      ];
    }
    if (previous.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('No earlier-version photos. Replaced photos appear here after the next version is submitted.', style: TextStyle(color: AdinnColors.muted)),
        ),
      ];
    }
    return [
      for (final pp in previous)
        AppFileRow(
          key: ValueKey('prev-${pp.photo.id}'),
          name: photoCategoryLabel(pp.photo.category),
          url: pp.photo.displayUrl,
          subtitle: '${pp.versionText} | ${pp.photo.supersededBy != null ? 'replaced' : pp.photo.removedAt != null ? 'removed' : 'earlier version'}',
        ),
    ];
  }

}
