import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/input_formats.dart';
import '../../../data/catalog/signage_catalog.dart';
import '../../board/media_type_grid.dart';
import '../../board/site_questions_form.dart';
import '../data/catalog_data.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';
import '../data/rework_alert.dart' show FlaggedSection;
import 'add_boards_screen.dart';
import 'live_widgets.dart';
import 'rework_alert.dart' show SectionReworkBanner;

/// Boards: one card per physical board, folded to one line. A card opens to two tabs: "Size & details" (media type, size, sides,
/// position, notes) and "Installation" (the installation method of its media type, then its site questions in a section that
/// folds once they are answered). A board made with "Add
/// boards" is always one unit with its own number; an older line (made before numbers existed) may still stand for several
/// identical boards through its quantity. Boards of one media type sit under one header whose + and - change the quantity.
class BoardsTab extends StatelessWidget {
  const BoardsTab({super.key, required this.ctrl, this.onBoardsAdded, this.onNextBoard, this.onOpenPhotos});

  final ShopDetailController ctrl;

  /// Called after "Add boards" saved new boards: the shop screen then moves on to the Photos tab.
  final VoidCallback? onBoardsAdded;

  /// "Next" at the end of a board card: the shop screen decides what comes next (the photos of the next board, ...).
  final ValueChanged<BoardItem>? onNextBoard;

  /// The Photos chip of a board: opens the Photos tab on that board.
  final ValueChanged<BoardItem>? onOpenPhotos;

  Future<void> _remove(BuildContext context, BoardItem b) async {
    // The server keeps a board that has photos (they would lose their board): say so here instead of failing at Save.
    if (ctrl.boardHasPhotos(b.key)) {
      showSnack(context, '${b.label} has photos, so it cannot be removed. Delete its draft photos first.', error: true);
      return;
    }
    final ok = await confirmDialog(context, title: 'Remove ${b.label}?', message: 'This board will be removed from the recce.', confirmText: 'Remove', destructive: true);
    if (ok) ctrl.removeBoard(b);
  }

