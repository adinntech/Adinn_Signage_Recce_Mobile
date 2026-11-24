import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signage_recce/features/live_recce/data/recce_api.dart';
import 'package:signage_recce/features/live_recce/data/recce_controllers.dart';
import 'package:signage_recce/features/live_recce/data/recce_models.dart';
import 'package:signage_recce/features/live_recce/data/upload_queue.dart';
import 'package:signage_recce/features/live_recce/presentation/live_widgets.dart';
import 'package:signage_recce/features/live_recce/presentation/photos_tab.dart';

/// A photo the reviewer REJECTED shows "Rejected" and the reason for rejection; a plain rework photo keeps "Rework required".
/// Fake data only.

Map<String, dynamic> _photo(String id, String category, {required String status, String note = '', bool? rejected}) => {
      'id': id,
      'category': category,
      'state': 'SUBMITTED',
      'mediaKey': 'b1',
      'version': 1,
      'lat': 13.04,
      'lng': 80.23,
      'gpsAccuracy': 8.0,
      'gpsVerified': true,
      'url': 'http://host/$id.jpg',
      'review': {
        'status': status,
        'openRework': status == 'REWORK_REQUIRED'
            ? {
                'reworkId': 'rw1',
                'itemId': 'it-$id',
                'note': note,
                'stage': 'OPS',
                'stageLabel': 'Recce Operations',
                'instructions': 'Please fix',
                'requestedBy': 'Asha',
                'requestedAt': '2026-11-23T08:00:00.000Z',
                'rejected': ?rejected,
              }
            : null,
      },
    };

Map<String, dynamic> _detail() => {
      'siteId': 's1',
      'siteCode': 'SM-1',
      'shopName': 'Sri Murugan',
      'project': {'id': 'p1', 'code': 'ADN-1', 'name': 'South', 'closed': false},
      'status': 'REWORK_REQUIRED',
      'editable': false,
      'version': 1,
      'mediaItems': [
        {'key': 'b1', 'name': 'GSB', 'quantity': 1, 'width': 6, 'height': 4, 'unit': 'FT', 'required': ['SHOP_FRONT', 'LEFT_SIDE']},
      ],
      'photos': [
        _photo('p-front', 'SHOP_FRONT', status: 'REWORK_REQUIRED', note: 'Board is cut off', rejected: true),
        _photo('p-side', 'LEFT_SIDE', status: 'REWORK_REQUIRED', note: 'Please retake', rejected: false),
        _photo('p-long', 'LONG_SHOT', status: 'PENDING'),
      ],
      'progress': {'percent': 50, 'required': 3, 'done': 3, 'missing': []},
      'reworks': [
        {
          'id': 'rw1',
          'versionNo': 1,
          'stage': 'OPS',
          'stageLabel': 'Recce Operations',
          'kind': 'REWORK',
          'status': 'OPEN',
          'instructions': 'Please fix',
          'requestedBy': 'Asha',
          'requestedAt': '2026-11-23T08:00:00.000Z',
          'items': [
            {'id': 'it-p-front', 'type': 'REPLACE_PHOTO', 'category': 'SHOP_FRONT', 'categoryLabel': 'Front View', 'mediaKey': 'b1', 'photo': 'p-front', 'note': 'Board is cut off', 'rejected': true, 'resolved': false},
            {'id': 'it-p-side', 'type': 'REPLACE_PHOTO', 'category': 'LEFT_SIDE', 'categoryLabel': 'Left View', 'mediaKey': 'b1', 'photo': 'p-side', 'note': 'Please retake', 'resolved': false},
          ],
        },
      ],
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

  group('models', () {
    test('rejected comes from the photo flag, the rework item and the photo history', () {
      final d = ShopDetail.fromJson(_detail());
      final front = d.photos.firstWhere((p) => p.id == 'p-front');
      final side = d.photos.firstWhere((p) => p.id == 'p-side');
      final long = d.photos.firstWhere((p) => p.id == 'p-long');
      expect(front.isRejected, isTrue);
      expect(front.attentionLabel, 'Rejected');
      expect(front.needsRework, isTrue); // still has to be retaken: same flow as a rework
      expect(side.isRejected, isFalse);
      expect(side.attentionLabel, 'Rework required');
      expect(long.isRejected, isFalse);
      expect(d.reworkNoteFor(front)!.rejected, isTrue);
      expect(d.reworkNoteFor(front)!.reason, 'Board is cut off');
      expect(d.reworks.single.items.map((i) => i.rejected), [true, false]);
      expect(reworkItemText(d.reworks.single.items.first), 'Rejected: retake Front View: Board is cut off');
      expect(reworkItemText(d.reworks.single.items.last), 'Replace Left View: Please retake');
      expect(PhotoRework.fromJson({'reworkId': 'r', 'rejected': true}).rejected, isTrue);
      expect(PhotoRework.fromJson({'reworkId': 'r'}).rejected, isFalse);
    });

    test('an older server that sends no rejected flag keeps "Rework required"', () {
      final j = _detail();
      final p = (j['photos'] as List).first as Map<String, dynamic>;
      ((p['review'] as Map)['openRework'] as Map).remove('rejected');
      final d = ShopDetail.fromJson(j);
      expect(d.photos.first.isRejected, isFalse);
      expect(d.photos.first.attentionLabel, 'Rework required');
    });
  });

  group('screens', () {
    testWidgets('the Photos tab names a rejected photo "Rejected" with its reason and a plain rework photo "Rework required"', (t) async {
      t.view.physicalSize = const Size(412, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = _Api();
      final queue = UploadQueue(api, autoRetry: false);
      final c = ShopDetailController(api, queue, 's1');
      await c.load();
      await t.pumpWidget(MaterialApp(home: Scaffold(body: PhotosTab(ctrl: c))));
      await t.pump();

      // the tile of the rejected photo and its row in the Files list
      expect(find.text('Rejected'), findsNWidgets(2));
      expect(find.textContaining('Reason: Board is cut off'), findsOneWidget);
      // the plain rework photo is not called rejected, and shows no reason line
      expect(find.text('Rework required'), findsNWidgets(2));
      expect(find.textContaining('Reason: Please retake'), findsNothing);
      expect(t.takeException(), isNull);
      c.dispose();
      queue.dispose();
    });

    testWidgets('the rework box starts a rejected photo with "Reason for rejection" and the reviewer\'s own words', (t) async {
      final d = ShopDetail.fromJson(_detail());
      final front = d.photos.firstWhere((p) => p.id == 'p-front');
      final side = d.photos.firstWhere((p) => p.id == 'p-side');
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [ReworkBox(note: d.reworkNoteFor(front)), ReworkBox(note: d.reworkNoteFor(side))]))));
      expect(find.text('Reason for rejection'), findsOneWidget); // only the rejected photo has the heading
      expect(find.text('Board is cut off'), findsOneWidget);
      expect(find.text('Please retake'), findsOneWidget);
      expect(find.textContaining('Rejected by Asha'), findsOneWidget);
      expect(find.textContaining('Requested by Asha'), findsOneWidget);
    });

    testWidgets('a rejected photo with no written reason still says it was rejected', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: ReworkBox(note: ReworkNote(rejected: true)))));
      expect(find.text('Reason for rejection'), findsOneWidget);
      expect(find.text('The reviewer rejected this photo.'), findsOneWidget);
    });
  });
}

