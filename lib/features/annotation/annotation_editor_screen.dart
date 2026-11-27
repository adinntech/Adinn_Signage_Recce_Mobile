import '../../l10n/l10n.dart';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../photos/site_photo_view.dart';
import 'annotation_geometry.dart';
import 'annotation_painter.dart';
import 'photo_tour.dart';
import '../../core/widgets/adinn_app_bar.dart';

/// Returned by [AnnotationEditorScreen] when the user taps Save.
class AnnotationEditorResult {
  const AnnotationEditorResult({
    required this.annotations,
    this.applyWidth,
    this.applyHeight,
    this.applyUnit,
    this.applyUnitId,
  });

  final List<Annotation> annotations;

  /// Set when the user chose "Use as board size" on a measured rectangle.
  final double? applyWidth;
  final double? applyHeight;
  final MeasureUnit? applyUnit;

  /// Canonical physical-board ID of that rectangle. The measurement must be
  /// applied to THIS board, never to `units.first` or the workspace unit.
  final String? applyUnitId;
}

/// A signage unit the placement rectangles can be linked to.
class AnnotationUnitOption {
  const AnnotationUnitOption({
    required this.id,
    required this.label,
    this.width,
    this.height,
    this.unit = MeasureUnit.ft,
    this.recorded = const [],
  });

  final String id;

  /// e.g. "GSB – Unit 01".
  final String label;
  final double? width;
  final double? height;
  final MeasureUnit unit;

  /// User-entered advanced measurements of the item (offered as values for
  /// dimension lines – never estimated from the photo).
  final List<RecordedMeasurement> recorded;

  bool get hasSize => (width ?? 0) > 0 && (height ?? 0) > 0;
}

/// A measured value recorded for a signage item, e.g. "Bottom height 9 ft".
class RecordedMeasurement {
  const RecordedMeasurement(this.label, this.value, this.unit);

  final String label;
  final double value;
  final MeasureUnit unit;
}