  /// The bin on a media type's header: a type added by mistake goes with all its boards (and its draft photos), in one confirmed step.
  Future<void> _removeType(BuildContext context, String type) async {
    final list = ctrl.boardsOfType(type);
    if (list.isEmpty) return;
    final photos = ctrl.photosOfType(type);
    if (photos.submitted > 0) {
      showSnack(context, '$type has photos that were already submitted, so it cannot be removed.', error: true);
      return;
    }
    final loose = photos.drafts + photos.waiting;
    final names = list.map((b) => b.label).join(', ');
    final ok = await confirmDialog(
      context,
      title: 'Remove ${list.first.name}?',
      message: 'This removes ${list.length == 1 ? 'the board' : 'all ${list.length} boards'} of this media type ($names) from the recce.${loose > 0 ? ' Its $loose photo${loose == 1 ? '' : 's'} will be deleted too.' : ''}',
      confirmText: 'Remove',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final err = await ctrl.removeMediaType(type);
    if (!context.mounted) return;
    showSnack(context, err ?? '${list.first.name} removed. Save the draft to keep this change.', error: err != null);
  }

  Future<void> _add(BuildContext context) async {
    // The new boards are saved the moment they are added (their photos need a saved board); unsaved edits go with that save.
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AddBoardsScreen(ctrl: ctrl)));
    if (added == true) onBoardsAdded?.call();
  }

  /// "+" on a media type: one more board like the last one (saved at once, its photos need a saved board).
  Future<void> _more(BuildContext context, String type) async {
    final list = ctrl.boardsOfType(type);
    if (list.isEmpty) return;
    if (ctrl.boards.length >= maxBoardItems) {
      showSnack(context, 'A shop can hold $maxBoardItems boards.', error: true);
      return;
    }
    final err = await ctrl.addBoardLike(list.last);
    if (!context.mounted) return;
    showSnack(context, err ?? '${ctrl.boardsOfType(type).last.label} added, like ${list.last.label}. Change its size if it differs.', error: err != null);
  }

  /// "-" on a media type: the highest-numbered board of that type goes.
  Future<void> _fewer(BuildContext context, String type) async {
    final list = ctrl.boardsOfType(type);
    if (list.length <= 1) return;
    final ok = await confirmDialog(context, title: 'Remove ${list.last.label}?', message: 'The last board of this type will be removed from the recce.', confirmText: 'Remove', destructive: true);
    if (!ok || !context.mounted) return;
    final err = ctrl.removeLastOfType(type);
    if (err != null) showSnack(context, err, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final editable = ctrl.canEdit;
    // Size / quantity / media type requests that name no board (web reviewers may send them that way) cannot sit on a card: one banner for all.
    final general = ctrl.detail?.measurementReworksWithoutBoard(ctrl.boards.map((b) => b.key)) ?? const [];
    // In rework only what the reviewer flagged is open: boards are not added or removed, and a board card is editable only when a request
    // names it. A request that names no board (general banner, or a Boards checklist item) leaves every board open.
    final inRework = ctrl.inRework;
    final anyBoardOpen = general.isNotEmpty || (ctrl.detail != null && FlaggedSection.of(ctrl.detail!, section: 'BOARDS').isNotEmpty);
    bool open(BoardItem b) => editable && (!inRework || anyBoardOpen || (ctrl.detail?.boardReworksFor(b.key).isNotEmpty ?? false));
    final shownTypes = <String>{};
    final rows = <Widget>[];
    for (final b in ctrl.boards) {
      if (b.isNumbered) {
        if (!shownTypes.add(b.mediaType)) continue; // its group was already drawn with the first board of the type
        final list = ctrl.boardsOfType(b.mediaType);
        rows.add(_GroupHeader(
          media: ctrl.mediaOf(list.first),
          type: b.mediaType,
          name: list.first.name,
          count: list.length,
          enabled: editable && !inRework,
          canAdd: ctrl.boards.length < maxBoardItems,
          onMore: () => _more(context, b.mediaType),
          onFewer: () => _fewer(context, b.mediaType),
          onRemove: () => _removeType(context, b.mediaType),
        ));
        rows.add(const SizedBox(height: 8));
        for (final x in list) {
          rows.add(_card(context, x, open(x)));
          rows.add(const SizedBox(height: 10));
        }
        rows.add(const SizedBox(height: 4));
      } else {
        rows.add(_card(context, b, open(b)));
        rows.add(const SizedBox(height: 12));
      }
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Checklist items of the Boards section that are not a size, quantity or media type request (those use the banner below).
        if (ctrl.detail != null) SectionReworkBanner(items: FlaggedSection.of(ctrl.detail!, section: 'BOARDS'), title: 'Reviewer asked for changes to the boards'),
        if (general.isNotEmpty) ...[
          _MeasurementBanner(items: general),
          const SizedBox(height: 12),
        ],
        Row(children: [
          const Expanded(child: Text('Boards', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          Text('${ctrl.boards.length}/$maxBoardItems', style: const TextStyle(color: AdinnColors.muted)),
        ]),
        const SizedBox(height: 4),
        Text(
          inRework
              ? 'The reviewer asked for changes. Only the boards marked in red can be edited. The others stay as they are.'
              : 'Every physical board has its own number (GSB-01, GSB-02 ...), size, photos and installation requirement. Tap a board to open it.',
          style: const TextStyle(color: AdinnColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        if (ctrl.boards.isEmpty)
          editable
              ? const _NoBoardsWarning()
              : const EmptyState(icon: Icons.view_in_ar_outlined, title: 'No boards yet', message: 'Add the boards you measured.'),
        ...rows,
        if (editable && !inRework)
          OutlinedButton.icon(
            key: const Key('add-boards'),
            onPressed: ctrl.boards.length >= maxBoardItems ? null : () => _add(context),
            icon: const Icon(Icons.add),
            label: const Text('Add boards'),
          ),
      ],
    );
  }

  Widget _card(BuildContext context, BoardItem b, bool editable) => _BoardCard(
        key: ValueKey(b.key),
        ctrl: ctrl,
        item: b,
        enabled: editable,
        fixes: ctrl.detail?.boardReworksFor(b.key) ?? const [],
        onRemove: () => _remove(context, b),
        onNext: onNextBoard == null ? null : () => onNextBoard!(b),
        onOpenPhotos: onOpenPhotos == null ? null : () => onOpenPhotos!(b),
      );
}

/// One media type's header: its name and how many boards of it the shop has; + and - change that quantity.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.media, required this.type, required this.name, required this.count, required this.enabled, required this.canAdd, required this.onMore, required this.onFewer, required this.onRemove});

  final CatalogMedia? media;
  final String type;
  final String name;
  final int count;
  final bool enabled;
  final bool canAdd;
  final VoidCallback onMore;
  final VoidCallback onFewer;

  /// Removes the whole media type (every board of it): for a type added by mistake.
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(key: Key('group-$type'), children: [
      Icon(media == null ? Icons.view_in_ar_outlined : catalogIcon(media!.icon), color: media == null ? AdinnColors.red : hexColor(media!.color)),
      const SizedBox(width: 8),
      Expanded(child: Text('$type  ·  $name', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
      if (enabled) IconButton(key: Key('group-minus-$type'), tooltip: 'One board less', visualDensity: VisualDensity.compact, onPressed: count <= 1 ? null : onFewer, icon: const Icon(Icons.remove_circle_outline)),
      Text('$count', key: Key('group-count-$type'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      if (enabled) IconButton(key: Key('group-plus-$type'), tooltip: 'One board more', visualDensity: VisualDensity.compact, onPressed: canAdd ? onMore : null, icon: const Icon(Icons.add_circle_outline)),
      if (enabled) IconButton(key: Key('group-remove-$type'), tooltip: 'Remove this media type', visualDensity: VisualDensity.compact, onPressed: onRemove, icon: const Icon(Icons.delete_outline, color: AdinnColors.red)),
    ]);
  }
}

/// "Board details to correct": the reviewer's size / quantity / media type notes when they are not tied to one board.
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
              Expanded(child: Text('Board details to correct', style: TextStyle(fontWeight: FontWeight.w800, color: AdinnColors.red))),
            ]),
            for (final i in items) ...[
              const SizedBox(height: 8),
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${boardFixTitleFor(i.note.itemType, rejected: i.note.rejected, label: i.note.label)}${i.forBoard.isNotEmpty ? ' (board ${i.forBoard})' : ''}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AdinnColors.redDark))),
              ReworkBox(note: i.note, fallback: 'The reviewer asked you to correct the board details.'),
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
  const _BoardCard({super.key, required this.ctrl, required this.item, required this.enabled, this.fixes = const [], required this.onRemove, this.onNext, this.onOpenPhotos});

  final ShopDetailController ctrl;
  final BoardItem item;
  final bool enabled;

  /// The open requests for this board: the reviewer asked for its size, quantity or media type to be checked or corrected.
  final List<ReworkNote> fixes;
  final VoidCallback onRemove;
  final VoidCallback? onNext;
  final VoidCallback? onOpenPhotos;

  @override
  State<_BoardCard> createState() => _BoardCardState();
}

