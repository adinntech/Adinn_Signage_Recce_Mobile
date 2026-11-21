import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/measurement_fields.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import 'measurement_diagram.dart';

Color issueColor(MeasureIssueLevel l) => switch (l) {
  MeasureIssueLevel.error => AdinnColors.red,
  MeasureIssueLevel.warning => AdinnColors.warning,
  MeasureIssueLevel.review => AdinnColors.info,
};

IconData issueIcon(MeasureIssueLevel l) => switch (l) {
  MeasureIssueLevel.error => Icons.error_outline,
  MeasureIssueLevel.warning => Icons.warning_amber_rounded,
  MeasureIssueLevel.review => Icons.flag_outlined,
};

/// Advanced measurements of one signage item (canonical millimetres).
/// Board width / height are only shown here: they stay owned by the media
/// group's Measurements step.
class MeasurementForm extends StatefulWidget {
  const MeasurementForm({
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
  State<MeasurementForm> createState() => _MeasurementFormState();
}

class _MeasurementFormState extends State<MeasurementForm>
    with AutomaticKeepAliveClientMixin {
  late MeasurementDetails _draft;
  final Map<String, TextEditingController> _ctl = {};

  /// Field ids whose text is not a valid number.
  final Set<String> _badInput = {};
  bool _dirty = false;

  /// Draft restored from the device after an interrupted session.
  bool _restored = false;

  String get _draftKey => 'measure:${widget.unit.id}';
  late final AppController _app = context.read<AppController>();

  @override
  bool get wantKeepAlive => true;

  Board get _b => widget.board;
  SignageUnit get _u => widget.unit;

  @override
  void initState() {
    super.initState();
    _draft = _u.measurements.copy();
    if (_u.measurements.isEmpty) _draft.unit = _b.unit;
    // Restore unsaved values kept on the device (app closed mid-entry).
    final saved = widget.editable ? _app.formDraft(_draftKey) : null;
    if (saved != null) {
      _draft = MeasurementDetails.fromJson(saved);
      _restored = true;
      _dirty = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDirtyChanged?.call(true);
      });
    }
    _syncControllers();
  }

  void _discardDraft() {
    _app.clearFormDraft(_draftKey);
    setState(() {
      _draft = _u.measurements.copy();
      if (_u.measurements.isEmpty) _draft.unit = _b.unit;
      _restored = false;
      _dirty = false;
      _syncControllers();
    });
    widget.onDirtyChanged?.call(false);
  }

