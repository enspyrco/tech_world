import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/bot_character_component.dart';
import 'package:tech_world/flame/components/player_bubble_component.dart';
import 'package:tech_world/flame/components/grid_component.dart';
import 'package:tech_world/flame/components/path_component.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/components/video_bubble_component.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/utils/locator.dart';

/// We create a [TechWorld] component by extending flame's [World] class and
/// the world world compent adds all other components that make up the game world.
///
/// The [TechWorld] component responds to taps by calculating the selected
/// grid point in minigrid space then passing the player position and selected
/// grid point to the [PathComponent]. The list of [Direction]s calculated in
/// the [PathComponent] are then passed to the [Player] component where they
/// are used to create a set of [MoveEffect]s and set the appropriate animation.
class TechWorld extends World with TapCallbacks {
  TechWorld({required Stream<AuthUser> authStateChanges})
      : _authStateChanges = authStateChanges;

  final PlayerComponent _userPlayerComponent = PlayerComponent(
    position: Vector2(0, 0),
    id: '',
    displayName: '',
  );

  final Map<String, PlayerComponent> _otherPlayerComponentsMap = {};
  BotCharacterComponent? _botCharacterComponent;
  final GridComponent _gridComponent = GridComponent();
  final BarriersComponent _barriersComponent = BarriersComponent();
  late PathComponent _pathComponent;

  // Bubble components - shown when player is near other players
  static const _botUserId = 'bot-claude';
  static const _localPlayerBubbleKey = '_local_player_';
  static const _proximityThreshold = 3; // grid squares
  static final _bubbleOffset =
      Vector2(16, -20); // center horizontally, above sprite
  final Map<String, PositionComponent> _playerBubbles = {};
  Point<int>? _lastPlayerGridPosition; // track to skip unnecessary updates

  // LiveKit integration for video bubbles
  LiveKitService? _liveKitService;
  ui.FragmentProgram? _shaderProgram; // Keep reference for creating new shaders

  final Stream<AuthUser> _authStateChanges;
  StreamSubscription<AuthUser>? _authStateChangesSubscription;
  StreamSubscription<(Participant, VideoTrack)>? _trackSubscribedSubscription;
  StreamSubscription<LocalTrackPublication>? _localTrackPublishedSubscription;
  StreamSubscription<PlayerPath>? _liveKitPositionSubscription;
  StreamSubscription<RemoteParticipant>? _participantJoinedSubscription;
  StreamSubscription<RemoteParticipant>? _participantLeftSubscription;

  // Position tracking for proximity detection
  Point<int> get localPlayerPosition => _userPlayerComponent.miniGridPosition;
  String get localPlayerId => _userPlayerComponent.id;

  Map<String, Point<int>> get otherPlayerPositions {
    final positions = _otherPlayerComponentsMap.map(
      (id, component) => MapEntry(id, component.miniGridPosition),
    );
    // Include bot position if bot character exists
    if (_botCharacterComponent != null) {
      positions[_botUserId] = _botCharacterComponent!.miniGridPosition;
    }
    return positions;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _updatePlayerBubbles();
  }

