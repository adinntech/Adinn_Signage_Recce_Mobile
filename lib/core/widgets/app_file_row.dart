import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/storage/web_media.dart';
import '../theme/app_theme.dart';

enum AppFileState { waiting, uploading, done, failed }

/// A stored picture (signed link to the file storage). Use this instead of a bare `Image.network` for every stored file.
/// In Chrome, Flutter reads a picture with a script request (XHR), which the storage host blocks with a CORS error unless
/// its bucket has a CORS rule. `prefer` shows it with a plain `<img>` element instead: no CORS check, no rule to maintain.
/// On a phone this is an ordinary `Image.network`.
Widget appNetworkImage(
  String url, {
  BoxFit? fit,
  int? cacheWidth,
  ImageLoadingBuilder? loadingBuilder,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  return Image.network(
    url,
    fit: fit,
    cacheWidth: cacheWidth,
    loadingBuilder: loadingBuilder,
    errorBuilder: errorBuilder,
    webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
  );
}

/// One file in an upload list: thumbnail, name, size, live state with a progress bar, then View, Download and Remove
/// (Cancel while uploading, Retry when failed). Use it for every file list in the app (same behaviour as web and the field app).
class AppFileRow extends StatelessWidget {
  const AppFileRow({
    super.key,
    required this.name,
    this.subtitle,
    this.size,
    this.state = AppFileState.done,
    this.progress = 0,
    this.message,
    this.localPath,
    this.url,
    this.badge,
    this.flagged = false,
    this.onTap,
    this.onRemove,
    this.onCancel,
    this.onRetry,
  });

  final String name;
  final String? subtitle;
  final int? size;
  final AppFileState state;
  final double progress; // 0..1
  final String? message;
  final String? localPath;
  final String? url;
  final Widget? badge;

  /// Red border and tint (a reviewer asked for this file to be replaced).
  final bool flagged;

  /// Replaces the default tap (open the full-screen viewer). The View button still opens the viewer.
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  static String bytes(int? b) {
    if (b == null) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  static Widget image(String? url, String? localPath, {BoxFit fit = BoxFit.cover, int? cacheWidth}) {
    const broken = ColoredBox(color: AdinnColors.canvas, child: Icon(Icons.broken_image_outlined, color: AdinnColors.muted));
    if (url != null) return appNetworkImage(url, fit: fit, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => broken);
    if (localPath != null) {
      if (isMemPath(localPath)) {
        final kept = getMem(localPath);
        return kept == null ? broken : Image.memory(kept, fit: fit, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => broken);
      }
      return kIsWeb
          ? Image.network(localPath, fit: fit, errorBuilder: (_, _, _) => broken)
          : Image.file(File(localPath), fit: fit, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => broken);
    }
    return const ColoredBox(color: AdinnColors.canvas, child: Icon(Icons.insert_drive_file_outlined, color: AdinnColors.muted));
  }

  void _view(BuildContext context) {
    if (url == null && localPath == null) return;
    showAppPhotoViewer(context, title: name, url: url, localPath: localPath);
  }

  @override
  Widget build(BuildContext context) {
    final failed = state == AppFileState.failed;
    final uploading = state == AppFileState.uploading;
    final done = state == AppFileState.done;
    final status = switch (state) {
      AppFileState.waiting => const Text('Waiting to upload', style: TextStyle(fontSize: 12, color: AdinnColors.muted)),
      AppFileState.uploading => Text('Uploading ${(progress * 100).round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AdinnColors.info)),
      AppFileState.done => const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle, size: 14, color: AdinnColors.success),
          SizedBox(width: 4),
          Text('Uploaded', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AdinnColors.success)),
        ]),
      AppFileState.failed => const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 14, color: AdinnColors.red),
          SizedBox(width: 4),
          Text('Upload failed', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AdinnColors.red)),
        ]),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: failed || flagged ? AdinnColors.redLight : Colors.white,
      shape: flagged ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AdinnColors.red, width: 1.4)) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap ?? ((url != null || localPath != null) ? () => _view(context) : null),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SizedBox(width: 48, height: 48, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: image(url, localPath, cacheWidth: 200))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (size != null) Text(bytes(size), style: const TextStyle(fontSize: 12, color: AdinnColors.muted)),
                    status,
                    if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: const TextStyle(fontSize: 12, color: AdinnColors.muted)),
                    ?badge,
                  ]),
                ]),
              ),
              if (failed && onRetry != null) IconButton(tooltip: 'Retry', icon: const Icon(Icons.refresh, color: AdinnColors.info), onPressed: onRetry),
              if (done && (url != null || localPath != null)) IconButton(tooltip: 'View', icon: const Icon(Icons.visibility_outlined), onPressed: () => _view(context)),
              if (done && url != null) IconButton(tooltip: 'Download', icon: const Icon(Icons.download_outlined), onPressed: () => downloadFile(context, url!)),
              if (uploading && onCancel != null)
                IconButton(tooltip: 'Cancel upload', icon: const Icon(Icons.close, color: AdinnColors.red), onPressed: onCancel)
              else if (!uploading && onRemove != null)
                IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, color: AdinnColors.red), onPressed: onRemove),
            ]),
            if (uploading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: progress > 0 ? progress : null, minHeight: 8, backgroundColor: AdinnColors.line, color: AdinnColors.red),
                ),
              ),
            if (failed && (message ?? '').isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(message!, style: const TextStyle(fontSize: 12, color: AdinnColors.red))),
          ]),
        ),
      ),
    );
  }
}

/// Opens the stored file in the browser / system viewer, which downloads or saves it.
Future<void> downloadFile(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the download')));
  }
}

/// Full-screen picture with pinch / double-tap zoom and a download button.
Future<void> showAppPhotoViewer(BuildContext context, {required String title, String? url, String? localPath}) {
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (ctx) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(children: [
        Positioned.fill(child: InteractiveViewer(maxScale: 6, child: AppFileRow.image(url, localPath, fit: BoxFit.contain))),
        SafeArea(
          child: Row(children: [
            IconButton(color: Colors.white, icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            if (url != null) IconButton(color: Colors.white, tooltip: 'Download', icon: const Icon(Icons.download_outlined), onPressed: () => downloadFile(ctx, url)),
          ]),
        ),
      ]),
    ),
  );
}
