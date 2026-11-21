import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/features/live_recce/data/recce_api.dart';
import 'package:signage_recce/features/live_recce/data/recce_models.dart';
import 'package:signage_recce/features/live_recce/data/submit_validator.dart';
import 'package:signage_recce/features/live_recce/presentation/live_widgets.dart';
import 'package:signage_recce/features/live_recce/presentation/versions_section.dart';

/// Milestone 2 (rework, versions, compare, approval history). Fake JSON in the exact shape of the backend
/// (recceReview.versions.ts, recceReview.field.ts, recceReview.review.ts `timeline`). No network, no emulator.

Map<String, dynamic> _photo(
  String id,
  String category, {
  String state = 'SUBMITTED',
  int? version = 1,
  String? replaces,
  String? supersededBy,
  Map<String, dynamic>? review,
  double lat = 13.04,
  String capturedAt = '2026-11-21T06:30:00.000Z',
  String mediaKey = '',
}) =>
    {
      'id': id,
      'category': category,
      'mediaKey': mediaKey,
      'caption': '',
      'order': 0,
      'state': state,
      'version': version,
      'url': 'http://host/file/$id.jpg',
      'editedUrl': null,
      'capturedAt': capturedAt,
      'uploadedAt': '2026-11-21T06:31:00.000Z',
      'uploadedBy': 'Ravi',
      'capturedByRole': 'RECCE_EXECUTIVE',
      'source': 'LIVE_CAMERA',
      'device': 'Android / Adinn Recce 1.0',
      'gpsVerified': true,
      'lat': lat,
      'lng': 80.23,
      'gpsAccuracy': 8.0,
      'replaces': replaces,
      'supersededBy': supersededBy,
      'review': ?review,
    };

Map<String, dynamic> _board(String key, double w, double h, {int qty = 1, String name = 'GSB'}) => {
      'key': key,
      'name': name,
      'quantity': qty,
      'width': w,
      'height': h,
      'unit': 'FT',
      'notes': '',
      'sided': 'SINGLE',
      'condition': 'PROPOSED',
      'position': '',
      'installationNotes': '',
    };

Map<String, dynamic> _installation({String crane = 'NO'}) => {
      'ladderRequired': 'YES',
      'scaffoldingRequired': 'NO',
      'craneRequired': crane,
      'hydraRequired': 'NO',
      'manualInstallationPossible': 'YES',
      'electricalAccess': 'AVAILABLE',
      'installationHeightFt': 12,
      'accessRestrictions': <String>[],
      'obstruction': '',
      'roadsideConstraints': '',
      'safetyNotes': '',
      'additionalEquipment': <String>[],
      'notes': '',
    };

Map<String, dynamic> _decision(String stage, String decision, {String? reviewer, String? at, String comment = ''}) => {
      'stage': stage,
      'stageLabel': stage == 'OPS' ? 'Recce Operations' : 'Client Servicing',
      'decision': decision,
      'reviewer': reviewer,
      'decidedAt': at,
      'comment': comment,
    };

/// `GET /recce/shops/:siteId/versions`: V1 got rework from Recce Operations, V2 is waiting for review.
List<Map<String, dynamic>> _versionsJson() => [
      {
        'version': 1,
        'current': false,
        'submittedAt': '2026-11-22T05:00:00.000Z',
        'submittedBy': 'Ravi',
        'notes': 'All angles done',
        'mediaItems': [_board('b1', 6, 4)],
        'installation': _installation(),
        'installationRecorded': true,
        'photos': [_photo('p1', 'SHOP_FRONT', supersededBy: 'p1b', state: 'SUPERSEDED'), _photo('p2', 'SIDE_VIEW')],
        'addedIds': ['p1', 'p2'],
        'removedIds': <String>[],
        'stages': ['OPS', 'CS'],
        'decisions': [
          _decision('CS', 'VOID'),
          _decision('OPS', 'REWORK', reviewer: 'Asha', at: '2026-11-22T08:00:00.000Z', comment: 'Board not clear, retake front'),
        ],
        'reworks': [
          {
            'id': 'rw1',
            'versionNo': 1,
            'stage': 'OPS',
            'stageLabel': 'Recce Operations',
            'kind': 'REWORK',
            'status': 'RESOLVED',
            'instructions': 'Board not clear, retake front',
            'requestedBy': 'Asha',
            'requestedAt': '2026-11-22T08:00:00.000Z',
            'resolvedAt': '2026-11-23T05:00:00.000Z',
            'items': [
              {'id': 'it1', 'type': 'REPLACE_PHOTO', 'category': 'SHOP_FRONT', 'categoryLabel': 'Full Shop Front View', 'mediaKey': '', 'photo': 'p1', 'note': 'Too dark', 'resolved': true, 'resolvedInVersion': 2},
              {'id': 'it2', 'type': 'FIX_MEASUREMENT', 'category': null, 'categoryLabel': null, 'mediaKey': 'b1', 'photo': null, 'note': 'Width is 8 ft', 'resolved': true, 'resolvedInVersion': 2},
            ],
          },
        ],
      },
      {
        'version': 2,
        'current': true,
        'submittedAt': '2026-11-23T05:00:00.000Z',
        'submittedBy': 'Ravi',
        'notes': '',
        'mediaItems': [_board('b1', 8, 4)],
        'installation': _installation(crane: 'YES'),
        'installationRecorded': true,
        'photos': [_photo('p1b', 'SHOP_FRONT', version: 2, replaces: 'p1'), _photo('p2', 'SIDE_VIEW')],
        'addedIds': ['p1b'],
        'removedIds': ['p1'],
        'stages': ['OPS', 'CS'],
        'decisions': [_decision('CS', 'PENDING'), _decision('OPS', 'PENDING')],
        'reworks': <Map<String, dynamic>>[],
      },
    ];

