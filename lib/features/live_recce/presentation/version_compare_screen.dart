import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_file_row.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/history_controllers.dart';
import '../data/recce_api.dart';
import '../data/recce_models.dart';
import 'live_widgets.dart';

/// Version Comparison: pick two versions (default: previous and latest) and see what changed: photos added / replaced /
/// unchanged / removed, board size changes ("6 x 4 ft -> 8 x 4 ft"), installation answers, notes, and each version's reviewer
/// comments. Everything is read from `GET /recce/shops/:siteId/versions/compare`.
class VersionCompareScreen extends StatefulWidget {
  const VersionCompareScreen({super.key, required this.api, required this.siteId, required this.shopTitle, required this.versions});

  final RecceApi api;
  final String siteId;
  final String shopTitle;
  final List<RecceVersion> versions;

  @override
  State<VersionCompareScreen> createState() => _VersionCompareScreenState();
}

class _VersionCompareScreenState extends State<VersionCompareScreen> {
  late final CompareController _ctrl = CompareController(widget.api, widget.siteId, widget.versions)..load();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compare versions')),
      body: ListenableBuilder(
        listenable: _ctrl,
        builder: (context, _) {
          if (!_ctrl.canCompare) {
            return const EmptyState(icon: Icons.compare_arrows, title: 'Only one version so far', message: 'Comparison opens after a second version is submitted.');
          }
          // Pull down to read the comparison again: its photo pictures are signed links that expire after about 10 minutes.
          return RefreshIndicator(
            onRefresh: _ctrl.load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(widget.shopTitle, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _Picker(label: 'From', value: _ctrl.from, versions: _ctrl.versions, onChanged: (v) => _ctrl.select(from: v))),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.arrow_forward, color: AdinnColors.muted)),
                  Expanded(child: _Picker(label: 'To', value: _ctrl.to, versions: _ctrl.versions, onChanged: (v) => _ctrl.select(to: v))),
                ]),
                const SizedBox(height: 14),
                if (_ctrl.loading && _ctrl.result == null)
                  const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                else if (_ctrl.error != null && _ctrl.result == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(children: [
                      Text(_ctrl.error!, textAlign: TextAlign.center, style: const TextStyle(color: AdinnColors.red)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(onPressed: _ctrl.load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                    ]),
                  )
                else if (_ctrl.result != null) ...[
                  if (_ctrl.loading) const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator(minHeight: 3)),
                  CompareBody(result: _ctrl.result!, versionOf: _ctrl.versionNo),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({required this.label, required this.value, required this.versions, required this.onChanged});

  final String label;
  final int value;
  final List<RecceVersion> versions;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: versions.any((v) => v.version == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final v in versions) DropdownMenuItem(value: v.version, child: Text('V${v.version}${v.submittedAt != null ? '  ${fmtDate(v.submittedAt!)}' : ''}', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// The answer of a comparison as cards. [versionOf] gives the full board of each version so a size change reads "6 x 4 ft -> 8 x 4 ft".
class CompareBody extends StatelessWidget {
  const CompareBody({super.key, required this.result, required this.versionOf});

  final VersionCompare result;
  final RecceVersion? Function(int) versionOf;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final a = versionOf(r.from.version);
    final b = versionOf(r.to.version);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubmissionCard(r),
        const SizedBox(height: 12),
        if (!r.changed)
          const SectionCard(
            child: Row(children: [
              Icon(Icons.check_circle_outline, color: AdinnColors.success),
              SizedBox(width: 8),
              Expanded(child: Text('Nothing changed between these two versions.')),
            ]),
          ),
        if (r.boardsChanged.isNotEmpty || r.boardsAdded.isNotEmpty || r.boardsRemoved.isNotEmpty) ...[
          SectionCard(
            title: 'Measurements and boards',
            icon: Icons.straighten,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final c in r.boardsChanged) _BoardChangeTile(change: c, before: a?.board(c.key), after: b?.board(c.key)),
              for (final i in r.boardsAdded) _Line(icon: Icons.add_circle_outline, color: AdinnColors.success, text: 'Board added: ${i.key} ${boardSummaryText(i)}'),
              for (final i in r.boardsRemoved) _Line(icon: Icons.remove_circle_outline, color: AdinnColors.red, text: 'Board removed: ${i.key} ${boardSummaryText(i)}'),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        if (r.replaced.isNotEmpty || r.added.isNotEmpty || r.removed.isNotEmpty || r.unchanged.isNotEmpty) ...[
          SectionCard(
            title: 'Photos',
            icon: Icons.photo_library_outlined,
            trailing: Text('${r.replaced.length} replaced | ${r.added.length} added | ${r.removed.length} removed', style: const TextStyle(fontSize: 11, color: AdinnColors.muted)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (r.replaced.isNotEmpty) ...[
                _Sub('Replaced', Icons.swap_horiz, AdinnColors.warning, r.replaced.length),
                for (final p in r.replaced) _ReplacedCard(p, fromVersion: r.from.version, toVersion: r.to.version),
              ],
              if (r.added.isNotEmpty) ...[
                _Sub('Added in V${r.to.version}', Icons.add_a_photo_outlined, AdinnColors.success, r.added.length),
                _PhotoWrap(r.added),
              ],
              if (r.removed.isNotEmpty) ...[
                _Sub('Removed', Icons.delete_outline, AdinnColors.red, r.removed.length),
                _PhotoWrap(r.removed),
              ],
              if (r.unchanged.isNotEmpty) ...[
                _Sub('Unchanged', Icons.check_circle_outline, AdinnColors.muted, r.unchanged.length),
                _PhotoWrap(r.unchanged, small: true),
              ],
            ]),
          ),
          const SizedBox(height: 12),
        ],
        if (r.installation.isNotEmpty) ...[
          SectionCard(
            title: 'Installation changes',
            icon: Icons.construction_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final c in r.installation) _Line(icon: Icons.edit_outlined, color: AdinnColors.warning, text: c.text),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        if (r.notesChanged) ...[
          SectionCard(
            title: 'Notes changed',
            icon: Icons.notes_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('V${r.from.version}: ${(r.notesFrom ?? '').isEmpty ? 'no notes' : r.notesFrom!}', style: const TextStyle(color: AdinnColors.muted)),
              const SizedBox(height: 4),
              Text('V${r.to.version}: ${(r.notesTo ?? '').isEmpty ? 'no notes' : r.notesTo!}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        _CommentsCard(r),
      ],
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard(this.r);
  final VersionCompare r;

  @override
  Widget build(BuildContext context) {
    Widget side(CompareSide s, String tag) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tag, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AdinnColors.muted)),
            Text('V${s.version}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AdinnColors.red)),
            if (s.submittedAt != null) Text(fmtDateTime(s.submittedAt!), style: const TextStyle(fontSize: 12)),
            if (s.submittedBy != null) Text('by ${s.submittedBy}', style: const TextStyle(fontSize: 12, color: AdinnColors.muted)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [side(r.from, 'FROM'), const Icon(Icons.arrow_forward, color: AdinnColors.muted), const SizedBox(width: 12), side(r.to, 'TO')]),
      ),
    );
  }
}

class _BoardChangeTile extends StatelessWidget {
  const _BoardChangeTile({required this.change, this.before, this.after});

  final BoardChange change;
  final BoardItem? before;
  final BoardItem? after;

  @override
  Widget build(BuildContext context) {
    final headline = change.sizeHeadline(before: before, after: after);
    final others = [for (final f in change.fields) if (!const {'width', 'height', 'unit'}.contains(f.field)) f];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AdinnColors.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: AdinnColors.warning.withValues(alpha: 0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          TagChip(change.key, icon: Icons.label_outline),
          const SizedBox(width: 8),
          Expanded(child: Text(change.name, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        if (headline != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(headline, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AdinnColors.redDark))),
        if (change.sizeChanged && headline != null && change.field('unit') != null) Text(change.field('unit')!.text, style: const TextStyle(fontSize: 13)),
        for (final f in others) Text(f.text, style: const TextStyle(fontSize: 13)),
      ]),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      );
}

class _Sub extends StatelessWidget {
  const _Sub(this.text, this.icon, this.color, this.count);
  final String text;
  final IconData icon;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text('$text ($count)', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ]),
      );
}

String photoCaptionText(ShopPhoto p) => [
      if (p.hasGps) 'GPS ${p.lat!.toStringAsFixed(5)}, ${p.lng!.toStringAsFixed(5)}${p.gpsAccuracy != null ? ' (${p.gpsAccuracy!.toStringAsFixed(0)} m)' : ''}' else 'No GPS',
      if (p.capturedAt != null) fmtDateTime(p.capturedAt!),
    ].join('\n');

class _Thumb extends StatelessWidget {
  const _Thumb(this.p, {this.title});
  final ShopPhoto p;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final name = photoCategoryLabel(p.category);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(title!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AdinnColors.muted))),
      GestureDetector(
        onTap: p.displayUrl == null ? null : () => showAppPhotoViewer(context, title: name, url: p.displayUrl),
        child: AspectRatio(aspectRatio: 4 / 3, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: AppFileRow.image(p.displayUrl, null))),
      ),
      const SizedBox(height: 4),
      Text(photoCaptionText(p), style: const TextStyle(fontSize: 11, color: AdinnColors.muted)),
    ]);
  }
}

