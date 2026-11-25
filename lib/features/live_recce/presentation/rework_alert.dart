import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_file_row.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';
import '../data/rework_alert.dart';
import 'live_widgets.dart';

/// The alert that tells the recce person what the reviewers flagged: a banner on top of the shop screen (every tab) and one sheet per
/// rework request that lists each rejected / rework photo and board detail with the reviewer's reason and a "Retake now" button.

/// The rework requests whose sheet was already shown in this app session (by [ReworkAlert.requestKey]): a sheet is never shown twice
/// for the same request, however often the shop screen is rebuilt or opened again.
final _shownRequests = <String>{};

/// True the first time it is asked for a request key; the key is remembered for the rest of the session.
bool claimReworkAlert(String requestKey) => requestKey.isNotEmpty && _shownRequests.add(requestKey);

@visibleForTesting
void resetReworkAlertMemory() => _shownRequests.clear();

/// What the reviewers flagged on this shop right now. A flagged photo counts as answered once a new picture exists for it (a stored draft
/// or an upload still running); an extra photo asked for, once a draft of its category exists.
ReworkAlert reworkAlertOf(ShopDetailController ctrl) {
  final d = ctrl.detail;
  if (d == null) return const ReworkAlert();
  final drafts = d.photos.where((p) => p.isDraft).toList();
  return ReworkAlert.of(
    d,
    answeredPhoto: (p) => ctrl.draftReplacementOf(p) != null || ctrl.pendingReplacementOf(p) != null,
    answeredRequest: (q) => q.item.answeredBy(drafts) || ctrl.pending.any((u) => u.category == q.category),
  );
}

/// Red banner at the top of the shop screen: how many photos / board details the reviewers flagged, and a button that goes to them.
/// Turns green when every flagged photo already has a new picture.
class ReworkAlertBanner extends StatelessWidget {
  const ReworkAlertBanner({super.key, required this.alert, required this.onOpen, this.compact = false});

  final ReworkAlert alert;
  final VoidCallback onOpen;

  /// One line (used while the Chat tab is open and the room is needed for the thread).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (alert.isEmpty) return const SizedBox.shrink();
    final done = alert.allAnswered;
    final color = done ? AdinnColors.success : AdinnColors.red;
    final title = done ? 'New photos are ready' : (alert.rejectedPhotos > 0 ? 'Retake needed' : 'Rework requested');
    final text = done ? 'Every flagged item has a new photo. Resubmit when you are ready.' : alert.summary;
    return Material(
      key: const Key('rework-alert-banner'),
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.4)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 6 : 10),
          child: Row(children: [
            Icon(done ? Icons.check_circle : Icons.notification_important, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: compact
                  ? Text('$title: $text', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                      Text(text, key: const Key('rework-alert-summary'), style: const TextStyle(fontSize: 13)),
                    ]),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onOpen, child: Text(done ? 'Review' : 'Fix now')),
          ]),
        ),
      ),
    );
  }
}

/// The checklist items the reviewer sent back, each with its Rework / Rejected tag, its label in bold and the reviewer's OWN remark for it
/// (and who asked, when). The list itself, used by [SectionReworkBanner] on the tabs and by the alert sheet. [showSection] adds the part of
/// the app the item belongs to ("Photos", "Boards", ...) after the label.
class SectionReworkItems extends StatelessWidget {
  const SectionReworkItems({super.key, required this.items, this.showSection = false});

  final List<FlaggedSection> items;
  final bool showSection;

  static String sectionName(String section) => switch (section) {
        'PHOTOS' => 'Photos',
        'BOARDS' => 'Boards',
        'INSTALLATION' => 'Installation',
        _ => 'Shop',
      };

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final f in items)
        Container(
          key: ValueKey('section-rework-${f.section}-${f.label}'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AdinnColors.redLight, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ReworkTag(text: f.rejected ? 'Rejected' : 'Rework'),
              Text(f.label, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (showSection) TagChip(sectionName(f.section), icon: Icons.label_outline),
            ]),
            const SizedBox(height: 4),
            Text(
              f.remark.isEmpty ? 'The reviewer sent this back.' : (f.rejected ? 'Reason: ${f.remark}' : f.remark),
              style: const TextStyle(color: AdinnColors.redDark, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            if (f.note.by != null || f.note.at != null)
              Text([if (f.note.by != null) f.note.by!, if (f.note.at != null) fmtDateTime(f.note.at!)].join('  |  '), style: const TextStyle(fontSize: 11.5, color: AdinnColors.muted)),
          ]),
        ),
    ]);
  }
}

/// A red box at the top of a tab with what the reviewer sent back for THIS part of the shop (the tab's own section): every checklist item
/// with its status (Rework / Rejected) and its own remark. Draws nothing when there is none.
class SectionReworkBanner extends StatelessWidget {
  const SectionReworkBanner({super.key, required this.items, this.title = 'Reviewer asked for changes here'});

  final List<FlaggedSection> items;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('section-rework-banner'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(color: AdinnColors.red.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: AdinnColors.red.withValues(alpha: 0.5), width: 1.4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.notification_important, color: AdinnColors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(color: AdinnColors.red, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
        SectionReworkItems(items: items),
      ]),
    );
  }
}

