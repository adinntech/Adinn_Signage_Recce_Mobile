import 'package:flutter/foundation.dart';

/// Build-time configuration of the live backend. Override with
/// `--dart-define=API_BASE_URL=https://host/api/v1` (a physical phone needs the
/// LAN address of the PC, e.g. http://192.168.1.74:4000/api/v1).
class ApiConfig {
  const ApiConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// Browser/desktop reach the backend on localhost; the Android emulator reaches
  /// the host PC through 10.0.2.2.
  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:4000/api/v1';
    }
    return 'http://localhost:4000/api/v1';
  }

  /// Sent with every photo so reviewers know which build captured it.
  static const String appLabel = 'Adinn Recce 1.0';
}
