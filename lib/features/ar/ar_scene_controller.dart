import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import 'ar_model_builder.dart';
import 'ar_scene_engine.dart';
import 'ar_scene_items.dart';
import 'ar_session_controller.dart';

/// One editing tool is active at a time.
enum ArTool { none, move, rotate, scale, dimensions }

extension ArToolX on ArTool {
  String get label => switch (this) {
    ArTool.none => 'None',
    ArTool.move => 'Move',
    ArTool.rotate => 'Rotate',
    ArTool.scale => 'Scale',
    ArTool.dimensions => 'Dimensions',
  };
}

/// Anchor state of a scene object.
enum ArAnchorStatus {
  /// Not anchored yet (loaded layout, undo without a pose, …): needs a tap
  /// on a surface.
  pending,
  anchored,

  /// ARCore stopped tracking the anchor; the transform is kept and the
  /// object can be re-anchored.
  lost,
}

/// Rotation axis allowed for an object.
enum ArRotationAxis {
  /// Around the vertical axis (floor / ground / manual placement).
  yaw,

  /// Around the wall normal: the sign stays flat on the wall.
  roll,

  /// No rotation (flange boards stay perpendicular to the wall).
  none,
}

/// Direction of a fine move in the anchor frame.
enum ArMoveAxis { lateral, vertical, depth }

/// Visual state shown on the camera view.
enum ArSceneStatus {
  scanning,
  readyToPlace,
  modelSelected,
  modelMoving,
  trackingLost,
  idle,
}

extension ArSceneStatusX on ArSceneStatus {
  String get label => switch (this) {
    ArSceneStatus.scanning => 'Scanning surface',
    ArSceneStatus.readyToPlace => 'Ready to place',
    ArSceneStatus.modelSelected => 'Model selected',
    ArSceneStatus.modelMoving => 'Moving model',
    ArSceneStatus.trackingLost => 'Tracking lost',
    ArSceneStatus.idle => 'Tracking',
  };
}

/// Can an item be inserted as a new placement?
enum ArInsertCheck {
  ok,

  /// The signage unit is already in the scene (a second copy would only be a
  /// preview duplicate).
  alreadyPlaced,

  /// No 3D model can be generated (media / installation not set).
  unavailable,

  /// The AR engine can only show one model.
  engineLimit,
}

/// One inserted model instance in the AR scene. [placementId] is the AR
/// Placement ID; [unitId] is the business Signage Item ID it shows.
@immutable
class ArPlacement {
  const ArPlacement({
    required this.placementId,
    required this.unitId,
    required this.groupId,
    required this.mediaCode,
    required this.installationCode,
    required this.label,
    required this.widthFt,
    required this.heightFt,
    this.sizeText = '',
    this.preferVertical = false,
    this.doubleSided = false,
    this.isFlange = false,
    this.previewDuplicate = false,
    this.duplicateOf,
    this.transform = const ArObjectTransform(),
    this.visible = true,
    this.locked = false,
    this.status = ArAnchorStatus.pending,
    this.surface,
    this.pose,
  });

  factory ArPlacement.fromItem(
    ArSceneItem item,
    String placementId, {
    bool previewDuplicate = false,
    String? duplicateOf,
    ArObjectTransform transform = const ArObjectTransform(),
  }) => ArPlacement(
    placementId: placementId,
    unitId: item.unitId,
    groupId: item.groupId,
    mediaCode: item.mediaCode,
    installationCode: item.installationCode,
    label: item.label,
    widthFt: item.widthFt,
    heightFt: item.heightFt,
    sizeText: item.sizeText,
    preferVertical: item.preferVertical,
    doubleSided: item.doubleSided,
    isFlange: item.isFlange,
    previewDuplicate: previewDuplicate,
    duplicateOf: duplicateOf,
    transform: transform,
  );

  final String placementId;
  final String unitId;
  final String groupId;
  final String mediaCode;
  final String installationCode;
  final String label;
  final double widthFt;
  final double heightFt;
  final String sizeText;
  final bool preferVertical;
  final bool doubleSided;
  final bool isFlange;
  final bool previewDuplicate;
  final String? duplicateOf;
  final ArObjectTransform transform;
  final bool visible;
  final bool locked;
  final ArAnchorStatus status;

  /// "vertical", "horizontal" or "manual" once anchored.
  final String? surface;

  /// World pose of the anchor in this session (undo / duplicate only).
  final List<double>? pose;

  String get id => placementId;
  bool get isAnchored => status == ArAnchorStatus.anchored;

  String get displayName =>
      previewDuplicate ? '$label – Preview Duplicate' : label;

  /// Wall-like frame: x along the surface, y up, z out of the surface.
  bool get onWall =>
      surface == 'vertical' ||
      surface == 'manual' ||
      (surface == null && preferVertical);

  ArRotationAxis get rotationAxis {
    if (isFlange && surface != 'horizontal') return ArRotationAxis.none;
    if (surface == 'vertical' || (surface == null && preferVertical)) {
      return ArRotationAxis.roll;
    }
    return ArRotationAxis.yaw;
  }

  /// Current rotation (radians) around [rotationAxis].
  double get rotation => switch (rotationAxis) {
    ArRotationAxis.roll => transform.roll,
    ArRotationAxis.yaw => transform.yaw,
    ArRotationAxis.none => 0,
  };

  double get rotationDeg => rotation * 180 / math.pi;

