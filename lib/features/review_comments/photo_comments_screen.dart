import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../annotation/annotation_painter.dart';
import '../photos/site_photo_view.dart';
import 'comment_widgets.dart';

/// Reviewer comments pinned on one site photo. Reviewers add numbered
/// markers at an exact spot; recce staff respond / mark them addressed.
/// Comments are stored separately and never change staff annotations.
class PhotoCommentsScreen extends StatefulWidget {
  const PhotoCommentsScreen({
    super.key,
    required this.shopId,
    required this.boardId,
    required this.photoId,
    this.snapshot,
  });

  final String shopId;
  final String boardId;
  final String photoId;

  /// Submitted snapshot being reviewed (fallback source of the photo).
  final Shop? snapshot;

  @override
  State<PhotoCommentsScreen> createState() => _PhotoCommentsScreenState();
}

class _NewComment {
  const _NewComment(this.type, this.text, this.unitId, this.rejects);

  final ReviewCommentType type;
  final String text;
  final String? unitId;
  final bool rejects;
}

class _PhotoCommentsScreenState extends State<PhotoCommentsScreen> {
  final _tc = TransformationController();
  bool _placing = false;
  String? _highlight;

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onZoom);
  }

  @override
  void dispose() {
    _tc.removeListener(_onZoom);
    _tc.dispose();
    super.dispose();
  }

  void _onZoom() {
    if (mounted) setState(() {});
  }

  Future<void> _add(
    AppController c,
    Shop shop,
    ResolvedPhoto rp,
    SurveyPoint at,
  ) async {
    setState(() => _placing = false);
    final units = rp.board.activeUnits;
    final linked = rp.photo.unitIds.where(
      (id) => rp.board.unitById(id) != null,
    );
    final result = await showModalBottomSheet<_NewComment>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewCommentSheet(
        board: rp.board,
        units: units,
        initialUnitId: units.length == 1
            ? units.first.id
            : (linked.length == 1 ? linked.first : null),
      ),
    );
    if (result == null || !mounted) return;
    try {
      final cm = c.addReviewComment(
        shop.id,
        groupId: rp.board.id,
        photoId: rp.photo.id,
        unitId: result.unitId,
        type: result.type,
        text: result.text,
        position: at,
        rejectsEvidence: result.rejects,
      );
      setState(() => _highlight = cm.id);
      showSnack(context, 'Comment ${cm.markerLabel} added');
    } on StateError catch (e) {
      showSnack(context, e.message, error: true);
    }
  }

  void _compareVersions(Shop shop, ResolvedPhoto rp, int oldVersion) {
    final old = snapshotPhoto(shop, oldVersion, rp.photo.id);
    if (old == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('v$oldVersion evidence vs current')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Submitted in v$oldVersion',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              AnnotatedPhotoView(old, key: const Key('rc_old_photo')),
              const SizedBox(height: 16),
              Text(
                rp.fromVersion == null
                    ? 'Current (corrected) photo'
                    : 'Photo from v${rp.fromVersion} submission',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              AnnotatedPhotoView(rp.photo, key: const Key('rc_new_photo')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(widget.shopId);
    final rp = shop == null
        ? null
        : resolveCommentPhoto(
            shop,
            widget.boardId,
            widget.photoId,
            snapshot: widget.snapshot,
          );
    if (shop == null || rp == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review comments')),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'Photo not found',
        ),
      );
    }
    final comments = c.reviewComments(shop.id, photoId: rp.photo.id)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final canComment = c.canComment(shop);
    final olderVersions =
        comments
            .map((e) => e.version)
            .where(
              (v) =>
                  v < shop.currentVersion &&
                  snapshotPhoto(shop, v, rp.photo.id) != null,
            )
            .toSet()
            .toList()
          ..sort();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Review comments',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              '${rp.board.name} • ${rp.photo.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AdinnColors.muted),
            ),
          ],
        ),
        actions: [
          if (olderVersions.isNotEmpty)
            IconButton(
              key: const Key('rc_compare_versions'),
              tooltip: 'Compare with v${olderVersions.first} evidence',
              icon: const Icon(Icons.compare),
              onPressed: () => _compareVersions(shop, rp, olderVersions.first),
            ),
        ],
      ),
      bottomNavigationBar: canComment
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton.icon(
                  key: const Key('rc_add'),
                  onPressed: () => setState(() => _placing = !_placing),
                  icon: Icon(_placing ? Icons.close : Icons.add_comment),
                  label: Text(_placing ? 'Cancel' : 'Add Review Comment'),
                ),
              ),
            )
          : null,
      body: Column(
        children: [
          if (rp.fromVersion != null)
            Container(
              key: const Key('rc_snapshot_banner'),
              width: double.infinity,
              color: AdinnColors.info.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(8),
              child: Text(
                'Photo from v${rp.fromVersion} submission (no longer in the '
                'current recce)',
                style: const TextStyle(fontSize: 12.5, color: AdinnColors.info),
              ),
            ),
          if (_placing)
            Container(
              key: const Key('rc_place_hint'),
              width: double.infinity,
              color: AdinnColors.redLight,
              padding: const EdgeInsets.all(8),
              child: const Text(
                'Tap the photo exactly where the comment applies.',
                style: TextStyle(fontSize: 12.5, color: AdinnColors.redDark),
              ),
            ),
          Expanded(flex: 3, child: _viewer(c, shop, rp, comments)),
          Expanded(
            flex: 2,
            child: comments.isEmpty
                ? const EmptyState(
                    icon: Icons.mode_comment_outlined,
                    title: 'No review comments on this photo',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    children: [
                      for (final cm in comments)
                        Card(
                          child: ListTile(
                            key: Key('rc_item_${cm.id}'),
                            leading: CommentMarkerDot(comment: cm, size: 32),
                            title: Text(
                              cm.type.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              '${cm.text}\nRaised in v${cm.version} • '
                              '${commentItemLabel(rp.board, cm.unitId)}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: true,
                            trailing: CommentStatusChip(cm.status),
                            onTap: () {
                              setState(() => _highlight = cm.id);
                              showCommentDetails(
                                context,
                                shopId: shop.id,
                                commentId: cm.id,
                              );
                            },
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _viewer(
    AppController c,
    Shop shop,
    ResolvedPhoto rp,
    List<PhotoReviewComment> comments,
  ) {
    final photo = rp.photo;
    return Container(
      color: const Color(0xFF202124),
      child: LayoutBuilder(
        builder: (context, box) {
          final fitted = applyBoxFit(
            BoxFit.contain,
            Size(photo.aspectRatio, 1),
            Size(
              math.max(box.maxWidth - 16, 1),
              math.max(box.maxHeight - 16, 1),
            ),
          ).destination;
          final zoom = _tc.value.getMaxScaleOnAxis();
          const r = 15.0;
          return InteractiveViewer(
            transformationController: _tc,
            maxScale: 6,
            child: Center(
              child: SizedBox(
                key: const Key('rc_photo'),
                width: fitted.width,
                height: fitted.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(child: SitePhotoImage(photo)),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: AnnotationPainter(
                          annotations: photo.annotations,
                          imageSize: Size(
                            photo.width.toDouble(),
                            photo.height.toDouble(),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        key: const Key('rc_canvas'),
                        behavior: HitTestBehavior.opaque,
                        onTapUp: _placing
                            ? (d) => _add(
                                c,
                                shop,
                                rp,
                                SurveyPoint(
                                  d.localPosition.dx / fitted.width,
                                  d.localPosition.dy / fitted.height,
                                ).clamped(),
                              )
                            : null,
                      ),
                    ),
                    for (final cm in comments)
                      Positioned(
                        left: cm.position.x * fitted.width - r,
                        top: cm.position.y * fitted.height - r,
                        width: r * 2,
                        height: r * 2,
                        child: Transform.scale(
                          scale: 1 / math.max(zoom, 1),
                          child: CommentMarkerDot(
                            key: Key('rc_marker_${cm.id}'),
                            comment: cm,
                            size: r * 2,
                            highlighted: cm.id == _highlight,
                            onTap: () {
                              setState(() => _highlight = cm.id);
                              showCommentDetails(
                                context,
                                shopId: shop.id,
                                commentId: cm.id,
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NewCommentSheet extends StatefulWidget {
  const _NewCommentSheet({
    required this.board,
    required this.units,
    this.initialUnitId,
  });

  final Board board;
  final List<SignageUnit> units;
  final String? initialUnitId;

  @override
  State<_NewCommentSheet> createState() => _NewCommentSheetState();
}

class _NewCommentSheetState extends State<_NewCommentSheet> {
  final _text = TextEditingController();
  ReviewCommentType _type = ReviewCommentType.general;
  late String? _unitId = widget.initialUnitId;
  bool _rejects = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add review comment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ReviewCommentType>(
              key: const Key('rc_type'),
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Comment type'),
              items: [
                for (final t in ReviewCommentType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              key: const Key('rc_unit'),
              initialValue: _unitId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Signage item'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Whole photo / media group'),
                ),
                for (final u in widget.units)
                  DropdownMenuItem<String?>(
                    value: u.id,
                    child: Text(commentItemLabel(widget.board, u.id)),
                  ),
              ],
              onChanged: (v) => setState(() => _unitId = v),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('rc_text'),
              controller: _text,
              maxLines: 4,
              minLines: 2,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: 'Rejection / clarification text *',
                alignLabelWithHint: true,
                errorText: _error,
              ),
            ),
            CheckboxListTile(
              key: const Key('rc_reject'),
              contentPadding: EdgeInsets.zero,
              value: _rejects,
              onChanged: (v) => setState(() => _rejects = v ?? false),
              title: const Text('Reject this photo / evidence'),
              subtitle: const Text(
                'Added to the item-specific issues when you reject the recce.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('rc_save'),
              onPressed: () {
                if (_text.text.trim().isEmpty) {
                  setState(() => _error = 'Enter the comment text');
                  return;
                }
                Navigator.pop(
                  context,
                  _NewComment(_type, _text.text.trim(), _unitId, _rejects),
                );
              },
              child: const Text('Save comment'),
            ),
          ],
        ),
      ),
    );
  }
}
