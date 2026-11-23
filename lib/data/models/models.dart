import 'dart:math' as math;

import 'ar_layout.dart';
import 'enums.dart';
import 'gsb_override.dart';
import 'media_reference.dart';
import 'panorama.dart';
import 'site_survey.dart';

export 'ar_layout.dart';
export 'enums.dart';
export 'gsb_override.dart';
export 'media_reference.dart';
export 'panorama.dart';
export 'site_survey.dart';

double _d(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : (double.tryParse('$v') ?? fallback);

double? _dn(Object? v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

DateTime _dt(Object? v) =>
    (v is String ? DateTime.tryParse(v) : null) ??
    DateTime.fromMillisecondsSinceEpoch(0);

String _s(Object? v, [String fallback = '']) => v is String ? v : fallback;

List<String> _strings(Object? v) =>
    v is List ? v.whereType<String>().toList() : <String>[];

/// Malformed entries are skipped (see [ModelParseLog]) so one bad record never
/// makes the whole local data unreadable.
List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) f) =>
    surveyList(v, f);

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

class AppUser {
  AppUser({
    required this.id,
    required this.code,
    required this.pin,
    required this.name,
    required this.role,
    required this.mobile,
    this.email = '',
    this.company = '',
    this.region = '',
    this.designation = '',
  });

  final String id;

  /// Vendor / employee ID (shown on the profile; not used to log in).
  String code;

  /// 4-digit login PIN. Unique per user because login asks for PIN only.
  String pin;
  String name;
  UserRole role;
  String mobile;
  String email;
  String company;
  String region;
  String designation;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'pin': pin,
    'name': name,
    'role': role.name,
    'mobile': mobile,
    'email': email,
    'company': company,
    'region': region,
    'designation': designation,
  };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
    id: _s(j['id']),
    code: _s(j['code']),
    // Schema 1 stored the credential under "password".
    pin: _s(j['pin'] ?? j['password']),
    name: _s(j['name']),
    role: enumByName(UserRole.values, j['role'], UserRole.vendor),
    mobile: _s(j['mobile']),
    email: _s(j['email']),
    company: _s(j['company']),
    region: _s(j['region']),
    designation: _s(j['designation']),
  );
}

// ---------------------------------------------------------------------------
// Projects & tasks
// ---------------------------------------------------------------------------

class Project {
  Project({
    required this.id,
    required this.code,
    required this.name,
    required this.client,
    required this.description,
    required this.region,
    required this.startDate,
    required this.endDate,
    required this.coordinatorName,
    required this.coordinatorPhone,
  });

  final String id;
  String code;
  String name;
  String client;
  String description;
  String region;
  DateTime startDate;
  DateTime endDate;
  String coordinatorName;
  String coordinatorPhone;

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'client': client,
    'description': description,
    'region': region,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'coordinatorName': coordinatorName,
    'coordinatorPhone': coordinatorPhone,
  };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
    id: _s(j['id']),
    code: _s(j['code']),
    name: _s(j['name']),
    client: _s(j['client']),
    description: _s(j['description']),
    region: _s(j['region']),
    startDate: _dt(j['startDate']),
    endDate: _dt(j['endDate']),
    coordinatorName: _s(j['coordinatorName']),
    coordinatorPhone: _s(j['coordinatorPhone']),
  );
}

class RecceTask {
  RecceTask({
    required this.id,
    required this.projectId,
    required this.title,
    required this.location,
    required this.city,
    required this.dueDate,
    required this.assignedVendorId,
    this.priority = 'Medium',
    this.instructions = '',
  });

  final String id;
  final String projectId;
  String title;
  String location;
  String city;
  DateTime dueDate;
  String assignedVendorId;
  String priority;
  String instructions;

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'title': title,
    'location': location,
    'city': city,
    'dueDate': dueDate.toIso8601String(),
    'assignedVendorId': assignedVendorId,
    'priority': priority,
    'instructions': instructions,
  };

  factory RecceTask.fromJson(Map<String, dynamic> j) => RecceTask(
    id: _s(j['id']),
    projectId: _s(j['projectId']),
    title: _s(j['title']),
    location: _s(j['location']),
    city: _s(j['city']),
    dueDate: _dt(j['dueDate']),
    assignedVendorId: _s(j['assignedVendorId']),
    priority: _s(j['priority'], 'Medium'),
    instructions: _s(j['instructions']),
  );
}

// ---------------------------------------------------------------------------
// Media: photos, annotations, voice notes
// ---------------------------------------------------------------------------

/// A drawing on a site photo. All coordinates are in the photo's own pixel
/// space (0..width, 0..height) so they stay valid at any display size.
///
/// * box types (rectangle, text, shapes, markers): [x],[y] is the centre,
///   [w]x[h] the size, [rotation] in radians around the centre.
/// * two-point types (arrow, line, dimension): from ([x],[y]) to ([x2],[y2]).
/// * freehand: [points] as a flat list x0, y0, x1, y1, …
class Annotation {
  Annotation({
    required this.id,
    required this.type,
    this.x = 0,
    this.y = 0,
    this.w = 0,
    this.h = 0,
    this.x2 = 0,
    this.y2 = 0,
    this.rotation = 0,
    this.label = '',
    this.measureW,
    this.measureH,
    this.unit = MeasureUnit.ft,
    this.color = 0xFFD71920,
    this.thickness = 1,
    this.itemId,
    List<double>? points,
  }) : points = points ?? [];

  final String id;
  AnnotationType type;
  double x;
  double y;
  double w;
  double h;
  double x2;
  double y2;
  double rotation;
  String label;
  double? measureW;
  double? measureH;
  MeasureUnit unit;
  int color;

  /// Line thickness multiplier (1 = default stroke).
  double thickness;

