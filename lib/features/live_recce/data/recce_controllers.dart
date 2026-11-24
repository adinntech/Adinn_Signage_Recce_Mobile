import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/catalog/signage_catalog.dart' show SiteQuestion;
import 'catalog_controller.dart';
import 'catalog_data.dart';
import 'recce_api.dart';
import 'recce_models.dart';
import 'submit_validator.dart';
import 'upload_queue.dart';

String errorText(Object e) => switch (e) {
      ApiException(:final message) => message,
      RecceInputException(:final message) => message,
      _ => 'Something went wrong. Try again.',
    };

/// The shops given to this login (Dashboard, Projects and Shops screens all read this one list).
class ShopListController extends ChangeNotifier {
  ShopListController(this._api, UploadQueue queue) {
    _sub = queue.uploaded.listen((_) => load(silent: true));
  }

  final RecceApi _api;
  StreamSubscription<String>? _sub;
  var _disposed = false;

  /// Counts every load start and every [reset]. An answer that arrives for an older number is dropped, so the shops of the
  /// previous login can never come back after a sign-out.
  var _loadGen = 0;

  List<ShopSummary> shops = const [];
  Map<String, int> summary = const {};
  bool loading = false;
  bool loaded = false;
  String? error;

  DashboardCounts get counts => DashboardCounts.fromSummary(summary);
  List<ProjectGroup> get projects => groupByProject(shops);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load({bool silent = false}) async {
    if (loading || _disposed) return;
    final gen = ++_loadGen;
    loading = true;
    if (!silent) {
      error = null;
      _notify();
    }
    try {
      final page = await _api.shops();
      if (gen != _loadGen || _disposed) return; // reset() or dispose() happened while the answer was on its way
      shops = page.items;
      summary = page.summary.isNotEmpty ? page.summary : _countStatuses(page.items);
      error = null;
      loaded = true;
    } catch (e) {
      if (gen == _loadGen && (!silent || !loaded)) error = errorText(e);
    } finally {
      if (gen == _loadGen) {
        loading = false;
        _notify();
      }
    }
  }

  static Map<String, int> _countStatuses(List<ShopSummary> list) {
    final out = <String, int>{};
    for (final s in list) {
      out[s.status] = (out[s.status] ?? 0) + 1;
    }
    return out;
  }

  /// Search (shop, code, address, project) and status filter, optionally inside one project.
  List<ShopSummary> filtered({String query = '', ShopFilter filter = ShopFilter.all, String? projectId}) {
    final q = query.trim().toLowerCase();
    return shops.where((s) {
      if (projectId != null && s.projectId != projectId) return false;
      if (!filter.matches(s.status)) return false;
      if (q.isEmpty) return true;
      return [s.title, s.siteCode, s.address, s.projectCode, s.projectName].any((f) => f.toLowerCase().contains(q));
    }).toList();
  }

  void reset() {
    _loadGen++; // a load that is still running belongs to the previous login: its answer is dropped
    loading = false;
    shops = const [];
    summary = const {};
    loaded = false;
    error = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}

/// Result of a submit attempt.
class SubmitOutcome {
  const SubmitOutcome({this.problems = const [], this.serverError, this.version});
  final List<String> problems; // local validation failures
  final String? serverError; // the server's own text
  final int? version;
  bool get ok => problems.isEmpty && serverError == null;
}

/// What the person chose for ONE media type on "Add boards": one board is made for each size (the quantity), each with its own number.
class NewBoards {
  const NewBoards({
    required this.mediaCode,
    required this.mediaType,
    required this.name,
    required this.unit,
    required this.sizes,
    this.sided = 'SINGLE',
    this.installationType,
    this.answers = const {},
  });

