import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/input_formats.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';

const _restrictionChoices = ['Narrow lane', 'Heavy traffic', 'Permission needed', 'Overhead wires', 'No parking', 'Time limited'];

/// Installation feasibility: Yes / No / Not assessed for each question. Not assessed is never read as No.
class InstallationTab extends StatefulWidget {
  const InstallationTab({super.key, required this.ctrl, this.onNext});

  final ShopDetailController ctrl;

  /// "Continue": opens the next step (Review). The tab has optional fields below the five questions, so it does not jump away by
  /// itself the moment the fifth answer is given; the person taps this when done.
  final VoidCallback? onNext;

  @override
  State<InstallationTab> createState() => _InstallationTabState();
}

class _InstallationTabState extends State<InstallationTab> {
  late final _height = TextEditingController(text: _num(widget.ctrl.installation.installationHeightFt));
  late final _notes = TextEditingController(text: widget.ctrl.installation.notes);

  static String _num(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  @override
  void dispose() {
    _height.dispose();
    _notes.dispose();
    super.dispose();
  }

  Installation get _i => widget.ctrl.installation;

  void _set(VoidCallback f) {
    f();
    widget.ctrl.markDirty();
  }

  @override
  Widget build(BuildContext context) {
    final en = widget.ctrl.canEdit;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Installation feasibility', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        const Text('Answer every question marked *. Choose "Not assessed" only if you could not check it.', style: TextStyle(color: AdinnColors.muted, fontSize: 13)),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            children: [
              _TriRow('Ladder required *', _i.ladderRequired, en, (v) => _set(() => _i.ladderRequired = v)),
              _TriRow('Scaffolding required *', _i.scaffoldingRequired, en, (v) => _set(() => _i.scaffoldingRequired = v)),
              _TriRow('Crane required *', _i.craneRequired, en, (v) => _set(() => _i.craneRequired = v)),
              _TriRow('Hydra required *', _i.hydraRequired, en, (v) => _set(() => _i.hydraRequired = v)),
              _TriRow('Manual installation possible *', _i.manualInstallationPossible, en, (v) => _set(() => _i.manualInstallationPossible = v)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Site details',
          icon: Icons.electrical_services_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Electrical access', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'AVAILABLE', label: Text('Available')),
                  ButtonSegment(value: 'NOT_AVAILABLE', label: Text('Not available')),
                  ButtonSegment(value: triUnknown, label: Text('Not assessed')),
                ],
                selected: {_i.electricalAccess},
                showSelectedIcon: false,
                onSelectionChanged: en ? (s) => _set(() => _i.electricalAccess = s.first) : null,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _height,
                enabled: en,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: decimalFormat(places: 1, maxLength: 5),
                // Empty = cleared: the draft then sends an explicit null so the server removes the stored height. Above 500 ft the server
                // refuses it, so the person is told here, before saving.
                decoration: InputDecoration(labelText: 'Installation height (ft)', suffixText: 'ft', helperText: 'Up to 500 ft. Leave empty if not measured.', errorText: _i.heightProblem),
                onChanged: (v) => _set(() => _i.installationHeightFt = double.tryParse(v)),
              ),
              const SizedBox(height: 14),
              const Text('Access restrictions', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final r in _restrictionChoices)
                    FilterChip(
                      label: Text(r),
                      selected: _i.accessRestrictions.contains(r),
                      onSelected: en
                          ? (on) => _set(() => on ? _i.accessRestrictions.add(r) : _i.accessRestrictions.remove(r))
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _notes,
                enabled: en,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Installation notes'),
                onChanged: (v) => _set(() => _i.notes = v),
              ),
            ],
          ),
        ),
        if (widget.onNext != null) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('install-next'),
            onPressed: _i.unanswered.isEmpty ? widget.onNext : null,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue to Review'),
          ),
          if (_i.unanswered.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Still to answer: ${_i.unanswered.join(', ')}', key: const Key('install-open'), textAlign: TextAlign.center, style: const TextStyle(color: AdinnColors.muted, fontSize: 12.5)),
            ),
        ],
      ],
    );
  }
}

class _TriRow extends StatelessWidget {
  const _TriRow(this.label, this.value, this.enabled, this.onChanged);

  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: triYes, label: Text('Yes')),
              ButtonSegment(value: triNo, label: Text('No')),
              ButtonSegment(value: triUnknown, label: Text('Not assessed')),
            ],
            selected: {value},
            showSelectedIcon: false,
            onSelectionChanged: enabled ? (s) => onChanged(s.first) : null,
          ),
        ],
      ),
    );
  }
}
