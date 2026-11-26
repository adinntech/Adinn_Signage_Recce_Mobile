import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/enums.dart';
import '../theme/app_theme.dart';

/// Path of the original Adinn logo: the same artwork as the website sidebar (`Adinn_Logo.svg`), rendered to PNG.
const adinnLogoAsset = 'assets/images/adinn_logo.png';

/// Loads and decodes the logo into the image cache BEFORE the first screen is drawn, so the start-up screen has it in its very first
/// frame (an image that is loaded when first drawn appears a moment late, most visibly on Chrome). Gives up after two seconds: the
/// logo then simply loads the usual way, nothing waits for it longer than that. Never throws.
Future<void> preloadAdinnLogo() async {
  final done = Completer<void>();
  final stream = const AssetImage(adinnLogoAsset).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish() {
    if (!done.isCompleted) done.complete();
    stream.removeListener(listener);
  }

  listener = ImageStreamListener((_, _) => finish(), onError: (_, _) => finish());
  stream.addListener(listener);
  await done.future.timeout(const Duration(seconds: 2), onTimeout: () {});
}

/// The original Adinn logo (the website's own artwork, not a redrawn one). [size] sets the scale (the logo is about 1.45 x [size]
/// high and keeps its shape). On a coloured background pass [light]: the logo then sits on a white rounded plate, so its own red
/// and black stay exactly as designed.
class AdinnLogo extends StatelessWidget {
  const AdinnLogo({super.key, this.size = 34, this.light = false});

  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final h = size * 1.45;
    // The box has the logo's own shape (125 x 47) from the first frame, so nothing shifts when the picture arrives; a picture that
    // had to be loaded fades in (one that was preloaded is simply there).
    final logo = SizedBox(
      width: h * 125 / 47,
      height: h,
      child: Image.asset(
        adinnLogoAsset,
        height: h,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: 'Adinn Advertising Services',
        frameBuilder: (_, child, frame, loadedAtOnce) =>
            loadedAtOnce ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 200), child: child),
      ),
    );
    if (!light) return logo;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.4, vertical: size * 0.2),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(size * 0.45)),
      child: logo,
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.compact = false});

  final RecceStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = status.color;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: compact ? 12 : 14, color: c),
          const SizedBox(width: 4),
          Text(
            compact ? status.shortLabel : status.label,
            style: TextStyle(
              color: c,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip(
    this.text, {
    super.key,
    this.color = AdinnColors.muted,
    this.icon,
  });

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          // Never overflows a narrow card: long text is cut with an ellipsis.
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.icon,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: AdinnColors.red),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AdinnColors.muted),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: AdinnColors.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: AdinnColors.redLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AdinnColors.red),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AdinnColors.muted),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class ProgressBarLabel extends StatelessWidget {
  const ProgressBarLabel({
    super.key,
    required this.value,
    required this.label,
    this.color = AdinnColors.red,
  });

  final double value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
              ),
            ),
            Text(
              '${(value * 100).round()}%',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 7,
            color: color,
            backgroundColor: AdinnColors.line,
          ),
        ),
      ],
    );
  }
}

class IssueList extends StatelessWidget {
  const IssueList({super.key, required this.items, this.warning = false});

  final List<String> items;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? AdinnColors.warning : AdinnColors.red;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final i in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  warning ? Icons.warning_amber_rounded : Icons.error_outline,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(i, style: TextStyle(color: color, fontSize: 13)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AdinnColors.redDark)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AdinnColors.redDark : AdinnColors.ink,
      ),
    );
}

/// Opens the phone dialer with [number] pre-filled.
Future<void> dialNumber(BuildContext context, String number) async {
  final cleaned = number.replaceAll(RegExp(r'[^0-9+]'), '');
  if (cleaned.isEmpty) {
    showSnack(context, 'No phone number available', error: true);
    return;
  }
  final uri = Uri(scheme: 'tel', path: cleaned);
  var ok = false;
  try {
    ok = await launchUrl(uri);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    showSnack(context, 'Could not open the dialer for $cleaned', error: true);
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.initials, {super.key, this.size = 40, this.light = false});

  final String initials;
  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: light ? Colors.white : AdinnColors.redLight,
      child: Text(
        initials,
        style: TextStyle(
          color: AdinnColors.red,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}