  final String mediaCode;
  final String mediaType;
  final String name;
  final String unit;
  final List<({double width, double height})> sizes;
  final String sided;
  final String? installationType;
  final Map<String, dynamic> answers;
}

/// The parts of a board card on the Boards tab, top to bottom.
enum BoardSection { size, installation }

/// Everything the shop recce screen edits: server detail plus the local board / installation / notes edits.
class ShopDetailController extends ChangeNotifier {
  ShopDetailController(this._api, this.queue, this.siteId, {DateTime Function()? clock, CatalogController? catalog})
      : _clock = clock ?? DateTime.now,
        _catalogCtl = catalog {
    queue.addListener(_onQueue);
    _catalogCtl?.addListener(_onCatalog);
    _sub = queue.uploaded.listen((s) {
      if (s == siteId) unawaited(refresh());
    });
  }

  /// Signed photo links live for SIGNED_URL_TTL_SECONDS (default 600 s, the server does not send the end time). A detail read
  /// longer ago than this may carry dead links, so it is read again when the app comes back or a picture fails to load.
  static const urlLifetime = Duration(minutes: 8);
  static const _imageRefreshGap = Duration(seconds: 20);

  final RecceApi _api;
  final UploadQueue queue;
  final String siteId;
  final DateTime Function() _clock;
  final CatalogController? _catalogCtl;
  StreamSubscription<String>? _sub;

  static final CatalogData _builtIn = CatalogData.builtIn();

  /// The media catalog the boards are made from: the server's copy, or the one built into the app when none was given or read.
  CatalogData get catalog => _catalogCtl?.data ?? _builtIn;
  void _onCatalog() => _notify();

  ShopDetail? detail;
  String? loadError;
  bool loading = true;
  bool busy = false;
  bool dirty = false;

  List<BoardItem> boards = [];
  Installation installation = Installation();
  String notes = '';

  /// Every immutable version (`GET .../versions`). Loaded after the shop has a version and again when a new one is made.
  List<RecceVersion> versionList = const [];
  bool versionsLoading = false;
  String? versionsError;
  int _versionsLoadedFor = -1;
  var _disposed = false;
  DateTime? _fetchedAt;
  DateTime? _lastImageRefresh;
  Future<String?>? _saveRun;
  Future<SubmitOutcome>? _submitRun;

  /// New upload id -> the older DRAFT photo it takes the place of. The old draft is deleted on the server only after the new photo
  /// is stored there, so a failed delete (or no network) can never lose the new photo.
  final Map<String, String> _swaps = {};
  var _reaping = false;

  bool get canEdit => detail != null && detail!.editable && !detail!.project.closed;
  List<UploadItem> get pending => queue.forShop(siteId);

  /// Rework: the server's own status says the reviewers asked for changes and the field person may edit again.
  bool get inRework => detail?.status == 'REWORK_REQUIRED' && canEdit;

  /// Photos of older versions that are not live any more (replaced or removed), from the versions list.
  List<PreviousPhoto> get previousPhotos => previousPhotosOf(versionList, (detail?.photos ?? const []).map((p) => p.id));

  /// The one place that tells listeners: nothing is sent after [dispose] (async answers can arrive late).
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onQueue() => _notify();

  void _adopt(ShopDetail d, {required bool keepLocal}) {
    detail = d;
    _fetchedAt = _clock();
    if (!keepLocal || !dirty) {
      boards = [for (final b in d.mediaItems) b.copy()];
      installation = Installation.fromJson(d.installation.toJson());
      notes = d.notes;
      dirty = false;
    }
    if (d.version > 0 && d.version != _versionsLoadedFor) unawaited(loadVersions());
  }

  /// Loads the version list. [force] reloads even when this version was already read.
  Future<void> loadVersions({bool force = false}) async {
    final v = detail?.version ?? 0;
    if (_disposed || versionsLoading || (!force && v == _versionsLoadedFor)) return;
    versionsLoading = true;
    versionsError = null;
    _notify();
    try {
      final list = await _api.versions(siteId);
      if (_disposed) return;
      versionList = list;
      _versionsLoadedFor = v;
    } catch (e) {
      if (!_disposed) versionsError = errorText(e);
    } finally {
      versionsLoading = false;
      _notify();
    }
  }

