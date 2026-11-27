import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/features/drawing/drawing_2d_painter.dart';
import 'package:signage_recce/features/live_recce/data/board_geometry.dart';
import 'package:signage_recce/features/live_recce/data/board_render_export.dart';
import 'package:signage_recce/features/live_recce/data/recce_models.dart';

bool _isPng(List<int> b) => b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47;

void main() {
  final geo = geometryForBoard(BoardItem(key: 'b1', name: 'GSB', width: 6, height: 4, unit: 'FT', position: 'Shop fascia'));

  testWidgets('the 2D drawing of a board becomes a PNG that can be stored', (tester) async {
    final bytes = await tester.runAsync(() => drawing2dPng(geo, const DrawingInfo(projectName: 'P', shopName: 'S', shopAddress: 'A', boardName: 'GSB (b1)', drawnBy: 'T', date: '2026-11-27', statusLabel: 'Draft', notes: [])));
    expect(_isPng(bytes!), isTrue);
    expect(bytes.length, greaterThan(2000));
  });

  testWidgets('the 3D preview of a board becomes a PNG that can be stored', (tester) async {
    final bytes = await tester.runAsync(() => view3dPng(geo, brand: 'P'));
    expect(_isPng(bytes!), isTrue);
    expect(bytes.length, greaterThan(2000));
  });
}
