import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_file_row.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/chat_controller.dart';
import '../data/recce_models.dart';

/// What a reference chip says: the photo's category, the board's name, the version number. [detail] and [versions] come from the
/// shop screen; a reference to something that is not there any more still gets a plain label.
String chatRefLabel(ChatRef r, {ShopDetail? detail, List<RecceVersion> versions = const []}) {
  switch (r.type) {
    case ChatRefType.photo:
      for (final p in [...?detail?.photos, for (final v in versions) ...v.photos]) {
        if (p.id == r.id) return 'Photo: ${detail?.categoryLabel(p.category) ?? photoCategoryLabel(p.category)}';
      }
      return 'Photo';
    case ChatRefType.board:
      for (final b in [...?detail?.mediaItems, for (final v in versions) ...v.mediaItems]) {
        if (b.key == r.id) return 'Board ${b.key} (${boardSummaryText(b)})';
      }
      return 'Board ${r.id}';
    case ChatRefType.version:
      return 'Version ${r.id}';
  }
}

Color chatToneColor(String tone) => switch (tone) {
      'good' => AdinnColors.success,
      'warn' => AdinnColors.warning,
      'bad' => AdinnColors.red,
      'info' => AdinnColors.info,
      _ => AdinnColors.muted,
    };

IconData chatToneIcon(String tone) => switch (tone) {
      'good' => Icons.check_circle_outline,
      'warn' => Icons.flag_outlined,
      'bad' => Icons.cancel_outlined,
      'info' => Icons.info_outline,
      _ => Icons.notifications_none,
    };

/// The references of a message as tappable chips (a photo opens, a board jumps to the Boards tab, a version opens its details).
/// With [onTap] null the chips only show.
class ChatRefChips extends StatelessWidget {
  const ChatRefChips({super.key, required this.refs, required this.labelOf, this.onTap});

  final List<ChatRef> refs;
  final String Function(ChatRef) labelOf;
  final ValueChanged<ChatRef>? onTap;

  @override
  Widget build(BuildContext context) {
    if (refs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final r in refs)
            ActionChip(
              key: ValueKey('ref-${r.key}'),
              avatar: Icon(r.type.icon, size: 15, color: AdinnColors.red),
              label: Text(labelOf(r), maxLines: 1, overflow: TextOverflow.ellipsis),
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdinnColors.ink),
              backgroundColor: Colors.white,
              side: const BorderSide(color: AdinnColors.line),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onPressed: onTap == null ? null : () => onTap!(r),
            ),
        ],
      ),
    );
  }
}

/// The date heading between the days of a thread.
class ChatDayChip extends StatelessWidget {
  const ChatDayChip(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: AdinnColors.line.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdinnColors.muted)),
        ),
      ),
    );
  }
}

/// A system message: Shop Recce Submitted, Recce Review Update, Shop Reopened ... Drawn full width with the tone colour, apart from
/// the bubbles of people.
class ChatSystemCard extends StatelessWidget {
  const ChatSystemCard({super.key, required this.message, required this.labelOf, this.onRef});

  final ChatMessage message;
  final String Function(ChatRef) labelOf;
  final ValueChanged<ChatRef>? onRef;

  @override
  Widget build(BuildContext context) {
    final card = message.card!;
    final color = chatToneColor(card.tone);
    return Container(
      key: ValueKey('card-${message.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4), top: BorderSide(color: color.withValues(alpha: 0.3)), right: BorderSide(color: color.withValues(alpha: 0.3)), bottom: BorderSide(color: color.withValues(alpha: 0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(chatToneIcon(card.tone), size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(card.title, style: TextStyle(fontWeight: FontWeight.w800, color: color))),
          ]),
          for (final l in card.lines)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 92, child: Text(l.label, style: const TextStyle(fontSize: 12, color: AdinnColors.muted))),
                Expanded(child: Text(l.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              ]),
            ),
          if (message.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(message.body)),
          ChatRefChips(refs: message.refs, labelOf: labelOf, onTap: onRef),
          if (message.createdAt != null)
            Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(top: 4), child: Text('System  |  ${fmtTime(message.createdAt!)}', style: const TextStyle(fontSize: 11, color: AdinnColors.muted)))),
        ],
      ),
    );
  }
}

