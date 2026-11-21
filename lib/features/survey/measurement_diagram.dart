import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/catalog/measurement_fields.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';

/// Values the smart measurement diagram is drawn from. Every length is in
/// millimetres and comes from user-entered measurements; null = not
/// measured (the diagram then uses a neutral sketch position and labels the
/// value as "not measured" – it never invents a dimension).
class MeasurementDiagramData {
  const MeasurementDiagramData({
    required this.installationCode,
    required this.unit,
    this.boardW,
    this.boardH,
    this.values = const {},
    this.counts = const {},
    this.pipesUsed = false,
  });

  /// Builds the data for unit [u] of [b] using the (possibly unsaved)
  /// measurement draft [m].
  factory MeasurementDiagramData.of(
    Board b,
    SignageUnit u,
    MeasurementDetails m,
  ) {
    final w = b.widthOf(u), h = b.heightOf(u);
    return MeasurementDiagramData(
      installationCode: b.installationOf(u),
      unit: m.unit,
      boardW: (w ?? 0) > 0 ? b.unit.toMm(w!) : null,
      boardH: (h ?? 0) > 0 ? b.unit.toMm(h!) : null,
      values: Map.of(m.valuesMm),
      counts: Map.of(m.counts),
      pipesUsed: m.flags[MeasurementCatalog.pipesUsedFlag] == true,
    );
  }

  final String? installationCode;
  final MeasureUnit unit;
  final double? boardW;
  final double? boardH;
  final Map<String, double> values;
  final Map<String, double> counts;
  final bool pipesUsed;

  double? v(String id) {
    final x = values[id];
    return x != null && x.isFinite && x >= 0 ? x : null;
  }

  bool get isPole =>
      installationCode == SignageCatalog.singlePole ||
      installationCode == SignageCatalog.doublePole;
  bool get isDoublePole => installationCode == SignageCatalog.doublePole;
  bool get isStandee => installationCode == SignageCatalog.freeStanding;
  bool get isGlass => installationCode == SignageCatalog.glassPasting;
  bool get showsPipes =>
      MeasurementCatalog.pipeInstallations.contains(installationCode) ||
      (MeasurementCatalog.optionalPipeInstallations.contains(
            installationCode,
          ) &&
          pipesUsed);

  @override
  bool operator ==(Object other) =>
      other is MeasurementDiagramData &&
      other.installationCode == installationCode &&
      other.unit == unit &&
      other.boardW == boardW &&
      other.boardH == boardH &&
      other.pipesUsed == pipesUsed &&
      _mapEq(other.values, values) &&
      _mapEq(other.counts, counts);

  static bool _mapEq(Map<String, double> a, Map<String, double> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    installationCode,
    unit,
    boardW,
    boardH,
    pipesUsed,
    values.length,
    counts.length,
  );
}

/// Schematic elevation: ground level, board outline, width / height
/// arrows, bottom / top mounting heights, poles + spacing, support pipes,
/// standee base, available wall / glass area and clearances.
class MeasurementDiagramPainter extends CustomPainter {
  MeasurementDiagramPainter(this.data);

  final MeasurementDiagramData data;

  static const _ink = Color(0xFF1D1D1F);
  static const _red = Color(0xFFD71920);
  static const _blue = Color(0xFF1A73E8);
  static const _muted = Color(0xFF6B6F76);
  static const _ground = Color(0xFF8D6E63);

  String _len(double? mm, String what) =>
      mm == null ? '$what: not measured' : fmtMm(mm, data.unit);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final d = data;
    // ---- World layout (mm, y up from ground). Unmeasured values get a
    // neutral sketch position only.
    final standeePanelW = d.isStandee ? d.v('panel_width') : null;
    final standeePanelH = d.isStandee ? d.v('panel_height') : null;
    final bw = standeePanelW ?? d.boardW ?? 2400.0;
    final bh = standeePanelH ?? d.boardH ?? 900.0;
    final measuredBottom = d.v('bottom_height');
    final overall = d.isStandee ? d.v('standee_overall_height') : null;
    final poleAbove = d.isPole ? d.v('pole_above_ground') : null;
    final bottom =
        measuredBottom ??
        (overall != null && overall > bh
            ? overall - bh
            : (poleAbove != null && poleAbove > bh
                  ? poleAbove - bh
                  : (d.isStandee ? bh * 0.4 : bh * 1.6)));
    final measuredTop = d.v('top_height');
    final top = bottom + bh;
    final left = -bw / 2, right = bw / 2;