  /// Signage unit ([SignageUnit.id]) this marking belongs to, if any.
  String? itemId;

  /// Freehand path in photo pixels: x0, y0, x1, y1, …
  List<double> points;

  bool get hasMeasurement => (measureW ?? 0) > 0 && (measureH ?? 0) > 0;

  /// Dimension lines / measurement labels carry a single measured value.
  bool get hasValue => (measureW ?? 0) > 0;

  Annotation copy() => Annotation.fromJson(toJson());

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    'x2': x2,
    'y2': y2,
    'rotation': rotation,
    'label': label,
    'measureW': measureW,
    'measureH': measureH,
    'unit': unit.name,
    'color': color,
    if (thickness != 1) 'thickness': thickness,
    if (itemId != null) 'itemId': itemId,
    if (points.isNotEmpty) 'points': points,
  };

  factory Annotation.fromJson(Map<String, dynamic> j) => Annotation(
    id: _s(j['id']),
    type: enumByName(
      AnnotationType.values,
      j['type'],
      AnnotationType.rectangle,
    ),
    x: _d(j['x']),
    y: _d(j['y']),
    w: _d(j['w']),
    h: _d(j['h']),
    x2: _d(j['x2']),
    y2: _d(j['y2']),
    rotation: _d(j['rotation']),
    label: _s(j['label']),
    measureW: _dn(j['measureW']),
    measureH: _dn(j['measureH']),
    unit: enumByName(MeasureUnit.values, j['unit'], MeasureUnit.ft),
    color: (j['color'] as num?)?.toInt() ?? 0xFFD71920,
    thickness: _d(j['thickness'], 1).clamp(0.25, 8).toDouble(),
    itemId: j['itemId'] is String ? j['itemId'] as String : null,
    points: j['points'] is List
        ? (j['points'] as List)
              .whereType<num>()
              .map((e) => e.toDouble())
              .toList()
        : null,
  );
}

/// A GPS reading: WGS84 coordinates, horizontal accuracy and time taken.
class GeoFix {
  const GeoFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy radius in metres (68% confidence).
  final double accuracyM;
  final DateTime capturedAt;

  /// "10.86270, 78.68970"
  String get coordinates =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  /// Great-circle distance in metres (haversine).
  double distanceTo(GeoFix other) =>
      distanceMetres(latitude, longitude, other.latitude, other.longitude);

  static double distanceMetres(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracyM': accuracyM,
    'capturedAt': capturedAt.toIso8601String(),
  };

  static GeoFix? fromJson(Object? j) {
    if (j is! Map) return null;
    final lat = _dn(j['latitude']);
    final lng = _dn(j['longitude']);
    if (lat == null || lng == null) return null;
    return GeoFix(
      latitude: lat,
      longitude: lng,
      accuracyM: _d(j['accuracyM']),
      capturedAt: _dt(j['capturedAt']),
    );
  }
}

class SitePhoto {
  SitePhoto({
    required this.id,
    required this.path,
    required this.label,
    required this.capturedAt,
    required this.width,
    required this.height,
    List<Annotation>? annotations,
    this.geo,
    List<String>? unitIds,
    SiteMarkup? markup,
    this.gsbView,
  }) : annotations = annotations ?? [],
       unitIds = unitIds ?? [],
       markup = markup ?? SiteMarkup();

  static const demoPrefix = 'demo://';

  final String id;
  String path;
  String label;
  DateTime capturedAt;
  int width;
  int height;
  List<Annotation> annotations;

  /// Where the photo was taken (null if GPS was unavailable).
  GeoFix? geo;

  /// Signage units this photo shows. One photo may cover several units of
  /// the group (shared reference, the image file is never duplicated).
  /// Empty = applies to the whole media group.
  List<String> unitIds;

  /// Advanced site markings (perspective placements, placement markers,
  /// electrical points, cable routes, obstructions). Kept separate from
  /// [annotations] so the classic editor data is never rewritten.
  SiteMarkup markup;

  /// GSB only: which side of the proposed board this photo looks at
  /// (`front`, `left`, `right`, `back`, `custom`). Null = not chosen
  /// (front). Presentation metadata; the photo file is never touched.
  String? gsbView;

  /// Built-in sample photo (rendered in Dart) used for demos/emulators.
  bool get isDemo => path.startsWith(demoPrefix);

  int get demoSeed => int.tryParse(path.substring(demoPrefix.length)) ?? 0;

  double get aspectRatio => height == 0 ? 4 / 3 : width / height;

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'label': label,
    'capturedAt': capturedAt.toIso8601String(),
    'width': width,
    'height': height,
    'annotations': annotations.map((a) => a.toJson()).toList(),
    'geo': geo?.toJson(),
    if (unitIds.isNotEmpty) 'unitIds': unitIds,
    if (!markup.isEmpty) 'markup': markup.toJson(),
    if (gsbView != null) 'gsbView': gsbView,
  };

  factory SitePhoto.fromJson(Map<String, dynamic> j) => SitePhoto(
    id: _s(j['id']),
    path: _s(j['path']),
    label: _s(j['label'], 'Site photo'),
    capturedAt: _dt(j['capturedAt']),
    width: (j['width'] as num?)?.toInt() ?? 1200,
    height: (j['height'] as num?)?.toInt() ?? 900,
    annotations: _list(j['annotations'], Annotation.fromJson),
    geo: GeoFix.fromJson(j['geo']),
    unitIds: _strings(j['unitIds']),
    markup: SiteMarkup.fromJson(j['markup']),
    gsbView: j['gsbView'] is String ? j['gsbView'] as String : null,
  );
}

class VoiceNote {
  VoiceNote({
    required this.id,
    required this.path,
    required this.durationMs,
    required this.createdAt,
    this.label = 'Voice note',
  });

