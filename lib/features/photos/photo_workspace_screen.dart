import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../annotation/annotation_editor_screen.dart';
import '../ar/ar_preview_tab.dart';
import '../compare/comparison_screen.dart';
import '../ar/ar_session_controller.dart';
import '../preview_live/capture_utils.dart';
import '../preview_live/live_preview_tab.dart';
import '../survey/markup_entry.dart';
import 'annotation_apply.dart';
import 'site_photo_view.dart';

/// Photo preview section opened after a photo is captured (or tapped):
/// 1. Photo Editor – advanced annotation on the original photo.
/// 2. Live Preview – the selected signage model in 3D on the photo.
/// 3. Camera AR – the model in the live camera (when AR is available).
/// All tabs keep the same Project / Task / Shop / media group / unit context.
class PhotoWorkspaceScreen extends StatefulWidget {
  const PhotoWorkspaceScreen({
    super.key,
    required this.shopId,
    required this.boardId,
    required this.photoId,
    this.initialUnitId,
    this.initialTab = 0,
    this.arPlatform,
    this.writer,
  });

  final String shopId;
  final String boardId;
  final String photoId;
  final String? initialUnitId;
  final int initialTab;
  final ArPlatform? arPlatform;
  final PngWriter? writer;

  @override
  State<PhotoWorkspaceScreen> createState() => _PhotoWorkspaceScreenState();
}