/// `GET /recce/shops/:siteId/versions/compare?from=1&to=2`: 6 x 4 became 8 x 4, the front photo was replaced.
Map<String, dynamic> _compareJson() => {
      'from': {
        'version': 1,
        'submittedAt': '2026-11-22T05:00:00.000Z',
        'submittedBy': 'Ravi',
        'reviewerComments': [_decision('OPS', 'REWORK', reviewer: 'Asha', at: '2026-11-22T08:00:00.000Z', comment: 'Board not clear')],
      },
      'to': {'version': 2, 'submittedAt': '2026-11-23T05:00:00.000Z', 'submittedBy': 'Ravi', 'reviewerComments': <Map<String, dynamic>>[]},
      'photos': {
        'added': [_photo('p9', 'ACCESS_PATH', version: 2)],
        'replaced': [
          {'from': _photo('p1', 'SHOP_FRONT', state: 'SUPERSEDED', lat: 13.0411, capturedAt: '2026-11-21T06:30:00.000Z'), 'to': _photo('p1b', 'SHOP_FRONT', version: 2, replaces: 'p1', lat: 13.0422, capturedAt: '2026-11-23T04:00:00.000Z')},
        ],
        'unchanged': [_photo('p2', 'SIDE_VIEW')],
        'removed': [_photo('p5', 'LONG_SHOT', state: 'REMOVED')],
      },
      'mediaItems': {
        'added': [_board('b2', 4, 3, name: 'Acrylic')],
        'removed': <Map<String, dynamic>>[],
        'changed': [
          {
            'key': 'b1',
            'name': 'GSB',
            'fields': [
              {'field': 'width', 'from': 6, 'to': 8},
            ],
          },
        ],
      },
      'installation': [
        {'field': 'craneRequired', 'from': 'NO', 'to': 'YES'},
      ],
      'notes': {'from': 'All angles done', 'to': ''},
      'changed': true,
    };

/// `GET /recce/shops/:siteId/photos/p1b/history`: p1 was uploaded, flagged, replaced by p1b.
Map<String, dynamic> _historyJson() => {
      'photoId': 'p1b',
      'revisions': [
        {'revision': 1, 'current': false, ..._photo('p1', 'SHOP_FRONT', state: 'SUPERSEDED', supersededBy: 'p1b')},
        {'revision': 2, 'current': true, ..._photo('p1b', 'SHOP_FRONT', version: 2, replaces: 'p1')},
      ],
      'events': [
        {'id': 'e2', 'type': 'PHOTO_REPLACED', 'label': 'Photo replaced', 'actor': 'Ravi', 'role': 'RECCE_EXECUTIVE', 'at': '2026-11-23T04:05:00.000Z', 'reason': '', 'photoId': 'p1b', 'version': null},
        {'id': 'e1', 'type': 'PHOTO_CAPTURED', 'label': 'Photo uploaded', 'actor': 'Ravi', 'role': 'RECCE_EXECUTIVE', 'at': '2026-11-21T06:31:00.000Z', 'reason': '', 'photoId': 'p1', 'version': null},
      ],
      'reworks': [
        {
          'reworkId': 'rw1',
          'itemId': 'it1',
          'photoId': 'p1',
          'stage': 'OPS',
          'stageLabel': 'Recce Operations',
          'requestedBy': 'Asha',
          'requestedAt': '2026-11-22T08:00:00.000Z',
          'note': 'Too dark',
          'instructions': 'Board not clear, retake front',
          'resolved': true,
          'resolvedInVersion': 2,
        },
      ],
    };

