import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Offset, Size;

import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import 'perspective_math.dart';
import 'site_markup_painter.dart';

/// Tools of the advanced site markup editor.
enum SiteMarkupTool {
  select,
  perspective,
  marker,
  electricalPoint,
  switchPoint,
  powerNote,
  cableRoute,
  obstruction,
  pan,
}

extension SiteMarkupToolX on SiteMarkupTool {
  String get label => switch (this) {
    SiteMarkupTool.select => 'Select',
    SiteMarkupTool.perspective => 'Perspective',
    SiteMarkupTool.marker => 'Marker',
    SiteMarkupTool.electricalPoint => 'Elec. point',
    SiteMarkupTool.switchPoint => 'Switch',
    SiteMarkupTool.powerNote => 'Power note',
    SiteMarkupTool.cableRoute => 'Cable route',
    SiteMarkupTool.obstruction => 'Obstruction',
    SiteMarkupTool.pan => 'Zoom',
  };

  String get hint => switch (this) {
    SiteMarkupTool.select =>
      'Tap a marking to select it. Drag to move; drag a corner handle to '
          'reshape a perspective board.',
    SiteMarkupTool.perspective =>
      'Tap where the board goes, then drag the four corners onto the '
          'installation area.',
    SiteMarkupTool.marker =>
      'Tap the photo to drop a numbered board placement marker.',
    SiteMarkupTool.electricalPoint => 'Tap the electrical point location.',
    SiteMarkupTool.switchPoint => 'Tap the switch location.',
    SiteMarkupTool.powerNote => 'Tap to add a power availability note.',
    SiteMarkupTool.cableRoute =>
      'Tap points along the proposed cable route, then tap Done.',
    SiteMarkupTool.obstruction =>
      'Choose the obstruction type and shape, then mark it on the photo.',
    SiteMarkupTool.pan => 'Pinch to zoom, drag to pan the photo.',
  };

  MarkupLayer? get layer => switch (this) {
    SiteMarkupTool.perspective => MarkupLayer.perspective,
    SiteMarkupTool.marker => MarkupLayer.markers,
    SiteMarkupTool.electricalPoint ||
    SiteMarkupTool.switchPoint ||
    SiteMarkupTool.powerNote ||
    SiteMarkupTool.cableRoute => MarkupLayer.electrical,
    SiteMarkupTool.obstruction => MarkupLayer.obstructions,
    _ => null,
  };
}

/// Result of adding a placement marker.
enum MarkerAddResult { added, duplicatePrimary }

/// Kind of the selected marking.
enum MarkupKind { perspective, marker, electrical, cable, obstruction }

/// Editing state of the advanced markup of one photo. Pure Dart (no
/// widgets) so every rule – corners, validation, duplicate prevention,
/// stable numbering, undo / redo – is unit-testable.
///
/// Coordinates are normalised to the photo ([SurveyPoint]); [imageSize] is
/// the photo's pixel size and is used for aspect-correct geometry checks.
class SiteMarkupController extends ChangeNotifier {
  SiteMarkupController({
    required this.photoId,
    required SiteMarkup initial,
    required this.imageSize,
    this.activeUnitId,
    this.maxHistory = 40,
    String Function(String prefix)? newIdFn,
  }) : _m = initial.copy(),
       _newId = newIdFn ?? newId;

  final String photoId;
  final Size imageSize;
  final int maxHistory;
  final String Function(String prefix) _newId;

  SiteMarkup _m;
  SiteMarkupTool _tool = SiteMarkupTool.select;
  String? _selectedId;
  String? activeUnitId;
  final Set<MarkupLayer> hidden = {};
  final List<Map<String, dynamic>> _undo = [];
  final List<Map<String, dynamic>> _redo = [];
  Map<String, dynamic>? _gestureStart;
  bool _dirty = false;

  // Obstruction defaults for the next obstruction.
  ObstructionType obstructionType = ObstructionType.acUnit;
  ObstructionShape obstructionShape = ObstructionShape.point;
  Severity obstructionSeverity = Severity.medium;

