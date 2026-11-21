import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../photos/site_photo_view.dart';
import '../preview3d/renderer_painter.dart';
import 'capture_utils.dart';
import 'live_preview_controller.dart';

/// Saves PNG bytes into a media folder and returns the file path.
typedef PngWriter = Future<String> Function(Uint8List png, String folder);

/// Live Preview: the selected signage model(s) rendered in 3D on top of the
/// captured site photo. Each model can be dragged, pinched (scale +
/// rotate), turned, tilted for perspective and faded, then the composed
/// image is saved against the signage item. The original photo is untouched.
class LivePreviewTab extends StatefulWidget {
  const LivePreviewTab({
    super.key,
    required this.shopId,
    required this.boardId,
    required this.photoId,
    this.initialUnitId,
    this.editable = true,
    this.writer,
  });

  final String shopId;
  final String boardId;
  final String photoId;
  final String? initialUnitId;
  final bool editable;

  /// Overrides where captures are written (tests).
  final PngWriter? writer;

  @override
  State<LivePreviewTab> createState() => _LivePreviewTabState();
}

class _LivePreviewTabState extends State<LivePreviewTab> {
  final _boundaryKey = GlobalKey();
  LivePreviewController? _c;
  PreviewOverlay? _gestureStart;
  Offset _focalStart = Offset.zero;
  Size _display = Size.zero;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
    final shop = app.shop(widget.shopId);
    final board = app.board(widget.shopId, widget.boardId);
    final photo = board?.photos
        .where((p) => p.id == widget.photoId)
        .firstOrNull;
    if (shop == null || board == null || photo == null) return;
    final brand = (app.project(shop.projectId)?.name ?? 'Adinn').toUpperCase();
    final restored = LivePreviewController.restoreFrom(board, photo);
    _c = LivePreviewController(
      board: board,
      photo: photo,
      brand: brand,
      overlays: restored,
    )..addListener(_changed);
    if (restored == null) {
      final unitId =
          board.unitById(widget.initialUnitId)?.id ?? board.units.first.id;
      _c!.addUnit(unitId);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c?.removeListener(_changed);
    _c?.dispose();
    super.dispose();
  }

  String _unitTitle(Board b, PreviewOverlay o) {
    final u = b.unitById(o.unitId);
    final media = SignageCatalog.media(b.mediaCode)?.shortName ?? b.name;
    return u == null ? media : '$media ${b.unitLabel(u)}';
  }

  // ---------------------------------------------------------------------------
  // Gestures
  // ---------------------------------------------------------------------------

  void _onTapUp(TapUpDetails d) {
    final c = _c!;
    final hit = c.overlayAt(d.localPosition, _display);
    if (hit != null) c.select(hit);
  }

