import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../drawing/signage_geometry.dart';
import '../preview_live/live_preview_controller.dart' show unitGeometry;
import 'ar_scene_controller.dart';
import 'ar_scene_engine.dart';
import 'ar_scene_items.dart';

// -----------------------------------------------------------------------------
// Shared bits
// -----------------------------------------------------------------------------

class _PanelHeader extends StatelessWidget {
  const _PanelHeader(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      ?trailing,
    ],
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.color = AdinnColors.muted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2, bottom: 4),
    child: Text(text, style: TextStyle(fontSize: 11.5, color: color)),
  );
}

/// Numeric entry + apply. Shows the current value while not being edited.
class _NumberField extends StatefulWidget {
  const _NumberField({
    super.key,
    required this.value,
    required this.suffix,
    required this.onSubmit,
    this.enabled = true,
    this.signed = false,
  });

  final String value;
  final String suffix;
  final bool enabled;
  final bool signed;

  /// Returns an error message (shown under the field) or null.
  final Future<String?> Function(String text) onSubmit;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.value,
  );
  final _focus = FocusNode();
  String? _error;

  @override
  void didUpdateWidget(covariant _NumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final error = await widget.onSubmit(_c.text);
    if (!mounted) return;
    setState(() => _error = error);
    if (error == null) {
      _focus.unfocus();
      _c.text = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 128,
    child: TextField(
      controller: _c,
      focusNode: _focus,
      enabled: widget.enabled,
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: widget.signed,
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        suffixText: widget.suffix,
        errorText: _error,
        errorMaxLines: 2,
        suffixIcon: IconButton(
          tooltip: 'Apply',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.check, size: 18),
          onPressed: widget.enabled ? _submit : null,
        ),
      ),
    ),
  );
}

Widget _fineToggle(ArSceneController scene, String label) => FilterChip(
  key: const ValueKey('ar_fine'),
  label: Text(label, style: const TextStyle(fontSize: 11.5)),
  selected: scene.fineSteps,
  visualDensity: VisualDensity.compact,
  onSelected: scene.setFineSteps,
);

// -----------------------------------------------------------------------------
// Tool panel
// -----------------------------------------------------------------------------

/// Compact panel of the active editing tool (one tool at a time).
class ArToolPanel extends StatelessWidget {
  const ArToolPanel({
    super.key,
    required this.scene,
    required this.board,
    required this.unit,
    required this.editable,
    this.onEditDimensions,
  });

  final ArSceneController scene;

  /// Media group / signage unit of the selected placement (business data,
  /// read-only here).
  final Board? board;
  final SignageUnit? unit;
  final bool editable;
  final VoidCallback? onEditDimensions;

