import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notifications_controller.dart';
import '../data/recce_models.dart' show ShopFilter;
import 'live_dashboard_screen.dart';
import 'live_profile_screen.dart';
import 'live_projects_screen.dart';
import 'live_shops_screen.dart';
import 'notifications_screen.dart';

/// Home of a signed-in VENDOR / RECCE_EXECUTIVE: Home, Projects, Submitted, Activity, Profile. Each has the notification bell in its top bar. While
/// the app is in front, the bell's unread count is read about every minute; in the background nothing is read.
class LiveHomeShell extends StatefulWidget {
  const LiveHomeShell({super.key});

  @override
  State<LiveHomeShell> createState() => _LiveHomeShellState();
}

class _LiveHomeShellState extends State<LiveHomeShell> with WidgetsBindingObserver {
  int _index = 0;
  late final NotificationsController _notes;

  void _go(int i) => setState(() => _index = i);

  @override
  void initState() {
    super.initState();
    _notes = context.read<NotificationsController>()
      ..load(silent: true)
      ..startPolling();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _notes
        ..load(silent: true)
        ..startPolling();
    } else {
      _notes.stopPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notes.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: [
        LiveDashboardScreen(onOpenTab: _go),
        const LiveProjectsScreen(),
        const LiveShopsScreen(title: 'Submitted', initialFilter: ShopFilter.submitted),
        const NotificationsScreen(title: 'Activity'),
        const LiveProfileScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder), label: 'Projects'),
          NavigationDestination(icon: Icon(Icons.outbox_outlined), selectedIcon: Icon(Icons.outbox), label: 'Submitted'),
          NavigationDestination(icon: Icon(Icons.timeline_outlined), selectedIcon: Icon(Icons.timeline), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
