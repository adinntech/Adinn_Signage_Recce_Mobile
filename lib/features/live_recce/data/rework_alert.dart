import 'recce_models.dart';

/// What the reviewers flagged on one shop, for the retake alert (the banner on the shop screen and the sheet that opens once per
/// rework request). Pure data: it is worked out from the shop detail the server sent, nothing is invented on the phone.
///
/// Four kinds of things can be flagged:
///  - a photo (rejected, or rework required): it needs a NEW picture ([FlaggedPhoto]),
///  - a detail of a board (size, quantity or media type): the person corrects it or confirms it is right ([FlaggedBoardFix]),
///  - a photo that was asked for and does not exist yet ([FlaggedRequest]),
///  - a CHECKLIST item of the reviewer that is not a photo or a board detail ("Shop front visible", "Correct shop"), each with its own
///    remark, belonging to a section of the app: SHOP | PHOTOS | BOARDS | INSTALLATION ([FlaggedSection]).

/// A photo the reviewer rejected or sent back. [answered] = a new picture for it already exists (stored draft or still uploading).
class FlaggedPhoto {
  const FlaggedPhoto({required this.photo, required this.angle, required this.board, this.note, this.answered = false});

  final ShopPhoto photo;

  /// The angle the photo shows ("Front View", "Left Side View" ...).
  final String angle;

  /// The board number ("GSB-01"); empty when the photo belongs to no board.
  final String board;
  final ReworkNote? note;
  final bool answered;

  bool get rejected => photo.isRejected || (note?.rejected ?? false);
  String get reason => note?.reason ?? '';
}

/// A request to check / correct one detail of a board.
class FlaggedBoardFix {
  const FlaggedBoardFix({required this.type, required this.mediaKey, required this.board, required this.note});

  /// FIX_MEASUREMENT (size) | FIX_QUANTITY | FIX_MEDIA_TYPE.
  final String type;
  final String mediaKey;

  /// The board number ("GSB-01"), or "A board" when the request named none.
  final String board;
  final ReworkNote note;

  bool get rejected => note.rejected;

  /// "Correct the size" - or, for a checklist item, its label ("Measurements available").
  String get title => boardFixTitleFor(type, rejected: rejected, label: note.label);
}

/// A checklist item the reviewer sent back (Rework or Rejected) with its own remark: it shows in its [section] of the shop screen.
class FlaggedSection {
  const FlaggedSection({required this.label, required this.section, required this.note});

  /// The checklist label ("Shop front visible"); never empty.
  final String label;

  /// SHOP | PHOTOS | BOARDS | INSTALLATION.
  final String section;
  final ReworkNote note;

  bool get rejected => note.rejected;

  /// The reviewer's remark for this item.
  String get remark => note.reason;

  /// The open, unresolved checklist items of one section ([section] null = every section), in the order the reviewers sent them.
  static List<FlaggedSection> of(ShopDetail d, {String? section}) => [
        for (final r in d.reworks.where((r) => r.isOpen))
          for (final i in r.items.where((i) => i.isSectionNote && !i.resolved && (section == null || i.sectionKey == section)))
            FlaggedSection(label: i.label.isNotEmpty ? i.label : 'Reviewer check', section: i.sectionKey, note: r.noteFor(i)),
      ];
}

/// A photo the reviewer asked for (an extra angle). [answered] = a new photo of that category already exists.
class FlaggedRequest {
  const FlaggedRequest({required this.label, required this.board, required this.note, this.answered = false});

  final String label;
  final String board;
  final ReworkNote note;
  final bool answered;
}

class ReworkAlert {
  const ReworkAlert({this.requestKey = '', this.photos = const [], this.boardFixes = const [], this.requested = const [], this.sections = const []});

  /// The open rework requests (their ids): the sheet is shown once per key, never again for the same request.
  final String requestKey;
  final List<FlaggedPhoto> photos;
  final List<FlaggedBoardFix> boardFixes;
  final List<FlaggedRequest> requested;

