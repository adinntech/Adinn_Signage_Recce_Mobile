import 'dart:math' as math;
import 'dart:ui';

import '../../core/utils/formatters.dart';
import '../../data/catalog/signage_catalog.dart';
import '../drawing/signage_geometry.dart';
import '../gsb/gsb_presentation.dart';
import '../nlb/nlb_presentation.dart';
import '../model3d/parametric_builder.dart';
import 'scene3d.dart';

/// Palette for the 3D preview.
class SceneColors {
  SceneColors._();

  static const red = Color(0xFFD71920);
  static const white = Color(0xFFF7F7F7);
  static const frame = Color(0xFF4A4D52);
  static const steel = Color(0xFF8C939B);
  static const concrete = Color(0xFFB8B4AC);
  static const wall = Color(0xFFE9DCC5);
  static const building = Color(0xFFDCD3C3);
  static const shutter = Color(0xFFA9AFB6);
  static const slat = Color(0xFF8D939A);
  static const glass = Color(0xCC86B3D1);
  static const window = Color(0xFF5E7F99);
  static const vinyl = Color(0xE600897B);
  static const silver = Color(0xFFC0C4C8);
  static const black = Color(0xFF2B2B2B);
  static const skin = Color(0xFFC68B59);
  static const shirt = Color(0xFF2F4F7F);
  static const trousers = Color(0xFF3C3F44);
}

/// Turns a [SignageGeometry] into a 3D [Scene]: the board styled by media
/// type, the installation-specific structure, a 5.5 ft person for scale and
/// dimension anchors.
class SignageSceneBuilder {
  SignageSceneBuilder._();

  static Scene build(SignageGeometry g, {String brand = 'ADINN'}) {
    // Catalog-v2 media use the parametric templates (GSB / NLB / ACP and
    // legacy media keep the builder below unchanged).
    if (ParametricModelBuilder.routesGeometry(g)) {
      final scene = ParametricModelBuilder.sceneForGeometry(g, brand: brand);
      _addPerson(scene, g);
      scene.finalize();
      return scene;
    }
    final label = brand.trim().isEmpty ? 'ADINN' : brand.trim().toUpperCase();
    final w = g.widthFt, h = g.heightFt, d = g.depthFt;
    final b = g.bottomFt;
    final p = g.projectionFt;

    final focus = g.isFlangeBracket
        ? Vec3(0, b + h / 2, p + w / 2)
        : Vec3(0, b + h / 2, -d / 2);
    final scene = Scene(focus: focus);

    _addStructure(scene, g, label);
    if (!g.isSurfaceArtwork) _addBoard(scene, g, label);
    _addPerson(scene, g);
    _addDims(scene, g);

    scene.finalize();
    return scene;
  }

  /// Solids that represent the surroundings (walls, facades, buildings) –
  /// left out of [buildModel] because the site photo provides them.
  static const contextSolids = {
    'wall',
    'facade',
    'building',
    'shopfront',
    'sunshade',
    'parapet',
  };

  /// The signage model alone (board + its own support structure) for photo
  /// overlays (Live Preview / AR). No walls, building, person or ground.
  static Scene buildModel(
    SignageGeometry g, {
    String brand = 'ADINN',
    bool dimensions = false,
  }) {
    if (ParametricModelBuilder.routesGeometry(g)) {
      return ParametricModelBuilder.sceneForGeometry(
        g,
        brand: brand,
        modelOnly: true,
        dimensions: dimensions,
      );
    }
    final label = brand.trim().isEmpty ? 'ADINN' : brand.trim().toUpperCase();
    final w = g.widthFt, d = g.depthFt;
    final b = g.bottomFt, t = g.topFt;
    final focus = g.isFlangeBracket
        ? Vec3(0, b + g.heightFt / 2, g.projectionFt + w / 2)
        : Vec3(0, b + g.heightFt / 2, -d / 2);
    final scene = Scene(focus: focus);
    _addStructure(scene, g, label);
    scene.solids.removeWhere((s) => contextSolids.contains(s.name));
    if (g.isSurfaceArtwork) {
      // Artwork is normally a decal on the (removed) wall: show it as a thin
      // printed panel instead.
      final paint = g.mediaCode == SignageCatalog.wallPainting;
      scene.add(
        Shapes.box(
          Vec3(-w / 2, b, -0.05),
          Vec3(w / 2, t, 0),
          SceneColors.frame,
          name: 'board',
          sideColors: {
            BoxSide.front: paint ? SceneColors.red : SceneColors.vinyl,
          },
          labels: {BoxSide.front: label},
        ),
      );
    } else {
      _addBoard(scene, g, label);
    }
    if (dimensions) _addDims(scene, g);
    scene.finalize();
    return scene;
  }

