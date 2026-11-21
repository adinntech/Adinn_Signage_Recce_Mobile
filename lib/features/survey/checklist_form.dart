import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/site_checklists.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';

/// Picks evidence photos among the media group's photos (ids only; the
/// image files are never copied).
Future<List<String>?> pickEvidencePhotos(
  BuildContext context,
  Board b,
  List<String> selected,
) {
  final chosen = {...selected};
  return showModalBottomSheet<List<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Evidence photos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              if (b.photos.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No photos in this media group yet. Capture them in the '
                    'board editor first.',
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in b.photos)
                      CheckboxListTile(
                        key: Key('evidence_${p.id}'),
                        value: chosen.contains(p.id),
                        title: Text(p.label),
                        onChanged: (v) => setSheet(() {
                          if (v == true) {
                            chosen.add(p.id);
                          } else {
                            chosen.remove(p.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  key: const Key('evidence_done'),
                  onPressed: () => Navigator.pop(ctx, [
                    for (final p in b.photos)
                      if (chosen.contains(p.id)) p.id,
                  ]),
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

/// Media-specific site checklist of one signage item, generated from the
/// configurable [SiteChecklists] definitions.
class ChecklistForm extends StatefulWidget {
  const ChecklistForm({
    super.key,
    required this.shopId,
    required this.board,
    required this.unit,
    required this.editable,
    this.onDirtyChanged,
  });

  final String shopId;
  final Board board;
  final SignageUnit unit;
  final bool editable;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<ChecklistForm> createState() => _ChecklistFormState();
}

class _ChecklistFormState extends State<ChecklistForm>
    with AutomaticKeepAliveClientMixin {
  late Map<String, ChecklistResponse> _draft;
  final Map<String, TextEditingController> _ctl = {};
  final Set<String> _showRemarks = {};
  bool _dirty = false;

  @override
  bool get wantKeepAlive => true;

  Board get _b => widget.board;
  SignageUnit get _u => widget.unit;

  @override
  void initState() {
    super.initState();
    _draft = Map.of(_u.checklist);
    for (final r in _draft.values) {
      final v = r.value;
      if (v is String && v != 'yes' && v != 'no' && v != 'na') {
        _c(r.questionId).text = v;
      } else if (v is num) {
        _c(r.questionId).text = v == v.roundToDouble() ? '${v.toInt()}' : '$v';
      }
      if (r.remarks.isNotEmpty) {
        _c('${r.questionId}#remarks').text = r.remarks;
        _showRemarks.add(r.questionId);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _c(String id) =>
      _ctl.putIfAbsent(id, TextEditingController.new);

  void _markDirty() {
    if (!_dirty) {
      _dirty = true;
      widget.onDirtyChanged?.call(true);
    }
    setState(() {});
  }

  ChecklistResponse _resp(String qid) =>
      _draft[qid] ?? ChecklistResponse(questionId: qid);

  /// Stores [r], dropping it when it carries nothing at all.
  void _put(ChecklistResponse r) {
    if (!r.hasValue && r.remarks.isEmpty && r.evidencePhotoIds.isEmpty) {
      _draft.remove(r.questionId);
    } else {
      _draft[r.questionId] = r;
    }
    _markDirty();
  }

  void _setValue(ChecklistQuestion q, Object? value) {
    final r = _resp(q.id);
    _put(
      value == null ? r.copyWith(clearValue: true) : r.copyWith(value: value),
    );
  }

  void _onText(ChecklistQuestion q, String text) {
    final t = text.trim();
    if (t.isEmpty) {
      _setValue(q, null);
    } else if (q.type == ChecklistResponseType.numeric) {
      _setValue(q, double.tryParse(t) ?? t);
    } else {
      _setValue(q, t);
    }
  }

  void _save() {
    context.read<AppController>().saveChecklist(
      widget.shopId,
      _b,
      _u.id,
      _draft,
    );
    _dirty = false;
    widget.onDirtyChanged?.call(false);
    setState(() {});
    final st = SiteChecklists.statusFor(
      _b.mediaCode,
      _b.installationOf(_u),
      _draft,
    );
    showSnack(
      context,
      st.isComplete
          ? 'Checklist saved – complete'
          : 'Checklist saved – ${st.missingRequired.length} required left',
    );
  }

  Future<void> _copyToAll() async {
    final others = _b.activeUnits.length - 1;
    final ok = await confirmDialog(
      context,
      title: 'Copy answers to all units?',
      message:
          'The answers of ${_b.unitLabel(_u)} replace the checklist of the '
          'other $others unit(s) of ${_b.name}. Evidence photos are not '
          'copied.',
      confirmText: 'Copy',
    );
    if (!ok || !mounted) return;
    final c = context.read<AppController>();
    if (_dirty) _save();
    final n = c.copyChecklistToOtherUnits(widget.shopId, _b, _u.id);
    if (mounted) showSnack(context, 'Answers copied to $n unit(s)');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final def = SiteChecklists.definitionFor(_b.mediaCode);
    final inst = _b.installationOf(_u);
    final qs = SiteChecklists.questionsFor(_b.mediaCode, inst);
    final st = SiteChecklists.statusFor(_b.mediaCode, inst, _draft);
    final applicableIds = qs.map((q) => q.id).toSet();
    final kept = _draft.values
        .where((r) => !applicableIds.contains(r.questionId))
        .toList();

    if (def == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EmptyState(
            icon: Icons.checklist,
            title: 'No checklist for this media type',
            message: _b.mediaCode == null
                ? 'Select the media type of this group first.'
                : 'There is no site checklist configured for this media type.',
          ),
          if (kept.isNotEmpty) _keptSection(kept),
        ],
      );
    }

    return ListView(
      key: const PageStorageKey('survey_checklist_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          def.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        ProgressBarLabel(
          key: const Key('cl_progress'),
          value: st.total == 0 ? 0 : st.answered / st.total,
          label:
              '${st.answered} / ${st.total} answered • '
              '${st.missingRequired.length} required left',
          color: st.isComplete ? AdinnColors.success : AdinnColors.warning,
        ),
        if (!_b.checklistRequired)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Recorded before the checklist was introduced: completing it '
              'is recommended but does not block submission.',
              style: TextStyle(fontSize: 11.5, color: AdinnColors.muted),
            ),
          ),
        if (widget.editable && _b.activeUnits.length > 1)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('cl_copy_all'),
              onPressed: _draft.isEmpty ? null : _copyToAll,
              icon: const Icon(Icons.copy_all, size: 18),
              label: const Text('Copy answers to all units'),
            ),
          ),
        const SizedBox(height: 8),
        for (final q in qs) _question(q),
        if (kept.isNotEmpty) _keptSection(kept),
        if (widget.editable) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('cl_save'),
            onPressed: _dirty ? _save : null,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save checklist'),
          ),
        ],
      ],
    );
  }

  Widget _keptSection(List<ChecklistResponse> kept) => Card(
    child: ExpansionTile(
      key: const Key('cl_kept'),
      title: Text(
        'Answers kept from an earlier configuration (${kept.length})',
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      subtitle: const Text(
        'Not part of the current checklist; kept for history.',
        style: TextStyle(fontSize: 11.5),
      ),
      children: [
        for (final r in kept)
          ListTile(
            dense: true,
            title: Text(_questionText(r.questionId)),
            subtitle: Text(_keptAnswer(r)),
          ),
      ],
    ),
  );

  String _questionText(String id) {
    for (final d in SiteChecklists.definitions) {
      for (final q in d.questions) {
        if (q.id == id) return q.text;
      }
    }
    return id;
  }

  String _keptAnswer(ChecklistResponse r) {
    for (final d in SiteChecklists.definitions) {
      for (final q in d.questions) {
        if (q.id == r.questionId) return q.answerText(r);
      }
    }
    return '${r.value ?? '—'}';
  }

  Widget _question(ChecklistQuestion q) {
    final r = _draft[q.id];
    final answered = q.isAnswered(r);
    return Card(
      key: Key('cl_q_${q.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  answered ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 18,
                  color: answered
                      ? AdinnColors.success
                      : (q.required ? AdinnColors.warning : AdinnColors.muted),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: q.text,
                      children: [
                        if (q.required)
                          const TextSpan(
                            text: ' *',
                            style: TextStyle(color: AdinnColors.red),
                          ),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.editable)
                  IconButton(
                    key: Key('cl_${q.id}_remark_toggle'),
                    tooltip: 'Remarks',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.comment_outlined,
                      size: 18,
                      color: _showRemarks.contains(q.id)
                          ? AdinnColors.red
                          : AdinnColors.muted,
                    ),
                    onPressed: () => setState(() {
                      if (!_showRemarks.remove(q.id)) _showRemarks.add(q.id);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _input(q, r),
            if (_showRemarks.contains(q.id) ||
                (r != null && r.remarks.isNotEmpty)) ...[
              const SizedBox(height: 6),
              TextField(
                key: Key('cl_${q.id}_remarks'),
                controller: _c('${q.id}#remarks'),
                enabled: widget.editable,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Remarks (optional)',
                  isDense: true,
                ),
                onChanged: (t) => _put(_resp(q.id).copyWith(remarks: t.trim())),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _input(ChecklistQuestion q, ChecklistResponse? r) {
    switch (q.type) {
      case ChecklistResponseType.yesNoNa:
        Widget chip(String v, String label) => ChoiceChip(
          key: Key('cl_${q.id}_$v'),
          label: Text(label),
          selected: r?.value == v,
          onSelected: widget.editable
              ? (sel) => _setValue(q, sel ? v : null)
              : null,
        );
        return Wrap(
          spacing: 8,
          children: [
            chip('yes', 'Yes'),
            chip('no', 'No'),
            if (q.allowNa) chip('na', 'N/A'),
          ],
        );
      case ChecklistResponseType.dropdown:
        final current = r?.value;
        return DropdownButtonFormField<String>(
          key: Key('cl_${q.id}'),
          initialValue: current is String && q.options.contains(current)
              ? current
              : (current == 'na' && q.allowNa ? 'na' : null),
          isExpanded: true,
          decoration: const InputDecoration(isDense: true, hintText: 'Select'),
          items: [
            for (final o in q.options)
              DropdownMenuItem(value: o, child: Text(o)),
            if (q.allowNa)
              const DropdownMenuItem(
                value: 'na',
                child: Text('Not applicable'),
              ),
          ],
          onChanged: widget.editable ? (v) => _setValue(q, v) : null,
        );
      case ChecklistResponseType.numeric:
      case ChecklistResponseType.shortText:
      case ChecklistResponseType.longText:
        final numeric = q.type == ChecklistResponseType.numeric;
        final v = r?.value;
        return TextField(
          key: Key('cl_${q.id}'),
          controller: _c(q.id),
          enabled: widget.editable,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          minLines: 1,
          maxLines: q.type == ChecklistResponseType.longText ? 4 : 1,
          decoration: InputDecoration(
            isDense: true,
            suffixText: q.unit,
            errorText: numeric && v is String && double.tryParse(v) == null
                ? 'Enter a number'
                : null,
          ),
          onChanged: (t) => _onText(q, t),
        );
      case ChecklistResponseType.photoEvidence:
        final ids = r?.evidencePhotoIds ?? const <String>[];
        final labels = [
          for (final p in _b.photos)
            if (ids.contains(p.id)) p.label,
        ];
        return Row(
          children: [
            Expanded(
              child: Text(
                labels.isEmpty ? 'No photo selected' : labels.join(', '),
                style: TextStyle(
                  fontSize: 12.5,
                  color: labels.isEmpty ? AdinnColors.muted : AdinnColors.ink,
                ),
              ),
            ),
            OutlinedButton.icon(
              key: Key('cl_${q.id}_photos'),
              onPressed: widget.editable
                  ? () async {
                      final picked = await pickEvidencePhotos(context, _b, ids);
                      if (picked == null || !mounted) return;
                      _put(_resp(q.id).copyWith(evidencePhotoIds: picked));
                    }
                  : null,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(ids.isEmpty ? 'Select' : '${ids.length}'),
            ),
          ],
        );
    }
  }
}
