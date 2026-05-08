import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:logging/logging.dart';
import 'package:tech_world/avatar/avatar.dart';
import 'package:tech_world/flame/bubble_manager.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world/infra/infra_health_service.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/livekit/livekit_topic.dart';
import 'package:tech_world/utils/locator.dart';

final _log = Logger('LiveKitGameBridge');

/// Manages the lifecycle of all LiveKit stream subscriptions for the game
/// world.
///
/// Plain Dart class (not a Flame Component). Owns the 14 stream subscriptions
/// that translate LiveKit events into game-world mutations, plus the
/// [InfraHealthService] lifecycle. All game-world mutations are performed via
/// callbacks provided at construction — the bridge does not hold references to
/// Flame components.
///
/// This extraction reduces [TechWorld] from a god-class by separating the
/// subscription lifecycle (setup, teardown, reconnection) from the game-world
/// state it drives.
class LiveKitGameBridge {
  LiveKitGameBridge({
    required LiveKitService liveKitService,
    required String userId,
    required BubbleManager bubbleManager,
    required ValueNotifier<Point<int>> playerGridPosition,
    required Avatar? localAvatar,
    // Position / heartbeat
    required void Function(PlayerPath) onPositionReceived,
    required void Function(PositionHeartbeat) onHeartbeatReceived,
    // Participants
    required void Function(RemoteParticipant) onParticipantJoined,
    required void Function(RemoteParticipant) onParticipantLeft,
    // Avatar
    required void Function(AvatarUpdate) onAvatarUpdate,
    // Data channel
    required void Function(DataChannelMessage) onSpeechTranscript,
    required void Function(DataChannelMessage) onDoorUnlock,
    // Map
    required void Function() onMapInfoRequested,
    required void Function(String mapId) onMapSwitchReceived,
    // Connection
    required void Function() onConnectionLost,
  })  : _liveKitService = liveKitService,
        _userId = userId,
        _bubbleManager = bubbleManager,
        _playerGridPosition = playerGridPosition,
        _localAvatar = localAvatar,
        _onPositionReceived = onPositionReceived,
        _onHeartbeatReceived = onHeartbeatReceived,
        _onParticipantJoined = onParticipantJoined,
        _onParticipantLeft = onParticipantLeft,
        _onAvatarUpdate = onAvatarUpdate,
        _onSpeechTranscript = onSpeechTranscript,
        _onDoorUnlock = onDoorUnlock,
        _onMapInfoRequested = onMapInfoRequested,
        _onMapSwitchReceived = onMapSwitchReceived,
        _onConnectionLost = onConnectionLost;

  final LiveKitService _liveKitService;
  final String _userId;
  final BubbleManager _bubbleManager;
  final ValueNotifier<Point<int>> _playerGridPosition;
  final Avatar? _localAvatar;

  // Callbacks
  final void Function(PlayerPath) _onPositionReceived;
  final void Function(PositionHeartbeat) _onHeartbeatReceived;
  final void Function(RemoteParticipant) _onParticipantJoined;
  final void Function(RemoteParticipant) _onParticipantLeft;
  final void Function(AvatarUpdate) _onAvatarUpdate;
  final void Function(DataChannelMessage) _onSpeechTranscript;
  final void Function(DataChannelMessage) _onDoorUnlock;
  final void Function() _onMapInfoRequested;
  final void Function(String) _onMapSwitchReceived;
  final void Function() _onConnectionLost;

  // Subscriptions
  StreamSubscription<(Participant, VideoTrack)>? _trackSubscribedSub;
  StreamSubscription<(Participant, VideoTrack)>? _trackUnsubscribedSub;
  StreamSubscription<LocalTrackPublication>? _localTrackPublishedSub;
  StreamSubscription<PlayerPath>? _positionSub;
  StreamSubscription<PositionHeartbeat>? _heartbeatSub;
  StreamSubscription<RemoteParticipant>? _participantJoinedSub;
  StreamSubscription<RemoteParticipant>? _participantLeftSub;
  StreamSubscription<AvatarUpdate>? _avatarSub;
  StreamSubscription<(Participant, bool)>? _speakingSub;
  StreamSubscription<String?>? _connectionLostSub;
  StreamSubscription<void>? _mapInfoRequestedSub;
  StreamSubscription<String>? _mapSwitchSub;
  StreamSubscription<DataChannelMessage>? _speechTranscriptSub;
  StreamSubscription<DataChannelMessage>? _doorUnlockSub;

  InfraHealthService? _infraHealthService;

  /// The underlying service. Exposed so TechWorld can forward calls like
  /// publishAvatar, publishMapInfo, etc.
  LiveKitService get liveKitService => _liveKitService;

