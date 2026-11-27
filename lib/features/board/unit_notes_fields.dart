import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../../state/app_controller.dart';

/// Optional per-physical-board placement location and notes. These used to be
/// reachable only through the Unit Details screen; they now live in the Site
/// Questions step of the board editor (same stored fields, never required).
class UnitNotesFields extends StatefulWidget {
  const UnitNotesFields({
    super.key,
    required this.shopId,
    required this.board,
    required this.unit,
    required this.enabled,
  });

  final String shopId;
  final Board board;
  final SignageUnit unit;
  final bool enabled;

  @override
  State<UnitNotesFields> createState() => _UnitNotesFieldsState();
}

class _UnitNotesFieldsState extends State<UnitNotesFields> {
  late final _placement = TextEditingController(text: widget.unit.placement);
  late final _notes = TextEditingController(text: widget.unit.notes);

  @override
  void dispose() {
    _placement.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() => context.read<AppController>().touchUnit(
    widget.shopId,
    widget.board,
    widget.unit,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      children: [
        TextField(
          key: Key('unit_placement_${widget.unit.id}'),
          controller: _placement,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: context.t.placementOptional,
            isDense: true,
          ),
          onChanged: (t) {
            widget.unit.placement = t.trim();
            _save();
          },
        ),
        const SizedBox(height: 10),
        TextField(
          key: Key('unit_notes_${widget.unit.id}'),
          controller: _notes,
          enabled: widget.enabled,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: context.t.boardNotesOptional,
            isDense: true,
          ),
          onChanged: (t) {
            widget.unit.notes = t.trim();
            _save();
          },
        ),
      ],
    ),
  );
}
