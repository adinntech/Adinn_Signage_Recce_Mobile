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

/// Reads the device GPS. Everything stays on the device; nothing is sent to
/// any server (no maps API or reverse geocoding is used).
abstract class LocationService {
  Future<GeoFix> currentFix({Duration timeout = const Duration(seconds: 20)});

  /// Opens the system location settings, or the app's settings page when
  /// [appSettings] is true (to re-grant a permanently denied permission).
  Future<bool> openSettings({bool appSettings = false});
}

class DeviceLocationService implements LocationService {
  @override
  Future<GeoFix> currentFix({
    Duration timeout = const Duration(seconds: 20),
  }) async {
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

  GeoFix _toFix(Position p) => GeoFix(
    latitude: p.latitude,
    longitude: p.longitude,
    accuracyM: p.accuracy,
    capturedAt: p.timestamp.toLocal(),
  );

  @override
  Future<bool> openSettings({bool appSettings = false}) => appSettings
      ? Geolocator.openAppSettings()
      : Geolocator.openLocationSettings();
}
