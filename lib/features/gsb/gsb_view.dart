import 'dart:math' as math;

/// Which side of the proposed GSB a site photo looks at.
///
/// Scene convention (verified against `ViewProjector`): yaw 0 shows the
/// front; **+90° shows the board's right side, −90° its left side**, 180° the
/// back. A "Left View" photo therefore starts the board at −90°.
enum GsbPhotoView { front, left, right, back, custom }

extension GsbPhotoViewX on GsbPhotoView {
  String get label => switch (this) {
    GsbPhotoView.front => 'Front View',
    GsbPhotoView.left => 'Left View',
    GsbPhotoView.right => 'Right View',
    GsbPhotoView.back => 'Back View',
    GsbPhotoView.custom => 'Custom View',
  };

  /// Initial yaw (radians). Custom has no base: it keeps the current yaw.
  double get baseYaw => switch (this) {
    GsbPhotoView.front || GsbPhotoView.custom => 0,
    GsbPhotoView.left => -math.pi / 2,
    GsbPhotoView.right => math.pi / 2,
    GsbPhotoView.back => math.pi,
  };

  static GsbPhotoView? fromKey(String? key) {
    for (final v in GsbPhotoView.values) {
      if (v.name == key) return v;
    }
    return null;
  }
}

/// Starting orientation implied by a photo angle label (any media type):
/// Front 0°, Left −90°, Right +90°, Back 180°. Other categories (close-up,
/// long shot, surroundings, historical labels) keep the neutral default.
GsbPhotoView? viewForAngleLabel(String label) => switch (label.trim().toLowerCase()) {
  'front view' => GsbPhotoView.front,
  'left angle' => GsbPhotoView.left,
  'right angle' => GsbPhotoView.right,
  'back view' => GsbPhotoView.back,
  _ => null,
};

/// Normalises an angle to (−π, π]. Non-finite input → 0.
double wrapYaw(double a) {
  if (!a.isFinite) return 0;
  var r = a % (2 * math.pi);
  if (r > math.pi) r -= 2 * math.pi;
  if (r <= -math.pi) r += 2 * math.pi;
  return r;
}

/// Effective yaw = view base + vendor adjustment, normalised.
double effectiveYaw(GsbPhotoView view, double offset) =>
    wrapYaw(view.baseYaw + offset);

String yawDegreesLabel(double yaw) {
  final d = (wrapYaw(yaw) * 180 / math.pi);
  final n = d < 0 ? d + 360 : d; // 0…360
  return '${n.round() % 360}°';
}
