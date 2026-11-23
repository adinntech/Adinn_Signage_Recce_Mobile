import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/features/live_recce/data/recce_models.dart';
import 'package:signage_recce/features/live_recce/presentation/board_views_screen.dart';

ShopDetail _detail({List<Map<String, dynamic>>? boards}) => ShopDetail.fromJson({
      'siteId': 's1',
      'siteCode': 'SM-0234',
      'shopName': 'Sri Murugan Super Market',
      'address': 'T. Nagar, Chennai',
      'project': {'id': 'p1', 'code': 'ADN-2451', 'name': 'South Zone', 'client': 'ABC Retail', 'closed': false},
      'status': 'IN_PROGRESS',
      'editable': true,
      'version': 0,
      'mediaItems': boards ?? [],
      'installation': null,
      'notes': '',
      'photos': [
        {'id': 'p1', 'category': 'SHOP_FRONT', 'state': 'DRAFT', 'mediaKey': '', 'url': 'http://host/file/p1.jpg', 'review': {'status': 'PENDING', 'openRework': null}},
      ],
      'progress': {'percent': 10, 'missing': []},
      'versions': [],
      'reviews': [],
      'reworks': [],
    });

void main() {
  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(412, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('shows the 2D drawing first, the 3D model on the second tab, and a chip per board', (t) async {
    phone(t);
    final boards = [
      BoardItem(key: 'b1', name: 'GSB', width: 6, height: 4, position: 'Shop fascia'),
      BoardItem(key: 'b2', name: 'Acrylic', width: 4, height: 2, position: 'Entrance glass'),
    ];
    await t.pumpWidget(MaterialApp(home: BoardViewsScreen(detail: _detail(), boards: boards, drawnBy: 'Test person')));
    await t.pump();

    expect(find.text('2D / 3D view'), findsOneWidget);
    expect(find.byKey(const Key('live-drawing2d-viewer')), findsOneWidget);
    expect(find.text('GSB b1'), findsOneWidget);
    expect(find.text('Acrylic b2'), findsOneWidget);
    expect(find.textContaining('Preview only'), findsNothing); // size, type and position are all known

    await t.tap(find.text('3D view'));
    await t.pump(); // the tab animation starts on the next frame
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('live-preview3d-viewport')), findsOneWidget);
    expect(find.text('Isometric'), findsOneWidget);

    // The Isometric preset and a drag both redraw without errors, and another board can be picked.
    await t.tap(find.text('Isometric'));
    await t.pump();
    await t.drag(find.byKey(const Key('live-preview3d-viewport')), const Offset(60, 20));
    await t.pump();
    await t.tap(find.text('Acrylic b2'));
    await t.pump();
    expect(find.byKey(const Key('live-preview3d-viewport')), findsOneWidget);
    await t.pump(const Duration(seconds: 1)); // lets the double-tap and image timers run out
    expect(t.takeException(), isNull);
  });

  testWidgets('a board with no size is drawn with defaults and the screen says so', (t) async {
    phone(t);
    await t.pumpWidget(MaterialApp(home: BoardViewsScreen(detail: _detail(), boards: [BoardItem(key: 'b1', name: 'Other')])));
    await t.pump();
    expect(find.textContaining('Preview only'), findsOneWidget);
    expect(find.textContaining('10 x 4 ft'), findsOneWidget);
    expect(find.byKey(const Key('live-drawing2d-viewer')), findsOneWidget);
  });

  testWidgets('no board yet shows a message instead of an empty drawing', (t) async {
    phone(t);
    await t.pumpWidget(MaterialApp(home: BoardViewsScreen(detail: _detail(), boards: const [])));
    await t.pump();
    expect(find.text('No board yet'), findsOneWidget);
    expect(find.byKey(const Key('live-drawing2d-viewer')), findsNothing);
  });
}