  /// The draft photo already uploaded as the replacement of [old], or the replacement still on its way.
  ShopPhoto? draftReplacementOf(ShopPhoto old) {
    for (final p in detail?.photos ?? const <ShopPhoto>[]) {
      if (p.isDraft && p.replaces == old.id) return p;
    }
    return null;
  }

  UploadItem? pendingReplacementOf(ShopPhoto old) {
    for (final u in pending) {
      if (u.replaces == old.id) return u;
    }
    return null;
  }

  /// TESTING ONLY (the Photos tab offers the switch in debug and profile builds, never in a release build): while it is on, the
  /// first picture taken is also queued for every other photo type that is still empty, so one shop is filled with one picture.
  bool useFirstPhotoForAll = false;

  void setUseFirstPhotoForAll(bool on) {
    if (useFirstPhotoForAll == on) return;
    useFirstPhotoForAll = on;
    _notify();
  }

  /// Queues a copy of [first] for each of [slots] (a category on a board) that has no photo and nothing waiting to upload yet; the
  /// slot of [first] itself is skipped. [copyFile] gives every copy a file of its own, because the queue deletes a file once it is
  /// uploaded. Returns how many copies were queued.
  Future<int> queueFirstPhotoForAll(UploadItem first, List<PhotoSlot> slots, Future<String> Function(String path) copyFile) async {
    final d = detail;
    if (d == null || !canEdit) return 0;
    var queued = 0;
    for (final s in slots) {
      final isFirst = s.category == first.category && s.mediaKey == first.mediaKey;
      if (isFirst || d.photoOf(s.category, s.mediaKey) != null || pending.any((u) => u.category == s.category && u.mediaKey == s.mediaKey)) continue;
      queue.add(first.copyAs(id: newClientId(), path: await copyFile(first.path), category: s.category, mediaKey: s.mediaKey));
      queued++;
    }
    return queued;
  }

  /// Every photo place of ONE saved board: the seven standard categories plus what the server requires on top for it.
  List<PhotoSlot> photoSlotsOf(BoardItem b) {
    final d = detail;
    if (d == null) return const [];
    return [
      for (final c in boardPhotoCategories) PhotoSlot(c.key, b.key),
      for (final c in d.extraTilesFor(b)) PhotoSlot(c.key, b.key),
    ];
  }

  /// Every photo place of the saved boards, board after board.
  List<PhotoSlot> photoSlots() => [for (final b in detail?.mediaItems ?? const <BoardItem>[]) ...photoSlotsOf(b)];

  /// One saved board has all its photos: each place has a live photo, or a picture that is uploading (it is on the phone and on its
  /// way, so the person has nothing left to take for it). A board the server does not know yet is never done.
  bool boardPhotosDone(String key) {
    final d = detail;
    if (d == null) return false;
    final board = d.mediaItems.where((b) => b.key == key).firstOrNull;
    if (board == null) return false;
    return photoSlotsOf(board).every((s) => d.photoOf(s.category, s.mediaKey) != null || pending.any((u) => u.category == s.category && u.mediaKey == s.mediaKey));
  }

  /// Whether the server holds board [key] (a board made on the phone is saved at once; photos need that).
  bool isSaved(String key) => detail?.mediaItems.any((m) => m.key == key) ?? false;

  /// Photos of board [key] that are stored on the server, out of the places it has (0 / 0 for a board the server does not hold).
  ({int done, int total}) boardPhotoProgress(String key) {
    final d = detail;
    final board = d?.mediaItems.where((b) => b.key == key).firstOrNull;
    if (d == null || board == null) return (done: 0, total: 0);
    final slots = photoSlotsOf(board);
    return (done: slots.where((s) => d.photoOf(s.category, s.mediaKey) != null).length, total: slots.length);
  }

  /// The first saved board (in order) that still lacks photos, or null when every board has them.
  BoardItem? get firstBoardWithoutPhotos => (detail?.mediaItems ?? const <BoardItem>[]).where((b) => !boardPhotosDone(b.key)).firstOrNull;

