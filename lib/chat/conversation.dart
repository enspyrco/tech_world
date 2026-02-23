/// Type of chat conversation.
enum ConversationType {
  /// Group chat visible to all room participants.
  group,

  /// Private direct message between two users.
  dm,
}

/// An immutable chat conversation — either the shared group chat or a private
/// DM thread.
///
/// Use [copyWith] to derive a new instance with updated fields.
class Conversation {
  const Conversation({
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
  final int unreadCount;

  /// Timestamp of the most recent message, used for sorting.
  final DateTime? lastActivity;

  /// Returns a copy of this conversation with the given fields replaced.
  Conversation copyWith({
    String? id,
    ConversationType? type,
    String? peerId,
    String? peerDisplayName,
    int? unreadCount,
    DateTime? lastActivity,
  }) {
    return Conversation(
      id: id ?? this.id,
      type: type ?? this.type,
      peerId: peerId ?? this.peerId,
      peerDisplayName: peerDisplayName ?? this.peerDisplayName,
      unreadCount: unreadCount ?? this.unreadCount,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }

  /// Compute a deterministic conversation ID for a DM between two users.
  ///
  /// Sorts UIDs alphabetically so both sides produce the same key.
  static String conversationIdFor(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return 'dm_${sorted[0]}_${sorted[1]}';
  }
}
