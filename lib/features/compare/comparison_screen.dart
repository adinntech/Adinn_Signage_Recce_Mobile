import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../data/storage/media_storage.dart';
import '../../state/app_controller.dart';
import '../photos/site_photo_view.dart';
import '../preview_live/capture_utils.dart';
import '../survey/site_markup_painter.dart';
import 'comparison_renderer.dart';

/// Writes an exported comparison PNG and returns its path.
typedef ComparisonWriter = Future<String> Function(Uint8List png);

/// Reads the pixel size of an image file (null when missing).
typedef ImageSizeReader = Future<Size?> Function(String path);

enum CompareMode { sideBySide, slider, toggle }

/// One "Proposed" image the before photo can be compared with. Only images
/// aligned to the same site photo are offered (never AR captures).
class ProposedOption {
  const ProposedOption({
    required this.key,
    required this.label,
    required this.source,
    this.capture,
  });

  /// `live:<captureId>` or 'perspective'.
  final String key;

  /// "Live preview 2 of 3 • 18 Nov 2026, 10:30 AM".
  final String label;
  final ProposedSource source;
  final PreviewCapture? capture;

  /// Proposed images available for [photo] of [b], oldest first.
  static List<ProposedOption> forPhoto(Board b, SitePhoto photo) {
    final live =
        b.previews
            .where((c) => c.kind == CaptureKind.live && c.photoId == photo.id)
            .toList()
          ..sort((a, c) => a.createdAt.compareTo(c.createdAt));
    return [
      for (var i = 0; i < live.length; i++)
        ProposedOption(
          key: 'live:${live[i].id}',
          label:
              'Live preview ${i + 1} of ${live.length} • '
              '${fmtDateTime(live[i].createdAt)}',
          source: ProposedSource.livePreview,
          capture: live[i],
        ),
      if (photo.markup.perspectives.isNotEmpty)
        const ProposedOption(
          key: 'perspective',
          label: 'Perspective placement (live render)',
          source: ProposedSource.perspective,
        ),
    ];
  }
}

/// Before / Proposed comparison of a site photo and a saved Live Preview
/// or perspective placement of the same photo. A visual proposal only.
class ComparisonScreen extends StatefulWidget {
  const ComparisonScreen({
    super.key,
    required this.shopId,
    required this.boardId,
    this.photoId,
    this.unitId,
    this.renderer,
    this.writer,
    this.imageSize,
  });

  final String shopId;
  final String boardId;
  final String? photoId;

  /// Signage item the saved comparison is stored against.
  final String? unitId;
  final ComparisonRenderer? renderer;
  final ComparisonWriter? writer;
  final ImageSizeReader? imageSize;

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  String? _photoId;
  String? _proposalKey;
  String? _unitId;
  CompareMode _mode = CompareMode.sideBySide;
  double _split = 0.5;
  bool _showProposed = true;
  bool _saving = false;

  /// Aspect ratio of the proposed image (null = same as the photo / unknown).
  double? _proposedAspect;
  String? _aspectFor;

  @override
  void initState() {
    super.initState();
    _photoId = widget.photoId;
    _unitId = widget.unitId;
  }

  Future<void> _checkAspect(ProposedOption? o) async {
    final path = o?.capture?.path;
    if (path == null) {
      if (_proposedAspect != null || _aspectFor != null) {
        setState(() {
          _proposedAspect = null;
          _aspectFor = null;
        });
      }
      return;
    }
    if (_aspectFor == path) return;
    _aspectFor = path;
    final reader = widget.imageSize ?? encodedImageSize;
    final size = await reader(path);
    if (!mounted || _aspectFor != path) return;
    setState(
      () => _proposedAspect = size == null || size.height == 0
          ? null
          : size.width / size.height,
    );
  }

  String _unitFor(Board b, SitePhoto photo, ProposedOption? o) {
    final active = b.activeUnits.map((u) => u.id).toSet();
    if (_unitId != null && active.contains(_unitId)) return _unitId!;
    final c = o?.capture;
    if (c != null && active.contains(c.unitId)) return c.unitId;
    for (final id in photo.unitIds) {
      if (active.contains(id)) return id;
    }
    return b.activeUnits.first.id;
  }

