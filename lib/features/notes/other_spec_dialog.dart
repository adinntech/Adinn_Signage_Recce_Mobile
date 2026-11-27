import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';
import '../../state/app_controller.dart';
import 'voice_notes_section.dart';

/// One finished recording.
class VoiceTake {
  const VoiceTake(this.path, this.duration);
  final String path;
  final Duration duration;
}

/// Recording back-end of the "Other" dialog (the app's `record` plugin by
/// default; tests inject a fake).
abstract class VoiceCapture {
  /// Null when ready, else a message (permission denied, storage missing…).
  Future<String?> prepare(BuildContext context);
  Future<void> start();

  /// The finished take, or null when nothing usable was recorded.
  Future<VoiceTake?> stop();
  Future<void> cancel();
  void dispose();
}

class DeviceVoiceCapture implements VoiceCapture {
  AudioRecorder? _rec;
  String? _path;
  DateTime? _startedAt;

  @override
  Future<String?> prepare(BuildContext context) async {
    final media = context.read<AppController>().media;
    if (media == null) return 'Storage not available';
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) await openAppSettings();
      return status.isPermanentlyDenied
          ? 'Microphone blocked. Enable it in app settings.'
          : 'Microphone permission is needed to record voice notes';
    }
    _path = await media.newFilePath('voice', 'm4a');
    return null;
  }

  @override
  Future<void> start() async {
    _rec ??= AudioRecorder();
    await _rec!.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: _path!);
    _startedAt = DateTime.now();
  }

  @override
  Future<VoiceTake?> stop() async {
    final started = _startedAt;
    String? p;
    try {
      p = await _rec?.stop();
    } catch (_) {
      p = null;
    }
    p ??= _path;
    _startedAt = null;
    if (p == null || started == null) return null;
    final f = File(p);
    // An unsuccessful / empty recording is never accepted.
    if (!f.existsSync() || f.lengthSync() == 0) return null;
    return VoiceTake(p, DateTime.now().difference(started));
  }

  @override
  Future<void> cancel() async {
    try {
      await _rec?.cancel();
    } catch (_) {}
    _startedAt = null;
  }

  @override
  void dispose() => _rec?.dispose();
}

/// Overrides the recording back-end (tests).
VoiceCapture Function() voiceCaptureFactory = DeviceVoiceCapture.new;

/// "+ Other" popup: a text description and / or a voice recording (with
/// playback and re-record). At least one valid input is required; Cancel
/// returns null and changes nothing.
Future<CustomSpec?> showOtherSpecDialog(
  BuildContext context, {
  required String title,
  required String hint,
  CustomSpec? initial,
}) {
  return showDialog<CustomSpec>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OtherSpecDialog(title: title, hint: hint, initial: initial),
  );
}

class _OtherSpecDialog extends StatefulWidget {
  const _OtherSpecDialog({required this.title, required this.hint, this.initial});

  final String title;
  final String hint;
  final CustomSpec? initial;

  @override
  State<_OtherSpecDialog> createState() => _OtherSpecDialogState();
}

class _OtherSpecDialogState extends State<_OtherSpecDialog> {
  late final _text = TextEditingController(text: widget.initial?.text ?? '');
  late final VoiceCapture _capture;
  VoiceNote? _voice;
  bool _recording = false;
  String? _error;
  DateTime? _since;

  @override
  void initState() {
    super.initState();
    _capture = voiceCaptureFactory();
    _voice = widget.initial?.voice;
  }

  @override
  void dispose() {
    _text.dispose();
    if (_recording) unawaited(_capture.cancel());
    _capture.dispose();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      final take = await _capture.stop();
      if (!mounted) return;
      setState(() => _recording = false);
      if (take == null || take.duration.inMilliseconds < 600) {
        // Too short / failed: nothing is saved and the old take stays.
        setState(() => _error = 'Recording failed or too short – try again.');
        return;
      }
      setState(() {
        _error = null;
        _voice = VoiceNote(
          id: newId('vn'),
          path: take.path,
          durationMs: take.duration.inMilliseconds,
          createdAt: DateTime.now(),
          label: widget.title,
        );
      });
      return;
    }
    final problem = await _capture.prepare(context);
    if (!mounted) return;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    try {
      await _capture.start();
      if (mounted) {
        setState(() {
          _recording = true;
          _since = DateTime.now();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start recording: $e');
    }
  }

  void _save() {
    final spec = CustomSpec(text: _text.text, voice: _voice);
    if (!spec.isValid) {
      setState(() => _error = context.t.textOrVoiceRequired);
      return;
    }
    Navigator.of(context).pop(spec);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AlertDialog(
      title: Text(widget.title, key: const Key('other_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('other_text'),
              controller: _text,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(hintText: widget.hint, isDense: true),
            ),
            const SizedBox(height: 12),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              children: [
                FilledButton.icon(
                  key: const Key('other_record'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AdinnColors.red,
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: _toggleRecord,
                  icon: Icon(_recording ? Icons.stop : Icons.mic),
                  label: Text(
                    _recording
                        ? t.stopRecording
                        : (_voice == null ? t.recordVoice : t.reRecord),
                  ),
                ),
                if (_recording && _since != null)
                  Text(
                    fmtDuration(DateTime.now().difference(_since!)),
                    style: const TextStyle(color: AdinnColors.red),
                  ),
              ],
            ),
            if (_voice != null && !_recording) ...[
              const SizedBox(height: 8),
              VoiceNoteTile(
                key: ValueKey('other_voice_${_voice!.id}'),
                note: _voice!,
                onDelete: () => setState(() => _voice = null),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('other_error'),
                  style: const TextStyle(color: AdinnColors.red, fontSize: 12.5),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('other_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        FilledButton(
          key: const Key('other_save'),
          onPressed: _recording ? null : _save,
          child: Text(t.continueLabel),
        ),
      ],
    );
  }
}
