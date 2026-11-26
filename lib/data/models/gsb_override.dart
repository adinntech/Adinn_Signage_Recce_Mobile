/// Vendor-proposed change to an approved GSB fabrication specification
/// (board depth, frame profile or pipe wall thickness).
///
/// An override is NEVER an approval: it is stored with the vendor's reason
/// and stays "Requires Engineering Review" until the existing review process
/// handles it. Overrides are additive (`Board.gsbOverrides`), reversible and
/// never replace the original default.
enum GsbOverrideField { depth, profileWidth, profileHeight, wallThickness }

extension GsbOverrideFieldX on GsbOverrideField {
  String get label => switch (this) {
    GsbOverrideField.depth => 'Board depth',
    GsbOverrideField.profileWidth => 'Frame profile width',
    GsbOverrideField.profileHeight => 'Frame profile height',
    GsbOverrideField.wallThickness => 'Pipe wall thickness',
  };
}

enum GsbOverrideStatus { requiresReview, reverted }

extension GsbOverrideStatusX on GsbOverrideStatus {
  String get label => switch (this) {
    GsbOverrideStatus.requiresReview => 'Requires Engineering Review',
    GsbOverrideStatus.reverted => 'Reverted',
  };
}

class GsbSpecOverride {
  GsbSpecOverride({
    required this.id,
    required this.unitId,
    required this.field,
    required this.originalIn,
    required this.proposedIn,
    required this.reason,
    required this.userId,
    required this.projectId,
    required this.taskId,
    required this.shopId,
    required this.boardId,
    required this.createdAt,
    required this.ruleVersion,
    this.status = GsbOverrideStatus.requiresReview,
    this.revertedAt,
    this.revertedBy,
  });

  final String id;

  /// Signage item ([SignageUnit.id]) the override belongs to.
  final String unitId;
  final GsbOverrideField field;

  /// Specification before the override (null = was unspecified).
  final double? originalIn;
  final double proposedIn;
  final String reason;
  final String userId;
  final String projectId;
  final String taskId;
  final String shopId;
  final String boardId;
  final DateTime createdAt;
  final String ruleVersion;
  GsbOverrideStatus status;
  DateTime? revertedAt;
  String? revertedBy;

  bool get isActive => status == GsbOverrideStatus.requiresReview;

  Map<String, dynamic> toJson() => {
    'id': id,
    'unitId': unitId,
    'field': field.name,
    'originalIn': originalIn,
    'proposedIn': proposedIn,
    'reason': reason,
    'userId': userId,
    'projectId': projectId,
    'taskId': taskId,
    'shopId': shopId,
    'boardId': boardId,
    'createdAt': createdAt.toIso8601String(),
    'ruleVersion': ruleVersion,
    'status': status.name,
    if (revertedAt != null) 'revertedAt': revertedAt!.toIso8601String(),
    if (revertedBy != null) 'revertedBy': revertedBy,
  };

  static GsbSpecOverride fromJson(Map<String, dynamic> j) {
    GsbOverrideField? field;
    for (final f in GsbOverrideField.values) {
      if (f.name == j['field']) field = f;
    }
    final proposed = j['proposedIn'];
    if (field == null || proposed is! num) {
      throw const FormatException('Invalid GSB override');
    }
    var status = GsbOverrideStatus.requiresReview;
    for (final s in GsbOverrideStatus.values) {
      if (s.name == j['status']) status = s;
    }
    String s(Object? v) => v is String ? v : '';
    DateTime dt(Object? v) =>
        (v is String ? DateTime.tryParse(v) : null) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final original = j['originalIn'];
    return GsbSpecOverride(
      id: s(j['id']),
      unitId: s(j['unitId']),
      field: field,
      originalIn: original is num ? original.toDouble() : null,
      proposedIn: proposed.toDouble(),
      reason: s(j['reason']),
      userId: s(j['userId']),
      projectId: s(j['projectId']),
      taskId: s(j['taskId']),
      shopId: s(j['shopId']),
      boardId: s(j['boardId']),
      createdAt: dt(j['createdAt']),
      ruleVersion: s(j['ruleVersion']),
      status: status,
      revertedAt: j['revertedAt'] is String
          ? DateTime.tryParse(j['revertedAt'] as String)
          : null,
      revertedBy: j['revertedBy'] is String ? j['revertedBy'] as String : null,
    );
  }
}
