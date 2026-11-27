import 'dart:typed_data';

/// In a browser there is no device folder (path_provider and dart:io files do not exist there), so captured photos, voice
/// notes and drawings are kept in memory under a `mem://` path for as long as the page is open. On a phone nothing here is used.
const memPrefix = 'mem://';

final Map<String, Uint8List> _store = {};

bool isMemPath(String path) => path.startsWith(memPrefix);

void putMem(String path, Uint8List bytes) => _store[path] = bytes;

Uint8List? getMem(String path) => _store[path];

void removeMem(String path) => _store.remove(path);

void clearMem() => _store.clear();
