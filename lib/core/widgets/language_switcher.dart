import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../state/app_controller.dart';
import '../theme/app_theme.dart';

/// Compact two-state AppBar toggle: `[ ENG | அ ]`.
///
/// The active locale is the single source of truth; there is no per-screen
/// language state. Switching never touches navigation, form data or drafts.
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({super.key, this.light = false});

  /// White outline variant for the red dashboard header.
  final bool light;

  @override
  Widget build(BuildContext context) {
    final AppController c;
    try {
      c = context.watch<AppController>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    final t = context.t;
    final isTamil = c.isTamil;
    final accent = light ? Colors.white : AdinnColors.red;

    Widget segment({
      required String label,
      required bool selected,
      required String semantic,
      required VoidCallback onTap,
    }) {
      return Semantics(
        button: true,
        selected: selected,
        label: semantic,
        child: InkWell(
          key: Key(label == 'ENG' ? 'lang_en' : 'lang_ta'),
          // Tapping the already-selected segment toggles, which keeps the
          // legacy whole-widget lang_switch tap working as a toggle too.
          onTap: selected ? c.toggleLanguage : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected
                    ? (light ? AdinnColors.red : Colors.white)
                    : accent,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: t.langSwitchTooltip,
      child: Container(
        key: const Key('lang_switch'),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(color: accent),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            segment(
              label: 'ENG',
              selected: !isTamil,
              semantic: 'English',
              onTap: () => c.setLanguage('en'),
            ),
            segment(
              label: 'அ',
              selected: isTamil,
              semantic: 'Tamil',
              onTap: () => c.setLanguage('ta'),
            ),
          ],
        ),
      ),
    );
  }
}
