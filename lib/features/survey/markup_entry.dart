import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/app_controller.dart';
import '../annotation/annotation_editor_screen.dart';
import 'site_markup_controller.dart';
import 'site_markup_painter.dart';
import 'site_markup_screen.dart';
import 'unit_survey_screen.dart';

/// Opens the advanced site markup editor for a photo.
Future<void> openSiteMarkup(
  BuildContext context, {
  required String shopId,
  required String boardId,
  required String photoId,
  SiteMarkupTool tool = SiteMarkupTool.select,
  String? activeUnitId,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => SiteMarkupScreen(
      shopId: shopId,
      boardId: boardId,
      photoId: photoId,
      initialTool: tool,
      activeUnitId: activeUnitId,
      onOpenItem: (ctx, b, u) => openUnitSurvey(ctx, shopId, b, u),
    ),
  ),
);

/// Opens the site survey (measurements, checklist, electrical,
/// obstructions) of one signage item.
Future<void> openUnitSurvey(
  BuildContext context,
  String shopId,
  Board b,
  SignageUnit u, {
  int initialTab = 0,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => UnitSurveyScreen(
      shopId: shopId,
      boardId: b.id,
      unitId: u.id,
      initialTab: initialTab,
      onOpenPhotoMarkup: (ctx, photo) {
        final owner = _ownerOf(ctx, shopId, photo.id) ?? b.id;
        openSiteMarkup(
          ctx,
          shopId: shopId,
          boardId: owner,
          photoId: photo.id,
          activeUnitId: u.id,
        );
      },
    ),
  ),
);

String? _ownerOf(BuildContext context, String shopId, String photoId) {
  final s = context.read<AppController>().shop(shopId);
  for (final b in s?.boards ?? const <Board>[]) {
    if (b.photos.any((p) => p.id == photoId)) return b.id;
  }
  return null;
}

/// Advanced site markup tools offered inside the classic photo editor.
List<AnnotationExtraTool> siteMarkupTools(
  BuildContext context, {
  required String shopId,
  required String boardId,
  required String photoId,
  String? activeUnitId,
}) {
  AnnotationExtraTool tool(
    String id,
    IconData icon,
    String label,
    SiteMarkupTool t,
  ) => AnnotationExtraTool(
    id: id,
    icon: icon,
    label: label,
    onTap: () => openSiteMarkup(
      context,
      shopId: shopId,
      boardId: boardId,
      photoId: photoId,
      tool: t,
      activeUnitId: activeUnitId,
    ),
  );
  return [
    tool(
      'perspective',
      Icons.crop_rotate,
      'Perspective',
      SiteMarkupTool.perspective,
    ),
    tool('marker', Icons.pin_drop_outlined, 'Board pin', SiteMarkupTool.marker),
    tool(
      'electrical',
      Icons.bolt,
      'Electrical',
      SiteMarkupTool.electricalPoint,
    ),
    tool(
      'obstruction',
      Icons.report_problem_outlined,
      'Obstruction',
      SiteMarkupTool.obstruction,
    ),
  ];
}

/// Read-only painter of a photo's saved site markup that repaints whenever
/// the app data changes (the markup object is replaced on save).
class LiveMarkupUnderlay extends CustomPainter {
  LiveMarkupUnderlay({
    required this.controller,
    required this.shopId,
    required this.photo,
  }) : super(repaint: controller);

  final AppController controller;
  final String shopId;
  final SitePhoto photo;

  @override
  void paint(Canvas canvas, Size size) {
    final s = controller.shop(shopId);
    if (s == null || photo.markup.isEmpty) return;
    SiteMarkupPainter(
      markup: photo.markup,
      labels: MarkupLabels.forShop(
        s,
        brand: controller.project(s.projectId)?.client ?? '',
      ),
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant LiveMarkupUnderlay old) =>
      old.photo != photo || old.shopId != shopId;
}

/// Opens the markup editor for [photo] wherever it lives in the shop.
void openPhotoMarkup(
  BuildContext context,
  String shopId,
  SitePhoto photo, {
  String? unitId,
}) {
  final owner = _ownerOf(context, shopId, photo.id);
  if (owner == null) return;
  openSiteMarkup(
    context,
    shopId: shopId,
    boardId: owner,
    photoId: photo.id,
    activeUnitId: unitId,
  );
}