  /// Ground base + supporting frame of a single / double sided standee.
  /// The support type comes from the recce answer (configurable).
  static void _addStandeeSupport(Scene scene, SignageGeometry g) {
    final w = g.widthFt, d = g.depthFt;
    final b = g.bottomFt, t = g.topFt;
    final zc = -d / 2;
    final bw = g.baseWidthFt > 0 ? g.baseWidthFt : math.max(1.5, w * 0.7);
    final bd = g.baseDepthFt > 0 ? g.baseDepthFt : 1.5;
    const baseH = 0.2;
    scene.add(
      Shapes.box(
        Vec3(-bw / 2, 0, zc - bd / 2),
        Vec3(bw / 2, baseH, zc + bd / 2),
        SceneColors.frame,
        name: 'base',
      ),
    );
    final postX = w / 2 + 0.08;
    void sidePosts() {
      for (final x in [-postX, postX]) {
        scene.add(
          Shapes.beam(
            Vec3(x, baseH, zc),
            Vec3(x, t, zc),
            0.16,
            SceneColors.steel,
            name: 'post',
          ),
        );
        if (bw < w) {
          // Each post needs its own foot when the base is narrower.
          scene.add(
            Shapes.box(
              Vec3(x - 0.3, 0, zc - bd / 2),
              Vec3(x + 0.3, baseH, zc + bd / 2),
              SceneColors.frame,
              name: 'base',
            ),
          );
        }
      }
    }

    switch (g.supportType) {
      case 'Single centre pole':
        final top = g.doubleSided ? b : t - 0.2;
        final z = g.doubleSided ? zc : -d - 0.18;
        if (top > baseH + 0.05) {
          scene.add(
            Shapes.cylinder(
              Vec3(0, baseH, z),
              0.14,
              top - baseH,
              SceneColors.steel,
            ),
          );
        }
      case 'A-frame':
        for (final x in [-postX, postX]) {
          for (final s in [-1.0, 1.0]) {
            scene.add(
              Shapes.beam(
                Vec3(x, baseH, zc + s * bd / 2),
                Vec3(x, t, zc),
                0.12,
                SceneColors.steel,
                name: 'post',
              ),
            );
          }
        }
      case 'Box frame':
        sidePosts();
        for (final y in [b - 0.08, t + 0.08]) {
          scene.add(
            Shapes.beam(
              Vec3(-postX, y, zc),
              Vec3(postX, y, zc),
              0.14,
              SceneColors.steel,
              name: 'rail',
            ),
          );
        }
      default: // Twin side posts
        sidePosts();
    }
  }
  // ---------------------------------------------------------------------------
  // Board
  // ---------------------------------------------------------------------------

