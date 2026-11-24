import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/features/live_recce/data/recce_api.dart';
import 'package:signage_recce/features/live_recce/data/recce_controllers.dart';
import 'package:signage_recce/features/live_recce/data/recce_models.dart';
import 'package:signage_recce/features/live_recce/data/upload_queue.dart';
import 'package:signage_recce/features/live_recce/presentation/capture_flow.dart';

/// The same picture may be used for other angles: the preview offers "Use this photo for other angles too", the chosen angles get a
/// copy of the picture (with its location and time), and nothing is refused for being the same picture. Fake data only.

class _Api extends RecceApi {
  _Api() : super(Dio());

  @override
  Future<ShopDetail> detail(String siteId) async => ShopDetail.fromJson({
        'siteId': 's1',
        'siteCode': 'SM-1',
        'project': {'id': 'p1', 'code': 'ADN-1', 'name': 'South', 'closed': false},
        'status': 'IN_PROGRESS',
        'editable': true,
        'version': 0,
        'mediaItems': [
          for (final k in ['b1', 'b2']) {'key': k, 'name': 'GSB', 'mediaType': 'GSB', 'seq': k == 'b1' ? 1 : 2, 'quantity': 1, 'width': 6, 'height': 4, 'unit': 'FT', 'required': <String>[]},
        ],
        'photos': [
          {'id': 'p1', 'category': 'LEFT_SIDE', 'state': 'DRAFT', 'mediaKey': 'b2', 'lat': 13.0, 'lng': 80.0, 'url': 'http://host/p1.jpg'},
        ],
        'progress': {'percent': 0, 'required': 0, 'done': 0, 'missing': []},
        'reworks': [],
      });

  @override
  Future<List<RecceVersion>> versions(String siteId) async => const [];
}

CapturedPhoto _shot() => CapturedPhoto(path: '/none/shot.jpg', lat: 13.04, lng: 80.23, accuracy: 8, capturedAt: DateTime.utc(2026, 11, 24, 6, 30));

/// Opens the preview from a button and keeps what it returned.
class _Host extends StatefulWidget {
  const _Host({required this.angles});
  final List<PhotoCategoryDef> angles;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  Object? result = 'not closed yet';

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('open'),
            onPressed: () async {
              final r = await Navigator.of(context).push<Object?>(MaterialPageRoute(builder: (_) => capturePreviewForTest(photo: _shot(), label: 'Front View', otherAngles: widget.angles)));
              setState(() => result = r);
            },
            child: const Text('open'),
          ),
        ),
      );
}

final _angles = boardPhotoCategories.where((c) => c.key != 'SHOP_FRONT').toList(); // Left, Right, Long Shot, Annotated, Location, Access Path