/// Old photo and new photo side by side, with GPS and capture time under each.
class _ReplacedCard extends StatelessWidget {
  const _ReplacedCard(this.r, {required this.fromVersion, required this.toVersion});
  final ReplacedPhoto r;
  final int fromVersion;
  final int toVersion;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AdinnColors.canvas, borderRadius: BorderRadius.circular(10), border: Border.all(color: AdinnColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(photoCategoryLabel(r.to.category), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _Thumb(r.from, title: 'OLD  V$fromVersion')),
          const SizedBox(width: 10),
          Expanded(child: _Thumb(r.to, title: 'NEW  V$toVersion')),
        ]),
      ]),
    );
  }
}

class _PhotoWrap extends StatelessWidget {
  const _PhotoWrap(this.photos, {this.small = false});
  final List<ShopPhoto> photos;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = small ? 3 : 2;
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final p in photos)
          SizedBox(
            width: w,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Thumb(p),
              Text(photoCategoryLabel(p.category), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
      ]);
    });
  }
}

class _CommentsCard extends StatelessWidget {
  const _CommentsCard(this.r);
  final VersionCompare r;

  @override
  Widget build(BuildContext context) {
    Widget block(CompareSide s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 6, bottom: 2), child: Text('V${s.version} reviewers', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
          if (s.reviewerComments.isEmpty)
            const Text('No reviewer decisions on this version.', style: TextStyle(color: AdinnColors.muted, fontSize: 13))
          else
            for (final d in s.reviewerComments) StageDecisionTile(d, dense: true),
        ]);
    return SectionCard(
      title: 'Reviewer comments',
      icon: Icons.rate_review_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [block(r.from), const Divider(), block(r.to)]),
    );
  }
}