  final String id;
  String path;
  int durationMs;
  DateTime createdAt;
  String label;

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'durationMs': durationMs,
    'createdAt': createdAt.toIso8601String(),
    'label': label,
  };

  factory VoiceNote.fromJson(Map<String, dynamic> j) => VoiceNote(
    id: _s(j['id']),
    path: _s(j['path']),
    durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
    createdAt: _dt(j['createdAt']),
    label: _s(j['label'], 'Voice note'),
  );
}

// ---------------------------------------------------------------------------
// Boards & shops
// ---------------------------------------------------------------------------

/// One physical signage unit inside a media group (e.g. "GSB – Unit 02").
///
/// Width/height are only used when the group captures different sizes per
/// unit; with "same size" the group's own width/height apply to every unit.
/// Placement, installation details and notes are always per unit.
class SignageUnit {
  SignageUnit({
    required this.id,
    this.width,
    this.height,
    this.placement = '',
    this.installationCode,
    this.installationDetails = '',
    this.notes = '',
    MeasurementDetails? measurements,
    Map<String, ChecklistResponse>? checklist,
    ElectricalSurvey? electrical,
  }) : measurements = measurements ?? MeasurementDetails(),
       checklist = checklist ?? {},
       electrical = electrical ?? ElectricalSurvey();

  final String id;
  double? width;
  double? height;

  /// Where this unit goes, e.g. "Above entrance", "Footpath left of gate".
  String placement;

  /// Installation override. Null = same as the media group.
  String? installationCode;

  /// Installation measurements / fixing details for this unit.
  String installationDetails;
  String notes;

  /// Advanced measurements (canonical millimetres).
  MeasurementDetails measurements;

  /// Media-specific site checklist responses by question id.
  Map<String, ChecklistResponse> checklist;

  /// Electrical availability survey.
  ElectricalSurvey electrical;

  bool get hasOwnSize => (width ?? 0) > 0 && (height ?? 0) > 0;

  SignageUnit copyWith({required String id}) =>
      SignageUnit.fromJson({...toJson(), 'id': id});

  Map<String, dynamic> toJson() => {
    'id': id,
    'width': width,
    'height': height,
    'placement': placement,
    'installationCode': installationCode,
    'installationDetails': installationDetails,
    'notes': notes,
    if (!measurements.isEmpty) 'measurements': measurements.toJson(),
    if (checklist.isNotEmpty)
      'checklist': ChecklistResponse.mapToJson(checklist),
    if (!electrical.isEmpty) 'electrical': electrical.toJson(),
  };

  factory SignageUnit.fromJson(Map<String, dynamic> j) => SignageUnit(
    id: _s(j['id']),
    width: _dn(j['width']),
    height: _dn(j['height']),
    placement: _s(j['placement']),
    installationCode: j['installationCode'] is String
        ? j['installationCode'] as String
        : null,
    installationDetails: _s(j['installationDetails']),
    notes: _s(j['notes']),
    measurements: MeasurementDetails.fromJson(j['measurements']),
    checklist: ChecklistResponse.mapFromJson(j['checklist']),
    electrical: ElectricalSurvey.fromJson(j['electrical']),
  );
}

/// Placement of one signage model over a photo (Live Preview). Values are
/// photo-relative so they survive zoom, resize and rotation: [cx]/[cy] are
/// the model centre as a fraction of the photo width/height and [scale] is
/// the model box width as a fraction of the photo width.
class PreviewOverlay {
  PreviewOverlay({
    required this.unitId,
    this.cx = 0.5,
    this.cy = 0.45,
    this.scale = 0.45,
    this.rotation = 0,
    this.yaw = 0,
    this.pitch = 0.05,
    this.opacity = 1,
  });

  final String unitId;
  double cx;
  double cy;
  double scale;

  /// In-plane rotation of the model on the photo (radians).
  double rotation;

  /// Turn of the 3D model (radians, 0 = facing the camera).
  double yaw;

  /// Perspective tilt of the 3D model (radians).
  double pitch;
  double opacity;

  PreviewOverlay copy() => PreviewOverlay.fromJson(toJson());

  Map<String, dynamic> toJson() => {
    'unitId': unitId,
    'cx': cx,
    'cy': cy,
    'scale': scale,
    'rotation': rotation,
    'yaw': yaw,
    'pitch': pitch,
    'opacity': opacity,
  };

  factory PreviewOverlay.fromJson(Map<String, dynamic> j) => PreviewOverlay(
    unitId: _s(j['unitId']),
    cx: _d(j['cx'], 0.5),
    cy: _d(j['cy'], 0.45),
    scale: _d(j['scale'], 0.45),
    rotation: _d(j['rotation']),
    yaw: _d(j['yaw']),
    pitch: _d(j['pitch'], 0.05),
    opacity: _d(j['opacity'], 1).clamp(0.05, 1).toDouble(),
  );
}

/// A generated image saved against a signage item: a Live Preview over a
/// site photo, an AR screenshot or an exported annotated photo. The original
/// photo is only referenced ([photoId]), never overwritten.
class PreviewCapture {
  PreviewCapture({
    required this.id,
    required this.kind,
    required this.projectId,
    required this.taskId,
    required this.shopId,
    required this.groupId,
    required this.unitId,
    required this.path,
    required this.createdAt,
    this.photoId,
    List<PreviewOverlay>? overlays,
    Map<String, double>? arTransform,
    Map<String, String>? info,
    this.layoutId,
    List<String>? visibleUnitIds,
    List<String>? placementIds,
  }) : overlays = overlays ?? [],
       arTransform = arTransform ?? {},
       info = info ?? {},
       visibleUnitIds = visibleUnitIds ?? [],
       placementIds = placementIds ?? [];

