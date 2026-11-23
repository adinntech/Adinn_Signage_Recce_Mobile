import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../drawing/drawing_2d_screen.dart';
import '../notes/voice_notes_section.dart';
import '../photos/photo_section.dart';
import '../preview3d/preview_3d_screen.dart';
import '../ar/camera_ar_screen.dart';
import '../preview_live/preview_gallery.dart';
import 'media_type_grid.dart';
import 'quantity_size_section.dart';
import 'site_questions_form.dart';

/// Step-by-step capture of one signage board:
/// media → installation → site questions → measurements → photos → notes →
/// drawings. Every change is saved locally immediately.
class BoardEditorScreen extends StatefulWidget {
  const BoardEditorScreen({
    super.key,
    required this.shopId,
    required this.boardId,
    this.initialStep,
  });

  final String shopId;
  final String boardId;

  /// Step to open (e.g. 3 = Measurements from the Camera AR dimension
  /// panel). Null = first incomplete step (default behaviour).
  final int? initialStep;

  /// Index of the Measurements step.
  static const measurementsStep = 3;

  @override
  State<BoardEditorScreen> createState() => _BoardEditorScreenState();
}

class _BoardEditorScreenState extends State<BoardEditorScreen> {
  int _step = 0;
  final _name = TextEditingController();
  final _w = TextEditingController();
  final _h = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    final b = context.read<AppController>().board(
      widget.shopId,
      widget.boardId,
    );
    if (b != null) {
      _name.text = b.name;
      _syncSize(b);
      _note.text = b.textNote;
      // Jump to the requested step, else the first incomplete one.
      _step = widget.initialStep?.clamp(0, 6) ?? _firstIncomplete(b);
    }
  }

  void _syncSize(Board b) {
    _w.text = b.width == null ? '' : fmtNum(b.width!);
    _h.text = b.height == null ? '' : fmtNum(b.height!);
  }

  @override
  void dispose() {
    _name.dispose();
    _w.dispose();
    _h.dispose();
    _note.dispose();
    super.dispose();
  }

  bool _mediaDone(Board b) => SignageCatalog.media(b.mediaCode) != null;
  bool _installDone(Board b) =>
      _mediaDone(b) &&
      (SignageCatalog.media(
        b.mediaCode,
      )!.installations.contains(b.installationCode));
  bool _questionsDone(Board b) =>
      _installDone(b) && SignageCatalog.missingAnswers(b).isEmpty;

  int _firstIncomplete(Board b) {
    if (!_mediaDone(b)) return 0;
    if (!_installDone(b)) return 1;
    if (!_questionsDone(b)) return 2;
    if (!b.hasSize) return 3;
    if (b.photos.isEmpty) return 4;
    return 0;
  }

  /// Answers that no longer apply move to [Board.answersArchive] (never
  /// silently lost); archived answers that apply again are restored.
  int _pruneAnswers(Board b) {
    final ids = SignageCatalog.questionsFor(
      b.mediaCode,
      b.installationCode,
    ).map((q) => q.id).toSet();
    final moved = <String>[];
    b.answers.removeWhere((k, v) {
      if (ids.contains(k)) return false;
      b.answersArchive[k] = v;
      moved.add(k);
      return true;
    });
    for (final k in ids) {
      if (!b.answers.containsKey(k) && b.answersArchive.containsKey(k)) {
        b.answers[k] = b.answersArchive.remove(k);
      }
    }
    return moved.length;
  }

  void _notePruned(int n) {
    if (n == 0 || !mounted) return;
    showSnack(
      context,
      '$n answer${n == 1 ? '' : 's'} no longer apply – kept aside and '
      'restored if you switch back.',
    );
  }

  void _selectMedia(AppController c, Board b, MediaType m) {
    if (b.mediaCode == m.code) {
      setState(() => _step = 1);
      return;
    }
    b.mediaCode = m.code;
    if (!m.installations.contains(b.installationCode)) {
      b.installationCode = m.installations.length == 1
          ? m.installations.first
          : null;
    }
    final pruned = _pruneAnswers(b);
    c.touchBoard(
      widget.shopId,
      b,
      title: 'Board updated',
      message: '${b.name}: media set to ${m.shortName}.',
    );
    _notePruned(pruned);
    setState(() => _step = 1);
  }

  Future<void> _mapLegacy(
    AppController c,
    Board b,
    String code,
    bool? doubleSided,
  ) async {
    final m = SignageCatalog.media(code);
    if (m == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Map to ${m.name}?',
      message:
          'This media group will use the catalog media "${m.name}". The '
          'original type is kept in its history and submitted versions do '
          'not change.',
      confirmText: 'Map',
    );
    if (!ok || !mounted) return;
    c.mapLegacyMedia(widget.shopId, b, code, doubleSided: doubleSided);
    _notePruned(_pruneAnswers(b));
    c.touchBoard(widget.shopId, b);
  }

  void _selectInstallation(AppController c, Board b, InstallationType i) {
    b.installationCode = i.code;
    final pruned = _pruneAnswers(b);
    c.touchBoard(
      widget.shopId,
      b,
      title: 'Board updated',
      message: '${b.name}: installation set to ${i.name}.',
    );
    _notePruned(pruned);
    setState(() => _step = 2);
  }

  StepState _state(bool done, int index, bool editable) {
    if (done) return StepState.complete;
    if (!editable) return StepState.disabled;
    return _step == index ? StepState.editing : StepState.indexed;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(widget.shopId);
    final board = c.board(widget.shopId, widget.boardId);
    if (shop == null || board == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'Board not found',
        ),
      );
    }
    final editable = c.canEdit(shop);
    final media = SignageCatalog.media(board.mediaCode);
    final inst = SignageCatalog.installation(board.installationCode);
    final issues = c.boardIssues(board);
    final warnings = c.boardWarnings(board, shop.geo);
    final questions = SignageCatalog.questionsFor(
      board.mediaCode,
      board.installationCode,
    );

    final steps = <Step>[
      Step(
        title: const Text('Media type'),
        subtitle: Text(
          media?.name ??
              'Choose one of ${SignageCatalog.catalogCodes.length} media types',
        ),
        state: _state(_mediaDone(board), 0, editable),
        isActive: _step >= 0,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (SignageCatalog.isLegacy(board.mediaCode))
              _LegacyMediaCard(
                board: board,
                editable: editable,
                onMap: (code, sides) => _mapLegacy(c, board, code, sides),
              ),
            MediaTypeGrid(
              selected: board.mediaCode,
              enabled: editable,
              onSelect: (m) => _selectMedia(c, board, m),
            ),
            if (media?.sidedness == MediaSidedness.selectable)
              _SidednessChoice(
                doubleSided: board.doubleSided ?? false,
                enabled: editable,
                onChanged: (v) => c.setDoubleSided(widget.shopId, board, v),
              ),
          ],
        ),
      ),
      Step(
        title: const Text('Installation type'),
        subtitle: Text(inst?.name ?? 'Depends on media'),
        state: _state(_installDone(board), 1, editable),
        isActive: _step >= 1,
        content: media == null
            ? const Text('Select a media type first.')
            : Column(
                children: [
                  for (final i in SignageCatalog.installationsFor(media.code))
                    _OptionTile(
                      key: Key('inst_${i.code}'),
                      icon: i.icon,
                      title: i.name,
                      subtitle: i.description,
                      selected: board.installationCode == i.code,
                      onTap: editable
                          ? () => _selectInstallation(c, board, i)
                          : null,
                    ),
                ],
              ),
      ),
      Step(
        title: const Text('Site questions'),
        subtitle: Text(
          _installDone(board)
              ? '${SignageCatalog.missingAnswers(board).length} required pending'
              : 'Loaded after installation',
        ),
        state: _state(_questionsDone(board), 2, editable),
        isActive: _step >= 2,
        content: SiteQuestionsForm(
          key: ValueKey('${board.mediaCode}_${board.installationCode}'),
          questions: questions,
          answers: board.answers,
          enabled: editable,
          onChanged: (id, v) {
            if (v == null) {
              board.answers.remove(id);
            } else {
              board.answers[id] = v;
            }
            // Keep the canonical measurement in step with mirrored answers.
            c.syncAnswerToMeasurements(board, id);
            c.touchBoard(widget.shopId, board);
          },
        ),
      ),
      Step(
        title: const Text('Measurements'),
        subtitle: Text(
          !board.hasSize
              ? (board.quantity > 1
                    ? 'Quantity ${board.quantity} • width × height'
                    : 'Width × height')
              : board.isSameSize
              ? '${fmtSize(board.width, board.height, board.unit)}'
                    '${board.quantity > 1 ? ' ×${board.quantity}' : ''}'
                    ' • ${fmtNum(board.areaSqFt)} sq ft'
              : '${board.quantity} units, different sizes • '
                    '${fmtNum(board.areaSqFt)} sq ft',
        ),
        state: _state(board.hasSize, 3, editable),
        isActive: _step >= 3,
        content: _MeasurementsForm(
          shopId: widget.shopId,
          board: board,
          name: _name,
          w: _w,
          h: _h,
          enabled: editable,
          onChanged: () => c.touchBoard(widget.shopId, board),
        ),
      ),
      Step(
        title: const Text('Site photos & annotation'),
        subtitle: Text(
          '${board.photos.length} photo(s) • ${board.annotationCount} marking(s)'
          '${board.previews.isEmpty ? '' : ' • ${board.previews.length} preview(s)'}',
        ),
        state: _state(board.photos.isNotEmpty, 4, editable),
        isActive: _step >= 4,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PhotoSection(
              shopId: widget.shopId,
              board: board,
              editable: editable,
              onBoardSizeApplied: () => setState(() => _syncSize(board)),
            ),
            if (board.previews.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Live previews, AR captures & exports',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              PreviewGallery(
                board: board,
                shopId: widget.shopId,
                editable: editable,
              ),
            ],
          ],
        ),
      ),
      Step(
        title: const Text('Voice & text notes'),
        subtitle: Text(
          '${board.voiceNotes.length} voice • ${board.textNote.isEmpty ? 'no' : '1'} text',
        ),
        state: _state(
          board.voiceNotes.isNotEmpty || board.textNote.isNotEmpty,
          5,
          editable,
        ),
        isActive: _step >= 5,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('board_text_note'),
              controller: _note,
              enabled: editable,
              maxLines: 4,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Text note',
                hintText: 'Obstructions, owner requests, electrical points…',
                alignLabelWithHint: true,
              ),
              onChanged: (t) {
                board.textNote = t;
                c.touchBoard(widget.shopId, board);
              },
            ),
            const SizedBox(height: 12),
            VoiceNotesSection(
              shopId: widget.shopId,
              board: board,
              editable: editable,
            ),
          ],
        ),
      ),
      Step(
        title: const Text('2D drawing & 3D preview'),
        subtitle: Text(
          board.drawingPath == null ? 'Auto-generated' : 'Drawing saved',
        ),
        state: board.drawingPath != null
            ? StepState.complete
            : (_step == 6 ? StepState.editing : StepState.indexed),
        isActive: _step >= 6,
        content: _DrawingsStep(shopId: widget.shopId, board: board),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(board.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '2D drawing',
            icon: const Icon(Icons.architecture),
            onPressed: () => _open2D(context, board),
          ),
          IconButton(
            tooltip: '3D preview',
            icon: const Icon(Icons.view_in_ar),
            onPressed: () => _open3D(context, board),
          ),
        ],
      ),
      body: Column(
        children: [
          _Header(
            shopName: shop.name,
            board: board,
            issues: issues,
            warnings: warnings,
            readOnly: !editable,
          ),
          Expanded(
            child: Stepper(
              currentStep: _step,
              onStepTapped: (i) => setState(() => _step = i),
              onStepContinue: () {
                if (_step < steps.length - 1) {
                  setState(() => _step++);
                } else {
                  Navigator.of(context).maybePop();
                }
              },
              onStepCancel: _step == 0 ? null : () => setState(() => _step--),
              controlsBuilder: (context, details) => Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  children: [
                    FilledButton(
                      onPressed: details.onStepContinue,
                      child: Text(
                        details.stepIndex == steps.length - 1 ? 'DONE' : 'NEXT',
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (details.stepIndex > 0)
                      TextButton(
                        onPressed: details.onStepCancel,
                        child: const Text('BACK'),
                      ),
                  ],
                ),
              ),
              steps: steps,
            ),
          ),
        ],
      ),
    );
  }

  bool _readyForDrawing(BuildContext context, Board b) {
    if (b.mediaCode == null || b.installationCode == null) {
      showSnack(
        context,
        'Select media and installation type first',
        error: true,
      );
      return false;
    }
    return true;
  }

  void _open2D(BuildContext context, Board b) {
    if (!_readyForDrawing(context, b)) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            Drawing2DScreen(shopId: widget.shopId, boardId: widget.boardId),
      ),
    );
  }

  void _open3D(BuildContext context, Board b) {
    if (!_readyForDrawing(context, b)) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) =>
                Preview3DScreen(shopId: widget.shopId, boardId: widget.boardId),
          ),
        )
        .then((_) {
          if (mounted) setState(() => _syncSize(b));
        });
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.shopName,
    required this.board,
    required this.issues,
    required this.warnings,
    required this.readOnly,
  });

  final String shopName;
  final Board board;
  final List<String> issues;
  final List<String> warnings;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final ok = issues.isEmpty;
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shopName,
            style: const TextStyle(color: AdinnColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: issues.isEmpty && warnings.isEmpty
                      ? null
                      : () => showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          builder: (_) => SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Board checklist',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  IssueList(items: issues),
                                  IssueList(items: warnings, warning: true),
                                ],
                              ),
                            ),
                          ),
                        ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          ok ? Icons.check_circle : Icons.error_outline,
                          size: 18,
                          color: ok ? AdinnColors.success : AdinnColors.warning,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            ok
                                ? (warnings.isEmpty
                                      ? 'Board ready for submission'
                                      : 'Ready • ${warnings.length} suggestion(s)')
                                : '${issues.length} item(s) pending – tap to view',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: ok
                                  ? AdinnColors.success
                                  : AdinnColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (readOnly)
                const TagChip('Read only', icon: Icons.lock_outline),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AdinnColors.redLight : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AdinnColors.red : AdinnColors.line,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: AdinnColors.red),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdinnColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? AdinnColors.red : AdinnColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MeasurementsForm extends StatelessWidget {
  const _MeasurementsForm({
    required this.shopId,
    required this.board,
    required this.name,
    required this.w,
    required this.h,
    required this.enabled,
    required this.onChanged,
  });

  final String shopId;
  final Board board;
  final TextEditingController name;
  final TextEditingController w;
  final TextEditingController h;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('board_name'),
          controller: name,
          enabled: enabled,
          decoration: const InputDecoration(
            labelText: 'Board name / position',
            prefixIcon: Icon(Icons.label_outline),
          ),
          onChanged: (t) {
            board.name = t.trim().isEmpty ? 'Board' : t.trim();
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        SegmentedButton<MeasureUnit>(
          segments: [
            for (final u in MeasureUnit.values)
              ButtonSegment(value: u, label: Text(u.label)),
          ],
          selected: {board.unit},
          onSelectionChanged: enabled
              ? (s) {
                  board.unit = s.first;
                  onChanged();
                }
              : null,
        ),
        const SizedBox(height: 12),
        QuantitySizeSection(
          shopId: shopId,
          board: board,
          w: w,
          h: h,
          enabled: enabled,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _DrawingsStep extends StatelessWidget {
  const _DrawingsStep({required this.shopId, required this.board});

  final String shopId;
  final Board board;

  Future<void> _openCameraAr(BuildContext context) async {
    var unitId = board.units.first.id;
    if (board.quantity > 1) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Which signage item?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              for (final u in board.activeUnits)
                ListTile(
                  key: Key('ar_pick_${u.id}'),
                  leading: const Icon(Icons.view_in_ar),
                  title: Text(board.unitLabel(u)),
                  subtitle: Text(
                    fmtSize(board.widthOf(u), board.heightOf(u), board.unit),
                  ),
                  onTap: () => Navigator.pop(ctx, u.id),
                ),
            ],
          ),
        ),
      );
      if (picked == null) return;
      unitId = picked;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CameraArScreen(shopId: shopId, boardId: board.id, unitId: unitId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = board.mediaCode != null && board.installationCode != null;
    final saved = board.drawingPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!ready)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Select media and installation type to generate drawings.',
              style: TextStyle(color: AdinnColors.muted),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('open_2d'),
                onPressed: ready
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Drawing2DScreen(
                            shopId: shopId,
                            boardId: board.id,
                          ),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.architecture),
                label: const Text('2D Drawing'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('open_3d'),
                onPressed: ready
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Preview3DScreen(
                            shopId: shopId,
                            boardId: board.id,
                          ),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.view_in_ar),
                label: const Text('3D Preview'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('open_camera_ar'),
          onPressed: ready ? () => _openCameraAr(context) : null,
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Camera AR (live camera)'),
        ),
        if (saved != null && File(saved).existsSync()) ...[
          const SizedBox(height: 10),
          const Text(
            'Saved drawing',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(File(saved), cacheWidth: 900),
          ),
        ],
      ],
    );
  }
}

