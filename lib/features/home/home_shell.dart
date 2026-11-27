import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../../state/app_controller.dart';
import '../approvals/approvals_screen.dart';
import '../history/activity_screen.dart';
import '../profile/profile_screen.dart';
import '../projects/projects_screen.dart';
import 'dashboard_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final reviewer = !c.isVendor;
    final pendingCount = reviewer
        ? c.pendingReviews.length
        : c.mySubmissions.where((s) => s.status.isRejected).length;

    final notice = c.recoveryNotice;
    final tabs = IndexedStack(
      index: _index,
      children: [
        DashboardScreen(onOpenTab: _go),
        const ProjectsScreen(),
        const ApprovalsScreen(),
        const ActivityScreen(),
        const ProfileScreen(),
      ],
    );
    final storageError = c.storageError;
    return Scaffold(
      body: notice == null && storageError == null
          ? tabs
          : Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      if (storageError != null)
                        MaterialBanner(
                          key: const Key('storage_error'),
                          backgroundColor: const Color(0xFFFDECEC),
                          content: Text(storageError),
                          leading: const Icon(
                            Icons.sd_card_alert_outlined,
                            color: Color(0xFFD71920),
                          ),
                          actions: [
                            TextButton(
                              onPressed: c.retrySave,
                              child: Text(context.ui('Retry')),
                            ),
                          ],
                        ),
                      if (notice != null)
                        MaterialBanner(
                          key: const Key('recovery_notice'),
                          content: Text(notice),
                          leading: const Icon(Icons.restore_page_outlined),
                          actions: [
                            TextButton(
                              onPressed: c.dismissRecoveryNotice,
                              child: Text(context.ui('OK')),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Expanded(child: tabs),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: context.t.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_outlined),
            selectedIcon: const Icon(Icons.folder),
            label: context.t.navProjects,
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: Icon(
                reviewer ? Icons.fact_check_outlined : Icons.outbox_outlined,
              ),
            ),
            selectedIcon: Icon(reviewer ? Icons.fact_check : Icons.outbox),
            label: reviewer ? context.t.navApprovals : context.t.navSubmitted,
          ),
          NavigationDestination(
            icon: const Icon(Icons.timeline_outlined),
            selectedIcon: const Icon(Icons.timeline),
            label: context.t.navActivity,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: context.t.navProfile,
          ),
        ],
      ),
    );
  }
}