  /// Checklist items the reviewer sent back (each with its own remark), for every section.
  final List<FlaggedSection> sections;

  bool get isEmpty => photos.isEmpty && boardFixes.isEmpty && requested.isEmpty && sections.isEmpty;

  /// Photos still waiting for a new picture, split by the reviewer's word.
  int get rejectedPhotos => photos.where((p) => p.rejected && !p.answered).length;
  int get reworkPhotos => photos.where((p) => !p.rejected && !p.answered).length;
  int get boardDetails => boardFixes.length;
  int get extraPhotos => requested.where((r) => !r.answered).length;
  int get checks => sections.length;

  /// Everything the person still has to do (photos without a new picture, board details, extra photos, checklist items).
  int get open => rejectedPhotos + reworkPhotos + boardDetails + extraPhotos + checks;

  /// Every flagged photo has a new picture (and every extra photo asked for exists). Board details may still be open.
  bool get photosAnswered => photos.isNotEmpty && rejectedPhotos + reworkPhotos + extraPhotos == 0;

  /// Nothing is left to do: all new pictures are there and no board detail is flagged. The person only has to resubmit.
  bool get allAnswered => !isEmpty && open == 0;

  /// The first flagged photo that still needs a new picture, or the first flagged photo.
  FlaggedPhoto? get firstPhoto => photos.where((p) => !p.answered).firstOrNull ?? photos.firstOrNull;

  static String _n(int n, String one, String many) => '$n ${n == 1 ? one : many}';

  /// "2 photos rejected, 1 photo to redo, 1 board detail to correct, 1 extra photo asked, 2 checks to fix".
  String get summary {
    final parts = [
      if (rejectedPhotos > 0) '${_n(rejectedPhotos, 'photo', 'photos')} rejected',
      if (reworkPhotos > 0) '${_n(reworkPhotos, 'photo', 'photos')} to redo',
      if (boardDetails > 0) '${_n(boardDetails, 'board detail', 'board details')} to correct',
      if (extraPhotos > 0) '${_n(extraPhotos, 'extra photo', 'extra photos')} asked',
      if (checks > 0) '${_n(checks, 'check', 'checks')} to fix',
    ];
    return parts.join(', ');
  }

  /// Reads the flagged things from the shop detail. [answeredPhoto] says whether a new picture exists for a flagged photo (the
  /// controller knows the draft replacement and the upload still running); [answeredRequest] the same for an extra photo asked.
  static ReworkAlert of(ShopDetail d, {bool Function(ShopPhoto old)? answeredPhoto, bool Function(RequestedPhoto req)? answeredRequest}) {
    final open = d.reworks.where((r) => r.isOpen).toList();
    if (open.isEmpty && !d.photos.any((p) => p.needsRework)) return const ReworkAlert();
    final labels = d.boardLabels;
    return ReworkAlert(
      requestKey: ([for (final r in open) r.id]..sort()).join('|'),
      photos: [
        for (final p in d.photos.where((p) => p.needsRework && !p.isDraft))
          FlaggedPhoto(
            photo: p,
            angle: d.categoryLabel(p.category),
            board: labels[p.mediaKey] ?? '',
            note: d.reworkNoteFor(p),
            answered: answeredPhoto?.call(p) ?? false,
          ),
      ],
      boardFixes: [
        for (final r in open)
          for (final i in r.items.where((i) => i.isBoardFix && !i.resolved))
            FlaggedBoardFix(type: i.type, mediaKey: i.mediaKey, board: i.mediaKey.isEmpty ? 'A board' : (labels[i.mediaKey] ?? i.mediaKey), note: r.noteFor(i)),
      ],
      requested: [
        for (final q in d.requestedPhotos)
          FlaggedRequest(label: q.label, board: labels[q.item.mediaKey] ?? '', note: q.note, answered: answeredRequest?.call(q) ?? false),
      ],
      sections: FlaggedSection.of(d),
    );
  }
}