class _PhotoWorkspaceScreenState extends State<PhotoWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String? _unitId;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    final b = context.read<AppController>().board(
      widget.shopId,
      widget.boardId,
    );
    _unitId = b?.unitById(widget.initialUnitId)?.id ?? b?.units.firstOrNull?.id;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _linkUnits(Board b, SitePhoto photo) async {
    final selected = photo.unitIds.toSet();
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Signage items in this photo',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Text(
                  'One photo can show several units. The image is shared, '
                  'never copied.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AdinnColors.muted),
                ),
              ),
              for (final u in b.activeUnits)
                CheckboxListTile(
                  key: ValueKey('photo-unit-${u.id}'),
                  dense: true,
                  value: selected.contains(u.id),
                  title: Text(b.unitLabel(u)),
                  subtitle: u.placement.isEmpty ? null : Text(u.placement),
                  onChanged: (v) => setSheet(
                    () =>
                        v == true ? selected.add(u.id) : selected.remove(u.id),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    context.read<AppController>().setPhotoUnits(
      widget.shopId,
      b.id,
      photo.id,
      result,
    );
  }

  Future<void> _export(Shop shop, Board b, SitePhoto photo) async {
    final app = context.read<AppController>();
    final media = app.media;
    final PngWriter? writer =
        widget.writer ??
        (media == null ? null : (png, folder) => writePng(media, png, folder));
    if (writer == null) {
      showSnack(context, 'Storage not available', error: true);
      return;
    }
    setState(() => _exporting = true);
    try {
      final png = await renderAnnotatedPhoto(photo);
      if (png == null) throw StateError('Photo file not found');
      final path = await writer(png, 'exports');
      app.addPreview(
        shop.id,
        b.id,
        PreviewCapture(
          id: newId('ex'),
          kind: CaptureKind.edited,
          projectId: shop.projectId,
          taskId: shop.taskId,
          shopId: shop.id,
          groupId: b.id,
          unitId: _unitId ?? b.units.first.id,
          photoId: photo.id,
          path: path,
          createdAt: DateTime.now(),
        ),
      );
      if (mounted) {
        showSnack(context, 'Annotated photo exported (original kept)');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(widget.shopId);
    final b = c.board(widget.shopId, widget.boardId);
    final photo = b?.photos.where((p) => p.id == widget.photoId).firstOrNull;
    if (shop == null || b == null || photo == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'Photo not found',
        ),
      );
    }
    final editable = c.canEdit(shop);
    final unit = b.unitById(_unitId) ?? b.units.first;
    final media = SignageCatalog.media(b.mediaCode);
    final project = c.project(shop.projectId);
    final task = c.task(shop.taskId);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              photo.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              [
                project?.name,
                task?.title,
                shop.name,
              ].whereType<String>().join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AdinnColors.muted),
            ),
          ],
        ),
        actions: [
          if (editable)
            IconButton(
              key: const ValueKey('link_photo_units'),
              tooltip: 'Signage items in this photo',
              onPressed: () => _linkUnits(b, photo),
              icon: const Icon(Icons.link),
            ),
          IconButton(
            key: const ValueKey('open_compare'),
            tooltip: 'Before / Proposed comparison',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ComparisonScreen(
                  shopId: widget.shopId,
                  boardId: b.id,
                  photoId: photo.id,
                  unitId: unit.id,
                ),
              ),
            ),
            icon: const Icon(Icons.compare),
          ),
          IconButton(
            key: const ValueKey('open_site_markup'),
            tooltip: 'Site markup (perspective, markers, electrical)',
            onPressed: () => openSiteMarkup(
              context,
              shopId: widget.shopId,
              boardId: b.id,
              photoId: photo.id,
              activeUnitId: unit.id,
            ),
            icon: const Icon(Icons.crop_rotate),
          ),
          IconButton(
            key: const ValueKey('export_annotated'),
            tooltip: 'Export annotated photo',
            onPressed: _exporting || !editable
                ? null
                : () => _export(shop, b, photo),
            icon: const Icon(Icons.ios_share),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(92),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Row(
                  children: [
                    Icon(
                      media?.icon ?? Icons.dashboard_customize_outlined,
                      size: 18,
                      color: AdinnColors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${media?.shortName ?? 'Media not set'} • ${b.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (b.units.length > 1)
                      DropdownButton<String>(
                        key: const ValueKey('workspace_unit'),
                        value: unit.id,
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final u in b.activeUnits)
                            DropdownMenuItem(
                              value: u.id,
                              child: Text(
                                '${b.unitLabel(u)} • '
                                '${fmtSize(b.widthOf(u), b.heightOf(u), b.unit)}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _unitId = v),
                      )
                    else
                      Text(
                        fmtSize(b.widthOf(unit), b.heightOf(unit), b.unit),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AdinnColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabs,
                labelColor: AdinnColors.red,
                indicatorColor: AdinnColors.red,
                tabs: const [
                  Tab(
                    key: ValueKey('tab-editor'),
                    icon: Icon(Icons.draw_outlined, size: 20),
                    text: 'Photo Editor',
                    height: 52,
                  ),
                  Tab(
                    key: ValueKey('tab-live'),
                    icon: Icon(Icons.layers_outlined, size: 20),
                    text: 'Live Preview',
                    height: 52,
                  ),
                  Tab(
                    key: ValueKey('tab-ar'),
                    icon: Icon(Icons.view_in_ar, size: 20),
                    text: 'Camera AR',
                    height: 52,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        // Drawing / dragging gestures must not swipe between tabs.
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _KeepAlive(
            child: editable
                ? AnnotationEditorScreen(
                    key: ValueKey('editor-${photo.id}-${unit.id}'),
                    photo: photo,
                    boardName: b.name,
                    defaultUnit: b.unit,
                    units: unitOptionsFor(b),
                    activeUnitId: b.quantity > 1 ? unit.id : null,
                    extraTools: siteMarkupTools(
                      context,
                      shopId: widget.shopId,
                      boardId: b.id,
                      photoId: photo.id,
                      activeUnitId: unit.id,
                    ),
                    underlay: LiveMarkupUnderlay(
                      controller: c,
                      shopId: widget.shopId,
                      photo: photo,
                    ),
                    onSave: (result) {
                      final sized = applyAnnotationResult(
                        c,
                        widget.shopId,
                        b,
                        photo.id,
                        result,
                      );
                      showSnack(
                        context,
                        sized
                            ? 'Annotations saved • board size updated'
                            : 'Annotations saved',
                      );
                    },
                  )
                : InteractiveViewer(
                    maxScale: 6,
                    child: Center(child: AnnotatedPhotoView(photo)),
                  ),
          ),
          LivePreviewTab(
            key: ValueKey('live-${photo.id}-${unit.id}'),
            shopId: widget.shopId,
            boardId: b.id,
            photoId: photo.id,
            initialUnitId: unit.id,
            editable: editable,
            writer: widget.writer,
          ),
          ArPreviewTab(
            key: ValueKey('ar-${unit.id}'),
            shopId: widget.shopId,
            boardId: b.id,
            unitId: unit.id,
            photoId: photo.id,
            platform: widget.arPlatform,
            editable: editable,
            writer: widget.writer,
            onOpenLivePreview: () => _tabs.animateTo(1),
          ),
        ],
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
