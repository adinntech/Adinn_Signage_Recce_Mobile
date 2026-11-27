import '../../l10n/l10n.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../board/media_tabs.dart';
import 'report_service.dart';
import 'reports_screen.dart';

/// Which boards go into a Recce PDF.
class RecceReportScope {
  const RecceReportScope.combined() : groupIds = null;
  const RecceReportScope.group(Set<String> this.groupIds);

  /// Null = combined report (all media groups).
  final Set<String>? groupIds;

  bool get combined => groupIds == null;
}

/// File name: shop + media group (or All_Media) + report date.
String recceReportFileName(Shop shop, String part, DateTime when) {
  String clean(String s) => s
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final d =
      '${when.year}${when.month.toString().padLeft(2, '0')}'
      '${when.day.toString().padLeft(2, '0')}';
  return 'Recce_${clean(shop.name)}_${clean(part)}_$d.pdf';
}

/// "Recce Report" card on Shop Details: Preview / Download, enabled only
/// when the whole shop's Vendor Recce is complete.
class RecceReportCard extends StatefulWidget {
  const RecceReportCard({super.key, required this.shopId, this.service});

  final String shopId;
  final ReportService? service;

  /// Platform adapters for widget tests (null in production): the report
  /// service (storage), the PDF viewer (printing plugin) and the share sheet.
  static ReportService? testService;
  static Future<void> Function(Uint8List bytes, String name)? testViewer;
  static Future<void> Function(Uint8List bytes, String name)? testShare;

  @override
  State<RecceReportCard> createState() => _RecceReportCardState();
}

class _RecceReportCardState extends State<RecceReportCard> {
  late final ReportService _service =
      widget.service ?? RecceReportCard.testService ?? ReportService();
  bool _busy = false;
  String _progress = '';

  bool _choosing = false;

