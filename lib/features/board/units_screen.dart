import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/measurement_fields.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/catalog/site_checklists.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../ar/camera_ar_screen.dart';
import '../photos/photo_workspace_screen.dart';
import '../photos/site_photo_view.dart';
import '../preview_live/preview_gallery.dart';
import '../survey/feasibility.dart';
import '../survey/readiness.dart';
import '../survey/unit_survey_screen.dart';
import '../../core/widgets/adinn_app_bar.dart';

/// Individual signage units of a media group: placement, installation
/// (override + measurements), notes, linked photos and previews per unit.
class UnitsScreen extends StatefulWidget {
  const UnitsScreen({
    super.key,
    required this.shopId,
    required this.boardId,
    this.onOpenPhotoMarkup,
  });

  final String shopId;
  final String boardId;

  /// Opens the advanced photo markup editor from the site survey screen.
  final void Function(BuildContext context, SitePhoto photo)? onOpenPhotoMarkup;

  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen> {
  final Map<String, List<TextEditingController>> _ctl = {};

  @override
  void dispose() {
    for (final list in _ctl.values) {
      for (final c in list) {
        c.dispose();
      }
    }
    super.dispose();
  }

  List<TextEditingController> _controllers(SignageUnit u) => _ctl.putIfAbsent(
    u.id,
    () => [
      TextEditingController(text: u.placement),
      TextEditingController(text: u.installationDetails),
      TextEditingController(text: u.notes),
    ],
  );

  Future<void> _remove(Board b, SignageUnit u) async {
    final c = context.read<AppController>();
    final att = c.unitAttachments(b, [u]);
    final ok = await confirmDialog(
      context,
      title: 'Remove ${b.unitLabel(u)}?',
      message:
          'Quantity becomes ${b.quantity - 1}. '
          '${att.markings} placement marking(s) and ${att.previews} '
          'preview(s) of this unit are deleted; shared photos stay.',
      confirmText: 'Remove',
      destructive: true,
    );
    if (ok) await c.removeUnit(widget.shopId, b, u.id);
  }

  void _openPhoto(Board b, SignageUnit u, SitePhoto p, {int tab = 0}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoWorkspaceScreen(
          shopId: widget.shopId,
          boardId: b.id,
          photoId: p.id,
          initialUnitId: u.id,
          initialTab: tab,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(widget.shopId);
    final b = c.board(widget.shopId, widget.boardId);
    if (shop == null || b == null) {
      return Scaffold(
        appBar: AdinnAppBar(),
        body: const EmptyState(icon: Icons.search_off, title: 'Not found'),
      );
    }
    final editable = c.canEdit(shop);
    final media = SignageCatalog.media(b.mediaCode);
    final issues = c.openIssues(shop).where((i) => i.groupId == b.id).toList();
    return Scaffold(
      appBar: AdinnAppBar(
        title: Text(
          '${media?.shortName ?? b.name} – ${b.quantity} unit${b.quantity == 1 ? '' : 's'}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '${b.name} • ${b.isSameSize ? 'Same size' : 'Different sizes'}',
            style: const TextStyle(color: AdinnColors.muted),
          ),
          const SizedBox(height: 8),
          for (final u in b.activeUnits) ...[
            _unitCard(b, u, editable, issues),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  void _openSurvey(Board b, SignageUnit u) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnitSurveyScreen(
          shopId: widget.shopId,
          boardId: b.id,
          unitId: u.id,
          onOpenPhotoMarkup: widget.onOpenPhotoMarkup,
        ),
      ),
    );
  }

  /// Compact advanced-survey status: checklist, measurements, feasibility.
  Widget _surveyBlock(Board b, SignageUnit u, int i) {
    final st = SiteChecklists.statusOf(b, u);
    final measured = MeasurementCatalog.recorded(b, u).length;
    final f = feasibilityOf(b, u);
    final checklistText = st.total == 0
        ? 'No checklist'
        : (st.isComplete
              ? 'Checklist ${st.answered}/${st.total} • complete'
              : 'Checklist ${st.answered}/${st.total} • '
                    '${st.missingRequired.length} required left');
    return Container(
      key: Key('unit_survey_block_$i'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdinnColors.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdinnColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(context.ui('Site survey'),
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                key: Key('unit_survey_$i'),
                onPressed: () => _openSurvey(b, u),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: Text(context.ui('Open')),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _SurveyTag(
                checklistText,
                icon: Icons.checklist,
                color: st.total == 0
                    ? AdinnColors.muted
                    : (st.isComplete
                          ? AdinnColors.success
                          : (b.checklistRequired
                                ? AdinnColors.red
                                : AdinnColors.warning)),
              ),
              _SurveyTag(
                '$measured measurement${measured == 1 ? '' : 's'}',
                icon: Icons.square_foot,
                color: measured == 0 ? AdinnColors.muted : AdinnColors.info,
              ),
              FeasibilityChip(f.level, compact: true),
              if (context.read<AppController>().shop(widget.shopId)
                  case final shop?)
                ReadinessChip(
                  unitReadiness(shop, b, u).level,
                  key: Key('unit_readiness_$i'),
                ),
            ],
          ),
          if (context.read<AppController>().shop(widget.shopId)
              case final shop?)
            for (final r in unitReadiness(shop, b, u).reasons.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '• $r',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AdinnColors.muted,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _unitCard(
    Board b,
    SignageUnit u,
    bool editable,
    List<RejectionIssue> issues,
  ) {
    final c = context.read<AppController>();
    final i = b.units.indexOf(u);
    final ctl = _controllers(u);
    final photos = b.photosOf(u);
    final allowed = SignageCatalog.selectableInstallations(b);
    final unitIssues = issues.where((x) => x.unitId == u.id).toList();
    final missingSize = !b.unitHasSize(u);
    return SectionCard(
      title: b.unitLabel(u),
      icon: Icons.crop_landscape,
      trailing: TagChip(
        fmtSize(b.widthOf(u), b.heightOf(u), b.unit),
        icon: Icons.straighten,
        color: missingSize ? AdinnColors.warning : AdinnColors.red,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (unitIssues.isNotEmpty) ...[
            for (final x in unitIssues)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.report_gmailerrorred,
                      size: 16,
                      color: AdinnColors.red,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Rejected: ${x.aspect.label}'
                        '${x.note.isEmpty ? '' : ' – ${x.note}'}',
                        style: const TextStyle(
                          color: AdinnColors.red,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
          ],
          TextField(
            key: Key('unit_place_$i'),
            controller: ctl[0],
            enabled: editable,
            decoration: InputDecoration(
              labelText: context.ui('Placement location'),
              hintText: context.ui('e.g. Above entrance / footpath left of gate'),
              prefixIcon: Icon(Icons.place_outlined),
            ),
            onChanged: (t) {
              u.placement = t.trim();
              c.touchUnit(widget.shopId, b, u);
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            key: Key('unit_inst_$i'),
            initialValue: u.installationCode,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.ui('Installation type'),
              prefixIcon: Icon(Icons.construction_outlined),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'Same as group (${SignageCatalog.installation(b.installationCode)?.name ?? 'not set'})',
                ),
              ),
              for (final inst in allowed)
                DropdownMenuItem<String?>(
                  value: inst.code,
                  child: Text(inst.name),
                ),
            ],
            onChanged: editable
                ? (v) {
                    u.installationCode = v;
                    c.touchUnit(
                      widget.shopId,
                      b,
                      u,
                      message:
                          '${b.name} ${b.unitLabel(u)}: installation '
                          '${SignageCatalog.installation(b.installationOf(u))?.name ?? '—'}.',
                    );
                  }
                : null,
          ),
          const SizedBox(height: 10),
          TextField(
            key: Key('unit_inst_details_$i'),
            controller: ctl[1],
            enabled: editable,
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(
              labelText: context.ui('Installation measurements / details'),
              hintText: context.ui('Mount height, pole gap, fixing method…'),
              prefixIcon: Icon(Icons.square_foot),
            ),
            onChanged: (t) {
              u.installationDetails = t.trim();
              c.touchUnit(widget.shopId, b, u);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            key: Key('unit_notes_$i'),
            controller: ctl[2],
            enabled: editable,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              labelText: context.ui('Notes'),
              prefixIcon: Icon(Icons.notes),
            ),
            onChanged: (t) {
              u.notes = t.trim();
              c.touchUnit(widget.shopId, b, u);
            },
          ),
          const SizedBox(height: 10),
          _surveyBlock(b, u, i),
          const Divider(height: 22),
          Text(
            'Photos (${photos.length}) • markings ${b.annotationsOf(u).length}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (photos.isEmpty)
            Text(
              b.photos.isEmpty
                  ? 'No site photos yet – capture them in the board editor.'
                  : 'Not linked to a photo yet. Open a photo below and mark '
                        'this unit (Signage tool) or link it.',
              style: const TextStyle(color: AdinnColors.muted, fontSize: 12.5),
            ),
          SizedBox(
            height: photos.isEmpty && b.photos.isEmpty ? 0 : 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: (photos.isEmpty ? b.photos : photos).length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, k) {
                final p = (photos.isEmpty ? b.photos : photos)[k];
                return InkWell(
                  key: Key('unit_photo_${i}_$k'),
                  onTap: () => _openPhoto(b, u, p),
                  child: SizedBox(
                    width: 120,
                    child: AnnotatedPhotoView(p, cacheWidth: 300),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(context.ui('Live previews & annotated exports'),
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          PreviewGallery(
            board: b,
            shopId: widget.shopId,
            unitId: u.id,
            kinds: const {CaptureKind.live, CaptureKind.edited},
            editable: editable,
            emptyText: 'None saved (optional).',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(context.ui('AR Previews'),
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                key: Key('unit_ar_$i'),
                onPressed: b.mediaCode == null || b.installationOf(u) == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CameraArScreen(
                            shopId: widget.shopId,
                            boardId: b.id,
                            unitId: u.id,
                          ),
                        ),
                      ),
                icon: const Icon(Icons.view_in_ar, size: 18),
                label: Text(
                  b.previewsOf(u).any((c) => c.kind == CaptureKind.ar)
                      ? 'Capture another'
                      : 'Camera AR',
                ),
              ),
            ],
          ),
          PreviewGallery(
            board: b,
            shopId: widget.shopId,
            unitId: u.id,
            kinds: const {CaptureKind.ar},
            editable: editable,
            emptyText: 'No AR captures yet (optional).',
          ),
          if (editable && b.units.length > 1) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('unit_remove_$i'),
                onPressed: () => _remove(b, u),
                icon: const Icon(Icons.delete_outline, color: AdinnColors.red),
                label: Text(context.ui('Remove unit'),
                  style: TextStyle(color: AdinnColors.red),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small status tag whose text wraps instead of overflowing narrow cards.
class _SurveyTag extends StatelessWidget {
  const _SurveyTag(this.text, {required this.icon, required this.color});

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
