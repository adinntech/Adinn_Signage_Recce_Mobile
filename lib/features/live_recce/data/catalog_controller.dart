import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_data.dart';
import 'recce_api.dart';

/// Holds the media catalog the screens read. It starts as the copy built into the app, takes the copy saved on the phone at start-up,
/// and replaces it with the server's when a read succeeds (one cheap "has it changed since version N" call). A read that fails keeps
/// what is there, so a phone with no network always has a catalog.
class CatalogController extends ChangeNotifier {
  CatalogController(this._api);

  final RecceApi _api;
  static const cacheKey = 'live_catalog_cache_v1';

  CatalogData _data = CatalogData.builtIn();
  CatalogData get data => _data;

  bool refreshing = false;
  Object? lastError;
  bool _disposed = false;

  /// Loads the copy saved on the phone. Never throws.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw == null) return;
      final saved = CatalogData.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      if (saved.version > 0 && saved.media.isNotEmpty) {
        _data = saved;
        _notify();
      }
    } catch (_) {
      // a damaged copy is ignored: the built-in one stays
    }
  }

  /// Asks the server whether the catalog changed since the version held and takes the new one when it did. Never throws.
  /// Returns true when the catalog was replaced.
  Future<bool> refresh() async {
    if (refreshing) return false;
    refreshing = true;
    lastError = null;
    try {
      final fresh = await _api.catalog(version: _data.isBuiltIn ? null : _data.version);
      if (fresh == null || _disposed) return false; // unchanged
      _data = fresh;
      await _save(fresh);
      _notify();
      return true;
    } catch (e) {
      lastError = e; // offline or refused: keep the catalog we have
      return false;
    } finally {
      refreshing = false;
    }
  }

  Future<void> _save(CatalogData d) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(d.toJson()));
    } catch (_) {
      // storage unavailable: the catalog still works for this session
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
