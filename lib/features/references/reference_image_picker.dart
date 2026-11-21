import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../../data/storage/media_storage.dart';

/// Picks a reference image from the gallery and copies it into app storage
/// (MediaStorage folder "references"). Injectable so widget tests never
/// touch platform channels.
abstract class ReferenceImagePicker {
  /// App-local path of the copied image, or null when the user cancelled.
  /// Throws with a readable message when storage is unavailable.
  Future<String?> pickAndStore(MediaStorage? media);
}

class GalleryReferenceImagePicker implements ReferenceImagePicker {
  const GalleryReferenceImagePicker();

  @override
  Future<String?> pickAndStore(MediaStorage? media) async {
    if (media == null) throw StateError('Storage not available');
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final ext = picked.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final path = await media.newFilePath('references', ext);
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }
}
