import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signage_recce/features/live_recce/data/recce_api.dart';
import 'package:signage_recce/features/live_recce/data/recce_controllers.dart';
import 'package:signage_recce/features/live_recce/data/recce_models.dart';
import 'package:signage_recce/features/live_recce/data/upload_queue.dart';
import 'package:signage_recce/features/live_recce/presentation/photos_tab.dart';

/// A submitted (locked) shop with several boards: every board is folded to one line on the Photos tab (a tap opens one), and a photo that
/// replaced a flagged one in the current version is called "Resubmitted". Fake data only.

Map<String, dynamic> _photo(String id, String category, String board, {int version = 2, String? replaces}) => {
      'id': id,
      'category': category,
      'state': 'SUBMITTED',
      'mediaKey': board,
      'version': version,
      'lat': 13.04,
      'lng': 80.23,
      'gpsAccuracy': 8.0,
      'gpsVerified': true,
      'url': 'http://host/$id.jpg',
      'replaces': replaces,
      'review': {'status': 'PENDING', 'openRework': null},
    };

Map<String, dynamic> _detail({String status = 'UNDER_REVIEW'}) => {
      'siteId': 's1',
      'siteCode': 'SM-1',
      'shopName': 'Sri Murugan',
      'project': {'id': 'p1', 'code': 'ADN-1', 'name': 'South', 'closed': false},
      'status': status,
      'editable': false,
      'version': 2,
      'mediaItems': [
        {'key': 'b1', 'name': 'GSB', 'mediaType': 'GSB', 'seq': 1, 'quantity': 1, 'width': 20, 'height': 30, 'unit': 'FT'},
        {'key': 'b2', 'name': 'Foam Vinyl', 'mediaType': 'FVB', 'seq': 1, 'quantity': 1, 'width': 22, 'height': 12, 'unit': 'FT'},
      ],
      'photos': [
        // board 1: the front photo was retaken and resubmitted in version 2, the left one is from version 1
        _photo('b1-front-new', 'SHOP_FRONT', 'b1', replaces: 'b1-front-old'),
        _photo('b1-left', 'LEFT_SIDE', 'b1', version: 1),
        _photo('b2-front', 'SHOP_FRONT', 'b2', version: 1),
      ],
      'progress': {'percent': 50, 'required': 3, 'done': 3, 'missing': []},
      'reworks': const [],
    };

class _Api extends RecceApi {
  _Api() : super(Dio());
  @override
  Future<ShopDetail> detail(String siteId) async => ShopDetail.fromJson(_detail());
  @override
  Future<List<RecceVersion>> versions(String siteId) async => const [];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a photo is resubmitted when it replaced an earlier one in the current version', () {
    final d = ShopDetail.fromJson(_detail());
    expect(d.isResubmitted(d.photos.firstWhere((p) => p.id == 'b1-front-new')), isTrue);
    expect(d.isResubmitted(d.photos.firstWhere((p) => p.id == 'b1-left')), isFalse);
    expect(d.isResubmitted(null), isFalse);
    expect(d.resubmittedCount('b1'), 1);
    expect(d.resubmittedCount('b2'), 0);
  });

  testWidgets('a submitted shop folds every board; a tap opens one, a tap on it folds it again', (t) async {
    t.view.physicalSize = const Size(412, 3200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final api = _Api();
    final queue = UploadQueue(api, autoRetry: false);
    final c = ShopDetailController(api, queue, 's1');
    await c.load();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ListenableBuilder(listenable: c, builder: (_, _) => PhotosTab(ctrl: c)))));
    await t.pump();

    expect(c.canEdit, isFalse);
    expect(find.byKey(const ValueKey('board-row-b1')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-row-b2')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-b1-SHOP_FRONT')), findsNothing); // no photo grid yet
    expect(find.text('Tap a board to see its photos.'), findsOneWidget);
    // the folded line already says what was resubmitted
    expect(find.byKey(const Key('resubmitted-b1')), findsOneWidget);
    expect(find.text('1 photo resubmitted'), findsOneWidget);
    expect(find.byKey(const Key('resubmitted-b2')), findsNothing);

    await t.tap(find.byKey(const ValueKey('board-row-b1')));
    await t.pump();
    expect(find.byKey(const ValueKey('tile-b1-SHOP_FRONT')), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-b2-SHOP_FRONT')), findsNothing); // the other board stays one line
    expect(find.byKey(const ValueKey('board-row-b2')), findsOneWidget);
    expect(find.text('Resubmitted'), findsWidgets); // the tile caption (and its row in the Files list)

    await t.tap(find.byKey(const ValueKey('board-toggle-b1')));
    await t.pump();
    expect(find.byKey(const ValueKey('tile-b1-SHOP_FRONT')), findsNothing);
    expect(find.byKey(const ValueKey('board-row-b1')), findsOneWidget);
    expect(t.takeException(), isNull);
    c.dispose();
    queue.dispose();
  });
}
