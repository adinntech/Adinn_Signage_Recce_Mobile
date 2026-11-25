part of 'recce_models.dart';

/// Milestone 2 models: version history, version comparison, per-photo history and the approval timeline.
/// Contract: `GET /recce/shops/:siteId/versions`, `.../versions/compare`, `.../photos/:photoId/history`, `.../activity`
/// (backend: recceReview.versions.ts, recceReview.review.ts `timeline`). Parsing is tolerant like the rest of this library.

/* ------------------------------------------------------------------ decisions and labels */

/// Decision of one review stage: PENDING | APPROVED | REWORK | REJECTED | VOID (the server writes VOID on a stage that never got to decide).
String decisionLabel(String? d) => switch (d) {
      'APPROVE' || 'APPROVED' => 'Approved',
      'REJECT' || 'REJECTED' => 'Rejected',
      'REWORK' || 'REWORK_REQUIRED' => 'Rework requested',
      'ADDITIONAL' => 'More photos requested',
      'VOID' => 'Not needed',
      null || 'PENDING' => 'Pending',
      final other => other,
    };

Color decisionColor(String? d) => switch (d) {
      'APPROVE' || 'APPROVED' => statusColor('APPROVED'),
      'REJECT' || 'REJECTED' => statusColor('REJECTED'),
      'REWORK' || 'REWORK_REQUIRED' || 'ADDITIONAL' => statusColor('REWORK_REQUIRED'),
      _ => const Color(0xFF6B6F76),
    };

/// A decision of one review stage on one version (`versions[].decisions[]`).
class StageDecision {
  const StageDecision({required this.stage, required this.stageLabel, this.decision = 'PENDING', this.reviewer, this.decidedAt, this.comment = ''});

  final String stage; // OPS | CS
  final String stageLabel; // Recce Operations | Client Servicing
  final String decision;
  final String? reviewer;
  final DateTime? decidedAt;
  final String comment;

  bool get isPending => decision == 'PENDING';
  bool get isVoid => decision == 'VOID';

  factory StageDecision.fromJson(Json j) => StageDecision(
        stage: (j['stage'] ?? '').toString(),
        stageLabel: (j['stageLabel'] ?? j['stage'] ?? '').toString(),
        decision: (j['decision'] ?? 'PENDING').toString(),
        reviewer: _s(j['reviewer']),
        decidedAt: _dt(j['decidedAt']),
        comment: (j['comment'] ?? '').toString(),
      );

  /// The decisions of `shop detail.reviews` for one version, as [StageDecision]s (what the status header shows).
  static List<StageDecision> forVersion(List<ReviewEntry> reviews, int versionNo) => [
        for (final r in reviews)
          if (r.versionNo == versionNo)
            StageDecision(stage: r.stageLabel, stageLabel: r.stageLabel, decision: r.decision ?? 'PENDING', reviewer: r.reviewer, decidedAt: r.decidedAt, comment: r.comment),
      ];
}

/// The overall state of one version from its stage decisions. Same rule as the server: any REJECTED rejects, any REWORK asks for
/// rework, every stage APPROVED approves, anything else is still under review. (The CURRENT state of the shop always comes from
/// the server's own `status`; this only labels older versions, which the server does not label.)
String versionStatusOf(List<String> stages, List<StageDecision> decisions) {
  if (decisions.any((d) => d.decision == 'REJECTED')) return 'REJECTED';
  if (decisions.any((d) => d.decision == 'REWORK')) return 'REWORK_REQUIRED';
  final need = stages.isNotEmpty ? stages : [for (final d in decisions) d.stage];
  if (need.isNotEmpty && need.every((s) => decisions.any((d) => d.stage == s && d.decision == 'APPROVED'))) return 'APPROVED';
  return 'UNDER_REVIEW';
}

/// "Rework Required", "Under Review" (title case, for the version rows).
String statusTitle(String status) => statusLabel(status).split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

/* ------------------------------------------------------------------ board and installation text */

String unitLabel(String unit) => unit.toLowerCase();

