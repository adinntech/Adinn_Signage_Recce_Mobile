/// Field rules for sign in and registration. Mirrors the backend
/// (common/validators/credentials.ts); the backend stays authoritative.
/// Phone: the +91 is fixed in the box, the person types exactly 10 digits starting 6-9.
class AuthRules {
  const AuthRules._();

  static const _weakMpins = {
    '0000', '1111', '2222', '3333', '4444', '5555', '6666', '7777', '8888', '9999', '1234', '4321', '0123', '3210', //
  };

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _employeeId = RegExp(r'^[A-Za-z0-9._-]{2,30}$');
  static final _phone = RegExp(r'^[6-9]\d{9}$');
  static final _fourDigits = RegExp(r'^\d{4}$');

  static bool hasMinLength(String v) => v.length >= 8;
  static bool hasLetter(String v) => RegExp(r'[A-Za-z]').hasMatch(v);
  static bool hasDigit(String v) => RegExp(r'\d').hasMatch(v);

  static String? identifier(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Enter your email or employee ID';
    if (s.contains('@')) return _email.hasMatch(s) ? null : 'Enter a valid email';
    return _employeeId.hasMatch(s) ? null : 'Enter a valid employee ID';
  }

  /// Vendor card: the last 4 digits of the vendor ID, or the full ID (4 to 10 digits).
  static String? vendorId(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Enter the last 4 digits of your vendor ID';
    return RegExp(r'^\d{4,10}$').hasMatch(s) ? null : 'Enter the last 4 digits of your vendor ID';
  }

  static String? name(String? v) => (v?.trim().length ?? 0) < 2 ? 'Enter your full name' : null;

  static String? email(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Enter your email';
    return _email.hasMatch(s) ? null : 'Enter a valid email';
  }

  static String? employeeId(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Enter your employee ID';
    return _employeeId.hasMatch(s) ? null : 'Enter a valid employee ID';
  }

  /// Exactly 10 digits, first digit 6-9 (the +91 is not part of the value).
  static String? phone(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Enter your phone number';
    if (!RegExp(r'^\d{10}$').hasMatch(s)) return 'Phone number must be exactly 10 digits';
    return _phone.hasMatch(s) ? null : 'Phone number must start with 6, 7, 8 or 9';
  }

  static String? newPassword(String v) {
    if (!hasMinLength(v)) return 'Password needs at least 8 characters';
    if (!hasLetter(v)) return 'Password needs a letter';
    if (!hasDigit(v)) return 'Password needs a number';
    return null;
  }

  /// Sign in only needs 4 digits.
  static String? signInMpin(String v) => _fourDigits.hasMatch(v) ? null : 'Enter your 4-digit MPIN';

  /// Registration also rejects trivial MPINs.
  static String? newMpin(String v) {
    if (!_fourDigits.hasMatch(v)) return 'MPIN must be exactly 4 digits';
    if (_weakMpins.contains(v)) return 'Choose a less obvious MPIN';
    return null;
  }

  static String? resetCode(String v) => RegExp(r'^\d{6}$').hasMatch(v) ? null : 'Enter the 6-digit code from the email';
}