  final String id;
  final CaptureKind kind;
  final String projectId;
  final String taskId;
  final String shopId;

  /// Media group = [Board.id].
  final String groupId;

  /// Primary signage unit ([SignageUnit.id]).
  final String unitId;
  final String? photoId;
  final String path;
  final DateTime createdAt;

  /// Every model placed on the photo (Live Preview).
  final List<PreviewOverlay> overlays;

  /// AR model transform at capture time (x, y, z metres, yaw, scale).
  final Map<String, double> arTransform;

  /// Extra capture details, e.g. mediaCode, surface, arEngine, arSupport.
  final Map<String, String> info;

  /// AR Layout ID the capture was taken in (multi-object AR scene).
  final String? layoutId;

  /// Signage Item IDs visible in an AR capture (may span media groups).
  final List<String> visibleUnitIds;

  /// AR Placement IDs visible in an AR capture.
  final List<String> placementIds;

  /// All units shown in this capture.
  Set<String> get unitIds => {unitId, ...overlays.map((o) => o.unitId)};

  /// [info] keys of generated companion files (GSB day / night renders,
  /// AR original frame, comparison PDF). Additive and optional: older
  /// captures simply have none.
  static const companionKeys = [
    'originalPath',
    'dayPath',
    'nightPath',
    'comparisonPdf',
  ];

  /// Generated companion files of this capture (never the site photo).
  List<String> get companionPaths => [
    for (final k in companionKeys)
      if ((info[k] ?? '').isNotEmpty && info[k] != path) info[k]!,
  ];

  /// Comparison PDF generated with this capture, if any.
  String? get comparisonPdf {
    final p = info['comparisonPdf'];
    return p == null || p.isEmpty ? null : p;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'projectId': projectId,
    'taskId': taskId,
    'shopId': shopId,
    'groupId': groupId,
    'unitId': unitId,
    'photoId': photoId,
    'path': path,
    'createdAt': createdAt.toIso8601String(),
    'overlays': overlays.map((o) => o.toJson()).toList(),
    if (arTransform.isNotEmpty) 'arTransform': arTransform,
    if (info.isNotEmpty) 'info': info,
    if (layoutId != null) 'layoutId': layoutId,
    if (visibleUnitIds.isNotEmpty) 'visibleUnitIds': visibleUnitIds,
    if (placementIds.isNotEmpty) 'placementIds': placementIds,
  };

  factory PreviewCapture.fromJson(Map<String, dynamic> j) => PreviewCapture(
    id: _s(j['id']),
    kind: enumByName(CaptureKind.values, j['kind'], CaptureKind.live),
    projectId: _s(j['projectId']),
    taskId: _s(j['taskId']),
    shopId: _s(j['shopId']),
    groupId: _s(j['groupId']),
    unitId: _s(j['unitId']),
    photoId: j['photoId'] is String ? j['photoId'] as String : null,
    path: _s(j['path']),
    createdAt: _dt(j['createdAt']),
    overlays: _list(j['overlays'], PreviewOverlay.fromJson),
    arTransform: j['arTransform'] is Map
        ? {
            for (final e in (j['arTransform'] as Map).entries)
              if (e.value is num) '${e.key}': (e.value as num).toDouble(),
          }
        : null,
    info: j['info'] is Map
        ? {
            for (final e in (j['info'] as Map).entries)
              if (e.value != null) '${e.key}': '${e.value}',
          }
        : null,
    layoutId: j['layoutId'] is String ? j['layoutId'] as String : null,
    visibleUnitIds: _strings(j['visibleUnitIds']),
    placementIds: _strings(j['placementIds']),
  );
}

/// A media group of a shop recce: one media type with a quantity of
/// physical [units]. (Stored as "board" for backward compatibility – a
/// legacy single board is simply a group with one unit.)
class Board {
  Board({
    required this.id,
    required this.name,
    this.mediaCode,
    this.installationCode,
    Map<String, dynamic>? answers,
    this.width,
    this.height,
    this.unit = MeasureUnit.ft,
    this.quantity = 1,
    this.textNote = '',
    List<SitePhoto>? photos,
    List<VoiceNote>? voiceNotes,
    this.drawingPath,
    DateTime? updatedAt,
    this.sizeMode = SizeMode.same,
    List<SignageUnit>? units,
    List<PreviewCapture>? previews,
    int? unitSeq,
    List<ComparisonRecord>? comparisons,
    this.checklistRequired = false,
    this.doubleSided,
    this.legacyMediaCode,
    Map<String, dynamic>? answersArchive,
    List<GsbSpecOverride>? gsbOverrides,
    this.gsbLedSide,
    this.nlbSubtype,
  }) : answersArchive = answersArchive ?? {},
       gsbOverrides = gsbOverrides ?? [],
       comparisons = comparisons ?? [],
       answers = answers ?? {},
       photos = photos ?? [],
       voiceNotes = voiceNotes ?? [],
       units = units ?? [],
       previews = previews ?? [],
       unitSeq = unitSeq ?? (units?.length ?? 0),
       updatedAt = updatedAt ?? DateTime.now() {
    if (quantity < 1) quantity = 1;
    if (this.units.length > quantity) quantity = this.units.length;
    syncUnits();
  }

  final String id;
  String name;
  String? mediaCode;
  String? installationCode;
  Map<String, dynamic> answers;

  /// Shared size (used for every unit when [isSameSize]).
  double? width;
  double? height;
  MeasureUnit unit;
  int quantity;
  String textNote;
  List<SitePhoto> photos;
  List<VoiceNote> voiceNotes;
  String? drawingPath;
  DateTime updatedAt;

  /// Same size for all units, or a size per unit (quantity > 1 only).
  SizeMode sizeMode;