    // Available area (wall or glass).
    final areaW = d.isGlass ? d.v('glass_width') : d.v('wall_width');
    final areaH = d.isGlass ? d.v('glass_height') : d.v('wall_height');
    final cl = d.v('clear_left'), cr = d.v('clear_right');
    final ct = d.v('clear_top'), cb = d.v('clear_bottom');
    Rect? area;
    if (areaW != null || areaH != null) {
      final aw = areaW ?? bw + (cl ?? 0) + (cr ?? 0);
      final ah = areaH ?? bh + (ct ?? 0) + (cb ?? 0);
      final aLeft = cl != null ? left - cl : -aw / 2;
      final aBottom = cb != null ? bottom - cb : bottom - (ah - bh) / 2;
      area = Rect.fromLTWH(aLeft, aBottom, aw, ah);
    }

    final embed = d.isPole ? d.v('pole_embedment') : null;
    final spacing = d.isDoublePole ? d.v('pole_spacing') : null;
    final poleXs = d.isPole
        ? (d.isDoublePole
              ? [-(spacing ?? bw * 0.7) / 2, (spacing ?? bw * 0.7) / 2]
              : [0.0])
        : <double>[];
    final poleTop = poleAbove ?? top;

    final baseW = d.isStandee ? d.v('base_width') : null;

    var minX = math.min(left, area?.left ?? left);
    var maxX = math.max(right, area?.right ?? right);
    for (final x in poleXs) {
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
    }
    if (baseW != null) {
      minX = math.min(minX, -baseW / 2);
      maxX = math.max(maxX, baseW / 2);
    }
    final minY = -(embed ?? 0) - bh * 0.05;
    final maxY = [
      top,
      area?.bottom ?? 0, // Rect in world: bottom = top in y-up terms
      area?.top ?? 0,
      poleTop,
      measuredTop ?? 0,
      overall ?? 0,
    ].reduce(math.max);
    final worldW = math.max(maxX - minX, 1.0);
    final worldH = math.max(maxY - minY, 1.0);

    const padL = 64.0, padR = 56.0, padT = 34.0, padB = 30.0;
    final avail = Size(
      math.max(size.width - padL - padR, 10),
      math.max(size.height - padT - padB, 10),
    );
    final k = math.min(avail.width / worldW, avail.height / worldH);
    final ox = padL + (avail.width - worldW * k) / 2;
    final oy = padT + (avail.height - worldH * k) / 2;
    Offset p(double x, double y) =>
        Offset(ox + (x - minX) * k, oy + (maxY - y) * k);

    final groundY = p(0, 0).dy;

    // ---- Available area
    if (area != null) {
      final r = Rect.fromPoints(
        p(area.left, area.top),
        p(area.right, area.bottom),
      );
      canvas.drawRect(r, Paint()..color = _blue.withValues(alpha: 0.06));
      _dashedRect(canvas, r, _blue);
      _text(
        canvas,
        '${d.isGlass ? 'Glass' : 'Wall'} ${_len(areaW, 'W')} × ${_len(areaH, 'H')}',
        r.topLeft + const Offset(4, 3),
        _blue,
        size: 10,
        align: TextAlign.left,
      );
    }

