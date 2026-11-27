import 'l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/common_widgets.dart';

import 'data/services/location_service.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'l10n/app_localizations.dart';
import 'state/app_controller.dart';

class AdinnRecceApp extends StatefulWidget {
  const AdinnRecceApp({super.key, required this.controller, this.location});

  final AppController controller;

  /// GPS source; defaults to the device GPS. Tests inject a fake.
  final LocationService? location;

  @override
  State<AdinnRecceApp> createState() => _AdinnRecceAppState();
}

class _AdinnRecceAppState extends State<AdinnRecceApp> {
  late final LocationService _location =
      widget.location ?? DeviceLocationService();

  @override
  void initState() {
    super.initState();
    if (!widget.controller.isReady) widget.controller.init();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppController>.value(value: widget.controller),
        Provider<LocationService>.value(value: _location),
      ],
      // Rebuild the app shell only when the LANGUAGE changes (never on every
      // data change).
      child: Selector<AppController, String>(
        selector: (_, c) => c.locale.languageCode,
        builder: (context, lang, _) => MaterialApp(
          title: 'Adinn Recce',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          // English by default; the saved preference restores on restart.
          locale: Locale(lang),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const RootGate(),
        ),
      ),
    );
  }
}

/// Chooses splash / login / home based on controller state.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    if (!c.isReady) return const SplashScreen();
    if (!c.isLoggedIn) return const LoginScreen();
    // Key by user so switching accounts resets tab state.
    return HomeShell(key: ValueKey(c.currentUser!.id));
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AdinnLogo(size: 44),
            SizedBox(height: 18),
            Text(context.ui('Signage Recce'),
              style: TextStyle(
                color: AdinnColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}
