import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../data/storage/media_storage.dart';
import '../../state/app_controller.dart';
import '../survey/photo_render.dart';
import '../survey/site_markup_painter.dart';
import '../model3d/signage_spec.dart';
import '../model3d/technical_drawing.dart';
import 'model_image_renderer.dart';
import 'report_data.dart';
import 'report_pdf.dart';

/// Long side of pictures placed in the PDF (pixels).
const kReportImageMaxSide = 1400;

/// JPEG quality of PDF pictures.
const kReportJpegQuality = 75;

/// Resolves the pictures of a report. Injectable so tests never decode
/// real files or use platform image codecs.
abstract class ReportImageLoader {
  /// A site photo, optionally with annotations + advanced markup.
  Future<ReportImage?> photo(
    SitePhoto photo, {
    required bool annotated,
    MarkupLabels? labels,
  });

  /// An image file on the device (previews, comparisons, drawings).
  Future<ReportImage?> file(String path);
}

class _RgbaJob {
  const _RgbaJob(this.rgba, this.width, this.height, this.quality);

  final Uint8List rgba;
  final int width;
  final int height;
  final int quality;
}

Uint8List _encodeJpeg(_RgbaJob job) {
  final image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: job.rgba.buffer,
    numChannels: 4,
  );
  return img.encodeJpg(image, quality: job.quality);
}

/// Default loader: renders with the engine (fast, downscaled decode) and
/// JPEG-compresses in a background isolate.
class DeviceReportImageLoader implements ReportImageLoader {
  const DeviceReportImageLoader({this.maxSide = kReportImageMaxSide});

  final int maxSide;

  Future<ReportImage?> _compress(ui.Image? image) async {
    if (image == null) return null;
    try {
      final rgba = await rgbaBytes(image);
      if (rgba == null) return null;
      final jpeg = await compute(
        _encodeJpeg,
        _RgbaJob(rgba, image.width, image.height, kReportJpegQuality),
      );
      return ReportImage(jpeg, image.width, image.height);
    } catch (_) {
      return null;
    } finally {
      image.dispose();
    }
  }

