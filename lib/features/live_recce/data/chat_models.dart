part of 'recce_models.dart';

/// Milestone 3 models: the shop communication thread. Contract: `GET/POST /recce/shops/:siteId/messages`, `.../unread`, `.../read`
/// (docs/recce-development/08-milestone3-api-payloads.md section 1; backend recceReview.thread.ts, connect.service.ts `present`).
/// Parsing is null-safe like the rest of this library: a missing field becomes a safe default, never a thrown cast.

/// A message body is at most this long (the server trims first, then checks).
const maxChatBody = 2000;

/// One message carries at most this many references (the server drops duplicates).
const maxChatRefs = 10;

/// Messages per page (`?limit=`).
const chatPageSize = 30;

/* ------------------------------------------------------------------ refs */

/// What a message can point at: a photo of this shop, a board key, or a submitted version number.
enum ChatRefType {
  photo('PHOTO', 'Photo', Icons.photo_outlined),
  board('BOARD', 'Board', Icons.view_in_ar_outlined),
  version('VERSION', 'Version', Icons.history);

  const ChatRefType(this.code, this.label, this.icon);
  final String code;
  final String label;
  final IconData icon;

  static ChatRefType? parse(Object? code) {
    final c = code?.toString().trim().toUpperCase();
    for (final t in values) {
      if (t.code == c) return t;
    }
    return null;
  }
}

class ChatRef {
  const ChatRef(this.type, this.id);

  final ChatRefType type;

  /// A photo id, a board key (`b1`) or a version number as text (`2`).
  final String id;

  String get key => '${type.code}:$id';

  /// Body item of the POST `refs` array.
  Json toJson() => {'type': type.code, 'id': id};

  /// Null for an unknown type or an empty id (the app then simply shows no chip for it).
  static ChatRef? tryParse(dynamic v) {
    if (v is! Map) return null;
    final type = ChatRefType.parse(v['type']);
    final id = _s(v['id']);
    return type == null || id == null ? null : ChatRef(type, id);
  }

  @override
  bool operator ==(Object other) => other is ChatRef && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}

/// The refs without duplicates, first one kept (the server drops duplicates too, so the count shown is the real count).
List<ChatRef> uniqueRefs(Iterable<ChatRef> refs) => {...refs}.toList();

/* ------------------------------------------------------------------ message */

/// "RECCE_EXECUTIVE" -> "Recce Executive".
String roleText(String role) {
  final words = role.trim().toLowerCase().split('_').where((w) => w.isNotEmpty);
  return words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
}

class ChatAuthor {
  const ChatAuthor({this.id = '', this.name = '', this.role = ''});

  final String id;
  final String name;
  final String role;

  String get displayName => name.isEmpty ? 'Former member' : name;
  String get roleLabel => roleText(role);

  factory ChatAuthor.fromJson(dynamic v) {
    final j = _m(v);
    return ChatAuthor(id: (j['id'] ?? '').toString(), name: (j['name'] ?? '').toString(), role: (j['role'] ?? '').toString());
  }
}

class ChatAttachment {
  const ChatAttachment({required this.fileId, this.name = 'file', this.size = 0, this.mimeType = '', this.kind = '', this.url, this.expiresAt});

  final String fileId;
  final String name;
  final int size;
  final String mimeType;
  final String kind;

  /// A short-lived private link: null when the server could not sign one. Ask the list again for a fresh one.
  final String? url;
  final DateTime? expiresAt;

  bool get isImage => kind == 'image' || mimeType.startsWith('image/');

  /// True when the signed link has run out (or has no link at all).
  bool linkExpired(DateTime now) => url == null || (expiresAt != null && !expiresAt!.isAfter(now));

  factory ChatAttachment.fromJson(Json j) => ChatAttachment(
        fileId: (j['fileId'] ?? '').toString(),
        name: _s(j['name']) ?? 'file',
        size: _i(j['size']),
        mimeType: (j['mimeType'] ?? '').toString(),
        kind: (j['kind'] ?? '').toString(),
        url: _s(j['url']),
        expiresAt: _dt(j['expiresAt']),
      );
}

class ChatCardLine {
  const ChatCardLine(this.label, this.value);
  final String label;
  final String value;
}

/// A system message (version submitted, reviewed, rework asked, reopened ...). `tone` is info | good | warn | bad.
class ChatCard {
  const ChatCard({required this.title, this.tone = '', this.path, this.lines = const []});

  final String title;
  final String tone;
  final String? path;
  final List<ChatCardLine> lines;