  /// Subscribe to all LiveKit streams and register existing participants.
  void connect() {
    _log.info('Connecting LiveKit bridge');

    // ── Map ──────────────────────────────────────────────────────────────
    _mapInfoRequestedSub = _liveKitService.mapInfoRequested.listen((_) {
      _log.info('Bot requested map-info, sending current map');
      _onMapInfoRequested();
    });

    _mapSwitchSub = _liveKitService.mapSwitchReceived.listen((mapId) {
      _log.info('Remote player switched to map "$mapId"');
      _onMapSwitchReceived(mapId);
    });

    // ── Position / heartbeat ─────────────────────────────────────────────
    _positionSub = _liveKitService.positionReceived.listen((path) {
      if (path.playerId == _userId) return; // skip own
      _onPositionReceived(path);
    });

    _heartbeatSub =
        _liveKitService.positionHeartbeatReceived.listen((heartbeat) {
      if (heartbeat.playerId == _userId) return; // skip own
      _onHeartbeatReceived(heartbeat);
    });

    _liveKitService.startPositionHeartbeat(
      () => _playerGridPosition.value,
    );

    // ── Avatar ───────────────────────────────────────────────────────────
    _avatarSub = _liveKitService.avatarReceived.listen(_onAvatarUpdate);

    // ── Participants ─────────────────────────────────────────────────────
    _participantJoinedSub =
        _liveKitService.participantJoined.listen(_onParticipantJoined);

    // Process existing participants that joined before we subscribed.
    for (final participant in _liveKitService.remoteParticipants.values) {
      _log.fine('Found existing participant: ${participant.identity}');
      _onParticipantJoined(participant);
    }

    _participantLeftSub =
        _liveKitService.participantLeft.listen(_onParticipantLeft);

    // ── Audio / video ────────────────────────────────────────────────────
    _speakingSub = _liveKitService.speakingChanged.listen((event) {
      final (participant, isSpeaking) = event;
      _bubbleManager.updateSpeakingState(participant.identity, isSpeaking);
    });

    _trackSubscribedSub = _liveKitService.trackSubscribed.listen((event) {
      final (participant, track) = event;
      if (track.kind == TrackType.VIDEO) {
        _log.fine('Video track subscribed for ${participant.identity}');
        _bubbleManager.refreshBubbleForPlayer(participant.identity);
      }
      _bubbleManager.notifyTrackReady(participant.identity);
    });

    _trackUnsubscribedSub =
        _liveKitService.trackUnsubscribed.listen((event) {
      final (participant, track) = event;
      if (track.kind == TrackType.VIDEO) {
        _log.info('Video track unsubscribed for ${participant.identity}');
        _bubbleManager.downgradeVideoBubble(participant.identity);
      }
    });

    _localTrackPublishedSub =
        _liveKitService.localTrackPublished.listen((publication) {
      if (publication.kind == TrackType.VIDEO) {
        _log.fine('Local video track published, refreshing bubble');
        _bubbleManager.refreshLocalPlayerBubble();
      }
    });

    // ── Data channels ────────────────────────────────────────────────────
    _speechTranscriptSub = _liveKitService.dataReceived
        .where((msg) => msg.topic == LiveKitTopic.speechTranscript.wire)
        .listen(_onSpeechTranscript);

    _doorUnlockSub = _liveKitService.dataReceived
        .where((msg) => msg.topic == LiveKitTopic.doorUnlock.wire)
        .listen(_onDoorUnlock);

    // ── Infrastructure health ────────────────────────────────────────────
    _infraHealthService = InfraHealthService(
      liveKitService: _liveKitService,
    );
    Locator.add<InfraHealthService>(_infraHealthService!);

    // ── Connection loss ──────────────────────────────────────────────────
    _connectionLostSub = _liveKitService.connectionLost.listen((reason) {
      _log.warning('LiveKit connection lost (reason: $reason), cleaning up');
      _onConnectionLost();
    });

    // ── Already-connected check ──────────────────────────────────────────
    if (_liveKitService.isConnected) {
      _log.fine('LiveKit already connected');
      _bubbleManager.refreshLocalPlayerBubble();
      if (_localAvatar != null) {
        _liveKitService.publishAvatar(_localAvatar);
      }
    } else {
      _log.fine('Waiting for LiveKit connection...');
    }
  }

  /// Cancel all subscriptions and clean up bridge-owned state.
  ///
  /// Does NOT clear game-world state (speech bubbles, player components,
  /// etc.) — that is the caller's responsibility via the cleanup callback.
  void disconnect() {
    _log.info('Disconnecting LiveKit bridge');

    _trackSubscribedSub?.cancel();
    _trackSubscribedSub = null;
    _trackUnsubscribedSub?.cancel();
    _trackUnsubscribedSub = null;
    _localTrackPublishedSub?.cancel();
    _localTrackPublishedSub = null;
    _positionSub?.cancel();
    _positionSub = null;
    _heartbeatSub?.cancel();
    _heartbeatSub = null;
    _participantJoinedSub?.cancel();
    _participantJoinedSub = null;
    _participantLeftSub?.cancel();
    _participantLeftSub = null;
    _avatarSub?.cancel();
    _avatarSub = null;
    _speakingSub?.cancel();
    _speakingSub = null;
    _connectionLostSub?.cancel();
    _connectionLostSub = null;
    _mapInfoRequestedSub?.cancel();
    _mapInfoRequestedSub = null;
    _mapSwitchSub?.cancel();
    _mapSwitchSub = null;
    _speechTranscriptSub?.cancel();
    _speechTranscriptSub = null;
    _doorUnlockSub?.cancel();
    _doorUnlockSub = null;

    _infraHealthService?.dispose();
    Locator.remove<InfraHealthService>();
    _infraHealthService = null;
  }
}
