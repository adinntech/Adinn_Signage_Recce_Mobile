import '../../l10n/l10n.dart';
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';

/// Record, play back and delete voice notes for a board. Audio files are
/// stored as AAC (.m4a) inside the app's private storage.
class VoiceNotesSection extends StatefulWidget {
  const VoiceNotesSection({
    super.key,
    required this.shopId,
    required this.board,
    required this.editable,
  });

  final String shopId;
  final Board board;
  final bool editable;

  @override
  State<VoiceNotesSection> createState() => _VoiceNotesSectionState();
}

class _VoiceNotesSectionState extends State<VoiceNotesSection> {
  AudioRecorder? _recorder;
  String? _recordingPath;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  double _level = 0;
  StreamSubscription<Amplitude>? _ampSub;

  bool get _recording => _recordingPath != null;

  @override
  void dispose() {
    _ticker?.cancel();
    _ampSub?.cancel();
    if (_recording) {
      // Discard an unfinished take if the user leaves mid-recording.
      _recorder?.cancel();
    }
    _recorder?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final controller = context.read<AppController>();
    final media = controller.media;
    if (media == null) {
      showSnack(context, context.ui('Storage not available'), error: true);
      return;
    }
    final status = await Permission.microphone.request();
    if (!mounted) return;
    if (!status.isGranted) {
      showSnack(
        context,
        status.isPermanentlyDenied
            ? 'Microphone blocked. Enable it in app settings.'
            : 'Microphone permission is needed to record voice notes',
        error: true,
      );
      if (status.isPermanentlyDenied) await openAppSettings();
      return;
    }
    try {
      _recorder ??= AudioRecorder();
      final path = await media.newFilePath('voice', 'm4a');
      await _recorder!.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _ampSub = _recorder!
          .onAmplitudeChanged(const Duration(milliseconds: 160))
          .listen((a) {
            if (!mounted) return;
            // dBFS is roughly -60 (silence) .. 0 (loud).
            setState(() => _level = ((a.current + 60) / 60).clamp(0.0, 1.0));
          });
      setState(() {
        _recordingPath = path;
        _startedAt = DateTime.now();
        _elapsed = Duration.zero;
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted || _startedAt == null) return;
        setState(() => _elapsed = DateTime.now().difference(_startedAt!));
      });
    } catch (e) {
      if (mounted) {
        showSnack(context, context.uf('Could not start recording: {0}', [e]), error: true);
      }
    }
  }

  Future<void> _stop({bool save = true}) async {
    _ticker?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    // Use wall-clock time: the UI ticker can lag when the device is busy.
    final duration = _startedAt == null
        ? _elapsed
        : DateTime.now().difference(_startedAt!);
    String? path;
    try {
      path = save ? await _recorder?.stop() : null;
      if (!save) await _recorder?.cancel();
    } catch (_) {
      path = null;
    }
    path ??= save ? _recordingPath : null;
    setState(() {
      _recordingPath = null;
      _startedAt = null;
      _level = 0;
    });
    if (!mounted || !save || path == null) return;
    if (duration.inMilliseconds < 600) {
      showSnack(context, context.ui('Recording too short – hold on a bit longer'));
      return;
    }
    final c = context.read<AppController>();
    c.addVoiceNote(
      widget.shopId,
      widget.board.id,
      VoiceNote(
        id: newId('vn'),
        path: path,
        durationMs: duration.inMilliseconds,
        createdAt: DateTime.now(),
        label: 'Voice note ${widget.board.voiceNotes.length + 1}',
      ),
    );
    showSnack(context, context.uf('Voice note saved ({0})', [fmtDuration(duration)]));
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.board.voiceNotes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.editable)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _recording ? AdinnColors.redLight : AdinnColors.canvas,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _recording ? AdinnColors.red : AdinnColors.line,
              ),
            ),
            child: Row(
              children: [
                FloatingActionButton.small(
                  heroTag: 'rec_${widget.board.id}',
                  elevation: 0,
                  backgroundColor: AdinnColors.red,
                  foregroundColor: Colors.white,
                  tooltip: _recording ? 'Stop & save' : 'Record voice note',
                  onPressed: _recording ? _stop : _start,
                  child: Icon(_recording ? Icons.stop : Icons.mic),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _recording
                            ? 'Recording… ${fmtDuration(_elapsed)}'
                            : 'Tap the mic to record a voice note',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _recording ? AdinnColors.red : AdinnColors.ink,
                        ),
                      ),
                      if (_recording) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _level,
                            minHeight: 6,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_recording)
                  IconButton(
                    tooltip: context.ui('Discard'),
                    onPressed: () => _stop(save: false),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (notes.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(context.ui('No voice notes yet.'),
              style: TextStyle(color: AdinnColors.muted),
            ),
          ),
        for (final n in notes)
          VoiceNoteTile(
            note: n,
            onDelete: widget.editable
                ? () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Delete voice note?',
                      message: '${n.label} will be removed from this device.',
                      confirmText: 'Delete',
                      destructive: true,
                    );
                    if (ok && context.mounted) {
                      await context.read<AppController>().removeVoiceNote(
                        widget.shopId,
                        widget.board.id,
                        n.id,
                      );
                    }
                  }
                : null,
          ),
      ],
    );
  }
}

