import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flame/components.dart' hide Timer;
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:logging/logging.dart';
import 'package:tech_world/avatar/avatar.dart';
import 'package:tech_world/avatar/predefined_avatars.dart';
import 'package:tech_world/bots/bot_config.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world/livekit/agent_hello.dart';
import 'package:tech_world/livekit/livekit_topic.dart';
import 'package:tech_world/timer/room_timer_message.dart';
import 'package:tech_world/livekit/platform_info.dart';
import 'package:tech_world/livekit/set_track_volume.dart';

/// Protocol version stamped on every outgoing LiveKit data-channel message.
/// Bump when a wire-format change requires receivers to upgrade.
const kProtocolVersion = 1;

/// Whether this client requests adaptive streaming from the SFU.
///
/// MUST stay `false` for Tech World: adaptive streaming requires LiveKit's
/// `VideoTrackRenderer` widget to signal demand. We render LiveKit frames
/// through the Flame canvas, which never signals, so the SFU stops
/// forwarding video (and can pause audio too).
///
/// Read by both the `RoomOptions` constructor and the `agent_hello`
/// diagnostic so the value is reported truthfully if it ever changes.
const bool kAdaptiveStream = false;

/// Whether this client requests dynacast from the SFU.
///
/// Kept off for the same canvas-rendering reasons as [kAdaptiveStream].
const bool kDynacast = false;

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
const String kLiveKitSdkVersion = '2.7.0';

/// Result of a [LiveKitService.connect] attempt.
enum ConnectionResult {
  /// Successfully connected to the LiveKit room.
  connected,

  /// Already connected or connecting — no action taken.
  alreadyConnected,

  /// Token retrieval failed due to a network error (retryable).
  tokenNetworkError,

  /// Token retrieval failed due to an authentication error (re-sign-in needed).
  tokenAuthError,

  /// Token retrieval failed for an unknown reason.
  tokenUnknownError,

  /// Room connection failed after token was obtained.
  roomFailed,
}

/// Internal connection state for [LiveKitService].
///
/// Replaces the former `_isConnecting` / `_isConnected` boolean pair, which
/// admitted the illegal `(true, true)` combination.
enum _ConnectionState { disconnected, connecting, connected }

final _log = Logger('LiveKitService');

/// Service that manages LiveKit room connection and participant tracking.
///
/// This service:
/// - Connects to LiveKit room automatically
/// - Tracks remote participants
/// - Exposes streams for participant join/leave events
/// - Manages local audio/video tracks
class LiveKitService {
  LiveKitService({
    required this.userId,
    required this.displayName,
    this.roomName = 'tech-world',
    @visibleForTesting Future<String?> Function()? tokenRetriever,
    @visibleForTesting void Function(String identity)? silenceParticipantAudio,
  })  : _tokenRetriever = tokenRetriever,
        // Seam for unit-testing the silence-on-subscribe logic without faking
        // the LiveKit SDK. Defaults to the real server-side audio disable
        // (see [applyDreamfinderSilenceOnSubscribe]). The late-init dance is
        // because the default closure captures `this`.
        _silenceParticipantAudio = silenceParticipantAudio {
    _silenceParticipantAudio ??=
        (identity) => setParticipantAudioEnabled(identity, false);
  }

  final String userId;
  final String displayName;
  final String roomName;
  final Future<String?> Function()? _tokenRetriever;

  /// Effect invoked to silence a participant's audio (server-side disable).
  ///
  /// Injectable so tests can observe which identities get silenced without a
  /// live LiveKit `Room`. Defaults to [setParticipantAudioEnabled]`(id, false)`.
  void Function(String identity)? _silenceParticipantAudio;

  // LiveKit server URL
  static const _serverUrl = 'wss://livekit.imagineering.cc';

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  _ConnectionState _connectionState = _ConnectionState.disconnected;

  /// Identities of participants who were speaking on the last
  /// [ActiveSpeakersChangedEvent]. Diffed against the current set to
  /// emit (participant, false) for speakers who just stopped — LiveKit
  /// doesn't fire stop events directly, only "currently speaking" sets.
  Set<String> _previousSpeakerIds = const {};

  // Stream controllers for participant events
  final _participantJoinedController =
      StreamController<RemoteParticipant>.broadcast();
  final _participantLeftController =
      StreamController<RemoteParticipant>.broadcast();
  final _speakingChangedController =
      StreamController<(Participant, bool)>.broadcast();
  final _trackSubscribedController =
      StreamController<(Participant, VideoTrack)>.broadcast();
  final _localTrackPublishedController =
      StreamController<LocalTrackPublication>.broadcast();
  final _trackUnsubscribedController =
      StreamController<(Participant, VideoTrack)>.broadcast();
  final _dataReceivedController =
      StreamController<DataChannelMessage>.broadcast();
  final _connectionLostController = StreamController<String?>.broadcast();