  /// Individual signage units (at least [quantity] after [syncUnits]).
  List<SignageUnit> units;

  /// Live previews, AR captures and exported annotated photos.
  List<PreviewCapture> previews;

  /// Highest unit number ever issued (unit ids are never reused).
  int unitSeq;

  /// Saved Before / Proposed comparison images.
  List<ComparisonRecord> comparisons;

  /// The media-specific site checklist must be complete before submission.
  /// True for media groups created since the checklist was introduced;
  /// older records (false) are never retroactively blocked.
  bool checklistRequired;

  /// Sidedness chosen for media with a single/double choice (GSB, Non-Lit).
  /// Null = not chosen (single). Fixed-sided media ignore it.
  bool? doubleSided;

  /// Original legacy media code when the group was explicitly mapped to the
  /// 13-media catalog (kept for history; never set automatically).
  String? legacyMediaCode;

  /// Site answers that stopped applying after a media / installation change.
  /// Kept so switching back restores them (no silent data loss).
  Map<String, dynamic> answersArchive;

  /// GSB fabrication spec overrides (depth / profile / wall thickness)
  /// proposed by the vendor. History is kept; reverted entries stay.
  List<GsbSpecOverride> gsbOverrides;

  /// GSB Double: side of the ONE physical LED set (`front` / `rear`).
  /// Null = front. Never changes LED quantities.
  String? gsbLedSide;

  bool get gsbLedOnRear => gsbLedSide == 'rear';

  /// NLB fabrication subtype: `NLB_SINGLE_FRAME` (rulebook NON_LIT) or
  /// `NLB_BOX_FRAME` (NON_LIT_BOX). Null = never chosen (legacy NLB keeps
  /// its previous behaviour). Additive; the media category stays `NLB`.
  String? nlbSubtype;

  bool get isNlb => mediaCode == 'NLB';
  bool get isNlbBoxFrame => isNlb && nlbSubtype == 'NLB_BOX_FRAME';
  bool get isNlbSingleFrame => isNlb && nlbSubtype == 'NLB_SINGLE_FRAME';

  /// Canonical GSB fabrication variant key derived from the stored
  /// [doubleSided] choice: `GSB_SINGLE` / `GSB_DOUBLE`, or null when the
  /// media is not GSB or the sidedness was never chosen explicitly.
  String? get gsbVariantKey => mediaCode != 'GSB' || doubleSided == null
      ? null
      : (doubleSided! ? 'GSB_DOUBLE' : 'GSB_SINGLE');

  /// Media Group ID.
  String get groupId => id;

  bool get isSameSize => quantity <= 1 || sizeMode == SizeMode.same;

  /// Units that count towards [quantity].
  List<SignageUnit> get activeUnits =>
      units.length <= quantity ? units : units.sublist(0, quantity);

  /// Adds units until there are [quantity] of them. Never removes any.
  /// Ids are deterministic ("groupId_uN") so a legacy board parsed twice
  /// gets the same unit ids (idempotent migration).
  void syncUnits() {
    while (units.length < quantity) {
      unitSeq++;
      units.add(SignageUnit(id: '${id}_u$unitSeq'));
    }
  }

  /// "Unit 01" – position of [u] inside the group.
  String unitLabel(SignageUnit u) {
    final i = units.indexWhere((e) => e.id == u.id);
    return 'Unit ${(i < 0 ? 0 : i + 1).toString().padLeft(2, '0')}';
  }

  SignageUnit? unitById(String? unitId) {
    for (final u in units) {
      if (u.id == unitId) return u;
    }
    return null;
  }

  double? widthOf(SignageUnit u) => isSameSize ? width : u.width;
  double? heightOf(SignageUnit u) => isSameSize ? height : u.height;

  bool unitHasSize(SignageUnit u) =>
      (widthOf(u) ?? 0) > 0 && (heightOf(u) ?? 0) > 0;

  /// Installation that applies to [u] (its override, else the group's).
  String? installationOf(SignageUnit u) =>
      u.installationCode ?? installationCode;

  bool get hasSize => isSameSize
      ? (width ?? 0) > 0 && (height ?? 0) > 0
      : activeUnits.every(unitHasSize);

  double get widthFt => unit.toFeet(width ?? 0);
  double get heightFt => unit.toFeet(height ?? 0);

  /// Board face area in square feet (all quantities).
  double get areaSqFt => isSameSize
      ? widthFt * heightFt * quantity
      : activeUnits.fold(
          0.0,
          (s, u) => s + unit.toFeet(u.width ?? 0) * unit.toFeet(u.height ?? 0),
        );

  int get annotationCount =>
      photos.fold(0, (sum, p) => sum + p.annotations.length);

  /// Photos showing [u]: tagged with the unit or carrying one of its
  /// markings.
  List<SitePhoto> photosOf(SignageUnit u) => photos
      .where(
        (p) =>
            p.unitIds.contains(u.id) ||
            p.annotations.any((a) => a.itemId == u.id) ||
            p.markup.unitIds.contains(u.id),
      )
      .toList();

  List<Annotation> annotationsOf(SignageUnit u) => [
    for (final p in photos) ...p.annotations.where((a) => a.itemId == u.id),
  ];

  List<PreviewCapture> previewsOf(SignageUnit u) =>
      previews.where((c) => c.unitIds.contains(u.id)).toList();

