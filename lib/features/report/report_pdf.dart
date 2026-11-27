import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../l10n/ta_report.dart';
import 'report_sheet.dart';

/// A compressed picture for the PDF (JPEG or PNG bytes + pixel size).
class ReportImage {
  const ReportImage(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Everything the PDF is built from. Plain data so the build can run in a
/// background isolate.
class ReportInput {
  const ReportInput({
    required this.data,
    this.images = const {},
    this.compress = true,
    this.tamil = false,
    this.taImages = const {},
  });

  /// Tamil report: fixed vocabulary is shaped by Flutter's text engine in
  /// the main isolate ([taImages], see [collectTamilRequests]) and embedded
  /// as small text images. Free text stays exactly as entered.
  final bool tamil;
  final Map<String, ReportImage> taImages;

  /// Report data from [buildReportData] (the immutable snapshot).
  final Map<String, dynamic> data;

  /// Resolved pictures by image key (missing key = placeholder).
  final Map<String, ReportImage> images;
  final bool compress;
}

/// One Tamil text block that needs shaping.
class TaRequest {
  const TaRequest(this.text, this.size, this.bold, this.color, this.maxW);

  final String text;
  final double size;
  final bool bold;
  final int color;
  final double maxW;

  String get key => '$size|$bold|$color|$maxW|$text';
}

/// Pixel scale the text images are rendered at (image px / 2 = PDF pt).
const kTaImageScale = 2.0;

class _TaMode {
  _TaMode(this.images, this.collect, this.tamil);

  final Map<String, ReportImage> images;
  final Map<String, TaRequest>? collect;

  /// Translate the report's own labels (Tamil report).
  final bool tamil;
}

/// Per-report rendering context. It lives in the ZONE of one build, so two
/// overlapping English / Tamil reports can never see each other's state.
_TaMode? get _ta => Zone.current[#reportTaMode] as _TaMode?;

final _mappedPunctuation = RegExp(
  '[–—−•…×‘’‚′“”'
  '„″±°₹→← ]',
);

/// True when [s] has characters the built-in PDF fonts cannot print (Tamil
/// and other scripts): such text is shaped by Flutter's text engine.
bool needsShaping(String s) {
  for (final r in s.runes) {
    if (r > 255 && !_mappedPunctuation.hasMatch(String.fromCharCode(r))) {
      return true;
    }
  }
  return false;
}

/// Any user / data text in [data] that needs shaping (any language mode).
bool reportNeedsShaping(Object? data) {
  if (data is String) return needsShaping(data);
  if (data is Map) return data.values.any(reportNeedsShaping);
  if (data is Iterable) return data.any(reportNeedsShaping);
  return false;
}

List<String> _chunks(String s, int max) {
  final out = <String>[];
  for (final para in s.split('\n')) {
    var cur = '';
    for (final w in para.split(' ')) {
      var word = w;
      while (word.length > max) {
        if (cur.isNotEmpty) {
          out.add(cur);
          cur = '';
        }
        out.add(word.substring(0, max));
        word = word.substring(max);
      }
      if (cur.isEmpty) {
        cur = word;
      } else if (cur.length + 1 + word.length <= max) {
        cur = '$cur $word';
      } else {
        out.add(cur);
        cur = word;
      }
    }
    out.add(cur);
  }
  return out.where((e) => e.isNotEmpty).toList();
}

/// A text widget: plain PDF text in English; in Tamil mode the translated
/// wording as a shaped image. A missing image is an ERROR (never a silent
/// English fallback). Text without a Tamil wording is printed as entered.
pw.Widget _txt(
  String text,
  pw.TextStyle style, {
  double maxW = 330,
  bool upper = false,
  pw.TextOverflow? overflow,
  int? maxLines,
  bool translate = false,
  pw.TextAlign? align,
}) {
  pw.Widget plain() => pw.Text(
    upper ? pdfSafe(text).toUpperCase() : pdfSafe(text),
    style: style,
    textAlign: align,
    overflow: overflow,
    maxLines: maxLines,
  );
  final ta = _ta;
  String? shaped;
  if (ta != null && ta.tamil && translate) shaped = TamilReport.tr(text);
  shaped ??= needsShaping(text) ? text : null;
  if (shaped == null) return plain();
  if (ta == null) {
    throw StateError('Tamil text needs the shaping pass: $shaped');
  }
  final widgets = <pw.Widget>[];
  // About one line of text per chunk (Tamil glyphs are ~0.7 em wide), so a
  // chunk rarely wraps again and long text still splits across pages.
  final perLine = (maxW / ((style.fontSize ?? 10) * 0.7)).floor().clamp(
    12,
    150,
  );
  for (final part in _chunks(shaped, perLine)) {
    final req = TaRequest(
      part,
      style.fontSize ?? 10,
      style.fontWeight == pw.FontWeight.bold,
      (style.color ?? _ink).toInt(),
      maxW,
    );
    final collect = ta.collect;
    if (collect != null) {
      collect[req.key] = req;
      widgets.add(pw.SizedBox(height: req.size * 1.3));
      continue;
    }
    final img = ta.images[req.key];
    if (img == null) {
      throw StateError('Tamil text could not be rendered: $part');
    }
    // Natural size (px / scale = pt); shrunk only when wider than its column.
    final w = img.width / kTaImageScale, h = img.height / kTaImageScale;
    final k = w > maxW ? maxW / w : 1.0;
    widgets.add(
      pw.Image(pw.MemoryImage(img.bytes), width: w * k, height: h * k),
    );
  }
  if (widgets.length == 1) return widgets.single;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: widgets,
  );
}

/// First pass of a Tamil report: every Tamil text block (with its style and
/// width) the report needs. Pure Dart.
/// Text for the measurement sheets (same rules as the main report).
pw.Widget reportTxt(
  String text,
  pw.TextStyle style, {
  double maxW = 330,
  bool translate = false,
  int? maxLines,
  pw.TextAlign? align,
}) => _txt(
  text,
  style,
  maxW: maxW,
  translate: translate,
  maxLines: maxLines,
  align: align,
);

Future<List<TaRequest>> collectTamilRequests(ReportInput input) async {
  final seen = <String, TaRequest>{};
  await runZoned(
    () => _buildReportPdf(
      ReportInput(
        data: input.data,
        images: input.images,
        compress: false,
        tamil: input.tamil,
      ),
    ),
    zoneValues: {#reportTaMode: _TaMode(const {}, seen, input.tamil)},
  );
  return seen.values.toList();
}

class ReportOutput {
  const ReportOutput(this.bytes, this.pageCount);

  final Uint8List bytes;
  final int pageCount;
}

const _red = PdfColor.fromInt(0xFFD71920);
const _redLight = PdfColor.fromInt(0xFFFDECEC);
const _ink = PdfColor.fromInt(0xFF1D1D1F);
const _muted = PdfColor.fromInt(0xFF6B6F76);
const _line = PdfColor.fromInt(0xFFDADADF);
const _green = PdfColor.fromInt(0xFF1E8E3E);
const _greenLight = PdfColor.fromInt(0xFFE6F4EA);
const _grey = PdfColor.fromInt(0xFFF3F3F5);

/// A4 with 32 pt margins.
const kReportPageFormat = PdfPageFormat.a4;
const kReportMargin = 32.0;
double get kReportContentWidth => kReportPageFormat.width - 2 * kReportMargin;

/// Longest table cell text (longer remarks continue as paragraphs).
const kMaxCellChars = 900;

/// Footer page label.
String reportPageLabel(int page, int count) => 'Page $page of $count';

/// Size an image of [w]×[h] pixels is drawn at inside [maxW]×[maxH]
/// points: uniform scale, aspect ratio preserved, never enlarged beyond
/// the box.
(double, double) reportImageBox(int w, int h, double maxW, double maxH) {
  if (w <= 0 || h <= 0) return (maxW, math.min(maxH, maxW * 0.75));
  final k = math.min(maxW / w, maxH / h);
  return (w * k, h * k);
}

/// Built-in PDF fonts only cover WinAnsi (Latin-1): replace typographic
/// characters and drop anything else that cannot be printed.
String pdfSafe(Object? value) {
  final s = '${value ?? ''}'
      .replaceAll(RegExp('[–—−]'), '-')
      .replaceAll('•', '-')
      .replaceAll('…', '...')
      .replaceAll('×', 'x')
      .replaceAll(RegExp('[‘’‚′]'), "'")
      .replaceAll(RegExp('[“”„″]'), '"')
      .replaceAll('±', '+/-')
      .replaceAll('°', ' deg')
      .replaceAll('₹', 'Rs.')
      .replaceAll('→', '->')
      .replaceAll('←', '<-')
      .replaceAll(' ', ' ')
      .replaceAll('\t', '    ');
  final out = StringBuffer();
  for (final r in s.runes) {
    if (r == 10 || (r >= 32 && r <= 126) || (r >= 160 && r <= 255)) {
      out.writeCharCode(r);
    }
  }
  return out.toString();
}

String _cell(Object? v) {
  // Tamil / non-Latin text is kept exactly as entered (it is shaped later);
  // only Latin text goes through the built-in-font filter.
  final raw = '${v ?? ''}';
  final s = needsShaping(raw) ? raw.trim() : pdfSafe(v).trim();
  if (s.isEmpty) return '-';
  return s.length <= kMaxCellChars
      ? s
      : '${s.substring(0, kMaxCellChars)}... (continued below)';
}

List<String> _strings(Object? v) =>
    v is List ? v.map((e) => '$e').toList() : const [];

List<List<String>> _rows(Object? v) => v is List
    ? [
        for (final r in v)
          if (r is List) r.map((e) => e == null ? '' : '$e').toList(),
      ]
    : const [];

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Builds the measurement PDF. Pure: safe to run in an isolate.
Future<ReportOutput> buildReportPdf(ReportInput input) {
  if (!input.tamil && input.taImages.isEmpty) return _buildReportPdf(input);
  return runZoned(
    () => _buildReportPdf(input),
    zoneValues: {#reportTaMode: _TaMode(input.taImages, null, input.tamil)},
  );
}

Future<ReportOutput> _buildReportPdf(ReportInput input) async {
  final d = input.data;
  final header = _map(d['header']);
  final banner = _map(d['banner']);
  final draft = banner['draft'] != false;
  final doc = pw.Document(
    compress: input.compress,
    title: pdfSafe(d['title']),
    author: 'Adinn Signage Recce',
    subject: pdfSafe('${header['shopName']} – v${header['version']}'),
  );
  final theme = pw.ThemeData.withFont(
    base: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    italic: pw.Font.helveticaOblique(),
  );

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: kReportPageFormat,
        margin: const pw.EdgeInsets.all(kReportMargin),
        theme: theme,
      ),
      maxPages: 400,
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.only(bottom: 3),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: _red)),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Row(
                      children: [
                        _txt(
                          '${d['title']}',
                          const pw.TextStyle(fontSize: 8, color: _muted),
                          maxW: 260,
                          translate: true,
                        ),
                        _txt(
                          '  |  ${header['shopName']}',
                          const pw.TextStyle(fontSize: 8, color: _muted),
                          maxW: 260,
                        ),
                      ],
                    ),
                  ),
                  pw.Row(
                    children: [
                      pw.Text(
                        pdfSafe('v${header['version']}  '),
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: draft ? _red : _green,
                        ),
                      ),
                      _txt(
                        draft ? 'DRAFT' : 'APPROVED',
                        pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: draft ? _red : _green,
                        ),
                        maxW: 80,
                        translate: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
      footer: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.only(top: 3),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _line)),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: reportTxt(
                'Generated ${header['generatedAt']} - Adinn Signage Recce '
                '(offline). ${draft ? 'Draft - not approved for fabrication.' : ''}',
                const pw.TextStyle(fontSize: 7, color: _muted),
                maxW: 420,
                translate: true,
              ),
            ),
            if (_ta == null)
              pw.Text(
                reportPageLabel(ctx.pageNumber, ctx.pagesCount),
                style: const pw.TextStyle(fontSize: 8, color: _ink),
              )
            else
              pw.Row(
                children: [
                  _txt(
                    'Page',
                    const pw.TextStyle(fontSize: 8, color: _ink),
                    maxW: 60,
                  ),
                  pw.Text(
                    ' ${ctx.pageNumber} / ${ctx.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8, color: _ink),
                  ),
                ],
              ),
          ],
        ),
      ),
      build: (ctx) => [
        ..._cover(d, header, banner, draft),
        ..._overview(_map(d['overview'])),
        for (final g in (d['groups'] as List? ?? const []))
          ..._group(_map(g), input.images),
        ..._review(_map(d['review'])),
        if (d['imageLimitReached'] == true)
          _note(
            'Picture limit reached: only the first pictures are included to '
            'keep the PDF small. All pictures remain in the app.',
          ),
        pw.SizedBox(height: 10),
        _note(
          'Measurements, checklist answers and electrical / obstruction '
          'details are as recorded on site by recce staff. This report is '
          'not a structural, electrical or municipal compliance '
          'certification. Before / Proposed images are visual proposals, '
          'not as-built photographs.',
        ),
      ],
    ),
  );
  // Sections D / E: one landscape measurement sheet per signage item.
  for (final g in (d['groups'] as List? ?? const [])) {
    final gm = _map(g);
    for (final it in (gm['items'] as List? ?? const [])) {
      final item = _map(it);
      if (_map(item['sheet']).isEmpty) continue;
      doc.addPage(
        reportSheetPage(
          data: d,
          draft: draft,
          group: gm,
          item: item,
          images: input.images,
          theme: theme,
        ),
      );
    }
  }
  final bytes = await doc.save();
  return ReportOutput(bytes, doc.document.pdfPageList.pages.length);
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

