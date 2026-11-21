import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../data/models/models.dart';
import '../drawing/signage_geometry.dart';
import '../preview3d/scene3d.dart';
import '../preview3d/signage_scene_builder.dart';

/// Geometry of one signage unit (its own size / installation override).
SignageGeometry unitGeometry(Board b, SignageUnit u) {
  final tmp = Board(
    id: b.id,
    name: b.name,
    mediaCode: b.mediaCode,
    installationCode: b.installationOf(u),
    answers: b.answers,
    width: b.widthOf(u),
    height: b.heightOf(u),
    unit: b.unit,
    doubleSided: b.doubleSided,
  );
  return SignageGeometry.fromBoard(tmp, unit: u);
}

/// Fraction of the overlay box (smaller side) the renderer maps to the
/// scene radius – mirrors [ViewProjector]'s `0.42` so placement math stays
/// in sync with what is drawn.
const double kRendererFill = 0.42;

/// State of the Live Preview tab: models placed over a captured photo.
/// All values are photo-relative (see [PreviewOverlay]).
class LivePreviewController extends ChangeNotifier {
  LivePreviewController({
    required this.board,
    required this.photo,
    List<PreviewOverlay>? overlays,
    this.brand = 'ADINN',
  }) : overlays = overlays ?? [];

  final Board board;
  final SitePhoto photo;
  final String brand;
  final List<PreviewOverlay> overlays;

  int _selected = 0;
  bool showMeasurements = false;
  bool showModels = true;

  final Map<String, (SignageGeometry, Scene)> _scenes = {};

  static const minScale = 0.05;
  static const maxScale = 3.0;
  static const minPitch = -0.15;
  static const maxPitch = 0.9;

  int get selectedIndex =>
      overlays.isEmpty ? -1 : _selected.clamp(0, overlays.length - 1);

  PreviewOverlay? get selected =>
      overlays.isEmpty ? null : overlays[selectedIndex];

  Size get imageSize => Size(photo.width.toDouble(), photo.height.toDouble());

  SignageUnit? unitOf(PreviewOverlay o) => board.unitById(o.unitId);

  /// Model scene for an overlay (cached until the unit's geometry changes).
  Scene sceneFor(PreviewOverlay o) {
    final unit = unitOf(o) ?? board.units.first;
    final g = unitGeometry(board, unit);
    final cached = _scenes[unit.id];
    if (cached != null && cached.$1 == g) return cached.$2;
    final scene = SignageSceneBuilder.buildModel(
      g,
      brand: brand,
      dimensions: true,
    );
    _scenes[unit.id] = (g, scene);
    return scene;
  }

  /// Placement rectangle marked for [unitId] on this photo, if any.
  Annotation? placementFor(String unitId) {
    for (final a in photo.annotations.reversed) {
      if (a.type == AnnotationType.rectangle && a.itemId == unitId) return a;
    }
    return null;
  }

  /// Overlay whose board front exactly covers [rect] (photo pixels).
  PreviewOverlay fitToRect(String unitId, Rect rect) {
    final unit = board.unitById(unitId) ?? board.units.first;
    final g = unitGeometry(board, unit);
    final scene = sceneFor(PreviewOverlay(unitId: unit.id));
    final iw = imageSize.width;
    final boxPx = rect.width * scene.radius / (kRendererFill * g.widthFt);
    return PreviewOverlay(
      unitId: unit.id,
      cx: rect.center.dx / iw,
      cy: rect.center.dy / imageSize.height,
      scale: (boxPx / iw).clamp(minScale, maxScale).toDouble(),
      yaw: 0,
      pitch: 0,
    );
  }

  /// Default overlay for a unit: snapped to its marked placement rectangle
  /// when one exists, otherwise centred.
  PreviewOverlay defaultFor(String unitId, {int? index}) {
    final rect = placementFor(unitId);
    if (rect != null && rect.w > 0 && rect.h > 0 && rect.rotation == 0) {
      return fitToRect(
        unitId,
        Rect.fromCenter(
          center: Offset(rect.x, rect.y),
          width: rect.w,
          height: rect.h,
        ),
      );
    }
    final n = index ?? overlays.length;
    return PreviewOverlay(unitId: unitId, cx: 0.5 + 0.06 * (n % 4), cy: 0.45);
  }

