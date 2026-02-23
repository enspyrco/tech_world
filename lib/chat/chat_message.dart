/// A message in the chat conversation.
class ChatMessage {
  ChatMessage({
    required this.text,
    required this.senderName,
    this.senderId,
    this.conversationId,
    this.participants,
    this.isLocalUser = false,
    this.isBot = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Reconstruct a [ChatMessage] from a Firestore document map.
  factory ChatMessage.fromFirestore(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['text'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
      senderId: json['senderId'] as String?,
      conversationId: json['conversationId'] as String?,
      participants: (json['participants'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  final String text;
  final String senderName;

  /// Firebase UID of the sender, or `'bot-claude'` for bot messages.
  final String? senderId;

  /// Which conversation this message belongs to:
  /// `'group'` for group chat, `'dm_{uid1}_{uid2}'` for DMs.
  final String? conversationId;

  /// UIDs of both participants in a DM conversation.
  ///
  /// Used by Firestore security rules for efficient array-contains checks.
  /// `null` for group messages (which use `conversationId == 'group'` rule).
  final List<String>? participants;

  final bool isLocalUser; // true if this message was sent by the local user
  final bool isBot; // true if this message is from Claude
  final DateTime timestamp;

  /// Legacy getter for backwards compatibility.
  bool get isUser => isLocalUser;

  /// Serialize to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() {
    return {
      'text': text,
      'senderName': senderName,
      if (senderId != null) 'senderId': senderId,
      if (conversationId != null) 'conversationId': conversationId,
      if (participants != null) 'participants': participants,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