pw.Widget _note(String text) => _txt(
  text,
  pw.TextStyle(fontSize: 7.5, color: _muted, fontStyle: pw.FontStyle.italic),
  maxW: 500,
  translate: true,
);

pw.Widget _heading(String text) => pw.Container(
  margin: const pw.EdgeInsets.only(top: 14, bottom: 6),
  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
  color: _ink,
  child: _txt(
    text,
    pw.TextStyle(
      color: PdfColors.white,
      fontSize: 10.5,
      fontWeight: pw.FontWeight.bold,
      letterSpacing: 0.5,
    ),
    maxW: 500,
    upper: true,
    translate: true,
  ),
);

pw.Widget _subheading(String text, {String? trailing}) => pw.Container(
  margin: const pw.EdgeInsets.only(top: 10, bottom: 4),
  padding: const pw.EdgeInsets.only(bottom: 2),
  decoration: const pw.BoxDecoration(
    border: pw.Border(bottom: pw.BorderSide(color: _red, width: 1.2)),
  ),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Expanded(
        child: _txt(
          text,
          pw.TextStyle(
            fontSize: 10.5,
            fontWeight: pw.FontWeight.bold,
            color: _red,
          ),
          maxW: 380,
          translate: true,
        ),
      ),
      if (trailing != null)
        _txt(
          trailing,
          const pw.TextStyle(fontSize: 8, color: _muted),
          maxW: 200,
        ),
    ],
  ),
);

