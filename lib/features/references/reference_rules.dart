import '../../data/models/models.dart';
import '../model3d/signage_spec.dart';

/// 3D model status of a media type from its reference library:
///
/// * no reference at all → [ModelStatus.illustrative];
/// * references exist but none is an approved, current (not superseded)
///   reference → [ModelStatus.referencePending];
/// * an approved, non-superseded reference exists →
///   [ModelStatus.technicallyReviewed].
ModelStatus modelStatusFor(List<MediaReference> refs, String mediaCode) {
  final mine = refs.where((r) => r.mediaCode == mediaCode).toList();
  if (mine.isEmpty) return ModelStatus.illustrative;
  if (mine.any((r) => r.isActiveApproval)) {
    return ModelStatus.technicallyReviewed;
  }
  return ModelStatus.referencePending;
}
