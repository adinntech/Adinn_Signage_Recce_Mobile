import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/models/models.dart';
import '../../../state/app_controller.dart';
import '../../../state/live_link.dart';
import '../data/recce_api.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';

/// Shows ONE shop of the server with the screens built on the local [Shop] / [Board] models (the shop detail page, the media type
/// picker, the board editor) and carries what the person does there back to the server.
///
///  * server -> screens: every fresh read of the shop ([ShopDetailController.detail]) becomes a [Shop] in the [AppController]
///    ([hydrate]); the boards are one-to-one (board key = board id).
///  * screens -> server: a local edit ([localChanged]) is copied into the controller's boards and saved as the server draft
///    after a short pause; a photo taken on the phone goes through the upload queue into the first free photo place of its board.
///  * submit goes through [ShopDetailController.submit], so the server's own checks apply.
class LiveShopBridge extends ChangeNotifier implements LiveShopLink {
  LiveShopBridge({required this.app, required this.ctrl, required this.userId, required this.userName, this.userPhone = ''}) {
    ctrl.addListener(_onCtrl);
  }

  final AppController app;
  final ShopDetailController ctrl;
  final String userId;
  final String userName;
  final String userPhone;

  String get siteId => ctrl.siteId;
  String get projectId => 'live-project-${ctrl.detail?.project.id ?? ''}';
  String get taskId => 'live-task-$siteId';

  /// The server's refusal of the last draft save (shown to the person), or null.
  String? syncError;
  bool syncing = false;

  Timer? _debounce;
  var _attached = false;
  var _disposed = false;
  ShopDetail? _hydratedFor;
  var _hydratedPending = '';

  /// Photos that came from the server, and photos of this phone already handed to the upload queue.
  Set<String> _serverPhotoIds = {};
  final Set<String> _queuedIds = {};

  /// A local edit waits to be saved (or is being saved): the server's copy must not overwrite it meanwhile.
  bool get _localPending => (_debounce?.isActive ?? false) || syncing || ctrl.dirty;

  /// An edit that is not on the server yet (screens ask before closing).
  bool get hasPending => _localPending;

  /* ------------------------------------------------------------------ server -> screens */

  void _onCtrl() {
    if (_disposed) return;
    final d = ctrl.detail;
    if (d == null || _localPending) return;
    final pending = ctrl.pending.map((u) => '${u.id}:${u.status.name}').join(',');
    if (identical(d, _hydratedFor) && pending == _hydratedPending) return;
    hydrate();
  }

  /// Builds the local shop from the current server read and gives it to the [AppController].
  void hydrate() {
    final d = ctrl.detail;
    if (d == null || _disposed) return;
    _hydratedFor = d;
    _hydratedPending = ctrl.pending.map((u) => '${u.id}:${u.status.name}').join(',');
    final shop = _shopFrom(d);
    if (!_attached) {
      _attached = true;
      app.attachLiveShop(
        user: AppUser(id: userId, code: userId, pin: '0000', name: userName, role: UserRole.vendor, mobile: userPhone),
        project: Project(
          id: projectId,
          code: d.project.code,
          name: d.project.name,
          client: d.project.client ?? '',
          description: '',
          region: '',
          startDate: d.assignedAt ?? DateTime.now(),
          endDate: d.project.expectedBy ?? DateTime.now(),
          coordinatorName: '',
          coordinatorPhone: '',
        ),
        task: RecceTask(
          id: taskId,
          projectId: projectId,
          title: d.title,
          location: d.address,
          city: '',
          dueDate: d.project.expectedBy ?? DateTime.now(),
          assignedVendorId: userId,
        ),
        shop: shop,
        link: this,
      );
    } else {
      app.replaceLiveShop(shop);
    }
    notifyListeners();
  }

  Shop _shopFrom(ShopDetail d) {
    final boards = [for (final b in d.mediaItems) _boardFrom(d, b)];
    final firstFix = boards.expand((b) => b.photos).map((p) => p.geo).whereType<GeoFix>().firstOrNull;
    return Shop(
      id: siteId,
      projectId: projectId,
      taskId: taskId,
      name: d.title,
      ownerName: d.contactPerson ?? '',
      phone: d.mobile ?? '',
      address: d.address,
      geo: firstFix,
      status: _statusOf(d),
      boards: boards,
      createdAt: d.assignedAt,
    );
  }

  RecceStatus _statusOf(ShopDetail d) {
    if (ctrl.canEdit) {
      return switch (d.status) {
        'NOT_STARTED' => RecceStatus.notStarted,
        'REWORK_REQUIRED' || 'REJECTED' => RecceStatus.rejectedBusiness,
        _ => RecceStatus.inProgress,
      };
    }
    return switch (d.status) {
      'APPROVED' => RecceStatus.approved,
      'REJECTED' => RecceStatus.rejectedBusiness,
      _ => RecceStatus.pendingBusiness,
    };
  }

