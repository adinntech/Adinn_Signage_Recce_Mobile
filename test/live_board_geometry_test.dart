import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/features/drawing/signage_geometry.dart';
import 'package:signage_recce/features/live_recce/data/board_geometry.dart';
import 'package:signage_recce/features/live_recce/data/recce_models.dart';
import 'package:signage_recce/features/preview3d/signage_scene_builder.dart';

void main() {
  test('size is converted to feet from every live unit', () {
    expect(geometryForBoard(BoardItem(key: 'b1', width: 6, height: 4, unit: 'FT')).widthFt, closeTo(6, 1e-9));
    expect(geometryForBoard(BoardItem(key: 'b1', width: 72, height: 48, unit: 'IN')).widthFt, closeTo(6, 1e-9));
    expect(geometryForBoard(BoardItem(key: 'b1', width: 2, height: 1, unit: 'M')).widthFt, closeTo(6.5617, 1e-3));
    expect(geometryForBoard(BoardItem(key: 'b1', width: 183, height: 122, unit: 'CM')).heightFt, closeTo(4.0, 0.01));
    expect(geometryForBoard(BoardItem(key: 'b1', width: 1829, height: 1219, unit: 'MM')).widthFt, closeTo(6.0, 0.01));
  });

  test('a board without a size is drawn with the default size and flagged', () {
    final g = geometryForBoard(BoardItem(key: 'b1'));
    expect(g.usingDefaults, isTrue);
    expect(g.anyDefaults, isTrue);
    expect(g.widthFt, SignageGeometry.defaultWidthFt);
    expect(g.heightFt, SignageGeometry.defaultHeightFt);
  });

  test('board type and position choose the media and the fixing method; unknown ones fall back and are flagged', () {
    final fascia = geometryForBoard(BoardItem(key: 'b1', name: 'GSB', width: 6, height: 4, position: 'Shop fascia'));
    expect(fascia.mediaCode, SignageCatalog.gsb);
    expect(fascia.installationCode, SignageCatalog.shopFascia);
    expect(fascia.anyDefaults, isFalse);

    final glass = geometryForBoard(BoardItem(key: 'b2', name: 'Acrylic', width: 4, height: 2, position: 'Entrance glass'));
    expect(glass.mediaCode, SignageCatalog.clearAcrylic);
    expect(glass.installationCode, SignageCatalog.glassPasting);

    // "Other" is not a drawing type; a position that names nothing leaves the usual fixing of the media.
    final other = geometryForBoard(BoardItem(key: 'b3', name: 'Other', width: 4, height: 2, position: 'somewhere'));
    expect(other.mediaCode, SignageCatalog.gsb);
    expect(other.mediaSelected, isFalse);
    expect(other.installationSelected, isFalse);
    expect(other.anyDefaults, isTrue);
  });

  test('double sided and quantity are carried over, and a CM board is labelled in metres', () {
    final g = geometryForBoard(BoardItem(key: 'b1', width: 120, height: 60, unit: 'CM', sided: 'DOUBLE', quantity: 3));
    expect(g.doubleSided, isTrue);
    expect(g.quantity, 3);
    expect(g.unit, MeasureUnit.m);
  });

  test('the 3D scene builds for every live board type and position without errors', () {
    for (final name in boardTypes) {
      for (final position in ['Shop fascia', 'Entrance glass', 'Left wall', 'Roof', 'Road side pole', '']) {
        final g = geometryForBoard(BoardItem(key: 'b1', name: name, width: 8, height: 3, position: position));
        expect(SignageSceneBuilder.build(g, brand: 'Test'), isNotNull, reason: '$name / $position');
      }
    }
  });
}