  /// Stream of participants that joined the room
  Stream<RemoteParticipant> get participantJoined =>
      _participantJoinedController.stream;

  /// Stream of participants that left the room
  Stream<RemoteParticipant> get participantLeft =>
      _participantLeftController.stream;

  /// Stream of speaking state changes (participant, isSpeaking)
  Stream<(Participant, bool)> get speakingChanged =>
      _speakingChangedController.stream;

  /// Stream of video track subscription events (participant, videoTrack)
  Stream<(Participant, VideoTrack)> get trackSubscribed =>
      _trackSubscribedController.stream;

  /// Stream of video track unsubscription events (participant, videoTrack)
  Stream<(Participant, VideoTrack)> get trackUnsubscribed =>
      _trackUnsubscribedController.stream;

  /// Stream of local track publication events (fires when camera/mic is published)
  Stream<LocalTrackPublication> get localTrackPublished =>
      _localTrackPublishedController.stream;

  /// Stream of data channel messages received from other participants
  Stream<DataChannelMessage> get dataReceived => _dataReceivedController.stream;

  /// Emits the disconnect reason when the room connection is lost unexpectedly.
  ///
  /// Consumers (e.g. `main.dart`) can listen to show a reconnection banner or
  /// trigger cleanup. This does NOT fire on intentional [disconnect] calls.
  Stream<String?> get connectionLost => _connectionLostController.stream;

  /// Stream of player position updates received from other participants.
  ///
  /// Filters dataReceived for 'position' topic and parses into PlayerPath.
  Stream<PlayerPath> get positionReceived => dataReceived
      .where((msg) => msg.topic == LiveKitTopic.position.wire)
      .map((msg) {
        final json = msg.json;
        if (json == null) return null;
        return _parsePlayerPath(json);
      })
      .where((path) => path != null)
      .cast<PlayerPath>();

  /// Stream of position heartbeat messages from other participants.
  ///
  /// Heartbeats carry a single grid position with reliable delivery,
  /// correcting stale positions caused by dropped unreliable path updates.
  Stream<PositionHeartbeat> get positionHeartbeatReceived => dataReceived
      .where((msg) => msg.topic == LiveKitTopic.positionHeartbeat.wire)
      .map((msg) {
        final json = msg.json;
        if (json == null) return null;
        return PositionHeartbeat.tryParse(json);
      })
      .where((hb) => hb != null)
      .cast<PositionHeartbeat>();

  /// Stream that fires when a bot requests map info.
  ///
  /// Bots publish a `map-info-request` message when they connect and are
  /// ready to receive data. The client responds by sending the current map.
  Stream<void> get mapInfoRequested =>
      dataReceived.where((msg) => msg.topic == LiveKitTopic.mapInfoRequest.wire);

  /// Stream of map-switch notifications from other human players.
  ///
  /// Fires when another player switches maps, carrying the map ID so this
  /// client can load the same map. Own messages (matching [userId]) and
  /// messages from bots are excluded.
  Stream<String> get mapSwitchReceived => dataReceived
      .where((msg) => msg.topic == LiveKitTopic.mapSwitch.wire)
      .map((msg) {
        if (msg.json case {'senderId': String senderId, 'mapId': String mapId}
            when senderId != userId) {
          return mapId;
        }
        return null;
      })
      .where((mapId) => mapId != null)
      .cast<String>();

  /// Stream of avatar updates received from other participants.
  ///
  /// Filters [dataReceived] for the `avatar` topic and parses into
  /// [AvatarUpdate]. Own messages (matching [userId]) are excluded.
  Stream<AvatarUpdate> get avatarReceived => dataReceived
      .where((msg) => msg.topic == LiveKitTopic.avatar.wire)
      .map((msg) {
        final json = msg.json;
        if (json == null) return null;
        final update = AvatarUpdate.tryParse(json);
        // Ignore our own avatar broadcasts
        if (update != null && update.playerId == userId) return null;
        return update;
      })
      .where((update) => update != null)
      .cast<AvatarUpdate>();

  /// Broadcast the local player's avatar to the room.
  ///
  /// Uses reliable delivery so late-joiners' catch-up works correctly.
  Future<void> publishAvatar(Avatar avatar) async {
    final message = {
      'playerId': userId,
      'avatarId': avatar.id,
      'spriteAsset': avatar.spriteAsset,
    };
    await publishJson(message, topic: LiveKitTopic.avatar.wire);
  }

