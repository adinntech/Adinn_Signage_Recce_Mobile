import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/catalog/measurement_fields.dart';
import '../../data/catalog/signage_catalog.dart';
import 'signage_spec.dart';

/// Views of the 2D technical drawing.
enum DrawingView { front, side, top, installation }

extension DrawingViewX on DrawingView {
  String get label => switch (this) {
    DrawingView.front => 'Front Elevation',
    DrawingView.side => 'Side Elevation',
    DrawingView.top => 'Top View',
    DrawingView.installation => 'Installation Schematic',
  };
}

/// One dimension of a drawing (for tests and the PDF dimension table).
class DrawingDimension {
  const DrawingDimension(this.id, this.label, this.valueMm, this.field);

  final String id;
  final String label;
  final double valueMm;
  final SpecField? field;
}

/// Dimensions shown on [view] for [spec] – the same canonical values the
/// 3D model and the recce form use (never re-derived elsewhere).
List<DrawingDimension> drawingDimensions(
  SignageModelSpec spec,
  DrawingView view,
) {
  final out = <DrawingDimension>[];
  void add(String id, SpecField f, [String? label]) {
    if (spec.has(f)) {
      out.add(DrawingDimension(id, label ?? f.label, spec[f], f));
    }
  }

  switch (view) {
    case DrawingView.front:
    case DrawingView.installation:
      add('width', SpecField.width);
      add('height', SpecField.height);
      add('mounting', SpecField.mountingHeight);
      add('pole_spacing', SpecField.poleSpacing);
      add('pipe_spacing', SpecField.pipeSpacing);
      add('base_width', SpecField.baseWidth);
      add('overall', SpecField.overallHeight);
      add('gsb_w', SpecField.gsbPanelWidth);
      add('gsb_h', SpecField.gsbPanelHeight);
      if (view == DrawingView.installation) {
        add('embedment', SpecField.poleEmbedment);
        add('rooftop', SpecField.rooftopFrameHeight);
      }
    case DrawingView.side:
      add('height', SpecField.height);
      add('depth', SpecField.depth);
      add('mounting', SpecField.mountingHeight);
      add('pipe_length', SpecField.pipeLength);
      add('standoff', SpecField.standoff);
      add('letters', SpecField.letterDepthFront);
      add('letters_rear', SpecField.letterDepthRear);
      add('mdf', SpecField.mdfThickness);
      add('thickness', SpecField.materialThickness);
      add('embedment', SpecField.poleEmbedment);
      add('base_depth', SpecField.baseDepth);
    case DrawingView.top:
      add('width', SpecField.width);
      add('depth', SpecField.depth);
      add('pole_spacing', SpecField.poleSpacing);
      add('base_depth', SpecField.baseDepth);
      add('pipe_length', SpecField.pipeLength);
  }
  return out;
}

/// Technical 2D drawing generated from a [SignageModelSpec]. Illustrative
/// schematic – not a fabrication-certified structural drawing.
class TechnicalDrawingPainter extends CustomPainter {
  TechnicalDrawingPainter({
    required this.spec,
    required this.view,
    this.showDimensions = true,
    this.title,
  });

  final SignageModelSpec spec;
  final DrawingView view;
  final bool showDimensions;
  final String? title;

  static const _ink = Color(0xFF1D1D1F);
  static const _red = Color(0xFFD71920);
  static const _muted = Color(0xFF6B6F76);
  static const _steel = Color(0xFF8C939B);

