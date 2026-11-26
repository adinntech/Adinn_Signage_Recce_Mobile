import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/catalog/signage_catalog.dart';

/// Lightweight vector diagrams for the five GSB Double Side installation
/// cards. No image assets or 3D libraries: just a few grey structural shapes
/// and a small red GSB panel so each option reads at a glance.
class InstallationArtPainter extends CustomPainter {
  const InstallationArtPainter({required this.art});

  final InstallationArt art;

  static const _steel = Color(0xFFB7BCC4);
  static const _steelDark = Color(0xFF9096A0);
  static const _panel = Color(0xFFFFE7E7);
  static const _red = AdinnColors.red;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    switch (art) {
      case InstallationArt.projecting:
        _projecting(canvas, w, h);
      case InstallationArt.doublePole:
        _poles(canvas, w, h, count: 2);
      case InstallationArt.singlePole:
        _poles(canvas, w, h, count: 1);
      case InstallationArt.rooftop:
        _rooftop(canvas, w, h);
      case InstallationArt.hanging:
        _hanging(canvas, w, h);
      case InstallationArt.generic:
        return;
    }
  }

  @override
  bool shouldRepaint(covariant InstallationArtPainter oldDelegate) =>
      oldDelegate.art != art;

  void _panelRect(Canvas canvas, Rect r, {bool label = true}) {
    canvas.drawRect(
      r,
      Paint()..color = _panel..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      r,
      Paint()
        ..color = _red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
    if (!label) return;
    final tp = TextPainter(
      text: const TextSpan(
        text: 'GSB',
        style: TextStyle(
          color: _red,
          fontSize: 6.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _bar(Canvas canvas, Rect r) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(1)),
      Paint()..color = _steel,
    );
  }

  void _ground(Canvas canvas, double w, double h) {
    canvas.drawLine(
      Offset(w * 0.06, h * 0.92),
      Offset(w * 0.94, h * 0.92),
      Paint()
        ..color = _steelDark
        ..strokeWidth = 1.4,
    );
  }

  void _projecting(Canvas canvas, double w, double h) {
    // Grey wall plane in subtle isometric perspective.
    final wall = Path()
      ..moveTo(w * 0.04, h * 0.16)
      ..lineTo(w * 0.24, h * 0.07)
      ..lineTo(w * 0.24, h * 0.88)
      ..lineTo(w * 0.04, h * 0.96)
      ..close();
    canvas.drawPath(wall, Paint()..color = const Color(0xFFE2E5E9));
    canvas.drawPath(
      wall,
      Paint()
        ..color = _steelDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Bracket holding the board off the wall.
    canvas.drawLine(
      Offset(w * 0.22, h * 0.62),
      Offset(w * 0.60, h * 0.53),
      Paint()
        ..color = _steelDark
        ..strokeWidth = 2,
    );
    // Red-bordered panel projecting outwards at ~90 degrees.
    final face = Path()
      ..moveTo(w * 0.24, h * 0.24)
      ..lineTo(w * 0.94, h * 0.13)
      ..lineTo(w * 0.94, h * 0.61)
      ..lineTo(w * 0.24, h * 0.72)
      ..close();
    canvas.drawPath(face, Paint()..color = _panel);
    canvas.drawPath(
      face,
      Paint()
        ..color = _red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
  }

  void _poles(Canvas canvas, double w, double h, {required int count}) {
    final xs = count == 2 ? [w * 0.28, w * 0.64] : [w * 0.46];
    for (final x in xs) {
      _bar(
        canvas,
        Rect.fromLTWH(x, h * 0.52, w * 0.08, h * 0.38),
      );
    }
    _panelRect(
      canvas,
      Rect.fromLTWH(w * 0.10, h * 0.16, w * 0.80, h * 0.38),
    );
    _ground(canvas, w, h);
  }

  void _rooftop(Canvas canvas, double w, double h) {
    // Roof platform with a little depth so it is distinct from a pole.
    canvas.drawRect(
      Rect.fromLTWH(w * 0.10, h * 0.66, w * 0.80, h * 0.14),
      Paint()..color = const Color(0xFFE2E5E9),
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.10, h * 0.66, w * 0.80, h * 0.14),
      Paint()
        ..color = _steelDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    for (final x in [w * 0.30, w * 0.62]) {
      _bar(canvas, Rect.fromLTWH(x, h * 0.50, w * 0.07, h * 0.16));
    }
    _panelRect(
      canvas,
      Rect.fromLTWH(w * 0.14, h * 0.16, w * 0.72, h * 0.35),
    );
  }

  void _hanging(Canvas canvas, double w, double h) {
    // Overhead beam + two hangers, clearly not a rooftop or a ground pole.
    _bar(canvas, Rect.fromLTWH(w * 0.08, h * 0.10, w * 0.84, h * 0.10));
    for (final x in [w * 0.28, w * 0.66]) {
      canvas.drawLine(
        Offset(x, h * 0.20),
        Offset(x, h * 0.44),
        Paint()
          ..color = _steelDark
          ..strokeWidth = 1.8,
      );
    }
    _panelRect(
      canvas,
      Rect.fromLTWH(w * 0.14, h * 0.44, w * 0.72, h * 0.36),
    );
  }
}

/// One selectable installation card: diagram on the left, bold name and
/// one-line description in the middle, radio indicator on the right.
class InstallationChoiceCard extends StatelessWidget {
  const InstallationChoiceCard({
    super.key,
    required this.choice,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final InstallationChoice choice;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? AdinnColors.redLight : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AdinnColors.red : AdinnColors.line,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 44,
                  // Same Material icon as the GSB Single Side cards when the
                  // choice carries one; the painter is only a fallback.
                  child: choice.icon != null
                      ? Icon(choice.icon, color: AdinnColors.red, size: 26)
                      : CustomPaint(
                          painter: InstallationArtPainter(art: choice.art),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        choice.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AdinnColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        choice.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdinnColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20,
                  color: selected ? AdinnColors.red : Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
