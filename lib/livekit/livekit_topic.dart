/// Closed set of LiveKit data-channel topic strings used in Tech World.
///
/// Wire values are kebab-case identifiers preserved verbatim on the network.
/// Dart identifiers are camelCase so exhaustive `switch` catches every
/// consumer the moment a new topic is added.
///
/// Usage:
/// ```dart
/// await publishJson(msg, topic: LiveKitTopic.chat.wire);
/// dataReceived.where((m) => m.topic == LiveKitTopic.chat.wire);
/// ```
enum LiveKitTopic {
  // ── Position ──────────────────────────────────────────────────────────────
  position('position'),
  positionHeartbeat('position-heartbeat'),

  // ── Avatar ────────────────────────────────────────────────────────────────
  avatar('avatar'),

  // ── Map ───────────────────────────────────────────────────────────────────
  mapInfo('map-info'),
  mapInfoRequest('map-info-request'),
  mapSwitch('map-switch'),
  mapEdit('map-edit'),
  mapEditSync('map-edit-sync'),

  // ── Doors & terminals ─────────────────────────────────────────────────────
  doorUnlock('door-unlock'),
  terminalActivity('terminal-activity'),

  // ── Speech ────────────────────────────────────────────────────────────────
  speechTranscript('speech-transcript'),

  // ── Chat ──────────────────────────────────────────────────────────────────
  chat('chat'),
  chatResponse('chat-response'),
  dm('dm'),
  dmResponse('dm-response'),
  helpRequest('help-request'),
  helpResponse('help-response'),

  /// Acknowledgement that a mentioned player has *seen* a mention — broadcast
  /// by the named player's OWN client when it opens the chat panel. All clients
  /// stop that avatar's mention pulse on receiving it. Payload carries the
  /// stable `messageId` of the originating mention so a concurrent mention of
  /// the same player isn't cross-cancelled. The acked player's UID is the
  /// transport-verified `senderId`, never the payload — a peer can only ack
  /// its own mentions. Reliable. See `lib/flame/components/mention_beacon_component.dart`.
  mentionAck('mention-ack'),

  // ── Bot / Oracle ──────────────────────────────────────────────────────────
  oracleRequest('oracle-request'),
  oracleResponse('oracle-response'),

  /// Local player's proximity to Dreamfinder, published on enter/exit of DF's
  /// range. The client owns DF's on-screen position, so it is the authority on
  /// proximity; the bot gates whose speech DF responds to on this signal (near
  /// OR addressed-by-name). Payload `{near: bool}`, reliable.
  dfProximity('df-proximity'),

  // ── Infrastructure ────────────────────────────────────────────────────────
  infraHealth('infra-health'),
  infraHeal('infra-heal'),
  infraHealResult('infra-heal-result'),
  infraBoot('infra-boot'),

  // ── Connectivity ──────────────────────────────────────────────────────────
  ping('ping'),
  pong('pong'),

  // ── Shared room timer ─────────────────────────────────────────────────────
  /// A shared countdown timer that any participant can start or cancel; every
  /// client renders the same remaining time and plays an alarm at zero.
  ///
  /// Flutter-only — the bot does not participate. Payload is a [TimerAction]
  /// (`start` / `cancel`) plus, for `start`, the duration, start timestamp, and
  /// who started it (see `lib/timer/room_timer_message.dart`). Reliable, since
  /// a missed start/cancel desyncs the timer across clients.
  roomTimer('room-timer'),

  // ── Diagnostics ───────────────────────────────────────────────────────────
  /// One-shot self-report sent by every client immediately after connect.
  ///
  /// Surfaces the client's actual `ConnectOptions` (notably `adaptiveStream`
  /// and `dynacast`) plus SDK/build/version metadata so the bot can warn when
  /// a client connects with a configuration known to break Tech World video
  /// or audio forwarding. Reliable delivery.
  ///
  /// Wire string follows the kebab-case convention used by every other
  /// LiveKit topic in this enum (matches bot-side `AGENT_HELLO`).
  agentHello('agent-hello');

  const LiveKitTopic(this.wire);

  /// The wire-format string transmitted over the LiveKit data channel.
  final String wire;

  /// Parse a wire string to its [LiveKitTopic], returning null for unknown topics.
  static LiveKitTopic? tryParse(String wire) {
    for (final topic in values) {
      if (topic.wire == wire) return topic;
    }
    return null;
  }
}
