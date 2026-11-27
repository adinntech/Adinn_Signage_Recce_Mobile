import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';

/// Status shown on a media tab.
enum MediaTabStatus { completed, draft, inProgress }

extension MediaTabStatusX on MediaTabStatus {
  String get label => switch (this) {
    MediaTabStatus.completed => 'Completed',
    MediaTabStatus.draft => 'Draft',
    MediaTabStatus.inProgress => 'In progress',
  };
}

MediaTabStatus mediaTabStatus(AppController c, Board b) {
  if (c.boardIssues(b).isEmpty) return MediaTabStatus.completed;
  if (c.isDraftSaved(b)) return MediaTabStatus.draft;
  return MediaTabStatus.inProgress;
}

/// Tab label: media + subtype, with the quantity when > 1. Falls back to the
/// board name when two groups would otherwise read the same.
String mediaTabLabel(Board b, List<Board> all) {
  final label = SignageCatalog.media(b.mediaCode) == null
      ? b.name
      : SignageCatalog.mediaNameLabel(b);
  final clash = all.where(
    (o) =>
        o.id != b.id &&
        SignageCatalog.media(o.mediaCode) != null &&
        SignageCatalog.mediaNameLabel(o) == label,
  );
  final base = clash.isEmpty ? label : b.name;
  return b.quantity > 1 ? '$base (${b.quantity})' : base;
}

/// Locale-aware tab label. Only the predefined media prefix is translated;
/// a custom board name is inserted unchanged. Quantity stays a parameter.
String mediaTabLabelL(BuildContext context, Board b, List<Board> all) {
  if (SignageCatalog.media(b.mediaCode) == null) return b.name;
  final label = SignageCatalog.mediaNameLabel(b);
  final clash = all.any(
    (o) =>
        o.id != b.id &&
        SignageCatalog.media(o.mediaCode) != null &&
        SignageCatalog.mediaNameLabel(o) == label,
  );
  var base = clash ? b.name : context.mediaLabel(label);
  if (clash && SignageCatalog.isAutoBoardName(base)) {
    base = context.generatedBoardName(base);
  }
  return b.quantity > 1 ? '$base (${b.quantity})' : base;
}

/// Locale-aware physical-board name (generated prefix only).
String unitNameL(BuildContext context, Board b, SignageUnit u) {
  final name = SignageCatalog.unitName(b, u);
  return SignageCatalog.isAutoBoardName(name)
      ? context.generatedBoardName(name)
      : name;
}

/// Horizontally scrollable media-group tabs at the top of the editor. Each
/// tab is a media group (Board) identified by its stable id.
class MediaTabs extends StatefulWidget {
  const MediaTabs({
    super.key,
    required this.controller,
    required this.boards,
    required this.currentId,
    required this.onSelect,
    this.onAdd,
  });

  final AppController controller;
  final List<Board> boards;
  final String currentId;
  final ValueChanged<Board> onSelect;

  /// Compact "+" after the last tab (null = hidden, e.g. read-only).
  final VoidCallback? onAdd;

  @override
  State<MediaTabs> createState() => _MediaTabsState();
}

class _MediaTabsState extends State<MediaTabs> {
  final _selectedKey = GlobalKey();
  String? _ensuredFor;

  /// Bring the selected group into view once per selection change, never on
  /// every rebuild (so locale/state changes don't cause repeated scrolling).
  void _ensureSelectedVisible() {
    if (_ensuredFor == widget.currentId) return;
    _ensuredFor = widget.currentId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, alignment: 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _ensureSelectedVisible();
    return SizedBox(
      height: 58,
      child: ListView.separated(
        key: const Key('media_tabs'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        itemCount: widget.boards.length + (widget.onAdd == null ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == widget.boards.length) {
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: const Key('media_tab_add'),
                borderRadius: BorderRadius.circular(10),
                onTap: widget.onAdd,
                child: Container(
                  width: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AdinnColors.red),
                  ),
                  child: const Icon(Icons.add, color: AdinnColors.red),
                ),
              ),
            );
          }
          final b = widget.boards[i];
          final sel = b.id == widget.currentId;
          final st = mediaTabStatus(widget.controller, b);
          return SizedBox(
            key: sel ? _selectedKey : null,
            child: Material(
              color: sel ? AdinnColors.red : Colors.white,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: Key('media_tab_${b.id}'),
                borderRadius: BorderRadius.circular(10),
                onTap: sel ? null : () => widget.onSelect(b),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel ? AdinnColors.red : AdinnColors.line,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mediaTabLabelL(context, b, widget.boards),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: sel ? Colors.white : AdinnColors.ink,
                            ),
                          ),
                          Text(
                            context.ui(st.label),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: sel
                                  ? Colors.white70
                                  : st == MediaTabStatus.completed
                                  ? AdinnColors.success
                                  : AdinnColors.muted,
                            ),
                          ),
                        ],
                      ),
                      if (st == MediaTabStatus.completed) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: sel ? Colors.white : AdinnColors.success,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Physical boards of one media group ("GSB Single 01 | GSB Single 02"):
/// name, size, own installation and pending count. Identified by unit id.
class UnitSelector extends StatelessWidget {
  const UnitSelector({
    super.key,
    required this.board,
    required this.selectedId,
    required this.pendingOf,
    required this.onSelect,
    this.keyPrefix = 'unit_chip',
  });

  final Board board;
  final String selectedId;
  final int Function(SignageUnit u) pendingOf;
  final ValueChanged<SignageUnit> onSelect;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final u in board.activeUnits) ...[
            _chip(context, u),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, SignageUnit u) {
    final sel = u.id == selectedId;
    final pending = pendingOf(u);
    final inst = SignageCatalog.installation(board.installationOf(u));
    final size = board.unitHasSize(u)
        ? '${_n(board.widthOf(u)!)} × ${_n(board.heightOf(u)!)} '
              '${board.unit.label}'
        : context.ui('Size pending');
    return Material(
      color: sel ? AdinnColors.redLight : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: Key('${keyPrefix}_${u.id}'),
        borderRadius: BorderRadius.circular(10),
        onTap: sel ? null : () => onSelect(u),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: sel ? AdinnColors.red : AdinnColors.line,
              width: sel ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    unitNameL(context, board, u),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    pending == 0 ? Icons.check_circle : Icons.error_outline,
                    size: 15,
                    color: pending == 0
                        ? AdinnColors.success
                        : AdinnColors.warning,
                  ),
                ],
              ),
              Text(
                '$size · ${context.installationLabel(inst?.name ?? context.ui('Installation pending'))}'
                '${pending == 0 ? '' : ' · ${context.uf('{0} pending', [pending])}'}',
                style: const TextStyle(fontSize: 11, color: AdinnColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(2);
}

/// "Save as Draft?" prompt. Returns true for Save & Continue.
Future<bool> showSaveDraftDialog(
  BuildContext context, {
  required String from,
  required String to,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.ui('Save as Draft?')),
      content: Text(
        '$from is not completed. Save your progress as a draft before '
        'switching to $to.',
      ),
      actions: [
        TextButton(
          key: const Key('draft_stay'),
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.ui('Stay Here')),
        ),
        FilledButton(
          key: const Key('draft_save'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(context.ui('Save & Continue')),
        ),
      ],
    ),
  );
  return r ?? false;
}
