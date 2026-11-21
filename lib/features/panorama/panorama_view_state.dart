import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import '../../data/models/models.dart';

/// Viewing direction and zoom of the panorama viewer.
///
/// Projection is an approximate *flat window* over the equirectangular
/// image: screen x maps linearly to yaw and screen y linearly to pitch,
/// with the same degrees-per-pixel on both axes. There is no spherical
/// (rectilinear) correction, so straight lines bend near the top / bottom.
class PanoramaViewState {
  PanoramaViewState({this.yawDeg = 0, this.pitchDeg = 0, this.zoom = 1})
    : initialYawDeg = yawDeg;

  static const minZoom = 0.75;
  static const maxZoom = 4.0;

  /// Horizontal field of view at zoom 1.
  static const baseFovDeg = 90.0;

  /// Orientation restored by [reset].
  final double initialYawDeg;

  /// Centre of the view: yaw 0..360 (0 = image centre), pitch -90..90.
  double yawDeg;
  double pitchDeg;
  double zoom;

  double get fovH => baseFovDeg / zoom;

  double degPerPx(Size s) => s.width <= 0 ? 0 : fovH / s.width;

  double fovV(Size s) => s.width <= 0 ? fovH : fovH * s.height / s.width;

  /// Wraps an angle difference to -180 < d ≤ 180.
  static double wrapDelta(double d) {
    var r = d % 360;
    if (r > 180) r -= 360;
    if (r <= -180) r += 360;
    return r;
  }

  /// Keeps zoom and pitch inside the image (the window never shows more
  /// than 180° vertically or goes past the poles).
  void clamp(Size s) {
    var lo = minZoom;
    if (s.width > 0 && s.height > 0) {
      lo = math.max(lo, baseFovDeg * s.height / (s.width * 180));
    }
    zoom = zoom.clamp(lo, math.max(lo, maxZoom)).toDouble();
    yawDeg = normalizeYaw(yawDeg);
    final limit = math.max(0.0, 90 - fovV(s) / 2);
    pitchDeg = pitchDeg.clamp(-limit, limit).toDouble();
  }

  /// Drag: the image follows the finger. Wraps around horizontally.
  void panByPixels(Offset delta, Size s) {
    final k = degPerPx(s);
    yawDeg -= delta.dx * k;
    pitchDeg += delta.dy * k;
    clamp(s);
  }

  void zoomTo(double z, Size s) {
    zoom = z;
    clamp(s);
  }

  void zoomBy(double factor, Size s) => zoomTo(zoom * factor, s);

  /// Turns to face [yaw] (pitch and zoom unchanged).
  void lookAt(double yaw, Size s) {
    yawDeg = yaw;
    clamp(s);
  }

  /// Back to the initial orientation, level horizon, zoom 1.
  void reset(Size s) {
    yawDeg = initialYawDeg;
    pitchDeg = 0;
    zoom = 1;
    clamp(s);
  }

  /// Screen position of a direction (may lie outside the view).
  Offset screenOf(double yaw, double pitch, Size s) {
    final k = degPerPx(s);
    if (k == 0) return Offset.zero;
    return Offset(
      s.width / 2 + wrapDelta(yaw - yawDeg) / k,
      s.height / 2 - (pitch - pitchDeg) / k,
    );
  }

  /// Direction (yaw, pitch) shown at a screen position.
  (double, double) directionAt(Offset p, Size s) {
    final k = degPerPx(s);
    return (
      normalizeYaw(yawDeg + (p.dx - s.width / 2) * k),
      (pitchDeg - (p.dy - s.height / 2) * k).clamp(-90, 90).toDouble(),
    );
  }

  /// Whether a direction of half-width [marginDeg] is (partly) visible.
  bool isVisible(double yaw, double pitch, Size s, {double marginDeg = 0}) {
    final dx = wrapDelta(yaw - yawDeg).abs();
    final dy = (pitch - pitchDeg).abs();
    return dx <= fovH / 2 + marginDeg && dy <= fovV(s) / 2 + marginDeg;
  }

  /// Image x (pixels, unwrapped) for a yaw on an image [imageWidth] wide.
  static double imageX(double yaw, num imageWidth) =>
      (yaw + 180) / 360 * imageWidth;

  /// Image y (pixels) for a pitch on an image [imageHeight] tall.
  static double imageY(double pitch, num imageHeight) =>
      (90 - pitch) / 180 * imageHeight;
}

/// Compass direction presets relative to the panorama's north yaw.
enum PanoramaDirection { n, e, s, w }

extension PanoramaDirectionX on PanoramaDirection {
  String get label => switch (this) {
    PanoramaDirection.n => 'N',
    PanoramaDirection.e => 'E',
    PanoramaDirection.s => 'S',
    PanoramaDirection.w => 'W',
  };

  double get offsetDeg => index * 90.0;

  double yawFor(double northYawDeg) => normalizeYaw(northYawDeg + offsetDeg);
}
