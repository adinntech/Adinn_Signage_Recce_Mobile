import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'common_widgets.dart';

/// Start-up / refresh screen shown while the app restores the saved session.
/// Follows the app tone: white surface, Adinn red accent, ink text. A red arc circles the logo while loading.
/// Native Flutter animation only; it is skipped when the phone asks to reduce motion.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.message = 'Getting things ready…'});

  /// One short line under the title.
  final String message;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
    } else {
      _intro.forward();
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    final rise = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Soft red tints in two corners.
          Positioned(top: -110, right: -90, child: _blob(280, AdinnColors.redLight)),
          Positioned(bottom: -130, left: -100, child: _blob(320, AdinnColors.redLight.withValues(alpha: 0.7))),
          SafeArea(
            child: Center(
              child: FadeTransition(
                opacity: fade,
                child: SlideTransition(
                  position: rise,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 150,
                        height: 150,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 130,
                              height: 130,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: AdinnColors.line),
                                boxShadow: const [BoxShadow(color: Color(0x14D71920), blurRadius: 28, offset: Offset(0, 10))],
                              ),
                              alignment: Alignment.center,
                              child: const AdinnLogo(size: 26),
                            ),
                            AnimatedBuilder(
                              animation: _spin,
                              builder: (_, _) => CustomPaint(size: const Size.square(150), painter: _ArcPainter(_spin.value)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Signage Recce',
                        style: TextStyle(color: AdinnColors.ink, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                      ),
                      const SizedBox(height: 6),
                      Text(widget.message, style: const TextStyle(color: AdinnColors.muted, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: SafeArea(
              child: Text(
                'Field recce app',
                textAlign: TextAlign.center,
                style: TextStyle(color: AdinnColors.muted, fontSize: 12, letterSpacing: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, Color colour) => Container(width: size, height: size, decoration: BoxDecoration(color: colour, shape: BoxShape.circle));
}

/// A red arc that circles the logo, with a faint full ring behind it.
class _ArcPainter extends CustomPainter {
  _ArcPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = AdinnColors.red.withValues(alpha: 0.12);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..color = AdinnColors.red;
    final inset = rect.deflate(2);
    canvas.drawArc(inset, 0, math.pi * 2, false, track);
    canvas.drawArc(inset, t * math.pi * 2 - math.pi / 2, math.pi * 0.55, false, arc);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.t != t;
}
