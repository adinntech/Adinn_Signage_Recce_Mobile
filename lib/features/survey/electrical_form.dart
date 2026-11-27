import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/measurement_fields.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import 'checklist_form.dart' show pickEvidencePhotos;
import 'site_markup_painter.dart' show kElectricalColor;

/// Photos of [b] that show unit [u] (falls back to every photo of the
/// group when none is linked yet).
List<SitePhoto> surveyPhotosFor(Board b, SignageUnit u) {
  final linked = b.photosOf(u);
  return linked.isEmpty ? b.photos : linked;
}

/// Electrical marks / cable routes on the group's photos that concern [u]:
/// linked to it, or unlinked on a photo that shows it.
List<(SitePhoto, String, String)> electricalMarksFor(Board b, SignageUnit u) {
  final shows = b.photosOf(u).map((p) => p.id).toSet();
  bool concerns(SitePhoto p, List<String> ids) =>
      ids.contains(u.id) || (ids.isEmpty && shows.contains(p.id));
  return [
    for (final p in b.photos) ...[
      for (final e in p.markup.electrical)
        if (concerns(p, e.unitIds))
          (
            p,
            e.code,
            '${e.kind.label}${e.notes.isEmpty ? '' : ' – ${e.notes}'}',
          ),
      for (final r in p.markup.cableRoutes)
        if (concerns(p, r.unitIds))
          (p, r.code, 'Cable route${r.notes.isEmpty ? '' : ' – ${r.notes}'}'),
    ],
  ];
}

/// Electrical availability survey of one signage item. Operational record
/// only – not an electrical safety certification or load calculation.
class ElectricalForm extends StatefulWidget {
  const ElectricalForm({
    super.key,
    required this.shopId,
    required this.board,
    required this.unit,
    required this.editable,
    this.onDirtyChanged,
    this.onOpenPhotoMarkup,
  });

  final String shopId;
  final Board board;
  final SignageUnit unit;
  final bool editable;
  final ValueChanged<bool>? onDirtyChanged;
  final void Function(BuildContext context, SitePhoto photo)? onOpenPhotoMarkup;

  @override
  State<ElectricalForm> createState() => _ElectricalFormState();
}