  Board _boardFrom(ShopDetail d, BoardItem b) {
    final catalog = ctrl.catalog;
    final media = b.mediaCode.isEmpty ? null : catalog.mediaByCode(b.mediaCode);
    final photos = <SitePhoto>[
      for (final p in d.photos)
        if (p.mediaKey == b.key && p.removedAt == null && p.supersededBy == null && (p.url ?? '').isNotEmpty) _photoFrom(d, p),
      // Photos taken on this phone that are still on their way up.
      for (final u in ctrl.pending)
        if (u.mediaKey == b.key)
          SitePhoto(
            id: u.id,
            path: u.path,
            label: photoCategoryLabel(u.category),
            capturedAt: u.capturedAt ?? DateTime.now(),
            width: u.width ?? 1200,
            height: u.height ?? 900,
            geo: _fix(u.lat, u.lng, u.accuracy, u.capturedAt),
          ),
    ];
    _serverPhotoIds = {..._serverPhotoIds, for (final p in d.photos) p.id};
    final board = Board(
      id: b.key,
      name: b.isNumbered ? b.label : (media?.shortName ?? b.name),
      mediaCode: b.mediaCode.isEmpty ? null : b.mediaCode,
      installationCode: b.installationType,
      answers: Map<String, dynamic>.of(b.answers),
      width: b.width,
      height: b.height,
      unit: _unitOf(b.unit),
      quantity: b.quantity < 1 ? 1 : b.quantity,
      textNote: b.notes,
      photos: photos,
      doubleSided: b.sided == 'DOUBLE' ? true : null,
      checklistRequired: true,
    );
    for (final u in board.units) {
      u.placement = b.position;
    }
    return board;
  }

  SitePhoto _photoFrom(ShopDetail d, ShopPhoto p) => SitePhoto(
        id: p.id,
        path: p.url!,
        label: d.categoryNames[p.category] ?? photoCategoryLabel(p.category),
        capturedAt: p.capturedAt ?? p.uploadedAt ?? DateTime.now(),
        width: 1200,
        height: 900,
        geo: _fix(p.lat, p.lng, p.gpsAccuracy, p.capturedAt),
      );

  GeoFix? _fix(double? lat, double? lng, double? acc, DateTime? at) =>
      lat == null || lng == null || (lat == 0 && lng == 0) ? null : GeoFix(latitude: lat, longitude: lng, accuracyM: acc ?? 0, capturedAt: at ?? DateTime.now());

  static MeasureUnit _unitOf(String u) => switch (u) {
        'IN' => MeasureUnit.inch,
        'M' => MeasureUnit.m,
        'MM' => MeasureUnit.mm,
        _ => MeasureUnit.ft,
      };

  static String _unitCode(MeasureUnit u) => switch (u) {
        MeasureUnit.ft => 'FT',
        MeasureUnit.inch => 'IN',
        MeasureUnit.m => 'M',
        MeasureUnit.mm => 'MM',
      };

  /* ------------------------------------------------------------------ screens -> server */