  PlayerPath? _parsePlayerPath(Map<String, dynamic> json) {
    try {
      final playerId = json['playerId'] as String?;
      final pointsJson = json['points'] as List<dynamic>?;
      final directionsJson = json['directions'] as List<dynamic>?;

      if (playerId == null || pointsJson == null || directionsJson == null) {
        return null;
      }

      // Clamp at parse boundary — a malformed or hostile peer could
      // otherwise push huge coordinates into Flame movement/rendering.
      // 2× world bounds: path interpolation can briefly overshoot.
      // Units: world-space pixels.
      final maxCoord = (gridSize * gridSquareSize * 2).toDouble();
      final points = pointsJson
          .map((p) => Vector2(
                (p['x'] as num).toDouble().clamp(-maxCoord, maxCoord),
                (p['y'] as num).toDouble().clamp(-maxCoord, maxCoord),
              ))
          .toList();

      final directions = directionsJson
          .map((d) => Direction.values.asNameMap()[d] ?? Direction.none)
          .toList();

      return PlayerPath(
        playerId: playerId,
        largeGridPoints: points,
        directions: directions,
      );
    } catch (e) {
      _log.warning('Failed to parse player path', e);
      return null;
    }
  }

  /// Current room instance
  Room? get room => _room;

  /// Whether connected to LiveKit
  bool get isConnected => _connectionState == _ConnectionState.connected;

  /// Local participant
  LocalParticipant? get localParticipant => _room?.localParticipant;

  /// All remote participants
  Map<String, RemoteParticipant> get remoteParticipants =>
      _room?.remoteParticipants ?? {};

  /// Connect to the LiveKit room.
  ///
  /// Returns a [ConnectionResult] indicating success or the specific failure
  /// reason, so the UI can show actionable messages.
  Future<ConnectionResult> connect() async {
    if (_connectionState != _ConnectionState.disconnected) {
      _log.info('Already connecting or connected');
      return ConnectionResult.alreadyConnected;
    }

    _connectionState = _ConnectionState.connecting;
    _log.info('Connecting to LiveKit...');

    try {
      // Get token from Firebase Function
      final tokenResult = await _retrieveToken();
      if (tokenResult.token == null) {
        _log.warning('Failed to retrieve token');
        _connectionState = _ConnectionState.disconnected;
        return tokenResult.connectionResult;
      }

      // Create room with options
      _room = Room(
        roomOptions: const RoomOptions(
          // Adaptive streaming requires LiveKit's VideoTrackRenderer widget
          // to signal "I'm rendering this track." We render via Flame canvas,
          // so the SDK never signals demand and the SFU stops forwarding.
          adaptiveStream: kAdaptiveStream,
          dynacast: kDynacast,
          defaultCameraCaptureOptions: CameraCaptureOptions(
            maxFrameRate: 30,
            params: VideoParametersPresets.h540_169,
          ),
          defaultVideoPublishOptions: VideoPublishOptions(
            simulcast: false,
            videoCodec: 'vp8',
          ),
          defaultAudioCaptureOptions: AudioCaptureOptions(
            noiseSuppression: true,
            echoCancellation: true,
            autoGainControl: true,
          ),
        ),
      );

      // Set up event listener
      _listener = _room!.createListener();
      _setupListeners();

      // Connect to room — explicit RTCConfiguration ensures TURN relay
      // candidates are tried alongside direct UDP.
      await _room!.connect(
        _serverUrl,
        tokenResult.token!,
        connectOptions: const ConnectOptions(
          rtcConfiguration: RTCConfiguration(
            iceTransportPolicy: RTCIceTransportPolicy.all,
          ),
        ),
        fastConnectOptions: FastConnectOptions(
          microphone: const TrackOption(enabled: false),
          camera: const TrackOption(enabled: false),
        ),
      );

      _connectionState = _ConnectionState.connected;
      _log.info('Connected to LiveKit room "$roomName"');
      dispatch([LiveKitConnected(roomName: roomName)]);

      // Fire-and-forget agent-hello so the bot can detect mis-configured
      // clients (e.g. adaptiveStream:true). Failure here MUST NOT bubble out
      // — diagnostics shouldn't break a successful connect.
      unawaited(_publishAgentHello());

      // Notify about existing participants
      for (final participant in _room!.remoteParticipants.values) {
        _participantJoinedController.add(participant);
      }

      return ConnectionResult.connected;
    } catch (e) {
      _log.severe('Connection failed', e);
      // Clean up dangling _room and _listener created before the failure.
      // Each cleanup is wrapped individually so one failure doesn't prevent
      // the other from running.
      try {
        await _listener?.dispose();
      } catch (cleanupError) {
        _log.warning('Listener cleanup failed', cleanupError);
      }
      _listener = null;
      try {
        await _room?.disconnect();
      } catch (cleanupError) {
        _log.warning('Room cleanup failed', cleanupError);
      }
      _room = null;
      _connectionState = _ConnectionState.disconnected;
      return ConnectionResult.roomFailed;
    }
  }

