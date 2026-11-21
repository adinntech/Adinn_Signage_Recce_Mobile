import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/input_formats.dart';
import '../domain/auth_models.dart';
import '../domain/auth_rules.dart';
import 'live_auth_controller.dart';
import 'live_auth_widgets.dart';

/// Create account: name, email, phone (+91 fixed, 10 digits), employee ID, role, MPIN or password.
class LiveRegisterScreen extends StatefulWidget {
  const LiveRegisterScreen({super.key});

  @override
  State<LiveRegisterScreen> createState() => _LiveRegisterScreenState();
}

class _LiveRegisterScreenState extends State<LiveRegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _employeeId = TextEditingController();
  final _credential = CredentialInputs(create: true);
  LiveRole _role = LiveRole.recceExecutive;
  final _errors = <String, String?>{};

  @override
  void initState() {
    super.initState();
    context.read<LiveAuthController>().clearError();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _employeeId.dispose();
    _credential.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<LiveAuthController>();
    if (auth.busy) return;
    setState(() {
      _errors['name'] = AuthRules.name(_name.text);
      _errors['email'] = AuthRules.email(_email.text);
      _errors['phone'] = AuthRules.phone(_phone.text);
      _errors['employeeId'] = AuthRules.employeeId(_employeeId.text);
    });
    final credOk = _credential.validate();
    if (_errors.values.any((e) => e != null) || !credOk) return;
    FocusScope.of(context).unfocus();
    final ok = await auth.register(RegisterRequest(
      name: _name.text,
      email: _email.text,
      phone: _phone.text.trim(),
      employeeId: _employeeId.text,
      role: _role,
      credential: _credential.credential,
    ));
    if (ok && mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<LiveAuthController>();
    final busy = auth.busy;
    return LiveAuthScaffold(
      title: 'Create account',
      subtitle: 'Register to receive and complete shop recces',
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (auth.error != null) AuthBanner(message: friendlyAuthMessage(auth.error!)),
          SegmentedButton<LiveRole>(
            segments: const [
              ButtonSegment(value: LiveRole.recceExecutive, label: Text('Recce'), icon: Icon(Icons.travel_explore)),
              ButtonSegment(value: LiveRole.vendor, label: Text('Vendor'), icon: Icon(Icons.storefront_outlined)),
            ],
            selected: {_role},
            onSelectionChanged: busy ? null : (s) => setState(() => _role = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            enabled: !busy,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[0-9<>]'))],
            decoration: InputDecoration(labelText: 'Full name *', errorText: _errors['name'], counterText: '', prefixIcon: const Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _email,
            enabled: !busy,
            maxLength: 80,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            decoration: InputDecoration(labelText: 'Email *', errorText: _errors['email'], counterText: '', prefixIcon: const Icon(Icons.mail_outline)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phone,
            enabled: !busy,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            inputFormatters: phoneFormat,
            decoration: InputDecoration(
              labelText: 'Phone number *',
              hintText: '10 digits',
              errorText: _errors['phone'],
              prefixIcon: const PhonePrefix(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _employeeId,
            enabled: !busy,
            maxLength: 30,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._-]'))],
            decoration: InputDecoration(labelText: 'Employee ID *', errorText: _errors['employeeId'], counterText: '', prefixIcon: const Icon(Icons.badge_outlined)),
          ),
          const SizedBox(height: 10),
          CredentialSection(inputs: _credential, switchLabel: 'Use 4-digit MPIN instead of a password', enabled: !busy),
          const SizedBox(height: 18),
          AuthButton(label: 'Create account', busy: busy, onPressed: _submit),
        ],
      ),
    );
  }
}