  void addUnit(String unitId) {
    overlays.add(defaultFor(unitId));
    _selected = overlays.length - 1;
    notifyListeners();
  }

  void select(int index) {
    if (index < 0 || index >= overlays.length) return;
    _selected = index;
    notifyListeners();
  }

  void removeSelected() {
    if (overlays.isEmpty) return;
    overlays.removeAt(selectedIndex);
    _selected = math.max(0, _selected - 1);
    notifyListeners();
  }

  void _edit(void Function(PreviewOverlay o) f) {
    final o = selected;
    if (o == null) return;
    f(o);
    notifyListeners();
  }

  /// Moves by a photo-relative delta (fractions of width / height).
  void moveBy(Offset delta) => _edit((o) {
    o
      ..cx = (o.cx + delta.dx).clamp(-0.5, 1.5).toDouble()
      ..cy = (o.cy + delta.dy).clamp(-0.5, 1.5).toDouble();
  });

  void setPosition(double cx, double cy) => _edit((o) {
    o
      ..cx = cx.clamp(-0.5, 1.5).toDouble()
      ..cy = cy.clamp(-0.5, 1.5).toDouble();
  });

  void setScale(double s) =>
      _edit((o) => o.scale = s.clamp(minScale, maxScale).toDouble());

  void setRotation(double r) => _edit((o) {
    var a = r % (2 * math.pi);
    if (a > math.pi) a -= 2 * math.pi;
    o.rotation = a;
  });

  void setYaw(double y) => _edit((o) => o.yaw = y.clamp(-1.4, 1.4).toDouble());

  void setPitch(double p) =>
      _edit((o) => o.pitch = p.clamp(minPitch, maxPitch).toDouble());

  void setOpacity(double v) =>
      _edit((o) => o.opacity = v.clamp(0.1, 1).toDouble());

  void resetSelected() {
    final o = selected;
    if (o == null) return;
    overlays[selectedIndex] = defaultFor(o.unitId, index: selectedIndex);
    notifyListeners();
  }

  void toggleMeasurements() {
    showMeasurements = !showMeasurements;
    notifyListeners();
  }

  void toggleModels() {
    showModels = !showModels;
    notifyListeners();
  }

  /// Hit test (display coordinates of a photo shown at [display] size).
  int? overlayAt(Offset p, Size display) {
    for (var i = overlays.length - 1; i >= 0; i--) {
      final o = overlays[i];
      final side = o.scale * display.width;
      final c = Offset(o.cx * display.width, o.cy * display.height);
      final local = _rotate(p - c, -o.rotation);
      if (local.dx.abs() <= side / 2 && local.dy.abs() <= side / 2) return i;
    }
    return null;
  }

  static Offset _rotate(Offset p, double a) {
    final c = math.cos(a), s = math.sin(a);
    return Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c);
  }

  /// Metadata for "Save Live Preview".
  PreviewCapture toCapture({
    required String id,
    required Shop shop,
    required String path,
    required DateTime at,
  }) {
    final primary = selected?.unitId ?? board.units.first.id;
    return PreviewCapture(
      id: id,
      kind: CaptureKind.live,
      projectId: shop.projectId,
      taskId: shop.taskId,
      shopId: shop.id,
      groupId: board.id,
      unitId: primary,
      photoId: photo.id,
      path: path,
      createdAt: at,
      overlays: overlays.map((o) => o.copy()).toList(),
    );
  }

  /// Overlays of the latest saved Live Preview of this photo (restore).
  static List<PreviewOverlay>? restoreFrom(Board b, SitePhoto photo) {
    final saved = b.previews
        .where((c) => c.kind == CaptureKind.live && c.photoId == photo.id)
        .toList();
    if (saved.isEmpty) return null;
    saved.sort((a, c) => a.createdAt.compareTo(c.createdAt));
    final valid = saved.last.overlays
        .where((o) => b.unitById(o.unitId) != null)
        .map((o) => o.copy())
        .toList();
    return valid.isEmpty ? null : valid;
  }
}
