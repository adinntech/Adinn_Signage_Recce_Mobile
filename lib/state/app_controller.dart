import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/utils/formatters.dart';
import '../data/catalog/measurement_fields.dart';
import '../data/catalog/question_equivalence.dart';
import '../data/catalog/signage_catalog.dart';
import '../data/catalog/site_checklists.dart';
import '../data/mock/mock_seed.dart';
import '../data/models/models.dart';
import '../data/storage/local_store.dart';
import '../data/storage/media_storage.dart';
import '../features/model3d/signage_spec.dart';
import '../features/references/reference_rules.dart';
import '../features/survey/feasibility.dart';
import 'live_link.dart';

/// Workflow section that resolves a blocking issue.
enum IssueSection { media, details, installation, questions, photos }

/// One blocking validation issue of a media group, pointing at the physical
/// board ([unitId], null = whole group) and the section that resolves it.
class BoardIssue {
  const BoardIssue(this.text, this.section, {this.unitId});

  final String text;
  final IssueSection section;
  final String? unitId;
}

/// Aggregated counts for a set of shops.
class ProgressSummary {
  ProgressSummary(Iterable<Shop> shops) {
    for (final s in shops) {
      total++;
      switch (s.status) {
        case RecceStatus.notStarted:
          notStarted++;
        case RecceStatus.inProgress:
          inProgress++;
        case RecceStatus.pendingBusiness:
        case RecceStatus.pendingOps:
          pending++;
        case RecceStatus.approved:
          approved++;
        case RecceStatus.rejectedBusiness:
        case RecceStatus.rejectedOps:
          rejected++;
      }
    }
  }

  int total = 0;
  int notStarted = 0;
  int inProgress = 0;
  int pending = 0;
  int approved = 0;
  int rejected = 0;

  /// Share of shops that have at least been submitted.
  double get submittedRatio => total == 0 ? 0 : (pending + approved) / total;
  double get approvedRatio => total == 0 ? 0 : approved / total;

  String get label {
    if (total == 0) return 'No shops yet';
    if (approved == total) return 'Completed';
    if (rejected > 0) return 'Action required';
    if (notStarted == total) return 'Not Started';
    return 'In Progress';
  }
}

