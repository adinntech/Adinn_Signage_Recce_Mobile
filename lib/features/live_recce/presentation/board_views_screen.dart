import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_file_row.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../data/models/models.dart';
import '../../drawing/drawing_2d_painter.dart';
import '../../drawing/signage_geometry.dart';
import '../../preview3d/renderer_painter.dart';
import '../../preview3d/scene3d.dart';
import '../../preview3d/signage_scene_builder.dart';
import '../data/board_geometry.dart';
import '../data/recce_models.dart';

/// "2D / 3D view" of the boards of one shop, opened from the Photos tab once photos are uploaded. It only draws what the recce person
/// entered on the Boards tab (type, size, unit, sided, position) with the same painters as the older recce screens. Nothing is saved.
class BoardViewsScreen extends StatefulWidget {
  /// [boards] are the boards as they are on the Boards tab right now (saved or not); [drawnBy] goes into the drawing's title block.
  const BoardViewsScreen({super.key, required this.detail, required this.boards, this.drawnBy = '-'});

  final ShopDetail detail;
  final List<BoardItem> boards;
  final String drawnBy;

  @override
  State<BoardViewsScreen> createState() => _BoardViewsScreenState();
}

class _BoardViewsScreenState extends State<BoardViewsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late final List<BoardItem> _boards = [for (final b in widget.boards) b.copy()];
  late final List<SignageGeometry> _geo = [for (final b in _boards) geometryForBoard(b)];
  var _selected = 0;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final photos = [for (final p in d.photos) if (p.displayUrl != null) p];
    return Scaffold(
      appBar: AppBar(title: const Text('2D / 3D view')),
      body: _boards.isEmpty
          ? const EmptyState(icon: Icons.architecture, title: 'No board yet', message: 'Add a board with its size on the Boards tab, then open this view again.')
          : Column(
              children: [
                if (photos.isNotEmpty) _PhotoStrip(photos: photos),
                if (_boards.length > 1) _BoardChips(boards: _boards, selected: _selected, onSelect: (i) => setState(() => _selected = i)),
                Material(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabs,
                    labelColor: AdinnColors.red,
                    indicatorColor: AdinnColors.red,
                    unselectedLabelColor: AdinnColors.muted,
                    tabs: const [Tab(icon: Icon(Icons.architecture), text: '2D drawing'), Tab(icon: Icon(Icons.view_in_ar_outlined), text: '3D view')],
                  ),
                ),
                if (_geo[_selected].anyDefaults) _DefaultsNote(geo: _geo[_selected]),
                Expanded(
                  // Swiping sideways turns the 3D model, so the tabs change by tapping only.
                  child: TabBarView(
                    controller: _tabs,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _Drawing2D(key: ValueKey('2d-${_boards[_selected].key}'), geo: _geo[_selected], info: _info(d, _boards[_selected])),
                      _Orbit3D(key: ValueKey('3d-${_boards[_selected].key}'), geo: _geo[_selected], brand: d.project.name),
                    ],
                  ),
                ),
                _Caption(board: _boards[_selected], geo: _geo[_selected]),
              ],
            ),
    );
  }

  DrawingInfo _info(ShopDetail d, BoardItem b) {
    return DrawingInfo(
      projectName: d.project.name,
      shopName: d.title,
      shopAddress: d.address,
      boardName: '${b.name} (${b.key})',
      drawnBy: widget.drawnBy,
      date: fmtDate(DateTime.now()),
      statusLabel: d.status,
      notes: [
        'Quantity ${b.quantity}',
        '${b.sided == 'DOUBLE' ? 'Double' : 'Single'} sided, ${b.condition == 'EXISTING' ? 'existing' : 'proposed'}',
        if (b.position.trim().isNotEmpty) 'Position: ${b.position.trim()}',
        if (b.notes.trim().isNotEmpty) 'Remark: ${b.notes.trim()}',
      ],
    );
  }
}

/// The uploaded photos of the shop, small, so the drawing is read next to what was photographed.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.photos});
  final List<ShopPhoto> photos;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      height: 74,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Tooltip(
          message: photoCategoryLabel(photos[i].category),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 62,
              height: 62,
              child: appNetworkImage(photos[i].displayUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: AdinnColors.canvas, child: const Icon(Icons.broken_image_outlined, color: AdinnColors.muted))),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardChips extends StatelessWidget {
  const _BoardChips({required this.boards, required this.selected, required this.onSelect});
  final List<BoardItem> boards;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (var i = 0; i < boards.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${boards[i].name} ${boards[i].key}'),
                selected: selected == i,
                selectedColor: AdinnColors.redLight,
                labelStyle: TextStyle(fontWeight: FontWeight.w600, color: selected == i ? AdinnColors.red : AdinnColors.ink),
                side: BorderSide(color: selected == i ? AdinnColors.red : AdinnColors.line),
                onSelected: (_) => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _DefaultsNote extends StatelessWidget {
  const _DefaultsNote({required this.geo});
  final SignageGeometry geo;

  @override
  Widget build(BuildContext context) {
    final why = [
      if (geo.usingDefaults) 'the board size is not set (10 x 4 ft is drawn)',
      if (!geo.mediaSelected) 'the board type is not one of the drawing types (drawn as GSB)',
      if (!geo.installationSelected) 'the position names no fixing method (the usual one is drawn)',
    ].join('; ');
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF4E5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text('Preview only: $why. Fill the Boards tab for an exact drawing.', style: const TextStyle(fontSize: 12, color: AdinnColors.warning)),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.board, required this.geo});
  final BoardItem board;
  final SignageGeometry geo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: SafeArea(
        top: false,
        child: Text(
          '${board.name} | ${geo.installation.name} | ${fmtSize(geo.unit.fromFeet(geo.widthFt), geo.unit.fromFeet(geo.heightFt), geo.unit)} | Pinch to zoom, drag to move',
          maxLines: 2,
          style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
        ),
      ),
    );
  }
}