  /// Disconnect from the LiveKit room.
  ///
  /// Also handles the `connecting` state so that a disconnect request during
  /// an in-flight [connect] call tears down resources correctly.
  Future<void> disconnect() async {
    if (_connectionState == _ConnectionState.disconnected || _room == null) {
      return;
    }

    _log.info('Disconnecting from LiveKit...');
    stopPositionHeartbeat();

    await _room!.disconnect();
    await _listener?.dispose();
    _listener = null;
    _room = null;
    _connectionState = _ConnectionState.disconnected;

    _log.info('Disconnected');
  }

  /// Enable/disable local camera
  Future<void> setCameraEnabled(bool enabled) async {
    if (_room?.localParticipant == null) return;
    try {
      await _room!.localParticipant!.setCameraEnabled(enabled);
      _log.info('Camera ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      _log.warning('Failed to set camera', e);
    }
  }

  /// Enable/disable local microphone
  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (_room?.localParticipant == null) return;
    try {
      await _room!.localParticipant!.setMicrophoneEnabled(enabled);
      _log.info('Microphone ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      _log.warning('Failed to set microphone', e);
    }
  }

  /// Enable/disable local screen share.
  ///
  /// On web, the browser's built-in screen picker is shown automatically.
  /// On desktop, LiveKit's `setScreenShareEnabled` triggers the native picker.
  ///
  /// Rethrows exceptions so callers can update UI state correctly on failure.
  Future<void> setScreenShareEnabled(bool enabled,
      {ScreenShareCaptureOptions? options}) async {
    if (_room?.localParticipant == null) return;
    try {
      await _room!.localParticipant!.setScreenShareEnabled(
        enabled,
        screenShareCaptureOptions: options,
      );
      _log.info('Screen share ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      _log.warning('Failed to set screen share', e);
      rethrow;
    }
  }

  /// Whether the local participant is currently sharing their screen.
  bool get isScreenShareEnabled =>
      _room?.localParticipant?.isScreenShareEnabled() ?? false;

  /// Enable or disable audio playback for a remote participant.
  ///
  /// Uses [RemoteTrackPublication.enable]/[RemoteTrackPublication.disable] to
  /// tell the server we want/don't want this participant's audio track.
  /// Used for proximity-based audio: mute players who are too far away.
  void setParticipantAudioEnabled(String identity, bool enabled) {
    final participant = _room?.remoteParticipants[identity];
    if (participant == null) return;

    for (final publication in participant.audioTrackPublications) {
      if (enabled) {
        publication.enable();
      } else {
        publication.disable();
      }
    }
  }

  /// Set the playback volume (0.0–1.0) for a remote participant's audio.
  ///
  /// Used by the proximity layer to fade voices by distance instead of hard
  /// cutting. Distinct from [setParticipantAudioEnabled], which is a server-side
  /// subscription toggle (binary forward/don't-forward) — this is a local
  /// playback gain applied while the track is subscribed. Web-only effect today
  /// (see [setTrackVolume]); a safe no-op on other platforms.
  ///
  /// Returns true iff the volume actually landed on at least one track — i.e.
  /// [setTrackVolume] reported it wrote the value, not merely that a
  /// [RemoteTrackPublication.track] exists. The track can be subscribed a frame
  /// or two before its web audio element is appended, so this distinction is
  /// what lets the caller retry instead of caching a silent no-op (which would
  /// strand the late track at default volume).
  bool setParticipantAudioVolume(String identity, double volume) {
    final participant = _room?.remoteParticipants[identity];
    if (participant == null) return false;

    var applied = false;
    for (final publication in participant.audioTrackPublications) {
      final track = publication.track;
      if (track != null && setTrackVolume(track.getCid(), volume)) {
        applied = true;
      }
    }
    return applied;
  }

  /// Whether Dreamfinder's audio is currently silenced for the local player.
  ///
  /// Server-side disable (via [setParticipantAudioEnabled]) — DF still
  /// speaks in the room, but the SFU stops forwarding their audio to us.
  /// State is session-scoped (resets on rejoin); applies to all current
  /// and future DF participants (including `agent-*` identities).
  final ValueNotifier<bool> dreamfinderSilenced = ValueNotifier<bool>(false);

  /// Toggle whether we receive Dreamfinder's audio.
  ///
  /// Iterates current remote participants and disables/enables audio on
  /// any matching [isDreamfinderIdentity]. Late-joining DF tracks are
  /// caught in the [TrackSubscribedEvent] handler.
  void setDreamfinderSilenced(bool silenced) {
    dreamfinderSilenced.value = silenced;
    final room = _room;
    if (room == null) return;
    // Silencing mutes DF immediately. UN-silencing does NOT force-enable here:
    // the per-frame proximity gate (BubbleManager._updateDreamfinderAudio) is
    // the SOLE enabler, so DF only becomes audible again when you are actually
    // in range. Force-enabling on un-silence re-enabled DF for every matching
    // participant regardless of distance, leaving it audible from anywhere
    // until the next near→far transition (the #594 / PR #485 leak).
    if (!silenced) return;
    for (final participant in room.remoteParticipants.values) {
      if (isDreamfinderIdentity(participant.identity)) {
        setParticipantAudioEnabled(participant.identity, false);
      }
    }
  }

  /// Silence a freshly-subscribed track if it belongs to a silenced
  /// Dreamfinder.
  ///
  /// Called from the [TrackSubscribedEvent] handler. A DF audio track that
  /// arrives *after* the local player has toggled silence (DF joining late, or
  /// republishing its track) would otherwise leak audio — [setDreamfinderSilenced]
  /// only iterates the participants present at toggle time. Disabling on
  /// subscribe closes that gap.
  ///
  /// Only fires for audio tracks ([isAudioTrack] true) from a Dreamfinder
  /// [identity] while [dreamfinderSilenced] is set. Extracted from the inline
  /// handler so the branch logic is unit-testable via the
  /// `silenceParticipantAudio` seam without a live `Room`.
  @visibleForTesting
  void applyDreamfinderSilenceOnSubscribe({
    required bool isAudioTrack,
    required String identity,
  }) {
    if (isAudioTrack &&
        dreamfinderSilenced.value &&
        isDreamfinderIdentity(identity)) {
      _silenceParticipantAudio!(identity);
    }
  }

  /// Get a participant by their identity (userId)
  Participant? getParticipant(String identity) {
    if (_room == null) return null;

    if (_room!.localParticipant?.identity == identity) {
      return _room!.localParticipant;
    }

    return _room!.remoteParticipants[identity];
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
      final bytes = encodeAgentHelloPayload(payload);
      await publishData(
        bytes,
        reliable: true,
        topic: LiveKitTopic.agentHello.wire,
      );
      _log.fine('Published agent_hello');
    } catch (e, st) {
      // Diagnostic — don't propagate. Log and move on.
      _log.warning('Failed to publish agent_hello', e, st);
    }
  }

  /// Publish data to the room via data channel.
  ///
  /// [data] is the raw bytes to send.
  /// [reliable] when true, uses reliable (ordered) delivery (default: true).
  /// [destinationIdentities] when provided, sends only to specific participants.
  /// [topic] optional topic string to categorize the message.
  Future<void> publishData(
    List<int> data, {
    bool reliable = true,
    List<String>? destinationIdentities,
    String? topic,
  }) async {
    if (_room?.localParticipant == null) {
      _log.warning('Cannot publish data - not connected');
      return;
    }

    await _room!.localParticipant!.publishData(
      data,
      reliable: reliable,
      destinationIdentities: destinationIdentities,
      topic: topic,
    );
    _log.fine('Published data, topic: $topic');
  }

  /// Publish a JSON message to the room via data channel.
  ///
  /// Convenience method that encodes [json] as UTF-8 bytes.
  Future<void> publishJson(
    Map<String, dynamic> json, {
    bool reliable = true,
    List<String>? destinationIdentities,
    String? topic,
  }) async {
    final versioned = {'v': kProtocolVersion, ...json};
    final data = utf8.encode(jsonEncode(versioned));
    await publishData(
      data,
      reliable: reliable,
      destinationIdentities: destinationIdentities,
      topic: topic,
    );
  }

  /// Publish the current map layout to the bot.
  ///
  /// Sent when the bot joins the room and whenever the map is switched, so the
  /// bot knows about barriers, terminal locations, and the spawn point.
  Future<void> publishMapInfo(GameMap map) async {
    final message = {
      'mapId': map.id,
      'barriers': map.barriers.map((p) => [p.x, p.y]).toList(),
      'terminals': map.terminals.map((p) => [p.x, p.y]).toList(),
      'spawnPoint': [map.spawnPoint.x, map.spawnPoint.y],
      'gridSize': gridSize,
      'cellSize': gridSquareSize,
    };
    await publishJson(
      message,
      topic: LiveKitTopic.mapInfo.wire,
      destinationIdentities: allBotIdentities.toList(),
    );
  }

  /// Broadcast a map switch to other human players in the room.
  ///
  /// Includes [userId] so receivers can ignore their own echoes. Uses reliable
  /// delivery because a missed map-switch leaves players on different worlds.
  Future<void> publishMapSwitch(String mapId) async {
    final message = {
      'senderId': userId,
      'mapId': mapId,
    };
    await publishJson(message, topic: LiveKitTopic.mapSwitch.wire);
  }

  /// Publish the local player's position to other participants.
  ///
  /// Uses unreliable delivery for lower latency since positions update frequently.
  Future<void> publishPosition({
    required List<Vector2> points,
    required List<Direction> directions,
  }) async {
    final message = {
      'playerId': userId,
      'points': points.map((p) => {'x': p.x, 'y': p.y}).toList(),
      'directions': directions.map((d) => d.name).toList(),
    };

    await publishJson(
      message,
      topic: LiveKitTopic.position.wire,
      reliable: false, // Positions can use unreliable for lower latency
    );
  }

  /// Tell Dreamfinder whether the local player is within its range.
  ///
  /// Published on enter/exit transitions only (not every frame). Reliable,
  /// because a missed enter would leave DF unable to hear a nearby player and a
  /// missed exit would leave DF listening to someone who walked away. The bot
  /// gates whose speech it responds to on this signal (near OR named).
  Future<void> publishDfProximity({required bool near}) async {
    await publishJson(
      {'playerId': userId, 'near': near},
      topic: LiveKitTopic.dfProximity.wire,
      reliable: true,
    );
  }

  /// Broadcast a shared-timer start or cancel to every participant.
  ///
  /// Reliable: a missed start or cancel desyncs the timer across clients. The
  /// sender's own identity is stamped as `startedBy` so receivers (and the
  /// sender, via its own echo) know who triggered it.
  Future<void> publishRoomTimer(RoomTimerMessage message) async {
    await publishJson(
      message.toJson(),
      topic: LiveKitTopic.roomTimer.wire,
      reliable: true,
    );
  }

  /// Stream of shared-timer messages from the room.
  ///
  /// Filters [dataReceived] for the `room-timer` topic and parses into a typed
  /// [RoomTimerMessage]. Unlike position/avatar streams this does NOT drop the
  /// local sender's own messages: the starter needs to see its own countdown,
  /// and a single authoritative path (everyone reacts to the broadcast) keeps
  /// every client — including the one that pressed the button — in lock-step.
  Stream<RoomTimerMessage> get roomTimerReceived => dataReceived
      .where((msg) => msg.topic == LiveKitTopic.roomTimer.wire)
      .map((msg) => RoomTimerMessage.tryParse(msg.json))
      .where((m) => m != null)
      .cast<RoomTimerMessage>();

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
        if (_connectionState != _ConnectionState.connected) return;
        final pos = currentPosition();
        // Skip if position hasn't changed since last heartbeat.
        if (_lastHeartbeatPosition == pos) return;
        _lastHeartbeatPosition = pos;
        publishJson(
          {
            'playerId': userId,
            'x': pos.x,
            'y': pos.y,
            'type': 'heartbeat',
          },
          topic: LiveKitTopic.positionHeartbeat.wire,
          reliable: true,
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
    required String action,
    String? challengeId,
    String? challengeTitle,
    String? challengeDescription,
    int? terminalX,
    int? terminalY,
  }) async {
    final message = <String, dynamic>{
      'type': 'terminal-activity',
      'action': action,
      'playerId': userId,
      'playerName': displayName,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (challengeId != null) message['challengeId'] = challengeId;
    if (challengeTitle != null) message['challengeTitle'] = challengeTitle;
    if (challengeDescription != null) {
      message['challengeDescription'] = challengeDescription;
    }
    if (terminalX != null) message['terminalX'] = terminalX;
    if (terminalY != null) message['terminalY'] = terminalY;

    await publishJson(
      message,
      topic: LiveKitTopic.terminalActivity.wire,
      destinationIdentities: const ['bot-claude'],
    );
  }

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

  Future<_TokenResult> _retrieveToken() async {
    if (_tokenRetriever != null) {
      final token = await _tokenRetriever();
      return token != null
          ? _TokenResult.success(token)
          : const _TokenResult.failure(ConnectionResult.tokenUnknownError);
    }
    try {
      _log.info('Retrieving token for room "$roomName"');
      final result = await FirebaseFunctions.instance
          .httpsCallable('retrieveLiveKitToken')
          .call({'roomName': roomName});
      final token = result.data as String?;
      return token != null
          ? _TokenResult.success(token)
          : const _TokenResult.failure(ConnectionResult.tokenUnknownError);
    } on FirebaseFunctionsException catch (e) {
      _log.warning('Token retrieval failed', e);
      if (e.code == 'unauthenticated' || e.code == 'permission-denied') {
        return const _TokenResult.failure(ConnectionResult.tokenAuthError);
      }
      return const _TokenResult.failure(ConnectionResult.tokenNetworkError);
    } catch (e) {
      // Generic catch handles timeouts, network errors, and other transient
      // failures not covered by FirebaseFunctionsException above.
      _log.warning('Token retrieval failed', e);
      return const _TokenResult.failure(ConnectionResult.tokenNetworkError);
    }
  }

  void _setupListeners() {
    _listener
      ?..on<ParticipantConnectedEvent>((event) {
        _log.info('Participant joined: ${event.participant.identity}');
        _participantJoinedController.add(event.participant);
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        _log.info('Participant left: ${event.participant.identity}');
        _participantLeftController.add(event.participant);
      })
      ..on<TrackSubscribedEvent>((event) {
        _log.fine(
            'Track subscribed: ${event.participant.identity} - ${event.track.kind}');
        // Emit video track subscription events
        if (event.track is VideoTrack) {
          _trackSubscribedController
              .add((event.participant, event.track as VideoTrack));
        }
        // Apply Dreamfinder silence to a freshly-subscribed DF audio track.
        // Without this, toggling silence before DF joins (or while DF is
        // republishing) would leave the new track audible.
        applyDreamfinderSilenceOnSubscribe(
          isAudioTrack: event.track is AudioTrack,
          identity: event.participant.identity,
        );
      })
      ..on<TrackUnsubscribedEvent>((event) {
        _log.fine(
            'Track unsubscribed: ${event.participant.identity}');
        if (event.track is VideoTrack) {
          _trackUnsubscribedController
              .add((event.participant, event.track as VideoTrack));
        }
      })
      ..on<ActiveSpeakersChangedEvent>((event) {
        // Emit (participant, true) for the current set, and (participant, false)
        // for anyone who was speaking last tick but isn't now. Without the
        // diff, speaking indicators / audio UI get stuck active after the
        // first speech event — see project memory `feedback_speakers_diff.md`.
        final currentIds = event.speakers.map((s) => s.identity).toSet();
        for (final speaker in event.speakers) {
          _speakingChangedController.add((speaker, true));
        }
        for (final prevId in _previousSpeakerIds.difference(currentIds)) {
          final participant = getParticipant(prevId);
          if (participant != null) {
            _speakingChangedController.add((participant, false));
          }
        }
        _previousSpeakerIds = currentIds;
      })
      ..on<RoomDisconnectedEvent>((event) {
        _log.warning('Room disconnected: ${event.reason}');
        _connectionState = _ConnectionState.disconnected;
        stopPositionHeartbeat();
        // Clean up resources left dangling by the unexpected disconnect.
        // Note: _listener.dispose() is intentionally not awaited here — this
        // is a synchronous event callback and the dispose is fire-and-forget.
        try {
          _listener?.dispose();
        } catch (e) {
          _log.warning('Listener cleanup failed', e);
        }
        _listener = null;
        _room = null;
        // Notify consumers so they can show a banner / attempt reconnect.
        _connectionLostController.add(event.reason?.name);
        dispatch([LiveKitDisconnected(reason: event.reason?.name)]);
      })
      ..on<LocalTrackPublishedEvent>((event) {
        _log.fine(
            'Local track published: ${event.publication.kind}');
        _localTrackPublishedController.add(event.publication);
      })
      ..on<DataReceivedEvent>((event) {
        _log.fine(
            'Data received from: ${event.participant?.identity}, topic: ${event.topic}');
        _dataReceivedController.add(DataChannelMessage(
          senderId: event.participant?.identity,
          topic: event.topic,
          data: event.data,
        ));
      });
  }

  /// Dispose of resources.
  ///
  /// Awaits [disconnect] to ensure the room is fully torn down before closing
  /// stream controllers.
  Future<void> dispose() async {
    await disconnect();
    _participantJoinedController.close();
    _participantLeftController.close();
    _speakingChangedController.close();
    _trackSubscribedController.close();
    _trackUnsubscribedController.close();
    _localTrackPublishedController.close();
    _dataReceivedController.close();
    _connectionLostController.close();
  }
}

/// Internal result from [LiveKitService._retrieveToken].
class _TokenResult {
  const _TokenResult.success(String this.token)
      : connectionResult = ConnectionResult.connected;
  const _TokenResult.failure(this.connectionResult) : token = null;

