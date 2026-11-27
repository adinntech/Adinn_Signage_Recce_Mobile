import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../drawing/drawing_2d_screen.dart';
import '../preview3d/preview_3d_screen.dart';

/// What the vendor wants to open for the chosen physical board(s).
enum BoardView { drawing2d, preview3d, cameraAr }

extension BoardViewX on BoardView {
  String get title => switch (this) {
    BoardView.drawing2d => 'Select Boards for 2D Drawing',
    BoardView.preview3d => 'Select Boards for 3D Preview',
    BoardView.cameraAr => 'Which board for Camera AR?',
  };

  String get action => switch (this) {
    BoardView.drawing2d => 'View 2D Drawing',
    BoardView.preview3d => 'View 3D Preview',
    BoardView.cameraAr => 'Open Camera AR',
  };

  /// Camera AR places ONE board at a time (never all at the same spot).
  bool get allowsAll => this != BoardView.cameraAr;
}

/// Bottom sheet that lists the actual physical boards of [board]. Boards that
/// are not ready are disabled with their own pending reason; "Both Boards" /
/// "All Boards" is enabled only when every board is ready. Returns the chosen
/// unit ids (null = cancelled).
Future<List<String>?> showBoardPicker(
  BuildContext context, {
  required Board board,
  required BoardView view,
}) {
  final units = board.activeUnits;
  final blockers = {
    for (final u in units) u.id: SignageCatalog.unitDrawingBlocker(board, u),
  };
  final allReady = blockers.values.every((b) => b == null);
  final firstReady = units
      .where((u) => blockers[u.id] == null)
      .map((u) => u.id)
      .firstOrNull;
  String? choice = firstReady;
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  view.title,
                  key: const Key('board_picker_title'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Flexible(
                child: RadioGroup<String>(
                  groupValue: choice,
                  onChanged: (v) => set(() => choice = v),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final u in units)
                        Opacity(
                          opacity: blockers[u.id] == null ? 1 : 0.5,
                          child: RadioListTile<String>(
                            key: Key('pick_unit_${u.id}'),
                            value: u.id,
                            enabled: blockers[u.id] == null,
                            title: Text(SignageCatalog.unitName(board, u)),
                            subtitle: Text(
                              blockers[u.id] ??
                                  '${fmtSize(board.widthOf(u), board.heightOf(u), board.unit)}'
                                      ' · ${SignageCatalog.installation(board.installationOf(u))?.name ?? '—'}',
                            ),
                          ),
                        ),
                      if (view.allowsAll)
                        Opacity(
                          opacity: allReady ? 1 : 0.5,
                          child: RadioListTile<String>(
                            key: const Key('pick_all'),
                            value: 'all',
                            enabled: allReady,
                            title: Text(
                              units.length == 2 ? 'Both Boards' : 'All Boards',
                            ),
                            subtitle: Text(
                              allReady
                                  ? 'Switch between the boards in one viewer.'
                                  : 'Every board must be ready first.',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    TextButton(
                      key: const Key('pick_cancel'),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(context.ui('Cancel')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        key: const Key('pick_go'),
                        onPressed: choice == null
                            ? null
                            : () => Navigator.pop(ctx, [
                                if (choice == 'all')
                                  for (final u in units) u.id
                                else
                                  choice!,
                              ]),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(view.action),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Opens the chosen boards: ONE board straight into the existing viewer;
/// several boards into a viewer with a board selector. Only the active
/// board's viewer is built (others are disposed).
Route<void> boardViewerRoute({
  required String shopId,
  required String boardId,
  required BoardView view,
  required List<String> unitIds,
  Board? board,
}) {
  if (unitIds.length == 1) {
    return MaterialPageRoute<void>(
      builder: (_) => _single(shopId, boardId, view, unitIds.first),
    );
  }
  return MaterialPageRoute<void>(
    builder: (_) => BoardViewerShell(
      shopId: shopId,
      boardId: boardId,
      view: view,
      unitIds: unitIds,
      board: board,
    ),
  );
}

Widget _single(String shopId, String boardId, BoardView view, String unitId) =>
    switch (view) {
      BoardView.preview3d => Preview3DScreen(
        shopId: shopId,
        boardId: boardId,
        unitId: unitId,
      ),
      _ => Drawing2DScreen(shopId: shopId, boardId: boardId, unitId: unitId),
    };

/// Existing 2D / 3D viewer for the active board plus a selector at the
/// bottom ("GSB Single 01 | GSB Single 02"). Each board keeps its own
/// geometry, size and installation; switching rebuilds the viewer for the
/// newly selected board only.
class BoardViewerShell extends StatefulWidget {
  const BoardViewerShell({
    super.key,
    required this.shopId,
    required this.boardId,
    required this.view,
    required this.unitIds,
    this.board,
  });

  final String shopId;
  final String boardId;
  final BoardView view;
  final List<String> unitIds;

  /// Board used for the selector labels (looked up when null).
  final Board? board;

  @override
  State<BoardViewerShell> createState() => _BoardViewerShellState();
}

class _BoardViewerShellState extends State<BoardViewerShell> {
  late String _active = widget.unitIds.first;

  @override
  Widget build(BuildContext context) {
    final names = _labels(context);
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: KeyedSubtree(
              key: ValueKey('viewer_$_active'),
              child: _single(widget.shopId, widget.boardId, widget.view, _active),
            ),
          ),
          Material(
            elevation: 6,
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                key: const Key('viewer_board_bar'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    for (final id in widget.unitIds) ...[
                      ChoiceChip(
                        key: Key('viewer_chip_$id'),
                        label: Text(names[id] ?? id),
                        selected: id == _active,
                        selectedColor: AdinnColors.redLight,
                        onSelected: (_) => setState(() => _active = id),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, String> _labels(BuildContext context) {
    final b = widget.board;
    if (b == null) return const {};
    return {
      for (final u in b.activeUnits) u.id: SignageCatalog.unitName(b, u),
    };
  }
}
