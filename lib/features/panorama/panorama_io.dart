import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models/models.dart';
import '../../data/storage/media_storage.dart';
import '../../state/app_controller.dart';

// Panorama import plumbing. Picker, size probe, file writer and image loader
// are injectable so tests never touch platform channels or real files.

/// An image picked from the gallery (not yet validated or stored).
class PickedPanorama {
  const PickedPanorama({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;

  /// File extension used for the app-local copy.
  String get extension {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'png';
    if (n.endsWith('.webp')) return 'webp';
    return 'jpg';
  }
}

enum PanoramaPickerFailure { permissionDenied, unavailable }

class PanoramaPickerException implements Exception {
  const PanoramaPickerException(this.failure, this.message);

  final PanoramaPickerFailure failure;
  final String message;

  @override
  String toString() => message;
}

/// Gallery picker for panoramas. Returns null when the user cancels; throws
/// [PanoramaPickerException] when access is denied / unavailable.
abstract class PanoramaPicker {
  Future<PickedPanorama?> pickFromGallery();
}

class ImagePickerPanoramaPicker implements PanoramaPicker {
  const ImagePickerPanoramaPicker();

  @override
  Future<PickedPanorama?> pickFromGallery() async {
    final XFile? picked;
    try {
      // No resizing: the full resolution is needed (min 2000 px wide).
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
    } on PlatformException catch (e) {
      final code = e.code.toLowerCase();
      if (code.contains('denied') || code.contains('access')) {
        throw const PanoramaPickerException(
          PanoramaPickerFailure.permissionDenied,
          'Photo access was denied. Allow photos / media access for Adinn '
          'Recce in the phone settings, then try again.',
        );
      }
      throw PanoramaPickerException(
        PanoramaPickerFailure.unavailable,
        'The gallery could not be opened (${e.message ?? e.code}).',
      );
    }
    if (picked == null) return null;
    return PickedPanorama(bytes: await picked.readAsBytes(), name: picked.name);
  }
}

/// Pixel size of an encoded image.
class PanoramaImageInfo {
  const PanoramaImageInfo(this.width, this.height);

  final int width;
  final int height;
}

/// Reads the size of an encoded image (throws when it can't be decoded).
abstract class PanoramaImageProbe {
  Future<PanoramaImageInfo> probe(Uint8List bytes);
}

/// dart:ui based probe: reads the header and decodes a small thumbnail to
/// prove the file is a decodable image (without decoding it at full size).
class DartUiPanoramaProbe implements PanoramaImageProbe {
  const DartUiPanoramaProbe();

  @override
  Future<PanoramaImageInfo> probe(Uint8List bytes) async {
    if (bytes.isEmpty) throw const FormatException('Empty file');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final info = PanoramaImageInfo(descriptor.width, descriptor.height);
      final codec = await descriptor.instantiateCodec(targetWidth: 64);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
      return info;
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}

class PanoramaImportException implements Exception {
  const PanoramaImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Writes bytes to app storage and returns the path.
typedef PanoramaFileWriter =
    Future<String> Function(Uint8List bytes, String extension);

/// Writer into MediaStorage folder "panoramas".
PanoramaFileWriter mediaPanoramaWriter(MediaStorage? media) =>
    (bytes, extension) async {
      if (media == null) {
        throw const PanoramaImportException('Storage not available');
      }
      final path = await media.newFilePath('panoramas', extension);
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    };

/// Validates an image as an equirectangular panorama and stores it.
class PanoramaImporter {
  const PanoramaImporter({
    this.probe = const DartUiPanoramaProbe(),
    required this.writer,
  });

  final PanoramaImageProbe probe;
  final PanoramaFileWriter writer;

  /// Size of [bytes] if it is an acceptable panorama; otherwise throws
  /// [PanoramaImportException] with a readable message.
  Future<PanoramaImageInfo> validate(Uint8List bytes) async {
    PanoramaImageInfo info;
    try {
      info = await probe.probe(bytes);
    } catch (_) {
      throw const PanoramaImportException(
        'The selected file is not a readable image.',
      );
    }
    final problem = panoramaSizeProblem(info.width, info.height);
    if (problem != null) throw PanoramaImportException(problem);
    return info;
  }

  /// Validates, copies into app storage and registers the panorama.
  /// Nothing is written when validation fails.
  Future<PanoramaRecord> importInto(
    AppController c,
    String shopId,
    PickedPanorama picked, {
    String label = '360° panorama',
  }) async {
    if (!c.canEditPanoramas(shopId)) {
      throw const PanoramaImportException('This recce is read-only now.');
    }
    final info = await validate(picked.bytes);
    final path = await writer(picked.bytes, picked.extension);
    return c.addPanorama(
      shopId: shopId,
      path: path,
      width: info.width,
      height: info.height,
      label: label,
    );
  }
}

/// Loads a panorama for display.
typedef PanoramaImageLoader = Future<ui.Image> Function(String path);

/// Largest width decoded for display (GPU texture limit on most phones).
const panoramaDisplayMaxWidth = 4096;

Future<ui.Image> loadPanoramaImage(String path) async {
  final bytes = await File(path).readAsBytes();
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  try {
    final codec = await descriptor.instantiateCodec(
      targetWidth: math.min(descriptor.width, panoramaDisplayMaxWidth),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}

/// Writes a rendered preview PNG and returns its path.
typedef PanoramaPreviewWriter = Future<String> Function(Uint8List png);

PanoramaPreviewWriter mediaPreviewWriter(MediaStorage? media) => (png) async {
  if (media == null) throw StateError('Storage not available');
  final path = await media.newFilePath('panoramas', 'png');
  await File(path).writeAsBytes(png, flush: true);
  return path;
};