/// Extra tool button appended to the editor's tool bar (e.g. the advanced
/// site markup tools). The editor stays open underneath, so unsaved
/// markings are kept.
class AnnotationExtraTool {
  const AnnotationExtraTool({
    required this.id,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

enum AnnotationTool {
  select,
  rectangle,
  arrow,
  text,
  pan,
  shapeRect,
  circle,
  line,
  freehand,
  dimension,
  measureLabel,
  poleMarker,
  pipeMarker,
  groundMarker,
  numberMarker,
}

extension AnnotationToolX on AnnotationTool {
  String get label => switch (this) {
    AnnotationTool.select => 'Select',
    AnnotationTool.rectangle => 'Signage',
    AnnotationTool.arrow => 'Arrow',
    AnnotationTool.text => 'Text',
    AnnotationTool.pan => 'Zoom',
    AnnotationTool.shapeRect => 'Rect',
    AnnotationTool.circle => 'Circle',
    AnnotationTool.line => 'Line',
    AnnotationTool.freehand => 'Pen',
    AnnotationTool.dimension => 'Dimension',
    AnnotationTool.measureLabel => 'Measure',
    AnnotationTool.poleMarker => 'Pole',
    AnnotationTool.pipeMarker => 'Pipe',
    AnnotationTool.groundMarker => 'Ground',
    AnnotationTool.numberMarker => 'Number',
  };

  IconData get icon => switch (this) {
    AnnotationTool.select => Icons.near_me_outlined,
    AnnotationTool.rectangle => Icons.crop_square,
    AnnotationTool.arrow => Icons.north_east,
    AnnotationTool.text => Icons.title,
    AnnotationTool.pan => Icons.pan_tool_outlined,
    AnnotationTool.shapeRect => Icons.rectangle_outlined,
    AnnotationTool.circle => Icons.circle_outlined,
    AnnotationTool.line => Icons.horizontal_rule,
    AnnotationTool.freehand => Icons.gesture,
    AnnotationTool.dimension => Icons.straighten,
    AnnotationTool.measureLabel => Icons.label_important_outline,
    AnnotationTool.poleMarker => Icons.location_on_outlined,
    AnnotationTool.pipeMarker => Icons.vertical_align_bottom,
    AnnotationTool.groundMarker => Icons.landscape_outlined,
    AnnotationTool.numberMarker => Icons.looks_one_outlined,
  };

  String get hint => switch (this) {
    AnnotationTool.select =>
      'Tap a marking to select. Drag to move, corners to resize, top circle to rotate.',
    AnnotationTool.rectangle =>
      'Drag on the photo to mark the signage placement area.',
    AnnotationTool.arrow => 'Drag to draw an arrow.',
    AnnotationTool.text => 'Tap where the text label should go.',
    AnnotationTool.pan => 'Pinch to zoom, drag to pan the photo.',
    AnnotationTool.shapeRect => 'Drag to draw a rectangle.',
    AnnotationTool.circle => 'Drag to draw a circle / ellipse.',
    AnnotationTool.line => 'Drag to draw a straight line.',
    AnnotationTool.freehand => 'Draw freely with your finger.',
    AnnotationTool.dimension =>
      'Drag between two points, then enter the measured value.',
    AnnotationTool.measureLabel => 'Tap to place a measurement label.',
    AnnotationTool.poleMarker => 'Tap the pole location.',
    AnnotationTool.pipeMarker => 'Tap the support pipe location.',
    AnnotationTool.groundMarker => 'Tap the ground level line.',
    AnnotationTool.numberMarker => 'Tap to drop numbered markers 1, 2, 3…',
  };

  /// Annotation type the tool creates (null for select / pan).
  AnnotationType? get creates => switch (this) {
    AnnotationTool.select || AnnotationTool.pan => null,
    AnnotationTool.rectangle => AnnotationType.rectangle,
    AnnotationTool.arrow => AnnotationType.arrow,
    AnnotationTool.text => AnnotationType.text,
    AnnotationTool.shapeRect => AnnotationType.shapeRect,
    AnnotationTool.circle => AnnotationType.circle,
    AnnotationTool.line => AnnotationType.line,
    AnnotationTool.freehand => AnnotationType.freehand,
    AnnotationTool.dimension => AnnotationType.dimension,
    AnnotationTool.measureLabel => AnnotationType.measureLabel,
    AnnotationTool.poleMarker => AnnotationType.poleMarker,
    AnnotationTool.pipeMarker => AnnotationType.pipeMarker,
    AnnotationTool.groundMarker => AnnotationType.groundMarker,
    AnnotationTool.numberMarker => AnnotationType.numberMarker,
  };

  /// Tools that create a marking with a single tap.
  bool get placesOnTap => switch (this) {
    AnnotationTool.text ||
    AnnotationTool.measureLabel ||
    AnnotationTool.poleMarker ||
    AnnotationTool.pipeMarker ||
    AnnotationTool.groundMarker ||
    AnnotationTool.numberMarker => true,
    _ => false,
  };
}

enum _DragOp { none, draw, move, handle }

enum _SheetMode { rect, value, label }

/// Full-screen editor to mark signage placement rectangles (with W × H
/// measurements and a link to a signage unit), shapes, freehand strokes,
/// dimension lines, measurement labels, site markers and text on a site
/// photo. The photo itself is never modified: markings are saved as editable
/// data in photo pixel coordinates.
class AnnotationEditorScreen extends StatefulWidget {
  const AnnotationEditorScreen({
    super.key,
    required this.photo,
    required this.boardName,
    this.defaultUnit = MeasureUnit.ft,
    this.units = const [],
    this.activeUnitId,
    this.onSave,
    this.extraTools = const [],
    this.underlay,
    this.tour,
  });

  /// Guided signage-marking tour (null = none).
  final PhotoTour? tour;

  final SitePhoto photo;

  /// Additional tools shown after the annotation tools.
  final List<AnnotationExtraTool> extraTools;

  /// Read-only layer painted between the photo and the annotations (e.g.
  /// the advanced site markup). Painted in the displayed photo box.
  final CustomPainter? underlay;
  final String boardName;
  final MeasureUnit defaultUnit;

  /// Signage units of the media group (placement rectangles link to these).
  final List<AnnotationUnitOption> units;

  /// Unit new placement rectangles are linked to by default.
  final String? activeUnitId;

  /// Embedded mode (photo workspace tab): Save calls this instead of
  /// closing the screen.
  final ValueChanged<AnnotationEditorResult>? onSave;

  @override
  State<AnnotationEditorScreen> createState() => _AnnotationEditorScreenState();
}

class _AnnotationEditorScreenState extends State<AnnotationEditorScreen> {
  static const palette = <int>[
    0xFFD71920,
    0xFFFFC107,
    0xFFFFFFFF,
    0xFF1A73E8,
    0xFF1E8E3E,
    0xFF000000,
  ];

  /// Gesture margin around the photo so handles near the edges stay usable.
  static const double _margin = 28;

  late List<Annotation> _items;
  final _tc = TransformationController();
  final List<List<Annotation>> _undo = [];
  final List<List<Annotation>> _redo = [];
  final Set<AnnotationLayer> _hidden = {};
  AnnotationTool _tool = AnnotationTool.select;
  String? _selectedId;
  int _color = palette.first;

  /// Fixed default thickness for newly created annotations. The adjustment
  /// control was removed from the field UI; saved legacy values are untouched.
  double _thickness = 2.5;
  bool _dirty = false;
  double? _applyW;
  double? _applyH;
  MeasureUnit? _applyUnit;
  String? _applyUnitId;

  // Drag state
  double _displayScale = 1;
  Annotation? _draft;
  Offset _dragStart = Offset.zero;
  Offset _lastPoint = Offset.zero;
  _DragOp _op = _DragOp.none;
  AnnotationHandle? _activeHandle;
  List<Annotation>? _beforeDrag;
  bool _dragChanged = false;

  bool get _embedded => widget.onSave != null;

  Size get _imageSize =>
      Size(widget.photo.width.toDouble(), widget.photo.height.toDouble());

  double get _zoom => _tc.value.getMaxScaleOnAxis();

  double get _font => _imageSize.width / 38;

  /// Photo pixels per on-screen logical pixel.
  double get _screenToImage => 1 / math.max(_displayScale * _zoom, 1e-6);

  Annotation? get _selected {
    for (final a in _items) {
      if (a.id == _selectedId) return a;
    }
    return null;
  }

  AnnotationUnitOption? _unitOption(String? id) {
    for (final u in widget.units) {
      if (u.id == id) return u;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _items = widget.photo.annotations.map((a) => a.copy()).toList();
    _tc.addListener(_onTransform);
  }

  @override
  void dispose() {
    _tc.removeListener(_onTransform);
    _tc.dispose();
    super.dispose();
  }

  void _onTransform() {
    if (mounted) setState(() {});
  }

  List<Annotation> _cloneItems() => _items.map((a) => a.copy()).toList();

  void _pushUndo([List<Annotation>? snapshot]) {
    _undo.add(snapshot ?? _cloneItems());
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_cloneItems());
      _items = _undo.removeLast();
      if (_selected == null) _selectedId = null;
      _dirty = true;
    });
  }

  void _redoLast() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_cloneItems());
      _items = _redo.removeLast();
      if (_selected == null) _selectedId = null;
      _dirty = true;
    });
  }

  Offset _toImage(Offset local) =>
      (local - const Offset(_margin, _margin)) / _displayScale;

  Offset _clampToImage(Offset p) => Offset(
    p.dx.clamp(0.0, _imageSize.width),
    p.dy.clamp(0.0, _imageSize.height),
  );

  String _nextRectLabel() {
    final unit = _unitOption(widget.activeUnitId);
    if (unit != null) return unit.label;
    final count = _items
        .where((a) => a.type == AnnotationType.rectangle)
        .length;
    return count == 0 ? widget.boardName : '${widget.boardName} (${count + 1})';
  }

  int _nextNumber() {
    var n = 0;
    for (final a in _items.where(
      (a) => a.type == AnnotationType.numberMarker,
    )) {
      n = math.max(n, int.tryParse(a.label.trim()) ?? 0);
    }
    return n + 1;
  }

  void _showLayerOf(AnnotationTool tool) {
    final t = tool.creates;
    if (t != null) _hidden.remove(t.layer);
  }

  // ---------------------------------------------------------------------------
  // Gestures
  // ---------------------------------------------------------------------------

  void _onTapUp(TapUpDetails details) {
    final p = _toImage(details.localPosition);
    if (_tool.placesOnTap) {
      _placeAt(_tool, _clampToImage(p));
      return;
    }
    final hit = AnnotationGeometry.topmostVisibleAt(
      _items,
      p,
      _hidden,
      tolerance: 12 * _screenToImage,
    );
    setState(() {
      _selectedId = hit?.id;
      if (hit != null) _tool = AnnotationTool.select;
    });
  }

  Annotation _newDraft(AnnotationType type, Offset p) => Annotation(
    id: newId('a'),
    type: type,
    x: p.dx,
    y: p.dy,
    x2: p.dx,
    y2: p.dy,
    color: _color,
    thickness: _thickness,
    unit: widget.defaultUnit,
  );

  void _onPanStart(DragStartDetails details) {
    final raw = _toImage(details.localPosition);
    _lastPoint = raw;
    _dragChanged = false;
    _beforeDrag = _cloneItems();
    _op = _DragOp.none;
    _activeHandle = null;

    final creates = _tool.creates;
    if (creates != null && !_tool.placesOnTap) {
      final p = _clampToImage(raw);
      _dragStart = p;
      _op = _DragOp.draw;
      _draft = _newDraft(creates, p);
      if (creates == AnnotationType.freehand) {
        AnnotationGeometry.addPathPoint(_draft!, p);
      }
      setState(() {});
      return;
    }
    if (_tool == AnnotationTool.select) {
      final sel = _selected;
      if (sel != null && !_hidden.contains(sel.type.layer)) {
        final handle = AnnotationGeometry.hitHandle(
          sel,
          raw,
          radius: kHandleRadiusPx * kHandleTouchFactor * _screenToImage,
          rotateOffset: kRotateHandleOffsetPx * _screenToImage,
        );
        if (handle != null) {
          _op = _DragOp.handle;
          _activeHandle = handle;
          setState(() {});
          return;
        }
      }
      final hit = AnnotationGeometry.topmostVisibleAt(
        _items,
        raw,
        _hidden,
        tolerance: 12 * _screenToImage,
      );
      _selectedId = hit?.id;
      if (hit != null) _op = _DragOp.move;
    }
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final raw = _toImage(details.localPosition);
    switch (_op) {
      case _DragOp.draw:
        final d = _draft;
        if (d == null) break;
        final p = _clampToImage(raw);
        if (d.type.isFreehand) {
          AnnotationGeometry.addPathPoint(
            d,
            p,
            minStep: math.max(1.5, 2 * _screenToImage),
          );
        } else if (d.type.isTwoPoint) {
          d
            ..x2 = p.dx
            ..y2 = p.dy;
        } else {
          AnnotationGeometry.setRectFromPoints(d, _dragStart, p);
        }
      case _DragOp.move:
        final sel = _selected;
        if (sel == null) break;
        AnnotationGeometry.translate(sel, raw - _lastPoint);
        _dragChanged = true;
      case _DragOp.handle:
        final sel = _selected;
        final handle = _activeHandle;
        if (sel == null || handle == null) break;
        if (handle.isCorner) {
          AnnotationGeometry.resizeFromCorner(
            sel,
            handle,
            raw,
            minSize: math.max(8, 16 * _screenToImage),
          );
        } else if (handle == AnnotationHandle.rotate) {
          sel.rotation = AnnotationGeometry.snapAngle(
            AnnotationGeometry.rotationFromPointer(
              AnnotationGeometry.centre(sel),
              raw,
            ),
          );
        } else {
          AnnotationGeometry.moveArrowEndpoint(sel, handle, raw);
        }
        _dragChanged = true;
      case _DragOp.none:
        return;
    }
    _lastPoint = raw;
    setState(() {});
  }

  bool _validDraft(Annotation d, double minLen) {
    if (d.type.isTwoPoint) return AnnotationGeometry.arrowLength(d) >= minLen;
    if (d.type.isFreehand) {
      final b = AnnotationGeometry.bounds(d);
      return math.max(b.width, b.height) >= minLen;
    }
    return d.w >= minLen && d.h >= minLen;
  }

  void _onPanEnd(DragEndDetails details) {
    Annotation? created;
    final minLen = 14 * _screenToImage;
    switch (_op) {
      case _DragOp.draw:
        final d = _draft;
        _draft = null;
        if (d == null) break;
        if (_validDraft(d, minLen)) {
          _pushUndo(_beforeDrag);
          if (d.type == AnnotationType.rectangle) {
            d.label = _nextRectLabel();
            // Initial default only: the Signage Measurement dialog's
            // explicit selection overrides this before Save.
            final unit = _unitOption(
              widget.activeUnitId ??
                  (widget.units.length == 1 ? widget.units.first.id : null),
            );
            if (unit != null) {
              d.itemId = unit.id;
              if (unit.hasSize) {
                d
                  ..measureW = unit.width
                  ..measureH = unit.height
                  ..unit = unit.unit;
              }
            }
          }
          _items.add(d);
          _selectedId = d.id;
          if (d.type != AnnotationType.freehand) _tool = AnnotationTool.select;
          _dirty = true;
          created = d;
          if (d.type == AnnotationType.rectangle) widget.tour?.advanceTo(3);
        }
      case _DragOp.move:
      case _DragOp.handle:
        if (_dragChanged) {
          _pushUndo(_beforeDrag);
          _dirty = true;
        }
      case _DragOp.none:
        break;
    }
    _op = _DragOp.none;
    _activeHandle = null;
    _beforeDrag = null;
    setState(() {});
    if (created != null &&
        (created.type == AnnotationType.rectangle ||
            created.type == AnnotationType.dimension)) {
      _editDetails(created, isNew: true);
    }
  }

  void _onPanCancel() {
    setState(() {
      _draft = null;
      _op = _DragOp.none;
      _activeHandle = null;
      _beforeDrag = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _commitNew(Annotation a) {
    setState(() {
      _pushUndo();
      _items.add(a);
      _selectedId = a.id;
      if (_tool != AnnotationTool.numberMarker) _tool = AnnotationTool.select;
      _dirty = true;
    });
  }

  Future<void> _placeAt(AnnotationTool tool, Offset p) async {
    final font = _font;
    switch (tool) {
      case AnnotationTool.text:
        await _addText(p);
      case AnnotationTool.measureLabel:
        final draft = _newDraft(AnnotationType.measureLabel, p);
        final r = await _openSheet(draft, _SheetMode.value, isNew: true);
        if (r == null || !mounted) return;
        draft
          ..label = r.label
          ..measureW = r.width
          ..unit = r.unit;
        final size = AnnotationGeometry.estimateTextSize(
          AnnotationPainter.valueText(draft),
          font * 0.9,
        );
        draft
          ..w = size.width
          ..h = size.height;
        _commitNew(draft);
      case AnnotationTool.poleMarker:
      case AnnotationTool.pipeMarker:
      case AnnotationTool.numberMarker:
        final a = _newDraft(tool.creates!, p)
          ..w = font * 1.6
          ..h = font * 1.6;
        if (tool == AnnotationTool.numberMarker) a.label = '${_nextNumber()}';
        _commitNew(a);
      case AnnotationTool.groundMarker:
        _commitNew(
          _newDraft(AnnotationType.groundMarker, p)
            ..w = _imageSize.width * 0.35
            ..h = font * 0.8,
        );
      default:
        break;
    }
  }

  Future<void> _addText(Offset p) async {
    final text = await _askText(title: 'Add text label');
    if (text == null || text.trim().isEmpty || !mounted) return;
    final size = AnnotationGeometry.estimateTextSize(text, _font);
    _commitNew(
      Annotation(
        id: newId('a'),
        type: AnnotationType.text,
        x: p.dx,
        y: p.dy,
        w: size.width,
        h: size.height,
        label: text.trim(),
        color: _color,
      ),
    );
  }

  Future<String?> _askText({required String title, String initial = ''}) {
    // The controller must live as long as the TextField that uses it. A
    // whenComplete(controller.dispose) disposes it while the dismissing route
    // is still rebuilding (keyboard animation) -> "used after disposed" and
    // a cascading _dependents.isEmpty assertion. Own it in a StatefulWidget
    // instead so dispose runs only after the TextField is unmounted.
    return showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(title: title, initial: initial),
    );
  }

  Future<_DetailsResult?> _openSheet(
    Annotation a,
    _SheetMode mode, {
    bool isNew = false,
  }) {
    return showModalBottomSheet<_DetailsResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _DetailsSheet(
        annotation: a,
        isNew: isNew,
        mode: mode,
        defaultUnit: widget.defaultUnit,
        units: widget.units,
      ),
    );
  }

  Future<void> _editDetails(Annotation a, {bool isNew = false}) async {
    if (a.type == AnnotationType.text) {
      final text = await _askText(title: 'Edit text', initial: a.label);
      if (text == null || text.trim().isEmpty || !mounted) return;
      final target = _byId(a.id);
      if (target == null) return;
      setState(() {
        _pushUndo();
        final font = target.h / 1.7;
        target
          ..label = text.trim()
          ..w = AnnotationGeometry.estimateTextSize(text, font).width;
        _dirty = true;
      });
      return;
    }
    if (a.type == AnnotationType.numberMarker) {
      final text = await _askText(title: 'Marker number', initial: a.label);
      if (text == null || text.trim().isEmpty || !mounted) return;
      final target = _byId(a.id);
      if (target == null) return;
      setState(() {
        _pushUndo();
        target.label = text.trim();
        _dirty = true;
      });
      return;
    }

    final mode = switch (a.type) {
      AnnotationType.rectangle => _SheetMode.rect,
      AnnotationType.dimension ||
      AnnotationType.measureLabel => _SheetMode.value,
      _ => _SheetMode.label,
    };
    final result = await _openSheet(a, mode, isNew: isNew);
    if (result == null || !mounted) return;
    final target = _byId(a.id);
    if (target == null) return;
    setState(() {
      _pushUndo();
      target.label = result.label;
      switch (mode) {
        case _SheetMode.rect:
          target
            ..measureW = result.width
            ..measureH = result.height
            ..unit = result.unit
            ..itemId = result.itemId;
        case _SheetMode.value:
          target
            ..measureW = result.width
            ..unit = result.unit;
          if (target.type == AnnotationType.measureLabel) {
            target.w = AnnotationGeometry.estimateTextSize(
              AnnotationPainter.valueText(target),
              target.h / 1.7,
            ).width;
          }
        case _SheetMode.label:
          break;
      }
      _dirty = true;
    });
  }

  Annotation? _byId(String id) {
    for (final a in _items) {
      if (a.id == id) return a;
    }
    return null;
  }

  void _rotateSelected(double degrees) {
    final sel = _selected;
    if (sel == null || !AnnotationGeometry.isBox(sel)) return;
    setState(() {
      _pushUndo();
      sel.rotation = AnnotationGeometry.normalizeAngle(
        sel.rotation + degrees * math.pi / 180,
      );
      _dirty = true;
    });
  }

  void _duplicateSelected() {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _pushUndo();
      final copy = Annotation.fromJson({...sel.toJson(), 'id': newId('a')});
      final shift = _imageSize.width * 0.03;
      AnnotationGeometry.translate(copy, Offset(shift, shift));
      _items.add(copy);
      _selectedId = copy.id;
      _dirty = true;
    });
  }

  void _deleteSelected() {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _pushUndo();
      _items.remove(sel);
      _selectedId = null;
      _dirty = true;
    });
  }

  void _useAsBoardSize() {
    final sel = _selected;
    if (sel == null || !sel.hasMeasurement) return;
    setState(() {
      _applyW = sel.measureW;
      _applyH = sel.measureH;
      _applyUnit = sel.unit;
      _applyUnitId = sel.itemId;
      _dirty = true;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Board size will be set to '
            '${AnnotationPainter.measurementText(sel)} when you save.',
          ),
        ),
      );
  }

  void _setColor(int color) {
    setState(() {
      _color = color;
      final sel = _selected;
      if (sel != null && sel.color != color) {
        _pushUndo();
        sel.color = color;
        _dirty = true;
      }
    });
  }

  void _setTool(AnnotationTool tool) {
    setState(() {
      _tool = tool;
      _showLayerOf(tool);
      if (tool.creates != null) _selectedId = null;
    });
    if (tool == AnnotationTool.rectangle) widget.tour?.advanceTo(2);
  }

  void _resetZoom() => _tc.value = Matrix4.identity();

  Future<void> _openLayers() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  context.ui('Layers'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              for (final layer in const [
                AnnotationLayer.photo,
                AnnotationLayer.drawing,
                AnnotationLayer.text,
                AnnotationLayer.measurements,
                AnnotationLayer.placement,
              ])
                SwitchListTile(
                  key: ValueKey('layer-${layer.name}'),
                  dense: true,
                  title: Text(context.ui(layer.label)),
                  subtitle: layer == AnnotationLayer.photo
                      ? null
                      : Text(
                          '${_items.where((a) => a.type.layer == layer).length} marking(s)',
                        ),
                  value: !_hidden.contains(layer),
                  onChanged: (v) {
                    setState(() {
                      if (v) {
                        _hidden.remove(layer);
                      } else {
                        _hidden.add(layer);
                        final sel = _selected;
                        if (sel != null && sel.type.layer == layer) {
                          _selectedId = null;
                        }
                      }
                    });
                    setSheet(() {});
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  AnnotationEditorResult _result() => AnnotationEditorResult(
    annotations: _cloneItems(),
    applyWidth: _applyW,
    applyHeight: _applyH,
    applyUnit: _applyUnit,
    applyUnitId: _applyUnitId,
  );

  void _save() {
    final onSave = widget.onSave;
    // The tour completes only when a real, linked signage marking is saved.
    final marked = _items.any(
      (a) =>
          a.type == AnnotationType.rectangle &&
          a.w > 0 &&
          a.h > 0 &&
          a.itemId != null,
    );
    if (onSave == null) {
      if (marked) widget.tour?.finish();
      Navigator.of(context).pop(_result());
      return;
    }
    onSave(_result());
    if (marked) widget.tour?.finish();
    setState(() {
      _dirty = false;
      _applyW = null;
      _applyH = null;
      _applyUnit = null;
      _applyUnitId = null;
    });
  }

  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.ui('Discard changes?')),
        content: Text(
          context.ui('Your markings on this photo have not been saved.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.ui('Keep editing')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.ui('Discard')),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  List<Widget> _actions() => [
    IconButton(
      tooltip: context.ui('Undo'),
      onPressed: _undo.isEmpty ? null : _undoLast,
      icon: const Icon(Icons.undo),
    ),
    IconButton(
      tooltip: context.ui('Redo'),
      onPressed: _redo.isEmpty ? null : _redoLast,
      icon: const Icon(Icons.redo),
    ),
    IconButton(
      tooltip: context.ui('Reset zoom'),
      onPressed: _tc.value.isIdentity() ? null : _resetZoom,
      icon: const Icon(Icons.fit_screen_outlined),
    ),
    Padding(
      padding: const EdgeInsets.only(right: 8),
      child: KeyedSubtree(
        key: widget.tour?.saveKey,
        child: FilledButton(
          key: const ValueKey('annotation-save'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(60, 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          onPressed: _embedded && !_dirty ? null : _save,
          child: Text(context.ui('Save')),
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.ui('Annotate photo'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        Text(
          '${widget.boardName} • ${widget.photo.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            color: AdinnColors.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _embedded
            ? null
            : AdinnAppBar(titleSpacing: 0, title: title, actions: _actions()),
        body: Stack(
          children: [
            SafeArea(
              top: false,
              child: Column(
                children: [
                  if (_embedded)
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.only(left: 12),
                      child: Row(
                        children: [
                          Expanded(child: title),
                          ..._actions(),
                        ],
                      ),
                    ),
                  _hintBar(),
                  Expanded(
                    child: widget.tour == null
                        ? _editorArea()
                        : KeyedSubtree(
                            key: widget.tour!.canvasKey,
                            child: _editorArea(),
                          ),
                  ),
                  if (sel != null) _contextBar(sel),
                  _paletteRow(),
                  _toolBar(),
                ],
              ),
            ),
            if (widget.tour != null)
              Positioned.fill(child: PhotoTourOverlay(tour: widget.tour!)),
          ],
        ),
      ),
    );
  }

  Widget _hintBar() {
    final unit = _unitOption(widget.activeUnitId);
    return Container(
      width: double.infinity,
      color: AdinnColors.redLight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Icon(_tool.icon, size: 16, color: AdinnColors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _tool == AnnotationTool.rectangle && unit != null
                  ? '${_tool.hint} Linked to ${unit.label}.'
                  : _tool.hint,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AdinnColors.redDark),
            ),
          ),
          if (_hidden.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Tooltip(
                message: '${_hidden.length} layer(s) hidden',
                child: const Icon(
                  Icons.layers_clear_outlined,
                  size: 18,
                  color: AdinnColors.redDark,
                ),
              ),
            ),
          if (_applyW != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Tooltip(
                message: 'Board size will be updated on save',
                child: Icon(
                  Icons.straighten,
                  size: 18,
                  color: AdinnColors.success.withValues(alpha: 0.9),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _editorArea() {
    return Container(
      color: const Color(0xFF202124),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = Size(
            math.max(constraints.maxWidth - _margin * 2, 1),
            math.max(constraints.maxHeight - _margin * 2, 1),
          );
          final fitted = applyBoxFit(
            BoxFit.contain,
            _imageSize,
            available,
          ).destination;
          if (fitted.isEmpty) return const SizedBox.shrink();
          _displayScale = fitted.width / _imageSize.width;
          final editing = _tool != AnnotationTool.pan;

          return InteractiveViewer(
            transformationController: _tc,
            minScale: 1,
            maxScale: 6,
            panEnabled: !editing,
            scaleEnabled: !editing,
            boundaryMargin: const EdgeInsets.all(80),
            child: Center(
              child: SizedBox(
                width: fitted.width + _margin * 2,
                height: fitted.height + _margin * 2,
                child: Stack(
                  children: [
                    Positioned(
                      left: _margin,
                      top: _margin,
                      width: fitted.width,
                      height: fitted.height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _hidden.contains(AnnotationLayer.photo)
                              ? Container(
                                  key: const ValueKey('photo-hidden'),
                                  color: const Color(0xFF3C4043),
                                )
                              : SitePhotoImage(widget.photo),
                          if (widget.underlay != null)
                            CustomPaint(
                              key: const ValueKey('annotation-underlay'),
                              painter: widget.underlay,
                            ),
                        ],
                      ),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        key: const ValueKey('annotation-canvas'),
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onTapUp: editing ? _onTapUp : null,
                        onPanStart: editing ? _onPanStart : null,
                        onPanUpdate: editing ? _onPanUpdate : null,
                        onPanEnd: editing ? _onPanEnd : null,
                        onPanCancel: editing ? _onPanCancel : null,
                        child: Padding(
                          padding: const EdgeInsets.all(_margin),
                          child: CustomPaint(
                            painter: AnnotationPainter(
                              annotations: _items,
                              imageSize: _imageSize,
                              selectedId: _selectedId,
                              handleScale: _zoom,
                              showHandles: true,
                              draft: _draft,
                              hiddenLayers: Set.of(_hidden),
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickLinkedUnit(Annotation sel) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.ui('Link marking to signage item'),
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            ListTile(
              leading: const Icon(Icons.link_off),
              title: Text(context.ui('Not linked')),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final u in widget.units)
              ListTile(
                key: ValueKey('link-unit-${u.id}'),
                leading: Icon(
                  sel.itemId == u.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: AdinnColors.red,
                ),
                title: Text(u.label),
                subtitle: u.hasSize
                    ? Text(fmtSize(u.width, u.height, u.unit))
                    : null,
                onTap: () => Navigator.pop(ctx, u.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final target = _byId(sel.id);
    if (target == null) return;
    setState(() {
      _pushUndo();
      final unit = _unitOption(picked);
      target.itemId = unit?.id;
      if (unit != null) {
        target.label = unit.label;
        if (unit.hasSize && !target.hasMeasurement) {
          target
            ..measureW = unit.width
            ..measureH = unit.height
            ..unit = unit.unit;
        }
      }
      _dirty = true;
    });
  }

  Widget _contextBar(Annotation sel) {
    final isBox = AnnotationGeometry.isBox(sel);
    final linked = _unitOption(sel.itemId);
    final actions = <Widget>[
      if (sel.type != AnnotationType.freehand &&
          sel.type != AnnotationType.poleMarker &&
          sel.type != AnnotationType.pipeMarker &&
          sel.type != AnnotationType.groundMarker)
        _ActionChip(
          key: const ValueKey('action-edit'),
          icon: Icons.edit_outlined,
          label: switch (sel.type) {
            AnnotationType.rectangle => 'Size',
            AnnotationType.dimension || AnnotationType.measureLabel => 'Value',
            _ => 'Edit',
          },
          onTap: () => _editDetails(sel),
        ),
      if (sel.type == AnnotationType.poleMarker ||
          sel.type == AnnotationType.pipeMarker ||
          sel.type == AnnotationType.groundMarker)
        _ActionChip(
          key: const ValueKey('action-edit'),
          icon: Icons.edit_outlined,
          label: 'Label',
          onTap: () => _editDetails(sel),
        ),
      if (sel.type == AnnotationType.rectangle && widget.units.isNotEmpty)
        _ActionChip(
          key: const ValueKey('action-link-unit'),
          icon: Icons.link,
          label: linked == null ? 'Link item' : linked.label,
          onTap: () => _pickLinkedUnit(sel),
        ),
      if (sel.type == AnnotationType.rectangle && sel.hasMeasurement)
        _ActionChip(
          key: const ValueKey('action-board-size'),
          icon: Icons.straighten,
          label: 'Use as board size',
          onTap: _useAsBoardSize,
        ),
      if (isBox) ...[
        _ActionChip(
          icon: Icons.rotate_left,
          label: '−15°',
          onTap: () => _rotateSelected(-15),
        ),
        _ActionChip(
          icon: Icons.rotate_right,
          label: '+15°',
          onTap: () => _rotateSelected(15),
        ),
      ],
      _ActionChip(
        icon: Icons.copy_all_outlined,
        label: 'Duplicate',
        onTap: _duplicateSelected,
      ),
      _ActionChip(
        key: const ValueKey('action-delete'),
        icon: Icons.delete_outline,
        label: 'Delete',
        color: AdinnColors.red,
        onTap: _deleteSelected,
      ),
      _ActionChip(
        key: const ValueKey('action-deselect'),
        icon: Icons.deselect,
        label: 'Deselect',
        onTap: () => setState(() => _selectedId = null),
      ),
    ];
    return Container(
      height: 50,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AdinnColors.line)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) => actions[i],
      ),
    );
  }

  Widget _paletteRow() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in palette)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkResponse(
                        key: ValueKey('colour-${c.toRadixString(16)}'),
                        onTap: () => _setColor(c),
                        radius: 18,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == c
                                  ? AdinnColors.ink
                                  : AdinnColors.line,
                              width: _color == c ? 2.5 : 1.2,
                            ),
                          ),
                          child: _color == c
                              ? Icon(
                                  Icons.check,
                                  size: 13,
                                  color: AnnotationPainter.contrastOn(Color(c)),
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('layers'),
            tooltip: context.ui('Layers'),
            visualDensity: VisualDensity.compact,
            onPressed: _openLayers,
            icon: Icon(
              _hidden.isEmpty ? Icons.layers_outlined : Icons.layers_clear,
              size: 20,
            ),
          ),
          Text(
            '${_items.length} marking${_items.length == 1 ? '' : 's'}',
            maxLines: 1,
            style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
          ),
        ],
      ),
    );
  }

  /// Tools offered in the simplified field toolbar. Removed creation tools
  /// (Circle, Line, Measure, Pole, Pipe, Ground) stay supported for legacy
  /// annotations through the painter and selection/editing paths.
  static const _creationTools = <AnnotationTool>{
    AnnotationTool.select,
    AnnotationTool.rectangle,
    AnnotationTool.arrow,
    AnnotationTool.text,
    AnnotationTool.freehand,
    AnnotationTool.shapeRect,
    AnnotationTool.measureLabel,
    AnnotationTool.numberMarker,
    AnnotationTool.pan,
  };

  Widget _toolBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AdinnColors.line)),
      ),
      // One compact scrollable row; no category/filter chips.
      child: SizedBox(
        height: 62,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              for (final t in AnnotationTool.values.where(
                _creationTools.contains,
              ))
                SizedBox(
                  width: 64,
                  child: KeyedSubtree(
                    key: t == AnnotationTool.rectangle
                        ? widget.tour?.signageKey
                        : null,
                    child: _ToolButton(
                      key: ValueKey('tool-${t.name}'),
                      icon: t.icon,
                      label: t.label,
                      selected: _tool == t,
                      onTap: () => _setTool(t),
                    ),
                  ),
                ),
              for (final t in widget.extraTools)
                SizedBox(
                  width: 72,
                  child: _ToolButton(
                    key: ValueKey('tool-extra-${t.id}'),
                    icon: t.icon,
                    label: t.label,
                    selected: false,
                    onTap: t.onTap,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AdinnColors.red : AdinnColors.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AdinnColors.redLight : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AdinnColors.ink,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdinnColors.canvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AdinnColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Label / measurement bottom sheet
// -----------------------------------------------------------------------------

/// Text-entry dialog whose controller follows the dialog's own lifecycle.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('annotation-text-field'),
            controller: _controller,
            autofocus: true,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: context.ui('e.g. Power point here'),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final s in const [
                'Installation remark',
                'Wall condition',
                'Pole position',
                'Fixing height',
                'Board name',
                'Electrical point',
                'Measurement clarification',
              ])
                ActionChip(
                  label: Text(
                    context.ui(s),
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final t = _controller.text.trim();
                    _controller.text = t.isEmpty ? '$s: ' : '$t, $s: ';
                    _controller.selection = TextSelection.collapsed(
                      offset: _controller.text.length,
                    );
                  },
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('annotation-text-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(context.ui('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('annotation-text-add'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(context.ui('Add')),
        ),
      ],
    );
  }
}

class _DetailsResult {
  const _DetailsResult({
    required this.label,
    this.width,
    this.height,
    this.unit = MeasureUnit.ft,
    this.itemId,
  });

  final String label;
  final double? width;
  final double? height;
  final MeasureUnit unit;
  final String? itemId;
}

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({
    required this.annotation,
    required this.isNew,
    required this.mode,
    required this.defaultUnit,
    required this.units,
  });

  final Annotation annotation;
  final bool isNew;
  final _SheetMode mode;
  final MeasureUnit defaultUnit;
  final List<AnnotationUnitOption> units;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late MeasureUnit _unit;
  String? _itemId;

  bool get _isRect => widget.mode == _SheetMode.rect;
  bool get _isValue => widget.mode == _SheetMode.value;

  @override
  void initState() {
    super.initState();
    final a = widget.annotation;
    _label = TextEditingController(text: a.label);
    _width = TextEditingController(
      text: a.measureW == null ? '' : fmtNum(a.measureW!),
    );
    _height = TextEditingController(
      text: a.measureH == null ? '' : fmtNum(a.measureH!),
    );
    _unit = (a.hasMeasurement || a.hasValue) ? a.unit : widget.defaultUnit;
    _itemId = a.itemId;
  }

  @override
  void dispose() {
    _label.dispose();
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  /// Both fields empty is allowed (measurement can be added later); one
  /// filled requires the other.
  String? _validateNumber(String? value, String other) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return other.trim().isEmpty ? null : 'Required';
    final n = double.tryParse(text);
    if (n == null || n <= 0) return 'Enter a value > 0';
    return null;
  }

  String? _validateValue(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final n = double.tryParse(text);
    if (n == null || n <= 0) return 'Enter a value > 0';
    return null;
  }

  /// Recorded measurements of the linked item (or every item) as one-tap
  /// values for a dimension line.
  List<Widget> _recordedChips() {
    final options = [
      for (final u in widget.units)
        if (_itemId == null || u.id == _itemId) u,
    ];
    final values = [
      for (final u in options)
        for (final r in u.recorded) (u, r),
    ];
    if (values.isEmpty) return const [];
    return [
      const SizedBox(height: 10),
      Text(
        context.ui('Use a recorded measurement'),
        style: TextStyle(fontSize: 12, color: AdinnColors.muted),
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < values.length; i++)
            ActionChip(
              key: ValueKey('measure-recorded-$i'),
              label: Text(
                '${options.length > 1 ? '${values[i].$1.label}: ' : ''}'
                '${values[i].$2.label} ${fmtNum(values[i].$2.value)} '
                '${values[i].$2.unit.label}',
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: () => setState(() {
                final r = values[i].$2;
                _width.text = fmtNum(r.value);
                _unit = r.unit;
                if (_label.text.trim().isEmpty) _label.text = r.label;
              }),
            ),
        ],
      ),
    ];
  }

  void _linkUnit(String? id) {
    setState(() {
      _itemId = id;
      AnnotationUnitOption? unit;
      for (final u in widget.units) {
        if (u.id == id) unit = u;
      }
      if (unit == null) return;
      if (_label.text.trim().isEmpty || widget.isNew) _label.text = unit.label;
      if (unit.hasSize &&
          _width.text.trim().isEmpty &&
          _height.text.trim().isEmpty) {
        _width.text = fmtNum(unit.width!);
        _height.text = fmtNum(unit.height!);
        _unit = unit.unit;
      }
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final w = double.tryParse(_width.text.trim());
    final h = double.tryParse(_height.text.trim());
    if (_isValue) {
      Navigator.pop(
        context,
        _DetailsResult(
          label: _label.text.trim(),
          width: w != null && w > 0 ? w : null,
          unit: _unit,
        ),
      );
      return;
    }
    final both = w != null && h != null && w > 0 && h > 0;
    Navigator.pop(
      context,
      _DetailsResult(
        label: _label.text.trim(),
        width: both ? w : null,
        height: both ? h : null,
        unit: _unit,
        itemId: _itemId,
      ),
    );
  }

  Widget _unitDropdown() => SizedBox(
    width: 96,
    child: DropdownButtonFormField<MeasureUnit>(
      key: const ValueKey('measure-unit'),
      initialValue: _unit,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: context.ui('Unit'),
        contentPadding: EdgeInsets.fromLTRB(12, 14, 6, 14),
      ),
      items: [
        for (final u in MeasureUnit.values)
          DropdownMenuItem(value: u, child: Text(u.label)),
      ],
      onChanged: (u) => setState(() => _unit = u ?? _unit),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final numberFormatter = FilteringTextInputFormatter.allow(
      RegExp(r'^\d*\.?\d{0,3}'),
    );
    final title = switch (widget.mode) {
      _SheetMode.rect =>
        widget.isNew ? 'Signage measurement' : 'Edit signage marking',
      _SheetMode.value =>
        widget.annotation.type == AnnotationType.dimension
            ? 'Dimension value'
            : 'Measurement label',
      _SheetMode.label => 'Edit label',
    };
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_isRect) ...[
                const SizedBox(height: 4),
                Text(
                  context.ui(
                    'Enter the measured board size. You can skip and add it later.',
                  ),
                  style: TextStyle(fontSize: 12.5, color: AdinnColors.muted),
                ),
              ],
              if (_isValue) ...[
                const SizedBox(height: 4),
                Text(
                  context.ui(
                    'Enter the value you measured on site. Photo pixels are '
                    'never treated as real measurements.',
                  ),
                  style: TextStyle(fontSize: 12.5, color: AdinnColors.muted),
                ),
              ],
              if (_isRect && widget.units.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('measure-item'),
                  initialValue: _itemId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.ui('Signage item'),
                    prefixIcon: Icon(Icons.link),
                  ),
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text(context.ui('Not linked')),
                    ),
                    for (final u in widget.units)
                      DropdownMenuItem(value: u.id, child: Text(u.label)),
                  ],
                  onChanged: _linkUnit,
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('measure-label'),
                controller: _label,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: context.ui('Label'),
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              if (_isRect) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('measure-width'),
                        controller: _width,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [numberFormatter],
                        decoration: InputDecoration(
                          labelText: context.ui('Width'),
                        ),
                        validator: (v) => _validateNumber(v, _height.text),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(6, 16, 6, 0),
                      child: Text('×', style: TextStyle(fontSize: 18)),
                    ),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('measure-height'),
                        controller: _height,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [numberFormatter],
                        decoration: InputDecoration(
                          labelText: context.ui('Height'),
                        ),
                        validator: (v) => _validateNumber(v, _width.text),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _unitDropdown(),
                  ],
                ),
              ],
              if (_isValue) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('measure-value'),
                        controller: _width,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [numberFormatter],
                        decoration: InputDecoration(
                          labelText: context.ui('Measured value'),
                        ),
                        validator: _validateValue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _unitDropdown(),
                  ],
                ),
                ..._recordedChips(),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('measure-skip'),
                      onPressed: () => Navigator.pop(context),
                      child: Text(widget.isNew ? 'Skip' : 'Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('measure-save'),
                      onPressed: _submit,
                      child: Text(context.ui('Save')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
