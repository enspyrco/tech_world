import 'dart:async';
import 'dart:math';

import 'package:flame/components.dart' hide Timer;
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:tech_world/avatar/avatar_spec.dart';
import 'package:tech_world/bots/bot_config.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/emote.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world/livekit/agent_hello.dart';
import 'package:tech_world/livekit/data_channel.dart';
import 'package:tech_world/livekit/game_topics.dart';
import 'package:tech_world/livekit/livekit_topic.dart';
import 'package:tech_world/livekit/livekit_transport.dart';
import 'package:tech_world/timer/room_timer_message.dart';
import 'package:tech_world/livekit/platform_info.dart';

export 'package:tech_world/livekit/livekit_transport.dart';

/// Build SHA threaded in at build time via `--dart-define=APP_BUILD_SHA=...`.
/// CI sets this; local `flutter run` falls back to `'dev'`.
const String kAppBuildSha =
    String.fromEnvironment('APP_BUILD_SHA', defaultValue: 'dev');

/// App version reported in the agent-hello payload. Manually mirrored from
/// `pubspec.yaml`. Trading a build-time read for one source of duplication so
/// the field stays a plain `const` and is reachable in tests.
const String kAppVersion = '0.0.0+1';

/// LiveKit Dart SDK version. Manually mirrored from `pubspec.lock` (kept on
/// the published version line). One line to update on SDK bump — the
/// alternative (reading lock at build time) is a lot of plumbing for a
/// diagnostic field.
const String kLiveKitSdkVersion = '2.11.0';

final _log = Logger('LiveKitService');

/// Tech World's game protocol, layered on [LiveKitTransport] through its
/// public surface and its three hooks.
class LiveKitService extends LiveKitTransport {
  LiveKitService({
    required this.userId,
    required this.displayName,
    super.roomName = 'tech-world',
    super.tokenSource,
    @visibleForTesting void Function(String identity)? silenceParticipantAudio,
    @visibleForTesting void Function(String identity)? muteParticipantVolume,
    @visibleForTesting Iterable<String> Function()? remoteParticipantIdentities,
  }) : super(serverUrl: _serverUrl) {
    // Seams for unit-testing the DF-silence logic without faking the LiveKit
    // SDK. Default to the real server-side disable / the live `Room`'s
    // participant set. Assigned in the constructor body (not the initializer
    // list) because the default closures capture `this` — which lets the fields
    // be `late final` rather than nullable, encoding "set once, never null".
    _silenceParticipantAudio = silenceParticipantAudio ??
        ((identity) => setParticipantAudioEnabled(identity, false));
    _muteParticipantVolume = muteParticipantVolume ??
        ((identity) => setParticipantAudioVolume(identity, 0.0));
    _remoteParticipantIdentities = remoteParticipantIdentities ??
        (() => remoteParticipants.values.map((p) => p.identity));
  }

  final String userId;
  final String displayName;

  // LiveKit server URL
  static const _serverUrl = 'wss://livekit.imagineering.cc';

  /// Effect invoked to silence a participant's audio (server-side disable).
  ///
  /// Injectable so tests can observe which identities get silenced without a
  /// live LiveKit `Room`. Defaults to [setParticipantAudioEnabled]`(id, false)`.
  late final void Function(String identity) _silenceParticipantAudio;

  /// Effect invoked to hard-mute a participant's LOCAL playback volume.
  ///
  /// The server-side subscription disable ([_silenceParticipantAudio]) proved
  /// insufficient alone in production (2026-07-18: "DF will STILL not shut
  /// up" with a single clean DF in the room) — whatever the SFU does with the
  /// disable, a local volume of 0 on the playback element is not negotiable.
  /// Injectable for tests; defaults to [setParticipantAudioVolume]`(id, 0)`.
  late final void Function(String identity) _muteParticipantVolume;

  /// Source of the current remote participant identities.
  ///
  /// Injectable so [setDreamfinderSilenced]'s iteration is unit-testable
  /// without a live `Room`. Defaults to reading [remoteParticipants].
  late final Iterable<String> Function() _remoteParticipantIdentities;

  @override
  void onConnected() {
    dispatch([LiveKitConnected(roomName: roomName)]);

    // Fire-and-forget agent-hello so the bot can detect mis-configured
    // clients (e.g. adaptiveStream:true). Failure here MUST NOT bubble out
    // — diagnostics shouldn't break a successful connect.
    unawaited(_publishAgentHello());
  }

