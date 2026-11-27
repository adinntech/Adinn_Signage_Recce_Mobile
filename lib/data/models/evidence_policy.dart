import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Cached validation state of an original site photo.
enum EvidenceState { unknown, verifying, valid, invalid }

/// Which photos may count as real site evidence.
///
/// A photo counts only after it has been ASYNCHRONOUSLY VERIFIED: a real
/// frame must decode successfully. Unknown / verifying / invalid paths never
/// satisfy readiness. Decisions are cached, so widget rebuilds never touch
/// the disk or decode images.
class EvidencePolicy {
  EvidencePolicy._();

  /// Demo mode: `--dart-define=DEMO_EVIDENCE=true` (tests enable it too).
  /// Production builds never enable it.
  static bool allowDemo = const bool.fromEnvironment('DEMO_EVIDENCE');

  /// Test-only shortcut for synthetic paths. Never enabled in production.
  static bool checkFiles = true;

  static const _demo = 'demo://';
  static const _maxDecodedSide = 2048;

  static final _states = <String, EvidenceState>{};
  static final _fingerprints = <String, String>{};
  static final _meta = <String, String>{}; // length + mtime, cheap revalidation

  /// Called when a cached availability state changes (UI must recalculate).
  static void Function()? onChanged;

  static bool isDemoPath(String path) => path.startsWith(_demo);

  static EvidenceState stateOf(String path) =>
      _states[path] ?? EvidenceState.unknown;

  /// True while any registered photo is still being verified.
  static bool get hasPending =>
      _states.values.any((s) => s == EvidenceState.verifying);

  /// Cached content fingerprint (FNV-1a over the verified bytes). Photos with
  /// identical bytes count once even with different filenames.
  static String fingerprintOf(String path) => _fingerprints[path] ?? path;

  /// Cheap, cache-only decision. Unknown and verifying never count.
  static bool isUsable(String path) {
    if (path.trim().isEmpty) return false;
    if (isDemoPath(path)) return allowDemo;
    if (!checkFiles) return true; // isolated tests with synthetic paths
    return _states[path] == EvidenceState.valid;
  }

  /// Registers [paths] as verifying (pending) before async work starts.
  static void markVerifying(Iterable<String> paths) {
    var changed = false;
    for (final p in paths) {
      if (p.trim().isEmpty || isDemoPath(p)) continue;
      if (_states[p] != EvidenceState.valid) {
        changed |= _states[p] != EvidenceState.verifying;
        _states[p] = EvidenceState.verifying;
      }
    }
    if (changed) onChanged?.call();
  }

  /// Verifies [paths] in the background. Unknown paths stay unknown until
  /// this completes; already-valid paths are rechecked when file metadata
  /// changed (delete / replace / truncate / restore while app was closed).
  static Future<void> verify(
    Iterable<String> paths, {
    bool force = false,
  }) async {
    if (!checkFiles) return;
    final targets = <String>{};
    for (final p in paths) {
      if (p.trim().isEmpty || isDemoPath(p)) continue;
      if (!force && _states[p] == EvidenceState.valid) {
        final sig = await _signature(p);
        if (sig != null && sig == _meta[p]) continue; // still the same file
      }
      targets.add(p);
    }
    if (targets.isEmpty) return;
    markVerifying(targets);

    final results = <String, bool>{};
    final bytesByPath = <String, Uint8List>{};
    for (final p in targets) {
      final sig = await _signature(p);
      final (good, bytes) = await _decode(p);
      results[p] = good;
      if (sig != null) _meta[p] = sig;
      if (bytes != null) bytesByPath[p] = bytes;
    }

    var changed = false;
    for (final p in targets) {
      final good = results[p] ?? false;
      final next = good ? EvidenceState.valid : EvidenceState.invalid;
      changed |= _states[p] != next;
      _states[p] = next;
      if (good && bytesByPath[p] != null) {
        _fingerprints[p] = _fnv(bytesByPath[p]!);
      } else if (!good) {
        _fingerprints.remove(p);
        _meta.remove(p);
      }
    }
    if (changed) onChanged?.call();
  }

  /// Cheap metadata signature; null means the file is absent/unreadable.
  static Future<String?> _signature(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      final st = await f.stat();
      if (st.size <= 0) return null;
      return '${st.size}:${st.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  /// Real pixel validation: decode at least one frame, bounded in size.
  /// Returns (isUsable, bytes) so fingerprints come from verified content.
  static Future<(bool, Uint8List?)> _decode(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) return (false, null);
      final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buf);
        final w = descriptor.width, h = descriptor.height;
        if (w <= 0 || h <= 0) return (false, null);
        final scale = _maxDecodedSide / (w > h ? w : h);
        final codec = scale < 1
            ? await ui.instantiateImageCodec(
                bytes,
                targetWidth: (w * scale).round(),
                targetHeight: (h * scale).round(),
              )
            : await ui.instantiateImageCodec(bytes);
        try {
          final frame = await codec.getNextFrame();
          final image = frame.image;
          final ok = image.width > 0 && image.height > 0;
          image.dispose();
          if (!ok) return (false, null);
        } finally {
          codec.dispose();
        }
        return (true, bytes);
      } finally {
        descriptor?.dispose();
        buf.dispose();
      }
    } catch (_) {
      return (false, null);
    }
  }

  static String _fnv(List<int> bytes) {
    var h = 0xcbf29ce484222325;
    for (final b in bytes) {
      h ^= b;
      h *= 0x100000001b3;
    }
    return h.toRadixString(16);
  }

  /// Forget a path so it becomes unknown again (delete / replace / removal).
  static void forget(String path) {
    final had = _states.remove(path);
    _fingerprints.remove(path);
    _meta.remove(path);
    if (had != null) onChanged?.call();
  }

  /// Forget all cached results (app resume / draft reopen boundary).
  static void invalidateAll() {
    if (_states.isEmpty) return;
    _states.clear();
    _fingerprints.clear();
    _meta.clear();
    onChanged?.call();
  }
}
