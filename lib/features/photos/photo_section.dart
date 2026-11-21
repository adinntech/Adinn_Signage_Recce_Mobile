import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../data/services/location_service.dart';
import '../../state/app_controller.dart';
import '../annotation/annotation_editor_screen.dart';
import '../compare/comparison_screen.dart';
import '../location/gps_widgets.dart';
import '../review_comments/photo_comments_screen.dart';
import '../survey/markup_entry.dart';
import '../survey/site_markup_controller.dart';
import 'annotation_apply.dart';
import 'photo_workspace_screen.dart';
import 'site_photo_view.dart';

/// Capture, label, annotate and delete site photos of one board.
class PhotoSection extends StatefulWidget {
  const PhotoSection({
    super.key,
    required this.shopId,
    required this.board,
    required this.editable,
    this.onBoardSizeApplied,
  });

  final String shopId;
  final Board board;
  final bool editable;

  /// Called when the annotation editor pushed a measured size to the board.
  final VoidCallback? onBoardSizeApplied;

  @override
  State<PhotoSection> createState() => _PhotoSectionState();
}

class _PhotoSectionState extends State<PhotoSection> {
  bool _busy = false;

  Future<String?> _pickLabel({String? current}) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Which angle is this photo?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            for (final l in SignageCatalog.photoLabels)
              ListTile(
                leading: Icon(
                  l == current
                      ? Icons.radio_button_checked
                      : Icons.photo_outlined,
                  color: AdinnColors.red,
                ),
                title: Text(l),
                onTap: () => Navigator.pop(ctx, l),
              ),
          ],
        ),
      ),
    );
  }

  /// GPS fix for a photo geotag, or null (never throws, never blocks long).
  Future<GeoFix?> _tryFix(LocationService location) async {
    try {
      return await location.currentFix(timeout: const Duration(seconds: 12));
    } catch (_) {
      return null;
    }
  }

  Future<void> _capture(ImageSource source) async {
    final c = context.read<AppController>();
    final location = locationServiceOf(context);
    final media = c.media;
    if (media == null) {
      showSnack(context, 'Storage not available', error: true);
      return;
    }
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!mounted) return;
      if (!status.isGranted) {
        showSnack(
          context,
          status.isPermanentlyDenied
              ? 'Camera blocked. Enable it in app settings.'
              : 'Camera permission is needed to capture site photos',
          error: true,
        );
        if (status.isPermanentlyDenied) await openAppSettings();
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (picked == null) return;
      // Geotag camera shots: read GPS while the photo is being saved.
      // Gallery images are not tagged (we can't prove where they were taken).
      final geoFuture = source == ImageSource.camera
          ? _tryFix(location)
          : Future<GeoFix?>.value();
      final bytes = await picked.readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      final ext = picked.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final path = await media.newFilePath('photos', ext);
      await File(path).writeAsBytes(bytes, flush: true);
      final width = decoded.width;
      final height = decoded.height;
      decoded.dispose();
      if (!mounted) return;
      final label =
          await _pickLabel() ??
          SignageCatalog.photoLabels[min(
            widget.board.photos.length,
            SignageCatalog.photoLabels.length - 1,
          )];
      final geo = await geoFuture;
      final photo = SitePhoto(
        id: newId('ph'),
        path: path,
        label: label,
        capturedAt: DateTime.now(),
        width: width,
        height: height,
        geo: geo,
      );
      c.addPhoto(widget.shopId, widget.board.id, photo);
      if (source == ImageSource.camera && geo == null && mounted) {
        showSnack(
          context,
          'Photo saved without GPS tag (location unavailable)',
        );
      }
      // Straight into the photo preview section (editor / live / AR).
      if (mounted) _openWorkspace(photo);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save photo: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSample() async {
    final label = await _pickLabel();
    if (!mounted) return;
    context.read<AppController>().addPhoto(
      widget.shopId,
      widget.board.id,
      SitePhoto(
        id: newId('ph'),
        path: '${SitePhoto.demoPrefix}${Random().nextInt(6)}',
        label: label ?? 'Front view',
        capturedAt: DateTime.now(),
        width: 1200,
        height: 900,
      ),
    );
  }

  /// Photo preview section: Photo Editor / Live Preview / Camera AR tabs.
  Future<void> _openWorkspace(SitePhoto photo, {int tab = 0}) async {
    final b = widget.board;
    final before = (b.width, b.height, b.unit);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoWorkspaceScreen(
          shopId: widget.shopId,
          boardId: b.id,
          photoId: photo.id,
          initialTab: tab,
        ),
      ),
    );
    if (before != (b.width, b.height, b.unit)) {
      widget.onBoardSizeApplied?.call();
    }
  }

  /// Classic full-screen annotation editor.
  Future<void> _annotate(SitePhoto photo) async {
    final b = widget.board;
    final c0 = context.read<AppController>();
    final result = await Navigator.of(context).push<AnnotationEditorResult>(
      MaterialPageRoute(
        builder: (ctx) => AnnotationEditorScreen(
          photo: photo,
          boardName: b.name,
          defaultUnit: b.unit,
          units: unitOptionsFor(b),
          extraTools: siteMarkupTools(
            ctx,
            shopId: widget.shopId,
            boardId: b.id,
            photoId: photo.id,
          ),
          underlay: LiveMarkupUnderlay(
            controller: c0,
            shopId: widget.shopId,
            photo: photo,
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final c = context.read<AppController>();
    if (applyAnnotationResult(c, widget.shopId, b, photo.id, result)) {
      widget.onBoardSizeApplied?.call();
    }
    if (mounted) showSnack(context, 'Annotations saved');
  }

  void _view(SitePhoto photo) {
    final shopGeo = context.read<AppController>().shop(widget.shopId)?.geo;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerScreen(photo: photo, shopGeo: shopGeo),
      ),
    );
  }

  Future<void> _menu(SitePhoto photo) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.zoom_in),
              title: const Text('View full screen'),
              onTap: () => Navigator.pop(ctx, 'view'),
            ),
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('Live Preview (3D on photo)'),
              onTap: () => Navigator.pop(ctx, 'live'),
            ),
            ListTile(
              leading: const Icon(Icons.view_in_ar),
              title: const Text('Camera AR'),
              onTap: () => Navigator.pop(ctx, 'ar'),
            ),
            ListTile(
              key: const Key('photo_menu_compare'),
              leading: const Icon(Icons.compare),
              title: const Text('Before / Proposed comparison'),
              onTap: () => Navigator.pop(ctx, 'compare'),
            ),
            if (context
                .read<AppController>()
                .reviewComments(widget.shopId, photoId: photo.id)
                .isNotEmpty)
              ListTile(
                key: const Key('photo_menu_comments'),
                leading: const Icon(Icons.mode_comment_outlined),
                title: const Text('Reviewer comments on this photo'),
                onTap: () => Navigator.pop(ctx, 'comments'),
              ),
            ListTile(
              key: const Key('photo_menu_markup'),
              leading: const Icon(Icons.crop_rotate),
              title: Text(
                widget.editable
                    ? 'Site markup (perspective, markers, electrical, '
                          'obstructions)'
                    : 'View site markup',
              ),
              onTap: () => Navigator.pop(ctx, 'markup'),
            ),
            if (widget.editable) ...[
              ListTile(
                leading: const Icon(Icons.draw_outlined),
                title: const Text('Annotate / mark board'),
                onTap: () => Navigator.pop(ctx, 'annotate'),
              ),
              ListTile(
                leading: const Icon(Icons.label_outline),
                title: const Text('Change angle label'),
                onTap: () => Navigator.pop(ctx, 'label'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AdinnColors.red,
                ),
                title: const Text('Delete photo'),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final c = context.read<AppController>();
    switch (action) {
      case 'view':
        _view(photo);
      case 'live':
        await _openWorkspace(photo, tab: 1);
      case 'ar':
        await _openWorkspace(photo, tab: 2);
      case 'annotate':
        await _annotate(photo);
      case 'compare':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ComparisonScreen(
              shopId: widget.shopId,
              boardId: widget.board.id,
              photoId: photo.id,
            ),
          ),
        );
      case 'comments':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PhotoCommentsScreen(
              shopId: widget.shopId,
              boardId: widget.board.id,
              photoId: photo.id,
            ),
          ),
        );
      case 'markup':
        await openSiteMarkup(
          context,
          shopId: widget.shopId,
          boardId: widget.board.id,
          photoId: photo.id,
          tool: SiteMarkupTool.select,
        );
      case 'label':
        final l = await _pickLabel(current: photo.label);
        if (l != null) {
          photo.label = l;
          c.touchBoard(widget.shopId, widget.board);
        }
      case 'delete':
        final ok = await confirmDialog(
          context,
          title: 'Delete photo?',
          message: 'The photo and its markings will be removed.',
          confirmText: 'Delete',
          destructive: true,
        );
        if (ok) await c.removePhoto(widget.shopId, widget.board.id, photo.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.board.photos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.editable) ...[
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('capture_camera'),
                  onPressed: _busy ? null : () => _capture(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _capture(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('add_sample_photo'),
              onPressed: _busy ? null : _addSample,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Add sample photo (demo / no camera)'),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 4),
        ],
        if (photos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No photos yet. Capture front, left and right angles.',
              style: TextStyle(color: AdinnColors.muted),
            ),
          ),
        if (photos.isNotEmpty)
          LayoutBuilder(
            builder: (context, box) {
              final cols = box.maxWidth > 520 ? 3 : 2;
              return GridView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: photos.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.92,
                ),
                itemBuilder: (_, i) {
                  final p = photos[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => widget.editable ? _openWorkspace(p) : _view(p),
                    onLongPress: () => _menu(p),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Center(
                            child: AnnotatedPhotoView(p, cacheWidth: 500),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (p.geo != null)
                              const Padding(
                                padding: EdgeInsets.only(right: 2),
                                child: Icon(
                                  Icons.location_on,
                                  size: 14,
                                  color: AdinnColors.success,
                                ),
                              ),
                            if (p.unitIds.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: Text(
                                  '${p.unitIds.length}u',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AdinnColors.info,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            if (p.annotations.isNotEmpty)
                              Icon(
                                Icons.draw,
                                size: 14,
                                color: AdinnColors.red.withValues(alpha: 0.8),
                              ),
                            InkWell(
                              onTap: () => _menu(p),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(Icons.more_vert, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        if (photos.isNotEmpty && widget.editable)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Tap a photo to annotate it, preview the 3D signage on it (Live Preview) or open Camera AR.',
              style: TextStyle(fontSize: 12, color: AdinnColors.muted),
            ),
          ),
      ],
    );
  }
}

/// Full-screen, zoomable, read-only photo with annotations.
class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.photo, this.shopGeo});

  final SitePhoto photo;

  /// When given, the distance between photo and shop GPS is shown.
  final GeoFix? shopGeo;

  @override
  Widget build(BuildContext context) {
    final g = photo.geo;
    final distance = g != null && shopGeo != null
        ? ' • ${fmtDistance(g.distanceTo(shopGeo!))} from shop'
        : '';
    final gpsLine = g == null
        ? 'No GPS tag'
        : 'GPS ${g.coordinates} (±${g.accuracyM.round()} m)$distance';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(photo.label, style: const TextStyle(color: Colors.white)),
      ),
      body: InteractiveViewer(
        maxScale: 6,
        child: Center(child: AnnotatedPhotoView(photo, borderRadius: 0)),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Captured ${fmtDateTime(photo.capturedAt)} • '
            '${photo.width}×${photo.height}px • '
            '${photo.annotations.length} marking(s)\n$gpsLine',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ),
    );
  }
}