class _ElectricalFormState extends State<ElectricalForm>
    with AutomaticKeepAliveClientMixin {
  TriState? _available;
  TriState? _point;
  double? _distanceMm;
  late MeasureUnit _distUnit;
  List<String> _photos = [];
  bool _badDistance = false;
  bool _dirty = false;
  final _location = TextEditingController();
  final _distance = TextEditingController();
  final _cable = TextEditingController();
  final _switch = TextEditingController();
  final _remarks = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  Board get _b => widget.board;
  SignageUnit get _u => widget.unit;

  @override
  void initState() {
    super.initState();
    final e = _u.electrical;
    _available = e.electricityAvailable;
    _point = e.pointAvailable;
    _distanceMm = e.distanceMm;
    _distUnit = _b.unit;
    _photos = [...e.evidencePhotoIds];
    _location.text = e.pointLocation;
    _cable.text = e.cableRouteNotes;
    _switch.text = e.switchLocation;
    _remarks.text = e.remarks;
    _distance.text = _distanceMm == null
        ? ''
        : fmtMmValue(_distanceMm!, _distUnit);
  }

  @override
  void dispose() {
    for (final c in [_location, _distance, _cable, _switch, _remarks]) {
      c.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) {
      _dirty = true;
      widget.onDirtyChanged?.call(true);
    }
    setState(() {});
  }

  void _save() {
    context.read<AppController>().saveElectrical(
      widget.shopId,
      _b,
      _u.id,
      ElectricalSurvey(
        electricityAvailable: _available,
        pointAvailable: _point,
        pointLocation: _location.text.trim(),
        distanceMm: _distanceMm,
        cableRouteNotes: _cable.text.trim(),
        switchLocation: _switch.text.trim(),
        remarks: _remarks.text.trim(),
        evidencePhotoIds: _photos,
      ),
    );
    _dirty = false;
    widget.onDirtyChanged?.call(false);
    setState(() {});
    showSnack(context, context.ui('Electrical survey saved'));
  }

  Widget _tri(String prefix, TriState? value, ValueChanged<TriState?> set) =>
      Wrap(
        spacing: 8,
        children: [
          for (final t in TriState.values)
            ChoiceChip(
              key: Key('${prefix}_${t.name}'),
              label: Text(context.ui(t.label)),
              selected: value == t,
              onSelected: widget.editable
                  ? (sel) {
                      set(sel ? t : null);
                      _markDirty();
                    }
                  : null,
            ),
        ],
      );

  Widget _text(
    String key,
    TextEditingController c,
    String label, {
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      key: Key(key),
      controller: c,
      enabled: widget.editable,
      minLines: 1,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (_) => _markDirty(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final media = SignageCatalog.media(_b.mediaCode);
    final marks = electricalMarksFor(_b, _u);
    final photoLabels = [
      for (final p in _b.photos)
        if (_photos.contains(p.id)) p.label,
    ];
    return ListView(
      key: const PageStorageKey('survey_electrical_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kElectricalColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${media?.illuminated == true ? 'Recommended for illuminated media (${media!.shortName}). ' : ''}'
            'Records electrical availability seen on site. This is not an '
            'electrical safety certification and no load calculation is '
            'made.',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
        Text(context.ui('Electricity available'),
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        _tri('el_available', _available, (v) => _available = v),
        const SizedBox(height: 10),
        Text(context.ui('Electrical point available'),
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        _tri('el_point', _point, (v) => _point = v),
        const SizedBox(height: 12),
        _text('el_point_location', _location, 'Electrical point location'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('el_distance'),
                controller: _distance,
                enabled: widget.editable,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: context.ui('Approx. distance from board'),
                  isDense: true,
                  suffixText: context.ui(_distUnit.label),
                  errorText: _badDistance ? 'Enter a distance ≥ 0' : null,
                ),
                onChanged: (t) {
                  final mm = parseLengthMm(t, _distUnit);
                  _badDistance = t.trim().isNotEmpty && (mm == null || mm < 0);
                  _distanceMm = _badDistance ? null : mm;
                  _markDirty();
                },
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<MeasureUnit>(
              key: const Key('el_distance_unit'),
              value: _distUnit,
              onChanged: widget.editable
                  ? (v) {
                      if (v == null) return;
                      setState(() {
                        _distUnit = v;
                        if (_distanceMm != null) {
                          _distance.text = fmtMmValue(_distanceMm!, v);
                        }
                      });
                    }
                  : null,
              items: [
                for (final m in MeasureUnit.values)
                  DropdownMenuItem(value: m, child: Text(context.ui(m.label))),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        _text('el_cable_notes', _cable, 'Cable route notes', maxLines: 3),
        _text('el_switch', _switch, 'Switch location'),
        _text('el_remarks', _remarks, 'Electrical supply remarks', maxLines: 3),
        Row(
          children: [
            Expanded(
              child: Text(
                photoLabels.isEmpty
                    ? 'No evidence photo'
                    : 'Evidence: ${photoLabels.join(', ')}',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            OutlinedButton.icon(
              key: const Key('el_photos'),
              onPressed: widget.editable
                  ? () async {
                      final picked = await pickEvidencePhotos(
                        context,
                        _b,
                        _photos,
                      );
                      if (picked == null || !mounted) return;
                      _photos = picked;
                      _markDirty();
                    }
                  : null,
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: Text(context.ui('Evidence')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Marked on photos',
          icon: Icons.bolt,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (marks.isEmpty)
                Text(context.ui('No electrical point, switch or cable route marked for this '
                  'item yet.'),
                  style: TextStyle(fontSize: 12.5, color: AdinnColors.muted),
                ),
              for (final (p, code, text) in marks)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: kElectricalColor,
                    child: Text(
                      code.split('-').first,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AdinnColors.ink,
                      ),
                    ),
                  ),
                  title: Text('$code • ${p.label}'),
                  subtitle: Text(text),
                ),
              if (widget.onOpenPhotoMarkup != null && widget.editable)
                MarkOnPhotoButtons(
                  prefix: 'el_mark',
                  photos: surveyPhotosFor(_b, _u),
                  onOpen: widget.onOpenPhotoMarkup!,
                ),
            ],
          ),
        ),
        if (widget.editable) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('el_save'),
            onPressed: _dirty && !_badDistance ? _save : null,
            icon: const Icon(Icons.save_outlined),
            label: Text(context.ui('Save electrical survey')),
          ),
        ],
      ],
    );
  }
}

/// "Mark on (photo)" buttons opening the photo markup editor.
class MarkOnPhotoButtons extends StatelessWidget {
  const MarkOnPhotoButtons({
    super.key,
    required this.prefix,
    required this.photos,
    required this.onOpen,
  });

  final String prefix;
  final List<SitePhoto> photos;
  final void Function(BuildContext context, SitePhoto photo) onOpen;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(context.ui('Capture a site photo to mark it.'),
          style: TextStyle(fontSize: 12, color: AdinnColors.muted),
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final p in photos)
          ActionChip(
            key: Key('${prefix}_${p.id}'),
            avatar: const Icon(Icons.edit_location_alt_outlined, size: 16),
            label: Text(context.uf('Mark on {0}', [p.label])),
            onPressed: () => onOpen(context, p),
          ),
      ],
    );
  }
}
