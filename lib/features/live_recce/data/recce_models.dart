/// Typed models of the shop-wise recce API (contract: docs/recce-development/04-database-and-api-design.md).
/// Parsing is tolerant: a field the backend has not shipped yet falls back to a safe default.
library;

import 'package:flutter/material.dart';

part 'recce_history_models.dart';
part 'chat_models.dart';
part 'dashboard_models.dart';
part 'notification_models.dart';

typedef Json = Map<String, dynamic>;

String? _s(dynamic v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

double? _d(dynamic v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
int _i(dynamic v, [int fallback = 0]) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? fallback : fallback);
DateTime? _dt(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
Json _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Json> _ml(dynamic v) => v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : <Json>[];
List<String> _sl(dynamic v) => v is List ? [for (final e in v) if (e != null) e.toString()] : <String>[];

/* ------------------------------------------------------------------ statuses */

/// DRAFT and READY_TO_SUBMIT are worked out by the server.
const recceStatusLabels = <String, String>{
  'NOT_STARTED': 'Not started',
  'IN_PROGRESS': 'In progress',
  'DRAFT': 'Draft',
  'READY_TO_SUBMIT': 'Ready to submit',
  'SUBMITTED': 'Submitted',
  'UNDER_REVIEW': 'Under review',
  'APPROVED': 'Approved',
  'REWORK_REQUIRED': 'Rework required',
  'REJECTED': 'Rejected',
};

String statusLabel(String s) => recceStatusLabels[s] ?? s;

Color statusColor(String s) => switch (s) {
      'APPROVED' => const Color(0xFF1E8E3E),
      'REWORK_REQUIRED' => const Color(0xFFE37400),
      'REJECTED' => const Color(0xFFB3261E),
      'SUBMITTED' || 'UNDER_REVIEW' => const Color(0xFF1A73E8),
      'READY_TO_SUBMIT' => const Color(0xFF00897B),
      'IN_PROGRESS' || 'DRAFT' => const Color(0xFF7B1FA2),
      _ => const Color(0xFF6B6F76),
    };

/// Dashboard cards: Total / Submitted / Approved / Pending / Rework, from `meta.summary`.
class DashboardCounts {
  const DashboardCounts({this.total = 0, this.submitted = 0, this.approved = 0, this.pending = 0, this.rework = 0});

  final int total;
  final int submitted;
  final int approved;
  final int pending;
  final int rework;

  factory DashboardCounts.fromSummary(Map<String, int> s) {
    int n(String k) => s[k] ?? 0;
    return DashboardCounts(
      total: s.values.fold(0, (a, b) => a + b),
      submitted: n('SUBMITTED') + n('UNDER_REVIEW'),
      approved: n('APPROVED'),
      pending: n('NOT_STARTED') + n('IN_PROGRESS') + n('DRAFT') + n('READY_TO_SUBMIT'),
      rework: n('REWORK_REQUIRED'),
    );
  }
}

/// Status filter chips of the shop list.
enum ShopFilter {
  all('All', {}),
  notStarted('Not started', {'NOT_STARTED'}),
  inProgress('In progress', {'IN_PROGRESS', 'DRAFT', 'READY_TO_SUBMIT'}),
  submitted('Submitted', {'SUBMITTED', 'UNDER_REVIEW'}),
  rework('Rework', {'REWORK_REQUIRED'}),
  approved('Approved', {'APPROVED'});

  const ShopFilter(this.label, this.statuses);
  final String label;
  final Set<String> statuses;

  bool matches(String status) => statuses.isEmpty || statuses.contains(status);
}

/* ------------------------------------------------------------------ list */

class ShopSummary {
  const ShopSummary({
    required this.siteId,
    required this.projectId,
    required this.projectCode,
    required this.projectName,
    this.client,
    required this.siteCode,
    this.shopName,
    this.address = '',
    this.mediaTypes = const [],
    this.assignedAt,
    this.expectedBy,
    required this.status,
    this.progress = 0,
    this.photoCount = 0,
    this.missing = 0,
    this.reworkOpen = false,
    this.version = 0,
  });

  final String siteId;
  final String projectId;
  final String projectCode;
  final String projectName;
  final String? client;
  final String siteCode;
  final String? shopName;
  final String address;
  final List<String> mediaTypes; // "GSB x 2"
  final DateTime? assignedAt;
  final DateTime? expectedBy;
  final String status;
  final int progress;
  final int photoCount;
  final int missing;
  final bool reworkOpen;
  final int version;

  String get title => shopName ?? siteCode;

  factory ShopSummary.fromJson(Json j) => ShopSummary(
        siteId: j['siteId'].toString(),
        projectId: (j['projectId'] ?? '').toString(),
        projectCode: (j['projectCode'] ?? '').toString(),
        projectName: (j['projectName'] ?? '').toString(),
        client: _s(j['client']),
        siteCode: (j['siteCode'] ?? '').toString(),
        shopName: _s(j['shopName']),
        address: (j['address'] ?? '').toString(),
        mediaTypes: [for (final m in _ml(j['mediaTypes'])) '${m['name']} x ${m['quantity'] ?? 1}'],
        assignedAt: _dt(j['assignedAt']),
        expectedBy: _dt(j['expectedBy']),
        status: (j['status'] ?? 'NOT_STARTED').toString(),
        progress: _i(j['progress']),
        photoCount: _i(j['photoCount']),
        missing: _i(j['missing']),
        reworkOpen: j['reworkOpen'] == true,
        version: _i(j['version']),
      );
}

/// One page of `GET /recce/shops` with `meta.summary` (counts per status for the whole login).
class ShopListPage {
  const ShopListPage({required this.items, required this.total, required this.summary});

  final List<ShopSummary> items;
  final int total;
  final Map<String, int> summary;

  factory ShopListPage.fromEnvelope(dynamic body) {
    final map = body is Map ? body : const {};
    final meta = _m(map['meta']);
    final raw = _m(meta['summary']);
    return ShopListPage(
      items: [for (final e in _ml(map['data'])) ShopSummary.fromJson(e)],
      total: _i(meta['total']),
      summary: {for (final e in raw.entries) e.key: _i(e.value)},
    );
  }
}

/// A project with the shops given to this login (the Projects screen).
class ProjectGroup {
  const ProjectGroup({required this.projectId, required this.code, required this.name, this.client, required this.shops});

  final String projectId;
  final String code;
  final String name;
  final String? client;
  final List<ShopSummary> shops;

  int get done => shops.where((s) => s.status == 'APPROVED').length;
  int get submitted => shops.where((s) => s.status == 'SUBMITTED' || s.status == 'UNDER_REVIEW').length;
  int get rework => shops.where((s) => s.status == 'REWORK_REQUIRED').length;
  DateTime? get expectedBy => shops.map((s) => s.expectedBy).whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
}

List<ProjectGroup> groupByProject(List<ShopSummary> shops) {
  final byId = <String, List<ShopSummary>>{};
  for (final s in shops) {
    byId.putIfAbsent(s.projectId, () => []).add(s);
  }
  return [
    for (final e in byId.entries)
      ProjectGroup(projectId: e.key, code: e.value.first.projectCode, name: e.value.first.projectName, client: e.value.first.client, shops: e.value),
  ]..sort((a, b) => a.code.compareTo(b.code));
}

/* ------------------------------------------------------------------ photos */

class PhotoCategoryDef {
  const PhotoCategoryDef(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

/// The six GPS-tagged photos of the live flow: the checklist the product owner wants on every shop. The SERVER decides what
/// else is required (`RecceConfig.requiredPhotos`, reported in `progress.missing`): see [ShopDetail.extraPhotoSlots].
const requiredPhotoCategories = <PhotoCategoryDef>[
  PhotoCategoryDef('SHOP_FRONT', 'Front View', Icons.storefront_outlined),
  PhotoCategoryDef('SIDE_VIEW', 'Side View', Icons.swap_horiz),
  PhotoCategoryDef('LONG_SHOT', 'Long Shot', Icons.panorama_horizontal_outlined),
  PhotoCategoryDef('ANNOTATED_VIEW', 'Annotated View', Icons.draw_outlined),
  PhotoCategoryDef('LOCATION_VIEW', 'Location View', Icons.place_outlined),
  PhotoCategoryDef('ACCESS_PATH', 'Access Path', Icons.alt_route),
];

/// The photos EVERY physical board needs (2026-11-23), in capture order. The existing server categories are reused, none is
/// renamed: Front View = `SHOP_FRONT`, Left View = `LEFT_SIDE`, Right View = `RIGHT_SIDE`. Each photo is sent with the board's
/// key as its `mediaKey`, so one board's Front View never stands in for another board's.
const boardPhotoCategories = <PhotoCategoryDef>[
  PhotoCategoryDef('SHOP_FRONT', 'Front View', Icons.storefront_outlined),
  PhotoCategoryDef('LEFT_SIDE', 'Left View', Icons.arrow_back),
  PhotoCategoryDef('RIGHT_SIDE', 'Right View', Icons.arrow_forward),
  PhotoCategoryDef('LONG_SHOT', 'Long Shot', Icons.panorama_horizontal_outlined),
  PhotoCategoryDef('ANNOTATED_VIEW', 'Annotated View', Icons.draw_outlined),
  PhotoCategoryDef('LOCATION_VIEW', 'Location View', Icons.place_outlined),
  PhotoCategoryDef('ACCESS_PATH', 'Access Path', Icons.alt_route),
];

/// One photo place of one board: a category on a board (`mediaKey` = the board's key).
class PhotoSlot {
  const PhotoSlot(this.category, this.mediaKey);
  final String category;
  final String mediaKey;
}

/// A category that has its own standard tile (the six of the old shop checklist or the seven of a board).
bool isLiveFlowCategory(String key) => requiredPhotoCategories.any((c) => c.key == key) || boardPhotoCategories.any((c) => c.key == key);

/// One entry of `progress.missing`: a required photo category (or `DIMENSIONS`) that a board still lacks.
class MissingEvidence {
  const MissingEvidence({required this.category, this.label = '', this.mediaKey = '', this.mediaName = ''});

  static const dimensions = 'DIMENSIONS';

  final String category;
  final String label;
  final String mediaKey; // the board that needs it
  final String mediaName;

  /// A photo (not the width / height / quantity check).
  bool get isPhoto => category.isNotEmpty && category != dimensions;

  /// Same rule as the server (`missingFor`): a live photo of the category that belongs to this board or to no board.
  bool satisfiedBy(Iterable<ShopPhoto> photos) => photos.any((p) => p.category == category && (p.mediaKey.isEmpty || p.mediaKey == mediaKey));

  factory MissingEvidence.fromJson(Json j) => MissingEvidence(
        category: (j['category'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        mediaKey: (j['mediaKey'] ?? '').toString(),
        mediaName: (j['mediaName'] ?? '').toString(),
      );
}

/// A photo category the server requires on top of the six (for example NAME_BOARD): it gets its own capture tile.
class ExtraPhotoSlot {
  const ExtraPhotoSlot({required this.category, required this.label});
  final String category;
  final String label;
}

/// GPS accuracy (metres) worse than this is shown as "location unverified" (the server flags it too).
const gpsAccuracyLimitM = 50.0;

class ReworkNote {
  const ReworkNote({this.reason = '', this.note = '', this.instructions = '', this.by, this.role, this.at, this.reworkId, this.itemId});

  /// The text to show first: an explicit reason, else the note on this photo, else the overall instructions.
  final String reason;

  /// The note the reviewer wrote on this one photo (the open rework item).
  final String note;

  /// The overall instructions of the rework request.
  final String instructions;
  final String? by;
  final String? role; // stageLabel: "Recce Operations" / "Client Servicing"
  final DateTime? at;
  final String? reworkId;
  final String? itemId;

  static String? _name(dynamic v) => v is Map ? _s(v['name']) : _s(v);

  /// Reads `photo.review.openRework` (`reworkId, itemId, note, stage, stageLabel, instructions, requestedBy, requestedAt`).
  /// Older field names are still accepted.
  factory ReworkNote.fromJson(Json j) {
    final note = _s(j['note']) ?? '';
    final instructions = _s(j['instructions']) ?? '';
    return ReworkNote(
      reason: _s(j['reason']) ?? (note.isNotEmpty ? note : (instructions.isNotEmpty ? instructions : (_s(j['comment']) ?? ''))),
      note: note,
      instructions: instructions,
      by: _name(j['requestedBy'] ?? j['by'] ?? j['reviewer']),
      role: _s(j['stageLabel'] ?? j['requestedByRole'] ?? j['role'] ?? j['stage']),
      at: _dt(j['requestedAt'] ?? j['at'] ?? j['createdAt']),
      reworkId: _s(j['reworkId']),
      itemId: _s(j['itemId']),
    );
  }
}

class PhotoReview {
  const PhotoReview({this.status = 'PENDING', this.openRework});

  final String status;
  final ReworkNote? openRework;

  factory PhotoReview.fromJson(dynamic v) {
    final j = _m(v);
    return PhotoReview(
      status: (j['status'] ?? 'PENDING').toString(),
      openRework: j['openRework'] is Map ? ReworkNote.fromJson(_m(j['openRework'])) : null,
    );
  }
}

class ShopPhoto {
  const ShopPhoto({
    required this.id,
    required this.category,
    this.state = 'DRAFT',
    this.mediaKey = '',
    this.caption = '',
    this.capturedAt,
    this.lat,
    this.lng,
    this.gpsAccuracy,
    this.gpsVerified = false,
    this.source,
    this.url,
    this.editedUrl,
    this.flags = const [],
    this.review = const PhotoReview(),
    this.version,
    this.replaces,
    this.supersededBy,
    this.uploadedAt,
    this.uploadedBy,
    this.capturedByRole,
    this.device,
    this.removedAt,
    this.removedBy,
    this.removeReason,
  });

  final String id;
  final String category;
  final String state;
  final String mediaKey;
  final String caption;
  final DateTime? capturedAt;
  final double? lat;
  final double? lng;
  final double? gpsAccuracy;
  final bool gpsVerified;
  final String? source;
  final String? url;
  final String? editedUrl;
  final List<String> flags;
  final PhotoReview review;
  final int? version; // the version that first carried this photo (null while DRAFT)
  final String? replaces; // the older photo this one replaces
  final String? supersededBy; // the newer photo that replaced this one
  final DateTime? uploadedAt;
  final String? uploadedBy;
  final String? capturedByRole;
  final String? device;
  final DateTime? removedAt;
  final String? removedBy;
  final String? removeReason;

  bool get isDraft => state == 'DRAFT';
  bool get isApproved => review.status == 'APPROVED';

  bool get hasGps => lat != null && lng != null && !(lat == 0 && lng == 0);
  bool get weakGps => gpsAccuracy != null && gpsAccuracy! > gpsAccuracyLimitM;

  /// Shown as "location unverified": no usable GPS, weak accuracy, or the server did not verify it.
  bool get locationUnverified => !hasGps || weakGps || !gpsVerified;
  bool get needsRework => review.status == 'REWORK_REQUIRED';
  String? get displayUrl => editedUrl ?? url;

  factory ShopPhoto.fromJson(Json j) => ShopPhoto(
        id: j['id'].toString(),
        category: (j['category'] ?? '').toString(),
        state: (j['state'] ?? 'DRAFT').toString(),
        mediaKey: (j['mediaKey'] ?? '').toString(),
        caption: (j['caption'] ?? '').toString(),
        capturedAt: _dt(j['capturedAt']),
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        gpsAccuracy: _d(j['gpsAccuracy']),
        gpsVerified: j['gpsVerified'] == true,
        source: _s(j['source']),
        url: _s(j['url']),
        editedUrl: _s(j['editedUrl']),
        flags: [for (final f in (j['flags'] is List ? j['flags'] as List : const [])) f is Map ? (f['code'] ?? '').toString() : f.toString()],
        review: PhotoReview.fromJson(j['review']),
        version: j['version'] is num ? (j['version'] as num).toInt() : null,
        replaces: _s(j['replaces']),
        supersededBy: _s(j['supersededBy']),
        uploadedAt: _dt(j['uploadedAt']),
        uploadedBy: _s(j['uploadedBy']),
        capturedByRole: _s(j['capturedByRole']),
        device: _s(j['device']),
        removedAt: _dt(j['removedAt']),
        removedBy: _s(j['removedBy']),
        removeReason: _s(j['removeReason']),
      );
}

/// Label of a photo category: the live-flow names (the board's seven first, then the old six), else the key written in words
/// ("NAME_BOARD" -> "Name board").
String photoCategoryLabel(String key) {
  for (final c in [...boardPhotoCategories, ...requiredPhotoCategories]) {
    if (c.key == key) return c.label;
  }
  if (key.isEmpty) return 'Photo';
  final words = key.toLowerCase().split('_').join(' ');
  return words[0].toUpperCase() + words.substring(1);
}

/* ------------------------------------------------------------------ boards and installation */

const boardTypes = ['GSB', 'Acrylic', 'ACP', 'Vinyl', 'Flex', 'LED', 'Other'];
const boardUnits = ['FT', 'IN', 'M', 'CM', 'MM'];
const maxBoardItems = 12;

/// One physical board. Boards made with "Add boards" (from 2026-11-23) are always quantity 1, have their own permanent [key]
/// (photos, reviews and rework point at it) and a number: [mediaType] + [seq] read "GSB-01". Older lines have no number and may
/// stand for several identical boards ([quantity] above 1).
class BoardItem {
  BoardItem({
    required this.key,
    this.name = 'GSB',
    this.mediaType = '',
    this.seq = 0,
    this.requiredPhotos = const [],
    this.quantity = 1,
    this.width,
    this.height,
    this.unit = 'FT',
    this.sided = 'SINGLE',
    this.condition = 'PROPOSED',
    this.position = '',
    this.notes = '',
  });

  String key;
  String name;

  /// Short name of the media type the board was made from ("GSB", "ACP 2D"), as the person saw it. Empty on older lines.
  String mediaType;

  /// Number among the boards of the same media type (1 = "GSB-01"). 0 on older lines.
  int seq;

  /// Photo categories the SERVER requires for this board (`mediaItems[].required`). Read-only: never sent back.
  final List<String> requiredPhotos;
  int quantity;
  double? width;
  double? height;
  String unit;
  String sided; // SINGLE | DOUBLE
  String condition; // EXISTING | PROPOSED
  String position;
  String notes;

  /// A board that has its own number (made with "Add boards").
  bool get isNumbered => mediaType.isNotEmpty && seq > 0;

  /// "GSB-01" for a numbered board; an older line shows its name and key.
  String get label => isNumbered ? '$mediaType-${seq.toString().padLeft(2, '0')}' : (name.trim().isEmpty ? key : '${name.trim()} ($key)');

  factory BoardItem.fromJson(Json j) => BoardItem(
        key: j['key'].toString(),
        name: (j['name'] ?? 'GSB').toString(),
        mediaType: (j['mediaType'] ?? '').toString(),
        seq: _i(j['seq']),
        requiredPhotos: _sl(j['required']),
        quantity: _i(j['quantity'], 1),
        width: _d(j['width']),
        height: _d(j['height']),
        unit: boardUnits.contains(j['unit']) ? j['unit'] as String : 'FT',
        sided: j['sided'] == 'DOUBLE' ? 'DOUBLE' : 'SINGLE',
        condition: j['condition'] == 'EXISTING' ? 'EXISTING' : 'PROPOSED',
        position: (j['position'] ?? '').toString(),
        notes: (j['notes'] ?? '').toString(),
      );

  /// Body item of `PUT /recce/shops/:siteId/draft`.
  Json toJson() => {
        'key': key,
        'name': name.trim(),
        if (isNumbered) ...{'mediaType': mediaType, 'seq': seq},
        'quantity': quantity,
        'width': ?width,
        'height': ?height,
        'unit': unit,
        'sided': sided,
        'condition': condition,
        if (position.trim().isNotEmpty) 'position': position.trim(),
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      };

  BoardItem copy() => BoardItem.fromJson({...toJson(), 'required': requiredPhotos});

  bool get hasSize => (width ?? 0) > 0 && (height ?? 0) > 0;
}

/// The number the next board of [mediaType] gets: one above the highest number already used by that type (a removed board's
/// number is not handed out again while a higher one exists).
int nextBoardSeq(Iterable<BoardItem> boards, String mediaType) {
  var top = 0;
  for (final b in boards) {
    if (b.mediaType == mediaType && b.seq > top) top = b.seq;
  }
  return top + 1;
}

/// Next free `b1, b2, ...` key.
String nextBoardKey(Iterable<String> used) {
  final taken = used.toSet();
  var n = 1;
  while (taken.contains('b$n')) {
    n++;
  }
  return 'b$n';
}

const triYes = 'YES';
const triNo = 'NO';
const triUnknown = 'NOT_ASSESSED';

/// Installation feasibility. An unanswered field is NOT_ASSESSED, never read as NO.
class Installation {
  Installation({
    this.ladderRequired = triUnknown,
    this.scaffoldingRequired = triUnknown,
    this.craneRequired = triUnknown,
    this.hydraRequired = triUnknown,
    this.manualInstallationPossible = triUnknown,
    this.electricalAccess = triUnknown,
    this.installationHeightFt,
    List<String>? accessRestrictions,
    this.obstruction = '',
    this.roadsideConstraints = '',
    this.safetyNotes = '',
    List<String>? additionalEquipment,
    this.notes = '',
  })  : accessRestrictions = accessRestrictions ?? [],
        additionalEquipment = additionalEquipment ?? [];

  String ladderRequired;
  String scaffoldingRequired;
  String craneRequired;
  String hydraRequired;
  String manualInstallationPossible;
  String electricalAccess; // AVAILABLE | NOT_AVAILABLE | NOT_ASSESSED
  double? installationHeightFt;
  List<String> accessRestrictions;
  String obstruction;
  String roadsideConstraints;
  String safetyNotes;
  List<String> additionalEquipment;
  String notes;

  static String _tri(dynamic v) => v == triYes || v == triNo ? v as String : triUnknown;

  factory Installation.fromJson(dynamic v) {
    final j = _m(v);
    return Installation(
      ladderRequired: _tri(j['ladderRequired']),
      scaffoldingRequired: _tri(j['scaffoldingRequired']),
      craneRequired: _tri(j['craneRequired']),
      hydraRequired: _tri(j['hydraRequired']),
      manualInstallationPossible: _tri(j['manualInstallationPossible']),
      electricalAccess: j['electricalAccess'] == 'AVAILABLE' || j['electricalAccess'] == 'NOT_AVAILABLE' ? j['electricalAccess'] as String : triUnknown,
      installationHeightFt: _d(j['installationHeightFt']),
      accessRestrictions: _sl(j['accessRestrictions']),
      obstruction: (j['obstruction'] ?? '').toString(),
      roadsideConstraints: (j['roadsideConstraints'] ?? '').toString(),
      safetyNotes: (j['safetyNotes'] ?? '').toString(),
      additionalEquipment: _sl(j['additionalEquipment']),
      notes: (j['notes'] ?? '').toString(),
    );
  }

  Json toJson() => {
        'ladderRequired': ladderRequired,
        'scaffoldingRequired': scaffoldingRequired,
        'craneRequired': craneRequired,
        'hydraRequired': hydraRequired,
        'manualInstallationPossible': manualInstallationPossible,
        'electricalAccess': electricalAccess,
        'installationHeightFt': ?installationHeightFt,
        'accessRestrictions': accessRestrictions,
        'obstruction': obstruction.trim(),
        'roadsideConstraints': roadsideConstraints.trim(),
        'safetyNotes': safetyNotes.trim(),
        'additionalEquipment': additionalEquipment,
        'notes': notes.trim(),
      };

  /// Body of `PUT /recce/shops/:siteId/draft`. A cleared height is sent as an explicit `null`: the server only removes the stored
  /// value on `null` (a missing key means "leave it as it is"), so [toJson] alone could never clear it.
  Json toDraftJson() => {...toJson(), 'installationHeightFt': installationHeightFt};

  /// Largest installation height the server accepts (`installationBody`: max 500).
  static const maxHeightFt = 500.0;

  /// The reason the height cannot be saved, or null.
  String? get heightProblem {
    final h = installationHeightFt;
    return h != null && h > maxHeightFt ? 'Installation height can be at most ${maxHeightFt.toInt()} ft' : null;
  }

  /// Labels of the five required yes/no answers that are still NOT_ASSESSED.
  List<String> get unanswered => [
        if (ladderRequired == triUnknown) 'Ladder',
        if (scaffoldingRequired == triUnknown) 'Scaffolding',
        if (craneRequired == triUnknown) 'Crane',
        if (hydraRequired == triUnknown) 'Hydra',
        if (manualInstallationPossible == triUnknown) 'Manual installation',
      ];
}

/* ------------------------------------------------------------------ review / versions */

class ReviewEntry {
  const ReviewEntry({required this.versionNo, required this.stageLabel, this.decision, this.comment = '', this.reviewer, this.decidedAt});

  final int versionNo;
  final String stageLabel;
  final String? decision; // null while pending
  final String comment;
  final String? reviewer;
  final DateTime? decidedAt;

  factory ReviewEntry.fromJson(Json j) => ReviewEntry(
        versionNo: _i(j['versionNo']),
        stageLabel: (j['stageLabel'] ?? j['stage'] ?? '').toString(),
        decision: _s(j['decision']),
        comment: (j['comment'] ?? '').toString(),
        reviewer: _s(j['reviewer']),
        decidedAt: _dt(j['decidedAt']),
      );
}

class ReworkItem {
  const ReworkItem({
    required this.type,
    this.id = '',
    this.category,
    this.categoryLabel,
    this.mediaKey = '',
    this.photo,
    this.note = '',
    this.resolved = false,
    this.resolvedInVersion,
  });

  final String type; // REPLACE_PHOTO | ADDITIONAL_PHOTO | FIX_MEASUREMENT | OTHER
  final String id;
  final String? category;
  final int? resolvedInVersion;
  final String? categoryLabel;
  final String mediaKey;
  final String? photo;
  final String note;
  final bool resolved;

  /// Asks for a NEW photo of [category]: an extra photo, or a "replace" that names a category but no photo (nothing to link
  /// `replaces` to, so it can only be answered with a new photo of that category).
  bool get asksForNewPhoto => !resolved && category != null && (type == 'ADDITIONAL_PHOTO' || (type == 'REPLACE_PHOTO' && photo == null));

  /// Whether one of the DRAFT photos [drafts] answers it: same category, and the same board when the item names one (server rule).
  bool answeredBy(Iterable<ShopPhoto> drafts) => drafts.any((d) => d.category == category && (mediaKey.isEmpty || d.mediaKey == mediaKey));

  factory ReworkItem.fromJson(Json j) => ReworkItem(
        type: (j['type'] ?? '').toString(),
        id: (j['id'] ?? '').toString(),
        category: _s(j['category']),
        resolvedInVersion: j['resolvedInVersion'] is num ? (j['resolvedInVersion'] as num).toInt() : null,
        categoryLabel: _s(j['categoryLabel']),
        mediaKey: (j['mediaKey'] ?? '').toString(),
        photo: _s(j['photo']),
        note: (j['note'] ?? '').toString(),
        resolved: j['resolved'] == true,
      );
}

class ReworkEntry {
  const ReworkEntry({
    required this.id,
    required this.versionNo,
    required this.stageLabel,
    required this.kind,
    required this.status,
    this.instructions = '',
    this.requestedBy,
    this.requestedAt,
    this.resolvedAt,
    this.items = const [],
  });

  final String id;
  final int versionNo;
  final String stageLabel;
  final String kind;
  final String status; // OPEN | RESOLVED | ...
  final String instructions;
  final String? requestedBy;
  final DateTime? requestedAt;
  final DateTime? resolvedAt;
  final List<ReworkItem> items;

  bool get isOpen => status == 'OPEN';

  /// What this request says about one of its items: the item's note first, else the overall instructions; who asked and when.
  ReworkNote noteFor(ReworkItem i) => ReworkNote(
        reason: i.note.isNotEmpty ? i.note : instructions,
        note: i.note,
        instructions: instructions,
        by: requestedBy,
        role: stageLabel,
        at: requestedAt,
        reworkId: id,
        itemId: i.id.isEmpty ? null : i.id,
      );

  factory ReworkEntry.fromJson(Json j) => ReworkEntry(
        id: (j['id'] ?? '').toString(),
        versionNo: _i(j['versionNo']),
        stageLabel: (j['stageLabel'] ?? j['stage'] ?? '').toString(),
        kind: (j['kind'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        instructions: (j['instructions'] ?? '').toString(),
        requestedBy: ReworkNote._name(j['requestedBy']),
        requestedAt: _dt(j['requestedAt']),
        resolvedAt: _dt(j['resolvedAt']),
        items: [for (final i in _ml(j['items'])) ReworkItem.fromJson(i)],
      );
}

/// An open rework item that asks for a new photo ("Additional photo requested"), with the reviewer's note and who asked.
class RequestedPhoto {
  const RequestedPhoto({required this.item, required this.note, required this.label});

  final ReworkItem item;
  final ReworkNote note;
  final String label;

  String get category => item.category ?? '';
  String get mediaKey => item.mediaKey;
  String get key => item.id.isNotEmpty ? item.id : '${note.reworkId}|$category|$mediaKey';

  /// The newest of [drafts] that answers this request, or null.
  ShopPhoto? answer(Iterable<ShopPhoto> drafts) {
    ShopPhoto? found;
    for (final d in drafts) {
      if (d.isDraft && item.answeredBy([d])) found = d;
    }
    return found;
  }
}

class VersionEntry {
  const VersionEntry({required this.version, this.submittedAt, this.photoCount = 0});

  final int version;
  final DateTime? submittedAt;
  final int photoCount;

  factory VersionEntry.fromJson(Json j) =>
      VersionEntry(version: _i(j['version']), submittedAt: _dt(j['submittedAt']), photoCount: _i(j['photoCount']));
}

/* ------------------------------------------------------------------ detail */

class ProjectInfo {
  const ProjectInfo({required this.id, required this.code, required this.name, this.client, this.expectedBy, this.closed = false});

  final String id;
  final String code;
  final String name;
  final String? client;
  final DateTime? expectedBy;
  final bool closed;

  factory ProjectInfo.fromJson(dynamic v) {
    final j = _m(v);
    return ProjectInfo(
      id: (j['id'] ?? '').toString(),
      code: (j['code'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      client: _s(j['client']),
      expectedBy: _dt(j['expectedBy']),
      closed: j['closed'] == true,
    );
  }
}

/// `GET /recce/shops/:siteId` (also returned by draft, photo upload and submit).
class ShopDetail {
  const ShopDetail({
    required this.siteId,
    required this.siteCode,
    this.shopName,
    this.address = '',
    this.contactPerson,
    this.mobile,
    required this.project,
    required this.status,
    this.editable = false,
    this.version = 0,
    this.assignedAt,
    this.mediaItems = const [],
    required this.installation,
    this.notes = '',
    this.photos = const [],
    this.progressPercent = 0,
    this.missing = const [],
    this.serverRequired = const [],
    this.categoryNames = const {},
    this.versions = const [],
    this.reviews = const [],
    this.reworks = const [],
  });

  final String siteId;
  final String siteCode;
  final String? shopName;
  final String address;
  final String? contactPerson;
  final String? mobile;
  final ProjectInfo project;
  final String status;
  final bool editable;
  final int version;
  final DateTime? assignedAt;
  final List<BoardItem> mediaItems;
  final Installation installation;
  final String notes;
  final List<ShopPhoto> photos;
  final int progressPercent;

  /// `progress.missing`: what the SERVER still needs before this shop can be submitted (photo categories per board, and DIMENSIONS).
  final List<MissingEvidence> missing;

  /// Photo categories the server requires for the boards of this shop (`mediaItems[].required`), whether taken yet or not.
  final List<String> serverRequired;

  /// `categories`: every photo category the server knows, key to label.
  final Map<String, String> categoryNames;
  final List<VersionEntry> versions;
  final List<ReviewEntry> reviews;
  final List<ReworkEntry> reworks;

  String get title => shopName ?? siteCode;

  /// Newest photo of a category (the list is ordered oldest first).
  ShopPhoto? photoFor(String category) {
    ShopPhoto? found;
    for (final p in photos) {
      if (p.category == category) found = p;
    }
    return found;
  }

  /// Newest photo of [category] for the board [boardKey]. A photo with no board (taken before boards had their own photos) stands
  /// in for every board, the same rule as the server's `missingFor`; a photo of the board itself always wins.
  ShopPhoto? photoOf(String category, String boardKey) {
    ShopPhoto? own;
    ShopPhoto? shared;
    for (final p in photos) {
      if (p.category != category) continue;
      if (p.mediaKey == boardKey) {
        own = p;
      } else if (p.mediaKey.isEmpty) {
        shared = p;
      }
    }
    return own ?? shared;
  }

  /// Photo categories the server requires for [board] beyond the seven standard ones (for example NAME_BOARD): its own required
  /// list plus anything `progress.missing` names for it. Each gets a capture tile in the board's section.
  List<PhotoCategoryDef> extraTilesFor(BoardItem board) {
    final out = <String, PhotoCategoryDef>{};
    void add(String category, String? label) {
      if (category.isEmpty || category == MissingEvidence.dimensions || isLiveFlowCategory(category) || out.containsKey(category)) return;
      out[category] = PhotoCategoryDef(category, categoryLabel(category, fallback: label), Icons.add_a_photo_outlined);
    }

    for (final c in board.requiredPhotos) {
      add(c, null);
    }
    for (final m in missing) {
      if (m.isPhoto && m.mediaKey == board.key) add(m.category, m.label);
    }
    return out.values.toList();
  }

  /// Name of a photo category: the live-flow name for the standard ones, else the server's label ([fallback] when the list lacks
  /// it), else the key written in words.
  String categoryLabel(String key, {String? fallback}) {
    if (isLiveFlowCategory(key)) return photoCategoryLabel(key);
    final name = categoryNames[key] ?? ((fallback ?? '').isNotEmpty ? fallback : null);
    return name ?? photoCategoryLabel(key);
  }

  /// Photo categories the server needs beyond the six (for example NAME_BOARD, MEASUREMENT): every required category of the
  /// boards plus anything `progress.missing` names. Each one gets a capture tile so the shop can actually be completed.
  List<ExtraPhotoSlot> get extraPhotoSlots {
    final out = <String, ExtraPhotoSlot>{};
    void add(String category, String? label) {
      if (category.isEmpty || category == MissingEvidence.dimensions || isLiveFlowCategory(category) || out.containsKey(category)) return;
      out[category] = ExtraPhotoSlot(category: category, label: categoryLabel(category, fallback: label));
    }

    for (final c in serverRequired) {
      add(c, null);
    }
    for (final m in missing) {
      if (m.isPhoto) add(m.category, m.label);
    }
    return out.values.toList();
  }

  /// Open rework items that ask for a new photo, each with the reviewer's note (the "Additional photo requested" cards).
  List<RequestedPhoto> get requestedPhotos {
    final out = <RequestedPhoto>[];
    for (final r in reworks.where((r) => r.isOpen)) {
      for (final i in r.items.where((i) => i.asksForNewPhoto)) {
        out.add(RequestedPhoto(item: i, note: r.noteFor(i), label: categoryLabel(i.category!, fallback: i.categoryLabel)));
      }
    }
    return out;
  }

  /// Reason shown for a flagged photo: its own `review.openRework`, else the open rework item that names the photo.
  ReworkNote? reworkNoteFor(ShopPhoto p) {
    if (p.review.openRework != null) return p.review.openRework;
    for (final r in reworks.where((r) => r.isOpen)) {
      for (final i in r.items) {
        if (i.photo == p.id) return r.noteFor(i);
      }
    }
    return null;
  }

  /// The open FIX_MEASUREMENT request that names this board (`mediaKey`), as a note for the board card; null when there is none.
  ReworkNote? measurementReworkFor(String mediaKey) {
    if (mediaKey.isEmpty) return null;
    for (final r in reworks.where((r) => r.isOpen)) {
      for (final i in r.items) {
        if (i.type == 'FIX_MEASUREMENT' && !i.resolved && i.mediaKey == mediaKey) return r.noteFor(i);
      }
    }
    return null;
  }

  /// Open FIX_MEASUREMENT requests that cannot sit on a board card: web reviewers may send them without a `mediaKey`, or with the
  /// key of a board that is not in [boardKeys] any more. They are shown as a general "Measurement rework requested" banner so the
  /// note is never lost. [forBoard] is the board key the item named (empty when it named none).
  List<({ReworkNote note, String forBoard})> measurementReworksWithoutBoard(Iterable<String> boardKeys) {
    final keys = boardKeys.toSet();
    final out = <({ReworkNote note, String forBoard})>[];
    for (final r in reworks.where((r) => r.isOpen)) {
      for (final i in r.items) {
        if (i.type == 'FIX_MEASUREMENT' && !i.resolved && (i.mediaKey.isEmpty || !keys.contains(i.mediaKey))) {
          out.add((note: r.noteFor(i), forBoard: i.mediaKey));
        }
      }
    }
    return out;
  }

  factory ShopDetail.fromJson(Json j) {
    final progress = _m(j['progress']);
    final needed = <String>[];
    for (final m in _ml(j['mediaItems'])) {
      for (final c in _sl(m['required'])) {
        if (!needed.contains(c)) needed.add(c);
      }
    }
    return ShopDetail(
      siteId: j['siteId'].toString(),
      siteCode: (j['siteCode'] ?? '').toString(),
      shopName: _s(j['shopName']),
      address: (j['address'] ?? '').toString(),
      contactPerson: _s(j['contactPerson']),
      mobile: _s(j['mobile']),
      project: ProjectInfo.fromJson(j['project']),
      status: (j['status'] ?? 'NOT_STARTED').toString(),
      editable: j['editable'] == true,
      version: _i(j['version']),
      assignedAt: _dt(j['assignedAt']),
      mediaItems: [for (final e in _ml(j['mediaItems'])) BoardItem.fromJson(e)],
      installation: Installation.fromJson(j['installation']),
      notes: (j['notes'] ?? '').toString(),
      photos: [for (final e in _ml(j['photos'])) ShopPhoto.fromJson(e)],
      progressPercent: _i(progress['percent']),
      missing: [for (final e in _ml(progress['missing'])) MissingEvidence.fromJson(e)],
      serverRequired: needed,
      categoryNames: {
        for (final e in _ml(j['categories']))
          if (_s(e['key']) != null) _s(e['key'])!: _s(e['label']) ?? _s(e['key'])!,
      },
      versions: [for (final e in _ml(j['versions'])) VersionEntry.fromJson(e)],
      reviews: [for (final e in _ml(j['reviews'])) ReviewEntry.fromJson(e)],
      reworks: [for (final e in _ml(j['reworks'])) ReworkEntry.fromJson(e)],
    );
  }
}
