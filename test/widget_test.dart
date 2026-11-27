import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signage_recce/app.dart';
import 'package:signage_recce/core/theme/app_theme.dart';
import 'package:signage_recce/data/services/location_service.dart';
import 'package:signage_recce/data/storage/local_store.dart';
import 'package:signage_recce/features/board/board_editor_screen.dart';
import 'package:signage_recce/features/shop/shop_detail_screen.dart';
import 'package:signage_recce/features/submission/submission_screen.dart';
import 'package:signage_recce/state/app_controller.dart';

import 'helpers.dart';

void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<AppController> bootApp(
  WidgetTester tester, {
  FakeLocationService? location,
}) async {
  usePhoneSize(tester);
  final c = AppController(store: MemoryLocalStore());
  await c.init();
  await tester.pumpWidget(
    AdinnRecceApp(controller: c, location: location ?? FakeLocationService()),
  );
  await tester.pumpAndSettle();
  return c;
}

/// Types [pin] on the login keypad (auto-submits after the 4th digit).
Future<void> enterPin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(Key('pin_key_$d')));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Scrolls [finder] fully on screen, then taps it (fails if the tap misses).
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    // Lazily-built list item: scroll until it is built first.
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

Widget host(AppController c, Widget child) =>
    ChangeNotifierProvider<AppController>.value(
      value: c,
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );

void main() {
  // A tap that misses its target must fail the test, not just warn.
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);

  testWidgets('login asks only for a 4-digit PIN (no username)', (
    tester,
  ) async {
    await bootApp(tester);
    expect(find.text('Enter your 4-digit PIN'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    for (var d = 0; d <= 9; d++) {
      expect(find.byKey(Key('pin_key_$d')), findsOneWidget);
    }
    expect(find.text('DEMO PINS (tap to log in)'), findsOneWidget);
  });

  testWidgets('wrong PIN shows attempts left; backspace edits the PIN', (
    tester,
  ) async {
    final c = await bootApp(tester);
    await tester.tap(find.byKey(const Key('pin_key_9')));
    await tester.tap(find.byKey(const Key('pin_backspace')));
    await enterPin(tester, '9999');
    expect(find.text('Incorrect PIN. 4 attempts left.'), findsOneWidget);
    expect(c.isLoggedIn, isFalse);
    await enterPin(tester, '5678');
    expect(c.isLoggedIn, isTrue);
    expect(find.text('Murugan K'), findsOneWidget);
  });

  testWidgets('five wrong PINs lock the keypad', (tester) async {
    final c = await bootApp(tester);
    for (var i = 0; i < 5; i++) {
      await enterPin(tester, '9999');
    }
    expect(find.textContaining('Try again in'), findsOneWidget);
    // Keypad is disabled while locked: the right PIN does nothing.
    await enterPin(tester, '5678');
    expect(c.isLoggedIn, isFalse);
    // Let the lock expire so no timer is left pending.
    await tester.pump(AppController.pinLockDuration);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('vendor logs in and drills into project → task → shop', (
    tester,
  ) async {
    await bootApp(tester);
    await enterPin(tester, '5678');
    expect(find.text('Murugan K'), findsOneWidget);
    expect(find.textContaining('need field work'), findsOneWidget);

    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asian Paints').first);
    await tester.pumpAndSettle();
    expect(find.text('Project details'), findsOneWidget);

    await tapVisible(tester, find.text('Shop Recce – Srirangam'));
    await tester.pumpAndSettle();
    expect(find.text('Sri Ranga Paints & Hardwares'), findsOneWidget);
    expect(find.text('Add Shop'), findsOneWidget);

    await tester.tap(find.text('Sri Ranga Paints & Hardwares'));
    await tester.pumpAndSettle();
    expect(find.text('Shop location (GPS)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Signage requirements (1)'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Signage requirements (1)'), findsOneWidget);
    expect(find.byKey(const Key('open_submit')), findsOneWidget);
  });

  testWidgets('forgot PIN: mobile → OTP → new PIN', (tester) async {
    final c = await bootApp(tester);
    await tester.tap(find.text('Forgot PIN?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('forgot_mobile')),
      '9876543210',
    );
    await tester.tap(find.text('SEND OTP'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Use OTP: 246810'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('forgot_otp')), '246810');
    await tester.tap(find.text('VERIFY'));
    await tester.pumpAndSettle();
    // Another user's PIN is rejected (PIN alone identifies the user).
    await tester.enterText(find.byKey(const Key('forgot_pin1')), '1234');
    await tester.enterText(find.byKey(const Key('forgot_pin2')), '1234');
    await tester.tap(find.text('SET NEW PIN'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not available'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('forgot_pin1')), '2580');
    await tester.enterText(find.byKey(const Key('forgot_pin2')), '2580');
    await tester.tap(find.text('SET NEW PIN'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your 4-digit PIN'), findsOneWidget);
    await enterPin(tester, '2580');
    expect(c.currentUser?.name, 'Murugan K');
  });

  testWidgets('vendor captures shop GPS from the shop screen', (tester) async {
    final gps = FakeLocationService(
      fix: gpsAt(10.86281, 78.68952, accuracy: 7),
    );
    final c = await bootApp(tester, location: gps);
    c.loginWithPin('5678');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppController>.value(value: c),
          Provider<LocationService>.value(value: gps),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ShopDetailScreen(shopId: 's_sriranga'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('capture_gps')));
    await tester.pumpAndSettle();
    expect(gps.calls, 1);
    expect(c.shop('s_sriranga')!.geo!.coordinates, '10.86281, 78.68952');
    expect(find.text('10.86281, 78.68952'), findsOneWidget);
    expect(find.text('±7 m'), findsOneWidget);
    expect(find.text('Captured'), findsOneWidget);
  });

  testWidgets('GPS failure explains why and keeps the shop unlocated', (
    tester,
  ) async {
    final gps = FakeLocationService(
      error: const LocationException(
        LocationIssue.serviceDisabled,
        'Location (GPS) is turned off.',
      ),
    );
    final c = await bootApp(tester, location: gps);
    c.loginWithPin('5678');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppController>.value(value: c),
          Provider<LocationService>.value(value: gps),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ShopDetailScreen(shopId: 's_lakshmi'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('capture_gps')));
    await tester.pumpAndSettle();
    expect(find.text('Location (GPS) is turned off.'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(c.shop('s_lakshmi')!.geo, isNull);
  });

  testWidgets('business reviewer sees pending approval queue', (tester) async {
    await bootApp(tester);
    await enterPin(tester, '1234');
    await tester.tap(find.text('Approvals').last);
    await tester.pumpAndSettle();
    expect(find.text('Business Team Approvals'), findsOneWidget);
    expect(find.text('Amma Paint House'), findsOneWidget);

    await tester.tap(find.text('Amma Paint House'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open_review')));
    await tester.pumpAndSettle();
    expect(find.text('Review v1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('approve_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approve_confirm')));
    await tester.pumpAndSettle();
    final c = Provider.of<AppController>(
      tester.element(find.byType(Scaffold).first),
      listen: false,
    );
    expect(c.shop('s_amma')!.status.name, 'pendingOps');
  });

  testWidgets('board editor shows media grid and dynamic questions', (
    tester,
  ) async {
    usePhoneSize(tester);
    final c = AppController(store: MemoryLocalStore());
    await c.init();
    c.loginWithPin('5678');
    final b = c.addBoard('s_lakshmi');
    await tester.pumpWidget(
      host(c, BoardEditorScreen(shopId: 's_lakshmi', boardId: b.id)),
    );
    await tester.pumpAndSettle();
    // Media Type is the first step for a new board.
    expect(find.text('GSB'), findsOneWidget);
    // Catalog v2: legacy Wall Paint is no longer offered for new groups.
    expect(find.text('Wall Paint'), findsNothing);
    expect(find.text('MDF+GSB DS'), findsNothing);
    expect(find.text('MDF'), findsOneWidget);

    tester.widget<InkWell>(find.byKey(const Key('media_GSB'))).onTap!();
    await tester.pumpAndSettle();
    // GSB asks for the board type first.
    await tester.tap(find.byKey(const Key('gsb_type_single')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gsb_type_continue')));
    await tester.pumpAndSettle();
    expect(b.mediaCode, 'GSB');
    // Auto-named after the media; Board Details (step 2) is next.
    expect(b.name, 'GSB Single 01');
    expect(
      tester.widget<Stepper>(find.byType(Stepper)).currentStep,
      BoardEditorScreen.boardDetailsStep,
    );
    await tapVisible(tester, find.byKey(const Key('step_next_1')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Stepper>(find.byType(Stepper)).currentStep,
      BoardEditorScreen.installationStep,
    );
    await tapVisible(tester, find.byKey(const Key('inst_double_pole')));
    await tester.pumpAndSettle();
    expect(b.installationCode, 'double_pole');
    // Labels are Text.rich ("label *"), so match by substring.
    expect(
      find.textContaining('Clear height below board', findRichText: true),
      findsOneWidget,
    );
    // Conditional question appears only when power is not available.
    expect(
      find.textContaining('Distance to nearest power', findRichText: true),
      findsNothing,
    );
    await tapVisible(tester, find.byKey(const Key('q_power_available_false')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Distance to nearest power', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('vendor submits a completed recce from the review screen', (
    tester,
  ) async {
    usePhoneSize(tester);
    final c = AppController(store: MemoryLocalStore());
    await c.init();
    c.loginWithPin('5678');
    final shop = c.shop('s_sriranga')!;
    completeAnswers(shop.boards.first);
    c.touchBoard(shop.id, shop.boards.first);
    c.setShopLocation(shop, gpsAt(10.86270, 78.68970));

    await tester.pumpWidget(host(c, SubmissionScreen(shopId: shop.id)));
    await tester.pumpAndSettle();
    expect(find.text('Submit recce v1'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('submit_declare')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('submit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Submitted v1'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(shop.status.name, 'pendingBusiness');
    expect(shop.submissions, hasLength(1));
  });
}