  factory ChatCard.fromJson(Json j) => ChatCard(
        title: (j['title'] ?? '').toString(),
        tone: (j['tone'] ?? '').toString(),
        path: _s(j['path']),
        lines: [for (final l in _ml(j['lines'])) ChatCardLine((l['label'] ?? '').toString(), (l['value'] ?? '').toString())],
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    this.author = const ChatAuthor(),
    this.body = '',
    this.attachments = const [],
    this.refs = const [],
    this.card,
    this.createdAt,
    this.edited = false,
    this.deleted = false,
  });

  final String id;
  final ChatAuthor author;
  final String body;
  final List<ChatAttachment> attachments;
  final List<ChatRef> refs;
  final ChatCard? card;

  /// Local time (the server sends UTC).
  final DateTime? createdAt;
  final bool edited;
  final bool deleted;

  /// A system card, not a person's message.
  bool get isSystem => card != null;

  bool isMine(String myId) => !isSystem && myId.isNotEmpty && author.id == myId;

  bool hasExpiredLinks(DateTime now) => attachments.any((a) => a.isImage && a.linkExpired(now));

  factory ChatMessage.fromJson(Json j) => ChatMessage(
        id: (j['id'] ?? '').toString(),
        author: ChatAuthor.fromJson(j['author']),
        body: (j['body'] ?? '').toString(),
        attachments: [for (final a in _ml(j['attachments'])) ChatAttachment.fromJson(a)],
        refs: [for (final r in (j['refs'] is List ? j['refs'] as List : const [])) ?ChatRef.tryParse(r)],
        card: j['card'] is Map ? ChatCard.fromJson(_m(j['card'])) : null,
        createdAt: _dt(j['createdAt']),
        edited: j['edited'] == true,
        deleted: j['deleted'] == true,
      );

  /// The messages of a list answer; a row without an id or a deleted one is left out.
  static List<ChatMessage> listFrom(dynamic v) => [
        for (final e in _ml(v))
          if (_s(e['id']) != null && e['deleted'] != true) ChatMessage.fromJson(e),
      ];
}

/// One answer of `GET .../messages?limit=&before=`: a page, NEWEST first. [nextBefore] is the id to pass as `before` for the next
/// (older) page, and null when there is nothing older.
class ChatPage {
  const ChatPage({this.items = const [], this.nextBefore});

  final List<ChatMessage> items;
  final String? nextBefore;

  bool get hasMore => nextBefore != null;

  factory ChatPage.fromEnvelope(dynamic body) {
    final map = body is Map ? body : const {};
    return ChatPage(items: ChatMessage.listFrom(map['data']), nextBefore: _s(_m(map['meta'])['nextBefore']));
  }
}

/* ------------------------------------------------------------------ merging pages */

/// Oldest first by time, then by id.
int compareChat(ChatMessage a, ChatMessage b) {
  final x = a.createdAt;
  final y = b.createdAt;
  if (x != null && y != null) {
    final c = x.compareTo(y);
    if (c != 0) return c;
  }
  return a.id.compareTo(b.id);
}

List<ChatMessage> sortedOldestFirst(Iterable<ChatMessage> items) {
  final byId = <String, ChatMessage>{for (final m in items) m.id: m};
  return byId.values.toList()..sort(compareChat);
}

/// An OLDER page (newest first, as the server sends it) joins the thread we hold (oldest first). No message appears twice.
List<ChatMessage> mergeOlder(List<ChatMessage> current, ChatPage older) {
  final byId = <String, ChatMessage>{for (final m in older.items) m.id: m, for (final m in current) m.id: m};
  return byId.values.toList()..sort(compareChat);
}

/// The NEWEST page (a refresh or a poll) replaces the newest part of the thread we hold, which also brings fresh signed links.
/// Older messages we already loaded stay. A page with no older part holds the whole thread, so it simply replaces it.
List<ChatMessage> mergeLatest(List<ChatMessage> current, ChatPage latest) {
  final fresh = sortedOldestFirst(latest.items);
  if (!latest.hasMore || fresh.isEmpty) return fresh;
  final boundary = fresh.first;
  return sortedOldestFirst([...current.where((m) => compareChat(m, boundary) < 0), ...fresh]);
}

/// A message we just sent joins the end of the thread (or replaces the copy a refresh already brought).
List<ChatMessage> withSent(List<ChatMessage> current, ChatMessage sent) => sortedOldestFirst([...current, sent]);

/// `GET .../messages/unread` -> `data.unread` (never negative).
int parseUnread(dynamic body) {
  final data = body is Map ? body['data'] : null;
  final n = data is Map ? _i(data['unread']) : 0;
  return n < 0 ? 0 : n;
}

/* ------------------------------------------------------------------ composer rules */

/// Why this message cannot be sent, or null. The server checks the same: text or an image, 2000 characters after trimming, 10 refs.
String? validateChatDraft({required String body, required Iterable<ChatRef> refs, required bool hasImage}) {
  final text = body.trim();
  if (text.isEmpty && !hasImage) return 'Write a message or attach a photo.';
  if (text.length > maxChatBody) return 'A message can have at most $maxChatBody characters (now ${text.length}).';
  if (uniqueRefs(refs).length > maxChatRefs) return 'Attach at most $maxChatRefs references to one message.';
  return null;
}

/* ------------------------------------------------------------------ image file name */

/// The extension the server accepts (`.jpg .png .webp`) read from the first bytes, or null.
String? sniffImageExtension(List<int> b) {
  if (b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) return '.jpg';
  if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47) return '.png';
  if (b.length >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return '.webp';
  return null;
}

/// File name for the upload. The server decides the type from the extension and then checks the content, so the extension is the
/// real format of [bytes] (a picker may name a re-encoded photo `.heic` or give a browser blob no name at all).
String chatImageName(String? picked, List<int> bytes) {
  final raw = (picked ?? '').split(RegExp(r'[\\/]')).last.trim();
  final dot = raw.lastIndexOf('.');
  var base = (dot > 0 ? raw.substring(0, dot) : raw).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (base.length > 60) base = base.substring(0, 60);
  if (base.isEmpty) base = 'photo';
  final named = dot > 0 ? raw.substring(dot).toLowerCase() : '';
  final ext = sniffImageExtension(bytes) ?? (const ['.jpg', '.jpeg', '.png', '.webp'].contains(named) ? named : '.jpg');
  return '$base$ext';
}
