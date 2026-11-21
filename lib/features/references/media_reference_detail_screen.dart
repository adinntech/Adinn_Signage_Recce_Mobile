import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../model3d/signage_spec.dart';
import 'media_reference_library_screen.dart';
import 'reference_image_picker.dart';

/// References of one catalog media: register (gallery photo or external
/// link), edit metadata, submit for review, reviewer checklist with
/// approve / reject, and replacement that keeps the old record.
class MediaReferenceDetailScreen extends StatelessWidget {
  const MediaReferenceDetailScreen({
    super.key,
    required this.mediaCode,
    this.picker,
  });

  final String mediaCode;

  /// Injectable gallery picker (tests); defaults to image_picker.
  final ReferenceImagePicker? picker;

  ReferenceImagePicker get _picker =>
      picker ?? const GalleryReferenceImagePicker();

  Future<void> _add(BuildContext context, {MediaReference? replacing}) async {
    final c = context.read<AppController>();
    final draft = await showReferenceForm(
      context,
      mediaCode: mediaCode,
      picker: _picker,
      title: replacing == null ? 'Add reference' : 'Replace reference',
    );
    if (draft == null || !context.mounted) return;
    try {
      if (replacing == null) {
        c.registerReference(
          mediaCode: mediaCode,
          sourceCategory: draft.sourceCategory,
          installationCode: draft.installationCode,
          sourceUrl: draft.sourceUrl,
          localPath: draft.localPath,
          owner: draft.owner,
          label: draft.label,
          usageRights: draft.usageRights,
          technicalNotes: draft.notes,
        );
        showSnack(context, 'Reference registered');
      } else {
        c.replaceReference(
          replacing.id,
          sourceCategory: draft.sourceCategory,
          installationCode: draft.installationCode,
          sourceUrl: draft.sourceUrl,
          localPath: draft.localPath,
          owner: draft.owner,
          label: draft.label,
          usageRights: draft.usageRights,
          technicalNotes: draft.notes,
        );
        showSnack(context, 'Reference replaced – the old one is kept');
      }
    } on Object catch (e) {
      showSnack(context, _message(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final m = SignageCatalog.media(mediaCode);
    final current = c.referencesFor(mediaCode, includeSuperseded: false);
    final history = c
        .referencesFor(mediaCode)
        .where((r) => r.isSuperseded)
        .toList();
    final status = c.referenceLibraryStatus(mediaCode);
    final model = c.modelStatus(mediaCode);
    return Scaffold(
      appBar: AppBar(title: Text(m?.name ?? mediaCode)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SectionCard(
            title: m?.shortName ?? mediaCode,
            icon: m?.icon ?? Icons.image_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    TagChip(
                      referenceStatusShort(status),
                      key: const Key('ref_library_status'),
                      color: referenceStatusColor(status),
                    ),
                    TagChip(
                      model.label,
                      key: const Key('ref_model_status'),
                      color: modelStatusColor(model),
                      icon: Icons.view_in_ar_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  c.canReviewReferences
                      ? 'You can verify the 7 technical checks and approve '
                            'or reject references awaiting review.'
                      : 'Collect a factory / internal photo or link an '
                            'external image, then send it for technical '
                            'review by the Business Team or Recce Operations.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdinnColors.muted,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const Key('ref_add'),
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add reference'),
                ),
              ],
            ),
          ),
          if (current.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(
                icon: Icons.hide_image_outlined,
                title: 'Pending Reference',
                message:
                    'No reference collected yet. The 3D model of this media '
                    'is illustrative only.',
              ),
            ),
          for (final r in current)
            _ReferenceCard(
              reference: r,
              onReplace: () => _add(context, replacing: r),
              picker: _picker,
            ),
          if (history.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
              child: Text(
                'Replaced references (kept for history)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AdinnColors.muted,
                ),
              ),
            ),
            for (final r in history)
              _ReferenceCard(reference: r, picker: _picker),
          ],
        ],
      ),
    );
  }
}

