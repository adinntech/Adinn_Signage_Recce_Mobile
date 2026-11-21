import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_file_row.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';

/// Lets the person pick what a message is about: a photo of this shop, a board, a version (at most [maxChatRefs] together).
/// Only what the SERVER holds is offered (the shop detail and the version list): a reference to something that is not stored there
/// is refused by the server. Returns the new selection, or null when the sheet is closed without Done.
Future<List<ChatRef>?> showChatRefPicker(BuildContext context, {required ShopDetailController shop, required List<ChatRef> selected}) {
  return showModalBottomSheet<List<ChatRef>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ChatRefPickerSheet(shop: shop, selected: selected),
  );
}

class ChatRefPickerSheet extends StatefulWidget {
  const ChatRefPickerSheet({super.key, required this.shop, required this.selected});

  final ShopDetailController shop;
  final List<ChatRef> selected;

  @override
  State<ChatRefPickerSheet> createState() => _ChatRefPickerSheetState();
}

class _ChatRefPickerSheetState extends State<ChatRefPickerSheet> {
  late final Set<ChatRef> _sel = {...widget.selected};

  void _toggle(ChatRef r, bool on) => setState(() => on ? _sel.add(r) : _sel.remove(r));

  Widget _tile(ChatRef r, {required Widget title, String? subtitle, Widget? leading}) {
    final on = _sel.contains(r);
    final full = _sel.length >= maxChatRefs;
    return CheckboxListTile(
      key: ValueKey('pick-${r.key}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.trailing,
      value: on,
      onChanged: !on && full ? null : (v) => _toggle(r, v ?? false),
      secondary: leading,
      title: title,
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 12)),
    );
  }

  static Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AdinnColors.muted, letterSpacing: 0.6)),
      );

  @override
  Widget build(BuildContext context) {
    final d = widget.shop.detail;
    final photos = d?.photos ?? const <ShopPhoto>[];
    final boards = d?.mediaItems ?? const <BoardItem>[];
    final versions = widget.shop.versionList.isNotEmpty
        ? [for (final v in widget.shop.versionList) (n: v.version, at: v.submittedAt)]
        : [for (final v in d?.versions ?? const <VersionEntry>[]) (n: v.version, at: v.submittedAt)];
    final empty = photos.isEmpty && boards.isEmpty && versions.isEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(child: Text('Refer to', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              Text('${_sel.length}/$maxChatRefs', style: const TextStyle(color: AdinnColors.muted, fontWeight: FontWeight.w700)),
            ]),
            const Text('Pick the photo, board or version your message is about.', style: TextStyle(color: AdinnColors.muted, fontSize: 13)),
            Flexible(
              child: empty
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('Nothing to refer to yet.', style: TextStyle(color: AdinnColors.muted))))
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        if (photos.isNotEmpty) _heading('Photos'),
                        for (final p in photos)
                          _tile(
                            ChatRef(ChatRefType.photo, p.id),
                            title: Text(d!.categoryLabel(p.category)),
                            subtitle: [if (p.isDraft) 'Draft' else if (p.version != null) 'V${p.version}', if (p.needsRework) 'Rework required'].join(' | '),
                            leading: SizedBox(width: 44, height: 44, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: AppFileRow.image(p.displayUrl, null, cacheWidth: 120))),
                          ),
                        if (boards.isNotEmpty) _heading('Boards'),
                        for (final b in boards) _tile(ChatRef(ChatRefType.board, b.key), title: Text(b.key), subtitle: boardSummaryText(b), leading: const Icon(Icons.view_in_ar_outlined)),
                        if (versions.isNotEmpty) _heading('Versions'),
                        for (final v in versions)
                          _tile(ChatRef(ChatRefType.version, '${v.n}'), title: Text('Version ${v.n}'), subtitle: v.at == null ? null : 'Submitted ${fmtDateTime(v.at!)}', leading: const Icon(Icons.history)),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: _sel.isEmpty ? null : () => setState(_sel.clear), child: const Text('Clear'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, _sel.toList()), child: const Text('Done'))),
            ]),
          ],
        ),
      ),
    );
  }
}