pw.Widget _label(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 6, bottom: 3),
  child: _txt(
    text,
    pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink),
    maxW: 500,
    translate: true,
  ),
);

/// Two-column key / value table.
pw.Widget _kv(List<List<String>> rows, {double keyFlex = 1.1}) => pw.Table(
  border: pw.TableBorder.all(color: _line, width: 0.6),
  columnWidths: {
    0: pw.FlexColumnWidth(keyFlex),
    1: const pw.FlexColumnWidth(2),
  },
  children: [
    for (var i = 0; i < rows.length; i++)
      pw.TableRow(
        decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _grey),
        children: [
          _td(
            rows[i].isEmpty ? '' : rows[i][0],
            bold: true,
            maxW: kReportContentWidth * keyFlex / (keyFlex + 2) - 8,
          ),
          _td(
            rows[i].length > 1 ? rows[i][1] : '',
            maxW: kReportContentWidth * 2 / (keyFlex + 2) - 8,
          ),
        ],
      ),
  ],
);

pw.Widget _td(
  String text, {
  bool bold = false,
  PdfColor? color,
  double? maxW,
}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
  child: _txt(
    _cell(text),
    pw.TextStyle(
      fontSize: 8,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color ?? _ink,
    ),
    maxW: maxW ?? (bold ? 180 : 330),
    // Keys / header cells are the report's own wording; values are data
    // (user text is never translated).
    translate: bold || TamilReport.isFixedStatus(_cell(text)),
  ),
);