  ArPlacement copyWith({
    String? placementId,
    String? label,
    double? widthFt,
    double? heightFt,
    String? sizeText,
    String? installationCode,
    bool? preferVertical,
    bool? doubleSided,
    bool? isFlange,
    bool? previewDuplicate,
    String? duplicateOf,
    ArObjectTransform? transform,
    bool? visible,
    bool? locked,
    ArAnchorStatus? status,
    String? surface,
    List<double>? pose,
    bool clearPose = false,
  }) => ArPlacement(
    placementId: placementId ?? this.placementId,
    unitId: unitId,
    groupId: groupId,
    mediaCode: mediaCode,
    installationCode: installationCode ?? this.installationCode,
    label: label ?? this.label,
    widthFt: widthFt ?? this.widthFt,
    heightFt: heightFt ?? this.heightFt,
    sizeText: sizeText ?? this.sizeText,
    preferVertical: preferVertical ?? this.preferVertical,
    doubleSided: doubleSided ?? this.doubleSided,
    isFlange: isFlange ?? this.isFlange,
    previewDuplicate: previewDuplicate ?? this.previewDuplicate,
    duplicateOf: duplicateOf ?? this.duplicateOf,
    transform: transform ?? this.transform,
    visible: visible ?? this.visible,
    locked: locked ?? this.locked,
    status: status ?? this.status,
    surface: surface ?? this.surface,
    pose: clearPose ? null : (pose ?? this.pose),
  );
}

/// One undoable AR edit (never part of the recce approval history).
class ArHistoryEntry {
  ArHistoryEntry(
    this.label,
    this.before,
    this.after,
    this.selectedBefore,
    this.selectedAfter,
  );

  final String label;
  final List<ArPlacement> before;
  final List<ArPlacement> after;
  final String? selectedBefore;
  final String? selectedAfter;
}

/// Outcome of loading a saved layout.
@immutable
class ArLayoutLoadResult {
  const ArLayoutLoadResult({required this.loaded, required this.missing});

  final int loaded;

  /// Signage Item IDs referenced by the layout that no longer exist.
  final List<String> missing;
}

/// State of the multi-object Camera AR editor. Pure Dart: every engine call
/// goes through [ArSceneEngine], so it is unit-testable with a fake engine
/// (no camera, no ARCore).
class ArSceneController extends ChangeNotifier {
  ArSceneController({
    required this.engine,
    required this.session,
    this.initialItem,
    this.initialTransform = const ArObjectTransform(),
    String Function()? newPlacementId,
    DateTime Function()? clock,
    this.maxHistory = 50,
  }) : _newId = newPlacementId ?? (() => newId('arp')),
       _clock = clock ?? DateTime.now {
    _events = session.platform.events.listen(_onEvent);
    _lastPhase = session.phase;
    session.addListener(_onSession);
    if (session.sessionRunning) _onSessionStarted();
  }

  final ArSceneEngine engine;
  final ArSessionController session;
  final int maxHistory;
  final String Function() _newId;
  final DateTime Function() _clock;

  /// Item the screen was opened for: armed for placement when the session
  /// starts (the original one-tap flow).
  final ArSceneItem? initialItem;
  final ArObjectTransform initialTransform;
  bool _initialArmed = false;

  StreamSubscription<ArEvent>? _events;
  ArPhase _lastPhase = ArPhase.idle;
  bool _disposed = false;

  final List<ArPlacement> _placements = [];
  final Map<String, ArSceneItem> _items = {};
  final Map<String, Object> _registered = {};
  String? _selectedId;
  ArTool _tool = ArTool.none;

  ArSceneItem? _armedItem;
  bool _armedDuplicate = false;
  ArObjectTransform _armedTransform = const ArObjectTransform();
  String? _reanchorId;
  bool _reticleHit = false;
  String? _lastPlaceFailure;

  bool _moving = false;
  bool _dragBusy = false;
  Offset? _dragQueued;

  final List<ArHistoryEntry> _undo = [];
  final List<ArHistoryEntry> _redo = [];
  List<ArPlacement>? _gestureBefore;
  String? _gestureSelected;

  final Set<String> _inflight = {};
  final Set<String> _dirty = {};

  String? _message;
  bool freeAdjust = false;
  bool fineSteps = false;

  /// Fine move step (metres).
  double moveStep = 0.05;

  /// Saved layout this scene was loaded from / saved to.
  String? layoutId;
  String? layoutName;

  // ---------------------------------------------------------------------------
  // Read-only state
  // ---------------------------------------------------------------------------

  List<ArPlacement> get placements => List.unmodifiable(_placements);
  ArTool get tool => _tool;
  String? get selectedId => _selectedId;
  ArPlacement? get selected => byId(_selectedId);
  ArSceneItem? get armedItem => _armedItem;
  bool get armedDuplicate => _armedDuplicate;
  String? get reanchorId => _reanchorId;
  ArPlacement? get reanchorTarget => byId(_reanchorId);
  bool get awaitingPlacement => _armedItem != null || _reanchorId != null;
  bool get moving => _moving;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;
  List<ArHistoryEntry> get history => List.unmodifiable(_undo);
  String? get message => _message;

  /// Last failed placement reason (e.g. no_surface) – drives the fallback.
  String? get lastPlaceFailure => _lastPlaceFailure;
  bool get initialArmed => _initialArmed;
  Map<String, ArSceneItem> get items => Map.unmodifiable(_items);
  ArSceneItem? item(String unitId) => _items[unitId];

  ArPlacement? byId(String? id) {
    if (id == null) return null;
    for (final p in _placements) {
      if (p.placementId == id) return p;
    }
    return null;
  }

  /// Placements of one signage item (primary + preview duplicates).
  List<ArPlacement> placementsOf(String unitId) =>
      _placements.where((p) => p.unitId == unitId).toList();

  /// Visible anchored objects (what a capture shows).
  List<ArPlacement> get visibleAnchored =>
      _placements.where((p) => p.isAnchored && p.visible).toList();

  List<ArPlacement> get needsAnchor =>
      _placements.where((p) => !p.isAnchored).toList();

  /// Physical units represented in the scene (duplicates excluded).
  int get physicalUnitCount => _placements
      .where((p) => !p.previewDuplicate)
      .map((p) => p.unitId)
      .toSet()
      .length;

  bool get trackingLost => session.trackingLost;

