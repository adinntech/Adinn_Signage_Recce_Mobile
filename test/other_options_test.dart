import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/catalog/signage_catalog.dart';
import 'package:signage_recce/data/catalog/site_checklists.dart';
import 'package:signage_recce/data/mock/mock_seed.dart';
import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/notes/other_spec_dialog.dart';
import 'package:signage_recce/features/report/report_data.dart';
import 'package:signage_recce/features/shop/add_media_sheet.dart';
import 'package:signage_recce/state/app_controller.dart';

import 'helpers.dart';
import 'support/evidence_fixture.dart';

const _shop = 's_lakshmi';

Future<AppController> _vendor([MemoryLocalStore? store]) async {
  final c = AppController(store: store ?? MemoryLocalStore());
  await c.init();
  c.loginWithPin(DemoAccounts.vendorPin);
  return c;
}

class _FakeCapture implements VoiceCapture {
  _FakeCapture({this.problem, this.take});
  final String? problem;
  VoiceTake? take;
  bool started = false;

  @override
  Future<String?> prepare(BuildContext context) async => problem;
  @override
  Future<void> start() async => started = true;
  @override
  Future<VoiceTake?> stop() async => take;
  @override
  Future<void> cancel() async {}
  @override
  void dispose() {}
}

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2600);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Widget _host(AppController c, Widget home) => ChangeNotifierProvider.value(
  value: c,
  child: MaterialApp(theme: AppTheme.light(), home: home),
);

VoiceNote _voice() => VoiceNote(
  id: 'vn1',
  path: '/tmp/x.m4a',
  durationMs: 2500,
  createdAt: DateTime(2026),
);

