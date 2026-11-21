import 'package:dio/dio.dart';

/// Normalised error from the backend or the network layer.
class ApiException implements Exception {
  const ApiException({required this.code, required this.message, this.statusCode, this.details = const []});

  static const networkCode = 'NETWORK_ERROR';
  static const unknownCode = 'UNKNOWN';

  /// Most detail lines added to the user message (the rest is summarised as "+N more").
  static const maxDetailsShown = 3;
  static const _maxDetailLength = 120;

  final String code;

  /// The text for the screen: the server message, followed by up to [maxDetailsShown] of its `error.details`.
  final String message;
  final int? statusCode;

  /// Every readable line of `error.details` (all of them, not only the ones appended to [message]).
  final List<String> details;

  bool get isNetwork => code == networkCode;

  /// True when the server definitively rejected the credentials/session.
  bool get isAuthRejection =>
      statusCode == 401 ||
      statusCode == 403 ||
      code == 'TOKEN_INVALID' ||
      code == 'REFRESH_INVALID' ||
      code == 'REFRESH_REUSED' ||
      code == 'REFRESH_EXPIRED';

  /// Envelope: `{success:false, message, error:{code, message, details}}`. The text is read from `error.message` (or the
  /// top-level `message`), so the server's own wording reaches the screen. `error.details` (a list of `{path, message}`
  /// or plain strings) tells the person WHAT is wrong, e.g. "Validation failed: craneRequired is not assessed".
  factory ApiException.fromBody(dynamic body, int? statusCode) {
    var code = unknownCode;
    var message = '';
    var details = const <_Detail>[];
    if (body is Map) {
      final err = body['error'];
      if (err is Map) {
        code = (err['code'] ?? unknownCode).toString();
        if (err['message'] != null) message = err['message'].toString();
        details = _readDetails(err['details']);
      }
      if (message.isEmpty && body['message'] != null) message = body['message'].toString();
    }
    if (message.isEmpty && details.isEmpty) {
      return ApiException(code: unknownCode, message: 'Request failed ($statusCode)', statusCode: statusCode);
    }
    if (message.isEmpty) message = 'Request failed ($statusCode)';
    return ApiException(
      code: code,
      message: _withDetails(message, details),
      statusCode: statusCode,
      details: [for (final d in details) d.text],
    );
  }

  factory ApiException.fromDio(DioException e) {
    final res = e.response;
    if (res == null) {
      return const ApiException(code: networkCode, message: 'Cannot reach the server. Check your connection.');
    }
    return ApiException.fromBody(res.data, res.statusCode);
  }

  /// Appends up to [maxDetailsShown] detail lines to [message]. A line the message already says is skipped
  /// (the backend often sends the same sentence as `message` and as the only detail).
  static String _withDetails(String message, List<_Detail> details) {
    final lower = message.toLowerCase();
    final fresh = <String>[];
    for (final d in details) {
      if (lower.contains(d.text.toLowerCase()) || lower.contains(d.raw.toLowerCase()) || fresh.contains(d.text)) continue;
      fresh.add(d.text);
    }
    if (fresh.isEmpty) return message;
    final shown = fresh.take(maxDetailsShown).join('; ');
    final more = fresh.length > maxDetailsShown ? ' (+${fresh.length - maxDetailsShown} more)' : '';
    return '$message: $shown$more';
  }

  /// `details` may be a list of `{path, message}`, a list of strings, a single map or a string. Anything else is ignored.
  static List<_Detail> _readDetails(dynamic raw) {
    final items = raw is List ? raw : (raw == null ? const [] : [raw]);
    final out = <_Detail>[];
    for (final item in items) {
      final d = _detail(item);
      if (d == null) continue;
      final text = d.text.length > _maxDetailLength ? '${d.text.substring(0, _maxDetailLength)}...' : d.text;
      out.add((text: text, raw: d.raw));
    }
    return out;
  }

  static _Detail? _detail(dynamic item) {
    if (item is String) return item.trim().isEmpty ? null : (text: item.trim(), raw: item.trim());
    if (item is! Map) return null;
    final msg = (item['message'] ?? '').toString().trim();
    final path = (item['path'] ?? '').toString().trim();
    if (msg.isEmpty) return null;
    if (path.isEmpty) return (text: msg, raw: msg);
    // "craneRequired is not assessed" already names its field; "Required" does not: then the path goes in front.
    final leaf = path.split('.').last.toLowerCase();
    return (text: msg.toLowerCase().contains(leaf) ? msg : '$path: $msg', raw: msg);
  }

  @override
  String toString() => 'ApiException($code, $message)';
}

/// One readable detail line; [raw] is the server's own sentence (without the field path in front).
typedef _Detail = ({String text, String raw});
