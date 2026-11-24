/// Roles that sign in on the mobile app. Others (BD, Operations, ...) use the web CRM.
/// The administrator (SUPER_ADMIN) signs in on the phone only to manage the media catalog: see [AdminHomeShell].
enum LiveRole {
  recceExecutive('RECCE_EXECUTIVE', 'Recce Executive'),
  vendor('VENDOR', 'Vendor'),
  admin('SUPER_ADMIN', 'Administrator'),
  other('OTHER', 'Other');

  const LiveRole(this.code, this.label);
  final String code;
  final String label;

  static LiveRole parse(String? code) =>
      LiveRole.values.firstWhere((r) => r.code == code, orElse: () => LiveRole.other);

  /// Recce executives and vendors: the people who do the field work (shops, photos, chat).
  bool get isFieldStaff => this == LiveRole.recceExecutive || this == LiveRole.vendor;

  /// Every role the phone accepts at sign in: the field staff and the administrator.
  bool get signsInOnPhone => this != LiveRole.other;
}

/// The signed-in person as the backend returns it.
class LiveUser {
  const LiveUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
    this.vendorName,
    this.mustChangeMpin = false,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;
  final LiveRole role;
  final String? vendorName;

  /// Vendor login made by the office with a default MPIN: a new MPIN must be set first.
  final bool mustChangeMpin;

  /// The administrator: the phone shows the Media catalog screens instead of the field screens.
  bool get isAdmin => role == LiveRole.admin;

  factory LiveUser.fromJson(Map<String, dynamic> j) {
    final vendor = j['vendor'];
    return LiveUser(
      id: j['id'].toString(),
      name: (j['name'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      phone: j['phone']?.toString(),
      role: LiveRole.parse(j['role']?.toString()),
      vendorName: vendor is Map ? vendor['name']?.toString() : null,
      mustChangeMpin: (j['mustChangeMpin'] ?? j['mustChangeCredential']) == true,
    );
  }
}

/// A password or a 4-digit MPIN. Exactly one is sent, matching how the account was registered.
sealed class AuthCredential {
  const AuthCredential();

  /// Backend `authMethod` value.
  String get method;

  /// Fields merged into the request body (`password` or `mpin`).
  Map<String, String> toBody();
}

class PasswordCredential extends AuthCredential {
  const PasswordCredential(this.password);
  final String password;

  @override
  String get method => 'PASSWORD';

  @override
  Map<String, String> toBody() => {'password': password};
}

class MpinCredential extends AuthCredential {
  const MpinCredential(this.mpin);
  final String mpin;

  @override
  String get method => 'MPIN';

  @override
  Map<String, String> toBody() => {'mpin': mpin};
}

/// Failure surfaced to the UI. [code] is a backend error code or `NETWORK_ERROR` / `UNKNOWN`.
class AuthFailure implements Exception {
  const AuthFailure(this.code, [this.message = '']);
  final String code;
  final String message;

  @override
  String toString() => 'AuthFailure($code, $message)';
}

class RegisterRequest {
  const RegisterRequest({
    required this.name,
    required this.email,
    required this.phone,
    required this.employeeId,
    required this.role,
    required this.credential,
  });

  final String name;
  final String email;
  final String phone;
  final String employeeId;
  final LiveRole role;
  final AuthCredential credential;

  /// `POST /auth/register` body.
  Map<String, dynamic> toBody() => {
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'phone': phone,
        'employeeId': employeeId.trim(),
        'role': role.code,
        'platform': 'mobile',
        'authMethod': credential.method,
        ...credential.toBody(),
      };
}

/// Friendly text for a backend auth error code.
String friendlyAuthMessage(AuthFailure f) {
  switch (f.code) {
    case 'INVALID_CREDENTIALS':
      return 'Incorrect details. If you registered with an MPIN, switch on "Use MPIN".';
    case 'VENDOR_ID_AMBIGUOUS':
      return 'More than one vendor has these last 4 digits. Enter your full vendor ID.';
    case 'VENDOR_NOT_FOUND':
      return 'Vendor ID not found. Contact the office for your vendor ID.';
    case 'USER_NOT_FOUND':
      return 'User not found';
    case 'ACCOUNT_LOCKED':
      return 'Too many wrong attempts. Try again in 15 minutes or ask your administrator to reset your credential.';
    case 'PLATFORM_NOT_ALLOWED':
      return 'This account signs in on the web CRM, not the mobile app.';
    case 'INVALID_RESET_CODE':
      return 'The code is invalid or has expired. Request a new one.';
    case 'CONFLICT':
      return 'An account with this email or employee ID already exists.';
    case 'ACCOUNT_DISABLED':
      return 'Your account is disabled. Contact your administrator.';
    case 'VALIDATION_ERROR':
      return f.message.isNotEmpty ? f.message : 'Please check the details you entered.';
    case 'RATE_LIMITED':
      return 'Too many attempts. Please wait a minute and try again.';
    case 'NETWORK_ERROR':
      return 'Cannot reach the server. Check your connection and try again.';
    case 'TOKEN_INVALID':
    case 'REFRESH_INVALID':
    case 'REFRESH_REUSED':
    case 'REFRESH_EXPIRED':
      return 'Your session expired. Please sign in again.';
    default:
      return f.message.isNotEmpty ? f.message : 'Something went wrong. Please try again.';
  }
}