  /// Points of the polyline / polygon / drag being drawn.
  final List<SurveyPoint> draft = [];

  SiteMarkup get markup => _m;
  SiteMarkupTool get tool => _tool;
  String? get selectedId => _selectedId;
  bool get dirty => _dirty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Does the tool build a multi-point draft (route / polygon)?
  bool get drawsPolyline =>
      _tool == SiteMarkupTool.cableRoute ||
      (_tool == SiteMarkupTool.obstruction &&
          obstructionShape == ObstructionShape.polygon);

  // ---------------------------------------------------------------------------
  // Selection & lookup
  // ---------------------------------------------------------------------------

  MarkupKind? kindOf(String? id) {
    if (id == null) return null;
    if (_m.perspectives.any((e) => e.id == id)) return MarkupKind.perspective;
    if (_m.markers.any((e) => e.id == id)) return MarkupKind.marker;
    if (_m.electrical.any((e) => e.id == id)) return MarkupKind.electrical;
    if (_m.cableRoutes.any((e) => e.id == id)) return MarkupKind.cable;
    if (_m.obstructions.any((e) => e.id == id)) return MarkupKind.obstruction;
    return null;
  }

  MarkupKind? get selectedKind => kindOf(_selectedId);

  PerspectivePlacement? perspective(String? id) =>
      _m.perspectives.where((e) => e.id == id).firstOrNull;
  PlacementMarker? marker(String? id) =>
      _m.markers.where((e) => e.id == id).firstOrNull;
  ElectricalMark? electrical(String? id) =>
      _m.electrical.where((e) => e.id == id).firstOrNull;
  CableRoute? cable(String? id) =>
      _m.cableRoutes.where((e) => e.id == id).firstOrNull;
  ObstructionMark? obstruction(String? id) =>
      _m.obstructions.where((e) => e.id == id).firstOrNull;

  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = kindOf(id) == null ? null : id;
    notifyListeners();
  }

  void setTool(SiteMarkupTool t) {
    _tool = t;
    draft.clear();
    final layer = t.layer;
    if (layer != null) hidden.remove(layer);
    if (t != SiteMarkupTool.select && t != SiteMarkupTool.pan) {
      _selectedId = null;
    }
    notifyListeners();
  }

  void toggleLayer(MarkupLayer l) {
    if (!hidden.remove(l)) hidden.add(l);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  List<Offset> quadPixels(PerspectivePlacement p) => [
    for (final c in p.corners) c.toPixels(imageSize),
  ];

  QuadProblem problemOf(PerspectivePlacement p) =>
      QuadGeometry.validate(quadPixels(p), imageSize);

  /// Perspective placements that cannot be saved, with the reason.
  Map<String, QuadProblem> get problems => {
    for (final p in _m.perspectives)
      if (problemOf(p) != QuadProblem.none) p.id: problemOf(p),
  };

  /// Why Save is disabled (null = can save).
  String? get saveBlockedReason {
    final pr = problems;
    if (pr.isEmpty) return null;
    return pr.values.first.message;
  }

  bool get canSave => problems.isEmpty;

  // ---------------------------------------------------------------------------
  // History (one entry per completed gesture or action)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _snap() => _m.toJson();

  void _push(Map<String, dynamic> before) {
    _undo.add(before);
    if (_undo.length > maxHistory) _undo.removeAt(0);
    _redo.clear();
    _dirty = true;
  }

  /// Wraps a discrete action in one undo step.
  T _act<T>(T Function() f) {
    final before = _snap();
    final r = f();
    if (!_jsonEquals(before, _snap())) _push(before);
    notifyListeners();
    return r;
  }

  static bool _jsonEquals(Map<String, dynamic> a, Map<String, dynamic> b) =>
      jsonEncode(a) == jsonEncode(b);

  void beginGesture() => _gestureStart ??= _snap();

  void endGesture() {
    final start = _gestureStart;
    _gestureStart = null;
    if (start != null && !_jsonEquals(start, _snap())) _push(start);
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snap());
    _m = SiteMarkup.fromJson(_undo.removeLast());
    if (kindOf(_selectedId) == null) _selectedId = null;
    _dirty = true;
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snap());
    _m = SiteMarkup.fromJson(_redo.removeLast());
    if (kindOf(_selectedId) == null) _selectedId = null;
    _dirty = true;
    notifyListeners();
  }

  /// Marks the current state as saved.
  void markSaved() {
    _dirty = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Perspective placements
  // ---------------------------------------------------------------------------

  /// Default rectangle centred at [centre] with the board's aspect ratio
  /// (as seen on the photo, not a measurement).
  List<SurveyPoint> defaultQuad(SurveyPoint centre, {double aspect = 3}) {
    final iw = imageSize.width <= 0 ? 1.0 : imageSize.width;
    final ih = imageSize.height <= 0 ? 1.0 : imageSize.height;
    // 40 % of the photo width, height from the aspect ratio (≤ 50 %).
    var wPx = iw * 0.4;
    var hPx = wPx / aspect.clamp(0.1, 20);
    if (hPx > ih * 0.5) {
      hPx = ih * 0.5;
      wPx = hPx * aspect;
    }
    final w = wPx / iw, h = hPx / ih;
    final cx = centre.x.clamp(w / 2, 1 - w / 2).toDouble();
    final cy = centre.y.clamp(h / 2, 1 - h / 2).toDouble();
    return PerspectivePlacement.defaultCorners(cx: cx, cy: cy, w: w, h: h);
  }

  PerspectivePlacement addPerspective(
    String unitId, {
    SurveyPoint centre = const SurveyPoint(0.5, 0.4),
    double aspect = 3,
  }) => _act(() {
    final p = PerspectivePlacement(
      id: _newId('pp'),
      photoId: photoId,
      unitId: unitId,
      corners: defaultQuad(centre, aspect: aspect),
    );
    _m.perspectives.add(p);
    _selectedId = p.id;
    _tool = SiteMarkupTool.select;
    return p;
  });

  void _replacePerspective(PerspectivePlacement p) {
    final i = _m.perspectives.indexWhere((e) => e.id == p.id);
    if (i >= 0) _m.perspectives[i] = p;
  }

  /// Moves one corner (0 TL, 1 TR, 2 BR, 3 BL). Call inside a gesture.
  void moveCorner(String id, int corner, SurveyPoint to) {
    final p = perspective(id);
    if (p == null || corner < 0 || corner > 3) return;
    final c = [...p.corners];
    c[corner] = to.clamped(0.25);
    _replacePerspective(p.copyWith(corners: c, updatedAt: DateTime.now()));
    _dirty = true;
    notifyListeners();
  }

  /// Resets the corners to an upright rectangle around the current centre.
  void resetCorners(String id, {double aspect = 3}) => _act(() {
    final p = perspective(id);
    if (p == null) return;
    final ctr = QuadGeometry.centroid(quadPixels(p));
    _replacePerspective(
      p.copyWith(
        corners: defaultQuad(
          SurveyPoint.fromPixels(ctr, imageSize),
          aspect: aspect,
        ),
        updatedAt: DateTime.now(),
      ),
    );
  });

  void setArtworkVisible(String id, bool show) => _act(() {
    final p = perspective(id);
    if (p != null) _replacePerspective(p.copyWith(showArtwork: show));
  });

  void relinkPerspective(String id, String unitId) => _act(() {
    final p = perspective(id);
    if (p != null) _replacePerspective(p.copyWith(unitId: unitId));
  });

  // ---------------------------------------------------------------------------
  // Placement markers
  // ---------------------------------------------------------------------------

  int _nextNumber(Iterable<int> used) =>
      used.fold<int>(0, (m, n) => math.max(m, n)) + 1;

  /// Primary marker of [unitId] on this photo (if any).
  PlacementMarker? primaryMarkerOf(String unitId) => _m.markers
      .where((m) => m.unitId == unitId && !m.isAlternative)
      .firstOrNull;

  /// Adds a marker. A second primary marker for the same item is refused
  /// ([MarkerAddResult.duplicatePrimary]) unless [alternative] is set, in
  /// which case it becomes "alternative placement 2, 3…".
  MarkerAddResult addMarker(
    String unitId,
    SurveyPoint at, {
    bool alternative = false,
    String mediaCode = '',
  }) {
    final hasPrimary = primaryMarkerOf(unitId) != null;
    if (hasPrimary && !alternative) return MarkerAddResult.duplicatePrimary;
    return _act(() {
      final placementNo = hasPrimary
          ? _m.markers
                    .where((m) => m.unitId == unitId)
                    .fold<int>(1, (mx, m) => math.max(mx, m.placementNo)) +
                1
          : 1;
      final m = PlacementMarker(
        id: _newId('pm'),
        photoId: photoId,
        unitId: unitId,
        number: _nextNumber(_m.markers.map((e) => e.number)),
        placementNo: placementNo,
        mediaCode: mediaCode,
        position: at.clamped(),
      );
      _m.markers.add(m);
      _selectedId = m.id;
      return MarkerAddResult.added;
    });
  }

  void _replaceMarker(PlacementMarker m) {
    final i = _m.markers.indexWhere((e) => e.id == m.id);
    if (i >= 0) _m.markers[i] = m;
  }

  void updateMarker(String id, {String? notes, String? unitId}) => _act(() {
    final m = marker(id);
    if (m == null) return;
    _replaceMarker(m.copyWith(notes: notes, unitId: unitId));
  });

  /// Explicit reorder: gives [id] the visible number [number] and swaps
  /// with the marker that had it. Numbers never change otherwise.
  void setMarkerNumber(String id, int number) => _act(() {
    final m = marker(id);
    if (m == null || number < 1 || number == m.number) return;
    final other = _m.markers.where((e) => e.number == number).firstOrNull;
    if (other != null) _replaceMarker(other.copyWith(number: m.number));
    _replaceMarker(m.copyWith(number: number));
  });

  // ---------------------------------------------------------------------------
  // Electrical
  // ---------------------------------------------------------------------------

  ElectricalMark addElectrical(
    ElectricalMarkKind kind,
    SurveyPoint at, {
    String notes = '',
    List<String> unitIds = const [],
  }) => _act(() {
    final e = ElectricalMark(
      id: _newId('em'),
      photoId: photoId,
      kind: kind,
      number: _nextNumber(
        _m.electrical.where((x) => x.kind == kind).map((x) => x.number),
      ),
      position: at.clamped(),
      notes: notes,
      unitIds: unitIds,
    );
    _m.electrical.add(e);
    _selectedId = e.id;
    return e;
  });

  void updateElectrical(String id, {String? notes, List<String>? unitIds}) =>
      _act(() {
        final i = _m.electrical.indexWhere((e) => e.id == id);
        if (i < 0) return;
        _m.electrical[i] = _m.electrical[i].copyWith(
          notes: notes,
          unitIds: unitIds,
        );
      });

  void updateCable(String id, {String? notes, List<String>? unitIds}) =>
      _act(() {
        final i = _m.cableRoutes.indexWhere((e) => e.id == id);
        if (i < 0) return;
        _m.cableRoutes[i] = _m.cableRoutes[i].copyWith(
          notes: notes,
          unitIds: unitIds,
        );
      });

  void addDraftPoint(SurveyPoint p) {
    draft.add(p.clamped());
    notifyListeners();
  }

  void removeLastDraftPoint() {
    if (draft.isNotEmpty) draft.removeLast();
    notifyListeners();
  }

  void cancelDraft() {
    draft.clear();
    notifyListeners();
  }

  /// Replaces the draft (used while dragging a rectangle / arrow).
  void setDraft(List<SurveyPoint> points) {
    draft
      ..clear()
      ..addAll(points);
    notifyListeners();
  }

  /// Finishes the drawn cable route (needs ≥ 2 points).
  CableRoute? finishCableRoute({List<String> unitIds = const []}) {
    if (draft.length < 2) return null;
    final pts = List.of(draft);
    draft.clear();
    return _act(() {
      final c = CableRoute(
        id: _newId('cr'),
        photoId: photoId,
        number: _nextNumber(_m.cableRoutes.map((e) => e.number)),
        points: pts,
        unitIds: unitIds,
      );
      _m.cableRoutes.add(c);
      _selectedId = c.id;
      return c;
    });
  }

  // ---------------------------------------------------------------------------
  // Obstructions
  // ---------------------------------------------------------------------------

  /// Adds an obstruction with the current type / shape / severity. Returns
  /// null when the points do not form a valid shape.
  ObstructionMark? addObstruction(
    List<SurveyPoint> points, {
    ObstructionType? type,
    ObstructionShape? shape,
    Severity? severity,
    String label = '',
    String remarks = '',
    List<String> unitIds = const [],
  }) {
    final s = shape ?? obstructionShape;
    if (points.length < s.minPoints) return null;
    if ((s == ObstructionShape.rect || s == ObstructionShape.arrow) &&
        (points[0].toPixels(imageSize) - points[1].toPixels(imageSize))
                .distance <
            math.min(imageSize.width, imageSize.height) * 0.01) {
      return null;
    }
    return _act(() {
      final o = ObstructionMark(
        id: _newId('ob'),
        photoId: photoId,
        type: type ?? obstructionType,
        shape: s,
        number: _nextNumber(_m.obstructions.map((e) => e.number)),
        points: [for (final p in points) p.clamped()],
        severity: severity ?? obstructionSeverity,
        label: label,
        remarks: remarks,
        unitIds: unitIds,
      );
      _m.obstructions.add(o);
      _selectedId = o.id;
      return o;
    });
  }

  /// Finishes a polygon obstruction from the draft (≥ 3 points).
  ObstructionMark? finishPolygon() {
    if (draft.length < 3) return null;
    final pts = List.of(draft);
    draft.clear();
    return addObstruction(pts, shape: ObstructionShape.polygon);
  }

  void updateObstruction(
    String id, {
    ObstructionType? type,
    Severity? severity,
    String? label,
    String? remarks,
    List<String>? unitIds,
    String? evidencePhotoId,
    bool clearEvidence = false,
  }) => _act(() {
    final i = _m.obstructions.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _m.obstructions[i] = _m.obstructions[i].copyWith(
      type: type,
      severity: severity,
      label: label,
      remarks: remarks,
      unitIds: unitIds,
      evidencePhotoId: evidencePhotoId,
      clearEvidence: clearEvidence,
    );
  });

  // ---------------------------------------------------------------------------
  // Moving & deleting
  // ---------------------------------------------------------------------------

  /// Moves the selected marking by [d] (normalised). Call inside a gesture.
  void translateSelected(SurveyPoint d) {
    final id = _selectedId;
    switch (kindOf(id)) {
      case MarkupKind.perspective:
        final p = perspective(id)!;
        _replacePerspective(
          p.copyWith(
            corners: [for (final c in p.corners) (c + d).clamped(0.25)],
            updatedAt: DateTime.now(),
          ),
        );
      case MarkupKind.marker:
        final m = marker(id)!;
        _replaceMarker(
          m.copyWith(
            position: (m.position + d).clamped(),
            shape: [for (final s in m.shape) (s + d).clamped()],
          ),
        );
      case MarkupKind.electrical:
        final i = _m.electrical.indexWhere((e) => e.id == id);
        _m.electrical[i] = _m.electrical[i].copyWith(
          position: (_m.electrical[i].position + d).clamped(),
        );
      case MarkupKind.cable:
        final i = _m.cableRoutes.indexWhere((e) => e.id == id);
        _m.cableRoutes[i] = _m.cableRoutes[i].copyWith(
          points: [for (final p in _m.cableRoutes[i].points) (p + d).clamped()],
        );
      case MarkupKind.obstruction:
        final i = _m.obstructions.indexWhere((e) => e.id == id);
        _m.obstructions[i] = _m.obstructions[i].copyWith(
          points: [
            for (final p in _m.obstructions[i].points) (p + d).clamped(),
          ],
        );
      case null:
        return;
    }
    _dirty = true;
    notifyListeners();
  }

  /// Deletes the selected marking only (other markings and the photo stay).
  void deleteSelected() => _act(() {
    final id = _selectedId;
    if (id == null) return;
    _m.perspectives.removeWhere((e) => e.id == id);
    _m.markers.removeWhere((e) => e.id == id);
    _m.electrical.removeWhere((e) => e.id == id);
    _m.cableRoutes.removeWhere((e) => e.id == id);
    _m.obstructions.removeWhere((e) => e.id == id);
    _selectedId = null;
  });

  // ---------------------------------------------------------------------------
  // Hit testing (box pixels; [box] = displayed photo size)
  // ---------------------------------------------------------------------------

  /// Corner of the selected perspective under [p] (0..3) or null.
  int? hitCorner(Offset p, Size box, double radius) {
    final pp = perspective(_selectedId);
    if (pp == null || hidden.contains(MarkupLayer.perspective)) return null;
    int? best;
    var bestD = radius;
    for (var i = 0; i < 4; i++) {
      final d = (pp.corners[i].toPixels(box) - p).distance;
      if (d <= bestD) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }

  static double _segDist(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }

  /// Topmost marking at [p] (markers, electrical, cables, perspective,
  /// obstructions – the drawing order reversed).
  String? hitTest(Offset p, Size box, double tolerance) {
    if (!hidden.contains(MarkupLayer.markers)) {
      for (final m in _m.markers.reversed) {
        if ((m.position.toPixels(box) - p).distance <= tolerance * 1.4) {
          return m.id;
        }
      }
    }
    if (!hidden.contains(MarkupLayer.electrical)) {
      for (final e in _m.electrical.reversed) {
        if ((e.position.toPixels(box) - p).distance <= tolerance * 1.3) {
          return e.id;
        }
      }
      for (final c in _m.cableRoutes.reversed) {
        final pts = [for (final x in c.points) x.toPixels(box)];
        for (var i = 0; i < pts.length - 1; i++) {
          if (_segDist(p, pts[i], pts[i + 1]) <= tolerance) return c.id;
        }
      }
    }
    if (!hidden.contains(MarkupLayer.perspective)) {
      for (final q in _m.perspectives.reversed) {
        final quad = [for (final c in q.corners) c.toPixels(box)];
        if (QuadGeometry.contains(quad, p)) return q.id;
        for (var i = 0; i < 4; i++) {
          if (_segDist(p, quad[i], quad[(i + 1) % 4]) <= tolerance) {
            return q.id;
          }
        }
      }
    }
    if (!hidden.contains(MarkupLayer.obstructions)) {
      for (final o in _m.obstructions.reversed) {
        final pts = [for (final x in o.points) x.toPixels(box)];
        final hit = switch (o.shape) {
          ObstructionShape.point ||
          ObstructionShape.text => (pts.first - p).distance <= tolerance * 1.5,
          ObstructionShape.rect => _inflate(
            pts[0],
            pts[1],
            tolerance,
          ).contains(p),
          ObstructionShape.polygon =>
            QuadGeometry.contains(pts, p) ||
                pts.any((x) => (x - p).distance <= tolerance),
          ObstructionShape.arrow => _segDist(p, pts[0], pts[1]) <= tolerance,
        };
        if (hit) return o.id;
      }
    }
    return null;
  }

  static _Box _inflate(Offset a, Offset b, double t) => _Box(
    math.min(a.dx, b.dx) - t,
    math.min(a.dy, b.dy) - t,
    math.max(a.dx, b.dx) + t,
    math.max(a.dy, b.dy) + t,
  );
}

class _Box {
  const _Box(this.l, this.t, this.r, this.b);

  final double l, t, r, b;

  bool contains(Offset p) => p.dx >= l && p.dx <= r && p.dy >= t && p.dy <= b;
}
