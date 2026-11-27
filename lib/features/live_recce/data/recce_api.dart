import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart' show XFile;

import '../../../core/network/api_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/storage/web_media.dart';
import 'photo_shrink.dart';
import 'catalog_data.dart';
import 'recce_models.dart';

String newClientId() => 'c${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 31)}';

/// The text shown when a save is attempted with no board (the server keeps its earlier boards until at least one is sent).
const noBoardsSaveMessage = 'Add at least one board before saving. Nothing was saved: the server needs a board.';

/// A request the phone refuses to send because the server would reject or silently ignore it. [message] is for the screen.
class RecceInputException implements Exception {
  const RecceInputException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// "Android / Adinn Recce 1.0". Reviewers see which build captured a photo.
String deviceLabel() => '${kIsWeb ? 'web' : Platform.operatingSystem} / ${ApiConfig.appLabel}';

/// One photo waiting to go to the server. The phone keeps the file until the server has stored it.
class UploadItem {
  UploadItem({
    required this.id,
    required this.siteId,
    required this.path,
    required this.category,
    this.mediaKey = '',
    this.caption = '',
    this.capturedAt,
    this.lat,
    this.lng,
    this.accuracy,
    this.width,
    this.height,
    this.replaces,
    this.source = 'LIVE_CAMERA',
    this.device,
    this.status = UploadStatus.queued,
    this.progress = 0,
    this.error,
    this.retryable = true,
  });

  final String id; // clientId: the idempotency key
  final String siteId;
  final String path;
  final String category;
  final String mediaKey;
  final String caption;
  final DateTime? capturedAt;
  final double? lat;
  final double? lng;
  final double? accuracy;
  final int? width;
  final int? height;
  final String? replaces;
  final String source;
  final String? device;
  UploadStatus status;
  double progress;
  String? error;
  bool retryable;

  /// Upload that replaces ONE flagged photo: same category and board as the old photo and `replaces` = the old photo id.
  /// Every other photo stays as it is (the server marks only the old one SUPERSEDED when the next version is submitted).
  factory UploadItem.replacement(
    ShopPhoto old, {
    required String siteId,
    required String path,
    String? id,
    DateTime? capturedAt,
    double? lat,
    double? lng,
    double? accuracy,
    int? width,
    int? height,
    String? device,
  }) =>
      UploadItem(
        id: id ?? newClientId(),
        siteId: siteId,
        path: path,
        category: old.category,
        mediaKey: old.mediaKey,
        capturedAt: capturedAt,
        lat: lat,
        lng: lng,
        accuracy: accuracy,
        width: width,
        height: height,
        replaces: old.id,
        device: device,
      );

  /// The same picture and capture details for another photo place (the testing switch "use the first photo for all types").
  /// [path] must be a file of its own: the queue deletes a file after it is uploaded.
  UploadItem copyAs({required String id, required String path, required String category, required String mediaKey}) => UploadItem(
        id: id,
        siteId: siteId,
        path: path,
        category: category,
        mediaKey: mediaKey,
        caption: caption,
        capturedAt: capturedAt,
        lat: lat,
        lng: lng,
        accuracy: accuracy,
        width: width,
        height: height,
        source: source,
        device: device,
      );

  /// One object of the multipart `meta` array.
  Json meta() => {
        'clientId': id,
        'category': category,
        'mediaKey': mediaKey,
        'caption': caption,
        if (capturedAt != null) 'capturedAt': capturedAt!.toUtc().toIso8601String(),
        'lat': ?lat,
        'lng': ?lng,
        'gpsAccuracy': ?accuracy,
        'width': ?width,
        'height': ?height,
        'replaces': ?replaces,
        'source': source,
        'device': ?device,
      };

  Json toJson() => {...meta(), 'siteId': siteId, 'path': path};