/// Play / pause a single voice note with progress.
class VoiceNoteTile extends StatefulWidget {
  const VoiceNoteTile({super.key, required this.note, this.onDelete});

  final VoiceNote note;
  final VoidCallback? onDelete;

  @override
  State<VoiceNoteTile> createState() => _VoiceNoteTileState();
}

class _VoiceNoteTileState extends State<VoiceNoteTile> {
  AudioPlayer? _player;
  PlayerState _state = PlayerState.stopped;
  Duration _pos = Duration.zero;
  final _subs = <StreamSubscription<dynamic>>[];

  Duration? _fileDuration;

  /// Real length from the player once known, else the stored duration.
  Duration get _total =>
      _fileDuration ?? Duration(milliseconds: widget.note.durationMs);

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!File(widget.note.path).existsSync()) {
      showSnack(context, context.ui('Audio file not found on this device'), error: true);
      return;
    }
    try {
      if (_player == null) {
        final p = AudioPlayer();
        _player = p;
        _subs.add(
          p.onPlayerStateChanged.listen((s) {
            if (mounted) setState(() => _state = s);
          }),
        );
        _subs.add(
          p.onPositionChanged.listen((d) {
            if (mounted) setState(() => _pos = d);
          }),
        );
        _subs.add(
          p.onDurationChanged.listen((d) {
            if (mounted && d > Duration.zero) {
              setState(() => _fileDuration = d);
            }
          }),
        );
        _subs.add(
          p.onPlayerComplete.listen((_) {
            if (mounted) setState(() => _pos = Duration.zero);
          }),
        );
      }
      if (_state == PlayerState.playing) {
        await _player!.pause();
      } else if (_state == PlayerState.paused) {
        await _player!.resume();
      } else {
        await _player!.play(DeviceFileSource(widget.note.path));
      }
    } catch (e) {
      if (mounted) showSnack(context, context.uf('Playback failed: {0}', [e]), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playing = _state == PlayerState.playing;
    final progress = _total.inMilliseconds == 0
        ? 0.0
        : (_pos.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
        child: Row(
          children: [
            IconButton(
              tooltip: playing ? 'Pause' : 'Play',
              onPressed: _toggle,
              icon: Icon(
                playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                color: AdinnColors.red,
                size: 34,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.note.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: AdinnColors.line,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${fmtDuration(playing || _pos > Duration.zero ? _pos : _total)} • ${fmtDateTime(widget.note.createdAt)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AdinnColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onDelete != null)
              IconButton(
                tooltip: context.ui('Delete'),
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
      ),
    );
  }
}
