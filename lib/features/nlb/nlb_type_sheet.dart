import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../gsb/gsb_type_sheet.dart' show BoardTypeCard;
import 'nlb_rules.dart';

/// "Select NLB Board Type" sheet shown when the vendor taps the NLB media
/// card. Returns the chosen [NlbVariant], or null when cancelled (the recce
/// is then left exactly as it was).
Future<NlbVariant?> showNlbTypeSheet(
  BuildContext context, {
  NlbVariant? initial,
}) => showModalBottomSheet<NlbVariant>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => NlbTypeSheet(initial: initial),
);

class NlbTypeSheet extends StatefulWidget {
  const NlbTypeSheet({super.key, this.initial});

  /// Previously saved choice (restored). Null for a new NLB group or a
  /// legacy NLB record without a subtype.
  final NlbVariant? initial;

  @override
  State<NlbTypeSheet> createState() => _NlbTypeSheetState();
}

class _NlbTypeSheetState extends State<NlbTypeSheet> {
  NlbVariant? _selected;

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
            Text(context.ui('Select NLB Board Type'),
              key: Key('nlb_type_title'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            BoardTypeCard(
              key: const Key('nlb_type_single'),
              icon: Icons.crop_landscape,
              title: NlbVariant.singleFrame.label,
              selected: _selected == NlbVariant.singleFrame,
              onTap: () => setState(() => _selected = NlbVariant.singleFrame),
            ),
            const SizedBox(height: 10),
            BoardTypeCard(
              key: const Key('nlb_type_box'),
              icon: Icons.inventory_2_outlined,
              title: NlbVariant.boxFrame.label,
              selected: _selected == NlbVariant.boxFrame,
              onTap: () => setState(() => _selected = NlbVariant.boxFrame),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('nlb_type_cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.ui('Cancel')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const Key('nlb_type_continue'),
                    onPressed: _selected == null
                        ? null
                        : () => Navigator.of(context).pop(_selected),
                    child: Text(context.ui('Continue')),
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
