import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../preview3d/preview_3d_screen.dart';
import 'drawing_2d_painter.dart';
import 'signage_geometry.dart';

/// Default 2D technical drawing generated from the board's recce data.
class Drawing2DScreen extends StatefulWidget {
  const Drawing2DScreen({
    super.key,
    required this.shopId,
    required this.boardId,
  });

  final String shopId;
  final String boardId;

  @override
  State<Drawing2DScreen> createState() => _Drawing2DScreenState();
}

class _Drawing2DScreenState extends State<Drawing2DScreen> {
  final _tc = TransformationController();
  final _boundaryKey = GlobalKey();
  Size? _viewport;
  bool _fitScheduled = false;
  bool _saving = false;
  bool _useDefaults = false;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _fit() {
    final v = _viewport;
    if (v == null || v.isEmpty) return;
    const sheet = Drawing2DPainter.sheet;
    final s = math.min(v.width / sheet.width, v.height / sheet.height) * 0.96;
    final dx = (v.width - sheet.width * s) / 2;
    final dy = (v.height - sheet.height * s) / 2;
    _tc.value = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setEntry(0, 3, dx)
      ..setEntry(1, 3, dy);
  }

  void _scheduleFit(Size viewport) {
    if (_viewport == viewport && _fitScheduled) return;
    _viewport = viewport;
    _fitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fit();
    });
  }

  DrawingInfo _info(AppController c, Shop shop, Board board) {
    final questions = SignageCatalog.questionsFor(
      board.mediaCode,
      board.installationCode,
    );
    final gps = shop.geo;
    final notes = <String>[
      if (gps != null) 'GPS ${gps.coordinates} (±${gps.accuracyM.round()} m)',
      for (final q in questions)
        if (q.isVisible(board.answers) && q.isAnswered(board.answers))
          '${q.label} ${SignageCatalog.answerText(q, board.answers[q.id])}',
      if (board.textNote.trim().isNotEmpty) 'Remark: ${board.textNote.trim()}',
    ];
    return DrawingInfo(
      projectName: c.project(shop.projectId)?.name ?? '',
      shopName: shop.name,
      shopAddress: shop.fullAddress,
      boardName: board.name,
      drawnBy: c.currentUser?.name ?? '—',
      date: fmtDate(DateTime.now()),
      statusLabel: shop.status.label,
      notes: notes,
    );
  }

  bool _referencedInSnapshots(Shop shop, String path) =>
      shop.submissions.any((s) => jsonEncode(s.snapshot).contains(path));

  Future<void> _savePng(AppController c, Shop shop, Board board) async {
    final media = c.media;
    if (media == null) {
      showSnack(
        context,
        'Local storage is not available – drawing not saved',
        error: true,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Drawing is not ready yet');
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Could not encode PNG');
      final path = await media.newFilePath('drawings', 'png');
      await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      final old = board.drawingPath;
      board.drawingPath = path;
      c.touchBoard(
        shop.id,
        board,
        title: 'Drawing saved',
        message: '2D drawing of ${board.name} saved as PNG.',
      );
      if (old != null && old != path && !_referencedInSnapshots(shop, old)) {
        await media.deleteIfExists(old);
      }
      if (mounted) showSnack(context, 'Drawing saved to device storage');
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Could not save drawing: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(widget.shopId);
    final board = c.board(widget.shopId, widget.boardId);
    if (shop == null || board == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('2D Drawing')),
        body: const EmptyState(
          icon: Icons.architecture,
          title: 'Board not found',
          message: 'It may have been removed from this shop.',
        ),
      );
    }

    final geo = SignageGeometry.fromBoard(board);
    final missingSelection = !geo.mediaSelected || !geo.installationSelected;
    final canEdit = c.canEdit(shop);
    final showDrawing = !missingSelection || _useDefaults;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('2D Drawing'),
            Text(
              board.drawingPath == null
                  ? board.name
                  : '${board.name} · PNG saved',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AdinnColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          if (showDrawing)
            IconButton(
              tooltip: 'Fit to screen',
              icon: const Icon(Icons.fit_screen_outlined),
              onPressed: _fit,
            ),
          IconButton(
            tooltip: '3D view',
            icon: const Icon(Icons.view_in_ar_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Preview3DScreen(
                  shopId: widget.shopId,
                  boardId: widget.boardId,
                ),
              ),
            ),
          ),
          if (showDrawing && canEdit)
            IconButton(
              tooltip: 'Save PNG',
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt),
              onPressed: _saving ? null : () => _savePng(c, shop, board),
            ),
        ],
      ),
      body: !showDrawing
          ? EmptyState(
              icon: Icons.architecture,
              title: 'Drawing needs board details',
              message:
                  'Select the ${[if (!geo.mediaSelected) 'media type', if (!geo.installationSelected) 'installation type'].join(' and ')} '
                  'for ${board.name} to generate its default 2D drawing.',
              action: OutlinedButton.icon(
                onPressed: () => setState(() => _useDefaults = true),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Preview with defaults'),
              ),
            )
          : Column(
              children: [
                if (geo.anyDefaults)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFFFF4E5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: const Text(
                      'Default preview – some board details are missing, '
                      'assumed values are marked in the site notes.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AdinnColors.warning,
                      ),
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _scheduleFit(constraints.biggest);
                      return ColoredBox(
                        color: const Color(0xFFE9EAEE),
                        child: InteractiveViewer(
                          key: const Key('drawing2d-viewer'),
                          transformationController: _tc,
                          constrained: false,
                          minScale: 0.2,
                          maxScale: 6,
                          boundaryMargin: const EdgeInsets.all(600),
                          child: RepaintBoundary(
                            key: _boundaryKey,
                            child: CustomPaint(
                              size: Drawing2DPainter.sheet,
                              painter: Drawing2DPainter(
                                geo: geo,
                                info: _info(c, shop, board),
                                brand: c.project(shop.projectId)?.name ?? '',
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: SafeArea(
                    top: false,
                    child: Text(
                      '${geo.media.shortName} · ${geo.installation.name} · '
                      '${fmtSize(geo.unit.fromFeet(geo.widthFt), geo.unit.fromFeet(geo.heightFt), geo.unit)} · '
                      'Pinch to zoom, drag to pan',
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdinnColors.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
