import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import 'panorama_io.dart';
import 'panorama_viewer_screen.dart';

/// Optional 360° panoramas of a shop: import (Mode A), view and place
/// signage (Mode C). Guided capture / stitching (Mode B) is not available
/// on this build and says so.
class PanoramaListScreen extends StatefulWidget {
  const PanoramaListScreen({
    super.key,
    required this.shopId,
    this.picker,
    this.probe,
    this.writer,
    this.imageLoader,
    this.previewWriter,
  });

  final String shopId;

  /// Injectables (tests); default to image_picker / dart:ui / MediaStorage.
  final PanoramaPicker? picker;
  final PanoramaImageProbe? probe;
  final PanoramaFileWriter? writer;
  final PanoramaImageLoader? imageLoader;
  final PanoramaPreviewWriter? previewWriter;

  @override
  State<PanoramaListScreen> createState() => _PanoramaListScreenState();
}

class _PanoramaListScreenState extends State<PanoramaListScreen> {
  bool _busy = false;
  String? _error;
  bool _permissionDenied = false;

  Future<void> _import() async {
    final c = context.read<AppController>();
    setState(() {
      _busy = true;
      _error = null;
      _permissionDenied = false;
    });
    try {
      final picked = await (widget.picker ?? const ImagePickerPanoramaPicker())
          .pickFromGallery();
      if (picked == null) return;
      final importer = PanoramaImporter(
        probe: widget.probe ?? const DartUiPanoramaProbe(),
        writer: widget.writer ?? mediaPanoramaWriter(c.media),
      );
      await importer.importInto(c, widget.shopId, picked);
      if (mounted) showSnack(context, 'Panorama imported');
    } on PanoramaPickerException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _permissionDenied =
              e.failure == PanoramaPickerFailure.permissionDenied;
        });
      }
    } on PanoramaImportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not import: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(PanoramaRecord p) async {
    final c = context.read<AppController>();
    final ok = await confirmDialog(
      context,
      title: 'Remove panorama?',
      message:
          '${p.label} and its ${p.placements.length} placement(s) will be '
          'removed from this device.',
      confirmText: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await c.deletePanorama(p.id);
    } on Object catch (e) {
      if (mounted) showSnack(context, 'Could not remove: $e', error: true);
    }
  }

  void _open(PanoramaRecord p) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PanoramaViewerScreen(
        shopId: widget.shopId,
        panoramaId: p.id,
        imageLoader: widget.imageLoader,
        previewWriter: widget.previewWriter,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(widget.shopId);
    if (shop == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('360° site panorama')),
        body: const EmptyState(
          icon: Icons.storefront_outlined,
          title: 'Shop not found',
        ),
      );
    }
    final editable = c.canEdit(shop);
    final items = c.panoramasForShop(shop.id);
    return Scaffold(
      appBar: AppBar(title: const Text('360° site panorama')),
      // A handful of panoramas per shop: a plain scroll view keeps every
      // entry built (no lazy list needed).
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: 'Optional 360° panorama',
              icon: Icons.panorama_photosphere_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Import an equirectangular 360° image (2:1, at least '
                    '$panoramaMinWidth px wide) from a 360° camera or a phone '
                    'panorama app, then look around and place signage items. '
                    'The viewer uses an approximate flat projection; a '
                    'panorama is an image, not a measured 3D reconstruction.',
                    style: TextStyle(fontSize: 12, color: AdinnColors.muted),
                  ),
                  const SizedBox(height: 10),
                  if (editable)
                    FilledButton.icon(
                      key: const Key('pano_import'),
                      onPressed: _busy ? null : _import,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_upload_outlined),
                      label: const Text('Import panorama from gallery'),
                    )
                  else
                    const Text(
                      'View only – this recce cannot be edited now.',
                      key: Key('pano_read_only'),
                      style: TextStyle(fontSize: 12, color: AdinnColors.muted),
                    ),
                  if (_error != null)
                    Container(
                      key: const Key('pano_import_error'),
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AdinnColors.redLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _error!,
                            style: const TextStyle(color: AdinnColors.redDark),
                          ),
                          if (_permissionDenied)
                            TextButton(
                              key: const Key('pano_open_settings'),
                              onPressed: openAppSettings,
                              child: const Text('Open app settings'),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: EmptyState(
                  key: Key('pano_empty'),
                  icon: Icons.panorama_outlined,
                  title: 'No panorama yet',
                  message:
                      'Panoramas are optional. Normal site photos and Live '
                      'Preview work without one.',
                ),
              ),
            for (final p in items)
              Card(
                child: ListTile(
                  key: Key('pano_${p.id}'),
                  contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 72,
                      height: 36,
                      child: Image.file(
                        File(p.path),
                        fit: BoxFit.cover,
                        cacheWidth: 240,
                        errorBuilder: (_, _, _) => Container(
                          color: AdinnColors.canvas,
                          child: const Icon(
                            Icons.panorama_outlined,
                            color: AdinnColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  title: Text(p.label),
                  subtitle: Text(
                    '${p.width}×${p.height} px • ${p.placements.length} '
                    'placement(s) • ${fmtDateTime(p.importedAt)}',
                  ),
                  trailing: editable
                      ? IconButton(
                          key: Key('pano_delete_${p.id}'),
                          tooltip: 'Remove panorama',
                          onPressed: () => _delete(p),
                          icon: const Icon(Icons.delete_outline),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () => _open(p),
                ),
              ),
            const SizedBox(height: 4),
            const _GuidedCaptureUnsupportedCard(),
          ],
        ),
      ),
    );
  }
}

/// Mode B (guided capture + stitching) is intentionally not implemented:
/// there is no verified offline Flutter stitching solution.
class _GuidedCaptureUnsupportedCard extends StatelessWidget {
  const _GuidedCaptureUnsupportedCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      key: Key('pano_guided_unsupported'),
      child: ListTile(
        leading: Icon(Icons.block_outlined, color: AdinnColors.muted),
        title: Text('Guided 360° capture – not supported on this build'),
        subtitle: Text(
          'In-app capture and stitching of a panorama is not available '
          'offline. Normal photo capture and Live Preview remain available. '
          'Remember: a panorama is an image, not a metric 3D reconstruction.',
        ),
        isThreeLine: true,
      ),
    );
  }
}
