import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tech_world/chat/chat_message.dart';

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

  /// Load messages for a specific conversation, ordered by timestamp.
  ///
  /// [conversationId] is `'group'` for group chat or
  /// `'dm_{uid1}_{uid2}'` for DMs.
  Future<List<ChatMessage>> loadMessages(
    String roomId,
    String conversationId, {
    int limit = 100,
  }) async {
    final snapshot = await _messagesRef(roomId)
        .where('conversationId', isEqualTo: conversationId)
        .orderBy('timestamp')
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => ChatMessage.fromFirestore(doc.data()))
        .toList();
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
