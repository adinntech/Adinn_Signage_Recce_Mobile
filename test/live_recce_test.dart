import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signage_recce/core/network/api_exception.dart';
import 'package:signage_recce/core/network/dio_client.dart';
import 'package:signage_recce/core/network/token_manager.dart';
import 'package:signage_recce/core/storage/session_store.dart';
import 'package:signage_recce/data/models/models.dart' show GeoFix;
import 'package:signage_recce/data/services/location_service.dart';
import 'package:signage_recce/features/live_auth/data/auth_repository.dart';
import 'package:signage_recce/features/live_auth/domain/auth_models.dart';
import 'package:signage_recce/features/live_auth/domain/auth_rules.dart';
import 'package:signage_recce/features/live_auth/presentation/live_auth_controller.dart';
import 'package:signage_recce/features/live_recce/data/live_services.dart';
import 'package:signage_recce/features/live_recce/data/recce_api.dart';
import 'package:signage_recce/features/live_recce/data/recce_controllers.dart';
import 'package:signage_recce/features/live_recce/data/recce_models.dart';
import 'package:signage_recce/features/live_recce/data/submit_validator.dart';
import 'package:signage_recce/features/live_recce/data/upload_queue.dart';

import 'helpers.dart';

/// Fake data only: no network, no emulator, no database.
Map<String, dynamic> _shopRow(String id, String status, {String project = 'p1', String code = 'ADN-2451'}) => {
      'siteId': id,
      'projectId': project,
      'projectCode': code,
      'projectName': 'South Zone Retail Rollout',
      'client': 'ABC Retail',
      'siteCode': 'SM-$id',
      'shopName': id == 'a1' ? null : 'Sri Murugan Super Market',
      'address': 'T. Nagar, Chennai, 600017',
      'mediaTypes': [
        {'name': 'GSB', 'quantity': 2},
        {'name': 'Acrylic', 'quantity': 1},
      ],
      'assignedAt': '2026-11-20T05:00:00.000Z',
      'expectedBy': '2026-11-28T00:00:00.000Z',
      'status': status,
      'progress': 40,
      'photoCount': 3,
      'missing': 5,
      'reworkOpen': status == 'REWORK_REQUIRED',
      'version': 0,
      'submissionId': null,
    };

Map<String, dynamic> _photo(String id, String category, {double? lat = 13.04, double? lng = 80.23, double? acc = 8.2, bool verified = true, Map<String, dynamic>? review}) => {
      'id': id,
      'category': category,
      'state': 'DRAFT',
      'mediaKey': '',
      'capturedAt': '2026-11-21T06:30:00.000Z',
      'lat': lat,
      'lng': lng,
      'gpsAccuracy': acc,
      'gpsVerified': verified,
      'source': 'LIVE_CAMERA',
      'url': 'http://host/file/$id.jpg',
      'flags': const [],
      'review': review ?? {'status': 'PENDING', 'openRework': null},
    };

Map<String, dynamic> _detail({List<Map<String, dynamic>>? photos, List<Map<String, dynamic>>? mediaItems, Map<String, dynamic>? installation, List<Map<String, dynamic>>? reworks}) => {
      'siteId': 's1',
      'siteCode': 'SM-0234',
      'shopName': 'Sri Murugan Super Market',
      'address': 'T. Nagar, Chennai, 600017',
      'project': {'id': 'p1', 'code': 'ADN-2451', 'name': 'South Zone', 'client': 'ABC Retail', 'expectedBy': '2026-11-28T00:00:00.000Z', 'closed': false},
      'status': 'IN_PROGRESS',
      'editable': true,
      'version': 0,
      'mediaItems': mediaItems ??
          [
            {'key': 'b1', 'name': 'GSB', 'quantity': 2, 'width': 6, 'height': 4, 'unit': 'FT', 'required': ['SHOP_FRONT']},
          ],
      'installation': installation,
      'notes': 'Shop open from 9 am',
      'photos': photos ?? <Map<String, dynamic>>[],
      'progress': {'percent': 25, 'required': 8, 'done': 2, 'missing': []},
      'versions': [
        {'version': 1, 'submittedAt': '2026-11-22T05:00:00.000Z', 'photoCount': 6},
      ],
      'reviews': [
        {'versionNo': 1, 'stage': 'OPS', 'stageLabel': 'Recce Operations', 'decision': 'REWORK', 'comment': 'Retake front', 'reviewer': 'Asha', 'decidedAt': '2026-11-22T08:00:00.000Z'},
      ],
      'reworks': reworks ?? <Map<String, dynamic>>[],
    };

List<ShopPhoto> _allSix({Map<String, double?> lat = const {}}) => [
      for (final c in requiredPhotoCategories) ShopPhoto.fromJson(_photo('ph-${c.key}', c.key, lat: lat.containsKey(c.key) ? lat[c.key] : 13.04)),
    ];

Installation _answered() => Installation(
      ladderRequired: triYes,
      scaffoldingRequired: triNo,
      craneRequired: triNo,
      hydraRequired: triNo,
      manualInstallationPossible: triYes,
    );

