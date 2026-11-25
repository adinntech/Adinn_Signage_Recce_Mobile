import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/question_equivalence.dart';
import '../../data/catalog/signage_catalog.dart';
import '../../data/catalog/site_checklists.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../gsb/gsb_board.dart';
import '../gsb/gsb_rules.dart';
import '../gsb/gsb_type_sheet.dart';
import '../nlb/nlb_rules.dart';
import '../nlb/nlb_type_sheet.dart';
import '../notes/voice_notes_section.dart';
import '../photos/photo_section.dart';
import '../ar/camera_ar_screen.dart';
import '../preview_live/preview_gallery.dart';
import '../survey/checklist_form.dart';
import 'installation_choice_card.dart';
import 'board_picker.dart';
import 'installation_modes.dart';
import '../shop/add_media_sheet.dart';
import 'media_tabs.dart';
import 'quantity_size_section.dart';
import 'site_questions_form.dart';

/// Step-by-step capture of one signage board:
/// board details → media → installation → site questions → photos → notes →
/// drawings. Every change is saved locally immediately.
class BoardEditorScreen extends StatefulWidget {
  const BoardEditorScreen({
    super.key,
    required this.shopId,
    required this.boardId,
    this.initialStep,
    this.initialUnitId,
  });

  final String shopId;
  final String boardId;

  /// Physical board to open (e.g. from a pending issue). Null = last used
  /// / first board.
  final String? initialUnitId;

  /// Step to open (e.g. 0 = Board Details from the Camera AR dimension
  /// panel). Null = first incomplete step (default behaviour).
  final int? initialStep;

  /// Media Type is the first step (usually already chosen in the Add Media
  /// Type popup).
  static const mediaTypeStep = 0;

  /// Board name, quantity and measurements are the second step.
  static const boardDetailsStep = 1;

  static const installationStep = 2;

  static const siteQuestionsStep = 3;

  /// Editor step that resolves an issue of [section].
  static int stepFor(IssueSection section) => switch (section) {
    IssueSection.media => mediaTypeStep,
    IssueSection.details => boardDetailsStep,
    IssueSection.installation => installationStep,
    IssueSection.questions => siteQuestionsStep,
    IssueSection.photos => siteQuestionsStep + 1,
  };

  /// Legacy name kept for callers: there is no separate measurements step
  /// any more, it is part of Board Details.
  static const measurementsStep = boardDetailsStep;

  static const stepCount = 7;

  @override
  State<BoardEditorScreen> createState() => _BoardEditorScreenState();
}

class _BoardEditorScreenState extends State<BoardEditorScreen> {
  int _step = 0;

  /// null = derive from the data (mixed installations => different).
  bool? _diffInstall;

  /// Bumped after "Copy Common Answers" so the questions form rebuilds.
  int _copyTick = 0;

  late final AppController _ctl;
  bool _switching = false;

  /// Auto-fill of common answers runs at most once per physical board per
  /// editor session (never re-applied on rebuilds).
  final Set<String> _autoFillTried = {};
  final Map<String, Set<String>> _autoFilled = {};
  final Map<String, String> _autoFillNote = {};

