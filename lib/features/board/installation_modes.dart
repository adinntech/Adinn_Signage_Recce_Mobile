import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';

/// "Same Installation" / "Different Installations" switch shown when a media
/// group has more than one physical board.
class InstallationModeSwitch extends StatelessWidget {
  const InstallationModeSwitch({
    super.key,
    required this.different,
    required this.enabled,
    required this.onChanged,
  });

  final bool different;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SegmentedButton<bool>(
        key: const Key('inst_mode_selector'),
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: false,
            label: Text(context.ui('Same Installation'), key: Key('inst_mode_same')),
          ),
          ButtonSegment(
            value: true,
            label: Text(context.ui('Different Installations'), key: Key('inst_mode_diff')),
          ),
        ],
        selected: {different},
        onSelectionChanged: enabled ? (s) => onChanged(s.first) : null,
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AdinnColors.redLight,
          selectedForegroundColor: AdinnColors.ink,
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// One installation selector per physical board. Every selection is stored
/// on that board's own unit (never on the group or another unit).
class UnitInstallationPicker extends StatelessWidget {
  const UnitInstallationPicker({
    super.key,
    required this.board,
    required this.choices,
    required this.enabled,
    required this.onPick,
  });

  final Board board;
  final List<InstallationChoice> choices;
  final bool enabled;
  final void Function(SignageUnit unit, String code) onPick;

  @override
  Widget build(BuildContext context) {
    final persistable = [
      for (final c in choices)
        if (c.code != null) c,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final u in board.activeUnits)
          Container(
            key: Key('unit_inst_card_${u.id}'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdinnColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  SignageCatalog.unitName(board, u),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  board.unitHasSize(u)
                      ? fmtSize(board.widthOf(u), board.heightOf(u), board.unit)
                      : 'Size not entered',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdinnColors.muted,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final c in persistable)
                      ChoiceChip(
                        key: Key('unit_inst_${u.id}_${c.code}'),
                        avatar: c.icon == null ? null : Icon(c.icon, size: 18),
                        label: Text(c.name),
                        selected: board.installationOf(u) == c.code,
                        onSelected: enabled ? (_) => onPick(u, c.code!) : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Reviews and applies "Copy Common Answers". Returns the number of answers
/// copied (0 when cancelled).
/// Source / target are physical boards: (media group, unit).
Future<int> showCopyCommonAnswersSheet(
  BuildContext context, {
  required (Board, SignageUnit) target,
  required List<(Board, SignageUnit)> candidates,
  required int Function((Board, SignageUnit) source, bool overwrite) onCopy,
}) async {
  final (tb, tu) = target;
  final sources = [
    for (final c in candidates)
      if (!(c.$1.id == tb.id && c.$2.id == tu.id) &&
          SignageCatalog.media(c.$1.mediaCode) != null)
        c,
  ];
  if (sources.isEmpty) return 0;
  var source = sources.first;
  var overwrite = false;
  String label((Board, SignageUnit) c) =>
      '${SignageCatalog.unitName(c.$1, c.$2)} · '
      '${SignageCatalog.installation(c.$1.installationOf(c.$2))?.name ?? '—'}';
  final n = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final plan = SignageCatalog.planUnitAnswers(
          source.$1,
          source.$2,
          tb,
          tu,
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.ui('Copy Common Answers'),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  key: const Key('copy_source'),
                  initialValue: sources.indexOf(source),
                  isExpanded: true,
                  decoration: InputDecoration(labelText: context.ui('Copy from')),
                  items: [
                    for (var i = 0; i < sources.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          label(sources[i]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) =>
                      set(() => source = v == null ? source : sources[v]),
                ),
                const SizedBox(height: 4),
                Text(context.uf('Copy to: {0}', [label(target)]),
                    style: const TextStyle(color: AdinnColors.muted)),
                const SizedBox(height: 12),
                _line(
                  'Will be copied (empty at target)',
                  plan.toCopy.length + plan.toCopyChecklist.length,
                ),
                _line(
                  'Already answered at target',
                  plan.wouldOverwrite.length + plan.wouldOverwriteChecklist.length,
                ),
                _line('Not common – answer manually', plan.notCommon.length),
                _line('Not answered at source', plan.sourceUnanswered.length),
                if (plan.wouldOverwrite.isNotEmpty ||
                    plan.wouldOverwriteChecklist.isNotEmpty)
                  SwitchListTile(
                    key: const Key('copy_overwrite'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.ui('Also replace existing answers')),
                    value: overwrite,
                    onChanged: (v) => set(() => overwrite = v),
                  ),
                const SizedBox(height: 8),
                Text(context.ui('Copied answers stay editable and are not linked to the '
                  'source. Remaining required questions must still be '
                  'answered.'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdinnColors.muted,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      key: const Key('copy_cancel'),
                      onPressed: () => Navigator.pop(ctx, 0),
                      child: Text(context.ui('Cancel')),
                    ),
                    const Spacer(),
                    FilledButton(
                      key: const Key('copy_apply'),
                      onPressed:
                          plan.toCopy.isEmpty &&
                              plan.toCopyChecklist.isEmpty &&
                              !(overwrite &&
                                  (plan.wouldOverwrite.isNotEmpty ||
                                      plan.wouldOverwriteChecklist.isNotEmpty))
                          ? null
                          : () =>
                                Navigator.pop(ctx, onCopy(source, overwrite)),
                      child: Text(context.ui('Copy')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  return n ?? 0;
}

Widget _line(String label, int n) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    children: [
      Expanded(child: Text(label)),
      Text('$n', style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  ),
);
