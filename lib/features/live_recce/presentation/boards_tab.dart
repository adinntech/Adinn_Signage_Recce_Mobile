import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/input_formats.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';
import 'live_widgets.dart';

/// Boards: one card per physical board line. Same size = one line with a quantity; a different size = another line.
class BoardsTab extends StatelessWidget {
  const BoardsTab({super.key, required this.ctrl});

  final ShopDetailController ctrl;

  Future<void> _remove(BuildContext context, BoardItem b) async {
    final ok = await confirmDialog(context, title: 'Remove ${b.key}?', message: 'This board line will be removed from the recce.', confirmText: 'Remove', destructive: true);
    if (ok) ctrl.removeBoard(b);
  }

  @override
  Widget build(BuildContext context) {
    final editable = ctrl.canEdit;
    // FIX_MEASUREMENT requests that name no board (web reviewers may send them that way) cannot sit on a card: one banner for all.
    final general = ctrl.detail?.measurementReworksWithoutBoard(ctrl.boards.map((b) => b.key)) ?? const [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (general.isNotEmpty) ...[
          _MeasurementBanner(items: general),
          const SizedBox(height: 12),
        ],
        Row(children: [
          const Expanded(child: Text('Boards and sizes', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          Text('${ctrl.boards.length}/$maxBoardItems', style: const TextStyle(color: AdinnColors.muted)),
        ]),
        const SizedBox(height: 4),
        const Text('Boards of different sizes are separate lines (b1, b2, ...) so each keeps its own identity during rework.', style: TextStyle(color: AdinnColors.muted, fontSize: 13)),
        const SizedBox(height: 12),
        if (ctrl.boards.isEmpty)
          editable
              ? const _NoBoardsWarning()
              : const EmptyState(icon: Icons.view_in_ar_outlined, title: 'No boards yet', message: 'Add the boards you measured.'),
        for (final b in ctrl.boards) ...[
          _BoardCard(
            key: ValueKey(b.key),
            item: b,
            enabled: editable,
            rework: ctrl.detail?.measurementReworkFor(b.key),
            onChanged: ctrl.markDirty,
            onRemove: () => _remove(context, b),
          ),
          const SizedBox(height: 12),
        ],
        if (editable)
          OutlinedButton.icon(
            onPressed: ctrl.boards.length >= maxBoardItems ? null : ctrl.addBoard,
            icon: const Icon(Icons.add),
            label: const Text('Add board'),
          ),
      ],
    );
  }
}

/// "Measurement rework requested": the reviewer's note when it is not tied to one board.
class _MeasurementBanner extends StatelessWidget {
  const _MeasurementBanner({required this.items});

  final List<({ReworkNote note, String forBoard})> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AdinnColors.red, width: 1.6)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.flag, color: AdinnColors.red, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text('Measurement rework requested', style: TextStyle(fontWeight: FontWeight.w800, color: AdinnColors.red))),
            ]),
            for (final i in items) ...[
              const SizedBox(height: 8),
              if (i.forBoard.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('For board ${i.forBoard}', style: const TextStyle(fontSize: 12, color: AdinnColors.muted))),
              ReworkBox(note: i.note, fallback: 'The reviewer asked you to correct the measurements.'),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown when every board was removed: a save sends no boards, so the server would keep the old ones. Add one to save.
class _NoBoardsWarning extends StatelessWidget {
  const _NoBoardsWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: AdinnColors.redLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: AdinnColors.red.withValues(alpha: 0.4))),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, color: AdinnColors.red),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'No boards. A shop needs at least one board, so Save draft and Submit are blocked until you add one. '
            'Nothing is saved while the list is empty (the server keeps its earlier boards).',
          ),
        ),
      ]),
    );
  }
}

class _BoardCard extends StatefulWidget {
  const _BoardCard({super.key, required this.item, required this.enabled, this.rework, required this.onChanged, required this.onRemove});

  final BoardItem item;
  final bool enabled;

  /// The open FIX_MEASUREMENT request for this board, if the reviewer asked for the size to be corrected.
  final ReworkNote? rework;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_BoardCard> createState() => _BoardCardState();
}

