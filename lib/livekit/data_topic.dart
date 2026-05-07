/// Typed identifiers for LiveKit data-channel topics.
///
/// Replaces scattered string literals with a single exhaustive enum.
/// Wire names are preserved verbatim for protocol compatibility.
///
/// Usage at a **producer** site:
/// ```dart
/// await publishJson(message, topic: DataTopic.chat.wireName);
/// ```
///
/// Usage at a **consumer** site (filter):
/// ```dart
/// dataReceived.where((msg) => msg.topic == DataTopic.position.wireName)
/// ```
///
/// Usage at a **consumer** site (switch dispatch):
/// ```dart
/// final topic = DataTopic.parse(msg.topic);
/// if (topic == DataTopic.chat) { ... }
/// ```
enum DataTopic {
  // ── Player presence ────────────────────────────────────────────────────────
  position('position'),
  avatar('avatar'),

  // ── Chat ───────────────────────────────────────────────────────────────────
  chat('chat'),
  chatResponse('chat-response'),
  dm('dm'),
  dmResponse('dm-response'),
  helpRequest('help-request'),
  helpResponse('help-response'),

  // ── Map & Navigation ───────────────────────────────────────────────────────
  mapInfo('map-info'),
  mapInfoRequest('map-info-request'),
  mapEdit('map-edit'),
  mapEditSync('map-edit-sync'),

  // ── Game events ────────────────────────────────────────────────────────────
  terminalActivity('terminal-activity'),
  doorUnlock('door-unlock'),
  speechTranscript('speech-transcript'),

  // ── Connectivity ──────────────────────────────────────────────────────────
  ping('ping'),
  pong('pong'),

  // ── Infrastructure ────────────────────────────────────────────────────────
  infraHealth('infra-health'),
  infraHeal('infra-heal'),
  infraHealResult('infra-heal-result'),
  infraBoot('infra-boot'),

  // ── Oracle (bot-mediated generation) ─────────────────────────────────────
  oracleRequest('oracle-request'),
  oracleResponse('oracle-response'),

  // ── Dreamfinder avatar bridge ─────────────────────────────────────────────
  dreamfinderAudio('dreamfinder-audio'),
  dreamfinderMood('dreamfinder-mood'),
  ;

  const DataTopic(this.wireName);

  /// The exact string sent over the LiveKit data channel.
  final String wireName;

  /// Parse a wire string into a [DataTopic], or return `null` if unknown.
  static DataTopic? parse(String? wire) {
    if (wire == null) return null;
    for (final topic in values) {
      if (topic.wireName == wire) return topic;
    }
    return null;
  }
}
