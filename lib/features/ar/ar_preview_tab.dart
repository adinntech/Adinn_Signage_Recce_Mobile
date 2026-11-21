import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../board/board_editor_screen.dart';
import '../preview_live/capture_utils.dart';
import '../preview_live/live_preview_tab.dart' show PngWriter;
import '../preview_live/preview_gallery.dart';
import 'ar_editor_panels.dart';
import 'ar_model_builder.dart';
import 'ar_scene_controller.dart';
import 'ar_scene_engine.dart';
import 'ar_scene_items.dart';
import 'ar_session_controller.dart';
import 'native_ar_platform.dart';

/// AR engine for this device: ARCore on Android, otherwise unavailable.
ArPlatform defaultArPlatform() {
  if (!kIsWeb && Platform.isAndroid) return NativeArPlatform();
  return const UnavailableArPlatform();
}

/// Camera AR placement editor: checks ARCore support / services / camera
/// permission, runs a real ARCore session (native GL view) and lets the user
/// insert the shop's configured signage items as 3D models, select / move /
/// rotate / scale / duplicate / hide / lock them, undo / redo, save the
/// layout and capture the rendered scene (camera + models).
class ArPreviewTab extends StatefulWidget {
  const ArPreviewTab({
    super.key,
    required this.shopId,
    required this.boardId,
    required this.unitId,
    this.photoId,
    this.platform,
    this.editable = true,
    this.onOpenLivePreview,
    this.writer,
  });

  final String shopId;
  final String boardId;
  final String unitId;
  final String? photoId;
  final ArPlatform? platform;
  final bool editable;
  final VoidCallback? onOpenLivePreview;
  final PngWriter? writer;

  @override
  State<ArPreviewTab> createState() => _ArPreviewTabState();
}

class _ArPreviewTabState extends State<ArPreviewTab> {
  ArSessionController? _ar;
  ArSceneController? _scene;
  AppController? _app;
  AppLifecycleListener? _lifecycle;
  String _brand = 'ADINN';

