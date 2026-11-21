import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/auth_models.dart';
import '../domain/auth_rules.dart';
import 'live_auth_controller.dart';
import 'live_auth_widgets.dart';

/// Shown right after a vendor signs in with the default MPIN set by the office: nothing else is reachable
/// until a new MPIN is chosen. The server then ends every session and the vendor signs in again.
class LiveChangeMpinScreen extends StatefulWidget {
  const LiveChangeMpinScreen({super.key});

  @override
  State<LiveChangeMpinScreen> createState() => _LiveChangeMpinScreenState();
}

class _LiveChangeMpinScreenState extends State<LiveChangeMpinScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _currentError;
  String? _nextError;
  String? _confirmError;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final cur = _current.text;
    final nxt = _next.text;
    setState(() {
      _currentError = AuthRules.signInMpin(cur);
      _nextError = AuthRules.newMpin(nxt) ?? (nxt == cur ? 'Choose a different MPIN from the current one' : null);
      _confirmError = _confirm.text == nxt ? null : 'MPINs do not match';
    });
    if (_currentError != null || _nextError != null || _confirmError != null) return;
    setState(() => _busy = true);
    final auth = context.read<LiveAuthController>();
    try {
      await auth.changeMpin(cur, nxt); // signs out; the gate shows the login
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e.code == 'INVALID_CREDENTIALS') {
          _currentError = 'Current MPIN is incorrect';
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyAuthMessage(e))));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LiveAuthScaffold(
      title: 'Set your MPIN',
      subtitle: 'For safety, replace the default MPIN before you continue',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Your default MPIN is the last 4 digits of your vendor ID.'),
          const SizedBox(height: 18),
          MpinField(controller: _current, label: 'Current (default) MPIN', errorText: _currentError, enabled: !_busy, autofocus: true),
          const SizedBox(height: 14),
          MpinField(controller: _next, label: 'New 4-digit MPIN', errorText: _nextError, enabled: !_busy),
          const SizedBox(height: 14),
          MpinField(controller: _confirm, label: 'Confirm new MPIN', errorText: _confirmError, enabled: !_busy, onCompleted: _submit),
          const SizedBox(height: 20),
          AuthButton(label: 'Save MPIN', busy: _busy, onPressed: _submit),
          TextButton(
            onPressed: _busy ? null : () => context.read<LiveAuthController>().logout(),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