  @override
  void onConnectionLost(String? reason) {
    stopPositionHeartbeat();
    dispatch([LiveKitDisconnected(reason: reason)]);
  }

  @override
  void onRemoteTrackSubscribed({
    required String identity,
    required bool isAudioTrack,
  }) =>
      // Disable a freshly-subscribed DF audio track unconditionally; the
      // per-frame proximity gate re-enables it when the local player is in
      // range. Closes the deferred-component window where a fresh DF track
      // would be audible from anywhere before the gate's first tick.
      disableDreamfinderAudioOnSubscribe(
        isAudioTrack: isAudioTrack,
        identity: identity,
      );

  @override
  Future<void> disconnect() {
    stopPositionHeartbeat();
    return super.disconnect();
  }

  /// Player position updates received from other participants.
  Stream<PlayerPath> get positionReceived => receive(positionTopic);

  /// Position heartbeats from other participants.
  ///
  /// Heartbeats carry a single grid position with reliable delivery,
  /// correcting stale positions caused by dropped unreliable path updates.
  Stream<PositionHeartbeat> get positionHeartbeatReceived =>
      receive(positionHeartbeatTopic);

  /// Fires when a bot requests map info.
  ///
  /// Bots publish a `map-info-request` message when they connect and are
  /// ready to receive data. The client responds by sending the current map.
  Stream<void> get mapInfoRequested => receive(mapInfoRequestTopic);

  /// Map-switch notifications from other human players.
  ///
  /// Fires when another player switches maps, carrying the map ID so this
  /// client can load the same map. Messages whose payload `senderId` matches
  /// [userId] are excluded. That field is self-reported, so a peer can forge
  /// it, and nothing here excludes bots.
  Stream<String> get mapSwitchReceived => receive(mapSwitchTopic)
      .where((s) => s.senderId != userId)
      .map((s) => s.mapId);

  /// Avatar updates received from other participants. Own messages (matching
  /// [userId]) are excluded.
  Stream<AvatarUpdate> get avatarReceived =>
      receive(avatarTopic).where((u) => u.playerId != userId);

  /// Broadcast the local player's avatar to the room.
  Future<void> publishAvatar(AvatarSpec spec) =>
      send(avatarTopic, AvatarUpdate(playerId: userId, spec: spec));

  /// Broadcast a one-shot emote from the local player.
  ///
  /// No `playerId` in the payload: receivers attribute the emote to the
  /// transport-verified `senderId`, so a peer can only ever wave its own
  /// avatar.
  Future<void> publishEmote(EmoteId emote) => send(emoteTopic, emote);

  /// Whether Dreamfinder's audio is currently silenced for the local player.
  ///
  /// Server-side disable (via [setParticipantAudioEnabled]) — DF still
  /// speaks in the room, but the SFU stops forwarding their audio to us.
  /// State is session-scoped (resets on rejoin); applies to all current
  /// and future DF participants (including `agent-*` identities).
  final ValueNotifier<bool> dreamfinderSilenced = ValueNotifier<bool>(false);

  /// Toggle whether we receive Dreamfinder's audio.
  ///
  /// Silencing mutes every current DF participant immediately (server-side
  /// disable via [_silenceParticipantAudio]). UN-silencing does NOT force-enable
  /// here: the per-frame proximity gate ([BubbleManager._updateDreamfinderAudio])
  /// is the SOLE enabler, so DF only becomes audible again when you are actually
  /// in range. Force-enabling on un-silence re-enabled DF for every matching
  /// participant regardless of distance, leaving it audible from anywhere until
  /// the next near→far transition (the #594 / PR #485 leak).
  ///
  /// Iterates participants via the [_remoteParticipantIdentities] seam (live
  /// `Room` in production), so the disable-all / never-enable behaviour is
  /// unit-testable without a live SDK. Late-joining DF tracks are caught in
  /// [onRemoteTrackSubscribed].
  void setDreamfinderSilenced(bool silenced) {
    dreamfinderSilenced.value = silenced;
    if (!silenced) return;
    for (final identity in dreamfinderIdentities()) {
      // Per-identity isolation: one misbehaving participant (e.g. a zombie
      // record whose session is dead server-side, as on 2026-07-18) must not
      // abort silencing the rest — same invariant as the webhook's per-doc
      // sweep. Belt and braces per identity: server-side disable AND local
      // volume-0 (see _muteParticipantVolume for why both).
      try {
        _silenceParticipantAudio(identity);
        _muteParticipantVolume(identity);
      } catch (e) {
        _log.warning('setDreamfinderSilenced: failed for $identity: $e');
      }
    }
  }