  final String? token;

  /// The [ConnectionResult] describing the outcome — [ConnectionResult.connected]
  /// on success, or a specific failure reason otherwise.
  final ConnectionResult connectionResult;
}

/// A message received via LiveKit data channel.
class DataChannelMessage {
  DataChannelMessage({
    required this.senderId,
    required this.topic,
    required this.data,
  });

  /// Identity of the sender, or null if sent from server API.
  final String? senderId;

  /// Optional topic categorizing the message.
  final String? topic;

  /// Raw bytes of the message payload.
  final List<int> data;

  /// Decode data as UTF-8 JSON.
  Map<String, dynamic>? get json {
    try {
      return jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    } catch (e) {
      final preview = utf8.decode(data, allowMalformed: true);
      debugPrint(
        'DataChannelMessage: JSON parse failed '
        '(topic: $topic, error: $e, '
        'data: ${preview.length > 200 ? preview.substring(0, 200) : preview})',
      );
      return null;
    }
  }

  /// Decode data as UTF-8 string.
  String get text => utf8.decode(data);

  @override
  String toString() =>
      'DataChannelMessage(senderId: $senderId, topic: $topic, data: ${data.length} bytes)';
}

/// A parsed avatar update from the `avatar` data channel topic.
class AvatarUpdate {
  const AvatarUpdate({
    required this.playerId,
    required this.avatarId,
    required this.spriteAsset,
  });

