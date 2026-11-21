import 'recce_models.dart';

/// Local check before "Submit Version N". The server validates again and its error text is shown if it disagrees.
/// Returns human-readable problems; an empty list means the shop can be submitted.
///
/// Photos: the six live-flow categories are always required (the product owner's checklist). On top of them, whatever the SERVER
/// reports as still missing ([serverMissing] = `detail.progress.missing`, e.g. a NAME_BOARD the office requires) is required too.
/// Nothing else is: the phone never blocks on a photo the server does not need.
///
/// During rework (V2, V3...) the photos already stored with the earlier version, approved or not, count as present, so nothing
/// that is unrelated to the reviewer's request has to be taken again. The only extra rule is the server's own: every photo the
/// reviewer marked for replacement needs its replacement, and every extra photo asked for needs a new photo.
List<String> validateForSubmit({
  required List<ShopPhoto> photos,
  required List<BoardItem> boards,
  required Installation installation,
  int pendingUploads = 0,
  List<ReworkEntry> reworks = const [],
  Set<String> pendingReplaces = const {},
  Set<String> pendingCategories = const {},
  List<MissingEvidence> serverMissing = const [],
}) {
  final problems = <String>[];

  for (final c in requiredPhotoCategories) {
    final inCategory = photos.where((p) => p.category == c.key).toList();
    if (inCategory.isEmpty) {
      problems.add('${c.label} photo is missing');
    } else if (!inCategory.any((p) => p.hasGps)) {
      problems.add('${c.label} photo has no GPS location. Retake it with location on');
    }
  }
  problems.addAll(missingExtraPhotos(serverMissing, photos));

  if (boards.isEmpty) problems.add('Add at least one board');
  for (final b in boards) {
    final who = '${b.name.trim().isEmpty ? 'Board' : b.name.trim()} (${b.key})';
    if (b.name.trim().isEmpty) problems.add('Board ${b.key}: choose the type');
    if (b.quantity < 1) problems.add('$who: quantity must be at least 1');
    if ((b.width ?? 0) <= 0) problems.add('$who: enter the width');
    if ((b.height ?? 0) <= 0) problems.add('$who: enter the height');
  }

  final open = installation.unanswered;
  if (open.isNotEmpty) problems.add('Installation not answered: ${open.join(', ')}');
  final height = installation.heightProblem;
  if (height != null) problems.add(height);

  problems.addAll(unansweredRework(reworks, photos, pendingReplaces: pendingReplaces, pendingCategories: pendingCategories));

  if (pendingUploads > 0) {
    problems.add('$pendingUploads photo${pendingUploads == 1 ? ' is' : 's are'} still uploading');
  }
  return problems;
}

/// The photos the server reports as missing that are NOT one of the six (those have their own lines), one line per category,
/// unless a live photo of that category already exists. `DIMENSIONS` is not a photo and is checked with the boards.
List<String> missingExtraPhotos(List<MissingEvidence> serverMissing, List<ShopPhoto> photos) {
  final out = <String>[];
  final seen = <String>{};
  for (final m in serverMissing) {
    if (!m.isPhoto || isLiveFlowCategory(m.category) || m.satisfiedBy(photos) || !seen.add(m.category)) continue;
    out.add('${m.label.isEmpty ? photoCategoryLabel(m.category) : m.label} photo is missing');
  }
  return out;
}

/// What the open rework request still waits for. A replacement that is still uploading is not repeated here (the
/// "still uploading" line covers it). FIX_MEASUREMENT items need nothing: the server does not require an answer for them.
///
/// A request for a NEW photo (an ADDITIONAL_PHOTO item, or a REPLACE_PHOTO that names a category but no photo) is answered by a
/// new draft photo of that category (of that board when the item names one), or by one still uploading.
List<String> unansweredRework(
  List<ReworkEntry> reworks,
  List<ShopPhoto> photos, {
  Set<String> pendingReplaces = const {},
  Set<String> pendingCategories = const {},
}) {
  final out = <String>[];
  final drafts = photos.where((p) => p.isDraft).toList();
  for (final r in reworks.where((r) => r.isOpen)) {
    for (final i in r.items.where((i) => !i.resolved)) {
      if (i.type == 'REPLACE_PHOTO' && i.photo != null) {
        final answered = drafts.any((d) => d.replaces == i.photo) || pendingReplaces.contains(i.photo);
        if (!answered) out.add('Replace the ${i.categoryLabel ?? 'photo'} the reviewer marked');
      } else if (i.asksForNewPhoto) {
        final answered = i.answeredBy(drafts) || pendingCategories.contains(i.category);
        if (!answered) out.add('Add the ${i.categoryLabel ?? photoCategoryLabel(i.category!)} photo the reviewer asked for');
      }
    }
  }
  return out;
}