/// `GET /recce/shops/:siteId/activity`: newest first, exactly as `timeline()` returns it.
List<Map<String, dynamic>> _activityJson() => [
      {'id': 'a6', 'type': 'FINAL_APPROVAL', 'label': 'Final approval', 'actor': 'Meena', 'role': 'CLIENT_SERVICING', 'at': '2026-11-24T09:00:01.000Z', 'reason': '', 'mediaKey': null, 'photo': null, 'version': 2, 'changes': <Map<String, dynamic>>[]},
      {
        'id': 'a5',
        'type': 'REVIEW_APPROVED',
        'label': 'Review approved',
        'actor': 'Meena',
        'role': 'CLIENT_SERVICING',
        'at': '2026-11-24T09:00:00.000Z',
        'reason': 'Looks good',
        'mediaKey': null,
        'photo': null,
        'version': 2,
        'changes': [
          {'field': 'status', 'oldValue': 'UNDER_REVIEW', 'newValue': 'APPROVED'},
          {'field': 'review.CS', 'oldValue': 'PENDING', 'newValue': 'APPROVED'},
        ],
      },
      {
        'id': 'a4',
        'type': 'REWORK_SUBMITTED',
        'label': 'Rework submitted',
        'actor': 'Ravi',
        'role': 'RECCE_EXECUTIVE',
        'at': '2026-11-23T05:00:00.000Z',
        'reason': '',
        'mediaKey': null,
        'photo': null,
        'version': 2,
        'changes': [
          {'field': 'photos', 'oldValue': 6, 'newValue': 6},
        ],
      },
      {'id': 'a7', 'type': 'PHOTO_REPLACED', 'label': 'Photo replaced', 'actor': 'Ravi', 'role': 'RECCE_EXECUTIVE', 'at': '2026-11-23T04:05:00.000Z', 'reason': '', 'mediaKey': null, 'photo': 'p1b', 'version': null, 'changes': <Map<String, dynamic>>[]},
      {
        'id': 'a3',
        'type': 'REWORK_REQUESTED',
        'label': 'Rework requested',
        'actor': 'Asha',
        'role': 'OPERATIONS',
        'at': '2026-11-22T08:00:00.000Z',
        'reason': 'Board not clear, retake front',
        'mediaKey': null,
        'photo': null,
        'version': 1,
        'changes': [
          {'field': 'status', 'oldValue': 'UNDER_REVIEW', 'newValue': 'REWORK_REQUIRED'},
          {'field': 'review.OPS', 'oldValue': 'PENDING', 'newValue': 'REWORK'},
        ],
      },
      {'id': 'a2', 'type': 'SUBMISSION_CREATED', 'label': 'Submission created', 'actor': 'Ravi', 'role': 'RECCE_EXECUTIVE', 'at': '2026-11-22T05:00:00.000Z', 'reason': '', 'mediaKey': null, 'photo': null, 'version': 1, 'changes': <Map<String, dynamic>>[]},
    ];

Map<String, dynamic> _detailJson({String status = 'REWORK_REQUIRED', bool editable = true, List<Map<String, dynamic>>? photos, List<Map<String, dynamic>>? reworks}) => {
      'siteId': 's1',
      'siteCode': 'SM-0234',
      'shopName': 'Sri Murugan Super Market',
      'address': 'T. Nagar',
      'project': {'id': 'p1', 'code': 'ADN-2451', 'name': 'South Zone', 'client': 'ABC Retail', 'closed': false},
      'status': status,
      'editable': editable,
      'version': 1,
      'mediaItems': [_board('b1', 6, 4)],
      'installation': _installation(),
      'notes': '',
      'photos': photos ??
          [
            _photo('p1', 'SHOP_FRONT', review: {
              'status': 'REWORK_REQUIRED',
              'openRework': {
                'reworkId': 'rw1',
                'itemId': 'it1',
                'note': 'Too dark',
                'stage': 'OPS',
                'stageLabel': 'Recce Operations',
                'instructions': 'Board not clear, retake front',
                'requestedBy': 'Asha',
                'requestedAt': '2026-11-22T08:00:00.000Z',
              },
            }),
            _photo('p2', 'SIDE_VIEW', review: {'status': 'PENDING', 'openRework': null}),
            _photo('p3', 'LONG_SHOT', review: {'status': 'APPROVED', 'openRework': null}),
          ],
      'progress': {'percent': 80},
      'versions': [
        {'version': 1, 'submittedAt': '2026-11-22T05:00:00.000Z', 'photoCount': 6},
      ],
      'reviews': [
        {'versionNo': 1, 'stage': 'OPS', 'stageLabel': 'Recce Operations', 'decision': 'REWORK', 'comment': 'Board not clear, retake front', 'reviewer': 'Asha', 'decidedAt': '2026-11-22T08:00:00.000Z'},
        {'versionNo': 1, 'stage': 'CS', 'stageLabel': 'Client Servicing', 'decision': 'VOID', 'comment': '', 'reviewer': null, 'decidedAt': null},
      ],
      'reworks': reworks ??
          [
            {
              'id': 'rw1',
              'versionNo': 1,
              'stage': 'OPS',
              'stageLabel': 'Recce Operations',
              'kind': 'REWORK',
              'status': 'OPEN',
              'instructions': 'Board not clear, retake front',
              'requestedBy': 'Asha',
              'requestedAt': '2026-11-22T08:00:00.000Z',
              'items': [
                {'id': 'it1', 'type': 'REPLACE_PHOTO', 'category': 'SHOP_FRONT', 'categoryLabel': 'Full Shop Front View', 'mediaKey': '', 'photo': 'p1', 'note': 'Too dark', 'resolved': false},
                {'id': 'it2', 'type': 'FIX_MEASUREMENT', 'category': null, 'categoryLabel': null, 'mediaKey': 'b1', 'photo': null, 'note': 'Width is 8 ft', 'resolved': false},
              ],
            },
          ],
    };

