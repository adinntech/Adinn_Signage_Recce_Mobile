import '../../core/utils/formatters.dart';
import '../../data/catalog/measurement_fields.dart';
import '../../data/catalog/question_equivalence.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/catalog/site_checklists.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../model3d/signage_spec.dart';
import '../model3d/technical_drawing.dart';
import '../survey/feasibility.dart';

/// Title printed on every measurement report.
const kReportTitle = 'ADINN SIGNAGE – SITE RECCE REPORT';

/// Banner text of every report that is not finally approved.
const kDraftBanner = 'DRAFT – NOT APPROVED FOR FABRICATION';

/// What kind of picture an image reference points at.
enum ReportImageKind { photo, annotated, file, drawing2d, model3d }

/// An image the PDF needs. The report data only stores the [key] and
/// caption; the bytes are resolved when the PDF is generated.
class ReportImageRef {
  const ReportImageRef({
    required this.key,
    required this.kind,
    required this.caption,
    this.boardId,
    this.photoId,
    this.path,
    this.unitId,
    this.view,
  });

  /// Signage item for [ReportImageKind.drawing2d] / [ReportImageKind.model3d].
  final String? unitId;

  /// Drawing view name (front, side, top, installation).
  final String? view;

  final String key;
  final ReportImageKind kind;
  final String caption;
  final String? boardId;
  final String? photoId;

  /// File path for [ReportImageKind.file].
  final String? path;

  Map<String, dynamic> toJson() => {
    'key': key,
    'kind': kind.name,
    'caption': caption,
    'boardId': ?boardId,
    'photoId': ?photoId,
    'path': ?path,
    'unitId': ?unitId,
    'view': ?view,
  };
}

/// Immutable report data (stored as [RecceReport.snapshot]) plus the
/// images to resolve and the shop the content was taken from.
class ReportBuild {
  const ReportBuild({
    required this.data,
    required this.images,
    required this.source,
  });

  final Map<String, dynamic> data;
  final List<ReportImageRef> images;

  /// Live shop (draft) or the latest submission snapshot.
  final Shop source;
}

/// At most this many pictures go into one report (keeps the PDF small).
const kMaxReportImages = 60;

/// True when the recce content must come from the latest submitted
/// version (it is under review or finally approved).
bool reportUsesSnapshot(Shop s) =>
    s.latestSubmission != null &&
    (s.status == RecceStatus.pendingBusiness ||
        s.status == RecceStatus.pendingOps ||
        s.status == RecceStatus.approved);

String _reviewText(ReviewRecord? r) {
  if (r == null) return 'Pending';
  final what = r.decision == ReviewDecision.approved ? 'Approved' : 'Rejected';
  return '$what by ${r.reviewerName} on ${fmtDateTime(r.at)}';
}

