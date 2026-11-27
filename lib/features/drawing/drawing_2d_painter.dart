import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import 'signage_geometry.dart';

/// Text shown in the drawing's title block and notes column.
class DrawingInfo {
  const DrawingInfo({
    required this.projectName,
    required this.shopName,
    required this.shopAddress,
    required this.boardName,
    required this.drawnBy,
    required this.date,
    this.statusLabel = '',
    this.notes = const [],
    this.summaryTitle = 'SITE DETAILS SUMMARY',
  });

  /// Heading of the notes column (Tamil in Tamil mode).
  final String summaryTitle;

  final String projectName;
  final String shopName;
  final String shopAddress;
  final String boardName;
  final String drawnBy;
  final String date;
  final String statusLabel;
  final List<String> notes;
}

/// Maps feet to sheet pixels inside one elevation viewport (y up).
class _Frame {
  factory _Frame(
    Rect region,
    double x0,
    double x1,
    double y0,
    double y1,
    EdgeInsets pad,
  ) {
    final avail = pad.deflateRect(region);
    final ew = math.max(x1 - x0, 0.1), eh = math.max(y1 - y0, 0.1);
    final s = math.min(avail.width / ew, avail.height / eh);
    return _Frame._(
      s,
      avail.left + (avail.width - ew * s) / 2 - x0 * s,
      avail.top + (avail.height - eh * s) / 2 + y1 * s,
    );
  }

  _Frame._(this.s, this.ox, this.gy);

  /// Pixels per foot.
  final double s;
  final double ox;

  /// Screen y of ground level (y = 0 ft).
  final double gy;

  Offset p(double x, double y) => Offset(ox + x * s, gy - y * s);
  double x(double ft) => ox + ft * s;
  double y(double ft) => gy - ft * s;

  Rect r(double xa, double ya, double xb, double yb) =>
      Rect.fromPoints(p(xa, ya), p(xb, yb));
}

/// Auto-generated technical drawing (front + side elevation, title block and
/// site notes) on a fixed 1400 × 990 logical sheet.
class Drawing2DPainter extends CustomPainter {
  Drawing2DPainter({required this.geo, required this.info, this.brand = ''});

  static const sheet = Size(1400, 990);

  final SignageGeometry geo;
  final DrawingInfo info;
  final String brand;

  static const _ink = AdinnColors.ink;
  static const _muted = AdinnColors.muted;
  static const _red = AdinnColors.red;
  static const _structure = Color(0xFF6B7078);
  static const _wallFill = Color(0xFFF4EDE1);
  static const _buildingFill = Color(0xFFEDE6DA);
  static const _shutterFill = Color(0xFFD4D8DD);
  static const _glassFill = Color(0xFFCFE3F1);
  static const _concrete = Color(0xFFCFCBC3);

  static const _frontRect = Rect.fromLTRB(36, 70, 896, 706);
  static const _sideRect = Rect.fromLTRB(912, 70, 1364, 706);
  static const _titleRect = Rect.fromLTRB(36, 722, 896, 960);
  static const _notesRect = Rect.fromLTRB(912, 722, 1364, 960);

  String get _brand {
    final b = brand.trim().isEmpty ? info.projectName : brand;
    return b.trim().isEmpty ? 'ADINN' : b.trim().toUpperCase();
  }

