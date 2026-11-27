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
import '../../l10n/l10n.dart';
import '../annotation/photo_tour.dart';
import '../compare/comparison_screen.dart';
import '../location/gps_widgets.dart';
import '../review_comments/photo_comments_screen.dart';
import '../survey/markup_entry.dart';
import '../survey/site_markup_controller.dart';
import 'annotation_apply.dart';
import 'photo_workspace_screen.dart';
import 'site_photo_view.dart';
import '../../core/widgets/adinn_app_bar.dart';

/// Capture, label, annotate and delete site photos of one board.
class PhotoSection extends StatefulWidget {
  const PhotoSection({
    super.key,
    required this.shopId,
    required this.board,
    required this.editable,
    this.onBoardSizeApplied,
    this.unitId,
  });

  /// The physical board currently selected in the editor. New photos, the
  /// annotation editor and the tour all belong to THIS board.
  final String? unitId;

  final String shopId;
  final Board board;
  final bool editable;

  /// Called when the annotation editor pushed a measured size to the board.
  final VoidCallback? onBoardSizeApplied;

  /// Test fixture for the camera / gallery: returns the picked photo's
  /// pixels (path / size) without the camera plugin, permission prompt or
  /// file copy. Everything after the pick (angle sheet, evidence rules, tour,
  /// editor) is the real flow. Null in production.
  static Future<SitePhoto?> Function(ImageSource source)? testCapture;

  @override
  State<PhotoSection> createState() => _PhotoSectionState();
}

class _PhotoSectionState extends State<PhotoSection> {
  bool _busy = false;

  /// Selected physical board (never silently the first one).
  SignageUnit? get _unit =>
      widget.board.unitById(widget.unitId) ??
      widget.board.activeUnits.firstOrNull;

  /// Photos of a multi-board group are linked to the board they were taken
  /// for (a single-board group needs no explicit link).
  List<String> get _newPhotoUnits {
    final u = _unit;
    return u != null && widget.board.activeUnits.length > 1 ? [u.id] : const [];
  }

  // Signage-marking tour of the photo just captured.
  final _tileKeys = <String, GlobalKey>{};
  PhotoTour? _tour;
  String? _tourPhotoId;
  OverlayEntry? _tourEntry;

  @override
  void dispose() {
    _tourEntry?.remove();
    super.dispose();
  }

  void _endTileTour() {
    _tourEntry?.remove();
    _tourEntry = null;
    _tourPhotoId = null;
  }

  /// Step 0: highlight the captured photo's tile; tapping it (or Open) opens
  /// the Photo Editor with the rest of the tour.
  Future<void> _startTileTour(SitePhoto photo) async {
    final b = widget.board;
    final unit = _unit;
    if (unit == null) return;
    final tour = PhotoTour.forNewPhoto(b, unit, photo);
    _endTileTour();
    _tour = tour;
    _tourPhotoId = photo.id;
    // Let the new tile build, bring it into view, then highlight it.
    await WidgetsBinding.instance.endOfFrame;
    final tile = _tileKeys[photo.id]?.currentContext;
    if (tile != null && mounted) {
      await Scrollable.ensureVisible(tile, alignment: 0.3);
      await WidgetsBinding.instance.endOfFrame;
    }
    final key = _tileKeys[photo.id];
    if (!mounted || key == null || _tourPhotoId != photo.id) return;
    _tourEntry = OverlayEntry(
      builder: (_) => TileTourOverlay(
        tour: tour,
        target: key,
        onOpen: () => _openFromTour(photo),
        onSkip: () {
          tour.skip();
          _endTileTour();
        },
      ),
    );
    Overlay.of(context).insert(_tourEntry!);
  }

  void _openFromTour(SitePhoto photo) {
    final tour = _tour;
    _endTileTour();
    tour?.advanceTo(1);
    _openWorkspace(photo, tour: tour);
  }

