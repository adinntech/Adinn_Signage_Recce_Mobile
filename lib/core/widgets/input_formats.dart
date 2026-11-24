import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What a person may type into a field. Anything else is dropped as they type or paste, so a letter never
/// appears in a phone number and a number never runs past its length. The backend checks the same rules again.

/// Mobile number: digits only, at most 10 (the fixed +91 is drawn by [PhonePrefix], never typed or stored).
final List<TextInputFormatter> phoneFormat = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(10),
];

/// Whole number, optionally limited in length (a quantity, a code).
List<TextInputFormatter> digitsFormat([int? max]) => [
      FilteringTextInputFormatter.digitsOnly,
      if (max != null) LengthLimitingTextInputFormatter(max),
    ];

/// A size or an amount: digits and one dot, at most [places] decimals and [maxLength] characters.
List<TextInputFormatter> decimalFormat({int places = 2, int maxLength = 9}) => [
      FilteringTextInputFormatter.allow(RegExp('^\\d*\\.?\\d{0,$places}')),
      LengthLimitingTextInputFormatter(maxLength),
    ];

/// A code or key the administrator types (media code GSB_2D, installation code wall_mount, question key fascia_material): letters,
/// digits and `_` only, at most [max], changed to capitals ([upper]) or small letters as it is typed.
List<TextInputFormatter> codeFormat({required int max, bool upper = false}) => [
      FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_]')),
      TextInputFormatter.withFunction((o, n) => n.copyWith(text: upper ? n.text.toUpperCase() : n.text.toLowerCase())),
      LengthLimitingTextInputFormatter(max),
    ];

/// Free text the administrator types (a name, a label, an option): no `<` or `>` and no control characters, at most [max].
List<TextInputFormatter> safeTextFormat(int max) => [
      FilteringTextInputFormatter.deny(RegExp(r'[<>\u0000-\u001f]')),
      LengthLimitingTextInputFormatter(max),
    ];

/// The country code shown inside every mobile number box (not typed, not part of the value).
const String phonePrefix = '+91 ';

/// A stored 10-digit mobile number shown with its country code: "+91 9876543210".
/// Blank stays blank, an existing +91 is not doubled.
String showMobile(String? raw) {
  var d = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('91')) {
    d = d.substring(2);
  } else if (d.length == 11 && d.startsWith('0')) {
    d = d.substring(1);
  }
  return d.isEmpty ? '' : '$phonePrefix$d';
}

/// The "+91" chip at the left edge of every mobile number box. Use as `prefixIcon: const PhonePrefix()`.
class PhonePrefix extends StatelessWidget {
  const PhonePrefix({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.06),
          border: Border(right: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Text('+91', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
      ),
    );
  }
}
