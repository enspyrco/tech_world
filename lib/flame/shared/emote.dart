/// The closed set of player emotes.
///
/// Wire values are lowercase identifiers preserved verbatim on the
/// [LiveKitTopic.emote] data channel. An enum (not a `String`) so a new emote
/// forces every consumer to be revisited, and so a hostile peer's arbitrary
/// string can never reach the renderer — [parse] returns null and the receiver
/// drops the message.
enum EmoteId {
  /// Front-facing alternating arm-raise. Sprite cells 12–15.
  wave('wave');

  const EmoteId(this.wireName);

  /// The on-the-wire form. Never use [name] — it is only incidentally equal.
  final String wireName;

  /// Parse a wire value, or null if unknown.
  static EmoteId? parse(String wire) {
    for (final e in EmoteId.values) {
      if (e.wireName == wire) return e;
    }
    return null;
  }
}
