/// A message in the chat conversation.
class ChatMessage {
  ChatMessage({
    required this.text,
    required this.senderName,
    this.isLocalUser = false,
    this.isBot = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String text;
  final String senderName;
  final bool isLocalUser; // true if this message was sent by the local user
  final bool isBot; // true if this message is from Claude
  final DateTime timestamp;

  /// Legacy getter for backwards compatibility
  bool get isUser => isLocalUser;
}
