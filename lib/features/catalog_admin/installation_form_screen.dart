import 'package:flutter/material.dart';

import '../../core/widgets/input_formats.dart';
import '../live_recce/data/catalog_data.dart';
import 'catalog_admin_controller.dart';
import 'catalog_form_parts.dart';

/// Add or edit one installation type (how a board is fixed: shop fascia, wall mount ...). Returns true when something was saved.
class InstallationFormScreen extends StatefulWidget {
  const InstallationFormScreen({super.key, required this.ctrl, this.installation});

  final CatalogAdminController ctrl;

  /// Null = a new installation type.
  final CatalogInstallation? installation;

  @override
  State<InstallationFormScreen> createState() => _InstallationFormScreenState();
}

class _InstallationFormScreenState extends State<InstallationFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.installation?.code ?? '');
  late final _name = TextEditingController(text: widget.installation?.name ?? '');
  late final _desc = TextEditingController(text: widget.installation?.description ?? '');
  late String _icon = widget.installation?.icon ?? 'category_outlined';
  late bool _active = widget.installation?.active ?? true;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.installation == null;

  @override
  void dispose() {
    for (final c in [_code, _name, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _values() => {
        if (_isNew) 'code': _code.text.trim(),
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'icon': _icon,
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
      err = await widget.ctrl.create(CatalogKind.installations, values);
    } else {
      final changes = changedFields(widget.installation!.toJson(), values, installationEditable);
      if (changes.isEmpty) {
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      err = await widget.ctrl.update(CatalogKind.installations, widget.installation!.code, changes);
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

  @override
  Widget build(BuildContext context) {
    return CatalogFormPage(
      title: _isNew ? 'New installation type' : 'Edit ${widget.installation!.name}',
      formKey: _form,
      busy: _busy,
      error: _error,
      onSave: _save,
      children: [
        TextFormField(
          key: const Key('f-code'),
          controller: _code,
          enabled: _isNew,
          autocorrect: false,
          inputFormatters: codeFormat(max: 40),
          decoration: InputDecoration(labelText: 'Code *', helperText: _isNew ? 'Small letters, digits and _ (2 to 40). Cannot change later.' : 'The code cannot change.'),
          validator: (v) => RegExp(r'^[a-z0-9_]{2,40}$').hasMatch((v ?? '').trim()) ? null : 'Code: 2 to 40 small letters, digits or _',
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: const Key('f-name'),
          controller: _name,
          inputFormatters: safeTextFormat(60),
          decoration: const InputDecoration(labelText: 'Name *'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the name' : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: const Key('f-desc'),
          controller: _desc,
          maxLines: 2,
          inputFormatters: safeTextFormat(200),
          decoration: const InputDecoration(labelText: 'Description', helperText: 'Where and how the board is fixed'),
        ),
        const FormLabel('Icon'),
        CatalogIconPicker(selected: _icon, onChanged: (v) => setState(() => _icon = v)),
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
