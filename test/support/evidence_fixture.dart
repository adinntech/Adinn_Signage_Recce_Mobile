import 'package:signage_recce/data/models/models.dart';
import 'package:signage_recce/state/app_controller.dart';

/// Qualifying site evidence for EVERY active physical board of [b]: two
/// distinct original photos (different files) linked to all boards, and a
/// genuine Signage rectangle on the first photo for each board.
List<SitePhoto> validEvidence(Board b, {String tag = 'ev'}) {
  final ids = [for (final u in b.activeUnits) u.id];
  return [
    SitePhoto(
      id: '${tag}_1_${b.id}',
      path: 'demo://1',
      label: 'Front view',
      capturedAt: DateTime(2026, 11, 24),
      width: 100,
      height: 80,
      unitIds: ids,
      annotations: [
        for (final id in ids)
          Annotation(
            id: '${tag}_m_${b.id}_$id',
            type: AnnotationType.rectangle,
            itemId: id,
            x: 50,
            y: 40,
            w: 40,
            h: 20,
          ),
      ],
    ),
    SitePhoto(
      id: '${tag}_2_${b.id}',
      path: 'demo://2',
      label: 'Left angle',
      capturedAt: DateTime(2026, 11, 24),
      width: 100,
      height: 80,
      unitIds: ids,
    ),
  ];
}

/// Extends the EXISTING photos of [b] so every active board (for example a
/// board added later with increaseQuantity) is linked to the first two
/// photos and has its own signage marking on the first one. Requires two
/// distinct photos to exist already.
void ensureEvidenceForAllUnits(Board b) {
  assert(b.photos.length >= 2, 'needs two distinct photos');
  for (final u in b.activeUnits) {
    for (final p in b.photos.take(2)) {
      if (!p.unitIds.contains(u.id)) {
        p.unitIds = [...p.unitIds, u.id];
      }
    }
    final first = b.photos.first;
    if (!first.annotations.any((a) => a.itemId == u.id)) {
      first.annotations.add(
        Annotation(
          id: 'ens_${u.id}',
          type: AnnotationType.rectangle,
          itemId: u.id,
          x: 50,
          y: 40,
          w: 40,
          h: 20,
        ),
      );
    }
  }
}

/// Adds [validEvidence] through the controller.
void addValidEvidence(AppController c, String shopId, Board b) {
  for (final p in validEvidence(b)) {
    c.addPhoto(shopId, b.id, p);
  }
}
