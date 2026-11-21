import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists the whole app state as one JSON document on the device.
abstract class LocalStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> data);
  Future<void> clear();

  /// Keeps a copy of the original JSON before a repair / migration rewrites
  /// it (so a failed or lossy upgrade never destroys the user's data).
  Future<void> backup(Map<String, dynamic> raw, String reason);
}

/// JSON file in the app's private documents directory.
class FileLocalStore implements LocalStore {
  FileLocalStore({this.fileName = 'adinn_recce_state.json'});

  final String fileName;
  File? _file;

  Future<File> _resolve() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}${Platform.pathSeparator}adinn_recce');
    if (!await folder.exists()) await folder.create(recursive: true);
    return _file = File('${folder.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<Map<String, dynamic>?> read() async {
    final file = await _resolve();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(Map<String, dynamic> data) async {
    final file = await _resolve();
    // Write to a temp file first so a crash never leaves half-written JSON.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }

  @override
  Future<void> clear() async {
    final file = await _resolve();
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> backup(Map<String, dynamic> raw, String reason) async {
    final file = await _resolve();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final out = File('${file.path}.backup-$reason-$stamp.json');
    await out.writeAsString(jsonEncode(raw), flush: true);
  }
}

/// In-memory store used by tests.
class MemoryLocalStore implements LocalStore {
  MemoryLocalStore([this._data]);

  Map<String, dynamic>? _data;
  int writes = 0;

  /// Backups taken (reason, data) – inspected by tests.
  final List<(String, Map<String, dynamic>)> backups = [];

  Map<String, dynamic>? get data => _data;

  @override
  Future<Map<String, dynamic>?> read() async => _data == null
      ? null
      : jsonDecode(jsonEncode(_data)) as Map<String, dynamic>;

  @override
  Future<void> write(Map<String, dynamic> data) async {
    writes++;
    _data = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  }

  @override
  Future<void> clear() async => _data = null;

  @override
  Future<void> backup(Map<String, dynamic> raw, String reason) async => backups
      .add((reason, jsonDecode(jsonEncode(raw)) as Map<String, dynamic>));
}
