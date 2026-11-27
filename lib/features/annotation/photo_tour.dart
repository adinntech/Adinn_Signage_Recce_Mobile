import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../data/models/photo_requirement.dart';
import '../../l10n/l10n.dart';

/// Guided "mark the signage board" tour shown after every new camera photo.
///
/// Skip eligibility comes from the SAVED evidence of the physical board
/// (never from a "tour was seen" flag):
///   * first photo of the board            -> Skip allowed;
///   * later photo, a valid marking exists -> Skip allowed;
///   * later photo, no valid marking yet   -> not skippable (the tour ends
///     only when a real marking has been saved or the vendor leaves the
///     screen with Back; completion is never faked).
class PhotoTour extends ChangeNotifier {
  PhotoTour({required this.canSkip});

  /// Decides the skip rule for a freshly captured [photo] of [unit].
  factory PhotoTour.forNewPhoto(
    Board board,
    SignageUnit unit,
    SitePhoto photo,
  ) {
    final counted = board.groupPhotos;
    final already = counted.any((p) => p.id == photo.id);
    final sequence = counted.length + (already ? 0 : 1);
    // Skip is allowed on the first group photo, and later as soon as EVERY
    // active board of this media group has a valid saved marking. A board may
    // be marked on any photo; it need not be marked on the current one.
    final allMarked = board.photoRequirement.missingUnitIds.isEmpty;
    return PhotoTour(canSkip: sequence <= 1 || allMarked);
  }

  final bool canSkip;
  final signageKey = GlobalKey(debugLabel: 'tour_signage');
  final canvasKey = GlobalKey(debugLabel: 'tour_canvas');
  final saveKey = GlobalKey(debugLabel: 'tour_save');

  /// 0 open photo editor, 1 Signage tool, 2 mark the canvas, 3 Save.
  int _step = 0;
  bool _finished = false;

  int get step => _step;
  bool get active => !_finished;

  void advanceTo(int s) {
    if (_finished || s <= _step) return;
    _step = s;
    notifyListeners();
  }

  /// Ends the tour (skipped, or a valid marking was saved).
  void finish() {
    if (_finished) return;
    _finished = true;
    notifyListeners();
  }

  /// Vendor pressed Skip. Ignored when skipping is not allowed.
  bool skip() {
    if (!canSkip) return false;
    finish();
    return true;
  }
}

/// Dims the screen slightly, highlights only the current target and shows a
/// compact instruction card. Taps pass through the dim layer, so the tool,
/// canvas and Save button stay fully usable.
class PhotoTourOverlay extends StatelessWidget {
  const PhotoTourOverlay({super.key, required this.tour});

  final PhotoTour tour;

  GlobalKey? get _target => switch (tour.step) {
    1 => tour.signageKey,
    2 => tour.canvasKey,
    3 => tour.saveKey,
    _ => tour.canvasKey,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tour,
      builder: (context, _) {
        if (!tour.active) return const SizedBox.shrink();
        final t = context.t;
        final text = switch (tour.step) {
          0 => t.tourOpenPhoto,
          1 => t.tourSignageTool,
          2 => t.tourMarkArea,
          _ => t.tourSave,
        };
        final box = _target?.currentContext?.findRenderObject() as RenderBox?;
        final overlayBox = context.findRenderObject() as RenderBox?;
        Rect? hole;
        if (box != null && box.attached && overlayBox != null) {
          final topLeft = overlayBox.globalToLocal(
            box.localToGlobal(Offset.zero),
          );
          hole = (topLeft & box.size).inflate(4);
        }
        return Stack(
          key: const Key('photo_tour'),
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _DimPainter(hole)),
              ),
            ),
            // The card never covers its own target: Save lives at the top,
            // the Signage tool at the bottom, so step 3 shows it low and the
            // others show it high.
            Positioned(
              left: 12,
              right: 12,
              top: tour.step == 3 ? null : 8,
              bottom: tour.step == 3 ? 150 : null,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.touch_app_outlined,
                        color: AdinnColors.red,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          text,
                          key: const Key('tour_text'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      if (tour.step == 0)
                        TextButton(
                          key: const Key('tour_next'),
                          onPressed: () => tour.advanceTo(1),
                          child: Text(t.next),
                        ),
                      if (tour.canSkip)
                        TextButton(
                          key: const Key('tour_skip'),
                          onPressed: tour.skip,
                          child: Text(t.skip),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (!tour.canSkip && tour.step > 0)
              Positioned(
                left: 12,
                right: 12,
                top: 70,
                child: IgnorePointer(
                  child: Text(
                    t.tourMarkRequired,
                    key: const Key('tour_required'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      shadows: [Shadow(blurRadius: 4)],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Step 0: dims the screen and highlights the NEWLY CAPTURED photo tile.
/// Taps pass through the dim layer, so the tile itself opens the editor;
/// "Open" does the same, "Skip" only exists when the saved-evidence rule
/// allows it.
class TileTourOverlay extends StatelessWidget {
  const TileTourOverlay({
    super.key,
    required this.tour,
    required this.target,
    required this.onOpen,
    required this.onSkip,
  });

  final PhotoTour tour;
  final GlobalKey target;
  final VoidCallback onOpen;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final box = target.currentContext?.findRenderObject() as RenderBox?;
    final me = context.findRenderObject() as RenderBox?;
    Rect? hole;
    if (box != null && box.attached && me != null) {
      hole = (me.globalToLocal(box.localToGlobal(Offset.zero)) & box.size)
          .inflate(4);
    }
    return Stack(
      key: const Key('photo_tour_tile'),
      children: [
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _DimPainter(hole))),
        ),
        // Everything except the highlighted tile (and the AppBar, so Back
        // keeps working) absorbs taps: nothing unrelated can be used to
        // bypass the required marking.
        if (hole != null && me != null) ...[
          for (final r in _blockers(
            me.size,
            hole,
            MediaQuery.paddingOf(context).top + kToolbarHeight,
          ))
            Positioned.fromRect(
              rect: r,
              child: const AbsorbPointer(child: SizedBox.expand()),
            ),
        ],
        Positioned(
          left: 12,
          right: 12,
          bottom: 24,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  const Icon(Icons.touch_app_outlined, color: AdinnColors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t.tourOpenPhoto,
                      key: const Key('tour_text'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('tour_open'),
                    onPressed: onOpen,
                    child: Text(t.tourOpen),
                  ),
                  if (tour.canSkip)
                    TextButton(
                      key: const Key('tour_skip'),
                      onPressed: onSkip,
                      child: Text(t.skip),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The four regions around [hole] below [top] (the AppBar stays usable).
List<Rect> _blockers(Size size, Rect hole, double top) => [
  Rect.fromLTRB(0, top, size.width, hole.top.clamp(top, size.height)),
  Rect.fromLTRB(
    0,
    hole.bottom.clamp(top, size.height),
    size.width,
    size.height,
  ),
  Rect.fromLTRB(
    0,
    hole.top.clamp(top, size.height),
    hole.left.clamp(0, size.width),
    hole.bottom.clamp(top, size.height),
  ),
  Rect.fromLTRB(
    hole.right.clamp(0, size.width),
    hole.top.clamp(top, size.height),
    size.width,
    hole.bottom.clamp(top, size.height),
  ),
];

class _DimPainter extends CustomPainter {
  _DimPainter(this.hole);

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      dim.addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(10)));
      dim.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(dim, Paint()..color = const Color(0x55000000));
    if (hole != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole!, const Radius.circular(10)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = AdinnColors.red,
      );
    }
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole;
}
