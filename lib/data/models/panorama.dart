// Optional 360° site panorama (local only).
//
// A panorama is an imported equirectangular image (2:1) of the site. It is a
// visual aid, not a metric 3D reconstruction: signage placements are stored
// as viewing directions (yaw / pitch in degrees) plus a relative size, so
// they survive zoom and pan but carry no real-world measurement.

import 'site_survey.dart' show surveyList;

double _num(Object? v, [double fallback = 0]) {
  final r = v is num ? v.toDouble() : (double.tryParse('$v') ?? fallback);
  return r.isFinite ? r : fallback;
}

int _int(Object? v, [int fallback = 0]) =>
    v is num ? v.toInt() : (int.tryParse('$v') ?? fallback);

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

DateTime _date(Object? v) =>
    (v is String ? DateTime.tryParse(v) : null) ??
    DateTime.fromMillisecondsSinceEpoch(0);

DateTime? _dateN(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Normalises a yaw angle to 0 ≤ yaw < 360.
double normalizeYaw(double deg) {
  if (!deg.isFinite) return 0;
  final r = deg % 360;
  return r < 0 ? r + 360 : r;
}

/// Smallest accepted panorama width in pixels.
const panoramaMinWidth = 2000;

/// Equirectangular images are 2:1; ±10 % is accepted.
const panoramaAspect = 2.0;
const panoramaAspectTolerance = 0.10;

/// Why an image of [width]×[height] px is not accepted as an
/// equirectangular panorama (null = accepted).
String? panoramaSizeProblem(int width, int height) {
  if (width <= 0 || height <= 0) {
    return 'The image could not be read (no size information).';
  }
  final ratio = width / height;
  final lo = panoramaAspect * (1 - panoramaAspectTolerance);
  final hi = panoramaAspect * (1 + panoramaAspectTolerance);
  if (ratio < lo || ratio > hi) {
    return 'Not a 360° equirectangular panorama: the image is '
        '$width×$height px (aspect ${ratio.toStringAsFixed(2)}:1). A 360° '
        'panorama must be about 2:1 (${lo.toStringAsFixed(1)}–'
        '${hi.toStringAsFixed(1)}:1).';
  }
  if (width < panoramaMinWidth) {
    return 'The panorama is too small ($width px wide). At least '
        '$panoramaMinWidth px width is needed.';
  }
  return null;
}

/// One signage item placed in a panorama.
class PanoramaPlacement {
  PanoramaPlacement({
    required this.id,
    required this.unitId,
    required double yawDeg,
    required double pitchDeg,
    required this.createdAt,
    double scale = 1,
    double rotationDeg = 0,
  }) : yawDeg = normalizeYaw(yawDeg),
       pitchDeg = pitchDeg.clamp(-90, 90).toDouble(),
       scale = scale.clamp(minScale, maxScale).toDouble(),
       rotationDeg = rotationDeg.clamp(-180, 180).toDouble();

  static const minScale = 0.2;
  static const maxScale = 5.0;

  /// Horizontal angle a placement covers at scale 1.
  static const baseWidthDeg = 20.0;

  final String id;

  /// Signage item ([SignageUnit.id]).
  final String unitId;

  /// Direction of the board centre: yaw 0..360 (0 = image centre),
  /// pitch -90..90 (up is positive).
  double yawDeg;
  double pitchDeg;

  /// Size multiplier ([baseWidthDeg] wide at 1).
  double scale;

  /// In-view rotation in degrees.
  double rotationDeg;
  final DateTime createdAt;

  double get widthDeg => baseWidthDeg * scale;

  PanoramaPlacement copy() => PanoramaPlacement.fromJson(toJson());

  Map<String, dynamic> toJson() => {
    'id': id,
    'unitId': unitId,
    'yawDeg': yawDeg,
    'pitchDeg': pitchDeg,
    'scale': scale,
    'rotationDeg': rotationDeg,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PanoramaPlacement.fromJson(Map<String, dynamic> j) {
    final id = _str(j['id']);
    final unitId = _str(j['unitId']);
    if (id.isEmpty || unitId.isEmpty) {
      throw const FormatException('Panorama placement without id / unit');
    }
    return PanoramaPlacement(
      id: id,
      unitId: unitId,
      yawDeg: _num(j['yawDeg']),
      pitchDeg: _num(j['pitchDeg']),
      scale: _num(j['scale'], 1),
      rotationDeg: _num(j['rotationDeg']),
      createdAt: _date(j['createdAt']),
    );
  }
}

/// An imported panorama of a shop site.
class PanoramaRecord {
  PanoramaRecord({
    required this.id,
    required this.shopId,
    required this.projectId,
    required this.taskId,
    required this.path,
    required this.width,
    required this.height,
    required this.importedAt,
    this.label = '360° panorama',
    this.capturedAt,
    this.northYawDeg = 0,
    List<PanoramaPlacement>? placements,
    List<String>? previews,
  }) : placements = placements ?? [],
       previews = previews ?? [];

  final String id;
  final String shopId;
  final String projectId;
  final String taskId;

  /// App-local copy of the image (MediaStorage folder "panoramas").
  final String path;
  final int width;
  final int height;
  String label;
  final DateTime importedAt;

  /// When the photo was taken, if known (gallery imports usually aren't).
  final DateTime? capturedAt;

  /// Yaw that faces north, set by the user ("set current view as North").
  /// 0 until set – direction presets are relative to it.
  double northYawDeg;
  List<PanoramaPlacement> placements;

  /// Saved preview images (current view with placements, PNG).
  List<String> previews;

  double get aspectRatio => height == 0 ? 0 : width / height;

  Map<String, dynamic> toJson() => {
    'id': id,
    'shopId': shopId,
    'projectId': projectId,
    'taskId': taskId,
    'path': path,
    'width': width,
    'height': height,
    if (label.isNotEmpty) 'label': label,
    'importedAt': importedAt.toIso8601String(),
    if (capturedAt != null) 'capturedAt': capturedAt!.toIso8601String(),
    if (northYawDeg != 0) 'northYawDeg': northYawDeg,
    if (placements.isNotEmpty)
      'placements': placements.map((p) => p.toJson()).toList(),
    if (previews.isNotEmpty) 'previews': previews,
  };

  factory PanoramaRecord.fromJson(Map<String, dynamic> j) {
    final id = _str(j['id']);
    final shopId = _str(j['shopId']);
    if (id.isEmpty || shopId.isEmpty) {
      throw const FormatException('Panorama without id / shop');
    }
    return PanoramaRecord(
      id: id,
      shopId: shopId,
      projectId: _str(j['projectId']),
      taskId: _str(j['taskId']),
      path: _str(j['path']),
      width: _int(j['width']),
      height: _int(j['height']),
      label: _str(j['label'], '360° panorama'),
      importedAt: _date(j['importedAt']),
      capturedAt: _dateN(j['capturedAt']),
      northYawDeg: normalizeYaw(_num(j['northYawDeg'])),
      placements: surveyList(j['placements'], PanoramaPlacement.fromJson),
      previews: j['previews'] is List
          ? (j['previews'] as List).whereType<String>().toList()
          : null,
    );
  }
}
