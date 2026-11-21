import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import 'checklist_form.dart';
import 'electrical_form.dart';
import 'feasibility.dart';
import 'measurement_form.dart';
import 'site_markup_painter.dart' show severityColor;

/// Advanced site survey of one signage item: measurements, media-specific
/// checklist, electrical availability and obstructions / feasibility.
/// Each tab keeps an editable draft and saves explicitly.
class UnitSurveyScreen extends StatefulWidget {
  const UnitSurveyScreen({
    super.key,
    required this.shopId,
    required this.boardId,
    required this.unitId,
    this.initialTab = 0,
    this.onOpenPhotoMarkup,
  });

  final String shopId;
  final String boardId;
  final String unitId;
  final int initialTab;

  /// Opens the advanced markup editor for a photo (perspective, markers,
  /// electrical, obstructions). Hidden when null.
  final void Function(BuildContext context, SitePhoto photo)? onOpenPhotoMarkup;

  @override
  State<UnitSurveyScreen> createState() => _UnitSurveyScreenState();
}

class _UnitSurveyScreenState extends State<UnitSurveyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 3),
  );
  final Set<int> _dirty = {};

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _setDirty(int tab, bool dirty) {
    final changed = dirty ? _dirty.add(tab) : _dirty.remove(tab);
    if (changed && mounted) setState(() {});
  }

  Future<void> _onPop(bool didPop, Object? result) async {
    if (didPop) return;
    final ok = await confirmDialog(
      context,
      title: 'Discard unsaved changes?',
      message:
          'Some survey details on this screen have not been saved. '
          'Leave without saving?',
      confirmText: 'Discard',
      destructive: true,
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(widget.shopId);
    final b = c.board(widget.shopId, widget.boardId);
    final u = b?.unitById(widget.unitId);
    if (shop == null || b == null || u == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'Signage item not found',
        ),
      );
    }
    final editable = c.canEdit(shop);
    final media = SignageCatalog.media(b.mediaCode);
    final inst = SignageCatalog.installation(b.installationOf(u));
    final title = '${media?.shortName ?? b.name} – ${b.unitLabel(u)}';
    return PopScope(
      canPop: _dirty.isEmpty,
      onPopInvokedWithResult: _onPop,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                key: const Key('survey_title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                [
                  fmtSize(b.widthOf(u), b.heightOf(u), b.unit),
                  inst?.name ?? 'Installation not set',
                  if (!editable) 'Read only',
                ].join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
              ),
            ],
          ),
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AdinnColors.red,
            indicatorColor: AdinnColors.red,
            tabs: [
              _tab('survey_tab_measure', 'Measurements', 0),
              _tab('survey_tab_checklist', 'Checklist', 1),
              _tab('survey_tab_electrical', 'Electrical', 2),
              _tab('survey_tab_obstructions', 'Obstructions', 3),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            MeasurementForm(
              shopId: widget.shopId,
              board: b,
              unit: u,
              editable: editable,
              onDirtyChanged: (d) => _setDirty(0, d),
            ),
            ChecklistForm(
              shopId: widget.shopId,
              board: b,
              unit: u,
              editable: editable,
              onDirtyChanged: (d) => _setDirty(1, d),
            ),
            ElectricalForm(
              shopId: widget.shopId,
              board: b,
              unit: u,
              editable: editable,
              onDirtyChanged: (d) => _setDirty(2, d),
              onOpenPhotoMarkup: widget.onOpenPhotoMarkup,
            ),
            ObstructionSummary(
              board: b,
              unit: u,
              editable: editable,
              onOpenPhotoMarkup: widget.onOpenPhotoMarkup,
            ),
          ],
        ),
      ),
    );
  }

  Tab _tab(String key, String text, int i) => Tab(
    key: Key(key),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        if (_dirty.contains(i)) ...[
          const SizedBox(width: 4),
          const Icon(Icons.circle, size: 7, color: AdinnColors.warning),
        ],
      ],
    ),
  );
}

/// Site feasibility indicator + obstructions concerning one signage item.
class ObstructionSummary extends StatelessWidget {
  const ObstructionSummary({
    super.key,
    required this.board,
    required this.unit,
    required this.editable,
    this.onOpenPhotoMarkup,
  });

  final Board board;
  final SignageUnit unit;
  final bool editable;
  final void Function(BuildContext context, SitePhoto photo)? onOpenPhotoMarkup;

  @override
  Widget build(BuildContext context) {
    final f = feasibilityOf(board, unit);
    final list = obstructionsFor(board, unit);
    String photoLabel(String? id) =>
        board.photos.where((p) => p.id == id).firstOrNull?.label ??
        'Missing photo';
    return ListView(
      key: const PageStorageKey('survey_obstruction_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        SectionCard(
          title: 'Site feasibility',
          icon: Icons.fact_check_outlined,
          trailing: FeasibilityChip(f.level, key: const Key('ob_feasibility')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (f.reasons.isEmpty)
                const Text(
                  'No obstruction or review flag recorded for this item.',
                  style: TextStyle(fontSize: 12.5),
                ),
              for (final r in f.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('• $r', style: const TextStyle(fontSize: 12.5)),
                ),
              const SizedBox(height: 6),
              const Text(
                'Operational indicator only – not a structural, electrical or '
                'municipal certification.',
                style: TextStyle(fontSize: 11.5, color: AdinnColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Obstructions (${list.length})',
          icon: Icons.report_problem_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (list.isEmpty)
                const Text(
                  'No obstruction marked on the photos of this item.',
                  style: TextStyle(fontSize: 12.5, color: AdinnColors.muted),
                ),
              for (final (p, o) in list)
                Container(
                  key: Key('ob_${o.id}'),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: severityColor(o.severity).withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${o.code} ${o.type.label}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TagChip(
                            o.severity.label,
                            color: severityColor(o.severity),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Photo: ${p.label} • ${o.shape.label}'
                        '${o.unitIds.isEmpty ? ' • whole photo' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdinnColors.muted,
                        ),
                      ),
                      if (o.remarks.trim().isNotEmpty)
                        Text(
                          o.remarks.trim(),
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      if (o.evidencePhotoId != null)
                        Text(
                          'Evidence: ${photoLabel(o.evidencePhotoId)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
              if (onOpenPhotoMarkup != null && editable)
                MarkOnPhotoButtons(
                  prefix: 'ob_mark',
                  photos: surveyPhotosFor(board, unit),
                  onOpen: onOpenPhotoMarkup!,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
