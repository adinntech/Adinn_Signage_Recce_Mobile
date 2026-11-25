import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/auth_models.dart';
import '../domain/auth_rules.dart';
import 'live_auth_controller.dart';
import 'live_auth_widgets.dart';
import 'live_forgot_screen.dart';
import 'live_register_screen.dart';

const _roleCards = [
  (role: LiveRole.recceExecutive, key: 'RECCE', label: 'Recce', hint: 'Field execution', icon: Icons.travel_explore),
  (role: LiveRole.vendor, key: 'VENDOR', label: 'Vendor', hint: 'Field vendors', icon: Icons.storefront_outlined),
  (role: LiveRole.admin, key: 'ADMIN', label: 'Admin', hint: 'Media catalog', icon: Icons.admin_panel_settings_outlined),
];

/// Live sign in: Recce and Admin cards (email / employee ID + MPIN or password) and Vendor card (vendor ID digits).
/// The Admin card is for the administrator, who manages the media catalog on the phone.
class LiveLoginScreen extends StatefulWidget {
  const LiveLoginScreen({super.key});

  @override
  State<LiveLoginScreen> createState() => _LiveLoginScreenState();
}

class _LiveLoginScreenState extends State<LiveLoginScreen> {
  final _identifier = TextEditingController();
  final _credential = CredentialInputs(create: false);
  LiveRole _role = LiveRole.recceExecutive;
  String? _identifierError;

  bool get _isVendor => _role == LiveRole.vendor;
  bool get _isAdmin => _role == LiveRole.admin;

  @override
  void dispose() {
    _identifier.dispose();
    _credential.dispose();
    super.dispose();
  }

  void _pickRole(LiveRole role) {
    if (role == _role) return;
    context.read<LiveAuthController>().clearError();
    setState(() {
      _role = role;
      _identifier.clear();
      _identifierError = null;
    });
    _credential.setUseMpin(false);
  }

  Future<void> _submit() async {
    final auth = context.read<LiveAuthController>();
    if (auth.busy) return;
    if (_isVendor) {
      final err = AuthRules.vendorId(_identifier.text);
      setState(() => _identifierError = err);
      if (err != null) return;
      FocusScope.of(context).unfocus();
      await auth.vendorLogin(_identifier.text);
      return;
    }
    final err = AuthRules.identifier(_identifier.text);
    final ok = _credential.validate();
    setState(() => _identifierError = err);
    if (err != null || !ok) return;
    FocusScope.of(context).unfocus();
    await auth.login(
      _identifier.text,
      _credential.credential,
      loginRole: _roleCards.firstWhere((r) => r.role == _role).key,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<LiveAuthController>();
    final busy = auth.busy;
    final error = auth.error;
    return LiveAuthScaffold(
      title: 'Welcome back',
      subtitle: _isVendor
          ? 'Enter the last 4 digits of your vendor ID'
          : _isAdmin
              ? 'Administrator sign in: manage the media catalog'
              : 'Sign in with your password or MPIN',
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null)
              AuthBanner(
                // An admin made on the web usually has a password only, so an MPIN sign in fails until one is set by email code.
                message: _isAdmin && error.code == 'INVALID_CREDENTIALS'
                    ? 'Incorrect details. If this admin account has no MPIN yet, tap "Set up / reset MPIN" below and set one with the emailed code.'
                    : friendlyAuthMessage(error),
              ),
            const Text('Select your role', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final r in _roleCards) ...[
                  Expanded(
                    child: _RoleCard(
                      label: r.label,
                      hint: r.hint,
                      icon: r.icon,
                      selected: _role == r.role,
                      onTap: busy ? null : () => _pickRole(r.role),
                    ),
                  ),
                  if (r != _roleCards.last) const SizedBox(width: 12),
                ],
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _identifier,
              enabled: !busy,
              keyboardType: _isVendor ? TextInputType.number : TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              inputFormatters: _isVendor
                  ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)]
                  : [LengthLimitingTextInputFormatter(80)],
              autofillHints: _isVendor ? null : const [AutofillHints.username, AutofillHints.email],
              autocorrect: false,
              decoration: InputDecoration(
                labelText: _isVendor ? 'Vendor ID (last 4 digits)' : 'Email / Employee ID',
                helperText: _isVendor ? 'Example: vendor ID 11001, enter 1001' : null,
                errorText: _identifierError,
                prefixIcon: Icon(_isVendor ? Icons.storefront_outlined : Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 14),
            if (_isVendor) ...[
              AuthButton(label: 'Continue', busy: busy, onPressed: _submit),
            ] else ...[
              CredentialSection(inputs: _credential, switchLabel: 'Use MPIN', enabled: !busy, onSubmit: _submit),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => LiveForgotScreen(initialIdentifier: _identifier.text.trim(), startWithMpin: _isAdmin || _credential.useMpin),
                          )),
                  child: Text(_isAdmin ? 'Set up / reset MPIN' : 'Forgot MPIN or password?'),
                ),
              ),
              AuthButton(label: 'Login', busy: busy, onPressed: _submit),
              // An administrator account is made on the web, never from the phone.
              if (_isAdmin)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Admin accounts are created on the web CRM. Already have one? Set your MPIN above, then sign in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AdinnColors.muted),
                  ),
                ),
              if (!_isAdmin)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('New here?'),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LiveRegisterScreen())),
                      child: const Text('Create an account'),
                    ),
                  ],
                ),
            ],
            const Divider(height: 28),
            Center(
              child: TextButton.icon(
                onPressed: busy ? null : context.read<LiveAuthController>().enterOfflineDemo,
                icon: const Icon(Icons.cloud_off_outlined, size: 18),
                label: const Text('Offline demo mode'),
                style: TextButton.styleFrom(foregroundColor: AdinnColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.label, required this.hint, required this.icon, required this.selected, required this.onTap});

  final String label;
  final String hint;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $hint',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AdinnColors.red : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AdinnColors.red : AdinnColors.line),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? Colors.white : AdinnColors.red),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.white : AdinnColors.ink)),
              Text(hint, style: TextStyle(fontSize: 11, color: selected ? Colors.white70 : AdinnColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