class _BoardCardState extends State<_BoardCard> {
  late final _qty = TextEditingController(text: widget.item.quantity.toString());
  late final _width = TextEditingController(text: _num(widget.item.width));
  late final _height = TextEditingController(text: _num(widget.item.height));
  late final _position = TextEditingController(text: widget.item.position);
  late final _notes = TextEditingController(text: widget.item.notes);
  late final _otherName = TextEditingController(text: widget.item.name == 'Other' ? '' : widget.item.name);
  late bool _other = !boardTypes.where((t) => t != 'Other').contains(widget.item.name);

  static String _num(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  @override
  void dispose() {
    for (final c in [_qty, _width, _height, _position, _notes, _otherName]) {
      c.dispose();
    }
    super.dispose();
  }

  BoardItem get _i => widget.item;

  void _changed() => widget.onChanged();

  @override
  Widget build(BuildContext context) {
    final en = widget.enabled;
    final dropValue = _other ? 'Other' : _i.name;
    final fix = widget.rework;
    return Card(
      shape: fix == null ? null : RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AdinnColors.red, width: 1.6)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              TagChip(_i.key, icon: Icons.label_outline),
              if (fix != null) const Padding(padding: EdgeInsets.only(left: 8), child: ReworkTag(text: 'Rework: correct the size')),
              const Spacer(),
              if (en) IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, color: AdinnColors.red), onPressed: widget.onRemove),
            ]),
            if (fix != null) ...[
              const SizedBox(height: 6),
              ReworkBox(note: fix, fallback: 'The reviewer asked you to correct the size of this board.'),
              const SizedBox(height: 10),
            ],
            DropdownButtonFormField<String>(
              initialValue: dropValue,
              decoration: const InputDecoration(labelText: 'Board type *'),
              items: [for (final t in boardTypes) DropdownMenuItem(value: t, child: Text(t))],
              onChanged: en
                  ? (v) {
                      if (v == null) return;
                      setState(() {
                        _other = v == 'Other';
                        _i.name = _other ? _otherName.text.trim() : v;
                      });
                      _changed();
                    }
                  : null,
            ),
            if (_other) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _otherName,
                enabled: en,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Type name *', counterText: ''),
                onChanged: (v) {
                  _i.name = v.trim();
                  _changed();
                },
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  enabled: en,
                  keyboardType: TextInputType.number,
                  inputFormatters: digitsFormat(3),
                  decoration: const InputDecoration(labelText: 'Quantity *'),
                  onChanged: (v) {
                    _i.quantity = int.tryParse(v) ?? 0;
                    _changed();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _i.unit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items: [for (final u in boardUnits) DropdownMenuItem(value: u, child: Text(u))],
                  onChanged: en
                      ? (v) {
                          if (v == null) return;
                          _i.unit = v;
                          _changed();
                        }
                      : null,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _sizeField(_width, 'Width *', (v) => _i.width = v)),
              const SizedBox(width: 10),
              Expanded(child: _sizeField(_height, 'Height *', (v) => _i.height = v)),
            ]),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'SINGLE', label: Text('Single side')), ButtonSegment(value: 'DOUBLE', label: Text('Double side'))],
              selected: {_i.sided},
              onSelectionChanged: en
                  ? (s) {
                      setState(() => _i.sided = s.first);
                      _changed();
                    }
                  : null,
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'EXISTING', label: Text('Existing')), ButtonSegment(value: 'PROPOSED', label: Text('Proposed'))],
              selected: {_i.condition},
              onSelectionChanged: en
                  ? (s) {
                      setState(() => _i.condition = s.first);
                      _changed();
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _position,
              enabled: en,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Position (e.g. shop fascia)', counterText: ''),
              onChanged: (v) {
                _i.position = v;
                _changed();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              enabled: en,
              maxLength: 500,
              maxLines: 2,
              inputFormatters: [LengthLimitingTextInputFormatter(500)],
              decoration: const InputDecoration(labelText: 'Notes'),
              onChanged: (v) {
                _i.notes = v;
                _changed();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sizeField(TextEditingController c, String label, void Function(double?) set) => TextField(
        controller: c,
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: decimalFormat(places: 2, maxLength: 8),
        decoration: InputDecoration(labelText: label),
        onChanged: (v) {
          set(double.tryParse(v));
          _changed();
        },
      );
}
