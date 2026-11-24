// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';

import '../live_recce/data/catalog_controller.dart';
import '../live_recce/data/catalog_data.dart';
import '../live_recce/data/recce_api.dart';
import '../live_recce/data/recce_controllers.dart' show errorText;

/// The three lists the administrator manages. [path] is the segment of `/api/v1/catalog/<path>`.
enum CatalogKind {
  media('media', 'Media types'),
  installations('installations', 'Installation types'),
  questions('questions', 'Questions');

  const CatalogKind(this.path, this.label);
  final String path;
  final String label;
}

/// What the edit screens may change on an existing entry (the server refuses anything else: a question's scope, key and type are fixed).
const mediaEditable = ['shortName', 'name', 'description', 'icon', 'color', 'illuminated', 'sidedness', 'depthFt', 'thicknessMm', 'installations', 'active'];
const installationEditable = ['name', 'description', 'icon', 'active'];
const questionEditable = ['label', 'options', 'unit', 'required', 'hint', 'showIfId', 'showIfValue', 'active'];

bool _same(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_same(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  return a == b;
}

/// The body of an edit: ONLY the [editable] fields whose value differs from [before]. The server's edit schemas take no defaults, so
/// a field that is not sent stays as it is; a value the person cleared goes as an explicit `null`. Empty = nothing to save.
Map<String, dynamic> changedFields(Map<String, dynamic> before, Map<String, dynamic> after, Iterable<String> editable) => {
      for (final k in editable)
        if (after.containsKey(k) && !_same(before[k], after[k])) k: after[k],
    };

/// The body of a new entry: the edited values without the empty optional ones (the server gives them their defaults).
Map<String, dynamic> newEntryBody(Map<String, dynamic> values) => {
      for (final e in values.entries)
        if (e.value != null && !(e.value is String && (e.value as String).trim().isEmpty && e.key != 'code')) e.key: e.value,
    };

/// Everything the admin screens read and write: the catalog as it is on the server, how often each entry is used, and every change.
/// After a change the lists are read again, and [CatalogController] (the copy the field screens use, on this phone) is refreshed.
class CatalogAdminController extends ChangeNotifier {
  CatalogAdminController(this._api, {CatalogController? shared}) : _shared = shared;

  final RecceApi _api;
  final CatalogController? _shared;

  CatalogData data = CatalogData();
  CatalogUsage usage = const CatalogUsage();
  bool loading = false;
  bool loaded = false;
  bool busy = false;
  String? error;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Reads the catalog and the usage counts. A usage failure is not fatal: the lists still show, without counts.
  Future<void> load({bool silent = false}) async {
    if (loading || _disposed) return;
    loading = true;
    if (!silent) {
      error = null;
      _notify();
    }
    try {
      data = await _api.catalogFull();
      loaded = true;
      error = null;
      try {
        usage = await _api.catalogUsage();
      } catch (_) {
        usage = const CatalogUsage();
      }
    } catch (e) {
      if (!silent || !loaded) error = errorText(e);
    } finally {
      loading = false;
      _notify();
    }
  }

  /// Runs one write. Returns the server's error text, or null on success (then the lists are read again).
  Future<String?> _write(Future<void> Function() call) async {
    if (busy) return 'Wait for the last change to finish.';
    busy = true;
    _notify();
    try {
      await call();
      await load(silent: true);
      if (_shared != null) await _shared.refresh();
      return null;
    } catch (e) {
      return errorText(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<String?> create(CatalogKind kind, Map<String, dynamic> values) => _write(() => _api.catalogCreate(kind.path, newEntryBody(values)));

  /// [changes] is what [changedFields] returned: nothing changed means nothing is sent.
  Future<String?> update(CatalogKind kind, String id, Map<String, dynamic> changes) async {
    if (changes.isEmpty) return null;
    return _write(() => _api.catalogUpdate(kind.path, id, changes));
  }

  Future<String?> delete(CatalogKind kind, String id) => _write(() => _api.catalogDelete(kind.path, id));

  Future<String?> setActive(CatalogKind kind, String id, bool active) => update(kind, id, {'active': active});

  /// [ids] in the new order (codes, or the question uids of ONE group).
  Future<String?> reorder(CatalogKind kind, List<String> ids) => _write(() => _api.catalogReorder(kind.path, ids));

  /// How many built-in entries the last "Load built-in defaults" added back.
  int lastDefaultsAdded = 0;

  /// "Load built-in defaults": adds back every built-in entry that was deleted. Returns the error text, or null (then [lastDefaultsAdded] is set).
  Future<String?> loadDefaults() {
    lastDefaultsAdded = 0;
    return _write(() async {
      final r = await _api.catalogLoadDefaults();
      lastDefaultsAdded = r.values.fold(0, (a, b) => a + b);
    });
  }

  /* ---- reads the screens use ---- */

  /// The media types the admin can order: the offered ones (the older ones kept for old records are listed apart and never moved).
  List<CatalogMedia> get currentMedia => [for (final m in data.media) if (!m.legacy) m];
  List<CatalogMedia> get legacyMedia => [for (final m in data.media) if (m.legacy) m];

  /// The questions of one group, in the order the field person sees them.
  List<CatalogQuestion> questionsOf(String scope, String scopeCode) =>
      [for (final q in data.questions) if (q.scope == scope && (scope == 'COMMON' || q.scopeCode == scopeCode)) q];

  CatalogInstallation? installation(String code) => data.installationByCode(code);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