/// Scripted upload server: [script] decides, per photo and attempt number, whether the upload works or throws.
class _FakeApi extends RecceApi {
  _FakeApi([this.script]) : super(Dio());

  Future<void> Function(UploadItem u, int attempt)? script;
  final attempts = <String, int>{};
  int shopCalls = 0;

  int get uploadCalls => attempts.values.fold(0, (a, b) => a + b);

  @override
  Future<void> uploadPhoto(UploadItem u, {required void Function(double) onProgress, CancelToken? cancel}) async {
    final n = attempts[u.id] = (attempts[u.id] ?? 0) + 1;
    await script?.call(u, n);
  }

  @override
  Future<ShopListPage> shops() async {
    shopCalls++;
    return ShopListPage(items: const [], total: 0, summary: const {});
  }
}

ApiException _http(int status, [String message = 'No']) => ApiException(code: 'X', message: message, statusCode: status);

class _MemoryStore implements SessionStore {
  String? refresh;
  String? user;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<String?> readUserJson() async => user;

  @override
  Future<void> save({required String refreshToken, required String userJson}) async {
    refresh = refreshToken;
    user = userJson;
  }

  @override
  Future<void> clear() async {
    refresh = null;
    user = null;
  }
}

/// Auth repository with no network: [login] returns [signedIn] or throws [failWith].
class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo({this.signedIn, this.failWith})
      : super(plainDio: Dio(), tokens: TokenManager(refreshDio: Dio(), store: _MemoryStore()), store: _MemoryStore());

  final LiveUser? signedIn;
  final Object? failWith;

  @override
  Future<LiveUser> login(String identifier, AuthCredential credential, {String? loginRole}) async {
    if (failWith != null) throw failWith!;
    return signedIn!;
  }

  @override
  Future<void> logout() async {}
}

LiveUser _recceUser([String id = 'u1']) => LiveUser(id: id, name: 'Siva', email: 'siva@x.com', role: LiveRole.recceExecutive);

/// A location service that has the strict path, to prove [freshFixOf] picks it.
class _StrictLocation implements LocationService, StrictLocationService {
  int fresh = 0;
  int current = 0;

  @override
  Future<GeoFix> freshFix({Duration timeout = const Duration(seconds: 15)}) async {
    fresh++;
    return gpsAt(1, 2);
  }

  @override
  Future<GeoFix> currentFix({Duration timeout = const Duration(seconds: 20)}) async {
    current++;
    return gpsAt(9, 9);
  }

  @override
  Future<bool> openSettings({bool appSettings = false}) async => true;
}