/// Single source of truth for the app: session, dummy data, the approval
/// workflow and local persistence. Screens read it through Provider.
class AppController extends ChangeNotifier {
  AppController({required this.store, this.media, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LocalStore store;
  final MediaStorage? media;
  final DateTime Function() _clock;

  AppData _data = AppData(
    users: [],
    projects: [],
    tasks: [],
    shops: [],
    activities: [],
  );
  bool _ready = false;
  Future<void> _pendingWrite = Future.value();
  String? _otpUserId;

  bool get isReady => _ready;
  AppData get data => _data;

  /// Set when stored data could not be read completely. The original JSON
  /// was backed up first (see [LocalStore.backup]).
  String? recoveryNotice;

  void dismissRecoveryNotice() {
    recoveryNotice = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle & persistence
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    Map<String, dynamic>? json;
    try {
      json = await store.read();
    } catch (_) {
      json = null;
    }
    if (json == null || (json['users'] as List?)?.isEmpty != false) {
      _data = buildSeedData();
      _save();
    } else {
      ModelParseLog.skipped = 0;
      AppData? parsed;
      try {
        parsed = AppData.fromJson(json);
      } catch (e) {
        debugPrint('Stored data unreadable: $e');
      }
      if (parsed == null) {
        // Keep the original document; start from demo data.
        await _backup(json, 'unreadable');
        recoveryNotice =
            'Saved data could not be read. A backup was kept on the device.';
        _data = buildSeedData();
        _save();
      } else {
        _data = parsed;
        final skipped = ModelParseLog.skipped;
        final upgrade = _data.loadedSchemaVersion < AppData.schemaVersion;
        if (skipped > 0 || upgrade) {
          // Back up before the first rewrite in the new format.
          await _backup(
            json,
            skipped > 0 ? 'repair' : 'v${_data.loadedSchemaVersion}',
          );
          if (skipped > 0) {
            recoveryNotice =
                '$skipped damaged record(s) were skipped. A backup of the '
                'original data was kept on the device.';
          }
          _migrate();
          _save();
        }
      }
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> _backup(Map<String, dynamic> raw, String reason) async {
    try {
      await store.backup(raw, reason);
    } catch (e) {
      debugPrint('Backup failed: $e');
    }
  }

  /// Upgrades data saved by older app versions. Idempotent: running it on
  /// already-upgraded data changes nothing.
  ///
  /// v3 → v4 needs no rewrite: the advanced survey fields are optional and
  /// default to "not recorded" (never to "completed").
  void _migrate() {
    // v1 → v2: login moved from ID + password to a unique 4-digit PIN.
    final used = <String>{};
    for (final u in _data.users) {
      if (!isValidPin(u.pin) || used.contains(u.pin)) {
        u.pin = DemoAccounts.seedPins[u.id] ?? u.pin;
      }
      // Still invalid or clashing: assign the first free PIN.
      for (var n = 1000; !isValidPin(u.pin) || used.contains(u.pin); n++) {
        u.pin = '$n';
      }
      used.add(u.pin);
    }
  }

  /// Set when the last write to device storage failed (cleared after the
  /// next successful write). Data stays in memory meanwhile.
  String? storageError;

  void _save() {
    final snapshot = _persistable();
    _pendingWrite = _pendingWrite
        .then((_) => store.write(snapshot))
        .then((_) {
          if (storageError != null) {
            storageError = null;
            notifyListeners();
          }
        })
        .catchError((Object e) {
          debugPrint('Save failed: $e');
          storageError =
              'Changes could not be saved on this device ($e). They are '
              'kept while the app is open – free some storage and tap Retry.';
          notifyListeners();
        });
  }

  bool _draftWriteQueued = false;

  /// Coalesced write for high-frequency draft updates: a burst of edits
  /// produces one write of the latest state (no timers involved).
  void _saveDraftSoon() {
    if (_draftWriteQueued) return;
    _draftWriteQueued = true;
    _pendingWrite = _pendingWrite
        .then((_) {
          _draftWriteQueued = false;
          return store.write(_persistable());
        })
        .catchError((Object e) {
          _draftWriteQueued = false;
          debugPrint('Draft save failed: $e');
        });
  }

  /// Unsaved form draft stored on the device (null when none).
  Map<String, dynamic>? formDraft(String key) {
    final v = _data.formDrafts[key];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  /// Keeps an unsaved form state so an interrupted recce can be restored.
  /// Not logged and not part of the recce until the form is saved.
  void saveFormDraft(String key, Map<String, dynamic> json) {
    _data.formDrafts[key] = json;
    _saveDraftSoon();
  }

  void clearFormDraft(String key) {
    if (_data.formDrafts.remove(key) != null) _saveDraftSoon();
  }

  /// Writes the current data again (after a storage error).
  Future<void> retrySave() {
    _save();
    return _pendingWrite;
  }

  /// Completes when every queued write has reached storage.
  Future<void> flush() => _pendingWrite;

  void _commit() {
    _save();
    notifyListeners();
    for (final l in _links.values.toList()) {
      l.localChanged();
    }
  }

  // ---------------------------------------------------------------------------
  // Live backend link (shops that come from the server, shown with the same screens)
  // ---------------------------------------------------------------------------

  AppUser? _liveUser;
  final Map<String, LiveShopLink> _links = {};
  final Set<String> _liveProjects = {};
  final Set<String> _liveTasks = {};
  final Set<String> _liveUsers = {};

  /// The server's link of [shopId], or null for an offline (prototype) shop.
  LiveShopLink? liveLink(String shopId) => _links[shopId];
  bool isLiveShop(String shopId) => _links.containsKey(shopId);

  /// Puts a shop read from the server next to the local data so the usual screens can show it. Nothing of it is written to
  /// the device store (see [_persistable]). Calling it again for the same shop replaces the earlier copy.
  void attachLiveShop({
    required AppUser user,
    required Project project,
    required RecceTask task,
    required Shop shop,
    required LiveShopLink link,
  }) {
    _liveUser = user;
    _liveUsers.add(user.id);
    if (!_data.users.any((u) => u.id == user.id)) _data.users.add(user);
    _data.projects.removeWhere((p) => p.id == project.id);
    _data.projects.add(project);
    _liveProjects.add(project.id);
    _data.tasks.removeWhere((t) => t.id == task.id);
    _data.tasks.add(task);
    _liveTasks.add(task.id);
    _data.shops.removeWhere((x) => x.id == shop.id);
    _data.shops.add(shop);
    _links[shop.id] = link;
    notifyListeners();
  }

  /// Replaces the local copy of a live shop with a fresh read (the link is not told: it is not a local edit).
  void replaceLiveShop(Shop shop) {
    final i = _data.shops.indexWhere((x) => x.id == shop.id);
    if (i < 0) {
      _data.shops.add(shop);
    } else {
      _data.shops[i] = shop;
    }
    notifyListeners();
  }

  void detachLiveShop(String shopId, {String? projectId, String? taskId}) {
    _links.remove(shopId);
    _data.shops.removeWhere((x) => x.id == shopId);
    if (taskId != null) {
      _data.tasks.removeWhere((t) => t.id == taskId);
      _liveTasks.remove(taskId);
    }
    if (projectId != null && !_data.tasks.any((t) => t.projectId == projectId)) {
      _data.projects.removeWhere((p) => p.id == projectId);
      _liveProjects.remove(projectId);
    }
    if (_links.isEmpty) {
      _data.users.removeWhere((u) => _liveUsers.contains(u.id));
      _liveUsers.clear();
      _liveUser = null;
    }
  }

  /// The local data without what came from the server (that lives on the server, not on the device).
  Map<String, dynamic> _persistable() {
    final j = _data.toJson();
    if (_links.isEmpty && _liveProjects.isEmpty) return j;
    List<dynamic> keep(String key, bool Function(Map) live) =>
        [for (final e in (j[key] as List? ?? const [])) if (!(e is Map && live(e))) e];
    final liveShops = _links.keys.toSet();
    j['shops'] = keep('shops', (e) => liveShops.contains(e['id']));
    j['tasks'] = keep('tasks', (e) => _liveTasks.contains(e['id']));
    j['projects'] = keep('projects', (e) => _liveProjects.contains(e['id']));
    j['users'] = keep('users', (e) => _liveUsers.contains(e['id']));
    if (_liveUsers.contains(j['sessionUserId'])) j['sessionUserId'] = null;
    return j;
  }

  /// Id of a board made now: a live shop numbers its boards b1, b2 ... as the server does.
  String _newBoardId(Shop s) {
    if (!_links.containsKey(s.id)) return newId('b');
    final taken = s.boards.map((b) => b.id).toSet();
    var n = 1;
    while (taken.contains('b$n')) {
      n++;
    }
    return 'b$n';
  }

  Future<void> resetDemoData() async {
    final keepSession = _data.sessionUserId;
    await media?.deleteAll();
    _data = buildSeedData();
    if (_data.users.any((u) => u.id == keepSession)) {
      _data.sessionUserId = keepSession;
    }
    _commit();
    await flush();
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  AppUser? get currentUser {
    if (_liveUser != null) return _liveUser;
    final id = _data.sessionUserId;
    if (id == null) return null;
    for (final u in _data.users) {
      if (u.id == id) return u;
    }
    return null;
  }

  bool get isLoggedIn => currentUser != null;
  UserRole? get role => currentUser?.role;
  bool get isVendor => role == UserRole.vendor;

  AppUser? findUser(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final u in _data.users) {
      if (u.code.toLowerCase() == q || u.mobile == q) return u;
    }
    return null;
  }

  AppUser? userById(String id) {
    for (final u in _data.users) {
      if (u.id == id) return u;
    }
    return null;
  }

  static final _pinPattern = RegExp(r'^\d{4}$');
  static const maxPinAttempts = 5;
  static const pinLockDuration = Duration(seconds: 30);

  int _failedPinAttempts = 0;
  DateTime? _lockedUntil;

  static bool isValidPin(String pin) => _pinPattern.hasMatch(pin);

  /// Time left before PIN entry is allowed again (null when not locked).
  Duration? get pinLockRemaining {
    final until = _lockedUntil;
    if (until == null) return null;
    final left = until.difference(_clock());
    return left.isNegative || left == Duration.zero ? null : left;
  }

  /// Logs in with the 4-digit PIN only. Returns an error message, or null on
  /// success. After [maxPinAttempts] wrong PINs entry is locked for
  /// [pinLockDuration] (a 4-digit PIN alone is otherwise easy to guess).
  String? loginWithPin(String pin) {
    final locked = pinLockRemaining;
    if (locked != null) {
      return 'Too many wrong attempts. Try again in ${locked.inSeconds + 1}s.';
    }
    if (!isValidPin(pin)) return 'Enter your 4-digit PIN';
    final user = _data.users.where((u) => u.pin == pin).firstOrNull;
    if (user == null) {
      _failedPinAttempts++;
      if (_failedPinAttempts >= maxPinAttempts) {
        _failedPinAttempts = 0;
        _lockedUntil = _clock().add(pinLockDuration);
        notifyListeners();
        return 'Too many wrong attempts. Locked for '
            '${pinLockDuration.inSeconds} seconds.';
      }
      final left = maxPinAttempts - _failedPinAttempts;
      return 'Incorrect PIN. $left attempt${left == 1 ? '' : 's'} left.';
    }
    _failedPinAttempts = 0;
    _lockedUntil = null;
    _data.sessionUserId = user.id;
    _commit();
    return null;
  }

  void logout() {
    _data.sessionUserId = null;
    _commit();
  }

  /// Starts the forgot-PIN flow using the registered mobile number. Returns
  /// the (dummy) OTP that would be sent by SMS, or null when no user matches.
  String? requestOtp(String mobile) {
    final m = mobile.trim();
    final user = _data.users.where((u) => u.mobile == m).firstOrNull;
    if (user == null) return null;
    _otpUserId = user.id;
    return DemoAccounts.otp;
  }

  bool verifyOtp(String otp) =>
      _otpUserId != null && otp.trim() == DemoAccounts.otp;

  String? _pinProblem(String pin, AppUser forUser) {
    if (!isValidPin(pin)) return 'PIN must be exactly 4 digits';
    if (RegExp(r'^(\d)\1{3}$').hasMatch(pin)) {
      return 'PIN is too easy to guess. Avoid repeating one digit.';
    }
    // PIN alone identifies the user, so it must be unique.
    if (_data.users.any((u) => u.id != forUser.id && u.pin == pin)) {
      return 'This PIN is not available. Choose a different PIN.';
    }
    return null;
  }

  /// Completes the reset. Returns an error message or null on success.
  String? resetPin(String newPin) {
    final user = _otpUserId == null ? null : userById(_otpUserId!);
    if (user == null) return 'Session expired. Request a new OTP.';
    final problem = _pinProblem(newPin, user);
    if (problem != null) return problem;
    user.pin = newPin;
    _otpUserId = null;
    _failedPinAttempts = 0;
    _lockedUntil = null;
    _log(
      'auth',
      'PIN reset',
      '${user.name} reset the PIN using OTP.',
      actor: user,
    );
    _commit();
    return null;
  }

  String? changePin(String current, String next) {
    final user = currentUser;
    if (user == null) return 'Not logged in';
    if (user.pin != current) return 'Current PIN is incorrect';
    if (next == current) return 'New PIN must be different';
    final problem = _pinProblem(next, user);
    if (problem != null) return problem;
    user.pin = next;
    _log('auth', 'PIN changed', '${user.name} changed the login PIN.');
    _commit();
    return null;
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  bool _taskVisible(RecceTask t) {
    final u = currentUser;
    if (u == null) return false;
    return u.role != UserRole.vendor || t.assignedVendorId == u.id;
  }

  List<RecceTask> get visibleTasks => _data.tasks.where(_taskVisible).toList();

  List<Project> get projects {
    final ids = visibleTasks.map((t) => t.projectId).toSet();
    return _data.projects.where((p) => ids.contains(p.id)).toList();
  }

  Project? project(String id) {
    for (final p in _data.projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  RecceTask? task(String id) {
    for (final t in _data.tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  List<RecceTask> tasksForProject(String projectId) =>
      visibleTasks.where((t) => t.projectId == projectId).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  List<Shop> get visibleShops {
    final taskIds = visibleTasks.map((t) => t.id).toSet();
    return _data.shops.where((s) => taskIds.contains(s.taskId)).toList();
  }

  List<Shop> shopsForTask(String taskId) =>
      visibleShops.where((s) => s.taskId == taskId).toList();

  List<Shop> shopsForProject(String projectId) =>
      visibleShops.where((s) => s.projectId == projectId).toList();

  Shop? shop(String id) {
    for (final s in _data.shops) {
      if (s.id == id) return s;
    }
    return null;
  }

  Board? board(String shopId, String boardId) {
    final s = shop(shopId);
    if (s == null) return null;
    for (final b in s.boards) {
      if (b.id == boardId) return b;
    }
    return null;
  }

  ProgressSummary get overallSummary => ProgressSummary(visibleShops);
  ProgressSummary projectSummary(String projectId) =>
      ProgressSummary(shopsForProject(projectId));
  ProgressSummary taskSummary(String taskId) =>
      ProgressSummary(shopsForTask(taskId));

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  ReviewStage? get reviewStage => switch (role) {
    UserRole.businessTeam => ReviewStage.business,
    UserRole.recceOps => ReviewStage.ops,
    _ => null,
  };

  RecceStatus? get _awaitingStatus => switch (reviewStage) {
    ReviewStage.business => RecceStatus.pendingBusiness,
    ReviewStage.ops => RecceStatus.pendingOps,
    null => null,
  };

  bool canEdit(Shop shop) {
    final u = currentUser;
    if (u == null || u.role != UserRole.vendor) return false;
    final t = task(shop.taskId);
    return t != null && t.assignedVendorId == u.id && shop.status.isEditable;
  }

  bool canReview(Shop shop) =>
      _awaitingStatus != null && shop.status == _awaitingStatus;

  /// Shops waiting for the logged-in reviewer.
  List<Shop> get pendingReviews {
    final s = _awaitingStatus;
    if (s == null) return [];
    return visibleShops.where((e) => e.status == s).toList()..sort(
      (a, b) => (a.latestSubmission?.submittedAt ?? a.updatedAt).compareTo(
        b.latestSubmission?.submittedAt ?? b.updatedAt,
      ),
    );
  }

  /// Shops the logged-in reviewer has acted on at least once.
  List<Shop> get reviewedByMe {
    final u = currentUser;
    if (u == null) return [];
    return visibleShops
        .where(
          (s) => s.submissions.any(
            (sub) => sub.reviews.any((r) => r.reviewerId == u.id),
          ),
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Shops the vendor has submitted at least once.
  List<Shop> get mySubmissions =>
      visibleShops.where((s) => s.submissions.isNotEmpty).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  // ---------------------------------------------------------------------------
  // Shop & board editing
  // ---------------------------------------------------------------------------

  Shop createShop(RecceTask task, Shop draft) {
    final shop = Shop(
      id: newId('s'),
      projectId: task.projectId,
      taskId: task.id,
      name: draft.name,
      ownerName: draft.ownerName,
      phone: draft.phone,
      address: draft.address,
      area: draft.area,
      city: draft.city,
      pincode: draft.pincode,
      landmark: draft.landmark,
      remarks: draft.remarks,
      geo: draft.geo,
    );
    _data.shops.add(shop);
    _log(
      'created',
      'Shop added',
      '${shop.name} added to ${task.title}.',
      shop: shop,
    );
    _commit();
    return shop;
  }

  /// Persist changes made directly on [shop]'s fields.
  void touchShop(Shop shop, {String? title, String? message}) {
    shop.updatedAt = DateTime.now();
    if (shop.status == RecceStatus.notStarted) {
      shop.status = RecceStatus.inProgress;
    }
    if (title != null) {
      _log('updated', title, message ?? shop.name, shop: shop);
    }
    _commit();
  }

  bool canDeleteShop(Shop shop) =>
      canEdit(shop) && shop.submissions.isEmpty && !isLiveShop(shop.id);

  Future<void> deleteShop(String shopId) async {
    final s = shop(shopId);
    if (s == null || !canDeleteShop(s)) return;
    for (final b in s.boards) {
      await _deleteBoardMedia(s, b);
    }
    _data.shops.remove(s);
    _data.arLayouts.removeWhere((l) => l.shopId == s.id);
    for (final r in _data.reports.where((r) => r.shopId == s.id).toList()) {
      await media?.deleteIfExists(r.path);
      _data.reports.remove(r);
    }
    for (final p in _data.panoramas.where((p) => p.shopId == s.id).toList()) {
      await media?.deleteIfExists(p.path);
      for (final v in p.previews) {
        await media?.deleteIfExists(v);
      }
      _data.panoramas.remove(p);
    }
    _log(
      'updated',
      'Shop removed',
      '${s.name} was removed.',
      projectId: s.projectId,
      taskId: s.taskId,
    );
    _commit();
  }

  Board addBoard(String shopId) {
    final s = shop(shopId)!;
    final board = Board(
      id: _newBoardId(s),
      name: 'Board ${s.boards.length + 1}',
      checklistRequired: true,
    );
    s.boards.add(board);
    touchShop(
      s,
      title: 'Board added',
      message: '${board.name} added to ${s.name}.',
    );
    return board;
  }

  /// Creates the media groups confirmed in the Add Media Type popup, in one
  /// operation (nothing is created while the vendor is still choosing).
  /// Existing boards are never modified. Throws on an invalid plan.
  List<Board> addMediaGroups(
    String shopId,
    List<MediaGroupPlan> plans, {
    int? totalBoards,
  }) {
    final s = shop(shopId);
    if (s == null) throw StateError('Shop not found');
    if (!canEdit(s)) throw StateError('This recce is read-only now');
    // Validate against the total the vendor actually requested (not only a
    // total recomputed from the plans).
    final total = totalBoards ?? plans.fold<int>(0, (t, p) => t + p.quantity);
    final err = SignageCatalog.validateGroupPlans(total, plans);
    if (err != null) throw ArgumentError(err);
    if (plans.any((p) => p.quantity > maxQuantity)) {
      throw ArgumentError('At most $maxQuantity boards per media type.');
    }
    final created = <Board>[];
    for (final p in plans) {
      final b = Board(
        id: _newBoardId(s),
        name: '',
        mediaCode: p.option.mediaCode,
        doubleSided: p.option.doubleSided,
        nlbSubtype: p.option.nlbSubtype,
        quantity: p.quantity,
        checklistRequired: true,
      );
      b.name = SignageCatalog.nextBoardName(b, s.boards);
      s.boards.add(b);
      created.add(b);
    }
    touchShop(
      s,
      title: 'Media types added',
      message:
          '${created.map((b) => '${b.name} ×${b.quantity}').join(', ')} '
          'added to ${s.name}.',
    );
    return created;
  }

  /// In-memory marker of the last explicit "Save as Draft" per board.
  final Map<String, DateTime> _draftSavedAt = {};

  /// [b] was explicitly saved as a draft and has not changed since.
  bool isDraftSaved(Board b) {
    final saved = _draftSavedAt[b.id];
    return saved != null && !b.updatedAt.isAfter(saved);
  }

  /// True when switching away from [b] should offer "Save as Draft?":
  /// the board is incomplete and changed since the last explicit save.
  bool needsDraftPrompt(Board b) {
    if (boardIssues(b).isEmpty) return false;
    final saved = _draftSavedAt[b.id];
    return saved == null || b.updatedAt.isAfter(saved);
  }

  /// Saves [b] as a draft (local store; no submission validation). Returns
  /// false when the write failed, so the caller stays on the board.
  Future<bool> saveDraft(String shopId, Board b) async {
    final s = shop(shopId);
    if (s == null) return false;
    // Reuses the normal local write queue; a failed write sets
    // [storageError] (already surfaced with Retry on the home screen).
    await retrySave();
    if (storageError != null) return false;
    _draftSavedAt[b.id] = b.updatedAt;
    return true;
  }

  Board duplicateBoard(String shopId, String boardId) {
    final s = shop(shopId)!;
    final src = board(shopId, boardId)!;
    final copy = Board(
      id: newId('b'),
      name: '${src.name} (copy)',
      mediaCode: src.mediaCode,
      installationCode: src.installationCode,
      answers: Map<String, dynamic>.from(src.answers),
      width: src.width,
      height: src.height,
      unit: src.unit,
      quantity: src.quantity,
      sizeMode: src.sizeMode,
      checklistRequired: true,
    );
    // Same configuration, fresh unit ids (photos / previews are not copied).
    copy.units
      ..clear()
      ..addAll([
        for (var i = 0; i < src.units.length; i++)
          src.units[i].copyWith(id: '${copy.id}_u${i + 1}'),
      ]);
    copy.unitSeq = copy.units.length;
    copy.syncUnits();
    // Evidence photos belong to the source group; they are not copied.
    for (final u in copy.units) {
      u.checklist = {
        for (final e in u.checklist.entries)
          e.key: e.value.copyWith(evidencePhotoIds: const []),
      };
      u.electrical = ElectricalSurvey.fromJson({
        ...u.electrical.toJson(),
        'evidencePhotoIds': const <String>[],
      });
    }
    s.boards.add(copy);
    touchShop(s, title: 'Board duplicated', message: '${copy.name} created.');
    return copy;
  }

  /// Persist changes made directly on a board's fields.
  void touchBoard(
    String shopId,
    Board board, {
    String? title,
    String? message,
  }) {
    final s = shop(shopId);
    if (s == null) return;
    board.updatedAt = DateTime.now();
    touchShop(s, title: title, message: message);
  }

  /// Replace a board by id (used by editors that work on a copy).
  void updateBoard(
    String shopId,
    Board updated, {
    String? title,
    String? message,
  }) {
    final s = shop(shopId);
    if (s == null) return;
    final i = s.boards.indexWhere((b) => b.id == updated.id);
    if (i < 0) return;
    s.boards[i] = updated;
    touchBoard(shopId, updated, title: title, message: message);
  }

  Future<void> deleteBoard(String shopId, String boardId) async {
    final s = shop(shopId);
    final b = board(shopId, boardId);
    if (s == null || b == null) return;
    await _deleteBoardMedia(s, b);
    s.boards.remove(b);
    final unitIds = b.units.map((u) => u.id).toSet();
    _forgetArUnits(s, unitIds);
    for (final other in s.boards) {
      for (final p in other.photos) {
        p.markup.forgetUnits(unitIds);
      }
    }
    touchShop(s, title: 'Board removed', message: '${b.name} removed.');
  }

  void addPhoto(String shopId, String boardId, SitePhoto photo) {
    final b = board(shopId, boardId);
    if (b == null) return;
    b.photos.add(photo);
    touchBoard(
      shopId,
      b,
      title: 'Photo captured',
      message: '${photo.label} added to ${b.name}.',
    );
  }

  Future<void> removePhoto(
    String shopId,
    String boardId,
    String photoId,
  ) async {
    final s = shop(shopId);
    final b = board(shopId, boardId);
    if (s == null || b == null) return;
    final photo = b.photos.where((p) => p.id == photoId).firstOrNull;
    if (photo == null) return;
    b.photos.remove(photo);
    if (!_referencedInSnapshots(s, photo.path)) {
      await media?.deleteIfExists(photo.path);
    }
    touchBoard(shopId, b);
  }

  void setAnnotations(
    String shopId,
    String boardId,
    String photoId,
    List<Annotation> annotations,
  ) {
    final b = board(shopId, boardId);
    if (b == null) return;
    final photo = b.photos.where((p) => p.id == photoId).firstOrNull;
    if (photo == null) return;
    photo.annotations = annotations.map((a) => a.copy()).toList();
    touchBoard(
      shopId,
      b,
      title: 'Photo annotated',
      message: '${annotations.length} marking(s) saved on ${photo.label}.',
    );
  }

  void addVoiceNote(String shopId, String boardId, VoiceNote note) {
    final b = board(shopId, boardId);
    if (b == null) return;
    b.voiceNotes.add(note);
    touchBoard(
      shopId,
      b,
      title: 'Voice note recorded',
      message: 'Voice note added to ${b.name}.',
    );
  }

  Future<void> removeVoiceNote(
    String shopId,
    String boardId,
    String noteId,
  ) async {
    final s = shop(shopId);
    final b = board(shopId, boardId);
    if (s == null || b == null) return;
    final note = b.voiceNotes.where((n) => n.id == noteId).firstOrNull;
    if (note == null) return;
    b.voiceNotes.remove(note);
    if (!_referencedInSnapshots(s, note.path)) {
      await media?.deleteIfExists(note.path);
    }
    touchBoard(shopId, b);
  }

  bool _referencedInSnapshots(Shop shop, String path) =>
      shop.submissions.any((s) => jsonEncode(s.snapshot).contains(path));

  Future<void> _deleteBoardMedia(Shop s, Board b) async {
    final paths = [
      ...b.photos.map((p) => p.path),
      ...b.voiceNotes.map((v) => v.path),
      ...b.previews.map((c) => c.path),
      ...b.comparisons.map((c) => c.path),
      ?b.drawingPath,
    ];
    for (final p in paths) {
      if (!_referencedInSnapshots(s, p)) await media?.deleteIfExists(p);
    }
  }

  // ---------------------------------------------------------------------------
  // Media groups: quantity, size mode and individual signage units
  // ---------------------------------------------------------------------------

  /// Largest quantity accepted for one media group.
  static const maxQuantity = 99;

  /// In "different sizes" mode the group's own width/height mirror unit 1 so
  /// the 2D drawing / 3D preview of the group keep working unchanged.
  void _mirrorPrimarySize(Board b) {
    if (b.isSameSize || b.units.isEmpty) return;
    final first = b.units.first;
    b.width = first.width;
    b.height = first.height;
  }

  /// Raises the quantity. Only the additional units are created; existing
  /// units, photos and ids are untouched.
  void increaseQuantity(String shopId, Board b, int quantity) {
    final q = quantity.clamp(1, maxQuantity);
    if (q <= b.quantity) return;
    final before = b.quantity;
    b.quantity = q;
    b.syncUnits();
    if (!b.isSameSize) {
      // New units start with the first unit's size as a sensible default.
      for (final u in b.activeUnits.skip(before)) {
        if (!u.hasOwnSize) {
          u.width = b.units.first.width;
          u.height = b.units.first.height;
        }
      }
    }
    touchBoard(
      shopId,
      b,
      title: 'Quantity updated',
      message: '${b.name}: quantity $before → $q.',
    );
  }

  /// Units that would be removed when lowering the quantity to [quantity].
  List<SignageUnit> unitsRemovedBy(Board b, int quantity) {
    final q = quantity.clamp(1, maxQuantity);
    return q >= b.units.length ? const [] : b.units.sublist(q);
  }

  /// What is attached to [units] (shown before a removal is confirmed).
  ({int photos, int markings, int previews, int notes}) unitAttachments(
    Board b,
    Iterable<SignageUnit> units,
  ) {
    final ids = units.map((u) => u.id).toSet();
    return (
      photos: b.photos
          .where(
            (p) =>
                p.unitIds.any(ids.contains) ||
                p.annotations.any((a) => ids.contains(a.itemId)),
          )
          .length,
      markings: b.photos.fold(
        0,
        (s, p) => s + p.annotations.where((a) => ids.contains(a.itemId)).length,
      ),
      previews: b.previews
          .where((c) => c.unitIds.length == 1 && ids.contains(c.unitId))
          .length,
      notes: units
          .where(
            (u) =>
                u.notes.trim().isNotEmpty ||
                u.placement.trim().isNotEmpty ||
                u.installationDetails.trim().isNotEmpty,
          )
          .length,
    );
  }

  /// Lowers the quantity (call only after the user confirmed the removal).
  /// Removes the trailing units, their placement markings and previews that
  /// show only them. Shared photos stay; files still referenced by a
  /// submitted version are kept on disk.
  Future<void> reduceQuantity(String shopId, Board b, int quantity) async {
    final removed = unitsRemovedBy(b, quantity);
    if (removed.isEmpty) return;
    await _removeUnits(shopId, b, removed);
  }

  /// Removes one specific unit (minimum one unit per group).
  Future<void> removeUnit(String shopId, Board b, String unitId) async {
    final u = b.unitById(unitId);
    if (u == null || b.units.length <= 1) return;
    await _removeUnits(shopId, b, [u]);
  }

  Future<void> _removeUnits(
    String shopId,
    Board b,
    List<SignageUnit> removed,
  ) async {
    final s = shop(shopId);
    if (s == null) return;
    final ids = removed.map((u) => u.id).toSet();
    final labels = removed.map(b.unitLabel).join(', ');
    for (final p in b.photos) {
      p.unitIds.removeWhere(ids.contains);
      p.annotations.removeWhere((a) => ids.contains(a.itemId));
    }
    for (final other in s.boards) {
      for (final p in other.photos) {
        p.markup.forgetUnits(ids);
      }
    }
    for (final r
        in b.comparisons.where((r) => ids.contains(r.unitId)).toList()) {
      b.comparisons.remove(r);
      if (!_referencedInSnapshots(s, r.path)) {
        await media?.deleteIfExists(r.path);
      }
    }
    final orphaned = b.previews
        .where((c) => c.unitIds.every(ids.contains))
        .toList();
    for (final c in orphaned) {
      b.previews.remove(c);
      if (!_referencedInSnapshots(s, c.path)) {
        await media?.deleteIfExists(c.path);
      }
    }
    for (final c in b.previews) {
      c.overlays.removeWhere((o) => ids.contains(o.unitId));
    }
    _forgetArUnits(s, ids);
    // [Board.answers] belongs to the first unit. When that unit is removed,
    // the next unit becomes first: its own answers move into the group map
    // and the removed unit's answers are archived (not lost).
    final first = SignageCatalog.firstUnit(b);
    final next = b.units.where((u) => !ids.contains(u.id)).firstOrNull;
    if (first != null && ids.contains(first.id) && next != null) {
      for (final e in b.answers.entries) {
        b.answersArchive.putIfAbsent(e.key, () => e.value);
      }
      b.answers = Map<String, dynamic>.from(next.siteAnswers);
      next.siteAnswers = {};
    }
    b.units.removeWhere((u) => ids.contains(u.id));
    b.quantity = math.max(1, b.units.length);
    b.syncUnits();
    if (b.quantity == 1 && b.sizeMode == SizeMode.different) {
      final only = b.units.first;
      if (only.hasOwnSize) {
        b.width = only.width;
        b.height = only.height;
      }
      b.sizeMode = SizeMode.same;
    }
    _mirrorPrimarySize(b);
    touchBoard(
      shopId,
      b,
      title: 'Quantity updated',
      message: '${b.name}: removed $labels (now ${b.quantity}).',
    );
  }

  /// Switches between "same size" and "different sizes".
  ///
  /// * same → different: the shared size is copied into every unit so each
  ///   can then be edited independently.
  /// * different → same: [fromUnitId] picks whose size applies to all.
  void setSizeMode(
    String shopId,
    Board b,
    SizeMode mode, {
    String? fromUnitId,
  }) {
    if (b.sizeMode == mode) return;
    if (mode == SizeMode.different) {
      for (final u in b.activeUnits) {
        u.width = b.width;
        u.height = b.height;
      }
      b.sizeMode = SizeMode.different;
      _mirrorPrimarySize(b);
      touchBoard(
        shopId,
        b,
        title: 'Size mode changed',
        message: '${b.name}: each unit now has its own size.',
      );
      return;
    }
    final src = b.unitById(fromUnitId) ?? b.units.first;
    b.width = src.width;
    b.height = src.height;
    b.sizeMode = SizeMode.same;
    touchBoard(
      shopId,
      b,
      title: 'Size mode changed',
      message:
          '${b.name}: all units set to ${fmtSize(b.width, b.height, b.unit)} '
          '(from ${b.unitLabel(src)}).',
    );
  }

  /// Sets one unit's own size (different-sizes mode).
  void setUnitSize(
    String shopId,
    Board b,
    SignageUnit u, {
    double? width,
    double? height,
  }) {
    u.width = width;
    u.height = height;
    _mirrorPrimarySize(b);
    touchBoard(shopId, b);
  }

  /// Persists edits made directly on a unit's fields.
  // ---------------------------------------------------------------------------
  // Per-board installation, naming and common answers
  // ---------------------------------------------------------------------------

  /// Names a group after its media ("GSB Single 01") only while its name is
  /// still app-generated; a manually edited name is never touched.
  void autoNameBoard(String shopId, Board b) {
    final s = shop(shopId);
    if (s == null || SignageCatalog.media(b.mediaCode) == null) return;
    if (!SignageCatalog.isAutoBoardName(b.name)) return;
    b.name = SignageCatalog.nextBoardName(b, s.boards);
  }

  /// After a media / subtype change: a unit override that is not valid for
  /// the new media is cleared (never silently kept or substituted).
  void dropInvalidUnitInstallations(Board b) {
    for (final u in b.units) {
      final code = u.installationCode;
      if (code != null && !SignageCatalog.allowsInstallation(b, code)) {
        u.installationCode = null;
      }
    }
  }

  /// Editor step last shown per board (in memory), so switching media tabs
  /// returns to the same place.
  final Map<String, int> editorStep = {};

  /// Physical board last selected in the editor per media group (memory).
  final Map<String, String> editorUnit = {};

  /// Sets ONE unit's installation (its own override). The group code and the
  /// other units are never touched. Returns false when [code] is not a valid
  /// choice for this media / variant.
  bool setUnitInstallation(
    String shopId,
    Board b,
    SignageUnit u,
    String? code,
  ) {
    final s = shop(shopId);
    if (s == null || !canEdit(s)) return false;
    if (code != null && !SignageCatalog.allowsInstallation(b, code)) {
      return false;
    }
    u.installationCode = code;
    touchUnit(
      shopId,
      b,
      u,
      message:
          '${b.name} ${SignageCatalog.unitName(b, u)}: installation '
          '${SignageCatalog.installation(b.installationOf(u))?.name ?? '—'}.',
    );
    return true;
  }

  /// "Same Installation": explicit action that applies [code] to the group
  /// and clears every unit override (callers confirm when overrides differ).
  bool setSameInstallation(String shopId, Board b, String code) {
    final s = shop(shopId);
    if (s == null || !canEdit(s)) return false;
    if (!SignageCatalog.allowsInstallation(b, code)) return false;
    b.installationCode = code;
    for (final u in b.units) {
      u.installationCode = null;
    }
    touchBoard(
      shopId,
      b,
      title: 'Board updated',
      message:
          '${b.name}: installation set to '
          '${SignageCatalog.installation(code)?.name ?? code} for all boards.',
    );
    return true;
  }

  /// Copies the common, applicable answers of [source] into [target]. Only
  /// unanswered target fields are filled unless [overwrite] is true. The
  /// values are copied (no live link); provenance is stored on the target.
  /// Returns the number of answers written.
  int copyCommonAnswers(
    String shopId,
    Board source,
    Board target, {
    bool overwrite = false,
    Set<String>? onlyIds,
    SignageUnit? sourceUnit,
    SignageUnit? targetUnit,
  }) {
    final s = shop(shopId);
    if (s == null || !canEdit(s)) return 0;
    final su = sourceUnit ?? SignageCatalog.firstUnit(source);
    final tu = targetUnit ?? SignageCatalog.firstUnit(target);
    if (su == null || tu == null) return 0;
    if (source.id == target.id && su.id == tu.id) return 0;
    final plan = SignageCatalog.planUnitAnswers(source, su, target, tu);
    final qs = [...plan.toCopy, if (overwrite) ...plan.wouldOverwrite];
    final from = SignageCatalog.answersOf(source, su);
    final to = SignageCatalog.answersOf(target, tu);
    var n = 0;
    for (final q in qs) {
      if (onlyIds != null && !onlyIds.contains(q.id)) continue;
      final v = from[q.id];
      // Independent value (no shared mutable reference).
      to[q.id] = v is List ? [...v] : (v is Map ? {...v} : v);
      QuestionEquivalence.syncToChecklist(target, tu, q.id);
      n++;
    }
    // Common checklist-only questions (never evidence, never installation
    // specific, never answers the target already has unless overwriting).
    final cqs = [
      ...plan.toCopyChecklist,
      if (overwrite) ...plan.wouldOverwriteChecklist,
    ];
    for (final q in cqs) {
      final r = su.checklist[q.id];
      if (r == null || !r.hasValue) continue;
      tu.checklist[q.id] = ChecklistResponse(
        questionId: q.id,
        value: r.value,
        remarks: r.remarks,
      );
      n++;
    }
    if (n == 0) return 0;
    // Provenance (source + time) lives in the activity log entry below; the
    // answers map itself only ever holds real question ids.
    touchBoard(
      shopId,
      target,
      title: 'Common answers copied',
      message:
          '${SignageCatalog.unitName(target, tu)}: $n answer(s) copied from '
          '${SignageCatalog.unitName(source, su)}.',
    );
    return n;
  }

  /// Saves one Site Question answer of ONE physical board (null = cleared).
  /// Mirrored structure answers update only that unit's measurements.
  void setUnitAnswer(
    String shopId,
    Board b,
    SignageUnit u,
    String questionId,
    Object? value,
  ) {
    final a = SignageCatalog.answersOf(b, u);
    if (value == null) {
      a.remove(questionId);
    } else {
      a[questionId] = value;
    }
    _syncUnitAnswerToMeasurements(b, u, questionId, a[questionId]);
    // One answer for both validation systems (verified equivalents only).
    QuestionEquivalence.syncToChecklist(b, u, questionId);
    touchBoard(shopId, b);
  }

  void _syncUnitAnswerToMeasurements(
    Board b,
    SignageUnit u,
    String answerId,
    Object? v,
  ) {
    final target = kAnswerMirrors[answerId];
    final isShutter = answerId == 'shutter_height';
    if (target == null && !isShutter) return;
    final inst = b.installationOf(u);
    if (target == 'bottom_height' && answerId != mountAnswerKey(inst)) return;
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    final id = isShutter ? 'bottom_height' : target!;
    if (d == null) {
      u.measurements.valuesMm.remove(id);
      u.measurements.counts.remove(id);
    } else if (id == 'pipe_count') {
      u.measurements.counts[id] = d;
    } else {
      u.measurements.valuesMm[id] = (isShutter ? d + 0.5 : d) * 304.8;
    }
  }

  /// Required Site Questions still unanswered for unit [u] (its own
  /// installation + answers) PLUS its required site-checklist questions.
  /// This is the single count shown by the Site Questions step.
  int siteQuestionsPendingFor(Board b, SignageUnit u) {
    var n = SignageCatalog.missingAnswersFor(b, u).length;
    // Checklist-only questions; verified equivalents are counted above.
    if (b.checklistRequired) n += SiteChecklists.uniqueMissing(b, u).length;
    return n;
  }

  /// [siteQuestionsPendingFor] summed over every active physical board.
  int siteQuestionsPending(Board b) {
    if (b.activeUnits.isEmpty) return SignageCatalog.missingAnswers(b).length;
    return b.activeUnits.fold(0, (s, u) => s + siteQuestionsPendingFor(b, u));
  }

  void touchUnit(String shopId, Board b, SignageUnit u, {String? message}) {
    touchBoard(
      shopId,
      b,
      title: message == null ? null : 'Signage unit updated',
      message: message,
    );
  }

  /// Links / unlinks a shared photo to signage units of its group.
  void setPhotoUnits(
    String shopId,
    String boardId,
    String photoId,
    Iterable<String> unitIds,
  ) {
    final b = board(shopId, boardId);
    final p = b?.photos.where((e) => e.id == photoId).firstOrNull;
    if (b == null || p == null) return;
    final valid = b.units.map((u) => u.id).toSet();
    p.unitIds = unitIds.where(valid.contains).toSet().toList();
    touchBoard(shopId, b);
  }

  // ---------------------------------------------------------------------------
  // Camera AR layouts (preview configuration, not recce business data)
  // ---------------------------------------------------------------------------

  /// Saved AR layouts of a shop, newest first.
  List<ArLayout> arLayoutsForShop(String shopId) =>
      _data.arLayouts.where((l) => l.shopId == shopId).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  ArLayout? arLayout(String layoutId) {
    for (final l in _data.arLayouts) {
      if (l.id == layoutId) return l;
    }
    return null;
  }

  /// Inserts or replaces (same id) a layout. Not logged in the recce
  /// activity history: it is a preview, not a change to the recce.
  void saveArLayout(ArLayout layout) {
    final i = _data.arLayouts.indexWhere((l) => l.id == layout.id);
    if (i < 0) {
      _data.arLayouts.add(layout);
    } else {
      _data.arLayouts[i] = layout;
    }
    _commit();
  }

  void deleteArLayout(String layoutId) {
    final before = _data.arLayouts.length;
    _data.arLayouts.removeWhere((l) => l.id == layoutId);
    if (_data.arLayouts.length != before) _commit();
  }

  /// Drops AR references to removed signage units so no layout or capture
  /// keeps a dangling Signage Item ID.
  void _forgetArUnits(Shop s, Set<String> unitIds) {
    if (unitIds.isEmpty) return;
    for (final l in _data.arLayouts) {
      if (l.shopId != s.id) continue;
      l.objects.removeWhere((o) => unitIds.contains(o.signageItemId));
    }
    for (final b in s.boards) {
      for (final c in b.previews) {
        c.visibleUnitIds.removeWhere(unitIds.contains);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Live previews, AR captures and exported annotated photos
  // ---------------------------------------------------------------------------

  void addPreview(String shopId, String boardId, PreviewCapture capture) {
    final b = board(shopId, boardId);
    if (b == null) return;
    b.previews.add(capture);
    final unit = b.unitById(capture.unitId);
    touchBoard(
      shopId,
      b,
      title: '${capture.kind.label} saved',
      message:
          '${capture.kind.label} saved for ${b.name}'
          '${unit == null ? '' : ' – ${b.unitLabel(unit)}'}.',
    );
  }

  /// Deletes a preview image. The original site photo is never touched.
  Future<void> removePreview(
    String shopId,
    String boardId,
    String captureId,
  ) async {
    final s = shop(shopId);
    final b = board(shopId, boardId);
    if (s == null || b == null) return;
    final c = b.previews.where((e) => e.id == captureId).firstOrNull;
    if (c == null) return;
    b.previews.remove(c);
    // Generated companions (night render / comparison PDF) go with the
    // preview; the original site photo is never one of them.
    for (final path in [c.path, ...c.companionPaths]) {
      if (!_referencedInSnapshots(s, path)) {
        await media?.deleteIfExists(path);
      }
    }
    touchBoard(
      shopId,
      b,
      title: '${c.kind.label} deleted',
      message: '${c.kind.label} removed from ${b.name}.',
    );
  }

  // ---------------------------------------------------------------------------
  // Advanced site survey: markup, measurements, checklist, electrical
  // ---------------------------------------------------------------------------

  SitePhoto? photo(String shopId, String boardId, String photoId) =>
      board(shopId, boardId)?.photos.where((p) => p.id == photoId).firstOrNull;

  /// Saves the advanced markings of a photo, replacing the previous set.
  /// One activity entry per meaningful change (never per drag).
  void saveSiteMarkup(
    String shopId,
    String boardId,
    String photoId,
    SiteMarkup markup,
  ) {
    final s = shop(shopId);
    final b = board(shopId, boardId);
    final p = photo(shopId, boardId, photoId);
    if (s == null || b == null || p == null) return;
    final next = markup.copy();
    final events = siteMarkupEvents(p.markup, next);
    p.markup = next;
    b.updatedAt = DateTime.now();
    for (final (title, message) in events) {
      _log('updated', title, '${b.name} • ${p.label}: $message', shop: s);
    }
    touchShop(s);
  }

  /// Activity entries describing what changed between two markup sets.
  static List<(String, String)> siteMarkupEvents(
    SiteMarkup before,
    SiteMarkup after,
  ) {
    final out = <(String, String)>[];
    final oldP = {for (final p in before.perspectives) p.id: p};
    final changedP = after.perspectives.where((p) {
      final o = oldP[p.id];
      return o == null ||
          o.unitId != p.unitId ||
          !listEquals(o.corners, p.corners) ||
          o.showArtwork != p.showArtwork;
    }).length;
    if (changedP > 0) {
      out.add((
        'Perspective placement saved',
        '$changedP perspective board placement(s) saved',
      ));
    }
    final oldM = before.markers.map((m) => m.id).toSet();
    final addedM = after.markers.where((m) => !oldM.contains(m.id)).length;
    if (addedM > 0) {
      out.add(('Placement marker added', '$addedM board marker(s) added'));
    }
    final oldE = {
      ...before.electrical.map((e) => e.id),
      ...before.cableRoutes.map((c) => c.id),
    };
    final addedE = [
      ...after.electrical.where((e) => !oldE.contains(e.id)).map((e) => e.code),
      ...after.cableRoutes
          .where((c) => !oldE.contains(c.id))
          .map((c) => c.code),
    ];
    if (addedE.isNotEmpty) {
      out.add(('Electrical mapping updated', addedE.join(', ')));
    }
    final oldO = before.obstructions.map((o) => o.id).toSet();
    final addedO = after.obstructions.where((o) => !oldO.contains(o.id));
    if (addedO.isNotEmpty) {
      out.add((
        'Obstruction added',
        addedO
            .map((o) => '${o.code} ${o.type.label} (${o.severity.label})')
            .join(', '),
      ));
    }
    Set<String> ids(SiteMarkup m) => {
      ...m.perspectives.map((e) => e.id),
      ...m.markers.map((e) => e.id),
      ...m.electrical.map((e) => e.id),
      ...m.cableRoutes.map((e) => e.id),
      ...m.obstructions.map((e) => e.id),
    };
    final removed = ids(before).difference(ids(after)).length;
    if (removed > 0) {
      out.add(('Site markings removed', '$removed marking(s) removed'));
    }
    return out;
  }

  /// Validates and saves the advanced measurements of a unit. Nothing is
  /// saved when a blocking error is found; all findings are returned.
  List<MeasurementIssue> saveMeasurements(
    String shopId,
    Board b,
    String unitId,
    MeasurementDetails m,
  ) {
    final u = b.unitById(unitId);
    if (u == null) return const [];
    final issues = MeasurementCatalog.validate(b, u, m);
    if (issues.any((i) => i.isError)) return issues;
    u.measurements = m.copy()..updatedAt = _clock();
    final n = MeasurementCatalog.recorded(b, u).length;
    touchBoard(
      shopId,
      b,
      title: 'Measurements updated',
      message: '${b.name} – ${b.unitLabel(u)}: $n measurement(s) recorded.',
    );
    return issues;
  }

  /// Saves checklist responses of a unit. Responses to questions that no
  /// longer apply are kept (never silently erased).
  void saveChecklist(
    String shopId,
    Board b,
    String unitId,
    Map<String, ChecklistResponse> responses,
  ) {
    final u = b.unitById(unitId);
    if (u == null) return;
    final was = SiteChecklists.statusOf(b, u);
    u.checklist = Map.of(responses);
    final now = SiteChecklists.statusOf(b, u);
    final completed =
        now.isComplete && now.total > 0 && !(was.isComplete && was.isStarted);
    touchBoard(
      shopId,
      b,
      title: completed ? 'Checklist completed' : null,
      message:
          '${b.name} – ${b.unitLabel(u)}: ${now.answered}/${now.total} '
          'answered.',
    );
  }

  /// Copies [fromUnitId]'s checklist answers to the other units of [b]
  /// (evidence photos are not copied). Returns the number of units updated.
  int copyChecklistToOtherUnits(String shopId, Board b, String fromUnitId) {
    final from = b.unitById(fromUnitId);
    if (from == null || from.checklist.isEmpty) return 0;
    var n = 0;
    final fromInst = b.installationOf(from);
    for (final u in b.activeUnits) {
      if (u.id == from.id) continue;
      // Only questions that apply to THIS board's installation and are not
      // answered yet are copied; evidence, installation-specific answers
      // and verified Site Question equivalents are never cloned.
      final applicable = {
        for (final q in SiteChecklists.questionsFor(
          b.mediaCode,
          b.installationOf(u),
        ))
          q.id: q,
      };
      final mapped = QuestionEquivalence.mappedChecklistIds(b, u);
      var copied = 0;
      for (final e in from.checklist.entries) {
        final q = applicable[e.key];
        if (q == null ||
            mapped.contains(q.id) ||
            q.type == ChecklistResponseType.photoEvidence ||
            (q.installations != null && b.installationOf(u) != fromInst)) {
          continue;
        }
        if (q.isAnswered(u.checklist[q.id])) continue;
        u.checklist[q.id] = ChecklistResponse(
          questionId: q.id,
          value: e.value.value,
          remarks: e.value.remarks,
          answeredAt: _clock(),
        );
        copied++;
      }
      if (copied > 0) n++;
    }
    if (n > 0) {
      touchBoard(
        shopId,
        b,
        title: 'Checklist copied',
        message:
            '${b.name}: answers of ${b.unitLabel(from)} copied to $n unit(s).',
      );
    }
    return n;
  }

  void saveElectrical(
    String shopId,
    Board b,
    String unitId,
    ElectricalSurvey e,
  ) {
    final u = b.unitById(unitId);
    if (u == null) return;
    u.electrical = ElectricalSurvey.fromJson({
      ...e.toJson(),
      'updatedAt': _clock().toIso8601String(),
    });
    touchBoard(
      shopId,
      b,
      title: 'Electrical survey updated',
      message:
          '${b.name} – ${b.unitLabel(u)}: electricity '
          '${e.electricityAvailable?.label ?? 'not recorded'}.',
    );
  }

  // ---------------------------------------------------------------------------
  // Signage model spec: two-way measurement sync (single source of truth)
  // ---------------------------------------------------------------------------

  /// Current model spec of a signage item (resolved from canonical data).
  SignageModelSpec? modelSpec(String shopId, String boardId, String unitId) {
    final b = board(shopId, boardId);
    final u = b?.unitById(unitId);
    if (b == null || u == null) return null;
    return SignageModelSpec.of(b, u);
  }

  /// Commits edited model dimensions to the canonical recce data: width /
  /// height to the board size (respecting same / different sizes), every
  /// other value to the unit's measurements, with legacy site answers kept
  /// mirrored. Nothing is written when validation fails; the problems are
  /// returned. Read-only recces throw.
  List<String> applySpecEdits(
    String shopId,
    String boardId,
    String unitId,
    Map<SpecField, double> edits,
  ) {
    final s = shop(shopId);
    final b = board(shopId, boardId);
    final u = b?.unitById(unitId);
    if (s == null || b == null || u == null) return const ['Item not found'];
    if (!canEdit(s)) throw StateError('This recce is read-only now');
    if (edits.isEmpty) return const [];
    final problems = SignageModelSpec.validate(edits);
    if (problems.isNotEmpty) return problems;

    // Validate the measurement record that would result.
    final m = u.measurements.copy();
    for (final e in edits.entries) {
      final id = e.key.measureId;
      if (id == null) continue;
      if (e.key.kind == SpecValueKind.length) {
        m.valuesMm[id] = e.value;
      } else {
        m.counts[id] = e.value;
      }
    }
    final w = edits[SpecField.width];
    final h = edits[SpecField.height];
    final probe = b.copy();
    final pu = probe.unitById(u.id)!..measurements = m;
    if (w != null || h != null) {
      final cw = w == null ? probe.widthOf(pu) : b.unit.fromMm(w);
      final ch = h == null ? probe.heightOf(pu) : b.unit.fromMm(h);
      if (probe.isSameSize) {
        probe
          ..width = cw
          ..height = ch;
      } else {
        pu
          ..width = cw
          ..height = ch;
      }
    }
    final errors = MeasurementCatalog.validate(
      probe,
      pu,
      m,
    ).where((i) => i.isError).map((i) => i.message).toList();
    if (errors.isNotEmpty) return errors;

    // Commit.
    if (w != null || h != null) {
      final cw = w == null ? b.widthOf(u) : b.unit.fromMm(w);
      final ch = h == null ? b.heightOf(u) : b.unit.fromMm(h);
      if (b.isSameSize) {
        b
          ..width = cw
          ..height = ch;
      } else {
        u
          ..width = cw
          ..height = ch;
        _mirrorPrimarySize(b);
      }
    }
    u.measurements = m..updatedAt = _clock();
    // Keep legacy answers equal to the canonical value (single-unit groups
    // only – with several units each unit owns its own structure values).
    if (b.quantity == 1) _mirrorToAnswers(b, u);
    final names = edits.keys.map((f) => f.label).join(', ');
    touchBoard(
      shopId,
      b,
      title: 'Measurements updated',
      message: '${b.name} – ${b.unitLabel(u)}: $names (from 3D view).',
    );
    return const [];
  }

  void _mirrorToAnswers(Board b, SignageUnit u) {
    final m = u.measurements;
    const ft = 304.8;
    final mountKey = mountAnswerKey(b.installationOf(u));
    final questions = SignageCatalog.questionsFor(
      b.mediaCode,
      b.installationOf(u),
    ).map((q) => q.id).toSet();
    for (final e in kAnswerMirrors.entries) {
      if (!questions.contains(e.key)) continue;
      if (e.value == 'bottom_height' && e.key != mountKey) continue;
      final mm = m.valuesMm[e.value];
      final count = m.counts[e.value];
      if (mm != null) {
        b.answers[e.key] = double.parse((mm / ft).toStringAsFixed(4));
      } else if (count != null) {
        b.answers[e.key] = count;
      }
    }
    if (b.installationOf(u) == SignageCatalog.shopFascia &&
        questions.contains('shutter_height')) {
      final mm = m.valuesMm['bottom_height'];
      if (mm != null) {
        b.answers['shutter_height'] = double.parse(
          (mm / ft - 0.5).clamp(0, 1e6).toStringAsFixed(4),
        );
      }
    }
  }

  /// Keeps a site-question answer and the canonical measurement in step:
  /// called when the media group's site form changes a mirrored answer.
  void syncAnswerToMeasurements(Board b, String answerId) {
    final target = kAnswerMirrors[answerId];
    final isShutter = answerId == 'shutter_height';
    if (target == null && !isShutter) return;
    final v = b.answers[answerId];
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    // [Board.answers] belongs to the group's first unit only (other units
    // own their answers): never push one board's value into another board.
    for (final u in b.activeUnits.take(1)) {
      final inst = b.installationOf(u);
      if (target == 'bottom_height' && answerId != mountAnswerKey(inst)) {
        continue;
      }
      final id = isShutter ? 'bottom_height' : target!;
      if (d == null) {
        u.measurements.valuesMm.remove(id);
        u.measurements.counts.remove(id);
      } else if (id == 'pipe_count') {
        u.measurements.counts[id] = d;
      } else {
        u.measurements.valuesMm[id] = (isShutter ? d + 0.5 : d) * 304.8;
      }
    }
  }

  /// Explicitly maps a legacy media group to a catalog media type. The
  /// original code is kept on the group; submitted snapshots never change.
  void mapLegacyMedia(
    String shopId,
    Board b,
    String newCode, {
    bool? doubleSided,
  }) {
    final s = shop(shopId);
    final m = SignageCatalog.media(newCode);
    final from = b.mediaCode;
    if (s == null || m == null || m.legacy) return;
    if (!canEdit(s)) throw StateError('This recce is read-only now');
    final mapping = SignageCatalog.legacyMapping(from);
    if (mapping == null || !mapping.candidates.contains(newCode)) {
      throw StateError('$newCode is not a mapping option for $from');
    }
    b.legacyMediaCode ??= from;
    b.mediaCode = newCode;
    if (m.sidedness == MediaSidedness.selectable) b.doubleSided = doubleSided;
    if (!SignageCatalog.allowsInstallation(b, b.installationCode)) {
      b.installationCode = null;
    }
    touchBoard(
      shopId,
      b,
      title: 'Media type mapped',
      message:
          '${b.name}: legacy ${SignageCatalog.media(from)?.shortName ?? from} '
          'mapped to ${m.name} (catalog v${SignageCatalog.catalogVersion}).',
    );
  }

  /// Sets single / double-sided for media with a selectable sidedness.
  void setDoubleSided(String shopId, Board b, bool doubleSided) {
    b.doubleSided = doubleSided;
    dropInvalidUnitInstallations(b);
    autoNameBoard(shopId, b);
    touchBoard(
      shopId,
      b,
      title: 'Board updated',
      message: '${b.name}: ${doubleSided ? 'double' : 'single'}-sided.',
    );
  }

  // ---------------------------------------------------------------------------
  // GSB fabrication spec overrides (depth / frame profile / wall thickness)
  // ---------------------------------------------------------------------------

  /// Records a vendor-proposed GSB spec override. Never approves anything:
  /// the entry is stored as "Requires Engineering Review". Returns an error
  /// message (nothing saved) or null on success.
  String? addGsbOverride(
    String shopId,
    Board b, {
    required String unitId,
    required GsbOverrideField field,
    required double? originalIn,
    required double proposedIn,
    required String reason,
    required String ruleVersion,
  }) {
    final s = shop(shopId);
    if (s == null || b.unitById(unitId) == null) return 'Item not found';
    if (!canEdit(s)) return 'This recce is read-only now';
    if (!proposedIn.isFinite || proposedIn <= 0) {
      return '${field.label} must be a positive number';
    }
    if (originalIn != null && (proposedIn - originalIn).abs() < 1e-6) {
      return 'The proposed value is the same as the current value';
    }
    final why = reason.trim();
    if (why.isEmpty) return 'Enter the reason for the override';
    if (why.length < 5) return 'Describe the reason in a few words';
    b.gsbOverrides.add(
      GsbSpecOverride(
        id: newId('gov'),
        unitId: unitId,
        field: field,
        originalIn: originalIn,
        proposedIn: proposedIn,
        reason: why,
        userId: currentUser?.id ?? '',
        projectId: s.projectId,
        taskId: s.taskId,
        shopId: s.id,
        boardId: b.id,
        createdAt: _clock(),
        ruleVersion: ruleVersion,
      ),
    );
    final u = b.unitById(unitId)!;
    touchBoard(
      shopId,
      b,
      title: 'GSB override – review required',
      message:
          '${b.name} – ${b.unitLabel(u)}: ${field.label} '
          '${originalIn == null ? 'unspecified' : '${fmtNum(originalIn)} in'}'
          ' → ${fmtNum(proposedIn)} in (Requires Engineering Review).',
    );
    return null;
  }

  /// Sets the NLB fabrication subtype (`NLB_SINGLE_FRAME` = rulebook
  /// NON_LIT, `NLB_BOX_FRAME` = NON_LIT_BOX). The box frame prints front and
  /// rear, so it is stored as double-sided; measurements are untouched.
  void setNlbSubtype(String shopId, Board b, String subtype) {
    if (subtype != 'NLB_SINGLE_FRAME' && subtype != 'NLB_BOX_FRAME') return;
    b.nlbSubtype = subtype;
    b.doubleSided = subtype == 'NLB_BOX_FRAME';
    // Projecting Mount exists only for Box Frame; never keep an invalid value.
    if (b.installationCode != null &&
        !SignageCatalog.allowsInstallation(b, b.installationCode)) {
      b.installationCode = null;
    }
    dropInvalidUnitInstallations(b);
    autoNameBoard(shopId, b);
    touchBoard(
      shopId,
      b,
      title: 'Board updated',
      message:
          '${b.name}: NLB ${subtype == 'NLB_BOX_FRAME' ? 'Box' : 'Single'} Frame.',
    );
  }

  /// Records which side of the proposed GSB a site photo looks at. Only
  /// presentation metadata: the photo file and measurements are untouched.
  void setGsbPhotoView(String shopId, Board b, String photoId, String viewKey) {
    final p = b.photos.where((e) => e.id == photoId).firstOrNull;
    if (p == null || p.gsbView == viewKey) return;
    p.gsbView = viewKey;
    touchBoard(shopId, b);
  }

  /// GSB Double: side of the single physical LED set (`front` / `rear`).
  /// Display only – LED quantity and BOM never change.
  void setGsbLedSide(String shopId, Board b, String side) {
    final s = shop(shopId);
    if (s == null || !canEdit(s) || (side != 'front' && side != 'rear')) {
      return;
    }
    b.gsbLedSide = side == 'front' ? null : side;
    touchBoard(
      shopId,
      b,
      title: 'GSB LED side',
      message: '${b.name}: LED set on the $side side.',
    );
  }

  /// Reverts an override (history kept; the default applies again).
  void revertGsbOverride(String shopId, Board b, String overrideId) {
    final s = shop(shopId);
    if (s == null) return;
    if (!canEdit(s)) throw StateError('This recce is read-only now');
    final o = b.gsbOverrides.where((e) => e.id == overrideId).firstOrNull;
    if (o == null || !o.isActive) return;
    o
      ..status = GsbOverrideStatus.reverted
      ..revertedAt = _clock()
      ..revertedBy = currentUser?.id;
    touchBoard(
      shopId,
      b,
      title: 'GSB override reverted',
      message: '${b.name}: ${o.field.label} override reverted to default.',
    );
  }

  // ---------------------------------------------------------------------------
  // Media reference library (technical approval of reference photos) and
  // optional 360° site panoramas. Both live at AppData level and are never
  // part of a submission snapshot. UI: lib/features/references and
  // lib/features/panorama.
  // ---------------------------------------------------------------------------

  /// Every media reference (all media codes, superseded ones included).
  List<MediaReference> get mediaReferences =>
      List.unmodifiable(_data.mediaReferences);

  /// References of one media code, newest first.
  List<MediaReference> referencesFor(
    String mediaCode, {
    bool includeSuperseded = true,
  }) => referencesOf(
    _data.mediaReferences,
    mediaCode,
    includeSuperseded: includeSuperseded,
  );

  MediaReference? mediaReference(String id) =>
      _data.mediaReferences.where((r) => r.id == id).firstOrNull;

  /// Library status of a media type ("Pending Reference" when none).
  ReferenceStatus referenceLibraryStatus(String mediaCode) =>
      libraryStatusFor(_data.mediaReferences, mediaCode);

  /// 3D model status of a media type, derived from its references.
  ModelStatus modelStatus(String mediaCode) =>
      modelStatusFor(_data.mediaReferences, mediaCode);

  /// The "concerned team" for technical review in this frontend phase:
  /// Business Team and Recce Operations.
  bool get canReviewReferences => role?.isReviewer ?? false;

  AppUser _referenceUser() {
    final u = currentUser;
    if (u == null) throw StateError('Login required');
    return u;
  }

  MediaReference _referenceById(String id) {
    final r = mediaReference(id);
    if (r == null) throw StateError('Media reference not found');
    return r;
  }

  void _requireReferenceReviewer() {
    if (!canReviewReferences) {
      throw StateError(
        'Only the Business Team or Recce Operations can review media '
        'references',
      );
    }
  }

  String? _cleanReferenceUrl(
    ReferenceSourceCategory category,
    String? sourceUrl,
  ) {
    final url = sourceUrl?.trim() ?? '';
    if (url.isNotEmpty && !isValidReferenceUrl(url)) {
      throw ArgumentError('Enter a valid http(s) source URL');
    }
    if (category == ReferenceSourceCategory.external && url.isEmpty) {
      throw ArgumentError('External references must carry a source URL');
    }
    return url.isEmpty ? null : url;
  }

  String _mediaName(String code) => SignageCatalog.media(code)?.name ?? code;

  MediaReference _createReference({
    required String mediaCode,
    required ReferenceSourceCategory sourceCategory,
    String? installationCode,
    String? sourceUrl,
    String? localPath,
    String owner = '',
    String label = '',
    ReferenceUsageRights? usageRights,
    String technicalNotes = '',
    String? supersedes,
  }) {
    final u = _referenceUser();
    if (!SignageCatalog.catalogCodes.contains(mediaCode)) {
      throw ArgumentError.value(mediaCode, 'mediaCode', 'Not a catalog media');
    }
    if (installationCode != null &&
        SignageCatalog.installation(installationCode) == null) {
      throw ArgumentError.value(installationCode, 'installationCode');
    }
    final url = _cleanReferenceUrl(sourceCategory, sourceUrl);
    final path = localPath?.trim() ?? '';
    final now = _clock();
    final r = MediaReference(
      id: newId('mr'),
      mediaCode: mediaCode,
      installationCode: installationCode,
      sourceCategory: sourceCategory,
      sourceUrl: url,
      localPath: path.isEmpty ? null : path,
      owner: owner.trim(),
      label: label.trim(),
      // External (web) references always start with unknown rights.
      usageRights: usageRights ?? ReferenceUsageRights.unknown,
      technicalNotes: technicalNotes.trim(),
      createdByName: u.name,
      createdAt: now,
      supersedes: supersedes,
    );
    r.status = r.hasSource
        ? ReferenceStatus.collected
        : ReferenceStatus.pendingReference;
    _data.mediaReferences.add(r);
    return r;
  }

  /// Registers a reference (factory / internal sample photo or external
  /// link). External references must carry a source URL; their usage rights
  /// default to unknown. Never approved on creation.
  MediaReference registerReference({
    required String mediaCode,
    required ReferenceSourceCategory sourceCategory,
    String? installationCode,
    String? sourceUrl,
    String? localPath,
    String owner = '',
    String label = '',
    ReferenceUsageRights? usageRights,
    String technicalNotes = '',
  }) {
    final r = _createReference(
      mediaCode: mediaCode,
      sourceCategory: sourceCategory,
      installationCode: installationCode,
      sourceUrl: sourceUrl,
      localPath: localPath,
      owner: owner,
      label: label,
      usageRights: usageRights,
      technicalNotes: technicalNotes,
    );
    _log(
      'created',
      'Media reference registered',
      '${_mediaName(mediaCode)}: ${sourceCategory.label} reference '
          '(${r.status.label}).',
    );
    _commit();
    return r;
  }

  /// Edits reference metadata. Approved or replaced references are locked
  /// (replace them instead). Changing the photo / link of a reference under
  /// review sends it back to "Collected" with the checks cleared.
  void updateReference(
    String id, {
    String? owner,
    String? label,
    ReferenceUsageRights? usageRights,
    String? sourceUrl,
    String? localPath,
    String? installationCode,
    bool clearInstallation = false,
    String? technicalNotes,
  }) {
    _referenceUser();
    final r = _referenceById(id);
    if (r.isSuperseded || r.isApproved) {
      throw StateError(
        'Approved or replaced references are locked – use Replace instead',
      );
    }
    if (installationCode != null &&
        SignageCatalog.installation(installationCode) == null) {
      throw ArgumentError.value(installationCode, 'installationCode');
    }
    final url = sourceUrl == null
        ? r.sourceUrl
        : _cleanReferenceUrl(r.sourceCategory, sourceUrl);
    final path = localPath == null
        ? r.localPath
        : (localPath.trim().isEmpty ? null : localPath.trim());
    final sourceChanged = url != r.sourceUrl || path != r.localPath;
    r.sourceUrl = url;
    r.localPath = path;
    if (owner != null) r.owner = owner.trim();
    if (label != null) r.label = label.trim();
    if (usageRights != null) r.usageRights = usageRights;
    if (clearInstallation) r.installationCode = null;
    if (installationCode != null) r.installationCode = installationCode;
    if (technicalNotes != null) r.technicalNotes = technicalNotes.trim();
    if (sourceChanged && r.status == ReferenceStatus.awaitingTechnicalReview) {
      r.status = ReferenceStatus.collected;
      r.technicalChecks.clear();
    }
    if (r.status == ReferenceStatus.pendingReference && r.hasSource) {
      r.status = ReferenceStatus.collected;
    }
    if (r.status == ReferenceStatus.collected && !r.hasSource) {
      r.status = ReferenceStatus.pendingReference;
    }
    r.updatedAt = _clock();
    _commit();
  }

  /// Sends a collected (or previously rejected) reference to technical
  /// review. The reviewer's checks start empty.
  void submitReferenceForReview(String id) {
    _referenceUser();
    final r = _referenceById(id);
    if (r.isSuperseded) throw StateError('This reference was replaced');
    if (r.status != ReferenceStatus.collected &&
        r.status != ReferenceStatus.rejected) {
      throw StateError('Only collected or rejected references can be sent');
    }
    if (!r.hasSource) throw StateError('Add a photo or source link first');
    r.status = ReferenceStatus.awaitingTechnicalReview;
    r.technicalChecks.clear();
    r.updatedAt = _clock();
    _log(
      'submitted',
      'Media reference sent for review',
      '${_mediaName(r.mediaCode)}: ${r.sourceCategory.label} reference.',
    );
    _commit();
  }

  /// Reviewer ticks / unticks one technical verification item.
  void setReferenceCheck(String id, TechnicalCheck check, bool? value) {
    _requireReferenceReviewer();
    final r = _referenceById(id);
    if (r.isSuperseded || r.status != ReferenceStatus.awaitingTechnicalReview) {
      throw StateError('Only references awaiting review can be checked');
    }
    r.technicalChecks[check] = value;
    r.updatedAt = _clock();
    _commit();
  }

  /// Approves a reference (reviewers only). Requires all technical checks
  /// and recorded usage rights; sets the approver's name, role and time.
  void approveReference(String id, {String notes = ''}) {
    _requireReferenceReviewer();
    final u = _referenceUser();
    final r = _referenceById(id);
    final blocker = referenceApprovalBlocker(r);
    if (blocker != null) throw StateError(blocker);
    final now = _clock();
    r.status = ReferenceStatus.approved;
    r.approvedByName = u.name;
    r.approvedByRole = u.role;
    r.approvedAt = now;
    if (notes.trim().isNotEmpty) r.technicalNotes = notes.trim();
    r.updatedAt = now;
    _log(
      'approved',
      'Media reference approved',
      '${_mediaName(r.mediaCode)}: reference technically reviewed by '
          '${u.name}.',
    );
    _commit();
  }

  /// Rejects a reference under review with a reason (reviewers only).
  void rejectReference(String id, String reason) {
    _requireReferenceReviewer();
    final u = _referenceUser();
    final r = _referenceById(id);
    if (reason.trim().isEmpty) {
      throw ArgumentError('A rejection reason is required');
    }
    if (r.isSuperseded || r.status != ReferenceStatus.awaitingTechnicalReview) {
      throw StateError('Only references awaiting review can be rejected');
    }
    final now = _clock();
    r.status = ReferenceStatus.rejected;
    r.rejectionReason = reason.trim();
    r.rejectedByName = u.name;
    r.rejectedAt = now;
    r.approvedByName = null;
    r.approvedByRole = null;
    r.approvedAt = null;
    r.updatedAt = now;
    _log(
      'rejected',
      'Media reference rejected',
      '${_mediaName(r.mediaCode)}: ${reason.trim()}',
    );
    _commit();
  }

  /// Replaces a reference without data loss: a new record is created
  /// ([MediaReference.supersedes]) and the old one is kept, marked
  /// superseded. A replaced approval no longer counts.
  MediaReference replaceReference(
    String oldId, {
    required ReferenceSourceCategory sourceCategory,
    String? installationCode,
    String? sourceUrl,
    String? localPath,
    String owner = '',
    String label = '',
    ReferenceUsageRights? usageRights,
    String technicalNotes = '',
  }) {
    _referenceUser();
    final old = _referenceById(oldId);
    if (old.isSuperseded) {
      throw StateError('This reference was already replaced');
    }
    final r = _createReference(
      mediaCode: old.mediaCode,
      sourceCategory: sourceCategory,
      installationCode: installationCode ?? old.installationCode,
      sourceUrl: sourceUrl,
      localPath: localPath,
      owner: owner,
      label: label,
      usageRights: usageRights,
      technicalNotes: technicalNotes,
      supersedes: old.id,
    );
    old.replacedById = r.id;
    old.updatedAt = _clock();
    _log(
      'updated',
      'Media reference replaced',
      '${_mediaName(old.mediaCode)}: ${old.status.label} reference kept as '
          'superseded; new ${sourceCategory.label} reference registered.',
    );
    _commit();
    return r;
  }

  /// Imported panoramas of a shop, newest first.
  List<PanoramaRecord> panoramasForShop(String shopId) =>
      _data.panoramas.where((p) => p.shopId == shopId).toList()
        ..sort((a, b) => b.importedAt.compareTo(a.importedAt));

  PanoramaRecord? panorama(String id) =>
      _data.panoramas.where((p) => p.id == id).firstOrNull;

  /// Panoramas follow the recce's edit rights (view only otherwise).
  bool canEditPanoramas(String shopId) {
    final s = shop(shopId);
    return s != null && canEdit(s);
  }

  Shop _panoramaShop(String shopId) {
    final s = shop(shopId);
    if (s == null) throw StateError('Shop not found');
    if (!canEdit(s)) throw StateError('This recce is read-only now');
    return s;
  }

  PanoramaRecord _panoramaById(String id) {
    final p = panorama(id);
    if (p == null) throw StateError('Panorama not found');
    return p;
  }

  /// Stores an imported panorama (file already copied to app storage).
  /// The size must pass [panoramaSizeProblem].
  PanoramaRecord addPanorama({
    required String shopId,
    required String path,
    required int width,
    required int height,
    String label = '360° panorama',
    DateTime? capturedAt,
  }) {
    final s = _panoramaShop(shopId);
    final problem = panoramaSizeProblem(width, height);
    if (problem != null) throw ArgumentError(problem);
    final p = PanoramaRecord(
      id: newId('pano'),
      shopId: s.id,
      projectId: s.projectId,
      taskId: s.taskId,
      path: path,
      width: width,
      height: height,
      label: label.trim().isEmpty ? '360° panorama' : label.trim(),
      importedAt: _clock(),
      capturedAt: capturedAt,
    );
    _data.panoramas.add(p);
    _log(
      'photo',
      'Panorama imported',
      '${p.label} ($width×$height px) added to ${s.name}.',
      shop: s,
    );
    _commit();
    return p;
  }

  /// Replaces the signage placements of a panorama (explicit save).
  void savePanoramaPlacements(
    String panoramaId,
    List<PanoramaPlacement> placements,
  ) {
    final p = _panoramaById(panoramaId);
    final s = _panoramaShop(p.shopId);
    p.placements = [for (final x in placements) x.copy()];
    _log(
      'updated',
      'Panorama placements saved',
      '${p.label}: ${p.placements.length} signage placement(s).',
      shop: s,
    );
    _commit();
  }

  /// Records which yaw faces north (direction presets use it).
  void setPanoramaNorth(String panoramaId, double yawDeg) {
    final p = _panoramaById(panoramaId);
    _panoramaShop(p.shopId);
    p.northYawDeg = normalizeYaw(yawDeg);
    _commit();
  }

  void addPanoramaPreview(String panoramaId, String path) {
    final p = _panoramaById(panoramaId);
    final s = _panoramaShop(p.shopId);
    p.previews.add(path);
    _log('photo', 'Panorama preview saved', '${p.label} preview.', shop: s);
    _commit();
  }

  /// Deletes a panorama, its image file and saved previews.
  Future<void> deletePanorama(String panoramaId) async {
    final p = _panoramaById(panoramaId);
    final s = _panoramaShop(p.shopId);
    _data.panoramas.remove(p);
    await media?.deleteIfExists(p.path);
    for (final v in p.previews) {
      await media?.deleteIfExists(v);
    }
    _log('updated', 'Panorama removed', '${p.label} was removed.', shop: s);
    _commit();
  }

  // ---------------------------------------------------------------------------
  // Before / Proposed comparisons
  // ---------------------------------------------------------------------------

  void addComparison(String shopId, String boardId, ComparisonRecord r) {
    final b = board(shopId, boardId);
    if (b == null) return;
    b.comparisons.add(r);
    final u = b.unitById(r.unitId);
    touchBoard(
      shopId,
      b,
      title: 'Comparison saved',
      message:
          'Before / Proposed saved for ${b.name}'
          '${u == null ? '' : ' – ${b.unitLabel(u)}'} (${r.versionLabel}).',
    );
  }

  /// Deletes a comparison image (the original photo is never touched).
  Future<void> removeComparison(
    String shopId,
    String boardId,
    String comparisonId,
  ) async {
    final s = shop(shopId);
    final b = board(shopId, boardId);
    if (s == null || b == null) return;
    final r = b.comparisons.where((e) => e.id == comparisonId).firstOrNull;
    if (r == null) return;
    b.comparisons.remove(r);
    if (!_referencedInSnapshots(s, r.path)) {
      await media?.deleteIfExists(r.path);
    }
    touchBoard(shopId, b);
  }

  // ---------------------------------------------------------------------------
  // Photo-level review comments
  // ---------------------------------------------------------------------------

  /// Comments of a shop, filtered; oldest first.
  List<PhotoReviewComment> reviewComments(
    String shopId, {
    String? photoId,
    int? version,
    String? unitId,
  }) {
    final s = shop(shopId);
    if (s == null) return const [];
    return s.reviewComments
        .where(
          (c) =>
              (photoId == null || c.photoId == photoId) &&
              (version == null || c.version == version) &&
              (unitId == null || c.unitId == unitId),
        )
        .toList();
  }

  /// Open (not yet addressed) comments of all versions.
  List<PhotoReviewComment> openComments(String shopId) => reviewComments(
    shopId,
  ).where((c) => c.status == CommentStatus.open).toList();

  /// The reviewer awaiting this shop may pin comments on its photos.
  bool canComment(Shop s) => canReview(s);

  PhotoReviewComment addReviewComment(
    String shopId, {
    required String groupId,
    required String photoId,
    required ReviewCommentType type,
    required String text,
    required SurveyPoint position,
    String? unitId,
    bool rejectsEvidence = false,
  }) {
    final s = shop(shopId);
    final u = currentUser;
    if (s == null || u == null || !canComment(s)) {
      throw StateError('Only the reviewer awaiting this recce can comment');
    }
    if (text.trim().isEmpty) throw StateError('Enter the comment text');
    if (!position.isFinite) throw StateError('Invalid comment position');
    final number =
        s.reviewComments
            .where((c) => c.reviewerRole == u.role)
            .fold<int>(0, (m, c) => math.max(m, c.number)) +
        1;
    final c = PhotoReviewComment(
      id: newId('rc'),
      projectId: s.projectId,
      taskId: s.taskId,
      shopId: s.id,
      groupId: groupId,
      unitId: unitId,
      photoId: photoId,
      version: s.currentVersion,
      reviewerRole: u.role,
      reviewerId: u.id,
      reviewerName: u.name,
      type: type,
      text: text.trim(),
      position: position.clamped(),
      createdAt: _clock(),
      number: number,
      rejectsEvidence: rejectsEvidence,
    );
    s.reviewComments.add(c);
    _log(
      'updated',
      'Photo comment added',
      '${c.markerLabel} ${type.label} (v${c.version}): ${c.text}',
      shop: s,
      version: c.version,
    );
    _commit();
    return c;
  }

  PhotoReviewComment? _comment(Shop s, String id) =>
      s.reviewComments.where((c) => c.id == id).firstOrNull;

  /// Recce staff reply; optionally marks the comment Addressed.
  void respondToComment(
    String shopId,
    String commentId,
    String text, {
    bool markAddressed = false,
  }) {
    final s = shop(shopId);
    final u = currentUser;
    if (s == null || u == null || !canEdit(s)) {
      throw StateError('Only the recce staff can respond now');
    }
    final c = _comment(s, commentId);
    if (c == null) throw StateError('Comment not found');
    if (text.trim().isEmpty && !markAddressed) {
      throw StateError('Enter a response');
    }
    if (text.trim().isNotEmpty) {
      c.responses.add(
        CommentResponse(
          byId: u.id,
          byName: u.name,
          role: u.role,
          text: text.trim(),
          at: _clock(),
          version: s.currentVersion,
        ),
      );
    }
    if (markAddressed && c.status == CommentStatus.open) {
      c.status = CommentStatus.addressed;
      c.addressedAt = _clock();
      _log(
        'updated',
        'Photo correction submitted',
        '${c.markerLabel} ${c.type.label} marked addressed'
            '${text.trim().isEmpty ? '' : ': ${text.trim()}'}',
        shop: s,
      );
    }
    touchShop(s);
  }

  /// Only the reviewer of the same stage, while the recce awaits them, can
  /// verify an addressed comment. Staff can never verify (no self-approval).
  bool canVerifyComment(Shop s, PhotoReviewComment c) {
    final u = currentUser;
    return u != null &&
        u.role.isReviewer &&
        u.role == c.reviewerRole &&
        canReview(s) &&
        c.status == CommentStatus.addressed;
  }

  void verifyComment(String shopId, String commentId) {
    final s = shop(shopId);
    final c = s == null ? null : _comment(s, commentId);
    if (s == null || c == null || !canVerifyComment(s, c)) {
      throw StateError('Not allowed to verify this comment');
    }
    c
      ..status = CommentStatus.verified
      ..verifiedAt = _clock()
      ..verifiedByName = currentUser!.name;
    _log(
      'updated',
      'Photo comment verified',
      '${c.markerLabel} ${c.type.label} (raised in v${c.version}) verified.',
      shop: s,
      version: s.currentVersion,
    );
    _commit();
  }

  /// Reviewer re-opens an addressed / verified comment of their stage.
  void reopenComment(String shopId, String commentId) {
    final s = shop(shopId);
    final u = currentUser;
    final c = s == null ? null : _comment(s, commentId);
    if (s == null ||
        c == null ||
        u == null ||
        u.role != c.reviewerRole ||
        !canReview(s)) {
      throw StateError('Not allowed to reopen this comment');
    }
    c
      ..status = CommentStatus.open
      ..verifiedAt = null
      ..verifiedByName = null;
    _commit();
  }

  /// The author may delete an open comment of the version under review.
  bool canDeleteComment(Shop s, PhotoReviewComment c) =>
      currentUser?.id == c.reviewerId &&
      canReview(s) &&
      c.version == s.currentVersion &&
      c.status == CommentStatus.open;

  void deleteReviewComment(String shopId, String commentId) {
    final s = shop(shopId);
    final c = s == null ? null : _comment(s, commentId);
    if (s == null || c == null || !canDeleteComment(s, c)) {
      throw StateError('Not allowed to delete this comment');
    }
    s.reviewComments.remove(c);
    _commit();
  }

  /// Open comments of the version under review that reject evidence, as
  /// item-specific rejection issues (added when the reviewer rejects).
  List<RejectionIssue> commentIssues(Shop s) {
    final out = <RejectionIssue>[];
    for (final c in s.reviewComments) {
      if (c.version != s.currentVersion ||
          !c.rejectsEvidence ||
          c.status != CommentStatus.open) {
        continue;
      }
      final b = s.boards.where((e) => e.id == c.groupId).firstOrNull;
      final p = b?.photos.where((e) => e.id == c.photoId).firstOrNull;
      final u = b?.unitById(c.unitId);
      out.add(
        RejectionIssue(
          groupId: c.groupId,
          unitId: c.unitId,
          photoId: c.photoId,
          aspect: c.type.aspect,
          label: [
            b?.name ?? 'Media group',
            if (u != null && b != null) b.unitLabel(u),
            if (p != null) p.label,
          ].join(' • '),
          note: '${c.markerLabel} ${c.type.label}: ${c.text}',
        ),
      );
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Measurement PDF reports
  // ---------------------------------------------------------------------------

  /// Reports of a shop, newest first.
  List<RecceReport> reportsForShop(String shopId) =>
      _data.reports.where((r) => r.shopId == shopId).toList()
        ..sort((a, b) => b.generatedAt.compareTo(a.generatedAt));

  void addReport(RecceReport r) {
    _data.reports.add(r);
    final s = shop(r.shopId);
    _log(
      'updated',
      'Measurement PDF generated',
      '${s?.name ?? 'Shop'}: ${r.isDraft ? 'Draft' : 'Approved'} report '
          '(v${r.version}, ${r.pageCount} page(s)).',
      shop: s,
      projectId: r.projectId,
      taskId: r.taskId,
      version: r.version == 0 ? null : r.version,
    );
    _commit();
  }

  Future<void> deleteReport(String reportId) async {
    final r = _data.reports.where((e) => e.id == reportId).firstOrNull;
    if (r == null) return;
    _data.reports.remove(r);
    await media?.deleteIfExists(r.path);
    _commit();
  }

  /// Item-specific issues of the latest rejection (empty when not rejected).
  List<RejectionIssue> openIssues(Shop s) {
    if (!s.status.isRejected) return const [];
    final r = s.latestSubmission?.reviews.lastOrNull;
    if (r == null || r.decision != ReviewDecision.rejected) return const [];
    return r.issues;
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  /// Blocking issues as text (same wording as before; see
  /// [boardIssueDetails] for the board / section each one points to).
  List<String> boardIssues(Board b) => [
    for (final i in boardIssueDetails(b)) i.text,
  ];

  /// Canonical blocking validation of a media group: every issue knows the
  /// physical board (unit) and workflow section that resolves it.
  List<BoardIssue> boardIssueDetails(Board b) {
    final issues = <BoardIssue>[];
    void add(String text, IssueSection section, [String? unitId]) =>
        issues.add(BoardIssue(text, section, unitId: unitId));
    final media = SignageCatalog.media(b.mediaCode);
    if (media == null) {
      add('Select a media type', IssueSection.media);
    }
    // Each unit resolves its own installation (override, else the group's).
    final missingInst = [
      for (final u in b.activeUnits)
        if (b.installationOf(u) == null) u,
    ];
    if (b.activeUnits.isEmpty ? b.installationCode == null : missingInst.isNotEmpty) {
      add(
        missingInst.isNotEmpty && missingInst.length < b.activeUnits.length
            ? 'Select an installation type for '
                  '${missingInst.map((u) => SignageCatalog.unitName(b, u)).join(', ')}'
            : 'Select an installation type',
        IssueSection.installation,
        missingInst.isEmpty ? null : missingInst.first.id,
      );
    } else if (!SignageCatalog.installationComplete(b)) {
      add(
        'Installation type not valid for ${media?.shortName ?? b.mediaCode}',
        IssueSection.installation,
      );
    }
    if (media != null && b.activeUnits.isEmpty &&
        SignageCatalog.primaryInstallation(b) != null) {
      final missing = SignageCatalog.missingAnswers(b).length;
      if (missing > 0) {
        add(
          'Answer $missing site question${missing == 1 ? '' : 's'}',
          IssueSection.questions,
        );
      }
    }
    if (media != null) {
      for (final u in b.activeUnits) {
        final unit = b.quantity > 1 ? ' for ${b.unitLabel(u)}' : '';
        // Site Questions of THIS board, for its own installation.
        if (b.installationOf(u) != null) {
          final missing = SignageCatalog.missingAnswersFor(b, u).length;
          if (missing > 0) {
            add(
              'Answer $missing site question${missing == 1 ? '' : 's'}$unit',
              IssueSection.questions,
              u.id,
            );
          }
        }
        final uniq = SiteChecklists.uniqueMissing(b, u);
        if (b.checklistRequired && uniq.isNotEmpty) {
          final n = uniq.length;
          add(
            'Complete the site checklist$unit ($n required question'
            '${n == 1 ? '' : 's'} left)',
            IssueSection.questions,
            u.id,
          );
        }
        final errors = MeasurementCatalog.errors(b, u);
        if (errors.isNotEmpty) {
          add(
            'Fix measurements$unit: ${errors.first.message}',
            IssueSection.details,
            u.id,
          );
        }
      }
    }
    if (b.isSameSize) {
      if (!b.hasSize) add('Enter board width and height', IssueSection.details);
    } else {
      for (final u in b.activeUnits) {
        if (!b.unitHasSize(u)) {
          add(
            'Enter width and height for ${b.unitLabel(u)}',
            IssueSection.details,
            u.id,
          );
        }
      }
    }
    if (b.photos.isEmpty) {
      add('Capture at least one site photo', IssueSection.photos);
    }
    return issues;
  }

  /// Photos taken farther than this from the shop GPS are flagged.
  static const photoDistanceWarningM = 300.0;

  /// GPS fixes less precise than this are flagged for recapture.
  static const lowAccuracyWarningM = 50.0;

  List<String> boardWarnings(Board b, [GeoFix? shopGeo]) {
    final w = <String>[];
    final marked = b.photos.any(
      (p) => p.annotations.any((a) => a.type == AnnotationType.rectangle),
    );
    if (b.photos.isNotEmpty && !marked) {
      w.add('Board area not marked on any photo');
    }
    if (b.photos.length == 1) w.add('Only one photo angle captured');
    if (b.quantity > 1 && b.photos.isNotEmpty) {
      final unmarked = b.activeUnits
          .where((u) => b.annotationsOf(u).isEmpty)
          .length;
      if (unmarked > 0) {
        w.add(
          '$unmarked of ${b.quantity} units have no placement marking on a '
          'photo',
        );
      }
    }
    final untagged = b.photos.where((p) => p.geo == null).length;
    if (untagged > 0) {
      w.add(
        untagged == b.photos.length
            ? 'No photo has a GPS tag (sample, gallery or pre-GPS photos)'
            : '$untagged of ${b.photos.length} photos have no GPS tag',
      );
    }
    if (shopGeo != null) {
      for (final p in b.photos) {
        final g = p.geo;
        if (g == null) continue;
        final d = g.distanceTo(shopGeo);
        if (d > photoDistanceWarningM) {
          w.add(
            '"${p.label}" photo was taken ${fmtDistance(d)} away from the '
            'shop GPS location',
          );
        }
      }
    }
    for (final u in b.activeUnits) {
      final f = feasibilityOf(b, u);
      if (f.level == SiteFeasibility.noKnownObstruction) continue;
      final unit = b.quantity > 1 ? '${b.unitLabel(u)}: ' : '';
      final more = f.reasons.length > 1
          ? ' (+${f.reasons.length - 1} more)'
          : '';
      w.add('$unit${f.level.label} – ${f.reasons.first}$more');
    }
    return w;
  }

  /// Non-blocking shop-level warnings (shown before submit and to reviewers).
  List<String> shopWarnings(Shop s) {
    final w = <String>[];
    final g = s.geo;
    if (g != null && g.accuracyM > lowAccuracyWarningM) {
      w.add(
        'Shop GPS accuracy is low (±${g.accuracyM.round()} m) – recapture '
        'in an open area if possible',
      );
    }
    // Possible duplicate media groups (same media, sides, installation and
    // size). Repeated media with other installations / sizes is normal.
    for (var i = 0; i < s.boards.length; i++) {
      for (var j = i + 1; j < s.boards.length; j++) {
        final a = s.boards[i], b = s.boards[j];
        if (a.mediaCode == null ||
            a.mediaCode != b.mediaCode ||
            a.installationCode != b.installationCode ||
            SignageCatalog.isDoubleSided(a) !=
                SignageCatalog.isDoubleSided(b) ||
            !a.hasSize ||
            !b.hasSize ||
            !a.isSameSize ||
            !b.isSameSize ||
            a.widthFt != b.widthFt ||
            a.heightFt != b.heightFt) {
          continue;
        }
        w.add(
          '${a.name} and ${b.name} have the same media, installation and '
          'size – check they are not entered twice (use quantity for '
          'identical units)',
        );
      }
    }
    return w;
  }

  /// Saves the shop's GPS location captured on site.
  void setShopLocation(Shop shop, GeoFix fix) {
    shop.geo = fix;
    touchShop(
      shop,
      title: 'GPS location captured',
      message:
          '${shop.name}: ${fix.coordinates} (±${fix.accuracyM.round()} m).',
    );
  }

  List<String> shopIssues(Shop s) {
    final issues = <String>[];
    if (s.name.trim().isEmpty) issues.add('Shop name is missing');
    if (s.phone.trim().isEmpty) issues.add('Shop contact number is missing');
    if (s.address.trim().isEmpty) issues.add('Shop address is missing');
    if (s.geo == null) issues.add('Capture the shop GPS location');
    if (s.boards.isEmpty) issues.add('Add at least one board');
    for (final b in s.boards) {
      for (final i in boardIssues(b)) {
        issues.add('${b.name}: $i');
      }
    }
    return issues;
  }

  // ---------------------------------------------------------------------------
  // Workflow: submit → Business → Ops
  // ---------------------------------------------------------------------------

  Submission submitShop(String shopId, {String remarks = ''}) {
    final s = shop(shopId);
    final u = currentUser;
    if (s == null || u == null) throw StateError('Shop or user missing');
    if (!canEdit(s)) throw StateError('This recce cannot be submitted now');
    final issues = shopIssues(s);
    if (issues.isNotEmpty) throw StateError(issues.first);

    final version = s.submissions.length + 1;
    s.status = RecceStatus.pendingBusiness;
    s.updatedAt = DateTime.now();
    final submission = Submission(
      version: version,
      submittedAt: s.updatedAt,
      submittedById: u.id,
      submittedByName: u.name,
      snapshot: s.toSnapshotJson(),
      vendorRemarks: remarks.trim(),
    );
    s.submissions.add(submission);
    _log(
      'submitted',
      version == 1 ? 'Recce submitted (v1)' : 'Recce resubmitted (v$version)',
      '${s.name} sent for Business approval'
          '${remarks.trim().isEmpty ? '.' : ' – ${remarks.trim()}'}',
      shop: s,
      version: version,
    );
    _commit();
    return submission;
  }

  void reviewShop(
    String shopId, {
    required ReviewDecision decision,
    String remarks = '',
    List<String> reasons = const [],
    List<RejectionIssue> issues = const [],
  }) {
    final s = shop(shopId);
    final u = currentUser;
    final stage = reviewStage;
    if (s == null || u == null || stage == null) {
      throw StateError('Not allowed');
    }
    if (!canReview(s)) throw StateError('This recce is not awaiting you');
    if (decision == ReviewDecision.rejected && remarks.trim().isEmpty) {
      throw StateError('Remarks are required when rejecting');
    }
    final sub = s.latestSubmission!;
    sub.reviews.add(
      ReviewRecord(
        stage: stage,
        decision: decision,
        reviewerId: u.id,
        reviewerName: u.name,
        remarks: remarks.trim(),
        reasons: reasons,
        issues: decision == ReviewDecision.rejected ? issues : const [],
        at: DateTime.now(),
      ),
    );
    final approved = decision == ReviewDecision.approved;
    s.status = switch (stage) {
      ReviewStage.business =>
        approved ? RecceStatus.pendingOps : RecceStatus.rejectedBusiness,
      ReviewStage.ops =>
        approved ? RecceStatus.approved : RecceStatus.rejectedOps,
    };
    s.updatedAt = DateTime.now();
    final who = stage == ReviewStage.business ? 'Business' : 'Ops';
    final title = approved
        ? (stage == ReviewStage.ops
              ? '$who approved (v${sub.version}) – Final'
              : '$who approved (v${sub.version})')
        : '$who rejected (v${sub.version})';
    final detail = [
      if (reasons.isNotEmpty) reasons.join(', '),
      if (decision == ReviewDecision.rejected && issues.isNotEmpty)
        issues.map((i) => i.text).join('; '),
      if (remarks.trim().isNotEmpty) remarks.trim(),
    ].join(' – ');
    _log(
      approved ? 'approved' : 'rejected',
      title,
      detail.isEmpty ? s.name : '${s.name}: $detail',
      shop: s,
      version: sub.version,
    );
    _commit();
  }

  // ---------------------------------------------------------------------------
  // Activity timeline
  // ---------------------------------------------------------------------------

  void _log(
    String kind,
    String title,
    String message, {
    Shop? shop,
    AppUser? actor,
    int? version,
    String? projectId,
    String? taskId,
  }) {
    final a = actor ?? currentUser;
    _data.activities.add(
      ActivityEvent(
        id: newId('e'),
        kind: kind,
        title: title,
        message: message,
        actorName: a?.name ?? 'System',
        actorRole: a?.role,
        at: DateTime.now(),
        shopId: shop?.id,
        projectId: shop?.projectId ?? projectId,
        taskId: shop?.taskId ?? taskId,
        version: version,
      ),
    );
    // Keep the local log bounded.
    if (_data.activities.length > 600) {
      _data.activities.removeRange(0, _data.activities.length - 600);
    }
  }

  List<ActivityEvent> activities({String? shopId, String? projectId}) {
    final u = currentUser;
    final visibleTaskIds = visibleTasks.map((t) => t.id).toSet();
    final all = _data.activities;
    final indexed = <(int, ActivityEvent)>[
      for (var i = 0; i < all.length; i++)
        if (_activityVisible(all[i], shopId, projectId, u, visibleTaskIds))
          (i, all[i]),
    ];
    // Newest first; ties (same timestamp) keep reverse insertion order.
    indexed.sort((a, b) {
      final t = b.$2.at.compareTo(a.$2.at);
      return t != 0 ? t : b.$1.compareTo(a.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  bool _activityVisible(
    ActivityEvent e,
    String? shopId,
    String? projectId,
    AppUser? u,
    Set<String> visibleTaskIds,
  ) {
    if (shopId != null && e.shopId != shopId) return false;
    if (projectId != null && e.projectId != projectId) return false;
    if (e.kind == 'auth') return e.actorName == u?.name;
    return e.taskId == null || visibleTaskIds.contains(e.taskId);
  }
}
