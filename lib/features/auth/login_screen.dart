import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/mock/mock_seed.dart';
import '../../state/app_controller.dart';
import 'forgot_pin_screen.dart';

/// PIN-only login: the user types their 4-digit PIN on a keypad and is
/// logged in automatically after the 4th digit.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  static const _length = 4;

  String _pin = '';
  String? _error;
  bool _busy = false;
  Timer? _lockTicker;
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    _startLockTickerIfNeeded();
  }

  @override
  void dispose() {
    _lockTicker?.cancel();
    _shake.dispose();
    super.dispose();
  }

  Duration? get _lockLeft => context.read<AppController>().pinLockRemaining;

  void _startLockTickerIfNeeded() {
    _lockTicker?.cancel();
    if (context.read<AppController>().pinLockRemaining == null) return;
    _lockTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_lockLeft == null) {
        t.cancel();
        setState(() => _error = null);
      } else {
        setState(() {});
      }
    });
  }

  void _press(String digit) {
    if (_busy || _pin.length >= _length || _lockLeft != null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == _length) _submit();
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit([String? pin]) async {
    final value = pin ?? _pin;
    setState(() {
      _busy = true;
      _pin = value;
    });
    // Let the 4th dot render before switching screens.
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    final err = context.read<AppController>().loginWithPin(value);
    if (!mounted) return;
    if (err == null) return; // RootGate swaps to the home shell.
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    setState(() {
      _busy = false;
      _pin = '';
      _error = err;
    });
    _startLockTickerIfNeeded();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = e.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      _press(ch);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final lockLeft = context.watch<AppController>().pinLockRemaining;
    final message = lockLeft != null
        ? 'Too many wrong attempts. Try again in ${lockLeft.inSeconds + 1}s.'
        : _error;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const AdinnLogo(size: 40),
                          const SizedBox(height: 8),
                          const Text(
                            'Signage Board Recce',
                            style: TextStyle(
                              fontSize: 15,
                              color: AdinnColors.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            'Enter your 4-digit PIN',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 20),
                          AnimatedBuilder(
                            animation: _shake,
                            builder: (context, child) => Transform.translate(
                              offset: Offset(
                                math.sin(_shake.value * math.pi * 6) *
                                    12 *
                                    (1 - _shake.value),
                                0,
                              ),
                              child: child,
                            ),
                            child: _PinDots(
                              filled: _pin.length,
                              length: _length,
                              error: message != null,
                            ),
                          ),
                          SizedBox(
                            height: 44,
                            child: Center(
                              child: _busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : message == null
                                  ? null
                                  : Text(
                                      message,
                                      key: const Key('login_error'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AdinnColors.redDark,
                                        fontSize: 13,
                                      ),
                                    ),
                            ),
                          ),
                          _Keypad(
                            enabled: !_busy && lockLeft == null,
                            onDigit: _press,
                            onBackspace: _backspace,
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const ForgotPinScreen(),
                              ),
                            ),
                            child: const Text('Forgot PIN?'),
                          ),
                          const SizedBox(height: 12),
                          _DemoPins(
                            enabled: !_busy && lockLeft == null,
                            onPick: _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.filled,
    required this.length,
    required this.error,
  });

  final int filled;
  final int length;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$filled of $length digits entered',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? AdinnColors.red : Colors.transparent,
                border: Border.all(
                  color: error
                      ? AdinnColors.redDark
                      : (i < filled ? AdinnColors.red : AdinnColors.muted),
                  width: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    Widget key(String d) => _KeyButton(
      key: Key('pin_key_$d'),
      onTap: enabled ? () => onDigit(d) : null,
      child: Text(
        d,
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
      ),
    );

    Widget row(List<Widget> children) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: children,
      ),
    );

    return Column(
      children: [
        row([key('1'), key('2'), key('3')]),
        row([key('4'), key('5'), key('6')]),
        row([key('7'), key('8'), key('9')]),
        row([
          const SizedBox(width: 72, height: 72),
          key('0'),
          _KeyButton(
            key: const Key('pin_backspace'),
            onTap: enabled ? onBackspace : null,
            filled: false,
            child: const Icon(
              Icons.backspace_outlined,
              semanticLabel: 'Delete',
            ),
          ),
        ]),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    super.key,
    required this.child,
    required this.onTap,
    this.filled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AdinnColors.canvas : Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: IconTheme.merge(
              data: const IconThemeData(color: AdinnColors.ink),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: onTap == null ? AdinnColors.muted : AdinnColors.ink,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoPins extends StatelessWidget {
  const _DemoPins({required this.enabled, required this.onPick});

  final bool enabled;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    Widget chip(String role, String pin, IconData icon) => ActionChip(
      key: Key('demo_pin_$pin'),
      avatar: Icon(icon, size: 16, color: AdinnColors.red),
      label: Text('$role • $pin'),
      onPressed: enabled ? () => onPick(pin) : null,
    );

    return Column(
      children: [
        const Text(
          'DEMO PINS (tap to log in)',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.8,
            color: AdinnColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            chip('Vendor', DemoAccounts.vendorPin, Icons.engineering_outlined),
            chip(
              'Business',
              DemoAccounts.businessPin,
              Icons.business_center_outlined,
            ),
            chip('Ops', DemoAccounts.opsPin, Icons.fact_check_outlined),
          ],
        ),
      ],
    );
  }
}
