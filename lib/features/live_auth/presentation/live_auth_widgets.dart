import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../domain/auth_models.dart';
import '../domain/auth_rules.dart';

/// Page frame for every sign-in screen: logo, title, one white card (same look as the other Adinn screens).
class LiveAuthScaffold extends StatelessWidget {
  const LiveAuthScaffold({super.key, required this.title, this.subtitle, required this.child, this.showBack = false});

  final String title;
  final String? subtitle;
  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdinnColors.canvas,
      appBar: showBack ? AppBar(backgroundColor: AdinnColors.canvas, scrolledUnderElevation: 0) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AdinnLogo(size: 38)),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text('Signage Board Recce', style: TextStyle(color: AdinnColors.muted, fontSize: 14)),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(subtitle!, style: const TextStyle(color: AdinnColors.muted)),
                          ],
                          const SizedBox(height: 18),
                          child,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthBanner extends StatelessWidget {
  const AuthBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdinnColors.redLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdinnColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AdinnColors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: AdinnColors.redDark))),
        ],
      ),
    );
  }
}

class AuthButton extends StatelessWidget {
  const AuthButton({super.key, required this.label, required this.busy, required this.onPressed});
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
          : Text(label),
    );
  }
}

/// Four MPIN boxes driven by one invisible numeric field, so the keyboard, paste and backspace work natively.
/// Digits only, never longer than 4, hidden while typing (same look as the web login).
class MpinField extends StatefulWidget {
  const MpinField({
    super.key,
    required this.controller,
    required this.label,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.onCompleted,
  });

  final TextEditingController controller;
  final String label;
  final String? errorText;
  final bool enabled;
  final bool autofocus;
  final VoidCallback? onCompleted;

  @override
  State<MpinField> createState() => _MpinFieldState();
}

class _MpinFieldState extends State<MpinField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_rebuild);
    widget.controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;
    final hasError = widget.errorText != null;
    return Semantics(
      label: '${widget.label}, ${value.length} of 4 digits entered',
      textField: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w700, color: AdinnColors.ink, fontSize: 13)),
          const SizedBox(height: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled ? _focus.requestFocus : null,
            child: Stack(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(4, (i) {
                  final filled = i < value.length;
                  final active = _focus.hasFocus && i == value.length.clamp(0, 3);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: filled ? AdinnColors.redLight : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: hasError ? AdinnColors.red : (active || filled ? AdinnColors.red : AdinnColors.line),
                        width: active || hasError ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 140),
                      scale: filled ? 1 : 0,
                      child: const Icon(Icons.circle, size: 16, color: AdinnColors.ink),
                    ),
                  );
                }),
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    autofocus: widget.autofocus,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    showCursor: false,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    onChanged: (v) {
                      if (v.length == 4) widget.onCompleted?.call();
                    },
                  ),
                ),
              ),
            ]),
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(widget.errorText!, style: const TextStyle(color: AdinnColors.red, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// State of the password-or-MPIN block shared by sign in, register and the reset flow.
class CredentialInputs extends ChangeNotifier {
  CredentialInputs({required this.create});

  /// true = new credential (strength rules + confirmation); false = sign in.
  final bool create;

  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final mpin = TextEditingController();
  final confirmMpin = TextEditingController();

  bool useMpin = false;
  String? passwordError;
  String? confirmError;
  String? mpinError;
  String? confirmMpinError;

  void setUseMpin(bool v) {
    useMpin = v;
    for (final c in [password, confirmPassword, mpin, confirmMpin]) {
      c.clear();
    }
    passwordError = confirmError = mpinError = confirmMpinError = null;
    notifyListeners();
  }

  /// Returns true when valid; otherwise sets the field errors and notifies.
  bool validate() {
    passwordError = confirmError = mpinError = confirmMpinError = null;
    if (useMpin) {
      mpinError = create ? AuthRules.newMpin(mpin.text) : AuthRules.signInMpin(mpin.text);
      if (create && mpinError == null && confirmMpin.text != mpin.text) confirmMpinError = 'MPINs do not match';
    } else {
      final p = password.text;
      if (p.isEmpty) {
        passwordError = 'Enter your password';
      } else if (create) {
        passwordError = AuthRules.newPassword(p);
        if (passwordError == null && confirmPassword.text != p) confirmError = 'Passwords do not match';
      }
    }
    notifyListeners();
    return passwordError == null && confirmError == null && mpinError == null && confirmMpinError == null;
  }

  AuthCredential get credential => useMpin ? MpinCredential(mpin.text) : PasswordCredential(password.text);

  @override
  void dispose() {
    password.dispose();
    confirmPassword.dispose();
    mpin.dispose();
    confirmMpin.dispose();
    super.dispose();
  }
}

class CredentialSection extends StatefulWidget {
  const CredentialSection({super.key, required this.inputs, required this.switchLabel, this.enabled = true, this.onSubmit});

  final CredentialInputs inputs;
  final String switchLabel;
  final bool enabled;
  final VoidCallback? onSubmit;

  @override
  State<CredentialSection> createState() => _CredentialSectionState();
}

class _CredentialSectionState extends State<CredentialSection> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.inputs,
      builder: (context, _) {
        final i = widget.inputs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: i.useMpin,
              onChanged: widget.enabled ? i.setUseMpin : null,
              title: Text(widget.switchLabel),
            ),
            const SizedBox(height: 8),
            if (i.useMpin) ...[
              MpinField(
                controller: i.mpin,
                label: i.create ? 'New 4-digit MPIN' : '4-digit MPIN',
                errorText: i.mpinError,
                enabled: widget.enabled,
                onCompleted: i.create ? null : widget.onSubmit,
              ),
              if (i.create) ...[
                const SizedBox(height: 14),
                MpinField(controller: i.confirmMpin, label: 'Confirm MPIN', errorText: i.confirmMpinError, enabled: widget.enabled),
              ],
            ] else ...[
              TextField(
                controller: i.password,
                enabled: widget.enabled,
                obscureText: _obscure,
                maxLength: 64,
                autofillHints: const [AutofillHints.password],
                textInputAction: i.create ? TextInputAction.next : TextInputAction.done,
                onSubmitted: i.create ? null : (_) => widget.onSubmit?.call(),
                decoration: InputDecoration(
                  labelText: i.create ? 'New password' : 'Password',
                  helperText: i.create ? 'At least 8 characters with a letter and a number' : null,
                  errorText: i.passwordError,
                  counterText: '',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (i.create) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: i.confirmPassword,
                  enabled: widget.enabled,
                  obscureText: _obscure,
                  maxLength: 64,
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    errorText: i.confirmError,
                    counterText: '',
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}