  void _onScaleStart(ScaleStartDetails d) {
    final c = _c!;
    final hit = c.overlayAt(d.localFocalPoint, _display);
    if (hit != null) c.select(hit);
    _gestureStart = c.selected?.copy();
    _focalStart = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final c = _c!;
    final start = _gestureStart;
    if (start == null || _display.isEmpty) return;
    final delta = d.localFocalPoint - _focalStart;
    c.setPosition(
      start.cx + delta.dx / _display.width,
      start.cy + delta.dy / _display.height,
    );
    if (d.pointerCount >= 2) {
      c.setScale(start.scale * d.scale);
      c.setRotation(start.rotation + d.rotation);
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _addItem(Board b) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add signage item to preview',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            for (final u in b.activeUnits)
              ListTile(
                key: ValueKey('live-add-${u.id}'),
                leading: const Icon(Icons.add_box_outlined),
                title: Text(
                  '${SignageCatalog.media(b.mediaCode)?.shortName ?? b.name} '
                  '${b.unitLabel(u)}',
                ),
                subtitle: Text(fmtSize(b.widthOf(u), b.heightOf(u), b.unit)),
                onTap: () => Navigator.pop(ctx, u.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null) _c!.addUnit(picked);
  }

  Future<void> _save(Shop shop, Board b) async {
    final c = _c!;
    final app = context.read<AppController>();
    if (c.overlays.isEmpty) {
      showSnack(context, 'Add a signage item first', error: true);
      return;
    }
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
      final ratio = _display.width <= 0
          ? 2.0
          : (c.photo.width / _display.width).clamp(1.0, 3.0).toDouble();
      final png = await captureBoundary(_boundaryKey, pixelRatio: ratio);
      if (png == null) throw StateError('Nothing to capture');
      final path = await writer(png, 'previews');
      app.addPreview(
        shop.id,
        b.id,
        c.toCapture(
          id: newId('pv'),
          shop: shop,
          path: path,
          at: DateTime.now(),
        ),
      );
      if (mounted) showSnack(context, 'Live preview saved');
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Could not save preview: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final shop = app.shop(widget.shopId);
    final b = app.board(widget.shopId, widget.boardId);
    final c = _c;
    if (shop == null || b == null || c == null) {
      return const EmptyState(icon: Icons.search_off, title: 'Photo not found');
    }
    return Column(
      children: [
        Expanded(child: _stage(c)),
        _controls(shop, b, c),
      ],
    );
  }

  Widget _stage(LivePreviewController c) {
    return Container(
      color: const Color(0xFF202124),
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, box) {
          final fitted = applyBoxFit(
            BoxFit.contain,
            c.imageSize,
            Size(box.maxWidth, box.maxHeight),
          ).destination;
          if (fitted.isEmpty) return const SizedBox.shrink();
          _display = fitted;
          return Center(
            child: SizedBox(
              width: fitted.width,
              height: fitted.height,
              child: GestureDetector(
                key: const ValueKey('live-stage'),
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTapUp,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: (_) => _gestureStart = null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      key: _boundaryKey,
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            SitePhotoImage(c.photo),
                            if (c.showModels)
                              for (final o in c.overlays) _model(c, o, fitted),
                          ],
                        ),
                      ),
                    ),
                    // Selection frame lives outside the captured boundary so
                    // it never appears in saved previews.
                    if (c.showModels && c.selected != null)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _SelectionPainter(c.selected!, fitted),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _model(LivePreviewController c, PreviewOverlay o, Size display) {
    final side = math.max(o.scale * display.width, 1.0);
    return Positioned(
      left: o.cx * display.width - side / 2,
      top: o.cy * display.height - side / 2,
      width: side,
      height: side,
      child: Transform.rotate(
        angle: o.rotation,
        child: Opacity(
          opacity: o.opacity,
          child: CustomPaint(
            key: ValueKey('live-model-${o.unitId}'),
            painter: Scene3DPainter(
              scene: c.sceneFor(o),
              camera: Camera3D(yaw: o.yaw, pitch: o.pitch),
              showDimensions: c.showMeasurements,
              paintBackground: false,
              paintGround: false,
              paintGizmo: false,
            ),
          ),
        ),
      ),
    );
  }

  Widget _slider({
    required Key key,
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AdinnColors.muted),
        const SizedBox(width: 6),
        SizedBox(
          width: 78,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            key: key,
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _controls(Shop shop, Board b, LivePreviewController c) {
    final sel = c.selected;
    final rect = sel == null ? null : c.placementFor(sel.unitId);
    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AdinnColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (var i = 0; i < c.overlays.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              key: ValueKey('live-chip-$i'),
                              label: Text(_unitTitle(b, c.overlays[i])),
                              selected: i == c.selectedIndex,
                              onSelected: (_) => c.select(i),
                            ),
                          ),
                        ActionChip(
                          key: const ValueKey('live_add_item'),
                          avatar: const Icon(Icons.add, size: 18),
                          label: const Text('Add item'),
                          onPressed: () => _addItem(b),
                        ),
                      ],
                    ),
                  ),
                  if (sel == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Add a signage item to place its 3D model on the photo.',
                        style: TextStyle(color: AdinnColors.muted),
                      ),
                    )
                  else ...[
                    const Text(
                      'Drag to move • pinch to resize & rotate',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AdinnColors.muted,
                      ),
                    ),
                    _slider(
                      key: const ValueKey('live_size'),
                      icon: Icons.open_in_full,
                      label: 'Size',
                      value: sel.scale,
                      min: LivePreviewController.minScale,
                      max: LivePreviewController.maxScale,
                      onChanged: c.setScale,
                    ),
                    _slider(
                      key: const ValueKey('live_yaw'),
                      icon: Icons.threed_rotation,
                      label: 'Turn',
                      value: sel.yaw,
                      min: -1.4,
                      max: 1.4,
                      onChanged: c.setYaw,
                    ),
                    _slider(
                      key: const ValueKey('live_pitch'),
                      icon: Icons.panorama_horizontal,
                      label: 'Perspective',
                      value: sel.pitch,
                      min: LivePreviewController.minPitch,
                      max: LivePreviewController.maxPitch,
                      onChanged: c.setPitch,
                    ),
                    _slider(
                      key: const ValueKey('live_rotation'),
                      icon: Icons.rotate_right,
                      label: 'Rotate',
                      value: sel.rotation,
                      min: -math.pi,
                      max: math.pi,
                      onChanged: c.setRotation,
                    ),
                    _slider(
                      key: const ValueKey('live_opacity'),
                      icon: Icons.opacity,
                      label: 'Opacity',
                      value: sel.opacity,
                      min: 0.1,
                      max: 1,
                      onChanged: c.setOpacity,
                    ),
                  ],
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (rect != null && sel != null)
                        ActionChip(
                          key: const ValueKey('live_fit'),
                          avatar: const Icon(Icons.crop_free, size: 18),
                          label: const Text('Fit to marking'),
                          onPressed: c.resetSelected,
                        ),
                      ActionChip(
                        key: const ValueKey('live_reset'),
                        avatar: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Reset'),
                        onPressed: sel == null ? null : c.resetSelected,
                      ),
                      FilterChip(
                        key: const ValueKey('live_measure'),
                        label: const Text('Measurements'),
                        selected: c.showMeasurements,
                        onSelected: (_) => c.toggleMeasurements(),
                      ),
                      FilterChip(
                        key: const ValueKey('live_models'),
                        label: const Text('Model layer'),
                        selected: c.showModels,
                        onSelected: (_) => c.toggleModels(),
                      ),
                      ActionChip(
                        key: const ValueKey('live_remove'),
                        avatar: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove'),
                        onPressed: sel == null ? null : c.removeSelected,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Always visible, below the scrollable adjustments.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: FilledButton.icon(
              key: const ValueKey('save_live_preview'),
              onPressed: _saving || !widget.editable || sel == null
                  ? null
                  : () => _save(shop, b),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt),
              label: const Text('Save Live Preview'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.o, this.display);

  final PreviewOverlay o;
  final Size display;

  @override
  void paint(Canvas canvas, Size size) {
    final side = o.scale * display.width;
    canvas.save();
    canvas.translate(o.cx * display.width, o.cy * display.height);
    canvas.rotate(o.rotation);
    final r = Rect.fromCenter(center: Offset.zero, width: side, height: side);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.9);
    // Corner brackets only, so the model stays visible.
    final l = math.min(18.0, side / 4);
    for (final (c, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(c, c + Offset(l * dx, 0), paint);
      canvas.drawLine(c, c + Offset(0, l * dy), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter old) => true;
}
