// Saved Camera AR scene layouts (local only).
//
// A layout stores *preview* configuration: which signage items were placed
// in the AR scene and their preview transforms. It never changes the recce
// business data (sizes, quantity, photos, approvals). World anchors are not
// persisted, so a reopened layout must be re-anchored on site.

double _num(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : (double.tryParse('$v') ?? fallback);

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

DateTime _date(Object? v) =>
    (v is String ? DateTime.tryParse(v) : null) ??
    DateTime.fromMillisecondsSinceEpoch(0);

/// One model placed in a saved AR layout.
class ArLayoutObject {
  ArLayoutObject({
    required this.placementId,
    required this.signageItemId,
    required this.groupId,
    required this.mediaCode,
    required this.installationCode,
    required this.savedAt,
    this.previewDuplicate = false,
    this.duplicateOf,
    Map<String, Object?>? modelConfig,
    Map<String, double>? transform,
    this.visible = true,
    this.locked = false,
    this.surface,
    this.lastSessionPose,
  }) : modelConfig = modelConfig ?? {},
       transform = transform ?? {};

  /// AR Placement ID (unique per inserted instance, never a business id).
  final String placementId;

  /// Signage Item ID ([SignageUnit.id]) this placement shows.
  final String signageItemId;

  /// Media group ([Board.id]) of the signage item.
  final String groupId;
  final String mediaCode;
  final String installationCode;

  /// Extra preview copy; never counts as a physical unit.
  final bool previewDuplicate;

  /// Placement this duplicate was made from.
  final String? duplicateOf;

  /// Model configuration at save time (widthFt, heightFt, unit, label,
  /// doubleSided). Informational: the model is always rebuilt from the
  /// current signage item.
  final Map<String, Object?> modelConfig;

  /// Preview transform relative to the anchor: x, y, z (metres), yaw, roll
  /// (radians), scale (multiplier).
  final Map<String, double> transform;
  final bool visible;
  final bool locked;

  /// Surface used when saved ("vertical", "horizontal", "manual").
  final String? surface;

  /// World pose in the AR session that saved it (tx, ty, tz, qx, qy, qz,
  /// qw). Only meaningful inside that session – never used to restore.
  final List<double>? lastSessionPose;
  final DateTime savedAt;

  double get scaleMultiplier => transform['scale'] ?? 1;

  /// Rotation shown to the user, in degrees.
  double get rotationDeg =>
      ((transform['yaw'] ?? 0) + (transform['roll'] ?? 0)) *
      180 /
      3.141592653589793;

  Map<String, dynamic> toJson() => {
    'placementId': placementId,
    'signageItemId': signageItemId,
    'groupId': groupId,
    'mediaCode': mediaCode,
    'installationCode': installationCode,
    'previewDuplicate': previewDuplicate,
    if (duplicateOf != null) 'duplicateOf': duplicateOf,
    'modelConfig': modelConfig,
    'transform': transform,
    'rotation': rotationDeg,
    'scaleMultiplier': scaleMultiplier,
    'visible': visible,
    'locked': locked,
    if (surface != null) 'surface': surface,
    if (lastSessionPose != null) 'lastSessionPose': lastSessionPose,
    'savedAt': savedAt.toIso8601String(),
  };

  factory ArLayoutObject.fromJson(Map<String, dynamic> j) {
    final rawTransform = j['transform'];
    final transform = <String, double>{
      if (rawTransform is Map)
        for (final e in rawTransform.entries)
          if (e.value is num) '${e.key}': (e.value as num).toDouble(),
    };
    // Older / partial records: fall back to the flat fields.
    transform.putIfAbsent('scale', () => _num(j['scaleMultiplier'], 1));
    final pose = j['lastSessionPose'];
    return ArLayoutObject(
      placementId: _str(j['placementId']),
      signageItemId: _str(j['signageItemId']),
      groupId: _str(j['groupId']),
      mediaCode: _str(j['mediaCode']),
      installationCode: _str(j['installationCode']),
      previewDuplicate: j['previewDuplicate'] == true,
      duplicateOf: j['duplicateOf'] is String
          ? j['duplicateOf'] as String
          : null,
      modelConfig: j['modelConfig'] is Map
          ? Map<String, Object?>.from(j['modelConfig'] as Map)
          : {},
      transform: transform,
      visible: j['visible'] != false,
      locked: j['locked'] == true,
      surface: j['surface'] is String ? j['surface'] as String : null,
      lastSessionPose: pose is List && pose.length == 7
          ? pose.map((e) => _num(e)).toList()
          : null,
      savedAt: _date(j['savedAt']),
    );
  }
}

/// A saved AR scene for one shop (several layouts per shop are allowed).
class ArLayout {
  ArLayout({
    required this.id,
    required this.name,
    required this.projectId,
    required this.taskId,
    required this.shopId,
    required this.createdAt,
    required this.updatedAt,
    List<ArLayoutObject>? objects,
  }) : objects = objects ?? [];

  /// AR Layout ID.
  final String id;
  String name;
  final String projectId;
  final String taskId;
  final String shopId;
  final DateTime createdAt;
  DateTime updatedAt;
  List<ArLayoutObject> objects;

  /// Signage Item IDs used by this layout.
  Set<String> get signageItemIds => objects.map((o) => o.signageItemId).toSet();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'projectId': projectId,
    'taskId': taskId,
    'shopId': shopId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'objects': objects.map((o) => o.toJson()).toList(),
  };

  factory ArLayout.fromJson(Map<String, dynamic> j) => ArLayout(
    id: _str(j['id']),
    name: _str(j['name'], 'AR Layout'),
    projectId: _str(j['projectId']),
    taskId: _str(j['taskId']),
    shopId: _str(j['shopId']),
    createdAt: _date(j['createdAt']),
    updatedAt: _date(j['updatedAt'] ?? j['createdAt']),
    objects: j['objects'] is List
        ? (j['objects'] as List)
              .whereType<Map>()
              .map((e) => ArLayoutObject.fromJson(Map<String, dynamic>.from(e)))
              .where(
                (o) => o.placementId.isNotEmpty && o.signageItemId.isNotEmpty,
              )
              .toList()
        : [],
  );
}