/// Builds the report data of [live] (the shop as stored now).
ReportBuild buildReportData(
  AppController c,
  Shop live, {
  required DateTime now,
  String generatedBy = '',
  /// Media-wise (separate) report: only these media groups. Null = all.
  Set<String>? groupIds,
}) {
  final useSnapshot = reportUsesSnapshot(live);
  final s = useSnapshot ? live.latestSubmission!.shopSnapshot : live;
  final project = c.project(live.projectId);
  final task = c.task(live.taskId);
  final vendor = task == null ? null : c.userById(task.assignedVendorId);
  final approved = live.status == RecceStatus.approved;
  final sub = live.latestSubmission;

  DateTime visit = s.createdAt;
  for (final b in s.boards) {
    for (final p in b.photos) {
      if (p.capturedAt.year > 1970 && p.capturedAt.isBefore(visit)) {
        visit = p.capturedAt;
      }
    }
  }

  final banner = approved
      ? {
          'draft': false,
          'text': 'APPROVED FOR FABRICATION – v${live.currentVersion}',
          'detail':
              'Business: ${_reviewText(sub?.reviewFor(ReviewStage.business))}'
              '\nOps: ${_reviewText(sub?.reviewFor(ReviewStage.ops))}',
        }
      : {
          'draft': true,
          'text': kDraftBanner,
          'detail': 'Current status: ${live.status.label}',
        };

  final header = {
    'projectId': live.projectId,
    'projectCode': project?.code ?? '',
    'projectName': project?.name ?? '',
    'taskId': live.taskId,
    'taskTitle': task?.title ?? '',
    'brand': project?.client ?? '',
    'shopId': live.id,
    'shopName': s.name,
    'shopAddress': s.fullAddress,
    'landmark': s.landmark,
    'gps': s.geo?.coordinates ?? '',
    'reccePerson': vendor?.name ?? sub?.submittedByName ?? '',
    'visitDate': fmtDate(visit),
    'generatedAt': fmtDateTime(now),
    'generatedBy': generatedBy,
    'status': live.status.name,
    'statusLabel': live.status.label,
    'version': live.currentVersion,
    'source': useSnapshot
        ? 'Submitted version v${sub!.version} (${fmtDateTime(sub.submittedAt)})'
        : 'Current draft (not yet ${live.submissions.isEmpty ? 'submitted' : 'resubmitted'})',
  };

  // Overview ---------------------------------------------------------------
  // Totals describe the report's scope (one media group for a separate
  // report); full-shop totals are kept under separate keys.
  final scoped = [
    for (final b in s.boards)
      if (groupIds == null || groupIds.contains(b.id)) b,
  ];
  var units = 0, complete = 0;
  final feasRows = <List<String>>[];
  for (final b in scoped) {
    for (final u in b.activeUnits) {
      units++;
      final cl = SiteChecklists.statusOf(b, u);
      if (b.unitHasSize(u) && cl.isComplete) complete++;
      final f = feasibilityOf(b, u);
      feasRows.add([
        _unitLabel(b, u),
        f.level.label,
        f.reasons.isEmpty ? '—' : f.reasons.join('; '),
      ]);
    }
  }
  final scopedIssues = groupIds == null
      ? c.shopIssues(s)
      : [
          for (final b in scoped)
            for (final i in c.boardIssues(b)) '${b.name}: $i',
        ];
  final overview = {
    'scope': groupIds == null
        ? 'Combined report – all media types'
        : 'Separate report – '
              '${scoped.map(SignageCatalog.mediaNameLabel).join(', ')}',
    'mediaSummary': [
      for (final b in scoped)
        // Existing wording (media short name) is kept for the summary.
        '${SignageCatalog.media(b.mediaCode)?.shortName ?? b.name}'
            '${SignageCatalog.isDoubleSided(b) ? ' (double-sided)' : ''} – '
            '${b.quantity} Unit${b.quantity == 1 ? '' : 's'}',
    ],
    'mediaGroups': scoped.length,
    'units': units,
    'shopMediaGroups': s.boards.length,
    'shopUnits': s.boards.fold<int>(0, (t, b) => t + b.activeUnits.length),
    'mediaTypes': [
      for (final code in scoped.map((b) => b.mediaCode).toSet())
        if (code != null) SignageCatalog.media(code)?.name ?? code,
    ],
    'completeUnits': complete,
    'completionPercent': units == 0 ? 0 : (complete * 100 / units).round(),
    'openIssues': scopedIssues.length,
    'issues': scopedIssues.take(12).toList(),
    'feasibility': shopFeasibility(s).label,
    'feasibilityRows': feasRows,
  };

  // Items & images ----------------------------------------------------------
  final images = <ReportImageRef>[];
  var imageCount = 0;
  // Required drawing / model images (4 per physical board) are reserved so
  // optional photographs can never push them out of the image budget.
  var requiredLeft =
      scoped.fold<int>(0, (t, b) => t + b.activeUnits.length) * 4;
  bool canAdd() => imageCount + requiredLeft < kMaxReportImages;
  String addImage(ReportImageRef Function(String key) make) {
    final key = 'img_${imageCount++}';
    images.add(make(key));
    return key;
  }

  final groups = <Map<String, dynamic>>[];
  for (final b in s.boards) {
    if (groupIds != null && !groupIds.contains(b.id)) continue;
    final media = SignageCatalog.media(b.mediaCode);
    final items = <Map<String, dynamic>>[];
    for (final u in b.activeUnits) {
      final item = _item(c, s, b, u);
      // Measurement sheet: 2D front + side drawing and the 3D model view,
      // all generated from the same canonical spec as the item table.
      final sheet = <String, dynamic>{};
      // Two 3D review angles per physical board: front and opposite-side
      // isometric (shows the rear face of double-sided boards).
      for (final (kind, view, slot, caption) in [
        (
          ReportImageKind.drawing2d,
          DrawingView.front.name,
          'front',
          '2D front elevation',
        ),
        (
          ReportImageKind.drawing2d,
          DrawingView.side.name,
          'side',
          '2D side elevation',
        ),
        (ReportImageKind.model3d, null, 'model', '3D front isometric view'),
        (
          ReportImageKind.model3d,
          'rear',
          'model_rear',
          '3D opposite-side isometric view',
        ),
      ]) {
        requiredLeft--;
        sheet[slot] = addImage(
          (key) => ReportImageRef(
            key: key,
            kind: kind,
            caption: '$caption – ${_unitLabel(b, u)}',
            boardId: b.id,
            unitId: u.id,
            view: view,
          ),
        );
      }
      item['sheet'] = sheet;
      items.add(item);
    }
    final pictures = <Map<String, dynamic>>[];
    for (final p in b.photos) {
      if (!canAdd()) break;
      final shows = [
        for (final u in b.activeUnits)
          if (p.unitIds.contains(u.id) ||
              p.annotations.any((a) => a.itemId == u.id) ||
              p.markup.unitIds.contains(u.id))
            b.unitLabel(u),
      ];
      final showText = shows.isEmpty ? 'whole media group' : shows.join(', ');
      final k = addImage(
        (key) => ReportImageRef(
          key: key,
          kind: ReportImageKind.photo,
          caption: 'Original site photo – ${p.label} ($showText)',
          boardId: b.id,
          photoId: p.id,
        ),
      );
      pictures.add({'key': k, 'caption': images.last.caption});
      final marked = p.annotations.isNotEmpty || !p.markup.isEmpty;
      if (marked && canAdd()) {
        final parts = [
          if (p.annotations.isNotEmpty) '${p.annotations.length} marking(s)',
          if (p.markup.perspectives.isNotEmpty)
            '${p.markup.perspectives.length} perspective board(s)',
          if (p.markup.markers.isNotEmpty)
            '${p.markup.markers.length} placement marker(s)',
          if (p.markup.electrical.isNotEmpty || p.markup.cableRoutes.isNotEmpty)
            'electrical mapping',
          if (p.markup.obstructions.isNotEmpty)
            '${p.markup.obstructions.length} obstruction(s)',
        ];
        final k2 = addImage(
          (key) => ReportImageRef(
            key: key,
            kind: ReportImageKind.annotated,
            caption: 'Annotated – ${p.label}: ${parts.join(', ')}',
            boardId: b.id,
            photoId: p.id,
          ),
        );
        pictures.add({'key': k2, 'caption': images.last.caption});
      }
    }
    for (final pv in b.previews) {
      if (!canAdd()) break;
      final unit = b.unitById(pv.unitId);
      final k = addImage(
        (key) => ReportImageRef(
          key: key,
          kind: ReportImageKind.file,
          caption:
              '${pv.kind.label}${unit == null ? '' : ' – ${b.unitLabel(unit)}'}'
              ' (${fmtDateTime(pv.createdAt)})',
          path: pv.path,
        ),
      );
      pictures.add({'key': k, 'caption': images.last.caption});
    }
    for (final cmp in b.comparisons) {
      if (!canAdd()) break;
      final unit = b.unitById(cmp.unitId);
      final k = addImage(
        (key) => ReportImageRef(
          key: key,
          kind: ReportImageKind.file,
          caption:
              'Before / Proposed comparison'
              '${unit == null ? '' : ' – ${b.unitLabel(unit)}'}'
              ' (${cmp.versionLabel}) – visual proposal, not as-built',
          path: cmp.path,
        ),
      );
      pictures.add({'key': k, 'caption': images.last.caption});
    }
    final drawing = b.drawingPath;
    if (drawing != null && drawing.isNotEmpty && canAdd()) {
      final k = addImage(
        (key) => ReportImageRef(
          key: key,
          kind: ReportImageKind.file,
          caption: '2D measurement drawing – ${b.name}',
          path: drawing,
        ),
      );
      pictures.add({'key': k, 'caption': images.last.caption});
    }
    groups.add({
      'groupId': b.id,
      'name': b.name,
      'media': SignageCatalog.mediaDisplayName(b),
      'mediaShort': media?.shortName ?? b.name,
      'installation':
          SignageCatalog.installationSummary(b),
      'quantity': b.quantity,
      'sizeMode': b.isSameSize ? 'Same size' : 'Different sizes',
      // Each physical board's own final answers (own installation).
      'siteAnswers': [
        for (final u in b.activeUnits)
          for (final q in SignageCatalog.questionsForUnit(b, u))
            if (q.isVisible(QuestionEquivalence.effectiveSiteAnswers(b, u)) &&
                QuestionEquivalence.effectiveSiteAnswers(b, u)[q.id] != null)
              [
                b.activeUnits.length > 1
                    ? '${SignageCatalog.unitName(b, u)} – ${q.label}'
                    : q.label,
                SignageCatalog.answerText(
                  q,
                  QuestionEquivalence.effectiveSiteAnswers(b, u)[q.id],
                ),
                // 'p' = predefined answer (Yes / No / listed option): the only
                // kind a Tamil report may translate. Text / numbers are data.
                if (q.type == QuestionType.yesNo ||
                    q.type == QuestionType.choice)
                  'p',
              ],
      ],
      // Optional shop-level GST number (only when entered).
      if (s.gstNumber.isNotEmpty) 'gst': s.gstNumber,
      'note': b.textNote,
      'items': items,
      'pictures': pictures,
    });
  }

  // Review -------------------------------------------------------------------
  final rejections = <Map<String, dynamic>>[];
  for (final sb in live.submissions) {
    for (final r in sb.reviews) {
      if (r.decision != ReviewDecision.rejected) continue;
      rejections.add({
        'version': sb.version,
        'stage': r.stage.label,
        'by': r.reviewerName,
        'at': fmtDateTime(r.at),
        'remarks': r.remarks,
        'reasons': r.reasons,
        'issues': r.issues.map((i) => i.text).toList(),
      });
    }
  }
  final comments = [
    for (final cm in live.reviewComments)
      if (cm.status != CommentStatus.verified)
        [
          cm.markerLabel,
          'v${cm.version}',
          cm.type.label,
          cm.text,
          cm.status.label,
          cm.reviewerName,
        ],
  ];
  final review = {
    'version': live.currentVersion,
    'business': _reviewText(sub?.reviewFor(ReviewStage.business)),
    'ops': _reviewText(sub?.reviewFor(ReviewStage.ops)),
    'submittedBy': sub?.submittedByName ?? '',
    'submittedAt': sub == null ? '' : fmtDateTime(sub.submittedAt),
    'vendorRemarks': sub?.vendorRemarks ?? '',
    'rejections': rejections,
    'comments': comments,
  };

  return ReportBuild(
    data: {
      'title': kReportTitle,
      'header': header,
      'banner': banner,
      'overview': overview,
      'groups': groups,
      'review': review,
      'imageLimitReached': imageCount >= kMaxReportImages,
    },
    images: images,
    source: s,
  );
}

