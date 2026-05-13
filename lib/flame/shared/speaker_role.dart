/// Identifies which in-game entity spoke a transcript received on the
/// `speech-transcript` LiveKit data channel.
///
/// Parsed at the data-channel boundary in [TechWorld._handleSpeechTranscript]
/// so the handler body can switch on a typed value rather than string literals.
enum SpeakerRole {
  dreamfinder('dreamfinder'),
  user('user');

  const SpeakerRole(this.wire);

  /// Wire-format identifier as it appears in the LiveKit payload.
  final String wire;

  /// Parse a wire string to its [SpeakerRole], returning null for unknown roles.
  static SpeakerRole? tryParse(String? wire) {
    if (wire == null) return null;
    for (final role in values) {
      if (role.wire == wire) return role;
    }
    return null;
  }
}