    // ---- Ground
    canvas.drawLine(
      Offset(4, groundY),
      Offset(size.width - 4, groundY),
      Paint()
        ..color = _ground
        ..strokeWidth = 2,
    );
    for (var x = 8.0; x < size.width - 8; x += 12) {
      canvas.drawLine(
        Offset(x, groundY),
        Offset(x - 6, groundY + 6),
        Paint()
          ..color = _ground.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
    }
    _text(
      canvas,
      'Ground level',
      Offset(size.width - 6, groundY + 4),
      _ground,
      size: 10,
      align: TextAlign.right,
    );

    // ---- Poles
    final polePaint = Paint()
      ..color = const Color(0xFF546E7A)
      ..strokeWidth = math.max(3, 60 * k);
    for (final x in poleXs) {
      canvas.drawLine(p(x, 0), p(x, poleTop), polePaint);
      if (embed != null && embed > 0) {
        _dashedLine(canvas, p(x, 0), p(x, -embed), const Color(0xFF546E7A));
      }
    }
    if (d.isPole) {
      final x = poleXs.last;
      if (embed != null && embed > 0) {
        _dimV(
          canvas,
          p(x, 0),
          p(x, -embed),
          22,
          'Embed ${fmtMm(embed, d.unit)}',
        );
      }
      if (d.isDoublePole) {
        _dimH(
          canvas,
          p(poleXs.first, 0),
          p(poleXs.last, 0),
          -16,
          spacing == null
              ? 'Pole spacing: not measured'
              : 'Spacing ${fmtMm(spacing, d.unit)}',
          color: spacing == null ? _muted : _ink,
        );
      }
      if (poleAbove != null) {
        _dimV(
          canvas,
          p(poleXs.first, 0),
          p(poleXs.first, poleAbove),
          -18,
          'Pole ${fmtMm(poleAbove, d.unit)}',
        );
      }
    }

    // ---- Standee base + posts
    if (d.isStandee) {
      final bwBase = baseW ?? bw * 0.8;
      final baseH = math.max(bh * 0.06, 40.0);
      final r = Rect.fromPoints(p(-bwBase / 2, baseH), p(bwBase / 2, 0));
      canvas.drawRect(r, Paint()..color = const Color(0xFF5D4037));
      canvas.drawLine(
        p(-bw * 0.35, baseH),
        p(-bw * 0.35, bottom),
        polePaint..strokeWidth = math.max(2, 40 * k),
      );
      canvas.drawLine(p(bw * 0.35, baseH), p(bw * 0.35, bottom), polePaint);
      final depth = d.v('base_depth');
      _text(
        canvas,
        'Base ${_len(baseW, 'W')} × ${_len(depth, 'D')}',
        Offset(r.center.dx, groundY + 14),
        _ink,
        size: 10,
      );
    }

    // ---- Support pipes
    if (d.showsPipes) {
      final n = (d.counts['pipe_count'] ?? 2).clamp(1, 8).toInt();
      final ps = d.v('pipe_spacing');
      final gap = n <= 1 ? 0.0 : (ps ?? bw * 0.8 / (n - 1));
      final start = -gap * (n - 1) / 2;
      final pipeLen = d.v('pipe_length');
      final pipeBottom = math.max(0.0, bottom - (pipeLen ?? bh) * 0.5);
      for (var i = 0; i < n; i++) {
        final x = start + gap * i;
        canvas.drawLine(
          p(x, pipeBottom),
          p(x, top + bh * 0.15),
          Paint()
            ..color = const Color(0xFF78909C)
            ..strokeWidth = math.max(2, 35 * k),
        );
      }
      final mount = d.v('pipe_mount_height');
      _text(
        canvas,
        'Pipes: ${d.counts['pipe_count']?.toInt() ?? '?'} × '
        '${_len(pipeLen, 'L')}'
        '${ps == null ? '' : ', gap ${fmtMm(ps, d.unit)}'}'
        '${mount == null ? '' : ', mount ${fmtMm(mount, d.unit)}'}',
        p(0, top + bh * 0.15) - const Offset(0, 12),
        const Color(0xFF455A64),
        size: 10,
      );
    }

    // ---- Board
    final board = Rect.fromPoints(p(left, top), p(right, bottom));
    canvas.drawRect(board, Paint()..color = _red.withValues(alpha: 0.85));
    canvas.drawRect(
      board,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFA50F15),
    );
    _text(
      canvas,
      d.isStandee ? 'Display panel' : 'Board',
      board.center,
      Colors.white,
      size: 11,
    );

    // Width (above) / height (right side) arrows.
    final wv = standeePanelW ?? d.boardW;
    final hv = standeePanelH ?? d.boardH;
    _dimH(
      canvas,
      board.topLeft,
      board.topRight,
      -12,
      wv == null ? 'Width: not set' : 'W ${fmtMm(wv, d.unit)}',
      color: wv == null ? _muted : _ink,
    );
    _dimV(
      canvas,
      board.bottomRight,
      board.topRight,
      16,
      hv == null ? 'H: not set' : 'H ${fmtMm(hv, d.unit)}',
      color: hv == null ? _muted : _ink,
    );

    // Bottom / top mounting heights (left of the board).
    final xBottom = board.left - 14;
    _dimV(
      canvas,
      Offset(xBottom, groundY),
      Offset(xBottom, board.bottom),
      0,
      measuredBottom == null
          ? 'Bottom: not measured'
          : 'Bottom ${fmtMm(measuredBottom, d.unit)}',
      color: measuredBottom == null ? _muted : _red,
      labelLeft: true,
    );
    if (measuredTop != null) {
      final ty = p(0, measuredTop).dy;
      final xTop = math.max(10.0, board.left - 40);
      _dimV(
        canvas,
        Offset(xTop, groundY),
        Offset(xTop, ty),
        0,
        'Top ${fmtMm(measuredTop, d.unit)}',
        color: _blue,
        labelLeft: true,
      );
    }
    if (overall != null) {
      final xo = math.min(size.width - 10, board.right + 44);
      _dimV(
        canvas,
        Offset(xo, groundY),
        Offset(xo, p(0, overall).dy),
        0,
        'Overall ${fmtMm(overall, d.unit)}',
        color: _blue,
      );
    }

