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
    this.replyToMessageId,
    this.replyToText,
    this.replyToSenderName,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Reconstruct a [ChatMessage] from a Firestore document map.
  ///
  /// Optional fields are parsed defensively with Dart 3 if-case patterns
  /// rather than blind `as` casts: a malformed value (wrong type, e.g. an int
  /// where a string is expected) drops the field instead of throwing. This
  /// matters at the wire/persistence seam where the payload is untrusted.
  factory ChatMessage.fromFirestore(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['text'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
      senderId: json['senderId'] as String?,
      conversationId: json['conversationId'] as String?,
      participants: (json['participants'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      replyToMessageId: _asStringOrNull(json['replyToMessageId']),
      replyToText: _asStringOrNull(json['replyToText']),
      replyToSenderName: _asStringOrNull(json['replyToSenderName']),
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

  /// The ID of the message this one quote-replies to, or `null` if it isn't a
  /// reply. Free-form opaque ID (the sender's microsecond message id), so it
  /// stays a `String` rather than a closed-set enum.
  final String? replyToMessageId;

  /// Denormalized snapshot of the quoted message's text, carried so a reply
  /// renders its quote even when the original isn't in the local list. This is
  /// display-only (cosmetic), like [senderName] — it is NOT a trust anchor.
  final String? replyToText;

  /// Denormalized snapshot of the quoted message's sender name. Display-only.
  final String? replyToSenderName;

  /// Legacy getter for backwards compatibility.
  bool get isUser => isLocalUser;

  /// Whether this message quote-replies to another message.
  bool get isReply => replyToMessageId != null;

  /// A stable-enough key identifying this message for reply linkage.
  ///
  /// [ChatMessage] carries no transported wire `id`, so reply targeting uses a
  /// derived key from the sender + microsecond timestamp. Deterministic and
  /// survives the Firestore round-trip (both inputs persist). This is
  /// best-effort UX linkage (quote / scroll-to), not a correctness invariant.
  String get localKey =>
      '${senderId ?? senderName}:${timestamp.microsecondsSinceEpoch}';

  /// Coerce a dynamic value to a non-empty `String`, or `null` otherwise.
  ///
  /// Used at the Firestore parse seam so a malformed value (wrong type) drops
  /// the field instead of throwing and tearing down the caller.
  static String? _asStringOrNull(Object? value) =>
      value is String ? value : null;

  /// Serialize to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() {
    return {
      'text': text,
      'senderName': senderName,
      if (senderId != null) 'senderId': senderId,
      if (conversationId != null) 'conversationId': conversationId,
      if (participants != null) 'participants': participants,
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      if (replyToText != null) 'replyToText': replyToText,
      if (replyToSenderName != null) 'replyToSenderName': replyToSenderName,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
