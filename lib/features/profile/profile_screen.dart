import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/language_switcher.dart';
import '../../l10n/l10n.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../references/media_reference_library_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const supportPhone = '1800 425 0000';

  Future<void> _logout(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: context.ui('Logout?'),
      message: context.ui(
        'Your recce data stays saved on this device. You can log in again '
        'any time.',
      ),
      confirmText: context.ui('Logout'),
    );
    if (ok && context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      context.read<AppController>().logout();
    }
  }

  Future<void> _reset(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: context.ui('Reset demo data?'),
      message: context.ui(
        'All local projects, shops, photos, voice notes and history will be '
        'replaced with the original dummy data.',
      ),
      confirmText: context.ui('Reset'),
      destructive: true,
    );
    if (ok && context.mounted) {
      await context.read<AppController>().resetDemoData();
      if (context.mounted) showSnack(context, context.ui('Demo data restored'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final u = c.currentUser;
    if (u == null) return const SizedBox.shrink();
    final sum = c.overallSummary;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t.navProfile),
        actions: const [LanguageSwitcher(), SizedBox(width: 8)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Avatar(u.initials, size: 72),
                  const SizedBox(height: 10),
                  Text(
                    u.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    u.designation,
                    style: const TextStyle(color: AdinnColors.muted),
                  ),
                  const SizedBox(height: 8),
                  TagChip(u.role.label, color: AdinnColors.red),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Metric('Shops', '${sum.total}'),
                      _Metric('Approved', '${sum.approved}'),
                      _Metric(
                        u.role == UserRole.vendor ? 'Pending' : 'To review',
                        u.role == UserRole.vendor
                            ? '${sum.pending}'
                            : '${c.pendingReviews.length}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: context.ui('Account'),
            icon: Icons.badge_outlined,
            child: Column(
              children: [
                InfoRow(context.ui('Employee / Vendor ID'), u.code),
                InfoRow(context.ui('Mobile'), u.mobile),
                InfoRow('Email', u.email),
                InfoRow('Company', u.company),
                InfoRow(context.ui('Region'), u.region),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  key: const Key('change_pin_tile'),
                  leading: const Icon(
                    Icons.pin_outlined,
                    color: AdinnColors.red,
                  ),
                  title: Text(context.ui('Change login PIN')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => const _ChangePinSheet(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('open_media_references'),
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: AdinnColors.red,
                  ),
                  title: Text(context.ui('Media reference library')),
                  subtitle: Text(context.ui('Reference photos & technical approval per media'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MediaReferenceLibraryScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.support_agent,
                    color: AdinnColors.red,
                  ),
                  title: Text(context.ui('Call Adinn support')),
                  subtitle: const Text(supportPhone),
                  trailing: const Icon(Icons.call_outlined),
                  onTap: () => dialNumber(context, supportPhone),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.restart_alt,
                    color: AdinnColors.warning,
                  ),
                  title: Text(context.ui('Reset demo data')),
                  subtitle: Text(context.ui('Restore the original dummy dataset')),
                  onTap: () => _reset(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.info_outline, color: AdinnColors.muted),
                  title: Text(context.ui('Adinn Signage Recce')),
                  subtitle: Text(context.ui('v1.0.0 • Offline prototype – all data stored on this '
                    'device only'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('logout_button'),
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout),
            label: Text(context.ui('LOGOUT')),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
        ),
      ],
    );
  }
}

class _ChangePinSheet extends StatefulWidget {
  const _ChangePinSheet();

  @override
  State<_ChangePinSheet> createState() => _ChangePinSheetState();
}

class _ChangePinSheetState extends State<_ChangePinSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _save() {
    if (_next.text != _confirm.text) {
      setState(() => _error = 'New PINs do not match');
      return;
    }
    final err = context.read<AppController>().changePin(
      _current.text,
      _next.text,
    );
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context);
    showSnack(context, context.ui('Login PIN changed'));
  }

  Widget _pinField(String label, TextEditingController c, {Key? key}) {
    return TextField(
      key: key,
      controller: c,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 4,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, counterText: ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.ui('Change login PIN'),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(context.ui('Your PIN is the only thing needed to log in – keep it private.'),
            style: TextStyle(color: AdinnColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          _pinField('Current PIN', _current, key: const Key('pin_current')),
          const SizedBox(height: 10),
          _pinField('New 4-digit PIN', _next, key: const Key('pin_new')),
          const SizedBox(height: 10),
          _pinField('Confirm new PIN', _confirm, key: const Key('pin_confirm')),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AdinnColors.redDark)),
          ],
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('pin_update'),
            onPressed: _save,
            child: Text(context.ui('UPDATE PIN')),
          ),
        ],
      ),
    );
  }
}