  Board copy() => Board.fromJson(toJson());

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mediaCode': mediaCode,
    'installationCode': installationCode,
    'answers': answers,
    'width': width,
    'height': height,
    'unit': unit.name,
    'quantity': quantity,
    'textNote': textNote,
    'photos': photos.map((p) => p.toJson()).toList(),
    'voiceNotes': voiceNotes.map((v) => v.toJson()).toList(),
    'drawingPath': drawingPath,
    'updatedAt': updatedAt.toIso8601String(),
    'sizeMode': sizeMode.name,
    'units': units.map((u) => u.toJson()).toList(),
    'unitSeq': unitSeq,
    'previews': previews.map((c) => c.toJson()).toList(),
    if (comparisons.isNotEmpty)
      'comparisons': comparisons.map((c) => c.toJson()).toList(),
    if (checklistRequired) 'checklistRequired': true,
    if (doubleSided != null) 'doubleSided': doubleSided,
    if (legacyMediaCode != null) 'legacyMediaCode': legacyMediaCode,
    if (answersArchive.isNotEmpty) 'answersArchive': answersArchive,
    // Derived, write-only (always recomputed from mediaCode + doubleSided).
    if (gsbVariantKey != null) 'boardVariant': gsbVariantKey,
    if (gsbOverrides.isNotEmpty)
      'gsbOverrides': gsbOverrides.map((o) => o.toJson()).toList(),
    if (gsbLedSide != null) 'gsbLedSide': gsbLedSide,
    if (nlbSubtype != null) 'nlbSubtype': nlbSubtype,
  };

  factory Board.fromJson(Map<String, dynamic> j) {
    final units = _list(j['units'], SignageUnit.fromJson);
    return Board(
      id: _s(j['id']),
      name: _s(j['name'], 'Board'),
      mediaCode: j['mediaCode'] as String?,
      installationCode: j['installationCode'] as String?,
      answers: j['answers'] is Map
          ? Map<String, dynamic>.from(j['answers'] as Map)
          : {},
      width: _dn(j['width']),
      height: _dn(j['height']),
      unit: enumByName(MeasureUnit.values, j['unit'], MeasureUnit.ft),
      quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      textNote: _s(j['textNote']),
      photos: _list(j['photos'], SitePhoto.fromJson),
      voiceNotes: _list(j['voiceNotes'], VoiceNote.fromJson),
      drawingPath: j['drawingPath'] as String?,
      updatedAt: _dt(j['updatedAt']),
      sizeMode: enumByName(SizeMode.values, j['sizeMode'], SizeMode.same),
      units: units,
      previews: _list(j['previews'], PreviewCapture.fromJson),
      comparisons: _list(j['comparisons'], ComparisonRecord.fromJson),
      checklistRequired: j['checklistRequired'] == true,
      doubleSided: j['doubleSided'] is bool ? j['doubleSided'] as bool : null,
      legacyMediaCode: j['legacyMediaCode'] is String
          ? j['legacyMediaCode'] as String
          : null,
      answersArchive: j['answersArchive'] is Map
          ? Map<String, dynamic>.from(j['answersArchive'] as Map)
          : null,
      gsbOverrides: _list(j['gsbOverrides'], GsbSpecOverride.fromJson),
      gsbLedSide: j['gsbLedSide'] is String ? j['gsbLedSide'] as String : null,
      nlbSubtype:
          j['nlbSubtype'] == 'NLB_SINGLE_FRAME' ||
              j['nlbSubtype'] == 'NLB_BOX_FRAME'
          ? j['nlbSubtype'] as String
          : null,
      unitSeq: math.max(
        (j['unitSeq'] as num?)?.toInt() ?? units.length,
        units.length,
      ),
    );
  }
}

/// A reviewer's pointer to the exact part of a recce that was rejected.
class RejectionIssue {
  RejectionIssue({
    required this.groupId,
    required this.aspect,
    required this.label,
    this.unitId,
    this.photoId,
    this.note = '',
  });

  /// Media group ([Board.id]).
  final String groupId;
  final String? unitId;
  final String? photoId;
  final IssueAspect aspect;

  /// Human readable target, e.g. "GSB • Unit 02".
  final String label;
  final String note;

  String get text =>
      '$label – ${aspect.label}${note.trim().isEmpty ? '' : ': ${note.trim()}'}';

  Map<String, dynamic> toJson() => {
    'groupId': groupId,
    'unitId': unitId,
    'photoId': photoId,
    'aspect': aspect.name,
    'label': label,
    'note': note,
  };

  factory RejectionIssue.fromJson(Map<String, dynamic> j) => RejectionIssue(
    groupId: _s(j['groupId']),
    unitId: j['unitId'] is String ? j['unitId'] as String : null,
    photoId: j['photoId'] is String ? j['photoId'] as String : null,
    aspect: enumByName(IssueAspect.values, j['aspect'], IssueAspect.item),
    label: _s(j['label']),
    note: _s(j['note']),
  );
}

class ReviewRecord {
  ReviewRecord({
    required this.stage,
    required this.decision,
    required this.reviewerId,
    required this.reviewerName,
    required this.remarks,
    required this.at,
    List<String>? reasons,
    List<RejectionIssue>? issues,
  }) : reasons = reasons ?? [],
       issues = issues ?? [];

  final ReviewStage stage;
  final ReviewDecision decision;
  final String reviewerId;
  final String reviewerName;
  final String remarks;
  final List<String> reasons;

  /// Item-specific rejection targets (empty for whole-recce decisions).
  final List<RejectionIssue> issues;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'stage': stage.name,
    'decision': decision.name,
    'reviewerId': reviewerId,
    'reviewerName': reviewerName,
    'remarks': remarks,
    'reasons': reasons,
    if (issues.isNotEmpty) 'issues': issues.map((i) => i.toJson()).toList(),
    'at': at.toIso8601String(),
  };

  factory ReviewRecord.fromJson(Map<String, dynamic> j) => ReviewRecord(
    stage: enumByName(ReviewStage.values, j['stage'], ReviewStage.business),
    decision: enumByName(
      ReviewDecision.values,
      j['decision'],
      ReviewDecision.approved,
    ),
    reviewerId: _s(j['reviewerId']),
    reviewerName: _s(j['reviewerName']),
    remarks: _s(j['remarks']),
    reasons: (j['reasons'] as List?)?.map((e) => '$e').toList(),
    issues: _list(j['issues'], RejectionIssue.fromJson),
    at: _dt(j['at']),
  );
}

