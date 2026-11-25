import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/features/live_recce/data/recce_api.dart';
import 'package:signage_recce/features/live_recce/data/recce_controllers.dart';
import 'package:signage_recce/features/live_recce/data/recce_models.dart';
import 'package:signage_recce/features/live_recce/data/rework_alert.dart';
import 'package:signage_recce/features/live_recce/data/upload_queue.dart';
import 'package:signage_recce/features/live_recce/presentation/boards_tab.dart';
import 'package:signage_recce/features/live_recce/presentation/installation_tab.dart';
import 'package:signage_recce/features/live_recce/presentation/photos_tab.dart';
import 'package:signage_recce/features/live_recce/presentation/review_tab.dart';
import 'package:signage_recce/features/live_recce/presentation/rework_alert.dart';

/// The reviewer's CHECKLIST items (2026-11-25): each one sent back (Rework or Rejected) has its own remark and belongs to a section
/// (SHOP | PHOTOS | BOARDS | INSTALLATION). The phone shows it in that section with its status and remark, counts it in the alert, and keeps the
/// board requests (size, quantity, media type) on the Boards tab with the checklist label as their title. Fake data only.

Map<String, dynamic> _item(String id, String type, {String label = '', String? section, String note = '', bool rejected = false, bool resolved = false, String mediaKey = ''}) => {
      'id': id,
      'type': type,
      'category': null,
      'categoryLabel': null,
      'mediaKey': mediaKey,
      'photo': null,
      'note': note,
      'rejected': rejected,
      'section': section,
      'label': label,
      'resolved': resolved,
    };

/// One rework request that carries a checklist item for every section.
List<Map<String, dynamic>> _items() => [
      _item('c-front', 'OTHER', label: 'Shop front visible', section: 'PHOTOS', note: 'Front is hidden behind a tree'),
      _item('c-shop', 'OTHER', label: 'Correct shop', section: 'SHOP', note: 'This is the next door shop', rejected: true),
      _item('c-install', 'OTHER', label: 'Installation details complete', section: 'INSTALLATION', note: 'Add the crane height'),
      _item('c-boards', 'OTHER', label: 'Board count matches', section: 'BOARDS', note: 'Count the boards again'),
      _item('c-size', 'FIX_MEASUREMENT', label: 'Measurements available', section: 'BOARDS', note: 'Width is missing'),
    ];

Map<String, dynamic> _detail({List<Map<String, dynamic>>? items, bool editable = false}) => {
      'siteId': 's1',
      'siteCode': 'SM-1',
      'shopName': 'Sri Murugan',
      'project': {'id': 'p1', 'code': 'ADN-1', 'name': 'South', 'closed': false},
      'status': 'REWORK_REQUIRED',
      'editable': editable,
      'version': 1,
      'mediaItems': [
        {'key': 'b1', 'name': 'GSB', 'mediaType': 'GSB', 'seq': 1, 'quantity': 1, 'width': 6, 'height': 4, 'unit': 'FT'},
      ],
      'photos': <Map<String, dynamic>>[],
      'progress': {'percent': 50, 'required': 3, 'done': 3, 'missing': []},
      'reworks': [
        {
          'id': 'rw1',
          'versionNo': 1,
          'stage': 'OPS',
          'stageLabel': 'Recce Operations',
          'kind': 'REWORK',
          'status': 'OPEN',
          'instructions': 'Fix these',
          'requestedBy': 'Asha',
          'requestedAt': '2026-11-25T08:00:00.000Z',
          'items': items ?? _items(),
        },
      ],
    };

class _Api extends RecceApi {
  _Api([Map<String, dynamic>? json]) : json = json ?? _detail(), super(Dio());
  Map<String, dynamic> json;
  @override
  Future<ShopDetail> detail(String siteId) async => ShopDetail.fromJson(json);
  @override
  Future<List<RecceVersion>> versions(String siteId) async => const [];
}