String _unitLabel(Board b, SignageUnit u) {
  final media = SignageCatalog.media(b.mediaCode)?.shortName ?? b.name;
  return '$media – ${b.unitLabel(u)}';
}

Map<String, dynamic> _item(AppController c, Shop s, Board b, SignageUnit u) {
  final w = b.widthOf(u), h = b.heightOf(u);
  final m = u.measurements;
  final index = b.units.indexWhere((e) => e.id == u.id) + 1;
  String v(String id) =>
      m.valuesMm[id] == null ? '' : fmtMm(m.valuesMm[id], m.unit);

  // Checklist.
  final cl = SiteChecklists.statusOf(b, u);
  final def = SiteChecklists.definitionFor(b.mediaCode);
  // Questions answered as Site Questions are exported there only (no
  // duplicates); evidence photos are exported from Site Photos.
  final mapped = QuestionEquivalence.mappedChecklistIds(b, u);
  final projected = QuestionEquivalence.projectedChecklist(b, u);
  final checklistRows = [
    for (final q in cl.applicable)
      if (!mapped.contains(q.id) &&
          q.type != ChecklistResponseType.photoEvidence)
        [
          q.text,
          q.isAnswered(projected[q.id])
              ? q.answerText(projected[q.id])
              : (q.required ? 'NOT ANSWERED (required)' : '—'),
          u.checklist[q.id]?.remarks ?? '',
        ],
  ];

  // Electrical.
  final e = u.electrical;
  final electrical = e.isEmpty
      ? <List<String>>[]
      : [
          ['Electricity available', e.electricityAvailable?.label ?? '—'],
          ['Electrical point available', e.pointAvailable?.label ?? '—'],
          if (e.pointLocation.isNotEmpty)
            ['Electrical point location', e.pointLocation],
          if (e.distanceMm != null)
            ['Approx. distance from board', fmtMm(e.distanceMm, m.unit)],
          if (e.switchLocation.isNotEmpty)
            ['Switch location', e.switchLocation],
          if (e.cableRouteNotes.isNotEmpty)
            ['Cable route notes', e.cableRouteNotes],
          if (e.remarks.isNotEmpty) ['Electrical remarks', e.remarks],
          if (e.evidencePhotoIds.isNotEmpty)
            ['Evidence photos', '${e.evidencePhotoIds.length}'],
        ];

  // Obstructions & markers on photos.
  final obstructions = [
    for (final (p, o) in obstructionsFor(b, u))
      [
        o.code,
        o.type.label,
        o.severity.label,
        p.label,
        [o.label, o.remarks].where((x) => x.trim().isNotEmpty).join(' – '),
      ],
  ];
  final markers = <List<String>>[];
  final perspectives = <String>[];
  final electricalMarks = <String>[];
  for (final board in s.boards) {
    for (final p in board.photos) {
      for (final mk in p.markup.markers.where((x) => x.unitId == u.id)) {
        markers.add([
          p.label,
          mk.numberLabel,
          mk.isAlternative ? 'Alternative ${mk.placementNo}' : 'Primary',
          mk.notes,
        ]);
      }
      if (p.markup.perspectives.any((x) => x.unitId == u.id)) {
        perspectives.add(p.label);
      }
      for (final em in p.markup.electrical.where(
        (x) => x.unitIds.contains(u.id),
      )) {
        electricalMarks.add('${em.code} ${em.kind.label} (${p.label})');
      }
      for (final cr in p.markup.cableRoutes.where(
        (x) => x.unitIds.contains(u.id),
      )) {
        electricalMarks.add('${cr.code} Cable route (${p.label})');
      }
    }
  }

  final f = feasibilityOf(b, u);
  final inst = b.installationOf(u);
  final diagram = MeasurementCatalog.recorded(b, u).isEmpty
      ? null
      : {
          'unit': m.unit.label,
          'unitName': m.unit.name,
          'installation': inst,
          'widthMm': (w ?? 0) > 0 ? b.unit.toMm(w!) : null,
          'heightMm': (h ?? 0) > 0 ? b.unit.toMm(h!) : null,
          for (final id in const [
            'bottom_height',
            'top_height',
            'wall_width',
            'wall_height',
            'clear_left',
            'clear_right',
            'clear_top',
            'clear_bottom',
            'pole_above_ground',
            'pole_embedment',
            'pole_spacing',
            'pipe_spacing',
            'standee_overall_height',
            'panel_width',
            'panel_height',
            'base_width',
          ])
            id: m.valuesMm[id],
          'poleCount': m.counts['pole_count'],
          'pipeCount': m.counts['pipe_count'],
        };

  return {
    'unitId': u.id,
    'groupId': b.id,
    'label': _unitLabel(b, u),
    'media': SignageCatalog.mediaDisplayName(b),
    'unitNumber': b.unitLabel(u),
    'quantityContext':
        'Unit $index of ${b.quantity} – '
        '${b.isSameSize ? 'same size' : 'individual size'}',
    'width': (w ?? 0) > 0 ? '${fmtNum(w!)} ${b.unit.label}' : 'Not set',
    'height': (h ?? 0) > 0 ? '${fmtNum(h!)} ${b.unit.label}' : 'Not set',
    'installation': inst == null
        ? 'Installation not set'
        : SignageCatalog.installationNameOf(b, u),
    // Custom media / installation have no approved fabrication spec.
    if (SignageCatalog.isOtherMedia(b.mediaCode) ||
        SignageCatalog.isOtherInstallation(inst))
      'specNote': 'Technical Specification Required – no approved geometry.',
    'placement': u.placement,
    'installationDetails': u.installationDetails,
    'notes': u.notes,
    'measurements': [
      for (final (field, value) in MeasurementCatalog.recorded(b, u))
        [field.group.label, field.label, value],
    ],
    'groundClearance': {'bottom': v('bottom_height'), 'top': v('top_height')},
    'measurementIssues': [
      for (final i in MeasurementCatalog.validate(b, u, m))
        '${i.level.name.toUpperCase()}: ${i.message}',
    ],
    'electrical': electrical,
    'electricalMarks': electricalMarks,
    'obstructions': obstructions,
    'checklist': {
      'title': def?.title ?? 'No checklist for this media type',
      'answered': cl.answered,
      'total': cl.total,
      'missing': cl.missingRequired.length,
      'complete': cl.isComplete,
      'rows': checklistRows,
    },
    'markers': markers,
    'perspectives': perspectives,
    'feasibility': f.level.label,
    'feasibilityReasons': f.reasons,
    'diagram': diagram,
    'model': _modelData(c, b, u),
  };
}

/// Model / measurement-sheet data of one item from the canonical spec (the
/// same values the 3D model, 2D drawing and recce form use).
Map<String, dynamic> _modelData(AppController c, Board b, SignageUnit u) {
  final spec = SignageModelSpec.of(b, u);
  return {
    'template': spec.template,
    'sidedness': spec.isDoubleSided ? 'Double-sided' : 'Single-sided',
    'legacyMedia': spec.legacyMedia,
    'status': c.modelStatus(spec.mediaCode).label,
    'rows': [
      for (final fld in spec.editableFields)
        [
          fld.label,
          switch (fld.kind) {
            SpecValueKind.length => fmtMm(spec[fld], spec.displayUnit),
            SpecValueKind.count => '${spec[fld].round()}',
            SpecValueKind.angle => '${spec[fld].toStringAsFixed(0)} deg',
          },
          switch (spec.sources[fld]) {
            SpecSource.recorded => 'Recorded',
            SpecSource.siteAnswer => 'Site answer',
            _ => 'Not measured (illustrative)',
          },
        ],
    ],
  };
}
