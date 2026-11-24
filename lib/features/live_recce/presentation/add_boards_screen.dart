import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/input_formats.dart';
import '../../../data/catalog/signage_catalog.dart' show MediaType;
import '../../board/media_type_grid.dart';
import '../data/catalog_data.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';

/// "Add boards": tick one or MORE media types, then for each its quantity and the size of each board. One board is made for every
/// physical unit, each with its own permanent key and number (GSB-01, GSB-02, Acrylic-01 ...), so photos, installation requirement,
/// reviews and rework can point at ONE board. Everything is saved in one go. Returns true when the boards were added and saved.
class AddBoardsScreen extends StatefulWidget {
  const AddBoardsScreen({super.key, required this.ctrl});

  final ShopDetailController ctrl;

  @override
  State<AddBoardsScreen> createState() => _AddBoardsScreenState();
}

/// What is chosen for one ticked media type.
class _Entry {
  _Entry(this.media);

  final CatalogMedia media;
  int qty = 1;
  bool same = true;

  /// Width and height boxes: index 0 serves "same size" (and Board 1 of "different sizes"); more are made as the quantity grows.
  final w = <TextEditingController>[TextEditingController()];
  final h = <TextEditingController>[TextEditingController()];

  void grow(int to) {
    while (w.length < to) {
      w.add(TextEditingController());
      h.add(TextEditingController());
    }
  }

  void dispose() {
    for (final c in [...w, ...h]) {
      c.dispose();
    }
  }
}

class _AddBoardsScreenState extends State<AddBoardsScreen> {
  final _entries = <String, _Entry>{}; // media code -> choice, in the order the types were ticked
  String _unit = 'FT';
  bool _busy = false;
  String? _error;

  ShopDetailController get ctrl => widget.ctrl;
  CatalogData get _catalog => ctrl.catalog;

  /// Boards that can still be added: the shop limit minus what the shop has and what the other ticked types take.
  int _roomFor(_Entry e) => maxBoardItems - ctrl.boards.length - _entries.values.where((x) => x != e).fold<int>(0, (n, x) => n + x.qty);
  int get _total => _entries.values.fold<int>(0, (n, e) => n + e.qty);

  @override
  void dispose() {
    for (final e in _entries.values) {
      e.dispose();
    }
    super.dispose();
  }

  void _toggle(MediaType t) {
    setState(() {
      _error = null;
      final had = _entries.remove(t.code);
      if (had != null) {
        had.dispose();
        return;
      }
      if (ctrl.boards.length + _total >= maxBoardItems) {
        _error = 'A shop can hold $maxBoardItems boards.';
        return;
      }
      final media = _catalog.mediaByCode(t.code);
      if (media != null) _entries[t.code] = _Entry(media);
    });
  }

  void _setQty(_Entry e, int q) {
    final room = _roomFor(e);
    final next = q.clamp(1, room < 1 ? 1 : room);
    e.grow(next);
    setState(() {
      e.qty = next;
      if (next == 1) e.same = true;
      _error = null;
    });
  }

  /// The numbers the boards of [e] will get: GSB-03, GSB-04 ... (after the boards of that type the shop already has).
  List<String> _numbers(_Entry e) {
    final start = nextBoardSeq(ctrl.boards, e.media.shortName);
    return [for (var i = 0; i < e.qty; i++) '${e.media.shortName}-${(start + i).toString().padLeft(2, '0')}'];
  }