String _message(Object e) => switch (e) {
  StateError(:final message) => message,
  ArgumentError(:final message) => '$message',
  _ => '$e',
};

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({
    required this.reference,
    required this.picker,
    this.onReplace,
  });

  final MediaReference reference;
  final ReferenceImagePicker picker;
  final VoidCallback? onReplace;

  Future<void> _edit(BuildContext context) async {
    final c = context.read<AppController>();
    final r = reference;
    final draft = await showReferenceForm(
      context,
      mediaCode: r.mediaCode,
      picker: picker,
      title: 'Edit reference',
      initial: r,
    );
    if (draft == null || !context.mounted) return;
    try {
      c.updateReference(
        r.id,
        owner: draft.owner,
        label: draft.label,
        usageRights: draft.usageRights,
        sourceUrl: draft.sourceUrl ?? '',
        localPath: draft.localPath ?? '',
        installationCode: draft.installationCode,
        clearInstallation: draft.installationCode == null,
        technicalNotes: draft.notes,
      );
    } on Object catch (e) {
      showSnack(context, _message(e), error: true);
    }
  }

  Future<void> _reject(BuildContext context) async {
    final c = context.read<AppController>();
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject reference'),
        content: TextField(
          key: const Key('ref_reject_reason'),
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason (required)',
            hintText: 'e.g. Shows a non-lit board, frame not visible',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('ref_reject_confirm'),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;
    try {
      c.rejectReference(reference.id, reason);
      showSnack(context, 'Reference rejected');
    } on Object catch (e) {
      showSnack(context, _message(e), error: true);
    }
  }

  void _run(BuildContext context, void Function() action, String done) {
    try {
      action();
      showSnack(context, done);
    } on Object catch (e) {
      showSnack(context, _message(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final r = reference;
    final reviewer = c.canReviewReferences;
    final awaiting =
        !r.isSuperseded && r.status == ReferenceStatus.awaitingTechnicalReview;
    final canSubmit =
        !r.isSuperseded &&
        r.hasSource &&
        (r.status == ReferenceStatus.collected ||
            r.status == ReferenceStatus.rejected);
    final locked = r.isSuperseded || r.isApproved;
    final blocker = referenceApprovalBlocker(r);
    final inst = SignageCatalog.installation(r.installationCode);
    return Card(
      key: Key('ref_card_${r.id}'),
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumb(reference: r),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    r.label.isNotEmpty ? r.label : r.sourceCategory.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                TagChip(
                  r.isSuperseded
                      ? 'Superseded'
                      : referenceStatusShort(r.status),
                  color: r.isSuperseded
                      ? AdinnColors.muted
                      : referenceStatusColor(r.status),
                ),
                TagChip(r.sourceCategory.label),
                TagChip(
                  'Rights: ${r.usageRights.label}',
                  color: r.usageRights.cleared
                      ? AdinnColors.success
                      : AdinnColors.warning,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (r.sourceUrl != null)
              SelectableText(
                'Source: ${r.sourceUrl}',
                style: const TextStyle(fontSize: 12, color: AdinnColors.info),
              ),
            _line('Owner / photographer', r.owner),
            _line('Installation', inst?.name ?? ''),
            _line(
              'Registered',
              '${fmtDateTime(r.createdAt)}'
                  '${r.createdByName.isEmpty ? '' : ' by ${r.createdByName}'}',
            ),
            if (r.isApproved)
              _line(
                'Approved',
                '${r.approvedByName} (${r.approvedByRole?.label ?? '-'}), '
                    '${fmtDateTime(r.approvedAt!)}',
              ),
            if (r.rejectionReason != null)
              _line(
                r.status == ReferenceStatus.rejected
                    ? 'Rejected'
                    : 'Last rejection',
                '${r.rejectionReason}'
                '${r.rejectedByName == null ? '' : ' – ${r.rejectedByName}'}',
                color: AdinnColors.redDark,
              ),
            _line('Technical notes', r.technicalNotes),
            if (r.isSuperseded)
              _line('Replaced by', 'newer reference (record kept)'),
            if (awaiting || r.checksPassed > 0) ...[
              const Divider(height: 18),
              Text(
                'Technical checks (${r.checksPassed}/'
                '${TechnicalCheck.values.length})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final check in TechnicalCheck.values)
                CheckboxListTile(
                  key: Key('ref_check_${check.index}_${r.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(check.label),
                  value: r.technicalChecks[check] == true,
                  onChanged: reviewer && awaiting
                      ? (v) => _run(
                          context,
                          () => c.setReferenceCheck(r.id, check, v ?? false),
                          check.label,
                        )
                      : null,
                ),
            ],
            if (reviewer && awaiting && blocker != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  blocker,
                  key: Key('ref_blocker_${r.id}'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdinnColors.warning,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                if (!locked)
                  TextButton.icon(
                    key: Key('ref_edit_${r.id}'),
                    onPressed: () => _edit(context),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                if (onReplace != null && !r.isSuperseded)
                  TextButton.icon(
                    key: Key('ref_replace_${r.id}'),
                    onPressed: onReplace,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Replace'),
                  ),
                if (canSubmit)
                  FilledButton.tonalIcon(
                    key: Key('ref_submit_${r.id}'),
                    onPressed: () => _run(
                      context,
                      () => c.submitReferenceForReview(r.id),
                      'Sent for technical review',
                    ),
                    icon: const Icon(Icons.send_outlined, size: 18),
                    label: const Text('Submit for review'),
                  ),
                if (reviewer && awaiting) ...[
                  OutlinedButton(
                    key: Key('ref_reject_${r.id}'),
                    onPressed: () => _reject(context),
                    child: const Text('Reject'),
                  ),
                  FilledButton(
                    key: Key('ref_approve_${r.id}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AdinnColors.success,
                    ),
                    onPressed: blocker == null
                        ? () => _run(
                            context,
                            () => c.approveReference(r.id),
                            'Reference approved',
                          )
                        : null,
                    child: const Text('Approve'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value, {Color? color}) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: AdinnColors.muted),
            ),
            TextSpan(
              text: value,
              style: TextStyle(color: color),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.reference});

  final MediaReference reference;

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    final path = reference.localPath;
    Widget child;
    if (path != null && path.isNotEmpty) {
      child = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: 216,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.broken_image_outlined, color: AdinnColors.muted),
      );
    } else {
      child = Icon(
        reference.sourceUrl != null ? Icons.link : Icons.hide_image_outlined,
        color: AdinnColors.muted,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: AdinnColors.canvas,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// Values entered in the reference form.
class ReferenceDraft {
  const ReferenceDraft({
    required this.sourceCategory,
    required this.usageRights,
    this.sourceUrl,
    this.localPath,
    this.installationCode,
    this.owner = '',
    this.label = '',
    this.notes = '',
  });

  final ReferenceSourceCategory sourceCategory;
  final ReferenceUsageRights usageRights;
  final String? sourceUrl;
  final String? localPath;
  final String? installationCode;
  final String owner;
  final String label;
  final String notes;
}

/// Opens the add / edit / replace form. Returns null when cancelled.
Future<ReferenceDraft?> showReferenceForm(
  BuildContext context, {
  required String mediaCode,
  required ReferenceImagePicker picker,
  required String title,
  MediaReference? initial,
}) => showModalBottomSheet<ReferenceDraft>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ReferenceForm(
    mediaCode: mediaCode,
    picker: picker,
    title: title,
    initial: initial,
  ),
);

class _ReferenceForm extends StatefulWidget {
  const _ReferenceForm({
    required this.mediaCode,
    required this.picker,
    required this.title,
    this.initial,
  });

  final String mediaCode;
  final ReferenceImagePicker picker;
  final String title;
  final MediaReference? initial;

  @override
  State<_ReferenceForm> createState() => _ReferenceFormState();
}

class _ReferenceFormState extends State<_ReferenceForm> {
  late ReferenceSourceCategory _category;
  late ReferenceUsageRights _rights;
  String? _installation;
  String? _localPath;
  late final TextEditingController _url;
  late final TextEditingController _owner;
  late final TextEditingController _label;
  late final TextEditingController _notes;
  String? _error;
  bool _picking = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _category = r?.sourceCategory ?? ReferenceSourceCategory.factory;
    _rights = r?.usageRights ?? ReferenceUsageRights.unknown;
    _installation = r?.installationCode;
    _localPath = r?.localPath;
    _url = TextEditingController(text: r?.sourceUrl ?? '');
    _owner = TextEditingController(text: r?.owner ?? '');
    _label = TextEditingController(text: r?.label ?? '');
    _notes = TextEditingController(text: r?.technicalNotes ?? '');
  }

  @override
  void dispose() {
    _url.dispose();
    _owner.dispose();
    _label.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final media = context.read<AppController>().media;
    setState(() => _picking = true);
    try {
      final path = await widget.picker.pickAndStore(media);
      if (path != null && mounted) setState(() => _localPath = path);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not add the photo: $e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _save() {
    final url = _url.text.trim();
    final external = _category == ReferenceSourceCategory.external;
    if (external && url.isEmpty) {
      setState(() => _error = 'External references need the source URL.');
      return;
    }
    if (url.isNotEmpty && !isValidReferenceUrl(url)) {
      setState(() => _error = 'Enter a valid http(s) link.');
      return;
    }
    Navigator.pop(
      context,
      ReferenceDraft(
        sourceCategory: _category,
        usageRights: _rights,
        sourceUrl: url.isEmpty ? null : url,
        localPath: external ? null : _localPath,
        installationCode: _installation,
        owner: _owner.text,
        label: _label.text,
        notes: _notes.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final external = _category == ReferenceSourceCategory.external;
    final installs = SignageCatalog.installationsFor(widget.mediaCode);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text('Source', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final cat in ReferenceSourceCategory.values)
                  ChoiceChip(
                    key: Key('ref_source_${cat.name}'),
                    label: Text(cat.label),
                    selected: _category == cat,
                    onSelected: _editing
                        ? null
                        : (_) => setState(() {
                            _category = cat;
                            _error = null;
                            if (cat == ReferenceSourceCategory.external) {
                              _rights = ReferenceUsageRights.unknown;
                            }
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (!external) ...[
              OutlinedButton.icon(
                key: const Key('ref_pick_image'),
                onPressed: _picking ? null : _pick,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(
                  _localPath == null
                      ? 'Pick photo from gallery'
                      : 'Photo added – pick another',
                ),
              ),
              if (_localPath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _localPath!.split(RegExp(r'[\\/]')).last,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AdinnColors.muted,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
            TextField(
              key: const Key('ref_url'),
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: external
                    ? 'Source URL (required)'
                    : 'Source URL (optional)',
                hintText: 'https://…',
              ),
            ),
            if (external)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Link only – the web image is not downloaded or bundled. '
                  'Usage rights stay "Unknown" until recorded, so it cannot '
                  'be approved before that.',
                  style: TextStyle(fontSize: 11, color: AdinnColors.muted),
                ),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ReferenceUsageRights>(
              key: const Key('ref_rights'),
              isExpanded: true,
              initialValue: _rights,
              decoration: const InputDecoration(labelText: 'Usage rights'),
              items: [
                for (final r in ReferenceUsageRights.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (v) => setState(() => _rights = v ?? _rights),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('ref_owner'),
              controller: _owner,
              decoration: const InputDecoration(
                labelText: 'Owner / photographer',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('ref_label'),
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Caption',
                hintText: 'e.g. Factory sample – front view',
              ),
            ),
            if (installs.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                key: const Key('ref_installation'),
                isExpanded: true,
                initialValue: _installation,
                decoration: const InputDecoration(
                  labelText: 'Installation (optional)',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Any / not specified'),
                  ),
                  for (final i in installs)
                    DropdownMenuItem<String?>(
                      value: i.code,
                      child: Text(i.name),
                    ),
                ],
                onChanged: (v) => setState(() => _installation = v),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              key: const Key('ref_notes'),
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Technical notes'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('ref_form_error'),
                  style: const TextStyle(color: AdinnColors.redDark),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('ref_save'),
              onPressed: _picking ? null : _save,
              child: const Text('Save reference'),
            ),
          ],
        ),
      ),
    );
  }
}
