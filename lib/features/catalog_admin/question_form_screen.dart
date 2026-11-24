import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/widgets/input_formats.dart';
import '../live_recce/data/catalog_data.dart';
import 'catalog_admin_controller.dart';
import 'catalog_form_parts.dart';

const questionTypes = [
  ('TEXT', 'Text', Icons.short_text),
  ('NUMBER', 'Number', Icons.numbers),
  ('YES_NO', 'Yes / No', Icons.toggle_on_outlined),
  ('CHOICE', 'Choice', Icons.checklist),
];

String questionTypeLabel(String type) => questionTypes.firstWhere((t) => t.$1 == type, orElse: () => questionTypes.first).$2;

/// Add or edit one site question of a group (every board, one media type, or one installation type). Returns true when something was saved.
/// The group, the key and the type of an existing question cannot change (answers are stored under the key and its type).
class QuestionFormScreen extends StatefulWidget {
  const QuestionFormScreen({super.key, required this.ctrl, required this.scope, required this.scopeCode, this.question});

  final CatalogAdminController ctrl;

  /// COMMON, MEDIA or INSTALLATION, and the media / installation code ('' for COMMON): the group the question belongs to.
  final String scope;
  final String scopeCode;

  /// Null = a new question.
  final CatalogQuestion? question;

  @override
  State<QuestionFormScreen> createState() => _QuestionFormScreenState();
}