  /// The board the person picked (or the flow moved to) as the one being photographed now.
  String? _focusBoard;

  static const _allClosed = '';

  /// The board whose photos are open on the Photos tab: the one picked or moved to, else the first board that still lacks photos,
  /// else the last board. Null when the shop has no board, or when the person closed every board.
  BoardItem? get photoBoard {
    if (boards.isEmpty || _focusBoard == _allClosed) return null;
    final picked = boards.where((b) => b.key == _focusBoard).firstOrNull;
    if (picked != null) return picked;
    final open = firstBoardWithoutPhotos;
    return boards.where((b) => b.key == open?.key).firstOrNull ?? boards.last;
  }

  void focusBoard(String key) {
    if (_focusBoard == key) return;
    _focusBoard = key;
    _notify();
  }

  /// Folds the open board too, so every board shows as one line (a tap on a line opens it).
  void closePhotoBoards() {
    if (_focusBoard == _allClosed) return;
    _focusBoard = _allClosed;
    _notify();
  }

  /* ---- the guided steps: Boards, then Photos, then Install, then Review (the shop screen moves on by itself when one is done) ---- */

  /// Boards step: at least one board, and every board has its media type and its size.
  bool get boardsDone => boards.isNotEmpty && boards.every((b) => b.name.trim().isNotEmpty && b.quantity >= 1 && b.hasSize);

  /// Photos step: every saved board has all its photos (see [boardPhotosDone]).
  bool get photosDone {
    final d = detail;
    if (d == null || d.mediaItems.isEmpty) return false;
    return d.mediaItems.every((b) => boardPhotosDone(b.key));
  }

  /// Install step: the five required answers are given (the rest of the tab is optional).
  bool get installDone => installation.unanswered.isEmpty && installation.heightProblem == null;

  /// A board changes its media type from the cards. A single older line (no number yet) becomes a numbered board of the new type
  /// (GSB-01 ...); a line that stands for several boards only takes the name, because one number cannot name several boards.
  void changeBoardType(BoardItem b, {required String mediaType, required String name, String mediaCode = ''}) {
    if (b.isNumbered) return; // a numbered board keeps its type: its number and its photos depend on it
    b.name = name;
    if (b.quantity == 1) {
      b.mediaType = mediaType;
      b.mediaCode = mediaCode;
      b.seq = nextBoardSeq(boards.where((x) => !identical(x, b)), mediaType);
    }
    markDirty();
  }

  /* ---- per-board installation requirement: the installation method and the site questions of ONE board ---- */

  /// The catalog media type of [b]: by its code, else (a numbered board made before codes were stored) by its name.
  CatalogMedia? mediaOf(BoardItem b) => catalog.mediaByCode(b.mediaCode) ?? (b.isNumbered ? catalog.mediaByName(b.name) : null);

  /// The installation methods offered for [b] (active ones, in the admin's order).
  List<CatalogInstallation> installationsOf(BoardItem b) => catalog.installationsFor(mediaOf(b)?.code);

  /// The site questions asked for [b] with the installation it has now.
  List<SiteQuestion> questionsOf(BoardItem b) => catalog.questionsFor(mediaOf(b)?.code, b.installationType);

  /// Whether [b] must have an installation requirement before the FIRST submit. Not asked again for a resubmission (rework asks only
  /// for what the reviewer flagged) and not for an older line that was never made from the catalog.
  bool needsInstallation(BoardItem b) {
    if ((detail?.version ?? 0) > 0) return false;
    if (!b.isNumbered && b.mediaCode.isEmpty) return false;
    return installationsOf(b).isNotEmpty;
  }

  /// What is still missing of [b]'s installation requirement, as sentences ("GSB-01: choose the installation type"). Empty = done.
  List<String> installationProblems(BoardItem b) {
    if (!needsInstallation(b)) return const [];
    final who = boards.length > 1 ? '${b.label}: ' : '';
    final chosen = b.installationType;
    if (chosen == null || chosen.isEmpty) return ['${who}choose the installation type'];
    return [for (final q in catalog.missingAnswers(mediaOf(b)?.code, chosen, b.answers)) '${who}answer "${q.label}"'];
  }