/// Usable width (pt) of column [j] of a flex table.
double _colW(List<double>? flex, int n, int j) {
  final f = flex ?? List.filled(n, 1.0);
  final total = f.fold<double>(0, (a, b) => a + b);
  return kReportContentWidth * f[j] / total - 8;
}

/// Table with a red header row.
pw.Widget _table(
  List<String> headers,
  List<List<String>> rows, {
  List<double>? flex,
}) => pw.Table(
  border: pw.TableBorder.all(color: _line, width: 0.6),
  columnWidths: {
    for (var i = 0; i < headers.length; i++)
      i: pw.FlexColumnWidth(flex == null ? 1 : flex[i]),
  },
  children: [
    pw.TableRow(
      repeat: true,
      decoration: const pw.BoxDecoration(color: _red),
      children: [
        for (var j = 0; j < headers.length; j++)
          _td(
            headers[j],
            bold: true,
            color: PdfColors.white,
            maxW: _colW(flex, headers.length, j),
          ),
      ],
    ),
    for (var i = 0; i < rows.length; i++)
      pw.TableRow(
        decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _grey),
        children: [
          for (var j = 0; j < headers.length; j++)
            _td(
              j < rows[i].length ? rows[i][j] : '',
              maxW: _colW(flex, headers.length, j),
            ),
        ],
      ),
  ],
);

/// Long free text that may continue across pages.
List<pw.Widget> _longText(String label, String text) {
  final t = pdfSafe(text).trim();
  if (t.isEmpty) return const [];
  return [
    _label(label),
    if (needsShaping(t))
      _txt(t, const pw.TextStyle(fontSize: 8.5), maxW: 500)
    else
      pw.Text(
        t,
        overflow: pw.TextOverflow.span,
        style: const pw.TextStyle(fontSize: 8.5, lineSpacing: 1.5),
      ),
  ];
}

