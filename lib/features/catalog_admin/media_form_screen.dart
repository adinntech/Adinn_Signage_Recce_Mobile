import 'package:flutter/material.dart';

import '../../core/widgets/input_formats.dart';
import '../live_recce/data/catalog_data.dart';
import 'catalog_admin_controller.dart';
import 'catalog_form_parts.dart';

/// Add or edit one media type (the cards the field person picks a board from). Returns true when something was saved.
/// An edit sends only the fields that changed; the code of an existing media type cannot change.
class MediaFormScreen extends StatefulWidget {
  const MediaFormScreen({super.key, required this.ctrl, this.media});

  final CatalogAdminController ctrl;

  /// Null = a new media type.
  final CatalogMedia? media;

  @override
  State<MediaFormScreen> createState() => _MediaFormScreenState();
}

class _MediaFormScreenState extends State<MediaFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.media?.code ?? '');
  late final _short = TextEditingController(text: widget.media?.shortName ?? '');
  late final _name = TextEditingController(text: widget.media?.name ?? '');
  late final _desc = TextEditingController(text: widget.media?.description ?? '');
  late final _color = TextEditingController(text: (widget.media?.color ?? '#455A64').toUpperCase());
  late final _depth = TextEditingController(text: _num(widget.media?.depthFt));
  late final _thick = TextEditingController(text: _num(widget.media?.thicknessMm));
  late String _icon = widget.media?.icon ?? 'category_outlined';
  late bool _lit = widget.media?.illuminated ?? false;
  late String _sided = widget.media?.sidedness ?? 'SINGLE';
  late bool _active = widget.media?.active ?? true;
  late final List<String> _inst = [...?widget.media?.installations];
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.media == null;

  static String _num(double? v) => v == null || v == 0 ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  @override
  void dispose() {
    for (final c in [_code, _short, _name, _desc, _color, _depth, _thick]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _values() => {
        if (_isNew) 'code': _code.text.trim(),
        'shortName': _short.text.trim(),
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'icon': _icon,
        'color': _color.text.trim().toUpperCase(),
        'illuminated': _lit,
        'sidedness': _sided,
        'depthFt': double.tryParse(_depth.text.trim()) ?? 0.0,
        'thicknessMm': double.tryParse(_thick.text.trim()) ?? 0.0,
        'installations': _inst,
        'active': _active,
      };

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final values = _values();
    setState(() {
      _busy = true;
      _error = null;
    });
    final String? err;
    if (_isNew) {
      err = await widget.ctrl.create(CatalogKind.media, values);
    } else {
      final changes = changedFields(widget.media!.toJson(), values, mediaEditable);
      if (changes.isEmpty) {
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      err = await widget.ctrl.update(CatalogKind.media, widget.media!.code, changes);
    }
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  String? _range(String? v, double max, String what) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = double.tryParse(t);
    if (n == null || n < 0 || n > max) return '$what must be between 0 and ${max.toInt()}';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final installations = widget.ctrl.data.installations;
    return CatalogFormPage(
      title: _isNew ? 'New media type' : 'Edit ${widget.media!.shortName}',
      formKey: _form,
      busy: _busy,
      error: _error,
      onSave: _save,
      children: [
        if (!_isNew && widget.media!.legacy)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('An older media type, kept so old recces stay readable. It is never offered for a new board.', style: TextStyle(color: Colors.black54, fontSize: 13)),
          ),
        TextFormField(
          key: const Key('f-code'),
          controller: _code,
          enabled: _isNew,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          inputFormatters: codeFormat(max: 30, upper: true),
          decoration: InputDecoration(labelText: 'Code *', helperText: _isNew ? 'Capital letters, digits and _ (2 to 30). Cannot change later.' : 'The code cannot change.'),
          validator: (v) => RegExp(r'^[A-Z0-9_]{2,30}$').hasMatch((v ?? '').trim()) ? null : 'Code: 2 to 30 capital letters, digits or _',
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: const Key('f-short'),
          controller: _short,
          inputFormatters: safeTextFormat(30),
          decoration: const InputDecoration(labelText: 'Short name *', helperText: 'Shown on the board number, like GSB-01'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the short name' : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: const Key('f-name'),
          controller: _name,
          inputFormatters: safeTextFormat(80),
          decoration: const InputDecoration(labelText: 'Name *'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the name' : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: const Key('f-desc'),
          controller: _desc,
          maxLines: 2,
          inputFormatters: safeTextFormat(200),
          decoration: const InputDecoration(labelText: 'Description', helperText: 'One or two lines shown on the card'),
        ),
        const FormLabel('Icon'),
        CatalogIconPicker(selected: _icon, onChanged: (v) => setState(() => _icon = v), color: hexColor(_color.text.trim().isEmpty ? '#455A64' : _color.text.trim())),
        const FormLabel('Colour'),
        CatalogColorField(controller: _color, onChanged: () => setState(() {})),
        const FormLabel('Board'),
        SwitchListTile(
          key: const Key('f-lit'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Illuminated (lit board)'),
          value: _lit,
          onChanged: (v) => setState(() => _lit = v),
        ),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          key: const Key('f-sided'),
          segments: const [
            ButtonSegment(value: 'SINGLE', label: Text('Single')),
            ButtonSegment(value: 'DOUBLE', label: Text('Double')),
            ButtonSegment(value: 'SELECTABLE', label: Text('Either')),
          ],
          selected: {_sided},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _sided = s.first),
        ),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextFormField(
              key: const Key('f-depth'),
              controller: _depth,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalFormat(places: 2, maxLength: 5),
              decoration: const InputDecoration(labelText: 'Depth (ft)', helperText: '0 to 20'),
              validator: (v) => _range(v, 20, 'Depth'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              key: const Key('f-thick'),
              controller: _thick,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalFormat(places: 1, maxLength: 5),
              decoration: const InputDecoration(labelText: 'Thickness (mm)', helperText: '0 to 200'),
              validator: (v) => _range(v, 200, 'Thickness'),
            ),
          ),
        ]),
        const FormLabel('Installation methods offered', hint: 'The field person picks one of these for each board. The number shows the order.'),
        if (installations.isEmpty)
          const Text('No installation types yet. Add them on the Installation tab first.', style: TextStyle(color: Colors.black54))
        else
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final i in installations)
              FilterChip(
                key: Key('inst-${i.code}'),
                label: Text(_inst.contains(i.code) ? '${_inst.indexOf(i.code) + 1}. ${i.name}${i.active ? '' : ' (inactive)'}' : '${i.name}${i.active ? '' : ' (inactive)'}'),
                selected: _inst.contains(i.code),
                onSelected: (on) => setState(() => on ? _inst.add(i.code) : _inst.remove(i.code)),
              ),
          ]),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const Key('f-active'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          subtitle: const Text('Off = not offered for a new board; boards that already use it keep it.'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
      ],
    );
  }
}
