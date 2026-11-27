import 'evidence_policy.dart';
import 'models.dart';

/// Site Photos & Annotation completion of ONE MEDIA GROUP.
///
/// Supersedes the old "two photos per physical board" rule:
///   * at least [minPhotos] distinct valid original site photos for the group;
///   * at least one valid saved signage marking for EACH active physical
///     board of that group.
///
/// The two photos are SHARED by the whole group. Markings stay per board.
/// Photo associations (`unitIds`) are not required for the shared photos;
/// a valid linked signage annotation is what covers a physical board.
class PhotoRequirement {
  const PhotoRequirement({
    required this.photoCount,
    required this.markedCount,
    required this.totalUnits,
    required this.missingUnitIds,
  });

  static const minPhotos = 2;

  final int photoCount;
  final int markedCount;
  final int totalUnits;
  final List<String> missingUnitIds;

  bool get needsPhotos => photoCount < minPhotos;
  bool get needsMarkings => missingUnitIds.isNotEmpty;

  /// Backward-compatible aliases used by existing evidence tests/callers.
  bool get needsMarking => needsMarkings;
  int get markingCount => markedCount;
  bool get isComplete => totalUnits > 0 && !needsPhotos && !needsMarkings;

  /// Canonical (English) messages. UI-localize fixed wording with context.ui.
  List<String> get messages => [
    if (needsPhotos)
      (photoCount == 0
          ? 'Capture at least two site photos'
          : '1 more valid site photo required'),
    if (needsMarkings) 'Signage marking is missing',
  ];

  String get photoMessage => photoCount == 0
      ? 'Capture at least two site photos'
      : '1 more valid site photo required';
}

extension BoardPhotoRequirement on Board {
  /// True for a SIGNAGE placement of [u] on [p]: a Signage rectangle linked
  /// to that board or an advanced perspective placement. Arrows, text,
  /// freehand, markers and unlinked shapes never count.
  static bool hasSignageMarking(
    SitePhoto p,
    SignageUnit u, {
    bool sole = false,
  }) =>
      p.annotations.any(
        (a) =>
            a.type == AnnotationType.rectangle &&
            (a.itemId == u.id || (sole && a.itemId == null)) &&
            a.w.isFinite &&
            a.h.isFinite &&
            a.w > 0 &&
            a.h > 0,
      ) ||
      p.markup.perspectives.any(
        (e) => e.unitId == u.id && e.photoId == p.id && _validQuad(e.corners),
      );

  /// Four finite corners with a real (non-degenerate) area.
  static bool _validQuad(List<SurveyPoint> c) {
    if (c.length != 4) return false;
    for (final p in c) {
      if (!p.x.isFinite || !p.y.isFinite) return false;
      if (p.x < -0.01 || p.x > 1.01 || p.y < -0.01 || p.y > 1.01) return false;
    }
    var a = 0.0;
    for (var i = 0; i < 4; i++) {
      final p = c[i], q = c[(i + 1) % 4];
      a += p.x * q.y - q.x * p.y;
    }
    return (a / 2).abs() > 1e-4;
  }

  /// All ORIGINAL, usable photos of this media group, deduplicated by
  /// content fingerprint. Group photos are shared by every physical board;
  /// per-photo `unitIds` only describe which boards the photo shows.
  List<SitePhoto> get groupPhotos {
    final byContent = <String, SitePhoto>{};
    final ids = activeUnits.map((u) => u.id).toSet();
    for (final p in photos) {
      if (!EvidencePolicy.isUsable(p.path)) continue;
      final key = EvidencePolicy.fingerprintOf(p.path);
      final kept = byContent[key];
      if (kept == null || (_hasMarking(p, ids) && !_hasMarking(kept, ids))) {
        byContent[key] = p; // keep the copy that carries a real marking
      }
    }
    return byContent.values.toList();
  }

  static bool _hasMarking(SitePhoto p, Set<String> ids) => p.annotations.any(
    (a) =>
        a.type == AnnotationType.rectangle &&
        (a.itemId == null || ids.contains(a.itemId)) &&
        a.w.isFinite &&
        a.h.isFinite &&
        a.w > 0 &&
        a.h > 0,
  );

  /// Kept for tour/legacy consumers: group photos (not unit-specific).
  List<SitePhoto> requirementPhotosOf(SignageUnit u) => groupPhotos;

  /// Group-level evidence result.
  PhotoRequirement get photoRequirement {
    final ps = groupPhotos;
    final units = activeUnits;
    final marked = <String>{};
    for (final u in units) {
      final covered = ps.any(
        (p) => hasSignageMarking(p, u, sole: units.length <= 1),
      );
      if (covered) marked.add(u.id);
    }
    final missing = <String>[
      for (final u in units)
        if (!marked.contains(u.id)) u.id,
    ];
    return PhotoRequirement(
      photoCount: ps.length,
      markedCount: marked.length,
      totalUnits: units.length,
      missingUnitIds: missing,
    );
  }

  /// Legacy per-unit accessor. Photo count is the shared group count; the
  /// marking flag reflects THIS board only.
  PhotoRequirement photoRequirementOf(SignageUnit u) {
    final r = photoRequirement;
    return PhotoRequirement(
      photoCount: r.photoCount,
      markedCount: r.missingUnitIds.contains(u.id) ? 0 : 1,
      totalUnits: 1,
      missingUnitIds: r.missingUnitIds.contains(u.id) ? [u.id] : const [],
    );
  }

  /// True when the group has enough distinct photos and every active board
  /// has its own valid saved marking.
  bool get photosRequirementComplete => photoRequirement.isComplete;
}