Installation _answered() => Installation(ladderRequired: triYes, scaffoldingRequired: triNo, craneRequired: triNo, hydraRequired: triNo, manualInstallationPossible: triYes);

List<ShopPhoto> _sixLive({List<Map<String, dynamic>> extra = const []}) => [
      for (final c in requiredPhotoCategories) ShopPhoto.fromJson(_photo('ph-${c.key}', c.key)),
      for (final e in extra) ShopPhoto.fromJson(e),
    ];

void main() {
  group('versions parsing', () {
    final versions = [for (final j in _versionsJson()) RecceVersion.fromJson(j)];

    test('reads submitter, time, notes, photos, boards, installation and stage decisions', () {
      expect(versions.map((v) => v.version), [1, 2]);
      final v1 = versions.first;
      expect(v1.submittedBy, 'Ravi');
      expect(v1.submittedAt!.toUtc(), DateTime.utc(2026, 11, 22, 5));
      expect(v1.notes, 'All angles done');
      expect(v1.photos, hasLength(2));
      expect(v1.photos.first.supersededBy, 'p1b');
      expect(v1.mediaItems.single.width, 6);
      expect(v1.installationRecorded, isTrue);
      expect(v1.installation.craneRequired, triNo);
      expect(versions.last.installation.craneRequired, triYes);
      expect(versions.last.current, isTrue);
    });

    test('decisions come in review order with comment, reviewer and time', () {
      final d = versions.first.orderedDecisions;
      expect(d.map((x) => x.stage), ['OPS', 'CS']); // config order, not the server's alphabetical order
      expect(d.first.decision, 'REWORK');
      expect(d.first.reviewer, 'Asha');
      expect(d.first.comment, 'Board not clear, retake front');
      expect(d.first.decidedAt!.toUtc(), DateTime.utc(2026, 11, 22, 8));
      expect(d.last.isVoid, isTrue);
      expect(decisionLabel('REWORK'), 'Rework requested');
      expect(decisionLabel('PENDING'), 'Pending');
      expect(decisionLabel('VOID'), 'Not needed');
    });

    test('row text: "V1 - GSB 6 x 4 ft - Rework Required" and "V2 - GSB 8 x 4 ft - Under Review"', () {
      expect(versions[0].rowTitle, 'V1 - GSB 6 x 4 ft - Rework Required');
      expect(versions[1].rowTitle, 'V2 - GSB 8 x 4 ft - Under Review');
    });

    test('status of a version follows the server rule', () {
      List<StageDecision> ds(String ops, String cs) => [StageDecision(stage: 'OPS', stageLabel: 'Recce Operations', decision: ops), StageDecision(stage: 'CS', stageLabel: 'Client Servicing', decision: cs)];
      expect(versionStatusOf(['OPS', 'CS'], ds('APPROVED', 'APPROVED')), 'APPROVED');
      expect(versionStatusOf(['OPS', 'CS'], ds('APPROVED', 'PENDING')), 'UNDER_REVIEW');
      expect(versionStatusOf(['OPS', 'CS'], ds('REJECTED', 'VOID')), 'REJECTED');
      expect(versionStatusOf(['OPS', 'CS'], ds('APPROVED', 'REWORK')), 'REWORK_REQUIRED');
      expect(versionStatusOf(const [], const []), 'UNDER_REVIEW');
    });

    test('board and installation summaries', () {
      expect(versions[0].boardSummary, 'GSB 6 x 4 ft');
      expect(boardSummaryText(BoardItem(key: 'b2', name: 'ACP', quantity: 3, width: 4.5, height: 3, unit: 'FT')), 'ACP 4.5 x 3 ft x3');
      expect(versions[0].installationSummary, 'Needs Ladder');
      expect(versions[1].installationSummary, 'Needs Ladder, Crane');
      expect(installationSummaryText(Installation(), recorded: false), 'Installation not recorded');
      expect(installationSummaryText(Installation()), 'Installation not assessed');
    });

    test('a missing field never breaks parsing', () {
      final v = RecceVersion.fromJson({'version': 3});
      expect(v.rowTitle, 'V3 - No boards - Under Review');
      expect(v.photos, isEmpty);
    });

    test('photos of older versions that are no longer live are "previous versions"', () {
      final prev = previousPhotosOf(versions, ['p1b', 'p2']);
      expect(prev.map((p) => p.photo.id), ['p1']);
      expect(prev.single.versionText, 'V1');
      expect(previousPhotosOf(versions, ['p1', 'p1b', 'p2']), isEmpty);
    });
  });

  group('compare parsing', () {
    final c = VersionCompare.fromJson(_compareJson());

    test('6 x 4 -> 8 x 4 appears as a changed width field', () {
      expect(c.boardsChanged, hasLength(1));
      final b = c.boardsChanged.single;
      expect(b.key, 'b1');
      expect(b.fields.single.field, 'width');
      expect(b.fields.single.from, 6);
      expect(b.fields.single.to, 8);
      expect(b.fields.single.text, 'Width: 6 -> 8');
      expect(b.sizeChanged, isTrue);
    });

    test('size headline reads "6 x 4 ft -> 8 x 4 ft" using the boards of both versions', () {
      final versions = [for (final j in _versionsJson()) RecceVersion.fromJson(j)];
      final b = c.boardsChanged.single;
      expect(b.sizeHeadline(before: versions[0].board('b1'), after: versions[1].board('b1')), '6 x 4 ft -> 8 x 4 ft');
      expect(b.sizeHeadline(), 'Width 6 -> 8'); // no boards at hand: still readable
    });

    test('photos: added, replaced (old and new with GPS and time), unchanged, removed', () {
      expect(c.added.single.category, 'ACCESS_PATH');
      expect(c.unchanged.single.id, 'p2');
      expect(c.removed.single.id, 'p5');
      final r = c.replaced.single;
      expect(r.from.id, 'p1');
      expect(r.to.id, 'p1b');
      expect(r.to.replaces, 'p1');
      expect(r.from.lat, 13.0411);
      expect(r.to.lat, 13.0422);
      expect(r.from.capturedAt!.toUtc(), DateTime.utc(2026, 11, 21, 6, 30));
      expect(r.to.capturedAt!.toUtc(), DateTime.utc(2026, 11, 23, 4));
    });

    test('boards added, installation changes, notes change, sides and reviewer comments', () {
      expect(c.boardsAdded.single.name, 'Acrylic');
      expect(c.installation.single.text, 'Crane: No -> Yes');
      expect(c.notesChanged, isTrue);
      expect(c.notesFrom, 'All angles done');
      expect(c.notesTo, '');
      expect(c.from.version, 1);
      expect(c.to.version, 2);
      expect(c.from.submittedBy, 'Ravi');
      expect(c.to.submittedAt!.toUtc(), DateTime.utc(2026, 11, 23, 5));
      expect(c.from.reviewerComments.single.comment, 'Board not clear');
      expect(c.to.reviewerComments, isEmpty);
      expect(c.changed, isTrue);
    });

    test('an unchanged pair parses to "nothing changed"', () {
      final n = VersionCompare.fromJson({
        'from': {'version': 1},
        'to': {'version': 2},
        'photos': {'added': [], 'replaced': [], 'unchanged': [], 'removed': []},
        'mediaItems': {'added': [], 'removed': [], 'changed': []},
        'installation': [],
        'notes': null,
        'changed': false,
      });
      expect(n.changed, isFalse);
      expect(n.notesChanged, isFalse);
      expect(n.boardsChanged, isEmpty);
    });

    test('field values read as words', () {
      expect(fieldValueText('NOT_ASSESSED'), 'Not assessed');
      expect(fieldValueText(null), 'not set');
      expect(fieldValueText(6.0), '6');
      expect(fieldValueText(4.5), '4.5');
      expect(fieldValueText(['Ladder', 'Rope']), 'Ladder, Rope');
      expect(fieldValueText('SINGLE'), 'Single side');
    });
  });

  group('photo history parsing', () {
    final h = PhotoHistory.fromJson(_historyJson());

    test('revisions, events and rework requests', () {
      expect(h.photoId, 'p1b');
      expect(h.revisions.map((r) => r.revision), [1, 2]);
      expect(h.revisions.last.current, isTrue);
      expect(h.revisions.last.photo.replaces, 'p1');
      expect(h.revisions.first.photo.supersededBy, 'p1b');
      expect(h.events.map((e) => e.type), ['PHOTO_REPLACED', 'PHOTO_CAPTURED']);
      expect(h.events.first.version, isNull);
      expect(h.reworks.single.note, 'Too dark');
      expect(h.reworks.single.stageLabel, 'Recce Operations');
      expect(h.reworks.single.resolved, isTrue);
      expect(h.reworks.single.resolvedInVersion, 2);
    });

    test('time-ordered list: upload, rework request, replacement (no duplicate for revisions that have an upload event)', () {
      final t = h.timeline;
      expect(t.map((l) => l.title), ['Photo uploaded', 'Recce Operations requested rework (done in V2)', 'Photo replaced']);
      expect(t[1].kind, 'rework');
      expect(t[1].detail, contains('Too dark'));
      expect(t[1].detail, contains('Board not clear'));
      expect(t[0].who, 'Ravi (Recce Executive)');
      for (var i = 1; i < t.length; i++) {
        expect(t[i].at!.isAfter(t[i - 1].at!), isTrue);
      }
    });

    test('a revision without an upload event still gets a line', () {
      final j = _historyJson()..['events'] = <Map<String, dynamic>>[];
      final t = PhotoHistory.fromJson(j).timeline;
      expect(t.where((l) => l.kind == 'upload'), hasLength(2));
      expect(t.any((l) => l.title.contains('revision 2')), isTrue);
    });
  });

  group('activity parsing', () {
    final events = [for (final j in _activityJson()) ActivityEvent.fromJson(j)];
    ActivityEvent ev(String id) => events.firstWhere((e) => e.id == id);

    test('reads actor, role, version, comment and changes', () {
      final e = ev('a3');
      expect(e.actor, 'Asha');
      expect(e.role, 'OPERATIONS');
      expect(e.version, 1);
      expect(e.reason, 'Board not clear, retake front');
      expect(e.stage, 'OPS');
      expect(e.who, 'Asha (Recce Operations)');
      expect(e.at!.toUtc(), DateTime.utc(2026, 11, 22, 8));
      expect(e.changes, hasLength(2));
    });

    test('titles tell the approval story', () {
      expect(ev('a2').title, 'Submitted V1');
      expect(ev('a3').title, 'Recce Operations requested rework');
      expect(ev('a4').title, 'Resubmitted V2');
      expect(ev('a5').title, 'Client Servicing approved');
      expect(ev('a6').title, 'Shop approved');
      expect(ev('a7').title, 'Photo replaced');
      expect(ev('a7').photo, 'p1b');
    });

    test('oldest first is the default order, newest first reverses it; approval steps hide photo events', () {
      final story = orderActivity(events, newestFirst: false).where((e) => e.isApproval).map((e) => e.title).toList();
      expect(story, ['Submitted V1', 'Recce Operations requested rework', 'Resubmitted V2', 'Client Servicing approved', 'Shop approved']);
      expect(orderActivity(events, newestFirst: true).first.id, 'a6');
      expect(ev('a7').isApproval, isFalse);
    });

    test('a rework event finds its rework request and its items', () {
      final reworks = [for (final r in (_detailJson()['reworks'] as List)) ReworkEntry.fromJson(r as Map<String, dynamic>)];
      final r = reworkForEvent(ev('a3'), reworks);
      expect(r, isNotNull);
      expect(r!.items.map((i) => i.type), ['REPLACE_PHOTO', 'FIX_MEASUREMENT']);
      expect(reworkForEvent(ev('a2'), reworks), isNull);
      expect(reworkItemText(r.items.last), 'Correct the size of b1: Width is 8 ft');
    });

    test('a null actor or photo does not break parsing', () {
      final e = ActivityEvent.fromJson({'id': 'x', 'type': 'DRAFT_SAVED', 'label': 'Draft saved', 'actor': null, 'at': null, 'photo': null, 'changes': null});
      expect(e.actor, 'Unknown');
      expect(e.photo, isNull);
      expect(e.changes, isEmpty);
    });
  });

  group('rework flag derivation', () {
    final d = ShopDetail.fromJson(_detailJson());

    test('review.status REWORK_REQUIRED flags the photo, the others are not flagged', () {
      expect(d.photos.firstWhere((p) => p.id == 'p1').needsRework, isTrue);
      expect(d.photos.firstWhere((p) => p.id == 'p2').needsRework, isFalse);
      expect(d.photos.firstWhere((p) => p.id == 'p3').isApproved, isTrue);
    });

    test('the open rework carries reviewer, stage label, time, item note and instructions', () {
      final n = d.reworkNoteFor(d.photos.first)!;
      expect(n.note, 'Too dark');
      expect(n.instructions, 'Board not clear, retake front');
      expect(n.reason, 'Too dark');
      expect(n.by, 'Asha');
      expect(n.role, 'Recce Operations');
      expect(n.reworkId, 'rw1');
      expect(n.itemId, 'it1');
      expect(n.at!.toUtc(), DateTime.utc(2026, 11, 22, 8));
    });

    test('a board with an open FIX_MEASUREMENT item gets the note; others do not', () {
      final n = d.measurementReworkFor('b1')!;
      expect(n.note, 'Width is 8 ft');
      expect(n.role, 'Recce Operations');
      expect(d.measurementReworkFor('b2'), isNull);
      expect(d.measurementReworkFor(''), isNull);
    });

    test('a resolved FIX_MEASUREMENT item is no longer shown', () {
      final j = _detailJson(reworks: [
        {
          'id': 'rw1',
          'versionNo': 1,
          'stage': 'OPS',
          'stageLabel': 'Recce Operations',
          'kind': 'REWORK',
          'status': 'RESOLVED',
          'instructions': 'x',
          'items': [
            {'id': 'it2', 'type': 'FIX_MEASUREMENT', 'mediaKey': 'b1', 'note': 'Width is 8 ft', 'resolved': true},
          ],
        },
      ]);
      expect(ShopDetail.fromJson(j).measurementReworkFor('b1'), isNull);
    });

    test('photo filters: All, Pending, Approved, Rework Required, Previous Versions', () {
      List<String> ids(PhotoFilter f) => [for (final p in d.photos) if (f.matches(p)) p.id];
      expect(ids(PhotoFilter.all), ['p1', 'p2', 'p3']);
      expect(ids(PhotoFilter.pending), ['p2']);
      expect(ids(PhotoFilter.approved), ['p3']);
      expect(ids(PhotoFilter.rework), ['p1']);
      expect(ids(PhotoFilter.previous), isEmpty); // comes from the versions list, not from live photos
      expect(PhotoFilter.values.map((f) => f.label), ['All', 'Pending', 'Approved', 'Rework Required', 'Previous Versions']);
    });

    test('status header: the server status and the decisions of the current version', () {
      final s = StageDecision.forVersion(d.reviews, d.version);
      expect(d.status, 'REWORK_REQUIRED');
      expect(s.map((x) => x.decision), ['REWORK', 'VOID']);
      expect(StageDecision.forVersion(d.reviews, 2), isEmpty);
    });
  });

  group('replace one photo', () {
    test('the upload meta contains replaces, keeps the category and board, and nothing else is re-requested', () {
      final old = ShopPhoto.fromJson(_photo('p1', 'SHOP_FRONT', mediaKey: 'b1'));
      final u = UploadItem.replacement(
        old,
        siteId: 's1',
        path: '/tmp/new.jpg',
        id: 'c1234567890',
        capturedAt: DateTime.utc(2026, 11, 23, 4),
        lat: 13.05,
        lng: 80.24,
        accuracy: 6,
        width: 1200,
        height: 900,
        device: 'Android / Adinn Recce 1.0',
      );
      final m = u.meta();
      expect(m['replaces'], 'p1');
      expect(m['category'], 'SHOP_FRONT');
      expect(m['mediaKey'], 'b1');
      expect(m['clientId'], 'c1234567890');
      expect(m['lat'], 13.05);
      expect(m['source'], 'LIVE_CAMERA');
      expect(jsonDecode(jsonEncode([m])).first['replaces'], 'p1'); // the multipart `meta` array
      expect(UploadItem.fromJson(jsonDecode(jsonEncode(u.toJson())) as Map<String, dynamic>).replaces, 'p1'); // survives a restart
    });

    test('a normal upload has no replaces', () {
      final u = UploadItem(id: 'c1234567890', siteId: 's1', path: '/x.jpg', category: 'SIDE_VIEW');
      expect(u.meta().containsKey('replaces'), isFalse);
    });

    test('photo parsing keeps the replaces link of a draft replacement', () {
      final p = ShopPhoto.fromJson(_photo('p1b', 'SHOP_FRONT', state: 'DRAFT', version: null, replaces: 'p1'));
      expect(p.isDraft, isTrue);
      expect(p.replaces, 'p1');
      expect(p.version, isNull);
    });
  });

  group('submit validator in rework', () {
    final reworks = [for (final r in (_detailJson()['reworks'] as List)) ReworkEntry.fromJson(r as Map<String, dynamic>)];
    final board = [BoardItem(key: 'b1', width: 8, height: 4)];

    test('already stored photos (approved, pending or flagged) count as present: nothing unrelated is asked again', () {
      final live = _sixLive(); // all six exist from V1, one of them is the flagged one
      final p = validateForSubmit(photos: live, boards: board, installation: _answered(), reworks: const []);
      expect(p, isEmpty);
    });

    test('a flagged photo with no replacement blocks submit with a clear line', () {
      final p = validateForSubmit(photos: _sixLive(), boards: board, installation: _answered(), reworks: reworks);
      expect(p, ['Replace the Full Shop Front View the reviewer marked']);
    });

    test('an uploaded draft that replaces the flagged photo answers the request', () {
      final live = _sixLive(extra: [_photo('p1b', 'SHOP_FRONT', state: 'DRAFT', version: null, replaces: 'ph-SHOP_FRONT')]);
      final rw = [
        ReworkEntry.fromJson({
          'id': 'rw1',
          'versionNo': 1,
          'stageLabel': 'Recce Operations',
          'kind': 'REWORK',
          'status': 'OPEN',
          'instructions': 'x',
          'items': [
            {'id': 'it1', 'type': 'REPLACE_PHOTO', 'category': 'SHOP_FRONT', 'categoryLabel': 'Front View', 'photo': 'ph-SHOP_FRONT', 'resolved': false},
            {'id': 'it2', 'type': 'FIX_MEASUREMENT', 'mediaKey': 'b1', 'note': 'Width is 8 ft', 'resolved': false},
          ],
        }),
      ];
      expect(validateForSubmit(photos: live, boards: board, installation: _answered(), reworks: rw), isEmpty);
    });

    test('a replacement still uploading is reported once, as "still uploading"', () {
      final p = validateForSubmit(
        photos: _sixLive(),
        boards: board,
        installation: _answered(),
        reworks: reworks,
        pendingUploads: 1,
        pendingReplaces: {'p1'},
      );
      expect(p, ['1 photo is still uploading']);
    });

    test('an additional-photo request needs a new photo of that category; measurement fixes need no photo', () {
      final rw = [
        ReworkEntry.fromJson({
          'id': 'rw2',
          'versionNo': 1,
          'kind': 'ADDITIONAL',
          'status': 'OPEN',
          'instructions': 'more',
          'items': [
            {'type': 'ADDITIONAL_PHOTO', 'category': 'NAME_BOARD', 'categoryLabel': 'Shop Name Board', 'resolved': false},
          ],
        }),
      ];
      expect(validateForSubmit(photos: _sixLive(), boards: board, installation: _answered(), reworks: rw), ['Add the Shop Name Board photo the reviewer asked for']);
      final withNew = _sixLive(extra: [_photo('n1', 'NAME_BOARD', state: 'DRAFT', version: null)]);
      expect(validateForSubmit(photos: withNew, boards: board, installation: _answered(), reworks: rw), isEmpty);
    });

    test('the idempotency key of the next version is stable per version', () {
      expect(submitKey('s1', 1), 'submit-s1-2');
      expect(submitKey('s1', 1), submitKey('s1', 1));
      expect(submitKey('s1', 2), 'submit-s1-3');
    });

    test('category names of non-live-flow photos read as words', () {
      expect(photoCategoryLabel('NAME_BOARD'), 'Name board');
      expect(photoCategoryLabel('SHOP_FRONT'), 'Front View');
    });
  });

  group('widgets', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

    testWidgets('version row shows the title and its stage decisions', (tester) async {
      final v = RecceVersion.fromJson(_versionsJson().first);
      await tester.pumpWidget(host(VersionTile(version: v, initiallyExpanded: true)));
      expect(find.text('V1 - GSB 6 x 4 ft - Rework Required'), findsOneWidget);
      expect(find.text('Recce Operations'), findsOneWidget);
      expect(find.text('Rework requested'), findsOneWidget);
      expect(find.text('Board not clear, retake front'), findsWidgets);
      expect(find.text('Client Servicing'), findsOneWidget);
    });

    testWidgets('status header shows the server status and both stage decisions', (tester) async {
      await tester.pumpWidget(host(ReviewStatusHeader(detail: ShopDetail.fromJson(_detailJson()))));
      expect(find.text('Rework required'), findsOneWidget); // StatusPill of REWORK_REQUIRED
      expect(find.text('Recce Operations'), findsOneWidget);
      expect(find.text('Client Servicing'), findsOneWidget);
      expect(find.text('Version 1'), findsOneWidget);
    });

    testWidgets('rework box shows the note, instructions, reviewer, stage and time', (tester) async {
      final d = ShopDetail.fromJson(_detailJson());
      await tester.pumpWidget(host(ReworkBox(note: d.reworkNoteFor(d.photos.first))));
      expect(find.text('Too dark'), findsOneWidget);
      expect(find.textContaining('Board not clear, retake front'), findsOneWidget);
      expect(find.textContaining('Asha (Recce Operations)'), findsOneWidget);
    });
  });
}