  ArSceneStatus get status {
    if (session.trackingLost) return ArSceneStatus.trackingLost;
    if (_moving) return ArSceneStatus.modelMoving;
    if (awaitingPlacement) {
      return _reticleHit || _wantedPlanes > 0
          ? ArSceneStatus.readyToPlace
          : ArSceneStatus.scanning;
    }
    if (selected != null) return ArSceneStatus.modelSelected;
    return _placements.isEmpty ? ArSceneStatus.scanning : ArSceneStatus.idle;
  }

  bool get _placingVertical =>
      _armedItem?.preferVertical ?? reanchorTarget?.preferVertical ?? false;

  int get _wantedPlanes =>
      _placingVertical ? session.verticalPlanes : session.horizontalPlanes;

  /// Instruction for the camera view (null = nothing to say).
  String? get guidance {
    if (!session.sessionRunning) return null;
    if (session.trackingLost) return session.guidance;
    final target = _armedItem?.label ?? reanchorTarget?.displayName;
    if (target != null) {
      final wall = _placingVertical;
      if (session.horizontalPlanes + session.verticalPlanes == 0) {
        return 'Move your phone slowly to scan the area. '
            '${wall ? 'Point your camera toward the wall.' : 'Point your camera toward the ground.'}';
      }
      if (_wantedPlanes == 0 && !_reticleHit) {
        return wall
            ? 'Point your camera toward the wall to place $target.'
            : 'Point your camera toward the ground to place $target.';
      }
      return _reanchorId != null
          ? 'Tap a surface to re-anchor $target.'
          : 'Tap the surface to place $target.';
    }
    if (_placements.isEmpty) return 'Tap “Insert” to add a signage model.';
    if (selected == null) return 'Tap a model to select it.';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _say(String? m) {
    _message = m;
    _notify();
  }

  void clearMessage() {
    if (_message == null) return;
    _message = null;
    _notify();
  }

  List<ArPlacement> _snapshot() => List.of(_placements);

  int _indexOf(String id) => _placements.indexWhere((p) => p.placementId == id);

  void _replace(ArPlacement p) {
    final i = _indexOf(p.placementId);
    if (i >= 0) _placements[i] = p;
  }

  static bool _sameList(List<ArPlacement> a, List<ArPlacement> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.placementId != y.placementId ||
          x.transform != y.transform ||
          x.status != y.status ||
          !listEquals(x.pose, y.pose)) {
        return false;
      }
    }
    return true;
  }

  void _record(String label, List<ArPlacement> before, String? selBefore) {
    final after = _snapshot();
    if (_sameList(before, after)) return;
    _undo.add(ArHistoryEntry(label, before, after, selBefore, _selectedId));
    if (_undo.length > maxHistory) _undo.removeAt(0);
    _redo.clear();
  }

  /// Sends the latest transform of [id] to the engine. Calls made while one
  /// is in flight are coalesced (sliders / pinch never queue a backlog).
  Future<void> _push(String id) async {
    if (_inflight.contains(id)) {
      _dirty.add(id);
      return;
    }
    _inflight.add(id);
    try {
      do {
        _dirty.remove(id);
        final p = byId(id);
        if (p == null || _disposed) break;
        await engine.setObjectTransform(id, p.transform);
      } while (_dirty.contains(id) && !_disposed);
    } finally {
      _inflight.remove(id);
    }
  }

  void _syncSession() {
    final shown = visibleAnchored;
    final primary =
        selected != null && selected!.isAnchored && selected!.visible
        ? selected!
        : (shown.isEmpty ? null : shown.first);
    session.syncScenePlaced(shown.isNotEmpty, surface: primary?.surface);
  }

  Future<bool> _ensureModel(String unitId) async {
    final item = _items[unitId];
    if (item == null || !item.modelAvailable) return false;
    if (_registered[unitId] == item.signature) return true;
    final ArModelData data;
    try {
      data = item.buildModel();
    } catch (_) {
      return false;
    }
    if (data.faces.isEmpty) return false;
    final ok = await engine.registerModel(unitId, data);
    if (ok) _registered[unitId] = item.signature;
    return ok;
  }

  Future<void> _indicator() => engine.setPlacementIndicator(
    awaitingPlacement,
    preferVertical: _placingVertical,
  );

  // ---------------------------------------------------------------------------
  // Session / engine events
  // ---------------------------------------------------------------------------

  void _onSession() {
    final phase = session.phase;
    final previous = _lastPhase;
    _lastPhase = phase;
    if (phase == ArPhase.starting && previous != ArPhase.starting) {
      // A new native session: anchors and uploaded models are gone.
      _registered.clear();
      for (var i = 0; i < _placements.length; i++) {
        final p = _placements[i];
        if (p.isAnchored) {
          _placements[i] = p.copyWith(
            status: ArAnchorStatus.pending,
            clearPose: true,
          );
        }
      }
    }
    if (previous == ArPhase.starting &&
        (phase == ArPhase.scanning || phase == ArPhase.placed)) {
      _onSessionStarted();
    }
    _notify();
  }

  void _onSessionStarted() {
    if (!_initialArmed && _placements.isEmpty && initialItem != null) {
      _initialArmed = true;
      final item = _items[initialItem!.unitId] ?? initialItem!;
      _items.putIfAbsent(item.unitId, () => item);
      if (item.modelAvailable) {
        armInsert(item, initialTransform: initialTransform);
        return;
      }
    }
    if (!awaitingPlacement && needsAnchor.isNotEmpty) {
      requestReanchor(needsAnchor.first.placementId);
    } else {
      _indicator();
    }
  }

  void _onEvent(ArEvent e) {
    if (_disposed) return;
    switch (e.type) {
      case 'objectLost':
        final p = byId('${e.data['id']}');
        if (p == null || !p.isAnchored) return;
        _replace(p.copyWith(status: ArAnchorStatus.lost, clearPose: true));
        _syncSession();
        _say(
          '${p.displayName} lost tracking. Select it and tap Re-anchor '
          '(its scale and rotation are kept).',
        );
      case 'anchorLost':
        if (engine.supportsMultipleObjects) return;
        var any = false;
        for (var i = 0; i < _placements.length; i++) {
          if (_placements[i].isAnchored) {
            _placements[i] = _placements[i].copyWith(
              status: ArAnchorStatus.lost,
              clearPose: true,
            );
            any = true;
          }
        }
        if (any) {
          _syncSession();
          _notify();
        }
      case 'reticle':
        final hit = e.data['hit'] == true;
        if (hit != _reticleHit) {
          _reticleHit = hit;
          _notify();
        }
      case 'tracking':
        // Tracking lost mid-drag: keep the last valid pose, end the gesture.
        if (_moving && '${e.data['state']}' != 'tracking') endDrag();
    }
  }

  // ---------------------------------------------------------------------------
  // Items (business records, read-only)
  // ---------------------------------------------------------------------------

  /// Updates the insertable items (call when the recce changes). Models of
  /// items whose dimensions / installation changed are regenerated;
  /// placements of items that no longer exist are removed safely.
  Future<void> setItems(List<ArSceneItem> items) async {
    _items
      ..clear()
      ..addEntries(items.map((i) => MapEntry(i.unitId, i)));
    final missing = _placements
        .where((p) => !_items.containsKey(p.unitId))
        .toList();
    for (final p in missing) {
      await engine.removeObject(p.placementId);
      _placements.remove(p);
    }
    if (missing.isNotEmpty) {
      // History entries may point at removed items: start a clean history.
      _undo.clear();
      _redo.clear();
      if (!_placements.any((p) => p.placementId == _selectedId)) {
        _selectedId = null;
        await engine.selectObject(null);
      }
      _message =
          '${missing.length} placement(s) removed: the signage item no longer '
          'exists in this recce.';
    }
    if (_armedItem != null && !_items.containsKey(_armedItem!.unitId)) {
      _armedItem = null;
      await _indicator();
    } else if (_armedItem != null) {
      _armedItem = _items[_armedItem!.unitId];
    }
    for (var i = 0; i < _placements.length; i++) {
      final p = _placements[i];
      final item = _items[p.unitId]!;
      _placements[i] = p.copyWith(
        label: item.label,
        widthFt: item.widthFt,
        heightFt: item.heightFt,
        sizeText: item.sizeText,
        installationCode: item.installationCode,
        preferVertical: item.preferVertical,
        doubleSided: item.doubleSided,
        isFlange: item.isFlange,
      );
    }
    // Regenerate models whose geometry changed (only items in the scene).
    for (final key in _registered.keys.toList()) {
      final item = _items[key];
      if (item == null) {
        _registered.remove(key);
      } else if (_registered[key] != item.signature &&
          _placements.any((p) => p.unitId == key)) {
        await _ensureModel(key);
      }
    }
    _syncSession();
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Insert / place / re-anchor
  // ---------------------------------------------------------------------------

  ArInsertCheck checkInsert(ArSceneItem item) {
    if (!item.modelAvailable) return ArInsertCheck.unavailable;
    final placed = _placements.any(
      (p) => p.unitId == item.unitId && !p.previewDuplicate,
    );
    if (!engine.supportsMultipleObjects && _placements.isNotEmpty) {
      return placed ? ArInsertCheck.alreadyPlaced : ArInsertCheck.engineLimit;
    }
    return placed ? ArInsertCheck.alreadyPlaced : ArInsertCheck.ok;
  }

  /// Keeps [item] ready for placement: the next tap on a surface anchors
  /// it. [previewDuplicate] must be chosen explicitly for an item that is
  /// already in the scene.
  void armInsert(
    ArSceneItem item, {
    bool previewDuplicate = false,
    ArObjectTransform initialTransform = const ArObjectTransform(),
  }) {
    _items.putIfAbsent(item.unitId, () => item);
    _endGesture();
    _armedItem = item;
    _armedDuplicate = previewDuplicate;
    _armedTransform = initialTransform;
    _reanchorId = null;
    _lastPlaceFailure = null;
    _message = null;
    session.clearError();
    _indicator();
    _notify();
  }

  void cancelPlacement() {
    if (!awaitingPlacement) return;
    _armedItem = null;
    _reanchorId = null;
    _indicator();
    _notify();
  }

  /// Arms re-anchoring of an existing placement (moved / lost / loaded).
  bool requestReanchor([String? id]) {
    final p = byId(id ?? _selectedId);
    if (p == null) {
      _say('Select a model first.');
      return false;
    }
    if (p.locked && p.isAnchored) {
      _say('${p.displayName} is locked. Unlock it to re-anchor.');
      return false;
    }
    _endGesture();
    _armedItem = null;
    _reanchorId = p.placementId;
    _lastPlaceFailure = null;
    _selectedId = p.placementId;
    engine.selectObject(p.placementId);
    _indicator();
    _notify();
    return true;
  }

  String _placeFailure(String? reason, bool wall) => switch (reason) {
    'not_tracking' => 'Tracking lost. Move the phone slowly, then tap again.',
    'single_object' =>
      'This AR engine can show only the signage item it was opened with.',
    'no_model' || 'model' => 'The 3D model could not be loaded.',
    'timeout' => 'The AR engine did not respond. Try again.',
    _ =>
      wall
          ? 'No wall found there. Point your camera toward the wall and move '
                'slowly, place without a surface, or use Live Preview.'
          : 'No floor found there. Point your camera toward the ground and '
                'move slowly, or use Live Preview.',
  };

  /// Routes a tap on the camera view: place the armed item, re-anchor,
  /// select the tapped model, or (Move tool) re-anchor the selection.
  Future<bool> handleTap(Offset point) async {
    if (!session.sessionRunning || _disposed) return false;
    if (session.trackingLost) {
      _say('Tracking lost. Move the phone slowly before placing.');
      return false;
    }
    if (_armedItem != null) return _placeArmed(point);
    if (_reanchorId != null) return _reanchorAt(_reanchorId!, point);
    final hit = await engine.hitTestObject(point);
    if (_disposed) return false;
    if (hit != null && byId(hit) != null) {
      select(hit);
      return true;
    }
    final sel = selected;
    if (_tool == ArTool.move && sel != null) {
      if (sel.locked) {
        _say('${sel.displayName} is locked. Unlock it to move.');
        return false;
      }
      return _reanchorAt(sel.placementId, point, label: 'Move');
    }
    return false;
  }

  Future<bool> _placeArmed(Offset point) async {
    final item = _armedItem!;
    final duplicate = _armedDuplicate;
    final transform = _armedTransform;
    if (!await _ensureModel(item.unitId)) {
      _say(
        engine.supportsMultipleObjects
            ? 'The 3D model for ${item.label} could not be loaded.'
            : 'This AR engine can show only the signage item it was opened '
                  'with.',
      );
      return false;
    }
    final id = _newId();
    final before = _snapshot();
    final selBefore = _selectedId;
    final r = await engine.placeObject(
      id,
      item.unitId,
      point,
      manual: session.manualPlacement,
    );
    if (_disposed) return r.placed;
    if (!r.placed) {
      _lastPlaceFailure = r.reason ?? 'no_surface';
      _say(_placeFailure(r.reason, item.preferVertical));
      return false;
    }
    final source = duplicate ? placementsOf(item.unitId).firstOrNull : null;
    final p =
        ArPlacement.fromItem(
          item,
          id,
          previewDuplicate: duplicate,
          duplicateOf: source?.placementId,
          transform: transform,
        ).copyWith(
          status: ArAnchorStatus.anchored,
          surface: r.surface,
          pose: r.pose,
        );
    _placements.add(p);
    _armedItem = null;
    _lastPlaceFailure = null;
    _message = null;
    _selectedId = id;
    await _push(id);
    await engine.selectObject(id);
    await _indicator();
    _record(
      duplicate ? 'Insert preview duplicate' : 'Insert ${item.label}',
      before,
      selBefore,
    );
    _syncSession();
    _notify();
    return true;
  }

  Future<bool> _reanchorAt(String id, Offset point, {String? label}) async {
    final p = byId(id);
    if (p == null) {
      _reanchorId = null;
      _notify();
      return false;
    }
    if (!await _ensureModel(p.unitId)) {
      _say('The 3D model for ${p.label} could not be loaded.');
      return false;
    }
    final before = _snapshot();
    final selBefore = _selectedId;
    final r = await engine.placeObject(
      id,
      p.unitId,
      point,
      manual: session.manualPlacement,
    );
    if (_disposed) return r.placed;
    if (!r.placed) {
      _lastPlaceFailure = r.reason ?? 'no_surface';
      _say(_placeFailure(r.reason, p.preferVertical));
      return false;
    }
    final wasPending = !p.isAnchored;
    _replace(
      p.copyWith(
        status: ArAnchorStatus.anchored,
        surface: r.surface,
        pose: r.pose,
        clearPose: r.pose == null,
      ),
    );
    await _push(id);
    if (!p.visible) await engine.setObjectVisible(id, false);
    _selectedId = id;
    await engine.selectObject(id);
    _lastPlaceFailure = null;
    _message = null;
    if (_reanchorId == id) {
      _reanchorId = null;
      // Loaded layout: continue with the next object that needs a surface.
      final next = needsAnchor.firstOrNull;
      if (wasPending && next != null) _reanchorId = next.placementId;
    }
    await _indicator();
    _record(label ?? 'Re-anchor ${p.displayName}', before, selBefore);
    _syncSession();
    _notify();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Selection, tools, visibility, lock
  // ---------------------------------------------------------------------------

  void select(String? id) {
    if (id != null && byId(id) == null) return;
    _endGesture();
    _selectedId = id;
    engine.selectObject(id);
    _syncSession();
    _notify();
  }

  /// Switching tools never modifies the selected model.
  void setTool(ArTool t) {
    _endGesture();
    _tool = _tool == t ? ArTool.none : t;
    _notify();
  }

  Future<void> setVisible(String id, bool visible) async {
    final p = byId(id);
    if (p == null || p.visible == visible) return;
    _replace(p.copyWith(visible: visible));
    await engine.setObjectVisible(id, visible);
    _syncSession();
    _notify();
  }

  void setLocked(String id, bool locked) {
    final p = byId(id);
    if (p == null || p.locked == locked) return;
    if (_moving && _selectedId == id) endDrag();
    _replace(p.copyWith(locked: locked));
    _notify();
  }

  void setFreeAdjust(bool v) {
    freeAdjust = v;
    _notify();
  }

  void setFineSteps(bool v) {
    fineSteps = v;
    _notify();
  }

  void setMoveStep(double metres) {
    moveStep = metres;
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Transform edits
  // ---------------------------------------------------------------------------

  /// Why the selected object cannot be edited (null = editable).
  String? get editBlockedReason {
    final p = selected;
    if (p == null) return 'Select a model to edit it.';
    if (p.locked) return '${p.displayName} is locked. Unlock it to edit.';
    if (session.trackingLost) return 'Tracking lost – edits are paused.';
    return null;
  }

  bool get canEditSelected => editBlockedReason == null;

  /// Starts a continuous gesture (pinch, drag, slider): the whole gesture
  /// becomes one undo step in [endGesture].
  void beginGesture() {
    if (_gestureBefore != null) return;
    _gestureBefore = _snapshot();
    _gestureSelected = _selectedId;
  }

  void endGesture(String label) {
    final before = _gestureBefore;
    if (before == null) return;
    _gestureBefore = null;
    _record(label, before, _gestureSelected);
    _notify();
  }

  void _endGesture() {
    if (_moving) {
      _moving = false;
      _dragQueued = null;
    }
    if (_gestureBefore != null) endGesture('Edit');
  }

  Future<bool> _edit(
    String label,
    ArObjectTransform Function(ArPlacement p) change,
  ) async {
    final reason = editBlockedReason;
    if (reason != null) {
      _say(reason);
      return false;
    }
    final p = selected!;
    final t = change(p);
    if (t == p.transform) return false;
    final record = _gestureBefore == null;
    final before = record ? _snapshot() : null;
    _replace(p.copyWith(transform: t));
    _message = null;
    _notify();
    await _push(p.placementId);
    if (before != null) _record(label, before, _selectedId);
    _notify();
    return true;
  }

  // Scale ---------------------------------------------------------------------

  double get scaleStep => fineSteps ? 0.01 : 0.05;

  Future<bool> setScale(double scale) =>
      _edit('Scale', (p) => p.transform.copyWith(scale: scale));

  Future<bool> scaleBy(double factor) => _edit(
    'Scale',
    (p) => p.transform.copyWith(scale: p.transform.scale * factor),
  );

  /// Plus / minus buttons (5 % or 1 % steps, snapped to the step grid).
  Future<bool> stepScale(int direction) => _edit('Scale', (p) {
    final step = scaleStep;
    final steps = p.transform.scale / step;
    final k = direction > 0
        ? (steps + 1e-6).floor() + 1
        : (steps - 1e-6).ceil() - 1;
    return p.transform.copyWith(scale: _round(k * step));
  });

  /// Back to the entered physical size; position and rotation are kept.
  Future<bool> resetScale() =>
      _edit('Reset scale', (p) => p.transform.copyWith(scale: 1));

  /// Rebuilds the model from the signage item's current dimensions and
  /// shows it at actual size (100 %).
  Future<bool> fitToDimensions() async {
    final p = selected;
    if (p == null) {
      _say('Select a model to edit it.');
      return false;
    }
    await _ensureModel(p.unitId);
    if (p.transform.scale == 1) {
      _say('${p.displayName} is already at its entered size (${p.sizeText}).');
      return true;
    }
    return _edit('Fit to dimensions', (p) => p.transform.copyWith(scale: 1));
  }

  /// Validates a typed percentage (10–300). Returns an error or null.
  static String? validateScaleInput(String text) {
    final v = double.tryParse(text.trim().replaceAll('%', ''));
    if (v == null || !v.isFinite) return 'Enter a number, e.g. 120';
    final min = ArObjectTransform.minScale * 100;
    final max = ArObjectTransform.maxScale * 100;
    if (v < min || v > max) {
      return 'Scale must be ${min.round()}–${max.round()} %';
    }
    return null;
  }

  /// Applies a typed percentage. Returns an error message or null.
  Future<String?> setScalePercentText(String text) async {
    final error = validateScaleInput(text);
    if (error != null) return error;
    final v = double.parse(text.trim().replaceAll('%', ''));
    await setScale(v / 100);
    return editBlockedReason;
  }

  // Rotation ------------------------------------------------------------------

  double get rotationStepDeg => fineSteps ? 1 : 5;

  ArObjectTransform _withRotation(ArPlacement p, double radians) =>
      switch (p.rotationAxis) {
        ArRotationAxis.roll => p.transform.copyWith(roll: radians),
        ArRotationAxis.yaw => p.transform.copyWith(yaw: radians),
        ArRotationAxis.none => p.transform,
      };

  String? _rotationBlocked() {
    final p = selected;
    if (p != null && p.rotationAxis == ArRotationAxis.none) {
      return 'Flange boards stay perpendicular to the wall: rotation is '
          'disabled.';
    }
    return null;
  }

  Future<bool> rotateByRadians(double radians) {
    final blocked = _rotationBlocked();
    if (blocked != null) {
      _say(blocked);
      return Future.value(false);
    }
    return _edit('Rotate', (p) => _withRotation(p, p.rotation + radians));
  }

  Future<bool> rotateByDegrees(double degrees) =>
      rotateByRadians(degrees * math.pi / 180);

  /// Clockwise (+1) / counter-clockwise (-1) by the current step.
  Future<bool> stepRotation(int direction) =>
      rotateByDegrees(-direction * rotationStepDeg);

  Future<bool> setRotationDegrees(double degrees) {
    final blocked = _rotationBlocked();
    if (blocked != null) {
      _say(blocked);
      return Future.value(false);
    }
    return _edit('Rotate', (p) => _withRotation(p, degrees * math.pi / 180));
  }

  static String? validateRotationInput(String text) {
    final v = double.tryParse(text.trim().replaceAll('°', ''));
    if (v == null || !v.isFinite) return 'Enter degrees, e.g. 45';
    if (v < -180 || v > 180) return 'Rotation must be -180° to 180°';
    return null;
  }

  Future<String?> setRotationText(String text) async {
    final error = validateRotationInput(text);
    if (error != null) return error;
    await setRotationDegrees(double.parse(text.trim().replaceAll('°', '')));
    return editBlockedReason;
  }

  Future<bool> resetRotation() =>
      _edit('Reset rotation', (p) => p.transform.copyWith(yaw: 0, roll: 0));

  /// Double-sided standee: turn 180° to view the other face.
  Future<bool> flipFace() {
    final p = selected;
    if (p == null || !p.doubleSided) {
      _say('Only double-sided signage has a second face.');
      return Future.value(false);
    }
    return _edit(
      'Show other face',
      (p) => p.transform.copyWith(yaw: p.transform.yaw + math.pi),
    );
  }

  // Move ----------------------------------------------------------------------

  /// Axes the selected object may move along (anchor frame).
  Set<ArMoveAxis> allowedMoveAxes([ArPlacement? p]) {
    p ??= selected;
    if (p == null) return const {};
    return p.onWall
        ? {
            ArMoveAxis.lateral,
            ArMoveAxis.vertical,
            if (freeAdjust) ArMoveAxis.depth,
          }
        : {
            ArMoveAxis.lateral,
            ArMoveAxis.depth,
            if (freeAdjust) ArMoveAxis.vertical,
          };
  }

  /// Fine move by [direction] × [moveStep] along [axis]. Wall signs stay on
  /// their wall (depth) and ground signs on the ground (height) unless free
  /// adjustment is enabled.
  Future<bool> nudge(ArMoveAxis axis, int direction) {
    if (!allowedMoveAxes().contains(axis)) {
      _say('Enable “Free adjustment” to move off the placement surface.');
      return Future.value(false);
    }
    final d = direction * moveStep;
    return _edit('Move', (p) {
      final t = p.transform;
      return switch (axis) {
        ArMoveAxis.lateral => t.copyWith(x: _round(t.x + d)),
        ArMoveAxis.vertical => t.copyWith(y: _round(t.y + d)),
        ArMoveAxis.depth => t.copyWith(z: _round(t.z + d)),
      };
    });
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(4));

  /// Clears the fine offsets (anchor, rotation and scale kept).
  Future<bool> resetPosition() =>
      _edit('Reset position', (p) => p.transform.copyWith(x: 0, y: 0, z: 0));

  /// Drag-to-move (Move tool): re-anchors under the finger with AR hit
  /// tests. The whole drag is one undo step.
  bool beginDrag() {
    final reason = editBlockedReason;
    if (reason != null) {
      _say(reason);
      return false;
    }
    if (!selected!.isAnchored) {
      _say('Re-anchor ${selected!.displayName} first.');
      return false;
    }
    if (!_moving) {
      _moving = true;
      beginGesture();
      _notify();
    }
    return true;
  }

  Future<void> dragTo(Offset point) async {
    if (!_moving) return;
    if (_dragBusy) {
      _dragQueued = point;
      return;
    }
    _dragBusy = true;
    try {
      Offset? next = point;
      while (next != null && _moving && !_disposed) {
        _dragQueued = null;
        final p = selected;
        if (p == null || p.locked || session.trackingLost) break;
        final r = await engine.placeObject(
          p.placementId,
          p.unitId,
          next,
          manual: session.manualPlacement,
        );
        if (r.placed && !_disposed) {
          final cur = byId(p.placementId);
          if (cur != null) {
            _replace(
              cur.copyWith(
                status: ArAnchorStatus.anchored,
                surface: r.surface,
                pose: r.pose,
                clearPose: r.pose == null,
              ),
            );
            _notify();
          }
        }
        next = _dragQueued;
      }
    } finally {
      _dragBusy = false;
    }
  }

  void endDrag() {
    if (!_moving) return;
    _moving = false;
    _dragQueued = null;
    endGesture('Move');
    _syncSession();
    _notify();
  }

  /// Back to the anchor with no offset / rotation / scale change.
  Future<bool> resetTransform(String id) async {
    final p = byId(id);
    if (p == null) return false;
    if (p.locked) {
      _say('${p.displayName} is locked. Unlock it to reset.');
      return false;
    }
    final before = _snapshot();
    _replace(p.copyWith(transform: const ArObjectTransform()));
    await _push(id);
    _record('Reset transform', before, _selectedId);
    _notify();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Duplicate / delete
  // ---------------------------------------------------------------------------

  /// Adds a preview copy of the selected model (never a new signage unit:
  /// quantity, dimensions, photos and approvals are untouched).
  Future<bool> duplicateSelected() async {
    final src = selected;
    if (src == null) {
      _say('Select a model to duplicate.');
      return false;
    }
    if (!engine.supportsMultipleObjects) {
      _say('This AR engine can show only one model at a time.');
      return false;
    }
    final before = _snapshot();
    final selBefore = _selectedId;
    final id = _newId();
    final widthM = src.widthFt * kFeetToMetres * src.transform.scale;
    var dup = src.copyWith(
      placementId: id,
      previewDuplicate: true,
      duplicateOf: src.placementId,
      locked: false,
      visible: true,
      transform: src.transform.copyWith(
        x: _round(src.transform.x + widthM + 0.15),
      ),
    );
    final pose = src.pose;
    if (src.isAnchored && pose != null && await _ensureModel(src.unitId)) {
      final r = await engine.anchorObject(
        id,
        src.unitId,
        pose,
        src.surface ?? 'horizontal',
      );
      dup = r.placed
          ? dup.copyWith(status: ArAnchorStatus.anchored, pose: r.pose ?? pose)
          : dup.copyWith(status: ArAnchorStatus.pending, clearPose: true);
    } else {
      dup = dup.copyWith(status: ArAnchorStatus.pending, clearPose: true);
    }
    _placements.add(dup);
    _selectedId = id;
    if (dup.isAnchored) {
      await _push(id);
      await engine.selectObject(id);
    }
    _record('Duplicate', before, selBefore);
    if (!dup.isAnchored) {
      requestReanchor(id);
      _message = 'Tap a surface to place the preview duplicate.';
    } else {
      _message = 'Preview duplicate added. It does not change the quantity.';
    }
    _syncSession();
    _notify();
    return true;
  }

  Future<bool> removeSelected() async {
    final id = _selectedId;
    if (id == null) {
      _say('Select a model to delete.');
      return false;
    }
    return remove(id);
  }

  /// Removes a placement from the AR scene only (the signage item stays).
  Future<bool> remove(String id) async {
    final p = byId(id);
    if (p == null) return false;
    if (p.locked) {
      _say('${p.displayName} is locked. Unlock it to remove.');
      return false;
    }
    _endGesture();
    final before = _snapshot();
    final selBefore = _selectedId;
    await engine.removeObject(id);
    _placements.removeWhere((e) => e.placementId == id);
    if (_selectedId == id) {
      _selectedId = null;
      await engine.selectObject(null);
    }
    if (_reanchorId == id) {
      _reanchorId = null;
      await _indicator();
    }
    _record('Remove ${p.displayName}', before, selBefore);
    _message = '${p.displayName} removed from the AR scene.';
    _syncSession();
    _notify();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Undo / redo (AR editing session only)
  // ---------------------------------------------------------------------------

  Future<bool> undo() async {
    if (_undo.isEmpty) return false;
    _endGesture();
    final e = _undo.removeLast();
    await _apply(e.before);
    _redo.add(e);
    _selectAfterHistory(e.selectedBefore);
    _message = 'Undone: ${e.label}';
    _syncSession();
    _notify();
    return true;
  }

  Future<bool> redo() async {
    if (_redo.isEmpty) return false;
    _endGesture();
    final e = _redo.removeLast();
    await _apply(e.after);
    _undo.add(e);
    _selectAfterHistory(e.selectedAfter);
    _message = 'Redone: ${e.label}';
    _syncSession();
    _notify();
    return true;
  }

  void _selectAfterHistory(String? id) {
    _selectedId = byId(id) == null ? null : id;
    engine.selectObject(_selectedId);
  }

  /// Brings the scene to [target]: objects are re-created / removed /
  /// re-anchored / re-transformed. Visibility and lock are view settings
  /// and keep their current value.
  Future<void> _apply(List<ArPlacement> target) async {
    final current = {for (final p in _placements) p.placementId: p};
    final next = <ArPlacement>[];
    for (final t in target) {
      final c = current.remove(t.placementId);
      var p = c == null ? t : c.copyWith(transform: t.transform);
      final pose = t.pose;
      final needsAnchor =
          t.isAnchored &&
          pose != null &&
          (c == null || !c.isAnchored || !listEquals(c.pose, pose));
      if (needsAnchor) {
        final ok = await _ensureModel(t.unitId);
        final r = ok
            ? await engine.anchorObject(
                t.placementId,
                t.unitId,
                pose,
                t.surface ?? 'horizontal',
              )
            : const ArObjectPlaceResult(placed: false);
        p = r.placed
            ? p.copyWith(
                status: ArAnchorStatus.anchored,
                pose: r.pose ?? pose,
                surface: t.surface,
              )
            : (c != null && c.isAnchored
                  ? p
                  : p.copyWith(
                      status: ArAnchorStatus.pending,
                      clearPose: true,
                    ));
        if (r.placed && !p.visible) {
          await engine.setObjectVisible(p.placementId, false);
        }
      } else if (c == null && t.isAnchored) {
        // Recreated without a known pose: must be placed again.
        p = t.copyWith(status: ArAnchorStatus.pending, clearPose: true);
      }
      next.add(p);
    }
    for (final gone in current.values) {
      await engine.removeObject(gone.placementId);
    }
    _placements
      ..clear()
      ..addAll(next);
    for (final p in _placements) {
      if (p.isAnchored) await _push(p.placementId);
    }
  }

  // ---------------------------------------------------------------------------
  // Layouts
  // ---------------------------------------------------------------------------

  /// Builds the layout record for the current scene.
  ArLayout toLayout({
    required String id,
    required String name,
    required Shop shop,
    DateTime? createdAt,
  }) {
    final now = _clock();
    return ArLayout(
      id: id,
      name: name,
      projectId: shop.projectId,
      taskId: shop.taskId,
      shopId: shop.id,
      createdAt: createdAt ?? now,
      updatedAt: now,
      objects: [
        for (final p in _placements)
          ArLayoutObject(
            placementId: p.placementId,
            signageItemId: p.unitId,
            groupId: p.groupId,
            mediaCode: p.mediaCode,
            installationCode: p.installationCode,
            previewDuplicate: p.previewDuplicate,
            duplicateOf: p.duplicateOf,
            modelConfig: {
              'label': p.label,
              'widthFt': p.widthFt,
              'heightFt': p.heightFt,
              'size': p.sizeText,
              'doubleSided': p.doubleSided,
              'preferVertical': p.preferVertical,
            },
            transform: p.transform.toMap(),
            visible: p.visible,
            locked: p.locked,
            surface: p.surface,
            lastSessionPose: p.pose,
            savedAt: now,
          ),
      ],
    );
  }

  void markSaved(ArLayout layout) {
    layoutId = layout.id;
    layoutName = layout.name;
    _message = 'AR layout “${layout.name}” saved on this phone.';
    _notify();
  }

  /// Replaces the scene with a saved layout. Objects come back with their
  /// transforms but must be re-anchored (world anchors are not persisted).
  /// Placements whose signage item no longer exists are skipped.
  Future<ArLayoutLoadResult> loadLayout(ArLayout layout) async {
    _endGesture();
    for (final p in _placements) {
      await engine.removeObject(p.placementId);
    }
    _placements.clear();
    _undo.clear();
    _redo.clear();
    _armedItem = null;
    _reanchorId = null;
    _selectedId = null;
    await engine.selectObject(null);
    final missing = <String>[];
    for (final o in layout.objects) {
      final item = _items[o.signageItemId];
      if (item == null || !item.modelAvailable) {
        missing.add(o.signageItemId);
        continue;
      }
      if (_placements.any((p) => p.placementId == o.placementId)) continue;
      _placements.add(
        ArPlacement.fromItem(
          item,
          o.placementId,
          previewDuplicate: o.previewDuplicate,
          duplicateOf: o.duplicateOf,
          transform: ArObjectTransform.fromMap(o.transform),
        ).copyWith(visible: o.visible, locked: o.locked, surface: o.surface),
      );
    }
    layoutId = layout.id;
    layoutName = layout.name;
    _message = _placements.isEmpty
        ? 'Nothing to load: the layout\'s signage items no longer exist.'
        : 'Layout “${layout.name}” loaded. Saved AR positions cannot be '
              'restored – tap a surface to re-anchor each model.';
    if (_placements.isNotEmpty && session.sessionRunning) {
      _reanchorId = _placements.first.placementId;
      _selectedId = _reanchorId;
      await engine.selectObject(_selectedId);
    }
    await _indicator();
    _syncSession();
    _notify();
    return ArLayoutLoadResult(loaded: _placements.length, missing: missing);
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    session.removeListener(_onSession);
    super.dispose();
  }
}
