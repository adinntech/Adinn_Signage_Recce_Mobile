import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';

/// Thumbnail of a saved preview image (falls back when the file is gone).
class PreviewThumb extends StatelessWidget {
  const PreviewThumb(this.capture, {super.key, this.height = 96});

  final PreviewCapture capture;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: height,
        width: height * 4 / 3,
        child: Image.file(
          File(capture.path),
          fit: BoxFit.cover,
          cacheWidth: 400,
          errorBuilder: (_, _, _) => Container(
            color: AdinnColors.canvas,
            alignment: Alignment.center,
            child: Icon(_icon(capture.kind), color: AdinnColors.muted),
          ),
        ),
      ),
    );
  }

  static IconData _icon(CaptureKind k) => switch (k) {
    CaptureKind.live => Icons.layers_outlined,
    CaptureKind.ar => Icons.view_in_ar,
    CaptureKind.edited => Icons.draw_outlined,
  };
}

/// Horizontal list of Live Previews / AR captures / annotated exports of a
/// media group (optionally only those showing [unitId]).
class PreviewGallery extends StatelessWidget {
  const PreviewGallery({
    super.key,
    required this.board,
    this.shopId,
    this.unitId,
    this.kinds,
    this.editable = false,
    this.emptyText,
  });

  final Board board;

  /// Live shop id; null for read-only snapshots (no delete).
  final String? shopId;
  final String? unitId;
  final Set<CaptureKind>? kinds;
  final bool editable;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final unit = board.unitById(unitId);
    final items =
        (unit == null ? board.previews : board.previewsOf(unit))
            .where((c) => kinds == null || kinds!.contains(c.kind))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (items.isEmpty) {
      return emptyText == null
          ? const SizedBox.shrink()
          : Text(
              emptyText!,
              style: const TextStyle(color: AdinnColors.muted, fontSize: 12.5),
            );
    }
    final media =
        SignageCatalog.media(board.mediaCode)?.shortName ?? board.name;
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = items[i];
          final u = board.unitById(c.unitId);
          return InkWell(
            key: ValueKey('preview-${c.id}'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PreviewViewerScreen(
                  board: board,
                  capture: c,
                  shopId: editable ? shopId : null,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PreviewThumb(c),
                const SizedBox(height: 3),
                SizedBox(
                  width: 128,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.kind.label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        u == null ? media : '$media • ${board.unitLabel(u)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5),
                      ),
                      Text(
                        fmtDateTime(c.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AdinnColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Full-screen preview image with its metadata; delete when [shopId] set.
class PreviewViewerScreen extends StatelessWidget {
  const PreviewViewerScreen({
    super.key,
    required this.board,
    required this.capture,
    this.shopId,
  });

  final Board board;
  final PreviewCapture capture;
  final String? shopId;

  @override
  Widget build(BuildContext context) {
    final units = capture.unitIds
        .map(board.unitById)
        .whereType<SignageUnit>()
        .map(board.unitLabel)
        .join(', ');
    final media = SignageCatalog.media(board.mediaCode)?.shortName ?? '';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          capture.kind.label,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          if (shopId != null)
            IconButton(
              key: const ValueKey('delete-preview'),
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Delete ${capture.kind.label.toLowerCase()}?',
                  message:
                      'Only this generated image is removed. The original '
                      'site photo and other markings stay.',
                  confirmText: 'Delete',
                  destructive: true,
                );
                if (!ok || !context.mounted) return;
                await context.read<AppController>().removePreview(
                  shopId!,
                  board.id,
                  capture.id,
                );
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: Image.file(
            File(capture.path),
            errorBuilder: (_, _, _) => const Text(
              'Image not found on device',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '${board.name} • $media${units.isEmpty ? '' : ' • $units'}\n'
            'Item ID ${capture.unitId} • Saved ${fmtDateTime(capture.createdAt)}'
            '${capture.kind == CaptureKind.ar && capture.arTransform.isNotEmpty ? '\nRotation ${((capture.arTransform['yaw'] ?? 0) * 57.2958).round()}° • scale ${fmtNum(capture.arTransform['scale'] ?? 1)}×' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ),
    );
  }
}