  Future<void> _save() async {
    if (_entries.isEmpty || _busy) return;
    final specs = <NewBoards>[];
    final labels = <String>[];
    for (final e in _entries.values) {
      final numbers = _numbers(e);
      final sizes = <({double width, double height})>[];
      for (var i = 0; i < e.qty; i++) {
        final at = e.same ? 0 : i;
        final w = double.tryParse(e.w[at].text.trim()) ?? 0;
        final h = double.tryParse(e.h[at].text.trim()) ?? 0;
        if (w <= 0 || h <= 0) {
          setState(() => _error = e.same ? 'Enter the width and height of ${e.media.shortName}.' : 'Enter the width and height of ${numbers[i]}.');
          return;
        }
        sizes.add((width: w, height: h));
      }
      labels.addAll(numbers);
      specs.add(NewBoards(
        mediaCode: e.media.code,
        mediaType: e.media.shortName,
        name: e.media.name,
        unit: _unit,
        sizes: sizes,
        sided: e.media.sidedness == 'DOUBLE' ? 'DOUBLE' : 'SINGLE',
      ));
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ctrl.addBoards(specs);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    Navigator.of(context).pop(true);
    showSnack(context, labels.length == 1 ? '${labels.first} added. Take its photos now.' : '${labels.join(', ')} added. Take the photos of ${labels.first} first.');
  }

  @override
  Widget build(BuildContext context) {
    final grid = [for (final m in _catalog.offered) m.toMediaType()];
    final picked = _entries.values.map((e) => e.media.shortName).join(', ');
    return Scaffold(
      appBar: AppBar(title: const Text('Add boards')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Step(number: 1, title: 'Media types', subtitle: _entries.isEmpty ? 'Choose one or more media types' : picked, done: _entries.isNotEmpty),
          const SizedBox(height: 10),
          MediaTypeGrid(selected: null, selectedCodes: _entries.keys.toSet(), media: grid, enabled: !_busy, onSelect: _toggle),
          if (_entries.isNotEmpty) ...[
            const SizedBox(height: 22),
            _Step(number: 2, title: 'Quantity and size', subtitle: '$_total board${_total == 1 ? '' : 's'}, one number each', done: false),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const Key('add-unit'),
              initialValue: _unit,
              decoration: const InputDecoration(labelText: 'Unit (all boards)'),
              items: [for (final u in boardUnits) DropdownMenuItem(value: u, child: Text(u))],
              onChanged: _busy ? null : (v) => setState(() => _unit = v ?? 'FT'),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: Text('${ctrl.boards.length + _total} of $maxBoardItems boards in this shop.', style: const TextStyle(color: AdinnColors.muted, fontSize: 12.5)),
            ),
            for (final e in _entries.values) ...[
              _TypeCard(
                entry: e,
                numbers: _numbers(e),
                unit: _unit,
                busy: _busy,
                canAdd: _roomFor(e) > e.qty,
                onQty: (q) => _setQty(e, q),
                onSame: (v) => setState(() => e.same = v),
              ),
              const SizedBox(height: 12),
            ],
            if (_error != null) Text(_error!, key: const Key('add-boards-error'), style: const TextStyle(color: AdinnColors.red, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('add-boards-save'),
              onPressed: _busy ? null : _save,
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
              label: Text(_total == 1 ? 'Add ${_numbers(_entries.values.first).first}' : 'Add $_total boards'),
            ),
          ] else if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, key: const Key('add-boards-error'), style: const TextStyle(color: AdinnColors.red, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.entry, required this.numbers, required this.unit, required this.busy, required this.canAdd, required this.onQty, required this.onSame});

  final _Entry entry;
  final List<String> numbers;
  final String unit;
  final bool busy;
  final bool canAdd;
  final ValueChanged<int> onQty;
  final ValueChanged<bool> onSame;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final code = e.media.code;
    return Container(
      key: Key('type-card-$code'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AdinnColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(catalogIcon(e.media.icon), color: hexColor(e.media.color)),
          const SizedBox(width: 8),
          Expanded(child: Text('${e.media.shortName}  ·  ${e.media.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton.outlined(key: Key('qty-minus-$code'), onPressed: busy || e.qty <= 1 ? null : () => onQty(e.qty - 1), icon: const Icon(Icons.remove)),
          SizedBox(width: 52, child: Center(child: Text('${e.qty}', key: Key('qty-value-$code'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)))),
          IconButton.outlined(key: Key('qty-plus-$code'), onPressed: busy || !canAdd ? null : () => onQty(e.qty + 1), icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: 8),
        if (e.qty > 1) ...[
          SegmentedButton<bool>(
            key: Key('same-size-$code'),
            segments: const [
              ButtonSegment(value: true, label: Text('Same size for all'), icon: Icon(Icons.copy_all_outlined)),
              ButtonSegment(value: false, label: Text('Different sizes'), icon: Icon(Icons.straighten)),
            ],
            selected: {e.same},
            onSelectionChanged: busy ? null : (s) => onSame(s.first),
          ),
          const SizedBox(height: 10),
        ],
        if (e.same)
          _SizeRow(label: e.qty == 1 ? numbers.first : 'All ${numbers.length} boards (${numbers.first} to ${numbers.last})', w: e.w[0], h: e.h[0], unit: unit, enabled: !busy, keySuffix: '$code-0')
        else
          for (var i = 0; i < e.qty; i++) ...[
            _SizeRow(label: numbers[i], w: e.w[i], h: e.h[i], unit: unit, enabled: !busy, keySuffix: '$code-$i'),
            const SizedBox(height: 10),
          ],
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.subtitle, required this.done});
  final int number;
  final String title;
  final String subtitle;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      CircleAvatar(
        radius: 16,
        backgroundColor: AdinnColors.red,
        child: done ? const Icon(Icons.check, size: 18, color: Colors.white) : Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
        ]),
      ),
    ]);
  }
}

class _SizeRow extends StatelessWidget {
  const _SizeRow({required this.label, required this.w, required this.h, required this.unit, required this.enabled, required this.keySuffix});
  final String label;
  final TextEditingController w;
  final TextEditingController h;
  final String unit;
  final bool enabled;
  final String keySuffix;

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String text, String key) => TextField(
          key: Key('$key-$keySuffix'),
          controller: c,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalFormat(places: 2, maxLength: 8),
          decoration: InputDecoration(labelText: '$text (${unit.toLowerCase()}) *'),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Row(children: [Expanded(child: field(w, 'Width', 'width')), const SizedBox(width: 10), Expanded(child: field(h, 'Height', 'height'))]),
    ]);
  }
}