  bool boardInstallDone(BoardItem b) => installationProblems(b).isEmpty;

  /// Choosing another installation method keeps the answers (the questions they belong to may come back); they are tidied at save.
  void setInstallation(BoardItem b, String code) {
    if (b.installationType == code) return;
    b.installationType = code;
    markDirty();
  }

  void setAnswer(BoardItem b, String id, Object? value) {
    if (value == null) {
      b.answers.remove(id);
    } else {
      b.answers[id] = value;
    }
    markDirty();
  }

  /// Before a save: an answer to a question this catalog knows but that no longer applies to the board's installation is dropped
  /// (the server holds at most 60 answers per board). An answer whose key this phone does not know is kept as it is.
  void _pruneAnswers() {
    final known = {for (final q in catalog.questions) q.id};
    for (final b in boards) {
      final media = mediaOf(b);
      if (media == null) continue;
      final applicable = {for (final q in catalog.questionsFor(media.code, b.installationType)) q.id};
      b.answers.removeWhere((k, _) => known.contains(k) && !applicable.contains(k));
    }
  }

  /* ---- the Boards tab: which card is open, and quantity per media type ---- */

  String? _openCard; // null = automatic (a shop with one board shows it open); '' = every card closed
  BoardSection? cardSection;

  bool boardCardOpen(String key) => _openCard == null ? boards.length == 1 : _openCard == key;

  void toggleBoardCard(String key) {
    _openCard = boardCardOpen(key) ? '' : key;
    cardSection = null;
    _notify();
  }

  /// Opens the card of [key] (one at a time) and, with [section], asks it to bring that section into view.
  void openBoardCard(String key, {BoardSection? section}) {
    _openCard = key;
    cardSection = section;
    _notify();
  }

  /// The section a card was asked to show, once: the card reads it when it opens and the request is forgotten.
  BoardSection? takeCardSection(String key) {
    if (_openCard != key) return null;
    final s = cardSection;
    cardSection = null;
    return s;
  }

  /// The numbered boards of one media type, in number order ("quantity" of that type).
  List<BoardItem> boardsOfType(String mediaType) => [for (final b in boards) if (b.isNumbered && b.mediaType == mediaType) b]..sort((a, b) => a.seq.compareTo(b.seq));

  /// "+" on a media type: one more board like the last one of its type (same size, installation and answers, its own number and
  /// photos). Saved at once (its photos need a saved board).
  Future<String?> addBoardLike(BoardItem like) => addBoards([
        NewBoards(
          mediaCode: like.mediaCode,
          mediaType: like.mediaType,
          name: like.name,
          unit: like.unit,
          sided: like.sided,
          sizes: [(width: like.width ?? 0, height: like.height ?? 0)],
          installationType: like.installationType,
          answers: Map<String, dynamic>.of(like.answers),
        ),
      ]);

  /// "-" on a media type: the board with the highest number of that type goes (it must have no photos). Saved with the draft.
  /// Returns the reason when it cannot, else null.
  String? removeLastOfType(String mediaType) {
    final list = boardsOfType(mediaType);
    if (list.length <= 1) return 'A media type keeps at least one board. Use the bin to remove it.';
    final last = list.last;
    if (boardHasPhotos(last.key)) return '${last.label} has photos, so it cannot be removed. Delete its draft photos first.';
    removeBoard(last);
    return null;
  }

  /// Whether the board has a live photo or an upload on its way (the server will not remove such a board).
  bool boardHasPhotos(String key) => (detail?.photos.any((p) => p.mediaKey == key) ?? false) || pending.any((u) => u.mediaKey == key);

