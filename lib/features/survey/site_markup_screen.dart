import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../annotation/annotation_painter.dart';
import '../photos/site_photo_view.dart';
import 'perspective_math.dart';
import 'site_markup_controller.dart';
import 'site_markup_painter.dart';

/// Opens the signage item behind a marker (e.g. its site survey screen).
typedef OpenSignageItem =
    void Function(BuildContext context, Board board, SignageUnit unit);

/// Advanced photo markup: four-corner perspective boards, numbered board
/// placement markers, electrical points / switches / power notes, cable
/// routes and obstructions. Works on a copy and saves editable data only –
/// the photo file and the classic annotations are never modified.
class SiteMarkupScreen extends StatefulWidget {
  const SiteMarkupScreen({
    super.key,
    required this.shopId,
    required this.boardId,
    required this.photoId,
    this.initialTool = SiteMarkupTool.select,
    this.activeUnitId,
    this.onOpenItem,
  });

  final String shopId;
  final String boardId;
  final String photoId;
  final SiteMarkupTool initialTool;

  /// Signage item new perspective boards / markers link to by default.
  final String? activeUnitId;
  final OpenSignageItem? onOpenItem;

  @override
  State<SiteMarkupScreen> createState() => _SiteMarkupScreenState();
}

enum _Op { none, corner, move, shape }

class _SiteMarkupScreenState extends State<SiteMarkupScreen> {
  static const double _margin = 28;

  SiteMarkupController? _ctrl;
  final _tc = TransformationController();
  Size _box = Size.zero;
  _Op _op = _Op.none;
  int _corner = -1;
  Offset _last = Offset.zero;
  SurveyPoint? _shapeStart;

  SiteMarkupController get ctrl => _ctrl!;