  @override
  void localChanged() {
    if (_disposed || !ctrl.canEdit) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), () => unawaited(_push()));
    notifyListeners();
  }

  @override
  Future<String?> saveDraft() async {
    _debounce?.cancel();
    return _push();
  }

  /// Copies the local boards into the controller's boards, hands new photos to the upload queue and saves the draft.
  Future<String?> _push() async {
    final shop = app.shop(siteId);
    if (shop == null || _disposed || !ctrl.canEdit) return null;
    if (syncing) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () => unawaited(_push()));
      return null;
    }
    syncing = true;
    syncError = null;
    notifyListeners();
    String? error;
    try {
      _copyBoards(shop);
      await _syncPhotos(shop);
      if (ctrl.boards.isEmpty) {
        // The server needs one board to save; with none there is nothing to keep yet.
        ctrl.dirty = false;
      } else if (ctrl.dirty) {
        error = await ctrl.saveDraft();
      }
    } catch (e) {
      error = e.toString();
    } finally {
      syncing = false;
    }
    syncError = error;
    if (_disposed) return error;
    if (error == null) {
      _hydratedFor = null; // the next read of the shop is shown
      hydrate();
    } else {
      notifyListeners();
    }
    return error;
  }

  void _copyBoards(Shop shop) {
    final catalog = ctrl.catalog;
    final before = ctrl.boards.map((b) => '${b.key}|${b.mediaCode}|${b.installationType}|${b.width}|${b.height}|${b.unit}|${b.quantity}|${b.sided}|${b.notes}|${b.position}|${b.answers}').join(';');
    final next = <BoardItem>[];
    for (final b in shop.boards) {
      final item = ctrl.boards.where((x) => x.key == b.id).firstOrNull ?? BoardItem(key: b.id);
      final media = (b.mediaCode ?? '').isEmpty ? null : catalog.mediaByCode(b.mediaCode);
      final isNew = !ctrl.boards.any((x) => x.key == b.id);
      if (media != null && (isNew || item.mediaCode.isEmpty)) {
        item.mediaCode = media.code;
        item.mediaType = media.shortName;
        item.name = media.name;
        item.seq = nextBoardSeq([...ctrl.boards, ...next], media.shortName);
      }
      item.installationType = b.installationCode;
      item.answers
        ..clear()
        ..addAll(b.answers);
      item.width = b.width;
      item.height = b.height;
      item.unit = _unitCode(b.unit);
      item.quantity = b.quantity;
      item.sided = b.doubleSided == true ? 'DOUBLE' : 'SINGLE';
      item.notes = b.textNote;
      item.position = b.units.isEmpty ? '' : b.units.first.placement;
      next.add(item);
    }
    final after = next.map((b) => '${b.key}|${b.mediaCode}|${b.installationType}|${b.width}|${b.height}|${b.unit}|${b.quantity}|${b.sided}|${b.notes}|${b.position}|${b.answers}').join(';');
    if (before != after || next.length != ctrl.boards.length) {
      ctrl.boards
        ..clear()
        ..addAll(next);
      ctrl.markDirty();
    }
  }

  /// A photo taken on this phone is queued for the first free photo place of its board (the place named like its label first);
  /// a photo removed on the screen is deleted from the server's draft.
  Future<void> _syncPhotos(Shop shop) async {
    final d = ctrl.detail;
    if (d == null) return;
    final localIds = {for (final b in shop.boards) for (final p in b.photos) p.id};
    for (final b in shop.boards) {
      final saved = d.mediaItems.where((m) => m.key == b.id).firstOrNull;
      for (final p in b.photos) {
        if (p.isDemo || p.path.startsWith('http') || _serverPhotoIds.contains(p.id) || _queuedIds.contains(p.id)) continue;
        if (saved == null) continue; // the server does not hold this board yet: its photos wait for the next save
        final slot = _freeSlot(saved, p.label);
        if (slot == null) continue;
        _queuedIds.add(p.id);
        ctrl.queue.add(UploadItem(
          id: p.id,
          siteId: siteId,
          path: p.path,
          category: slot.category,
          mediaKey: b.id,
          caption: p.label,
          capturedAt: p.capturedAt,
          lat: p.geo?.latitude,
          lng: p.geo?.longitude,
          accuracy: p.geo?.accuracyM,
          width: p.width,
          height: p.height,
        ));
      }
    }
    for (final ph in d.photos) {
      if (ph.isDraft && ph.removedAt == null && ph.mediaKey.isNotEmpty && !localIds.contains(ph.id) && d.mediaItems.any((m) => m.key == ph.mediaKey)) {
        await ctrl.deletePhoto(ph);
      }
    }
  }

  PhotoSlot? _freeSlot(BoardItem saved, String label) {
    final d = ctrl.detail!;
    final slots = ctrl.photoSlotsOf(saved);
    bool free(PhotoSlot s) => d.photoOf(s.category, s.mediaKey) == null && !ctrl.pending.any((u) => u.category == s.category && u.mediaKey == s.mediaKey);
    final named = slots.where((s) => photoCategoryLabel(s.category).toLowerCase() == label.trim().toLowerCase() && free(s)).firstOrNull;
    return named ?? slots.where(free).firstOrNull;
  }

  /* ------------------------------------------------------------------ submit */

  @override
  Future<LiveSubmitResult> submit(String remarks) async {
    _debounce?.cancel();
    final err = await _push();
    if (err != null) return LiveSubmitResult(problems: [err]);
    if (remarks.trim().isNotEmpty) ctrl.setNotes(remarks.trim());
    final out = await ctrl.submit();
    if (out.problems.isNotEmpty) return LiveSubmitResult(problems: out.problems);
    if (out.serverError != null) return LiveSubmitResult(problems: [out.serverError!]);
    _hydratedFor = null;
    hydrate();
    return LiveSubmitResult(version: out.version);
  }

  /// Reads the shop from the server again and shows it.
  Future<void> reload() async {
    await ctrl.refresh();
    _hydratedFor = null;
    hydrate();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    ctrl.removeListener(_onCtrl);
    app.detachLiveShop(siteId, projectId: projectId, taskId: taskId);
    super.dispose();
  }
}
