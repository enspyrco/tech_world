/// Type of chat conversation.
enum ConversationType {
  /// Group chat visible to all room participants.
  group,

  /// Private direct message between two users.
  dm,
}

/// A chat conversation — either the shared group chat or a private DM thread.
class Conversation {
  Conversation({
    required this.id,
    required this.type,
    this.peerId,
    this.peerDisplayName,
    this.unreadCount = 0,
    this.lastActivity,
  });

  /// Unique identifier. `'group'` for the group chat, or
  /// `'dm_{sortedUid1}_{sortedUid2}'` for DMs.
  final String id;

  /// Whether this is a group or DM conversation.
  final ConversationType type;

  /// For DM conversations, the other participant's user ID.
  final String? peerId;

  /// For DM conversations, the other participant's display name.
  final String? peerDisplayName;

  /// Number of unread messages in this conversation.
  int unreadCount;

  /// Timestamp of the most recent message, used for sorting.
  DateTime? lastActivity;

  /// Compute a deterministic conversation ID for a DM between two users.
  ///
  /// Sorts UIDs alphabetically so both sides produce the same key.
  static String conversationIdFor(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return 'dm_${sorted[0]}_${sorted[1]}';
  }
}
