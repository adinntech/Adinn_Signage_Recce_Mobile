import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/measurement_fields.dart';
import '../../state/app_controller.dart';
import 'signage_spec.dart';
import 'technical_drawing.dart';
import '../../core/widgets/adinn_app_bar.dart';

/// 2D technical views (front, side, top, installation schematic) of one
/// signage item, generated from the same canonical spec as the 3D model,
/// so values can never contradict each other.
class TechnicalDrawingScreen extends StatefulWidget {
  const TechnicalDrawingScreen({
    super.key,
    required this.shopId,
    required this.boardId,
    required this.unitId,
  });

  final String shopId;
  final String boardId;
  final String unitId;

  @override
  State<TechnicalDrawingScreen> createState() => _TechnicalDrawingScreenState();
}

class _TechnicalDrawingScreenState extends State<TechnicalDrawingScreen> {
  DrawingView _view = DrawingView.front;
  bool _dims = true;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final b = c.board(widget.shopId, widget.boardId);
    final u = b?.unitById(widget.unitId);
    if (b == null || u == null) {
      return Scaffold(
        appBar: AdinnAppBar(),
        body: const EmptyState(icon: Icons.search_off, title: 'Item not found'),
      );
    }
    final spec = SignageModelSpec.of(b, u);
    final dims = drawingDimensions(spec, _view);
    return Scaffold(
      appBar: AdinnAppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.ui('2D Technical Drawing')),
            Text(
              '${b.name} · ${b.unitLabel(u)} · ${spec.media?.shortName ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('drawing_dims_toggle'),
            tooltip: _dims ? 'Hide dimensions' : 'Show dimensions',
            icon: Icon(
              Icons.straighten,
              color: _dims ? AdinnColors.red : AdinnColors.muted,
            ),
            onPressed: () => setState(() => _dims = !_dims),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                for (final v in DrawingView.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: Key('drawing_view_${v.name}'),
                      label: Text(v.label),
                      selected: _view == v,
                      onSelected: (_) => setState(() => _view = v),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 3 / 2,
                  child: CustomPaint(
                    key: const Key('technical_drawing'),
                    painter: TechnicalDrawingPainter(
                      spec: spec,
                      view: _view,
                      showDimensions: _dims,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            color: Colors.white,
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              children: [
                for (final d in dims)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${d.label}'
                          '${d.field != null && spec.isAssumed(d.field!) ? ' (not measured)' : ''}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      Text(
                        fmtMm(d.valueMm, spec.displayUnit),
                        key: Key('drawing_dim_${d.id}'),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                Text(context.ui('Illustrative schematic generated from the recce '
                  'measurements – not a fabrication-certified structural '
                  'drawing.'),
                  style: TextStyle(fontSize: 11, color: AdinnColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
