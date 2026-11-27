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
import '../../data/catalog/question_equivalence.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../../state/app_controller.dart';
import '../preview3d/preview_3d_screen.dart';
import 'drawing_2d_painter.dart';
import 'signage_geometry.dart';
import '../../core/widgets/adinn_app_bar.dart';

/// Default 2D technical drawing generated from the board's recce data.
class Drawing2DScreen extends StatefulWidget {
  const Drawing2DScreen({
    super.key,
    required this.shopId,
    required this.boardId,
    this.unitId,
  });

  final String shopId;
  final String boardId;

  /// Physical board to draw (default: the group's first board).
  final String? unitId;

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
    final unit = board.unitById(widget.unitId) ??
        SignageCatalog.firstUnit(board);
    final questions = unit == null
        ? SignageCatalog.questionsFor(board.mediaCode, board.installationCode)
        : SignageCatalog.questionsForUnit(board, unit);
    // This board's own final answers (never another board's).
    final answers = unit == null
        ? SignageCatalog.answersOf(board, unit)
        : QuestionEquivalence.effectiveSiteAnswers(board, unit);
    final gps = shop.geo;
    final siteRemarks = unit?.checklist['checklist_remarks']?.value;
    final notes = <String>[
      if (gps != null) 'GPS ${gps.coordinates} (±${gps.accuracyM.round()} m)',
      if (shop.gstNumber.isNotEmpty) 'GST No. ${shop.gstNumber}',
      for (final q in questions)
        if (q.isVisible(answers) && q.isAnswered(answers))
          '${context.tq(q.label)} ${_answer(q, answers[q.id])}',
      if (siteRemarks is String && siteRemarks.trim().isNotEmpty)
        'Additional site remarks: ${siteRemarks.trim()}',
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
      summaryTitle: context.isTamil
          ? context.t.siteDetailsSummary
          : 'SITE DETAILS SUMMARY',
    );
  }

  /// Answer wording for the sheet: Tamil for Yes / No and predefined
  /// options; numbers, units and typed text stay as entered.
  String _answer(SiteQuestion q, Object? v) {
    if (!context.isTamil) return SignageCatalog.answerText(q, v);
    if (v is bool) return v ? context.t.yes : context.t.no;
    if (q.type == QuestionType.choice && v is String) return context.tq(v);
    return SignageCatalog.answerText(q, v);
  }

  bool _referencedInSnapshots(Shop shop, String path) =>
      shop.submissions.any((s) => jsonEncode(s.snapshot).contains(path));

  Future<void> _savePng(AppController c, Shop shop, Board board) async {
    final media = c.media;
    if (media == null) {
      showSnack(
        context,
        context.ui('Local storage is not available – drawing not saved'),
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
      if (mounted) showSnack(context, context.ui('Drawing saved to device storage'));
    } catch (e) {
      if (mounted) {
        showSnack(context, context.uf('Could not save drawing: {0}', [e]), error: true);
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
        appBar: AdinnAppBar(title: Text(context.ui('2D Drawing'))),
        body: const EmptyState(
          icon: Icons.architecture,
          title: 'Board not found',
          message: 'It may have been removed from this shop.',
        ),
      );
    }

    final geo = SignageGeometry.fromBoard(
      board,
      unit: board.unitById(widget.unitId),
    );
    final missingSelection = !geo.mediaSelected || !geo.installationSelected;
    final canEdit = c.canEdit(shop);
    final showDrawing = !missingSelection || _useDefaults;

    return Scaffold(
      appBar: AdinnAppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.ui('2D Drawing')),
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
              tooltip: context.ui('Fit to screen'),
              icon: const Icon(Icons.fit_screen_outlined),
              onPressed: _fit,
            ),
          IconButton(
            tooltip: context.ui('3D view'),
            icon: const Icon(Icons.view_in_ar_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Preview3DScreen(
                  shopId: widget.shopId,
                  boardId: widget.boardId,
                  unitId: widget.unitId,
                ),
              ),
            ),
          ),
          if (showDrawing && canEdit)
            IconButton(
              tooltip: context.ui('Save PNG'),
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
                label: Text(context.ui('Preview with defaults')),
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
                    child: Text(context.ui('Default preview – some board details are missing, '
                      'assumed values are marked in the site notes.'),
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
                // The sheet's notes column fits 11 lines; every answered
                // question stays readable in full here (wrapped, scrollable).
                Builder(
                  builder: (_) {
                    final info = _info(c, shop, board);
                    if (info.notes.length <= 8) return const SizedBox.shrink();
                    return Material(
                      color: Colors.white,
                      child: ExpansionTile(
                        key: const Key('all_site_notes'),
                        title: Text(
                          '${info.summaryTitle} (${info.notes.length})',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView(
                              shrinkWrap: true,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              children: [
                                for (final n in info.notes)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '• $n',
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
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
