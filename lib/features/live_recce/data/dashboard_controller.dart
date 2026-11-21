import 'package:flutter/foundation.dart';

import 'recce_api.dart';
import 'recce_controllers.dart' show errorText;
import 'recce_models.dart';

/// The field dashboard (`GET /recce/dashboard`). A failed read leaves [data] null and sets [error]: the screen then shows the shop
/// counts it already has, with the message and a Retry, never a spinner that does not end.
class FieldDashboardController extends ChangeNotifier {
  FieldDashboardController(this._api);

  final RecceApi _api;

  FieldDashboard? data;
  bool loading = false;
  bool loaded = false;
  String? error;

  var _gen = 0;
  var _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// A silent read (after a shop change) keeps the numbers on screen when it fails.
  Future<void> load({bool silent = false}) async {
    if (loading || _disposed) return;
    final gen = ++_gen;
    loading = true;
    if (!silent) {
      error = null;
      _notify();
    }
    try {
      final d = await _api.dashboard();
      if (gen != _gen || _disposed) return; // a sign out happened while the answer was on its way
      data = d;
      error = null;
      loaded = true;
    } catch (e) {
      if (gen == _gen && (!silent || data == null)) error = errorText(e);
    } finally {
      if (gen == _gen) {
        loading = false;
        _notify();
      }
    }
  }

  /// Sign out: the numbers of this login are dropped.
  void reset() {
    _gen++;
    data = null;
    loading = false;
    loaded = false;
    error = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
