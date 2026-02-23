import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tech_world/chat/chat_message.dart';

/// Firestore persistence for chat messages.
///
/// Messages are stored in a subcollection under each room:
/// `rooms/{roomId}/messages/{messageId}`
///
/// Follows the same constructor-injection pattern as [RoomService].
class ChatMessageRepository {
  ChatMessageRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _messagesRef(String roomId) =>
      _firestore.collection('rooms').doc(roomId).collection('messages');

  /// Persist a [ChatMessage] to the room's messages subcollection.
  Future<void> saveMessage(String roomId, ChatMessage message) async {
    await _messagesRef(roomId).add(message.toFirestore());
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
  /// A user participates in a conversation if:
  /// - It's `'group'` (everyone participates), or
  /// - It's a DM whose ID contains the user's UID.
  Future<Set<String>> loadConversationIds(
    String roomId,
    String userId,
  ) async {
    final snapshot = await _messagesRef(roomId).get();

    final ids = <String>{};
    for (final doc in snapshot.docs) {
      final conversationId = doc.data()['conversationId'] as String?;
      if (conversationId == null) continue;

      if (conversationId == 'group' || conversationId.contains(userId)) {
        ids.add(conversationId);
      }
    }
    return ids;
  }
}
