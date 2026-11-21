import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/input_formats.dart';
import '../../live_auth/presentation/live_auth_controller.dart';
import '../data/live_services.dart';
import '../data/upload_queue.dart';
import 'notifications_screen.dart';

/// Profile: who is signed in, waiting uploads, sign out.
class LiveProfileScreen extends StatelessWidget {
  const LiveProfileScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    final services = context.read<LiveServices>();
    final pending = services.queue.totalPending;
    final ok = await confirmDialog(
      context,
      title: 'Sign out?',
      message: pending > 0
          ? '$pending photo${pending == 1 ? '' : 's'} not uploaded yet will be discarded. Sign out anyway?'
          : 'You will need to sign in again.',
      confirmText: 'Sign out',
      destructive: pending > 0,
    );
    if (ok) await services.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<LiveAuthController>();
    final queue = context.watch<UploadQueue>();
    final u = auth.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), actions: const [NotificationBell()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            child: Row(
              children: [
                Avatar(_initials(u?.name ?? '?'), size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u?.name ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(u?.role.label ?? '', style: const TextStyle(color: AdinnColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Account',
            icon: Icons.badge_outlined,
            child: Column(
              children: [
                if ((u?.email ?? '').isNotEmpty) InfoRow('Email', u!.email, icon: Icons.mail_outline),
                if ((u?.phone ?? '').isNotEmpty) InfoRow('Phone', showMobile(u!.phone), icon: Icons.phone_outlined),
                if (u?.vendorName != null) InfoRow('Vendor', u!.vendorName!, icon: Icons.storefront_outlined),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Connection',
            icon: Icons.cloud_outlined,
            child: Column(
              children: [
                InfoRow('Server', ApiConfig.baseUrl, icon: Icons.dns_outlined),
                InfoRow('Waiting uploads', '${queue.totalPending}', icon: Icons.cloud_upload_outlined),
                if (auth.offlineSession) const InfoRow('Mode', 'Offline session (server not reached)', icon: Icons.cloud_off_outlined),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(onPressed: () => _signOut(context), icon: const Icon(Icons.logout), label: const Text('Sign out')),
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
