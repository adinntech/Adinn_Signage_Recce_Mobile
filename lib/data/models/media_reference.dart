// Media reference photo library (local only).
//
// A media reference is a photo (app-local copy) or an external link that
// shows what a catalog media type really looks like, so the illustrative 3D
// model can be checked against it. A reference only counts as
// "technically reviewed" after a reviewer ticked all technical checks and
// approved it – nothing is ever seeded or parsed as approved without the
// approver's name and time.
//
// Replacing a reference never deletes the old record: it is kept and marked
// superseded ([MediaReference.replacedById]).

import 'enums.dart';
import 'site_survey.dart' show surveyList;

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

String? _strN(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

DateTime _date(Object? v) =>
    (v is String ? DateTime.tryParse(v) : null) ??
    DateTime.fromMillisecondsSinceEpoch(0);

DateTime? _dateN(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Where a reference image comes from.
enum ReferenceSourceCategory { factory, internalSample, external }

extension ReferenceSourceCategoryX on ReferenceSourceCategory {
  String get label => switch (this) {
    ReferenceSourceCategory.factory => 'Factory photo',
    ReferenceSourceCategory.internalSample => 'Internal sample',
    ReferenceSourceCategory.external => 'External (web link)',
  };
}

/// Whether Adinn may use the reference image.
enum ReferenceUsageRights {
  unknown,
  internalOwned,
  licensed,
  permissionGranted,
  notAllowed,
}

extension ReferenceUsageRightsX on ReferenceUsageRights {
  String get label => switch (this) {
    ReferenceUsageRights.unknown => 'Unknown',
    ReferenceUsageRights.internalOwned => 'Internally owned',
    ReferenceUsageRights.licensed => 'Licensed',
    ReferenceUsageRights.permissionGranted => 'Permission granted',
    ReferenceUsageRights.notAllowed => 'Not allowed',
  };

  /// Rights are recorded and allow use (required for approval).
  bool get cleared =>
      this != ReferenceUsageRights.unknown &&
      this != ReferenceUsageRights.notAllowed;
}

/// Review lifecycle of one reference.
enum ReferenceStatus {
  pendingReference,
  collected,
  awaitingTechnicalReview,
  approved,
  rejected,
}

extension ReferenceStatusX on ReferenceStatus {
  String get label => switch (this) {
    ReferenceStatus.pendingReference => 'Pending Reference',
    ReferenceStatus.collected => 'Collected',
    ReferenceStatus.awaitingTechnicalReview => 'Awaiting Technical Review',
    ReferenceStatus.approved => 'Approved',
    ReferenceStatus.rejected => 'Rejected',
  };
}

/// The seven items a reviewer verifies before approving a reference.
enum TechnicalCheck {
  mediaType,
  material,
  thicknessAppearance,
  sidedConfiguration,
  mountingStructure,
  frameAppearance,
  supportArrangement,
}

extension TechnicalCheckX on TechnicalCheck {
  String get label => switch (this) {
    TechnicalCheck.mediaType => 'Correct media type',
    TechnicalCheck.material => 'Material',
    TechnicalCheck.thicknessAppearance => 'Thickness appearance',
    TechnicalCheck.sidedConfiguration => 'Single / double-sided configuration',
    TechnicalCheck.mountingStructure => 'Mounting structure',
    TechnicalCheck.frameAppearance => 'Frame appearance',
    TechnicalCheck.supportArrangement => 'Support arrangement',
  };
}

class MediaReference {
  MediaReference({
    required this.id,
    required this.mediaCode,
    required this.sourceCategory,
    required this.createdAt,
    DateTime? updatedAt,
    this.installationCode,
    this.sourceUrl,
    this.localPath,
    this.owner = '',
    this.label = '',
    this.usageRights = ReferenceUsageRights.unknown,
    this.status = ReferenceStatus.pendingReference,
    Map<TechnicalCheck, bool?>? technicalChecks,
    this.approvedByName,
    this.approvedByRole,
    this.approvedAt,
    this.rejectionReason,
    this.rejectedByName,
    this.rejectedAt,
    this.technicalNotes = '',
    this.createdByName = '',
    this.replacedById,
    this.supersedes,
  }) : technicalChecks = technicalChecks ?? {},
       updatedAt = updatedAt ?? createdAt;

  final String id;

  /// Catalog media code ([SignageCatalog.catalogCodes]).
  final String mediaCode;

  /// Installation the reference shows (optional).
  String? installationCode;
  ReferenceSourceCategory sourceCategory;

  /// Web page / image link (required for external references). The image
  /// itself is never downloaded or bundled.
  String? sourceUrl;

  /// App-local copy of a picked image.
  String? localPath;

  /// Owner / photographer.
  String owner;

  /// Short caption, e.g. "Factory sample – front view".
  String label;
  ReferenceUsageRights usageRights;
  ReferenceStatus status;

  /// Reviewer's verification per item (null = not checked yet).
  Map<TechnicalCheck, bool?> technicalChecks;

  /// Set only by an actual reviewer approval.
  String? approvedByName;
  UserRole? approvedByRole;
  DateTime? approvedAt;

  String? rejectionReason;
  String? rejectedByName;
  DateTime? rejectedAt;
  String technicalNotes;
  String createdByName;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Newer reference that replaced this one (record kept, superseded).
  String? replacedById;

  /// Older reference this one replaces.
  String? supersedes;

  bool get isSuperseded => replacedById != null;

  bool get hasImage => localPath != null && localPath!.isNotEmpty;

  bool get hasSource => hasImage || (sourceUrl?.trim().isNotEmpty ?? false);

  bool get isApproved =>
      status == ReferenceStatus.approved &&
      approvedAt != null &&
      (approvedByName?.isNotEmpty ?? false);

  /// Approved and still current (not replaced).
  bool get isActiveApproval => isApproved && !isSuperseded;

  bool get allChecksPassed =>
      TechnicalCheck.values.every((c) => technicalChecks[c] == true);

  int get checksPassed =>
      TechnicalCheck.values.where((c) => technicalChecks[c] == true).length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'mediaCode': mediaCode,
    if (installationCode != null) 'installationCode': installationCode,
    'sourceCategory': sourceCategory.name,
    if (sourceUrl != null && sourceUrl!.isNotEmpty) 'sourceUrl': sourceUrl,
    if (localPath != null && localPath!.isNotEmpty) 'localPath': localPath,
    if (owner.isNotEmpty) 'owner': owner,
    if (label.isNotEmpty) 'label': label,
    'usageRights': usageRights.name,
    'status': status.name,
    if (technicalChecks.values.any((v) => v != null))
      'technicalChecks': {
        for (final e in technicalChecks.entries)
          if (e.value != null) e.key.name: e.value,
      },
    if (approvedByName != null) 'approvedByName': approvedByName,
    if (approvedByRole != null) 'approvedByRole': approvedByRole!.name,
    if (approvedAt != null) 'approvedAt': approvedAt!.toIso8601String(),
    if (rejectionReason != null) 'rejectionReason': rejectionReason,
    if (rejectedByName != null) 'rejectedByName': rejectedByName,
    if (rejectedAt != null) 'rejectedAt': rejectedAt!.toIso8601String(),
    if (technicalNotes.isNotEmpty) 'technicalNotes': technicalNotes,
    if (createdByName.isNotEmpty) 'createdByName': createdByName,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (replacedById != null) 'replacedById': replacedById,
    if (supersedes != null) 'supersedes': supersedes,
  };

  /// Tolerant: unknown enum names fall back safely; an "approved" status
  /// without approver name and time is read as awaiting review (an approval
  /// is never fabricated from incomplete data). Records without id or
  /// media code throw and are skipped by [surveyList].
  factory MediaReference.fromJson(Map<String, dynamic> j) {
    final id = _str(j['id']);
    final mediaCode = _str(j['mediaCode']);
    if (id.isEmpty || mediaCode.isEmpty) {
      throw const FormatException('Media reference without id / media code');
    }
    final checks = <TechnicalCheck, bool?>{};
    final rawChecks = j['technicalChecks'];
    if (rawChecks is Map) {
      for (final c in TechnicalCheck.values) {
        final v = rawChecks[c.name];
        if (v is bool) checks[c] = v;
      }
    }
    final approvedByName = _strN(j['approvedByName']);
    final approvedAt = _dateN(j['approvedAt']);
    var status = enumByName(
      ReferenceStatus.values,
      j['status'],
      ReferenceStatus.pendingReference,
    );
    if (status == ReferenceStatus.approved &&
        (approvedByName == null || approvedAt == null)) {
      status = ReferenceStatus.awaitingTechnicalReview;
    }
    final createdAt = _date(j['createdAt']);
    return MediaReference(
      id: id,
      mediaCode: mediaCode,
      installationCode: _strN(j['installationCode']),
      sourceCategory: enumByName(
        ReferenceSourceCategory.values,
        j['sourceCategory'],
        ReferenceSourceCategory.internalSample,
      ),
      sourceUrl: _strN(j['sourceUrl']),
      localPath: _strN(j['localPath']),
      owner: _str(j['owner']),
      label: _str(j['label']),
      usageRights: enumByName(
        ReferenceUsageRights.values,
        j['usageRights'],
        ReferenceUsageRights.unknown,
      ),
      status: status,
      technicalChecks: checks,
      approvedByName: status == ReferenceStatus.approved
          ? approvedByName
          : null,
      approvedByRole:
          status == ReferenceStatus.approved && j['approvedByRole'] is String
          ? enumByName(
              UserRole.values,
              j['approvedByRole'],
              UserRole.businessTeam,
            )
          : null,
      approvedAt: status == ReferenceStatus.approved ? approvedAt : null,
      rejectionReason: _strN(j['rejectionReason']),
      rejectedByName: _strN(j['rejectedByName']),
      rejectedAt: _dateN(j['rejectedAt']),
      technicalNotes: _str(j['technicalNotes']),
      createdByName: _str(j['createdByName']),
      createdAt: createdAt,
      updatedAt: _dateN(j['updatedAt']) ?? createdAt,
      replacedById: _strN(j['replacedById']),
      supersedes: _strN(j['supersedes']),
    );
  }

  static List<MediaReference> listFromJson(Object? v) =>
      surveyList(v, MediaReference.fromJson);
}

/// References of one media code, newest first.
List<MediaReference> referencesOf(
  Iterable<MediaReference> refs,
  String mediaCode, {
  bool includeSuperseded = true,
}) =>
    refs
        .where(
          (r) =>
              r.mediaCode == mediaCode &&
              (includeSuperseded || !r.isSuperseded),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

/// Library status of a media type, from its current (not superseded)
/// references. No reference at all → [ReferenceStatus.pendingReference].
ReferenceStatus libraryStatusFor(
  Iterable<MediaReference> refs,
  String mediaCode,
) {
  final current = referencesOf(refs, mediaCode, includeSuperseded: false);
  if (current.isEmpty) return ReferenceStatus.pendingReference;
  if (current.any((r) => r.isActiveApproval)) return ReferenceStatus.approved;
  for (final s in const [
    ReferenceStatus.awaitingTechnicalReview,
    ReferenceStatus.collected,
    ReferenceStatus.pendingReference,
  ]) {
    if (current.any((r) => r.status == s)) return s;
  }
  return ReferenceStatus.rejected;
}

/// Why [r] cannot be approved right now (null = it can).
String? referenceApprovalBlocker(MediaReference r) {
  if (r.isSuperseded) return 'This reference was replaced by a newer one.';
  if (r.status != ReferenceStatus.awaitingTechnicalReview) {
    return 'Only references awaiting technical review can be approved.';
  }
  if (!r.hasSource) return 'Add a photo or source link first.';
  if (r.sourceCategory == ReferenceSourceCategory.external &&
      (r.sourceUrl?.trim().isEmpty ?? true)) {
    return 'External references need a source URL.';
  }
  if (!r.usageRights.cleared) {
    return r.usageRights == ReferenceUsageRights.notAllowed
        ? 'Usage rights: not allowed – this image cannot be approved.'
        : 'Record the usage rights before approving.';
  }
  if (!r.allChecksPassed) {
    return 'Tick all ${TechnicalCheck.values.length} technical checks '
        '(${r.checksPassed}/${TechnicalCheck.values.length} done).';
  }
  return null;
}

/// Accepts only absolute http(s) links with a host.
bool isValidReferenceUrl(String? url) {
  final u = Uri.tryParse(url?.trim() ?? '');
  return u != null &&
      (u.scheme == 'http' || u.scheme == 'https') &&
      u.host.isNotEmpty;
}