    // Clearances.
    if (area != null) {
      final cy = board.center.dy;
      final ar = Rect.fromPoints(
        p(area.left, area.top),
        p(area.right, area.bottom),
      );
      if (cl != null && cl > 0) {
        _dimH(
          canvas,
          Offset(ar.left, cy),
          Offset(board.left, cy),
          0,
          'L ${fmtMm(cl, d.unit)}',
          color: _blue,
        );
      }
      if (cr != null && cr > 0) {
        _dimH(
          canvas,
          Offset(board.right, cy),
          Offset(ar.right, cy),
          0,
          'R ${fmtMm(cr, d.unit)}',
          color: _blue,
        );
      }
      final cx = board.center.dx + board.width * 0.25;
      if (ct != null && ct > 0) {
        _dimV(
          canvas,
          Offset(cx, board.top),
          Offset(cx, ar.top),
          0,
          'T ${fmtMm(ct, d.unit)}',
          color: _blue,
        );
      }
      if (cb != null && cb > 0) {
        _dimV(
          canvas,
          Offset(cx, ar.bottom),
          Offset(cx, board.bottom),
          0,
          'B ${fmtMm(cb, d.unit)}',
          color: _blue,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------

  void _arrowHead(Canvas c, Offset tip, Offset from, Color color) {
    final d = tip - from;
    if (d.distance < 0.5) return;
    final dir = d / d.distance;
    final n = Offset(-dir.dy, dir.dx);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - dir.dx * 7 + n.dx * 3.5,
        tip.dy - dir.dy * 7 + n.dy * 3.5,
      )
      ..lineTo(
        tip.dx - dir.dx * 7 - n.dx * 3.5,
        tip.dy - dir.dy * 7 - n.dy * 3.5,
      )
      ..close();
    c.drawPath(path, Paint()..color = color);
  }

  void _dimH(
    Canvas c,
    Offset a,
    Offset b,
    double offsetY,
    String label, {
    Color color = _ink,
  }) {
    final y = a.dy + offsetY;
    final pa = Offset(a.dx, y), pb = Offset(b.dx, y);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    c.drawLine(pa, pb, paint);
    _arrowHead(c, pa, pb, color);
    _arrowHead(c, pb, pa, color);
    _text(
      c,
      label,
      Offset((pa.dx + pb.dx) / 2, y - 8),
      color,
      size: 10.5,
      background: true,
    );
  }

  void _dimV(
    Canvas c,
    Offset a,
    Offset b,
    double offsetX,
    String label, {
    Color color = _ink,
    bool labelLeft = false,
  }) {
    final x = a.dx + offsetX;
    final pa = Offset(x, a.dy), pb = Offset(x, b.dy);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    c.drawLine(pa, pb, paint);
    _arrowHead(c, pa, pb, color);
    _arrowHead(c, pb, pa, color);
    _text(
      c,
      label,
      Offset(x + (labelLeft ? -4 : 4), (pa.dy + pb.dy) / 2),
      color,
      size: 10,
      align: labelLeft ? TextAlign.right : TextAlign.left,
      background: true,
    );
  }

  void _dashedLine(Canvas c, Offset a, Offset b, Color color) {
    final d = b - a;
    final len = d.distance;
    if (len < 1) return;
    final dir = d / len;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (var t = 0.0; t < len; t += 8) {
      c.drawLine(a + dir * t, a + dir * math.min(t + 4, len), paint);
    }
  }

  void _dashedRect(Canvas c, Rect r, Color color) {
    _dashedLine(c, r.topLeft, r.topRight, color);
    _dashedLine(c, r.topRight, r.bottomRight, color);
    _dashedLine(c, r.bottomRight, r.bottomLeft, color);
    _dashedLine(c, r.bottomLeft, r.topLeft, color);
  }

  void _text(
    Canvas c,
    String text,
    Offset at,
    Color color, {
    double size = 11,
    TextAlign align = TextAlign.center,
    bool background = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final dx = switch (align) {
      TextAlign.left => at.dx,
      TextAlign.right => at.dx - tp.width,
      _ => at.dx - tp.width / 2,
    };
    final o = Offset(dx, at.dy - tp.height / 2);
    if (background) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(o.dx - 2, o.dy - 1, tp.width + 4, tp.height + 2),
          const Radius.circular(3),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(covariant MeasurementDiagramPainter old) =>
      old.data != data;
}
