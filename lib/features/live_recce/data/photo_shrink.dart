import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// The largest picture the server stores (backend `MAX_IMAGE_SIZE`, 3 MB). A bigger file is refused with 413.
const serverPhotoLimitBytes = 3 * 1024 * 1024;

/// Headroom below the limit: the multipart wrapper adds a few hundred bytes to the file.
const _headroomBytes = 256 * 1024;

/// (longest side in pixels, JPEG quality) tried in order until the picture fits.
const _steps = <(int, int)>[(2400, 85), (2400, 75), (2000, 75), (1600, 70), (1280, 65), (1024, 60)];

/// Returns [bytes] untouched when they fit under [limit]; otherwise the same picture re-encoded as a smaller JPEG
/// (upright, longest side down to 1024 px). Never throws: when the bytes are not a readable picture they are returned
/// as they are, so the server gives the real answer.
Future<Uint8List> shrinkPhoto(Uint8List bytes, {int limit = serverPhotoLimitBytes}) async {
  if (bytes.length <= limit) return bytes;
  final target = limit > _headroomBytes * 2 ? limit - _headroomBytes : (limit * 0.9).floor();
  try {
    return await compute(_shrink, (bytes, target));
  } catch (_) {
    return bytes;
  }
}

Uint8List _shrink((Uint8List, int) args) {
  final (bytes, target) = args;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final upright = img.bakeOrientation(decoded); // the phone's rotation flag is lost on re-encode, so apply it now
  Uint8List? out;
  for (final (edge, quality) in _steps) {
    final longest = upright.width >= upright.height ? upright.width : upright.height;
    final scaled = longest <= edge
        ? upright
        : upright.width >= upright.height
            ? img.copyResize(upright, width: edge)
            : img.copyResize(upright, height: edge);
    out = img.encodeJpg(scaled, quality: quality);
    if (out.length <= target) return out;
  }
  return out ?? bytes;
}
