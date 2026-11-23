import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:signage_recce/features/live_recce/data/photo_shrink.dart';

/// A noisy picture (noise does not compress, so it is big like a detailed shop photo).
Uint8List _noisyJpeg(int w, int h, {int quality = 100}) {
  final r = Random(7);
  final image = img.Image(width: w, height: h);
  for (final p in image) {
    p.setRgb(r.nextInt(256), r.nextInt(256), r.nextInt(256));
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

void main() {
  test('a picture under the limit is sent exactly as it is', () async {
    final small = _noisyJpeg(80, 60, quality: 80);
    final out = await shrinkPhoto(small, limit: serverPhotoLimitBytes);
    expect(identical(out, small), isTrue);
  });

  test('a picture over the limit is re-encoded under it and stays a readable JPEG', () async {
    final big = _noisyJpeg(1600, 1200);
    const limit = 400 * 1024;
    expect(big.length, greaterThan(limit));

    final out = await shrinkPhoto(big, limit: limit);
    expect(out.length, lessThanOrEqualTo(limit));
    final decoded = img.decodeJpg(out);
    expect(decoded, isNotNull);
    expect(decoded!.width, lessThanOrEqualTo(1600));
    expect(decoded.width / decoded.height, closeTo(1600 / 1200, 0.02)); // same shape, not cropped
  });

  test('the file extension follows what the bytes really are', () {
    Uint8List of(List<int> head) => Uint8List.fromList([...head, ...List.filled(40, 1)]);
    expect(photoExtension(of([0xff, 0xd8, 0xff, 0xe0])), 'jpg');
    expect(photoExtension(of([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])), 'png'); // a PNG screenshot is not ".jpg"
    expect(photoExtension(of([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits])), 'webp');
    expect(photoExtension(of('GIF89a'.codeUnits)), 'gif');
    expect(photoExtension(of([...'BM'.codeUnits, 0, 0, 0, 0, 0, 0, 0, 0])), 'bmp');
    expect(photoExtension(of([0, 0, 0, 24, ...'ftypheic'.codeUnits])), 'heic');
    expect(photoExtension(Uint8List.fromList(List.filled(50, 7))), 'jpg'); // unknown bytes: the server gives the answer
    expect(photoExtension(Uint8List(0)), 'jpg');
  });

  test('bytes that are not a picture are returned untouched (the server gives the answer)', () async {
    final junk = Uint8List.fromList(List.filled(1000, 7));
    expect(identical(await shrinkPhoto(junk, limit: 100), junk), isTrue);
  });
}