List<pw.Widget> _cover(
  Map<String, dynamic> d,
  Map<String, dynamic> h,
  Map<String, dynamic> banner,
  bool draft,
) => [
  pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    color: _red,
    child: pw.Row(
      children: [
        pw.Expanded(
          child: _txt(
            '${d['title']}',
            maxW: 440,
            translate: true,
            pw.TextStyle(
              color: PdfColors.white,
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Text(
          pdfSafe('v${h['version']}'),
          style: pw.TextStyle(
            color: PdfColors.white,
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    ),
  ),
  pw.SizedBox(height: 8),
  pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      color: draft ? _redLight : _greenLight,
      border: pw.Border.all(color: draft ? _red : _green, width: 1.5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _txt(
          '${banner['text']}',
          maxW: 480,
          translate: true,
          pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: draft ? _red : _green,
          ),
        ),
        pw.SizedBox(height: 2),
        _txt(
          '${banner['detail']}',
          const pw.TextStyle(fontSize: 8.5, color: _ink),
          maxW: 480,
          translate: true,
        ),
      ],
    ),
  ),
  pw.SizedBox(height: 8),
  _kv([
    [
      'Project',
      '${h['projectName']} (ID: ${h['projectId']}, ${h['projectCode']})',
    ],
    ['Task', '${h['taskTitle']} (ID: ${h['taskId']})'],
    ['Brand', '${h['brand']}'],
    ['Shop', '${h['shopName']} (ID: ${h['shopId']})'],
    ['Shop address', '${h['shopAddress']}'],
    if ('${h['landmark']}'.isNotEmpty) ['Landmark', '${h['landmark']}'],
    if ('${h['gps']}'.isNotEmpty) ['GPS', '${h['gps']}'],
    ['Recce person', '${h['reccePerson']}'],
    ['Visit date', '${h['visitDate']}'],
    ['Report generated', '${h['generatedAt']} by ${h['generatedBy']}'],
    ['Approval status', '${h['statusLabel']}'],
    ['Submission version', 'v${h['version']}'],
    ['Report content from', '${h['source']}'],
  ]),
];

List<pw.Widget> _overview(Map<String, dynamic> o) => [
  _heading('Shop overview'),
  _kv([
    ['Total media groups', '${o['mediaGroups']}'],
    ['Total signage units', '${o['units']}'],
    ['Media summary', _strings(o['mediaSummary']).join('; ')],
    ['Media types', _strings(o['mediaTypes']).join(', ')],
    [
      'Overall recce completion',
      '${o['completionPercent']}% (${o['completeUnits']} of ${o['units']} '
          'units with size and complete checklist)',
    ],
    ['Open recce issues', '${o['openIssues']}'],
    ['Site feasibility summary', '${o['feasibility']}'],
  ]),
  if (_strings(o['issues']).isNotEmpty) ...[
    _label('Open issues'),
    for (final i in _strings(o['issues']))
      pw.Bullet(
        text: pdfSafe(i),
        style: const pw.TextStyle(fontSize: 8),
        bulletSize: 3,
      ),
  ],
  if (_rows(o['feasibilityRows']).isNotEmpty) ...[
    _label('Site feasibility by signage unit (operational indicator only)'),
    _table(
      ['Signage unit', 'Indicator', 'Reason'],
      _rows(o['feasibilityRows']),
      flex: [1.2, 1.2, 3],
    ),
  ],
];

List<pw.Widget> _group(
  Map<String, dynamic> g,
  Map<String, ReportImage> images,
) => [
  _heading('Media group: ${g['name']} - ${g['media']} (qty ${g['quantity']})'),
  _kv([
    ['Media group ID', '${g['groupId']}'],
    ['Media type', '${g['media']}'],
    ['Installation (group)', '${g['installation']}'],
    ['Quantity', '${g['quantity']} - ${g['sizeMode']}'],
  ]),
  if (_rows(g['siteAnswers']).isNotEmpty || '${g['gst'] ?? ''}'.isNotEmpty) ...[
    if (images['${g['summaryKey']}'] != null)
      // Tamil mode: shaped by Flutter's text engine (title included).
      pw.Image(
        pw.MemoryImage(images['${g['summaryKey']}']!.bytes),
        width: kReportContentWidth,
        fit: pw.BoxFit.contain,
      )
    else ...[
      _label('Site Details Summary'),
      _kv([
        if ('${g['gst'] ?? ''}'.isNotEmpty) ['GST No.', '${g['gst']}'],
        ..._rows(g['siteAnswers']),
      ], keyFlex: 1.6),
    ],
  ],
  ..._longText('Group notes', '${g['note'] ?? ''}'),
  for (final it in (g['items'] as List? ?? const [])) ..._item(_map(it)),
  if ((g['pictures'] as List? ?? const []).isNotEmpty) ...[
    _subheading('Photos and drawings - ${g['name']}'),
    for (final p in (g['pictures'] as List)) _picture(_map(p), images),
  ],
];

List<pw.Widget> _item(Map<String, dynamic> it) {
  final ground = _map(it['groundClearance']);
  final checklist = _map(it['checklist']);
  final diagram = it['diagram'] is Map ? _map(it['diagram']) : null;
  return [
    _subheading('${it['label']}', trailing: 'Signage Item ID: ${it['unitId']}'),
    _kv([
      ['Media type', '${it['media']}'],
      ['Unit number', '${it['unitNumber']}'],
      ['Quantity context', '${it['quantityContext']}'],
      ['Width', '${it['width']}'],
      ['Height', '${it['height']}'],
      ['Installation type', '${it['installation']}'],
      if ('${it['specNote'] ?? ''}'.isNotEmpty)
        ['Specification', '${it['specNote']}'],
      if ('${ground['bottom']}'.isNotEmpty)
        ['Ground clearance (bottom height)', '${ground['bottom']}'],
      if ('${ground['top']}'.isNotEmpty)
        ['Top height from ground', '${ground['top']}'],
      if ('${it['placement']}'.isNotEmpty) ['Placement', '${it['placement']}'],
      ['Site feasibility', '${it['feasibility']}'],
    ]),
    if (_rows(it['measurements']).isNotEmpty) ...[
      _label('Installation measurements'),
      _table(
        ['Group', 'Measurement', 'Value'],
        _rows(it['measurements']),
        flex: [1.3, 2, 1],
      ),
    ],
    if (_strings(it['measurementIssues']).isNotEmpty)
      for (final i in _strings(it['measurementIssues']))
        pw.Bullet(
          text: pdfSafe(i),
          style: const pw.TextStyle(fontSize: 8, color: _red),
          bulletSize: 3,
        ),
    if (diagram != null) ...[
      _label('Ground clearance / pole position diagram (not to exact scale)'),
      measurementDiagram(diagram),
    ],
    if (_rows(it['electrical']).isNotEmpty ||
        _strings(it['electricalMarks']).isNotEmpty) ...[
      _label('Electrical information (as recorded - not a safety certificate)'),
      if (_rows(it['electrical']).isNotEmpty) _kv(_rows(it['electrical'])),
      if (_strings(it['electricalMarks']).isNotEmpty)
        _txt(
          'Marked on photos: ${_strings(it['electricalMarks']).join(', ')}',
          const pw.TextStyle(fontSize: 8),
          maxW: 500,
        ),
    ],
    if (_rows(it['obstructions']).isNotEmpty) ...[
      _label('Obstructions'),
      _table(
        ['Code', 'Type', 'Severity', 'Photo', 'Remarks'],
        _rows(it['obstructions']),
        flex: [0.6, 1.2, 0.7, 1.1, 2.4],
      ),
    ],
    if (_rows(it['markers']).isNotEmpty) ...[
      _label('Board placement markers'),
      _table(
        ['Photo', 'Marker', 'Placement', 'Notes'],
        _rows(it['markers']),
        flex: [1.4, 0.6, 1, 2.4],
      ),
    ],
    if (_strings(it['perspectives']).isNotEmpty)
      _txt(
        'Perspective placement drawn on: '
        '${_strings(it['perspectives']).join(', ')}',
        const pw.TextStyle(fontSize: 8),
        maxW: 500,
      ),
    _label(
      'Site checklist - ${checklist['title']} '
      '(${checklist['answered']}/${checklist['total']} answered'
      '${checklist['complete'] == true ? ', complete' : ', ${checklist['missing']} required missing'})',
    ),
    if (_rows(checklist['rows']).isNotEmpty)
      _table(
        ['Question', 'Response', 'Remarks'],
        _rows(checklist['rows']),
        flex: [2.6, 1.2, 1.6],
      ),
    ..._longText('Installation details', '${it['installationDetails'] ?? ''}'),
    ..._longText('Notes', '${it['notes'] ?? ''}'),
    ..._longRemarksFromRows(_rows(checklist['rows'])),
  ];
}

/// Remarks too long for a table cell continue here in full.
List<pw.Widget> _longRemarksFromRows(List<List<String>> rows) => [
  for (final r in rows)
    if (r.length > 2 && pdfSafe(r[2]).trim().length > kMaxCellChars)
      ..._longText('Remarks (full) - ${r[0]}', r[2]),
];

pw.Widget _picture(Map<String, dynamic> p, Map<String, ReportImage> images) {
  final img = images['${p['key']}'];
  final maxW = kReportContentWidth;
  const maxH = 300.0;
  final pw.Widget body;
  if (img == null) {
    body = pw.Container(
      width: maxW,
      height: 60,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: _grey,
        border: pw.Border.all(color: _line),
      ),
      child: reportTxt(
        'Image not available on this device',
        const pw.TextStyle(fontSize: 9, color: _muted),
        translate: true,
      ),
    );
  } else {
    final (w, h) = reportImageBox(img.width, img.height, maxW, maxH);
    body = pw.Image(
      pw.MemoryImage(img.bytes),
      width: w,
      height: h,
      fit: pw.BoxFit.contain,
    );
  }
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 6, bottom: 4),
    child: pw.Column(
      children: [
        pw.Center(child: body),
        pw.SizedBox(height: 3),
        _txt(
          '${p['caption']}',
          maxW: 480,
          translate: true,
          pw.TextStyle(
            fontSize: 7.5,
            color: _muted,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
      ],
    ),
  );
}

List<pw.Widget> _review(Map<String, dynamic> r) => [
  _heading('Review information'),
  _kv([
    ['Current submission version', 'v${r['version']}'],
    if ('${r['submittedBy']}'.isNotEmpty)
      ['Submitted', '${r['submittedBy']} on ${r['submittedAt']}'],
    ['Business review', '${r['business']}'],
    ['Operations review', '${r['ops']}'],
    if ('${r['vendorRemarks']}'.isNotEmpty)
      ['Vendor remarks', '${r['vendorRemarks']}'],
  ]),
  for (final rej in (r['rejections'] as List? ?? const [])) ...[
    _label(
      'Rejected v${_map(rej)['version']} by ${_map(rej)['stage']} '
      '(${_map(rej)['by']}, ${_map(rej)['at']})',
    ),
    ..._longText('Remarks', '${_map(rej)['remarks']}'),
    if (_strings(_map(rej)['reasons']).isNotEmpty)
      _txt(
        'Reasons: ${_strings(_map(rej)['reasons']).join(', ')}',
        const pw.TextStyle(fontSize: 8),
        maxW: 500,
      ),
    for (final i in _strings(_map(rej)['issues']))
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('- ', style: const pw.TextStyle(fontSize: 8)),
          pw.Expanded(
            child: _txt(i, const pw.TextStyle(fontSize: 8), maxW: 480),
          ),
        ],
      ),
  ],
  if (_rows(r['comments']).isNotEmpty) ...[
    _label('Outstanding review comments'),
    _table(
      ['Marker', 'Version', 'Type', 'Comment', 'Status', 'Reviewer'],
      _rows(r['comments']),
      flex: [0.6, 0.6, 1.2, 2.6, 0.8, 1],
    ),
  ] else
    pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4),
      child: reportTxt(
        'No outstanding review comments.',
        const pw.TextStyle(fontSize: 8, color: _muted),
        translate: true,
      ),
    ),
];

