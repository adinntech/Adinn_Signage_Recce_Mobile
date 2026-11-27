import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../model3d/signage_spec.dart';
import 'media_reference_detail_screen.dart';
import 'reference_image_picker.dart';
import '../../core/widgets/adinn_app_bar.dart';

Color referenceStatusColor(ReferenceStatus s) => switch (s) {
  ReferenceStatus.pendingReference => AdinnColors.muted,
  ReferenceStatus.collected => AdinnColors.info,
  ReferenceStatus.awaitingTechnicalReview => AdinnColors.warning,
  ReferenceStatus.approved => AdinnColors.success,
  ReferenceStatus.rejected => AdinnColors.redDark,
};

/// Compact status text for chips.
String referenceStatusShort(ReferenceStatus s) => switch (s) {
  ReferenceStatus.awaitingTechnicalReview => 'Awaiting Review',
  _ => s.label,
};

Color modelStatusColor(ModelStatus s) => switch (s) {
  ModelStatus.illustrative => AdinnColors.muted,
  ModelStatus.referencePending => AdinnColors.warning,
  ModelStatus.technicallyReviewed => AdinnColors.success,
};

/// The 13 catalog media with their reference status. Every media without
/// a reference shows "Pending Reference"; nothing is pre-approved.
class MediaReferenceLibraryScreen extends StatelessWidget {
  const MediaReferenceLibraryScreen({super.key, this.picker});

  /// Injectable gallery picker (tests).
  final ReferenceImagePicker? picker;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final media = SignageCatalog.catalogMedia;
    final approved = media
        .where(
          (m) => c.referenceLibraryStatus(m.code) == ReferenceStatus.approved,
        )
        .length;
    return Scaffold(
      appBar: AdinnAppBar(title: Text(context.ui('Media reference library'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SectionCard(
            title: 'Reference photos & technical approval',
            icon: Icons.photo_library_outlined,
            child: Text(
              'Real reference photos show what each media looks like. A 3D '
              'model stays "Illustrative" until a reference is technically '
              'approved by the Business Team or Recce Operations. Web images '
              'are only linked with their source URL – never downloaded or '
              'bundled.\n\n$approved of ${media.length} media have an '
              'approved reference.',
              style: const TextStyle(fontSize: 13, color: AdinnColors.muted),
            ),
          ),
          const SizedBox(height: 8),
          for (final m in media)
            Card(
              child: ListTile(
                key: Key('ref_media_${m.code}'),
                leading: CircleAvatar(
                  backgroundColor: m.color.withValues(alpha: 0.12),
                  child: Icon(m.icon, color: m.color),
                ),
                title: Text(m.name),
                subtitle: Text(
                  '${c.referencesFor(m.code, includeSuperseded: false).length}'
                  ' reference(s) • ${c.modelStatus(m.code).label}',
                ),
                trailing: Builder(
                  builder: (_) {
                    final s = c.referenceLibraryStatus(m.code);
                    return TagChip(
                      referenceStatusShort(s),
                      color: referenceStatusColor(s),
                    );
                  },
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MediaReferenceDetailScreen(
                      mediaCode: m.code,
                      picker: picker,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