  final String playerId;
  final String avatarId;
  final String spriteAsset;

  /// Try to parse an [AvatarUpdate] from a JSON map. Returns null if required
  /// fields are missing or have wrong types.
  ///
  /// Uses Dart 3 map patterns so a wrong-typed value returns null rather
  /// than throwing — a thrown error inside the stream's `.map` callback
  /// would tear down avatar reception for the rest of the session.
  static AvatarUpdate? tryParse(Map<String, dynamic>? json) {
    if (json case {'playerId': String playerId, 'spriteAsset': String spriteAsset}) {
      // Whitelist sprite asset against the known-avatar set — prevents
      // path-traversal, empty strings, and cache-miss crashes from
      // forwarding through to the renderer. Set is lifted to a top-level
      // `final` (`predefinedAvatarSpriteAssets`) so it's built once.
      if (!predefinedAvatarSpriteAssets.contains(spriteAsset)) return null;
      final avatarId = switch (json['avatarId']) { String s => s, _ => '' };
      return AvatarUpdate(
        playerId: playerId,
        avatarId: avatarId,
        spriteAsset: spriteAsset,
      );
    }
    return null;
  }
}

/// A reliable position heartbeat from another participant.
///
/// Carries a single grid position with reliable delivery to correct stale
/// positions caused by dropped unreliable path updates.
class PositionHeartbeat {
  const PositionHeartbeat({
    required this.playerId,
    required this.x,
    required this.y,
  });

  final String playerId;
  final int x;
  final int y;

  /// Try to parse a [PositionHeartbeat] from a JSON map. Returns null if
  /// required fields are missing or have wrong types.
  ///
  /// Uses `is` checks rather than `as` casts so a malformed packet from
  /// any participant returns null rather than throwing — a thrown error
  /// inside the stream's `.map` would propagate and tear down the
  /// heartbeat-reception stream for the rest of the session.
  static PositionHeartbeat? tryParse(Map<String, dynamic>? json) {
    if (json == null) return null;
    final playerId = json['playerId'];
    final x = json['x'];
    final y = json['y'];
    if (playerId is! String || x is! int || y is! int) return null;
    // 2× grid bounds: negative coords valid for off-origin maps. Units: grid cells.
    const maxCoord = gridSize * 2;
    return PositionHeartbeat(
      playerId: playerId,
      x: x.clamp(-maxCoord, maxCoord),
      y: y.clamp(-maxCoord, maxCoord),
    );
  }
}
