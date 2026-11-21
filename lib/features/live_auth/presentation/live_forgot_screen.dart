import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/input_formats.dart';
import '../domain/auth_models.dart';
import '../domain/auth_rules.dart';
import 'live_auth_controller.dart';
import 'live_auth_widgets.dart';

/// Forgot MPIN / password: email a 6-digit code, then set the new MPIN or password.
class LiveForgotScreen extends StatefulWidget {
  const LiveForgotScreen({super.key, this.initialIdentifier = '', this.startWithMpin = false});

  final String initialIdentifier;
  final bool startWithMpin;

  @override
  State<LiveForgotScreen> createState() => _LiveForgotScreenState();
}

class _LiveForgotScreenState extends State<LiveForgotScreen> {
  late final _identifier = TextEditingController(text: widget.initialIdentifier);
  final _code = TextEditingController();
  final _credential = CredentialInputs(create: true);

  bool _confirmStep = false;
  bool _busy = false;
  String? _identifierError;
  String? _codeError;
  String? _error;
  int _wait = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.startWithMpin) _credential.setUseMpin(true);
    _credential.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _identifier.dispose();
    _code.dispose();
    _credential.dispose();
    super.dispose();
  }

  LiveAuthController get _auth => context.read<LiveAuthController>();

  void _cooldown(int seconds) {
    _timer?.cancel();
    setState(() => _wait = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _wait <= 1) {
        t.cancel();
        if (mounted) setState(() => _wait = 0);
      } else {
        setState(() => _wait--);
      }
    });
  }

  String _message(Object e) => e is AuthFailure ? friendlyAuthMessage(e) : 'Something went wrong. Please try again.';

  Future<void> _send() async {
    if (_busy) return;
    final err = AuthRules.identifier(_identifier.text);
    setState(() => _identifierError = err);
    if (err != null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final wait = await _auth.requestResetCode(_identifier.text.trim());
      if (!mounted) return;
      setState(() => _confirmStep = true);
      _cooldown(wait);
      _snack('If this account exists, a code has been emailed.');
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit({bool confirmReuse = false}) async {
    if (_busy) return;
    final codeErr = AuthRules.resetCode(_code.text);
    final credOk = _credential.validate();
    setState(() => _codeError = codeErr);
    if (codeErr != null || !credOk) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.confirmReset(_identifier.text.trim(), _code.text, _credential.credential, confirmReuse: confirmReuse);
      if (!mounted) return;
      _snack('${_credential.useMpin ? 'MPIN' : 'Password'} updated. You can sign in now.');
      Navigator.of(context).pop();
    } on AuthFailure catch (e) {
      if (!mounted) return;
      if (e.code == 'CREDENTIAL_REUSED') {
        setState(() => _busy = false);
        final keep = await _askKeep();
        if (keep == true) await _submit(confirmReuse: true);
        return;
      }
      setState(() {
        _error = friendlyAuthMessage(e);
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _message(e);
          _busy = false;
        });
      }
    }
  }

  Future<bool?> _askKeep() {
    final what = _credential.useMpin ? 'MPIN' : 'password';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Same $what'),
        content: Text('This is your already used $what. Are you okay with keeping it?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, choose another')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, keep it')),
        ],
      ),
    );
  }

  void _changeEmail() {
    _code.clear();
    _credential.setUseMpin(_credential.useMpin);
    _timer?.cancel();
    setState(() {
      _confirmStep = false;
      _codeError = null;
      _error = null;
      _wait = 0;
    });
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final method = _credential.useMpin ? 'MPIN' : 'password';
    return LiveAuthScaffold(
      title: _confirmStep ? 'Set a new $method' : 'Forgot MPIN or password?',
      subtitle: _confirmStep
          ? 'Enter the 6-digit code emailed to the address linked to ${_identifier.text.trim().toLowerCase()}, then choose your new $method.'
          : 'Enter your email or employee ID. We will email a 6-digit code. No email on your account (some vendors)? Contact Recce Operations to reset your MPIN.',
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) AuthBanner(message: _error!),
          if (!_confirmStep) ...[
            TextField(
              controller: _identifier,
              enabled: !_busy,
              maxLength: 80,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(labelText: 'Email / Employee ID', errorText: _identifierError, counterText: '', prefixIcon: const Icon(Icons.mail_outline)),
            ),
            const SizedBox(height: 20),
            AuthButton(label: 'Send code', busy: _busy, onPressed: _send),
          ] else ...[
            TextField(
              controller: _code,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: digitsFormat(6),
              style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w700),
              decoration: InputDecoration(labelText: '6-digit code *', errorText: _codeError, prefixIcon: const Icon(Icons.verified_user_outlined)),
            ),
            const SizedBox(height: 14),
            CredentialSection(inputs: _credential, switchLabel: 'Use 4-digit MPIN', enabled: !_busy, onSubmit: _submit),
            const SizedBox(height: 18),
            AuthButton(label: 'Reset $method', busy: _busy, onPressed: _submit),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              children: [
                TextButton(onPressed: _busy ? null : _changeEmail, child: const Text('Change email')),
                TextButton(
                  onPressed: _busy || _wait > 0 ? null : _send,
                  child: Text(_wait > 0 ? 'Resend code in ${_wait}s' : 'Resend code'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