void main() {
  group('Custom description model', () {
    test('needs text or voice; whitespace never counts; round-trips', () {
      expect(CustomSpec(text: '   ').isValid, isFalse);
      expect(CustomSpec().isValid, isFalse);
      expect(CustomSpec(text: 'Glass fin').isValid, isTrue);
      expect(CustomSpec(voice: _voice()).isValid, isTrue);
      final both = CustomSpec(text: ' x ', voice: _voice());
      final back = CustomSpec.fromJson(jsonDecode(jsonEncode(both.toJson())) as Map<String, dynamic>);
      expect(back.text, 'x');
      expect(back.voice!.durationMs, 2500);
      expect(CustomSpec.fromJsonOrNull({'text': '  '}), isNull);
      expect(CustomSpec.fromJsonOrNull(null), isNull);
    });
  });

  group('Other media', () {
    test('text-only and voice-only create independent custom groups; nothing for invalid', () async {
      final c = await _vendor();
      final s = c.shop(_shop)!..boards.clear();
      expect(() => c.addOtherMedia(_shop, CustomSpec(text: '  ')), throwsArgumentError);
      expect(s.boards, isEmpty, reason: 'cancel / invalid creates nothing');
      final a = c.addOtherMedia(_shop, CustomSpec(text: 'Neon sign'));
      final b = c.addOtherMedia(_shop, CustomSpec(voice: _voice()));
      expect(a.id, isNot(b.id));
      expect(a.mediaCode, 'OTHER');
      expect(b.mediaCode, 'OTHER', reason: 'never GSB or another standard code');
      expect(a.name, 'Other 01');
      expect(b.name, 'Other 02');
      expect(a.customMedia!.text, 'Neon sign');
      expect(b.customMedia!.hasVoice, isTrue);
    });

    test('description survives save / reopen', () async {
      final store = MemoryLocalStore();
      final c = await _vendor(store);
      final b = c.addOtherMedia(_shop, CustomSpec(text: 'Neon', voice: _voice()));
      await c.flush();
      final r = AppController(store: store);
      await r.init();
      final back = r.board(_shop, b.id)!;
      expect(back.mediaCode, 'OTHER');
      expect(back.customMedia!.text, 'Neon');
      expect(back.customMedia!.voice!.id, 'vn1');
    });

    test('asks only the common compatible questions, no geometry, spec required', () async {
      final c = await _vendor();
      final b = c.addOtherMedia(_shop, CustomSpec(text: 'Neon'))
        ..width = 4
        ..height = 2
        ..installationCode = SignageCatalog.otherInstallation;
      b.units.first.customInstallation = CustomSpec(text: 'Hung on chains');
      final u = b.units.first;
      final ids = SignageCatalog.questionsForUnit(b, u).map((q) => q.id);
      expect(ids, containsAll(['existing_board', 'remove_existing']));
      expect(ids, isNot(contains('pole_height')));
      expect(ids, isNot(contains('mount_height')));
      expect(SiteChecklists.questionsFor('OTHER', 'other').map((q) => q.id), contains('checklist_remarks'));
      expect(SignageCatalog.unitDrawingBlocker(b, u), contains('Technical Specification Required'));
      // Descriptive recce can complete: no impossible drawing requirement.
      completeAnswers(b);
      addValidEvidence(c, _shop, b);
      expect(c.boardIssues(b), isEmpty);
    });

    test('report shows the custom description and the spec limitation', () async {
      final c = await _vendor();
      final s = c.shop(_shop)!..boards.clear();
      c.setShopLocation(s, gpsAt(10.8627, 78.6897));
      final b = c.addOtherMedia(_shop, CustomSpec(text: 'Neon sign', voice: _voice()))
        ..width = 4
        ..height = 2;
      c.setCustomInstallationForAll(_shop, b, CustomSpec(text: 'Hung on chains'));
      completeAnswers(b);
      addValidEvidence(c, _shop, b);
      final r = buildReportData(c, s, now: DateTime(2026, 11, 26), groupIds: {b.id});
      final g = (r.data['groups'] as List).single as Map;
      expect(g['media'], contains('Neon sign'));
      expect(g['media'], contains('Voice description attached'));
      expect(g['installation'], contains('Hung on chains'));
      final it = (g['items'] as List).single as Map;
      expect(it['specNote'], contains('Technical Specification Required'));
    });
  });

  group('Other installation', () {
    test('Same Installation: every board gets its own copy; unrelated questions stay out', () async {
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(SignageCatalog.mediaOptions.firstWhere((o) => o.key == 'GSB_SINGLE'), 1),
      ]).single
        ..width = 5
        ..height = 3;
      c.increaseQuantity(_shop, b, 2);
      expect(c.setCustomInstallationForAll(_shop, b, CustomSpec(text: 'Roof edge clamp')), isTrue);
      expect(b.installationCode, 'other');
      final u1 = b.units[0], u2 = b.units[1];
      expect(identical(u1.customInstallation, u2.customInstallation), isFalse);
      u2.customInstallation!.text = 'changed only on board 2';
      expect(u1.customInstallation!.text, 'Roof edge clamp');
      final ids = SignageCatalog.questionsForUnit(b, u1).map((q) => q.id).toSet();
      expect(ids.intersection({'pole_height', 'pole_gap', 'shutter_height', 'terrace_access', 'wall_type'}), isEmpty);
      expect(ids, containsAll(['existing_board', 'power_available']), reason: 'media-level questions stay');
    });

    test('Different Installations: independent custom and standard boards', () async {
      final c = await _vendor();
      final b = c.addMediaGroups(_shop, [
        MediaGroupPlan(SignageCatalog.mediaOptions.firstWhere((o) => o.key == 'GSB_SINGLE'), 1),
      ]).single
        ..width = 5
        ..height = 3;
      c.increaseQuantity(_shop, b, 3);
      expect(c.setCustomInstallationForUnit(_shop, b, b.units[0], CustomSpec(text: 'A')), isTrue);
      expect(c.setCustomInstallationForUnit(_shop, b, b.units[1], CustomSpec(voice: _voice())), isTrue);
      expect(c.setUnitInstallation(_shop, b, b.units[2], 'wall_mount'), isTrue);
      expect(c.setCustomInstallationForUnit(_shop, b, b.units[2], CustomSpec(text: '  ')), isFalse);
      expect(b.installationOf(b.units[0]), 'other');
      expect(b.installationOf(b.units[2]), 'wall_mount');
      expect(SignageCatalog.installationSummary(b), contains('Mixed'));
      expect(SignageCatalog.installationNameOf(b, b.units[0]), 'Other – A');
      expect(SignageCatalog.installationNameOf(b, b.units[1]), contains('Voice description attached'));
      // Wall-mount board keeps its own questions.
      expect(
        SignageCatalog.questionsForUnit(b, b.units[2]).map((q) => q.id),
        contains('wall_type'),
      );
      // Reopen: data restored per board.
      final copy = Board.fromJson(jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>);
      expect(copy.units[0].customInstallation!.text, 'A');
      expect(copy.units[1].customInstallation!.hasVoice, isTrue);
      expect(copy.units[2].customInstallation, isNull);
    });

    test('Other is the last installation option for every applicable media', () {
      for (final o in SignageCatalog.mediaOptions) {
        final b = Board(id: 'x', name: 'x', mediaCode: o.mediaCode, doubleSided: o.doubleSided, nlbSubtype: o.nlbSubtype);
        final codes = SignageCatalog.choicesForBoard(b).map((c) => c.code).toList();
        expect(codes.last, 'other', reason: o.key);
        expect(codes.where((c) => c == 'other'), hasLength(1));
      }
      expect(SignageCatalog.allowsInstallation(Board(id: 'y', name: 'y', mediaCode: 'ACP'), 'other'), isFalse,
          reason: 'legacy media are not extended');
    });
  });

  group('Other dialog (text / voice)', () {
    testWidgets('empty input is rejected; text-only saves; cancel returns nothing', (tester) async {
      _phone(tester);
      CustomSpec? result;
      await tester.pumpWidget(
        _host(
          await _vendor(),
          Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                key: const Key('open'),
                onPressed: () async => result = await showOtherSpecDialog(ctx, title: 'Other Media Type', hint: 'h'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(find.text('Other Media Type'), findsOneWidget);
      await tester.tap(find.byKey(const Key('other_save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('other_error')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('other_text')), '    ');
      await tester.tap(find.byKey(const Key('other_save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('other_error')), findsOneWidget, reason: 'whitespace only');
      await tester.tap(find.byKey(const Key('other_cancel')));
      await tester.pumpAndSettle();
      expect(result, isNull);

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('other_text')), 'Glass fin');
      await tester.tap(find.byKey(const Key('other_save')));
      await tester.pumpAndSettle();
      expect(result!.text, 'Glass fin');
      expect(result!.voice, isNull);
    });

    testWidgets('voice-only works; failed / too-short recording and denied permission do not', (tester) async {
      _phone(tester);
      addTearDown(() => voiceCaptureFactory = DeviceVoiceCapture.new);
      CustomSpec? result;
      Future<void> open() async {
        await tester.tap(find.byKey(const Key('open')));
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        _host(
          await _vendor(),
          Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                key: const Key('open'),
                onPressed: () async => result = await showOtherSpecDialog(ctx, title: 'Other Installation Type', hint: 'h'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      // Permission denied.
      voiceCaptureFactory = () => _FakeCapture(problem: 'Microphone permission is needed to record voice notes');
      await open();
      await tester.tap(find.byKey(const Key('other_record')));
      await tester.pumpAndSettle();
      expect(find.text('Microphone permission is needed to record voice notes'), findsOneWidget);
      await tester.tap(find.byKey(const Key('other_save')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'still no valid input');
      await tester.tap(find.byKey(const Key('other_cancel')));
      await tester.pumpAndSettle();

      // Recording failure (nothing usable) and a too-short take.
      for (final take in [null, const VoiceTake('/tmp/a.m4a', Duration(milliseconds: 200))]) {
        voiceCaptureFactory = () => _FakeCapture(take: take);
        await open();
        await tester.tap(find.byKey(const Key('other_record')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('other_record'))); // stop
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('other_error')), findsOneWidget);
        await tester.tap(find.byKey(const Key('other_save')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.byKey(const Key('other_cancel')));
        await tester.pumpAndSettle();
      }
      expect(result, isNull);

      // A good take saves with voice only; re-record replaces it.
      voiceCaptureFactory = () => _FakeCapture(take: const VoiceTake('/tmp/ok.m4a', Duration(seconds: 3)));
      await open();
      await tester.tap(find.byKey(const Key('other_record')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('other_record')));
      await tester.pumpAndSettle();
      expect(find.text('Re-record'), findsOneWidget);
      await tester.tap(find.byKey(const Key('other_save')));
      await tester.pumpAndSettle();
      expect(result!.hasVoice, isTrue);
      expect(result!.text, isEmpty);
      expect(result!.voice!.durationMs, 3000);
    });
  });

  group('Add Media sheet', () {
    testWidgets('+ Other creates one custom media; cancelling creates nothing', (tester) async {
      _phone(tester);
      final c = await _vendor();
      final s = c.shop(_shop)!..boards.clear();
      List<Board>? created;
      await tester.pumpWidget(
        _host(
          c,
          Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                key: const Key('go'),
                onPressed: () async => created = await runAddMedia(ctx, c, _shop),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      // Nine standard options stay; "+ Other" is the extra, final one.
      await tester.ensureVisible(find.byKey(const Key('opt_OTHER')));
      await tester.tap(find.byKey(const Key('opt_OTHER')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('other_cancel')));
      await tester.pumpAndSettle();
      expect(s.boards, isEmpty);
      await tester.tap(find.byKey(const Key('sheet_cancel')));
      await tester.pumpAndSettle();
      expect(created, isEmpty);

      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('opt_OTHER')));
      await tester.tap(find.byKey(const Key('opt_OTHER')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('other_text')), 'Standee with lights');
      await tester.tap(find.byKey(const Key('other_save')));
      await tester.pumpAndSettle();
      expect(created, hasLength(1));
      expect(s.boards.single.mediaCode, 'OTHER');
      expect(s.boards.single.customMedia!.text, 'Standee with lights');
    });
  });
}