/// A person's message: own on the right, the others' on the left with name and role.
class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message, required this.mine, required this.labelOf, this.onRef, this.onImageFailed});

  final ChatMessage message;
  final bool mine;
  final String Function(ChatRef) labelOf;
  final ValueChanged<ChatRef>? onRef;

  /// A picture could not load (its signed link ran out): the thread is read again for fresh links.
  final VoidCallback? onImageFailed;

  @override
  Widget build(BuildContext context) {
    return _BubbleFrame(
      mine: mine,
      key: ValueKey('msg-${message.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!mine)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(message.author.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
              if (message.author.roleLabel.isNotEmpty) ...[const SizedBox(width: 6), TagChip(message.author.roleLabel)],
            ]),
          if (message.body.isNotEmpty) Padding(padding: EdgeInsets.only(top: mine ? 0 : 4), child: SelectableText(message.body)),
          for (final a in message.attachments)
            a.isImage
                ? _ChatImage(attachment: a, onFailed: onImageFailed)
                : Padding(padding: const EdgeInsets.only(top: 6), child: AppFileRow(name: a.name, size: a.size, url: a.url)),
          ChatRefChips(refs: message.refs, labelOf: labelOf, onTap: onRef),
          if (message.createdAt != null)
            Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(fmtTime(message.createdAt!), style: const TextStyle(fontSize: 11, color: AdinnColors.muted)))),
        ],
      ),
    );
  }
}

/// A message still on its way (or that failed): the person's own bubble with its state, Retry and Discard.
class PendingChatBubble extends StatelessWidget {
  const PendingChatBubble({super.key, required this.message, required this.labelOf, required this.onRetry, required this.onDiscard});

  final PendingChatMessage message;
  final String Function(ChatRef) labelOf;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final p = message;
    return _BubbleFrame(
      mine: true,
      failed: p.failed,
      key: ValueKey('pending-${p.localId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p.body.isNotEmpty) Text(p.body),
          if (p.hasImage)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: AppFileRow(
                name: p.imageName ?? 'Photo',
                size: p.imageSize,
                localPath: p.imagePath,
                state: p.failed ? AppFileState.failed : AppFileState.uploading,
                progress: p.progress,
                message: p.error,
                onRetry: onRetry,
                onCancel: onDiscard,
                onRemove: onDiscard,
              ),
            ),
          ChatRefChips(refs: p.refs, labelOf: labelOf),
          if (!p.hasImage)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: p.failed
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline, size: 15, color: AdinnColors.red),
                        const SizedBox(width: 4),
                        Flexible(child: Text('Not sent${(p.error ?? '').isEmpty ? '' : ': ${p.error}'}', style: const TextStyle(fontSize: 12, color: AdinnColors.red, fontWeight: FontWeight.w600))),
                      ]),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 16), label: const Text('Retry')),
                        TextButton(onPressed: onDiscard, child: const Text('Discard')),
                      ]),
                    ])
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 6),
                      Text('Sending...', style: TextStyle(fontSize: 12, color: AdinnColors.muted)),
                    ]),
            ),
        ],
      ),
    );
  }
}

/// The bubble shape: own right-aligned on a light red ground, the others' left-aligned on white.
class _BubbleFrame extends StatelessWidget {
  const _BubbleFrame({super.key, required this.mine, required this.child, this.failed = false});

  final bool mine;
  final bool failed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.84;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? AdinnColors.redLight : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(mine ? 14 : 4),
              bottomRight: Radius.circular(mine ? 4 : 14),
            ),
            border: Border.all(color: failed ? AdinnColors.red : (mine ? AdinnColors.red.withValues(alpha: 0.25) : AdinnColors.line), width: failed ? 1.4 : 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A stored picture: a fixed-shape preview (so the thread does not jump while it loads), tap for the full-screen zoom viewer, and a
/// download button. A missing or dead link shows a note and asks for a fresh read of the thread.
class _ChatImage extends StatelessWidget {
  const _ChatImage({required this.attachment, this.onFailed});

  final ChatAttachment attachment;
  final VoidCallback? onFailed;

  static Widget _note(String text) => ColoredBox(
        color: AdinnColors.canvas,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.broken_image_outlined, color: AdinnColors.muted),
              const SizedBox(height: 4),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AdinnColors.muted)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final url = attachment.url;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: AspectRatio(
          aspectRatio: 1.4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: url == null
                ? GestureDetector(onTap: onFailed, child: _note('Picture link expired. Tap to refresh.'))
                : Stack(fit: StackFit.expand, children: [
                    GestureDetector(
                      onTap: () => showAppPhotoViewer(context, title: attachment.name, url: url),
                      child: appNetworkImage(
                        url,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) => progress == null ? child : const ColoredBox(color: AdinnColors.canvas, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                        errorBuilder: (_, _, _) {
                          if (onFailed != null) WidgetsBinding.instance.addPostFrameCallback((_) => onFailed!());
                          return _note('Picture could not load');
                        },
                      ),
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Download',
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          color: Colors.white,
                          icon: const Icon(Icons.download_outlined),
                          onPressed: () => downloadFile(context, url),
                        ),
                      ),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }
}
