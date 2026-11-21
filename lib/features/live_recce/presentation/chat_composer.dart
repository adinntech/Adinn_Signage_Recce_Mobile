import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_file_row.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/chat_controller.dart';
import '../data/recce_controllers.dart';
import '../data/recce_models.dart';
import 'chat_bubbles.dart';
import 'chat_ref_picker.dart';

/// Picks ONE picture from the camera or the gallery. Tests give a fake one (no camera, no gallery).
typedef ChatImagePicker = Future<XFile?> Function(ImageSource source);

Future<XFile?> pickChatImage(ImageSource source) => ImagePicker().pickImage(source: source, maxWidth: 2400, imageQuality: 85);

/// The box under the thread: text (2000 characters at most), one picture, and the references. The draft lives in the
/// [ShopChatController], so it is still there after a change of tab. Send is only active when the message is allowed.
class ChatComposer extends StatefulWidget {
  const ChatComposer({super.key, required this.chat, required this.shop, this.picker = pickChatImage});

  final ShopChatController chat;
  final ShopDetailController shop;
  final ChatImagePicker picker;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  late final _text = TextEditingController(text: widget.chat.draftBody);

  ShopChatController get chat => widget.chat;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _changed(String v) {
    chat.draftBody = v; // no rebuild of the thread for a keystroke
    setState(() {});
  }

  void _send() {
    final problem = chat.sendDraft();
    if (problem != null) return showSnack(context, problem, error: true);
    _text.clear();
    setState(() {});
  }

  Future<void> _attach() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final file = await widget.picker(source);
      if (file == null || !mounted) return;
      chat.setDraftImage(file.path, file.name, await file.length());
    } on PlatformException {
      if (mounted) showSnack(context, 'Allow camera or photo access to attach a picture.', error: true);
    } catch (_) {
      if (mounted) showSnack(context, 'The picture could not be picked. Try again.', error: true);
    }
  }

  Future<void> _pickRefs() async {
    final picked = await showChatRefPicker(context, shop: widget.shop, selected: chat.draftRefs);
    if (picked != null) chat.setDraftRefs(picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final path = chat.draftImagePath;
        final canSend = chat.draftProblem == null;
        final length = _text.text.trim().length;
        return Material(
          color: Colors.white,
          elevation: 8,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (path != null)
                    AppFileRow(
                      key: const ValueKey('draft-image'),
                      name: chat.draftImageName ?? 'Photo',
                      size: chat.draftImageSize,
                      localPath: path,
                      state: AppFileState.waiting,
                      onRemove: chat.clearDraftImage,
                    ),
                  if (chat.draftRefs.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final r in chat.draftRefs)
                              InputChip(
                                key: ValueKey('draft-ref-${r.key}'),
                                avatar: Icon(r.type.icon, size: 15, color: AdinnColors.red),
                                label: Text(chatRefLabel(r, detail: widget.shop.detail, versions: widget.shop.versionList)),
                                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                onDeleted: () => chat.setDraftRefs([for (final x in chat.draftRefs) if (x != r) x]),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(key: const ValueKey('attach-photo'), tooltip: 'Attach a picture', onPressed: path != null ? null : _attach, icon: const Icon(Icons.add_photo_alternate_outlined)),
                      IconButton(key: const ValueKey('attach-ref'), tooltip: 'Refer to a photo, board or version', onPressed: _pickRefs, icon: const Icon(Icons.link)),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('chat-text'),
                          controller: _text,
                          minLines: 1,
                          maxLines: 5,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          inputFormatters: [LengthLimitingTextInputFormatter(maxChatBody)],
                          onChanged: _changed,
                          decoration: const InputDecoration(hintText: 'Write a message', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton.filled(key: const ValueKey('send-message'), tooltip: 'Send', onPressed: canSend ? _send : null, icon: const Icon(Icons.send)),
                    ],
                  ),
                  if (length >= maxChatBody - 200)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(padding: const EdgeInsets.only(right: 56, top: 2), child: Text('$length / $maxChatBody', style: TextStyle(fontSize: 11, color: length >= maxChatBody ? AdinnColors.red : AdinnColors.muted))),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
