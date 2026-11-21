import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../survey/markup_entry.dart';
import 'units_screen.dart';

final _numFmt = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))];

String? _sizeError(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null) return 'Invalid number';
  if (v <= 0) return 'Must be greater than 0';
  return null;
}

/// Quantity-based dimension workflow of a media group:
/// * quantity 1 → the normal width × height form, nothing else asked;
/// * quantity ≥ 2 → "Are all signage units the same size?"
///   - same size: one width × height applied to every unit;
///   - different sizes: width × height per unit.
/// Increasing the quantity only adds units; decreasing asks for
/// confirmation and lists what will be removed.
class QuantitySizeSection extends StatefulWidget {
  const QuantitySizeSection({
    super.key,
    required this.shopId,
    required this.board,
    required this.w,
    required this.h,
    required this.enabled,
    required this.onChanged,
  });

  final String shopId;
  final Board board;

  /// Shared width / height controllers (owned by the board editor).
  final TextEditingController w;
  final TextEditingController h;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  State<QuantitySizeSection> createState() => _QuantitySizeSectionState();
}

class _QuantitySizeSectionState extends State<QuantitySizeSection> {
  final Map<String, (TextEditingController, TextEditingController)> _unitCtl =
      {};

  Board get b => widget.board;

  @override
  void dispose() {
    for (final (w, h) in _unitCtl.values) {
      w.dispose();
      h.dispose();
    }
    super.dispose();
  }

  (TextEditingController, TextEditingController) _ctlFor(SignageUnit u) =>
      _unitCtl.putIfAbsent(
        u.id,
        () => (
          TextEditingController(text: u.width == null ? '' : fmtNum(u.width!)),
          TextEditingController(
            text: u.height == null ? '' : fmtNum(u.height!),
          ),
        ),
      );

  void _resyncUnitControllers() {
    for (final u in b.units) {
      final c = _unitCtl[u.id];
      if (c == null) continue;
      c.$1.text = u.width == null ? '' : fmtNum(u.width!);
      c.$2.text = u.height == null ? '' : fmtNum(u.height!);
    }
  }

  void _resyncShared() {
    widget.w.text = b.width == null ? '' : fmtNum(b.width!);
    widget.h.text = b.height == null ? '' : fmtNum(b.height!);
  }

  String get _media => SignageCatalog.media(b.mediaCode)?.shortName ?? b.name;

