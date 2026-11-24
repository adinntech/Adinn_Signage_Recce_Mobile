import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/catalog/signage_catalog.dart';

/// The media type cards: one card per media type (icon, short name, full name, description), two to a row. The ONE media type
/// selector of the app: the legacy board editor and the live recce "Add boards" screen both use it.
///
/// One choice: pass [selected] and [onSelect]. Several choices: also pass [selectedCodes]; a tap then toggles that card (it calls
/// [onSelect] with the card's media type either way, the caller decides whether it was ticked or unticked).
/// [media] is the list to draw (the live flow passes the catalog the admin edits); null draws the built-in list.
class MediaTypeGrid extends StatelessWidget {
  const MediaTypeGrid({super.key, required this.selected, required this.onSelect, required this.enabled, this.media, this.selectedCodes});

  final String? selected;
  final ValueChanged<MediaType> onSelect;
  final bool enabled;
  final List<MediaType>? media;
  final Set<String>? selectedCodes;

  @override
  Widget build(BuildContext context) {
    final list = media ?? SignageCatalog.catalogMedia;
    return GridView.count(
      crossAxisCount: 2,
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.05,
      children: [
        for (final m in [
          ...list,
          // A legacy type stays visible only on a group that already uses it.
          if (media == null && SignageCatalog.isLegacy(selected)) SignageCatalog.media(selected)!,
        ])
          MediaTypeCard(
            media: m,
            selected: selectedCodes != null ? selectedCodes!.contains(m.code) : m.code == selected,
            onTap: enabled ? () => onSelect(m) : null,
          ),
      ],
    );
  }
}

class MediaTypeCard extends StatelessWidget {
  const MediaTypeCard({super.key, required this.media, required this.selected, this.onTap});

  final MediaType media;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AdinnColors.redLight : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: Key('media_${media.code}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AdinnColors.red : AdinnColors.line, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(media.icon, color: media.color),
                  const Spacer(),
                  if (selected) const Icon(Icons.check_circle, color: AdinnColors.red, size: 18),
                ],
              ),
              const SizedBox(height: 6),
              Text(media.shortName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(media.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Expanded(
                child: Text(media.description, overflow: TextOverflow.fade, style: const TextStyle(fontSize: 10.5, color: AdinnColors.muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