  @override
  Widget build(BuildContext context) {
    final p = scene.selected;
    final body = switch (scene.tool) {
      ArTool.scale => _ScalePanel(scene: scene),
      ArTool.rotate => _RotatePanel(scene: scene),
      ArTool.move => _MovePanel(scene: scene),
      ArTool.dimensions => _DimensionsPanel(
        scene: scene,
        board: board,
        unit: unit,
        editable: editable,
        onEditDimensions: onEditDimensions,
      ),
      ArTool.none => const SizedBox.shrink(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PanelHeader(
          '${scene.tool.label}${p == null ? '' : ' • ${p.displayName}'}',
          trailing: IconButton(
            key: const ValueKey('ar_tool_close'),
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => scene.setTool(scene.tool),
          ),
        ),
        if (p == null && scene.tool != ArTool.dimensions)
          const _Hint('Select a model first: tap it, or use Objects.')
        else if (p != null && p.locked && scene.tool != ArTool.dimensions)
          _Hint(
            '${p.displayName} is locked. Unlock it in Objects to edit.',
            color: AdinnColors.warning,
          ),
        body,
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Scale
// -----------------------------------------------------------------------------

class _ScalePanel extends StatelessWidget {
  const _ScalePanel({required this.scene});

  final ArSceneController scene;

  @override
  Widget build(BuildContext context) {
    final p = scene.selected;
    final t = p?.transform ?? const ArObjectTransform();
    final enabled = scene.canEditSelected;
    final percent = t.scalePercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              'Scale: $percent%',
              key: const ValueKey('ar_scale_value'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            if (p != null)
              Expanded(
                child: Text(
                  'Actual: ${p.sizeText}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AdinnColors.muted,
                  ),
                ),
              ),
          ],
        ),
        if (t.scaleAdjusted)
          Container(
            key: const ValueKey('ar_scale_warning'),
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AdinnColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Preview Scale Adjusted – Not Actual Size',
              style: TextStyle(
                color: AdinnColors.warning,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Row(
          children: [
            IconButton(
              key: const ValueKey('ar_scale_minus'),
              tooltip: 'Smaller',
              onPressed: enabled && t.scale > ArObjectTransform.minScale
                  ? () => scene.stepScale(-1)
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Expanded(
              child: Slider(
                key: const ValueKey('ar_scale_slider'),
                value: (t.scale * 100).clamp(10, 300).toDouble(),
                min: ArObjectTransform.minScale * 100,
                max: ArObjectTransform.maxScale * 100,
                label: '$percent%',
                onChangeStart: enabled ? (_) => scene.beginGesture() : null,
                onChanged: enabled ? (v) => scene.setScale(v / 100) : null,
                onChangeEnd: enabled ? (_) => scene.endGesture('Scale') : null,
              ),
            ),
            IconButton(
              key: const ValueKey('ar_scale_plus'),
              tooltip: 'Larger',
              onPressed: enabled && t.scale < ArObjectTransform.maxScale
                  ? () => scene.stepScale(1)
                  : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _NumberField(
              key: const ValueKey('ar_scale_input'),
              value: '$percent',
              suffix: '%',
              enabled: enabled,
              onSubmit: scene.setScalePercentText,
            ),
            _fineToggle(scene, 'Fine 1%'),
            OutlinedButton(
              key: const ValueKey('ar_scale_reset'),
              onPressed: enabled ? scene.resetScale : null,
              child: const Text('Reset Scale'),
            ),
            OutlinedButton(
              key: const ValueKey('ar_scale_fit'),
              onPressed: enabled ? scene.fitToDimensions : null,
              child: const Text('Fit to Entered Dimensions'),
            ),
          ],
        ),
        const _Hint(
          'Pinch on the camera view to scale. 100% = entered size; preview '
          'scale never changes the recce measurements.',
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Rotate
// -----------------------------------------------------------------------------

class _RotatePanel extends StatelessWidget {
  const _RotatePanel({required this.scene});

  final ArSceneController scene;

  @override
  Widget build(BuildContext context) {
    final p = scene.selected;
    final axis = p?.rotationAxis ?? ArRotationAxis.yaw;
    final enabled = scene.canEditSelected && axis != ArRotationAxis.none;
    final deg = p?.rotationDeg ?? 0;
    final shown = deg.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Rotation: $shown°',
          key: const ValueKey('ar_rot_value'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        _Hint(switch (axis) {
          ArRotationAxis.roll =>
            'Wall sign: turns flat on the wall (around the wall normal).',
          ArRotationAxis.yaw =>
            'Turns around the vertical axis. Twist with two fingers or drag '
                'left / right.',
          ArRotationAxis.none =>
            'Flange boards stay perpendicular to the wall: rotation is off.',
        }),
        Row(
          children: [
            IconButton(
              key: const ValueKey('ar_rot_ccw'),
              tooltip: 'Counter-clockwise',
              onPressed: enabled ? () => scene.stepRotation(-1) : null,
              icon: const Icon(Icons.rotate_left),
            ),
            Expanded(
              child: Slider(
                key: const ValueKey('ar_rot_slider'),
                value: deg.clamp(-180, 180).toDouble(),
                min: -180,
                max: 180,
                label: '$shown°',
                onChangeStart: enabled ? (_) => scene.beginGesture() : null,
                onChanged: enabled ? scene.setRotationDegrees : null,
                onChangeEnd: enabled ? (_) => scene.endGesture('Rotate') : null,
              ),
            ),
            IconButton(
              key: const ValueKey('ar_rot_cw'),
              tooltip: 'Clockwise',
              onPressed: enabled ? () => scene.stepRotation(1) : null,
              icon: const Icon(Icons.rotate_right),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _NumberField(
              key: const ValueKey('ar_rot_input'),
              value: '$shown',
              suffix: '°',
              signed: true,
              enabled: enabled,
              onSubmit: scene.setRotationText,
            ),
            _fineToggle(scene, 'Fine 1°'),
            OutlinedButton(
              key: const ValueKey('ar_rot_reset'),
              onPressed: scene.canEditSelected ? scene.resetRotation : null,
              child: const Text('Reset Rotation'),
            ),
            if (p != null && p.doubleSided)
              OutlinedButton.icon(
                key: const ValueKey('ar_rot_flip'),
                onPressed: scene.canEditSelected ? scene.flipFace : null,
                icon: const Icon(Icons.flip, size: 18),
                label: const Text('View other face'),
              ),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Move
// -----------------------------------------------------------------------------

class _MovePanel extends StatelessWidget {
  const _MovePanel({required this.scene});

  final ArSceneController scene;

  @override
  Widget build(BuildContext context) {
    final p = scene.selected;
    final enabled = scene.canEditSelected;
    final axes = scene.allowedMoveAxes();
    final t = p?.transform ?? const ArObjectTransform();
    final wall = p?.onWall ?? false;
    Widget arrow(String key, IconData icon, String tip, ArMoveAxis a, int d) =>
        IconButton.filledTonal(
          key: ValueKey(key),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: enabled && axes.contains(a)
              ? () => scene.nudge(a, d)
              : null,
          icon: Icon(icon, size: 20),
        );
    String cm(double m) => '${(m * 100).toStringAsFixed(0)} cm';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Hint(
          p == null
              ? 'Drag a selected model on a detected surface to move it.'
              : 'Drag the model on a surface to move it (AR hit test). '
                    '${wall ? 'Wall sign: stays on its wall.' : 'Ground sign: stays on the ground.'}',
        ),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            arrow(
              'ar_move_left',
              Icons.arrow_back,
              'Left',
              ArMoveAxis.lateral,
              -1,
            ),
            arrow(
              'ar_move_right',
              Icons.arrow_forward,
              'Right',
              ArMoveAxis.lateral,
              1,
            ),
            arrow(
              'ar_move_up',
              Icons.arrow_upward,
              'Up',
              ArMoveAxis.vertical,
              1,
            ),
            arrow(
              'ar_move_down',
              Icons.arrow_downward,
              'Down',
              ArMoveAxis.vertical,
              -1,
            ),
            arrow(
              'ar_move_out',
              Icons.north_west,
              wall ? 'Away from wall' : 'Toward camera',
              ArMoveAxis.depth,
              1,
            ),
            arrow(
              'ar_move_in',
              Icons.south_east,
              wall ? 'Back to wall' : 'Away from camera',
              ArMoveAxis.depth,
              -1,
            ),
          ],
        ),
        Row(
          children: [
            const Text('Step', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 6),
            for (final s in const [0.01, 0.05, 0.10])
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  key: ValueKey('ar_move_step_${(s * 100).round()}'),
                  label: Text(cm(s), style: const TextStyle(fontSize: 11.5)),
                  visualDensity: VisualDensity.compact,
                  selected: (scene.moveStep - s).abs() < 1e-9,
                  onSelected: (_) => scene.setMoveStep(s),
                ),
              ),
          ],
        ),
        if (p != null)
          _Hint(
            'Offset from anchor: ${cm(t.x)} sideways, ${cm(t.y)} up, '
            '${cm(t.z)} ${wall ? 'out' : 'toward camera'}',
          ),
        SwitchListTile(
          key: const ValueKey('ar_move_free'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: scene.freeAdjust,
          onChanged: scene.setFreeAdjust,
          title: const Text('Free adjustment', style: TextStyle(fontSize: 13)),
          subtitle: Text(
            wall
                ? 'Allows moving the sign off its wall.'
                : 'Allows lifting the sign off the ground.',
            style: const TextStyle(fontSize: 11),
          ),
        ),
        Wrap(
          spacing: 6,
          children: [
            OutlinedButton(
              key: const ValueKey('ar_move_reset'),
              onPressed: enabled ? scene.resetPosition : null,
              child: const Text('Reset Position'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('ar_move_reanchor'),
              onPressed: p == null ? null : () => scene.requestReanchor(),
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Re-anchor'),
            ),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Dimensions
// -----------------------------------------------------------------------------

class _DimensionsPanel extends StatelessWidget {
  const _DimensionsPanel({
    required this.scene,
    required this.board,
    required this.unit,
    required this.editable,
    this.onEditDimensions,
  });

  final ArSceneController scene;
  final Board? board;
  final SignageUnit? unit;
  final bool editable;
  final VoidCallback? onEditDimensions;

  @override
  Widget build(BuildContext context) {
    final p = scene.selected;
    final b = board;
    final u = unit;
    if (p == null || b == null || u == null) {
      return const _Hint('Select a model to see its dimensions.');
    }
    final SignageGeometry g = unitGeometry(b, u);
    final media = SignageCatalog.media(b.mediaCode);
    final inst = SignageCatalog.installation(b.installationOf(u));
    final clearanceKey = SignageGeometry.clearanceKey(b.installationOf(u));
    final clearance = clearanceKey == null ? null : b.answers[clearanceKey];
    final t = p.transform;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Actual Dimensions (signage item)',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
        ),
        InfoRow('Media Type', media?.name ?? 'Not set'),
        InfoRow(
          'Width',
          (b.widthOf(u) ?? 0) > 0
              ? '${fmtNum(b.widthOf(u)!)} ${b.unit.label}'
              : 'Not entered',
        ),
        InfoRow(
          'Height',
          (b.heightOf(u) ?? 0) > 0
              ? '${fmtNum(b.heightOf(u)!)} ${b.unit.label}'
              : 'Not entered',
        ),
        InfoRow('Unit', b.unit.label),
        InfoRow('Installation Type', inst?.name ?? 'Not set'),
        if (clearance != null && '$clearance'.isNotEmpty)
          InfoRow(
            SignageGeometry.clearanceLabel(b.installationOf(u)),
            '$clearance ft',
          ),
        if (g.supportType != null && g.supportType!.isNotEmpty)
          InfoRow('Support Structure', g.supportType!),
        if (g.baseWidthFt > 0 && g.baseDepthFt > 0)
          InfoRow(
            'Base Dimensions',
            '${fmtNum(g.baseWidthFt)} × ${fmtNum(g.baseDepthFt)} ft',
          ),
        if (!b.unitHasSize(u))
          const _Hint(
            'No size entered yet: the model uses the default 10 × 4 ft '
            'preview size.',
            color: AdinnColors.warning,
          ),
        const Divider(height: 14),
        const Text(
          'AR Preview Scale (this placement only)',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
        ),
        InfoRow('Preview scale', '${t.scalePercent}%'),
        InfoRow(
          'Shown as',
          '${fmtNum(p.widthFt * t.scale)} × ${fmtNum(p.heightFt * t.scale)} ft',
        ),
        if (t.scaleAdjusted)
          const _Hint(
            'Preview Scale Adjusted – Not Actual Size. The recorded '
            'dimensions above are unchanged.',
            color: AdinnColors.warning,
          ),
        const SizedBox(height: 4),
        FilledButton.tonalIcon(
          key: const ValueKey('ar_edit_dimensions'),
          onPressed: editable ? onEditDimensions : null,
          icon: const Icon(Icons.straighten, size: 18),
          label: const Text('Edit Actual Dimensions'),
        ),
        if (!editable)
          const _Hint(
            'This recce is not editable (submitted / approved): dimensions '
            'are read-only.',
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Insert media sheet
// -----------------------------------------------------------------------------

/// Item chosen in the Insert Media sheet.
class ArInsertChoice {
  const ArInsertChoice(
    this.item, {
    this.previewDuplicate = false,
    this.selectId,
  });

  final ArSceneItem item;
  final bool previewDuplicate;

  /// "Select existing" was chosen instead of inserting.
  final String? selectId;
}

String _placementStatus(ArSceneController scene, ArSceneItem item) {
  final list = scene.placementsOf(item.unitId);
  if (list.isEmpty) return 'Not placed';
  final dups = list.where((p) => p.previewDuplicate).length;
  final pending = list.where((p) => !p.isAnchored).length;
  final base = pending > 0 ? 'Needs re-anchor' : 'Placed';
  return dups > 0 ? '$base • $dups preview duplicate(s)' : base;
}

Future<ArInsertChoice?> showArInsertSheet(
  BuildContext context,
  ArSceneController scene, {
  required String shopName,
}) {
  final items = scene.items.values.toList();
  return showModalBottomSheet<ArInsertChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Text(
            'Insert Media',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          Text(
            'Shop: $shopName • signage items configured in this recce',
            style: const TextStyle(color: AdinnColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No signage items configured for this shop yet.'),
            ),
          for (final item in items)
            Card(
              key: ValueKey('ar_insert_card_${item.unitId}'),
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.mediaName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${item.unitLabel} • ${item.sizeText}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          Text(
                            item.installationName,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AdinnColors.muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TagChip(
                            item.modelAvailable
                                ? _placementStatus(scene, item)
                                : item.unavailableReason!,
                            color: !item.modelAvailable
                                ? AdinnColors.muted
                                : (scene.placementsOf(item.unitId).isEmpty
                                      ? AdinnColors.info
                                      : AdinnColors.success),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      key: ValueKey('ar_insert_${item.unitId}'),
                      onPressed: !item.modelAvailable
                          ? null
                          : () async {
                              final choice = await _resolveInsert(
                                ctx,
                                scene,
                                item,
                              );
                              if (choice != null && ctx.mounted) {
                                Navigator.pop(ctx, choice);
                              }
                            },
                      child: const Text('Insert'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'Inserting places a 3D preview of an existing signage item. It '
            'never creates a new item or changes the quantity.',
            style: TextStyle(fontSize: 11.5, color: AdinnColors.muted),
          ),
        ],
      ),
    ),
  );
}

Future<ArInsertChoice?> _resolveInsert(
  BuildContext context,
  ArSceneController scene,
  ArSceneItem item,
) async {
  switch (scene.checkInsert(item)) {
    case ArInsertCheck.ok:
      return ArInsertChoice(item);
    case ArInsertCheck.unavailable:
      showSnack(context, item.unavailableReason ?? 'No 3D model', error: true);
      return null;
    case ArInsertCheck.engineLimit:
      showSnack(
        context,
        'This AR engine can show only one model at a time.',
        error: true,
      );
      return null;
    case ArInsertCheck.alreadyPlaced:
      final existing = scene
          .placementsOf(item.unitId)
          .where((p) => !p.previewDuplicate)
          .first;
      return showDialog<ArInsertChoice>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${item.label} is already placed'),
          content: const Text(
            'This signage unit is already in the AR scene. A second copy is '
            'only a Preview Duplicate: it does not add a physical unit or '
            'change the quantity.\n\nTo add another physical unit, increase '
            'the quantity in the media details.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const ValueKey('ar_insert_select_existing'),
              onPressed: () => Navigator.pop(
                ctx,
                ArInsertChoice(item, selectId: existing.placementId),
              ),
              child: const Text('Select existing'),
            ),
            FilledButton(
              key: const ValueKey('ar_insert_duplicate'),
              onPressed: () => Navigator.pop(
                ctx,
                ArInsertChoice(item, previewDuplicate: true),
              ),
              child: const Text('Add Preview Duplicate'),
            ),
          ],
        ),
      );
  }
}

// -----------------------------------------------------------------------------
// Objects (layer) sheet
// -----------------------------------------------------------------------------

String _objectSubtitle(ArPlacement p) {
  final where = switch (p.status) {
    ArAnchorStatus.pending => 'Needs re-anchoring',
    ArAnchorStatus.lost => 'Tracking lost – re-anchor',
    ArAnchorStatus.anchored => switch (p.surface) {
      'vertical' => 'On wall',
      'horizontal' => 'On floor / ground',
      _ => 'Manual placement',
    },
  };
  return [
    where,
    '${p.transform.scalePercent}%',
    if (!p.visible) 'Hidden',
    if (p.locked) 'Locked',
  ].join(' • ');
}

Future<void> showArObjectsSheet(
  BuildContext context,
  ArSceneController scene,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (ctx) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.5,
    maxChildSize: 0.9,
    builder: (ctx, scroll) => ListenableBuilder(
      listenable: scene,
      builder: (ctx, _) {
        final list = scene.placements;
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Objects in AR scene (${list.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 2, 8, 6),
              child: Text(
                'Selection, visibility and lock affect the preview only.',
                style: TextStyle(fontSize: 11.5, color: AdinnColors.muted),
              ),
            ),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No models inserted yet. Use Insert.'),
              ),
            for (final p in list)
              Material(
                color: p.placementId == scene.selectedId
                    ? AdinnColors.redLight
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  key: ValueKey('ar_obj_${p.placementId}'),
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 8),
                  leading: Icon(
                    p.placementId == scene.selectedId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: p.placementId == scene.selectedId
                        ? AdinnColors.red
                        : AdinnColors.muted,
                  ),
                  title: Text(
                    p.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(_objectSubtitle(p)),
                  onTap: () => scene.select(p.placementId),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey('ar_obj_vis_${p.placementId}'),
                        tooltip: p.visible ? 'Hide' : 'Show',
                        icon: Icon(
                          p.visible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            scene.setVisible(p.placementId, !p.visible),
                      ),
                      IconButton(
                        key: ValueKey('ar_obj_lock_${p.placementId}'),
                        tooltip: p.locked ? 'Unlock' : 'Lock',
                        icon: Icon(
                          p.locked ? Icons.lock : Icons.lock_open_outlined,
                        ),
                        onPressed: () =>
                            scene.setLocked(p.placementId, !p.locked),
                      ),
                      PopupMenuButton<String>(
                        key: ValueKey('ar_obj_more_${p.placementId}'),
                        onSelected: (v) {
                          switch (v) {
                            case 'reset':
                              scene.resetTransform(p.placementId);
                            case 'anchor':
                              scene.requestReanchor(p.placementId);
                              Navigator.pop(ctx);
                            case 'remove':
                              scene.remove(p.placementId);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'reset',
                            child: Text('Reset Transform'),
                          ),
                          const PopupMenuItem(
                            value: 'anchor',
                            child: Text('Re-anchor'),
                          ),
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove Placement'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  ),
);

// -----------------------------------------------------------------------------
// Saved layouts sheet
// -----------------------------------------------------------------------------

Future<ArLayout?> showArLayoutsSheet(
  BuildContext context, {
  required List<ArLayout> layouts,
  required bool editable,
  required void Function(ArLayout layout) onDelete,
  String? currentId,
}) => showModalBottomSheet<ArLayout>(
  context: context,
  showDragHandle: true,
  builder: (ctx) => StatefulBuilder(
    builder: (ctx, setSheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Saved AR Layouts',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const Text(
              'Layouts keep models and their preview transforms. Positions '
              'must be re-anchored on site.',
              style: TextStyle(fontSize: 11.5, color: AdinnColors.muted),
            ),
            const SizedBox(height: 6),
            if (layouts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No saved layouts for this shop yet.'),
              ),
            for (final l in layouts)
              ListTile(
                key: ValueKey('ar_layout_${l.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.dashboard_customize_outlined,
                  color: l.id == currentId ? AdinnColors.red : null,
                ),
                title: Text(l.name),
                subtitle: Text(
                  '${l.objects.length} object(s) • ${fmtDateTime(l.updatedAt)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (editable)
                      IconButton(
                        key: ValueKey('ar_layout_delete_${l.id}'),
                        tooltip: 'Delete layout',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await confirmDialog(
                            ctx,
                            title: 'Delete layout?',
                            message:
                                '“${l.name}” is removed. AR captures stay.',
                            confirmText: 'Delete',
                            destructive: true,
                          );
                          if (!ok) return;
                          onDelete(l);
                          setSheet(() => layouts.remove(l));
                        },
                      ),
                    FilledButton(
                      key: ValueKey('ar_layout_open_${l.id}'),
                      onPressed: () => Navigator.pop(ctx, l),
                      child: const Text('Open'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  ),
);