  /// "Add boards": one board per physical unit, each with its own key and number (GSB-01, GSB-02 ...) and its own size. The
  /// boards are saved at once, so their photos can be linked to them on the server. Returns the error text, or null.
  Future<String?> addBoardsOfType({
    required String mediaType,
    required String name,
    required String unit,
    required List<({double width, double height})> sizes,
    String sided = 'SINGLE',
    String mediaCode = '',
  }) =>
      addBoards([NewBoards(mediaCode: mediaCode, mediaType: mediaType, name: name, unit: unit, sizes: sizes, sided: sided)]);

  /// Several media types in ONE save (the multi-select "Add boards"): each spec makes one board per size, numbered after the boards
  /// of its type the shop already has. Nothing is kept when the save is refused. Returns the error text, or null.
  Future<String?> addBoards(List<NewBoards> specs) async {
    if (!canEdit) return 'This shop is locked. Boards cannot be added now.';
    final total = specs.fold<int>(0, (n, s) => n + s.sizes.length);
    if (total == 0) return 'Choose how many boards to add.';
    if (specs.any((s) => s.sizes.any((z) => z.width <= 0 || z.height <= 0))) return 'Enter the width and height of every board.';
    if (boards.length + total > maxBoardItems) return 'A shop can hold $maxBoardItems boards.';
    final before = boards.length;
    final wasDirty = dirty;
    final newKeys = <String>[];
    for (final spec in specs) {
      for (final s in spec.sizes) {
        final key = nextBoardKey(boards.map((b) => b.key));
        newKeys.add(key);
        boards.add(BoardItem(
          key: key,
          name: spec.name,
          mediaType: spec.mediaType,
          mediaCode: spec.mediaCode,
          seq: nextBoardSeq(boards, spec.mediaType),
          unit: spec.unit,
          width: s.width,
          height: s.height,
          sided: spec.sided,
          installationType: spec.installationType,
          answers: Map<String, dynamic>.of(spec.answers),
        ));
      }
    }
    markDirty();
    final err = await saveDraft();
    if (err != null) {
      boards.removeRange(before, boards.length); // not saved: do not keep boards the server does not know
      dirty = wasDirty;
      _notify();
    } else {
      focusBoard(newKeys.first); // the photos of the first board just added come next
      openBoardCard(newKeys.first);
    }
    return err;
  }

  /// Queues [item]. When it takes the place of an older DRAFT photo ([stale]) that draft is deleted from the server once the new
  /// photo has been stored there (never before). While both exist the server simply holds two drafts of the category (it has no
  /// one-per-category rule); [reapSwaps] removes the old one after the next reload, so the version never carries both.
  void queueSwap(UploadItem item, {ShopPhoto? stale}) {
    queue.add(item);
    if (stale != null && stale.isDraft) _swaps[item.id] = stale.id;
  }

  /// Queues the new picture of ONE flagged photo (`meta.replaces` = the old photo id, same category). A second take swaps the
  /// first one that is not submitted yet (after the new one is uploaded). No other photo is touched or asked for again.
  /// Returns an error text, or null (nothing here can fail now: the picture is saved on the phone first).
  Future<String?> queueReplacement(
    ShopPhoto old, {
    required String path,
    DateTime? capturedAt,
    double? lat,
    double? lng,
    double? accuracy,
    int? width,
    int? height,
    String? device,
  }) async {
    final stale = draftReplacementOf(old);
    final waiting = pendingReplacementOf(old);
    if (waiting != null) queue.cancel(waiting.id);
    queueSwap(
      UploadItem.replacement(
        old,
        siteId: siteId,
        path: path,
        capturedAt: capturedAt,
        lat: lat,
        lng: lng,
        accuracy: accuracy,
        width: width,
        height: height,
        device: device,
      ),
      stale: stale,
    );
    return null;
  }

  /// True when the new photo that should take the place of [old] is stored on the server (and is not [old] itself).
  bool _landedAfter(ShopPhoto old) {
    for (final p in detail?.photos ?? const <ShopPhoto>[]) {
      if (!p.isDraft || p.id == old.id || p.category != old.category) continue;
      if (old.replaces != null ? p.replaces == old.replaces : (p.replaces == null && p.mediaKey == old.mediaKey)) return true;
    }
    return false;
  }