  Future<void> _setQuantity(int next) async {
    final c = context.read<AppController>();
    next = next.clamp(1, AppController.maxQuantity);
    if (next == b.quantity) return;
    if (next > b.quantity) {
      c.increaseQuantity(widget.shopId, b, next);
      widget.onChanged();
      setState(() {});
      return;
    }
    final removed = c.unitsRemovedBy(b, next);
    final att = c.unitAttachments(b, removed);
    final details = [
      if (att.photos > 0) '${att.photos} linked photo(s) will be unlinked',
      if (att.markings > 0) '${att.markings} placement marking(s) deleted',
      if (att.previews > 0) '${att.previews} preview / AR capture(s) deleted',
      if (att.notes > 0) '${att.notes} unit(s) with placement / notes',
    ];
    final ok = await confirmDialog(
      context,
      title: 'Reduce quantity to $next?',
      message:
          'These units will be removed: '
          '${removed.map(b.unitLabel).join(', ')}.'
          '${details.isEmpty ? '' : '\n\n• ${details.join('\n• ')}'}'
          '\n\nShared site photos stay. Earlier submitted versions keep '
          'their copy.',
      confirmText: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await c.reduceQuantity(widget.shopId, b, next);
    _resyncShared();
    widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _typeQuantity() async {
    final ctl = TextEditingController(text: '${b.quantity}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How many signage units are required?'),
        content: TextField(
          key: const Key('qty_input'),
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Quantity'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('qty_ok'),
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    ).whenComplete(ctl.dispose);
    if (v == null || !mounted) return;
    if (v < 1) {
      showSnack(context, 'Quantity must be at least 1', error: true);
      return;
    }
    await _setQuantity(v);
  }

  Future<void> _setMode(SizeMode mode) async {
    final c = context.read<AppController>();
    if (mode == b.sizeMode) return;
    if (mode == SizeMode.different) {
      c.setSizeMode(widget.shopId, b, SizeMode.different);
      _resyncUnitControllers();
      widget.onChanged();
      setState(() {});
      return;
    }
    // Different → same: ask whose size applies to every unit.
    final units = b.activeUnits;
    final sizes = units.map((u) => (u.width, u.height)).toSet();
    String? from = units.first.id;
    if (sizes.length > 1) {
      from = await showDialog<String>(
        context: context,
        builder: (ctx) {
          var pick = units.first.id;
          return StatefulBuilder(
            builder: (ctx, setDlg) => AlertDialog(
              title: const Text('Apply which size to all units?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final u in units)
                    ListTile(
                      key: Key('size_from_${b.unitLabel(u)}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        pick == u.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: AdinnColors.red,
                      ),
                      title: Text(b.unitLabel(u)),
                      subtitle: Text(fmtSize(u.width, u.height, b.unit)),
                      onTap: () => setDlg(() => pick = u.id),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const Key('size_from_ok'),
                  onPressed: () => Navigator.pop(ctx, pick),
                  child: const Text('Apply to all'),
                ),
              ],
            ),
          );
        },
      );
      if (from == null || !mounted) return;
    }
    c.setSizeMode(widget.shopId, b, SizeMode.same, fromUnitId: from);
    _resyncShared();
    widget.onChanged();
    setState(() {});
  }

  Widget _sizeRow({
    required Key wKey,
    required Key hKey,
    required TextEditingController w,
    required TextEditingController h,
    required ValueChanged<String> onW,
    required ValueChanged<String> onH,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: wKey,
            controller: w,
            enabled: widget.enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _numFmt,
            decoration: InputDecoration(
              labelText: 'Width *',
              suffixText: b.unit.label,
              errorText: _sizeError(w.text),
            ),
            onChanged: (t) {
              onW(t);
              setState(() {});
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 14, 8, 0),
          child: Text('×', style: TextStyle(fontSize: 20)),
        ),
        Expanded(
          child: TextField(
            key: hKey,
            controller: h,
            enabled: widget.enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _numFmt,
            decoration: InputDecoration(
              labelText: 'Height *',
              suffixText: b.unit.label,
              errorText: _sizeError(h.text),
            ),
            onChanged: (t) {
              onH(t);
              setState(() {});
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<AppController>();
    final multi = b.quantity > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'How many signage units are required?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton.outlined(
              key: const Key('qty_minus'),
              tooltip: 'Decrease',
              onPressed: widget.enabled && b.quantity > 1
                  ? () => _setQuantity(b.quantity - 1)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            InkWell(
              key: const Key('qty_value'),
              onTap: widget.enabled ? _typeQuantity : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Text(
                  '${b.quantity}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            IconButton.outlined(
              key: const Key('qty_plus'),
              tooltip: 'Increase',
              onPressed:
                  widget.enabled && b.quantity < AppController.maxQuantity
                  ? () => _setQuantity(b.quantity + 1)
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (b.mediaCode == SignageCatalog.doubleStandee)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'Quantity = physical double-sided standees (each has 2 faces).',
              style: TextStyle(fontSize: 11.5, color: AdinnColors.muted),
            ),
          ),
        if (multi) ...[
          const SizedBox(height: 12),
          const Text(
            'Are all signage units the same size?',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SegmentedButton<SizeMode>(
            segments: const [
              ButtonSegment(
                value: SizeMode.same,
                label: Text('Yes – Same Size', key: Key('size_same')),
              ),
              ButtonSegment(
                value: SizeMode.different,
                label: Text('No – Different Sizes', key: Key('size_diff')),
              ),
            ],
            selected: {b.sizeMode},
            onSelectionChanged: widget.enabled
                ? (s) => _setMode(s.first)
                : null,
          ),
        ],
        const SizedBox(height: 12),
        if (b.isSameSize) ...[
          _sizeRow(
            wKey: const Key('board_width'),
            hKey: const Key('board_height'),
            w: widget.w,
            h: widget.h,
            onW: (t) {
              b.width = double.tryParse(t);
              widget.onChanged();
            },
            onH: (t) {
              b.height = double.tryParse(t);
              widget.onChanged();
            },
          ),
          if (multi)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Applied to all ${b.quantity} units. Placement, installation, '
                'photos and notes stay separate per unit.',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AdinnColors.muted,
                ),
              ),
            ),
        ] else
          for (var i = 0; i < b.activeUnits.length; i++) ...[
            Text(
              '$_media – ${b.unitLabel(b.activeUnits[i])}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Builder(
              builder: (context) {
                final u = b.activeUnits[i];
                final (wc, hc) = _ctlFor(u);
                return _sizeRow(
                  wKey: Key('unit_w_$i'),
                  hKey: Key('unit_h_$i'),
                  w: wc,
                  h: hc,
                  onW: (t) {
                    c.setUnitSize(
                      widget.shopId,
                      b,
                      u,
                      width: double.tryParse(t),
                      height: u.height,
                    );
                    widget.onChanged();
                  },
                  onH: (t) {
                    c.setUnitSize(
                      widget.shopId,
                      b,
                      u,
                      width: u.width,
                      height: double.tryParse(t),
                    );
                    widget.onChanged();
                  },
                );
              },
            ),
            const SizedBox(height: 10),
          ],
        if (b.hasSize) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AdinnColors.canvas,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              b.isSameSize
                  ? 'Size ${fmtLength(b.widthFt, MeasureUnit.ft)} × '
                        '${fmtLength(b.heightFt, MeasureUnit.ft)} • '
                        'Area ${fmtNum(b.areaSqFt)} sq ft'
                        '${b.quantity > 1 ? ' (×${b.quantity})' : ''}'
                  : '${b.quantity} units, different sizes • '
                        'Total area ${fmtNum(b.areaSqFt)} sq ft',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('open_units'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => UnitsScreen(
                shopId: widget.shopId,
                boardId: b.id,
                onOpenPhotoMarkup: (ctx, p) =>
                    openPhotoMarkup(ctx, widget.shopId, p),
              ),
            ),
          ),
          icon: const Icon(Icons.view_list_outlined),
          label: Text(
            multi
                ? 'Unit details (${b.quantity}) – placement, installation, notes'
                : 'Unit details – placement, installation, notes',
          ),
        ),
      ],
    );
  }
}