// ---------------------------------------------------------------------------
// Measurement diagram (vector, from the recorded values)
// ---------------------------------------------------------------------------

double? _n(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

String _fmt(double mm, String unitName) {
  final factor = switch (unitName) {
    'inch' => 25.4,
    'm' => 1000.0,
    'mm' => 1.0,
    _ => 304.8,
  };
  final decimals = switch (unitName) {
    'inch' => 1,
    'm' => 3,
    'mm' => 0,
    _ => 2,
  };
  var s = (mm / factor).toStringAsFixed(decimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  final label = unitName == 'inch' ? 'in' : unitName;
  return '$s $label';
}

/// Elevation diagram: ground line, board outline with W / H, bottom and
/// top mounting heights, poles with spacing, wall and clearances.
pw.Widget measurementDiagram(Map<String, dynamic> d) {
  const width = 500.0, height = 200.0;
  final unit = '${d['unitName'] ?? 'ft'}';
  final inst = '${d['installation'] ?? ''}';
  final wMm = _n(d['widthMm']) ?? _n(d['panel_width']);
  final hMm = _n(d['heightMm']) ?? _n(d['panel_height']);
  final bw = wMm ?? 2000.0;
  final bh = hMm ?? bw / 3;
  final poleTop = _n(d['pole_above_ground']);
  final bottomRec = _n(d['bottom_height']);
  final bottom =
      bottomRec ?? (poleTop != null ? math.max(0.0, poleTop - bh) : 0.0);
  final topRec = _n(d['top_height']);
  final wallW = _n(d['wall_width']);
  final wallH = _n(d['wall_height']);
  final spacing = _n(d['pole_spacing']);
  final overall = _n(d['standee_overall_height']);
  final baseW = _n(d['base_width']);
  final embed = _n(d['pole_embedment']);
  final isDouble = inst == 'double_pole';
  final isPole = isDouble || inst == 'single_pole';

  final sceneW =
      [bw, wallW ?? 0, spacing ?? 0, baseW ?? 0].reduce(math.max) * 1.5;
  final sceneH =
      [
        bottom + bh,
        topRec ?? 0,
        wallH ?? 0,
        overall ?? 0,
        poleTop ?? 0,
      ].reduce(math.max) *
      1.18;
  final k = math.min(
    (width - 120) / sceneW,
    (height - 40) / math.max(sceneH, 1),
  );
  const groundY = 26.0; // PDF y (up)
  const cx = width / 2;
  final boardL = cx - bw * k / 2, boardR = cx + bw * k / 2;
  final boardB = groundY + bottom * k, boardT = boardB + bh * k;

  final labels = <pw.Widget>[];
  void label(double x, double yUp, String text, {bool centre = true}) {
    final top = height - yUp - 5;
    labels.add(
      pw.Positioned(
        left: centre ? math.max(0, x - 60) : x,
        top: math.max(0, math.min(height - 10, top)),
        child: pw.SizedBox(
          width: 120,
          child: reportTxt(
            text,
            const pw.TextStyle(fontSize: 7, color: _ink),
            maxW: 120,
            translate: true,
            align: centre ? pw.TextAlign.center : pw.TextAlign.left,
          ),
        ),
      ),
    );
  }

  if (wMm != null) label(cx, boardT + 10, 'W ${_fmt(wMm, unit)}');
  if (hMm != null) {
    label(boardR + 64, (boardB + boardT) / 2, 'H ${_fmt(hMm, unit)}');
  }
  if (bottomRec != null) {
    label(
      boardL - 64,
      (groundY + boardB) / 2,
      'Bottom ${_fmt(bottomRec, unit)}',
    );
  }
  if (topRec != null) {
    label(boardR + 64, boardT + 6, 'Top ${_fmt(topRec, unit)}');
  }
  if (isPole && spacing != null && isDouble) {
    label(cx, groundY - 14, 'Pole spacing ${_fmt(spacing, unit)}');
  }
  if (embed != null && isPole) {
    label(cx + 70, groundY - 22, 'Embedment ${_fmt(embed, unit)}');
  }
  if (wallW != null) {
    label(
      cx,
      groundY + (wallH ?? (bottom + bh) * 1.1) * k + 6,
      'Available wall ${_fmt(wallW, unit)}${wallH == null ? '' : ' x ${_fmt(wallH, unit)}'}',
    );
  }
  final clear = [
    for (final (id, name) in const [
      ('clear_left', 'L'),
      ('clear_right', 'R'),
      ('clear_top', 'T'),
      ('clear_bottom', 'B'),
    ])
      if (_n(d[id]) != null) '$name ${_fmt(_n(d[id])!, unit)}',
  ];
  if (clear.isNotEmpty) {
    label(4, height - 12, 'Clearances: ${clear.join(', ')}', centre: false);
  }
  if (overall != null) {
    label(
      boardL - 64,
      groundY + overall * k - 4,
      'Overall ${_fmt(overall, unit)}',
    );
  }
  label(width - 70, groundY - 12, 'Ground level');

  return pw.Container(
    width: width,
    height: height,
    decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
    child: pw.Stack(
      children: [
        pw.CustomPaint(
          size: const PdfPoint(width, height),
          painter: (canvas, size) {
            // Ground.
            canvas
              ..setStrokeColor(_ink)
              ..setLineWidth(1.2)
              ..drawLine(10, groundY, width - 10, groundY)
              ..strokePath();
            canvas.setLineWidth(0.5);
            for (var x = 14.0; x < width - 10; x += 10) {
              canvas.drawLine(x, groundY, x - 6, groundY - 6);
            }
            canvas.strokePath();
            // Wall.
            if (wallW != null) {
              final wh = (wallH ?? (bottom + bh) * 1.1) * k;
              canvas
                ..setStrokeColor(_muted)
                ..setLineDashPattern([3, 2])
                ..setLineWidth(0.7)
                ..drawRect(cx - wallW * k / 2, groundY, wallW * k, wh)
                ..strokePath()
                ..setLineDashPattern();
            }
            // Poles.
            if (isPole) {
              final xs = isDouble
                  ? [
                      cx - (spacing ?? bw * 0.7) * k / 2,
                      cx + (spacing ?? bw * 0.7) * k / 2,
                    ]
                  : [cx];
              final topY = math.max(boardB, groundY + (poleTop ?? bottom) * k);
              for (final x in xs) {
                canvas
                  ..setStrokeColor(_ink)
                  ..setLineWidth(2.2)
                  ..drawLine(x, groundY, x, topY)
                  ..strokePath();
                if (embed != null) {
                  canvas
                    ..setLineDashPattern([2, 2])
                    ..setLineWidth(1.4)
                    ..drawLine(x, groundY, x, math.max(4, groundY - embed * k))
                    ..strokePath()
                    ..setLineDashPattern();
                }
              }
              if (isDouble && spacing != null) {
                canvas
                  ..setStrokeColor(_red)
                  ..setLineWidth(0.6)
                  ..drawLine(xs[0], groundY - 4, xs[1], groundY - 4)
                  ..strokePath();
              }
            }
            // Standee base / overall height.
            if (baseW != null) {
              canvas
                ..setFillColor(_muted)
                ..drawRect(cx - baseW * k / 2, groundY, baseW * k, 3)
                ..fillPath();
            }
            // Board.
            canvas
              ..setFillColor(_redLight)
              ..drawRect(boardL, boardB, boardR - boardL, boardT - boardB)
              ..fillPath()
              ..setStrokeColor(_red)
              ..setLineWidth(1.4)
              ..drawRect(boardL, boardB, boardR - boardL, boardT - boardB)
              ..strokePath();
            // Dimension lines.
            canvas
              ..setStrokeColor(_red)
              ..setLineWidth(0.6);
            if (wMm != null) {
              canvas
                ..drawLine(boardL, boardT + 5, boardR, boardT + 5)
                ..drawLine(boardL, boardT + 2, boardL, boardT + 8)
                ..drawLine(boardR, boardT + 2, boardR, boardT + 8);
            }
            if (hMm != null) {
              canvas
                ..drawLine(boardR + 5, boardB, boardR + 5, boardT)
                ..drawLine(boardR + 2, boardB, boardR + 8, boardB)
                ..drawLine(boardR + 2, boardT, boardR + 8, boardT);
            }
            canvas.strokePath();
            if (bottomRec != null && bottomRec > 0) {
              final x = boardL - 8;
              canvas
                ..setStrokeColor(_ink)
                ..drawLine(x, groundY, x, boardB)
                ..drawLine(x - 3, boardB, x + 3, boardB)
                ..strokePath();
            }
            if (topRec != null) {
              final x = boardR + 16;
              final y = groundY + topRec * k;
              canvas
                ..setStrokeColor(_muted)
                ..setLineDashPattern([2, 2])
                ..drawLine(x, groundY, x, y)
                ..drawLine(x - 3, y, x + 3, y)
                ..strokePath()
                ..setLineDashPattern();
            }
            if (overall != null) {
              final y = groundY + overall * k;
              canvas
                ..setStrokeColor(_muted)
                ..setLineDashPattern([2, 2])
                ..drawLine(boardL - 4, y, boardR + 4, y)
                ..strokePath()
                ..setLineDashPattern();
            }
          },
        ),
        ...labels,
      ],
    ),
  );
}
