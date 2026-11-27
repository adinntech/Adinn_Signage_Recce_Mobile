import '../../l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../drawing/drawing_2d_screen.dart';
import '../location/gps_widgets.dart';
import '../notes/voice_notes_section.dart';
import '../photos/photo_section.dart';
import '../photos/site_photo_view.dart';
import '../preview3d/preview_3d_screen.dart';
import '../preview_live/preview_gallery.dart';

/// Read-only rendering of a shop recce (live or a submitted snapshot).
class ShopSnapshotView extends StatelessWidget {
  const ShopSnapshotView({
    super.key,
    required this.shop,
    this.liveShopId,
    this.issues = const [],
  });

  final Shop shop;

  /// Item-specific rejection issues to highlight (latest rejection).
  final List<RejectionIssue> issues;

  /// When set, 2D/3D buttons open the live board (only valid when the
  /// snapshot equals the current state, e.g. while pending review).
  final String? liveShopId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: context.ui('Shop'),
          icon: Icons.storefront_outlined,
          child: Column(
            children: [
              InfoRow(context.ui('Name'), shop.name),
              InfoRow(context.ui('Owner'), shop.ownerName),
              InfoRow(context.ui('Phone'), shop.phone),
              InfoRow(context.ui('Address'), shop.fullAddress),
              InfoRow(context.ui('Landmark'), shop.landmark),
              if (shop.remarks.isNotEmpty)
                InfoRow(context.ui('Remarks'), shop.remarks),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: context.ui('Shop location (GPS)'),
          icon: Icons.my_location,
          child: shop.geo == null
              ? Text(context.ui('GPS location not captured in this version.'),
                  style: TextStyle(color: AdinnColors.muted),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GeoDetails(geo: shop.geo!),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: () =>
                          openInMaps(context, shop.geo!, shop.name),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(context.ui('Open in Maps')),
                    ),
                  ],
                ),
        ),
        for (final b in shop.boards) ...[
          const SizedBox(height: 12),
          BoardSnapshotCard(
            board: b,
            liveShopId: liveShopId,
            shopGeo: shop.geo,
            issues: issues.where((i) => i.groupId == b.id).toList(),
          ),
        ],
      ],
    );
  }
}

class BoardSnapshotCard extends StatelessWidget {
  const BoardSnapshotCard({
    super.key,
    required this.board,
    this.liveShopId,
    this.shopGeo,
    this.issues = const [],
  });

  final Board board;
  final String? liveShopId;
  final List<RejectionIssue> issues;

  /// Shop GPS, used to show how far each photo was taken from the shop.
  final GeoFix? shopGeo;

