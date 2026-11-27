import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../notes/other_spec_dialog.dart';
import '../../state/app_controller.dart';

/// Confirmed result of the Add Media Type sheet.
class AddMediaResult {
  const AddMediaResult(
    this.plans, {
    this.selectInEditor = false,
    this.other,
  });

  /// A confirmed custom ("+ Other") media description: creates ONE custom
  /// media group.
  final CustomSpec? other;

  /// One group (one physical board) per selected media subtype.
  final List<MediaGroupPlan> plans;

  /// Create one empty board and pick its media in the editor's Media Type
  /// step.
  final bool selectInEditor;

  int get totalBoards => plans.fold(0, (s, p) => s + p.quantity);
}

/// Option keys of the media subtypes that [shop] already has (they are not
/// offered again).
Set<String> existingMediaKeys(Shop shop) => {
  for (final b in shop.boards)
    for (final o in SignageCatalog.mediaOptions)
      if (o.mediaCode == b.mediaCode &&
          (o.mediaCode != SignageCatalog.gsb || o.doubleSided == (b.doubleSided == true)) &&
          (o.mediaCode != SignageCatalog.nlb ||
              o.nlbSubtype == b.nlbSubtype))
        o.key,
};

/// "+ Add media type": media selection straight away (no quantity / media
/// count questions). Returns null when cancelled.
Future<AddMediaResult?> showAddMediaSheet(
  BuildContext context, {
  Set<String> existing = const {},
  bool allowSelectInEditor = true,
}) {
  return showModalBottomSheet<AddMediaResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => AddMediaSheet(
      existing: existing,
      allowSelectInEditor: allowSelectInEditor,
    ),
  );
}

/// The ONE add-media implementation (Shop Details and the editor's media
/// tabs): sheet → create the boards once → returns them (empty = cancelled).
/// Existing boards are never touched.
Future<List<Board>> runAddMedia(
  BuildContext context,
  AppController c,
  String shopId,
) async {
  final shop = c.shop(shopId);
  if (shop == null || !c.canEdit(shop)) return const [];
  final result = await showAddMediaSheet(
    context,
    existing: existingMediaKeys(shop),
  );
  if (result == null) return const [];
  try {
    if (result.other != null) return [c.addOtherMedia(shopId, result.other!)];
    if (result.selectInEditor) return [c.addBoard(shopId)];
    return c.addMediaGroups(shopId, result.plans);
  } on Object catch (e) {
    if (context.mounted) showSnack(context, '$e', error: true);
    return const [];
  }
}

class AddMediaSheet extends StatefulWidget {
  const AddMediaSheet({
    super.key,
    this.existing = const {},
    this.allowSelectInEditor = true,
  });

  final Set<String> existing;
  final bool allowSelectInEditor;

  @override
  State<AddMediaSheet> createState() => _AddMediaSheetState();
}

class _AddMediaSheetState extends State<AddMediaSheet> {
  final List<String> _selected = []; // option keys, in tap order
  bool _done = false; // a double tap never creates twice

  void _finish(AddMediaResult r) {
    if (_done) return;
    _done = true;
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(context.ui('Select the media type'),
                    key: Key('sheet_title'),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(context.ui('Choose one or more. Each becomes a board; add more '
                    'boards of the same type later with Number of Boards.'),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: AdinnColors.muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final o in SignageCatalog.mediaOptions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _OptionRow(
                        key: Key('opt_${o.key}'),
                        option: o,
                        selected: _selected.contains(o.key),
                        added: widget.existing.contains(o.key),
                        onTap: () => setState(() {
                          if (!_selected.remove(o.key)) _selected.add(o.key);
                        }),
                      ),
                    ),
                  // "+ Other": a custom media described by text or voice.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        key: const Key('opt_OTHER'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          final spec = await showOtherSpecDialog(
                            context,
                            title: context.t.otherMediaTitle,
                            hint: context.t.otherMediaHint,
                          );
                          if (spec != null && mounted) {
                            _finish(AddMediaResult(const [], other: spec));
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AdinnColors.line),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.add_circle_outline),
                              const SizedBox(width: 12),
                              Text(
                                context.t.otherMedia,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.allowSelectInEditor)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('sheet_in_editor'),
                onPressed: _selected.isEmpty
                    ? () => _finish(
                        const AddMediaResult([], selectInEditor: true),
                      )
                    : null,
                child: Text(context.ui('Select in editor')),
              ),
            ),
          Row(
            children: [
              TextButton(
                key: const Key('sheet_cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.ui('Cancel')),
              ),
              const Spacer(),
              FilledButton(
                key: const Key('sheet_next'),
                onPressed: _selected.isEmpty
                    ? null
                    : () => _finish(
                        AddMediaResult([
                          for (final k in _selected)
                            MediaGroupPlan(
                              SignageCatalog.mediaOptions.firstWhere(
                                (o) => o.key == k,
                              ),
                              1,
                            ),
                        ]),
                      ),
                child: Text(context.ui('Continue')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.option,
    required this.selected,
    required this.added,
    required this.onTap,
  });

  final MediaOption option;
  final bool selected;

  /// Already in this shop: not offered again.
  final bool added;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = SignageCatalog.media(option.mediaCode);
    return Opacity(
      opacity: added ? 0.5 : 1,
      child: Material(
        color: selected ? AdinnColors.redLight : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: added ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AdinnColors.red : AdinnColors.line,
              ),
            ),
            child: Row(
              children: [
                Icon(m?.icon ?? Icons.crop_square, color: m?.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    added
                        ? '${context.mediaLabel(option.label)} · ${context.ui('already added')}'
                        : context.mediaLabel(option.label),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
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
