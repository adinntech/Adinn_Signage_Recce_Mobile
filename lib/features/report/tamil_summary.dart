import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../l10n/ta_catalog.dart';
import 'report_pdf.dart';

/// Tamil Site Details Summary for the PDF.
///
/// The `pdf` package cannot shape Tamil (vowel signs / conjuncts come out
/// wrong), so in Tamil mode the summary block is laid out by Flutter's own
/// text engine (HarfBuzz shaping, Noto Sans Tamil) and embedded as an image.
/// Only display wording is translated; answers and custom text stay as typed.
class TamilSummary {
  TamilSummary._();

  static const family = 'NotoSansTamil';
  static const _ink = Color(0xFF1B1B1B);
  static const _line = Color(0xFFDDDDDD);
  static const _red = Color(0xFFD71920);

  static const _yes = 'ஆம்';
  static const _no = 'இல்லை';

  /// Display Tamil for one stored English value (labels, options, answers).
  static String word(String en) {
    switch (en) {
      case 'Yes':
        return _yes;
      case 'No':
        return _no;
    }
    return TaCatalog.questions[en] ??
        TaCatalog.options[en] ??
        TaCatalog.media[en] ??
        TaCatalog.installations[en] ??
        en;
  }

  /// "10 ft" -> keeps the number and unit, translating plain words only.
  static String value(String en) => word(en);

  /// One Tamil text block (transparent background, tight width) for the
  /// report: shaped by the text engine, drawn at [kTaImageScale].
  static Future<ReportImage> renderText(TaRequest r) async {
    final p = TextPainter(
      text: TextSpan(
        text: r.text,
        style: TextStyle(
          fontFamily: family,
          fontFamilyFallback: const ['Roboto', 'sans-serif'],
          fontSize: r.size,
          fontWeight: r.bold ? FontWeight.w700 : FontWeight.w400,
          color: Color(r.color),
          height: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: r.maxW);
    final w = (p.width + 1).ceilToDouble(), h = p.height.ceilToDouble();
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec)..scale(kTaImageScale);
    p.paint(canvas, Offset.zero);
    final img = await rec.endRecording().toImage(
      (w * kTaImageScale).ceil(),
      (h * kTaImageScale).ceil(),
    );
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final iw = img.width, ih = img.height;
    img.dispose();
    return ReportImage(Uint8List.view(bytes!.buffer), iw, ih);
  }

  /// Renders [title] and [rows] (label, answer) as one PNG panel of [width]
  /// logical pixels (device scale 2 for crisp print).
  static Future<ReportImage> render({
    required String title,
    required List<List<String>> rows,
    double width = 515,
    double scale = 2,
  }) async {
    TextPainter tp(String t, double w, {bool bold = false, double size = 8.5, Color c = _ink}) {
      return TextPainter(
        text: TextSpan(
          text: t,
          style: TextStyle(
            fontFamily: family,
            // Noto Sans Tamil has no Latin glyphs: numbers, GST and units
            // come from the platform font.
            fontFamilyFallback: const ['Roboto', 'sans-serif'],
            fontSize: size,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            color: c,
            height: 1.35,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w);
    }

    const pad = 6.0;
    final labelW = width * 0.56;
    final valueW = width - labelW - pad * 3;
    final head = tp(title, width - pad * 2, bold: true, size: 10.5, c: _red);
    final cells = <(TextPainter, TextPainter, double)>[];
    var height = pad + head.height + pad;
    for (final r in rows) {
      final l = tp(word(r[0]), labelW - pad);
      // Only predefined answers are translated; typed text stays as entered.
      final v = tp(r.length > 2 && r[2] == 'p' ? word(r[1]) : r[1], valueW);
      final h = (l.height > v.height ? l.height : v.height) + pad * 1.2;
      cells.add((l, v, h));
      height += h;
    }
    height += pad;

    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec)..scale(scale);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    head.paint(canvas, const Offset(pad, pad));
    var y = pad + head.height + pad;
    final line = Paint()
      ..color = _line
      ..strokeWidth = 0.8;
    for (final (l, v, h) in cells) {
      canvas.drawLine(Offset(0, y), Offset(width, y), line);
      l.paint(canvas, Offset(pad, y + pad * 0.6));
      v.paint(canvas, Offset(labelW + pad * 2, y + pad * 0.6));
      y += h;
    }
    canvas.drawLine(Offset(0, y), Offset(width, y), line);
    final img = await rec.endRecording().toImage(
      (width * scale).ceil(),
      (height * scale).ceil(),
    );
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final w = img.width, h = img.height;
    img.dispose();
    return ReportImage(Uint8List.view(bytes!.buffer), w, h);
  }
}
