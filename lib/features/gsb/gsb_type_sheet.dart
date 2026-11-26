import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'gsb_rules.dart';

/// "Select GSB Board Type" bottom sheet shown when the vendor taps the GSB
/// media card. Returns the chosen [GsbVariant], or null when cancelled (the
/// recce is then left exactly as it was).
Future<GsbVariant?> showGsbTypeSheet(
  BuildContext context, {
  GsbVariant? initial,
}) => showModalBottomSheet<GsbVariant>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => GsbTypeSheet(initial: initial),
);

class GsbTypeSheet extends StatefulWidget {
  const GsbTypeSheet({super.key, this.initial});

  /// Previously saved choice (restored, never silently replaced). Null for
  /// a new GSB group or an older record without an explicit choice.
  final GsbVariant? initial;

  @override
  State<GsbTypeSheet> createState() => _GsbTypeSheetState();
}

class _GsbTypeSheetState extends State<GsbTypeSheet> {
  GsbVariant? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select GSB Board Type',
              key: Key('gsb_type_title'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose how many advertising faces this glow sign board has. '
              'Quantity still counts physical boards.',
              style: TextStyle(fontSize: 12.5, color: AdinnColors.muted),
            ),
            const SizedBox(height: 14),
            BoardTypeCard(
              key: const Key('gsb_type_single'),
              icon: Icons.crop_landscape,
              title: GsbVariant.single.label,
              selected: _selected == GsbVariant.single,
              onTap: () => setState(() => _selected = GsbVariant.single),
            ),
            const SizedBox(height: 10),
            BoardTypeCard(
              key: const Key('gsb_type_double'),
              icon: Icons.flip,
              title: GsbVariant.double.label,
              selected: _selected == GsbVariant.double,
              onTap: () => setState(() => _selected = GsbVariant.double),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('gsb_type_cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const Key('gsb_type_continue'),
                    onPressed: _selected == null
                        ? null
                        : () => Navigator.of(context).pop(_selected),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact selectable card (icon + name + radio) shared by the GSB and NLB
/// board-type sheets.
class BoardTypeCard extends StatelessWidget {
  const BoardTypeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: Material(
        color: selected ? AdinnColors.redLight : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AdinnColors.red : AdinnColors.line,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, color: AdinnColors.red, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AdinnColors.ink,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? AdinnColors.red : AdinnColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
