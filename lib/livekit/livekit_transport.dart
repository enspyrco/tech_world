import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:logging/logging.dart';
import 'package:tech_world/livekit/data_channel.dart';
import 'package:tech_world/livekit/set_track_volume.dart';

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

/// Result of a [LiveKitTransport.connect] attempt.
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

/// Internal connection state for [LiveKitTransport].
///
/// Replaces the former `_isConnecting` / `_isConnected` boolean pair, which
/// admitted the illegal `(true, true)` combination.
enum _ConnectionState { disconnected, connecting, connected }

final _log = Logger('LiveKitTransport');

/// The LiveKit room connection, with no game in it.
///
/// It is headed for `realm_livekit`, so nothing it imports may reach the rest
/// of `package:tech_world`; `test/livekit/transport_no_leak_test.dart` checks.
class LiveKitTransport {
  LiveKitTransport({
    required this.roomName,
    required String serverUrl,
    Future<TokenResult> Function()? tokenSource,
  })  : _serverUrl = serverUrl,
        _tokenSource = tokenSource;

  final String roomName;

  /// LiveKit server websocket URL.
  final String _serverUrl;

  /// Production token source, injected by [RoomSession]. When set, it fully
  /// owns token retrieval (Firebase login → RealmCredential → LiveKit token via
  /// the realm-token-server) and its classified [TokenResult] is used directly.
  /// When `null`, [_retrieveToken] fails with `tokenUnknownError` (no network
  /// call). Also the seam through which tests inject a canned token.
  final Future<TokenResult> Function()? _tokenSource;

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
  final _localTrackUnpublishedController =
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

  /// Stream of local track UN-publication events (fires when the camera/mic is
  /// turned off). The game bridge downgrades the local video bubble to a static
  /// avatar so it doesn't freeze on its last decoded frame.
  Stream<LocalTrackPublication> get localTrackUnpublished =>
      _localTrackUnpublishedController.stream;

  /// Stream of data channel messages received from other participants
  Stream<DataChannelMessage> get dataReceived => _dataReceivedController.stream;

  /// Emits the disconnect reason when the room connection is lost unexpectedly.
  ///
  /// Consumers (e.g. `main.dart`) can listen to show a reconnection banner or
  /// trigger cleanup. Does not fire on an intentional [disconnect], which
  /// detaches the listener before tearing the room down.
  Stream<String?> get connectionLost => _connectionLostController.stream;

  /// Messages on [topic], decoded. See [decodeTopic].
  Stream<T> receive<T>(TopicDecoder<T> topic) => decodeTopic(
        dataReceived,
        topic,
        onError: (e, st) => _log.warning(
            'Dropped undecodable ${topic.wireName} message', e, st),
      );

  /// Publish [value] on [topic], optionally only [to] the given identities.
  ///
  /// `async` on purpose: it turns an encoder throw into a failed Future, as
  /// the `async` publish methods this replaced did. Without it the throw
  /// escapes at the call site and skips whatever a fire-and-forget caller does
  /// next.
  Future<void> send<T>(TopicEncoder<T> topic, T value,
          {List<String>? to}) async =>
      publishData(
        topic.encode(value),
        reliable: topic.reliable,
        destinationIdentities: to,
        topic: topic.wireName,
      );

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

