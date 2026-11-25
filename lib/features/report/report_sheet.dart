import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report_pdf.dart';

const _red = PdfColor.fromInt(0xFFD71920);
const _redLight = PdfColor.fromInt(0xFFFDECEC);
const _ink = PdfColor.fromInt(0xFF1D1D1F);
const _muted = PdfColor.fromInt(0xFF6B6F76);
const _line = PdfColor.fromInt(0xFFDADADF);
const _green = PdfColor.fromInt(0xFF1E8E3E);
const _greenLight = PdfColor.fromInt(0xFFE6F4EA);

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<List<String>> _rows(Object? v) => v is List
    ? [
        for (final r in v)
          if (r is List) [for (final c in r) '${c ?? ''}'],
      ]
    : <List<String>>[];

pw.Widget _td(String text, {bool bold = false}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
  child: pw.Text(
    pdfSafe(text),
    style: pw.TextStyle(
      fontSize: 7,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: _ink,
    ),
  ),
);

/// Landscape measurement sheet of one signage item (layout follows the
/// classic signage elevation sheet: drawings on the left, 3D model on the
/// right, dimensions below, title block in a vertical strip).
pw.Page reportSheetPage({
  required Map<String, dynamic> data,
  required bool draft,
  required Map<String, dynamic> group,
  required Map<String, dynamic> item,
  required Map<String, ReportImage> images,
  required pw.ThemeData theme,
}) {
  final header = _map(data['header']);
  final model = _map(item['model']);
  final sheet = _map(item['sheet']);
  final rows = _rows(model['rows']);
  final bannerText =
      '${_map(data['banner'])['text'] ?? (draft ? 'DRAFT' : 'APPROVED')}';
  return pw.Page(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(18),
      theme: theme,
    ),
    build: (ctx) => pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    pdfSafe('MEASUREMENT SHEET - ${item['label']}'),
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: _red,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: _sheetImage(
                          images,
                          sheet['front'],
                          '2D front elevation',
                          '2D drawing could not be generated',
                          height: 200,
                        ),
                      ),
                      pw.SizedBox(width: 6),
                      pw.Expanded(
                        child: _sheetImage(
                          images,
                          sheet['model'],
                          '3D model - ${model['status'] ?? 'Illustrative Model'}',
                          '3D model image could not be generated on this '
                              'device (not replaced by a generic model)',
                          height: 200,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: _sheetImage(
                          images,
                          sheet['side'],
                          '2D side elevation',
                          '2D drawing could not be generated',
                          height: 150,
                        ),
                      ),
                      if (sheet['model_rear'] != null) ...[
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: _sheetImage(
                            images,
                            sheet['model_rear'],
                            '3D opposite-side view',
                            '3D model image could not be generated on this '
                                'device (not replaced by a generic model)',
                            height: 150,
                          ),
                        ),
                      ],
                      pw.SizedBox(width: 6),
                      pw.Expanded(
                        child: pw.Table(
                          border: pw.TableBorder.all(color: _line, width: 0.5),
                          columnWidths: const {
                            0: pw.FlexColumnWidth(1.5),
                            1: pw.FlexColumnWidth(1),
                            2: pw.FlexColumnWidth(1.2),
                          },
                          children: [
                            pw.TableRow(
                              decoration: const pw.BoxDecoration(
                                color: _redLight,
                              ),
                              children: [
                                _td('Dimension', bold: true),
                                _td('Value', bold: true),
                                _td('Source', bold: true),
                              ],
                            ),
                            for (final r in rows.take(14))
                              pw.TableRow(
                                children: [for (final c in r) _td(c)],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          pw.Container(
            width: 150,
            padding: const pw.EdgeInsets.all(8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(color: _ink)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ADINN SIGNAGE',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: _red,
                  ),
                ),
                pw.Divider(color: _red),
                for (final (k, v) in [
                  ('Shop', header['shopName']),
                  ('Address', header['shopAddress']),
                  ('Project', header['projectName'] ?? header['projectId']),
                  ('Task', header['taskTitle'] ?? header['taskId']),
                  ('Signage Item ID', item['unitId']),
                  ('Media', group['media']),
                  ('Sidedness', model['sidedness']),
                  ('Installation', item['installation']),
                  ('Quantity', item['quantityContext']),
                  ('Version', 'v${header['version']}'),
                ])
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          pdfSafe(k),
                          style: const pw.TextStyle(
                            fontSize: 6.5,
                            color: _muted,
                          ),
                        ),
                        pw.Text(
                          pdfSafe(v ?? '-'),
                          maxLines: 3,
                          style: const pw.TextStyle(fontSize: 8, color: _ink),
                        ),
                      ],
                    ),
                  ),
                pw.Spacer(),
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  color: draft ? _redLight : _greenLight,
                  child: pw.Text(
                    pdfSafe(bannerText),
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: draft ? _red : _green,
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Illustrative parametric model and schematic drawings from '
                  'recorded measurements - not fabrication-certified.',
                  style: const pw.TextStyle(fontSize: 6, color: _muted),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  pdfSafe('Generated ${header['generatedAt']}'),
                  style: const pw.TextStyle(fontSize: 6.5, color: _muted),
                ),
                pw.Text(
                  reportPageLabel(ctx.pageNumber, ctx.pagesCount),
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _sheetImage(
  Map<String, ReportImage> images,
  Object? key,
  String caption,
  String missing, {
  required double height,
}) {
  final img = key == null ? null : images['$key'];
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Container(
        height: height,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
        child: img == null
            ? pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(
                  pdfSafe(missing),
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8, color: _muted),
                ),
              )
            : pw.Image(pw.MemoryImage(img.bytes), fit: pw.BoxFit.contain),
      ),
      pw.Text(
        pdfSafe(caption),
        style: pw.TextStyle(
          fontSize: 7,
          color: _muted,
          fontStyle: pw.FontStyle.italic,
        ),
      ),
    ],
  );
}