  // Gesture state.
  double _lastScale = 1;
  double _lastRotation = 0;
  DateTime _lastMove = DateTime.fromMillisecondsSinceEpoch(0);
  bool _gestureHinted = false;
  bool _saving = false;
  PreviewCapture? _lastSaved;
  Timer? _savedTimer;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
    final shop = app.shop(widget.shopId);
    final b = app.board(widget.shopId, widget.boardId);
    final u = b?.unitById(widget.unitId) ?? b?.units.firstOrNull;
    if (shop == null || b == null || u == null) return;
    _app = app;
    _brand = (app.project(shop.projectId)?.name ?? 'Adinn').toUpperCase();
    final geometry = buildArModel(b, u, brand: _brand);
    // Restore orientation / size from the latest AR capture of this unit
    // (world anchors are not persisted: the model is placed again).
    final last =
        b.previews
            .where((c) => c.kind == CaptureKind.ar && c.unitId == u.id)
            .toList()
          ..sort((a, c) => a.createdAt.compareTo(c.createdAt));
    final restored = last.isEmpty
        ? null
        : ArObjectTransform.fromMap(
            last.last.arTransform,
          ).copyWith(x: 0, y: 0, z: 0);
    final platform = widget.platform ?? defaultArPlatform();
    final ar = ArSessionController(
      platform: platform,
      initialTransform: restored?.toLegacy(),
      model: ArModelSpec(
        mediaCode: geometry.mediaCode,
        installationCode: geometry.installationCode,
        widthFt: geometry.widthM / kFeetToMetres,
        heightFt: geometry.heightM / kFeetToMetres,
        label:
            '${SignageCatalog.media(b.mediaCode)?.shortName ?? b.name} '
            '${b.unitLabel(u)}',
        doubleSided: geometry.doubleSided,
        unitId: u.id,
        geometry: geometry,
      ),
    );
    final items = arSceneItemsForShop(shop, brand: _brand);
    final initial =
        items.where((i) => i.unitId == u.id).firstOrNull ??
        arSceneItemFor(b, u, brand: _brand);
    final scene = ArSceneController(
      engine: sceneEngineFor(platform, sessionModelKey: u.id),
      session: ar,
      initialItem: initial,
      initialTransform: restored ?? const ArObjectTransform(),
    );
    scene.setItems(items.isEmpty ? [initial] : items);
    _ar = ar..addListener(_changed);
    _scene = scene..addListener(_changed);
    app.addListener(_onAppChanged);
    _lifecycle = AppLifecycleListener(onResume: () => _ar?.onAppResumed());
    ar.open();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Recce data changed (e.g. dimensions edited): refresh insertable items
  /// and regenerate affected models.
  void _onAppChanged() {
    final shop = _app?.shop(widget.shopId);
    final scene = _scene;
    if (shop == null || scene == null || !mounted) return;
    scene.setItems(arSceneItemsForShop(shop, brand: _brand));
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    _lifecycle?.dispose();
    _app?.removeListener(_onAppChanged);
    _scene?.removeListener(_changed);
    _scene?.dispose();
    _ar?.removeListener(_changed);
    _ar?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Gestures on the camera view (one active tool at a time)
  // ---------------------------------------------------------------------------

  Offset _norm(Offset local, Size size) => Offset(
    (local.dx / size.width).clamp(0.0, 1.0),
    (local.dy / size.height).clamp(0.0, 1.0),
  );

  void _onTap(TapUpDetails d, Size size) =>
      _scene!.handleTap(_norm(d.localPosition, size));

  void _onScaleStart(ScaleStartDetails d) {
    _lastScale = 1;
    _lastRotation = 0;
    _gestureHinted = false;
  }

  bool _gestureAllowed() {
    final scene = _scene!;
    final reason = scene.editBlockedReason;
    if (reason == null) return true;
    if (!_gestureHinted && scene.selected != null) {
      _gestureHinted = true;
      showSnack(context, reason, error: true);
    }
    return false;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    final scene = _scene!;
    if (scene.awaitingPlacement || scene.selected == null) return;
    if (d.pointerCount >= 2) {
      final ds = d.scale / (_lastScale == 0 ? 1 : _lastScale);
      _lastScale = d.scale;
      final dr = d.rotation - _lastRotation;
      _lastRotation = d.rotation;
      switch (scene.tool) {
        case ArTool.scale:
          if (!_gestureAllowed()) return;
          scene.beginGesture();
          if ((ds - 1).abs() > 0.002) scene.scaleBy(ds);
        case ArTool.rotate:
          if (!_gestureAllowed()) return;
          scene.beginGesture();
          if (dr.abs() > 0.002) scene.rotateByRadians(-dr);
        default:
          if (!_gestureHinted) {
            _gestureHinted = true;
            showSnack(
              context,
              'Choose Scale to pinch-resize or Rotate to twist the model.',
            );
          }
      }
      return;
    }
    switch (scene.tool) {
      case ArTool.move:
        if (!scene.moving) {
          if (!_gestureAllowed() || !scene.beginDrag()) return;
        }
        // Drag = re-anchor under the finger (AR hit test), throttled.
        final now = DateTime.now();
        if (now.difference(_lastMove).inMilliseconds < 90) return;
        _lastMove = now;
        scene.dragTo(_norm(d.localFocalPoint, size));
      case ArTool.rotate:
        if (!_gestureAllowed()) return;
        scene.beginGesture();
        final sign = scene.selected?.rotationAxis == ArRotationAxis.roll
            ? -1
            : 1;
        scene.rotateByRadians(sign * d.focalPointDelta.dx * 0.012);
      case ArTool.scale:
        if (!_gestureAllowed()) return;
        scene.beginGesture();
        scene.scaleBy(math.exp(-d.focalPointDelta.dy * 0.004));
      default:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final scene = _scene!;
    if (scene.moving) {
      scene.endDrag();
    } else {
      scene.endGesture(scene.tool.label);
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _insert() async {
    final scene = _scene!;
    final shop = context.read<AppController>().shop(widget.shopId);
    if (scene.tool != ArTool.none) scene.setTool(scene.tool);
    final choice = await showArInsertSheet(
      context,
      scene,
      shopName: shop?.name ?? '',
    );
    if (choice == null || !mounted) return;
    if (choice.selectId != null) {
      scene.select(choice.selectId);
      return;
    }
    scene.armInsert(choice.item, previewDuplicate: choice.previewDuplicate);
  }

  Future<void> _delete() async {
    final scene = _scene!;
    final p = scene.selected;
    if (p == null) {
      showSnack(context, 'Select a model to delete.', error: true);
      return;
    }
    await scene.remove(p.placementId);
  }

  Future<void> _capture() async {
    final ar = _ar!;
    final scene = _scene!;
    final app = context.read<AppController>();
    final shop = app.shop(widget.shopId);
    if (shop == null) return;
    final shown = scene.visibleAnchored;
    if (shown.isEmpty) {
      showSnack(
        context,
        'Place a signage model before capturing.',
        error: true,
      );
      return;
    }
    final sel = scene.selected;
    final primary = sel != null && shown.contains(sel) ? sel : shown.first;
    final b =
        app.board(shop.id, primary.groupId) ??
        app.board(widget.shopId, widget.boardId);
    if (b == null) return;
    final media = app.media;
    final PngWriter? writer =
        widget.writer ??
        (media == null ? null : (png, folder) => writePng(media, png, folder));
    if (writer == null) {
      showSnack(context, 'Storage not available', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await ar.capture();
      if (result == null) {
        if (mounted) {
          showSnack(context, ar.error ?? 'Capture failed', error: true);
        }
        return;
      }
      final path = await writer(result.png, 'ar');
      final capture = PreviewCapture(
        id: newId('ar'),
        kind: CaptureKind.ar,
        projectId: shop.projectId,
        taskId: shop.taskId,
        shopId: shop.id,
        groupId: b.id,
        unitId: primary.unitId,
        photoId: widget.photoId,
        path: path,
        createdAt: result.capturedAt,
        arTransform: primary.transform.toMap(),
        info: {
          'mediaCode': b.mediaCode ?? '',
          'installationCode': primary.installationCode,
          'surface': primary.surface ?? '',
          'arEngine': ar.platform.engineName,
          'arSupport': ar.support.name,
          'scaleAdjusted': '${primary.transform.scaleAdjusted}',
          'objectCount': '${shown.length}',
          if (scene.layoutName != null) 'layoutName': scene.layoutName!,
        },
        layoutId: scene.layoutId,
        visibleUnitIds: shown.map((p) => p.unitId).toSet().toList(),
        placementIds: shown.map((p) => p.placementId).toList(),
      );
      app.addPreview(shop.id, b.id, capture);
      if (!mounted) return;
      // Inline banner on the camera view (a SnackBar would cover the
      // capture button and block "capture another").
      _savedTimer?.cancel();
      setState(() => _lastSaved = capture);
      _savedTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _lastSaved = null);
      });
    } catch (e) {
      // Existing recce data is untouched on failure.
      if (mounted) {
        showSnack(context, 'Could not save AR preview: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveLayout() async {
    final scene = _scene!;
    final app = context.read<AppController>();
    final shop = app.shop(widget.shopId);
    if (shop == null) return;
    if (scene.placements.isEmpty) {
      showSnack(context, 'Insert at least one model before saving.');
      return;
    }
    final existing = scene.layoutId == null
        ? null
        : app.arLayout(scene.layoutId!);
    final count = app.arLayoutsForShop(shop.id).length;
    final answer = await showDialog<(String, bool)>(
      context: context,
      builder: (ctx) => _LayoutNameDialog(
        initialName: existing?.name ?? 'AR Layout ${count + 1}',
        objectCount: scene.placements.length,
        updating: existing != null,
      ),
    );
    if (answer == null || !mounted) return;
    final (text, asNew) = answer;
    final replace = existing != null && !asNew;
    final layout = scene.toLayout(
      id: replace ? existing.id : newId('arl'),
      name: text.isEmpty ? 'AR Layout ${count + 1}' : text,
      shop: shop,
      createdAt: replace ? existing.createdAt : null,
    );
    app.saveArLayout(layout);
    scene.markSaved(layout);
    // Confirmation shown as a camera banner (a SnackBar would cover the
    // capture button).
  }

  Future<void> _openLayouts() async {
    final scene = _scene!;
    final app = context.read<AppController>();
    final chosen = await showArLayoutsSheet(
      context,
      layouts: app.arLayoutsForShop(widget.shopId),
      editable: widget.editable,
      currentId: scene.layoutId,
      onDelete: (l) => app.deleteArLayout(l.id),
    );
    if (chosen == null || !mounted) return;
    if (scene.placements.isNotEmpty) {
      final ok = await confirmDialog(
        context,
        title: 'Open “${chosen.name}”?',
        message:
            'The models currently in the AR scene are replaced. Unsaved '
            'changes are lost.',
        confirmText: 'Open',
      );
      if (!ok || !mounted) return;
    }
    final r = await scene.loadLayout(chosen);
    if (!mounted || r.missing.isEmpty) return;
    showSnack(
      context,
      '${r.missing.length} object(s) skipped: their signage item no longer '
      'exists.',
      error: true,
    );
  }

  Future<void> _editDimensions(ArPlacement p) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BoardEditorScreen(
          shopId: widget.shopId,
          boardId: p.groupId,
          initialStep: BoardEditorScreen.measurementsStep,
        ),
      ),
    );
    // Models are regenerated through _onAppChanged when sizes changed.
    _onAppChanged();
  }

  void _openGallery(Board b, String unitId) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AR Previews',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 8),
              PreviewGallery(
                board: b,
                shopId: widget.shopId,
                unitId: unitId,
                kinds: const {CaptureKind.ar},
                editable: widget.editable,
                emptyText: 'No AR captures for this item yet.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final b = app.board(widget.shopId, widget.boardId);
    final ar = _ar;
    final scene = _scene;
    if (b == null || ar == null || scene == null) {
      return const EmptyState(icon: Icons.search_off, title: 'Item not found');
    }
    final running =
        ar.phase == ArPhase.starting ||
        ar.phase == ArPhase.scanning ||
        ar.phase == ArPhase.placed ||
        ar.phase == ArPhase.capturing;
    if (running) return _session(app, ar, scene);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _status(ar)),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AdinnColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'AR Previews',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              PreviewGallery(
                board: b,
                shopId: widget.shopId,
                unitId: widget.unitId,
                kinds: const {CaptureKind.ar},
                editable: widget.editable,
                emptyText: 'No AR captures for this item yet.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _centered(List<Widget> children) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );

  Widget _liveButton() => TextButton.icon(
    key: const ValueKey('ar_open_live_secondary'),
    onPressed: widget.onOpenLivePreview,
    icon: const Icon(Icons.layers_outlined),
    label: const Text('Open Live Preview'),
  );

  Widget _status(ArSessionController ar) {
    switch (ar.phase) {
      case ArPhase.unsupported:
        return _centered([
          const Icon(
            Icons.view_in_ar_outlined,
            size: 56,
            color: AdinnColors.muted,
          ),
          const SizedBox(height: 12),
          const Text(
            'Camera AR is not supported on this device.',
            key: ValueKey('ar-unsupported'),
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'This phone cannot run ARCore. Use Live Preview to place the 3D '
            'signage on a site photo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AdinnColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('ar_open_live'),
            onPressed: widget.onOpenLivePreview,
            icon: const Icon(Icons.layers_outlined),
            label: const Text('Open Live Preview'),
          ),
        ]);
      case ArPhase.servicesMissing:
        return _centered([
          const Icon(
            Icons.extension_outlined,
            size: 52,
            color: AdinnColors.red,
          ),
          const SizedBox(height: 10),
          Text(
            ar.error ?? 'Google Play Services for AR is required.',
            key: const ValueKey('ar-services-missing'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            ar.installRequested
                ? 'Finish the installation in the Play Store, then come back '
                      'to this screen.'
                : 'It is a free Google app that powers Camera AR.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AdinnColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('ar_install'),
            onPressed: ar.installServices,
            icon: const Icon(Icons.download),
            label: Text(
              ar.errorCode == 'apk_too_old'
                  ? 'Update Google Play Services for AR'
                  : 'Install Google Play Services for AR',
            ),
          ),
          TextButton(onPressed: ar.open, child: const Text('Check again')),
          _liveButton(),
        ]);
      case ArPhase.permissionDenied:
        return _centered([
          const Icon(Icons.no_photography_outlined, size: 48),
          const SizedBox(height: 10),
          Text(
            ar.error ?? 'Camera permission denied',
            key: const ValueKey('ar-permission'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Allow the Camera permission to use Camera AR.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AdinnColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: ar.open, child: const Text('Try again')),
          TextButton(
            onPressed: openAppSettings,
            child: const Text('Open app settings'),
          ),
          _liveButton(),
        ]);
      case ArPhase.error:
        return _centered([
          const Icon(Icons.error_outline, size: 48, color: AdinnColors.red),
          const SizedBox(height: 10),
          Text(
            ar.error ?? 'AR error',
            key: const ValueKey('ar-error'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const ValueKey('ar_retry'),
            onPressed: ar.open,
            child: const Text('Retry'),
          ),
          _liveButton(),
        ]);
      default:
        return _centered(const [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Checking AR support…'),
        ]);
    }
  }

  Widget _banner(
    String text, {
    Key? key,
    Color color = Colors.black54,
    List<Widget> actions = const [],
  }) => Padding(
    padding: const EdgeInsets.only(top: 6, right: 52),
    child: Container(
      key: key,
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        10,
        actions.isEmpty ? 8 : 2,
        4,
        actions.isEmpty ? 8 : 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ),
          ...actions,
        ],
      ),
    ),
  );

  Widget _bannerButton(String label, VoidCallback? onPressed, {Key? key}) =>
      TextButton(
        key: key,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
        child: Text(label),
      );

  Color _statusColor(ArSceneStatus s) => switch (s) {
    ArSceneStatus.trackingLost => AdinnColors.red,
    ArSceneStatus.readyToPlace => AdinnColors.success,
    ArSceneStatus.modelSelected => AdinnColors.info,
    ArSceneStatus.modelMoving => AdinnColors.purple,
    ArSceneStatus.scanning => AdinnColors.warning,
    ArSceneStatus.idle => Colors.black54,
  };

  /// Top strip: tracking status, current item, undo / redo, objects, save,
  /// more.
  Widget _topStrip(
    AppController app,
    ArSessionController ar,
    ArSceneController scene,
  ) {
    final status = scene.status;
    final sel = scene.selected;
    final current = sel != null
        ? '${sel.displayName} • ${sel.sizeText}'
        : (scene.armedItem != null
              ? 'Placing: ${scene.armedItem!.label}'
              : 'No model selected');
    final b = app.board(widget.shopId, sel?.groupId ?? widget.boardId);
    const iconColor = Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            key: const ValueKey('ar_status'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor(status),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              current,
              key: const ValueKey('ar_current_item'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11.5),
            ),
          ),
          IconButton(
            key: const ValueKey('ar_save_layout'),
            tooltip: widget.editable
                ? 'Save AR Layout'
                : 'Read-only recce: layouts cannot be saved',
            visualDensity: VisualDensity.compact,
            color: iconColor,
            disabledColor: Colors.white38,
            onPressed: widget.editable && scene.placements.isNotEmpty
                ? _saveLayout
                : null,
            icon: const Icon(Icons.save_outlined, size: 20),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('ar_more'),
            iconColor: iconColor,
            tooltip: 'More',
            onSelected: (v) {
              switch (v) {
                case 'layouts':
                  _openLayouts();
                case 'planes':
                  ar.setPlanesVisible(!ar.planesVisible);
                case 'manual':
                  ar.setManualPlacement(!ar.manualPlacement);
                case 'gallery':
                  if (b != null) {
                    _openGallery(b, sel?.unitId ?? widget.unitId);
                  }
                case 'live':
                  widget.onOpenLivePreview?.call();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                key: ValueKey('ar_layouts'),
                value: 'layouts',
                child: Text('Saved AR Layouts'),
              ),
              CheckedPopupMenuItem(
                key: const ValueKey('ar_planes'),
                value: 'planes',
                checked: ar.planesVisible,
                child: const Text('Surface indicators'),
              ),
              CheckedPopupMenuItem(
                key: const ValueKey('ar_manual'),
                value: 'manual',
                checked: ar.manualPlacement,
                child: const Text('Place without a detected surface'),
              ),
              const PopupMenuItem(
                key: ValueKey('ar_gallery'),
                value: 'gallery',
                child: Text('AR Previews (captures)'),
              ),
              if (widget.onOpenLivePreview != null)
                const PopupMenuItem(
                  value: 'live',
                  child: Text('Open Live Preview (photo)'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Undo / redo / objects: small floating buttons at the bottom-right of
  /// the camera view (keeps the top strip readable on narrow phones).
  Widget _sideButtons(ArSceneController scene) {
    Widget round(Widget child) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: child,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        round(
          IconButton(
            key: const ValueKey('ar_objects'),
            tooltip: 'Objects',
            color: Colors.white,
            onPressed: () => showArObjectsSheet(context, scene),
            icon: Badge(
              isLabelVisible: scene.placements.isNotEmpty,
              label: Text('${scene.placements.length}'),
              child: const Icon(Icons.layers_outlined, size: 22),
            ),
          ),
        ),
        round(
          IconButton(
            key: const ValueKey('ar_undo'),
            tooltip: scene.undoLabel == null
                ? 'Undo'
                : 'Undo ${scene.undoLabel}',
            color: Colors.white,
            disabledColor: Colors.white38,
            onPressed: scene.canUndo ? scene.undo : null,
            icon: const Icon(Icons.undo, size: 22),
          ),
        ),
        round(
          IconButton(
            key: const ValueKey('ar_redo'),
            tooltip: scene.redoLabel == null
                ? 'Redo'
                : 'Redo ${scene.redoLabel}',
            color: Colors.white,
            disabledColor: Colors.white38,
            onPressed: scene.canRedo ? scene.redo : null,
            icon: const Icon(Icons.redo, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _session(
    AppController app,
    ArSessionController ar,
    ArSceneController scene,
  ) {
    final guidance = scene.guidance;
    final sel = scene.selected;
    final failure = scene.lastPlaceFailure;
    final placingItem = scene.armedItem;
    final placingWall =
        placingItem?.preferVertical ?? scene.reanchorTarget?.preferVertical;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final size = Size(box.maxWidth, box.maxHeight);
              return Stack(
                fit: StackFit.expand,
                children: [
                  ar.platform.buildView(context),
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey('ar-gesture-layer'),
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (d) => _onTap(d, size),
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: (d) => _onScaleUpdate(d, size),
                      onScaleEnd: _onScaleEnd,
                    ),
                  ),
                  if (scene.awaitingPlacement)
                    const IgnorePointer(
                      child: Center(
                        child: Icon(
                          Icons.add,
                          key: ValueKey('ar_crosshair'),
                          color: Colors.white70,
                          size: 34,
                        ),
                      ),
                    ),
                  if (ar.phase == ArPhase.starting)
                    const ColoredBox(
                      color: Colors.black54,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 10),
                            Text(
                              'Starting camera AR…',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    left: 8,
                    right: 8,
                    top: 8,
                    child: Column(
                      children: [
                        _topStrip(app, ar, scene),
                        if (_lastSaved != null)
                          _banner(
                            'AR preview saved',
                            key: const ValueKey('ar_saved'),
                            color: AdinnColors.success.withValues(alpha: 0.9),
                            actions: [
                              _bannerButton('View', () {
                                final saved = _lastSaved;
                                final board = saved == null
                                    ? null
                                    : app.board(widget.shopId, saved.groupId);
                                if (saved == null || board == null) return;
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => PreviewViewerScreen(
                                      board: board,
                                      capture: saved,
                                      shopId: widget.editable
                                          ? widget.shopId
                                          : null,
                                    ),
                                  ),
                                );
                              }, key: const ValueKey('ar_view_saved')),
                            ],
                          ),
                        if (guidance != null)
                          _banner(
                            guidance,
                            key: const ValueKey('ar-guidance'),
                            color: ar.trackingLost
                                ? AdinnColors.red.withValues(alpha: 0.85)
                                : Colors.black54,
                            actions: [
                              if (scene.awaitingPlacement &&
                                  scene.placements.isNotEmpty)
                                _bannerButton(
                                  'Cancel',
                                  scene.cancelPlacement,
                                  key: const ValueKey('ar_cancel_place'),
                                ),
                            ],
                          ),
                        if (scene.message != null)
                          _banner(
                            scene.message!,
                            key: const ValueKey('ar_scene_message'),
                            actions: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                color: Colors.white,
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: scene.clearMessage,
                              ),
                            ],
                          ),
                        if (ar.error != null && ar.phase != ArPhase.starting)
                          _banner(ar.error!),
                        if (scene.awaitingPlacement &&
                            (failure == 'no_surface' ||
                                (placingItem?.mayNeedManualPlacement ?? false)))
                          _banner(
                            placingWall == true
                                ? 'Wall / glass not detected? Glass is often '
                                      'invisible to ARCore.'
                                : 'Ground not detected?',
                            key: const ValueKey('ar_place_fallback'),
                            color: AdinnColors.warning.withValues(alpha: 0.9),
                            actions: [
                              if (!ar.manualPlacement)
                                _bannerButton(
                                  'Place anyway',
                                  () => ar.setManualPlacement(true),
                                  key: const ValueKey('ar_place_manual'),
                                ),
                              if (widget.onOpenLivePreview != null)
                                _bannerButton(
                                  'Live Preview',
                                  widget.onOpenLivePreview,
                                  key: const ValueKey('ar_open_live_fallback'),
                                ),
                            ],
                          ),
                        if (scene.initialArmed &&
                            scene.armedItem != null &&
                            scene.placements.isEmpty &&
                            scene.initialTransform != const ArObjectTransform())
                          _banner(
                            'Previous orientation & scale restored. Saved '
                            'AR positions cannot be re-anchored – tap a '
                            'surface to place again.',
                          ),
                        if (sel != null && sel.transform.scaleAdjusted)
                          _banner(
                            'Preview Scale Adjusted – Not Actual Size '
                            '(${sel.transform.scalePercent}%). Recce '
                            'measurements are unchanged.',
                            key: const ValueKey('ar_scale_adjusted'),
                            color: AdinnColors.warning.withValues(alpha: 0.9),
                            actions: [
                              _bannerButton(
                                'Actual size',
                                scene.canEditSelected ? scene.resetScale : null,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  if (ar.phase != ArPhase.starting)
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(child: _sideButtons(scene)),
                    ),
                  if (ar.phase != ArPhase.starting)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      child: Center(child: _captureButton(ar)),
                    ),
                ],
              );
            },
          ),
        ),
        _toolbar(app, ar, scene),
      ],
    );
  }

  Widget _toolButton({
    required String keyName,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool active = false,
  }) {
    final color = onPressed == null
        ? AdinnColors.muted.withValues(alpha: 0.5)
        : (active ? AdinnColors.red : AdinnColors.ink);
    return Expanded(
      child: InkWell(
        key: ValueKey(keyName),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: active ? AdinnColors.redLight : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Prominent capture button floating over the camera view.
  Widget _captureButton(ArSessionController ar) => FilledButton.icon(
    key: const ValueKey('ar_capture'),
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      shape: const StadiumBorder(),
      elevation: 3,
    ),
    onPressed: ar.canCapture && widget.editable && !_saving ? _capture : null,
    icon: _saving
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.camera_alt, size: 22),
    label: const Text('Capture'),
  );

  Widget _toolbar(
    AppController app,
    ArSessionController ar,
    ArSceneController scene,
  ) {
    final sel = scene.selected;
    final has = sel != null;
    final b = has ? app.board(widget.shopId, sel.groupId) : null;
    final u = b?.unitById(sel?.unitId);
    // Material ancestor (not a coloured box) so list tiles / ink render.
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AdinnColors.line)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (scene.tool != ArTool.none)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                    child: ArToolPanel(
                      scene: scene,
                      board: b,
                      unit: u,
                      editable: widget.editable,
                      onEditDimensions: has ? () => _editDimensions(sel) : null,
                    ),
                  ),
                ),
              if (scene.tool != ArTool.none)
                const Divider(height: 1, color: AdinnColors.line),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Row(
                  children: [
                    _toolButton(
                      keyName: 'ar_tool_insert',
                      icon: Icons.add_box_outlined,
                      label: 'Insert',
                      active: scene.armedItem != null,
                      onPressed: _insert,
                    ),
                    for (final (t, icon) in const [
                      (ArTool.move, Icons.open_with),
                      (ArTool.rotate, Icons.rotate_90_degrees_ccw),
                      (ArTool.scale, Icons.photo_size_select_large),
                      (ArTool.dimensions, Icons.straighten),
                    ])
                      _toolButton(
                        keyName: 'ar_tool_${t.name}',
                        icon: icon,
                        label: t == ArTool.dimensions ? 'Size' : t.label,
                        active: scene.tool == t,
                        onPressed: () => scene.setTool(t),
                      ),
                    _toolButton(
                      keyName: 'ar_tool_duplicate',
                      icon: Icons.copy_all_outlined,
                      label: 'Copy',
                      onPressed: has ? scene.duplicateSelected : null,
                    ),
                    _toolButton(
                      keyName: 'ar_tool_delete',
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      onPressed: has ? _delete : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Name + save / save-as-new dialog. Owns its text controller so it is
/// disposed only after the dialog's closing animation.
class _LayoutNameDialog extends StatefulWidget {
  const _LayoutNameDialog({
    required this.initialName,
    required this.objectCount,
    required this.updating,
  });

  final String initialName;
  final int objectCount;
  final bool updating;

  @override
  State<_LayoutNameDialog> createState() => _LayoutNameDialogState();
}

class _LayoutNameDialogState extends State<_LayoutNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done(bool asNew) => Navigator.pop(context, (_name.text.trim(), asNew));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save AR Layout'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('ar_layout_name'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'Layout name'),
        ),
        const SizedBox(height: 8),
        Text(
          '${widget.objectCount} object(s): models and preview transforms '
          'are saved on this phone. AR positions must be re-anchored when '
          'the layout is reopened.',
          style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      if (widget.updating)
        TextButton(
          key: const ValueKey('ar_layout_save_new'),
          onPressed: () => _done(true),
          child: const Text('Save as new'),
        ),
      FilledButton(
        key: const ValueKey('ar_layout_save'),
        onPressed: () => _done(false),
        child: Text(widget.updating ? 'Update' : 'Save'),
      ),
    ],
  );
}