    Room? room;
    try {
      // Get token: realm-token-server via the injected token source.
      final String token;
      switch (await _retrieveToken()) {
        case TokenFailure(:final connectionResult):
          _log.warning('Failed to retrieve token');
          _connectionState = _ConnectionState.disconnected;
          // A failure must never report `connected` (asserted in debug); coerce
          // in release so a mis-constructed failure can't fake a joined room.
          return connectionResult == ConnectionResult.connected
              ? ConnectionResult.tokenUnknownError
              : connectionResult;
        case TokenSuccess(token: final t):
          token = t;
      }

      // Create room with options
      room = Room(
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
      _room = room;

      // Set up event listener
      _listener = room.createListener();
      _setupListeners();

      // Connect to room — explicit RTCConfiguration ensures TURN relay
      // candidates are tried alongside direct UDP.
      await room.connect(
        _serverUrl,
        token,
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

      // A disconnect() during the join took this room and tore it down; this
      // attempt owns nothing now and must not announce a connection.
      if (!identical(_room, room)) return ConnectionResult.roomFailed;

      _connectionState = _ConnectionState.connected;
      _log.info('Connected to LiveKit room "$roomName"');
      onConnected();

      // Notify about existing participants
      for (final participant in room.remoteParticipants.values) {
        _participantJoinedController.add(participant);
      }

      return ConnectionResult.connected;
    } catch (e) {
      _log.severe('Connection failed', e);
      // Same as above: if disconnect() took the room, it owns the teardown and
      // the fields may already belong to a newer attempt.
      if (room != null && !identical(_room, room)) {
        return ConnectionResult.roomFailed;
      }
      // Clean up dangling _room and _listener created before the failure.
      // Each cleanup is wrapped individually so one failure doesn't prevent
      // the other from running.
      try {
        await _listener?.dispose();
      } catch (cleanupError) {
        _log.warning('Listener cleanup failed', cleanupError);
      }
      _listener = null;
      // Full teardown, not just disconnect — a half-built Room still owns an
      // engine with its own reconnect loop (see [_disposeRoom]).
      await _disposeRoom(_room);
      _room = null;
      _connectionState = _ConnectionState.disconnected;
      return ConnectionResult.roomFailed;
    }
  }

  /// Nothing is published without a room; keeps the mute toolbar honest across
  /// a reconnect (enableMedia re-flips these true on rejoin).
  void _resetPublishedMedia() {
    cameraEnabled.value = false;
    micEnabled.value = false;
  }

  /// Tear a [Room] down completely: disconnect, then **dispose**.
  ///
  /// `disconnect()` alone is NOT enough. [Room] is a `DisposableChangeNotifier`
  /// and its engine owns an auto-reconnect loop (`Engine.attemptReconnect`) plus
  /// the signal websocket. Dropping the reference after only disconnecting
  /// leaves that engine alive, and it will keep reconnecting its own socket in
  /// the background while the app builds a *second* Room on the next connect —
  /// two live engines racing. The orphan's socket is disposed but never has its
  /// stream subscription cancelled (see `LiveKitWebSocketIO`), so every frame
  /// the server still delivers logs
  /// `LiveKitWebSocketIO#<id> already disposed, ignoring received data`.
  /// That warning storm is the observable symptom of this leak.
  ///
  /// The SDK's own example disposes the room (`await widget.room.dispose()`).
  ///
  /// Never throws: teardown runs on error paths where a throw would mask the
  /// original failure.
  static Future<void> _disposeRoom(Room? room, {bool disconnect = true}) async {
    if (room == null) return;
    if (disconnect) {
      try {
        await room.disconnect();
      } catch (e) {
        _log.warning('Room disconnect during teardown failed', e);
      }
    }
    try {
      await room.dispose();
    } catch (e) {
      _log.warning('Room dispose during teardown failed', e);
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

    // Detach and take ownership before any await: the SDK emits
    // RoomDisconnectedEvent during its own teardown, and with the listener
    // still attached a deliberate leave would read as a lost connection. No
    // field is written after the await, so a connect() that starts meanwhile
    // keeps its own room.
    final listener = _listener;
    final room = _room;
    _listener = null;
    _room = null;
    _connectionState = _ConnectionState.disconnected;
    _resetPublishedMedia();

    try {
      await listener?.dispose();
    } catch (e) {
      _log.warning('Listener cleanup failed', e);
    }
    await _disposeRoom(room);

    _log.info('Disconnected');
  }

  /// Whether the local camera is currently publishing (true = live/unmuted).
  ///
  /// Reactive so the mute toolbar button reflects reality. Session-scoped:
  /// starts `false` (fast-connect publishes nothing), flips `true` once
  /// [enableMedia] succeeds on room entry, and tracks every [setCameraEnabled].
  final ValueNotifier<bool> cameraEnabled = ValueNotifier<bool>(false);

  /// Whether the local microphone is currently publishing (true = live/unmuted).
  ///
  /// See [cameraEnabled] for lifecycle. Tracks every [setMicrophoneEnabled].
  final ValueNotifier<bool> micEnabled = ValueNotifier<bool>(false);

  /// Enable/disable local camera
  Future<void> setCameraEnabled(bool enabled) async {
    if (_room?.localParticipant == null) return;
    try {
      await _room!.localParticipant!.setCameraEnabled(enabled);
      // Only reflect state after the toggle actually lands, so a failed
      // enable (e.g. permission denied) leaves the button showing muted.
      cameraEnabled.value = enabled;
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
      micEnabled.value = enabled;
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
  /// Enable or disable a remote participant's audio, reporting whether there
  /// was anything to act ON.
  ///
  /// READ THE RETURN VALUE'S SCOPE CAREFULLY. True means: the participant was
  /// present in `remoteParticipants` AND had at least one audio publication we
  /// iterated. It does NOT mean the SFU acted — `publication.enable()` returns
  /// void and reports nothing, so no confirmation is available at this layer.
  ///
  /// An earlier version of this docstring claimed the change "actually landed
  /// on at least one track", which is more than the code can know. That is the
  /// same prose-outruns-mechanism failure this method was changed to fix, so
  /// it is corrected here rather than quietly.
  ///
  /// Returns BOOL rather than void, matching [setParticipantAudioVolume], so a
  /// caller cannot latch a gate state that was never applied. The failure this
  /// closes is silent: a participant that has not appeared in
  /// `remoteParticipants` yet (late subscription) made this return early, while
  /// [ProximityAudioGate] recorded the peer as enabled — after which every
  /// later frame saw `hasAudio == true`, skipped the enable, and left the peer
  /// muted forever with diagnostics insisting otherwise.
  ///
  /// A participant with zero audio publications also reports false: there was
  /// no track to act on, so a later frame should try again rather than trust a
  /// gate that never gated anything.
  ///
  /// So the bool is an ADDRESSABILITY check, not a delivery receipt. That is
  /// still strictly better than void — it distinguishes "nobody to talk to"
  /// from "we said something" and closes the unsubscribed-peer latch — but a
  /// caller must not read it as proof the peer's audio state changed.
  bool setParticipantAudioEnabled(String identity, bool enabled) {
    final participant = _room?.remoteParticipants[identity];
    if (participant == null) return false;

    var applied = false;
    for (final publication in participant.audioTrackPublications) {
      if (enabled) {
        publication.enable();
      } else {
        publication.disable();
      }
      applied = true;
    }
    return applied;
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

  // Hooks, not streams: each runs synchronously where its event happens, so a
  // subclass sees it in order; a broadcast stream would deliver a microtask
  // late. Implementations must not throw or call [connect] or [disconnect].

  /// Called once the room is connected, before existing participants are
  /// announced on [participantJoined].
  @protected
  void onConnected() {}

  /// Called from the `RoomDisconnectedEvent` handler, after the room is torn
  /// down and [connectionLost] has been fed. See [connectionLost] for when
  /// that handler runs.
  @protected
  void onConnectionLost(String? reason) {}

  /// Called from the [TrackSubscribedEvent] handler for every remote track,
  /// audio and video, after a video track is forwarded to [trackSubscribed].
  /// The game side uses it to disable a fresh Dreamfinder audio track before
  /// it can play.
  @protected
  void onRemoteTrackSubscribed({
    required String identity,
    required bool isAudioTrack,
  }) {}

  /// Get a participant by their identity (userId)
  Participant? getParticipant(String identity) {
    if (_room == null) return null;

    if (_room!.localParticipant?.identity == identity) {
      return _room!.localParticipant;
    }

    return _room!.remoteParticipants[identity];
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

  Future<TokenResult> _retrieveToken() async {
    if (_tokenSource != null) {
      try {
        return await _tokenSource();
      } catch (e) {
        // RealmTokenSource already classifies every Exception into a
        // TokenResult; this guards the seam against an unexpected NON-Exception
        // escape (an Error, a future injector bug) so it can't fall through to
        // connect()'s outer catch and be mislabelled roomFailed.
        _log.warning('Token source threw unexpectedly', e);
        return const TokenResult.failure(ConnectionResult.tokenUnknownError);
      }
    }
    // No source wired. The retrieveLiveKitToken Cloud Function fallback was
    // retired once the realm-token-server cutover was proven live (zero
    // production callers across the 30-day log retention window, 2026-10-25);
    // a null source is now a wiring bug, never a silent route to a second mint.
    _log.warning('No token source wired for room "$roomName"');
    return const TokenResult.failure(ConnectionResult.tokenUnknownError);
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
        onRemoteTrackSubscribed(
          identity: event.participant.identity,
          isAudioTrack: event.track is AudioTrack,
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
        _resetPublishedMedia();
        // Clean up resources left dangling by the unexpected disconnect.
        // Note: _listener.dispose() is intentionally not awaited here — this
        // is a synchronous event callback and the dispose is fire-and-forget.
        try {
          _listener?.dispose();
        } catch (e) {
          _log.warning('Listener cleanup failed', e);
        }
        _listener = null;

        // DISPOSE the orphan, don't just drop it. Previously this nulled
        // `_room` and walked away: the Room survived with a live engine that
        // kept running its own reconnect loop, while RoomSession's backoff
        // built a SECOND Room — two engines racing, and the orphan's disposed
        // socket logging a warning per received frame.
        //
        // Deferred with `Future(...)` rather than called inline: we are inside
        // the Room's OWN event dispatch here, and `Room.dispose()` tears down
        // the event emitter we are currently being dispatched from. Hopping to
        // the next microtask gets us out of that callback first.
        //
        // Already disconnected by definition (this IS RoomDisconnectedEvent),
        // so skip the redundant disconnect and go straight to dispose.
        final orphan = _room;
        _room = null;
        if (orphan != null) {
          Future(() => _disposeRoom(orphan, disconnect: false));
        }
        // Notify consumers so they can show a banner / attempt reconnect.
        _connectionLostController.add(event.reason?.name);
        onConnectionLost(event.reason?.name);
      })
      ..on<LocalTrackPublishedEvent>((event) {
        _log.fine(
            'Local track published: ${event.publication.kind}');
        _localTrackPublishedController.add(event.publication);
      })
      ..on<LocalTrackUnpublishedEvent>((event) {
        _log.fine(
            'Local track unpublished: ${event.publication.kind}');
        _localTrackUnpublishedController.add(event.publication);
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
    _localTrackUnpublishedController.close();
    _dataReceivedController.close();
    _connectionLostController.close();
  }
}

/// Result of a token fetch — either a token, or a classified failure.
///
/// A `sealed` success/failure union (the house idiom for a closed result
/// hierarchy — cf. `CastResult` in the design standard). Carrying the
/// [ConnectionResult] rather than a bare `String?` lets the source distinguish
/// an auth failure — which must abort reconnection and bounce the user to
/// sign-in — from a retryable network failure. The realm-backed source maps
/// `RealmAuthException` subtypes to the right classification; see
/// `realm_token_source.dart`.
///
/// The [token] / [connectionResult] getters are retained for ergonomic reads;
/// consumers that need the token should pattern-match on [TokenSuccess] /
/// [TokenFailure] so the non-null token is type-checked rather than `!`-asserted.
sealed class TokenResult {
  const TokenResult();

  /// A successful fetch carrying the LiveKit access token.
  const factory TokenResult.success(String token) = TokenSuccess;

  /// A failed fetch classified by a failure [ConnectionResult] (never
  /// [ConnectionResult.connected]).
  const factory TokenResult.failure(ConnectionResult connectionResult) =
      TokenFailure;

  /// The LiveKit access token on success; `null` on failure.
  String? get token => switch (this) {
        TokenSuccess(:final token) => token,
        TokenFailure() => null,
      };

  /// [ConnectionResult.connected] on success, or the failure reason otherwise.
  ConnectionResult get connectionResult => switch (this) {
        TokenSuccess() => ConnectionResult.connected,
        TokenFailure(:final connectionResult) => connectionResult,
      };
}

/// A successful token fetch.
class TokenSuccess extends TokenResult {
  /// Wraps the minted LiveKit access [token], which must be non-empty — success
  /// means "usable token", not merely "non-null string" (asserted in debug; the
  /// construction sites reject empty in all modes).
  const TokenSuccess(this.token)
      : assert(token != '', 'TokenSuccess requires a non-empty token'),
        super();

  @override
  final String token;
}

/// A classified token-fetch failure.
class TokenFailure extends TokenResult {
  /// [connectionResult] must be a failure reason, never
  /// [ConnectionResult.connected] — the assert makes the illegal state
  /// unrepresentable in debug/CI; `connect()` coerces it in release too (a
  /// caught cage-match finding, PR #528).
  const TokenFailure(this.connectionResult)
      : assert(
          connectionResult != ConnectionResult.connected,
          'TokenResult.failure must carry a failure result, not connected',
        ),
        super();

  @override
  final ConnectionResult connectionResult;
}