/// The technical drawing sheet (front and side elevation, title block, notes), zoomable.
class _Drawing2D extends StatefulWidget {
  const _Drawing2D({super.key, required this.geo, required this.info});
  final SignageGeometry geo;
  final DrawingInfo info;

  @override
  State<_Drawing2D> createState() => _Drawing2DState();
}

class _Drawing2DState extends State<_Drawing2D> {
  final _tc = TransformationController();
  Size? _fitted;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  /// Shows the whole sheet inside the viewport, centred (once per viewport size).
  void _fit(Size v) {
    if (_fitted == v || v.isEmpty) return;
    _fitted = v;
    const sheet = Drawing2DPainter.sheet;
    final s = math.min(v.width / sheet.width, v.height / sheet.height) * 0.96;
    _tc.value = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setEntry(0, 3, (v.width - sheet.width * s) / 2)
      ..setEntry(1, 3, (v.height - sheet.height * s) / 2);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fit(c.biggest);
        });
        return ColoredBox(
          color: const Color(0xFFE9EAEE),
          child: InteractiveViewer(
            key: const Key('live-drawing2d-viewer'),
            transformationController: _tc,
            constrained: false,
            minScale: 0.2,
            maxScale: 6,
            boundaryMargin: const EdgeInsets.all(600),
            child: RepaintBoundary(child: CustomPaint(size: Drawing2DPainter.sheet, painter: Drawing2DPainter(geo: widget.geo, info: widget.info, brand: widget.info.projectName))),
          ),
        );
      },
    );
  }
}

enum _View { front, side, top, iso }

/// The 3D model: drag to turn, pinch or scroll to zoom, double tap to go back to the start view, plus Front / Side / Top / Isometric.
class _Orbit3D extends StatefulWidget {
  const _Orbit3D({super.key, required this.geo, required this.brand});
  final SignageGeometry geo;
  final String brand;

  @override
  State<_Orbit3D> createState() => _Orbit3DState();
}

class _Orbit3DState extends State<_Orbit3D> {
  late final Scene _scene = SignageSceneBuilder.build(widget.geo, brand: widget.brand);
  late Camera3D _camera = _home;
  _View? _view;
  double _startZoom = 1;

  double get _face => widget.geo.isFlangeBracket ? math.pi / 2 : 0;
  Camera3D get _home => Camera3D(yaw: _face + 0.55, pitch: 0.28);

  Camera3D _preset(_View v) => switch (v) {
        _View.front => Camera3D(yaw: _face, pitch: 0),
        _View.side => Camera3D(yaw: _face == 0 ? math.pi / 2 : 0, pitch: 0),
        _View.top => Camera3D(yaw: _face, pitch: 1.55),
        _View.iso => Camera3D(yaw: math.pi / 4, pitch: math.atan(1 / math.sqrt2), ortho: true),
      };

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) setState(() => _camera = _camera.copyWith(zoom: _camera.zoom * math.exp(-e.scrollDelta.dy * 0.0015)));
            },
            child: GestureDetector(
              key: const Key('live-preview3d-viewport'),
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) => _startZoom = _camera.zoom,
              onScaleUpdate: (d) => setState(() {
                _view = null;
                if (d.pointerCount <= 1) {
                  _camera = _camera.copyWith(yaw: _camera.yaw - d.focalPointDelta.dx * 0.009, pitch: _camera.pitch + d.focalPointDelta.dy * 0.009);
                } else {
                  _camera = _camera.copyWith(zoom: _startZoom * d.scale, pan: _camera.pan + d.focalPointDelta);
                }
              }),
              onDoubleTap: () => setState(() {
                _view = null;
                _camera = _home;
              }),
              child: CustomPaint(painter: Scene3DPainter(scene: _scene, camera: _camera), child: const SizedBox.expand()),
            ),
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          top: 8,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (v, label) in [(_View.front, 'Front'), (_View.side, 'Side'), (_View.top, 'Top'), (_View.iso, 'Isometric')])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _view == v,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() {
                        _view = v;
                        _camera = _preset(v);
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
