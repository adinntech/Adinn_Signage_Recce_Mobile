import '../../l10n/l10n.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import 'report_data.dart';
import 'report_service.dart';
import '../../core/widgets/adinn_app_bar.dart';

/// Generate, preview, share and browse the shop's measurement PDFs.
/// Everything stays on the device (no cloud upload, no e-mail).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.shopId, this.service});

  final String shopId;
  final ReportService? service;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportService _service = widget.service ?? ReportService();
  bool _busy = false;
  String _progress = '';

  Future<void> _generate() async {
    final c = context.read<AppController>();
    setState(() {
      _busy = true;
      _progress = 'Starting…';
    });
    try {
      final r = await _service.generate(
        c,
        widget.shopId,
        onProgress: (m) {
          if (mounted) setState(() => _progress = m);
        },
      );
      if (mounted) {
        showSnack(
          context,
          '${r.isDraft ? 'Draft' : 'Approved'} report saved '
          '(${r.pageCount} page${r.pageCount == 1 ? '' : 's'})',
        );
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, context.uf('Could not create the PDF: {0}', [e]), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List?> _bytes(RecceReport r) async {
    final bytes = await _service.read(r);
    if (bytes == null && mounted) {
      showSnack(
        context,
        context.ui('PDF file not found on this device. Generate it again.'),
        error: true,
      );
    }
    return bytes;
  }

  String _fileName(Shop? shop, RecceReport r) {
    final name = (shop?.name ?? 'shop')
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+$'), '');
    return 'Recce_${name}_v${r.version}_${r.isDraft ? 'DRAFT' : 'APPROVED'}.pdf';
  }

  Future<void> _preview(Shop? shop, RecceReport r) async {
    final bytes = await _bytes(r);
    if (bytes == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportPreviewScreen(
          bytes: bytes,
          title: r.isDraft
              ? 'Draft report v${r.version}'
              : 'Report v${r.version}',
          fileName: _fileName(shop, r),
        ),
      ),
    );
  }

  Future<void> _share(Shop? shop, RecceReport r) async {
    final bytes = await _bytes(r);
    if (bytes == null || !mounted) return;
    try {
      await Printing.sharePdf(bytes: bytes, filename: _fileName(shop, r));
    } catch (e) {
      if (mounted) {
        showSnack(context, context.uf('Sharing is not available: {0}', [e]), error: true);
      }
    }
  }

  Future<void> _delete(RecceReport r) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete report?',
      message: 'The PDF file will be removed from this device.',
      confirmText: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<AppController>().deleteReport(r.id);
    if (mounted) showSnack(context, context.ui('Report deleted'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(widget.shopId);
    if (shop == null) {
      return Scaffold(
        appBar: AdinnAppBar(title: Text(context.ui('Measurement PDF'))),
        body: const EmptyState(icon: Icons.search_off, title: 'Shop not found'),
      );
    }
    final reports = c.reportsForShop(shop.id);
    final approved = shop.status == RecceStatus.approved;
    final source = reportUsesSnapshot(shop)
        ? 'Uses submitted version v${shop.currentVersion}.'
        : 'Uses the current draft data.';
    return Scaffold(
      appBar: AdinnAppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.ui('Measurement PDF')),
            Text(
              shop.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            key: const Key('report_status_banner'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (approved ? AdinnColors.success : AdinnColors.red)
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: approved ? AdinnColors.success : AdinnColors.red,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  approved ? Icons.verified : Icons.edit_document,
                  color: approved ? AdinnColors.success : AdinnColors.red,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        approved
                            ? 'Approved for fabrication – v${shop.currentVersion}'
                            : kDraftBanner,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: approved
                              ? AdinnColors.success
                              : AdinnColors.red,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Status: ${shop.status.label}. $source',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('report_generate'),
            onPressed: _busy ? null : _generate,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_busy ? 'Generating…' : 'Generate PDF'),
          ),
          if (_busy) ...[
            const SizedBox(height: 6),
            Text(
              _progress,
              key: const Key('report_progress'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
            ),
          ],
          const SizedBox(height: 4),
          Text(context.ui('Saved on this device only. Preview, then share via the Android '
            'share sheet if needed.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AdinnColors.muted),
          ),
          const SizedBox(height: 16),
          Text(
            'Previous reports (${reports.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          if (reports.isEmpty)
            const EmptyState(
              icon: Icons.picture_as_pdf_outlined,
              title: 'No reports yet',
              message: 'Generate a PDF to keep a snapshot of this recce.',
            ),
          for (final r in reports)
            Card(
              key: Key('report_${r.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TagChip(
                          r.isDraft ? 'DRAFT' : 'APPROVED',
                          color: r.isDraft
                              ? AdinnColors.red
                              : AdinnColors.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'v${r.version} • ${r.status.label}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${fmtDateTime(r.generatedAt)} • ${r.pageCount} '
                      'page${r.pageCount == 1 ? '' : 's'} • '
                      '${fmtBytes(r.sizeBytes)} • by ${r.generatedByName}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdinnColors.muted,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          key: Key('report_preview_${r.id}'),
                          onPressed: () => _preview(shop, r),
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: Text(context.ui('Preview')),
                        ),
                        TextButton.icon(
                          key: Key('report_share_${r.id}'),
                          onPressed: () => _share(shop, r),
                          icon: const Icon(Icons.share_outlined, size: 18),
                          label: Text(context.ui('Share')),
                        ),
                        IconButton(
                          key: Key('report_delete_${r.id}'),
                          tooltip: context.ui('Delete'),
                          onPressed: () => _delete(r),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AdinnColors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// In-app PDF viewer (rendered with the printing plugin).
class ReportPreviewScreen extends StatelessWidget {
  const ReportPreviewScreen({
    super.key,
    required this.bytes,
    required this.title,
    required this.fileName,
  });

  final Uint8List bytes;
  final String title;
  final String fileName;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AdinnAppBar(title: Text(title)),
    body: PdfPreview(
      build: (_) async => bytes,
      pdfFileName: fileName,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      allowPrinting: true,
      allowSharing: true,
    ),
  );
}
