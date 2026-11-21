import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import 'panorama_io.dart';
import 'panorama_painter.dart';
import 'panorama_view_state.dart';

/// A signage item of the shop that can be placed in the panorama.
class _UnitOption {
  const _UnitOption(this.unitId, this.style);

  final String unitId;
  final PlacementStyle style;
}

List<_UnitOption> _unitOptions(Shop shop) => [
  for (final b in shop.boards)
    for (final u in b.activeUnits)
      _UnitOption(
        u.id,
        PlacementStyle(
          label:
              '${SignageCatalog.media(b.mediaCode)?.shortName ?? b.name} • '
              '${b.unitLabel(u)}',
          aspect: (b.widthOf(u) ?? 0) > 0 && (b.heightOf(u) ?? 0) > 0
              ? b.widthOf(u)! / b.heightOf(u)!
              : 2,
        ),
      ),
];

/// Interactive viewer for an imported 360° panorama with signage
/// placement (approximate flat projection). View only when the recce is
/// not editable.
class PanoramaViewerScreen extends StatefulWidget {
  const PanoramaViewerScreen({
    super.key,
    required this.shopId,
    required this.panoramaId,
    this.imageLoader,
    this.previewWriter,
  });

  final String shopId;
  final String panoramaId;

  /// Injectable (tests); defaults to decoding the stored file.
  final PanoramaImageLoader? imageLoader;
  final PanoramaPreviewWriter? previewWriter;

  @override
  State<PanoramaViewerScreen> createState() => _PanoramaViewerScreenState();
}

class _PanoramaViewerScreenState extends State<PanoramaViewerScreen> {
  PanoramaViewState? _view;
  ui.Image? _image;
  String? _loadError;
  bool _loading = true;
  List<PanoramaPlacement> _placements = [];
  String? _selectedId;
  String? _unitId;
  bool _dirty = false;
  bool _savingPreview = false;
  int _revision = 0;
  Size _canvas = Size.zero;
  double _zoomAtStart = 1;

  @override
  void initState() {
    super.initState();
    final c = context.read<AppController>();
    final p = c.panorama(widget.panoramaId);
    if (p == null) {
      _loading = false;
      return;
    }
    _view = PanoramaViewState(yawDeg: p.northYawDeg);
    _placements = [for (final x in p.placements) x.copy()];
    _load(p.path);
  }