  @override
  Widget build(BuildContext context) {
    final media = SignageCatalog.media(board.mediaCode);
    final inst = SignageCatalog.installation(board.installationCode);
    final questions = SignageCatalog.questionsFor(
      board.mediaCode,
      board.installationCode,
    ).where((q) => q.isVisible(board.answers)).toList();

    return SectionCard(
      title: board.name,
      icon: media?.icon ?? Icons.dashboard_customize_outlined,
      trailing: TagChip(
        board.isSameSize
            ? fmtSize(board.width, board.height, board.unit)
            : 'Different sizes',
        color: AdinnColors.red,
        icon: Icons.straighten,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(
            'Media',
            media == null ? '' : '${media.shortName} – ${media.name}',
          ),
          InfoRow('Installation', inst?.name ?? ''),
          InfoRow(
            'Quantity',
            '${board.quantity} unit${board.quantity == 1 ? '' : 's'}'
                '${board.quantity > 1 ? (board.isSameSize ? ' • same size' : ' • different sizes') : ''}',
          ),
          InfoRow('Area', '${fmtNum(board.areaSqFt)} sq ft'),
          const Divider(height: 20),
          Text(
            '${media?.shortName ?? board.name} – ${board.quantity} '
            'Unit${board.quantity == 1 ? '' : 's'}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          for (final u in board.activeUnits)
            _UnitRow(board: board, unit: u, issues: issues),
          if (questions.isNotEmpty) ...[
            const Divider(height: 20),
            Text(context.ui('Site answers'),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            for (final q in questions)
              InfoRow(
                q.label,
                SignageCatalog.answerText(q, board.answers[q.id]),
              ),
          ],
          const Divider(height: 20),
          Text(
            'Photos (${board.photos.length})',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (board.photos.isEmpty)
            Text(context.ui('No photos'), style: TextStyle(color: AdinnColors.muted)),
          if (board.photos.isNotEmpty)
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: board.photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final p = board.photos[i];
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PhotoViewerScreen(photo: p, shopGeo: shopGeo),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 108,
                          child: AnnotatedPhotoView(p, cacheWidth: 400),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.geo == null
                              ? '${p.label} • no GPS'
                              : shopGeo == null
                              ? '${p.label} • GPS'
                              : '${p.label} • '
                                    '${fmtDistance(p.geo!.distanceTo(shopGeo!))}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (board.previews.isNotEmpty) ...[
            const Divider(height: 20),
            Text(
              'Live previews / AR (${board.previews.length})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            PreviewGallery(board: board),
          ],
          if (board.textNote.isNotEmpty || board.voiceNotes.isNotEmpty) ...[
            const Divider(height: 20),
            Text(context.ui('Notes'), style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (board.textNote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(board.textNote),
              ),
            for (final n in board.voiceNotes) VoiceNoteTile(note: n),
          ],
          if (liveShopId != null &&
              board.mediaCode != null &&
              board.installationCode != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Drawing2DScreen(
                          shopId: liveShopId!,
                          boardId: board.id,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.architecture),
                    label: Text(context.ui('2D')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Preview3DScreen(
                          shopId: liveShopId!,
                          boardId: board.id,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.view_in_ar),
                    label: Text(context.ui('3D')),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Timeline of reviews on a submission (Business, then Ops).
class ReviewTrail extends StatelessWidget {
  const ReviewTrail({super.key, required this.submission});

  final Submission submission;

  @override
  Widget build(BuildContext context) {
    final entries = <Widget>[
      _entry(
        icon: Icons.send,
        color: AdinnColors.info,
        title: context.uf('Submitted by {0}', [submission.submittedByName]),
        when: submission.submittedAt,
        body: submission.vendorRemarks,
      ),
      for (final r in submission.reviews)
        _entry(
          icon: r.decision == ReviewDecision.approved
              ? Icons.verified
              : Icons.cancel,
          color: r.decision == ReviewDecision.approved
              ? AdinnColors.success
              : AdinnColors.red,
          title:
              '${r.stage.label} ${r.decision == ReviewDecision.approved ? 'approved' : 'rejected'} • ${r.reviewerName}',
          when: r.at,
          body: r.remarks,
          reasons: r.reasons,
          issues: r.issues.map((i) => i.text).toList(),
        ),
    ];
    final outcome = submission.outcome;
    if (outcome.isPending) {
      entries.add(
        _entry(
          icon: Icons.hourglass_top,
          color: outcome.color,
          title: outcome.label,
          when: null,
          body: '',
        ),
      );
    }
    return Column(children: entries);
  }

  Widget _entry({
    required IconData icon,
    required Color color,
    required String title,
    required DateTime? when,
    required String body,
    List<String> reasons = const [],
    List<String> issues = const [],
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (when != null)
                  Text(
                    fmtDateTime(when),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AdinnColors.muted,
                    ),
                  ),
                if (body.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(body, style: const TextStyle(fontSize: 13)),
                  ),
                if (reasons.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final r in reasons)
                          TagChip(r, color: AdinnColors.red),
                      ],
                    ),
                  ),
                // Item-specific issues can be long: plain wrapping text.
                for (final i in issues)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '↳ $i',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AdinnColors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One signage unit line in a review / snapshot: size, installation,
/// placement, notes and per-unit evidence counts.
class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.board,
    required this.unit,
    required this.issues,
  });

  final Board board;
  final SignageUnit unit;
  final List<RejectionIssue> issues;

  @override
  Widget build(BuildContext context) {
    final b = board, u = unit;
    final inst = SignageCatalog.installation(b.installationOf(u));
    final mine = issues.where((i) => i.unitId == u.id).toList();
    final photos = b.photosOf(u).length;
    final markings = b.annotationsOf(u).length;
    final live = b
        .previewsOf(u)
        .where((c) => c.kind == CaptureKind.live)
        .length;
    final ar = b.previewsOf(u).where((c) => c.kind == CaptureKind.ar).length;
    final complete = b.unitHasSize(u) && b.installationOf(u) != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: mine.isEmpty
            ? AdinnColors.canvas
            : AdinnColors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: mine.isEmpty ? AdinnColors.line : AdinnColors.red,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${b.unitLabel(u)} – '
                  '${fmtSize(b.widthOf(u), b.heightOf(u), b.unit)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                complete ? Icons.check_circle : Icons.error_outline,
                size: 16,
                color: complete ? AdinnColors.success : AdinnColors.warning,
              ),
            ],
          ),
          Text(
            [
              inst?.name ?? 'Installation not set',
              if (u.placement.isNotEmpty) u.placement,
            ].join(' • '),
            style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
          ),
          if (u.installationDetails.isNotEmpty)
            Text(
              'Installation: ${u.installationDetails}',
              style: const TextStyle(fontSize: 12),
            ),
          if (u.notes.isNotEmpty)
            Text(context.uf('Notes: {0}', [u.notes]), style: const TextStyle(fontSize: 12)),
          Text(
            'Photos $photos • markings $markings • live preview $live • AR $ar',
            style: const TextStyle(fontSize: 11, color: AdinnColors.muted),
          ),
          for (final i in mine)
            Text(
              'Rejected: ${i.aspect.label}${i.note.isEmpty ? '' : ' – ${i.note}'}',
              style: const TextStyle(
                fontSize: 12,
                color: AdinnColors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
