import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import 'perspective_math.dart';

/// Independent visibility layers of the advanced site markup.
enum MarkupLayer { perspective, markers, electrical, obstructions }

extension MarkupLayerX on MarkupLayer {
  String get label => switch (this) {
    MarkupLayer.perspective => 'Perspective boards',
    MarkupLayer.markers => 'Placement markers',
    MarkupLayer.electrical => 'Electrical',
    MarkupLayer.obstructions => 'Obstructions',
  };
}

/// Display details of the signage items referenced by markings. Read-only
/// view of the recce: the painter never changes business data.
class MarkupItemInfo {
  const MarkupItemInfo({
    required this.unitId,
    required this.label,
    required this.mediaShortName,
    required this.color,
    this.sizeText = '',
    this.widthFt,
    this.heightFt,
    this.mediaCode,
    this.installationName = '',
  });

  final String unitId;

  /// "GSB – Unit 01".
  final String label;
  final String mediaShortName;
  final Color color;

  /// "W: 8 ft | H: 3 ft" (empty when not measured).
  final String sizeText;
  final double? widthFt;
  final double? heightFt;
  final String? mediaCode;
  final String installationName;

  /// Width / height of the board face (fallback 3:1 when not measured).
  double get aspect {
    final w = widthFt ?? 0, h = heightFt ?? 0;
    if (w <= 0 || h <= 0) return 3;
    return (w / h).clamp(0.05, 40).toDouble();
  }
}

/// Builds [MarkupItemInfo]s for every active unit of [shop].
class MarkupLabels {
  MarkupLabels(this.items, {this.brand = ''});

  factory MarkupLabels.forShop(Shop shop, {String brand = ''}) {
    final items = <String, MarkupItemInfo>{};
    for (final b in shop.boards) {
      final media = SignageCatalog.media(b.mediaCode);
      for (final u in b.activeUnits) {
        final w = b.widthOf(u), h = b.heightOf(u);
        final short = media?.shortName ?? b.name;
        items[u.id] = MarkupItemInfo(
          unitId: u.id,
          label: '$short – ${b.unitLabel(u)}',
          mediaShortName: short,
          mediaCode: b.mediaCode,
          color: media?.color ?? const Color(0xFFD71920),
          sizeText: b.unitHasSize(u)
              ? 'W: ${fmtNum(w!)} ${b.unit.label} | '
                    'H: ${fmtNum(h!)} ${b.unit.label}'
              : '',
          widthFt: b.unitHasSize(u) ? b.unit.toFeet(w!) : null,
          heightFt: b.unitHasSize(u) ? b.unit.toFeet(h!) : null,
          installationName:
              SignageCatalog.installation(b.installationOf(u))?.name ?? '',
        );
      }
    }
    return MarkupLabels(items, brand: brand);
  }

  final Map<String, MarkupItemInfo> items;

  /// Text printed on the perspective artwork (e.g. the client brand).
  final String brand;

  MarkupItemInfo? operator [](String? unitId) =>
      unitId == null ? null : items[unitId];

  String labelOf(String? unitId) => this[unitId]?.label ?? 'Unlinked item';
}

/// Severity colours for obstructions.
Color severityColor(Severity s) => switch (s) {
  Severity.low => const Color(0xFF1A73E8),
  Severity.medium => const Color(0xFFE37400),
  Severity.high => const Color(0xFFD71920),
};

const Color kElectricalColor = Color(0xFFF9AB00);

/// Paints [SiteMarkup] over a photo shown in a box of the photo's aspect
/// ratio (normalised coordinates → box pixels). Used by the markup editor,
/// the classic photo editor (read-only underlay), comparisons and the PDF.
class SiteMarkupPainter extends CustomPainter {
  SiteMarkupPainter({
    required this.markup,
    required this.labels,
    this.selectedId,
    this.hiddenLayers = const {},
    this.showHandles = false,
    this.zoom = 1,
    this.draftPoints = const [],
    this.draftClosed = false,
    this.invalidIds = const {},
    this.dimmed = false,
  });