Position _position(DateTime at, {double lat = 13.04, double lng = 80.23, double accuracy = 6}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: at,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  group('shop list parsing', () {
    test('parses rows, meta.summary and totals', () {
      final body = {
        'success': true,
        'data': [_shopRow('a1', 'NOT_STARTED'), _shopRow('a2', 'REWORK_REQUIRED')],
        'meta': {
          'page': 1,
          'limit': 50,
          'total': 2,
          'summary': {'NOT_STARTED': 1, 'REWORK_REQUIRED': 1},
        },
      };
      final page = ShopListPage.fromEnvelope(body);
      expect(page.items, hasLength(2));
      expect(page.total, 2);
      expect(page.summary, {'NOT_STARTED': 1, 'REWORK_REQUIRED': 1});

      final s = page.items.first;
      expect(s.title, 'SM-a1'); // no shopName: falls back to the site code
      expect(page.items.last.title, 'Sri Murugan Super Market');
      expect(s.mediaTypes, ['GSB x 2', 'Acrylic x 1']);
      expect(s.assignedAt, isNotNull);
      expect(s.expectedBy!.toUtc(), DateTime.utc(2026, 11, 28));
      expect(page.items.last.reworkOpen, isTrue);
    });

    test('tolerates a missing meta block', () {
      final page = ShopListPage.fromEnvelope({'data': [_shopRow('a1', 'APPROVED')]});
      expect(page.items, hasLength(1));
      expect(page.summary, isEmpty);
    });

    test('dashboard counts come from the status summary', () {
      final c = DashboardCounts.fromSummary({
        'NOT_STARTED': 2,
        'IN_PROGRESS': 3,
        'READY_TO_SUBMIT': 1,
        'SUBMITTED': 4,
        'UNDER_REVIEW': 1,
        'APPROVED': 5,
        'REWORK_REQUIRED': 2,
      });
      expect(c.total, 18);
      expect(c.pending, 6);
      expect(c.submitted, 5);
      expect(c.approved, 5);
      expect(c.rework, 2);
    });

    test('groups by project and filters by status', () {
      final shops = [
        ShopSummary.fromJson(_shopRow('a1', 'APPROVED')),
        ShopSummary.fromJson(_shopRow('a2', 'REWORK_REQUIRED')),
        ShopSummary.fromJson(_shopRow('a3', 'SUBMITTED', project: 'p2', code: 'ADN-1000')),
      ];
      final groups = groupByProject(shops);
      expect(groups.map((g) => g.code), ['ADN-1000', 'ADN-2451']);
      expect(groups.last.shops, hasLength(2));
      expect(groups.last.done, 1);
      expect(groups.last.rework, 1);
      expect(shops.where((s) => ShopFilter.submitted.matches(s.status)), hasLength(1));
      expect(shops.where((s) => ShopFilter.all.matches(s.status)), hasLength(3));
    });
  });

  group('shop detail parsing', () {
    test('reads header, boards, notes, versions and reviews', () {
      final d = ShopDetail.fromJson(_detail());
      expect(d.title, 'Sri Murugan Super Market');
      expect(d.project.code, 'ADN-2451');
      expect(d.project.client, 'ABC Retail');
      expect(d.editable, isTrue);
      expect(d.mediaItems.single.width, 6);
      expect(d.mediaItems.single.sided, 'SINGLE'); // field not shipped yet: safe default
      expect(d.notes, 'Shop open from 9 am');
      expect(d.versions.single.version, 1);
      expect(d.reviews.single.decision, 'REWORK');
      expect(d.reviews.single.reviewer, 'Asha');
    });

    test('installation missing in the response means NOT_ASSESSED, never NO', () {
      final d = ShopDetail.fromJson(_detail());
      expect(d.installation.ladderRequired, triUnknown);
      expect(d.installation.unanswered, hasLength(5));
      expect(d.installation.electricalAccess, triUnknown);
    });

    test('reads photos with GPS, accuracy and the review block', () {
      final d = ShopDetail.fromJson(_detail(photos: [
        _photo('p1', 'SHOP_FRONT'),
        _photo('p2', 'SIDE_VIEW', acc: 120, verified: false),
        _photo('p3', 'LONG_SHOT', lat: null, lng: null, verified: false),
        _photo('p4', 'ACCESS_PATH', review: {
          'status': 'REWORK_REQUIRED',
          'openRework': {'reason': 'Board not clear', 'requestedBy': 'Asha', 'requestedByRole': 'Recce Operations', 'requestedAt': '2026-11-22T08:00:00.000Z'},
        }),
      ]));
      final front = d.photoFor('SHOP_FRONT')!;
      expect(front.hasGps, isTrue);
      expect(front.locationUnverified, isFalse);
      expect(front.source, 'LIVE_CAMERA');
      expect(d.photoFor('SIDE_VIEW')!.locationUnverified, isTrue); // accuracy 120 m is worse than 50 m
      expect(d.photoFor('LONG_SHOT')!.hasGps, isFalse);
      final flagged = d.photoFor('ACCESS_PATH')!;
      expect(flagged.needsRework, isTrue);
      final note = d.reworkNoteFor(flagged)!;
      expect(note.reason, 'Board not clear');
      expect(note.by, 'Asha');
      expect(note.role, 'Recce Operations');
      expect(note.at, isNotNull);
      expect(d.photoFor('LOCATION_VIEW'), isNull);
    });

    test('rework reason falls back to the open rework item that names the photo', () {
      final d = ShopDetail.fromJson(_detail(
        photos: [_photo('p9', 'SHOP_FRONT', review: {'status': 'REWORK_REQUIRED'})],
        reworks: [
          {
            'id': 'r1',
            'versionNo': 1,
            'stage': 'OPS',
            'stageLabel': 'Recce Operations',
            'kind': 'REWORK',
            'status': 'OPEN',
            'instructions': 'Fix these',
            'requestedBy': 'Asha',
            'requestedAt': '2026-11-22T08:00:00.000Z',
            'items': [
              {'type': 'REPLACE_PHOTO', 'category': 'SHOP_FRONT', 'categoryLabel': 'Front View', 'photo': 'p9', 'note': 'Too dark', 'resolved': false},
            ],
          },
        ],
      ));
      final note = d.reworkNoteFor(d.photos.single)!;
      expect(note.reason, 'Too dark');
      expect(note.by, 'Asha');
      expect(note.role, 'Recce Operations');
    });

    test('board items and installation serialise for PUT /draft', () {
      final b = BoardItem(key: 'b2', name: 'ACP', quantity: 3, width: 8, height: 4.5, sided: 'DOUBLE', condition: 'EXISTING', position: ' Fascia ');
      expect(b.toJson(), {
        'key': 'b2',
        'name': 'ACP',
        'quantity': 3,
        'width': 8.0,
        'height': 4.5,
        'unit': 'FT',
        'sided': 'DOUBLE',
        'condition': 'EXISTING',
        'position': 'Fascia',
      });
      final inst = _answered()..installationHeightFt = 12;
      final j = inst.toJson();
      expect(j['ladderRequired'], 'YES');
      expect(j['craneRequired'], 'NO');
      expect(j['electricalAccess'], 'NOT_ASSESSED');
      expect(j['installationHeightFt'], 12.0);
      expect(Installation().toJson().containsKey('installationHeightFt'), isFalse);
    });

    test('different sizes get unique keys', () {
      expect(nextBoardKey(const []), 'b1');
      expect(nextBoardKey(['b1', 'b2']), 'b3');
      expect(nextBoardKey(['b2']), 'b1');
    });
  });

  group('submit validator', () {
    test('passes when everything is present', () {
      final p = validateForSubmit(photos: _allSix(), boards: [BoardItem(key: 'b1', width: 6, height: 4)], installation: _answered());
      expect(p, isEmpty);
    });

    test('lists missing photos by name', () {
      final photos = _allSix().where((p) => p.category != 'SIDE_VIEW' && p.category != 'ACCESS_PATH').toList();
      final p = validateForSubmit(photos: photos, boards: [BoardItem(key: 'b1', width: 6, height: 4)], installation: _answered());
      expect(p, containsAll(['Side View photo is missing', 'Access Path photo is missing']));
      expect(p, hasLength(2));
    });

    test('a photo without GPS blocks submit', () {
      final photos = _allSix(lat: {'LONG_SHOT': null});
      final p = validateForSubmit(photos: photos, boards: [BoardItem(key: 'b1', width: 6, height: 4)], installation: _answered());
      expect(p.single, contains('Long Shot'));
      expect(p.single, contains('GPS'));
    });

    test('a weak-accuracy photo with coordinates is still allowed (the server flags it)', () {
      final photos = [
        for (final c in requiredPhotoCategories) ShopPhoto.fromJson(_photo('x${c.key}', c.key, acc: 300, verified: false)),
      ];
      final p = validateForSubmit(photos: photos, boards: [BoardItem(key: 'b1', width: 6, height: 4)], installation: _answered());
      expect(p, isEmpty);
    });

    test('every board needs width, height and quantity', () {
      final p = validateForSubmit(
        photos: _allSix(),
        boards: [BoardItem(key: 'b1', width: 6, height: 4), BoardItem(key: 'b2', quantity: 0, width: null, height: 0)],
        installation: _answered(),
      );
      expect(p.any((e) => e.contains('(b2)') && e.contains('quantity')), isTrue);
      expect(p.any((e) => e.contains('(b2)') && e.contains('width')), isTrue);
      expect(p.any((e) => e.contains('(b2)') && e.contains('height')), isTrue);
      expect(p.any((e) => e.contains('(b1)')), isFalse);
    });

    test('no boards, unanswered installation and pending uploads are reported', () {
      final p = validateForSubmit(photos: _allSix(), boards: const [], installation: Installation(ladderRequired: triYes), pendingUploads: 2);
      expect(p, contains('Add at least one board'));
      expect(p.any((e) => e.startsWith('Installation not answered') && e.contains('Scaffolding') && !e.contains('Ladder')), isTrue);
      expect(p, contains('2 photos are still uploading'));
    });

    test('submit key is stable per version', () {
      expect(submitKey('67f0a1', 0), 'submit-67f0a1-1');
      expect(submitKey('67f0a1', 1), 'submit-67f0a1-2');
    });
  });

  group('upload meta', () {
    UploadItem item() => UploadItem(
          id: 'c1732170000000123456',
          siteId: 's1',
          path: '/data/shot.jpg',
          category: 'SHOP_FRONT',
          caption: 'Front',
          capturedAt: DateTime.parse('2026-11-21T12:00:00+05:30'),
          lat: 13.0412,
          lng: 80.2345,
          accuracy: 8.2,
          width: 3000,
          height: 4000,
          device: 'android / Adinn Recce 1.0',
        );

    test('meta matches the contract and encodes as a one-item JSON array', () {
      final meta = item().meta();
      expect(meta['clientId'], 'c1732170000000123456');
      expect(meta['category'], 'SHOP_FRONT');
      expect(meta['mediaKey'], '');
      expect(meta['capturedAt'], '2026-11-21T06:30:00.000Z'); // UTC
      expect(meta['lat'], 13.0412);
      expect(meta['lng'], 80.2345);
      expect(meta['gpsAccuracy'], 8.2);
      expect(meta['width'], 3000);
      expect(meta['source'], 'LIVE_CAMERA');
      expect(meta['device'], 'android / Adinn Recce 1.0');
      expect(meta.containsKey('replaces'), isFalse);
      final decoded = jsonDecode(jsonEncode([meta])) as List;
      expect(decoded, hasLength(1));
      expect((decoded.single as Map)['clientId'], meta['clientId']);
    });

    test('a photo without GPS sends no lat/lng (the server flags GPS_MISSING)', () {
      final meta = UploadItem(id: 'c1', siteId: 's1', path: '/x.jpg', category: 'SIDE_VIEW').meta();
      expect(meta.containsKey('lat'), isFalse);
      expect(meta.containsKey('lng'), isFalse);
      expect(meta.containsKey('gpsAccuracy'), isFalse);
    });

    test('survives being saved on the phone and restored', () {
      final restored = UploadItem.fromJson(jsonDecode(jsonEncode(item().toJson())) as Map<String, dynamic>);
      expect(restored.id, 'c1732170000000123456');
      expect(restored.siteId, 's1');
      expect(restored.path, '/data/shot.jpg');
      expect(restored.lat, 13.0412);
      expect(restored.accuracy, 8.2);
      expect(restored.source, 'LIVE_CAMERA');
      expect(restored.capturedAt!.toUtc(), DateTime.utc(2026, 11, 21, 6, 30));
    });

    test('newClientId is long enough for the server (8+) and unique', () {
      final a = newClientId();
      final b = newClientId();
      expect(a.length, greaterThanOrEqualTo(8));
      expect(a, isNot(b));
    });
  });

  group('auth validators', () {
    test('phone: exactly 10 digits starting 6-9', () {
      expect(AuthRules.phone('9876543210'), isNull);
      expect(AuthRules.phone('6000000000'), isNull);
      expect(AuthRules.phone(''), isNotNull);
      expect(AuthRules.phone('987654321'), contains('exactly 10'));
      expect(AuthRules.phone('98765432101'), contains('exactly 10'));
      expect(AuthRules.phone('98765abcde'), contains('exactly 10'));
      expect(AuthRules.phone('5876543210'), contains('start with'));
    });

    test('MPIN: sign in needs 4 digits; new MPIN rejects trivial ones', () {
      expect(AuthRules.signInMpin('1234'), isNull);
      expect(AuthRules.signInMpin('123'), isNotNull);
      expect(AuthRules.signInMpin('12a4'), isNotNull);
      expect(AuthRules.newMpin('4829'), isNull);
      expect(AuthRules.newMpin('1111'), isNotNull);
      expect(AuthRules.newMpin('1234'), isNotNull);
      expect(AuthRules.newMpin('48291'), isNotNull);
    });

    test('identifier, vendor id and reset code', () {
      expect(AuthRules.identifier('emp101'), isNull);
      expect(AuthRules.identifier('a@b.co'), isNull);
      expect(AuthRules.identifier('a@b'), isNotNull);
      expect(AuthRules.identifier(' '), isNotNull);
      expect(AuthRules.vendorId('4821'), isNull);
      expect(AuthRules.vendorId('48'), isNotNull);
      expect(AuthRules.resetCode('123456'), isNull);
      expect(AuthRules.resetCode('12345'), isNotNull);
    });

    test('register body matches POST /auth/register', () {
      final body = const RegisterRequest(
        name: ' Siva ',
        email: 'Siva@X.com',
        phone: '9876543210',
        employeeId: 'emp101',
        role: LiveRole.vendor,
        credential: MpinCredential('4829'),
      ).toBody();
      expect(body, {
        'name': 'Siva',
        'email': 'siva@x.com',
        'phone': '9876543210',
        'employeeId': 'emp101',
        'role': 'VENDOR',
        'platform': 'mobile',
        'authMethod': 'MPIN',
        'mpin': '4829',
      });
    });

    test('user json: vendor name and forced MPIN change', () {
      final u = LiveUser.fromJson({'id': 'u1', 'name': 'Siva', 'email': 'a@b.co', 'role': 'VENDOR', 'mustChangeMpin': true, 'vendor': {'name': 'Siva Creations'}});
      expect(u.role, LiveRole.vendor);
      expect(u.vendorName, 'Siva Creations');
      expect(u.mustChangeMpin, isTrue);
      expect(LiveUser.fromJson({'id': 'u2', 'name': 'X', 'email': '', 'role': 'BD'}).role.isFieldStaff, isFalse);
    });
  });

  group('error envelope', () {
    test('the server message reaches the screen', () {
      final e = ApiException.fromBody({'success': false, 'message': 'Add the missing photos first', 'error': {'code': 'VALIDATION_ERROR', 'details': []}}, 400);
      expect(e.message, 'Add the missing photos first');
      expect(e.code, 'VALIDATION_ERROR');
      expect(e.statusCode, 400);
    });

    test('falls back to the status code when there is no body', () {
      expect(ApiException.fromBody('oops', 502).message, 'Request failed (502)');
    });

    test('error.details {path, message} is appended to the message; code and status stay', () {
      final e = ApiException.fromBody({
        'success': false,
        'error': {
          'code': 'VALIDATION_ERROR',
          'message': 'Validation failed',
          'details': [
            {'path': 'installation.craneRequired', 'message': 'craneRequired is not assessed'},
          ],
        },
      }, 422);
      expect(e.message, 'Validation failed: craneRequired is not assessed');
      expect(e.code, 'VALIDATION_ERROR');
      expect(e.statusCode, 422);
      expect(e.details, ['craneRequired is not assessed']);
    });

    test('a message that does not name its field gets the path in front (zod style)', () {
      final e = ApiException.fromBody({
        'error': {
          'code': 'VALIDATION_ERROR',
          'message': 'Validation failed',
          'details': [
            {'path': 'phone', 'message': 'Phone number must be exactly 10 digits'},
            {'path': 'name', 'message': 'Required'},
          ],
        },
      }, 422);
      expect(e.message, 'Validation failed: Phone number must be exactly 10 digits; name: Required');
    });

    test('plain string details work, at most 3 are shown and the rest is counted', () {
      final e = ApiException.fromBody({
        'error': {
          'code': 'MISSING_EVIDENCE',
          'message': 'Required photos are missing',
          'details': ['Front View is required', 'Side View is required', 'Long Shot is required', 'Access Path is required', 'Board is required'],
        },
      }, 422);
      expect(e.message, 'Required photos are missing: Front View is required; Side View is required; Long Shot is required (+2 more)');
      expect(e.details, hasLength(5)); // nothing is lost, only the screen text is short
    });

    test('a detail the message already says is not repeated', () {
      final e = ApiException.fromBody({
        'error': {
          'code': 'VALIDATION_ERROR',
          'message': 'Say why the claim is rejected',
          'details': [
            {'path': 'remark', 'message': 'Say why the claim is rejected'},
          ],
        },
      }, 422);
      expect(e.message, 'Say why the claim is rejected');
    });

    test('empty, null or odd details change nothing; details alone still give a message', () {
      expect(ApiException.fromBody({'message': 'Add the missing photos first', 'error': {'code': 'VALIDATION_ERROR', 'details': []}}, 400).message, 'Add the missing photos first');
      expect(ApiException.fromBody({'message': 'Bad', 'error': {'code': 'X', 'details': null}}, 400).message, 'Bad');
      expect(ApiException.fromBody({'message': 'Bad', 'error': {'code': 'X', 'details': 42}}, 400).message, 'Bad');
      expect(ApiException.fromBody({'message': 'Bad', 'error': {'code': 'X', 'details': [{'path': 'a'}, 7, <String, dynamic>{}]}}, 400).message, 'Bad');
      final only = ApiException.fromBody({'error': {'code': 'X', 'details': ['Phone is taken']}}, 409);
      expect(only.message, 'Request failed (409): Phone is taken');
      expect(only.statusCode, 409);
    });

    test('very long detail lines are cut', () {
      final e = ApiException.fromBody({'error': {'code': 'X', 'message': 'Bad', 'details': ['x' * 400]}}, 400);
      expect(e.message.length, lessThan(160));
    });
  });

  group('upload retry rules', () {
    test('network, 5xx, 408 and 401 are retryable; other 4xx are not', () {
      for (final s in [null, 500, 502, 503, 408, 401]) {
        expect(uploadErrorRetryable(s), isTrue, reason: '$s');
      }
      for (final s in [400, 403, 404, 409, 413, 422]) {
        expect(uploadErrorRetryable(s), isFalse, reason: '$s');
      }
    });

    test('only a request with a body gets a send timeout; uploads get the long one', () {
      expect(sendTimeoutFor(null), isNull);
      expect(sendTimeoutFor({'a': 1}), jsonSendTimeout);
      expect(sendTimeoutFor(FormData.fromMap({'a': '1'})), uploadSendTimeout);
      expect(uploadSendTimeout, greaterThan(jsonSendTimeout));
    });
  });

  group('upload queue', () {
    late Directory dir;
    late _FakeApi api;
    late UploadQueue queue;

    File photo(String name) => File('${dir.path}/$name.jpg')..writeAsBytesSync([1, 2, 3]);
    UploadItem item(String id, File f) => UploadItem(id: id, siteId: 's1', path: f.path, category: 'SHOP_FRONT');
    UploadItem only() => queue.items.single;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('upload_queue_test');
      api = _FakeApi();
      queue = UploadQueue(api, autoRetry: false);
    });

    tearDown(() {
      queue.dispose();
      dir.deleteSync(recursive: true);
    });

    test('a photo that uploads is removed and its local copy deleted', () async {
      final f = photo('ok');
      queue.add(item('c-ok-00001', f));
      await pumpEventQueue();
      expect(queue.items, isEmpty);
      expect(f.existsSync(), isFalse);
    });

    test('401: the photo is sent again at once, and a success then clears it', () async {
      final f = photo('a');
      api.script = (u, n) async {
        if (n == 1) throw _http(401, 'Invalid or expired token');
      };
      queue.add(item('c-401-0001', f));
      await pumpEventQueue();
      expect(api.attempts['c-401-0001'], 2); // one automatic re-send, no waiting for a timer or a tap
      expect(queue.items, isEmpty);
      expect(f.existsSync(), isFalse);
    });

    test('401 twice in a row: failed but retryable, so the timer sends it again; it never blocks forever', () async {
      final f = photo('b');
      api.script = (u, n) async {
        if (n <= 2) throw _http(401, 'Invalid or expired token');
      };
      queue.add(item('c-401-0002', f));
      await pumpEventQueue();
      expect(api.attempts['c-401-0002'], 2);
      expect(only().status, UploadStatus.failed);
      expect(only().retryable, isTrue);
      expect(only().error, 'Invalid or expired token');

      queue.retryFailedNow(); // the 30 s timer
      await pumpEventQueue();
      expect(api.attempts['c-401-0002'], 3);
      expect(queue.items, isEmpty);
      expect(f.existsSync(), isFalse);
    });

    test('a person tapping Retry after repeated 401s gets the immediate re-send again', () async {
      final f = photo('c');
      api.script = (u, n) async {
        if (n != 4) throw _http(401, 'Invalid or expired token');
      };
      queue.add(item('c-401-0003', f));
      await pumpEventQueue();
      expect(only().status, UploadStatus.failed);
      queue.retry('c-401-0003');
      await pumpEventQueue();
      // attempt 3 fails (401), attempt 4 is the immediate re-send and works
      expect(api.attempts['c-401-0003'], 4);
      expect(queue.items, isEmpty);
    });

    test('other 4xx stay failed and the timer does not retry them', () async {
      final f = photo('d');
      api.script = (u, n) async => throw _http(422, 'Invalid file');
      queue.add(item('c-422-0001', f));
      await pumpEventQueue();
      expect(only().status, UploadStatus.failed);
      expect(only().retryable, isFalse);
      queue.retryFailedNow();
      await pumpEventQueue();
      expect(api.attempts['c-422-0001'], 1);
      expect(f.existsSync(), isTrue); // the person may still retry, so the copy stays
    });

    test('a 5xx or no network is retried by the timer', () async {
      final f = photo('e');
      api.script = (u, n) async {
        if (n == 1) throw _http(503, 'Unavailable');
        if (n == 2) throw const ApiException(code: ApiException.networkCode, message: 'Cannot reach the server.');
      };
      queue.add(item('c-503-0001', f));
      await pumpEventQueue();
      expect(only().retryable, isTrue);
      queue.retryFailedNow();
      await pumpEventQueue();
      expect(only().status, UploadStatus.failed);
      queue.retryFailedNow();
      await pumpEventQueue();
      expect(queue.items, isEmpty);
      expect(api.attempts['c-503-0001'], 3);
    });

    test('409 "already uploaded" drops the item, announces the shop and deletes the local copy', () async {
      final f = photo('f');
      api.script = (u, n) async => throw const ApiException(code: 'CONFLICT', message: 'This photo was already uploaded', statusCode: 409);
      final seen = <String>[];
      final sub = queue.uploaded.listen(seen.add);
      queue.add(item('c-409-0001', f));
      await pumpEventQueue();
      await sub.cancel();
      expect(queue.items, isEmpty);
      expect(seen, ['s1']);
      expect(f.existsSync(), isFalse);
    });

    test('other 409s keep the item and the file', () async {
      final f = photo('g');
      api.script = (u, n) async => throw const ApiException(code: 'CONFLICT', message: 'Shop is submitted', statusCode: 409);
      queue.add(item('c-409-0002', f));
      await pumpEventQueue();
      expect(only().status, UploadStatus.failed);
      expect(f.existsSync(), isTrue);
    });

    test('cancel deletes the local copy of a running and of a waiting upload', () async {
      final gate = Completer<void>();
      api.script = (u, n) => gate.future;
      final files = [for (var i = 0; i < 3; i++) photo('h$i')];
      for (var i = 0; i < 3; i++) {
        queue.add(item('c-cancel-000$i', files[i]));
      }
      await pumpEventQueue();
      expect(queue.items.where((u) => u.status == UploadStatus.uploading), hasLength(UploadQueue.maxParallel));
      queue.cancel('c-cancel-0000'); // running
      queue.cancel('c-cancel-0002'); // waiting
      expect(files[0].existsSync(), isFalse);
      expect(files[2].existsSync(), isFalse);
      expect(queue.items.map((u) => u.id), ['c-cancel-0001']);
      expect(files[1].existsSync(), isTrue);
      gate.complete();
      await pumpEventQueue();
      expect(queue.items, isEmpty); // the remaining one uploaded
    });

    test('clearAll (sign out) deletes every local copy', () async {
      final gate = Completer<void>();
      api.script = (u, n) => gate.future;
      final files = [for (var i = 0; i < 3; i++) photo('i$i')];
      for (var i = 0; i < 3; i++) {
        queue.add(item('c-clear-000$i', files[i]));
      }
      await pumpEventQueue();
      await queue.clearAll();
      expect(queue.items, isEmpty);
      for (final f in files) {
        expect(f.existsSync(), isFalse);
      }
      gate.complete();
      await pumpEventQueue(); // the cancelled uploads finishing must not bring anything back
      expect(queue.items, isEmpty);
    });
  });

  group('unexpected sign-in errors', () {
    test('an unexpected exception shows a friendly message, never the raw text', () async {
      final c = LiveAuthController(_FakeAuthRepo(failWith: StateError('mongodb://user:pw@host failed: boom')));
      final ok = await c.login('a@b.co', const MpinCredential('4829'), loginRole: 'RECCE');
      expect(ok, isFalse);
      final shown = friendlyAuthMessage(c.error!);
      expect(shown, 'Something went wrong. Please try again.');
      expect(shown, genericAuthMessage);
      expect('${c.error!.message} $shown', isNot(contains('mongodb')));
      expect(c.error!.code, 'UNKNOWN');
      expect(c.busy, isFalse);
      c.dispose();
    });

    test('a server answer still reaches the screen (AuthFailure is not made generic)', () async {
      final c = LiveAuthController(_FakeAuthRepo(failWith: const AuthFailure('VALIDATION_ERROR', 'Validation failed: name: Required')));
      await c.login('a@b.co', const MpinCredential('4829'), loginRole: 'RECCE');
      expect(friendlyAuthMessage(c.error!), 'Validation failed: name: Required');
      c.dispose();
    });
  });

  group('shops reload on every sign in', () {
    test('sign out then the same person signs in again: the shops are loaded again', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi();
      final queue = UploadQueue(api, autoRetry: false);
      final shops = ShopListController(api, queue);
      final auth = LiveAuthController(_FakeAuthRepo(signedIn: _recceUser()));
      final services = LiveServices.withParts(auth: auth, api: api, queue: queue, shops: shops);
      await services.init();
      expect(api.shopCalls, 0); // nobody signed in

      await auth.login('siva@x.com', const MpinCredential('4829'), loginRole: 'RECCE');
      await pumpEventQueue();
      expect(api.shopCalls, 1);
      expect(shops.loaded, isTrue);

      // Status changes of the same session (busy, offline demo, ...) must not start another load.
      auth.enterOfflineDemo();
      auth.leaveOfflineDemo();
      await pumpEventQueue();
      expect(api.shopCalls, 1);

      await services.signOut();
      expect(shops.loaded, isFalse);
      expect(shops.shops, isEmpty);

      await auth.login('siva@x.com', const MpinCredential('4829'), loginRole: 'RECCE');
      await pumpEventQueue();
      expect(api.shopCalls, 2); // before the fix this stayed 1 and the dashboard was empty
      expect(shops.loaded, isTrue);

      auth.dispose();
      shops.dispose();
      queue.dispose();
    });

    test('a different person signing in loads their shops too', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _FakeApi();
      final queue = UploadQueue(api, autoRetry: false);
      final shops = ShopListController(api, queue);
      final repo = _SwitchingRepo(_recceUser('u1'));
      final auth = LiveAuthController(repo);
      final services = LiveServices.withParts(auth: auth, api: api, queue: queue, shops: shops);
      await services.init();
      await auth.login('a@x.com', const MpinCredential('4829'), loginRole: 'RECCE');
      await pumpEventQueue();
      await services.signOut();
      repo.next = _recceUser('u2');
      await auth.login('b@x.com', const MpinCredential('4829'), loginRole: 'RECCE');
      await pumpEventQueue();
      expect(api.shopCalls, 2);
      auth.dispose();
      shops.dispose();
      queue.dispose();
    });
  });

  group('strict GPS for live photos', () {
    final now = DateTime.utc(2026, 11, 21, 6, 30, 0);

    test('a last known position younger than 30 s is accepted', () {
      final fix = lastKnownIfFresh(_position(now.subtract(const Duration(seconds: 12)), lat: 13.5, lng: 80.5, accuracy: 9), now: now);
      expect(fix, isNotNull);
      expect(fix!.latitude, 13.5);
      expect(fix.longitude, 80.5);
      expect(fix.accuracyM, 9);
      expect(lastKnownIfFresh(_position(now.subtract(freshFixMaxAge)), now: now), isNotNull); // exactly 30 s is still fresh
    });

    test('an older, missing or future position is refused (never the photo\'s own location)', () {
      expect(lastKnownIfFresh(_position(now.subtract(const Duration(seconds: 31))), now: now), isNull);
      expect(lastKnownIfFresh(_position(now.subtract(const Duration(hours: 3))), now: now), isNull);
      expect(lastKnownIfFresh(null, now: now), isNull);
      expect(lastKnownIfFresh(_position(now.add(const Duration(minutes: 5))), now: now), isNull);
    });

    test('freshFixOf uses the strict path when the service has one', () async {
      final s = _StrictLocation();
      final fix = await freshFixOf(s);
      expect(fix.latitude, 1);
      expect(s.fresh, 1);
      expect(s.current, 0);
    });

    test('a service without the strict path (test fakes) answers through currentFix', () async {
      final fake = FakeLocationService(fix: gpsAt(10, 20));
      final fix = await freshFixOf(fake);
      expect(fix.latitude, 10);
      expect(fake.calls, 1);
    });

    test('the timeout error is what the "Location is needed" dialog shows', () async {
      final fake = FakeLocationService(error: const LocationException(LocationIssue.timeout, 'Could not get a fresh GPS fix.'));
      await expectLater(
        freshFixOf(fake),
        throwsA(isA<LocationException>().having((e) => e.issue, 'issue', LocationIssue.timeout)),
      );
    });
  });
}

/// Like [_FakeAuthRepo] but the signed-in person can change between sign ins.
class _SwitchingRepo extends _FakeAuthRepo {
  _SwitchingRepo(this.next) : super(signedIn: next);

  LiveUser next;

  @override
  Future<LiveUser> login(String identifier, AuthCredential credential, {String? loginRole}) async => next;
}
