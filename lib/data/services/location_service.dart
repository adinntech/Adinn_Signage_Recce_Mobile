import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/models.dart';

enum LocationIssue {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  unavailable,
}

class LocationException implements Exception {
  const LocationException(this.issue, this.message);

  final LocationIssue issue;
  final String message;

  @override
  String toString() => message;
}

/// How old a "last known" position may be before the strict path refuses to use it as the position of a new photo.
const freshFixMaxAge = Duration(seconds: 30);

/// Turns a last-known [last] position into a fix ONLY when it is younger than [maxAge] (and not from the future).
/// Anything older is somewhere the person may no longer be, so it must never be labelled as the photo's own location.
GeoFix? lastKnownIfFresh(Position? last, {DateTime? now, Duration maxAge = freshFixMaxAge}) {
  if (last == null) return null;
  final age = (now ?? DateTime.now()).difference(last.timestamp);
  if (age.isNegative || age > maxAge) return null;
  return _fixOf(last);
}

GeoFix _fixOf(Position p) => GeoFix(
  latitude: p.latitude,
  longitude: p.longitude,
  accuracyM: p.accuracy,
  capturedAt: p.timestamp.toLocal(),
);

/// Reads the device GPS. Everything stays on the device; nothing is sent to
/// any server (no maps API or reverse geocoding is used).
abstract class LocationService {
  Future<GeoFix> currentFix({Duration timeout = const Duration(seconds: 20)});

  /// Opens the system location settings, or the app's settings page when
  /// [appSettings] is true (to re-grant a permanently denied permission).
  Future<bool> openSettings({bool appSettings = false});
}

/// A location service that can give a STRICT fix for a live camera photo (see [freshFixOf]). Kept apart from
/// [LocationService] so existing implementations (and test fakes) need no change.
abstract interface class StrictLocationService {
  /// A fresh reading only: it never falls back to an old cached position (at most one younger than [freshFixMaxAge])
  /// and never to the shop's saved location. When no fresh fix arrives in [timeout] it throws [LocationException]
  /// with [LocationIssue.timeout].
  Future<GeoFix> freshFix({Duration timeout = const Duration(seconds: 15)});
}

/// The fix for a live camera photo. Uses the strict path when [service] has one; a service without it (a test fake)
/// answers through [LocationService.currentFix].
Future<GeoFix> freshFixOf(LocationService service, {Duration timeout = const Duration(seconds: 15)}) =>
    service is StrictLocationService
    ? (service as StrictLocationService).freshFix(timeout: timeout)
    : service.currentFix(timeout: timeout);

class DeviceLocationService implements LocationService, StrictLocationService {
  /// Location on and permission granted, or a [LocationException] saying why not.
  Future<void> _ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        LocationIssue.serviceDisabled,
        'Location (GPS) is turned off. Turn it on to capture the shop location.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException(
        LocationIssue.permissionDenied,
        'Location permission is needed to capture GPS.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        LocationIssue.permissionDeniedForever,
        'Location permission is blocked. Enable it in app settings.',
      );
    }
  }

  @override
  Future<GeoFix> currentFix({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await _ensureReady();
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: _settings(timeout),
      );
      return _toFix(p);
    } on TimeoutException {
      // Fall back to the last known fix rather than failing outright.
      final last = await Geolocator.getLastKnownPosition(
        forceAndroidLocationManager: _isAndroid,
      );
      if (last != null) return _toFix(last);
      throw const LocationException(
        LocationIssue.timeout,
        'Could not get a GPS fix. Move to an open area and try again.',
      );
    } on LocationServiceDisabledException {
      throw const LocationException(
        LocationIssue.serviceDisabled,
        'Location (GPS) is turned off.',
      );
    }
  }

  @override
  Future<GeoFix> freshFix({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await _ensureReady();
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: _settings(timeout),
      );
      return _toFix(p);
    } on TimeoutException {
      Position? last;
      try {
        last = await Geolocator.getLastKnownPosition(
          forceAndroidLocationManager: _isAndroid,
        );
      } catch (_) {
        last = null; // not supported on the web, or the platform refused: no fallback
      }
      final fix = lastKnownIfFresh(last);
      if (fix != null) return fix;
      throw const LocationException(
        LocationIssue.timeout,
        'Could not get a fresh GPS fix. Move to an open area and try again.',
      );
    } on LocationServiceDisabledException {
      throw const LocationException(
        LocationIssue.serviceDisabled,
        'Location (GPS) is turned off.',
      );
    }
  }

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// On Android, read GPS straight from the platform LocationManager instead
  /// of Google's fused provider: no Play-services "Location Accuracy" consent
  /// prompt (declining it made the fused request fail even with GPS on), and
  /// no data shared with Google. Recces happen outdoors, where GPS is fine.
  static LocationSettings _settings(Duration timeout) => _isAndroid
      ? AndroidSettings(
          accuracy: LocationAccuracy.high,
          forceLocationManager: true,
          timeLimit: timeout,
        )
      : LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeout);

  GeoFix _toFix(Position p) => _fixOf(p);

  @override
  Future<bool> openSettings({bool appSettings = false}) => appSettings
      ? Geolocator.openAppSettings()
      : Geolocator.openLocationSettings();
}
