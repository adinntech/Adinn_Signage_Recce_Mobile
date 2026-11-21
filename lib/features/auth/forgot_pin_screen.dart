import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../state/app_controller.dart';

/// Three-step dummy OTP reset: registered mobile → verify OTP → new PIN.
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key});

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  int _step = 0;
  final _mobileCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pin2Ctrl = TextEditingController();
  String? _sentOtp;
  String? _maskedMobile;
  String? _error;

  @override
  void dispose() {
    _mobileCtrl.dispose();
    _otpCtrl.dispose();
    _pinCtrl.dispose();
    _pin2Ctrl.dispose();
    super.dispose();
  }

  void _sendOtp() {
    final mobile = _mobileCtrl.text.trim();
    if (mobile.length != 10) {
      setState(() => _error = 'Enter your 10-digit registered mobile number');
      return;
    }
    final otp = context.read<AppController>().requestOtp(mobile);
    if (otp == null) {
      setState(() => _error = 'This mobile number is not registered');
      return;
    }
    setState(() {
      _sentOtp = otp;
      _maskedMobile = '••••••${mobile.substring(6)}';
      _error = null;
      _step = 1;
    });
  }

  void _verify() {
    final ok = context.read<AppController>().verifyOtp(_otpCtrl.text);
    setState(() {
      _error = ok ? null : 'Invalid OTP. Please check and retry.';
      if (ok) _step = 2;
    });
  }

  void _reset() {
    if (_pinCtrl.text != _pin2Ctrl.text) {
      setState(() => _error = 'PINs do not match');
      return;
    }
    final err = context.read<AppController>().resetPin(_pinCtrl.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    showSnack(context, 'PIN reset successfully. Log in with your new PIN.');
    Navigator.of(context).pop();
  }

  void _onContinue() {
    switch (_step) {
      case 0:
        _sendOtp();
      case 1:
        _verify();
      case 2:
        _reset();
    }
  }

  InputDecoration _pinDecoration(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        counterText: '',
      );

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot PIN')),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Container(
                key: const Key('forgot_error'),
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AdinnColors.redLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AdinnColors.redDark),
                ),
              ),
            Expanded(
              child: Stepper(
                currentStep: _step,
                onStepContinue: _onContinue,
                onStepCancel: _step == 0
                    ? () => Navigator.of(context).pop()
                    : () => setState(() {
                        _step--;
                        _error = null;
                      }),
                controlsBuilder: (context, details) => details.isActive
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            FilledButton(
                              onPressed: details.onStepContinue,
                              child: Text(
                                const [
                                  'SEND OTP',
                                  'VERIFY',
                                  'SET NEW PIN',
                                ][details.stepIndex],
                              ),
                            ),
                            TextButton(
                              onPressed: details.onStepCancel,
                              child: Text(
                                details.stepIndex == 0 ? 'CANCEL' : 'BACK',
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
                steps: [
                  Step(
                    title: const Text('Registered mobile'),
                    subtitle: const Text('We will send an OTP'),
                    isActive: _step >= 0,
                    state: _step > 0 ? StepState.complete : StepState.indexed,
                    content: TextField(
                      key: const Key('forgot_mobile'),
                      controller: _mobileCtrl,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: digits,
                      decoration: const InputDecoration(
                        labelText: 'Mobile number',
                        prefixIcon: Icon(Icons.phone_android),
                        counterText: '',
                      ),
                    ),
                  ),
                  Step(
                    title: const Text('Verify OTP'),
                    isActive: _step >= 1,
                    state: _step > 1 ? StepState.complete : StepState.indexed,
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'OTP sent to ${_maskedMobile ?? 'your mobile'}.',
                          style: const TextStyle(color: AdinnColors.muted),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Demo mode – no SMS is sent. Use OTP: '
                            '${_sentOtp ?? '—'}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('forgot_otp'),
                          controller: _otpCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          inputFormatters: digits,
                          decoration: const InputDecoration(
                            labelText: '6-digit OTP',
                            prefixIcon: Icon(Icons.sms_outlined),
                            counterText: '',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Step(
                    title: const Text('Set new PIN'),
                    subtitle: const Text('4 digits, unique to you'),
                    isActive: _step >= 2,
                    content: Column(
                      children: [
                        TextField(
                          key: const Key('forgot_pin1'),
                          controller: _pinCtrl,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          inputFormatters: digits,
                          decoration: _pinDecoration(
                            'New 4-digit PIN',
                            Icons.pin_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('forgot_pin2'),
                          controller: _pin2Ctrl,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          inputFormatters: digits,
                          decoration: _pinDecoration(
                            'Confirm PIN',
                            Icons.lock_reset,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