  /// Deletes the old drafts whose replacement is on the server now. A swap whose new photo was cancelled keeps its old photo.
  /// A delete that fails stays in the list and is tried again at the next reload.
  Future<void> reapSwaps() async {
    if (_swaps.isEmpty || _reaping || _disposed) return;
    _reaping = true;
    try {
      for (final e in _swaps.entries.toList()) {
        if (_disposed) return;
        if (pending.any((u) => u.id == e.key)) continue; // still on its way
        var old = _draftById(e.value);
        if (old == null) {
          _swaps.remove(e.key); // already gone
          continue;
        }
        if (!_landedAfter(old)) {
          // The shop we hold may be older than the upload: read it once more before deciding the new photo was cancelled.
          if (!await _reload()) continue; // offline: decide later
          old = _draftById(e.value);
          if (old == null || !_landedAfter(old)) {
            _swaps.remove(e.key); // cancelled: the old photo stays
            continue;
          }
        }
        try {
          await _api.deletePhoto(siteId, old.id);
          _swaps.remove(e.key);
        } catch (_) {
          continue; // offline: both stay, the old one goes at the next reload
        }
        await _reload();
      }
    } finally {
      _reaping = false;
    }
  }

  ShopPhoto? _draftById(String id) {
    for (final p in detail?.photos ?? const <ShopPhoto>[]) {
      if (p.id == id && p.isDraft) return p;
    }
    return null;
  }

  /// Reads the shop again and keeps unsaved local edits. False when it could not be read (or the screen is gone).
  Future<bool> _reload() async {
    try {
      final d = await _api.detail(siteId);
      if (_disposed) return false;
      _adopt(d, keepLocal: true);
      _notify();
      return true;
    } catch (_) {
      return false; // keep what is on screen
    }
  }

  Future<void> load() async {
    loading = true;
    loadError = null;
    _notify();
    try {
      var d = await _api.detail(siteId);
      if (_disposed) return;
      if (d.status == 'NOT_STARTED' && d.editable && !d.project.closed) {
        await _api.start(siteId);
        if (_disposed) return;
        d = await _api.detail(siteId);
        if (_disposed) return;
      }
      _adopt(d, keepLocal: false);
    } catch (e) {
      if (!_disposed) loadError = errorText(e);
    } finally {
      loading = false;
      _notify();
    }
  }

  /// Quiet reload after an upload finished; keeps unsaved local edits.
  Future<void> refresh() async {
    if (await _reload()) await reapSwaps();
  }

  /// Pull-to-refresh: the shop again (fresh photo links) and its versions list.
  Future<void> refreshAll() async {
    await refresh();
    if ((detail?.version ?? 0) > 0) await loadVersions(force: true);
  }

  /// True when the last read is old enough that signed photo links may have run out.
  bool get urlsStale {
    final t = _fetchedAt;
    return t != null && _clock().difference(t) >= urlLifetime;
  }

  /// App came back to the front: read the shop again only when its photo links may have expired.
  Future<void> refreshIfStale() async {
    if (!_disposed && detail != null && urlsStale) await refreshAll();
  }

  /// A picture failed to load (an expired signed link is the usual reason): read the shop again, at most once per 20 seconds.
  void imageFailed() {
    if (_disposed || detail == null) return;
    final now = _clock();
    final last = _lastImageRefresh;
    if (last != null && now.difference(last) < _imageRefreshGap) return;
    _lastImageRefresh = now;
    unawaited(refresh());
  }

  void markDirty() {
    dirty = true;
    _notify();
  }

  void addBoard() {
    if (boards.length >= maxBoardItems) return;
    boards.add(BoardItem(key: nextBoardKey(boards.map((b) => b.key))));
    markDirty();
  }

  void removeBoard(BoardItem b) {
    boards.remove(b);
    markDirty();
  }

