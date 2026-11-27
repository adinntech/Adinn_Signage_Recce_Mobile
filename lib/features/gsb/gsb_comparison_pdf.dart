import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../preview_live/live_preview_render.dart'
    show kNightDisclaimer, kNightDoubleNote;
import '../report/report_pdf.dart' show pdfSafe;

/// A PNG / JPEG plus its pixel size (aspect ratio is always preserved).
class PdfPicture {
  const PdfPicture(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;

  static Future<PdfPicture> of(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final img = (await codec.getNextFrame()).image;
      final p = PdfPicture(bytes, img.width, img.height);
      img.dispose();
      return p;
    } finally {
      codec.dispose();
    }
  }
}

/// Plain data for the GSB Day / Night comparison report.
class GsbComparisonData {
  const GsbComparisonData({
    required this.source,
    required this.projectName,
    required this.shopName,
    required this.boardName,
    required this.unitLabel,
    required this.variantLabel,
    required this.sizeText,
    required this.capturedAt,
    required this.original,
    required this.day,
    required this.night,
    this.dayLabelled,
    this.taskTitle,
    this.siteId,
    this.mountingText,
    this.depthText,
    this.reviewNotes = const [],
    this.ruleVersion = '',
  });

  /// "Live Preview" or "Camera AR".
  final String source;
  final String projectName;
  final String shopName;
  final String boardName;
  final String unitLabel;
  final String variantLabel;
  final String sizeText;
  final DateTime capturedAt;

  /// Untouched original site photo / camera frame (no board).
  final PdfPicture original;
  final PdfPicture day;
  final PdfPicture night;

  /// Day render with width / height / mounting labels (page 2), optional.
  final PdfPicture? dayLabelled;
  final String? taskTitle;
  final String? siteId;
  final String? mountingText;
  final String? depthText;
  final List<String> reviewNotes;
  final String ruleVersion;
}

const _red = PdfColor.fromInt(0xFFD71920);
const _ink = PdfColor.fromInt(0xFF1D1D1F);
const _muted = PdfColor.fromInt(0xFF6B6F76);
const _line = PdfColor.fromInt(0xFFDADADF);
const _navy = PdfColor.fromInt(0xFF1B2846);
const _warnBg = PdfColor.fromInt(0xFFFFF4E5);
const _warn = PdfColor.fromInt(0xFFB35A00);

String _two(int v) => v.toString().padLeft(2, '0');

String _stamp(DateTime d) {
  final l = d.toLocal();
  return '${l.year}-${_two(l.month)}-${_two(l.day)} '
      '${_two(l.hour)}:${_two(l.minute)}';
}