  Future<void> _run({required bool preview}) async {
    // No duplicate popups or exports from rapid taps.
    if (_busy || _choosing) return;
    final c = context.read<AppController>();
    final shop = c.shop(widget.shopId);
    if (shop == null) return;
    // One media group (one or several boards): act directly, no scope
    // question. Several groups keep the Combined / Separate choice.
    final groups = [
      for (final b in shop.boards)
        if (SignageCatalog.media(b.mediaCode) != null) b,
    ];
    if (groups.isEmpty) return;
    final RecceReportScope? scope;
    if (groups.length == 1) {
      scope = RecceReportScope.group({groups.single.id});
    } else {
      _choosing = true;
      try {
        scope = await _chooseScope(shop);
      } finally {
        _choosing = false;
      }
    }
    if (scope == null || !mounted) return;
    final ids = scope.groupIds;
    setState(() {
      _busy = true;
      _progress = 'Starting…';
    });
    try {
      final r = await _service.generate(
        c,
        widget.shopId,
        groupIds: ids,
        requireComplete: true,
        tamil: c.isTamil,
        onProgress: (m) {
          if (mounted) setState(() => _progress = m);
        },
      );
      final Uint8List? bytes = await _service.read(r);
      if (bytes == null) throw StateError('The PDF file could not be read.');
      if (!mounted) return;
      final part = ids == null
          ? 'All_Media'
          : shop.boards
                .where((b) => ids.contains(b.id))
                .map(SignageCatalog.mediaNameLabel)
                .join('_');
      final name = recceReportFileName(shop, part, r.generatedAt);
      if (preview && RecceReportCard.testViewer != null) {
        await RecceReportCard.testViewer!(bytes, name);
      } else if (!preview && RecceReportCard.testShare != null) {
        await RecceReportCard.testShare!(bytes, name);
      } else if (preview) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReportPreviewScreen(
              bytes: bytes,
              title: 'Recce report',
              fileName: name,
            ),
          ),
        );
      } else {
        await Printing.sharePdf(bytes: bytes, filename: name);
      }
    } catch (e) {
      if (mounted) {
        showSnack(
          context,
          context.uf('Could not create the report: {0}. '
          'Tap again to retry.', [e is StateError ? e.message : e]),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<RecceReportScope?> _chooseScope(Shop shop) {
    final groups = [
      for (final b in shop.boards)
        if (SignageCatalog.media(b.mediaCode) != null) b,
    ];
    final c = context.read<AppController>();
    final combinedOk = recceComplete(c, shop);
    final readyIds = {
      for (final b in groups)
        if (groupReportReady(c, shop, b)) b.id,
    };
    String? choice = combinedOk ? 'all' : readyIds.firstOrNull;
    bool allowed(String? v) =>
        v != null && (v == 'all' ? combinedOk : readyIds.contains(v));
    return showModalBottomSheet<RecceReportScope>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.ui('Download Recce Report'),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: choice,
                  // Unavailable scopes cannot be chosen.
                  onChanged: (v) => set(() {
                    if (allowed(v)) choice = v;
                  }),
                  child: Column(
                    children: [
                      Opacity(
                        opacity: combinedOk ? 1 : 0.5,
                        child: RadioListTile<String>(
                          key: const Key('scope_all'),
                          value: 'all',
                          title: Text(context.ui('Combined PDF – All Media Types'),
                          ),
                          subtitle: Text(
                            combinedOk
                                ? 'One PDF with shop details, every board, '
                                      'drawings and 3D views.'
                                : 'Disabled – every media type must be '
                                      'completed first.',
                          ),
                        ),
                      ),
                      for (final b in groups)
                        Opacity(
                          opacity: readyIds.contains(b.id) ? 1 : 0.5,
                          child: RadioListTile<String>(
                            key: Key('scope_${b.id}'),
                            value: b.id,
                            title: Text(
                              'Separate PDF – '
                              '${SignageCatalog.mediaNameLabel(b)}',
                            ),
                            subtitle: Text(
                              readyIds.contains(b.id)
                                  ? '${b.name} · ${b.quantity} '
                                        'board${b.quantity == 1 ? '' : 's'} '
                                        '· Completed'
                                  : '${mediaTabStatus(c, b).label} – '
                                        '${recceReportBlockers(c, shop, groupIds: {b.id}).firstOrNull ?? ''}',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const Key('scope_go'),
                  onPressed: !allowed(choice)
                      ? null
                      : () => Navigator.pop(
                          ctx,
                          choice == 'all'
                              ? const RecceReportScope.combined()
                              : RecceReportScope.group({choice!}),
                        ),
                  child: Text(context.ui('Continue')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(widget.shopId);
    if (shop == null) return const SizedBox.shrink();
    // Enabled when the combined report OR at least one media group's
    // separate report is allowed.
    final ready =
        recceComplete(c, shop) ||
        shop.boards.any((b) => groupReportReady(c, shop, b));
    return Container(
      key: const Key('recce_report_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdinnColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.picture_as_pdf_outlined, color: AdinnColors.red),
              SizedBox(width: 8),
              Text(context.ui('Recce Report'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            recceComplete(c, shop)
                ? 'Vendor recce complete. Download a combined or media-wise '
                      'report. (Does not change approval status.)'
                : ready
                ? '${shop.boards.where((b) => groupReportReady(c, shop, b)).length}'
                      ' of ${shop.boards.length} media type(s) complete – '
                      'their separate PDF is available. The combined PDF '
                      'needs every media type completed.'
                : [
                    kRecceIncompleteMessage,
                    ...shopLevelBlockers(reportSource(shop)),
                  ].join(' '),
            key: const Key('recce_report_reason'),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: ready ? AdinnColors.muted : AdinnColors.warning,
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
            const SizedBox(height: 4),
            Text(_progress, style: const TextStyle(fontSize: 12)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('recce_pdf_preview'),
                  onPressed: ready && !_busy
                      ? () => _run(preview: true)
                      : null,
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(context.ui('Preview PDF')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('recce_pdf_download'),
                  onPressed: ready && !_busy
                      ? () => _run(preview: false)
                      : null,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(context.ui('Download PDF')),
                ),
              ),
            ],
          ),
          if (!ready)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${shop.boards.where((b) => c.boardIssues(b).isEmpty).length}'
                ' of ${shop.boards.length} media group(s) complete '
                '· ${fmtNum(shop.boards.fold<int>(0, (s, b) => s + b.activeUnits.length).toDouble())} board(s)',
                style: const TextStyle(fontSize: 11.5, color: AdinnColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}