class _BoardCardState extends State<_BoardCard> {
  late final _qty = TextEditingController(text: widget.item.quantity.toString());
  late final _width = TextEditingController(text: _num(widget.item.width));
  late final _height = TextEditingController(text: _num(widget.item.height));
  late final _position = TextEditingController(text: widget.item.position);
  late final _notes = TextEditingController(text: widget.item.notes);
  /// The tab of the open card. Null until the card is first drawn: it then opens on the first part that is not done yet.
  _BoardTab? _tab;

  static String _num(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  @override
  void dispose() {
    for (final c in [_qty, _width, _height, _position, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  BoardItem get _i => widget.item;
  ShopDetailController get _c => widget.ctrl;

  void _changed() => _c.markDirty();

  /// The media type cards (the same ones as "Add boards"): one tap picks the type and closes the sheet. For an older line only.
  Future<void> _pickType() async {
    final grid = [for (final m in _c.catalog.offered) m.toMediaType()];
    final m = await showModalBottomSheet<MediaType>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const Text('Media type', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Choose one of ${grid.length} media types', style: const TextStyle(color: AdinnColors.muted)),
            const SizedBox(height: 12),
            MediaTypeGrid(selected: _c.mediaOf(_i)?.code, media: grid, enabled: true, onSelect: (t) => Navigator.pop(ctx, t)),
          ],
        ),
      ),
    );
    if (m == null || !mounted) return;
    setState(() {});
    _c.changeBoardType(_i, mediaType: m.shortName, name: m.name, mediaCode: m.code);
  }

  bool get _sizeDone => _i.hasSize && _i.name.trim().isNotEmpty;

  /// A card opens on the first part that is not done: Size, else Installation (when it is required and missing), else Size.
  _BoardTab _firstTab() => !_sizeDone ? _BoardTab.size : (_c.needsInstallation(_i) && !_c.boardInstallDone(_i) ? _BoardTab.install : _BoardTab.size);

  /// The part a flow asked for ("Next" moved on to this board's installation, a chip was tapped ...) is shown once the card is open.
  void _applyRequestedSection() {
    final section = _c.takeCardSection(_i.key);
    if (section == null) return;
    _tab = section == BoardSection.installation ? _BoardTab.install : _BoardTab.size;
  }

  String get _sizeText => _i.hasSize ? '${_trim(_i.width!)} x ${_trim(_i.height!)} ${_i.unit.toLowerCase()}' : 'size not entered';
  static String _trim(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final en = widget.enabled;
    final fixes = widget.fixes;
    final fix = fixes.isEmpty ? null : fixes.first;
    final open = _c.boardCardOpen(_i.key);
    if (open) _applyRequestedSection();
    final tab = _tab ??= _firstTab();
    final needs = _c.needsInstallation(_i);
    final photos = _c.boardPhotoProgress(_i.key);
    final media = _c.mediaOf(_i);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: fix == null ? AdinnColors.line : AdinnColors.red, width: fix == null ? 1 : 1.6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: Key('bcard-${_i.key}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => _c.toggleBoardCard(_i.key),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(media == null ? Icons.view_in_ar_outlined : catalogIcon(media.icon), color: media == null ? AdinnColors.red : hexColor(media.color)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_i.isNumbered ? _i.label : (_i.name.trim().isEmpty ? _i.key : _i.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(_i.quantity > 1 ? '$_sizeText  ×${_i.quantity}' : _sizeText, style: const TextStyle(fontSize: 12.5, color: AdinnColors.muted)),
                  ]),
                ),
                if (fixes.isNotEmpty) ReworkTag(text: fixes.every((f) => f.rejected) ? 'Rejected' : 'Rework'),
                Icon(open ? Icons.expand_less : Icons.expand_more, color: AdinnColors.muted),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _StateChip(key: Key('chip-size-${_i.key}'), label: 'Size', done: _sizeDone, onTap: () => _c.openBoardCard(_i.key, section: BoardSection.size)),
                if (needs) _StateChip(key: Key('chip-install-${_i.key}'), label: 'Installation', done: _c.boardInstallDone(_i), onTap: () => _c.openBoardCard(_i.key, section: BoardSection.installation)),
                if (_c.isSaved(_i.key)) _StateChip(key: Key('chip-photos-${_i.key}'), label: 'Photos ${photos.done}/${photos.total}', done: photos.total > 0 && photos.done >= photos.total, onTap: widget.onOpenPhotos),
              ]),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Divider(height: 1),
              for (final f in fixes) ...[
                const SizedBox(height: 10),
                Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(boardFixTitleFor(f.itemType, rejected: f.rejected, label: f.label), style: const TextStyle(fontWeight: FontWeight.w800, color: AdinnColors.red))),
                ReworkBox(note: f, fallback: 'The reviewer asked you to ${boardFixTitle(f.itemType).toLowerCase()} of this board.'),
              ],
              const SizedBox(height: 12),
              _BoardTabBar(boardKey: _i.key, selected: tab, sizeDone: _sizeDone, installDone: needs ? _c.boardInstallDone(_i) : null, onSelect: (t) => setState(() => _tab = t)),
              const SizedBox(height: 14),
              // One tab at a time (no animation: the person is typing measurements here).
              if (tab == _BoardTab.size) ...[..._sizeSection(en), const SizedBox(height: 16), ..._moreDetails(en)] else ..._installationSection(en),
              const SizedBox(height: 14),
              Row(children: [
                if (en)
                  IconButton(key: Key('bremove-${_i.key}'), tooltip: 'Remove this board', icon: const Icon(Icons.delete_outline, color: AdinnColors.red), onPressed: widget.onRemove),
                // A Wrap, not a Row: on a narrow phone or with a large font the two buttons go to a second line instead of overflowing.
                Expanded(
                  child: Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
                    if (widget.onOpenPhotos != null && _c.isSaved(_i.key))
                      OutlinedButton.icon(key: Key('bphotos-${_i.key}'), onPressed: widget.onOpenPhotos, icon: const Icon(Icons.photo_camera_outlined), label: Text('Photos ${photos.done}/${photos.total}')),
                    // Next is open once this board's size and installation requirement are complete (the optional notes do not hold it back).
                    if (en && widget.onNext != null)
                      FilledButton.icon(
                        key: Key('bnext-${_i.key}'),
                        onPressed: _i.hasSize && _i.name.trim().isNotEmpty && _c.boardInstallDone(_i) ? widget.onNext : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Next'),
                      ),
                  ]),
                ),
              ]),
            ]),
          ),
      ]),
    );
  }

  /// Media type (read-only on a numbered board, cards for an older line), quantity (older lines only), unit, size, faces, condition.
  List<Widget> _sizeSection(bool en) {
    return [
      // A numbered board keeps the media type it was made from (GSB-01 stays a GSB board): its number depends on it.
      if (_i.isNumbered)
        InputDecorator(decoration: const InputDecoration(labelText: 'Media type'), child: Text(_i.name, key: const Key('board-media-type')))
      else
        InkWell(
          key: const Key('board-pick-type'),
          borderRadius: BorderRadius.circular(12),
          onTap: en ? _pickType : null,
          child: InputDecorator(
            decoration: InputDecoration(labelText: 'Media type *', suffixIcon: en ? const Icon(Icons.grid_view_rounded) : null),
            child: Text(_i.name.trim().isEmpty ? 'Tap to choose a media type' : _i.name, style: TextStyle(color: _i.name.trim().isEmpty ? AdinnColors.muted : null)),
          ),
        ),
      const SizedBox(height: 12),
      Row(children: [
        // One numbered board is one physical unit: no quantity to enter (its media type header has + and -). Older lines keep their box.
        if (!_i.isNumbered) ...[
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
        ],
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
    ];
  }

  /// The installation methods of this board's media type (radio tiles), then the site questions of that media type and method.
  List<Widget> _installationSection(bool en) {
    final methods = _c.installationsOf(_i);
    if (methods.isEmpty) {
      return [
        Text(
          _c.mediaOf(_i) == null ? 'Choose the media type above first.' : 'No installation method is set up for this media type.',
          key: Key('install-none-${_i.key}'),
          style: const TextStyle(color: AdinnColors.muted),
        ),
      ];
    }
    final chosen = _i.installationType;
    return [
      for (final m in methods)
        _InstallTile(
          key: Key('inst_${_i.key}_${m.code}'),
          icon: catalogIcon(m.icon),
          title: m.name,
          subtitle: m.description,
          selected: chosen == m.code,
          onTap: en
              ? () {
                  setState(() => _c.setInstallation(_i, m.code));
                }
              : null,
        ),
      if (chosen != null && chosen.isNotEmpty) ...[
        const SizedBox(height: 8),
        // The answers fold: open while something is still to answer, folded once every question is answered (tap the header to open it again).
        Builder(builder: (_) {
          // The count is of the required questions (an optional one left empty must not keep the section open); with none required, of all.
          final visible = _c.questionsOf(_i).where((q) => q.isVisible(_i.answers)).toList();
          final counted = visible.any((q) => q.required) ? visible.where((q) => q.required).toList() : visible;
          return _AnswersPanel(
            key: ValueKey('answers-${_i.key}-$chosen'),
            title: 'Site questions',
            answered: counted.where((q) => q.isAnswered(_i.answers)).length,
            total: counted.length,
            child: SiteQuestionsForm(
              key: ValueKey('${_i.key}|${_c.mediaOf(_i)?.code}|$chosen'),
              questions: _c.questionsOf(_i),
              answers: _i.answers,
              enabled: en,
              onChanged: (id, v) => _c.setAnswer(_i, id, v),
            ),
          );
        }),
      ] else if (en)
        const Padding(padding: EdgeInsets.only(top: 6), child: Text('Choose the installation method to get its questions.', style: TextStyle(color: AdinnColors.muted, fontSize: 13))),
    ];
  }

  List<Widget> _moreDetails(bool en) => [
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
      ];

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

/// A small status pill under the board's name: done (green tick) or still to do (red dot). Tap = open that part.
class _StateChip extends StatelessWidget {
  const _StateChip({super.key, required this.label, required this.done, this.onTap});
  final String label;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = done ? AdinnColors.success : AdinnColors.red;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
    return onTap == null ? chip : InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: chip);
  }
}