  @override
  Future<ReportImage?> photo(
    SitePhoto photo, {
    required bool annotated,
    MarkupLabels? labels,
  }) async {
    try {
      final image = await renderPhotoComposite(
        photo,
        maxSide: maxSide,
        annotations: annotated,
        markup: annotated ? photo.markup : null,
        labels: labels,
      );
      return _compress(image);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ReportImage?> file(String path) async {
    if (path.isEmpty || path.startsWith(SitePhoto.demoPrefix)) return null;
    return _compress(await decodeImageFile(path, maxSide: maxSide));
  }
}

/// Generates, stores and reads measurement PDFs. Everything is local: no
/// upload, no e-mail.
class ReportService {
  ReportService({
    ReportImageLoader? images,
    ModelImageRenderer? models,
    this.writer,
    this.reader,
    DateTime Function()? clock,
    this.useIsolate = true,
    this.compress = true,
  }) : images = images ?? const DeviceReportImageLoader(),
       // Device default renders offscreen; a custom (test) image loader
       // without a model renderer gets none – the PDF then reports the
       // 2D / 3D images as not generated.
       models =
           models ??
           (images == null ? const OffscreenModelImageRenderer() : null),
       clock = clock ?? DateTime.now;

  final ReportImageLoader images;

  /// 2D drawing / 3D model pictures (null = not available).
  final ModelImageRenderer? models;

  /// Saves the PDF bytes and returns the file path (default: app storage).
  final Future<String> Function(Uint8List bytes)? writer;

  /// Reads a saved PDF (default: the file at the path; null if missing).
  final Future<Uint8List?> Function(String path)? reader;
  final DateTime Function() clock;

  /// Build the PDF in a background isolate (disable in widget tests).
  final bool useIsolate;
  final bool compress;

  Future<String> _write(AppController c, Uint8List bytes) async {
    if (writer != null) return writer!(bytes);
    final media = c.media ?? MediaStorage();
    final path = await media.newFilePath('reports', 'pdf');
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<Map<String, ReportImage>> _loadImages(
    ReportBuild build,
    MarkupLabels labels,
    void Function(String)? onProgress,
  ) async {
    final out = <String, ReportImage>{};
    var i = 0;
    for (final ref in build.images) {
      i++;
      onProgress?.call('Preparing pictures $i of ${build.images.length}…');
      ReportImage? image;
      try {
        switch (ref.kind) {
          case ReportImageKind.photo:
          case ReportImageKind.annotated:
            final photo = build.source.boards
                .where((b) => b.id == ref.boardId)
                .expand((b) => b.photos)
                .where((p) => p.id == ref.photoId)
                .firstOrNull;
            if (photo != null) {
              image = await images.photo(
                photo,
                annotated: ref.kind == ReportImageKind.annotated,
                labels: labels,
              );
            }
          case ReportImageKind.file:
            image = await images.file(ref.path ?? '');
          case ReportImageKind.drawing2d:
          case ReportImageKind.model3d:
            final b = build.source.boards
                .where((e) => e.id == ref.boardId)
                .firstOrNull;
            final u = b?.unitById(ref.unitId);
            final r = models;
            if (b != null && u != null && r != null) {
              final spec = SignageModelSpec.of(b, u);
              image = ref.kind == ReportImageKind.model3d
                  ? await r.model(spec, brand: labels.brand)
                  : await r.drawing(
                      spec,
                      DrawingView.values.firstWhere(
                        (v) => v.name == ref.view,
                        orElse: () => DrawingView.front,
                      ),
                    );
            }
        }
      } catch (_) {
        image = null;
      }
      if (image != null) out[ref.key] = image;
    }
    return out;
  }

  /// Builds the PDF for [shopId], saves it locally and records it with
  /// [AppController.addReport]. The stored snapshot never changes later.
  Future<RecceReport> generate(
    AppController c,
    String shopId, {
    void Function(String message)? onProgress,
  }) async {
    final shop = c.shop(shopId);
    if (shop == null) throw StateError('Shop not found');
    final now = clock();
    final by = c.currentUser?.name ?? 'Unknown user';
    onProgress?.call('Collecting recce data…');
    final build = buildReportData(c, shop, now: now, generatedBy: by);
    final project = c.project(shop.projectId);
    final labels = MarkupLabels.forShop(
      build.source,
      brand: project?.client ?? '',
    );
    final pictures = await _loadImages(build, labels, onProgress);
    onProgress?.call('Building PDF…');
    final input = ReportInput(
      data: build.data,
      images: pictures,
      compress: compress,
    );
    final output = useIsolate
        ? await compute(buildReportPdf, input)
        : await buildReportPdf(input);
    onProgress?.call('Saving…');
    final path = await _write(c, output.bytes);
    final report = RecceReport(
      id: newId('rp'),
      shopId: shop.id,
      projectId: shop.projectId,
      taskId: shop.taskId,
      version: shop.currentVersion,
      status: shop.status,
      isDraft: shop.status != RecceStatus.approved,
      generatedAt: now,
      generatedByName: by,
      path: path,
      sizeBytes: output.bytes.length,
      pageCount: output.pageCount,
      snapshot: {
        ...build.data,
        'images': [for (final r in build.images) r.toJson()],
      },
    );
    c.addReport(report);
    return report;
  }

  /// Bytes of a saved report; null when the file is gone.
  Future<Uint8List?> read(RecceReport r) async {
    if (reader != null) return reader!(r.path);
    try {
      final f = File(r.path);
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}

/// "245 KB" / "1.4 MB".
String fmtBytes(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).ceil()} KB'
    : '${fmtNum(bytes / (1024 * 1024), maxDecimals: 1)} MB';
