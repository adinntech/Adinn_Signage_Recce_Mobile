import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../annotation/annotation_painter.dart';

/// Shows a captured site photo (file on device) or a built-in demo photo,
/// stretched to fill its parent. Parents keep the photo's aspect ratio.
class SitePhotoImage extends StatelessWidget {
  const SitePhotoImage(this.photo, {super.key, this.cacheWidth});

  final SitePhoto photo;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    if (photo.isDemo) {
      return CustomPaint(
        painter: DemoShopfrontPainter(photo.demoSeed),
        child: const SizedBox.expand(),
      );
    }
    return Image.file(
      File(photo.path),
      fit: BoxFit.fill,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Container(
        color: AdinnColors.line,
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: AdinnColors.muted),
            SizedBox(height: 4),
            Text(
              'Photo not found on device',
              style: TextStyle(fontSize: 11, color: AdinnColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Photo with its saved annotations drawn on top (read-only).
class AnnotatedPhotoView extends StatelessWidget {
  const AnnotatedPhotoView(
    this.photo, {
    super.key,
    this.borderRadius = 10,
    this.cacheWidth,
  });

  final SitePhoto photo;
  final double borderRadius;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(
        aspectRatio: photo.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SitePhotoImage(photo, cacheWidth: cacheWidth),
            CustomPaint(
              painter: AnnotationPainter(
                annotations: photo.annotations,
                imageSize: Size(
                  photo.width.toDouble(),
                  photo.height.toDouble(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a stylised shop front so the full photo → annotation → drawing
/// journey can be demoed on emulators without a real camera scene.
/// Designed for a 1200×900 canvas and scaled to any size.
class DemoShopfrontPainter extends CustomPainter {
  DemoShopfrontPainter(this.seed);

  final int seed;

  static const _walls = [
    Color(0xFFF2E3C6),
    Color(0xFFDDE7EE),
    Color(0xFFF5D6C6),
    Color(0xFFE3EBD3),
    Color(0xFFE9E1F2),
    Color(0xFFF4EBD0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 1200, size.height / 900);
    final rnd = math.Random(seed);
    final wall = _walls[seed.abs() % _walls.length];

    // Sky
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1200, 900),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF9CC9F0), Color(0xFFE4F1FB)],
        ).createShader(const Rect.fromLTWH(0, 0, 1200, 500)),
    );

    // Neighbour buildings
    final grey = Paint()..color = const Color(0xFFC9CCD1);
    canvas.drawRect(const Rect.fromLTWH(0, 120, 150, 600), grey);
    canvas.drawRect(const Rect.fromLTWH(1050, 160, 150, 560), grey);

    // Main building
    canvas.drawRect(
      const Rect.fromLTWH(150, 90, 900, 630),
      Paint()..color = wall,
    );
    // Parapet
    canvas.drawRect(
      const Rect.fromLTWH(140, 70, 920, 30),
      Paint()..color = wall.withValues(alpha: 1).withRed(200),
    );

    // Upper windows
    final glass = Paint()..color = const Color(0xFF7FA7C4);
    final frame = Paint()
      ..color = const Color(0xFF5B4A3A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    for (var i = 0; i < 3; i++) {
      final r = Rect.fromLTWH(230.0 + i * 290, 120, 160, 70);
      canvas.drawRect(r, glass);
      canvas.drawRect(r, frame);
    }

    // Fascia band (where signage normally goes)
    canvas.drawRect(
      const Rect.fromLTWH(170, 200, 860, 200),
      Paint()..color = wall.withValues(alpha: 1),
    );
    canvas.drawRect(
      const Rect.fromLTWH(170, 200, 860, 200),
      Paint()
        ..color = const Color(0x22000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    // Faded old board
    if (seed.isOdd) {
      canvas.drawRect(
        const Rect.fromLTWH(320, 240, 560, 120),
        Paint()..color = const Color(0x55FFFFFF),
      );
    }

    // Sunshade
    canvas.drawRect(
      const Rect.fromLTWH(160, 400, 880, 22),
      Paint()..color = const Color(0xFF8E8E8E),
    );

    // Rolling shutters
    final shutter = Paint()..color = const Color(0xFFB9BEC4);
    final line = Paint()
      ..color = const Color(0xFF8D939A)
      ..strokeWidth = 3;
    for (final x in [190.0, 620.0]) {
      final r = Rect.fromLTWH(x, 430, 390, 290);
      canvas.drawRect(r, shutter);
      for (var y = r.top + 12; y < r.bottom; y += 16) {
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), line);
      }
    }

    // Steps & footpath
    canvas.drawRect(
      const Rect.fromLTWH(150, 720, 900, 30),
      Paint()..color = const Color(0xFF9E9E9E),
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 750, 1200, 150),
      Paint()..color = const Color(0xFF5F6368),
    );
    final dash = Paint()
      ..color = Colors.white
      ..strokeWidth = 6;
    for (var x = 20.0; x < 1200; x += 120) {
      canvas.drawLine(Offset(x, 840), Offset(x + 60, 840), dash);
    }

    // Electric pole + wires for realism
    final pole = Paint()..color = const Color(0xFF6D6D6D);
    final px = 80.0 + rnd.nextInt(40);
    canvas.drawRect(Rect.fromLTWH(px, 60, 14, 700), pole);
    canvas.drawLine(
      Offset(px, 80),
      const Offset(1200, 110),
      Paint()
        ..color = const Color(0xFF333333)
        ..strokeWidth = 2,
    );

    // "DEMO PHOTO" watermark
    final tp = TextPainter(
      text: const TextSpan(
        text: 'SAMPLE SITE PHOTO',
        style: TextStyle(
          color: Color(0x66FFFFFF),
          fontSize: 34,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(600 - tp.width / 2, 860 - tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DemoShopfrontPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
