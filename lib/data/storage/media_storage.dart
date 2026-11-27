import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import 'web_media.dart';

/// Local folders for captured photos, voice notes and exported drawings.
/// Everything stays inside the app's private storage on the device. In a browser (no folders) a `mem://` path is used instead.
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
    final stamp = DateTime.now().microsecondsSinceEpoch;
    if (kIsWeb) return '$memPrefix$folderName/$stamp.$extension';
    final dir = await folder(folderName);
    return '${dir.path}${Platform.pathSeparator}$stamp.$extension';
  }

  Future<void> deleteIfExists(String? path) async {
    if (path == null || path.isEmpty || path.startsWith('demo://')) return;
    if (isMemPath(path)) return removeMem(path);
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // Ignore: the file is already gone or locked; nothing else to do.
    }
  }

  Future<void> deleteAll() async {
    if (kIsWeb) return clearMem();
    final root = await _rootDir();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