Future<_HostState> _open(WidgetTester tester, List<PhotoCategoryDef> angles) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: _Host(angles: angles)));
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return tester.state<_HostState>(find.byType(_Host, skipOffstage: false));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('preview: use this photo for other angles', () {
    testWidgets('with no empty angle left there is nothing to offer: plain "Use photo", no angles', (tester) async {
      final host = await _open(tester, const []);
      expect(find.byKey(const Key('also-toggle')), findsNothing);
      expect(find.text('Use photo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('preview-use')));
      await tester.pumpAndSettle();
      expect((host.result as dynamic).alsoFor, isEmpty);
    });

    testWidgets('nothing is ticked by default, and the choice stays hidden until asked for', (tester) async {
      final host = await _open(tester, _angles);
      expect(find.text('Use this photo for other angles too'), findsOneWidget);
      expect(find.byKey(const Key('also-SIDE_VIEW')), findsNothing);
      expect(find.byKey(const Key('also-LEFT_SIDE')), findsNothing); // closed
      await tester.tap(find.byKey(const Key('preview-use')));
      await tester.pumpAndSettle();
      expect((host.result as dynamic).alsoFor, isEmpty);
      expect((host.result as dynamic).choice.toString(), '_PreviewChoice.use');
    });

    testWidgets('ticked angles come back in angle order and the button says how many angles the picture serves', (tester) async {
      final host = await _open(tester, _angles);
      await tester.tap(find.byKey(const Key('also-toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('also-LONG_SHOT')));
      await tester.tap(find.byKey(const Key('also-LEFT_SIDE'))); // ticked second, still reported first
      await tester.pump();
      expect(find.text('Use for 3 angles'), findsOneWidget); // this angle + two more
      expect(find.text('Also used for 2 other angles'), findsOneWidget);
      await tester.tap(find.byKey(const Key('preview-use')));
      await tester.pumpAndSettle();
      expect((host.result as dynamic).alsoFor, ['LEFT_SIDE', 'LONG_SHOT']);
    });

    testWidgets('Select all ticks every empty angle, and Clear takes them off again', (tester) async {
      final host = await _open(tester, _angles);
      await tester.tap(find.byKey(const Key('also-toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('also-all')));
      await tester.pump();
      expect(find.text('Use for 7 angles'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      await tester.tap(find.byKey(const Key('also-all')));
      await tester.pump();
      expect(find.text('Use photo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('also-all')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('preview-use')));
      await tester.pumpAndSettle();
      expect((host.result as dynamic).alsoFor, _angles.map((c) => c.key).toList());
    });

    testWidgets('Retake and the close button never carry angles', (tester) async {
      final host = await _open(tester, _angles);
      await tester.tap(find.byKey(const Key('also-toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('also-LEFT_SIDE')));
      await tester.tap(find.text('Retake'));
      await tester.pumpAndSettle();
      expect((host.result as dynamic).choice.toString(), '_PreviewChoice.retake');
      expect((host.result as dynamic).alsoFor, isEmpty);

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(host.result, isNull);
    });
  });

  group('copies of one picture for the chosen angles', () {
    UploadItem first() => UploadItem(id: 'c-first-0001', siteId: 's1', path: '/none/shot.jpg', category: 'SHOP_FRONT', mediaKey: 'b1', lat: 13.04, lng: 80.23);

    test('each chosen angle of the board gets its own copy with the same location; other boards and other angles are not touched', () async {
      final api = _Api();
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      var n = 0;
      final queued = await c.queueFirstPhotoForAll(first(), [const PhotoSlot('LEFT_SIDE', 'b1'), const PhotoSlot('LONG_SHOT', 'b1')], (p) async => '$p.copy${++n}');
      expect(queued, 2);
      final mine = c.pending.where((u) => u.id != 'c-first-0001').toList();
      expect(mine.map((u) => u.category).toSet(), {'LEFT_SIDE', 'LONG_SHOT'});
      expect(mine.every((u) => u.mediaKey == 'b1' && u.lat == 13.04 && u.lng == 80.23), isTrue);
      expect(mine.map((u) => u.path).toSet(), hasLength(2)); // a file of its own each: the queue deletes a file once it is uploaded
      expect(mine.map((u) => u.id).toSet(), hasLength(2)); // and its own upload id, so none counts as a retry of another
      expect(c.pending.any((u) => u.mediaKey == 'b2'), isFalse);
      c.dispose();
      queue.dispose();
    });

    test('an angle that already has a photo, or one on its way, is left alone', () async {
      final api = _Api();
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      // b2 already has its Left View (p1)
      expect(await c.queueFirstPhotoForAll(first().copyAs(id: 'c-first-0002', path: '/none/b2.jpg', category: 'SHOP_FRONT', mediaKey: 'b2'), [const PhotoSlot('LEFT_SIDE', 'b2'), const PhotoSlot('RIGHT_SIDE', 'b2')], (p) async => '$p.c'), 1);
      // asking again for the same angle does not queue a second upload
      expect(await c.queueFirstPhotoForAll(first().copyAs(id: 'c-first-0003', path: '/none/b2.jpg', category: 'SHOP_FRONT', mediaKey: 'b2'), [const PhotoSlot('RIGHT_SIDE', 'b2')], (p) async => '$p.c'), 0);
      c.dispose();
      queue.dispose();
    });
  });
}