  Future<String?> _pickLabel({String? current}) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      // Seven angles: scrollable so small phones never overflow.
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  ctx.ui('Which angle is this photo?'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
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
                  title: Text(ctx.ui(l)),
                  onTap: () => Navigator.pop(ctx, l),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Every media type asks "Which angle is this photo?" after capture; the
  /// angle is the photo's label and sets Live Preview's starting turn.
  Future<String> _labelForNewPhoto() async {
    return await _pickLabel() ??
        SignageCatalog.photoLabels[min(
          widget.board.photos.length,
          SignageCatalog.photoLabels.length - 1,
        )];
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
    final fixture = PhotoSection.testCapture;
    if (fixture != null) {
      final base = await fixture(source);
      if (base == null || !mounted) return;
      final label = await _labelForNewPhoto();
      if (!mounted) return;
      final photo = SitePhoto(
        id: newId('ph'),
        path: base.path,
        label: label,
        capturedAt: DateTime.now(),
        width: base.width,
        height: base.height,
        geo: source == ImageSource.camera ? base.geo : null,
        unitIds: _newPhotoUnits,
      );
      c.addPhoto(widget.shopId, widget.board.id, photo);
      await _startTileTour(photo);
      return;
    }
    final location = locationServiceOf(context);
    final media = c.media;
    if (media == null) {
      showSnack(context, context.ui('Storage not available'), error: true);
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
      final label = await _labelForNewPhoto();
      final geo = await geoFuture;
      final photo = SitePhoto(
        id: newId('ph'),
        path: path,
        label: label,
        capturedAt: DateTime.now(),
        width: width,
        height: height,
        geo: geo,
        unitIds: _newPhotoUnits,
      );
      c.addPhoto(widget.shopId, widget.board.id, photo);
      if (source == ImageSource.camera && geo == null && mounted) {
        showSnack(
          context,
          context.ui('Photo saved without GPS tag (location unavailable)'),
        );
      }
      // Straight into the photo preview section (editor / live / AR), with
      // the signage-marking tour. Skip eligibility comes from the SAVED
      // evidence of this physical board, not from a "seen" flag.
      if (mounted) await _startTileTour(photo);
    } catch (e) {
      if (mounted)
        showSnack(
          context,
          context.uf('Could not save photo: {0}', [e]),
          error: true,
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Photo preview section: Photo Editor / Live Preview / Camera AR tabs.
  Future<void> _openWorkspace(
    SitePhoto photo, {
    int tab = 0,
    PhotoTour? tour,
  }) async {
    final b = widget.board;
    final before = (b.width, b.height, b.unit);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoWorkspaceScreen(
          shopId: widget.shopId,
          boardId: b.id,
          photoId: photo.id,
          initialUnitId: _unit?.id,
          initialTab: tab,
          tour: tour,
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
    if (mounted) showSnack(context, context.ui('Annotations saved'));
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.zoom_in),
                title: Text(context.ui('View full screen')),
                onTap: () => Navigator.pop(ctx, 'view'),
              ),
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: Text(context.ui('Live Preview (3D on photo)')),
                onTap: () => Navigator.pop(ctx, 'live'),
              ),
              ListTile(
                leading: const Icon(Icons.view_in_ar),
                title: Text(context.ui('Camera AR')),
                onTap: () => Navigator.pop(ctx, 'ar'),
              ),
              ListTile(
                key: const Key('photo_menu_compare'),
                leading: const Icon(Icons.compare),
                title: Text(context.ui('Before / Proposed comparison')),
                onTap: () => Navigator.pop(ctx, 'compare'),
              ),
              if (context
                  .read<AppController>()
                  .reviewComments(widget.shopId, photoId: photo.id)
                  .isNotEmpty)
                ListTile(
                  key: const Key('photo_menu_comments'),
                  leading: const Icon(Icons.mode_comment_outlined),
                  title: Text(context.ui('Reviewer comments on this photo')),
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
                  title: Text(context.ui('Annotate / mark board')),
                  onTap: () => Navigator.pop(ctx, 'annotate'),
                ),
                ListTile(
                  leading: const Icon(Icons.label_outline),
                  title: Text(context.ui('Change angle label')),
                  onTap: () => Navigator.pop(ctx, 'label'),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AdinnColors.red,
                  ),
                  title: Text(context.ui('Delete photo')),
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
              ],
            ],
          ),
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
                  label: Text(context.ui('Camera')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _capture(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(context.ui('Gallery')),
                ),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 4),
        ],
        if (photos.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              context.ui(
                'No photos yet. Capture front, left and right angles.',
              ),
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
                  return KeyedSubtree(
                    key: _tileKeys.putIfAbsent(p.id, GlobalKey.new),
                    child: InkWell(
                      key: Key('photo_tile_${p.id}'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => !widget.editable
                          ? _view(p)
                          : _tourPhotoId == p.id
                          ? _openFromTour(p)
                          : _openWorkspace(p),
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
                    ),
                  );
                },
              );
            },
          ),
        if (photos.isNotEmpty && widget.editable)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              context.ui(
                'Tap a photo to annotate it, preview the 3D signage on it (Live Preview) or open Camera AR.',
              ),
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
      appBar: AdinnAppBar(
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
