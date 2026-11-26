import 'dart:ui';

import '../model3d/parametric_model.dart';
import '../preview3d/scene3d.dart';
import 'gsb_rules.dart';

/// Board-assembly components of the parametric GSB box that the
/// structural view replaces (context, wall, ground and installation stay).
const _boardComponents = {
  ModelComponentIds.displayPanel,
  ModelComponentIds.frontFace,
  ModelComponentIds.backFace,
  ModelComponentIds.frame,
  ModelComponentIds.sideReturns,
  ModelComponentIds.rearSupports,
  ModelComponentIds.illuminatedSurface,
};

const _frameColor = Color(0xFF5A6068);
const _supportColor = Color(0xFF7D868F);
const _connectorColor = Color(0xFF9AA2AA);
const _braceColor = Color(0xFFE37400);
const _seamBraceColor = Color(0xFFB0412E);

Color _colorFor(GsbMemberRole r) => switch (r) {
  GsbMemberRole.frontRail ||
  GsbMemberRole.rearRail ||
  GsbMemberRole.frontStile ||
  GsbMemberRole.rearStile => _frameColor,
  GsbMemberRole.internalVertical ||
  GsbMemberRole.extraHorizontal => _supportColor,
  GsbMemberRole.depthConnector => _connectorColor,
  GsbMemberRole.brace => _braceColor,
  GsbMemberRole.seamBrace => _seamBraceColor,
};

/// Structural-only GSB view: the physical members of [plan] (one solid per
/// member id) placed where the parametric model puts the board. Scene
/// units are feet; the board front is at z = 0 with depth towards −z and
/// the board centred on x = 0, bottom at [mountingFt] – the same frame as
/// the parametric model, so camera presets and dimensions stay valid.
/// No sheet cladding (flex / GI / trim) is added, per the rulebook.
Scene gsbStructureScene(
  ParametricModel model,
  GsbFabricationPlan plan, {
  required double mountingFt,
}) {
  final w = plan.input.widthIn;
  Vec3 toScene(In3 p) =>
      Vec3((p.x - w / 2) / 12, mountingFt + p.y / 12, -p.z / 12);

  final scene = Scene(focus: model.scene.focus);
  for (final s in model.scene.solids) {
    if (_boardComponents.contains(ModelComponentIds.of(s.name))) continue;
    scene.add(s);
  }
  for (final m in plan.members) {
    final a = toScene(m.start), b = toScene(m.end);
    final t = m.sectionIn / 12;
    final color = _colorFor(m.role);
    final dx = (a.x - b.x).abs(),
        dy = (a.y - b.y).abs(),
        dz = (a.z - b.z).abs();
    final axisAligned =
        [dx, dy, dz].where((v) => v > 1e-9).length == 1 && !m.role.isBrace;
    if (axisAligned) {
      // Exact box: the member length along its axis, the section across.
      final h = t / 2;
      final min = Vec3(
        (dx > 1e-9 ? (a.x < b.x ? a.x : b.x) : a.x - h),
        (dy > 1e-9 ? (a.y < b.y ? a.y : b.y) : a.y - h),
        (dz > 1e-9 ? (a.z < b.z ? a.z : b.z) : a.z - h),
      );
      final max = Vec3(
        (dx > 1e-9 ? (a.x > b.x ? a.x : b.x) : a.x + h),
        (dy > 1e-9 ? (a.y > b.y ? a.y : b.y) : a.y + h),
        (dz > 1e-9 ? (a.z > b.z ? a.z : b.z) : a.z + h),
      );
      scene.add(Shapes.box(min, max, color, name: 'gsb_member:${m.id}'));
    } else {
      scene.add(Shapes.beam(a, b, t, color, name: 'gsb_member:${m.id}'));
    }
  }
  scene.dims.addAll(model.scene.dims);
  scene.finalize();
  return scene;
}
