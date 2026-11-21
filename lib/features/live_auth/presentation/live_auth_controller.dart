import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/auth_repository.dart';
import '../domain/auth_models.dart';

/// What the person reads when something unexpected (not a server answer) goes wrong while signing in.
const genericAuthMessage = 'Something went wrong. Please try again.';

/// Live (server) session state. Provider + ChangeNotifier, like the rest of the app.
class LiveAuthController extends ChangeNotifier {
  LiveAuthController(this._repo) {
    _sub = _repo.sessionExpired.listen((_) {
      _user = null;
      notifyListeners();
    });
  }

  final AuthRepository _repo;
  StreamSubscription<void>? _sub;

  bool _ready = false;
  bool _busy = false;
  bool _offlineDemo = false;
  bool _offlineSession = false;
  LiveUser? _user;
  AuthFailure? _error;

  bool get ready => _ready;
  bool get busy => _busy;
  LiveUser? get user => _user;
  AuthFailure? get error => _error;

  /// True when the stored session was resumed without reaching the server.
  bool get offlineSession => _offlineSession;

  /// The user chose the old offline prototype from the login screen.
  bool get offlineDemo => _offlineDemo;

  Future<void> restore() async {
    try {
      final s = await _repo.restore();
      if (s != null && s.user.role.isFieldStaff) {
        _user = s.user;
        _offlineSession = s.offline;
      }
    } catch (_) {
      _user = null; // secure storage unavailable (tests) or unexpected: show the login
    }
    _ready = true;
    notifyListeners();
  }

  void enterOfflineDemo() {
    _offlineDemo = true;
    notifyListeners();
  }

  void leaveOfflineDemo() {
    _offlineDemo = false;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<bool> _run(Future<LiveUser> Function() call) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final user = await call();
      if (!user.role.isFieldStaff) {
        await _repo.logout();
        _error = const AuthFailure('PLATFORM_NOT_ALLOWED');
        return false;
      }
      _user = user;
      _offlineSession = false;
      return true;
    } on AuthFailure catch (e) {
      _error = e;
      return false;
    } catch (e, st) {
      // Never show a raw exception on screen (it can name internals); the detail stays in the debug log.
      debugPrint('LiveAuthController: unexpected error: $e\n$st');
      _error = const AuthFailure('UNKNOWN', genericAuthMessage);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> login(String identifier, AuthCredential credential, {required String loginRole}) =>
      _run(() => _repo.login(identifier, credential, loginRole: loginRole));

  Future<bool> vendorLogin(String vendorId) => _run(() => _repo.vendorLogin(vendorId));

  Future<bool> register(RegisterRequest request) => _run(() => _repo.register(request));

  /// Forgot flow (no session change). Throws [AuthFailure].
  Future<int> requestResetCode(String identifier) => _repo.requestResetCode(identifier);

  Future<void> confirmReset(String identifier, String code, AuthCredential credential, {bool confirmReuse = false}) =>
      _repo.confirmReset(identifier, code, credential, confirmReuse: confirmReuse);

  /// New MPIN, then sign out: the server ended every session. Throws [AuthFailure].
  Future<void> changeMpin(String current, String next) async {
    await _repo.changeOwnMpin(current, next);
    await logout();
  }

  Future<void> logout() async {
    await _repo.logout();
    _user = null;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