  Future<void> _save(
    AppController c,
    Shop shop,
    Board b,
    SitePhoto photo,
    ProposedOption o,
    MarkupLabels labels,
  ) async {
    setState(() => _saving = true);
    try {
      final unitId = _unitFor(b, photo, o);
      final unit = b.unitById(unitId)!;
      final media = SignageCatalog.media(b.mediaCode);
      final png = await (widget.renderer ?? const DefaultComparisonRenderer())
          .render(
            ComparisonRenderRequest(
              photo: photo,
              source: o.source,
              capture: o.capture,
              labels: labels,
              shopName: shop.name,
              itemLabel: labels.labelOf(unitId),
              mediaName: media?.name ?? b.name,
              versionLabel: o.label,
              date: DateTime.now(),
            ),
          );
      if (png == null) throw StateError('The site photo could not be read');
      final writer =
          widget.writer ??
          (bytes) => writePng(c.media ?? MediaStorage(), bytes, 'comparisons');
      final path = await writer(png);
      c.addComparison(
        shop.id,
        b.id,
        ComparisonRecord(
          id: newId('cmp'),
          groupId: b.id,
          unitId: unit.id,
          photoId: photo.id,
          source: o.source,
          previewId: o.capture?.id,
          versionLabel: o.label,
          path: path,
          createdAt: DateTime.now(),
          mode: _mode.name,
        ),
      );
      if (mounted) {
        showSnack(context, 'Comparison saved for ${b.unitLabel(unit)}');
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Could not save comparison: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(widget.shopId);
    final b = c.board(widget.shopId, widget.boardId);
    if (shop == null || b == null || b.photos.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Before / Proposed')),
        body: const EmptyState(
          icon: Icons.photo_outlined,
          title: 'No site photo',
          message: 'Capture a site photo first.',
        ),
      );
    }
    final photo =
        b.photos.where((p) => p.id == _photoId).firstOrNull ?? b.photos.first;
    final options = ProposedOption.forPhoto(b, photo);
    final option =
        options.where((o) => o.key == _proposalKey).firstOrNull ??
        options.lastOrNull;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkAspect(option);
    });
    final project = c.project(shop.projectId);
    final labels = MarkupLabels.forShop(shop, brand: project?.client ?? '');
    final editable = c.canEdit(shop);
    final aspect = photo.aspectRatio;
    final mismatch =
        _proposedAspect != null &&
        option?.capture != null &&
        (_proposedAspect! / aspect - 1).abs() > 0.02;
    final unitId = _unitFor(b, photo, option);
    final saved = b.comparisons.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Before / Proposed',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              '${shop.name} • ${b.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (b.photos.length > 1)
            DropdownButtonFormField<String>(
              key: const Key('cmp_photo'),
              initialValue: photo.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Before (site photo)',
              ),
              items: [
                for (final p in b.photos)
                  DropdownMenuItem(value: p.id, child: Text(p.label)),
              ],
              onChanged: (v) => setState(() {
                _photoId = v;
                _proposalKey = null;
              }),
            ),
          if (b.activeUnits.length > 1) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const Key('cmp_unit'),
              initialValue: unitId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Signage item'),
              items: [
                for (final u in b.activeUnits)
                  DropdownMenuItem(
                    value: u.id,
                    child: Text(labels.labelOf(u.id)),
                  ),
              ],
              onChanged: (v) => setState(() => _unitId = v),
            ),
          ],
          const SizedBox(height: 10),
          if (options.isEmpty)
            const EmptyState(
              key: Key('cmp_empty'),
              icon: Icons.compare_outlined,
              title: 'No proposed preview for this photo',
              message:
                  'Save a Live Preview on this photo or add a perspective '
                  'board placement first, then compare it here.',
            )
          else ...[
            DropdownButtonFormField<String>(
              key: const Key('cmp_proposed'),
              initialValue: option!.key,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Proposed'),
              items: [
                for (final o in options)
                  DropdownMenuItem(
                    value: o.key,
                    child: Text(o.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _proposalKey = v),
            ),
            const SizedBox(height: 10),
            SegmentedButton<CompareMode>(
              segments: const [
                ButtonSegment(
                  value: CompareMode.sideBySide,
                  icon: Icon(Icons.view_column_outlined, size: 18),
                  label: Text('Side', key: Key('cmp_mode_side')),
                ),
                ButtonSegment(
                  value: CompareMode.slider,
                  icon: Icon(Icons.compare, size: 18),
                  label: Text('Slider', key: Key('cmp_mode_slider')),
                ),
                ButtonSegment(
                  value: CompareMode.toggle,
                  icon: Icon(Icons.fullscreen, size: 18),
                  label: Text('Toggle', key: Key('cmp_mode_toggle')),
                ),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              'Comparing "${photo.label}" with ${option.label}',
              key: const Key('cmp_version'),
              style: const TextStyle(fontSize: 12.5, color: AdinnColors.muted),
            ),
            if (mismatch)
              Container(
                key: const Key('cmp_aspect_warning'),
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AdinnColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'The proposed image has a different aspect ratio. It is '
                  'shown letter-boxed (not stretched) – alignment may differ.',
                  style: TextStyle(fontSize: 12, color: AdinnColors.warning),
                ),
              ),
            const SizedBox(height: 10),
            _viewer(photo, option, labels, aspect),
            const SizedBox(height: 6),
            const Text(
              'Visual proposal only – not an as-built installation photo.',
              style: TextStyle(fontSize: 11.5, color: AdinnColors.muted),
            ),
            if (editable) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('cmp_save'),
                onPressed: _saving
                    ? null
                    : () => _save(c, shop, b, photo, option, labels),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt),
                label: const Text('Save Comparison'),
              ),
            ],
          ],
          const SizedBox(height: 16),
          Text(
            'Saved comparisons (${saved.length})',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (saved.isEmpty)
            const Text(
              'None saved yet.',
              style: TextStyle(color: AdinnColors.muted, fontSize: 12.5),
            ),
          for (final r in saved)
            ListTile(
              key: Key('cmp_saved_${r.id}'),
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 64,
                  height: 40,
                  child: Image.file(
                    File(r.path),
                    fit: BoxFit.cover,
                    cacheWidth: 200,
                    errorBuilder: (_, _, _) => Container(
                      color: AdinnColors.canvas,
                      child: const Icon(
                        Icons.compare_outlined,
                        size: 18,
                        color: AdinnColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
              title: Text(
                labels.labelOf(r.unitId),
                style: const TextStyle(fontSize: 13.5),
              ),
              subtitle: Text(
                '${r.versionLabel}\n${fmtDateTime(r.createdAt)}',
                style: const TextStyle(fontSize: 11.5),
              ),
              isThreeLine: true,
              trailing: editable
                  ? IconButton(
                      key: Key('cmp_delete_${r.id}'),
                      tooltip: 'Delete comparison',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await confirmDialog(
                          context,
                          title: 'Delete comparison?',
                          message:
                              'Only the comparison image is removed. The site '
                              'photo and previews stay.',
                          confirmText: 'Delete',
                          destructive: true,
                        );
                        if (ok) await c.removeComparison(shop.id, b.id, r.id);
                      },
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _before(SitePhoto photo) => SitePhotoImage(photo, cacheWidth: 1200);

  Widget _proposed(SitePhoto photo, ProposedOption o, MarkupLabels labels) {
    if (o.source == ProposedSource.perspective) {
      return Stack(
        fit: StackFit.expand,
        children: [
          SitePhotoImage(photo, cacheWidth: 1200),
          CustomPaint(
            painter: SiteMarkupPainter(
              markup: photo.markup,
              labels: labels,
              hiddenLayers: const {
                MarkupLayer.markers,
                MarkupLayer.electrical,
                MarkupLayer.obstructions,
              },
            ),
          ),
        ],
      );
    }
    return Container(
      color: const Color(0xFF202124),
      child: Image.file(
        File(o.capture!.path),
        fit: BoxFit.contain,
        cacheWidth: 1200,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => Container(
          key: const Key('cmp_missing'),
          color: AdinnColors.line,
          alignment: Alignment.center,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: AdinnColors.muted),
              SizedBox(height: 4),
              Text(
                'Proposed image not found on device',
                style: TextStyle(fontSize: 11, color: AdinnColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _box(double aspect, Widget child, {Key? key}) => ClipRRect(
    key: key,
    borderRadius: BorderRadius.circular(8),
    child: AspectRatio(aspectRatio: aspect, child: child),
  );

  Widget _viewer(
    SitePhoto photo,
    ProposedOption o,
    MarkupLabels labels,
    double aspect,
  ) {
    switch (_mode) {
      case CompareMode.sideBySide:
        return Row(
          key: const Key('cmp_side_view'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tag('BEFORE', AdinnColors.ink),
                  const SizedBox(height: 4),
                  _box(
                    aspect,
                    _before(photo),
                    key: const Key('cmp_before_box'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tag('PROPOSED', AdinnColors.red),
                  const SizedBox(height: 4),
                  _box(
                    aspect,
                    _proposed(photo, o, labels),
                    key: const Key('cmp_proposed_box'),
                  ),
                ],
              ),
            ),
          ],
        );
      case CompareMode.slider:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _box(
              aspect,
              LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth;
                  void update(Offset local) =>
                      setState(() => _split = (local.dx / w).clamp(0.0, 1.0));
                  return GestureDetector(
                    key: const Key('cmp_slider'),
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => update(d.localPosition),
                    onHorizontalDragUpdate: (d) => update(d.localPosition),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _proposed(photo, o, labels),
                        ClipRect(
                          clipper: _LeftClipper(_split),
                          child: _before(photo),
                        ),
                        Positioned(
                          left: (w * _split - 1).clamp(0.0, w - 2),
                          top: 0,
                          bottom: 0,
                          width: 2,
                          child: Container(color: Colors.white),
                        ),
                        Positioned(
                          left: (w * _split - 16).clamp(0.0, w - 32),
                          top: box.maxHeight / 2 - 16,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black26, blurRadius: 4),
                              ],
                            ),
                            child: const Icon(
                              Icons.compare_arrows,
                              size: 20,
                              color: AdinnColors.red,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 6,
                          top: 6,
                          child: _tag('BEFORE', AdinnColors.ink),
                        ),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: _tag('PROPOSED', AdinnColors.red),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Before ${(_split * 100).round()}% | Proposed '
              '${(100 - _split * 100).round()}%',
              key: const Key('cmp_slider_value'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
            ),
          ],
        );
      case CompareMode.toggle:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('Before'),
                Switch(
                  key: const Key('cmp_toggle'),
                  value: _showProposed,
                  onChanged: (v) => setState(() => _showProposed = v),
                ),
                const Text('Proposed'),
                const Spacer(),
                IconButton(
                  key: const Key('cmp_fullscreen'),
                  tooltip: 'Full screen',
                  icon: const Icon(Icons.fullscreen),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _FullScreenToggle(
                        aspect: aspect,
                        before: _before(photo),
                        proposed: _proposed(photo, o, labels),
                        initialProposed: _showProposed,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Stack(
              children: [
                _box(
                  aspect,
                  _showProposed ? _proposed(photo, o, labels) : _before(photo),
                  key: Key(
                    _showProposed
                        ? 'cmp_showing_proposed'
                        : 'cmp_showing_before',
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: _showProposed
                      ? _tag('PROPOSED', AdinnColors.red)
                      : _tag('BEFORE', AdinnColors.ink),
                ),
              ],
            ),
          ],
        );
    }
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.fraction != fraction;
}

/// Full-screen Original / Proposed toggle (tap the image to switch).
class _FullScreenToggle extends StatefulWidget {
  const _FullScreenToggle({
    required this.aspect,
    required this.before,
    required this.proposed,
    required this.initialProposed,
  });

  final double aspect;
  final Widget before;
  final Widget proposed;
  final bool initialProposed;

  @override
  State<_FullScreenToggle> createState() => _FullScreenToggleState();
}

class _FullScreenToggleState extends State<_FullScreenToggle> {
  late bool _proposed = widget.initialProposed;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(_proposed ? 'Proposed' : 'Original'),
      actions: [
        TextButton(
          key: const Key('cmp_fs_toggle'),
          onPressed: () => setState(() => _proposed = !_proposed),
          child: Text(
            _proposed ? 'Show Original' : 'Show Proposed',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
    body: GestureDetector(
      onTap: () => setState(() => _proposed = !_proposed),
      child: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: AspectRatio(
            aspectRatio: widget.aspect,
            child: _proposed ? widget.proposed : widget.before,
          ),
        ),
      ),
    ),
  );
}