  final SiteMarkup markup;
  final MarkupLabels labels;
  final String? selectedId;
  final Set<MarkupLayer> hiddenLayers;
  final bool showHandles;

  /// Current zoom of the viewer: handles / labels stay a constant size on
  /// screen.
  final double zoom;

  /// Points of a cable route / polygon being drawn.
  final List<SurveyPoint> draftPoints;
  final bool draftClosed;

  /// Perspective placements that currently fail validation.
  final Set<String> invalidIds;

  /// Draw everything semi-transparent (read-only underlay).
  final bool dimmed;

  /// Base size unit for markers and labels in box pixels.
  static double unitFor(Size size, double zoom) =>
      math.max(size.longestSide / 70, 7) / math.max(zoom, 0.2);

  /// Touch radius of a corner handle in box pixels.
  static double handleRadius(Size size, double zoom) =>
      unitFor(size, zoom) * 1.6;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final u = unitFor(size, zoom);
    if (dimmed) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = const Color(0xA6FFFFFF),
      );
    }
    if (!hiddenLayers.contains(MarkupLayer.obstructions)) {
      for (final o in markup.obstructions) {
        _obstruction(canvas, size, u, o);
      }
    }
    if (!hiddenLayers.contains(MarkupLayer.perspective)) {
      for (final p in markup.perspectives) {
        _perspective(canvas, size, u, p);
      }
    }
    if (!hiddenLayers.contains(MarkupLayer.electrical)) {
      for (final c in markup.cableRoutes) {
        _cable(canvas, size, u, c);
      }
      for (final e in markup.electrical) {
        _electrical(canvas, size, u, e);
      }
    }
    if (!hiddenLayers.contains(MarkupLayer.markers)) {
      for (final m in markup.markers) {
        _marker(canvas, size, u, m);
      }
    }
    if (draftPoints.isNotEmpty) _draft(canvas, size, u);
    if (dimmed) canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // Perspective boards
  // ---------------------------------------------------------------------------

  void _perspective(Canvas c, Size size, double u, PerspectivePlacement p) {
    final quad = [for (final pt in p.corners) pt.toPixels(size)];
    final info = labels[p.unitId];
    final invalid = invalidIds.contains(p.id);
    final selected = p.id == selectedId;
    if (p.showArtwork && !invalid) {
      paintBoardArtwork(c, quad, info, labels.brand, opacity: p.opacity);
    }
    final path = Path()..addPolygon(quad, true);
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.45
        ..color = Colors.white,
    );
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * (selected ? 0.32 : 0.22)
        ..color = invalid
            ? const Color(0xFFE37400)
            : (info?.color ?? const Color(0xFFD71920)),
    );
    // Label above the top edge.
    final top = Offset.lerp(quad[0], quad[1], 0.5)!;
    final lines = [
      info?.label ?? 'Unlinked item',
      if ((info?.sizeText ?? '').isNotEmpty) info!.sizeText,
      if (invalid) 'Invalid shape – fix corners',
    ];
    _label(
      c,
      size,
      top - Offset(0, u * 0.8),
      lines,
      u,
      background: invalid
          ? const Color(0xFFE37400)
          : (info?.color ?? const Color(0xFFD71920)),
      anchorBottom: true,
    );
    if (selected && showHandles) {
      for (var i = 0; i < 4; i++) {
        _handle(c, quad[i], u, label: const ['TL', 'TR', 'BR', 'BL'][i]);
      }
      final centre = QuadGeometry.centroid(quad);
      c.drawCircle(centre, u * 1.1, Paint()..color = const Color(0xCC1D1D1F));
      _icon(c, centre, Icons.open_with, u * 1.4, Colors.white);
    }
  }

  void _handle(Canvas c, Offset p, double u, {String? label}) {
    c.drawCircle(p, u * 1.05, Paint()..color = Colors.white);
    c.drawCircle(
      p,
      u * 1.05,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.3
        ..color = const Color(0xFFD71920),
    );
    if (label != null) {
      _text(
        c,
        label,
        p,
        u * 0.8,
        const Color(0xFFD71920),
        weight: FontWeight.w800,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Placement markers
  // ---------------------------------------------------------------------------

  void _marker(Canvas c, Size size, double u, PlacementMarker m) {
    final p = m.position.toPixels(size);
    final info = labels[m.unitId];
    final color = info?.color ?? const Color(0xFFD71920);
    final selected = m.id == selectedId;
    if (m.shape.length >= 3) {
      final poly = [for (final s in m.shape) s.toPixels(size)];
      c.drawPath(
        Path()..addPolygon(poly, true),
        Paint()..color = color.withValues(alpha: 0.18),
      );
      _dashedPolyline(c, poly, true, color, u * 0.25, u);
    }
    final r = u * 1.5;
    // Pin shadow + body.
    c.drawCircle(p + Offset(0, u * 0.15), r, Paint()..color = Colors.black26);
    c.drawCircle(p, r, Paint()..color = m.isAlternative ? Colors.white : color);
    c.drawCircle(
      p,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * (selected ? 0.45 : 0.25)
        ..color = selected
            ? const Color(0xFF1D1D1F)
            : (m.isAlternative ? color : Colors.white),
    );
    _text(
      c,
      m.numberLabel,
      p,
      u * 1.15,
      m.isAlternative ? color : Colors.white,
      weight: FontWeight.w800,
    );
    _label(
      c,
      size,
      p + Offset(0, r + u * 0.35),
      [
        '${info?.mediaShortName ?? m.mediaCode}'
            '${m.isAlternative ? ' (alt ${m.placementNo})' : ''}',
      ],
      u * 0.85,
      background: const Color(0xE61D1D1F),
    );
  }

  // ---------------------------------------------------------------------------
  // Electrical
  // ---------------------------------------------------------------------------

  void _electrical(Canvas c, Size size, double u, ElectricalMark e) {
    final p = e.position.toPixels(size);
    final selected = e.id == selectedId;
    final r = u * 1.25;
    switch (e.kind) {
      case ElectricalMarkKind.point:
        c.drawCircle(p, r, Paint()..color = kElectricalColor);
        _icon(c, p, Icons.bolt, r * 1.5, const Color(0xFF1D1D1F));
      case ElectricalMarkKind.switchPoint:
        final rect = Rect.fromCenter(center: p, width: r * 2, height: r * 2);
        c.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(u * 0.3)),
          Paint()..color = kElectricalColor,
        );
        _icon(c, p, Icons.toggle_on_outlined, r * 1.5, const Color(0xFF1D1D1F));
      case ElectricalMarkKind.powerNote:
        c.drawCircle(p, r, Paint()..color = const Color(0xFF1D1D1F));
        _icon(c, p, Icons.sticky_note_2_outlined, r * 1.3, kElectricalColor);
    }
    if (selected) {
      c.drawCircle(
        p,
        r + u * 0.35,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.3
          ..color = const Color(0xFF1D1D1F),
      );
    }
    _label(
      c,
      size,
      p + Offset(0, r + u * 0.35),
      [
        e.kind == ElectricalMarkKind.powerNote && e.notes.trim().isNotEmpty
            ? '${e.code} ${_short(e.notes)}'
            : e.code,
      ],
      u * 0.85,
      background: const Color(0xE61D1D1F),
      foreground: kElectricalColor,
    );
  }

  void _cable(Canvas c, Size size, double u, CableRoute r) {
    if (r.points.length < 2) return;
    final pts = [for (final p in r.points) p.toPixels(size)];
    final selected = r.id == selectedId;
    _dashedPolyline(
      c,
      pts,
      false,
      Colors.black54,
      u * (selected ? 0.75 : 0.55),
      u,
    );
    _dashedPolyline(
      c,
      pts,
      false,
      kElectricalColor,
      u * (selected ? 0.45 : 0.32),
      u,
    );
    for (final p in pts) {
      c.drawCircle(p, u * 0.35, Paint()..color = kElectricalColor);
    }
    _label(
      c,
      size,
      pts.first - Offset(0, u * 0.6),
      [r.code],
      u * 0.85,
      background: const Color(0xE61D1D1F),
      foreground: kElectricalColor,
      anchorBottom: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Obstructions
  // ---------------------------------------------------------------------------

  void _obstruction(Canvas c, Size size, double u, ObstructionMark o) {
    if (!o.isValid) return;
    final color = severityColor(o.severity);
    final pts = [for (final p in o.points) p.toPixels(size)];
    final selected = o.id == selectedId;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * (selected ? 0.42 : 0.28)
      ..color = color;
    Offset anchor;
    switch (o.shape) {
      case ObstructionShape.point:
        anchor = pts.first;
        final r = u * 1.4;
        final tri = Path()
          ..moveTo(anchor.dx, anchor.dy - r)
          ..lineTo(anchor.dx + r, anchor.dy + r * 0.8)
          ..lineTo(anchor.dx - r, anchor.dy + r * 0.8)
          ..close();
        c.drawPath(tri, Paint()..color = color);
        c.drawPath(
          tri,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.2
            ..color = Colors.white,
        );
        _text(
          c,
          '!',
          anchor + Offset(0, r * 0.15),
          r * 1.1,
          Colors.white,
          weight: FontWeight.w900,
        );
        anchor = anchor + Offset(0, r);
      case ObstructionShape.rect:
        final rect = Rect.fromPoints(pts[0], pts[1]);
        c.drawRect(rect, Paint()..color = color.withValues(alpha: 0.2));
        c.drawRect(rect, stroke);
        anchor = rect.bottomCenter;
      case ObstructionShape.polygon:
        final path = Path()..addPolygon(pts, true);
        c.drawPath(path, Paint()..color = color.withValues(alpha: 0.2));
        c.drawPath(path, stroke);
        var bottom = pts.first;
        for (final p in pts) {
          if (p.dy > bottom.dy) bottom = p;
        }
        anchor = bottom;
      case ObstructionShape.arrow:
        _arrow(c, pts[0], pts[1], color, u);
        anchor = pts[0];
      case ObstructionShape.text:
        anchor = pts.first;
    }
    final caption = o.shape == ObstructionShape.text && o.label.isNotEmpty
        ? '${o.code} ${_short(o.label)}'
        : '${o.code} ${o.type.label}';
    _label(
      c,
      size,
      anchor + Offset(0, u * 0.35),
      [caption],
      u * 0.85,
      background: color,
    );
  }

  void _arrow(Canvas c, Offset a, Offset b, Color color, double u) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = u * 0.4
      ..strokeCap = StrokeCap.round;
    c.drawLine(a, b, paint);
    final d = b - a;
    if (d.distance < 1) return;
    final dir = d / d.distance;
    final n = Offset(-dir.dy, dir.dx);
    final head = Path()
      ..moveTo(b.dx, b.dy)
      ..lineTo(
        b.dx - dir.dx * u * 1.6 + n.dx * u * 0.9,
        b.dy - dir.dy * u * 1.6 + n.dy * u * 0.9,
      )
      ..lineTo(
        b.dx - dir.dx * u * 1.6 - n.dx * u * 0.9,
        b.dy - dir.dy * u * 1.6 - n.dy * u * 0.9,
      )
      ..close();
    c.drawPath(head, Paint()..color = color);
  }

  void _draft(Canvas c, Size size, double u) {
    final pts = [for (final p in draftPoints) p.toPixels(size)];
    if (pts.length >= 2) {
      _dashedPolyline(c, pts, draftClosed, const Color(0xFF1A73E8), u * 0.3, u);
    }
    for (final p in pts) {
      c.drawCircle(p, u * 0.5, Paint()..color = const Color(0xFF1A73E8));
    }
  }

  // ---------------------------------------------------------------------------
  // Drawing helpers
  // ---------------------------------------------------------------------------

  static String _short(String s) {
    final t = s.trim().replaceAll('\n', ' ');
    return t.length <= 28 ? t : '${t.substring(0, 27)}…';
  }

  void _dashedPolyline(
    Canvas c,
    List<Offset> pts,
    bool closed,
    Color color,
    double width,
    double u,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dash = u * 0.9, gap = u * 0.6;
    final segs = [
      for (var i = 0; i < pts.length - 1; i++) (pts[i], pts[i + 1]),
      if (closed && pts.length > 2) (pts.last, pts.first),
    ];
    for (final (a, b) in segs) {
      final d = b - a;
      final len = d.distance;
      if (len < 0.01) continue;
      final dir = d / len;
      var t = 0.0;
      while (t < len) {
        final e = math.min(t + dash, len);
        c.drawLine(a + dir * t, a + dir * e, paint);
        t = e + gap;
      }
    }
  }

  void _text(
    Canvas c,
    String text,
    Offset centre,
    double fontSize,
    Color color, {
    FontWeight weight = FontWeight.w700,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: weight,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, centre - Offset(tp.width / 2, tp.height / 2));
  }

  void _icon(Canvas c, Offset centre, IconData icon, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, centre - Offset(tp.width / 2, tp.height / 2));
  }

  /// Pill with one or more lines, centred horizontally on [anchor] (top or
  /// bottom edge at the anchor) and kept inside the box.
  void _label(
    Canvas c,
    Size size,
    Offset anchor,
    List<String> lines,
    double u, {
    required Color background,
    Color foreground = Colors.white,
    bool anchorBottom = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        children: [
          for (var i = 0; i < lines.length; i++)
            TextSpan(
              text: i == 0 ? lines[i] : '\n${lines[i]}',
              style: TextStyle(
                fontSize: u * (i == 0 ? 1.05 : 0.95),
                fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600,
                color: foreground,
                height: 1.15,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 3,
    )..layout(maxWidth: math.max(size.width * 0.8, 40));
    final pad = Offset(u * 0.5, u * 0.3);
    final w = tp.width + pad.dx * 2, h = tp.height + pad.dy * 2;
    var left = anchor.dx - w / 2;
    var top = anchorBottom ? anchor.dy - h : anchor.dy;
    left = left.clamp(0.0, math.max(0.0, size.width - w)).toDouble();
    top = top.clamp(0.0, math.max(0.0, size.height - h)).toDouble();
    final rect = Rect.fromLTWH(left, top, w, h);
    c.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(u * 0.45)),
      Paint()..color = background,
    );
    tp.paint(c, rect.topLeft + pad);
  }

  @override
  bool shouldRepaint(covariant SiteMarkupPainter old) => true;
}

/// Paints the board face (brand / media artwork) mapped onto [quad] with a
/// true perspective homography (not a rotate / stretch approximation).
void paintBoardArtwork(
  Canvas canvas,
  List<Offset> quad,
  MarkupItemInfo? info,
  String brand, {
  double opacity = 0.85,
}) {
  final aspect = info?.aspect ?? 3;
  const baseH = 100.0;
  final art = Rect.fromLTWH(0, 0, baseH * aspect, baseH);
  final h = Homography.rectTo(art, quad);
  if (h == null) return;
  final color = info?.color ?? const Color(0xFFD71920);
  canvas.save();
  canvas.transform(h.toMatrix4().storage);
  final a = (opacity.clamp(0.1, 1) * 255).round();
  canvas.drawRect(art, Paint()..color = color.withAlpha(a));
  final inset = art.deflate(baseH * 0.06);
  canvas.drawRect(
    inset,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseH * 0.025
      ..color = Colors.white.withAlpha(a),
  );
  final title = brand.trim().isNotEmpty
      ? brand.trim().toUpperCase()
      : (info?.mediaShortName ?? 'SIGNAGE').toUpperCase();
  final tp = TextPainter(
    text: TextSpan(
      children: [
        TextSpan(
          text: title,
          style: TextStyle(
            fontSize: baseH * 0.34,
            fontWeight: FontWeight.w900,
            color: Colors.white.withAlpha(a),
            letterSpacing: 1,
          ),
        ),
        TextSpan(
          text: '\n${info?.label ?? ''}',
          style: TextStyle(
            fontSize: baseH * 0.14,
            fontWeight: FontWeight.w600,
            color: Colors.white.withAlpha(a),
          ),
        ),
      ],
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: inset.width * 0.94);
  tp.paint(
    canvas,
    Offset(art.center.dx - tp.width / 2, art.center.dy - tp.height / 2),
  );
  canvas.restore();
}
