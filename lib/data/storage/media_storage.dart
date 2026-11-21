import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local folders for captured photos, voice notes and exported drawings.
/// Everything stays inside the app's private storage on the device.
class MediaStorage {
  Directory? _root;

  Future<Directory> _rootDir() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    return _root = Directory(
      '${docs.path}${Platform.pathSeparator}adinn_recce${Platform.pathSeparator}media',
    );
  }

  Future<Directory> folder(String name) async {
    final root = await _rootDir();
    final dir = Directory('${root.path}${Platform.pathSeparator}$name');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// A fresh, unique file path such as `.../media/photos/<id>.jpg`.
  Future<String> newFilePath(String folderName, String extension) async {
    final dir = await folder(folderName);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '${dir.path}${Platform.pathSeparator}$stamp.$extension';
  }

  Future<void> deleteIfExists(String? path) async {
    if (path == null || path.isEmpty || path.startsWith('demo://')) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // Ignore: the file is already gone or locked; nothing else to do.
    }
  }

  Future<void> deleteAll() async {
    final root = await _rootDir();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
