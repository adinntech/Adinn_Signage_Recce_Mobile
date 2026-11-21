import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_file_row.dart';
import '../../../core/widgets/common_widgets.dart' show showSnack;
import '../../../data/models/models.dart' show GeoFix;
import '../../../data/services/location_service.dart';
import '../../location/gps_widgets.dart' show locationServiceOf;
import '../data/recce_models.dart';

/// A photo taken with the camera together with the GPS fix read just before the shutter.
class CapturedPhoto {
  const CapturedPhoto({required this.path, required this.lat, required this.lng, required this.accuracy, required this.capturedAt, this.width, this.height});

  final String path;
  final double lat;
  final double lng;
  final double accuracy;
  final DateTime capturedAt;
  final int? width;
  final int? height;

  /// Accuracy worse than 50 m: shown as "location unverified" (still uploaded; the server flags it too).
  bool get unverified => accuracy > gpsAccuracyLimitM;
}

/// Gets a FRESH GPS fix first (clear message + Retry when permission is denied, location is off or no fresh fix arrives),
/// then opens the camera, then shows a preview with lat/lng/accuracy/time. Returns null when the person cancels.
/// A camera error (permission denied) is explained with Try again / Open settings, never thrown at the caller.
Future<CapturedPhoto?> captureGeoPhoto(BuildContext context, {required String label}) async {
  var recovered = await _recoverLostShot();
  while (true) {
    if (!context.mounted) {
      if (recovered != null) _discard(recovered.path);
      return null;
    }
    final fix = await _fixWithRetry(context);
    if (fix == null || !context.mounted) {
      if (recovered != null) {
        // A picture can only carry a location read now; without one it is not kept.
        _discard(recovered.path);
        if (context.mounted) showSnack(context, 'The photo taken before the app closed was not kept: no GPS location.', error: true);
      }
      return null;
    }

    final bool wasRecovered;
    final XFile? shot;
    if (recovered != null) {
      shot = recovered;
      recovered = null;
      wasRecovered = true;
    } else {
      final taken = await _takeShot(context);
      if (taken.retry) continue; // read the GPS again: the dialogs may have taken a while
      shot = taken.shot;
      wasRecovered = false;
    }
    if (shot == null || !context.mounted) return null;

    final takenAt = wasRecovered ? await _shotTime(shot) : DateTime.now().toUtc();
    final path = await _keepCopy(shot.path);
    final size = await _imageSize(path);
    final photo = CapturedPhoto(
      path: path,
      lat: fix.latitude,
      lng: fix.longitude,
      accuracy: fix.accuracyM,
      capturedAt: takenAt,
      width: size?.$1,
      height: size?.$2,
    );
    if (!context.mounted) return null;
    final choice = await Navigator.of(context).push<_PreviewChoice>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => _PhotoPreview(photo: photo, label: label, recovered: wasRecovered)),
    );
    if (choice == _PreviewChoice.use) return photo;
    _discard(path);
    if (choice != _PreviewChoice.retake) return null;
  }
}

bool _lostDataChecked = false;

/// Android can kill the app while the camera is open; the picture is then waiting in the picker. It is collected once per
/// app start (the first capture), and only used when a fresh GPS fix can still be read for it.
Future<XFile?> _recoverLostShot() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || _lostDataChecked) return null;
  _lostDataChecked = true;
  try {
    final lost = await ImagePicker().retrieveLostData();
    if (lost.isEmpty || lost.file == null) return null;
    if (lost.type != null && lost.type != RetrieveType.image) return null;
    return lost.file;
  } catch (_) {
    return null; // never block a new capture because of an old one
  }
}

/// When a recovered picture was really taken (its file time), so the preview and the server do not show "just now".
Future<DateTime> _shotTime(XFile shot) async {
  final now = DateTime.now();
  try {
    final at = await shot.lastModified();
    return (at.isAfter(now) ? now : at).toUtc();
  } catch (_) {
    return now.toUtc();
  }
}

/// Opens the camera. `shot` is null when the person cancels. When the camera cannot open (permission denied, no camera) the
/// reason is shown and the person can try again (`retry: true`), open the app settings, or cancel.
Future<({XFile? shot, bool retry})> _takeShot(BuildContext context) async {
  try {
    final shot = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2400, imageQuality: 85);
    return (shot: shot, retry: false);
  } catch (e) {
    if (!context.mounted) return (shot: null, retry: false);
    final denied = e is PlatformException && e.code.startsWith('camera_access');
    final service = locationServiceOf(context);
    var action = await _askCameraAction(context, denied: denied);
    while (action == _CameraAction.settings) {
      await _openSettingsSafely(service, appSettings: true);
      if (!context.mounted) return (shot: null, retry: false);
      action = await _askCameraAction(context, denied: denied); // shown again for when the person comes back
    }
    return (shot: null, retry: action == _CameraAction.retry);
  }
}

enum _CameraAction { retry, settings, cancel }

Future<_CameraAction?> _askCameraAction(BuildContext context, {required bool denied}) {
  return showDialog<_CameraAction>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.no_photography_outlined, color: AdinnColors.red, size: 32),
      title: Text(denied ? 'Camera permission needed' : 'Camera could not open'),
      content: Text(
        denied
            ? 'Allow camera access to take recce photos.${kIsWeb ? '' : ' Open settings, allow Camera, then come back and try again.'}'
            : 'The camera could not be opened. Close other camera apps and try again.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, _CameraAction.cancel), child: const Text('Cancel')),
        if (denied && !kIsWeb) TextButton(onPressed: () => Navigator.pop(ctx, _CameraAction.settings), child: const Text('Open settings')),
        FilledButton(onPressed: () => Navigator.pop(ctx, _CameraAction.retry), child: const Text('Try again')),
      ],
    ),
  );
}

