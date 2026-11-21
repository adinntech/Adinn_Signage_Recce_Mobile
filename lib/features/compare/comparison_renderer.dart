import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../survey/photo_render.dart';
import '../survey/site_markup_painter.dart';

/// Everything needed to export one Before / Proposed comparison image.
class ComparisonRenderRequest {
  const ComparisonRenderRequest({
    required this.photo,
    required this.source,
    required this.labels,
    required this.shopName,
    required this.itemLabel,
    required this.mediaName,
    required this.versionLabel,
    required this.date,
    this.capture,
  });

  /// "Before" site photo (only read, never modified).
  final SitePhoto photo;
  final ProposedSource source;

  /// Proposed Live Preview (null for a perspective composite).
  final PreviewCapture? capture;
  final MarkupLabels labels;
  final String shopName;
  final String itemLabel;
  final String mediaName;
  final String versionLabel;
  final DateTime date;

  /// Header / footer text lines printed on the export.
  List<String> get headerLines => [
    'BEFORE / PROPOSED – $shopName',
    '$itemLabel • $mediaName',
  ];

  String get footer =>
      '$versionLabel • Compared ${_date(date)} • Visual proposal – not an '
      'as-built photo';

  static String _date(DateTime d) {
    final l = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}-${two(l.month)}-${l.year} '
        '${two(l.hour)}:${two(l.minute)}';
  }
}

/// Renders a comparison PNG. Injectable so widget tests need no image
/// decoding.
abstract class ComparisonRenderer {
  const ComparisonRenderer();

  Future<Uint8List?> render(ComparisonRenderRequest request);
}

/// Default renderer: both images side by side, each contain-fitted (never
/// stretched) in a box with the before photo's aspect ratio, with a small
/// header and footer.
class DefaultComparisonRenderer extends ComparisonRenderer {
  const DefaultComparisonRenderer({this.panelLongSide = 1200});

  final int panelLongSide;

  @override
  Future<Uint8List?> render(ComparisonRenderRequest r) async {
    final before = await renderPhotoComposite(r.photo, maxSide: panelLongSide);
    if (before == null) return null;
    ui.Image? proposed;
    if (r.source == ProposedSource.perspective) {
      proposed = await renderPhotoComposite(
        r.photo,
        maxSide: panelLongSide,
        markup: r.photo.markup,
        labels: r.labels,
        hiddenLayers: const {
          MarkupLayer.markers,
          MarkupLayer.electrical,
          MarkupLayer.obstructions,
        },
      );
    } else if (r.capture != null) {
      proposed = await decodeImageFile(r.capture!.path, maxSide: panelLongSide);
    }
    try {
      final panel = Size(before.width.toDouble(), before.height.toDouble());
      const gap = 16.0, margin = 16.0;
      final unit = math.max(panel.width / 40, 14.0);
      final headerH = unit * 3.6;
      final footerH = unit * 2;
      final labelH = unit * 1.6;
      final width = margin * 2 + panel.width * 2 + gap;
      final height = headerH + labelH + panel.height + footerH + margin;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width, height),
        Paint()..color = Colors.white,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width, unit * 0.35),
        Paint()..color = const Color(0xFFD71920),
      );
      _text(
        canvas,
        r.headerLines.join('\n'),
        Offset(margin, unit * 0.8),
        unit * 1.05,
        const Color(0xFF1D1D1F),
        width - margin * 2,
      );
      final top = headerH + labelH;
      final left = Rect.fromLTWH(margin, top, panel.width, panel.height);
      final right = Rect.fromLTWH(
        margin + panel.width + gap,
        top,
        panel.width,
        panel.height,
      );
      _text(
        canvas,
        'BEFORE',
        Offset(left.left, headerH),
        unit * 0.95,
        const Color(0xFF6B6F76),
        panel.width,
      );
      _text(
        canvas,
        'PROPOSED',
        Offset(right.left, headerH),
        unit * 0.95,
        const Color(0xFFD71920),
        panel.width,
      );
      _drawContained(canvas, before, left);
      if (proposed != null) {
        _drawContained(canvas, proposed, right);
      } else {
        canvas.drawRect(right, Paint()..color = const Color(0xFFE6E6EA));
        _text(
          canvas,
          'Proposed image not found',
          right.center - Offset(right.width / 4, unit),
          unit,
          const Color(0xFF6B6F76),
          right.width / 2,
        );
      }
      _text(
        canvas,
        r.footer,
        Offset(margin, top + panel.height + unit * 0.4),
        unit * 0.8,
        const Color(0xFF6B6F76),
        width - margin * 2,
      );
      final picture = recorder.endRecording();
      final out = await picture.toImage(width.round(), height.round());
      picture.dispose();
      try {
        return await encodePng(out);
      } finally {
        out.dispose();
      }
    } finally {
      before.dispose();
      proposed?.dispose();
    }
  }

  static void _drawContained(Canvas c, ui.Image img, Rect box) {
    c.drawRect(box, Paint()..color = const Color(0xFF202124));
    final src = Size(img.width.toDouble(), img.height.toDouble());
    final fit = applyBoxFit(BoxFit.contain, src, box.size);
    final dst = Alignment.center.inscribe(fit.destination, box);
    c.drawImageRect(
      img,
      Offset.zero & src,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  static void _text(
    Canvas c,
    String text,
    Offset at,
    double size,
    Color color,
    double maxWidth,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: math.max(maxWidth, 10));
    tp.paint(c, at);
  }
}

/// Reads width / height of an encoded image without decoding all pixels.
Future<Size?> encodedImageSize(String path) async {
  final img = await decodeImageFile(path, maxSide: 512);
  if (img == null) return null;
  final s = Size(img.width.toDouble(), img.height.toDouble());
  img.dispose();
  return s;
}
