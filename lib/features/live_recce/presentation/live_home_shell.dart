import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notifications_controller.dart';
import 'live_dashboard_screen.dart';
import 'live_profile_screen.dart';
import 'live_projects_screen.dart';

/// Home of a signed-in VENDOR / RECCE_EXECUTIVE: Dashboard, Projects, Profile. Each has the notification bell in its top bar. While
/// the app is in front, the bell's unread count is read about every minute; in the background nothing is read.
class LiveHomeShell extends StatefulWidget {
  const LiveHomeShell({super.key});

  @override
  State<LiveHomeShell> createState() => _LiveHomeShellState();
}

class _LiveHomeShellState extends State<LiveHomeShell> with WidgetsBindingObserver {
  int _index = 0;
  late final NotificationsController _notes;

  static const _pages = [LiveDashboardScreen(), LiveProjectsScreen(), LiveProfileScreen()];

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
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder), label: 'Projects'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