  Future<void> _load(String path) async {
    try {
      final img = await (widget.imageLoader ?? loadPanoramaImage)(path);
      if (!mounted) {
        img.dispose();
        return;
      }
      setState(() {
        _image = img;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'The panorama image could not be loaded.';
        });
      }
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _changed(void Function() f) => setState(() {
    f();
    _revision++;
  });

  PanoramaPlacement? get _selected =>
      _placements.where((p) => p.id == _selectedId).firstOrNull;

  void _place(PanoramaViewState view) {
    final unitId = _unitId;
    if (unitId == null) return;
    final p = PanoramaPlacement(
      id: newId('pp'),
      unitId: unitId,
      yawDeg: view.yawDeg,
      pitchDeg: view.pitchDeg,
      createdAt: DateTime.now(),
    );
    _changed(() {
      _placements.add(p);
      _selectedId = p.id;
      _dirty = true;
    });
  }

  void _save() {
    final c = context.read<AppController>();
    try {
      c.savePanoramaPlacements(widget.panoramaId, _placements);
      setState(() => _dirty = false);
      showSnack(context, 'Placements saved');
    } on Object catch (e) {
      showSnack(context, 'Could not save: $e', error: true);
    }
  }

  Future<void> _savePreview(
    PanoramaViewState view,
    Map<String, PlacementStyle> styles,
  ) async {
    final c = context.read<AppController>();
    final size = _canvas.isEmpty ? const Size(1200, 800) : _canvas;
    final scale = math.min(2.0, 1600 / size.width);
    final out = Size(
      (size.width * scale).roundToDouble(),
      (size.height * scale).roundToDouble(),
    );
    setState(() => _savingPreview = true);
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      PanoramaPainter(
        image: _image,
        view: view,
        placements: _placements,
        styles: styles,
        drawPlacements: true,
      ).paint(canvas, out);
      final picture = recorder.endRecording();
      final img = await picture.toImage(out.width.toInt(), out.height.toInt());
      picture.dispose();
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (data == null) throw StateError('PNG encoding failed');
      final writer = widget.previewWriter ?? mediaPreviewWriter(c.media);
      final path = await writer(data.buffer.asUint8List());
      c.addPanoramaPreview(widget.panoramaId, path);
      if (mounted) showSnack(context, 'Preview saved');
    } on Object catch (e) {
      if (mounted) {
        showSnack(context, 'Could not save preview: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _savingPreview = false);
    }
  }

  Future<void> _confirmLeave() async {
    final ok = await confirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Placement changes are not saved yet.',
      confirmText: 'Discard',
      destructive: true,
    );
    if (ok && mounted) {
      setState(() => _dirty = false);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final pano = c.panorama(widget.panoramaId);
    final shop = c.shop(widget.shopId);
    final view = _view;
    if (pano == null || shop == null || view == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('360° panorama')),
        body: const EmptyState(
          key: Key('pano_missing'),
          icon: Icons.panorama_photosphere_outlined,
          title: 'Panorama not found',
          message: 'It may have been removed.',
        ),
      );
    }
    final editable = c.canEdit(shop);
    final options = _unitOptions(shop);
    final styles = {for (final o in options) o.unitId: o.style};
    if (_unitId == null || !styles.containsKey(_unitId)) {
      _unitId = options.isEmpty ? null : options.first.unitId;
    }
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(pano.label),
          actions: [
            if (editable)
              IconButton(
                key: const Key('pano_save_preview'),
                tooltip: 'Save preview image',
                onPressed: _savingPreview
                    ? null
                    : () => _savePreview(view, styles),
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
            if (editable)
              IconButton(
                key: const Key('pano_save'),
                tooltip: 'Save placements',
                onPressed: _dirty ? _save : null,
                icon: const Icon(Icons.save_outlined),
              ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              color: AdinnColors.redLight,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                'Approximate flat projection (no spherical correction). A '
                'panorama is an image, not a measured 3D model – sizes here '
                'are visual only.${editable ? '' : '  View only.'}',
                key: const Key('pano_honesty'),
                style: const TextStyle(fontSize: 11, color: AdinnColors.ink),
              ),
            ),
            Expanded(child: _canvasArea(view, styles, editable)),
            _directionBar(c, pano, view, editable),
            if (editable) _placementPanel(view, options),
          ],
        ),
      ),
    );
  }

  Widget _canvasArea(
    PanoramaViewState view,
    Map<String, PlacementStyle> styles,
    bool editable,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _canvas) {
          _canvas = size;
          view.clamp(size);
        }
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const Key('pano_canvas'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selectedId = null),
                onScaleStart: (_) => _zoomAtStart = view.zoom,
                onScaleUpdate: (d) => _changed(() {
                  if (d.pointerCount >= 2) {
                    view.zoomTo(_zoomAtStart * d.scale, size);
                  }
                  view.panByPixels(d.focalPointDelta, size);
                }),
                child: CustomPaint(
                  painter: PanoramaPainter(
                    image: _image,
                    view: view,
                    revision: _revision,
                  ),
                ),
              ),
            ),
            for (final p in _placements)
              if (view.isVisible(
                p.yawDeg,
                p.pitchDeg,
                size,
                marginDeg: p.widthDeg,
              ))
                _marker(p, view, size, styles[p.unitId], editable),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_loadError != null)
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Card(
                  color: AdinnColors.redLight,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      _loadError!,
                      key: const Key('pano_load_error'),
                      style: const TextStyle(color: AdinnColors.redDark),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Yaw ${view.yawDeg.round()}° • Pitch '
                  '${view.pitchDeg.round()}° • ${view.zoom.toStringAsFixed(1)}×',
                  key: const Key('pano_readout'),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Column(
                children: [
                  _roundButton(
                    const Key('pano_zoom_in'),
                    Icons.add,
                    'Zoom in',
                    () => _changed(() => view.zoomBy(1.25, size)),
                  ),
                  const SizedBox(height: 6),
                  _roundButton(
                    const Key('pano_zoom_out'),
                    Icons.remove,
                    'Zoom out',
                    () => _changed(() => view.zoomBy(0.8, size)),
                  ),
                  const SizedBox(height: 6),
                  _roundButton(
                    const Key('pano_reset'),
                    Icons.center_focus_strong_outlined,
                    'Reset orientation',
                    () => _changed(() => view.reset(size)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _roundButton(Key key, IconData icon, String tip, VoidCallback onTap) =>
      Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: IconButton(
          key: key,
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white),
        ),
      );

  Widget _marker(
    PanoramaPlacement p,
    PanoramaViewState view,
    Size size,
    PlacementStyle? style,
    bool editable,
  ) {
    final box = placementBox(p, view, size, aspect: style?.aspect ?? 2);
    final w = math.max(24.0, box.size.width);
    final h = math.max(14.0, box.size.height);
    final selected = p.id == _selectedId;
    return Positioned(
      left: box.center.dx - w / 2,
      top: box.center.dy - h / 2,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: box.rotationRad,
        child: GestureDetector(
          key: Key('pano_mark_${p.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _selectedId = p.id),
          onPanStart: editable
              ? (_) => setState(() => _selectedId = p.id)
              : null,
          onPanUpdate: editable
              ? (d) => _changed(() {
                  final k = view.degPerPx(size);
                  p.yawDeg = normalizeYaw(p.yawDeg + d.delta.dx * k);
                  p.pitchDeg = (p.pitchDeg - d.delta.dy * k)
                      .clamp(-90, 90)
                      .toDouble();
                  _dirty = true;
                })
              : null,
          child: Container(
            decoration: BoxDecoration(
              color: AdinnColors.red.withValues(alpha: 0.28),
              border: Border.all(
                color: selected ? Colors.white : AdinnColors.red,
                width: selected ? 3 : 2,
              ),
            ),
            alignment: Alignment.center,
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Text(
                  style?.label ?? 'Removed item',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(blurRadius: 3)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _directionBar(
    AppController c,
    PanoramaRecord pano,
    PanoramaViewState view,
    bool editable,
  ) {
    final relative = normalizeYaw(view.yawDeg - pano.northYawDeg);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final d in PanoramaDirection.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: OutlinedButton(
                      key: Key('pano_dir_${d.name}'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 34),
                      ),
                      onPressed: () => _changed(
                        () => view.lookAt(d.yawFor(pano.northYawDeg), _canvas),
                      ),
                      child: Text(d.label),
                    ),
                  ),
                ),
              if (editable)
                Expanded(
                  flex: 2,
                  child: TextButton(
                    key: const Key('pano_set_north'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 34),
                    ),
                    onPressed: () {
                      c.setPanoramaNorth(pano.id, view.yawDeg);
                      showSnack(context, 'Current view set as North');
                    },
                    child: const Text(
                      'Set view as N',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  key: const Key('pano_compass'),
                  value: relative.clamp(0, 359.9).toDouble(),
                  max: 359.9,
                  onChanged: (v) => _changed(
                    () => view.lookAt(pano.northYawDeg + v, _canvas),
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '${relative.round()}° from N',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          if (pano.northYawDeg == 0)
            const Text(
              'North not set: N/E/S/W are relative to the image centre until '
              '"Set view as N" is used.',
              style: TextStyle(fontSize: 10, color: AdinnColors.muted),
            ),
        ],
      ),
    );
  }

  Widget _placementPanel(PanoramaViewState view, List<_UnitOption> options) {
    final sel = _selected;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (options.isEmpty)
              const Text(
                'Add a media group to this shop to place signage.',
                style: TextStyle(fontSize: 12, color: AdinnColors.muted),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      key: const Key('pano_unit'),
                      isExpanded: true,
                      value: _unitId,
                      items: [
                        for (final o in options)
                          DropdownMenuItem(
                            value: o.unitId,
                            child: Text(
                              o.style.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _unitId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('pano_place'),
                    onPressed: _unitId == null ? null : () => _place(view),
                    icon: const Icon(Icons.add_box_outlined, size: 18),
                    label: const Text('Place'),
                  ),
                ],
              ),
            if (sel != null) ...[
              Row(
                children: [
                  const SizedBox(width: 56, child: Text('Size')),
                  Expanded(
                    child: Slider(
                      key: const Key('pano_scale'),
                      value: sel.scale,
                      min: PanoramaPlacement.minScale,
                      max: PanoramaPlacement.maxScale,
                      onChanged: (v) => _changed(() {
                        sel.scale = v;
                        _dirty = true;
                      }),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 56, child: Text('Rotate')),
                  Expanded(
                    child: Slider(
                      key: const Key('pano_rotate'),
                      value: sel.rotationDeg,
                      min: -180,
                      max: 180,
                      onChanged: (v) => _changed(() {
                        sel.rotationDeg = v;
                        _dirty = true;
                      }),
                    ),
                  ),
                  IconButton(
                    key: const Key('pano_delete'),
                    tooltip: 'Remove placement',
                    onPressed: () => _changed(() {
                      _placements.removeWhere((p) => p.id == sel.id);
                      _selectedId = null;
                      _dirty = true;
                    }),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AdinnColors.redDark,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