  void _updatePlayerBubbles() {
    final playerGrid = _userPlayerComponent.miniGridPosition;

    // Skip update if player hasn't moved to a new grid position
    if (_lastPlayerGridPosition == playerGrid) {
      // Still update positions of existing bubbles
      _updateBubblePositions();
      return;
    }
    _lastPlayerGridPosition = playerGrid;

    // Check each other player for proximity
    final nearbyPlayerIds = <String>{};

    for (final entry in _otherPlayerComponentsMap.entries) {
      final playerId = entry.key;
      final playerComponent = entry.value;

      // Calculate Chebyshev distance (max of x/y difference)
      final otherGrid = playerComponent.miniGridPosition;
      final distance = max(
        (otherGrid.x - playerGrid.x).abs(),
        (otherGrid.y - playerGrid.y).abs(),
      );

      final isNearby = distance <= _proximityThreshold;

      if (isNearby) {
        nearbyPlayerIds.add(playerId);

        if (!_playerBubbles.containsKey(playerId)) {
          // Create bubble for this player
          final bubble = _createBubbleForPlayer(playerId, playerComponent);
          bubble.position = playerComponent.position + _bubbleOffset;
          _playerBubbles[playerId] = bubble;
          add(bubble);
        }
      }
    }

    // Check proximity to bot character
    if (_botCharacterComponent != null) {
      final botGrid = _botCharacterComponent!.miniGridPosition;
      final botDistance = max(
        (botGrid.x - playerGrid.x).abs(),
        (botGrid.y - playerGrid.y).abs(),
      );

      if (botDistance <= _proximityThreshold) {
        nearbyPlayerIds.add(_botUserId);

        if (!_playerBubbles.containsKey(_botUserId)) {
          // Create status bubble for bot
          final bubble = BotBubbleComponent();
          bubble.position = _botCharacterComponent!.position + _bubbleOffset;
          _playerBubbles[_botUserId] = bubble;
          add(bubble);
        }
      }
    }

    // Show local player's bubble if near anyone
    if (nearbyPlayerIds.isNotEmpty) {
      if (!_playerBubbles.containsKey(_localPlayerBubbleKey)) {
        final localBubble = _createLocalPlayerBubble();
        localBubble.position = _userPlayerComponent.position + _bubbleOffset;
        _playerBubbles[_localPlayerBubbleKey] = localBubble;
        add(localBubble);
      }
      nearbyPlayerIds.add(_localPlayerBubbleKey);
    }

    // Remove bubbles for players no longer nearby
    final toRemove = <String>[];
    for (final playerId in _playerBubbles.keys) {
      if (!nearbyPlayerIds.contains(playerId)) {
        _playerBubbles[playerId]?.removeFromParent();
        toRemove.add(playerId);
      }
    }
    for (final playerId in toRemove) {
      _playerBubbles.remove(playerId);
    }

    _updateBubblePositions();
  }

  void _updateBubblePositions() {
    for (final entry in _playerBubbles.entries) {
      if (entry.key == _localPlayerBubbleKey) {
        entry.value.position = _userPlayerComponent.position + _bubbleOffset;
      } else if (entry.key == _botUserId) {
        if (_botCharacterComponent != null) {
          entry.value.position =
              _botCharacterComponent!.position + _bubbleOffset;
        }
      } else {
        final playerComponent = _otherPlayerComponentsMap[entry.key];
        if (playerComponent != null) {
          entry.value.position = playerComponent.position + _bubbleOffset;
        }
      }
    }
  }

  PositionComponent _createBubbleForPlayer(
      String playerId, PlayerComponent playerComponent) {
    // Check if this player has a LiveKit participant with video
    final participant = _liveKitService?.getParticipant(playerId);
    if (participant != null && _hasVideoTrack(participant)) {
      final videoBubble = VideoBubbleComponent(
        participant: participant,
        displayName: playerComponent.displayName,
        bubbleSize: 64,
        targetFps: 15,
      );

      // Apply shader if loaded
      if (_shaderProgram != null) {
        videoBubble.setShader(_shaderProgram!.fragmentShader());
      }

      return videoBubble;
    }

    // Fallback to static bubble
    return PlayerBubbleComponent(
      displayName: playerComponent.displayName,
      playerId: playerId,
    );
  }