Future<({UploadQueue queue, ShopDetailController c})> _rig([Map<String, dynamic>? json]) async {
  final api = _Api(json);
  final queue = UploadQueue(api, autoRetry: false);
  final c = ShopDetailController(api, queue, 's1');
  await c.load();
  return (queue: queue, c: c);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('checklist items parse and read', () {
    test('an item keeps its section and label; one without a section belongs to the shop', () {
      final d = ShopDetail.fromJson(_detail(items: [..._items(), _item('old', 'OTHER', note: 'Something else')]));
      final items = d.reworks.single.items;
      expect(items.first.section, 'PHOTOS');
      expect(items.first.label, 'Shop front visible');
      expect(items.first.isSectionNote, isTrue);
      expect(items.first.sectionKey, 'PHOTOS');
      expect(items.last.section, isNull);
      expect(items.last.label, '');
      expect(items.last.sectionKey, 'SHOP');
      final note = d.reworks.single.noteFor(items.first);
      expect(note.label, 'Shop front visible');
      expect(note.section, 'PHOTOS');
      expect(note.reason, 'Front is hidden behind a tree'); // the item's own remark, not the overall instructions
      expect(note.instructions, 'Fix these');
    });

    test('a checklist item reads as its label in the rework list; a size / quantity / media type request keeps its label as its title', () {
      final d = ShopDetail.fromJson(_detail());
      final items = d.reworks.single.items;
      expect(reworkItemText(items[0]), 'Shop front visible: Front is hidden behind a tree');
      expect(reworkItemText(items[1]), 'Rejected: Correct shop: This is the next door shop');
      expect(reworkItemText(items[4]), 'Measurements available: Width is missing');
      expect(reworkItemText(ReworkItem.fromJson(_item('x', 'OTHER', note: 'Hello'))), 'Other: Hello'); // no label: as before
      expect(reworkItemText(ReworkItem.fromJson(_item('y', 'FIX_QUANTITY', mediaKey: 'b1', note: 'Two boards')), boardLabels: {'b1': 'GSB-01'}), 'Check the quantity of GSB-01: Two boards');
      expect(boardFixTitleFor('FIX_MEASUREMENT', label: 'Measurements available'), 'Measurements available');
      expect(boardFixTitleFor('FIX_MEASUREMENT', rejected: true, label: 'Measurements available'), 'Measurements available: rejected');
      expect(boardFixTitleFor('FIX_MEASUREMENT'), 'Correct the size');
    });
  });

  group('the alert counts checklist items', () {
    test('open checklist items count as checks to fix; a resolved one and a photo section note do not hide the rest', () {
      final d = ShopDetail.fromJson(_detail(items: [..._items(), _item('done', 'OTHER', label: 'Quality', section: 'PHOTOS', note: 'ok now', resolved: true)]));
      final a = ReworkAlert.of(d);
      expect(a.sections.map((s) => s.label), ['Shop front visible', 'Correct shop', 'Installation details complete', 'Board count matches']);
      expect(a.sections.map((s) => s.section), ['PHOTOS', 'SHOP', 'INSTALLATION', 'BOARDS']);
      expect(a.sections[1].rejected, isTrue);
      expect(a.boardFixes, hasLength(1)); // the size request stays a board request
      expect(a.boardFixes.single.title, 'Measurements available');
      expect(a.checks, 4);
      expect(a.open, 5);
      expect(a.isEmpty, isFalse);
      expect(a.allAnswered, isFalse);
      expect(a.summary, '1 board detail to correct, 4 checks to fix');
      expect(FlaggedSection.of(d, section: 'PHOTOS').map((s) => s.label), ['Shop front visible']);
      expect(FlaggedSection.of(d, section: 'INSTALLATION'), hasLength(1));
    });

    test('a shop with only checklist items is not empty and a single one reads "1 check to fix"', () {
      final a = ReworkAlert.of(ShopDetail.fromJson(_detail(items: [_item('c', 'OTHER', label: 'Correct shop', section: 'SHOP', note: 'Wrong shop')])));
      expect(a.isEmpty, isFalse);
      expect(a.photos, isEmpty);
      expect(a.summary, '1 check to fix');
    });

    testWidgets('the sheet lists the checks with their status, section and own remark; with nothing to retake the button says "Fix now"', (t) async {
      t.view.physicalSize = const Size(412, 2800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final a = ReworkAlert.of(ShopDetail.fromJson(_detail(items: [
        _item('c-front', 'OTHER', label: 'Shop front visible', section: 'PHOTOS', note: 'Front is hidden behind a tree'),
        _item('c-shop', 'OTHER', label: 'Correct shop', section: 'SHOP', note: 'This is the next door shop', rejected: true),
      ])));
      bool? result;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: Center(child: FilledButton(onPressed: () async => result = await showReworkAlertSheet(context, a), child: const Text('open')))))));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('2 checks to fix'), findsOneWidget);
      expect(find.text('Other checks to fix'), findsOneWidget);
      expect(find.text('Shop front visible'), findsOneWidget);
      expect(find.text('Front is hidden behind a tree'), findsOneWidget);
      expect(find.text('Rework'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget); // the section chip
      expect(find.text('Correct shop'), findsOneWidget);
      expect(find.text('Reason: This is the next door shop'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Shop'), findsOneWidget);
      expect(find.text('Asked by Asha (Recce Operations)'), findsOneWidget);
      expect(find.text('Fix now'), findsOneWidget);
      expect(find.text('Retake now'), findsNothing);
      await t.tap(find.byKey(const Key('rework-alert-retake')));
      await t.pumpAndSettle();
      expect(result, isTrue);
      expect(t.takeException(), isNull);
    });
  });

  group('every tab shows the items of its own section', () {
    Future<void> show(WidgetTester t, Widget body) async {
      t.view.physicalSize = const Size(412, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: body)));
      await t.pump();
    }

    testWidgets('Photos: the PHOTOS item with its status and remark; nothing of the other sections', (t) async {
      final r = await _rig();
      await show(t, PhotosTab(ctrl: r.c));
      expect(find.byKey(const Key('section-rework-banner')), findsOneWidget);
      expect(find.text('Reviewer asked for changes to the photos'), findsOneWidget);
      expect(find.text('Shop front visible'), findsOneWidget);
      expect(find.text('Front is hidden behind a tree'), findsOneWidget);
      expect(find.text('Rework'), findsOneWidget);
      expect(find.text('Correct shop'), findsNothing);
      expect(find.text('Installation details complete'), findsNothing);
      expect(t.takeException(), isNull);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('Install: the INSTALLATION item with its remark', (t) async {
      final r = await _rig();
      await show(t, InstallationTab(ctrl: r.c));
      expect(find.text('Reviewer asked for changes to the installation'), findsOneWidget);
      expect(find.text('Installation details complete'), findsOneWidget);
      expect(find.text('Add the crane height'), findsOneWidget);
      expect(find.text('Shop front visible'), findsNothing);
      expect(t.takeException(), isNull);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('Boards: the BOARDS item has its own banner, the size request keeps the general banner with the checklist label as its title', (t) async {
      final r = await _rig();
      await show(t, BoardsTab(ctrl: r.c));
      expect(find.text('Reviewer asked for changes to the boards'), findsOneWidget);
      expect(find.text('Board count matches'), findsOneWidget);
      expect(find.text('Count the boards again'), findsOneWidget);
      expect(find.text('Board details to correct'), findsOneWidget); // the existing banner for size / quantity / media type without a board
      expect(find.text('Measurements available'), findsOneWidget);
      expect(find.text('Width is missing'), findsOneWidget);
      expect(find.text('Correct the size'), findsNothing); // the label replaced the generic title
      expect(find.text('Correct shop'), findsNothing);
      expect(t.takeException(), isNull);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('Review: the SHOP item shows a Rejected tag with "Reason:"; the rework card names each item by its label', (t) async {
      final r = await _rig();
      await show(t, ReviewTab(ctrl: r.c));
      expect(find.text('Reviewer asked for changes to the shop'), findsOneWidget);
      expect(find.text('Correct shop'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Reason: This is the next door shop'), findsOneWidget);
      expect(find.text('Shop front visible'), findsNothing); // it belongs to Photos
      // the rework cards list every item as "label: remark"
      expect(find.text('- Shop front visible: Front is hidden behind a tree'), findsWidgets);
      expect(find.text('- Rejected: Correct shop: This is the next door shop'), findsWidgets);
      expect(t.takeException(), isNull);
      r.c.dispose();
      r.queue.dispose();
    });

    testWidgets('a shop with no checklist item shows no section banner on any tab', (t) async {
      final r = await _rig(_detail(items: [_item('q', 'FIX_QUANTITY', mediaKey: 'b1', note: 'Two boards')]));
      for (final tab in <Widget>[PhotosTab(ctrl: r.c), InstallationTab(ctrl: r.c), BoardsTab(ctrl: r.c), ReviewTab(ctrl: r.c)]) {
        await show(t, tab);
        expect(find.byKey(const Key('section-rework-banner')), findsNothing);
      }
      r.c.dispose();
      r.queue.dispose();
    });
  });
}