/// Shows the sheet; resolves to true when the person chose "Retake now".
Future<bool?> showReworkAlertSheet(BuildContext context, ReworkAlert alert) => showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ReworkAlertSheet(alert: alert),
    );

class ReworkAlertSheet extends StatelessWidget {
  const ReworkAlertSheet({super.key, required this.alert});

  final ReworkAlert alert;

  @override
  Widget build(BuildContext context) {
    final first = alert.photos.firstOrNull?.note ?? alert.boardFixes.firstOrNull?.note ?? alert.requested.firstOrNull?.note ?? alert.sections.firstOrNull?.note;
    // Nothing to photograph: the button says so (it still takes the person to the first flagged section).
    final nothingToRetake = alert.photos.isEmpty && alert.requested.isEmpty && alert.boardFixes.isEmpty && alert.sections.isNotEmpty;
    final who = [if (first?.by != null) first!.by!, if (first?.role != null) '(${first!.role})'].join(' ');
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.notification_important, color: AdinnColors.red),
                    SizedBox(width: 8),
                    Expanded(child: Text('Rework requested', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AdinnColors.red))),
                  ]),
                  const SizedBox(height: 4),
                  Text(alert.summary, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (who.isNotEmpty) Text('Asked by $who', style: const TextStyle(fontSize: 12, color: AdinnColors.muted)),
                  const SizedBox(height: 12),
                  if (alert.photos.isNotEmpty) ...[
                    const _SectionLabel('Photos to retake'),
                    for (final p in alert.photos) _FlaggedPhotoTile(p),
                  ],
                  if (alert.boardFixes.isNotEmpty) ...[
                    const _SectionLabel('Board details to correct'),
                    for (final f in alert.boardFixes) _BoardFixTile(f),
                  ],
                  if (alert.requested.isNotEmpty) ...[
                    const _SectionLabel('Extra photos asked for'),
                    for (final r in alert.requested) _RequestedTile(r),
                  ],
                  if (alert.sections.isNotEmpty) ...[
                    const _SectionLabel('Other checks to fix'),
                    SectionReworkItems(items: alert.sections, showSection: true),
                  ],
                  const SizedBox(height: 4),
                  const Text('Only these are asked again. Your other photos stay as they are.', style: TextStyle(fontSize: 12, color: AdinnColors.muted)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              Expanded(child: OutlinedButton(key: const Key('rework-alert-later'), onPressed: () => Navigator.pop(context, false), child: const Text('Later'))),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(key: const Key('rework-alert-retake'), onPressed: () => Navigator.pop(context, true), icon: Icon(nothingToRetake ? Icons.edit_note : Icons.photo_camera_outlined), label: Text(nothingToRetake ? 'Fix now' : 'Retake now')),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 6, bottom: 6), child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)));
}

/// One flagged photo: its picture, the angle and board, "Rejected" / "Rework", the reviewer's reason and who asked.
class _FlaggedPhotoTile extends StatelessWidget {
  const _FlaggedPhotoTile(this.f);
  final FlaggedPhoto f;

  @override
  Widget build(BuildContext context) {
    final reason = f.reason.isNotEmpty ? f.reason : (f.rejected ? 'The reviewer rejected this photo.' : 'The reviewer asked for this photo to be replaced.');
    final meta = [if (f.note?.by != null) f.note!.by!, if (f.note?.at != null) fmtDateTime(f.note!.at!)].join('  |  ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AdinnColors.redLight, borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 64, height: 64, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: AppFileRow.image(f.photo.displayUrl, null))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(f.angle, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (f.board.isNotEmpty) TagChip(f.board, icon: Icons.view_in_ar_outlined),
              ReworkTag(text: f.rejected ? 'Rejected' : 'Rework'),
              if (f.answered) const TagChip('New photo ready', icon: Icons.check_circle, color: AdinnColors.success),
            ]),
            const SizedBox(height: 4),
            Text(f.rejected ? 'Reason: $reason' : reason, style: const TextStyle(color: AdinnColors.redDark, fontWeight: FontWeight.w600, fontSize: 13)),
            if (meta.isNotEmpty) Text(meta, style: const TextStyle(fontSize: 11.5, color: AdinnColors.muted)),
          ]),
        ),
      ]),
    );
  }
}

class _BoardFixTile extends StatelessWidget {
  const _BoardFixTile(this.f);
  final FlaggedBoardFix f;

  @override
  Widget build(BuildContext context) {
    final reason = f.note.reason.isNotEmpty ? f.note.reason : 'The reviewer asked you to ${boardFixTitle(f.type).toLowerCase()} of this board.';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AdinnColors.redLight, borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.view_in_ar_outlined, color: AdinnColors.red),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${f.board}  |  ${f.title}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(f.rejected ? 'Reason: $reason' : reason, style: const TextStyle(color: AdinnColors.redDark, fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

class _RequestedTile extends StatelessWidget {
  const _RequestedTile(this.r);
  final FlaggedRequest r;

  @override
  Widget build(BuildContext context) {
    final reason = r.note.reason;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AdinnColors.redLight, borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.add_a_photo_outlined, color: AdinnColors.red),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r.label}${r.board.isEmpty ? '' : '  |  ${r.board}'}${r.answered ? '  (done)' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
            if (reason.isNotEmpty) Text(reason, style: const TextStyle(color: AdinnColors.redDark, fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}
