import 'package:flutter/foundation.dart';

import 'recce_api.dart';
import 'recce_controllers.dart' show errorText;
import 'recce_models.dart';

/// Version comparison: pick two versions (default: the one before the latest, and the latest) and read what changed.
class CompareController extends ChangeNotifier {
  CompareController(this._api, this.siteId, List<RecceVersion> versions)
      : versions = List.unmodifiable(versions),
        to = versions.isEmpty ? 0 : versions.last.version,
        from = versions.length < 2 ? 0 : versions[versions.length - 2].version;

  final RecceApi _api;
  final String siteId;
  final List<RecceVersion> versions;

  int from;
  int to;
  VersionCompare? result;
  bool loading = false;
  String? error;
  var _disposed = false;

  bool get canCompare => versions.length >= 2;

  RecceVersion? versionNo(int n) {
    for (final v in versions) {
      if (v.version == n) return v;
    }
    return null;
  }

  void select({int? from, int? to}) {
    if (from != null) this.from = from;
    if (to != null) this.to = to;
    load();
  }

  Future<void> load() async {
    if (!canCompare) return;
    if (from == to) {
      result = null;
      error = 'Pick two different versions.';
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    final wantFrom = from;
    final wantTo = to;
    try {
      final r = await _api.compare(siteId, wantFrom, wantTo);
      if (wantFrom == from && wantTo == to) result = r; // a newer pick may have started meanwhile
    } catch (e) {
      if (wantFrom == from && wantTo == to) {
        result = null;
        error = errorText(e);
      }
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

Future<T?> _quiet<T>(Future<T> f) => f.then<T?>((v) => v, onError: (Object _) => null);

/// Approval history of one shop: the server's timeline, oldest first by default (a story), with a toggle for newest first,
/// and a switch between the approval steps only and every event.
class ActivityController extends ChangeNotifier {
  /// [detail] and [versions] are what the shop screen already holds. Every [load] reads them again too, because the photo
  /// pictures of the history are signed links that expire (about 10 minutes): reopening or pulling to refresh gives fresh ones.
  ActivityController(this._api, this.siteId, {this.detail, this.versions = const []});

  final RecceApi _api;
  final String siteId;

  ShopDetail? detail;
  List<RecceVersion> versions;
  List<ActivityEvent> events = const [];
  bool loading = true;
  String? error;
  bool newestFirst = false;
  bool showAll = false;
  var _disposed = false;

  /// Photo of an event: a live photo of the shop, else one of an older version.
  Map<String, ShopPhoto> get photos => {
        for (final v in versions) for (final p in v.photos) p.id: p,
        for (final p in detail?.photos ?? const <ShopPhoto>[]) p.id: p,
      };

  /// What the screen lists, in the chosen order.
  List<ActivityEvent> get visible => orderActivity([for (final e in events) if (showAll || e.isApproval) e], newestFirst: newestFirst);

  int get hiddenCount => events.length - events.where((e) => e.isApproval).length;

  void setNewestFirst(bool v) {
    newestFirst = v;
    notifyListeners();
  }

  void setShowAll(bool v) {
    showAll = v;
    notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    if (!_disposed) notifyListeners();
    try {
      // The photos and boards are best effort (fresh links, current boards); the timeline is what must load.
      final freshDetail = _quiet(_api.detail(siteId));
      final freshVersions = _quiet(_api.versions(siteId));
      final list = await _api.activity(siteId);
      final d = await freshDetail;
      final v = await freshVersions;
      if (_disposed) return;
      events = list;
      detail = d ?? detail;
      versions = v ?? versions;
    } catch (e) {
      if (!_disposed) error = errorText(e);
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// History of one photo (revisions, events, rework requests) for the rework sheet.
class PhotoHistoryController extends ChangeNotifier {
  PhotoHistoryController(this._api, this.siteId, this.photoId);

  final RecceApi _api;
  final String siteId;
  final String photoId;

  PhotoHistory? history;
  bool loading = true;
  String? error;
  var _disposed = false;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      history = await _api.photoHistory(siteId, photoId);
    } catch (e) {
      error = errorText(e);
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