  String _len(double mm) => fmtMm(mm, spec.displayUnit);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    if (size.width < 40 || size.height < 40) return;
    final header = 22.0;
    _text(canvas, title ?? view.label, Offset(10, 6), 13, _ink, bold: true);
    _text(
      canvas,
      'Illustrative schematic – not a structural / fabrication drawing',
      Offset(10, size.height - 16),
      9,
      _muted,
    );
    final area = Rect.fromLTRB(
      44,
      header + 14,
      size.width - 44,
      size.height - 40,
    );
    switch (view) {
      case DrawingView.front:
      case DrawingView.installation:
        _front(canvas, area, context: view == DrawingView.installation);
      case DrawingView.side:
        _side(canvas, area);
      case DrawingView.top:
        _top(canvas, area);
    }
  }

  // ---------------------------------------------------------------------------
  // Views
  // ---------------------------------------------------------------------------

  double get _w => math.max(spec.widthMm, 1);
  double get _h => math.max(spec.heightMm, 1);
  double get _mount => math.max(spec.mountingHeightMm, 0);
  double get _depth =>
      spec.has(SpecField.depth) ? math.max(spec.depthMm, 1) : 20;

  bool get _poles => spec.has(SpecField.poleCount);
  bool get _pipes => spec.has(SpecField.pipeCount);
  bool get _free => spec.installationCode == SignageCatalog.freeStanding;
  bool get _roof => spec.installationCode == SignageCatalog.rooftop;

  /// Fits a world rectangle (mm, y up) into [area].
  (double, Offset) _fit(Rect world, Rect area) {
    final k = math.min(area.width / world.width, area.height / world.height);
    final ox = area.center.dx - world.center.dx * k;
    final oy = area.center.dy + world.center.dy * k;
    return (k, Offset(ox, oy));
  }

  void _front(Canvas c, Rect area, {required bool context}) {
    final embed = _poles ? spec[SpecField.poleEmbedment] : 0.0;
    final top = _mount + _h;
    final halfW = _w / 2;
    var minX = -halfW, maxX = halfW;
    if (_free && spec.has(SpecField.baseWidth)) {
      minX = math.min(minX, -spec[SpecField.baseWidth] / 2);
      maxX = math.max(maxX, spec[SpecField.baseWidth] / 2);
    }
    final pad = math.max(_w, top) * 0.18;
    final world = Rect.fromLTRB(
      minX - pad,
      -(context ? embed : 0) - pad * 0.4,
      maxX + pad,
      math.max(
            top,
            spec.has(SpecField.overallHeight)
                ? spec[SpecField.overallHeight]
                : top,
          ) +
          pad * 0.6,
    );
    final (k, o) = _fit(world, area);
    Offset p(double x, double y) => Offset(o.dx + x * k, o.dy - y * k);

    // Ground.
    final groundY = p(0, 0).dy;
    c.drawLine(
      Offset(area.left - 20, groundY),
      Offset(area.right + 20, groundY),
      Paint()
        ..color = _ink
        ..strokeWidth = 1.4,
    );
    for (var x = area.left - 20; x < area.right + 20; x += 10) {
      c.drawLine(
        Offset(x, groundY),
        Offset(x - 6, groundY + 6),
        Paint()
          ..color = _muted
          ..strokeWidth = 0.6,
      );
    }
    _text(c, 'Ground level', Offset(area.left - 20, groundY + 6), 9, _muted);

    // Context: wall / roof / glass.
    if (context) {
      final ctx = Paint()..color = const Color(0xFFEDE6D8);
      final inst = spec.installationCode;
      if (inst == SignageCatalog.shopFascia ||
          inst == SignageCatalog.wallMount ||
          inst == SignageCatalog.directWall ||
          inst == SignageCatalog.supportPipe) {
        c.drawRect(
          Rect.fromPoints(
            p(-halfW - pad * 0.7, 0),
            p(halfW + pad * 0.7, top + pad * 0.4),
          ),
          ctx,
        );
        _text(
          c,
          'Wall / fascia',
          p(-halfW - pad * 0.65, top + pad * 0.35),
          9,
          _muted,
        );
      } else if (inst == SignageCatalog.glassPasting) {
        c.drawRect(
          Rect.fromPoints(
            p(-halfW - pad * 0.5, 0),
            p(halfW + pad * 0.5, top + pad * 0.3),
          ),
          Paint()..color = const Color(0x5586B3D1),
        );
        _text(c, 'Glass', p(-halfW - pad * 0.45, top + pad * 0.25), 9, _muted);
      } else if (_roof) {
        final roofY = _mount - spec[SpecField.rooftopFrameHeight];
        c.drawRect(
          Rect.fromPoints(
            p(-halfW - pad * 0.7, 0),
            p(halfW + pad * 0.7, roofY),
          ),
          ctx,
        );
        _text(
          c,
          'Building (roof level)',
          p(-halfW - pad * 0.65, roofY),
          9,
          _muted,
        );
      }
    }

    // Supports.
    final steel = Paint()..color = _steel;
    final pw = math.max(3.0, 100 * k);
    if (_poles) {
      final n = spec[SpecField.poleCount].round().clamp(1, 6);
      final gap = n > 1 ? spec[SpecField.poleSpacing] : 0.0;
      for (var i = 0; i < n; i++) {
        final x = n == 1 ? 0.0 : -gap / 2 + gap * i / (n - 1);
        c.drawRect(
          Rect.fromCenter(
            center: Offset(p(x, 0).dx, (p(x, 0).dy + p(x, _mount).dy) / 2),
            width: pw,
            height: (p(x, 0).dy - p(x, _mount).dy).abs(),
          ),
          steel,
        );
        if (context && embed > 0) {
          _dashedRect(
            c,
            Rect.fromPoints(p(x - 50, 0), p(x + 50, -embed)),
            _steel,
          );
        }
      }
      if (showDimensions && n > 1) {
        _dimH(
          c,
          p(-gap / 2, _mount * 0.5),
          p(gap / 2, _mount * 0.5),
          'Pole spacing ${_len(gap)}',
        );
      }
      if (showDimensions && context && embed > 0) {
        _dimV(
          c,
          p(gap / 2 + 160, -embed),
          p(gap / 2 + 160, 0),
          'Embedment ${_len(embed)}',
          left: false,
        );
      }
    }
    if (_roof) {
      final fh = spec[SpecField.rooftopFrameHeight];
      for (final x in [-halfW * 0.8, 0.0, halfW * 0.8]) {
        c.drawRect(
          Rect.fromPoints(p(x - 40, _mount - fh), p(x + 40, _mount)),
          steel,
        );
      }
      if (showDimensions) {
        _dimV(
          c,
          p(halfW + pad * 0.3, _mount - fh),
          p(halfW + pad * 0.3, _mount),
          'Frame ${_len(fh)}',
          left: false,
        );
      }
    }
    if (_free) {
      if (spec.has(SpecField.baseWidth)) {
        final bw = spec[SpecField.baseWidth];
        c.drawRect(Rect.fromPoints(p(-bw / 2, 0), p(bw / 2, 60)), steel);
        if (showDimensions) {
          _dimH(
            c,
            p(-bw / 2, -pad * 0.25),
            p(bw / 2, -pad * 0.25),
            'Base ${_len(bw)}',
          );
        }
      }
      if (spec.template != 'sandwich') {
        for (final x in [-halfW * 0.9, halfW * 0.9]) {
          c.drawRect(Rect.fromPoints(p(x - 30, 0), p(x + 30, _mount)), steel);
        }
      }
    }

    // Board.
    final color = spec.media?.color ?? _red;
    final board = Rect.fromPoints(p(-halfW, _mount), p(halfW, top));
    c.drawRect(board, Paint()..color = color.withValues(alpha: 0.18));
    c.drawRect(
      board,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color,
    );
    if (spec.has(SpecField.frameThickness)) {
      final f = spec[SpecField.frameThickness] * k;
      c.drawRect(
        board.deflate(math.min(f, board.shortestSide / 4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = _ink,
      );
    }
    if (spec.has(SpecField.gsbPanelWidth)) {
      final gw = spec[SpecField.gsbPanelWidth],
          gh = spec[SpecField.gsbPanelHeight];
      final cy = _mount + _h / 2;
      final g = Rect.fromPoints(
        p(-gw / 2, cy - gh / 2),
        p(gw / 2, cy + gh / 2),
      );
      c.drawRect(g, Paint()..color = const Color(0x55FFC107));
      c.drawRect(
        g,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFFE37400),
      );
      if (showDimensions) {
        _dimH(
          c,
          g.bottomLeft + const Offset(0, -10),
          g.bottomRight + const Offset(0, -10),
          'GSB ${_len(gw)} × ${_len(gh)}',
        );
      }
    }
    _text(
      c,
      '${spec.media?.shortName ?? spec.mediaCode}'
      '${spec.isDoubleSided ? ' • double-sided' : ''}',
      board.center - const Offset(30, 6),
      10,
      color,
      bold: true,
    );
    if (_pipes) {
      final n = spec[SpecField.pipeCount].round().clamp(1, 8);
      final gap = math.min(spec[SpecField.pipeSpacing], _w);
      for (var i = 0; i < n; i++) {
        final x = n == 1 ? 0.0 : -gap / 2 + gap * i / (n - 1);
        c.drawCircle(p(x, _mount + _h / 2), math.max(2.5, 40 * k), steel);
      }
      if (showDimensions && n > 1) {
        _dimH(
          c,
          p(-gap / 2, top + pad * 0.15),
          p(gap / 2, top + pad * 0.15),
          'Pipe spacing ${_len(gap)}',
        );
      }
    }

    if (!showDimensions) return;
    _dimH(
      c,
      p(-halfW, top + pad * 0.38),
      p(halfW, top + pad * 0.38),
      'W ${_len(_w)}',
    );
    _dimV(
      c,
      p(-halfW - pad * 0.3, _mount),
      p(-halfW - pad * 0.3, top),
      'H ${_len(_h)}',
    );
    if (_mount > 0) {
      _dimV(
        c,
        p(halfW + pad * 0.55, 0),
        p(halfW + pad * 0.55, _mount),
        'Clearance ${_len(_mount)}',
        left: false,
      );
    }
    if (spec.has(SpecField.overallHeight)) {
      final oh = spec[SpecField.overallHeight];
      _dimV(
        c,
        p(-halfW - pad * 0.7, 0),
        p(-halfW - pad * 0.7, oh),
        'Overall ${_len(oh)}',
      );
    }
  }

  void _side(Canvas c, Rect area) {
    final d = _depth;
    final top = _mount + _h;
    final standoff = spec.has(SpecField.standoff)
        ? spec[SpecField.standoff]
        : 0.0;
    final pipe = _pipes ? spec[SpecField.pipeLength] : 0.0;
    final offset = math.max(standoff, pipe);
    final letters = spec.has(SpecField.letterDepthFront)
        ? spec[SpecField.letterDepthFront]
        : 0.0;
    final rear = spec.has(SpecField.letterDepthRear)
        ? spec[SpecField.letterDepthRear]
        : 0.0;
    final sandwich = spec.template == 'sandwich';
    final span = sandwich
        ? 2 * _h * math.sin(spec[SpecField.openingAngle] * math.pi / 180) + 200
        : offset + d + letters + rear + 200;
    final pad = math.max(span, top) * 0.25;
    final world = Rect.fromLTRB(
      -pad - 100,
      -pad * 0.3,
      span + pad,
      top + pad * 0.5,
    );
    final (k, o) = _fit(world, area);
    Offset p(double x, double y) => Offset(o.dx + x * k, o.dy - y * k);
    final ink = Paint()
      ..color = _ink
      ..strokeWidth = 1.4;
    c.drawLine(p(world.left, 0), p(world.right, 0), ink);
    final color = spec.media?.color ?? _red;

    if (sandwich) {
      final ang = spec[SpecField.openingAngle] * math.pi / 180;
      final hx = _h * math.sin(ang);
      final apex = p(hx, top);
      final paint = Paint()
        ..color = color
        ..strokeWidth = math.max(2, spec[SpecField.materialThickness] * k * 4);
      c.drawLine(p(0, 0), apex, paint);
      c.drawLine(p(2 * hx, 0), apex, paint);
      if (showDimensions) {
        _dimH(
          c,
          p(0, -pad * 0.15),
          p(2 * hx, -pad * 0.15),
          'Footprint ${_len(2 * hx)}',
        );
        _text(
          c,
          'Opening ${spec[SpecField.openingAngle].toStringAsFixed(0)}°',
          apex + const Offset(8, 2),
          10,
          _ink,
        );
        _dimV(c, p(-pad * 0.2, 0), p(-pad * 0.2, top), 'Overall ${_len(top)}');
      }
      return;
    }

    // Wall line (x = 0) for wall-type installations.
    final wallBacked = !_poles && !_free;
    if (wallBacked) {
      c.drawRect(
        Rect.fromPoints(p(-100, 0), p(0, top + pad * 0.3)),
        Paint()..color = const Color(0xFFEDE6D8),
      );
    }
    final x0 = wallBacked ? offset : 0.0;
    final board = Rect.fromPoints(p(x0, _mount), p(x0 + d, top));
    c.drawRect(board, Paint()..color = color.withValues(alpha: 0.25));
    c.drawRect(
      board,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = 1.4,
    );
    if (letters > 0) {
      c.drawRect(
        Rect.fromPoints(
          p(x0 + d, _mount + _h * 0.3),
          p(x0 + d + letters, _mount + _h * 0.7),
        ),
        Paint()..color = color,
      );
    }
    if (rear > 0) {
      c.drawRect(
        Rect.fromPoints(
          p(x0 - rear, _mount + _h * 0.3),
          p(x0, _mount + _h * 0.7),
        ),
        Paint()..color = color,
      );
    }
    if (offset > 0 && wallBacked) {
      c.drawLine(
        p(0, _mount + _h / 2),
        p(x0, _mount + _h / 2),
        Paint()
          ..color = _steel
          ..strokeWidth = 3,
      );
    }
    if (_poles) {
      c.drawRect(
        Rect.fromPoints(p(d / 2 - 50, 0), p(d / 2 + 50, _mount)),
        Paint()..color = _steel,
      );
    }
    if (!showDimensions) return;
    _dimH(
      c,
      p(x0, top + pad * 0.2),
      p(x0 + d, top + pad * 0.2),
      'D ${_len(d)}',
    );
    _dimV(
      c,
      p(x0 + d + letters + pad * 0.2, _mount),
      p(x0 + d + letters + pad * 0.2, top),
      'H ${_len(_h)}',
      left: false,
    );
    if (_mount > 0) {
      _dimV(
        c,
        p(-pad * 0.4, 0),
        p(-pad * 0.4, _mount),
        'Clearance ${_len(_mount)}',
      );
    }
    if (offset > 0 && wallBacked) {
      _dimH(
        c,
        p(0, _mount - pad * 0.15),
        p(x0, _mount - pad * 0.15),
        standoff > pipe ? 'Standoff ${_len(standoff)}' : 'Pipe ${_len(pipe)}',
      );
    }
    if (letters > 0) {
      _text(
        c,
        'Letters ${_len(letters)}',
        board.topRight + const Offset(4, -14),
        9,
        _ink,
      );
    }
    for (final f in [SpecField.mdfThickness, SpecField.materialThickness]) {
      if (spec.has(f)) {
        _text(
          c,
          '${f.label}: ${_len(spec[f])}',
          Offset(area.left, area.top + (f == SpecField.mdfThickness ? 0 : 12)),
          9,
          _ink,
        );
      }
    }
  }

  void _top(Canvas c, Rect area) {
    final d = _depth;
    final halfW = _w / 2;
    final baseD = _free && spec.has(SpecField.baseDepth)
        ? spec[SpecField.baseDepth]
        : 0.0;
    final pipe = _pipes ? spec[SpecField.pipeLength] : 0.0;
    final extent = math.max(d, math.max(baseD, pipe + d));
    final pad = math.max(_w, extent) * 0.2;
    final world = Rect.fromLTRB(-halfW - pad, -pad, halfW + pad, extent + pad);
    final (k, o) = _fit(world, area);
    Offset p(double x, double y) => Offset(o.dx + x * k, o.dy - y * k);
    final color = spec.media?.color ?? _red;
    final y0 = pipe;
    if (pipe > 0) {
      c.drawLine(
        p(-halfW - pad, 0),
        p(halfW + pad, 0),
        Paint()
          ..color = _ink
          ..strokeWidth = 2,
      );
      _text(c, 'Wall', p(-halfW - pad, 0) + const Offset(0, 4), 9, _muted);
    }
    final board = Rect.fromPoints(p(-halfW, y0), p(halfW, y0 + d));
    c.drawRect(board, Paint()..color = color.withValues(alpha: 0.25));
    c.drawRect(
      board,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = 1.4,
    );
    final steel = Paint()..color = _steel;
    if (_poles) {
      final n = spec[SpecField.poleCount].round().clamp(1, 6);
      final gap = n > 1 ? spec[SpecField.poleSpacing] : 0.0;
      for (var i = 0; i < n; i++) {
        final x = n == 1 ? 0.0 : -gap / 2 + gap * i / (n - 1);
        c.drawCircle(p(x, y0 + d / 2), math.max(3, 60 * k), steel);
      }
      if (showDimensions && n > 1) {
        _dimH(
          c,
          p(-gap / 2, -pad * 0.4),
          p(gap / 2, -pad * 0.4),
          'Pole spacing ${_len(gap)}',
        );
      }
    }
    if (baseD > 0) {
      final bw = spec.has(SpecField.baseWidth) ? spec[SpecField.baseWidth] : _w;
      c.drawRect(
        Rect.fromPoints(
          p(-bw / 2, y0 + d / 2 - baseD / 2),
          p(bw / 2, y0 + d / 2 + baseD / 2),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _steel
          ..strokeWidth = 1.2,
      );
      if (showDimensions) {
        _dimV(
          c,
          p(bw / 2 + pad * 0.3, y0 + d / 2 - baseD / 2),
          p(bw / 2 + pad * 0.3, y0 + d / 2 + baseD / 2),
          'Base ${_len(baseD)}',
          left: false,
        );
      }
    }
    if (!showDimensions) return;
    _dimH(
      c,
      p(-halfW, extent + pad * 0.5),
      p(halfW, extent + pad * 0.5),
      'W ${_len(_w)}',
    );
    _dimV(
      c,
      p(-halfW - pad * 0.4, y0),
      p(-halfW - pad * 0.4, y0 + d),
      'D ${_len(d)}',
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _dashedRect(Canvas c, Rect r, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    void dash(Offset a, Offset b) {
      final len = (b - a).distance;
      if (len < 1) return;
      final dir = (b - a) / len;
      for (var t = 0.0; t < len; t += 6) {
        c.drawLine(a + dir * t, a + dir * math.min(t + 3, len), paint);
      }
    }

    dash(r.topLeft, r.topRight);
    dash(r.topRight, r.bottomRight);
    dash(r.bottomRight, r.bottomLeft);
    dash(r.bottomLeft, r.topLeft);
  }

  void _arrow(Canvas c, Offset tip, Offset dir, Paint paint) {
    final n = Offset(-dir.dy, dir.dx);
    c.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - dir.dx * 7 + n.dx * 3, tip.dy - dir.dy * 7 + n.dy * 3)
        ..lineTo(tip.dx - dir.dx * 7 - n.dx * 3, tip.dy - dir.dy * 7 - n.dy * 3)
        ..close(),
      paint,
    );
  }

  void _dimLine(Canvas c, Offset a, Offset b) {
    final paint = Paint()
      ..color = _red
      ..strokeWidth = 1;
    c.drawLine(a, b, paint);
    final len = (b - a).distance;
    if (len < 1) return;
    final dir = (b - a) / len;
    _arrow(c, b, dir, paint);
    _arrow(c, a, -dir, paint);
  }

  void _dimH(Canvas c, Offset a, Offset b, String label) {
    _dimLine(c, a, b);
    final mid = Offset((a.dx + b.dx) / 2, a.dy);
    _pill(c, label, mid);
  }

  void _dimV(Canvas c, Offset a, Offset b, String label, {bool left = true}) {
    _dimLine(c, a, b);
    final mid = Offset(a.dx, (a.dy + b.dy) / 2);
    _pill(c, label, mid, shift: left ? -1 : 1);
  }

  void _pill(Canvas c, String text, Offset centre, {int shift = 0}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 9.5,
          color: _red,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var pos = centre - Offset(tp.width / 2, tp.height / 2);
    if (shift != 0) pos = pos + Offset(shift * (tp.width / 2 + 6), 0);
    final r = (pos & tp.size).inflate(2);
    c.drawRect(r, Paint()..color = Colors.white);
    tp.paint(c, pos);
  }

  void _text(
    Canvas c,
    String text,
    Offset at,
    double size,
    Color color, {
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 600);
    tp.paint(c, at);
  }

  @override
  bool shouldRepaint(covariant TechnicalDrawingPainter old) =>
      old.spec != spec ||
      old.view != view ||
      old.showDimensions != showDimensions;
}

/// Renders a drawing view to PNG bytes (used by the PDF report).
Future<Uint8List?> renderTechnicalDrawingPng(
  SignageModelSpec spec,
  DrawingView view, {
  Size size = const Size(900, 600),
  bool showDimensions = true,
}) async {
  final recorder = ui.PictureRecorder();
  TechnicalDrawingPainter(
    spec: spec,
    view: view,
    showDimensions: showDimensions,
  ).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