  String _len(double ft) => fmtLength(ft, geo.unit);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / sheet.width, size.height / sheet.height);
    canvas.drawRect(Offset.zero & sheet, Paint()..color = Colors.white);
    _paintSheetFrame(canvas);
    canvas.save();
    canvas.clipRect(_frontRect);
    if (geo.isFlangeBracket) {
      _paintFlangeFront(canvas);
    } else {
      _paintFront(canvas);
    }
    canvas.restore();
    canvas.save();
    canvas.clipRect(_sideRect);
    if (geo.isFlangeBracket) {
      _paintFlangeSide(canvas);
    } else {
      _paintSide(canvas);
    }
    canvas.restore();
    _caption(canvas, _frontRect, 'FRONT ELEVATION');
    _caption(
      canvas,
      _sideRect,
      geo.isFlangeBracket ? 'SIDE ELEVATION (FROM STREET)' : 'SIDE ELEVATION',
    );
    _paintTitleBlock(canvas);
    _paintNotes(canvas);
    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // Sheet
  // ---------------------------------------------------------------------------

  void _paintSheetFrame(Canvas canvas) {
    final thick = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final thin = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(const Rect.fromLTWH(14, 14, 1372, 962), thick);
    canvas.drawRect(const Rect.fromLTWH(20, 20, 1360, 950), thin);
    _text(
      canvas,
      'ADINN · SIGNAGE RECCE',
      const Offset(36, 30),
      size: 18,
      color: _red,
      weight: FontWeight.w900,
    );
    _text(
      canvas,
      'DEFAULT 2D DRAWING – ${info.boardName.toUpperCase()}',
      const Offset(700, 32),
      size: 15,
      weight: FontWeight.w800,
      align: Alignment.topCenter,
      maxWidth: 520,
    );
    _text(
      canvas,
      'Dimensions in ${geo.unit.label} · Not to scale',
      const Offset(1364, 34),
      size: 12,
      color: _muted,
      align: Alignment.topRight,
    );
    canvas.drawLine(const Offset(20, 62), const Offset(1380, 62), thin);
    canvas.drawLine(const Offset(904, 62), const Offset(904, 712), thin);
    canvas.drawLine(const Offset(20, 712), const Offset(1380, 712), thin);
    canvas.drawLine(const Offset(904, 712), const Offset(904, 970), thin);
  }

  void _caption(Canvas canvas, Rect region, String text) {
    final c = Offset(region.center.dx, region.bottom - 26);
    final w = _text(
      canvas,
      text,
      c,
      size: 14,
      weight: FontWeight.w800,
      align: Alignment.topCenter,
    );
    canvas.drawLine(
      Offset(c.dx - w / 2, c.dy + 19),
      Offset(c.dx + w / 2, c.dy + 19),
      Paint()
        ..color = _ink
        ..strokeWidth = 1.2,
    );
  }

  // ---------------------------------------------------------------------------
  // Front elevation (board facing the viewer)
  // ---------------------------------------------------------------------------

  double get _wallTop => math.max(geo.topFt + 3, 10);

  /// Half width of the structure behind / around the board.
  double get _structureHalf {
    final w = geo.widthFt;
    return switch (geo.installationCode) {
      SignageCatalog.doublePole => math.max(w / 2, geo.poleGapFt / 2 + 0.7),
      SignageCatalog.singlePole => math.max(w / 2, 0.9),
      SignageCatalog.wallMount => w / 2 + 4,
      SignageCatalog.shopFascia => w / 2 + 2,
      SignageCatalog.rooftop => w / 2 + 4,
      SignageCatalog.directWall => w / 2 + 3,
      SignageCatalog.glassPasting => w / 2 + 1.5,
      SignageCatalog.freeStanding => math.max(w / 2 + 0.25, _standeeBaseW / 2),
      _ => w / 2,
    };
  }

  double get _structureTop => switch (geo.installationCode) {
    SignageCatalog.wallMount => _wallTop,
    SignageCatalog.shopFascia => geo.topFt + 2.5,
    SignageCatalog.directWall => math.max(geo.topFt + 2, 10),
    SignageCatalog.glassPasting => _wallTop,
    SignageCatalog.rooftop => math.max(geo.topFt, geo.buildingHeightFt + 1),
    _ => geo.topFt,
  };

  void _paintFront(Canvas canvas) {
    final w = geo.widthFt, b = geo.bottomFt, t = geo.topFt;
    final half = _structureHalf;
    final humanX = half + 2.5;
    final below = geo.isPoleMounted ? geo.foundationDepthFt : 0.6;
    final f = _Frame(
      _frontRect,
      -half,
      humanX + 0.8,
      -below,
      math.max(_structureTop, 5.5),
      const EdgeInsets.fromLTRB(96, 64, 128, 76),
    );

    _ground(canvas, f, _frontRect);
    _paintFrontStructure(canvas, f);
    if (geo.isSurfaceArtwork) {
      _artworkFace(canvas, f.r(-w / 2, b, w / 2, t));
    } else {
      _boardFace(canvas, f.r(-w / 2, b, w / 2, t));
    }
    _human(canvas, f, humanX);

    // Dimensions
    final boardRect = f.r(-w / 2, b, w / 2, t);
    final structTopPx = f.y(_structureTop);
    final widthLineY = math.min(boardRect.top, structTopPx) - 26;
    _dimH(
      canvas,
      boardRect.topLeft,
      boardRect.topRight,
      widthLineY,
      'W ${_len(w)}',
    );
    final hx = boardRect.right + 28;
    _dimV(
      canvas,
      boardRect.topRight,
      boardRect.bottomRight,
      hx,
      'H ${_len(geo.heightFt)}',
    );
    final base = geo.baseLevelFt;
    if (b - base > 0.05) {
      final clx = math.min(boardRect.left, f.x(-half)) - 30;
      _dimV(
        canvas,
        f.p(-w / 2, base),
        boardRect.bottomLeft,
        clx,
        'Clr ${_len(b - base)}',
      );
    }
    final overallX = math.max(hx + 36, f.x(half) + 26);
    _dimV(canvas, f.p(half, 0), f.p(w / 2, t), overallX, 'Overall ${_len(t)}');
    if (geo.installationCode == SignageCatalog.rooftop) {
      final bx = f.x(-half) - 62;
      _dimV(
        canvas,
        f.p(-half, 0),
        f.p(-half, geo.buildingHeightFt),
        bx,
        'Bldg ${_len(geo.buildingHeightFt)}',
      );
    }
    if (geo.installationCode == SignageCatalog.doublePole) {
      final gap = geo.poleGapFt;
      _dimH(
        canvas,
        f.p(-gap / 2, b),
        f.p(gap / 2, b),
        boardRect.bottom + 26,
        'Pole c/c ${_len(gap)}',
        fromBelow: true,
      );
    }
  }

  double get _standeeBaseW =>
      geo.baseWidthFt > 0 ? geo.baseWidthFt : math.max(1.5, geo.widthFt * 0.7);

  double get _standeeBaseD => geo.baseDepthFt > 0 ? geo.baseDepthFt : 1.5;

  void _paintFrontStructure(Canvas canvas, _Frame f) {
    final w = geo.widthFt, b = geo.bottomFt, t = geo.topFt;
    final half = _structureHalf;
    switch (geo.installationCode) {
      case SignageCatalog.freeStanding:
        final bw = _standeeBaseW;
        _fillStroke(
          canvas,
          f.r(-bw / 2, 0, bw / 2, 0.2),
          _concrete,
          _structure,
        );
        if (geo.supportType == 'Single centre pole') {
          _pole(canvas, f, 0, 0.14, geo.doubleSided ? b : t - 0.2);
        } else {
          for (final x in [-w / 2 - 0.08, w / 2 + 0.08]) {
            _fillStroke(
              canvas,
              f.r(x - 0.08, 0.2, x + 0.08, t),
              _structure,
              _structure,
            );
          }
        }
      case SignageCatalog.doublePole:
        for (final x in [-geo.poleGapFt / 2, geo.poleGapFt / 2]) {
          _pole(canvas, f, x, 0.22, t);
          _footing(canvas, f, x, 0.7);
        }
        for (final y in [b + 0.3, t - 0.3]) {
          _fillStroke(
            canvas,
            f.r(-geo.poleGapFt / 2, y - 0.08, geo.poleGapFt / 2, y + 0.08),
            _structure,
            _structure,
          );
        }
      case SignageCatalog.singlePole:
        _pole(canvas, f, 0, 0.3, t - 0.15);
        _footing(canvas, f, 0, 0.9);
      case SignageCatalog.wallMount:
        _wall(canvas, f, f.r(-half, 0, half, _wallTop));
      case SignageCatalog.directWall:
        _wall(canvas, f, f.r(-half, 0, half, math.max(t + 2, 10)));
      case SignageCatalog.shopFascia:
        _fillStroke(
          canvas,
          f.r(-half, 0, half, t + 2.5),
          _buildingFill,
          _structure,
        );
        final shutterTop = math.max(0.5, b - 0.5);
        _shutters(canvas, f, -half + 0.5, half - 0.5, shutterTop);
        _fillStroke(
          canvas,
          f.r(-half - 0.3, shutterTop, half + 0.3, shutterTop + 0.2),
          _concrete,
          _structure,
        );
      case SignageCatalog.rooftop:
        final hb = geo.buildingHeightFt;
        _fillStroke(canvas, f.r(-half, 0, half, hb), _buildingFill, _structure);
        final floors = (hb / 10).round();
        final line = Paint()
          ..color = _structure.withValues(alpha: 0.5)
          ..strokeWidth = 1;
        for (var i = 1; i < floors; i++) {
          canvas.drawLine(f.p(-half, i * 10.0), f.p(half, i * 10.0), line);
        }
        for (var i = 1; i < floors; i++) {
          for (var x = -half + 2; x + 3 <= half - 1; x += 5) {
            _fillStroke(
              canvas,
              f.r(x, i * 10.0 + 3, x + 3, i * 10.0 + 7),
              _glassFill,
              _structure,
            );
          }
        }
        _shutters(canvas, f, -half + 1, half - 1, math.min(8, hb - 1));
        _fillStroke(
          canvas,
          f.r(-half, hb, half, hb + 1),
          _concrete,
          _structure,
        );
        final legs = math.max(2, (w / 8).ceil() + 1);
        for (var i = 0; i < legs; i++) {
          final x = -w / 2 + 0.4 + (w - 0.8) * i / (legs - 1);
          _fillStroke(
            canvas,
            f.r(x - 0.12, hb, x + 0.12, t),
            _structure,
            _structure,
          );
        }
        _fillStroke(
          canvas,
          f.r(-w / 2 + 0.2, b - 0.1, w / 2 - 0.2, b + 0.1),
          _structure,
          _structure,
        );
      case SignageCatalog.glassPasting:
        _fillStroke(
          canvas,
          f.r(-half, 0, half, _wallTop),
          _buildingFill,
          _structure,
        );
        final gy0 = math.max(0.0, b - 0.5);
        _fillStroke(
          canvas,
          f.r(-w / 2 - 0.5, gy0, w / 2 + 0.5, t + 0.5),
          _glassFill,
          _structure,
        );
        final mull = Paint()
          ..color = _ink
          ..strokeWidth = 2;
        for (var i = 0; i <= geo.panelCount; i++) {
          final x = -w / 2 - 0.5 + (w + 1) * i / geo.panelCount;
          canvas.drawLine(f.p(x, gy0), f.p(x, t + 0.5), mull);
        }
    }
  }

  // ---------------------------------------------------------------------------
  // Side elevation (profile, street to the right)
  // ---------------------------------------------------------------------------

  void _paintSide(Canvas canvas) {
    final d = geo.depthFt, b = geo.bottomFt, t = geo.topFt;
    final inst = geo.installationCode;
    final zp = inst == SignageCatalog.singlePole ? -d - 0.4 : -d - 0.3;
    final stay = math.max(2.0, geo.heightFt * 0.6);

    final (zMin, zMax) = switch (inst) {
      SignageCatalog.doublePole || SignageCatalog.singlePole => (zp - 1.2, 1.5),
      SignageCatalog.wallMount => (-d - 2.5, 2.0),
      SignageCatalog.shopFascia => (-d - 8, 2.5),
      SignageCatalog.rooftop => (-d - 0.2 - stay - 3, 3.0),
      _ => (-4.0, 2.0),
    };
    final below = geo.isPoleMounted ? geo.foundationDepthFt : 0.6;
    final f = _Frame(
      _sideRect,
      zMin,
      zMax,
      -below,
      math.max(_structureTop, geo.topFt),
      const EdgeInsets.fromLTRB(40, 64, 118, 76),
    );
    _ground(canvas, f, _sideRect);

    switch (inst) {
      case SignageCatalog.freeStanding:
        final bd = _standeeBaseD;
        _fillStroke(
          canvas,
          f.r(-d / 2 - bd / 2, 0, -d / 2 + bd / 2, 0.2),
          _concrete,
          _structure,
        );
        _fillStroke(
          canvas,
          f.r(-d / 2 - 0.08, 0.2, -d / 2 + 0.08, t),
          _structure,
          _structure,
        );
      case SignageCatalog.doublePole:
      case SignageCatalog.singlePole:
        final r = inst == SignageCatalog.singlePole ? 0.3 : 0.22;
        _pole(
          canvas,
          f,
          zp,
          r,
          inst == SignageCatalog.singlePole ? t - 0.15 : t,
        );
        _footing(canvas, f, zp, inst == SignageCatalog.singlePole ? 0.9 : 0.7);
        for (final y in [b + 0.3, t - 0.3]) {
          _fillStroke(
            canvas,
            f.r(zp, y - 0.08, -d, y + 0.08),
            _structure,
            _structure,
          );
        }
        _dimV(
          canvas,
          f.p(zp - 0.7, 0),
          f.p(zp - 0.7, -geo.foundationDepthFt),
          f.x(zp - 0.7) - 20,
          'Fdn ${_len(geo.foundationDepthFt)}',
        );
      case SignageCatalog.wallMount:
        _wall(canvas, f, f.r(-d - 0.75, 0, -d, _wallTop));
      case SignageCatalog.directWall:
      case SignageCatalog.glassPasting:
        _wall(canvas, f, f.r(-0.75, 0, 0, _structureTop));
      case SignageCatalog.shopFascia:
        _fillStroke(
          canvas,
          f.r(-d - 8, 0, -d, t + 2.5),
          _buildingFill,
          _structure,
        );
        _breakLine(canvas, f.p(-d - 8, 0), f.p(-d - 8, t + 2.5));
        final shutterTop = math.max(0.5, b - 0.5);
        _fillStroke(
          canvas,
          f.r(-d, shutterTop, -d + 1.5, shutterTop + 0.2),
          _concrete,
          _structure,
        );
      case SignageCatalog.rooftop:
        final hb = geo.buildingHeightFt;
        final zf = -d - 0.2;
        final back = zf - stay - 3;
        _fillStroke(canvas, f.r(back, 0, 2, hb), _buildingFill, _structure);
        _breakLine(canvas, f.p(back, 0), f.p(back, hb));
        _fillStroke(canvas, f.r(1.5, hb, 2, hb + 1), _concrete, _structure);
        _fillStroke(
          canvas,
          f.r(zf - 0.12, hb, zf + 0.12, t),
          _structure,
          _structure,
        );
        canvas.drawLine(
          f.p(zf, t - 0.3),
          f.p(zf - stay, hb),
          Paint()
            ..color = _structure
            ..strokeWidth = math.max(2, 0.18 * f.s),
        );
    }

    // Board profile
    final boardRect = geo.isSurfaceArtwork
        ? Rect.fromLTRB(f.x(0) - 1.5, f.y(t), f.x(0) + 1.5, f.y(b))
        : f.r(-d, b, 0, t);
    _fillStroke(canvas, boardRect, _mediaFill, _mediaStroke, width: 1.5);

    if (!geo.isSurfaceArtwork) {
      _dimH(
        canvas,
        boardRect.topLeft,
        boardRect.topRight,
        math.min(boardRect.top, f.y(_structureTop)) - 26,
        'D ${_len(d)}',
      );
    }
    final cx = math.max(boardRect.right, f.x(zMax - 1.0)) + 26;
    _dimV(
      canvas,
      boardRect.topRight,
      boardRect.bottomRight,
      cx,
      'H ${_len(geo.heightFt)}',
    );
    final base = geo.baseLevelFt;
    if (b - base > 0.05) {
      _dimV(
        canvas,
        f.p(0, base),
        boardRect.bottomRight,
        cx,
        'Clr ${_len(b - base)}',
      );
    }
    _text(
      canvas,
      'STREET →',
      Offset(_sideRect.right - 12, f.gy + 12),
      size: 10,
      color: _muted,
      weight: FontWeight.w700,
      align: Alignment.topRight,
    );
  }

  // ---------------------------------------------------------------------------
  // Flange (projecting) board
  // ---------------------------------------------------------------------------

  void _paintFlangeFront(Canvas canvas) {
    final w = geo.widthFt, b = geo.bottomFt, t = geo.topFt;
    final p = geo.projectionFt;
    final humanX = p + w + 2.5;
    final f = _Frame(
      _frontRect,
      -1.5,
      humanX + 0.8,
      -0.6,
      math.max(_wallTop, 5.5),
      const EdgeInsets.fromLTRB(40, 64, 128, 76),
    );
    _ground(canvas, f, _frontRect);
    _wall(canvas, f, f.r(-0.75, 0, 0, _wallTop));
    final steel = Paint()
      ..color = _structure
      ..strokeWidth = math.max(2.5, 0.15 * f.s)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(f.p(0, t + 0.15), f.p(p + w, t + 0.15), steel);
    canvas.drawLine(f.p(0, t + 1.5), f.p(p + w * 0.7, t + 0.15), steel);
    canvas.drawLine(f.p(0, b - 0.15), f.p(p + 0.6, b - 0.15), steel);
    final boardRect = f.r(p, b, p + w, t);
    _boardFace(canvas, boardRect);
    _human(canvas, f, humanX);

    _dimH(
      canvas,
      boardRect.topLeft,
      boardRect.topRight,
      f.y(t + 1.5) - 26,
      'W ${_len(w)}',
    );
    final hx = boardRect.right + 28;
    _dimV(
      canvas,
      boardRect.topRight,
      boardRect.bottomRight,
      hx,
      'H ${_len(geo.heightFt)}',
    );
    if (b > 0.05) {
      _dimV(canvas, f.p(p + w, 0), boardRect.bottomRight, hx, 'Clr ${_len(b)}');
    }
    if (p > 0.05) {
      _dimH(
        canvas,
        f.p(0, b),
        f.p(p, b),
        boardRect.bottom + 26,
        'Proj ${_len(p)}',
        fromBelow: true,
      );
    }
    _dimV(canvas, f.p(p + w, 0), f.p(p + w, t), hx + 40, 'Overall ${_len(t)}');
  }

  void _paintFlangeSide(Canvas canvas) {
    final d = geo.depthFt, b = geo.bottomFt, t = geo.topFt;
    final half = 6 + geo.widthFt * 0.3;
    final f = _Frame(
      _sideRect,
      -half,
      half,
      -0.6,
      _wallTop,
      const EdgeInsets.fromLTRB(30, 64, 100, 76),
    );
    _ground(canvas, f, _sideRect);
    _wall(canvas, f, f.r(-half, 0, half, _wallTop));
    final boardRect = f.r(-d / 2, b, d / 2, t);
    _fillStroke(canvas, boardRect, _mediaFill, _mediaStroke, width: 1.5);
    _fillStroke(
      canvas,
      f.r(-0.08, t + 0.08, 0.08, t + 0.22),
      _structure,
      _structure,
    );
    _dimH(
      canvas,
      boardRect.topLeft,
      boardRect.topRight,
      boardRect.top - 26,
      'T ${_len(d)}',
    );
    final x = boardRect.right + 40;
    _dimV(
      canvas,
      boardRect.topRight,
      boardRect.bottomRight,
      x,
      'H ${_len(geo.heightFt)}',
    );
    if (b > 0.05) {
      _dimV(canvas, f.p(d / 2, 0), boardRect.bottomRight, x, 'Clr ${_len(b)}');
    }
  }

  // ---------------------------------------------------------------------------
  // Building blocks
  // ---------------------------------------------------------------------------

  Color get _mediaFill => switch (geo.mediaCode) {
    SignageCatalog.gsb || SignageCatalog.flange => _red,
    SignageCatalog.nlb => Colors.white,
    SignageCatalog.acp => switch (geo.acpColour) {
      'Brand red' => _red,
      'White' => Colors.white,
      'Black' => const Color(0xFF2B2B2B),
      _ => const Color(0xFFC0C4C8),
    },
    SignageCatalog.vinyl => const Color(0xD900897B),
    _ => const Color(0xD9D71920),
  };

  Color get _mediaStroke =>
      geo.mediaCode == SignageCatalog.nlb ? _red : AdinnColors.redDark;

  void _boardFace(Canvas canvas, Rect r) {
    final fill = _mediaFill;
    canvas.drawRect(r, Paint()..color = fill);
    if (geo.mediaCode == SignageCatalog.gsb ||
        geo.mediaCode == SignageCatalog.flange) {
      // inner glow line of a lit box
      canvas.drawRect(
        r.deflate(math.min(4, r.shortestSide * 0.08)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    canvas.drawRect(
      r,
      Paint()
        ..color = _mediaStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final textColor = (fill == Colors.white || fill == const Color(0xFFC0C4C8))
        ? _red
        : Colors.white;
    _boardText(canvas, r, textColor);
  }

  void _artworkFace(Canvas canvas, Rect r) {
    canvas.drawRect(r, Paint()..color = _mediaFill);
    _dashedRect(canvas, r, AdinnColors.redDark);
    _boardText(canvas, r, Colors.white);
  }

  void _boardText(Canvas canvas, Rect r, Color color) {
    final brand = _brand;
    final fs = math
        .min(r.height * 0.36, r.width * 0.88 / math.max(1, brand.length * 0.66))
        .clamp(5.0, 64.0)
        .toDouble();
    final showSub = r.height > 34;
    final total = showSub ? fs * 1.25 + fs * 0.5 : fs * 1.25;
    final top = r.center.dy - total / 2;
    _text(
      canvas,
      brand,
      Offset(r.center.dx, top),
      size: fs,
      color: color,
      weight: FontWeight.w900,
      align: Alignment.topCenter,
      maxWidth: r.width * 0.95,
    );
    if (showSub) {
      _text(
        canvas,
        '${geo.media.shortName}${geo.media.illuminated ? ' · LIT' : ''}',
        Offset(r.center.dx, top + fs * 1.25),
        size: math.max(5, fs * 0.42),
        color: color.withValues(alpha: 0.85),
        weight: FontWeight.w700,
        align: Alignment.topCenter,
        maxWidth: r.width * 0.95,
      );
    }
  }

  void _ground(Canvas canvas, _Frame f, Rect region) {
    final y = f.gy;
    final x0 = region.left + 8, x1 = region.right - 8;
    canvas.drawLine(
      Offset(x0, y),
      Offset(x1, y),
      Paint()
        ..color = _ink
        ..strokeWidth = 2,
    );
    final hatch = Paint()
      ..color = _ink.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (var x = x0 + 10; x < x1; x += 12) {
      canvas.drawLine(Offset(x, y), Offset(x - 8, y + 8), hatch);
    }
    _text(
      canvas,
      'GL ±0',
      Offset(x0 + 2, y - 16),
      size: 10,
      color: _muted,
      weight: FontWeight.w700,
    );
  }

  void _pole(Canvas canvas, _Frame f, double x, double r, double top) {
    final rect = f.r(x - r, 0, x + r, top);
    final widened = rect.width < 3
        ? Rect.fromCenter(center: rect.center, width: 3, height: rect.height)
        : rect;
    _fillStroke(canvas, widened, const Color(0xFF9AA1A9), _structure);
  }

  void _footing(Canvas canvas, _Frame f, double x, double half) {
    _fillStroke(canvas, f.r(x - half, 0, x + half, 0.3), _concrete, _structure);
    _dashedRect(
      canvas,
      f.r(x - half, -geo.foundationDepthFt, x + half, 0),
      _structure,
    );
  }

  void _wall(Canvas canvas, _Frame f, Rect r) {
    canvas.drawRect(r, Paint()..color = _wallFill);
    final step = f.s; // one course per foot
    if (step > 5) {
      final line = Paint()
        ..color = _structure.withValues(alpha: 0.18)
        ..strokeWidth = 1;
      for (var y = r.bottom - step; y > r.top; y -= step) {
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), line);
      }
    }
    canvas.drawRect(
      r,
      Paint()
        ..color = _structure
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _shutters(Canvas canvas, _Frame f, double x0, double x1, double top) {
    if (top <= 0) return;
    final mid = (x0 + x1) / 2;
    final slat = Paint()
      ..color = _structure.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (final (a, c) in [(x0, mid - 0.5), (mid + 0.5, x1)]) {
      if (c - a < 0.5) continue;
      final r = f.r(a, 0, c, top);
      _fillStroke(canvas, r, _shutterFill, _structure);
      final step = math.max(4.0, 0.5 * f.s);
      for (var y = r.top + step; y < r.bottom; y += step) {
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), slat);
      }
    }
  }

  void _human(Canvas canvas, _Frame f, double x) {
    final paint = Paint()
      ..color = _muted
      ..strokeWidth = math.max(1.5, 0.12 * f.s)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(f.p(x, 5.15), 0.35 * f.s, paint);
    canvas.drawLine(f.p(x, 4.8), f.p(x, 2.6), paint);
    canvas.drawLine(f.p(x, 2.6), f.p(x - 0.45, 0), paint);
    canvas.drawLine(f.p(x, 2.6), f.p(x + 0.45, 0), paint);
    canvas.drawLine(f.p(x - 0.7, 3.2), f.p(x, 4.4), paint);
    canvas.drawLine(f.p(x + 0.7, 3.2), f.p(x, 4.4), paint);
    _text(
      canvas,
      '5.5 ft',
      f.p(x, -0.05) + const Offset(0, 4),
      size: 9,
      color: _muted,
      align: Alignment.topCenter,
    );
  }

  void _breakLine(Canvas canvas, Offset a, Offset b) {
    final path = Path()..moveTo(a.dx, a.dy);
    final mid = Offset.lerp(a, b, 0.5)!;
    path
      ..lineTo(mid.dx, mid.dy + 8)
      ..lineTo(mid.dx - 6, mid.dy + 3)
      ..lineTo(mid.dx + 6, mid.dy - 3)
      ..lineTo(mid.dx, mid.dy - 8)
      ..lineTo(b.dx, b.dy);
    canvas.drawLine(
      Offset(a.dx, a.dy),
      Offset(b.dx, b.dy),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _fillStroke(
    Canvas canvas,
    Rect r,
    Color fill,
    Color stroke, {
    double width = 1.2,
  }) {
    canvas.drawRect(r, Paint()..color = fill);
    canvas.drawRect(
      r,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  void _dashedRect(Canvas canvas, Rect r, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    void dashed(Offset a, Offset b) {
      final len = (b - a).distance;
      if (len == 0) return;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += 9) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + 5, len), paint);
      }
    }

    dashed(r.topLeft, r.topRight);
    dashed(r.topRight, r.bottomRight);
    dashed(r.bottomRight, r.bottomLeft);
    dashed(r.bottomLeft, r.topLeft);
  }

  // ---------------------------------------------------------------------------
  // Dimension lines
  // ---------------------------------------------------------------------------

  static final _dimPaint = Paint()
    ..color = _red
    ..strokeWidth = 1.2;
  static final _extPaint = Paint()
    ..color = _ink.withValues(alpha: 0.45)
    ..strokeWidth = 0.8;

  /// Horizontal dimension between [a] and [b], drawn at screen [y].
  void _dimH(
    Canvas canvas,
    Offset a,
    Offset b,
    double y,
    String label, {
    bool fromBelow = false,
  }) {
    if ((b.dx - a.dx).abs() < 2) return;
    final sign = y < a.dy ? -1.0 : 1.0;
    canvas.drawLine(Offset(a.dx, a.dy), Offset(a.dx, y + sign * 5), _extPaint);
    canvas.drawLine(Offset(b.dx, b.dy), Offset(b.dx, y + sign * 5), _extPaint);
    final p1 = Offset(math.min(a.dx, b.dx), y);
    final p2 = Offset(math.max(a.dx, b.dx), y);
    canvas.drawLine(p1, p2, _dimPaint);
    _arrow(canvas, p1, const Offset(1, 0));
    _arrow(canvas, p2, const Offset(-1, 0));
    _label(canvas, Offset((p1.dx + p2.dx) / 2, y), label);
  }

  /// Vertical dimension between [a] and [b], drawn at screen [x].
  void _dimV(Canvas canvas, Offset a, Offset b, double x, String label) {
    if ((b.dy - a.dy).abs() < 2) return;
    final sign = x < a.dx ? -1.0 : 1.0;
    canvas.drawLine(Offset(a.dx, a.dy), Offset(x + sign * 5, a.dy), _extPaint);
    canvas.drawLine(Offset(b.dx, b.dy), Offset(x + sign * 5, b.dy), _extPaint);
    final p1 = Offset(x, math.min(a.dy, b.dy));
    final p2 = Offset(x, math.max(a.dy, b.dy));
    canvas.drawLine(p1, p2, _dimPaint);
    _arrow(canvas, p1, const Offset(0, 1));
    _arrow(canvas, p2, const Offset(0, -1));
    canvas.save();
    canvas.translate(x, (p1.dy + p2.dy) / 2);
    canvas.rotate(-math.pi / 2);
    _label(canvas, Offset.zero, label);
    canvas.restore();
  }

  void _arrow(Canvas canvas, Offset tip, Offset dir) {
    final n = Offset(-dir.dy, dir.dx);
    final base = tip + dir * 8;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(base.dx + n.dx * 3.5, base.dy + n.dy * 3.5)
        ..lineTo(base.dx - n.dx * 3.5, base.dy - n.dy * 3.5)
        ..close(),
      Paint()..color = _red,
    );
  }

  void _label(Canvas canvas, Offset center, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: _ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final rect = Rect.fromCenter(
      center: center,
      width: tp.width + 8,
      height: tp.height + 2,
    );
    canvas.drawRect(rect, Paint()..color = Colors.white);
    tp.paint(canvas, rect.topLeft + const Offset(4, 1));
    tp.dispose();
  }

  // ---------------------------------------------------------------------------
  // Title block & notes
  // ---------------------------------------------------------------------------

  void _paintTitleBlock(Canvas canvas) {
    final r = _titleRect;
    // Wordmark
    final logo = RRect.fromRectAndRadius(
      Rect.fromLTWH(r.left + 14, r.top + 18, 46, 46),
      const Radius.circular(12),
    );
    canvas.drawRRect(logo, Paint()..color = _red);
    _text(
      canvas,
      'a',
      logo.center,
      size: 34,
      color: Colors.white,
      weight: FontWeight.w900,
      align: Alignment.center,
    );
    _text(
      canvas,
      'adinn',
      Offset(r.left + 70, r.top + 18),
      size: 32,
      color: _red,
      weight: FontWeight.w900,
    );
    _text(
      canvas,
      'Signage Board Recce',
      Offset(r.left + 14, r.top + 76),
      size: 13,
      weight: FontWeight.w700,
    );
    _text(
      canvas,
      'Auto-generated default drawing',
      Offset(r.left + 14, r.top + 96),
      size: 11,
      color: _muted,
    );
    if (info.statusLabel.isNotEmpty) {
      _text(
        canvas,
        'Status: ${info.statusLabel}',
        Offset(r.left + 14, r.top + 118),
        size: 11,
        color: _muted,
        maxWidth: 170,
      );
    }
    final divider = Paint()
      ..color = _ink
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(r.left + 190, r.top - 10),
      Offset(r.left + 190, r.bottom + 8),
      divider,
    );

    final u = geo.unit;
    final size = fmtSize(u.fromFeet(geo.widthFt), u.fromFeet(geo.heightFt), u);
    final area =
        '${fmtNum(geo.areaSqFt)} sq ft${geo.quantity > 1 ? ' × ${geo.quantity} = ${fmtNum(geo.areaSqFt * geo.quantity)} sq ft' : ''}';
    final col1 = [
      ('PROJECT', info.projectName),
      ('SHOP', info.shopName),
      ('ADDRESS', info.shopAddress),
      ('BOARD', info.boardName),
      ('MEDIA', '${geo.media.shortName} – ${geo.media.name}'),
      ('INSTALLATION', geo.installation.name),
    ];
    final col2 = [
      ('SIZE (W × H)', geo.usingDefaults ? '$size (default)' : size),
      ('AREA', area),
      ('BOARD BOTTOM FROM GL', _len(geo.bottomFt)),
      ('DEPTH', _len(geo.depthFt)),
      ('DATE', info.date),
      ('DRAWN BY', info.drawnBy),
    ];
    void column(List<(String, String)> rows, double x, double width) {
      for (var i = 0; i < rows.length; i++) {
        final y = r.top + i * 38.0 - 4;
        _text(
          canvas,
          rows[i].$1,
          Offset(x, y),
          size: 9.5,
          color: _muted,
          weight: FontWeight.w700,
        );
        _text(
          canvas,
          rows[i].$2.isEmpty ? '—' : rows[i].$2,
          Offset(x, y + 13),
          size: 13,
          weight: FontWeight.w700,
          maxWidth: width,
        );
        if (i < rows.length - 1) {
          canvas.drawLine(
            Offset(x, y + 33),
            Offset(x + width, y + 33),
            Paint()
              ..color = AdinnColors.line
              ..strokeWidth = 1,
          );
        }
      }
    }

    column(col1, r.left + 202, 316);
    canvas.drawLine(
      Offset(r.left + 528, r.top - 10),
      Offset(r.left + 528, r.bottom + 8),
      divider,
    );
    column(col2, r.left + 540, 312);
  }

  void _paintNotes(Canvas canvas) {
    final r = _notesRect;
    _text(
      canvas,
      info.summaryTitle,
      Offset(r.left + 4, r.top - 4),
      size: 13,
      weight: FontWeight.w800,
    );
    final lines = <(String, Color)>[
      if (!geo.mediaSelected) ('Media type not selected – GSB assumed', _red),
      if (!geo.installationSelected)
        ('Installation not selected – ${geo.installation.name} assumed', _red),
      if (geo.usingDefaults)
        ('Board size not entered – default 10 × 4 ft shown', _red),
      for (final n in info.notes) (n, _ink),
    ];
    if (lines.isEmpty) {
      lines.add(('No site answers recorded yet.', _muted));
    }
    const maxLines = 11;
    var y = r.top + 18;
    for (var i = 0; i < math.min(lines.length, maxLines); i++) {
      final last = i == maxLines - 1 && lines.length > maxLines;
      _text(
        canvas,
        last
            ? '… +${lines.length - maxLines + 1} more (full list below the sheet)'
            : '• ${lines[i].$1}',
        Offset(r.left + 4, y),
        size: 11,
        color: last ? _muted : lines[i].$2,
        maxWidth: r.width - 8,
      );
      y += 19;
    }
  }

  // ---------------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------------

  /// Paints [s] anchored at [at] using [align] (-1..1 like [Alignment]).
  /// Returns the painted width.
  double _text(
    Canvas canvas,
    String s,
    Offset at, {
    double size = 12,
    Color color = _ink,
    FontWeight weight = FontWeight.w500,
    Alignment align = Alignment.topLeft,
    double? maxWidth,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          // Tamil glyphs come from the bundled Noto Sans Tamil.
          fontFamilyFallback: const ['NotoSansTamil'],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    final dx = (align.x + 1) / 2 * tp.width;
    final dy = (align.y + 1) / 2 * tp.height;
    tp.paint(canvas, at - Offset(dx, dy));
    final w = tp.width;
    tp.dispose();
    return w;
  }

  @override
  bool shouldRepaint(covariant Drawing2DPainter old) =>
      old.geo != geo || !identical(old.info, info) || old.brand != brand;
}
