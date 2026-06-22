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
  /// EVERY field is parsed defensively (no unchecked `as` casts on values that
  /// could be malformed): a wrong-type / legacy / mixed-version value drops or
  /// falls back rather than throwing. This is the persistence seam — a single
  /// bad doc must not throw and tear down the whole history load. Specifically:
  /// - `participants`: non-`List` → null; non-`String` elements skipped.
  /// - `timestamp`: missing/unparseable → `DateTime.now()` fallback (no throw).
  /// - reply fields: wrong type → null (not treated as a reply).
  factory ChatMessage.fromFirestore(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['text'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
      senderId: asStringOrNull(json['senderId']),
      conversationId: asStringOrNull(json['conversationId']),
      participants: _parseParticipants(json['participants']),
      replyToMessageId: asStringOrNull(json['replyToMessageId']),
      replyToText: asStringOrNull(json['replyToText']),
      replyToSenderName: asStringOrNull(json['replyToSenderName']),
      timestamp: _parseTimestamp(json['timestamp']),
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

  /// Coerce an untrusted dynamic value to a `String`, or `null` otherwise.
  ///
  /// Shared by both wire seams — the Firestore parse here and the LiveKit
  /// data-channel parse in `ChatService` — so a malformed value (wrong type)
  /// drops the field instead of throwing and tearing down the caller.
  static String? asStringOrNull(Object? value) =>
      value is String ? value : null;

  /// Parse the quote-reply snapshot from an untrusted wire payload **atomically**:
  /// all three fields are returned together, or all three are `null`.
  ///
  /// The outbound paths ([ChatService.sendMessage] / [ChatService.sendDm])
  /// derive the trio from a single `replyTo`, so a "half-reply" (an ID with no
  /// snapshot, or a snapshot with no ID) is unrepresentable on send. This
  /// helper enforces the SAME predicate on RECEIVE — a malformed or hostile
  /// payload where only a subset of the three fields are valid strings is
  /// rejected wholesale, never partially admitted. Without this, an inbound
  /// `{replyToMessageId: "x"}` (no text/name) would render a reply bubble
  /// quoting an empty "Unknown", and an inbound `{replyToText: "spoof"}` with a
  /// wrong-typed ID would leave orphaned snapshot fields on a non-reply.
  ///
  /// Like [asStringOrNull], it never throws — the trust boundary is unaffected
  /// because these fields are display-only and never influence `senderId`.
  static ({String? messageId, String? text, String? senderName})
      parseReplySnapshot(Map<String, dynamic> json) {
    final messageId = asStringOrNull(json['replyToMessageId']);
    final text = asStringOrNull(json['replyToText']);
    final senderName = asStringOrNull(json['replyToSenderName']);
    // All-or-nothing: only a complete trio is a valid reply snapshot.
    if (messageId == null || text == null || senderName == null) {
      return (messageId: null, text: null, senderName: null);
    }
    return (messageId: messageId, text: text, senderName: senderName);
  }

  /// Defensively parse the `mentions` field from an untrusted wire payload.
  ///
  /// The structured `mentions` list — UIDs of named players — is the trust
  /// anchor for the world-mention beacon (NOT the inline `@Name` text, which is
  /// display-only and spoofable). It is parsed with the same discipline as
  /// [_parseParticipants]: a non-`List` value (legacy / corrupt / hostile
  /// payload) yields an empty list rather than throwing, and non-`String`
  /// elements are skipped via [Iterable.whereType]. The whole field drops to
  /// empty on malformed input — there is never a half-parsed mention list.
  ///
  /// Never throws — a single bad payload must not tear down the chat stream.
  /// The *mentioner's* UID is always the transport-verified `senderId`, never
  /// derived from this list, so a spoofed payload can name victims but cannot
  /// forge who sent the mention.
  ///
  /// **Bounded at the trust boundary, on both axes.** A hostile peer could
  /// otherwise put a large list on the wire and drive unbounded pulse state /
  /// beacons / arcs on every other client. Two independent caps:
  /// - [maxMentions] distinct UIDs in the OUTPUT (dedup-then-cap), so all
  ///   downstream world work is bounded; and
  /// - [_maxMentionsScan] elements SCANNED from the input, so even a pathological
  ///   payload (e.g. a million duplicate strings before 16 distinct ones) costs
  ///   O(1) here rather than O(n). (The LiveKit data channel already size-bounds
  ///   the payload, so this is belt-and-suspenders, but it makes the bound
  ///   explicit instead of relying on the transport.)
  ///
  /// A real group chat never names more than a handful of people at once.
  static const int maxMentions = 16;

  /// Hard cap on how many list elements [parseMentions] inspects, independent of
  /// how many turn out to be distinct valid UIDs. Comfortably above
  /// [maxMentions] so legitimate (deduped) payloads are never truncated, while a
  /// hostile duplicate-stuffed list can't force an unbounded scan.
  static const int _maxMentionsScan = 256;

  static List<String> parseMentions(Object? value) {
    if (value is! List) return const [];
    final seen = <String>{};
    var scanned = 0;
    for (final element in value) {
      if (scanned++ >= _maxMentionsScan) break;
      if (element is String) seen.add(element);
      if (seen.length >= maxMentions) break;
    }
    return seen.toList();
  }

  /// Defensively parse the `participants` field.
  ///
  /// A non-`List` value (legacy / corrupt doc) yields `null`; non-`String`
  /// elements are skipped rather than throwing. An empty result also yields
  /// `null` so the absence semantics match a missing field.
  static List<String>? _parseParticipants(Object? value) {
    if (value is! List) return null;
    final result = value.whereType<String>().toList();
    return result.isEmpty ? null : result;
  }

  /// Defensively parse the `timestamp` field.
  ///
  /// Missing or unparseable values fall back to [DateTime.now] rather than
  /// throwing — a single bad doc must not crash a whole history load. The
  /// constructor applies the same now-fallback, so this keeps the seam total.
  static DateTime? _parseTimestamp(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

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