/// One immutable version of a shop recce sent for approval.
class Submission {
  Submission({
    required this.version,
    required this.submittedAt,
    required this.submittedById,
    required this.submittedByName,
    required this.snapshot,
    this.vendorRemarks = '',
    List<ReviewRecord>? reviews,
  }) : reviews = reviews ?? [];

  final int version;
  final DateTime submittedAt;
  final String submittedById;
  final String submittedByName;

  /// Deep JSON copy of the [Shop] (without its submissions) at submit time.
  final Map<String, dynamic> snapshot;
  final String vendorRemarks;
  final List<ReviewRecord> reviews;

  Shop get shopSnapshot => Shop.fromJson(snapshot);

  ReviewRecord? reviewFor(ReviewStage stage) {
    for (final r in reviews.reversed) {
      if (r.stage == stage) return r;
    }
    return null;
  }

  /// Status this version ended in (or is currently at).
  RecceStatus get outcome {
    final ops = reviewFor(ReviewStage.ops);
    final biz = reviewFor(ReviewStage.business);
    if (ops != null) {
      return ops.decision == ReviewDecision.approved
          ? RecceStatus.approved
          : RecceStatus.rejectedOps;
    }
    if (biz != null) {
      return biz.decision == ReviewDecision.approved
          ? RecceStatus.pendingOps
          : RecceStatus.rejectedBusiness;
    }
    return RecceStatus.pendingBusiness;
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'submittedAt': submittedAt.toIso8601String(),
    'submittedById': submittedById,
    'submittedByName': submittedByName,
    'snapshot': snapshot,
    'vendorRemarks': vendorRemarks,
    'reviews': reviews.map((r) => r.toJson()).toList(),
  };

  factory Submission.fromJson(Map<String, dynamic> j) => Submission(
    version: (j['version'] as num?)?.toInt() ?? 1,
    submittedAt: _dt(j['submittedAt']),
    submittedById: _s(j['submittedById']),
    submittedByName: _s(j['submittedByName']),
    snapshot: j['snapshot'] is Map
        ? Map<String, dynamic>.from(j['snapshot'] as Map)
        : {},
    vendorRemarks: _s(j['vendorRemarks']),
    reviews: _list(j['reviews'], ReviewRecord.fromJson),
  );
}

class Shop {
  Shop({
    required this.id,
    required this.projectId,
    required this.taskId,
    required this.name,
    this.ownerName = '',
    this.phone = '',
    this.address = '',
    this.area = '',
    this.city = '',
    this.pincode = '',
    this.landmark = '',
    this.remarks = '',
    this.geo,
    this.status = RecceStatus.notStarted,
    List<Board>? boards,
    List<Submission>? submissions,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<PhotoReviewComment>? reviewComments,
  }) : reviewComments = reviewComments ?? [],
       boards = boards ?? [],
       submissions = submissions ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String projectId;
  final String taskId;
  String name;
  String ownerName;
  String phone;
  String address;
  String area;
  String city;
  String pincode;
  String landmark;
  String remarks;

  /// GPS location of the shop, captured on site by the vendor.
  GeoFix? geo;
  RecceStatus status;
  List<Board> boards;
  List<Submission> submissions;
  DateTime createdAt;
  DateTime updatedAt;

  /// Reviewers' pinned photo comments (all versions). Not part of the
  /// submission snapshots, which stay exactly as submitted.
  List<PhotoReviewComment> reviewComments;

  int get currentVersion => submissions.length;

  Submission? get latestSubmission =>
      submissions.isEmpty ? null : submissions.last;

  String get fullAddress => [
    address,
    area,
    city,
    pincode,
  ].where((e) => e.trim().isNotEmpty).join(', ');

  int get photoCount => boards.fold(0, (s, b) => s + b.photos.length);

  /// Physical signage units across all media groups.
  int get unitCount => boards.fold(0, (s, b) => s + b.quantity);

  /// JSON of the shop without its submission history (used for snapshots).
  Map<String, dynamic> toSnapshotJson() {
    final json = toJson();
    json['submissions'] = <dynamic>[];
    json.remove('reviewComments');
    return json;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'taskId': taskId,
    'name': name,
    'ownerName': ownerName,
    'phone': phone,
    'address': address,
    'area': area,
    'city': city,
    'pincode': pincode,
    'landmark': landmark,
    'remarks': remarks,
    'geo': geo?.toJson(),
    'status': status.name,
    'boards': boards.map((b) => b.toJson()).toList(),
    'submissions': submissions.map((s) => s.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (reviewComments.isNotEmpty)
      'reviewComments': reviewComments.map((c) => c.toJson()).toList(),
  };

  factory Shop.fromJson(Map<String, dynamic> j) => Shop(
    id: _s(j['id']),
    projectId: _s(j['projectId']),
    taskId: _s(j['taskId']),
    name: _s(j['name']),
    ownerName: _s(j['ownerName']),
    phone: _s(j['phone']),
    address: _s(j['address']),
    area: _s(j['area']),
    city: _s(j['city']),
    pincode: _s(j['pincode']),
    landmark: _s(j['landmark']),
    remarks: _s(j['remarks']),
    geo: GeoFix.fromJson(j['geo']),
    status: enumByName(RecceStatus.values, j['status'], RecceStatus.notStarted),
    boards: _list(j['boards'], Board.fromJson),
    submissions: _list(j['submissions'], Submission.fromJson),
    createdAt: _dt(j['createdAt']),
    updatedAt: _dt(j['updatedAt']),
    reviewComments: _list(j['reviewComments'], PhotoReviewComment.fromJson),
  );
}

// ---------------------------------------------------------------------------
// Activity timeline
// ---------------------------------------------------------------------------

class ActivityEvent {
  ActivityEvent({
    required this.id,
    required this.kind,
    required this.title,
    required this.message,
    required this.actorName,
    required this.at,
    this.actorRole,
    this.projectId,
    this.taskId,
    this.shopId,
    this.version,
  });

