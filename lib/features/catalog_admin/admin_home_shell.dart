import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../live_auth/presentation/live_auth_controller.dart';
import '../live_recce/data/live_services.dart';
import 'catalog_admin_controller.dart';
import 'catalog_admin_screen.dart';

/// Home of a signed-in administrator on the phone: the Media catalog and the profile, nothing else. The field screens (shops, photos,
/// chat) belong to the Recce and Vendor logins; the administrator works on the catalog here and on everything else on the web.
class AdminHomeShell extends StatefulWidget {
  const AdminHomeShell({super.key});

  @override
  State<AdminHomeShell> createState() => _AdminHomeShellState();
}

class _AdminHomeShellState extends State<AdminHomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CatalogAdminController>(
      create: (c) {
        final services = c.read<LiveServices>();
        return CatalogAdminController(services.api, shared: services.catalog)..load();
      },
      child: Scaffold(
        body: IndexedStack(index: _index, children: const [CatalogAdminScreen(), AdminProfileScreen()]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.category_outlined), selectedIcon: Icon(Icons.category), label: 'Catalog'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

/// Who is signed in, the server, and sign out.
class AdminProfileScreen extends StatelessWidget {
  const AdminProfileScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    final services = context.read<LiveServices>();
    final ok = await confirmDialog(context, title: 'Sign out?', message: 'You will need to sign in again.', confirmText: 'Sign out');
    if (ok) await services.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<LiveAuthController>().user;
    final name = u?.name ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            child: Row(children: [
              Avatar(_initials(name), size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(u?.role.label ?? '', style: const TextStyle(color: AdinnColors.muted)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Account',
            icon: Icons.badge_outlined,
            child: Column(children: [
              if ((u?.email ?? '').isNotEmpty) InfoRow('Email', u!.email, icon: Icons.mail_outline),
              const InfoRow('Access', 'Media catalog on the phone. Everything else is on the web.', icon: Icons.admin_panel_settings_outlined),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(title: 'Connection', icon: Icons.cloud_outlined, child: InfoRow('Server', ApiConfig.baseUrl, icon: Icons.dns_outlined)),
          const SizedBox(height: 18),
          OutlinedButton.icon(key: const Key('admin-signout'), onPressed: () => _signOut(context), icon: const Icon(Icons.logout), label: const Text('Sign out')),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }
}
