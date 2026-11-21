import 'dart:ui' show Offset, Size;

import 'enums.dart';

// Advanced site survey records (perspective placements, placement markers,
// electrical & obstruction mapping, checklists, measurements, comparisons,
// photo review comments and PDF reports).
//
// Every field is optional in JSON: records saved by older app versions parse
// with empty defaults, unknown enum names fall back to safe values and
// malformed entries are skipped instead of failing the whole document.

double _d(Object? v, [double fallback = 0]) {
  final r = v is num ? v.toDouble() : (double.tryParse('$v') ?? fallback);
  return r.isFinite ? r : fallback;
}

double? _dn(Object? v) {
  if (v == null) return null;
  final r = v is num ? v.toDouble() : double.tryParse('$v');
  return r != null && r.isFinite ? r : null;
}

int _i(Object? v, [int fallback = 0]) =>
    v is num ? v.toInt() : (int.tryParse('$v') ?? fallback);

String _s(Object? v, [String fallback = '']) => v is String ? v : fallback;

String? _sn(Object? v) => v is String && v.isNotEmpty ? v : null;

DateTime _dt(Object? v) =>
    (v is String ? DateTime.tryParse(v) : null) ??
    DateTime.fromMillisecondsSinceEpoch(0);

DateTime? _dtn(Object? v) => v is String ? DateTime.tryParse(v) : null;

List<String> _strings(Object? v) =>
    v is List ? v.whereType<String>().toList() : <String>[];

/// Parses every map in [v] with [f]; malformed entries are skipped.
/// Counts records skipped while parsing (malformed or unreadable entries).
/// [AppController] backs up the original JSON when this is non-zero.
class ModelParseLog {
  ModelParseLog._();

  static int skipped = 0;
}