  /// Reviewer notes typed. The first change flips [dirty] and tells listeners (the screen's back button must now ask before it
  /// discards the notes); the following keystrokes need no rebuild.
  void setNotes(String v) {
    notes = v;
    if (!dirty) {
      dirty = true;
      _notify();
    }
  }

  /// Saves boards, installation and notes. Returns the server's error text, or null on success. A save that is already running
  /// is not repeated: the caller gets the outcome of that one (so "save, then leave" really waits for it).
  Future<String?> saveDraft() {
    final running = _saveRun;
    if (running != null) return running;
    final run = _saveDraftOnce();
    _saveRun = run;
    unawaited(run.whenComplete(() => _saveRun = null));
    return run;
  }

  Future<String?> _saveDraftOnce() async {
    final submitting = _submitRun;
    if (submitting != null) {
      await submitting; // a submit saves the edits itself; then only what is still unsaved is saved
      if (!dirty) return null;
    }
    if (_disposed) return null;
    // The server needs at least one board when boards are sent, so a save with none would keep the old ones: say so instead.
    if (boards.isEmpty) return noBoardsSaveMessage;
    final tooTall = installation.heightProblem;
    if (tooTall != null) return tooTall;
    _pruneAnswers();
    busy = true;
    _notify();
    try {
      final d = await _api.saveDraft(siteId, mediaItems: boards, installation: installation, notes: notes);
      if (_disposed) return null;
      dirty = false;
      _adopt(d, keepLocal: false);
      return null;
    } catch (e) {
      return errorText(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  List<String> problems() => validateForSubmit(
        photos: detail?.photos ?? const [],
        boards: boards,
        installation: installation,
        installationProblems: [for (final b in boards) ...installationProblems(b)],
        pendingUploads: pending.length,
        reworks: detail?.reworks ?? const [],
        pendingReplaces: {for (final u in pending) ?u.replaces},
        pendingCategories: {for (final u in pending) u.category},
        serverMissing: detail?.missing ?? const [],
      );

  /// Validates locally, saves the draft, then submits the next version.
  Future<SubmitOutcome> submit() {
    if (detail == null) return Future.value(const SubmitOutcome(problems: ['Shop is not loaded yet']));
    if (busy || _saveRun != null || _submitRun != null) return Future.value(const SubmitOutcome(problems: ['Wait for the current save to finish']));
    final run = _submitOnce();
    _submitRun = run;
    unawaited(run.whenComplete(() => _submitRun = null));
    return run;
  }

  Future<SubmitOutcome> _submitOnce() async {
    await reapSwaps(); // an old draft that a new photo replaced must not go into the version as well
    if (_disposed || detail == null) return const SubmitOutcome(problems: ['Shop is not loaded yet']);
    final local = problems();
    if (local.isNotEmpty) return SubmitOutcome(problems: local);
    busy = true;
    _notify();
    try {
      var current = detail!;
      if (dirty) {
        current = await _api.saveDraft(siteId, mediaItems: boards, installation: installation, notes: notes);
        dirty = false;
        if (_disposed) return const SubmitOutcome();
        _adopt(current, keepLocal: false);
        // What the server still needs can change with the boards (a new board may need more photos): check again.
        final again = problems();
        if (again.isNotEmpty) return SubmitOutcome(problems: again);
      }
      final out = await _api.submit(siteId, submitKey(siteId, current.version), notes: notes);
      if (_disposed) return SubmitOutcome(version: out.version);
      _adopt(out, keepLocal: false);
      return SubmitOutcome(version: out.version);
    } catch (e) {
      return SubmitOutcome(serverError: errorText(e));
    } finally {
      busy = false;
      _notify();
    }
  }

  /// Deletes a draft photo. Returns the server's error text, or null.
  Future<String?> deletePhoto(ShopPhoto p, {String? reason}) async {
    try {
      await _api.deletePhoto(siteId, p.id, reason: reason);
      await refresh();
      return null;
    } catch (e) {
      return errorText(e);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    queue.removeListener(_onQueue);
    _catalogCtl?.removeListener(_onCatalog);
    _sub?.cancel();
    super.dispose();
  }
}