  static void _addBoard(Scene scene, SignageGeometry g, String brand) {
    final w = g.widthFt, d = g.depthFt;
    final b = g.bottomFt, t = g.topFt;

    if (g.isFlangeBracket) {
      final p = g.projectionFt;
      scene.add(
        Shapes.box(
          Vec3(-d / 2, b, p),
          Vec3(d / 2, t, p + w),
          SceneColors.frame,
          name: 'board',
          sideColors: {
            BoxSide.right: SceneColors.red,
            BoxSide.left: g.doubleSided ? SceneColors.red : SceneColors.steel,
          },
          labels: {
            BoxSide.right: brand,
            if (g.doubleSided) BoxSide.left: brand,
          },
          emissive: {BoxSide.right, if (g.doubleSided) BoxSide.left},
        ),
      );
      return;
    }

    if (g.mediaCode == SignageCatalog.nlb && g.nlbSingleFrame) {
      // NLB Single Frame: slim open frame with visible pipes.
      for (final s in NlbSingleBoard.build(
        NlbSinglePresentation(
          widthFt: w,
          heightFt: t - b,
          bottomFt: b,
          profileIn: d * 12,
          brand: brand,
        ),
      )) {
        scene.add(s);
      }
      return;
    }
    if (g.mediaCode == SignageCatalog.nlb && g.nlbBoxFrame) {
      // NLB Box Frame: fully flex-covered box (frame stays hidden).
      for (final s in NlbBoxBoard.build(
        NlbBoxPresentation(
          widthFt: w,
          heightFt: t - b,
          depthFt: d,
          bottomFt: b,
          brand: brand,
        ),
      )) {
        scene.add(s);
      }
      return;
    }
    final min = Vec3(-w / 2, b, -d);
    final max = Vec3(w / 2, t, 0);
    switch (g.mediaCode) {
      case SignageCatalog.gsb:
        // Finished exterior (flex, blue powder-coated covers, GI / rear
        // flex, sample screws) shared with the Isometric view.
        for (final s in GsbFinishedBoard.build(
          GsbPresentation(
            widthFt: w,
            heightFt: t - b,
            depthFt: d,
            bottomFt: b,
            isDouble: g.doubleSided,
            ledOnRear: g.gsbLedRear,
            brand: brand,
          ),
        )) {
          scene.add(s);
        }
      case SignageCatalog.flange:
        scene.add(
          Shapes.box(
            min,
            max,
            SceneColors.frame,
            name: 'board',
            sideColors: {BoxSide.front: SceneColors.red},
            labels: {BoxSide.front: brand},
            emissive: {BoxSide.front},
          ),
        );
      case SignageCatalog.acp:
        final panelColor = switch (g.acpColour) {
          'Brand red' => SceneColors.red,
          'White' => SceneColors.white,
          'Black' => SceneColors.black,
          _ => SceneColors.silver,
        };
        final letterColor = panelColor == SceneColors.red
            ? SceneColors.white
            : SceneColors.red;
        final panel = Shapes.box(
          min,
          max,
          SceneColors.frame,
          name: 'board',
          sideColors: {BoxSide.front: panelColor},
        );
        _addLetters(panel, g, brand, letterColor, panelColor);
        scene.add(panel);
      case SignageCatalog.vinyl:
        scene.add(
          Shapes.box(
            min,
            max,
            SceneColors.frame,
            name: 'board',
            sideColors: {BoxSide.front: SceneColors.vinyl},
            labels: {BoxSide.front: brand},
          ),
        );
      case SignageCatalog.wallPainting:
        scene.add(
          Shapes.box(
            min,
            max,
            SceneColors.wall,
            name: 'board',
            sideColors: {BoxSide.front: SceneColors.red},
            labels: {BoxSide.front: brand},
          ),
        );
      case SignageCatalog.singleStandee:
      case SignageCatalog.doubleStandee:
        final two = g.doubleSided;
        scene.add(
          Shapes.box(
            min,
            max,
            SceneColors.frame,
            name: 'board',
            sideColors: {
              BoxSide.front: SceneColors.red,
              BoxSide.back: two ? SceneColors.red : SceneColors.steel,
            },
            labels: {BoxSide.front: brand, if (two) BoxSide.back: brand},
          ),
        );
      default: // NLB and anything else: white face, red lettering.
        scene.add(
          Shapes.box(
            min,
            max,
            SceneColors.frame,
            name: 'board',
            sideColors: {BoxSide.front: SceneColors.white},
            labels: {BoxSide.front: brand},
            labelColor: SceneColors.red,
          ),
        );
    }
  }

  static void _addLetters(
    Solid panel,
    SignageGeometry g,
    String brand,
    Color letterColor,
    Color panelColor,
  ) {
    final chars = brand.replaceAll(' ', '').split('');
    final n = math.min(chars.length, 12);
    if (n == 0) return;
    final w = g.widthFt, h = g.heightFt;
    final pitch = w * 0.9 / n;
    final lh = (g.letterHeightFt ?? h * 0.55).clamp(0.2, h * 0.85).toDouble();
    final lw = math.min(lh * 0.75, pitch * 0.82);
    final cy = g.bottomFt + h / 2;
    for (var i = 0; i < n; i++) {
      final cx = -w * 0.45 + pitch * (i + 0.5);
      panel.decals.addAll(
        Shapes.boxFaces(
          Vec3(cx - lw / 2, cy - lh / 2, 0),
          Vec3(cx + lw / 2, cy + lh / 2, 0.15),
          letterColor,
          labels: {BoxSide.front: chars[i]},
          labelColor: panelColor,
          emissive: {BoxSide.front},
          skip: {BoxSide.back},
          layer: 1,
        ),
      );
    }
    panel.decalNormal = const Vec3(0, 0, 1);
  }