  /// Every remote participant currently in the room that maps to Dreamfinder
  /// (`bot-dreamfinder` or the agents-SDK `agent-*` identities).
  ///
  /// There can be MORE THAN ONE at a time — agent respawns, a stale session
  /// surviving a server restart, or a second dispatch — so every consumer that
  /// gates DF audio must act on the full set, never a single cached identity
  /// (the single-slot assumption was half of the 2026-07-18 silence failure).
  Iterable<String> dreamfinderIdentities() =>
      _remoteParticipantIdentities().where(isDreamfinderIdentity);

  /// Disable a freshly-subscribed Dreamfinder audio track.
  ///
  /// Called from [onRemoteTrackSubscribed]. DF audio is proximity-
  /// gated: the per-frame gate ([BubbleManager._updateDreamfinderAudio]) is the
  /// SOLE enabler and only forwards DF audio when the local player is in range.
  /// But that gate doesn't run until DF's `DreamfinderComponent` exists, which
  /// is deferred to `gameReady` (it needs the path component). Between a DF
  /// audio track subscribing and the gate's first tick, an *unsilenced* fresh
  /// track would be audible from anywhere on the map — the deferred-component
  /// window flagged in the PR #485 cage match.
  ///
  /// Fix: disable DF audio on subscribe **unconditionally** (not just when
  /// silenced). The gate then enables it on the first near-frame. This is
  /// consistent with the gate's own initial state — its `_audioEnabledParticipants`
  /// set starts empty (it assumes the track begins disabled), so disabling on
  /// subscribe simply makes the SFU match that assumption; the gate's
  /// `shouldEnable = !hasAudio && near` transition still fires correctly when
  /// the player walks into range. (Previously this only disabled when already
  /// silenced, leaving the unsilenced-late-join window open.)
  ///
  /// Only fires for audio tracks ([isAudioTrack] true) from a Dreamfinder
  /// [identity]. Extracted from the inline handler so the branch logic is
  /// unit-testable via the `silenceParticipantAudio` seam without a live `Room`.
  @visibleForTesting
  void disableDreamfinderAudioOnSubscribe({
    required bool isAudioTrack,
    required String identity,
  }) {
    if (isAudioTrack && isDreamfinderIdentity(identity)) {
      _silenceParticipantAudio(identity);
      // While manually silenced, also zero the local volume of the fresh
      // track — if the server-side disable is ineffective (the 2026-07-18
      // failure), a new utterance track would otherwise play at default
      // volume. NOT done when unsilenced: the proximity fade layer owns the
      // volume then, and pre-zeroing would fight its change-detection cache.
      if (dreamfinderSilenced.value) {
        _muteParticipantVolume(identity);
      }
    }
  }

  /// Publish a one-shot agent-hello payload to the room.
  ///
  /// Carries the connect-time configuration (adaptiveStream, dynacast) plus
  /// SDK/build/version/platform metadata so the bot can warn when a client
  /// is connected with a known-bad setup. Reliable delivery — diagnostic
  /// shouldn't be dropped under packet loss.
  ///
  /// Pure-builder is in `agent_hello.dart`; this method is just the seam
  /// between the live `Room` and the bytes-to-send.
  Future<void> _publishAgentHello() async {
    try {
      final payload = buildAgentHelloPayload(
        clientSdkVersion: kLiveKitSdkVersion,
        buildSha: kAppBuildSha,
        appVersion: kAppVersion,
        adaptiveStream: kAdaptiveStream,
        dynacast: kDynacast,
        platform: agentHelloPlatform(),
        userAgent: agentHelloUserAgent(),
      );
      await send(agentHelloTopic, payload);
      _log.fine('Published agent_hello');
    } catch (e, st) {
      // Diagnostic — don't propagate. Log and move on.
      _log.warning('Failed to publish agent_hello', e, st);
    }
  }

  /// Publish the current map layout to the bot.
  ///
  /// Sent when the bot joins the room and whenever the map is switched, so the
  /// bot knows about barriers, terminal locations, and the spawn point.
  Future<void> publishMapInfo(GameMap map) =>
      send(mapInfoTopic, map, to: allBotIdentities.toList());