/// Parses every map in [v] with [f]; malformed entries are skipped (and
/// counted in [ModelParseLog.skipped]) instead of failing the document.
List<T> surveyList<T>(Object? v, T Function(Map<String, dynamic>) f) {
  if (v is! List) return <T>[];
  final out = <T>[];
  for (final e in v) {
    if (e is! Map) continue;
    try {
      out.add(f(Map<String, dynamic>.from(e)));
    } catch (_) {
      ModelParseLog.skipped++;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/// A point on a photo as a fraction of its width ([x]) and height ([y]).
/// Normalised so it stays valid at any display size, zoom or orientation.
class SurveyPoint {
  const SurveyPoint(this.x, this.y);

  final double x;
  final double y;

  bool get isFinite => x.isFinite && y.isFinite;

  Offset toPixels(Size image) => Offset(x * image.width, y * image.height);

  static SurveyPoint fromPixels(Offset p, Size image) => SurveyPoint(
    image.width == 0 ? 0 : p.dx / image.width,
    image.height == 0 ? 0 : p.dy / image.height,
  );

  SurveyPoint operator +(SurveyPoint o) => SurveyPoint(x + o.x, y + o.y);
  SurveyPoint operator -(SurveyPoint o) => SurveyPoint(x - o.x, y - o.y);

  /// Keeps the point inside the photo plus [margin] (fraction) outside.
  SurveyPoint clamped([double margin = 0]) => SurveyPoint(
    x.clamp(-margin, 1 + margin).toDouble(),
    y.clamp(-margin, 1 + margin).toDouble(),
  );

  List<double> toJson() => [x, y];

  static SurveyPoint? fromJson(Object? v) {
    double? x, y;
    if (v is List && v.length >= 2) {
      x = _dn(v[0]);
      y = _dn(v[1]);
    } else if (v is Map) {
      x = _dn(v['x']);
      y = _dn(v['y']);
    }
    if (x == null || y == null) return null;
    return SurveyPoint(x, y);
  }

  static List<SurveyPoint> listFromJson(Object? v) => v is List
      ? v.map(SurveyPoint.fromJson).whereType<SurveyPoint>().toList()
      : <SurveyPoint>[];

  @override
  bool operator ==(Object other) =>
      other is SurveyPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

// ---------------------------------------------------------------------------
// Feature 1 – Four-corner perspective placement
// ---------------------------------------------------------------------------

/// Proposed board area on a photo as four independent corners (normalised
/// to the original image). Describes how the board appears in the photo –
/// never a physical measurement: the signage item's width/height are not
/// derived from it.
class PerspectivePlacement {
  PerspectivePlacement({
    required this.id,
    required this.photoId,
    required this.unitId,
    required List<SurveyPoint> corners,
    this.showArtwork = true,
    this.opacity = 0.85,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : corners = List.unmodifiable(corners),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now() {
    if (corners.length != 4) {
      throw ArgumentError('A perspective placement needs exactly 4 corners');
    }
  }

  final String id;
  final String photoId;

  /// Signage Item ID ([SignageUnit.id]).
  final String unitId;

  /// Top-left, top-right, bottom-right, bottom-left.
  final List<SurveyPoint> corners;
  final bool showArtwork;
  final double opacity;
  final DateTime createdAt;
  final DateTime updatedAt;

  SurveyPoint get topLeft => corners[0];
  SurveyPoint get topRight => corners[1];
  SurveyPoint get bottomRight => corners[2];
  SurveyPoint get bottomLeft => corners[3];

  /// Default, slightly inset rectangle used when a placement is added.
  static List<SurveyPoint> defaultCorners({
    double cx = 0.5,
    double cy = 0.4,
    double w = 0.4,
    double h = 0.18,
  }) => [
    SurveyPoint(cx - w / 2, cy - h / 2),
    SurveyPoint(cx + w / 2, cy - h / 2),
    SurveyPoint(cx + w / 2, cy + h / 2),
    SurveyPoint(cx - w / 2, cy + h / 2),
  ];

  PerspectivePlacement copyWith({
    List<SurveyPoint>? corners,
    String? unitId,
    bool? showArtwork,
    double? opacity,
    DateTime? updatedAt,
  }) => PerspectivePlacement(
    id: id,
    photoId: photoId,
    unitId: unitId ?? this.unitId,
    corners: corners ?? this.corners,
    showArtwork: showArtwork ?? this.showArtwork,
    opacity: opacity ?? this.opacity,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'photoId': photoId,
    'unitId': unitId,
    'corners': corners.map((c) => c.toJson()).toList(),
    'showArtwork': showArtwork,
    'opacity': opacity,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory PerspectivePlacement.fromJson(Map<String, dynamic> j) =>
      PerspectivePlacement(
        id: _s(j['id']),
        photoId: _s(j['photoId']),
        unitId: _s(j['unitId']),
        corners: SurveyPoint.listFromJson(j['corners']),
        showArtwork: j['showArtwork'] != false,
        opacity: _d(j['opacity'], 0.85).clamp(0.1, 1).toDouble(),
        createdAt: _dt(j['createdAt']),
        updatedAt: _dtn(j['updatedAt']),
      );
}

// ---------------------------------------------------------------------------
// Feature 3 – Board placement markers
// ---------------------------------------------------------------------------

/// Numbered pin showing where one signage item will be installed on a
/// photo. [number] is issued once and never regenerated on reload; only an
/// explicit reorder changes it.
class PlacementMarker {
  PlacementMarker({
    required this.id,
    required this.photoId,
    required this.unitId,
    required this.number,
    required this.position,
    this.placementNo = 1,
    this.mediaCode = '',
    List<SurveyPoint>? shape,
    this.notes = '',
    DateTime? createdAt,
  }) : shape = List.unmodifiable(shape ?? const []),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String photoId;

  /// Signage Item ID ([SignageUnit.id]).
  final String unitId;

  /// Visible marker number on this photo ("01", "02"…).
  final int number;

  /// 1 = primary placement of the item on this photo, 2+ = alternatives.
  final int placementNo;

  /// Media code at the time the marker was saved (display fallback).
  final String mediaCode;
  final SurveyPoint position;

  /// Optional outline of the placement area (≥ 3 points) or empty.
  final List<SurveyPoint> shape;
  final String notes;
  final DateTime createdAt;

  bool get isAlternative => placementNo > 1;

  String get numberLabel => number.toString().padLeft(2, '0');

  PlacementMarker copyWith({
    int? number,
    SurveyPoint? position,
    List<SurveyPoint>? shape,
    String? notes,
    String? unitId,
    int? placementNo,
    String? mediaCode,
  }) => PlacementMarker(
    id: id,
    photoId: photoId,
    unitId: unitId ?? this.unitId,
    number: number ?? this.number,
    position: position ?? this.position,
    placementNo: placementNo ?? this.placementNo,
    mediaCode: mediaCode ?? this.mediaCode,
    shape: shape ?? this.shape,
    notes: notes ?? this.notes,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'photoId': photoId,
    'unitId': unitId,
    'number': number,
    'placementNo': placementNo,
    'mediaCode': mediaCode,
    'position': position.toJson(),
    if (shape.isNotEmpty) 'shape': shape.map((p) => p.toJson()).toList(),
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PlacementMarker.fromJson(Map<String, dynamic> j) => PlacementMarker(
    id: _s(j['id']),
    photoId: _s(j['photoId']),
    unitId: _s(j['unitId']),
    number: _i(j['number'], 1),
    placementNo: _i(j['placementNo'], 1).clamp(1, 99),
    mediaCode: _s(j['mediaCode']),
    position:
        SurveyPoint.fromJson(j['position']) ?? const SurveyPoint(0.5, 0.5),
    shape: SurveyPoint.listFromJson(j['shape']),
    notes: _s(j['notes']),
    createdAt: _dt(j['createdAt']),
  );
}

// ---------------------------------------------------------------------------
// Feature 5 – Electrical & obstruction mapping
// ---------------------------------------------------------------------------

/// Yes / No / Unknown answer (null = not answered).
enum TriState { yes, no, unknown }

extension TriStateX on TriState {
  String get label => switch (this) {
    TriState.yes => 'Yes',
    TriState.no => 'No',
    TriState.unknown => 'Unknown',
  };
}

enum ElectricalMarkKind { point, switchPoint, powerNote }

extension ElectricalMarkKindX on ElectricalMarkKind {
  String get label => switch (this) {
    ElectricalMarkKind.point => 'Electrical Point',
    ElectricalMarkKind.switchPoint => 'Switch',
    ElectricalMarkKind.powerNote => 'Power Availability Note',
  };

  /// Code prefix shown on the photo ("EP-01").
  String get prefix => switch (this) {
    ElectricalMarkKind.point => 'EP',
    ElectricalMarkKind.switchPoint => 'SW',
    ElectricalMarkKind.powerNote => 'PN',
  };
}

/// Electrical point / switch / power note pinned on a photo.
class ElectricalMark {
  ElectricalMark({
    required this.id,
    required this.photoId,
    required this.kind,
    required this.number,
    required this.position,
    this.notes = '',
    List<String>? unitIds,
    DateTime? createdAt,
  }) : unitIds = List.unmodifiable(unitIds ?? const []),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String photoId;
  final ElectricalMarkKind kind;
  final int number;
  final SurveyPoint position;
  final String notes;

  /// Linked Signage Item IDs.
  final List<String> unitIds;
  final DateTime createdAt;

  String get code => '${kind.prefix}-${number.toString().padLeft(2, '0')}';

  ElectricalMark copyWith({
    SurveyPoint? position,
    String? notes,
    List<String>? unitIds,
  }) => ElectricalMark(
    id: id,
    photoId: photoId,
    kind: kind,
    number: number,
    position: position ?? this.position,
    notes: notes ?? this.notes,
    unitIds: unitIds ?? this.unitIds,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'photoId': photoId,
    'kind': kind.name,
    'number': number,
    'position': position.toJson(),
    'notes': notes,
    if (unitIds.isNotEmpty) 'unitIds': unitIds,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ElectricalMark.fromJson(Map<String, dynamic> j) => ElectricalMark(
    id: _s(j['id']),
    photoId: _s(j['photoId']),
    kind: enumByName(
      ElectricalMarkKind.values,
      j['kind'],
      ElectricalMarkKind.point,
    ),
    number: _i(j['number'], 1),
    position:
        SurveyPoint.fromJson(j['position']) ?? const SurveyPoint(0.5, 0.5),
    notes: _s(j['notes']),
    unitIds: _strings(j['unitIds']),
    createdAt: _dt(j['createdAt']),
  );
}

/// Proposed cable route drawn as a polyline on a photo ("CR-01").
class CableRoute {
  CableRoute({
    required this.id,
    required this.photoId,
    required this.number,
    required List<SurveyPoint> points,
    this.notes = '',
    List<String>? unitIds,
    DateTime? createdAt,
  }) : points = List.unmodifiable(points),
       unitIds = List.unmodifiable(unitIds ?? const []),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String photoId;
  final int number;
  final List<SurveyPoint> points;
  final String notes;
  final List<String> unitIds;
  final DateTime createdAt;

  String get code => 'CR-${number.toString().padLeft(2, '0')}';

  CableRoute copyWith({
    List<SurveyPoint>? points,
    String? notes,
    List<String>? unitIds,
  }) => CableRoute(
    id: id,
    photoId: photoId,
    number: number,
    points: points ?? this.points,
    notes: notes ?? this.notes,
    unitIds: unitIds ?? this.unitIds,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'photoId': photoId,
    'number': number,
    'points': points.map((p) => p.toJson()).toList(),
    'notes': notes,
    if (unitIds.isNotEmpty) 'unitIds': unitIds,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CableRoute.fromJson(Map<String, dynamic> j) => CableRoute(
    id: _s(j['id']),
    photoId: _s(j['photoId']),
    number: _i(j['number'], 1),
    points: SurveyPoint.listFromJson(j['points']),
    notes: _s(j['notes']),
    unitIds: _strings(j['unitIds']),
    createdAt: _dt(j['createdAt']),
  );
}

enum ObstructionType {
  acUnit,
  electricalCable,
  pipe,
  cctv,
  window,
  shutter,
  door,
  tree,
  existingSignage,
  other,
}

extension ObstructionTypeX on ObstructionType {
  String get label => switch (this) {
    ObstructionType.acUnit => 'AC Outdoor Unit',
    ObstructionType.electricalCable => 'Electrical Cable',
    ObstructionType.pipe => 'Pipe',
    ObstructionType.cctv => 'CCTV Camera',
    ObstructionType.window => 'Window',
    ObstructionType.shutter => 'Shutter',
    ObstructionType.door => 'Door',
    ObstructionType.tree => 'Tree',
    ObstructionType.existingSignage => 'Existing Signage',
    ObstructionType.other => 'Other Obstruction',
  };
}

/// How an obstruction is drawn on the photo.
enum ObstructionShape { point, rect, polygon, arrow, text }

extension ObstructionShapeX on ObstructionShape {
  String get label => switch (this) {
    ObstructionShape.point => 'Point marker',
    ObstructionShape.rect => 'Rectangle area',
    ObstructionShape.polygon => 'Polygon area',
    ObstructionShape.arrow => 'Arrow',
    ObstructionShape.text => 'Text label',
  };

  /// Minimum number of points for a valid shape.
  int get minPoints => switch (this) {
    ObstructionShape.point || ObstructionShape.text => 1,
    ObstructionShape.rect || ObstructionShape.arrow => 2,
    ObstructionShape.polygon => 3,
  };
}

enum Severity { low, medium, high }

extension SeverityX on Severity {
  String get label => switch (this) {
    Severity.low => 'Low',
    Severity.medium => 'Medium',
    Severity.high => 'High',
  };
}

/// An obstacle on a site photo that may affect installation ("OB-01").
class ObstructionMark {
  ObstructionMark({
    required this.id,
    required this.photoId,
    required this.type,
    required this.shape,
    required this.number,
    required List<SurveyPoint> points,
    this.severity = Severity.medium,
    this.label = '',
    this.remarks = '',
    List<String>? unitIds,
    this.evidencePhotoId,
    DateTime? createdAt,
  }) : points = List.unmodifiable(points),
       unitIds = List.unmodifiable(unitIds ?? const []),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String photoId;
  final ObstructionType type;
  final ObstructionShape shape;
  final int number;

  /// point/text: 1 point, rect: 2 opposite corners, arrow: tail → head,
  /// polygon: ≥ 3 vertices.
  final List<SurveyPoint> points;
  final Severity severity;

  /// Text shown for text labels (optional caption otherwise).
  final String label;
  final String remarks;

  /// Linked Signage Item IDs (empty = affects the photo in general).
  final List<String> unitIds;

  /// Optional close-up evidence photo ([SitePhoto.id]).
  final String? evidencePhotoId;
  final DateTime createdAt;

  String get code => 'OB-${number.toString().padLeft(2, '0')}';

  bool get isValid => points.length >= shape.minPoints;

  ObstructionMark copyWith({
    ObstructionType? type,
    List<SurveyPoint>? points,
    Severity? severity,
    String? label,
    String? remarks,
    List<String>? unitIds,
    String? evidencePhotoId,
    bool clearEvidence = false,
  }) => ObstructionMark(
    id: id,
    photoId: photoId,
    type: type ?? this.type,
    shape: shape,
    number: number,
    points: points ?? this.points,
    severity: severity ?? this.severity,
    label: label ?? this.label,
    remarks: remarks ?? this.remarks,
    unitIds: unitIds ?? this.unitIds,
    evidencePhotoId: clearEvidence
        ? null
        : (evidencePhotoId ?? this.evidencePhotoId),
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'photoId': photoId,
    'type': type.name,
    'shape': shape.name,
    'number': number,
    'points': points.map((p) => p.toJson()).toList(),
    'severity': severity.name,
    'label': label,
    'remarks': remarks,
    if (unitIds.isNotEmpty) 'unitIds': unitIds,
    'evidencePhotoId': ?evidencePhotoId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ObstructionMark.fromJson(Map<String, dynamic> j) => ObstructionMark(
    id: _s(j['id']),
    photoId: _s(j['photoId']),
    type: enumByName(ObstructionType.values, j['type'], ObstructionType.other),
    shape: enumByName(
      ObstructionShape.values,
      j['shape'],
      ObstructionShape.point,
    ),
    number: _i(j['number'], 1),
    points: SurveyPoint.listFromJson(j['points']),
    severity: enumByName(Severity.values, j['severity'], Severity.medium),
    label: _s(j['label']),
    remarks: _s(j['remarks']),
    unitIds: _strings(j['unitIds']),
    evidencePhotoId: _sn(j['evidencePhotoId']),
    createdAt: _dt(j['createdAt']),
  );
}

/// All advanced site markings of one photo. Stored next to (never inside)
/// the photo's existing [Annotation]s so the classic editor is untouched.
class SiteMarkup {
  SiteMarkup({
    List<PerspectivePlacement>? perspectives,
    List<PlacementMarker>? markers,
    List<ElectricalMark>? electrical,
    List<CableRoute>? cableRoutes,
    List<ObstructionMark>? obstructions,
  }) : perspectives = perspectives ?? [],
       markers = markers ?? [],
       electrical = electrical ?? [],
       cableRoutes = cableRoutes ?? [],
       obstructions = obstructions ?? [];

  List<PerspectivePlacement> perspectives;
  List<PlacementMarker> markers;
  List<ElectricalMark> electrical;
  List<CableRoute> cableRoutes;
  List<ObstructionMark> obstructions;

  bool get isEmpty =>
      perspectives.isEmpty &&
      markers.isEmpty &&
      electrical.isEmpty &&
      cableRoutes.isEmpty &&
      obstructions.isEmpty;

  int get count =>
      perspectives.length +
      markers.length +
      electrical.length +
      cableRoutes.length +
      obstructions.length;

  /// Every Signage Item ID referenced by a marking on this photo.
  Set<String> get unitIds => {
    ...perspectives.map((p) => p.unitId),
    ...markers.map((m) => m.unitId),
    for (final e in electrical) ...e.unitIds,
    for (final c in cableRoutes) ...c.unitIds,
    for (final o in obstructions) ...o.unitIds,
  };

  SiteMarkup copy() => SiteMarkup.fromJson(toJson());

  /// Drops every reference to [removed] Signage Item IDs (used when units
  /// are deleted). Markings owned by a removed unit are deleted; links on
  /// shared markings are removed.
  void forgetUnits(Set<String> removed) {
    perspectives.removeWhere((p) => removed.contains(p.unitId));
    markers.removeWhere((m) => removed.contains(m.unitId));
    electrical = [
      for (final e in electrical)
        e.copyWith(
          unitIds: e.unitIds.where((u) => !removed.contains(u)).toList(),
        ),
    ];
    cableRoutes = [
      for (final c in cableRoutes)
        c.copyWith(
          unitIds: c.unitIds.where((u) => !removed.contains(u)).toList(),
        ),
    ];
    obstructions = [
      for (final o in obstructions)
        o.copyWith(
          unitIds: o.unitIds.where((u) => !removed.contains(u)).toList(),
        ),
    ];
  }

  Map<String, dynamic> toJson() => {
    if (perspectives.isNotEmpty)
      'perspectives': perspectives.map((e) => e.toJson()).toList(),
    if (markers.isNotEmpty) 'markers': markers.map((e) => e.toJson()).toList(),
    if (electrical.isNotEmpty)
      'electrical': electrical.map((e) => e.toJson()).toList(),
    if (cableRoutes.isNotEmpty)
      'cableRoutes': cableRoutes.map((e) => e.toJson()).toList(),
    if (obstructions.isNotEmpty)
      'obstructions': obstructions.map((e) => e.toJson()).toList(),
  };

  factory SiteMarkup.fromJson(Object? j) {
    if (j is! Map) return SiteMarkup();
    return SiteMarkup(
      perspectives: surveyList(
        j['perspectives'],
        PerspectivePlacement.fromJson,
      ),
      markers: surveyList(j['markers'], PlacementMarker.fromJson),
      electrical: surveyList(j['electrical'], ElectricalMark.fromJson),
      cableRoutes: surveyList(
        j['cableRoutes'],
        CableRoute.fromJson,
      ).where((c) => c.points.length >= 2).toList(),
      obstructions: surveyList(
        j['obstructions'],
        ObstructionMark.fromJson,
      ).where((o) => o.isValid).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Feature 2 – Advanced measurements (per signage item)
// ---------------------------------------------------------------------------

/// Advanced measurements of one signage item. Lengths are stored in
/// millimetres (canonical unit, full double precision); [unit] is only the
/// unit the user enters / reads values in.
class MeasurementDetails {
  MeasurementDetails({
    Map<String, double>? valuesMm,
    Map<String, double>? counts,
    Map<String, String>? texts,
    Map<String, bool>? flags,
    this.unit = MeasureUnit.ft,
    this.updatedAt,
  }) : valuesMm = valuesMm ?? {},
       counts = counts ?? {},
       texts = texts ?? {},
       flags = flags ?? {};

  /// Length fields by field id, in millimetres.
  final Map<String, double> valuesMm;

  /// Count fields (pole count, pipe count, panel count).
  final Map<String, double> counts;

  /// Free-text fields (pole position, fixing position, surface…).
  final Map<String, String> texts;

  /// Yes/no switches (e.g. support pipes used).
  final Map<String, bool> flags;
  MeasureUnit unit;
  DateTime? updatedAt;

  bool get isEmpty =>
      valuesMm.isEmpty && counts.isEmpty && texts.isEmpty && flags.isEmpty;

  double? mm(String id) => valuesMm[id];

  MeasurementDetails copy() => MeasurementDetails.fromJson(toJson());

  Map<String, dynamic> toJson() => {
    if (valuesMm.isNotEmpty) 'valuesMm': valuesMm,
    if (counts.isNotEmpty) 'counts': counts,
    if (texts.isNotEmpty) 'texts': texts,
    if (flags.isNotEmpty) 'flags': flags,
    'unit': unit.name,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  static Map<String, double> _numMap(Object? v) => v is Map
      ? {
          for (final e in v.entries)
            if (_dn(e.value) != null) '${e.key}': _dn(e.value)!,
        }
      : {};

  factory MeasurementDetails.fromJson(Object? j) {
    if (j is! Map) return MeasurementDetails();
    return MeasurementDetails(
      valuesMm: _numMap(j['valuesMm']),
      counts: _numMap(j['counts']),
      texts: j['texts'] is Map
          ? {
              for (final e in (j['texts'] as Map).entries)
                if (e.value is String) '${e.key}': e.value as String,
            }
          : {},
      flags: j['flags'] is Map
          ? {
              for (final e in (j['flags'] as Map).entries)
                if (e.value is bool) '${e.key}': e.value as bool,
            }
          : {},
      unit: enumByName(MeasureUnit.values, j['unit'], MeasureUnit.ft),
      updatedAt: _dtn(j['updatedAt']),
    );
  }
}

// ---------------------------------------------------------------------------
// Feature 4 – Site checklist responses
// ---------------------------------------------------------------------------

/// Response to one checklist question of one signage item.
class ChecklistResponse {
  ChecklistResponse({
    required this.questionId,
    this.value,
    this.remarks = '',
    List<String>? evidencePhotoIds,
    DateTime? answeredAt,
  }) : evidencePhotoIds = List.unmodifiable(evidencePhotoIds ?? const []),
       answeredAt = answeredAt ?? DateTime.now();

  /// Checklist ID (question id of the definition).
  final String questionId;

  /// 'yes' / 'no' / 'na', an option string, a number or text.
  final Object? value;
  final String remarks;
  final List<String> evidencePhotoIds;
  final DateTime answeredAt;

  bool get isNa => value == 'na';

  bool get hasValue {
    final v = value;
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    return true;
  }

  ChecklistResponse copyWith({
    Object? value,
    bool clearValue = false,
    String? remarks,
    List<String>? evidencePhotoIds,
  }) => ChecklistResponse(
    questionId: questionId,
    value: clearValue ? null : (value ?? this.value),
    remarks: remarks ?? this.remarks,
    evidencePhotoIds: evidencePhotoIds ?? this.evidencePhotoIds,
  );

  Map<String, dynamic> toJson() => {
    'questionId': questionId,
    'value': ?value,
    if (remarks.isNotEmpty) 'remarks': remarks,
    if (evidencePhotoIds.isNotEmpty) 'evidencePhotoIds': evidencePhotoIds,
    'answeredAt': answeredAt.toIso8601String(),
  };

  factory ChecklistResponse.fromJson(Map<String, dynamic> j) {
    final v = j['value'];
    return ChecklistResponse(
      questionId: _s(j['questionId']),
      value: v is String || v is num || v is bool ? v : null,
      remarks: _s(j['remarks']),
      evidencePhotoIds: _strings(j['evidencePhotoIds']),
      answeredAt: _dt(j['answeredAt']),
    );
  }

  static Map<String, ChecklistResponse> mapFromJson(Object? j) {
    final out = <String, ChecklistResponse>{};
    for (final r in surveyList(j, ChecklistResponse.fromJson)) {
      if (r.questionId.isNotEmpty) out[r.questionId] = r;
    }
    return out;
  }

  static List<Map<String, dynamic>> mapToJson(
    Map<String, ChecklistResponse> m,
  ) => m.values.map((r) => r.toJson()).toList();
}

// ---------------------------------------------------------------------------
// Feature 5 – Electrical survey (per signage item)
// ---------------------------------------------------------------------------

/// Electrical availability recorded on site. Operational information only –
/// not an electrical safety certification or load calculation.
class ElectricalSurvey {
  ElectricalSurvey({
    this.electricityAvailable,
    this.pointAvailable,
    this.pointLocation = '',
    this.distanceMm,
    this.cableRouteNotes = '',
    this.switchLocation = '',
    this.remarks = '',
    List<String>? evidencePhotoIds,
    this.updatedAt,
  }) : evidencePhotoIds = List.unmodifiable(evidencePhotoIds ?? const []);

  final TriState? electricityAvailable;
  final TriState? pointAvailable;
  final String pointLocation;

  /// Approximate distance from the board, millimetres.
  final double? distanceMm;
  final String cableRouteNotes;
  final String switchLocation;
  final String remarks;
  final List<String> evidencePhotoIds;
  final DateTime? updatedAt;

  bool get isEmpty =>
      electricityAvailable == null &&
      pointAvailable == null &&
      pointLocation.isEmpty &&
      distanceMm == null &&
      cableRouteNotes.isEmpty &&
      switchLocation.isEmpty &&
      remarks.isEmpty &&
      evidencePhotoIds.isEmpty;

  Map<String, dynamic> toJson() => {
    'electricityAvailable': ?electricityAvailable?.name,
    'pointAvailable': ?pointAvailable?.name,
    if (pointLocation.isNotEmpty) 'pointLocation': pointLocation,
    'distanceMm': ?distanceMm,
    if (cableRouteNotes.isNotEmpty) 'cableRouteNotes': cableRouteNotes,
    if (switchLocation.isNotEmpty) 'switchLocation': switchLocation,
    if (remarks.isNotEmpty) 'remarks': remarks,
    if (evidencePhotoIds.isNotEmpty) 'evidencePhotoIds': evidencePhotoIds,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  static TriState? _tri(Object? v) => v is String
      ? TriState.values.where((t) => t.name == v).firstOrNull
      : null;

  factory ElectricalSurvey.fromJson(Object? j) {
    if (j is! Map) return ElectricalSurvey();
    final m = Map<String, dynamic>.from(j);
    return ElectricalSurvey(
      electricityAvailable: _tri(m['electricityAvailable']),
      pointAvailable: _tri(m['pointAvailable']),
      pointLocation: _s(m['pointLocation']),
      distanceMm: _dn(m['distanceMm']),
      cableRouteNotes: _s(m['cableRouteNotes']),
      switchLocation: _s(m['switchLocation']),
      remarks: _s(m['remarks']),
      evidencePhotoIds: _strings(m['evidencePhotoIds']),
      updatedAt: _dtn(m['updatedAt']),
    );
  }
}

// ---------------------------------------------------------------------------
// Feature 6 – Before / Proposed comparison
// ---------------------------------------------------------------------------

/// What the "Proposed" side of a comparison was made from.
enum ProposedSource { livePreview, perspective }

extension ProposedSourceX on ProposedSource {
  String get label => switch (this) {
    ProposedSource.livePreview => 'Live Preview',
    ProposedSource.perspective => 'Perspective placement',
  };
}

/// A saved Before / Proposed comparison image. A visual proposal only –
/// never an as-built photograph. The original photo is only referenced.
class ComparisonRecord {
  ComparisonRecord({
    required this.id,
    required this.groupId,
    required this.unitId,
    required this.photoId,
    required this.source,
    required this.versionLabel,
    required this.path,
    required this.createdAt,
    this.previewId,
    this.mode = 'sideBySide',
  });

  final String id;
  final String groupId;

  /// Signage Item ID the comparison is stored against.
  final String unitId;

  /// "Before" site photo ([SitePhoto.id]).
  final String photoId;
  final ProposedSource source;

  /// [PreviewCapture.id] of the proposed Live Preview (null for a
  /// perspective composite).
  final String? previewId;

  /// e.g. "Live preview 2 of 3 • 18 Nov 2026 10:30".
  final String versionLabel;

  /// Exported comparison image (app-local file).
  final String path;
  final String mode;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    'unitId': unitId,
    'photoId': photoId,
    'source': source.name,
    'previewId': ?previewId,
    'versionLabel': versionLabel,
    'path': path,
    'mode': mode,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ComparisonRecord.fromJson(Map<String, dynamic> j) => ComparisonRecord(
    id: _s(j['id']),
    groupId: _s(j['groupId']),
    unitId: _s(j['unitId']),
    photoId: _s(j['photoId']),
    source: enumByName(
      ProposedSource.values,
      j['source'],
      ProposedSource.livePreview,
    ),
    previewId: _sn(j['previewId']),
    versionLabel: _s(j['versionLabel']),
    path: _s(j['path']),
    mode: _s(j['mode'], 'sideBySide'),
    createdAt: _dt(j['createdAt']),
  );
}

// ---------------------------------------------------------------------------
// Feature 7 – Photo-level review comments
// ---------------------------------------------------------------------------

enum ReviewCommentType {
  incorrectMeasurement,
  unclearPhoto,
  wrongPlacement,
  installationConcern,
  electricalConcern,
  obstructionConcern,
  additionalPhoto,
  general,
}

extension ReviewCommentTypeX on ReviewCommentType {
  String get label => switch (this) {
    ReviewCommentType.incorrectMeasurement => 'Incorrect Measurement',
    ReviewCommentType.unclearPhoto => 'Unclear Photo',
    ReviewCommentType.wrongPlacement => 'Wrong Board Placement',
    ReviewCommentType.installationConcern => 'Installation Concern',
    ReviewCommentType.electricalConcern => 'Electrical Concern',
    ReviewCommentType.obstructionConcern => 'Obstruction Concern',
    ReviewCommentType.additionalPhoto => 'Additional Photo Required',
    ReviewCommentType.general => 'General Clarification',
  };

  /// Closest existing rejection aspect (used when a comment rejects
  /// evidence).
  IssueAspect get aspect => switch (this) {
    ReviewCommentType.incorrectMeasurement => IssueAspect.dimension,
    ReviewCommentType.wrongPlacement => IssueAspect.annotation,
    ReviewCommentType.installationConcern ||
    ReviewCommentType.electricalConcern ||
    ReviewCommentType.obstructionConcern => IssueAspect.installation,
    _ => IssueAspect.photo,
  };
}

enum CommentStatus { open, addressed, verified }

extension CommentStatusX on CommentStatus {
  String get label => switch (this) {
    CommentStatus.open => 'Open',
    CommentStatus.addressed => 'Addressed',
    CommentStatus.verified => 'Verified',
  };
}

/// Recce staff reply to a review comment.
class CommentResponse {
  CommentResponse({
    required this.byId,
    required this.byName,
    required this.text,
    required this.at,
    this.role,
    this.version,
  });

  final String byId;
  final String byName;
  final UserRole? role;
  final String text;
  final DateTime at;

  /// Recce version the response was written against.
  final int? version;

  Map<String, dynamic> toJson() => {
    'byId': byId,
    'byName': byName,
    'role': ?role?.name,
    'text': text,
    'at': at.toIso8601String(),
    'version': ?version,
  };

  factory CommentResponse.fromJson(Map<String, dynamic> j) => CommentResponse(
    byId: _s(j['byId']),
    byName: _s(j['byName']),
    role: j['role'] is String
        ? enumByName(UserRole.values, j['role'], UserRole.vendor)
        : null,
    text: _s(j['text']),
    at: _dt(j['at']),
    version: j['version'] is num ? (j['version'] as num).toInt() : null,
  );
}

/// A reviewer's pinned comment on a specific spot of a site photo. Stored
/// on the shop (outside submission snapshots) and tied to the submission
/// [version] it was written for. Never overwrites staff annotations.
class PhotoReviewComment {
  PhotoReviewComment({
    required this.id,
    required this.projectId,
    required this.taskId,
    required this.shopId,
    required this.groupId,
    required this.photoId,
    required this.version,
    required this.reviewerRole,
    required this.reviewerId,
    required this.reviewerName,
    required this.type,
    required this.text,
    required this.position,
    required this.createdAt,
    required this.number,
    this.unitId,
    this.status = CommentStatus.open,
    this.rejectsEvidence = false,
    List<CommentResponse>? responses,
    this.addressedAt,
    this.verifiedAt,
    this.verifiedByName,
  }) : responses = responses ?? [];

  final String id;
  final String projectId;
  final String taskId;
  final String shopId;

  /// Media group ([Board.id]).
  final String groupId;

  /// Signage Item ID (null = whole photo / media group).
  final String? unitId;
  final String photoId;

  /// Submission version the comment was written for.
  final int version;
  final UserRole reviewerRole;
  final String reviewerId;
  final String reviewerName;
  final ReviewCommentType type;
  final String text;

  /// Normalised position on the photo.
  final SurveyPoint position;
  final DateTime createdAt;

  /// Marker number shown on the photo (stable once issued).
  final int number;

  /// The reviewer flagged this photo / evidence as rejected.
  final bool rejectsEvidence;
  CommentStatus status;
  final List<CommentResponse> responses;
  DateTime? addressedAt;
  DateTime? verifiedAt;
  String? verifiedByName;

  bool get isOpen => status == CommentStatus.open;

  /// "B1" / "O2": stage letter + number.
  String get markerLabel =>
      '${reviewerRole == UserRole.recceOps ? 'O' : 'B'}$number';

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'taskId': taskId,
    'shopId': shopId,
    'groupId': groupId,
    'unitId': ?unitId,
    'photoId': photoId,
    'version': version,
    'reviewerRole': reviewerRole.name,
    'reviewerId': reviewerId,
    'reviewerName': reviewerName,
    'type': type.name,
    'text': text,
    'position': position.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'number': number,
    'status': status.name,
    if (rejectsEvidence) 'rejectsEvidence': true,
    if (responses.isNotEmpty)
      'responses': responses.map((r) => r.toJson()).toList(),
    if (addressedAt != null) 'addressedAt': addressedAt!.toIso8601String(),
    if (verifiedAt != null) 'verifiedAt': verifiedAt!.toIso8601String(),
    'verifiedByName': ?verifiedByName,
  };

  factory PhotoReviewComment.fromJson(Map<String, dynamic> j) =>
      PhotoReviewComment(
        id: _s(j['id']),
        projectId: _s(j['projectId']),
        taskId: _s(j['taskId']),
        shopId: _s(j['shopId']),
        groupId: _s(j['groupId']),
        unitId: _sn(j['unitId']),
        photoId: _s(j['photoId']),
        version: _i(j['version'], 1),
        reviewerRole: enumByName(
          UserRole.values,
          j['reviewerRole'],
          UserRole.businessTeam,
        ),
        reviewerId: _s(j['reviewerId']),
        reviewerName: _s(j['reviewerName']),
        type: enumByName(
          ReviewCommentType.values,
          j['type'],
          ReviewCommentType.general,
        ),
        text: _s(j['text']),
        position:
            SurveyPoint.fromJson(j['position']) ?? const SurveyPoint(0.5, 0.5),
        createdAt: _dt(j['createdAt']),
        number: _i(j['number'], 1),
        status: enumByName(
          CommentStatus.values,
          j['status'],
          CommentStatus.open,
        ),
        rejectsEvidence: j['rejectsEvidence'] == true,
        responses: surveyList(j['responses'], CommentResponse.fromJson),
        addressedAt: _dtn(j['addressedAt']),
        verifiedAt: _dtn(j['verifiedAt']),
        verifiedByName: _sn(j['verifiedByName']),
      );
}

// ---------------------------------------------------------------------------
// Feature 8 – Recce measurement PDF reports
// ---------------------------------------------------------------------------

/// A generated measurement PDF. [snapshot] is the immutable report data the
/// PDF was built from, so later recce edits never change a historical
/// report.
class RecceReport {
  RecceReport({
    required this.id,
    required this.shopId,
    required this.projectId,
    required this.taskId,
    required this.version,
    required this.status,
    required this.isDraft,
    required this.generatedAt,
    required this.generatedByName,
    required this.path,
    this.sizeBytes = 0,
    this.pageCount = 0,
    Map<String, dynamic>? snapshot,
  }) : snapshot = snapshot ?? {};

  final String id;
  final String shopId;
  final String projectId;
  final String taskId;

  /// Submission version the report describes (0 = never submitted).
  final int version;

  /// Recce status at generation time.
  final RecceStatus status;

  /// True unless the recce was finally approved.
  final bool isDraft;
  final DateTime generatedAt;
  final String generatedByName;

  /// PDF file in app-local storage.
  final String path;
  final int sizeBytes;
  final int pageCount;
  final Map<String, dynamic> snapshot;

  Map<String, dynamic> toJson() => {
    'id': id,
    'shopId': shopId,
    'projectId': projectId,
    'taskId': taskId,
    'version': version,
    'status': status.name,
    'isDraft': isDraft,
    'generatedAt': generatedAt.toIso8601String(),
    'generatedByName': generatedByName,
    'path': path,
    'sizeBytes': sizeBytes,
    'pageCount': pageCount,
    if (snapshot.isNotEmpty) 'snapshot': snapshot,
  };

  factory RecceReport.fromJson(Map<String, dynamic> j) => RecceReport(
    id: _s(j['id']),
    shopId: _s(j['shopId']),
    projectId: _s(j['projectId']),
    taskId: _s(j['taskId']),
    version: _i(j['version']),
    status: enumByName(RecceStatus.values, j['status'], RecceStatus.inProgress),
    isDraft: j['isDraft'] != false,
    generatedAt: _dt(j['generatedAt']),
    generatedByName: _s(j['generatedByName']),
    path: _s(j['path']),
    sizeBytes: _i(j['sizeBytes']),
    pageCount: _i(j['pageCount']),
    snapshot: j['snapshot'] is Map
        ? Map<String, dynamic>.from(j['snapshot'] as Map)
        : {},
  );
}