  double get _zoom => _tc.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onZoom);
  }

  void _onZoom() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tc.removeListener(_onZoom);
    _tc.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  SiteMarkupController _init(SitePhoto photo, Board b) {
    final first = b.activeUnits.isEmpty ? null : b.activeUnits.first.id;
    final c = SiteMarkupController(
      photoId: photo.id,
      initial: photo.markup,
      imageSize: Size(photo.width.toDouble(), photo.height.toDouble()),
      activeUnitId:
          widget.activeUnitId ??
          (photo.unitIds.isNotEmpty ? photo.unitIds.first : first),
    )..setTool(widget.initialTool);
    c.addListener(() {
      if (mounted) setState(() {});
    });
    return c;
  }

  // ---------------------------------------------------------------------------
  // Units of the shop (markers may link to any media group of the shop)
  // ---------------------------------------------------------------------------

  List<(Board, SignageUnit)> _units(Shop s) => [
    for (final b in s.boards)
      for (final u in b.activeUnits) (b, u),
  ];

  (Board, SignageUnit)? _unit(Shop s, String? id) {
    for (final e in _units(s)) {
      if (e.$2.id == id) return e;
    }
    return null;
  }

  Future<String?> _pickUnit(
    Shop s,
    MarkupLabels labels, {
    String title = 'Signage item',
  }) async {
    final units = _units(s);
    if (units.isEmpty) {
      showSnack(context, 'Add a signage item to this shop first', error: true);
      return null;
    }
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final (b, u) in units)
                ListTile(
                  key: ValueKey('markup_pick_${u.id}'),
                  leading: Icon(
                    SignageCatalog.media(b.mediaCode)?.icon ??
                        Icons.crop_landscape,
                    color: labels[u.id]?.color ?? AdinnColors.red,
                  ),
                  title: Text(labels.labelOf(u.id)),
                  subtitle: Text(
                    [
                      b.name,
                      fmtSize(b.widthOf(u), b.heightOf(u), b.unit),
                      if (labels[u.id]?.installationName.isNotEmpty ?? false)
                        labels[u.id]!.installationName,
                    ].join(' • '),
                  ),
                  trailing: ctrl.activeUnitId == u.id
                      ? const Icon(Icons.check, color: AdinnColors.red)
                      : null,
                  onTap: () => Navigator.pop(ctx, u.id),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _ensureUnit(Shop s, MarkupLabels labels) async {
    final id = ctrl.activeUnitId;
    if (id != null && _unit(s, id) != null) return id;
    final picked = await _pickUnit(s, labels);
    if (picked != null) setState(() => ctrl.activeUnitId = picked);
    return picked;
  }

  Future<String?> _askText(String title, {String initial = ''}) async {
    final t = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const ValueKey('markup_text_field'),
          controller: t,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('markup_text_ok'),
            onPressed: () => Navigator.pop(ctx, t.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    t.dispose();
    return r;
  }

  // ---------------------------------------------------------------------------
  // Gestures (local coordinates are already in the zoomed child's space)
  // ---------------------------------------------------------------------------

  Offset _toBox(Offset local) => local - const Offset(_margin, _margin);

  SurveyPoint _norm(Offset p) => SurveyPoint.fromPixels(p, _box);

  double get _tolerance => 14 / math.max(_zoom, 0.5);

  Future<void> _onTapUp(
    TapUpDetails d,
    Shop s,
    MarkupLabels labels,
    bool editable,
  ) async {
    final p = _toBox(d.localPosition);
    final n = _norm(p);
    switch (ctrl.tool) {
      case SiteMarkupTool.select:
      case SiteMarkupTool.pan:
        ctrl.select(ctrl.hitTest(p, _box, _tolerance));
      case SiteMarkupTool.perspective:
        if (!editable) return;
        final unit = await _ensureUnit(s, labels);
        if (unit == null || !mounted) return;
        ctrl.addPerspective(unit, centre: n, aspect: labels[unit]?.aspect ?? 3);
      case SiteMarkupTool.marker:
        if (!editable) return;
        final unit = await _ensureUnit(s, labels);
        if (unit == null || !mounted) return;
        final media = labels[unit]?.mediaCode ?? '';
        final r = ctrl.addMarker(unit, n, mediaCode: media);
        if (r == MarkerAddResult.duplicatePrimary) {
          final alt = await _confirmAlternative(labels.labelOf(unit));
          if (alt == true) {
            ctrl.addMarker(unit, n, alternative: true, mediaCode: media);
          }
        }
      case SiteMarkupTool.electricalPoint:
      case SiteMarkupTool.switchPoint:
        if (!editable) return;
        ctrl.addElectrical(
          ctrl.tool == SiteMarkupTool.switchPoint
              ? ElectricalMarkKind.switchPoint
              : ElectricalMarkKind.point,
          n,
          unitIds: [?ctrl.activeUnitId],
        );
      case SiteMarkupTool.powerNote:
        if (!editable) return;
        final text = await _askText('Power availability note');
        if (text == null || text.trim().isEmpty || !mounted) return;
        ctrl.addElectrical(
          ElectricalMarkKind.powerNote,
          n,
          notes: text.trim(),
          unitIds: [?ctrl.activeUnitId],
        );
      case SiteMarkupTool.cableRoute:
        if (editable) ctrl.addDraftPoint(n);
      case SiteMarkupTool.obstruction:
        if (!editable) return;
        switch (ctrl.obstructionShape) {
          case ObstructionShape.point:
            final o = ctrl.addObstruction([n]);
            if (o != null) await _editObstruction(s, labels, o.id);
          case ObstructionShape.text:
            final text = await _askText('Obstruction label');
            if (text == null || text.trim().isEmpty || !mounted) return;
            final o = ctrl.addObstruction([n], label: text.trim());
            if (o != null) await _editObstruction(s, labels, o.id);
          case ObstructionShape.polygon:
            ctrl.addDraftPoint(n);
          case ObstructionShape.rect:
          case ObstructionShape.arrow:
            showSnack(context, 'Drag on the photo to draw the shape');
        }
    }
  }

  Future<bool?> _confirmAlternative(String item) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Item already marked'),
      content: Text(
        '$item already has a primary placement marker on this photo. '
        'Add this one as an alternative placement?',
      ),
      actions: [
        TextButton(
          key: const ValueKey('mk_dup_cancel'),
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('mk_dup_alt'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Add alternative'),
        ),
      ],
    ),
  );

  void _onPanStart(DragStartDetails d, bool editable) {
    if (!editable) return;
    final p = _toBox(d.localPosition);
    _op = _Op.none;
    _last = p;
    if (ctrl.tool == SiteMarkupTool.obstruction &&
        (ctrl.obstructionShape == ObstructionShape.rect ||
            ctrl.obstructionShape == ObstructionShape.arrow)) {
      _shapeStart = _norm(p);
      ctrl.setDraft([_shapeStart!, _shapeStart!]);
      _op = _Op.shape;
      return;
    }
    if (ctrl.tool != SiteMarkupTool.select) return;
    final corner = ctrl.hitCorner(
      p,
      _box,
      SiteMarkupPainter.handleRadius(_box, _zoom) * 1.6,
    );
    if (corner != null) {
      _op = _Op.corner;
      _corner = corner;
      ctrl.beginGesture();
      return;
    }
    final hit = ctrl.hitTest(p, _box, _tolerance);
    if (hit != null) {
      ctrl.select(hit);
      _op = _Op.move;
      ctrl.beginGesture();
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final p = _toBox(d.localPosition);
    switch (_op) {
      case _Op.corner:
        final id = ctrl.selectedId;
        if (id != null) ctrl.moveCorner(id, _corner, _norm(p));
      case _Op.move:
        final delta = p - _last;
        ctrl.translateSelected(
          SurveyPoint(delta.dx / _box.width, delta.dy / _box.height),
        );
      case _Op.shape:
        ctrl.setDraft([_shapeStart!, _norm(p)]);
      case _Op.none:
        break;
    }
    _last = p;
  }

  Future<void> _onPanEnd(Shop s, MarkupLabels labels) async {
    final op = _op;
    _op = _Op.none;
    switch (op) {
      case _Op.corner:
      case _Op.move:
        ctrl.endGesture();
      case _Op.shape:
        final pts = List.of(ctrl.draft);
        ctrl.cancelDraft();
        final o = ctrl.addObstruction(pts);
        if (o != null) await _editObstruction(s, labels, o.id);
      case _Op.none:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Detail sheets
  // ---------------------------------------------------------------------------

  Future<void> _markerDetails(Shop s, MarkupLabels labels, String id) async {
    final m = ctrl.marker(id);
    if (m == null) return;
    final item = _unit(s, m.unitId);
    final info = labels[m.unitId];
    final notes = TextEditingController(text: m.notes);
    final editable = context.read<AppController>().canEdit(s);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Marker ${m.numberLabel}'
              '${m.isAlternative ? ' • Alternative ${m.placementNo}' : ''}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            InfoRow(
              'Media type',
              SignageCatalog.media(item?.$1.mediaCode)?.name ??
                  (m.mediaCode.isEmpty ? '—' : m.mediaCode),
            ),
            InfoRow('Signage item', info?.label ?? 'Item no longer exists'),
            InfoRow('Unit ID', m.unitId),
            InfoRow(
              'Width × Height',
              item == null
                  ? '—'
                  : fmtSize(
                      item.$1.widthOf(item.$2),
                      item.$1.heightOf(item.$2),
                      item.$1.unit,
                    ),
            ),
            InfoRow(
              'Installation',
              (info?.installationName.isEmpty ?? true)
                  ? '—'
                  : info!.installationName,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('mk_notes'),
              controller: notes,
              enabled: editable,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Placement notes'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (editable)
                  OutlinedButton.icon(
                    key: const ValueKey('mk_renumber'),
                    onPressed: () => Navigator.pop(ctx, 'renumber'),
                    icon: const Icon(Icons.format_list_numbered, size: 18),
                    label: const Text('Change number'),
                  ),
                if (item != null && widget.onOpenItem != null)
                  OutlinedButton.icon(
                    key: const ValueKey('mk_open_item'),
                    onPressed: () => Navigator.pop(ctx, 'open'),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Edit item details'),
                  ),
                if (editable)
                  FilledButton(
                    key: const ValueKey('mk_notes_save'),
                    onPressed: () => Navigator.pop(ctx, 'save'),
                    child: const Text('Done'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    final text = notes.text;
    notes.dispose();
    if (!mounted) return;
    if (editable && text != m.notes) ctrl.updateMarker(id, notes: text);
    if (result == 'open' && item != null) {
      // The editor stays on the stack, so unsaved markings are kept.
      widget.onOpenItem?.call(context, item.$1, item.$2);
    } else if (result == 'renumber') {
      final count = ctrl.markup.markers.length;
      final n = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Marker number'),
          children: [
            for (var i = 1; i <= count; i++)
              SimpleDialogOption(
                key: ValueKey('mk_number_$i'),
                onPressed: () => Navigator.pop(ctx, i),
                child: Text(i.toString().padLeft(2, '0')),
              ),
          ],
        ),
      );
      if (n != null) ctrl.setMarkerNumber(id, n);
    }
  }

  Future<List<String>?> _pickUnitLinks(
    Shop s,
    MarkupLabels labels,
    List<String> current,
  ) async {
    final selected = {...current};
    return showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Linked signage items',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                for (final (_, u) in _units(s))
                  CheckboxListTile(
                    key: ValueKey('markup_link_${u.id}'),
                    value: selected.contains(u.id),
                    title: Text(labels.labelOf(u.id)),
                    onChanged: (v) => setSheet(() {
                      if (v == true) {
                        selected.add(u.id);
                      } else {
                        selected.remove(u.id);
                      }
                    }),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    key: const ValueKey('markup_link_done'),
                    onPressed: () => Navigator.pop(ctx, selected.toList()),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _electricalDetails(
    Shop s,
    MarkupLabels labels,
    String id,
  ) async {
    final e = ctrl.electrical(id);
    final c = ctrl.cable(id);
    if (e == null && c == null) return;
    final notes = TextEditingController(text: e?.notes ?? c!.notes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          e != null
              ? '${e.code} – ${e.kind.label}'
              : '${c!.code} – Cable route',
        ),
        content: TextField(
          key: const ValueKey('el_mark_notes'),
          controller: notes,
          maxLines: 4,
          minLines: 1,
          decoration: const InputDecoration(labelText: 'Notes / location'),
        ),
        actions: [
          TextButton(
            key: const ValueKey('el_mark_links'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Link items…'),
          ),
          FilledButton(
            key: const ValueKey('el_mark_save'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final text = notes.text;
    notes.dispose();
    if (!mounted || ok == null) return;
    if (e != null) {
      ctrl.updateElectrical(id, notes: text);
    } else {
      ctrl.updateCable(id, notes: text);
    }
    if (ok == false) {
      final links = await _pickUnitLinks(s, labels, e?.unitIds ?? c!.unitIds);
      if (links == null) return;
      if (e != null) {
        ctrl.updateElectrical(id, unitIds: links);
      } else {
        ctrl.updateCable(id, unitIds: links);
      }
    }
  }

  Future<void> _editObstruction(Shop s, MarkupLabels labels, String id) async {
    final o = ctrl.obstruction(id);
    if (o == null) return;
    final b = context.read<AppController>().board(
      widget.shopId,
      widget.boardId,
    );
    var type = o.type;
    var severity = o.severity;
    var links = [...o.unitIds];
    String? evidence = o.evidencePhotoId;
    final remarks = TextEditingController(text: o.remarks);
    final label = TextEditingController(text: o.label);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${o.code} – ${o.shape.label}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<ObstructionType>(
                  key: const ValueKey('ob_edit_type'),
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final t in ObstructionType.values)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (v) => setSheet(() => type = v ?? type),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Severity',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                SegmentedButton<Severity>(
                  segments: [
                    for (final sv in Severity.values)
                      ButtonSegment(
                        value: sv,
                        label: Text(
                          sv.label,
                          key: ValueKey('ob_edit_sev_${sv.name}'),
                        ),
                      ),
                  ],
                  selected: {severity},
                  onSelectionChanged: (v) => setSheet(() => severity = v.first),
                ),
                if (o.shape == ObstructionShape.text) ...[
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('ob_edit_label'),
                    controller: label,
                    decoration: const InputDecoration(labelText: 'Label text'),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('ob_edit_remarks'),
                  controller: remarks,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(labelText: 'Remarks'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('ob_edit_evidence'),
                  initialValue: evidence,
                  decoration: const InputDecoration(
                    labelText: 'Evidence photo (optional)',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('None'),
                    ),
                    for (final p in b?.photos ?? const <SitePhoto>[])
                      if (p.id != widget.photoId)
                        DropdownMenuItem<String?>(
                          value: p.id,
                          child: Text(p.label),
                        ),
                  ],
                  onChanged: (v) => setSheet(() => evidence = v),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('ob_edit_links'),
                  onPressed: () async {
                    final r = await _pickUnitLinks(s, labels, links);
                    if (r != null) setSheet(() => links = r);
                  },
                  icon: const Icon(Icons.link, size: 18),
                  label: Text(
                    links.isEmpty
                        ? 'Link signage items (none – applies to photo)'
                        : links.map(labels.labelOf).join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey('ob_edit_save'),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save obstruction'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final r = remarks.text, l = label.text;
    remarks.dispose();
    label.dispose();
    if (saved != true || !mounted) return;
    ctrl.updateObstruction(
      id,
      type: type,
      severity: severity,
      remarks: r,
      label: l,
      unitIds: links,
      evidencePhotoId: evidence,
      clearEvidence: evidence == null,
    );
  }

  Future<void> _openLayers() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final l in MarkupLayer.values)
                SwitchListTile(
                  key: ValueKey('layer_${l.name}'),
                  title: Text(l.label),
                  value: !ctrl.hidden.contains(l),
                  onChanged: (_) => setSheet(() => ctrl.toggleLayer(l)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _save(AppController c, Shop s) {
    final reason = ctrl.saveBlockedReason;
    if (reason != null) {
      showSnack(context, reason, error: true);
      return;
    }
    c.saveSiteMarkup(s.id, widget.boardId, widget.photoId, ctrl.markup);
    ctrl.markSaved();
    showSnack(context, 'Site markup saved');
  }

  Future<void> _onPop(bool didPop, Object? _) async {
    if (didPop) return;
    final ok = await confirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Your site markings on this photo have not been saved.',
      confirmText: 'Discard',
      destructive: true,
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final s = c.shop(widget.shopId);
    final b = c.board(widget.shopId, widget.boardId);
    final photo = c.photo(widget.shopId, widget.boardId, widget.photoId);
    if (s == null || b == null || photo == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'Photo not found',
        ),
      );
    }
    _ctrl ??= _init(photo, b);
    final editable = c.canEdit(s);
    final labels = MarkupLabels.forShop(
      s,
      brand: c.project(s.projectId)?.client ?? '',
    );
    final problems = ctrl.problems;
    return PopScope(
      canPop: !ctrl.dirty,
      onPopInvokedWithResult: _onPop,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Site markup',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              Text(
                '${b.name} • ${photo.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
              ),
            ],
          ),
          actions: [
            IconButton(
              key: const ValueKey('markup_undo'),
              tooltip: 'Undo',
              onPressed: ctrl.canUndo ? ctrl.undo : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              key: const ValueKey('markup_redo'),
              tooltip: 'Redo',
              onPressed: ctrl.canRedo ? ctrl.redo : null,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              key: const ValueKey('markup_layers'),
              tooltip: 'Show / hide layers',
              onPressed: _openLayers,
              icon: const Icon(Icons.layers_outlined),
            ),
            if (editable)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  key: const ValueKey('markup_save'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(60, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: ctrl.dirty && problems.isEmpty
                      ? () => _save(c, s)
                      : null,
                  child: const Text('Save'),
                ),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _hintBar(s, labels, editable),
              if (problems.isNotEmpty)
                Container(
                  key: const ValueKey('markup_invalid'),
                  width: double.infinity,
                  color: const Color(0xFFFFF3E0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AdinnColors.warning,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          problems.values.first.message,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(child: _editor(photo, s, labels, editable, problems)),
              if (ctrl.draft.isNotEmpty && ctrl.drawsPolyline) _draftBar(s),
              if (ctrl.selectedId != null) _contextBar(s, labels, editable),
              if (ctrl.tool == SiteMarkupTool.obstruction && editable)
                _obstructionOptions(),
              _toolBar(editable),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hintBar(Shop s, MarkupLabels labels, bool editable) {
    final usesUnit =
        ctrl.tool == SiteMarkupTool.perspective ||
        ctrl.tool == SiteMarkupTool.marker;
    return Container(
      width: double.infinity,
      color: AdinnColors.canvas,
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              editable
                  ? ctrl.tool.hint
                  : 'Read-only: this recce cannot be edited now.',
              style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
            ),
          ),
          if (editable && usesUnit)
            ActionChip(
              key: const ValueKey('markup_unit'),
              avatar: const Icon(Icons.link, size: 16),
              label: Text(
                labels.labelOf(ctrl.activeUnitId),
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: () async {
                final id = await _pickUnit(s, labels);
                if (id != null) setState(() => ctrl.activeUnitId = id);
              },
            ),
        ],
      ),
    );
  }

  Widget _editor(
    SitePhoto photo,
    Shop s,
    MarkupLabels labels,
    bool editable,
    Map<String, QuadProblem> problems,
  ) {
    final imageSize = Size(photo.width.toDouble(), photo.height.toDouble());
    return Container(
      color: const Color(0xFF202124),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = Size(
            math.max(constraints.maxWidth - _margin * 2, 1),
            math.max(constraints.maxHeight - _margin * 2, 1),
          );
          final fitted = applyBoxFit(
            BoxFit.contain,
            imageSize.isEmpty ? const Size(4, 3) : imageSize,
            available,
          ).destination;
          if (fitted.isEmpty) return const SizedBox.shrink();
          _box = fitted;
          final panning = ctrl.tool == SiteMarkupTool.pan;
          return InteractiveViewer(
            transformationController: _tc,
            minScale: 1,
            maxScale: 6,
            panEnabled: panning,
            scaleEnabled: panning,
            boundaryMargin: const EdgeInsets.all(80),
            child: Center(
              child: SizedBox(
                width: fitted.width + _margin * 2,
                height: fitted.height + _margin * 2,
                child: Stack(
                  children: [
                    Positioned(
                      left: _margin,
                      top: _margin,
                      width: fitted.width,
                      height: fitted.height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          SitePhotoImage(photo),
                          // Classic annotations, read-only for context.
                          CustomPaint(
                            painter: AnnotationPainter(
                              annotations: photo.annotations,
                              imageSize: imageSize,
                            ),
                          ),
                          CustomPaint(
                            key: const ValueKey('markup_painter'),
                            painter: SiteMarkupPainter(
                              markup: ctrl.markup,
                              labels: labels,
                              selectedId: ctrl.selectedId,
                              hiddenLayers: Set.of(ctrl.hidden),
                              showHandles: editable,
                              zoom: _zoom,
                              draftPoints: List.of(ctrl.draft),
                              draftClosed:
                                  ctrl.tool == SiteMarkupTool.obstruction,
                              invalidIds: problems.keys.toSet(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        key: const ValueKey('markup_canvas'),
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onTapUp: panning
                            ? null
                            : (d) => _onTapUp(d, s, labels, editable),
                        onPanStart: panning
                            ? null
                            : (d) => _onPanStart(d, editable),
                        onPanUpdate: panning ? null : _onPanUpdate,
                        onPanEnd: panning ? null : (_) => _onPanEnd(s, labels),
                        onPanCancel: panning
                            ? null
                            : () => _onPanEnd(s, labels),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _draftBar(Shop s) {
    final polygon = ctrl.tool == SiteMarkupTool.obstruction;
    final need = polygon ? 3 : 2;
    return Container(
      color: const Color(0xFFE8F0FE),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${ctrl.draft.length} point(s) – '
              '${polygon ? 'polygon area' : 'cable route'}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          IconButton(
            tooltip: 'Remove last point',
            onPressed: ctrl.removeLastDraftPoint,
            icon: const Icon(Icons.backspace_outlined, size: 20),
          ),
          TextButton(
            key: const ValueKey('markup_draft_cancel'),
            onPressed: ctrl.cancelDraft,
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('markup_draft_done'),
            onPressed: ctrl.draft.length < need
                ? null
                : () async {
                    if (polygon) {
                      final o = ctrl.finishPolygon();
                      final labels = MarkupLabels.forShop(s);
                      if (o != null) await _editObstruction(s, labels, o.id);
                    } else {
                      ctrl.finishCableRoute(unitIds: [?ctrl.activeUnitId]);
                    }
                  },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _contextBar(Shop s, MarkupLabels labels, bool editable) {
    final id = ctrl.selectedId!;
    final kind = ctrl.selectedKind;
    String title;
    final actions = <Widget>[];
    switch (kind) {
      case MarkupKind.perspective:
        final p = ctrl.perspective(id)!;
        title = 'Perspective • ${labels.labelOf(p.unitId)}';
        if (editable) {
          actions.addAll([
            _action('mk_relink', Icons.link, 'Item', () async {
              final u = await _pickUnit(s, labels);
              if (u != null) ctrl.relinkPerspective(id, u);
            }),
            _action(
              'mk_reset_corners',
              Icons.crop_free,
              'Reset',
              () =>
                  ctrl.resetCorners(id, aspect: labels[p.unitId]?.aspect ?? 3),
            ),
            _action(
              'mk_artwork',
              p.showArtwork ? Icons.image : Icons.image_not_supported_outlined,
              p.showArtwork ? 'Artwork' : 'Outline',
              () => ctrl.setArtworkVisible(id, !p.showArtwork),
            ),
          ]);
        }
      case MarkupKind.marker:
        final m = ctrl.marker(id)!;
        title = 'Marker ${m.numberLabel} • ${labels.labelOf(m.unitId)}';
        actions.add(
          _action(
            'mk_details',
            Icons.info_outline,
            'Details',
            () => _markerDetails(s, labels, id),
          ),
        );
      case MarkupKind.electrical:
      case MarkupKind.cable:
        final e = ctrl.electrical(id);
        title = e != null
            ? '${e.code} • ${e.kind.label}'
            : '${ctrl.cable(id)!.code} • Cable route';
        if (editable) {
          actions.add(
            _action(
              'mk_details',
              Icons.edit_note,
              'Details',
              () => _electricalDetails(s, labels, id),
            ),
          );
        }
      case MarkupKind.obstruction:
        final o = ctrl.obstruction(id)!;
        title = '${o.code} • ${o.type.label} (${o.severity.label})';
        if (editable) {
          actions.add(
            _action(
              'mk_details',
              Icons.edit_note,
              'Details',
              () => _editObstruction(s, labels, id),
            ),
          );
        }
      case null:
        return const SizedBox.shrink();
    }
    if (editable) {
      actions.add(
        _action(
          'mk_delete',
          Icons.delete_outline,
          'Delete',
          ctrl.deleteSelected,
          color: AdinnColors.red,
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AdinnColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          ...actions,
          IconButton(
            key: const ValueKey('mk_deselect'),
            tooltip: 'Deselect',
            onPressed: () => ctrl.select(null),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _action(
    String key,
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) => InkWell(
    key: ValueKey(key),
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color ?? AdinnColors.ink),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: color ?? AdinnColors.ink),
          ),
        ],
      ),
    ),
  );

  Widget _obstructionOptions() => Container(
    color: AdinnColors.canvas,
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          DropdownButton<ObstructionType>(
            key: const ValueKey('ob_type'),
            value: ctrl.obstructionType,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final t in ObstructionType.values)
                DropdownMenuItem(
                  value: t,
                  child: Text(t.label, style: const TextStyle(fontSize: 12.5)),
                ),
            ],
            onChanged: (v) => setState(
              () => ctrl.obstructionType = v ?? ctrl.obstructionType,
            ),
          ),
          const SizedBox(width: 8),
          for (final sh in ObstructionShape.values)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                key: ValueKey('ob_shape_${sh.name}'),
                label: Text(switch (sh) {
                  ObstructionShape.point => 'Point',
                  ObstructionShape.rect => 'Rect',
                  ObstructionShape.polygon => 'Polygon',
                  ObstructionShape.arrow => 'Arrow',
                  ObstructionShape.text => 'Text',
                }, style: const TextStyle(fontSize: 12)),
                selected: ctrl.obstructionShape == sh,
                onSelected: (_) => setState(() {
                  ctrl.obstructionShape = sh;
                  ctrl.cancelDraft();
                }),
              ),
            ),
          const SizedBox(width: 8),
          for (final sv in Severity.values)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                key: ValueKey('ob_sev_${sv.name}'),
                label: Text(sv.label, style: const TextStyle(fontSize: 12)),
                selectedColor: severityColor(sv).withValues(alpha: 0.25),
                selected: ctrl.obstructionSeverity == sv,
                onSelected: (_) =>
                    setState(() => ctrl.obstructionSeverity = sv),
              ),
            ),
        ],
      ),
    ),
  );

  static IconData _toolIcon(SiteMarkupTool t) => switch (t) {
    SiteMarkupTool.select => Icons.near_me_outlined,
    SiteMarkupTool.perspective => Icons.crop_rotate,
    SiteMarkupTool.marker => Icons.pin_drop_outlined,
    SiteMarkupTool.electricalPoint => Icons.bolt,
    SiteMarkupTool.switchPoint => Icons.toggle_on_outlined,
    SiteMarkupTool.powerNote => Icons.sticky_note_2_outlined,
    SiteMarkupTool.cableRoute => Icons.timeline,
    SiteMarkupTool.obstruction => Icons.report_problem_outlined,
    SiteMarkupTool.pan => Icons.pan_tool_outlined,
  };

  Widget _toolBar(bool editable) {
    final tools = editable
        ? SiteMarkupTool.values
        : const [SiteMarkupTool.select, SiteMarkupTool.pan];
    return Container(
      height: 62,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AdinnColors.line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            for (final t in tools)
              SizedBox(
                width: 70,
                child: InkWell(
                  key: ValueKey('mtool_${t.name}'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => ctrl.setTool(t),
                  child: Container(
                    decoration: BoxDecoration(
                      color: ctrl.tool == t ? AdinnColors.redLight : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _toolIcon(t),
                          size: 20,
                          color: ctrl.tool == t
                              ? AdinnColors.red
                              : AdinnColors.ink,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: ctrl.tool == t
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: ctrl.tool == t
                                ? AdinnColors.red
                                : AdinnColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
