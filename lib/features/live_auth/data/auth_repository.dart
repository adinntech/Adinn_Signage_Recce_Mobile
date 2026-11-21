// ignore_for_file: prefer_initializing_formals
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/token_manager.dart';
import '../../../core/storage/session_store.dart';
import '../domain/auth_models.dart';

class RestoredSession {
  const RestoredSession(this.user, {required this.offline});
  final LiveUser user;
  final bool offline;
}

/// All `/auth/*` calls. Maps transport errors to [AuthFailure].
class AuthRepository {
  AuthRepository({required Dio plainDio, required TokenManager tokens, required SessionStore store})
      : _dio = plainDio,
        _tokens = tokens,
        _store = store;

  final Dio _dio;
  final TokenManager _tokens;
  final SessionStore _store;

  Stream<void> get sessionExpired => _tokens.sessionExpired;

  LiveUser? _decode(String? json) {
    if (json == null) return null;
    try {
      return LiveUser.fromJson(Map<String, dynamic>.from(jsonDecode(json) as Map));
    } catch (_) {
      return null;
    }
  }

  /// Tries to resume a stored session. Null when there is none or it was rejected.
  /// Returns an offline session when the network is down (never logs out for that).
  Future<RestoredSession?> restore() async {
    final refresh = await _store.readRefreshToken();
    if (refresh == null) return null;
    final cached = _decode(await _store.readUserJson());
    try {
      final token = await _tokens.refresh();
      if (token == null) return null; // rejected; storage already cleared
      final fresh = _decode(await _store.readUserJson()) ?? cached;
      return fresh == null ? null : RestoredSession(fresh, offline: false);
    } on ApiException catch (e) {
      if (e.isNetwork || !e.isAuthRejection) {
        return cached == null ? null : RestoredSession(cached, offline: true);
      }
      return null;
    }
  }

  Future<Response<dynamic>> _post(String path, Map<String, dynamic> body, {bool authed = false}) async {
    try {
      return await _dio.post<dynamic>(
        path,
        data: body,
        options: authed && _tokens.accessToken != null
            ? Options(headers: {'Authorization': 'Bearer ${_tokens.accessToken}'})
            : null,
      );
    } on DioException catch (e) {
      final api = ApiException.fromDio(e);
      throw AuthFailure(api.code, api.message);
    }
  }

  Future<LiveUser> _signedIn(Response<dynamic> res) async {
    final payload = TokenPayload.fromEnvelope(res.data);
    await _tokens.persist(payload);
    return LiveUser.fromJson(payload.user);
  }

  /// [identifier] is an email or employee ID. [loginRole] is the card picked (`RECCE` or `VENDOR`).
  Future<LiveUser> login(String identifier, AuthCredential credential, {String? loginRole}) async => _signedIn(
        await _post('/auth/login', {
          'identifier': identifier.trim(),
          ...credential.toBody(),
          'loginRole': ?loginRole,
          'platform': 'mobile',
        }),
      );

  /// Vendor card: the last 4+ digits of the vendor ID are the whole sign-in.
  Future<LiveUser> vendorLogin(String vendorId) async =>
      _signedIn(await _post('/auth/vendor-login', {'vendorId': vendorId.trim()}));

  Future<LiveUser> register(RegisterRequest r) async => _signedIn(await _post('/auth/register', r.toBody()));

  /// Emails a 6-digit reset code. Returns the seconds to wait before a resend.
  Future<int> requestResetCode(String identifier) async {
    final res = await _post('/auth/forgot', {'identifier': identifier.trim().toLowerCase()});
    final data = res.data is Map ? (res.data as Map)['data'] : null;
    final wait = data is Map ? data['resendAfterSeconds'] : null;
    return wait is num ? wait.toInt() : 60;
  }

  /// Throws [AuthFailure] (`CREDENTIAL_REUSED` when the new value equals the current one and [confirmReuse] is false).
  Future<void> confirmReset(String identifier, String code, AuthCredential credential, {bool confirmReuse = false}) async {
    await _post('/auth/forgot/confirm', {
      'identifier': identifier.trim().toLowerCase(),
      'code': code,
      'authMethod': credential.method,
      'newSecret': credential.toBody().values.first,
      'confirmReuse': confirmReuse,
    });
  }

  /// Signed-in person sets a new MPIN. The server then ends every session, so the caller signs out.
  Future<void> changeOwnMpin(String currentMpin, String newMpin) async {
    await _post(
      '/users/me/change-credential',
      {'currentSecret': currentMpin, 'authMethod': 'MPIN', 'mpin': newMpin},
      authed: true,
    );
  }

  /// Best-effort server logout, then always clears local storage.
  Future<void> logout() async {
    final refresh = await _store.readRefreshToken();
    if (refresh != null) {
      try {
        await _post('/auth/logout', {'refreshToken': refresh}, authed: true);
      } catch (_) {
        // best effort
      }
    }
    await _tokens.clear();
  }
}