  // ---------------------------------------------------------------------------
  // Structures
  // ---------------------------------------------------------------------------

  static void _addStructure(Scene scene, SignageGeometry g, String brand) {
    final w = g.widthFt, d = g.depthFt;
    final b = g.bottomFt, t = g.topFt;

    switch (g.installationCode) {
      case SignageCatalog.freeStanding:
        _addStandeeSupport(scene, g);

      case SignageCatalog.doublePole:
        final zp = -d - 0.3;
        for (final x in [-g.poleGapFt / 2, g.poleGapFt / 2]) {
          scene.add(
            Shapes.cylinder(Vec3(x, 0, zp), 0.22, t, SceneColors.steel),
          );
          scene.add(
            Shapes.box(
              Vec3(x - 0.7, 0, zp - 0.7),
              Vec3(x + 0.7, 0.3, zp + 0.7),
              SceneColors.concrete,
              name: 'footing',
            ),
          );
        }
        for (final y in [b + 0.3, t - 0.3]) {
          scene.add(
            Shapes.beam(
              Vec3(-g.poleGapFt / 2, y, -d - 0.12),
              Vec3(g.poleGapFt / 2, y, -d - 0.12),
              0.16,
              SceneColors.steel,
            ),
          );
        }

      case SignageCatalog.singlePole:
        final zp = -d - 0.4;
        scene.add(
          Shapes.cylinder(Vec3(0, 0, zp), 0.3, t - 0.15, SceneColors.steel),
        );
        scene.add(
          Shapes.box(
            Vec3(-0.9, 0, zp - 0.9),
            Vec3(0.9, 0.3, zp + 0.9),
            SceneColors.concrete,
            name: 'footing',
          ),
        );
        for (final y in [b + 0.3, t - 0.3]) {
          scene.add(
            Shapes.beam(
              Vec3(-w * 0.35, y, -d - 0.12),
              Vec3(w * 0.35, y, -d - 0.12),
              0.16,
              SceneColors.steel,
            ),
          );
        }

      case SignageCatalog.wallMount:
        scene.add(
          Shapes.box(
            Vec3(-(w / 2 + 4), 0, -d - 0.75),
            Vec3(w / 2 + 4, math.max(t + 3, 10), -d),
            SceneColors.wall,
            name: 'wall',
          ),
        );

      case SignageCatalog.shopFascia:
        final half = w / 2 + 2;
        final facade = Shapes.box(
          Vec3(-half, 0, -d - 12),
          Vec3(half, t + 2.5, -d),
          SceneColors.building,
          name: 'facade',
        );
        final shutterTop = math.max(0.5, b - 0.5);
        _addShutters(facade, -half + 0.5, half - 0.5, shutterTop, -d);
        facade.decalNormal = const Vec3(0, 0, 1);
        scene.add(facade);
        scene.add(
          Shapes.box(
            Vec3(-half, shutterTop, -d),
            Vec3(half, shutterTop + 0.2, -d + 1.5),
            SceneColors.concrete,
            name: 'sunshade',
          ),
        );

      case SignageCatalog.rooftop:
        final hb = g.buildingHeightFt;
        final half = w / 2 + 4;
        final building = Shapes.box(
          Vec3(-half, 0, -d - 18),
          Vec3(half, hb, 2),
          SceneColors.building,
          name: 'building',
        );
        final floors = (hb / 10).round();
        for (var f = 0; f < floors; f++) {
          final y0 = f * 10.0;
          if (f == 0) {
            _addShutters(building, -half + 1, half - 1, 8, 2);
            continue;
          }
          for (var x = -half + 2; x + 3 <= half - 1; x += 5) {
            building.decals.add(
              Shapes.frontQuad(x, y0 + 3, x + 3, y0 + 7, 2, SceneColors.window),
            );
          }
        }
        building.decalNormal = const Vec3(0, 0, 1);
        scene.add(building);
        scene.add(
          Shapes.box(
            Vec3(-half, hb, 1.5),
            Vec3(half, hb + 1, 2),
            SceneColors.concrete,
            name: 'parapet',
          ),
        );
        final legs = math.max(2, (w / 8).ceil() + 1);
        final zf = -d - 0.2;
        final stay = math.max(2.0, g.heightFt * 0.6);
        for (var i = 0; i < legs; i++) {
          final x = -w / 2 + 0.4 + (w - 0.8) * i / (legs - 1);
          scene.add(
            Shapes.beam(
              Vec3(x, hb, zf),
              Vec3(x, t, zf),
              0.25,
              SceneColors.steel,
            ),
          );
          scene.add(
            Shapes.beam(
              Vec3(x, t - 0.3, zf),
              Vec3(x, hb, zf - stay),
              0.18,
              SceneColors.steel,
            ),
          );
        }
        scene.add(
          Shapes.beam(
            Vec3(-w / 2 + 0.2, b, zf),
            Vec3(w / 2 - 0.2, b, zf),
            0.2,
            SceneColors.steel,
          ),
        );

      case SignageCatalog.flangeBracket:
        final half = 6 + w * 0.3;
        scene.add(
          Shapes.box(
            Vec3(-half, 0, -0.75),
            Vec3(half, math.max(t + 3, 10), 0),
            SceneColors.wall,
            name: 'wall',
          ),
        );
        final p = g.projectionFt;
        scene.add(
          Shapes.beam(
            Vec3(0, t + 0.15, 0),
            Vec3(0, t + 0.15, p + w),
            0.15,
            SceneColors.steel,
          ),
        );
        scene.add(
          Shapes.beam(
            Vec3(0, t + 1.5, 0),
            Vec3(0, t + 0.15, p + w * 0.7),
            0.12,
            SceneColors.steel,
          ),
        );
        scene.add(
          Shapes.beam(
            Vec3(0, b - 0.15, 0),
            Vec3(0, b - 0.15, p + 0.6),
            0.12,
            SceneColors.steel,
          ),
        );

      case SignageCatalog.directWall:
        final wall = Shapes.box(
          Vec3(-(w / 2 + 3), 0, -0.75),
          Vec3(w / 2 + 3, math.max(t + 2, 10), 0),
          SceneColors.wall,
          name: 'wall',
        );
        if (g.isSurfaceArtwork) {
          final paint = g.mediaCode == SignageCatalog.wallPainting;
          wall.decals.add(
            Shapes.frontQuad(
              -w / 2,
              b,
              w / 2,
              t,
              0,
              paint ? SceneColors.red : SceneColors.vinyl,
              label: brand,
            ),
          );
          wall.decalNormal = const Vec3(0, 0, 1);
        }
        scene.add(wall);

      case SignageCatalog.glassPasting:
        final half = w / 2 + 1.5;
        final front = Shapes.box(
          Vec3(-half, 0, -12),
          Vec3(half, math.max(t + 3, 10), 0),
          SceneColors.building,
          name: 'shopfront',
        );
        final gy0 = math.max(0.0, b - 0.5);
        front.decals.add(
          Shapes.frontQuad(
            -w / 2 - 0.5,
            gy0,
            w / 2 + 0.5,
            t + 0.5,
            0,
            SceneColors.glass,
            layer: 1,
          ),
        );
        if (g.isSurfaceArtwork) {
          front.decals.add(
            Shapes.frontQuad(
              -w / 2,
              b,
              w / 2,
              t,
              0,
              SceneColors.vinyl,
              label: brand,
              layer: 2,
            ),
          );
        }
        final panels = g.panelCount;
        for (var i = 0; i <= panels; i++) {
          final x = -w / 2 - 0.5 + (w + 1) * i / panels;
          front.decals.add(
            Shapes.frontQuad(
              x - 0.06,
              gy0,
              x + 0.06,
              t + 0.5,
              0,
              SceneColors.black,
              layer: 3,
              outline: false,
            ),
          );
        }
        front.decalNormal = const Vec3(0, 0, 1);
        scene.add(front);
    }
  }

