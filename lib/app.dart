import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/splash_screen.dart';
import 'data/services/location_service.dart';
import 'features/auth/login_screen.dart';
import 'features/catalog_admin/admin_home_shell.dart';
import 'features/home/home_shell.dart';
import 'features/live_auth/presentation/live_auth_controller.dart';
import 'features/live_auth/presentation/live_change_mpin_screen.dart';
import 'features/live_auth/presentation/live_login_screen.dart';
import 'features/live_recce/data/catalog_controller.dart';
import 'features/live_recce/data/chat_controller.dart';
import 'features/live_recce/data/dashboard_controller.dart';
import 'features/live_recce/data/live_services.dart';
import 'features/live_recce/data/notifications_controller.dart';
import 'features/live_recce/data/recce_controllers.dart';
import 'features/live_recce/data/upload_queue.dart';
import 'features/live_recce/presentation/live_home_shell.dart';
import 'state/app_controller.dart';

class AdinnRecceApp extends StatefulWidget {
  const AdinnRecceApp({super.key, required this.controller, this.location, this.live});

  final AppController controller;

  /// GPS source; defaults to the device GPS. Tests inject a fake.
  final LocationService? location;

  /// Live backend (login, projects, shops, recce). Null keeps the app in its offline prototype mode (tests).
  final LiveServices? live;

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
    widget.live?.init();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppController>.value(value: widget.controller),
        Provider<LocationService>.value(value: _location),
        if (widget.live != null) ...[
          Provider<LiveServices>.value(value: widget.live!),
          ChangeNotifierProvider<LiveAuthController>.value(value: widget.live!.auth),
          ChangeNotifierProvider<UploadQueue>.value(value: widget.live!.queue),
          ChangeNotifierProvider<ShopListController>.value(value: widget.live!.shops),
          ChangeNotifierProvider<ChatHub>.value(value: widget.live!.chat),
          ChangeNotifierProvider<FieldDashboardController>.value(value: widget.live!.dashboard),
          ChangeNotifierProvider<NotificationsController>.value(value: widget.live!.notifications),
          ChangeNotifierProvider<CatalogController>.value(value: widget.live!.catalog),
        ],
      ],
      child: MaterialApp(
        title: 'Adinn Recce',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: RootGate(live: widget.live != null),
      ),
    );
  }
}

/// Chooses splash / login / home based on controller state.
class RootGate extends StatelessWidget {
  const RootGate({super.key, this.live = false});

  /// True when [LiveServices] are provided: the live login / home come first and the offline prototype
  /// stays reachable through "Offline demo mode" on the login screen.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    if (!c.isReady) return const SplashScreen();
    if (!live) {
      if (!c.isLoggedIn) return const LoginScreen();
      // Key by user so switching accounts resets tab state.
      return HomeShell(key: ValueKey(c.currentUser!.id));
    }
    final auth = context.watch<LiveAuthController>();
    if (!auth.ready) return const SplashScreen();
    final user = auth.user;
    if (user != null) {
      if (user.mustChangeMpin) return const LiveChangeMpinScreen();
      // The administrator gets the Media catalog screens only; the field screens are for Recce and Vendor logins.
      if (user.isAdmin) return AdminHomeShell(key: ValueKey(user.id));
      return LiveHomeShell(key: ValueKey(user.id));
    }
    if (c.isLoggedIn) return HomeShell(key: ValueKey(c.currentUser!.id));
    if (auth.offlineDemo) return const _OfflineDemoLogin();
    return const LiveLoginScreen();
  }
}

/// The old PIN login, with a small way back to the live sign in.
class _OfflineDemoLogin extends StatelessWidget {
  const _OfflineDemoLogin();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const LoginScreen(),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Material(
              type: MaterialType.transparency,
              child: TextButton.icon(
                onPressed: context.read<LiveAuthController>().leaveOfflineDemo,
                icon: const Icon(Icons.cloud_outlined, size: 18),
                label: const Text('Online sign in'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

