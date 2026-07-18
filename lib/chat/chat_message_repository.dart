import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tech_world/chat/chat_message.dart';

/// An opaque cursor marking a position in a conversation's message history.
///
/// Produced by [ChatMessageRepository.loadMessagePage] and passed back to it
/// (`after:`) to fetch the next OLDER page. The concrete shape (a Firestore
/// [DocumentSnapshot] for the real repository) is hidden so [ChatService] can
/// hold and thread it without depending on Firestore — fakes in tests supply
/// their own [MessageCursor] subtype (e.g. an offset).
abstract class MessageCursor {
  const MessageCursor();
}

/// One page of history plus the cursor for the next (older) page.
///
/// [messages] are ASCENDING (oldest→newest) within the page, matching the
/// order [ChatService] keeps its in-memory lists in, even though the underlying
/// query is newest-first. [cursor] is null when there is no older page to
/// fetch; [hasMore] is true when the page filled to [limit] (so an older page
/// *might* exist). A page shorter than [limit] means history is exhausted —
/// the caller latches on `!hasMore` and never refetches.
class MessagePage {
  const MessagePage({
    required this.messages,
    required this.cursor,
    required this.hasMore,
  });

  /// An exhausted / empty page: no messages, no cursor, no more history.
  static const MessagePage empty =
      MessagePage(messages: [], cursor: null, hasMore: false);

  final List<ChatMessage> messages;
  final MessageCursor? cursor;
  final bool hasMore;
}

/// Firestore-backed [MessageCursor] wrapping the last document of a page, used
/// with `startAfterDocument` to fetch the next older page. Private to the
/// repository — the app only ever passes it back opaquely.
class _FirestoreCursor extends MessageCursor {
  const _FirestoreCursor(this.doc);
  final DocumentSnapshot<Map<String, dynamic>> doc;
}

/// Firestore persistence for chat messages and conversation metadata.
///
/// Messages are stored in `rooms/{roomId}/messages/{messageId}`.
/// Conversation metadata is stored in `rooms/{roomId}/conversations/{convId}`.
///
/// Follows the same constructor-injection pattern as [RoomService].
class ChatMessageRepository {
  ChatMessageRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Default page size for [loadMessagePage]. History is eternal (never
  /// cleared), so it is loaded a page at a time, newest-first, on demand.
  static const int defaultPageSize = 50;

  CollectionReference<Map<String, dynamic>> _messagesRef(String roomId) =>
      _firestore.collection('rooms').doc(roomId).collection('messages');

  CollectionReference<Map<String, dynamic>> _conversationsRef(String roomId) =>
      _firestore.collection('rooms').doc(roomId).collection('conversations');

  /// Persist a [ChatMessage] to the room's messages subcollection.
  Future<void> saveMessage(String roomId, ChatMessage message) async {
    await _messagesRef(roomId).add(message.toFirestore());
  }

  /// Upsert conversation metadata to the conversations subcollection.
  ///
  /// Called alongside [saveMessage] so that [loadConversationIds] can query
  /// the lightweight conversations collection instead of scanning all messages.
  Future<void> saveConversation(
    String roomId, {
    required String conversationId,
    required List<String> participants,
    required String type,
    String? lastMessageText,
  }) async {
    await _conversationsRef(roomId).doc(conversationId).set(
      {
        'participants': participants,
        'lastActivity': FieldValue.serverTimestamp(),
        'type': type,
        if (lastMessageText != null) 'lastMessageText': lastMessageText,
      },
      SetOptions(merge: true),
    );
  }

  /// Load one page of a conversation's messages, newest-first internally but
  /// returned ASCENDING (oldest→newest) within the page.
  ///
  /// [conversationId] is `'group'` for group chat or `'dm_{uid1}_{uid2}'` for
  /// DMs. Pass [after] = the [MessagePage.cursor] from a previous call to fetch
  /// the next OLDER page; pass `null` (the default) for the newest page.
  ///
  /// History is eternal, so this is the ONLY read path — the whole conversation
  /// is never loaded at once. `startAfterDocument` is used (rather than a raw
  /// timestamp value) so equal-timestamp messages page correctly: Firestore
  /// tie-breaks on the document key, avoiding the skip/duplicate a bare
  /// `startAfter(timestamp)` would cause when two messages share a millisecond.
  Future<MessagePage> loadMessagePage(
    String roomId,
    String conversationId, {
    MessageCursor? after,
    int limit = defaultPageSize,
  }) async {
    var query = _messagesRef(roomId)
        .where('conversationId', isEqualTo: conversationId)
        .orderBy('timestamp', descending: true);

    if (after != null) {
      query = query.startAfterDocument((after as _FirestoreCursor).doc);
    }

    final snapshot = await query.limit(limit).get();
    final docs = snapshot.docs; // newest→oldest

    // Reverse to ascending (oldest→newest) for the caller's in-memory list.
    final messages = docs.reversed
        .map((doc) => ChatMessage.fromFirestore(doc.data()))
        .toList();

    final hasMore = docs.length == limit;
    // The oldest doc of THIS page (last in the descending result) anchors the
    // next older page. Null when the page is empty or exhausted.
    final cursor =
        (hasMore && docs.isNotEmpty) ? _FirestoreCursor(docs.last) : null;

    return MessagePage(messages: messages, cursor: cursor, hasMore: hasMore);
  }

  /// Load the set of distinct conversation IDs that [userId] participates in.
  ///
  /// Queries the lightweight conversations subcollection using an
  /// `arrayContains` filter on `participants`, avoiding a full messages scan.
  Future<Set<String>> loadConversationIds(
    String roomId,
    String userId,
  ) async {
    final snapshot = await _conversationsRef(roomId)
        .where('participants', arrayContains: userId)
        .get();

    // The group conversation is always included.
    final ids = <String>{'group'};
    for (final doc in snapshot.docs) {
      ids.add(doc.id);
    }
    return ids;
  }
}
