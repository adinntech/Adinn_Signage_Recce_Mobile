import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';

/// Renders the dynamic site questions for the selected media + installation.
/// Questions with `showIf` rules appear/disappear as answers change.
class SiteQuestionsForm extends StatefulWidget {
  const SiteQuestionsForm({
    super.key,
    required this.questions,
    required this.answers,
    required this.onChanged,
    this.enabled = true,
  });

  final List<SiteQuestion> questions;
  final Map<String, dynamic> answers;
  final void Function(String id, Object? value) onChanged;
  final bool enabled;

  @override
  State<SiteQuestionsForm> createState() => _SiteQuestionsFormState();
}

class _SiteQuestionsFormState extends State<SiteQuestionsForm> {
  final _ctrls = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(SiteQuestion q) {
    return _ctrls.putIfAbsent(q.id, () {
      final v = widget.answers[q.id];
      final text = v == null
          ? ''
          : v is num
          ? fmtNum(v.toDouble())
          : '$v';
      return TextEditingController(text: text);
    });
  }

  Widget _label(SiteQuestion q, bool missing) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              text: q.label,
              children: [
                if (q.required)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: AdinnColors.red),
                  ),
              ],
            ),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        if (missing)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(
              Icons.error_outline,
              size: 16,
              color: AdinnColors.warning,
            ),
          ),
      ],
    );
  }

  Widget _input(SiteQuestion q) {
    final value = widget.answers[q.id];
    switch (q.type) {
      case QuestionType.yesNo:
        return Wrap(
          spacing: 8,
          children: [
            for (final opt in const [true, false])
              ChoiceChip(
                key: Key('q_${q.id}_$opt'),
                label: Text(opt ? 'Yes' : 'No'),
                selected: value == opt,
                onSelected: widget.enabled
                    ? (_) => widget.onChanged(q.id, opt)
                    : null,
              ),
          ],
        );
      case QuestionType.choice:
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final opt in q.options)
              ChoiceChip(
                key: Key('q_${q.id}_$opt'),
                label: Text(opt),
                selected: value == opt,
                onSelected: widget.enabled
                    ? (_) => widget.onChanged(q.id, opt)
                    : null,
              ),
          ],
        );
      case QuestionType.number:
        return TextField(
          key: Key('q_${q.id}'),
          controller: _ctrl(q),
          enabled: widget.enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          decoration: InputDecoration(
            isDense: true,
            hintText: q.hint ?? 'Enter value',
            suffixText: q.unit,
          ),
          onChanged: (t) => widget.onChanged(q.id, double.tryParse(t)),
        );
      case QuestionType.text:
        return TextField(
          key: Key('q_${q.id}'),
          controller: _ctrl(q),
          enabled: widget.enabled,
          decoration: InputDecoration(isDense: true, hintText: q.hint),
          onChanged: (t) => widget.onChanged(q.id, t.trim().isEmpty ? null : t),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.questions
        .where((q) => q.isVisible(widget.answers))
        .toList();
    if (visible.isEmpty) {
      return const Text(
        'Select media and installation type to load site questions.',
        style: TextStyle(color: AdinnColors.muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final q in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(q, q.required && !q.isAnswered(widget.answers)),
                const SizedBox(height: 6),
                _input(q),
              ],
            ),
          ),
      ],
    );
  }
}