/// Opens the system or app settings. A browser cannot (geolocator_web throws UnsupportedError) and a phone may refuse:
/// either way nothing escapes, the person simply stays in the flow.
Future<void> _openSettingsSafely(LocationService service, {required bool appSettings}) async {
  if (kIsWeb) return;
  try {
    await service.openSettings(appSettings: appSettings);
  } on UnsupportedError {
    // not supported on this platform
  } catch (_) {
    // settings page could not be opened
  }
}

/// Reads the GPS fix. On failure the person sees the reason and can retry, open settings, or cancel (null).
Future<GeoFix?> _fixWithRetry(BuildContext context) async {
  final service = locationServiceOf(context);
  while (true) {
    if (!context.mounted) return null;
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
            SizedBox(width: 16),
            Expanded(child: Text('Getting your location...')),
          ]),
        ),
      ),
    );
    try {
      // Strict: this position becomes the photo's own, so a fresh reading or nothing (never a stale cached one).
      final fix = await freshFixOf(service);
      navigator.pop();
      return fix;
    } on LocationException catch (e) {
      navigator.pop();
      if (!context.mounted) return null;
      final action = await _askLocationAction(context, e);
      if (action == _LocationAction.cancel || action == null) return null;
      if (action == _LocationAction.settings) {
        await _openSettingsSafely(service, appSettings: e.issue == LocationIssue.permissionDeniedForever);
      }
    } catch (_) {
      navigator.pop();
      if (!context.mounted) return null;
      final again = await _askLocationAction(context, const LocationException(LocationIssue.unavailable, 'Could not read your location.'));
      if (again != _LocationAction.retry) return null;
    }
  }
}

enum _LocationAction { retry, settings, cancel }

Future<_LocationAction?> _askLocationAction(BuildContext context, LocationException e) {
  // A browser cannot open the phone's settings, so it only offers Retry.
  final canOpen = !kIsWeb &&
      (e.issue == LocationIssue.serviceDisabled ||
          e.issue == LocationIssue.permissionDenied ||
          e.issue == LocationIssue.permissionDeniedForever);
  return showDialog<_LocationAction>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.location_off_outlined, color: AdinnColors.red, size: 32),
      title: const Text('Location is needed'),
      content: Text('${e.message}\n\nEvery recce photo must carry the GPS location where it was taken.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, _LocationAction.cancel), child: const Text('Cancel')),
        if (canOpen) TextButton(onPressed: () => Navigator.pop(ctx, _LocationAction.settings), child: const Text('Open settings')),
        FilledButton(onPressed: () => Navigator.pop(ctx, _LocationAction.retry), child: const Text('Retry')),
      ],
    ),
  );
}

/// The camera file lives in a temp folder; keep our own copy until the server has stored the photo.
Future<String> _keepCopy(String source) async {
  if (kIsWeb) return source; // a browser has no app folder; the picked file address stays valid for this session
  try {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/live_recce_media');
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest = File('${dir.path}/shot_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await File(source).copy(dest.path);
    return dest.path;
  } catch (_) {
    return source;
  }
}

void _discard(String path) {
  if (kIsWeb) return;
  try {
    File(path).deleteSync();
  } catch (_) {}
}

Future<(int, int)?> _imageSize(String path) async {
  try {
    final codec = await ui.instantiateImageCodec(await XFile(path).readAsBytes());
    final frame = (await codec.getNextFrame()).image;
    final r = (frame.width, frame.height);
    frame.dispose();
    return r;
  } catch (_) {
    return null;
  }
}

enum _PreviewChoice { use, retake }

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.photo, required this.label, this.recovered = false});

  final CapturedPhoto photo;
  final String label;

  /// The picture was taken before the app was closed by the phone; the location was read just now.
  final bool recovered;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(label),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          Expanded(child: InteractiveViewer(child: Center(child: AppFileRow.image(null, photo.path, fit: BoxFit.contain)))),
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(photo.unverified ? Icons.wrong_location_outlined : Icons.location_on, color: photo.unverified ? AdinnColors.warning : AdinnColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        photo.unverified ? 'Location unverified (accuracy ${photo.accuracy.toStringAsFixed(0)} m)' : 'Location captured',
                        style: TextStyle(fontWeight: FontWeight.w800, color: photo.unverified ? AdinnColors.warning : AdinnColors.success),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text('Latitude ${photo.lat.toStringAsFixed(6)}    Longitude ${photo.lng.toStringAsFixed(6)}'),
                  Text('Accuracy ${photo.accuracy.toStringAsFixed(1)} m    Time ${fmtDateTime(photo.capturedAt)}'),
                  if (recovered)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Recovered: this photo was taken before the app closed. The location above was read just now. Use it only if it is the $label photo, otherwise tap Retake.',
                        style: const TextStyle(color: AdinnColors.warning, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (photo.unverified)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('You can still use this photo, but the reviewer will see the weak location. Retake in an open area for a better fix.', style: TextStyle(color: AdinnColors.muted, fontSize: 12)),
                    ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () => Navigator.pop(context, _PreviewChoice.retake), icon: const Icon(Icons.refresh), label: const Text('Retake'))),
                    const SizedBox(width: 12),
                    Expanded(child: FilledButton.icon(onPressed: () => Navigator.pop(context, _PreviewChoice.use), icon: const Icon(Icons.check), label: const Text('Use photo'))),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