  static UploadItem fromJson(Json j) => UploadItem(
        id: j['clientId'] as String,
        siteId: j['siteId'] as String,
        path: j['path'] as String,
        category: j['category'] as String,
        mediaKey: (j['mediaKey'] as String?) ?? '',
        caption: (j['caption'] as String?) ?? '',
        capturedAt: j['capturedAt'] == null ? null : DateTime.tryParse(j['capturedAt'] as String),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        accuracy: (j['gpsAccuracy'] as num?)?.toDouble(),
        width: (j['width'] as num?)?.toInt(),
        height: (j['height'] as num?)?.toInt(),
        replaces: j['replaces'] as String?,
        source: (j['source'] as String?) ?? 'LIVE_CAMERA',
        device: j['device'] as String?,
      );
}

enum UploadStatus { queued, uploading, failed }

/// Calls the shop-wise recce API. Only the shops given to this login are ever returned (backend filter).
class RecceApi {
  RecceApi(this._dio);
  final Dio _dio;

  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Json _data(Response<dynamic> r) {
    final data = (r.data as Map)['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// All shops of this login (pages of 200); `summary` counts every status.
  Future<ShopListPage> shops() => _run(() async {
        final items = <ShopSummary>[];
        var summary = <String, int>{};
        var total = 0;
        for (var page = 1; page <= 25; page++) {
          final r = await _dio.get<dynamic>('/recce/shops', queryParameters: {'page': page, 'limit': 200});
          final p = ShopListPage.fromEnvelope(r.data);
          items.addAll(p.items);
          summary = p.summary;
          total = p.total;
          if (p.items.length < 200 || items.length >= p.total) break;
        }
        return ShopListPage(items: items, total: total == 0 ? items.length : total, summary: summary);
      });

  /// The media catalog. With [version] (the one the phone holds) the server answers "unchanged" and this returns null.
  Future<CatalogData?> catalog({int? version}) => _run(() async {
        final j = _data(await _dio.get<dynamic>('/catalog', queryParameters: {'version': ?version}));
        return j['unchanged'] == true ? null : CatalogData.fromJson(j);
      });

  /* ---- media catalog admin: SUPER_ADMIN only (`catalog:manage`); `kind` is "media", "installations" or "questions" ---- */

  /// The whole catalog as it is on the server right now (no version check): the admin edits what is stored, not the saved copy.
  Future<CatalogData> catalogFull() => _run(() async => CatalogData.fromJson(_data(await _dio.get<dynamic>('/catalog'))));

  /// How many boards use each media type and installation method (a used entry cannot be deleted, only made inactive).
  Future<CatalogUsage> catalogUsage() => _run(() async => CatalogUsage.fromJson(_data(await _dio.get<dynamic>('/catalog/usage'))));

  Future<void> catalogCreate(String kind, Map<String, dynamic> body) => _run(() async {
        await _dio.post<dynamic>('/catalog/$kind', data: body);
      });

  /// [id] is the media / installation code, or the question's `uid`. [body] holds ONLY the fields that changed (the server fills nothing in).
  Future<void> catalogUpdate(String kind, String id, Map<String, dynamic> body) => _run(() async {
        await _dio.put<dynamic>('/catalog/$kind/${Uri.encodeComponent(id)}', data: body);
      });

  Future<void> catalogDelete(String kind, String id) => _run(() async {
        await _dio.delete<dynamic>('/catalog/$kind/${Uri.encodeComponent(id)}');
      });

  /// [ids] are the codes in the new order, or the uids of the questions of ONE group.
  Future<void> catalogReorder(String kind, List<String> ids) => _run(() async {
        await _dio.post<dynamic>('/catalog/reorder', data: {'kind': kind, 'ids': ids});
      });

  /// Adds back every built-in entry that was deleted; returns how many came back: `{media, installations, questions}`.
  Future<Map<String, int>> catalogLoadDefaults() => _run(() async {
        final j = _data(await _dio.post<dynamic>('/catalog/defaults', data: <String, dynamic>{}));
        return {for (final e in j.entries) e.key: e.value is num ? (e.value as num).toInt() : 0};
      });

  Future<ShopDetail> detail(String siteId) => _run(() async => ShopDetail.fromJson(_data(await _dio.get<dynamic>('/recce/shops/$siteId'))));

  /// Creates the working record (status IN_PROGRESS). Safe to call again.
  Future<void> start(String siteId) => _run(() async {
        await _dio.post<dynamic>('/recce/shops/$siteId/start', data: <String, dynamic>{});
      });

  /// Saves boards, installation and notes. [mediaItems] null = leave the boards as they are; an EMPTY list is refused here
  /// (the server needs at least one board when `mediaItems` is sent), never silently dropped from the body, so the caller can
  /// not report a save that did not keep the boards. The installation goes as [Installation.toDraftJson]: a cleared height is
  /// an explicit `null`.
  Future<ShopDetail> saveDraft(String siteId, {List<BoardItem>? mediaItems, Installation? installation, String? notes}) => _run(() async {
        if (mediaItems != null && mediaItems.isEmpty) throw const RecceInputException(noBoardsSaveMessage);
        final body = <String, dynamic>{
          if (mediaItems != null) 'mediaItems': [for (final b in mediaItems) b.toJson()],
          'installation': ?installation?.toDraftJson(),
          'notes': notes ?? '',
        };
        return ShopDetail.fromJson(_data(await _dio.put<dynamic>('/recce/shops/$siteId/draft', data: body)));
      });

  /// The file part of one photo. A picture over the server's size limit is re-encoded smaller first (the server answers 413
  /// to anything above it); a picture that already fits is sent exactly as it was taken. The file name carries the extension
  /// of what the bytes really are (a PNG is `.png`, not `.jpg`).
  Future<MultipartFile> _photoPart(UploadItem u) async {
    MultipartFile of(Uint8List bytes) => MultipartFile.fromBytes(bytes, filename: 'photo_${u.id}.${photoExtension(bytes)}');
    if (kIsWeb) {
      // Browser: no dart:io File. A photo kept in memory (`mem://`) is read from there; a picked file (a blob link) is read as bytes.
      final kept = isMemPath(u.path) ? getMem(u.path) : null;
      if (isMemPath(u.path) && kept == null) throw const RecceInputException('This photo is no longer in the browser (the page was reloaded). Take it again.');
      return of(await shrinkPhoto(kept ?? await XFile(u.path).readAsBytes()));
    }
    final file = File(u.path);
    if (await file.length() <= serverPhotoLimitBytes) return MultipartFile.fromFile(u.path, filename: u.path.split(RegExp(r'[\\/]')).last);
    return of(await shrinkPhoto(await file.readAsBytes()));
  }

  Future<void> uploadPhoto(UploadItem u, {required void Function(double) onProgress, CancelToken? cancel}) => _run(() async {
        final form = FormData.fromMap({
          'photos': await _photoPart(u),
          'meta': jsonEncode([u.meta()]),
        });
        await _dio.post<dynamic>(
          '/recce/shops/${u.siteId}/photos',
          data: form,
          cancelToken: cancel,
          onSendProgress: (s, t) => onProgress(t <= 0 ? 0 : s / t),
        );
      });

  /// Saves the 2D drawing ([kind] `2d`) or the 3D preview (`3d`) picture of ONE board (`PUT /recce/shops/:siteId/boards/:mediaKey/renders/:kind`).
  /// The server keeps it inside the shop's document with that board; sending it again replaces the earlier draft picture.
  Future<ShopDetail> saveBoardRender(String siteId, String mediaKey, String kind, Uint8List png) => _run(() async {
        final form = FormData.fromMap({'file': MultipartFile.fromBytes(png, filename: 'board_${mediaKey}_$kind.png')});
        return ShopDetail.fromJson(_data(await _dio.put<dynamic>('/recce/shops/$siteId/boards/${Uri.encodeComponent(mediaKey)}/renders/$kind', data: form)));
      });

  Future<void> deletePhoto(String siteId, String photoId, {String? reason}) => _run(() async {
        await _dio.delete<dynamic>('/recce/shops/$siteId/photos/$photoId', queryParameters: {'reason': ?reason});
      });

  List<Json> _list(Response<dynamic> r) {
    final data = (r.data as Map)['data'];
    return data is List ? [for (final e in data) if (e is Map) Map<String, dynamic>.from(e)] : <Json>[];
  }

  /// Every immutable version of the shop, oldest first (`GET /recce/shops/:siteId/versions`).
  Future<List<RecceVersion>> versions(String siteId) => _run(() async {
        final r = await _dio.get<dynamic>('/recce/shops/$siteId/versions');
        return [for (final e in _list(r)) RecceVersion.fromJson(e)];
      });

  /// What changed between two versions (`GET /recce/shops/:siteId/versions/compare?from=&to=`).
  Future<VersionCompare> compare(String siteId, int from, int to) => _run(() async {
        final r = await _dio.get<dynamic>('/recce/shops/$siteId/versions/compare', queryParameters: {'from': from, 'to': to});
        return VersionCompare.fromJson(_data(r));
      });

  /// Revisions, events and rework requests of one photo (`GET /recce/shops/:siteId/photos/:photoId/history`).
  Future<PhotoHistory> photoHistory(String siteId, String photoId) => _run(() async {
        final r = await _dio.get<dynamic>('/recce/shops/$siteId/photos/$photoId/history');
        return PhotoHistory.fromJson(_data(r));
      });

  /// The shop's timeline as the server sends it, newest first (`GET /recce/shops/:siteId/activity`, up to 300 events).
  Future<List<ActivityEvent>> activity(String siteId, {int limit = 300}) => _run(() async {
        final r = await _dio.get<dynamic>('/recce/shops/$siteId/activity', queryParameters: {'limit': limit});
        return [for (final e in _list(r)) ActivityEvent.fromJson(e)];
      });

  /* ------------------------------------------------------------------ Milestone 3: thread, dashboard, notifications */

  /// One page of the shop thread, NEWEST first (`?limit=&before=`); pass the page's `nextBefore` as [before] for the next, older page.
  Future<ChatPage> messages(String siteId, {int limit = chatPageSize, String? before}) => _run(() async {
        final r = await _dio.get<dynamic>('/recce/shops/$siteId/messages', queryParameters: {'limit': limit, 'before': ?before});
        return ChatPage.fromEnvelope(r.data);
      });

  /// Messages from other people since this login last marked the thread read.
  Future<int> messagesUnread(String siteId) => _run(() async => parseUnread((await _dio.get<dynamic>('/recce/shops/$siteId/messages/unread')).data));

  /// Marks the thread read (safe to repeat); the server also marks this shop's message notifications read.
  Future<void> markMessagesRead(String siteId) => _run(() async {
        await _dio.post<dynamic>('/recce/shops/$siteId/messages/read', data: <String, dynamic>{});
      });

  /// Posts a message: JSON for text and refs, multipart (`body`, `refs` as a JSON string, one image in `file`) with an image.
  /// The picked file is read as bytes (`XFile`), so it works the same in a browser. Returns the created message.
  Future<ChatMessage> postMessage(
    String siteId, {
    String body = '',
    List<ChatRef> refs = const [],
    String? imagePath,
    String? imageName,
    void Function(double)? onProgress,
    CancelToken? cancel,
  }) =>
      _run(() async {
        final text = body.trim();
        final refJson = [for (final r in uniqueRefs(refs)) r.toJson()];
        Object payload = {'body': text, 'refs': refJson};
        if (imagePath != null) {
          final List<int> bytes;
          try {
            bytes = await XFile(imagePath).readAsBytes();
          } catch (_) {
            throw const RecceInputException('The photo could not be read. Pick it again.');
          }
          payload = FormData.fromMap({
            'body': text,
            'refs': jsonEncode(refJson),
            'file': MultipartFile.fromBytes(bytes, filename: chatImageName(imageName ?? imagePath, bytes)),
          });
        }
        final r = await _dio.post<dynamic>(
          '/recce/shops/$siteId/messages',
          data: payload,
          cancelToken: cancel,
          onSendProgress: (s, t) => onProgress?.call(t <= 0 ? 0 : s / t),
        );
        return ChatMessage.fromJson(_data(r));
      });

  /// The field dashboard (`GET /recce/dashboard`): only the shops given to this login.
  Future<FieldDashboard> dashboard() => _run(() async => FieldDashboard.fromJson(_data(await _dio.get<dynamic>('/recce/dashboard'))));

  /// The bell: the newest notifications and the unread total (`GET /notifications`).
  Future<NotificationFeed> notifications() => _run(() async => NotificationFeed.fromEnvelope((await _dio.get<dynamic>('/notifications')).data));

  Future<void> markNotificationRead(String id) => _run(() async {
        await _dio.post<dynamic>('/notifications/${Uri.encodeComponent(id)}/read', data: <String, dynamic>{});
      });

  Future<void> markAllNotificationsRead() => _run(() async {
        await _dio.post<dynamic>('/notifications/read', data: <String, dynamic>{});
      });

  /// Submits a version. The same [idempotencyKey] returns the same version (never a second one).
  /// The server answers the shop detail, or `{duplicate, version, detail}`; both are handled.
  Future<ShopDetail> submit(String siteId, String idempotencyKey, {String? notes}) => _run(() async {
        final r = await _dio.post<dynamic>(
          '/recce/shops/$siteId/submit',
          data: {'idempotencyKey': idempotencyKey, if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim()},
        );
        final data = _data(r);
        return ShopDetail.fromJson(data['detail'] is Map ? Map<String, dynamic>.from(data['detail'] as Map) : data);
      });
}

/// Idempotency key of one submit attempt: stable per shop and version, so a double tap or a retry never makes two versions.
String submitKey(String siteId, int currentVersion) => 'submit-$siteId-${currentVersion + 1}';