  /// Check if participant has an active video track
  bool _hasVideoTrack(Participant participant) {
    for (final publication in participant.videoTrackPublications) {
      if (publication.track != null) {
        // For local participant, check if track is published
        // For remote participant, check if track is subscribed
        if (participant is LocalParticipant) {
          return true; // Local tracks are always "active" when present
        } else {
          if (publication.subscribed) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Load the video bubble shader program
  Future<void> _loadVideoBubbleShader() async {
    try {
      _shaderProgram =
          await ui.FragmentProgram.fromAsset('shaders/video_bubble.frag');
    } catch (e) {
      // Shader loading failed - video bubbles will render without effects
    }
  }

  /// Connect to LiveKit room
  Future<void> _connectToLiveKit(String userId, String displayName) async {
    if (_liveKitService != null) {
      debugPrint('LiveKit already initialized');
      return;
    }

    // Get LiveKitService from Locator (created in main.dart when user signs in)
    _liveKitService = Locator.maybeLocate<LiveKitService>();
    if (_liveKitService == null) {
      debugPrint('LiveKitService not available yet');
      return;
    }

    debugPrint('TechWorld: Using LiveKitService from Locator');

    // Subscribe to position updates from other players via LiveKit
    _liveKitPositionSubscription =
        _liveKitService!.positionReceived.listen((PlayerPath path) {
      debugPrint('LiveKit position received for ${path.playerId}');
      // Don't process our own position
      if (path.playerId == userId) return;

      if (path.playerId == _botUserId) {
        // Set bot position directly (bot doesn't animate movement)
        if (_botCharacterComponent != null && path.largeGridPoints.isNotEmpty) {
          _botCharacterComponent!.position = path.largeGridPoints.first;
        }
      } else {
        // If player component doesn't exist, create it
        if (!_otherPlayerComponentsMap.containsKey(path.playerId)) {
          debugPrint('Creating player component for ${path.playerId} from position data');
          final playerComponent = PlayerComponent(
            position: path.largeGridPoints.isNotEmpty
                ? path.largeGridPoints.first
                : Vector2.zero(),
            id: path.playerId,
            displayName: path.playerId, // Use ID as fallback display name
          );
          _otherPlayerComponentsMap[path.playerId] = playerComponent;
          add(playerComponent);
        }
        _otherPlayerComponentsMap[path.playerId]
            ?.move(path.directions, path.largeGridPoints);
      }
    });

    // Listen for participant join/leave to manage player presence
    _participantJoinedSubscription =
        _liveKitService!.participantJoined.listen((participant) {
      debugPrint('LiveKit participant joined: ${participant.identity}');
      _refreshBubbleForPlayer(participant.identity);

      // Create player component if it doesn't exist
      if (participant.identity != _botUserId &&
          !_otherPlayerComponentsMap.containsKey(participant.identity)) {
        final playerComponent = PlayerComponent(
          position: Vector2.zero(),
          id: participant.identity,
          displayName: participant.name.isNotEmpty
              ? participant.name
              : participant.identity,
        );
        _otherPlayerComponentsMap[participant.identity] = playerComponent;
        add(playerComponent);
      }
    });

    _participantLeftSubscription =
        _liveKitService!.participantLeft.listen((participant) {
      debugPrint('LiveKit participant left: ${participant.identity}');

      // Remove player component and bubble
      final playerComponent =
          _otherPlayerComponentsMap.remove(participant.identity);
      if (playerComponent != null) {
        remove(playerComponent);
      }

      final bubble = _playerBubbles.remove(participant.identity);
      bubble?.removeFromParent();
    });

    _liveKitService!.speakingChanged.listen((event) {
      final (participant, isSpeaking) = event;
      _updateBubbleSpeakingState(participant.identity, isSpeaking);
    });

    // Listen for track subscription events to trigger capture init immediately
    _trackSubscribedSubscription =
        _liveKitService!.trackSubscribed.listen((event) {
      final (participant, _) = event;
      _notifyBubbleTrackReady(participant.identity);
    });

    // Listen for local track publication to refresh local bubble when camera is ready
    _localTrackPublishedSubscription =
        _liveKitService!.localTrackPublished.listen((publication) {
      if (publication.kind == TrackType.VIDEO) {
        debugPrint('TechWorld: Local video track published, refreshing bubble');
        _refreshLocalPlayerBubble();
      }
    });

    // Check if already connected, otherwise wait for connection
    if (_liveKitService!.isConnected) {
      debugPrint('LiveKit already connected');
      await _liveKitService!.setCameraEnabled(true);
      await _liveKitService!.setMicrophoneEnabled(true);
      _refreshLocalPlayerBubble();
    } else {
      debugPrint('Waiting for LiveKit connection...');
    }
  }

  /// Refresh a player's bubble (recreate if video is now available)
  void _refreshBubbleForPlayer(String playerId) {
    final existingBubble = _playerBubbles[playerId];
    if (existingBubble == null) return; // No bubble to refresh

    // If it's already a video bubble, no need to refresh
    if (existingBubble is VideoBubbleComponent) return;

    // Get player component
    final playerComponent = _otherPlayerComponentsMap[playerId];
    if (playerComponent == null) return;

    // Remove old bubble
    existingBubble.removeFromParent();

    // Create new bubble (might be video bubble now)
    final newBubble = _createBubbleForPlayer(playerId, playerComponent);
    newBubble.position = playerComponent.position + _bubbleOffset;
    _playerBubbles[playerId] = newBubble;
    add(newBubble);
  }

  /// Refresh local player bubble (recreate if video is now available)
  void _refreshLocalPlayerBubble() {
    final existingBubble = _playerBubbles[_localPlayerBubbleKey];
    if (existingBubble == null) return; // No bubble to refresh

    // If it's already a video bubble, no need to refresh
    if (existingBubble is VideoBubbleComponent) return;

    debugPrint('Refreshing local player bubble after camera enabled');

    // Remove old bubble
    existingBubble.removeFromParent();

    // Create new bubble (should be video bubble now)
    final newBubble = _createLocalPlayerBubble();
    newBubble.position = _userPlayerComponent.position + _bubbleOffset;
    _playerBubbles[_localPlayerBubbleKey] = newBubble;
    add(newBubble);
  }

  /// Update speaking state on video bubbles
  void _updateBubbleSpeakingState(String participantId, bool isSpeaking) {
    final bubble = _playerBubbles[participantId];
    if (bubble is VideoBubbleComponent) {
      bubble.speakingLevel = isSpeaking ? 1.0 : 0.0;
    }
  }

  /// Notify a video bubble that its track is ready for capture
  void _notifyBubbleTrackReady(String participantId) {
    final bubble = _playerBubbles[participantId];
    if (bubble is VideoBubbleComponent) {
      debugPrint('TechWorld: Notifying bubble track ready for $participantId');
      bubble.notifyTrackReady();
    }
  }

  /// Create bubble for local player (video if available, otherwise static)
  PositionComponent _createLocalPlayerBubble() {
    final localParticipant = _liveKitService?.localParticipant;

    if (localParticipant != null && _hasVideoTrack(localParticipant)) {
      debugPrint('Creating local VideoBubbleComponent');
      final videoBubble = VideoBubbleComponent(
        participant: localParticipant,
        displayName: _userPlayerComponent.displayName,
        bubbleSize: 64,
        targetFps: 15,
      );

      // Apply shader if loaded
      if (_shaderProgram != null) {
        videoBubble.setShader(_shaderProgram!.fragmentShader());
      }

      // Local player gets a cyan glow
      videoBubble.glowColor = Colors.cyan;

      return videoBubble;
    }

    // Fallback to static bubble
    return PlayerBubbleComponent(
      displayName: _userPlayerComponent.displayName,
      playerId: _userPlayerComponent.id,
    );
  }

  @override
  Future<void> onLoad() async {
    _pathComponent = PathComponent(barriers: _barriersComponent);

    await add(_gridComponent);
    await add(_pathComponent);
    await add(_barriersComponent);
    await add(_userPlayerComponent);

    (findGame() as TechWorldGame?)?.camera.follow(_userPlayerComponent);

    // Load the video bubble shader
    await _loadVideoBubbleShader();

    _authStateChangesSubscription = _authStateChanges.listen((authUser) async {
      if (authUser is! PlaceholderUser && authUser is! SignedOutUser) {
        _userPlayerComponent.id = authUser.id;
        _userPlayerComponent.displayName = authUser.displayName;

        // Connect to LiveKit when user is authenticated
        await _connectToLiveKit(authUser.id, authUser.displayName);
      }
    });
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    final worldPosition = event.localPosition;
    int miniGridX = (worldPosition.x / gridSquareSize).floor();
    int miniGridY = (worldPosition.y / gridSquareSize).floor();

    _pathComponent.calculatePath(
        start: _userPlayerComponent.miniGridTuple, end: (miniGridX, miniGridY));

    _pathComponent.drawPath();

    _userPlayerComponent.move(
        _pathComponent.directions, _pathComponent.largeGridPoints);

    // Publish position via LiveKit data channel
    _liveKitService?.publishPosition(
      points: _pathComponent.largeGridPoints,
      directions: _pathComponent.directions,
    );
  }

  void dispose() {
    _authStateChangesSubscription?.cancel();
    _trackSubscribedSubscription?.cancel();
    _localTrackPublishedSubscription?.cancel();
    _liveKitPositionSubscription?.cancel();
    _participantJoinedSubscription?.cancel();
    _participantLeftSubscription?.cancel();
    _liveKitService?.dispose();
  }
}