/// Legacy media type notice with explicit mapping options.
class _LegacyMediaCard extends StatelessWidget {
  const _LegacyMediaCard({
    required this.board,
    required this.editable,
    required this.onMap,
  });

  final Board board;
  final bool editable;
  final void Function(String code, bool? doubleSided) onMap;

  @override
  Widget build(BuildContext context) {
    final mapping = SignageCatalog.legacyMapping(board.mediaCode);
    final media = SignageCatalog.media(board.mediaCode);
    return Container(
      key: const Key('legacy_media_card'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFCC80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Legacy media type: ${media?.name ?? board.mediaCode}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${mapping?.note ?? ''} Existing data stays as recorded until '
            'you map it explicitly.',
            style: const TextStyle(fontSize: 12.5),
          ),
          if (editable && (mapping?.candidates.isNotEmpty ?? false)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in mapping!.candidates)
                  OutlinedButton(
                    key: Key('map_$code'),
                    onPressed: () => onMap(code, null),
                    child: Text(
                      'Map to ${SignageCatalog.media(code)?.shortName ?? code}',
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

/// Single / double-sided choice for GSB and Non-Lit boards.
class _SidednessChoice extends StatelessWidget {
  const _SidednessChoice({
    required this.doubleSided,
    required this.enabled,
    required this.onChanged,
  });

  final bool doubleSided;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Display faces',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Single-sided', key: Key('sides_single')),
            ),
            ButtonSegment(
              value: true,
              label: Text('Double-sided', key: Key('sides_double')),
            ),
          ],
          selected: {doubleSided},
          onSelectionChanged: enabled ? (v) => onChanged(v.first) : null,
        ),
        const SizedBox(height: 4),
        const Text(
          'Double-sided = two display faces on one physical board. Quantity '
          'still counts physical boards.',
          style: TextStyle(fontSize: 11.5, color: AdinnColors.muted),
        ),
      ],
    ),
  );
}
