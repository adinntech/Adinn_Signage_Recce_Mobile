import 'package:dio/dio.dart';

import 'api_config.dart';
import 'token_manager.dart';

/// Normal calls send small JSON bodies: a stalled send fails after this.
const jsonSendTimeout = Duration(seconds: 30);

/// A photo upload is a big multipart body. Long enough for a slow mobile network, short enough that a stalled upload
/// fails by itself and frees its slot in the upload queue (the queue retries it).
const uploadSendTimeout = Duration(seconds: 90);

BaseOptions baseOptions() => BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    );

/// The send timeout for a request body: none without a body (Dio on the web warns when a GET has one), the long
/// upload timeout for multipart, the short one for JSON.
Duration? sendTimeoutFor(Object? body) => body == null ? null : (body is FormData ? uploadSendTimeout : jsonSendTimeout);

/// Sets [sendTimeoutFor] on every request that does not set its own.
class SendTimeoutInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.sendTimeout ??= sendTimeoutFor(options.data);
    handler.next(options);
  }
}

/// Dio without the auth interceptor; used for refresh and unauthenticated calls.
Dio createPlainDio() => Dio(baseOptions())..interceptors.add(SendTimeoutInterceptor());

/// Dio with Bearer attach + one-shot refresh-and-retry on 401.
Dio createAuthedDio(TokenManager tokens) {
  final dio = Dio(baseOptions())..interceptors.add(SendTimeoutInterceptor());
  dio.interceptors.add(AuthInterceptor(dio, tokens));
  return dio;
}

class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._dio, this._tokens);

  final Dio _dio;
  final TokenManager _tokens;
  static const _retriedKey = 'auth_retried';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _tokens.accessToken;
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    final isAuthPath = req.path.contains('/auth/login') || req.path.contains('/auth/refresh');
    if (err.response?.statusCode != 401 || isAuthPath || req.extra[_retriedKey] == true) {
      return handler.next(err);
    }
    try {
      final token = await _tokens.refresh();
      if (token == null) return handler.next(err);
      req.extra[_retriedKey] = true;
      req.headers['Authorization'] = 'Bearer $token';
      // A multipart body is a stream and cannot be re-sent here. The token is fresh now, so the upload queue treats this
      // 401 as retryable and sends the photo again itself (see UploadQueue).
      if (req.data is FormData) return handler.next(err);
      handler.resolve(await _dio.fetch<dynamic>(req));
    } on DioException catch (e) {
      handler.next(e);
    } catch (_) {
      // Refresh failed for network reasons: surface the original error, no logout.
      handler.next(err);
    }
  }
}