  static void _addShutters(
    Solid host,
    double x0,
    double x1,
    double top,
    double z,
  ) {
    const pillar = 1.0;
    final mid = (x0 + x1) / 2;
    for (final (a, c) in [(x0, mid - pillar / 2), (mid + pillar / 2, x1)]) {
      if (c - a < 0.5) continue;
      host.decals.add(Shapes.frontQuad(a, 0, c, top, z, SceneColors.shutter));
      final slats = math.min(14, (top / 0.6).floor());
      for (var i = 1; i <= slats; i++) {
        final y = top * i / (slats + 1);
        host.decals.add(
          Shapes.frontQuad(
            a,
            y - 0.03,
            c,
            y + 0.03,
            z,
            SceneColors.slat,
            layer: 2,
            outline: false,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Scale figure
  // ---------------------------------------------------------------------------

  static void _addPerson(Scene scene, SignageGeometry g) {
    final double x, z;
    if (g.isFlangeBracket) {
      x = 3;
      z = g.projectionFt + g.widthFt + 2;
    } else if (g.installationCode == SignageCatalog.rooftop) {
      x = g.widthFt / 2 + 2;
      z = 5;
    } else if (g.installationCode == SignageCatalog.doublePole) {
      x = math.max(g.widthFt, g.poleGapFt + 1.4) / 2 + 2.5;
      z = 2;
    } else {
      x = g.widthFt / 2 + 2.5;
      z = 2;
    }
    scene.add(
      Shapes.beam(
        Vec3(x - 0.3, 0, z),
        Vec3(x - 0.25, 2.6, z),
        0.35,
        SceneColors.trousers,
        name: 'person',
      ),
    );
    scene.add(
      Shapes.beam(
        Vec3(x + 0.3, 0, z),
        Vec3(x + 0.25, 2.6, z),
        0.35,
        SceneColors.trousers,
        name: 'person',
      ),
    );
    scene.add(
      Shapes.box(
        Vec3(x - 0.55, 2.6, z - 0.3),
        Vec3(x + 0.55, 4.6, z + 0.3),
        SceneColors.shirt,
        name: 'person',
      ),
    );
    scene.add(
      Shapes.beam(
        Vec3(x - 0.7, 4.5, z),
        Vec3(x - 0.8, 2.9, z),
        0.25,
        SceneColors.shirt,
        name: 'person',
      ),
    );
    scene.add(
      Shapes.beam(
        Vec3(x + 0.7, 4.5, z),
        Vec3(x + 0.8, 2.9, z),
        0.25,
        SceneColors.shirt,
        name: 'person',
      ),
    );
    scene.add(
      Shapes.box(
        Vec3(x - 0.35, 4.75, z - 0.35),
        Vec3(x + 0.35, 5.5, z + 0.35),
        SceneColors.skin,
        name: 'person',
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Dimensions
  // ---------------------------------------------------------------------------

  static void _addDims(Scene scene, SignageGeometry g) {
    final w = g.widthFt, h = g.heightFt, d = g.depthFt;
    final b = g.bottomFt, t = g.topFt;
    final u = g.unit;
    final off = math.max(0.7, 0.08 * math.max(w, h));
    final clear = b - g.baseLevelFt;
    final clearLabel = 'Clr ${fmtLength(clear, u)}';

    if (g.isFlangeBracket) {
      final p = g.projectionFt;
      final x = d / 2;
      scene.dims.addAll([
        Dim3(
          Vec3(x, t, p),
          Vec3(x, t, p + w),
          Vec3(0, off, 0),
          'W ${fmtLength(w, u)}',
        ),
        Dim3(
          Vec3(x, b, p + w),
          Vec3(x, t, p + w),
          Vec3(0, 0, off),
          'H ${fmtLength(h, u)}',
        ),
        if (b > 0.05)
          Dim3(
            Vec3(x, 0, p + w),
            Vec3(x, b, p + w),
            Vec3(0, 0, off),
            clearLabel,
          ),
        if (p > 0.05)
          Dim3(
            Vec3(x, b, 0),
            Vec3(x, b, p),
            Vec3(0, -off * 0.6, 0),
            'Proj ${fmtLength(p, u)}',
          ),
      ]);
      return;
    }

    scene.dims.addAll([
      Dim3(
        Vec3(-w / 2, t, 0),
        Vec3(w / 2, t, 0),
        Vec3(0, off, 0),
        'W ${fmtLength(w, u)}',
      ),
      Dim3(
        Vec3(w / 2, b, 0),
        Vec3(w / 2, t, 0),
        Vec3(off, 0, 0),
        'H ${fmtLength(h, u)}',
      ),
      if (clear > 0.05)
        Dim3(
          Vec3(-w / 2, g.baseLevelFt, 0),
          Vec3(-w / 2, b, 0),
          Vec3(-off, 0, 0),
          clearLabel,
        ),
    ]);
  }
}