  /// Physical board (unit) currently edited in Site Questions / previews.
  String? _unitId;
  bool _savingDraft = false;
  final _name = TextEditingController();
  final _w = TextEditingController();
  final _h = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctl = context.read<AppController>();
    final b = _ctl.board(
      widget.shopId,
      widget.boardId,
    );
    if (b != null) {
      _name.text = b.name;
      _syncSize(b);
      _note.text = b.textNote;
      // Jump to the requested step, else the first incomplete one.
      // Requested step, else where this board was left (media tab switch),
      // else the first incomplete step.
      _step =
          (widget.initialStep ?? _ctl.editorStep[b.id] ?? _firstIncomplete(b))
              .clamp(0, BoardEditorScreen.stepCount - 1);
      _unitId =
          b.unitById(widget.initialUnitId)?.id ??
          b.unitById(_ctl.editorUnit[b.id])?.id;
    }
  }

  /// Selected physical board of [b] (falls back to the first one).
  SignageUnit? _unit(Board b) =>
      b.activeUnits.where((u) => u.id == _unitId).firstOrNull ??
      SignageCatalog.firstUnit(b);

  void _selectUnit(Board b, SignageUnit u) {
    setState(() => _unitId = u.id);
    _ctl.editorUnit[b.id] = u.id;
  }

  /// Opens the section (and board) that resolves a blocking issue.
  void _goToIssue(Board b, BoardIssue i) {
    final u = b.unitById(i.unitId);
    setState(() {
      if (u != null) _unitId = u.id;
      _step = BoardEditorScreen.stepFor(i.section);
    });
  }

  void _syncSize(Board b) {
    _w.text = b.width == null ? '' : fmtNum(b.width!);
    _h.text = b.height == null ? '' : fmtNum(b.height!);
  }

  /// Media tab tap: offers "Save as Draft?" when this board is incomplete
  /// and changed since its last draft save; stays here if saving fails.
  Future<void> _switchTo(Shop shop, Board cur, Board other) async {
    if (_switching || other.id == cur.id) return;
    _switching = true;
    try {
      if (_ctl.canEdit(shop) && _ctl.needsDraftPrompt(cur)) {
        final save = await showSaveDraftDialog(
          context,
          from: mediaTabLabel(cur, shop.boards),
          to: mediaTabLabel(other, shop.boards),
        );
        if (!save || !mounted) return;
        final ok = await _ctl.saveDraft(widget.shopId, cur);
        if (!mounted) return;
        if (!ok) {
          showSnack(
            context,
            'Draft could not be saved on this device. Nothing was lost – '
            'you are still on ${cur.name}.',
            error: true,
          );
          return;
        }
      }
      _ctl.editorStep[cur.id] = _step;
      await Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) =>
              BoardEditorScreen(shopId: widget.shopId, boardId: other.id),
          transitionDuration: Duration.zero,
        ),
      );
    } finally {
      _switching = false;
    }
  }

  bool _addingMedia = false;

  /// "+" beside the media tabs: same add-media flow as Shop Details. An
  /// incomplete, changed board is saved as a draft first; the new media opens
  /// afterwards. Rapid taps never create twice.
  Future<void> _addMedia(Shop shop, Board cur) async {
    if (_addingMedia || _switching) return;
    _addingMedia = true;
    try {
      if (_ctl.needsDraftPrompt(cur)) {
        final save = await showSaveDraftDialog(
          context,
          from: mediaTabLabel(cur, shop.boards),
          to: 'the new media',
        );
        if (!save || !mounted) return;
        if (!await _ctl.saveDraft(widget.shopId, cur)) {
          if (mounted) {
            showSnack(
              context,
              'Draft could not be saved on this device. Nothing was lost.',
              error: true,
            );
          }
          return;
        }
      }
      if (!mounted) return;
      final created = await runAddMedia(context, _ctl, widget.shopId);
      if (created.isEmpty || !mounted) return;
      _ctl.editorStep[cur.id] = _step;
      await Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => BoardEditorScreen(
            shopId: widget.shopId,
            boardId: created.first.id,
          ),
          transitionDuration: Duration.zero,
        ),
      );
    } finally {
      _addingMedia = false;
    }
  }

  /// Carries compatible common answers from another physical board of this
  /// shop into unanswered fields of board [u], once per board. Conflicting
  /// sources are never auto-picked.
  void _maybeAutoFill(Shop shop, Board b, SignageUnit u) {
    if (!_autoFillTried.add(u.id)) return;
    if (!_ctl.canEdit(shop) || b.installationOf(u) == null) return;
    final r = SignageCatalog.autoFillSourceForUnit(b, u, shop.boards);
    if (r.conflicting.isNotEmpty) {
      _autoFillNote[u.id] =
          'Common answers differ between '
          '${r.conflicting.map((e) => SignageCatalog.unitName(e.$1, e.$2)).join(', ')}'
          '. Use Copy Common Answers to choose the source.';
      return;
    }
    final sb = r.board, su = r.unit;
    if (sb == null || su == null) return;
    final ids = SignageCatalog.planUnitAnswers(
      sb,
      su,
      b,
      u,
    ).toCopy.map((q) => q.id).toSet();
    final n = _ctl.copyCommonAnswers(
      widget.shopId,
      sb,
      b,
      sourceUnit: su,
      targetUnit: u,
    );
    if (n > 0) {
      _autoFilled[u.id] = ids;
      _autoFillNote[u.id] =
          'Common answers carried from ${SignageCatalog.unitName(sb, su)}. '
          'You can update them if needed.';
      _copyTick++;
    }
  }

  Future<void> _saveDraftNow(Board b) async {
    if (_savingDraft) return;
    _savingDraft = true;
    final ok = await _ctl.saveDraft(widget.shopId, b);
    _savingDraft = false;
    if (!mounted) return;
    setState(() {});
    showSnack(
      context,
      ok
          ? 'Draft saved on this device.'
          : 'Draft could not be saved on this device. Tap again to retry.',
      error: !ok,
    );
  }

  @override
  void dispose() {
    _ctl.editorStep[widget.boardId] = _step;
    if (_unitId != null) _ctl.editorUnit[widget.boardId] = _unitId!;
    _name.dispose();
    _w.dispose();
    _h.dispose();
    _note.dispose();
    super.dispose();
  }

  bool _mediaDone(Board b) => SignageCatalog.media(b.mediaCode) != null;
  bool _installDone(Board b) =>
      _mediaDone(b) && SignageCatalog.installationComplete(b);
  /// Site Questions AND the physical-board checklist of every board: the
  /// same rules as [AppController.boardIssues].
  bool _questionsDone(Board b) =>
      _installDone(b) && _ctl.siteQuestionsPending(b) == 0;

  bool _detailsDone(Board b) => b.name.trim().isNotEmpty && b.hasSize;

  bool _badDimension(double? v) =>
      v != null && (!v.isFinite || v <= 0);

  /// Shows the validation state on Board Details when a typed dimension is
  /// invalid, even though the basic size is not complete yet.
  bool _detailsInvalid(Board b) {
    if (_badDimension(b.width) || _badDimension(b.height)) return true;
    if (b.isSameSize) return false;
    for (final u in b.activeUnits) {
      if (_badDimension(u.width) || _badDimension(u.height)) return true;
    }
    return false;
  }

  String _detailsSummary(Board b) {
    final count = '${b.quantity} ${b.quantity == 1 ? 'Board' : 'Boards'}';
    if (!b.hasSize) return '$count · measurements pending';
    if (!b.isSameSize) {
      return '$count · different sizes · ${fmtNum(b.areaSqFt)} sq ft';
    }
    return '$count · ${fmtSize(b.width, b.height, b.unit)}'
        '${b.quantity > 1 ? ' ×${b.quantity}' : ''}'
        ' · ${fmtNum(b.areaSqFt)} sq ft';
  }

  int _firstIncomplete(Board b) {
    if (!_mediaDone(b)) return BoardEditorScreen.mediaTypeStep;
    if (!_detailsDone(b)) return BoardEditorScreen.boardDetailsStep;
    if (!_installDone(b)) return BoardEditorScreen.installationStep;
    if (!_questionsDone(b)) return BoardEditorScreen.siteQuestionsStep;
    if (b.photos.isEmpty) return BoardEditorScreen.siteQuestionsStep + 1;
    return 0;
  }

  /// Answers that no longer apply move to [Board.answersArchive] (never
  /// silently lost); archived answers that apply again are restored.
  int _pruneAnswers(Board b) {
    // [Board.answers] belongs to the first physical board: prune it for
    // that board's own installation.
    final first = SignageCatalog.firstUnit(b);
    final ids = SignageCatalog.questionsFor(
      b.mediaCode,
      first == null
          ? SignageCatalog.primaryInstallation(b)
          : b.installationOf(first),
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

  /// After media / subtype is chosen: Board Details next unless it is
  /// already complete, then Installation Type. Also refreshes the (possibly
  /// auto-renamed) board name field.
  void _afterMediaChosen(Board b) {
    _name.text = b.name;
    setState(
      () => _step = _detailsDone(b)
          ? BoardEditorScreen.installationStep
          : BoardEditorScreen.boardDetailsStep,
    );
  }

  /// Media card tap. GSB first asks for the board type (single / double);
  /// cancelling the sheet leaves the recce untouched. Other media are
  /// selected directly, exactly as before.
  Future<void> _onMediaTap(AppController c, Board b, MediaType m) async {
    if (m.code == SignageCatalog.nlb) {
      await _onNlbTap(c, b, m);
      return;
    }
    if (m.code != SignageCatalog.gsb) {
      _selectMedia(c, b, m);
      return;
    }
    // Restore only an explicit, saved GSB choice (never carry over the
    // sidedness of another media type).
    final initial = b.mediaCode == SignageCatalog.gsb && b.doubleSided != null
        ? (b.doubleSided! ? GsbVariant.double : GsbVariant.single)
        : null;
    final picked = await showGsbTypeSheet(context, initial: initial);
    if (picked == null || !mounted) return;
    final isDouble = picked == GsbVariant.double;
    if (b.mediaCode != m.code) {
      b.doubleSided = isDouble;
      _selectMedia(c, b, m);
    } else if (b.doubleSided != isDouble) {
      c.setDoubleSided(widget.shopId, b, isDouble);
      _afterMediaChosen(b);
    } else {
      _afterMediaChosen(b);
    }
  }

  /// NLB asks for the frame type first (Single Frame = NON_LIT, Box Frame =
  /// NON_LIT_BOX). Cancel leaves the recce untouched; legacy NLB records
  /// without a subtype keep their behaviour until one is chosen.
  Future<void> _onNlbTap(AppController c, Board b, MediaType m) async {
    final initial = b.mediaCode == SignageCatalog.nlb
        ? NlbVariantX.fromKey(b.nlbSubtype)
        : null;
    final picked = await showNlbTypeSheet(context, initial: initial);
    if (picked == null || !mounted) return;
    if (b.mediaCode != m.code) {
      b.nlbSubtype = picked.key;
      b.doubleSided = picked == NlbVariant.boxFrame;
      _selectMedia(c, b, m);
    } else {
      if (b.nlbSubtype != picked.key) {
        c.setNlbSubtype(widget.shopId, b, picked.key);
      }
      _afterMediaChosen(b);
    }
  }

  void _selectMedia(AppController c, Board b, MediaType m) {
    if (b.mediaCode == m.code) {
      _afterMediaChosen(b);
      return;
    }
    b.mediaCode = m.code;
    // Never keep (or silently invent) an installation that is not valid for
    // the new media; the vendor must pick one.
    if (!SignageCatalog.allowsInstallation(b, b.installationCode)) {
      b.installationCode = null;
    }
    c.dropInvalidUnitInstallations(b);
    final pruned = _pruneAnswers(b);
    c.autoNameBoard(widget.shopId, b);
    c.touchBoard(
      widget.shopId,
      b,
      title: 'Board updated',
      message:
          '${b.name}: media set to ${m.shortName}'
          '${GsbBoard.isGsb(b) ? ' (${GsbBoard.variantOf(b)!.label})' : ''}.',
    );
    _notePruned(pruned);
    _afterMediaChosen(b);
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

  /// Card selected state in Same Installation mode.
  bool _isPicked(Board b, String? code) =>
      code != null &&
      !SignageCatalog.hasMixedInstallations(b) &&
      SignageCatalog.primaryInstallation(b) == code;

  /// "Same Installation": applies [i] to the group and every board. Asks
  /// before replacing a different installation already chosen for a board.
  Future<void> _selectInstallation(
    AppController c,
    Board b,
    InstallationType i,
  ) async {
    final clash = b.activeUnits.any(
      (u) => u.installationCode != null && u.installationCode != i.code,
    );
    if (clash) {
      final ok = await confirmDialog(
        context,
        title: 'Use ${i.name} for all boards?',
        message:
            'Some boards already have a different installation. They will '
            'all be changed to ${i.name}.',
        confirmText: 'Apply to all',
      );
      if (!ok || !mounted) return;
    }
    c.setSameInstallation(widget.shopId, b, i.code);
    final pruned = _pruneAnswers(b);
    c.touchBoard(widget.shopId, b);
    _notePruned(pruned);
    setState(() => _step = 3);
  }

  void _pickUnitInstallation(
    AppController c,
    Board b,
    SignageUnit u,
    String code,
  ) {
    if (!c.setUnitInstallation(widget.shopId, b, u, code)) return;
    final pruned = _pruneAnswers(b);
    c.touchBoard(widget.shopId, b);
    _notePruned(pruned);
    setState(() {});
  }

  StepState _state(
    bool done,
    int index,
    bool editable, {
    bool error = false,
  }) {
    if (done) return StepState.complete;
    if (error) return StepState.error;
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
    final issueDetails = c.boardIssueDetails(board);
    final issues = [for (final i in issueDetails) i.text];
    final warnings = c.boardWarnings(board, shop.geo);
    // Site Questions are per physical board: its own installation + answers.
    final unit = _unit(board);
    final questions = unit == null
        ? SignageCatalog.questionsFor(
            board.mediaCode,
            SignageCatalog.primaryInstallation(board),
          )
        : SignageCatalog.questionsForUnit(board, unit);
    // Stored answers completed by an earlier equivalent checklist answer.
    final unitAnswers = unit == null
        ? board.answers
        : QuestionEquivalence.effectiveSiteAnswers(board, unit);
    final sitePending = c.siteQuestionsPending(board);
    if (_step == BoardEditorScreen.siteQuestionsStep &&
        unit != null &&
        !_autoFillTried.contains(unit.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_autoFillTried.contains(unit.id)) {
          setState(() => _maybeAutoFill(shop, board, unit));
        }
      });
    }
    final multiUnit = board.activeUnits.length > 1;
    final diffInstall =
        multiUnit &&
        (_diffInstall ?? SignageCatalog.hasMixedInstallations(board));
    final legacyInstall = SignageCatalog.legacyInstallationOf(board);

    // Board Details is the SECOND step (after Media Type).
    final detailsStep = Step(
        title: const Text('Board Details'),
        subtitle: Text(
          _detailsDone(board)
              ? _detailsSummary(board)
              : 'Board name, quantity and measurements',
        ),
        state: _state(
          _detailsDone(board),
          BoardEditorScreen.boardDetailsStep,
          editable,
          error: _detailsInvalid(board),
        ),
        isActive: _step >= BoardEditorScreen.boardDetailsStep,
        content: _BoardDetailsForm(
          shopId: widget.shopId,
          board: board,
          name: _name,
          w: _w,
          h: _h,
          enabled: editable,
          onChanged: () => c.touchBoard(widget.shopId, board),
          onSizeSynced: () => setState(() => _syncSize(board)),
        ),
      );

    final steps = <Step>[
      Step(
        title: const Text('Media Type'),
        subtitle: Text(
          media == null
              ? 'Choose one of ${SignageCatalog.selectableCodes.length} media types'
              : GsbBoard.isExplicit(board)
              ? '${media.name} · ${GsbBoard.variantOf(board)!.label}'
              : NlbVariantX.fromKey(board.nlbSubtype) != null && board.isNlb
              ? '${media.name} · ${NlbVariantX.fromKey(board.nlbSubtype)!.label}'
              : media.name,
        ),
        state: _state(
          _mediaDone(board),
          BoardEditorScreen.mediaTypeStep,
          editable,
        ),
        isActive: _step >= BoardEditorScreen.mediaTypeStep,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (SignageCatalog.isLegacy(board.mediaCode))
              _LegacyMediaCard(
                board: board,
                editable: editable,
                onMap: (code, sides) => _mapLegacy(c, board, code, sides),
              ),
            _MediaGrid(
              selected: board.mediaCode,
              enabled: editable,
              onSelect: (m) => _onMediaTap(c, board, m),
            ),
            // GSB: the board type comes from the selection sheet (one
            // source of truth); the summary reopens it.
            if (GsbBoard.isGsb(board))
              _GsbVariantSummary(
                board: board,
                enabled: editable,
                onChange: () => _onMediaTap(c, board, media!),
              )
            else if (board.isNlb && board.nlbSubtype != null)
              _NlbVariantSummary(
                variant: NlbVariantX.fromKey(board.nlbSubtype)!,
                enabled: editable,
                onChange: () => _onMediaTap(c, board, media!),
              )
            else if (media?.sidedness == MediaSidedness.selectable)
              _SidednessChoice(
                doubleSided: board.doubleSided ?? false,
                enabled: editable,
                onChanged: (v) => c.setDoubleSided(widget.shopId, board, v),
              ),
          ],
        ),
      ),
      detailsStep,
      Step(
        title: const Text('Installation Type'),
        subtitle: Text(
          SignageCatalog.hasMixedInstallations(board)
              ? SignageCatalog.installationSummary(board)
              : SignageCatalog.installationLabel(
                  board,
                  SignageCatalog.primaryInstallation(board),
                ),
        ),
        state: _state(_installDone(board), 2, editable),
        isActive: _step >= 2,
        content: media == null
            ? const Text('Select a media type first.')
            : SignageCatalog.choicesForBoard(board).isEmpty &&
                legacyInstall == null
            ? Text(
                'Installation options for ${media.shortName} are not '
                'configured yet (pending approval).',
                key: const Key('inst_unconfigured'),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (multiUnit)
                    InstallationModeSwitch(
                      different: diffInstall,
                      enabled: editable,
                      onChanged: (v) => setState(() => _diffInstall = v),
                    ),
                  if (diffInstall)
                    UnitInstallationPicker(
                      board: board,
                      choices: SignageCatalog.choicesForBoard(board),
                      enabled: editable,
                      onPick: (u, code) =>
                          _pickUnitInstallation(c, board, u, code),
                    )
                  else
                  for (final choice in SignageCatalog.choicesForBoard(board)) ...[
                    if (choice.art == InstallationArt.generic)
                      _OptionTile(
                        key: Key('inst_${choice.code}'),
                        icon: choice.icon ?? Icons.help_outline,
                        title: choice.name,
                        subtitle: choice.description,
                        selected: _isPicked(board, choice.code),
                        onTap: editable && choice.canPersist
                            ? () => _selectInstallation(
                              c,
                              board,
                              SignageCatalog.installation(choice.code)!,
                            )
                            : null,
                      )
                    else
                      InstallationChoiceCard(
                        key: Key(
                          'inst_${choice.code ?? 'hanging_mount'}',
                        ),
                        choice: choice,
                        selected: _isPicked(board, choice.code),
                        enabled: editable,
                        onTap: () {
                          // No approved backend value yet: show the option,
                          // but never persist an invented code.
                          if (!choice.canPersist) {
                            showSnack(
                              context,
                              'Hanging Mount needs an approved backend '
                              'installation code before it can be saved. '
                              'Nothing was changed.',
                              error: true,
                            );
                            return;
                          }
                          _selectInstallation(
                            c,
                            board,
                            SignageCatalog.installation(choice.code)!,
                          );
                        },
                      ),
                  ],
                  // Old GSB records keep their original value on screen; it
                  // is only replaced when the vendor explicitly picks a card.
                  if (legacyInstall != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _OptionTile(
                        key: Key('inst_legacy_${legacyInstall.code}'),
                        icon: legacyInstall.icon,
                        title: '${legacyInstall.name} (saved earlier)',
                        subtitle:
                            '${legacyInstall.description} Kept as recorded – '
                            'choose a new card above to change it.',
                        selected: true,
                        onTap: null,
                      ),
                    ),
                ],
              ),
      ),
      Step(
        title: const Text('Site Questions'),
        subtitle: Text(
          _installDone(board)
              ? '$sitePending required pending'
              : 'Loaded after installation',
          key: const Key('site_questions_subtitle'),
        ),
        state: _state(
          _questionsDone(board),
          BoardEditorScreen.siteQuestionsStep,
          editable,
        ),
        isActive: _step >= BoardEditorScreen.siteQuestionsStep,
        content: unit == null || board.installationOf(unit) == null
            ? const Text('Select the installation type of this board first.')
            : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (board.activeUnits.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: UnitSelector(
                  board: board,
                  selectedId: unit.id,
                  pendingOf: (u) => c.siteQuestionsPendingFor(board, u),
                  onSelect: (u) => _selectUnit(board, u),
                ),
              ),
            Text(
              '${SignageCatalog.unitName(board, unit)} · '
              '${SignageCatalog.installation(board.installationOf(unit))?.name ?? '—'}'
              ' · ${c.siteQuestionsPendingFor(board, unit)} required pending',
              key: const Key('unit_questions_header'),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            if (editable &&
                shop.boards.any(
                  (o) => o.mediaCode != null && o.activeUnits.any(
                    (x) => !(o.id == board.id && x.id == unit.id),
                  ),
                ))
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('copy_common_answers'),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copy Common Answers'),
                  onPressed: () async {
                    final n = await showCopyCommonAnswersSheet(
                      context,
                      target: (board, unit),
                      candidates: [
                        for (final o in shop.boards)
                          for (final x in o.activeUnits) (o, x),
                      ],
                      onCopy: (src, overwrite) => c.copyCommonAnswers(
                        widget.shopId,
                        src.$1,
                        board,
                        overwrite: overwrite,
                        sourceUnit: src.$2,
                        targetUnit: unit,
                      ),
                    );
                    if (n > 0 && mounted) {
                      setState(() => _copyTick++);
                      showSnack(context, '$n answer(s) copied.');
                    }
                  },
                ),
              ),
            if (_autoFillNote[unit.id] != null)
              Container(
                key: const Key('autofill_note'),
                margin: const EdgeInsets.only(top: 8, bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AdinnColors.canvas,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AdinnColors.line),
                ),
                child: Text(
                  _autoFillNote[unit.id]!,
                  style: const TextStyle(fontSize: 12.5, height: 1.35),
                ),
              ),
            const SizedBox(height: 6),
            SiteQuestionsForm(
              key: ValueKey(
                'sq_${unit.id}_${board.installationOf(unit)}_$_copyTick',
              ),
              questions: questions,
              answers: unitAnswers,
              enabled: editable,
              sectionOf: (q) =>
                  SignageCatalog.questionSectionFor(board, unit, q),
              autoFilled: _autoFilled[unit.id] ?? const {},
              onChanged: (id, v) {
                _autoFilled[unit.id]?.remove(id);
                // Saved on THIS physical board only.
                c.setUnitAnswer(widget.shopId, board, unit, id, v);
              },
            ),
            // Earlier answers of the same question that disagree (never
            // resolved silently).
            for (final cf in QuestionEquivalence.conflicts(board, unit))
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Text(
                  'Earlier checklist answer for "${cf.site.label}" was '
                  '${cf.checklistText}. Choosing an answer above replaces it.',
                  key: Key('conflict_${cf.site.id}'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdinnColors.warning,
                  ),
                ),
              ),
            // Remaining checklist-only questions of this board (the ones that
            // are not already a Site Question above) in the SAME form. Site
            // evidence photos are collected in Site Photos & Annotation.
            if (SiteChecklists.definitionFor(board.mediaCode) != null)
              ChecklistForm(
                key: ValueKey(
                  'cl_${unit.id}_${board.installationOf(unit)}_$_copyTick',
                ),
                shopId: widget.shopId,
                board: board,
                unit: unit,
                editable: editable,
                embedded: true,
                hideIds: {
                  ...QuestionEquivalence.mappedChecklistIds(board, unit),
                  'site_evidence_photo',
                },
              ),
            if (board.activeUnits.length > 1 &&
                board.activeUnits.last.id != unit.id) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('save_next_board'),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Save & Next Board'),
                  onPressed: () async {
                    await c.flush();
                    if (!mounted) return;
                    final i = board.activeUnits.indexWhere(
                      (x) => x.id == unit.id,
                    );
                    _selectUnit(board, board.activeUnits[i + 1]);
                  },
                ),
              ),
            ],
            if (board.activeUnits.length > 1 && sitePending > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  [
                    for (final u in board.activeUnits)
                      if (c.siteQuestionsPendingFor(board, u) > 0)
                        '${SignageCatalog.unitName(board, u)}: '
                            '${c.siteQuestionsPendingFor(board, u)} pending',
                  ].join(' · '),
                  key: const Key('units_pending_summary'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdinnColors.warning,
                  ),
                ),
              ),
          ],
        ),
      ),
      Step(
        title: const Text('Site Photos & Annotation'),
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
        title: const Text('Voice & Text Notes'),
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
        title: const Text('2D Drawing & 3D Preview'),
        subtitle: Text(
          board.drawingPath == null ? 'Auto-generated' : 'Drawing saved',
        ),
        state: board.drawingPath != null
            ? StepState.complete
            : (_step == 6 ? StepState.editing : StepState.indexed),
        isActive: _step >= 6,
        content: _DrawingsStep(
          board: board,
          onOpen: _openView,
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        // The board being edited: its own name when the group has several.
        title: Text(
          unit != null && board.activeUnits.length > 1
              ? SignageCatalog.unitName(board, unit)
              : board.name,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (editable)
            IconButton(
              key: const Key('save_draft'),
              tooltip: 'Save as Draft',
              icon: const Icon(Icons.save_outlined),
              onPressed: () => _saveDraftNow(board),
            ),
          IconButton(
            tooltip: '2D drawing',
            icon: const Icon(Icons.architecture),
            onPressed: () => _openView(BoardView.drawing2d),
          ),
          IconButton(
            tooltip: '3D preview',
            icon: const Icon(Icons.view_in_ar),
            onPressed: () => _openView(BoardView.preview3d),
          ),
        ],
      ),
      body: Column(
        children: [
          if (shop.boards.length > 1 || editable)
            MediaTabs(
              controller: c,
              // A lone board shows only the "+" (its tab would repeat the
              // title).
              boards: shop.boards.length > 1 ? shop.boards : const [],
              currentId: board.id,
              onSelect: (o) => _switchTo(shop, board, o),
              onAdd: editable ? () => _addMedia(shop, board) : null,
            ),
          // Physical boards of this media group: each opens its own data.
          if (board.activeUnits.length > 1 && unit != null)
            Container(
              color: Colors.white,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              child: UnitSelector(
                key: const Key('board_unit_bar'),
                keyPrefix: 'unit_bar',
                board: board,
                selectedId: unit.id,
                pendingOf: (u) => issueDetails
                    .where((i) => i.unitId == u.id)
                    .length,
                onSelect: (u) => _selectUnit(board, u),
              ),
            ),
          _Header(
            shopName: shop.name,
            board: board,
            details: issueDetails,
            onIssueTap: (i) => _goToIssue(board, i),
            issues: issues,
            warnings: warnings,
            readOnly: !editable,
          ),
          Expanded(
            child: Stepper(
              currentStep: _step,
              // Keep the expanded form fully to the right of the timeline
              // gutter so labels never cross the red stepper line.
              contentPadding: const EdgeInsets.fromLTRB(56, 4, 16, 16),
              onStepTapped: (i) => setState(() => _step = i),
              onStepContinue: () {
                if (_step < steps.length - 1) {
                  setState(() => _step++);
                } else {
                  _onDone();
                }
              },
              onStepCancel: _step == 0 ? null : () => setState(() => _step--),
              controlsBuilder: (context, details) => Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 4),
                child: Row(
                  children: [
                    FilledButton(
                      key: Key('step_next_${details.stepIndex}'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(72, 46),
                      ),
                      onPressed: details.onStepContinue,
                      child: Text(
                        details.stepIndex == steps.length - 1 ? 'DONE' : 'NEXT',
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (details.stepIndex > 0)
                      TextButton(
                        key: Key('step_back_${details.stepIndex}'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(64, 46),
                        ),
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

  /// Illustrative drawing readiness of the SELECTED physical board only:
  /// its media and its own installation. Site questions, photos or other
  /// boards / media groups never block an illustrative preview.
  bool _openingView = false;

  /// 2D Drawing / 3D Preview / Camera AR for this media group. ONE board
  /// opens directly; several boards ask which one(s) first. Readiness is
  /// evaluated per physical board (its own installation and size).
  Future<void> _openView(BoardView view) async {
    if (_openingView) return; // repeated taps never stack viewers
    final b = _ctl.board(widget.shopId, widget.boardId);
    if (b == null) return;
    final units = b.activeUnits;
    final ready = SignageCatalog.drawingReadyUnits(b);
    if (ready.isEmpty) {
      final why = units.isEmpty
          ? 'Add a board first'
          : SignageCatalog.unitDrawingBlocker(b, units.first) ??
                'Not ready yet';
      showSnack(context, why, error: true);
      final u = units.firstOrNull;
      setState(() {
        if (u != null) _unitId = u.id;
        _step = b.mediaCode == null
            ? BoardEditorScreen.mediaTypeStep
            : (u != null && b.installationOf(u) == null)
            ? BoardEditorScreen.installationStep
            : BoardEditorScreen.boardDetailsStep;
      });
      return;
    }
    _openingView = true;
    try {
      List<String>? ids;
      if (units.length == 1) {
        ids = [units.first.id];
      } else {
        ids = await showBoardPicker(context, board: b, view: view);
      }
      if (ids == null || ids.isEmpty || !mounted) return;
      if (ids.length == 1) _unitId = ids.first;
      if (view == BoardView.cameraAr) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CameraArScreen(
              shopId: widget.shopId,
              boardId: b.id,
              unitId: ids!.first,
            ),
          ),
        );
      } else {
        await Navigator.of(context).push(
          boardViewerRoute(
            shopId: widget.shopId,
            boardId: b.id,
            view: view,
            unitIds: ids,
            board: b,
          ),
        );
      }
      if (mounted) setState(() => _syncSize(b));
    } finally {
      _openingView = false;
    }
  }

  bool _doneBusy = false;

  /// Step of the first blocker of [u] (its own issues, then group-level).
  IssueSection? _firstBlockerSection(Board b, SignageUnit u) {
    for (final i in _ctl.boardIssueDetails(b)) {
      if (i.unitId == u.id) return i.section;
    }
    for (final i in _ctl.boardIssueDetails(b)) {
      if (i.unitId == null) return i.section;
    }
    return null;
  }

  /// Blocking issues that stop physical board [u] from being complete: its
  /// own and the group-level ones (media, photos, shared size).
  List<BoardIssue> _blockersOf(Board b, SignageUnit u) => [
    for (final i in _ctl.boardIssueDetails(b))
      if (i.unitId == u.id || i.unitId == null) i,
  ];

  /// DONE: save, validate the selected board, then open the next incomplete
  /// board of this media group, or return to Shop Details after the last
  /// one. Never submits the shop.
  Future<void> _onDone() async {
    if (_doneBusy) return;
    final b = _ctl.board(widget.shopId, widget.boardId);
    final shop = _ctl.shop(widget.shopId);
    if (b == null || shop == null) return;
    _doneBusy = true;
    try {
      final editable = _ctl.canEdit(shop);
      if (editable) {
        // Await the real write; a failure keeps the vendor on this board.
        await _ctl.retrySave();
        if (!mounted) return;
        if (_ctl.storageError != null) {
          showSnack(
            context,
            'Could not save on this device. Nothing was lost – tap DONE '
            'again to retry.',
            error: true,
          );
          return;
        }
      }
      final cur = _unit(b);
      if (cur == null) {
        Navigator.of(context).maybePop();
        return;
      }
      final mine = _blockersOf(b, cur);
      if (editable && mine.isNotEmpty) {
        // Not complete: show the real pending requirements, tap to fix.
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (sheet) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                key: const Key('done_pending_sheet'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${SignageCatalog.unitName(b, cur)} is not complete',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final i in mine)
                    _IssueTile(
                      board: b,
                      issue: i,
                      onTap: () {
                        Navigator.of(sheet).pop();
                        _goToIssue(b, i);
                      },
                    ),
                ],
              ),
            ),
          ),
        );
        return;
      }
      // Next incomplete board after this one (then any earlier one); done
      // boards are not reopened and incomplete ones are not skipped.
      final units = b.activeUnits;
      final at = units.indexWhere((u) => u.id == cur.id);
      final order = [...units.skip(at + 1), ...units.take(at)];
      final next = order
          .where((u) => _blockersOf(b, u).isNotEmpty)
          .firstOrNull;
      if (next != null) {
        final section = _firstBlockerSection(b, next);
        _selectUnit(b, next);
        setState(() {
          _step = section == null
              ? BoardEditorScreen.boardDetailsStep
              : BoardEditorScreen.stepFor(section);
        });
        return;
      }
      Navigator.of(context).maybePop();
    } finally {
      _doneBusy = false;
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.shopName,
    required this.board,
    required this.issues,
    required this.warnings,
    required this.readOnly,
    this.details = const [],
    this.onIssueTap,
  });

  final String shopName;
  final Board board;
  final List<String> issues;

  /// Same blocking issues with the board / section that resolves each one.
  final List<BoardIssue> details;
  final ValueChanged<BoardIssue>? onIssueTap;
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
                          isScrollControlled: true,
                          builder: (sheet) => SafeArea(
                            child: SingleChildScrollView(
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
                                  // Blocking issues: tap opens the board and
                                  // section that resolves it.
                                  if (details.length == issues.length &&
                                      onIssueTap != null)
                                    for (final i in details)
                                      _IssueTile(
                                        board: board,
                                        issue: i,
                                        onTap: () {
                                          Navigator.of(sheet).pop();
                                          onIssueTap!(i);
                                        },
                                      )
                                  else
                                    IssueList(items: issues),
                                  if (warnings.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Suggestions (not blocking)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AdinnColors.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
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

/// One tappable blocking issue in the Board checklist sheet.
class _IssueTile extends StatelessWidget {
  const _IssueTile({
    required this.board,
    required this.issue,
    required this.onTap,
  });

  final Board board;
  final BoardIssue issue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final u = board.unitById(issue.unitId);
    final where = switch (issue.section) {
      IssueSection.media => 'Media Type',
      IssueSection.details => 'Board Details',
      IssueSection.installation => 'Installation Type',
      IssueSection.questions => 'Site Questions',
      IssueSection.photos => 'Site Photos & Annotation',
    };
    return InkWell(
      key: Key('issue_${issue.section.name}_${issue.unitId ?? 'group'}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 18, color: AdinnColors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [
                  if (u != null && board.activeUnits.length > 1)
                    '${SignageCatalog.unitName(board, u)}: ',
                  issue.text,
                  '  → $where',
                ].join(),
                style: const TextStyle(
                  color: AdinnColors.red,
                  fontSize: 13.5,
                  height: 1.35,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AdinnColors.muted),
          ],
        ),
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({
    required this.selected,
    required this.onSelect,
    required this.enabled,
  });

  final String? selected;
  final ValueChanged<MediaType> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      // Slightly taller cards so two-line names ("One-Way Vision") and the
      // short subtitle fit on 320 dp phones.
      childAspectRatio: 0.92,
      children: [
        for (final m in [
          ...SignageCatalog.selectableMedia,
          // A saved type that is no longer offered for new media stays
          // visible only on a group that already uses it.
          if (selected != null &&
              !SignageCatalog.selectableCodes.contains(selected) &&
              SignageCatalog.media(selected) != null)
            SignageCatalog.media(selected)!,
        ])
          _MediaCard(
            media: m,
            selected: m.code == selected,
            onTap: enabled ? () => onSelect(m) : null,
          ),
      ],
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.media, required this.selected, this.onTap});

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
            border: Border.all(
              color: selected ? AdinnColors.red : AdinnColors.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(media.icon, color: media.color),
                  const Spacer(),
                  if (selected)
                    const Icon(
                      Icons.check_circle,
                      color: AdinnColors.red,
                      size: 18,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                media.shortName,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  SignageCatalog.cardSubtitle(media),
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: AdinnColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
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

class _BoardDetailsForm extends StatelessWidget {
  const _BoardDetailsForm({
    required this.shopId,
    required this.board,
    required this.name,
    required this.w,
    required this.h,
    required this.enabled,
    required this.onChanged,
    required this.onSizeSynced,
  });

  final String shopId;
  final Board board;
  final TextEditingController name;
  final TextEditingController w;
  final TextEditingController h;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onSizeSynced;

  /// Changing the display unit must not change the physical board size.
  /// Values are rounded to 6 decimals to prevent drift on repeated switches.
  void _setUnit(MeasureUnit next) {
    if (next == board.unit) return;
    final old = board.unit;
    double? convert(double? value) {
      if (value == null) return null;
      final converted = next.fromFeet(old.toFeet(value));
      return double.parse(converted.toStringAsFixed(6));
    }

    board.width = convert(board.width);
    board.height = convert(board.height);
    for (final u in board.units) {
      u.width = convert(u.width);
      u.height = convert(u.height);
    }
    board.unit = next;
    onSizeSynced();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('board_details_content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The step heading already says "Board Details"; the old compact
        // form starts directly with the Board Name field.
        const Text(
          'Board Name',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('board_name'),
          controller: name,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: 'Board 1',
            prefixIcon: const Icon(Icons.label_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onChanged: (t) {
            board.name = t.trim().isEmpty ? 'Board' : t.trim();
            onChanged();
          },
        ),
        const SizedBox(height: 16),
        const Text(
          'Measurement Unit',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 8),
        _UnitSelector(
          selected: board.unit,
          enabled: enabled,
          onChanged: _setUnit,
        ),
        const SizedBox(height: 16),
        QuantitySizeSection(
          key: ValueKey(
            'qty_${board.id}_${board.unit.name}_'
            '${board.sizeMode.name}_${board.quantity}',
          ),
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

class _UnitSelector extends StatelessWidget {
  const _UnitSelector({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final MeasureUnit selected;
  final bool enabled;
  final ValueChanged<MeasureUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    // One connected four-part control with dividers, a pale red selected
    // segment and a checkmark – the original Measurements appearance.
    return SegmentedButton<MeasureUnit>(
      key: const Key('measurement_unit_selector'),
      segments: [
        for (final u in MeasureUnit.values)
          ButtonSegment<MeasureUnit>(
            value: u,
            label: Text(u.label, key: Key('unit_${u.name}')),
          ),
      ],
      selected: {selected},
      multiSelectionEnabled: false,
      showSelectedIcon: true,
      style: SegmentedButton.styleFrom(
        foregroundColor: AdinnColors.ink,
        selectedForegroundColor: AdinnColors.ink,
        selectedBackgroundColor: AdinnColors.redLight,
        side: BorderSide(color: Colors.grey.shade400),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onSelectionChanged: enabled
          ? (next) {
              if (next.isNotEmpty) onChanged(next.first);
            }
          : null,
    );
  }
}

class _DrawingsStep extends StatelessWidget {
  const _DrawingsStep({required this.board, required this.onOpen});

  final Board board;
  final Future<void> Function(BoardView view) onOpen;

  @override
  Widget build(BuildContext context) {
    // Ready when at least one physical board has what the drawing needs:
    // its OWN effective installation (unit override, else the group's) and
    // size. The group-level installation may legitimately be empty when the
    // boards use different installations.
    final ready = SignageCatalog.drawingReadyUnits(board).isNotEmpty;
    final blocker = board.activeUnits.isEmpty
        ? 'Add a board first.'
        : SignageCatalog.unitDrawingBlocker(board, board.activeUnits.first);
    final saved = board.drawingPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!ready)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Select media and installation type to generate drawings.'
              '${blocker == null ? '' : ' ($blocker)'}',
              key: const Key('drawings_blocker'),
              style: const TextStyle(color: AdinnColors.muted),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('open_2d'),
                onPressed: ready ? () => onOpen(BoardView.drawing2d) : null,
                icon: const Icon(Icons.architecture),
                label: const Text('2D Drawing'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('open_3d'),
                onPressed: ready ? () => onOpen(BoardView.preview3d) : null,
                icon: const Icon(Icons.view_in_ar),
                label: const Text('3D Preview'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('open_camera_ar'),
          onPressed: ready ? () => onOpen(BoardView.cameraAr) : null,
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

/// Selected GSB board type with a "Change" action (reopens the sheet).
class _GsbVariantSummary extends StatelessWidget {
  const _GsbVariantSummary({
    required this.board,
    required this.enabled,
    required this.onChange,
  });

  final Board board;
  final bool enabled;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final explicit = GsbBoard.isExplicit(board);
    final variant = GsbBoard.variantOf(board)!;
    return Container(
      key: const Key('gsb_variant_summary'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: explicit ? AdinnColors.redLight : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: explicit ? AdinnColors.red : const Color(0xFFFFCC80),
        ),
      ),
      child: Row(
        children: [
          Icon(
            variant.isDouble ? Icons.flip : Icons.crop_landscape,
            color: AdinnColors.red,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  explicit ? variant.label : 'GSB board type not confirmed',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  explicit
                      ? (variant.isDouble
                            ? 'Two display faces on one physical board.'
                            : 'One display face (front artwork).')
                      : 'Older record shown as single-sided. Tap Change to '
                            'confirm the board type.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AdinnColors.muted,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('gsb_variant_change'),
            onPressed: enabled ? onChange : null,
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

/// Selected NLB frame type with a "Change" action (reopens the sheet).
class _NlbVariantSummary extends StatelessWidget {
  const _NlbVariantSummary({
    required this.variant,
    required this.enabled,
    required this.onChange,
  });

  final NlbVariant variant;
  final bool enabled;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('nlb_variant_summary'),
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
    decoration: BoxDecoration(
      color: AdinnColors.redLight,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AdinnColors.red),
    ),
    child: Row(
      children: [
        Icon(
          variant == NlbVariant.boxFrame
              ? Icons.inventory_2_outlined
              : Icons.crop_landscape,
          color: AdinnColors.red,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            variant.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        TextButton(
          key: const Key('nlb_variant_change'),
          onPressed: enabled ? onChange : null,
          child: const Text('Change'),
        ),
      ],
    ),
  );
}

/// Single / double-sided choice for Non-Lit boards (GSB uses the board
/// type sheet instead).
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