/// The two parts of an open board card.
enum _BoardTab { size, install }

/// The tabs of an open board card: a red pill for the open one, a tick or a warning on each part that needs an answer.
class _BoardTabBar extends StatelessWidget {
  const _BoardTabBar({required this.boardKey, required this.selected, required this.sizeDone, required this.installDone, required this.onSelect});
  final String boardKey;
  final _BoardTab selected;
  final bool sizeDone;

  /// null = nothing is required on the Installation tab (no tick or warning shown).
  final bool? installDone;
  final ValueChanged<_BoardTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AdinnColors.canvas, borderRadius: BorderRadius.circular(14), border: Border.all(color: AdinnColors.line)),
      child: Row(children: [
        Expanded(child: _tab(key: Key('btab-size-$boardKey'), value: _BoardTab.size, icon: Icons.straighten, label: 'Size & details', done: sizeDone)),
        const SizedBox(width: 4),
        Expanded(child: _tab(key: Key('btab-install-$boardKey'), value: _BoardTab.install, icon: Icons.construction_outlined, label: 'Installation', done: installDone)),
      ]),
    );
  }

  Widget _tab({required Key key, required _BoardTab value, required IconData icon, required String label, required bool? done}) {
    final on = selected == value;
    final fg = on ? Colors.white : AdinnColors.muted;
    return Semantics(
      selected: on,
      button: true,
      child: Material(
        color: on ? AdinnColors.red : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(10),
          onTap: () => onSelect(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13.5))),
              if (done != null) ...[
                const SizedBox(width: 6),
                Icon(done ? Icons.check_circle : Icons.error_outline, size: 15, color: on ? Colors.white : (done ? AdinnColors.success : AdinnColors.red)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// A section of answers that folds: its header says how many questions are answered. It starts open while something is still to answer
/// and folded when everything is answered; a tap on the header opens or folds it again.
class _AnswersPanel extends StatefulWidget {
  const _AnswersPanel({super.key, required this.title, required this.answered, required this.total, required this.child});
  final String title;
  final int answered;
  final int total;
  final Widget child;

  @override
  State<_AnswersPanel> createState() => _AnswersPanelState();
}

class _AnswersPanelState extends State<_AnswersPanel> {
  late bool _open = widget.answered < widget.total;

  @override
  Widget build(BuildContext context) {
    final complete = widget.total > 0 && widget.answered >= widget.total;
    final color = complete ? AdinnColors.success : AdinnColors.red;
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AdinnColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: const Key('answers-toggle'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(children: [
              const Icon(Icons.fact_check_outlined, size: 20, color: AdinnColors.muted),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(widget.total == 0 ? 'none' : '${widget.answered}/${widget.total} answered', key: const Key('answers-count'), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
              ),
              const SizedBox(width: 4),
              Icon(_open ? Icons.expand_less : Icons.expand_more, color: AdinnColors.muted),
            ]),
          ),
        ),
        if (_open) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 4), child: widget.child),
      ]),
    );
  }
}

class _InstallTile extends StatelessWidget {
  const _InstallTile({super.key, required this.icon, required this.title, required this.subtitle, required this.selected, this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AdinnColors.redLight : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? AdinnColors.red : AdinnColors.line, width: selected ? 2 : 1)),
            child: Row(children: [
              Icon(icon, color: AdinnColors.red),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(fontSize: 12, color: AdinnColors.muted)),
                ]),
              ),
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AdinnColors.red : AdinnColors.muted),
            ]),
          ),
        ),
      ),
    );
  }
}