  /// Broadcast a map switch to other human players in the room.
  ///
  /// Includes [userId] so receivers can ignore their own echoes.
  Future<void> publishMapSwitch(String mapId) =>
      send(mapSwitchTopic, (senderId: userId, mapId: mapId));

  /// Publish the local player's position to other participants.
  Future<void> publishPosition({
    required List<Vector2> points,
    required List<Direction> directions,
  }) =>
      send(
        positionTopic,
        PlayerPath(
          playerId: userId,
          largeGridPoints: points,
          directions: directions,
        ),
      );

  /// Tell Dreamfinder whether the local player is within its range.
  ///
  /// Published on enter/exit transitions only (not every frame). The bot gates
  /// whose speech it responds to on this signal (near OR named).
  Future<void> publishDfProximity({required bool near}) =>
      send(dfProximityTopic, (playerId: userId, near: near));

  /// Broadcast a shared-timer start or cancel to every participant.
  ///
  /// The sender's own identity is stamped as `startedBy` so receivers (and the
  /// sender, via its own echo) know who triggered it.
  Future<void> publishRoomTimer(RoomTimerMessage message) =>
      send(roomTimerTopic, message);

  /// Shared-timer messages from the room.
  ///
  /// Unlike position/avatar streams this does NOT drop the local sender's own
  /// messages: the starter needs to see its own countdown, and a single
  /// authoritative path (everyone reacts to the broadcast) keeps every client —
  /// including the one that pressed the button — in lock-step.
  Stream<RoomTimerMessage> get roomTimerReceived => receive(roomTimerTopic);

  Timer? _heartbeatTimer;

  /// Last grid position sent via heartbeat, used to avoid duplicate sends.
  Point<int>? _lastHeartbeatPosition;

  /// Start the periodic position heartbeat.
  ///
  /// Sends the current grid position reliably every 2 seconds so that
  /// dropped unreliable path updates don't leave remote players frozen.
  /// Call [stopPositionHeartbeat] on disconnect or dispose.
  void startPositionHeartbeat(Point<int> Function() currentPosition) {
    stopPositionHeartbeat();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        if (!isConnected) return;
        final pos = currentPosition();
        // Skip if position hasn't changed since last heartbeat.
        if (_lastHeartbeatPosition == pos) return;
        _lastHeartbeatPosition = pos;
        send(
          positionHeartbeatTopic,
          PositionHeartbeat(playerId: userId, x: pos.x, y: pos.y),
        );
      },
    );
  }

  /// Stop the periodic position heartbeat.
  void stopPositionHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastHeartbeatPosition = null;
  }

  /// Publish a terminal-activity event to the bot.
  ///
  /// Notifies `bot-claude` when the local player opens or closes the code
  /// editor so the bot can track who is working on challenges and proactively
  /// offer help.
  Future<void> publishTerminalActivity({
    required TerminalAction action,
    String? challengeId,
    String? challengeTitle,
    String? challengeDescription,
    int? terminalX,
    int? terminalY,
  }) =>
      send(
        terminalActivityTopic,
        (
          action: action,
          playerId: userId,
          playerName: displayName,
          at: DateTime.now(),
          challengeId: challengeId,
          challengeTitle: challengeTitle,
          challengeDescription: challengeDescription,
          terminalX: terminalX,
          terminalY: terminalY,
        ),
        to: const ['bot-claude'],
      );

  /// Send a ping message to the bot and wait for pong response.
  ///
  /// Returns the pong response message if received within [timeout],
  /// or null if no response.
  Future<DataChannelMessage?> sendPing({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final pingId = DateTime.now().millisecondsSinceEpoch.toString();
    final pingMessage = {
      'type': 'ping',
      'id': pingId,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Listen for pong response with matching ID
    final pongFuture = dataReceived
        .where((msg) => msg.topic == LiveKitTopic.pong.wire)
        .where((msg) {
          final json = msg.json;
          return json != null &&
              json['originalMessage']?['id'] == pingId;
        })
        .first
        .timeout(timeout, onTimeout: () => throw TimeoutException('Ping timeout'));

    // Send the ping
    await publishJson(
      pingMessage,
      topic: LiveKitTopic.ping.wire,
      destinationIdentities: ['bot-claude'],
    );
    _log.fine('Sent ping with id: $pingId');

    try {
      final pong = await pongFuture;
      _log.fine('Received pong from ${pong.senderId}');
      return pong;
    } on TimeoutException {
      _log.info('Ping timed out');
      return null;
    }
  }
}
