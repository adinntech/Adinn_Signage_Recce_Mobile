import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_exception.dart';
import 'recce_api.dart';

/// Whether a failed upload fixes itself later: no answer (network), 5xx, 408 and 401. A 401 means the token expired; the
/// auth interceptor refreshed it but cannot re-send a multipart body, so the queue sends the photo again. Any other 4xx
/// (wrong state, invalid file) will not fix itself and waits for the person.
bool uploadErrorRetryable(int? statusCode) => statusCode == null || statusCode >= 500 || statusCode == 408 || statusCode == 401;

/// Deletes the phone's own copy of a photo (mobile only; a browser has no file of ours). Never throws.
void deleteLocalCopy(String path) {
  if (kIsWeb) return;
  try {
    File(path).deleteSync();
  } catch (_) {
    // already gone, or in use: nothing more to do
  }
}

/// Upload queue: at most [maxParallel] uploads at once, progress, retry, cancel. It is saved on the phone, so photos taken
/// without network (or when the app is closed) go up later. A failed upload is never dropped: it stays listed with its reason.
class UploadQueue extends ChangeNotifier {
  UploadQueue(this._api, {Future<SharedPreferences> Function()? prefs, bool autoRetry = true})
      : _prefs = prefs ?? SharedPreferences.getInstance {
    if (autoRetry) _timer = Timer.periodic(const Duration(seconds: 30), (_) => _retryNetworkFailures());
  }

  static const maxParallel = 2;
  static const _key = 'live_recce_upload_queue_v1';

  final RecceApi _api;
  final Future<SharedPreferences> Function() _prefs;
  final Map<String, CancelToken> _tokens = {};

  /// Photos that already got their one immediate re-send after a 401 (cleared on any other outcome).
  final Set<String> _authRetried = {};
  final _uploaded = StreamController<String>.broadcast();
  Timer? _timer;
  var _items = <UploadItem>[];
  var _disposed = false;

  List<UploadItem> get items => List.unmodifiable(_items);

  /// Emits the siteId whenever the server stored a photo of that shop (screens reload their detail).
  Stream<String> get uploaded => _uploaded.stream;

  List<UploadItem> forShop(String siteId) => _items.where((u) => u.siteId == siteId).toList();
  int pendingCount(String siteId) => _items.where((u) => u.siteId == siteId).length;
  int get totalPending => _items.length;

  Future<void> load() async {
    if (kIsWeb) return; // browser file addresses do not survive a reload
    try {
      final raw = (await _prefs()).getString(_key);
      if (raw == null) return;
      final saved = (jsonDecode(raw) as List)
          .map((e) => UploadItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((u) => File(u.path).existsSync())
          .toList();
      _items = [...saved, ..._items.where((n) => !saved.any((s) => s.id == n.id))];
      _changed();
      _pump();
    } catch (_) {
      // storage unavailable: start with an empty queue
    }
  }

  Future<void> _save() async {
    try {
      await (await _prefs()).setString(_key, jsonEncode(_items.map((u) => u.toJson()).toList()));
    } catch (_) {
      // best effort
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// What the 30 s timer does, callable by a test without waiting.
  @visibleForTesting
  void retryFailedNow() => _retryNetworkFailures();

  void _retryNetworkFailures() {
    var any = false;
    for (final u in _items) {
      if (u.status == UploadStatus.failed && u.retryable) {
        u.status = UploadStatus.queued;
        any = true;
      }
    }
    if (any) _changed();
    _pump();
  }

  void add(UploadItem u) {
    if (_items.any((x) => x.id == u.id)) return; // the same capture is never queued twice
    _items = [..._items, u];
    unawaited(_save());
    _changed();
    _pump();
  }

  void retry(String id) {
    _authRetried.remove(id); // a person's Retry starts fresh: a 401 gets its immediate re-send again
    for (final u in _items) {
      if (u.id == id) {
        u.status = UploadStatus.queued;
        u.error = null;
      }
    }
    _changed();
    _pump();
  }

  /// Cancels one waiting or running upload, forgets it and deletes the phone's copy of the photo.
  void cancel(String id) {
    _tokens.remove(id)?.cancel('cancelled');
    _authRetried.remove(id);
    for (final u in _items.where((u) => u.id == id)) {
      deleteLocalCopy(u.path);
    }
    _items = _items.where((u) => u.id != id).toList();
    unawaited(_save());
    _changed();
  }

  /// Forgets everything (sign out). Running uploads are cancelled and every local copy is deleted.
  Future<void> clearAll() async {
    for (final t in _tokens.values) {
      t.cancel('signed out');
    }
    _tokens.clear();
    _authRetried.clear();
    final old = _items;
    _items = [];
    for (final u in old) {
      deleteLocalCopy(u.path);
    }
    await _save();
    _changed();
  }

  void _pump() {
    if (_disposed) return;
    final running = _items.where((u) => u.status == UploadStatus.uploading).length;
    var free = maxParallel - running;
    for (final u in _items.where((u) => u.status == UploadStatus.queued).toList()) {
      if (free <= 0) break;
      free--;
      unawaited(_run(u));
    }
  }

  void _remove(UploadItem u, {bool deleteFile = false}) {
    _items = _items.where((x) => x.id != u.id).toList();
    _authRetried.remove(u.id);
    unawaited(_save());
    if (deleteFile) deleteLocalCopy(u.path); // our own copy; the server has the photo now
    _changed();
  }

  Future<void> _run(UploadItem u) async {
    u.status = UploadStatus.uploading;
    u.progress = 0;
    _changed();
    final token = CancelToken();
    _tokens[u.id] = token;
    try {
      await _api.uploadPhoto(u, cancel: token, onProgress: (p) {
        u.progress = p;
        _changed();
      });
      _remove(u, deleteFile: true);
      if (!_uploaded.isClosed) _uploaded.add(u.siteId);
    } on ApiException catch (e) {
      if (!_items.any((x) => x.id == u.id)) return; // cancelled meanwhile
      if (e.statusCode == 409 && e.message.contains('already uploaded')) {
        _remove(u, deleteFile: true); // the server already has this photo: our copy is not needed
        if (!_uploaded.isClosed) _uploaded.add(u.siteId);
      } else if (e.statusCode == 401 && _authRetried.add(u.id)) {
        // The token was just refreshed but the multipart body could not be re-sent: send it once more right away
        // (the finally block pumps). A second 401 in a row falls through to a retryable failure below.
        u.status = UploadStatus.queued;
        u.progress = 0;
        u.error = null;
        _changed();
      } else {
        if (e.statusCode != 401) _authRetried.remove(u.id);
        u.status = UploadStatus.failed;
        u.error = e.message;
        // 4xx (wrong state, invalid file) will not fix itself: wait for the person. Network trouble and 401 retry by themselves.
        u.retryable = uploadErrorRetryable(e.statusCode);
        unawaited(_save());
        _changed();
      }
    } catch (_) {
      u.status = UploadStatus.failed;
      u.error = 'Upload failed. Will retry.';
      _changed();
    } finally {
      _tokens.remove(u.id);
      _pump();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _uploaded.close();
    super.dispose();
  }
}
