import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalog/signage_catalog.dart';
import '../photos/photo_workspace_screen.dart';
import '../preview_live/live_preview_tab.dart' show PngWriter;
import '../../state/app_controller.dart';
import 'ar_preview_tab.dart';
import 'ar_session_controller.dart';

/// Full-screen Camera AR for one signage item. Works without any site photo
/// (uses the live camera); Live Preview needs a captured photo.
class CameraArScreen extends StatelessWidget {
  const CameraArScreen({
    super.key,
    required this.shopId,
    required this.boardId,
    required this.unitId,
    this.platform,
    this.writer,
  });

  final String shopId;
  final String boardId;
  final String unitId;
  final ArPlatform? platform;
  final PngWriter? writer;

  void _openLive(BuildContext context) {
    final c = context.read<AppController>();
    final b = c.board(shopId, boardId);
    final u = b?.unitById(unitId);
    if (b == null || u == null) return;
    final photos = b.photosOf(u).isNotEmpty ? b.photosOf(u) : b.photos;
    if (photos.isEmpty) {
      showSnack(
        context,
        'No site photos available. Capture a site photo to continue.',
        error: true,
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PhotoWorkspaceScreen(
          shopId: shopId,
          boardId: boardId,
          photoId: photos.first.id,
          initialUnitId: unitId,
          initialTab: 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final shop = c.shop(shopId);
    final b = c.board(shopId, boardId);
    final u = b?.unitById(unitId);
    if (shop == null || b == null || u == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.search_off, title: 'Item not found'),
      );
    }
    final media = SignageCatalog.media(b.mediaCode);
    final project = c.project(shop.projectId);
    final task = c.task(shop.taskId);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        toolbarHeight: 66,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              shop.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              '${project?.name ?? 'Project'} • ${task?.title ?? 'Task'}',
              key: const ValueKey('ar_project_task'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AdinnColors.ink),
            ),
            Text(
              '${media?.shortName ?? 'Media not set'} • ${b.unitLabel(u)} • '
              'ID ${u.id}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AdinnColors.muted),
            ),
          ],
        ),
      ),
      body: ArPreviewTab(
        shopId: shopId,
        boardId: boardId,
        unitId: unitId,
        platform: platform,
        writer: writer,
        editable: c.canEdit(shop),
        onOpenLivePreview: () => _openLive(context),
      ),
    );
  }
}