  /// One of: created, updated, photo, note, submitted, approved, rejected,
  /// auth, system.
  final String kind;
  final String id;
  final String title;
  final String message;
  final String actorName;
  final UserRole? actorRole;
  final DateTime at;
  final String? projectId;
  final String? taskId;
  final String? shopId;
  final int? version;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'title': title,
    'message': message,
    'actorName': actorName,
    'actorRole': actorRole?.name,
    'at': at.toIso8601String(),
    'projectId': projectId,
    'taskId': taskId,
    'shopId': shopId,
    'version': version,
  };

  factory ActivityEvent.fromJson(Map<String, dynamic> j) => ActivityEvent(
    id: _s(j['id']),
    kind: _s(j['kind'], 'system'),
    title: _s(j['title']),
    message: _s(j['message']),
    actorName: _s(j['actorName']),
    actorRole: j['actorRole'] == null
        ? null
        : enumByName(UserRole.values, j['actorRole'], UserRole.vendor),
    at: _dt(j['at']),
    projectId: j['projectId'] as String?,
    taskId: j['taskId'] as String?,
    shopId: j['shopId'] as String?,
    version: (j['version'] as num?)?.toInt(),
  );
}

/// Root of everything persisted on the device.
class AppData {
  AppData({
    required this.users,
    required this.projects,
    required this.tasks,
    required this.shops,
    required this.activities,
    this.sessionUserId,
    this.loadedSchemaVersion = schemaVersion,
    List<ArLayout>? arLayouts,
    List<RecceReport>? reports,
    List<MediaReference>? mediaReferences,
    List<PanoramaRecord>? panoramas,
    Map<String, dynamic>? formDrafts,
  }) : arLayouts = arLayouts ?? [],
       reports = reports ?? [],
       mediaReferences = mediaReferences ?? [],
       formDrafts = formDrafts ?? {},
       panoramas = panoramas ?? [];

  /// 1 = ID + password login. 2 = 4-digit PIN login + GPS.
  /// 3 = multi-unit media groups (units, size mode, previews). Older boards
  ///     are upgraded on read by [Board.fromJson] (one unit per quantity).
  /// 4 = advanced site survey (markup, measurements, checklists, electrical,
  ///     comparisons, review comments, PDF reports). All new fields are
  ///     optional, so v3 data reads unchanged.
  static const schemaVersion = 4;

  /// Schema of the JSON this instance was read from (for migrations).
  final int loadedSchemaVersion;

  List<AppUser> users;
  List<Project> projects;
  List<RecceTask> tasks;
  List<Shop> shops;
  List<ActivityEvent> activities;
  String? sessionUserId;

  /// Saved Camera AR layouts (preview configuration only, never part of a
  /// submission snapshot). Missing in older data → empty.
  List<ArLayout> arLayouts;

  /// Generated measurement PDF reports (immutable snapshots).
  List<RecceReport> reports;

  /// Media reference photo library (technical approval tracking).
  List<MediaReference> mediaReferences;

  /// Optional imported 360° site panoramas.
  List<PanoramaRecord> panoramas;

  /// Unsaved form drafts (e.g. measurements being typed) kept on the device
  /// so an interrupted recce can be restored. Key = `form:unitId`.
  Map<String, dynamic> formDrafts;

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'users': users.map((e) => e.toJson()).toList(),
    'projects': projects.map((e) => e.toJson()).toList(),
    'tasks': tasks.map((e) => e.toJson()).toList(),
    'shops': shops.map((e) => e.toJson()).toList(),
    'activities': activities.map((e) => e.toJson()).toList(),
    'sessionUserId': sessionUserId,
    if (arLayouts.isNotEmpty)
      'arLayouts': arLayouts.map((e) => e.toJson()).toList(),
    if (reports.isNotEmpty) 'reports': reports.map((e) => e.toJson()).toList(),
    if (mediaReferences.isNotEmpty)
      'mediaReferences': mediaReferences.map((e) => e.toJson()).toList(),
    if (panoramas.isNotEmpty)
      'panoramas': panoramas.map((e) => e.toJson()).toList(),
    if (formDrafts.isNotEmpty) 'formDrafts': formDrafts,
  };

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
    users: _list(j['users'], AppUser.fromJson),
    projects: _list(j['projects'], Project.fromJson),
    tasks: _list(j['tasks'], RecceTask.fromJson),
    shops: _list(j['shops'], Shop.fromJson),
    activities: _list(j['activities'], ActivityEvent.fromJson),
    sessionUserId: j['sessionUserId'] as String?,
    loadedSchemaVersion: (j['schemaVersion'] as num?)?.toInt() ?? 1,
    arLayouts: _list(j['arLayouts'], ArLayout.fromJson),
    reports: _list(j['reports'], RecceReport.fromJson),
    mediaReferences: _list(j['mediaReferences'], MediaReference.fromJson),
    panoramas: _list(j['panoramas'], PanoramaRecord.fromJson),
    formDrafts: j['formDrafts'] is Map
        ? Map<String, dynamic>.from(j['formDrafts'] as Map)
        : null,
  );
}
