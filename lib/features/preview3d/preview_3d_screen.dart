import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/length_input.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../../data/catalog/measurement_fields.dart';
import '../drawing/signage_geometry.dart';
import '../gsb/gsb_board.dart';
import '../gsb/gsb_override_sheet.dart';
import '../gsb/gsb_rules.dart';
import '../gsb/gsb_scene.dart';
import '../model3d/parametric_builder.dart';
import '../model3d/signage_spec.dart';
import '../model3d/technical_drawing_screen.dart';
import 'renderer_painter.dart';
import 'scene3d.dart';
import 'signage_scene_builder.dart';

enum _Preset { front, side, back, top, iso }

/// Interactive 3D preview of a board and its installation structure,
/// rendered in pure Dart (CustomPainter) – no WebView or native 3D engine.
class Preview3DScreen extends StatefulWidget {
  const Preview3DScreen({
    super.key,
    required this.shopId,
    required this.boardId,
    this.unitId,
  });

  final String shopId;
  final String boardId;

  /// Signage item to show (default: the first unit of the group).
  final String? unitId;

  @override
  State<Preview3DScreen> createState() => _Preview3DScreenState();
}

class _Preview3DScreenState extends State<Preview3DScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  Camera3D _camera = const Camera3D();
  Camera3D _from = const Camera3D();
  Camera3D _to = const Camera3D();
  bool _cameraInitialised = false;
  double _startZoom = 1;
  bool _showDims = true;
  bool _panelOpen = true;
  _Preset? _preset;

  // Live "what-if" overrides in feet (null = use board values).
  double? _wFt;
  double? _hFt;
  double? _clrFt;

  SignageGeometry? _sceneGeo;
  String? _sceneBrand;
  Scene? _scene;

  // Parametric model state (13-media catalog). Business measurements only
  // change through Save / Apply; zoom and camera never touch them.
  String? _unitId;
  final Map<SpecField, double> _pending = {};
  final Set<String> _hiddenParts = {};
  String? _selectedPart;
  ParametricModel? _model;
  String? _modelKey;
  String? _statusLabel;

  // View-only options (never change measurements).
  bool _showContext = true;
  bool _xray = false;
  bool _night = false;
  bool _selectedDimsOnly = false;
  String? _modelError;

  /// GSB only: show the physical fabrication frame (rulebook members)
  /// instead of the finished light box.
  bool _fabFrame = false;
  Scene? _structScene;
  String? _structKey;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..addListener(_onTick);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _onTick() {
    final t = Curves.easeInOutCubic.transform(_anim.value);
    setState(() => _camera = Camera3D.lerp(_from, _to, t));
  }

  void _animateTo(Camera3D target, {_Preset? preset}) {
    _from = _camera;
    _to = target;
    _preset = preset;
    _anim.forward(from: 0);
  }

  double _faceYaw(SignageGeometry g) => g.isFlangeBracket ? math.pi / 2 : 0;

  Camera3D _home(SignageGeometry g) =>
      Camera3D(yaw: _faceYaw(g) + 0.55, pitch: 0.28, ortho: _camera.ortho);

  Camera3D _presetCamera(_Preset p, SignageGeometry g) {
    final face = _faceYaw(g);
    return switch (p) {
      _Preset.front => Camera3D(yaw: face, pitch: 0, ortho: _camera.ortho),
      _Preset.side => Camera3D(
        yaw: face == 0 ? math.pi / 2 : 0,
        pitch: 0,
        ortho: _camera.ortho,
      ),
      _Preset.back => Camera3D(
        yaw: face + math.pi,
        pitch: 0,
        ortho: _camera.ortho,
      ),
      _Preset.top => Camera3D(yaw: face, pitch: 1.55, ortho: _camera.ortho),
      _Preset.iso => Camera3D(
        yaw: math.pi / 4,
        pitch: math.atan(1 / math.sqrt2),
        ortho: true,
      ),
    };
  }

  Scene _sceneFor(SignageGeometry g, String brand) {
    if (_scene == null || _sceneGeo != g || _sceneBrand != brand) {
      _scene = SignageSceneBuilder.build(g, brand: brand);
      _sceneGeo = g;
      _sceneBrand = brand;
    }
    return _scene!;
  }

  void _applyToBoard(
    AppController c,
    Shop shop,
    Board board,
    SignageGeometry g,
  ) {
    if (board.mediaCode != null && !SignageCatalog.isLegacy(board.mediaCode)) {
      // Catalog media: commit through the canonical measurement sync.
      final sizeChanged = _wFt != null || _hFt != null;
      final problems = c.applySpecEdits(shop.id, board.id, _unitId!, _edits());
      if (problems.isNotEmpty) {
        showSnack(context, problems.first, error: true);
        return;
      }
      _cancelEdits();
      final u = board.unitById(_unitId);
      final stale = !sizeChanged || u == null
          ? 0
          : board
                .previewsOf(u)
                .where((p) => p.kind != CaptureKind.edited)
                .length;
      showSnack(
        context,
        stale == 0
            ? 'Measurements saved – recce form, 2D drawing and PDF use them'
            : 'Measurements saved. $stale saved preview(s) used the previous '
                  'size – open Live Preview / Camera AR and save again to '
                  'refresh them.',
      );
      return;
    }
    double round(double v) => board.unit == MeasureUnit.mm
        ? v.roundToDouble()
        : (v * 100).roundToDouble() / 100;
    board.width = round(board.unit.fromFeet(g.widthFt));
    board.height = round(board.unit.fromFeet(g.heightFt));
    if (!board.isSameSize && board.units.isNotEmpty) {
      // Different sizes: the group size mirrors unit 1.
      board.units.first
        ..width = board.width
        ..height = board.height;
    }
    final key = SignageGeometry.clearanceKey(board.installationCode);
    if (key != null && _clrFt != null) {
      board.answers[key] = (g.clearanceFt * 100).roundToDouble() / 100;
      // Keep the canonical measurement equal to the edited answer (the
      // geometry prefers recorded measurements).
      c.syncAnswerToMeasurements(board, key);
    }
    c.touchBoard(
      shop.id,
      board,
      title: 'Dimensions updated',
      message:
          '${board.name} set to ${fmtSize(board.width, board.height, board.unit)} '
          'from the 3D preview.',
    );
    setState(() {
      _wFt = null;
      _hFt = null;
      _clrFt = null;
    });
    showSnack(context, 'Board dimensions updated');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(widget.shopId);
    final board = c.board(widget.shopId, widget.boardId);
    if (shop == null || board == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('3D Preview')),
        body: const EmptyState(
          icon: Icons.view_in_ar_outlined,
          title: 'Board not found',
          message: 'It may have been removed from this shop.',
        ),
      );
    }

    final unit = board.unitById(_unitId ?? widget.unitId) ?? board.units.first;
    _unitId = unit.id;
    final g = SignageGeometry.fromBoard(
      board,
      widthFt: _wFt,
      heightFt: _hFt,
      clearanceFt: _clrFt,
      unit: unit,
    );
    if (!_cameraInitialised) {
      _camera = _from = _to = _home(g);
      _cameraInitialised = true;
    }
    final brand = (c.project(shop.projectId)?.name ?? 'Adinn').toUpperCase();
    final parametric =
        board.mediaCode != null && !SignageCatalog.isLegacy(board.mediaCode);
    final spec = parametric ? _editedSpec(board, unit) : null;
    final model = spec == null ? null : _safeModel(spec, brand);
    _statusLabel = parametric ? c.modelStatus(board.mediaCode!).label : null;
    final isGsb = GsbBoard.isGsb(board);
    final plan = isGsb
        ? GsbBoard.planFor(
            board,
            unit,
            widthIn: g.widthFt * 12,
            heightIn: g.heightFt * 12,
          )
        : null;
    final Scene scene;
    if (model == null) {
      scene = _sceneFor(g, brand);
    } else {
      final structural = isGsb && _fabFrame && plan != null && !plan.hasErrors;
      scene = _styled(
        model,
        structural ? _structureFor(model, plan, spec!) : model.scene,
        gsb: isGsb,
      );
    }
    final canEdit = c.canEdit(shop);
    final media = SignageCatalog.media(board.mediaCode);
    final inst = SignageCatalog.installation(board.installationOf(unit));
    final dirty = _isDirty;

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await confirmDialog(
          context,
          title: 'Discard changes?',
          message: 'Your dimension edits have not been saved.',
          confirmText: 'Discard',
          destructive: true,
        );
        if (ok && context.mounted) {
          _cancelEdits();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('3D Preview'),
              Text(
                '${board.name} · ${media?.shortName ?? 'Media?'} · '
                '${inst?.name ?? 'Installation?'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AdinnColors.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${shop.name} · ${board.unitLabel(unit)} · ID ${unit.id}',
                key: const Key('model_item_id'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AdinnColors.muted),
              ),
            ],
          ),
          actions: [
            IconButton(
              key: const Key('open_tech_drawing'),
              tooltip: '2D technical drawing',
              icon: const Icon(Icons.architecture),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TechnicalDrawingScreen(
                    shopId: shop.id,
                    boardId: board.id,
                    unitId: unit.id,
                  ),
                ),
              ),
            ),
            if (parametric && canEdit)
              IconButton(
                key: const Key('model_save'),
                tooltip: 'Save changes',
                icon: Icon(
                  Icons.save_outlined,
                  color: dirty ? AdinnColors.red : null,
                ),
                onPressed: dirty
                    ? () => _applyToBoard(c, shop, board, g)
                    : null,
              ),
            IconButton(
              tooltip: _camera.ortho
                  ? 'Switch to perspective'
                  : 'Switch to orthographic',
              icon: Icon(_camera.ortho ? Icons.grid_on : Icons.threed_rotation),
              onPressed: () => setState(
                () => _camera = _camera.copyWith(ortho: !_camera.ortho),
              ),
            ),
            IconButton(
              tooltip: _showDims ? 'Hide dimensions' : 'Show dimensions',
              icon: Icon(
                Icons.straighten,
                color: _showDims ? AdinnColors.red : AdinnColors.muted,
              ),
              onPressed: () => setState(() => _showDims = !_showDims),
            ),
            IconButton(
              tooltip: 'Reset view',
              icon: const Icon(Icons.restart_alt),
              onPressed: () => _animateTo(_home(g)),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              if (board.units.length > 1) _unitPicker(board, unit),
              Expanded(child: _viewport(scene, g, model, gsb: isGsb)),
              _dimensionPanel(
                c,
                shop,
                board,
                g,
                SignageGeometry.fromBoard(board, unit: unit),
                canEdit,
                maxHeight: constraints.maxHeight * 0.42,
                spec: spec,
                model: model,
                plan: plan,
                unit: unit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Parametric model (13-media catalog)
  // ---------------------------------------------------------------------------

  bool get _isDirty =>
      _wFt != null || _hFt != null || _clrFt != null || _pending.isNotEmpty;

  /// Uncommitted edits of the current preview, in spec terms (mm).
  Map<SpecField, double> _edits() => {
    ..._pending,
    if (_wFt != null) SpecField.width: _wFt! * kMmPerFoot,
    if (_hFt != null) SpecField.height: _hFt! * kMmPerFoot,
    if (_clrFt != null) SpecField.mountingHeight: _clrFt! * kMmPerFoot,
  };

  /// Structural GSB scene, rebuilt only when the model or plan changes
  /// (never on day / night toggles or camera moves).
  Scene _structureFor(
    ParametricModel model,
    GsbFabricationPlan plan,
    SignageModelSpec spec,
  ) {
    final i = plan.input;
    final key = [
      identityHashCode(model),
      i.variant.key,
      i.widthIn,
      i.heightIn,
      i.depthIn,
      i.profileWidthIn,
      i.profileHeightIn,
      spec.mountingHeightMm,
    ].join('|');
    if (_structScene == null || _structKey != key) {
      _structScene = gsbStructureScene(
        model,
        plan,
        mountingFt: spec.mountingHeightMm / kMmPerFoot,
      );
      _structKey = key;
    }
    return _structScene!;
  }

  SignageModelSpec _editedSpec(Board board, SignageUnit unit) {
    var base = SignageModelSpec.of(board, unit);
    if (GsbBoard.isGsb(board)) {
      // Provisional preview of active (unapproved) GSB overrides; never
      // written to the recce measurements.
      final depthOv = GsbBoard.activeOverride(
        board,
        unit.id,
        GsbOverrideField.depth,
      );
      final profOv = GsbBoard.activeOverride(
        board,
        unit.id,
        GsbOverrideField.profileWidth,
      );
      final ov = <SpecField, double>{
        if (depthOv != null) SpecField.depth: depthOv.proposedIn * 25.4,
        if (profOv != null) SpecField.frameThickness: profOv.proposedIn * 25.4,
      };
      if (ov.isNotEmpty) base = base.copyWith(values: ov);
    }
    final edits = _edits();
    return edits.isEmpty ? base : base.copyWith(values: edits);
  }

  /// Builds the model; on an unexpected geometry error the legacy preview is
  /// shown instead with a message (never a crash or a blank canvas).
  ParametricModel? _safeModel(SignageModelSpec spec, String brand) {
    try {
      final m = _modelFor(spec, brand);
      _modelError = null;
      return m;
    } catch (e) {
      _model = null;
      _modelKey = null;
      _modelError =
          'The 3D model could not be built ($e). A basic '
          'preview is shown; measurements are not affected.';
      return null;
    }
  }

  /// View styling: surroundings, X-ray (transparent) material, night
  /// appearance and selected-component dimensions. Display only.
  Scene _styled(ParametricModel model, Scene base, {bool gsb = false}) {
    final selected = model.component(_selectedPart ?? '');
    final dims = _selectedDimsOnly && selected != null
        ? [
            for (final d in model.dimensions)
              if (d.field != null && selected.editable.contains(d.field))
                d.toDim3(),
          ]
        : null;
    if (!_xray && !_night && dims == null) return base;
    Color tone(Color c, bool emissive) {
      var out = c;
      if (_night && !emissive) {
        // GSB: moderate soft-blue evening that keeps the facade and
        // shutter readable; other media keep the original night tone.
        out = gsb
            ? Color.lerp(c, const Color(0xFF22314F), 0.42)!
            : Color.lerp(c, const Color(0xFF0B1020), 0.62)!;
      }
      if (_xray) out = out.withValues(alpha: math.min(out.a, 0.35));
      return out;
    }

    Face restyle(Face f) => Face(
      f.points,
      tone(f.color, f.emissive),
      f.normal,
      outline: f.outline || _xray,
      emissive: f.emissive,
      label: f.label,
      labelColor: f.labelColor,
      layer: f.layer,
    );
    final scene = Scene(focus: base.focus);
    for (final s in base.solids) {
      final copy = Solid(
        name: s.name,
        faces: [for (final f in s.faces) restyle(f)],
      );
      copy.decals.addAll([for (final f in s.decals) restyle(f)]);
      copy.decalNormal = s.decalNormal;
      scene.add(copy);
    }
    scene.dims.addAll(dims ?? base.dims);
    scene.finalize();
    return scene;
  }

  ParametricModel _modelFor(SignageModelSpec spec, String brand) {
    final key = [
      _showContext,
      spec.signageItemId,
      spec.mediaCode,
      spec.installationCode,
      spec.isDoubleSided,
      for (final e in spec.values.entries) '${e.key.name}=${e.value}',
      ...(_hiddenParts.toList()..sort()),
      _selectedPart,
      brand,
    ].join('|');
    if (_model == null || _modelKey != key) {
      _model = ParametricModelBuilder.build(
        spec,
        brand: brand,
        hiddenComponents: Set.of(_hiddenParts),
        highlight: _selectedPart,
        context: _showContext,
      );
      _modelKey = key;
    }
    return _model!;
  }

  void _cancelEdits() => setState(() {
    _wFt = null;
    _hFt = null;
    _clrFt = null;
    _pending.clear();
  });

  Widget _unitPicker(Board board, SignageUnit unit) => Container(
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    child: Row(
      children: [
        const Text('Signage item', style: TextStyle(fontSize: 12.5)),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButton<String>(
            key: const Key('model_unit'),
            value: unit.id,
            isExpanded: true,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final u in board.activeUnits)
                DropdownMenuItem(
                  value: u.id,
                  child: Text(
                    '${board.unitLabel(u)} • '
                    '${fmtSize(board.widthOf(u), board.heightOf(u), board.unit)}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
            onChanged: (v) {
              if (v == null || v == unit.id) return;
              if (_isDirty) {
                showSnack(context, 'Save or cancel the current edits first');
                return;
              }
              setState(() {
                _unitId = v;
                _selectedPart = null;
                _hiddenParts.clear();
              });
            },
          ),
        ),
      ],
    ),
  );

  String _fmtField(SpecField f, double v, MeasureUnit unit) => switch (f.kind) {
    SpecValueKind.length => fmtMm(v, unit),
    SpecValueKind.count => '${v.round()}',
    SpecValueKind.angle => '${v.toStringAsFixed(0)}°',
  };

  double _step(SpecField f, MeasureUnit unit) => switch (f.kind) {
    SpecValueKind.count => 1,
    SpecValueKind.angle => 1,
    SpecValueKind.length =>
      unit == MeasureUnit.mm || unit == MeasureUnit.m ? 10 : 25.4,
  };

  Future<void> _typeValue(SignageModelSpec spec, SpecField f) async {
    final unit = spec.displayUnit;
    final ctl = TextEditingController(
      text: f.kind == SpecValueKind.length
          ? fmtMmValue(spec[f], unit)
          : spec[f].toStringAsFixed(f.kind == SpecValueKind.count ? 0 : 1),
    );
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(f.label),
        content: TextField(
          key: const Key('spec_value_field'),
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: switch (f.kind) {
              SpecValueKind.length => unit.label,
              SpecValueKind.angle => 'deg',
              SpecValueKind.count => null,
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('spec_value_ok'),
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (r == null || !mounted) return;
    final v = double.tryParse(r.trim());
    if (v == null) {
      showSnack(context, 'Enter a number', error: true);
      return;
    }
    final mm = f.kind == SpecValueKind.length ? unit.toMm(v) : v;
    final problems = SignageModelSpec.validate({f: mm});
    if (problems.isNotEmpty) {
      showSnack(context, problems.first, error: true);
      return;
    }
    setState(() => _pending[f] = mm);
  }

  Widget _specRow(SignageModelSpec spec, SpecField f, bool canEdit) {
    final unit = spec.displayUnit;
    final edited = _pending.containsKey(f);
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${f.label}${spec.isAssumed(f) && !edited ? ' *' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          if (canEdit)
            IconButton(
              key: Key('spec_${f.name}_minus'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: () {
                final v = (_pending[f] ?? spec[f]) - _step(f, unit);
                if (SignageModelSpec.validate({f: v}).isEmpty) {
                  setState(() => _pending[f] = v);
                }
              },
            ),
          InkWell(
            key: Key('spec_${f.name}'),
            onTap: canEdit ? () => _typeValue(spec, f) : null,
            child: Container(
              constraints: const BoxConstraints(minWidth: 72),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: edited ? AdinnColors.redLight : AdinnColors.canvas,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _fmtField(f, spec[f], unit),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (canEdit)
            IconButton(
              key: Key('spec_${f.name}_plus'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: () => setState(
                () => _pending[f] = (_pending[f] ?? spec[f]) + _step(f, unit),
              ),
            ),
        ],
      ),
    );
  }

  /// Component list (select / highlight / show-hide / reset) and the
  /// structural dimensions of the selected component.
  Widget _structurePanel(
    SignageModelSpec spec,
    ParametricModel model,
    bool canEdit, {
    bool gsb = false,
  }) {
    final parts = [
      for (final p in model.components)
        if (!p.isContext) p,
    ];
    final selected = model.component(_selectedPart ?? '');
    const sizeFields = {
      SpecField.width,
      SpecField.height,
      SpecField.mountingHeight,
    };
    // GSB depth / frame profile only change through the reviewed override
    // workflow (GSB fabrication section), never by free editing.
    const gsbLocked = {SpecField.depth, SpecField.frameThickness};
    final fields = [
      for (final f in (selected?.editable ?? spec.editableFields))
        if (!sizeFields.contains(f) &&
            spec.has(f) &&
            !(gsb && gsbLocked.contains(f)))
          f,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (model.unsupported.isNotEmpty)
          Container(
            key: const Key('model_unsupported'),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            color: const Color(0xFFFFF4E5),
            child: Text(
              model.unsupported.first,
              style: const TextStyle(
                fontSize: 11.5,
                color: AdinnColors.warning,
              ),
            ),
          ),
        const Text(
          'View',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final (key, label, value, onChanged) in [
              (
                'view_context',
                'Wall & ground',
                _showContext,
                (bool v) => _showContext = v,
              ),
              ('view_xray', 'Transparent', _xray, (bool v) => _xray = v),
              ('view_night', 'Night', _night, (bool v) => _night = v),
              (
                'view_selected_dims',
                'Selected dims only',
                _selectedDimsOnly,
                (bool v) => _selectedDimsOnly = v,
              ),
              if (gsb)
                (
                  'view_gsb_frame',
                  'Fabrication frame',
                  _fabFrame,
                  (bool v) => _fabFrame = v,
                ),
            ])
              FilterChip(
                key: Key(key),
                label: Text(label, style: const TextStyle(fontSize: 11.5)),
                visualDensity: VisualDensity.compact,
                selected: value,
                onSelected: (v) => setState(() => onChanged(v)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Structure',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final p in parts)
              FilterChip(
                key: Key('comp_${p.id}'),
                label: Text(
                  p.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    decoration: _hiddenParts.contains(p.id)
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                visualDensity: VisualDensity.compact,
                selected: _selectedPart == p.id,
                onSelected: (v) =>
                    setState(() => _selectedPart = v ? p.id : null),
              ),
          ],
        ),
        if (selected != null)
          Wrap(
            children: [
              TextButton.icon(
                key: const Key('comp_toggle'),
                onPressed: () => setState(() {
                  if (!_hiddenParts.remove(selected.id)) {
                    _hiddenParts.add(selected.id);
                  }
                }),
                icon: Icon(
                  _hiddenParts.contains(selected.id)
                      ? Icons.visibility
                      : Icons.visibility_off,
                  size: 18,
                ),
                label: Text(
                  _hiddenParts.contains(selected.id) ? 'Show' : 'Hide',
                ),
              ),
              if (canEdit)
                TextButton.icon(
                  key: const Key('comp_reset'),
                  onPressed: () => setState(() {
                    for (final f in selected.editable) {
                      _pending.remove(f);
                    }
                  }),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Reset component'),
                ),
            ],
          ),
        for (final f in fields) _specRow(spec, f, canEdit),
        if (spec.sources.values.contains(SpecSource.assumed))
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '* Not measured yet – illustrative default shown. Illustrative '
              'parametric model, not a fabrication drawing.',
              style: TextStyle(fontSize: 11, color: AdinnColors.muted),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('model_restore'),
            onPressed: () => setState(() {
              _pending.clear();
              _hiddenParts.clear();
              _selectedPart = null;
              _showContext = true;
              _xray = false;
              _night = false;
              _selectedDimsOnly = false;
              _fabFrame = false;
              _wFt = null;
              _hFt = null;
              _clrFt = null;
            }),
            child: const Text('Restore default view & values'),
          ),
        ),
      ],
    );
  }

  Widget _viewport(
    Scene scene,
    SignageGeometry g,
    ParametricModel? model, {
    bool gsb = false,
  }) {
    final nightView = _night && model != null;
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                setState(() {
                  _camera = _camera.copyWith(
                    zoom: _camera.zoom * math.exp(-e.scrollDelta.dy * 0.0015),
                  );
                });
              }
            },
            child: GestureDetector(
              key: const Key('preview3d-viewport'),
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) {
                _anim.stop();
                _startZoom = _camera.zoom;
              },
              onScaleUpdate: (d) {
                setState(() {
                  _preset = null;
                  if (d.pointerCount <= 1) {
                    final delta = d.focalPointDelta;
                    _camera = _camera.copyWith(
                      yaw: _camera.yaw - delta.dx * 0.009,
                      pitch: _camera.pitch + delta.dy * 0.009,
                    );
                  } else {
                    _camera = _camera.copyWith(
                      zoom: _startZoom * d.scale,
                      pan: _camera.pan + d.focalPointDelta,
                    );
                  }
                });
              },
              onDoubleTap: () => _animateTo(_home(g)),
              child: Container(
                decoration: BoxDecoration(
                  color: nightView && !gsb
                      ? const Color(0xFF0B1020)
                      : Colors.transparent,
                  gradient: nightView && gsb
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF15203A), Color(0xFF34436A)],
                        )
                      : null,
                ),
                child: CustomPaint(
                  painter: Scene3DPainter(
                    scene: scene,
                    camera: _camera,
                    showDimensions: _showDims,
                    paintBackground: !nightView,
                    paintGround: _showContext || model == null,
                    night: nightView && gsb,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          top: 8,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (p, label) in [
                  (_Preset.front, 'Front'),
                  (_Preset.side, 'Side'),
                  (_Preset.back, 'Back'),
                  (_Preset.top, 'Top'),
                  (_Preset.iso, 'Isometric'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _preset == p,
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.white,
                      onSelected: (_) =>
                          _animateTo(_presetCamera(p, g), preset: p),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 8,
          top: 56,
          child: Column(
            children: [
              _roundButton(
                Icons.add,
                'Zoom in',
                () => setState(
                  () => _camera = _camera.copyWith(zoom: _camera.zoom * 1.25),
                ),
              ),
              const SizedBox(height: 6),
              _roundButton(
                Icons.remove,
                'Zoom out',
                () => setState(
                  () => _camera = _camera.copyWith(zoom: _camera.zoom / 1.25),
                ),
              ),
              const SizedBox(height: 6),
              _roundButton(
                Icons.fit_screen,
                'Fit model',
                () => setState(
                  () => _camera = _camera.copyWith(zoom: 1, pan: Offset.zero),
                ),
              ),
            ],
          ),
        ),
        if (_modelError != null)
          Positioned(
            left: 8,
            right: 56,
            top: 96,
            child: Container(
              key: const Key('model_error'),
              padding: const EdgeInsets.all(8),
              color: const Color(0xFFFFF4E5),
              child: Text(
                _modelError!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AdinnColors.warning,
                ),
              ),
            ),
          ),
        if (gsb && model != null)
          Positioned(left: 8, bottom: 40, child: _gsbRenderToggle()),
        if (_statusLabel != null)
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              key: const Key('model_status'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdinnColors.line),
              ),
              child: Text(
                _statusLabel!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (model == null
            ? g.anyDefaults
            : !g.mediaSelected || !g.installationSelected || g.usingDefaults)
          Positioned(left: 8, right: 56, top: 52, child: _banner(g)),
        Positioned(
          left: 56,
          right: 8,
          bottom: 8,
          child: Align(
            alignment: Alignment.bottomRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Yaw ${_camera.yawDegrees}° · Pitch ${_camera.pitchDegrees}° · '
                '${fmtNum(_camera.zoom, maxDecimals: 1)}× · '
                '${_camera.ortho ? 'Ortho' : 'Persp'}',
                key: const Key('preview3d-hud'),
                style: const TextStyle(fontSize: 11, color: AdinnColors.muted),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _banner(SignageGeometry g) {
    final parts = [
      if (!g.mediaSelected) 'media not selected',
      if (!g.installationSelected) 'installation not selected',
      if (g.usingDefaults) 'size not entered (10 × 4 ft shown)',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdinnColors.warning.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Default preview – ${parts.join(', ')}',
        style: const TextStyle(fontSize: 11, color: AdinnColors.warning),
      ),
    );
  }

  /// Render View (GSB Single / Double): Day | Night. Toggling restyles
  /// colours only – camera, geometry and quantities are untouched.
  Widget _gsbRenderToggle() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        key: const Key('gsb_render_view'),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AdinnColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (night, label, icon) in const [
              (false, 'Day', Icons.wb_sunny_outlined),
              (true, 'Night', Icons.nightlight_round),
            ])
              InkWell(
                key: Key('gsb_render_${night ? 'night' : 'day'}'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _night = night),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _night == night
                        ? (night ? const Color(0xFF1B2846) : AdinnColors.red)
                        : null,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: _night == night
                            ? Colors.white
                            : AdinnColors.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _night == night
                              ? Colors.white
                              : AdinnColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      if (_night)
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          color: Colors.black.withValues(alpha: 0.5),
          child: const Text(
            'Illustrative night render',
            style: TextStyle(color: Colors.white, fontSize: 10),
          ),
        ),
    ],
  );

  /// GSB fabrication summary: variant, depth, frame profile, wall
  /// thickness, modules and review items, with the override workflow.
  Widget _gsbPanel(
    AppController c,
    Shop shop,
    Board board,
    SignageUnit unit,
    GsbFabricationPlan plan,
    bool canEdit,
  ) {
    final i = plan.input;
    String inch(double v) => '${fmtNum(v)} in';
    final depthOv = GsbBoard.activeOverride(
      board,
      unit.id,
      GsbOverrideField.depth,
    );
    final reviews = plan.reviewItems.toList();
    final errors = plan.issues
        .where((x) => x.level == GsbIssueLevel.error)
        .toList();
    final history = GsbBoard.overridesOf(board, unit.id);
    Widget line(String k, String v, {bool flag = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              k,
              style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: flag ? AdinnColors.warning : AdinnColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
    final cols = plan.columnsIn, rows = plan.rowsIn;
    final modules = plan.modules.length <= 1
        ? (plan.heightSplit && rows == null
              ? 'Split required – partition needs review'
              : 'Single module')
        : '${plan.modules.length} modules · '
              '${cols!.map(fmtNum).join(' + ')} in wide · '
              '${rows!.map(fmtNum).join(' + ')} in high';
    return Container(
      key: const Key('gsb_fab_panel'),
      margin: const EdgeInsets.only(top: 6, bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdinnColors.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdinnColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.engineering, size: 18, color: AdinnColors.red),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'GSB fabrication · ${i.variant.label}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (plan.requiresReview || depthOv != null)
            Container(
              key: const Key('gsb_review_tag'),
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AdinnColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.rule, size: 14, color: AdinnColors.warning),
                  SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Requires Engineering Review',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AdinnColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          line(
            'Board depth',
            i.usesDefaultDepth
                ? '${inch(i.depthIn)} (default)'
                : '${inch(i.depthIn)} (default 8 in · '
                      '${depthOv != null ? 'override – provisional' : 'recorded'})',
            flag: !i.usesDefaultDepth,
          ),
          line(
            'Frame profile',
            '${fmtNum(i.profileWidthIn)} × ${fmtNum(i.profileHeightIn)} in MS SHS'
                '${i.usesDefaultProfile ? ' (default)' : ' (override – provisional)'}',
            flag: !i.usesDefaultProfile,
          ),
          line(
            'Pipe wall thickness',
            i.wallThicknessIn == null
                ? 'Unspecified – requires engineering confirmation'
                : '${inch(i.wallThicknessIn!)} (override – provisional)',
            flag: true,
          ),
          line('Modules', modules),
          line(
            'Members',
            '${plan.count(GsbMemberRole.internalVertical)} internal verticals'
                ' (${i.variant.isDouble ? 'centre depth' : 'rear plane'}) · '
                '${plan.count(GsbMemberRole.brace)} braces · '
                '${plan.count(GsbMemberRole.seamBrace)} seam braces · '
                '${plan.inserts.length} couplings',
          ),
          line(
            'Cladding',
            '${plan.printFlexFaces == 2 ? 'Front + rear' : 'Front'} flex · '
                '${plan.hasRearGi ? 'rear GI · ' : ''}'
                '${plan.trimPieceCount} powder-coated trim pieces · '
                '1 LED set',
          ),
          for (final e in errors)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                e.message,
                style: const TextStyle(fontSize: 11.5, color: AdinnColors.red),
              ),
            ),
          if (reviews.isNotEmpty)
            Material(
              type: MaterialType.transparency,
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: const Key('gsb_review_items'),
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '${reviews.length} item(s) need engineering review',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdinnColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  children: [
                    for (final r in reviews)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• ${r.message}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          for (final o in history.reversed.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${o.field.label}: '
                      '${o.originalIn == null ? 'unspecified' : inch(o.originalIn!)}'
                      ' → ${inch(o.proposedIn)} · ${o.status.label}\n'
                      '“${o.reason}” · ${fmtDateTime(o.createdAt)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: o.isActive
                            ? AdinnColors.warning
                            : AdinnColors.muted,
                      ),
                    ),
                  ),
                  if (o.isActive && canEdit)
                    TextButton(
                      key: Key('gsb_revert_${o.id}'),
                      onPressed: () =>
                          c.revertGsbOverride(shop.id, board, o.id),
                      child: const Text('Revert'),
                    ),
                ],
              ),
            ),
          if (canEdit)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('gsb_override'),
                onPressed: () => showGsbOverrideSheet(
                  context,
                  shopId: shop.id,
                  board: board,
                  unit: unit,
                  plan: plan,
                ),
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Edit / Override depth or frame'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _roundButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(side: BorderSide(color: AdinnColors.line)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 20, color: AdinnColors.ink),
          ),
        ),
      ),
    );
  }

  Widget _dimensionPanel(
    AppController c,
    Shop shop,
    Board board,
    SignageGeometry g,
    SignageGeometry saved,
    bool canEdit, {
    required double maxHeight,
    SignageModelSpec? spec,
    ParametricModel? model,
    GsbFabricationPlan? plan,
    SignageUnit? unit,
  }) {
    final u = g.unit;
    final dirty = _isDirty;
    final clrKey = spec != null
        ? 'mounting'
        : SignageGeometry.clearanceKey(g.installationCode);
    final mountFt = spec == null
        ? g.clearanceFt
        : spec.mountingHeightMm / kMmPerFoot;
    final mountLabel = spec == null
        ? SignageGeometry.clearanceLabel(g.installationCode)
        : 'Mounting height';
    final summary =
        '${fmtLength(g.widthFt, u)} × ${fmtLength(g.heightFt, u)}'
        '${clrKey == null ? '' : ' · $mountLabel ${fmtLength(mountFt, u)}'}';

    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _panelOpen = !_panelOpen),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.straighten,
                      size: 18,
                      color: AdinnColors.red,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Dimensions',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdinnColors.muted,
                        ),
                      ),
                    ),
                    Icon(
                      _panelOpen ? Icons.expand_more : Icons.expand_less,
                      color: AdinnColors.muted,
                    ),
                  ],
                ),
              ),
            ),
            if (_panelOpen)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: math.max(80, maxHeight)),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Column(
                    children: [
                      _slider(
                        key: const Key('width-slider'),
                        fieldKey: const Key('width-exact'),
                        label: 'Width',
                        valueFt: g.widthFt,
                        minFt: 1,
                        maxFt: math.max(40, (saved.widthFt * 2).ceilToDouble()),
                        limitFt: _maxWidthFt,
                        unit: u,
                        onChanged: (v) => setState(() => _wFt = v),
                      ),
                      _slider(
                        key: const Key('height-slider'),
                        fieldKey: const Key('height-exact'),
                        label: 'Height',
                        valueFt: g.heightFt,
                        minFt: 0.5,
                        maxFt: math.max(
                          20,
                          (saved.heightFt * 2).ceilToDouble(),
                        ),
                        limitFt: _maxHeightFt,
                        unit: u,
                        onChanged: (v) => setState(() => _hFt = v),
                      ),
                      if (clrKey != null)
                        _slider(
                          key: const Key('clearance-slider'),
                          fieldKey: const Key('clearance-exact'),
                          label: mountLabel,
                          valueFt: mountFt,
                          minFt: 0,
                          maxFt: math.max(
                            30,
                            (saved.clearanceFt * 2).ceilToDouble(),
                          ),
                          limitFt: _maxMountFt,
                          allowZero: true,
                          unit: u,
                          onChanged: (v) => setState(() => _clrFt = v),
                        ),
                      Row(
                        children: [
                          TextButton(
                            key: const Key('model_cancel'),
                            onPressed: dirty ? _cancelEdits : null,
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: canEdit
                                  ? FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(0, 40),
                                        ),
                                        onPressed: dirty
                                            ? () => _applyToBoard(
                                                c,
                                                shop,
                                                board,
                                                g,
                                              )
                                            : null,
                                        icon: const Icon(Icons.check, size: 18),
                                        label: const Text('Apply to board'),
                                      ),
                                    )
                                  : const Text(
                                      'View only – changes are not saved',
                                      textAlign: TextAlign.right,
                                      maxLines: 2,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AdinnColors.muted,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      if (plan != null && unit != null)
                        _gsbPanel(c, shop, board, unit, plan, canEdit),
                      if (spec != null && model != null)
                        _structurePanel(
                          spec,
                          model,
                          canEdit,
                          gsb: GsbBoard.isGsb(board),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Sanity limits for typed values (the slider range adapts up to these;
  /// typed values are never silently clamped to the old slider range).
  static const _maxWidthFt = 200.0;
  static const _maxHeightFt = 100.0;
  static const _maxMountFt = 200.0;

  /// `Label  [exact input]  [slider]` – one authoritative value (the
  /// pending edit in feet, full precision); typing updates the slider and
  /// sliding updates the text.
  Widget _slider({
    required Key key,
    required Key fieldKey,
    required String label,
    required double valueFt,
    required double minFt,
    required double maxFt,
    required double limitFt,
    required MeasureUnit unit,
    required ValueChanged<double> onChanged,
    bool allowZero = false,
  }) {
    // Grow the slider range to include a typed value instead of clamping.
    final lo = math.min(minFt, valueFt);
    final hi = math.max(maxFt, math.min(limitFt, valueFt * 1.25));
    final value = valueFt.clamp(lo, hi).toDouble();
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          SizedBox(
            width: 104,
            child: ExactLengthField(
              key: fieldKey,
              label: label,
              valueFt: valueFt,
              unit: unit,
              maxFt: limitFt,
              allowZero: allowZero,
              onCommitted: onChanged,
            ),
          ),
          Expanded(
            child: Slider(
              key: key,
              value: value,
              min: lo,
              max: hi,
              divisions: math.max(1, ((hi - lo) / 0.25).round()),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Editable exact length (e.g. `5 ft 6 in`). Shows the authoritative value
/// while not focused; parses and validates on submit / focus loss and only
/// then reports a value – invalid text is never committed.
class ExactLengthField extends StatefulWidget {
  const ExactLengthField({
    super.key,
    required this.label,
    required this.valueFt,
    required this.unit,
    required this.onCommitted,
    this.maxFt,
    this.allowZero = false,
  });

  final String label;
  final double valueFt;
  final MeasureUnit unit;
  final ValueChanged<double> onCommitted;
  final double? maxFt;
  final bool allowZero;

  @override
  State<ExactLengthField> createState() => _ExactLengthFieldState();
}

class _ExactLengthFieldState extends State<ExactLengthField> {
  late final TextEditingController _ctl;
  final _focus = FocusNode();
  String? _error;

  String get _formatted => formatLengthInput(widget.valueFt, widget.unit);

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: _formatted);
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _ctl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _ctl.text.length,
        );
      } else {
        _commit(revertOnError: true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ExactLengthField old) {
    super.didUpdateWidget(old);
    // Slider moved / edits cancelled: follow the authoritative value
    // unless the user is typing.
    if (!_focus.hasFocus &&
        (old.valueFt != widget.valueFt || old.unit != widget.unit)) {
      _ctl.text = _formatted;
      _error = null;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctl.dispose();
    super.dispose();
  }

  void _commit({bool revertOnError = false}) {
    final ft = parseLengthToFeet(_ctl.text, widget.unit);
    final err = validateLengthFeet(
      ft,
      label: widget.label,
      maxFt: widget.maxFt,
      allowZero: widget.allowZero,
    );
    if (err != null) {
      if (revertOnError) {
        setState(() => _error = null);
        _ctl.text = _formatted;
        if (mounted) showSnack(context, err, error: true);
      } else {
        setState(() => _error = err);
        showSnack(context, err, error: true);
      }
      return;
    }
    setState(() => _error = null);
    if ((ft! - widget.valueFt).abs() > 1e-9) widget.onCommitted(ft);
    if (!_focus.hasFocus) _ctl.text = formatLengthInput(ft, widget.unit);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctl,
      focusNode: _focus,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: const OutlineInputBorder(),
        errorText: _error,
        errorStyle: const TextStyle(fontSize: 0, height: 0),
        hintText:
            widget.unit == MeasureUnit.ft || widget.unit == MeasureUnit.inch
            ? '5 ft 6 in'
            : null,
      ),
      onSubmitted: (_) {
        _commit();
        if (_error == null) _focus.unfocus();
      },
      onTapOutside: (_) => _focus.unfocus(),
    );
  }
}
