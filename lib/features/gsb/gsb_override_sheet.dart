import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/length_input.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import 'gsb_rules.dart';

const kGsbOverrideReasons = [
  'Site clearance restriction',
  'Wall obstruction',
  'Existing structure limitation',
  'Client-requested depth',
  'Installation access restriction',
];

/// Edit / Override workflow for the approved GSB depth / frame spec.
/// Saving records a provisional override that "Requires Engineering
/// Review" – it never approves anything.
Future<void> showGsbOverrideSheet(
  BuildContext context, {
  required String shopId,
  required Board board,
  required SignageUnit unit,
  required GsbFabricationPlan plan,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: _GsbOverrideSheet(
      shopId: shopId,
      board: board,
      unit: unit,
      plan: plan,
    ),
  ),
);

class _GsbOverrideSheet extends StatefulWidget {
  const _GsbOverrideSheet({
    required this.shopId,
    required this.board,
    required this.unit,
    required this.plan,
  });

  final String shopId;
  final Board board;
  final SignageUnit unit;
  final GsbFabricationPlan plan;

  @override
  State<_GsbOverrideSheet> createState() => _GsbOverrideSheetState();
}

class _GsbOverrideSheetState extends State<_GsbOverrideSheet> {
  GsbOverrideField _field = GsbOverrideField.depth;
  final _value = TextEditingController();
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// Current effective value (null = unspecified).
  double? _current(GsbOverrideField f) {
    final i = widget.plan.input;
    return switch (f) {
      GsbOverrideField.depth => i.depthIn,
      GsbOverrideField.profileWidth => i.profileWidthIn,
      GsbOverrideField.profileHeight => i.profileHeightIn,
      GsbOverrideField.wallThickness => i.wallThicknessIn,
    };
  }

  double? _default(GsbOverrideField f) => switch (f) {
    GsbOverrideField.depth => GsbSpec.depthIn,
    GsbOverrideField.profileWidth => GsbSpec.profileWidthIn,
    GsbOverrideField.profileHeight => GsbSpec.profileHeightIn,
    GsbOverrideField.wallThickness => GsbSpec.wallThicknessIn,
  };

  String _fmt(double? v) => v == null ? 'Unspecified' : '${fmtNum(v)} in';

  void _save() {
    final ft = parseLengthToFeet(_value.text, MeasureUnit.inch);
    final proposed = ft == null ? null : ft * 12;
    String? err;
    if (proposed == null) {
      err = 'Enter the proposed value in inches (e.g. 6 or 6 1/2)';
    } else if (proposed <= 0) {
      err = '${_field.label} must be greater than zero';
    } else {
      // Physical sanity checks against the other frame values.
      final i = widget.plan.input;
      final profile = _field == GsbOverrideField.profileWidth
          ? proposed
          : i.profileWidthIn;
      final depth = _field == GsbOverrideField.depth ? proposed : i.depthIn;
      if (depth <= 2 * profile) {
        err =
            'Depth must exceed the front + rear frame profile '
            '(${fmtNum(2 * profile)} in).';
      } else if (_field == GsbOverrideField.wallThickness &&
          proposed * 2 >= i.profileWidthIn) {
        err = 'Wall thickness must be less than half the profile size.';
      }
    }
    err ??= context.read<AppController>().addGsbOverride(
      widget.shopId,
      widget.board,
      unitId: widget.unit.id,
      field: _field,
      originalIn: _current(_field),
      proposedIn: proposed!,
      reason: _reason.text,
      ruleVersion: kGsbRuleVersion,
    );
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.of(context).pop();
    showSnack(
      context,
      context.uf('{0} override saved – Requires Engineering Review', [_field.label]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _current(_field);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.ui('Edit / Override GSB specification'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<GsbOverrideField>(
              key: const Key('gsb_ov_field'),
              initialValue: _field,
              decoration: InputDecoration(labelText: context.ui('Specification')),
              items: [
                for (final f in GsbOverrideField.values)
                  DropdownMenuItem(value: f, child: Text(context.ui(f.label))),
              ],
              onChanged: (f) => setState(() {
                _field = f ?? _field;
                _error = null;
              }),
            ),
            const SizedBox(height: 10),
            InfoRow('Approved default', _fmt(_default(_field))),
            InfoRow('Current value', _fmt(current)),
            if (_field == GsbOverrideField.wallThickness)
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(context.ui('Wall thickness is not given in the rulebook. Changing it '
                  'never changes the outside profile size.'),
                  style: TextStyle(fontSize: 11.5, color: AdinnColors.muted),
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('gsb_ov_value'),
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: context.ui('Proposed value'),
                suffixText: 'in',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('gsb_ov_reason'),
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: context.ui('Reason (required)'),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final r in kGsbOverrideReasons)
                  ActionChip(
                    label: Text(r, style: const TextStyle(fontSize: 11.5)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _reason.text = r),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(context.ui('Status after saving: Requires Engineering Review. The 3D '
                'preview shows the change provisionally; it is not '
                'fabrication-approved. The original default and the full '
                'override history are kept and the change can be reverted.'),
                style: TextStyle(fontSize: 11.5, color: AdinnColors.warning),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('gsb_ov_error'),
                  style: const TextStyle(color: AdinnColors.red),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.ui('Cancel')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const Key('gsb_ov_save'),
                    onPressed: _save,
                    child: Text(context.ui('Save for review')),
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