  @override
  void deactivate() {
    // The form only leaves the tree when the user leaves the screen (after
    // saving or confirming "Discard"), so the device draft is no longer
    // needed. A killed app never gets here – its draft survives for
    // restore on the next visit.
    _app.clearFormDraft(_draftKey);
    super.deactivate();
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

  /// Rewrites every field's text from the stored values (used on load and
  /// when the display unit changes – values are converted from the stored
  /// millimetres, so switching units never accumulates rounding).
  void _syncControllers() {
    for (final f in MeasurementCatalog.fields) {
      switch (f.kind) {
        case MeasureFieldKind.length:
          final mm = _draft.valuesMm[f.id];
          _c(f.id).text = mm == null ? '' : fmtMmValue(mm, _draft.unit);
        case MeasureFieldKind.count:
          final n = _draft.counts[f.id];
          _c(f.id).text = n == null ? '' : '${n.toInt()}';
        case MeasureFieldKind.text:
          _c(f.id).text = _draft.texts[f.id] ?? '';
        case MeasureFieldKind.flag:
          break;
      }
    }
    _badInput.clear();
  }

  void _markDirty() {
    if (!_dirty) {
      _dirty = true;
      widget.onDirtyChanged?.call(true);
    }
    if (widget.editable) {
      _app.saveFormDraft(_draftKey, _draft.toJson());
    }
    setState(() {});
  }

  void _onText(MeasurementField f, String text) {
    final t = text.trim();
    _badInput.remove(f.id);
    switch (f.kind) {
      case MeasureFieldKind.length:
        if (t.isEmpty) {
          _draft.valuesMm.remove(f.id);
        } else {
          final mm = parseLengthMm(t, _draft.unit);
          if (mm == null) {
            _badInput.add(f.id);
            _draft.valuesMm.remove(f.id);
          } else {
            _draft.valuesMm[f.id] = mm;
          }
        }
      case MeasureFieldKind.count:
        if (t.isEmpty) {
          _draft.counts.remove(f.id);
        } else {
          final n = double.tryParse(t);
          if (n == null || !n.isFinite) {
            _badInput.add(f.id);
            _draft.counts.remove(f.id);
          } else {
            _draft.counts[f.id] = n;
          }
        }
      case MeasureFieldKind.text:
        if (t.isEmpty) {
          _draft.texts.remove(f.id);
        } else {
          _draft.texts[f.id] = t;
        }
      case MeasureFieldKind.flag:
        break;
    }
    _markDirty();
  }

  void _setUnit(MeasureUnit unit) {
    if (unit == _draft.unit) return;
    _draft.unit = unit;
    _syncControllers();
    _markDirty();
  }

  /// Copies the standee answers of the site questions (ft) into the draft.
  void _useAnswers() {
    const map = {
      'overall_height': 'standee_overall_height',
      'base_width': 'base_width',
      'base_depth': 'base_depth',
    };
    var n = 0;
    for (final e in map.entries) {
      final v = _b.answers[e.key];
      if (v is num && v > 0) {
        _draft.valuesMm[e.value] = MeasureUnit.ft.toMm(v.toDouble());
        n++;
      }
    }
    _syncControllers();
    _markDirty();
    showSnack(
      context,
      n == 0
          ? 'No standee values answered in the site questions yet'
          : '$n value(s) copied from the site questions – review and save',
    );
  }

  void _save() {
    final c = context.read<AppController>();
    final issues = c.saveMeasurements(widget.shopId, _b, _u.id, _draft);
    if (issues.any((i) => i.isError)) {
      showSnack(
        context,
        issues.firstWhere((i) => i.isError).message,
        error: true,
      );
      setState(() {});
      return;
    }
    c.clearFormDraft(_draftKey);
    _dirty = false;
    _restored = false;
    widget.onDirtyChanged?.call(false);
    setState(() {});
    showSnack(
      context,
      issues.isEmpty
          ? 'Measurements saved'
          : 'Measurements saved with ${issues.length} warning(s)',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ctx = MeasurementCatalog.contextOf(_b, _u, _draft);
    final fields = MeasurementCatalog.fieldsFor(ctx);
    final issues = MeasurementCatalog.validate(_b, _u, _draft);
    final hasErrors = issues.any((i) => i.isError) || _badInput.isNotEmpty;
    final w = _b.widthOf(_u), h = _b.heightOf(_u);
    final groups = <MeasureGroup, List<MeasurementField>>{};
    for (final f in fields) {
      groups.putIfAbsent(f.group, () => []).add(f);
    }

    return ListView(
      key: const PageStorageKey('survey_measure_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_restored)
          Container(
            key: const Key('m_draft_restored'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.restore, size: 18, color: AdinnColors.info),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Unsaved measurements from your last session were '
                    'restored. Review and save.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
                TextButton(
                  key: const Key('m_draft_discard'),
                  onPressed: _discardDraft,
                  child: const Text('Discard'),
                ),
              ],
            ),
          ),
        SectionCard(
          title: 'Board size (from media group)',
          icon: Icons.straighten,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(
                'Width',
                (w ?? 0) > 0 ? '${fmtNum(w!)} ${_b.unit.label}' : 'Not set',
              ),
              InfoRow(
                'Height',
                (h ?? 0) > 0 ? '${fmtNum(h!)} ${_b.unit.label}' : 'Not set',
              ),
              const Text(
                'Board width / height are edited in the media group\'s '
                'Measurements step and are never changed here.',
                style: TextStyle(fontSize: 12, color: AdinnColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Enter values in',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            DropdownButton<MeasureUnit>(
              key: const Key('m_unit'),
              value: _draft.unit,
              onChanged: widget.editable
                  ? (v) {
                      if (v != null) _setUnit(v);
                    }
                  : null,
              items: [
                for (final unit in MeasureUnit.values)
                  DropdownMenuItem(value: unit, child: Text(unit.label)),
              ],
            ),
          ],
        ),
        if (ctx.installationCode == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Select the installation type of this unit first – the '
              'relevant measurement fields depend on it.',
              style: TextStyle(color: AdinnColors.warning),
            ),
          ),
        if (ctx.installationCode == SignageCatalog.freeStanding &&
            widget.editable)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('m_use_answers'),
              onPressed: _useAnswers,
              icon: const Icon(Icons.input, size: 18),
              label: const Text('Use site question values'),
            ),
          ),
        for (final g in groups.entries)
          if (g.key == MeasureGroup.model)
            // Advanced construction values (3D model): collapsed until
            // needed, expanded automatically when any value is recorded.
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                // Own storage id: the list's PageStorageKey keeps the scroll
                // offset, which must not be read back as expansion state.
                key: const PageStorageKey<String>('m_group_model'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: g.value.any(
                  (f) =>
                      _draft.valuesMm.containsKey(f.id) ||
                      _draft.counts.containsKey(f.id),
                ),
                title: Text(
                  '${g.key.label} – advanced',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AdinnColors.red,
                  ),
                ),
                subtitle: const Text(
                  'Depth, thickness, letters, GSB panel… used by the 3D '
                  'model and drawings',
                  style: TextStyle(fontSize: 11.5),
                ),
                children: [for (final f in g.value) _field(f)],
              ),
            )
          else ...[
            const SizedBox(height: 8),
            Text(
              g.key.label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AdinnColors.red,
              ),
            ),
            const SizedBox(height: 6),
            for (final f in g.value) _field(f),
          ],
        const SizedBox(height: 12),
        SectionCard(
          title: 'Measurement diagram',
          icon: Icons.architecture,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1.25,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    border: Border.all(color: AdinnColors.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CustomPaint(
                    key: const Key('m_diagram'),
                    painter: MeasurementDiagramPainter(
                      MeasurementDiagramData.of(_b, _u, _draft),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Schematic, not to scale where values are missing. All values '
                'are user-entered; site photos are never used to estimate '
                'real-world size.',
                style: TextStyle(fontSize: 11.5, color: AdinnColors.muted),
              ),
            ],
          ),
        ),
        if (issues.isNotEmpty || _badInput.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Checks',
            icon: Icons.rule,
            child: Column(
              key: const Key('m_issues'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final id in _badInput)
                  _issueRow(
                    MeasurementIssue(
                      MeasureIssueLevel.error,
                      '${MeasurementCatalog.field(id)?.label ?? id}: enter a '
                      'valid number',
                      fieldId: id,
                    ),
                  ),
                for (final i in issues) _issueRow(i),
                const SizedBox(height: 4),
                const Text(
                  'Warnings flag values for review only; they are not '
                  'structural approvals or construction limits.',
                  style: TextStyle(fontSize: 11, color: AdinnColors.muted),
                ),
              ],
            ),
          ),
        ],
        if (widget.editable) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('m_save'),
            onPressed: hasErrors || !_dirty ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(hasErrors ? 'Fix errors to save' : 'Save measurements'),
          ),
          if (_dirty)
            const Padding(
              key: Key('m_draft_indicator'),
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Draft auto-saved on this device – tap Save to update the '
                'recce.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AdinnColors.muted),
              ),
            ),
        ],
      ],
    );
  }

  Widget _issueRow(MeasurementIssue i) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(issueIcon(i.level), size: 16, color: issueColor(i.level)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            i.message,
            style: TextStyle(fontSize: 12.5, color: issueColor(i.level)),
          ),
        ),
      ],
    ),
  );

  Widget _field(MeasurementField f) {
    if (f.kind == MeasureFieldKind.flag) {
      return SwitchListTile(
        key: Key('m_${f.id}'),
        contentPadding: EdgeInsets.zero,
        title: Text(f.label),
        value: _draft.flags[f.id] == true,
        onChanged: widget.editable
            ? (v) {
                _draft.flags[f.id] = v;
                _markDirty();
              }
            : null,
      );
    }
    final fieldErrors = MeasurementCatalog.validate(
      _b,
      _u,
      _draft,
    ).where((i) => i.isError && i.fieldId == f.id).toList();
    final bad = _badInput.contains(f.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: Key('m_${f.id}'),
        controller: _c(f.id),
        enabled: widget.editable,
        keyboardType: switch (f.kind) {
          MeasureFieldKind.length => const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          MeasureFieldKind.count => TextInputType.number,
          _ => TextInputType.text,
        },
        inputFormatters: f.kind == MeasureFieldKind.count
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))]
            : null,
        decoration: InputDecoration(
          labelText: f.label,
          hintText: f.hint,
          suffixText: f.kind == MeasureFieldKind.length
              ? _draft.unit.label
              : null,
          errorText: bad
              ? 'Enter a valid number'
              : (fieldErrors.isEmpty ? null : fieldErrors.first.message),
          isDense: true,
        ),
        onChanged: (t) => _onText(f, t),
      ),
    );
  }
}