/// Builds the 4-page report: original site, proposed day, proposed night,
/// side-by-side comparison. A4 landscape, built-in fonts (WinAnsi text).
Future<Uint8List> buildGsbComparisonPdf(GsbComparisonData d) async {
  final doc = pw.Document(
    title: pdfSafe('GSB ${d.source} comparison - ${d.shopName}'),
    author: 'Adinn Signage Recce',
  );
  final theme = pw.ThemeData.withFont(
    base: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    italic: pw.Font.helveticaOblique(),
  );
  const format = PdfPageFormat.a4;
  final page = format.landscape;

  pw.Widget header(String title, {PdfColor color = _red}) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: color, width: 2)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Text(
            pdfSafe(title),
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
        ),
        pw.Text(
          pdfSafe('ADINN - GSB ${d.source} Comparison'),
          style: const pw.TextStyle(fontSize: 9, color: _muted),
        ),
      ],
    ),
  );

  pw.Widget footer(pw.Context ctx) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 6),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            pdfSafe(
              'Illustrative visualisation from the saved board placement. '
              'Original photo preserved unchanged. '
              '${d.ruleVersion.isEmpty ? '' : 'Rule set ${d.ruleVersion}.'}',
            ),
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          ),
        ),
        pw.Text(
          'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 7, color: _muted),
        ),
      ],
    ),
  );

  pw.Widget picture(PdfPicture p) => pw.Container(
    decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
    alignment: pw.Alignment.center,
    child: pw.Image(pw.MemoryImage(p.bytes), fit: pw.BoxFit.contain),
  );

  pw.Widget row(String k, String? v) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 86,
          child: pw.Text(
            pdfSafe(k),
            style: const pw.TextStyle(fontSize: 8.5, color: _muted),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            pdfSafe(v == null || v.trim().isEmpty ? '-' : v),
            maxLines: 4,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
        ),
      ],
    ),
  );

  pw.Widget details(List<pw.Widget> extra) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      row('Project', d.projectName),
      if (d.taskTitle != null) row('Recce task', d.taskTitle),
      row('Shop / store', d.shopName),
      if (d.siteId != null) row('Site ID', d.siteId),
      row('Media item', '${d.boardName} - ${d.unitLabel}'),
      row('Board type', d.variantLabel),
      row('Board size', d.sizeText),
      if (d.mountingText != null) row('Mounting height', d.mountingText),
      if (d.depthText != null) row('Board depth', d.depthText),
      row('Captured', _stamp(d.capturedAt)),
      row('Source', d.source),
      pw.SizedBox(height: 8),
      ...extra,
    ],
  );

  pw.Widget tag(String text, PdfColor bg, PdfColor fg) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: pw.BoxDecoration(
      color: bg,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Text(
      pdfSafe(text),
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: fg,
      ),
    ),
  );

  pw.Widget note(String text) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 6),
    padding: const pw.EdgeInsets.all(6),
    color: _warnBg,
    child: pw.Text(
      pdfSafe(text),
      style: const pw.TextStyle(fontSize: 7.5, color: _warn),
    ),
  );

  pw.Page imagePage(String title, PdfPicture img, List<pw.Widget> extra) =>
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: page,
          margin: const pw.EdgeInsets.all(28),
          theme: theme,
        ),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            header(title),
            pw.SizedBox(height: 10),
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(flex: 3, child: picture(img)),
                  pw.SizedBox(width: 14),
                  pw.Expanded(flex: 2, child: details(extra)),
                ],
              ),
            ),
            footer(ctx),
          ],
        ),
      );

  final reviews = [
    for (final n in d.reviewNotes.take(4)) note('Requires review: $n'),
  ];

  doc.addPage(
    imagePage('1. Original Site', d.original, [
      tag(
        'ORIGINAL - NO PROPOSED BOARD',
        const PdfColor.fromInt(0xFFEFEFF2),
        _ink,
      ),
      pw.SizedBox(height: 6),
      pw.Text('Unedited site capture kept as recce evidence.',
        style: const pw.TextStyle(fontSize: 8.5, color: _muted),
      ),
    ]),
  );
  doc.addPage(
    imagePage('2. Proposed GSB - Day View', d.dayLabelled ?? d.day, [
      tag('DAY VIEW', const PdfColor.fromInt(0xFFFDECEC), _red),
      pw.SizedBox(height: 6),
      pw.Text(
        pdfSafe(
          'Board at the approved preview position with the selected '
          'artwork. Width, height and mounting height as listed.',
        ),
        style: const pw.TextStyle(fontSize: 8.5, color: _muted),
      ),
      ...reviews,
    ]),
  );
  doc.addPage(
    imagePage('3. Proposed GSB - Night View', d.night, [
      tag('NIGHT VIEW - ILLUSTRATIVE', _navy, PdfColors.white),
      pw.SizedBox(height: 6),
      pw.Text(
        pdfSafe(
          'Same board location and transformation with a soft-blue evening '
          'scene and simulated board illumination. Physical LED count '
          'unchanged.',
        ),
        style: const pw.TextStyle(fontSize: 8.5, color: _muted),
      ),
      note(kNightDisclaimer),
      if (d.variantLabel.contains('Double')) note(kNightDoubleNote),
    ]),
  );
  doc.addPage(
    pw.Page(
      pageTheme: pw.PageTheme(
        pageFormat: page,
        margin: const pw.EdgeInsets.all(28),
        theme: theme,
      ),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          header('4. Day vs Night Comparison'),
          pw.SizedBox(height: 10),
          pw.Expanded(
            child: pw.Row(
              children: [
                for (final (label, img, bg, fg) in [
                  ('DAY VIEW', d.day, const PdfColor.fromInt(0xFFFDECEC), _red),
                  (
                    'NIGHT VIEW (ILLUSTRATIVE)',
                    d.night,
                    _navy,
                    PdfColors.white,
                  ),
                ]) ...[
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        tag(label, bg, fg),
                        pw.SizedBox(height: 6),
                        pw.Expanded(child: picture(img)),
                      ],
                    ),
                  ),
                  if (img == d.day) pw.SizedBox(width: 12),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            pdfSafe(
              '${d.variantLabel} ${d.sizeText} at ${d.shopName}: both views '
              'use the same crop, field of view and saved board placement. '
              'Day shows the site as photographed; night shows an evening '
              'grade with the board lit. $kNightDisclaimer',
            ),
            style: const pw.TextStyle(fontSize: 8.5, color: _ink),
          ),
          footer(ctx),
        ],
      ),
    ),
  );
  return doc.save();
}