class _QuestionFormScreenState extends State<QuestionFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _key = TextEditingController(text: widget.question?.id ?? '');
  late final _label = TextEditingController(text: widget.question?.label ?? '');
  late final _unit = TextEditingController(text: widget.question?.unit ?? '');
  late final _hint = TextEditingController(text: widget.question?.hint ?? '');
  late final _opt = TextEditingController();
  late final _showText = TextEditingController(text: _showInitialText());
  late String _type = widget.question?.type ?? 'TEXT';
  late bool _required = widget.question?.required ?? true;
  late bool _active = widget.question?.active ?? true;
  late final List<String> _options = [...?widget.question?.options];
  late String? _showId = widget.question?.showIfId;
  late Object? _showValue = widget.question?.showIfValue;
  bool _busy = false;
  String? _error;
  String? _optionError;

  bool get _isNew => widget.question == null;

  String _showInitialText() {
    final v = widget.question?.showIfValue;
    return v == null || v is bool ? '' : '$v';
  }

  @override
  void dispose() {
    for (final c in [_key, _label, _unit, _hint, _opt, _showText]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The questions this one may depend on: the ones every board gets and the ones of its own group, except itself.
  List<CatalogQuestion> get _candidates {
    final seen = <String>{};
    return [
      for (final q in widget.ctrl.data.questions)
        if ((q.scope == 'COMMON' || (q.scope == widget.scope && q.scopeCode == widget.scopeCode)) && q.id != (widget.question?.id ?? _key.text.trim()) && seen.add(q.id)) q,
    ];
  }

  CatalogQuestion? get _showQuestion => _candidates.where((q) => q.id == _showId).firstOrNull;

  void _addOption() {
    final t = _opt.text.trim();
    if (t.isEmpty) return;
    if (_options.any((o) => o.toLowerCase() == t.toLowerCase())) {
      setState(() => _optionError = 'This option is already in the list');
      return;
    }
    if (_options.length >= 20) {
      setState(() => _optionError = 'At most 20 options');
      return;
    }
    setState(() {
      _options.add(t);
      _opt.clear();
      _optionError = null;
    });
  }

  Map<String, dynamic> _values() => {
        'scope': widget.scope,
        'scopeCode': widget.scope == 'COMMON' ? '' : widget.scopeCode,
        'id': _isNew ? _key.text.trim() : widget.question!.id,
        'label': _label.text.trim(),
        'type': _type,
        'options': _type == 'CHOICE' ? _options : <String>[],
        'unit': _type == 'NUMBER' && _unit.text.trim().isNotEmpty ? _unit.text.trim() : null,
        'required': _required,
        'hint': _hint.text.trim().isEmpty ? null : _hint.text.trim(),
        'showIfId': _showId,
        'showIfValue': _showId == null ? null : _showValue,
        'active': _active,
      };

  String? _problem() {
    if (_type == 'CHOICE' && _options.length < 2) return 'A choice question needs at least two options.';
    if (_showId != null && (_showValue == null || (_showValue is String && (_showValue as String).trim().isEmpty))) return 'Say which answer shows this question.';
    return null;
  }

  Future<void> _save() async {
    final formOk = _form.currentState!.validate();
    final problem = _problem();
    if (!formOk || problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (_busy) return;
    final values = _values();
    setState(() {
      _busy = true;
      _error = null;
    });
    final String? err;
    if (_isNew) {
      err = await widget.ctrl.create(CatalogKind.questions, values);
    } else {
      final changes = changedFields(widget.question!.toJson(), values, questionEditable);
      if (changes.isEmpty) {
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      err = await widget.ctrl.update(CatalogKind.questions, widget.question!.uid, changes);
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

  String get _groupLabel {
    if (widget.scope == 'COMMON') return 'Every board';
    if (widget.scope == 'MEDIA') return 'Media type: ${widget.ctrl.data.mediaByCode(widget.scopeCode)?.name ?? widget.scopeCode}';
    return 'Installation: ${widget.ctrl.data.installationByCode(widget.scopeCode)?.name ?? widget.scopeCode}';
  }

  @override
  Widget build(BuildContext context) {
    final showQ = _showQuestion;
    return CatalogFormPage(
      title: _isNew ? 'New question' : 'Edit question',
      formKey: _form,
      busy: _busy,
      error: _error,
      onSave: _save,
      children: [
        Align(alignment: Alignment.centerLeft, child: TagChip(_groupLabel, icon: Icons.account_tree_outlined, color: AdinnColors.info)),
        const SizedBox(height: 14),
        TextFormField(
          key: const Key('f-key'),
          controller: _key,
          enabled: _isNew,
          autocorrect: false,
          inputFormatters: codeFormat(max: 50),
          decoration: InputDecoration(labelText: 'Key *', helperText: _isNew ? 'Small letters, digits and _ (2 to 50). The answer is stored under it. Cannot change later.' : 'The key cannot change.'),
          validator: (v) => RegExp(r'^[a-z0-9_]{2,50}$').hasMatch((v ?? '').trim()) ? null : 'Key: 2 to 50 small letters, digits or _',
          onChanged: (_) => setState(() {}),
        ),
        const FormLabel('Answer type'),
        if (_isNew)
          Wrap(spacing: 8, children: [
            for (final t in questionTypes)
              ChoiceChip(
                key: Key('type-${t.$1}'),
                avatar: Icon(t.$3, size: 18),
                label: Text(t.$2),
                selected: _type == t.$1,
                onSelected: (_) => setState(() => _type = t.$1),
              ),
          ])
        else
          Align(alignment: Alignment.centerLeft, child: TagChip('${questionTypeLabel(_type)} (cannot change)', icon: Icons.lock_outline)),
        const SizedBox(height: 14),
        TextFormField(
          key: const Key('f-label'),
          controller: _label,
          maxLines: 2,
          inputFormatters: safeTextFormat(120),
          decoration: const InputDecoration(labelText: 'Question *', helperText: 'What the field person reads'),
          validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the question (at least 2 letters)' : null,
        ),
        if (_type == 'CHOICE') ...[
          const FormLabel('Options', hint: 'At least two, at most 20.'),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final o in _options) InputChip(key: Key('opt-$o'), label: Text(o), onDeleted: () => setState(() => _options.remove(o))),
          ]),
          const SizedBox(height: 8),
          TextField(
            key: const Key('f-option'),
            controller: _opt,
            inputFormatters: safeTextFormat(60),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addOption(),
            decoration: InputDecoration(labelText: 'New option', errorText: _optionError, suffixIcon: IconButton(key: const Key('add-option'), tooltip: 'Add option', icon: const Icon(Icons.add_circle_outline), onPressed: _addOption)),
          ),
        ],
        if (_type == 'NUMBER') ...[
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('f-unit'),
            controller: _unit,
            inputFormatters: safeTextFormat(10),
            decoration: const InputDecoration(labelText: 'Unit', helperText: 'Like ft, mm or kg (up to 10 letters)'),
          ),
        ],
        const SizedBox(height: 14),
        TextFormField(
          key: const Key('f-hint'),
          controller: _hint,
          inputFormatters: safeTextFormat(120),
          decoration: const InputDecoration(labelText: 'Hint', helperText: 'A short help line under the question'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(key: const Key('f-required'), contentPadding: EdgeInsets.zero, title: const Text('Required'), subtitle: const Text('The field person must answer it before submitting.'), value: _required, onChanged: (v) => setState(() => _required = v)),
        SwitchListTile(key: const Key('f-active'), contentPadding: EdgeInsets.zero, title: const Text('Active'), subtitle: const Text('Off = not asked any more; old answers stay.'), value: _active, onChanged: (v) => setState(() => _active = v)),
        const FormLabel('Show only if', hint: 'Leave empty to always ask this question.'),
        DropdownButtonFormField<String?>(
          key: const Key('f-showid'),
          initialValue: _candidates.any((q) => q.id == _showId) ? _showId : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Another question'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Always ask')),
            for (final q in _candidates) DropdownMenuItem<String?>(value: q.id, child: Text('${q.label} (${q.id})', maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() {
            _showId = v;
            _showValue = null;
            _showText.clear();
          }),
        ),
        if (showQ != null) ...[
          const SizedBox(height: 10),
          Text('is answered', style: const TextStyle(color: AdinnColors.muted, fontSize: 13)),
          const SizedBox(height: 6),
          _showValueInput(showQ),
        ],
      ],
    );
  }

  /// The answer of the other question that shows this one, drawn to match that question's type.
  Widget _showValueInput(CatalogQuestion q) {
    switch (q.type) {
      case 'YES_NO':
        return Wrap(spacing: 8, children: [
          for (final v in const [true, false]) ChoiceChip(key: Key('show-$v'), label: Text(v ? 'Yes' : 'No'), selected: _showValue == v, onSelected: (_) => setState(() => _showValue = v)),
        ]);
      case 'CHOICE':
        return Wrap(spacing: 8, runSpacing: 4, children: [
          for (final o in q.options) ChoiceChip(key: Key('show-$o'), label: Text(o), selected: _showValue == o, onSelected: (_) => setState(() => _showValue = o)),
        ]);
      case 'NUMBER':
        return TextField(
          key: const Key('f-showvalue'),
          controller: _showText,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalFormat(places: 2, maxLength: 8),
          decoration: const InputDecoration(labelText: 'Number'),
          onChanged: (t) => _showValue = double.tryParse(t),
        );
      default:
        return TextField(
          key: const Key('f-showvalue'),
          controller: _showText,
          inputFormatters: safeTextFormat(60),
          decoration: const InputDecoration(labelText: 'Answer'),
          onChanged: (t) => _showValue = t.trim().isEmpty ? null : t.trim(),
        );
    }
  }
}