String _num(num v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// "6 x 4 ft", or null when the size is not set.
String? boardSizeText(BoardItem? b) => b == null || !b.hasSize ? null : '${_num(b.width!)} x ${_num(b.height!)} ${unitLabel(b.unit)}';

/// "GSB 6 x 4 ft" (a quantity above 1 adds "x2").
String boardSummaryText(BoardItem b) {
  final size = boardSizeText(b);
  return [b.name, ?size, if (b.quantity > 1) 'x${b.quantity}'].join(' ');
}

/// Short line of the installation answers: what is needed, or that nothing special is.
String installationSummaryText(Installation i, {bool recorded = true}) {
  if (!recorded) return 'Installation not recorded';
  final needs = [
    if (i.ladderRequired == triYes) 'Ladder',
    if (i.scaffoldingRequired == triYes) 'Scaffolding',
    if (i.craneRequired == triYes) 'Crane',
    if (i.hydraRequired == triYes) 'Hydra',
    if (i.manualInstallationPossible == triNo) 'No manual install',
  ];
  final open = i.unanswered;
  if (needs.isEmpty && open.length == 5) return 'Installation not assessed';
  final base = needs.isEmpty ? 'No special equipment' : 'Needs ${needs.join(', ')}';
  return open.isEmpty ? base : '$base (${open.length} not assessed)';
}

/* ------------------------------------------------------------------ versions */

/// One immutable version of a shop recce (`GET /recce/shops/:siteId/versions`, oldest first).
class RecceVersion {
  const RecceVersion({
    required this.version,
    this.current = false,
    this.submittedAt,
    this.submittedBy,
    this.notes = '',
    this.mediaItems = const [],
    required this.installation,
    this.installationRecorded = false,
    this.photos = const [],
    this.addedIds = const [],
    this.removedIds = const [],
    this.stages = const [],
    this.decisions = const [],
    this.reworks = const [],
  });

  final int version;
  final bool current;
  final DateTime? submittedAt;
  final String? submittedBy;
  final String notes;
  final List<BoardItem> mediaItems;
  final Installation installation;
  final bool installationRecorded;
  final List<ShopPhoto> photos;
  final List<String> addedIds;
  final List<String> removedIds;
  final List<String> stages;
  final List<StageDecision> decisions;
  final List<ReworkEntry> reworks;

  /// Decisions in review order (the config order of `stages`).
  List<StageDecision> get orderedDecisions {
    int rank(StageDecision d) {
      final i = stages.indexOf(d.stage);
      return i < 0 ? 99 : i;
    }

    return [...decisions]..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  String get status => versionStatusOf(stages, decisions);
  String get statusText => statusTitle(status);
  String get boardSummary => mediaItems.isEmpty ? 'No boards' : mediaItems.map(boardSummaryText).join(', ');
  String get installationSummary => installationSummaryText(installation, recorded: installationRecorded);

  /// "V1 - GSB 6 x 4 ft - Rework Required"
  String get rowTitle => 'V$version - $boardSummary - $statusText';

  BoardItem? board(String key) {
    for (final b in mediaItems) {
      if (b.key == key) return b;
    }
    return null;
  }

  factory RecceVersion.fromJson(Json j) => RecceVersion(
        version: _i(j['version']),
        current: j['current'] == true,
        submittedAt: _dt(j['submittedAt']),
        submittedBy: _s(j['submittedBy']),
        notes: (j['notes'] ?? '').toString(),
        mediaItems: [for (final e in _ml(j['mediaItems'])) BoardItem.fromJson(e)],
        installation: Installation.fromJson(j['installation']),
        installationRecorded: j['installationRecorded'] == true,
        photos: [for (final e in _ml(j['photos'])) ShopPhoto.fromJson(e)],
        addedIds: _sl(j['addedIds']),
        removedIds: _sl(j['removedIds']),
        stages: _sl(j['stages']),
        decisions: [for (final e in _ml(j['decisions'])) StageDecision.fromJson(e)],
        reworks: [for (final e in _ml(j['reworks'])) ReworkEntry.fromJson(e)],
      );
}

/// A photo of an older version that is no longer live (replaced or removed), with the versions that carried it.
class PreviousPhoto {
  const PreviousPhoto({required this.photo, required this.versions});
  final ShopPhoto photo;
  final List<int> versions;

  String get versionText => versions.length == 1 ? 'V${versions.first}' : 'V${versions.first}-V${versions.last}';
}

/// Photos that were part of a version but are not live now (superseded / removed), newest version first.
List<PreviousPhoto> previousPhotosOf(List<RecceVersion> versions, Iterable<String> liveIds) {
  final live = liveIds.toSet();
  final byId = <String, ShopPhoto>{};
  final inVersions = <String, List<int>>{};
  for (final v in versions) {
    for (final p in v.photos) {
      if (live.contains(p.id)) continue;
      byId.putIfAbsent(p.id, () => p);
      inVersions.putIfAbsent(p.id, () => []).add(v.version);
    }
  }
  final out = [for (final e in byId.entries) PreviousPhoto(photo: e.value, versions: inVersions[e.key]!..sort())];
  out.sort((a, b) => b.versions.last.compareTo(a.versions.last));
  return out;
}

/* ------------------------------------------------------------------ compare */

const _fieldLabels = <String, String>{
  'name': 'Type',
  'quantity': 'Quantity',
  'width': 'Width',
  'height': 'Height',
  'unit': 'Unit',
  'sided': 'Sides',
  'condition': 'Condition',
  'position': 'Position',
  'installationNotes': 'Install notes',
  'notes': 'Notes',
  'ladderRequired': 'Ladder',
  'scaffoldingRequired': 'Scaffolding',
  'craneRequired': 'Crane',
  'hydraRequired': 'Hydra',
  'manualInstallationPossible': 'Manual installation',
  'electricalAccess': 'Electrical access',
  'installationHeightFt': 'Installation height (ft)',
  'accessRestrictions': 'Access restrictions',
  'obstruction': 'Obstruction',
  'roadsideConstraints': 'Roadside constraints',
  'safetyNotes': 'Safety notes',
  'additionalEquipment': 'Additional equipment',
};

/// Labels of the fields the activity log names that are not board or installation fields.
const _eventFieldLabels = <String, String>{
  'draft': 'Draft',
  'mediaItems': 'Boards',
  'photos': 'Photos',
};

String fieldLabel(String field) {
  if (field.startsWith('installation.')) return fieldLabel(field.substring(13));
  return _fieldLabels[field] ?? _eventFieldLabels[field] ?? field;
}

/// A board object (`{name, width, height, unit, quantity, ...}`) as one line: "GSB 6 x 4 ft".
bool _looksLikeBoard(Map<dynamic, dynamic> m) => m.containsKey('name') && (m.containsKey('width') || m.containsKey('height') || m.containsKey('quantity'));

String _boardLine(Map<dynamic, dynamic> m) => boardSummaryText(BoardItem.fromJson({for (final e in m.entries) e.key.toString(): e.value, 'key': m['key'] ?? ''}));

/// A map value in words: a board becomes "GSB 6 x 4 ft"; any other map becomes compact "label: value" lines.
String _mapText(Map<dynamic, dynamic> m) {
  if (_looksLikeBoard(m)) return _boardLine(m);
  final lines = <String>[];
  for (final e in m.entries) {
    final k = e.key.toString();
    if (k == '_id' || k == 'id') continue;
    final v = e.value;
    if (v == null || (v is String && v.trim().isEmpty) || (v is Iterable && v.isEmpty)) continue;
    lines.add('${fieldLabel(k)}: ${fieldValueText(v).replaceAll('\n', ', ')}');
  }
  return lines.isEmpty ? 'not set' : lines.join('\n');
}

/// A value of a changed field in words: YES -> Yes, 6.0 -> 6, a list -> "a, b", empty -> "not set". A board object reads
/// "GSB 6 x 4 ft"; another object reads as compact "label: value" lines (never a raw `{key: value}` dump).
String fieldValueText(dynamic v) {
  if (v == null) return 'not set';
  if (v is num) return _num(v);
  if (v is bool) return v ? 'Yes' : 'No';
  if (v is Map) return _mapText(v);
  if (v is List) {
    if (v.isEmpty) return 'none';
    return v.map((e) => e is Map ? _mapText(e).replaceAll('\n', '; ') : (e is num ? _num(e) : e.toString())).join(', ');
  }
  final s = v.toString().trim();
  if (s.isEmpty) return 'not set';
  return switch (s) {
    'YES' => 'Yes',
    'NO' => 'No',
    'NOT_ASSESSED' => 'Not assessed',
    'AVAILABLE' => 'Available',
    'NOT_AVAILABLE' => 'Not available',
    'SINGLE' => 'Single side',
    'DOUBLE' => 'Double side',
    'EXISTING' => 'Existing',
    'PROPOSED' => 'Proposed',
    _ => s,
  };
}

/// One changed field: `{field, from, to}` (board field or installation field).
class FieldChange {
  const FieldChange({required this.field, this.from, this.to});
  final String field;
  final dynamic from;
  final dynamic to;

  String get label => fieldLabel(field);

  /// "Width: 6 -> 8". An object value (several lines) is shown as "Label", then "Before:" and "After:" blocks.
  String get text {
    final a = fieldValueText(from);
    final b = fieldValueText(to);
    if (!a.contains('\n') && !b.contains('\n')) return '$label: $a -> $b';
    String indent(String s) => s.replaceAll('\n', '\n    ');
    return '$label\n  Before: ${indent(a)}\n  After: ${indent(b)}';
  }

  factory FieldChange.fromJson(Json j) => FieldChange(field: (j['field'] ?? '').toString(), from: j['from'], to: j['to']);
}

/// A board line present in both versions whose fields changed.
class BoardChange {
  const BoardChange({required this.key, required this.name, required this.fields});
  final String key;
  final String name;
  final List<FieldChange> fields;

  bool get sizeChanged => fields.any((f) => const {'width', 'height', 'unit'}.contains(f.field));

  FieldChange? field(String name) {
    for (final f in fields) {
      if (f.field == name) return f;
    }
    return null;
  }

  /// "6 x 4 ft -> 8 x 4 ft" when the size changed. [before] / [after] are the same board in the two versions
  /// (the compare answer only lists the fields that changed, so the unchanged side of the size comes from the versions list).
  String? sizeHeadline({BoardItem? before, BoardItem? after}) {
    if (!sizeChanged) return null;
    final a = boardSizeText(before);
    final b = boardSizeText(after);
    if (a != null && b != null) return '$a -> $b';
    final w = field('width');
    final h = field('height');
    final parts = [if (w != null) 'Width ${fieldValueText(w.from)} -> ${fieldValueText(w.to)}', if (h != null) 'Height ${fieldValueText(h.from)} -> ${fieldValueText(h.to)}'];
    return parts.isEmpty ? null : parts.join(', ');
  }

  factory BoardChange.fromJson(Json j) => BoardChange(
        key: (j['key'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        fields: [for (final f in _ml(j['fields'])) FieldChange.fromJson(f)],
      );
}

/// A photo replaced by a newer one between the two versions.
class ReplacedPhoto {
  const ReplacedPhoto({required this.from, required this.to});
  final ShopPhoto from;
  final ShopPhoto to;
}

/// One side of a comparison: the version, when and who submitted it, and the reviewers' comments on it.
class CompareSide {
  const CompareSide({required this.version, this.submittedAt, this.submittedBy, this.reviewerComments = const []});
  final int version;
  final DateTime? submittedAt;
  final String? submittedBy;
  final List<StageDecision> reviewerComments;

  factory CompareSide.fromJson(Json j) => CompareSide(
        version: _i(j['version']),
        submittedAt: _dt(j['submittedAt']),
        submittedBy: _s(j['submittedBy']),
        reviewerComments: [for (final e in _ml(j['reviewerComments'])) StageDecision.fromJson(e)],
      );
}

/// `GET /recce/shops/:siteId/versions/compare?from=&to=`
class VersionCompare {
  const VersionCompare({
    required this.from,
    required this.to,
    this.added = const [],
    this.replaced = const [],
    this.unchanged = const [],
    this.removed = const [],
    this.boardsAdded = const [],
    this.boardsRemoved = const [],
    this.boardsChanged = const [],
    this.installation = const [],
    this.notesFrom,
    this.notesTo,
    this.notesChanged = false,
    this.changed = false,
  });

  final CompareSide from;
  final CompareSide to;
  final List<ShopPhoto> added;
  final List<ReplacedPhoto> replaced;
  final List<ShopPhoto> unchanged;
  final List<ShopPhoto> removed;
  final List<BoardItem> boardsAdded;
  final List<BoardItem> boardsRemoved;
  final List<BoardChange> boardsChanged;
  final List<FieldChange> installation;
  final String? notesFrom;
  final String? notesTo;
  final bool notesChanged;
  final bool changed;

  factory VersionCompare.fromJson(Json j) {
    final photos = _m(j['photos']);
    final items = _m(j['mediaItems']);
    final notes = j['notes'];
    return VersionCompare(
      from: CompareSide.fromJson(_m(j['from'])),
      to: CompareSide.fromJson(_m(j['to'])),
      added: [for (final e in _ml(photos['added'])) ShopPhoto.fromJson(e)],
      replaced: [
        for (final e in _ml(photos['replaced']))
          ReplacedPhoto(from: ShopPhoto.fromJson(_m(e['from'])), to: ShopPhoto.fromJson(_m(e['to']))),
      ],
      unchanged: [for (final e in _ml(photos['unchanged'])) ShopPhoto.fromJson(e)],
      removed: [for (final e in _ml(photos['removed'])) ShopPhoto.fromJson(e)],
      boardsAdded: [for (final e in _ml(items['added'])) BoardItem.fromJson(e)],
      boardsRemoved: [for (final e in _ml(items['removed'])) BoardItem.fromJson(e)],
      boardsChanged: [for (final e in _ml(items['changed'])) BoardChange.fromJson(e)],
      installation: [for (final e in _ml(j['installation'])) FieldChange.fromJson(e)],
      notesFrom: notes is Map ? (notes['from'] ?? '').toString() : null,
      notesTo: notes is Map ? (notes['to'] ?? '').toString() : null,
      notesChanged: notes is Map,
      changed: j['changed'] == true,
    );
  }
}

/* ------------------------------------------------------------------ per-photo history */

/// One revision of a photo (the replaces chain, oldest first). `photo` is the stored photo of that revision.
class PhotoRevision {
  const PhotoRevision({required this.revision, this.current = false, required this.photo});
  final int revision;
  final bool current;
  final ShopPhoto photo;
}

/// One timeline event of a photo (`events[]`): uploaded, replaced, annotated, removed...
class PhotoEvent {
  const PhotoEvent({required this.id, required this.type, required this.label, this.actor = '', this.role = '', this.at, this.reason = '', this.photoId = '', this.version});

  final String id;
  final String type;
  final String label;
  final String actor;
  final String role;
  final DateTime? at;
  final String reason;
  final String photoId;
  final int? version;

  factory PhotoEvent.fromJson(Json j) => PhotoEvent(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        label: (j['label'] ?? j['type'] ?? '').toString(),
        actor: (j['actor'] ?? '').toString(),
        role: (j['role'] ?? '').toString(),
        at: _dt(j['at']),
        reason: (j['reason'] ?? '').toString(),
        photoId: (j['photoId'] ?? '').toString(),
        version: j['version'] is num ? (j['version'] as num).toInt() : null,
      );
}

/// A rework request that named this photo (`reworks[]`).
class PhotoRework {
  const PhotoRework({
    required this.reworkId,
    this.itemId = '',
    this.photoId = '',
    this.stage = '',
    this.stageLabel = '',
    this.requestedBy,
    this.requestedAt,
    this.note = '',
    this.instructions = '',
    this.resolved = false,
    this.resolvedInVersion,
    this.rejected = false,
  });

  final String reworkId;
  final String itemId;
  final String photoId;

  /// The reviewer rejected this photo: [note] is the reason for rejection.
  final bool rejected;
  final String stage;
  final String stageLabel;
  final String? requestedBy;
  final DateTime? requestedAt;
  final String note;
  final String instructions;
  final bool resolved;
  final int? resolvedInVersion;

  factory PhotoRework.fromJson(Json j) => PhotoRework(
        reworkId: (j['reworkId'] ?? '').toString(),
        itemId: (j['itemId'] ?? '').toString(),
        photoId: (j['photoId'] ?? '').toString(),
        stage: (j['stage'] ?? '').toString(),
        stageLabel: (j['stageLabel'] ?? j['stage'] ?? '').toString(),
        requestedBy: ReworkNote._name(j['requestedBy']),
        requestedAt: _dt(j['requestedAt']),
        note: (j['note'] ?? '').toString(),
        instructions: (j['instructions'] ?? '').toString(),
        resolved: j['resolved'] == true,
        resolvedInVersion: j['resolvedInVersion'] is num ? (j['resolvedInVersion'] as num).toInt() : null,
        rejected: j['rejected'] == true,
      );
}

/// One line of the time-ordered history list of a photo.
class PhotoHistoryLine {
  const PhotoHistoryLine({required this.at, required this.kind, required this.title, this.detail = '', this.who = '', this.version});

  final DateTime? at;
  final String kind; // event | upload | rework
  final String title;
  final String detail;
  final String who;
  final int? version;
}

/// `GET /recce/shops/:siteId/photos/:photoId/history`
class PhotoHistory {
  const PhotoHistory({required this.photoId, this.revisions = const [], this.events = const [], this.reworks = const []});

  final String photoId;
  final List<PhotoRevision> revisions;
  final List<PhotoEvent> events;
  final List<PhotoRework> reworks;

  factory PhotoHistory.fromJson(Json j) => PhotoHistory(
        photoId: (j['photoId'] ?? '').toString(),
        revisions: [
          for (final e in _ml(j['revisions']))
            PhotoRevision(revision: _i(e['revision'], 1), current: e['current'] == true, photo: ShopPhoto.fromJson(e)),
        ],
        events: [for (final e in _ml(j['events'])) PhotoEvent.fromJson(e)],
        reworks: [for (final e in _ml(j['reworks'])) PhotoRework.fromJson(e)],
      );

  /// Events, rework requests and (when no upload event exists for it) each revision's upload, oldest first.
  List<PhotoHistoryLine> get timeline {
    final out = <PhotoHistoryLine>[];
    final covered = {for (final e in events) if (e.type == 'PHOTO_CAPTURED' || e.type == 'PHOTO_REPLACED') e.photoId};
    for (final r in revisions) {
      if (covered.contains(r.photo.id)) continue;
      out.add(PhotoHistoryLine(
        at: r.photo.uploadedAt ?? r.photo.capturedAt,
        kind: 'upload',
        title: r.revision == 1 ? 'Photo uploaded' : 'Photo replaced (revision ${r.revision})',
        who: r.photo.uploadedBy ?? '',
        version: r.photo.version,
      ));
    }
    for (final e in events) {
      out.add(PhotoHistoryLine(at: e.at, kind: 'event', title: e.label, detail: e.reason, who: [e.actor, if (e.role.isNotEmpty) '(${roleLabel(e.role)})'].where((s) => s.isNotEmpty).join(' '), version: e.version));
    }
    for (final w in reworks) {
      out.add(PhotoHistoryLine(
        at: w.requestedAt,
        kind: 'rework',
        title: '${w.stageLabel} ${w.rejected ? 'rejected this photo' : 'requested rework'}${w.resolved ? ' (done${w.resolvedInVersion != null ? ' in V${w.resolvedInVersion}' : ''})' : ''}',
        detail: [if (w.note.isNotEmpty) w.note, if (w.instructions.isNotEmpty && w.instructions != w.note) w.instructions].join('\n'),
        who: w.requestedBy ?? '',
      ));
    }
    out.sort((a, b) => (a.at ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(b.at ?? DateTime.fromMillisecondsSinceEpoch(0)));
    return out;
  }
}

/* ------------------------------------------------------------------ approval history (activity) */

String roleLabel(String role) => switch (role) {
      'OPERATIONS' || 'RECCE_COORDINATOR' => 'Recce Operations',
      'CLIENT_SERVICING' => 'Client Servicing',
      'VENDOR' => 'Vendor',
      'RECCE_EXECUTIVE' => 'Recce Executive',
      'SUPER_ADMIN' => 'Admin',
      'MANAGEMENT' => 'Management',
      '' => '',
      final other => other,
    };

const _stageNames = {'OPS': 'Recce Operations', 'CS': 'Client Servicing'};

/// One entry of `GET /recce/shops/:siteId/activity` (the AuditLog row of a shop: `logEvent` in recceReview.common.ts).
class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.type,
    required this.label,
    this.actor = 'Unknown',
    this.role = '',
    this.at,
    this.reason = '',
    this.mediaKey,
    this.photo,
    this.version,
    this.changes = const [],
  });

  final String id;
  final String type; // SUBMISSION_CREATED, REVIEW_APPROVED, REWORK_REQUESTED, FINAL_APPROVAL, ...
  final String label; // the server's text for the type
  final String actor;
  final String role; // role of the actor at that time
  final DateTime? at;
  final String reason; // the comment / instructions
  final String? mediaKey; // board key
  final String? photo; // photo id
  final int? version;
  final List<FieldChange> changes;

  /// Types that belong to the approval story (the default view of the history screen).
  static const approvalTypes = {
    'SUBMISSION_CREATED',
    'REWORK_SUBMITTED',
    'REVIEW_APPROVED',
    'REVIEW_REJECTED',
    'REWORK_REQUESTED',
    'ADDITIONAL_PHOTOS_REQUESTED',
    'FINAL_APPROVAL',
    'REOPENED',
  };
  bool get isApproval => approvalTypes.contains(type);

  /// `review.OPS` change of a decision event, or null (the review stage this event is about).
  String? get stage {
    for (final c in changes) {
      if (c.field.startsWith('review.')) return c.field.substring(7);
    }
    return null;
  }

  String get stageName => _stageNames[stage] ?? (role.isNotEmpty ? roleLabel(role) : '');

  /// Who acted in words: "Asha (Recce Operations)".
  String get who => role.isEmpty ? actor : '$actor (${roleLabel(role)})';

  /// "Client Servicing approved", "Recce Operations requested rework", "Resubmitted V2"...
  String get title {
    final s = stageName;
    final v = version != null ? ' V$version' : '';
    return switch (type) {
      'SUBMISSION_CREATED' => 'Submitted$v',
      'REWORK_SUBMITTED' => 'Resubmitted$v',
      'REVIEW_APPROVED' => '${s.isEmpty ? 'Reviewer' : s} approved',
      'REVIEW_REJECTED' => '${s.isEmpty ? 'Reviewer' : s} rejected',
      'REWORK_REQUESTED' => '${s.isEmpty ? 'Reviewer' : s} requested rework',
      'ADDITIONAL_PHOTOS_REQUESTED' => '${s.isEmpty ? 'Reviewer' : s} asked for more photos',
      'FINAL_APPROVAL' => 'Shop approved',
      'REOPENED' => 'Reopened',
      _ => label,
    };
  }

  /// Everything except the review/status lines that the title already says.
  List<FieldChange> get detailChanges => [for (final c in changes) if (!c.field.startsWith('review.') && c.field != 'status') c];

  factory ActivityEvent.fromJson(Json j) {
    final photo = j['photo'] ?? j['photoId'];
    return ActivityEvent(
      id: (j['id'] ?? '').toString(),
      type: (j['type'] ?? '').toString(),
      label: (j['label'] ?? j['type'] ?? '').toString(),
      actor: _s(j['actor']) ?? 'Unknown',
      role: (j['role'] ?? '').toString(),
      at: _dt(j['at']),
      reason: (j['reason'] ?? '').toString(),
      mediaKey: _s(j['mediaKey']),
      photo: photo == null || photo.toString().isEmpty ? null : photo.toString(),
      version: j['version'] is num ? (j['version'] as num).toInt() : null,
      changes: [
        for (final c in _ml(j['changes'])) FieldChange(field: (c['field'] ?? '').toString(), from: c['oldValue'], to: c['newValue']),
      ],
    );
  }
}

/// The rework request that a REWORK_REQUESTED / ADDITIONAL_PHOTOS_REQUESTED event created: same version, closest in time
/// (the server writes both within a moment). Gives the history row its related photos and boards.
ReworkEntry? reworkForEvent(ActivityEvent e, List<ReworkEntry> reworks) {
  if (e.type != 'REWORK_REQUESTED' && e.type != 'ADDITIONAL_PHOTOS_REQUESTED') return null;
  final at = e.at;
  ReworkEntry? best;
  Duration? bestGap;
  for (final r in reworks) {
    if (e.version != null && r.versionNo != e.version) continue;
    final ra = r.requestedAt;
    if (at == null || ra == null) {
      best ??= r;
      continue;
    }
    final gap = ra.difference(at).abs();
    if (gap <= const Duration(minutes: 1) && (bestGap == null || gap < bestGap)) {
      best = r;
      bestGap = gap;
    }
  }
  return best;
}

/// Oldest first (a story), or newest first.
List<ActivityEvent> orderActivity(List<ActivityEvent> events, {required bool newestFirst}) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  final sorted = [...events]..sort((a, b) => (a.at ?? epoch).compareTo(b.at ?? epoch));
  return newestFirst ? sorted.reversed.toList() : sorted;
}

/* ------------------------------------------------------------------ photo filter (Photos tab) */

/// Filter chips of the Photos tab. `previous` lists photos of older versions that are not live any more.
enum PhotoFilter {
  all('All'),
  pending('Pending'),
  approved('Approved'),
  rework('Rework Required'),
  previous('Previous Versions');

  const PhotoFilter(this.label);
  final String label;

  /// Whether a LIVE photo belongs under this filter (`previous` never matches a live photo).
  bool matches(ShopPhoto p) => switch (this) {
        PhotoFilter.all => true,
        PhotoFilter.pending => p.review.status == 'PENDING',
        PhotoFilter.approved => p.review.status == 'APPROVED',
        PhotoFilter.rework => p.review.status == 'REWORK_REQUIRED',
        PhotoFilter.previous => false,
      };

  /// Photos still uploading from the phone are "pending" (not reviewed yet).
  bool get includesUploads => this == PhotoFilter.all || this == PhotoFilter.pending;
}

/// The rework item types that ask for one detail of a board to be checked: its size, quantity or media type. The server asks for no
/// answer to resubmit (the person corrects the board or confirms it is right).
const boardFixTypes = {'FIX_MEASUREMENT', 'FIX_QUANTITY', 'FIX_MEDIA_TYPE'};

/// The board detail a board request is about, in words: "size", "quantity", "media type".
String boardFixWhat(String type) => switch (type) {
      'FIX_QUANTITY' => 'quantity',
      'FIX_MEDIA_TYPE' => 'media type',
      _ => 'size',
    };

/// The title of a board request: "Check the quantity", "Correct the size", or "Quantity rejected" when the reviewer rejected it.
String boardFixTitle(String type, {bool rejected = false}) {
  final what = boardFixWhat(type);
  if (rejected) return '${what[0].toUpperCase()}${what.substring(1)} rejected';
  return type == 'FIX_MEASUREMENT' ? 'Correct the size' : 'Check the $what';
}

/// The title of a board request: the CHECKLIST label the reviewer ticked ("Measurements available", with "rejected" after it when the
/// reviewer rejected it) when there is one, else the generic [boardFixTitle].
String boardFixTitleFor(String type, {bool rejected = false, String label = ''}) {
  if (label.isEmpty) return boardFixTitle(type, rejected: rejected);
  return rejected ? '$label: rejected' : label;
}

/// What one rework item asks for, in words: "Replace Front View: Board not clear", "Correct the size of b1: Width is 8 ft",
/// "Check the quantity of GSB-01: Shop has 2 boards". [boardLabels] (board key to "GSB-01", see `ShopDetail.boardLabels`) names a board
/// by its number; without it the board key is shown.
String reworkItemText(ReworkItem i, {Map<String, String> boardLabels = const {}}) {
  final board = i.mediaKey.isEmpty ? 'a board' : (boardLabels[i.mediaKey] ?? i.mediaKey);
  // A reworked checklist item reads as its checklist label ("Shop front visible: Board is cut off"), not as the generic text.
  if (i.label.isNotEmpty && (i.type == 'OTHER' || boardFixTypes.contains(i.type))) {
    return '${i.rejected ? 'Rejected: ' : ''}${i.label}${i.note.isNotEmpty ? ': ${i.note}' : ''}${i.resolved ? ' (done)' : ''}';
  }
  final what = switch (i.type) {
    'REPLACE_PHOTO' => i.rejected ? 'Rejected: retake ${i.categoryLabel ?? 'the marked photo'}' : 'Replace ${i.categoryLabel ?? 'the marked photo'}',
    'ADDITIONAL_PHOTO' => 'Add ${i.categoryLabel ?? 'a photo'}',
    'FIX_MEASUREMENT' => i.rejected ? 'Rejected: size of $board' : 'Correct the size of $board',
    'FIX_QUANTITY' => i.rejected ? 'Rejected: quantity of $board' : 'Check the quantity of $board',
    'FIX_MEDIA_TYPE' => i.rejected ? 'Rejected: media type of $board' : 'Check the media type of $board',
    _ => 'Other',
  };
  return '$what${i.note.isNotEmpty ? ': ${i.note}' : ''}${i.resolved ? ' (done)' : ''}';
}
