import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors, FontWeight, TextStyle;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/editor/predefined_challenges.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/bot_character_component.dart';
import 'package:tech_world/flame/components/map_preview_component.dart';
import 'package:tech_world/flame/components/player_bubble_component.dart';
import 'package:tech_world/flame/components/tile_floor_component.dart';
import 'package:tech_world/flame/components/tile_object_layer_component.dart';
import 'package:tech_world/flame/components/wall_occlusion_component.dart';
// Grid lines hidden for now — uncomment to restore:
// import 'package:tech_world/flame/components/grid_component.dart';
import 'package:tech_world/flame/components/path_component.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/components/terminal_component.dart';
import 'package:tech_world/flame/components/video_bubble_component.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/predefined_maps.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/avatar/avatar.dart';
import 'package:tech_world/avatar/predefined_avatars.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/proximity/proximity_service.dart';
import 'package:tech_world/progress/progress_service.dart';
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
  // Grid lines hidden for now — uncomment to restore:
  // final GridComponent _gridComponent = GridComponent();
  BarriersComponent _barriersComponent =
      BarriersComponent(barriers: defaultMap.barriers);
  PathComponent? _pathComponent;

  /// The currently loaded map.
  final ValueNotifier<GameMap> currentMap = ValueNotifier(defaultMap);

  SpriteComponent? _backgroundSprite;
  final List<TerminalComponent> _terminalComponents = [];

  // Bubble components - shown when player is near other players
  static const _botUserId = 'bot-claude';
  static const _localPlayerBubbleKey = '_local_player_';
  static const _visualThreshold = 5; // grid squares — bubbles visible
  static const _audioThreshold = 2; // grid squares — audio enabled
  static final _bubbleOffset =
      Vector2(16, -20); // center horizontally, above sprite
  final Map<String, PositionComponent> _playerBubbles = {};
  final Set<String> _audioEnabledParticipants = {}; // track audio state
  Point<int>? _lastPlayerGridPosition; // track to skip unnecessary updates

  /// Current player grid position, updated each frame for UI consumers
  /// (e.g. the map editor mini-grid).
  final ValueNotifier<Point<int>> playerGridPosition =
      ValueNotifier(defaultMap.spawnPoint);

  // LiveKit integration for video bubbles
  LiveKitService? _liveKitService;
  ui.FragmentProgram? _shaderProgram; // Keep reference for creating new shaders

  /// Notifier for active challenge ID. Null means no editor open.
  final ValueNotifier<String?> activeChallenge = ValueNotifier(null);

  /// Grid position of the terminal the player is currently interacting with.
  /// Null when no editor is open.
  final ValueNotifier<Point<int>?> activeTerminalPosition =
      ValueNotifier(null);

  /// Whether the map editor sidebar is active.
  final ValueNotifier<bool> mapEditorActive = ValueNotifier(false);

  MapPreviewComponent? _mapPreviewComponent;
  WallOcclusionComponent? _wallOcclusion;
  TileFloorComponent? _tileFloor;
  TileObjectLayerComponent? _tileObjectLayer;

  /// Close the code editor panel.
  void closeEditor() {
    // Only publish if we were actually in the editor.
    if (activeChallenge.value != null) {
      _liveKitService?.publishTerminalActivity(action: 'close');
    }
    activeChallenge.value = null;
    activeTerminalPosition.value = null;
  }

  /// Enter map editor mode — shows preview overlay on the canvas.
  void enterEditorMode(MapEditorState editorState) {
    // Close code editor if open (also notifies the bot).
    closeEditor();

    // Pre-load the current map so the editor and canvas show existing layout.
    editorState.loadFromGameMap(currentMap.value);

    mapEditorActive.value = true;

    // Hide wall occlusion overlays and tile objects during editing.
    _wallOcclusion?.hide();
    _tileObjectLayer?.hide();

    // Hide normal barriers and add the preview component.
    _barriersComponent.renderBarriers = false;
    _mapPreviewComponent = MapPreviewComponent(editorState: editorState);
    add(_mapPreviewComponent!);

    // Listen for editor changes to update pathfinding grid.
    _editorState = editorState;
    editorState.addListener(_onEditorStateChanged);
  }

  /// Exit map editor mode — removes preview, applies editor changes to game.
  void exitEditorMode() {
    mapEditorActive.value = false;

    // Apply the editor's map to the game world so background / barriers
    // reflect whatever was edited (e.g. loading a predefined map in a new room).
    if (_editorState != null) {
      _applyEditorBackground(_editorState!);
    }

    // Stop listening for editor changes.
    _editorState?.removeListener(_onEditorStateChanged);
    _editorState = null;

    // Restore wall occlusion overlays and tile objects.
    _wallOcclusion?.show();
    _tileObjectLayer?.show();

    // Rebuild pathfinding grid from default barriers.
    _pathComponent?.invalidateGrid();

    if (_mapPreviewComponent != null) {
      _mapPreviewComponent!.removeFromParent();
      _mapPreviewComponent = null;
    }
    _barriersComponent.renderBarriers = !currentMap.value.usesTilesets;
  }

  /// Sync the game world's background sprite with the editor state.
  ///
  /// When the user loads a different map in the editor (e.g. a predefined map
  /// in a new room), the game world's [_backgroundSprite] may not match. This
  /// method adds/removes the sprite so exiting the editor shows the correct
  /// background.
  void _applyEditorBackground(MapEditorState editor) {
    final editorBg = editor.backgroundImage;
    final currentBg = currentMap.value.backgroundImage;

    // Nothing to change.
    if (editorBg == currentBg) return;

    final game = findGame() as TechWorldGame?;
    if (game == null) return;

    // Remove old background sprite if present.
    if (_backgroundSprite != null) {
      _backgroundSprite!.removeFromParent();
      _backgroundSprite = null;
    }

    // Remove old wall occlusion (tied to the old background).
    if (_wallOcclusion != null) {
      _wallOcclusion!.removeFromParent();
      _wallOcclusion = null;
    }

    // Add new background sprite if the editor has one.
    if (editorBg != null && game.images.containsKey(editorBg)) {
      final bgImage = game.images.fromCache(editorBg);
      _backgroundSprite =
          SpriteComponent(sprite: Sprite(bgImage), priority: -1);
      add(_backgroundSprite!);

      // Recreate wall occlusion for the new background.
      final editedMap = editor.toGameMap();
      _wallOcclusion = WallOcclusionComponent(
        backgroundImage: bgImage,
        barriers: editedMap.barriers,
      );
      add(_wallOcclusion!);

      // Update currentMap so the rest of the system sees the change.
      currentMap.value = editedMap;
    }
  }

  MapEditorState? _editorState;

  /// Called when the editor state changes — rebuild pathfinding grid.
  void _onEditorStateChanged() {
    _pathComponent?.setGridFromEditor(_editorState!);
  }

  /// Check if a challenge is completed via the [ProgressService].
  bool _isChallengeCompleted(String challengeId) {
    return Locator.maybeLocate<ProgressService>()
            ?.isChallengeCompleted(challengeId) ??
        false;
  }

  /// Update all terminal components' [isCompleted] state from current progress.
  void refreshTerminalStates() {
    for (var i = 0; i < _terminalComponents.length; i++) {
      final challengeIndex = i % allChallenges.length;
      _terminalComponents[i].isCompleted =
          _isChallengeCompleted(allChallenges[challengeIndex].id);
    }
  }

  static const _terminalProximityThreshold = 2; // grid squares

  final Stream<AuthUser> _authStateChanges;
  StreamSubscription<AuthUser>? _authStateChangesSubscription;
  StreamSubscription<(Participant, VideoTrack)>? _trackSubscribedSubscription;
  StreamSubscription<LocalTrackPublication>? _localTrackPublishedSubscription;
  StreamSubscription<PlayerPath>? _liveKitPositionSubscription;
  StreamSubscription<RemoteParticipant>? _participantJoinedSubscription;
  StreamSubscription<RemoteParticipant>? _participantLeftSubscription;
  StreamSubscription<AvatarUpdate>? _avatarSubscription;

  // Avatar tracking — stores updates for players not yet created
  final Map<String, String> _pendingAvatars = {};
  Avatar? _localAvatar;

  /// Set the local player's avatar. Also broadcasts to other participants.
  void setLocalAvatar(Avatar avatar) {
    _localAvatar = avatar;
    _userPlayerComponent.spriteAsset = avatar.spriteAsset;
    _liveKitService?.publishAvatar(avatar);
  }

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
    playerGridPosition.value = playerGrid;

    // Check each other player for proximity
    final nearbyPlayerIds = <String>{};
    int closestDistance = _visualThreshold + 1;

    for (final entry in _otherPlayerComponentsMap.entries) {
      final playerId = entry.key;
      final playerComponent = entry.value;

      // Calculate Chebyshev distance (max of x/y difference)
      final otherGrid = playerComponent.miniGridPosition;
      final distance = max(
        (otherGrid.x - playerGrid.x).abs(),
        (otherGrid.y - playerGrid.y).abs(),
      );

      final isVisible = distance <= _visualThreshold;

      if (isVisible) {
        nearbyPlayerIds.add(playerId);
        if (distance < closestDistance) closestDistance = distance;

        if (!_playerBubbles.containsKey(playerId)) {
          // Create bubble for this player
          final bubble = _createBubbleForPlayer(playerId, playerComponent);
          bubble.position = playerComponent.position + _bubbleOffset;
          _playerBubbles[playerId] = bubble;
          add(bubble);
        }

        // Set opacity based on distance
        _setBubbleOpacity(_playerBubbles[playerId]!, distance);

        // Manage audio: enable within audio threshold, disable outside
        _updateParticipantAudio(playerId, distance);
      } else {
        // Beyond visual range — ensure audio is disabled
        _updateParticipantAudio(playerId, distance);
      }
    }

    // Check proximity to bot character
    if (_botCharacterComponent != null) {
      final botGrid = _botCharacterComponent!.miniGridPosition;
      final botDistance = max(
        (botGrid.x - playerGrid.x).abs(),
        (botGrid.y - playerGrid.y).abs(),
      );

      if (botDistance <= _visualThreshold) {
        nearbyPlayerIds.add(_botUserId);
        if (botDistance < closestDistance) closestDistance = botDistance;

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
      // Local bubble opacity matches the closest other player
      _setBubbleOpacity(_playerBubbles[_localPlayerBubbleKey]!, closestDistance);
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

  /// Apply opacity to a bubble component (works for both Video and Player types).
  void _setBubbleOpacity(PositionComponent bubble, int distance) {
    final opacity = ProximityService.calculateOpacity(distance);
    if (bubble is VideoBubbleComponent) {
      bubble.opacity = opacity;
    } else if (bubble is PlayerBubbleComponent) {
      bubble.opacity = opacity;
    }
    // BotBubbleComponent doesn't fade — it stays fully visible when in range
  }

  /// Enable or disable audio for a participant based on distance.
  void _updateParticipantAudio(String playerId, int distance) {
    final shouldHaveAudio = distance <= _audioThreshold;
    final hasAudio = _audioEnabledParticipants.contains(playerId);

    if (shouldHaveAudio && !hasAudio) {
      _audioEnabledParticipants.add(playerId);
      _liveKitService?.setParticipantAudioEnabled(playerId, true);
    } else if (!shouldHaveAudio && hasAudio) {
      _audioEnabledParticipants.remove(playerId);
      _liveKitService?.setParticipantAudioEnabled(playerId, false);
    }
  }

  void _updateBubblePositions() {
    for (final entry in _playerBubbles.entries) {
      if (entry.key == _localPlayerBubbleKey) {
        entry.value.position = _userPlayerComponent.position + _bubbleOffset;
        entry.value.priority = _userPlayerComponent.priority + 1;
      } else if (entry.key == _botUserId) {
        if (_botCharacterComponent != null) {
          entry.value.position =
              _botCharacterComponent!.position + _bubbleOffset;
          entry.value.priority = _botCharacterComponent!.priority + 1;
        }
      } else {
        final playerComponent = _otherPlayerComponentsMap[entry.key];
        if (playerComponent != null) {
          entry.value.position = playerComponent.position + _bubbleOffset;
          entry.value.priority = playerComponent.priority + 1;
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

  /// Handle a participant joining the room
  void _handleParticipantJoined(RemoteParticipant participant) {
    debugPrint('LiveKit participant joined: ${participant.identity}');
    _refreshBubbleForPlayer(participant.identity);

    // Create component based on participant type
    if (participant.identity == _botUserId) {
      // Create bot character component at the map's spawn point
      if (_botCharacterComponent == null) {
        final spawn = currentMap.value.spawnPoint;
        _botCharacterComponent = BotCharacterComponent(
          position: Vector2(
            spawn.x * gridSquareSizeDouble,
            spawn.y * gridSquareSizeDouble,
          ),
          id: participant.identity,
          displayName: 'Claude',
        );
        add(_botCharacterComponent!);
      }

      // Send the current map layout so the bot knows about barriers/terminals
      _liveKitService?.publishMapInfo(currentMap.value);
    } else if (!_otherPlayerComponentsMap.containsKey(participant.identity)) {
      // Apply pending avatar if one arrived before the component was created
      final pendingSpriteAsset = _pendingAvatars.remove(participant.identity);

      final playerComponent = PlayerComponent(
        position: Vector2.zero(),
        id: participant.identity,
        displayName: participant.name.isNotEmpty
            ? participant.name
            : participant.identity,
        spriteAsset: pendingSpriteAsset ?? defaultAvatar.spriteAsset,
      );
      _otherPlayerComponentsMap[participant.identity] = playerComponent;
      add(playerComponent);
    }
  }

  /// Handle an avatar update from a remote player.
  void _handleAvatarUpdate(AvatarUpdate update) {
    final playerComponent = _otherPlayerComponentsMap[update.playerId];
    if (playerComponent != null) {
      playerComponent.spriteAsset = update.spriteAsset;
    } else {
      // Player component doesn't exist yet — store for later
      _pendingAvatars[update.playerId] = update.spriteAsset;
    }
  }

  /// Connect to LiveKit room.
  ///
  /// Safe to call multiple times — returns immediately if already connected.
  /// Called from [main.dart] after [LiveKitService] is registered and connected,
  /// since TechWorld's own auth listener may fire before the service exists.
  Future<void> connectToLiveKit(String userId, String displayName) async {
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
        // Animate bot along the full path, just like player movement.
        _botCharacterComponent?.move(path.largeGridPoints);
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

    // Subscribe to avatar updates from other players
    _avatarSubscription =
        _liveKitService!.avatarReceived.listen(_handleAvatarUpdate);

    // Listen for participant join/leave to manage player presence
    _participantJoinedSubscription =
        _liveKitService!.participantJoined.listen(_handleParticipantJoined);

    // Check for existing participants that joined before we subscribed
    for (final participant in _liveKitService!.remoteParticipants.values) {
      debugPrint('TechWorld: Found existing participant: ${participant.identity}');
      _handleParticipantJoined(participant);
    }

    _participantLeftSubscription =
        _liveKitService!.participantLeft.listen((participant) {
      debugPrint('LiveKit participant left: ${participant.identity}');

      // Remove component based on participant type
      if (participant.identity == _botUserId) {
        if (_botCharacterComponent != null) {
          remove(_botCharacterComponent!);
          _botCharacterComponent = null;
        }
      } else {
        final playerComponent =
            _otherPlayerComponentsMap.remove(participant.identity);
        if (playerComponent != null) {
          remove(playerComponent);
        }
      }

      final bubble = _playerBubbles.remove(participant.identity);
      bubble?.removeFromParent();
    });

    _liveKitService!.speakingChanged.listen((event) {
      final (participant, isSpeaking) = event;
      _updateBubbleSpeakingState(participant.identity, isSpeaking);
    });

    // Listen for track subscription events to upgrade placeholder bubbles to video
    _trackSubscribedSubscription =
        _liveKitService!.trackSubscribed.listen((event) {
      final (participant, track) = event;
      if (track.kind == TrackType.VIDEO) {
        debugPrint('TechWorld: Video track subscribed for ${participant.identity}, refreshing bubble');
        // This will upgrade PlayerBubbleComponent to VideoBubbleComponent
        _refreshBubbleForPlayer(participant.identity);
      }
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

      // Re-publish avatar so late joiners see our character
      if (_localAvatar != null) {
        _liveKitService!.publishAvatar(_localAvatar!);
      }
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

    // Grid lines hidden for now — uncomment to restore:
    // await add(_gridComponent);
    await add(_pathComponent!);
    await add(_userPlayerComponent);

    // Load initial map components.
    await _loadMapComponents(currentMap.value);

    final game = findGame() as TechWorldGame?;
    game?.camera.follow(_userPlayerComponent);

    // Load the video bubble shader
    await _loadVideoBubbleShader();

    _authStateChangesSubscription = _authStateChanges.listen((authUser) async {
      if (authUser is SignedOutUser) {
        // User signed out - clear LiveKit state so we can reconnect on next sign-in
        _disconnectFromLiveKit();
        // Clear stale terminal completion indicators from the previous user.
        refreshTerminalStates();
      } else if (authUser is! PlaceholderUser) {
        _userPlayerComponent.id = authUser.id;
        _userPlayerComponent.displayName = authUser.displayName;

        // Connect to LiveKit when user is authenticated
        await connectToLiveKit(authUser.id, authUser.displayName);
      }
    });
  }

  /// Load map-specific components: barriers, terminals, background, and wall
  /// occlusion overlays.
  Future<void> _loadMapComponents(GameMap map) async {
    // Barriers
    _barriersComponent = BarriersComponent(barriers: map.barriers);
    await add(_barriersComponent);
    _pathComponent?.barriers = _barriersComponent;

    // Terminals
    for (var i = 0; i < map.terminals.length; i++) {
      final terminalPos = map.terminals[i];
      final challengeIndex = i % allChallenges.length;
      final challenge = allChallenges[challengeIndex];
      final terminal = TerminalComponent(
        position: Vector2(
          terminalPos.x * gridSquareSizeDouble,
          terminalPos.y * gridSquareSizeDouble,
        ),
        onInteract: () => _onTerminalInteract(terminalPos, challenge),
        isCompleted: _isChallengeCompleted(challenge.id),
      );
      _terminalComponents.add(terminal);
      await add(terminal);
    }

    // Tile layers (tileset-based maps) or background image + wall occlusion.
    final game = findGame() as TechWorldGame?;
    if (game != null && map.usesTilesets) {
      // Tileset-based rendering.
      final registry = game.tilesetRegistry;

      if (map.floorLayer != null) {
        _tileFloor = TileFloorComponent(
          layerData: map.floorLayer!,
          registry: registry,
        );
        await add(_tileFloor!);
      }

      if (map.objectLayer != null) {
        _tileObjectLayer = TileObjectLayerComponent(
          layerData: map.objectLayer!,
          registry: registry,
        );
        await add(_tileObjectLayer!);
      }
    } else if (game != null && map.backgroundImage != null) {
      // Legacy background image rendering.
      final bgImage = game.images.fromCache(map.backgroundImage!);
      _backgroundSprite =
          SpriteComponent(sprite: Sprite(bgImage), priority: -1);
      add(_backgroundSprite!);

      _wallOcclusion = WallOcclusionComponent(
        backgroundImage: bgImage,
        barriers: map.barriers,
      );
      await add(_wallOcclusion!);
    }
  }

  /// Remove all map-specific components before loading a new map.
  void _removeMapComponents() {
    // Barriers
    _barriersComponent.removeBarriers();
    _barriersComponent.removeFromParent();

    // Terminals
    for (final terminal in _terminalComponents) {
      terminal.removeFromParent();
    }
    _terminalComponents.clear();

    // Background
    _backgroundSprite?.removeFromParent();
    _backgroundSprite = null;

    // Wall occlusion
    if (_wallOcclusion != null) {
      _wallOcclusion!.removeFromParent();
      _wallOcclusion = null;
    }

    // Tile layers
    if (_tileFloor != null) {
      _tileFloor!.removeFromParent();
      _tileFloor = null;
    }
    if (_tileObjectLayer != null) {
      _tileObjectLayer!.removeFromParent();
      _tileObjectLayer = null;
    }
  }

  /// Switch to a different map at runtime.
  Future<void> loadMap(GameMap map) async {
    if (map.id == currentMap.value.id) return; // Already on this map.

    // Auto-exit editor mode if active.
    if (mapEditorActive.value) exitEditorMode();

    // Close code editor if open — the terminals are about to change.
    closeEditor();

    _removeMapComponents();
    await _loadMapComponents(map);

    // Reposition player to new map's spawn point.
    _userPlayerComponent.position = Vector2(
      map.spawnPoint.x * gridSquareSizeDouble,
      map.spawnPoint.y * gridSquareSizeDouble,
    );
    playerGridPosition.value = map.spawnPoint;

    currentMap.value = map;

    // Notify the bot about the new map layout
    _liveKitService?.publishMapInfo(map);
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    final worldPosition = event.localPosition;
    int miniGridX = (worldPosition.x / gridSquareSize).floor();
    int miniGridY = (worldPosition.y / gridSquareSize).floor();

    final pathComponent = _pathComponent;
    if (pathComponent == null) return;

    pathComponent.calculatePath(
        start: _userPlayerComponent.miniGridTuple, end: (miniGridX, miniGridY));

    _userPlayerComponent.move(
        pathComponent.directions, pathComponent.largeGridPoints);

    // Publish position via LiveKit data channel
    _liveKitService?.publishPosition(
      points: pathComponent.largeGridPoints,
      directions: pathComponent.directions,
    );
  }

  /// Handle terminal interaction - check proximity before opening editor.
  void _onTerminalInteract(Point<int> terminalPos, Challenge challenge) {
    final playerGrid = _userPlayerComponent.miniGridPosition;
    final distance = max(
      (terminalPos.x - playerGrid.x).abs(),
      (terminalPos.y - playerGrid.y).abs(),
    );
    if (distance <= _terminalProximityThreshold) {
      activeChallenge.value = challenge.id;
      activeTerminalPosition.value = terminalPos;

      // Notify the bot that we opened a terminal editor.
      _liveKitService?.publishTerminalActivity(
        action: 'open',
        challengeId: challenge.id,
        challengeTitle: challenge.title,
        challengeDescription: challenge.description,
        terminalX: terminalPos.x,
        terminalY: terminalPos.y,
      );
    } else {
      _showHint(
        'Walk closer to use this terminal',
        Vector2(
          terminalPos.x * gridSquareSizeDouble + gridSquareSizeDouble / 2,
          terminalPos.y * gridSquareSizeDouble - 12,
        ),
      );
    }
  }

  /// Show an ephemeral text hint that fades out after a short delay.
  void _showHint(String message, Vector2 position) {
    final hint = TextComponent(
      text: message,
      position: position,
      anchor: Anchor.bottomCenter,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      priority: 1000,
    );
    add(hint);
    Future.delayed(const Duration(seconds: 2), () {
      hint.removeFromParent();
    });
  }

  /// Disconnect from LiveKit and clear all related state.
  /// Called when user signs out so we can reconnect on next sign-in.
  void _disconnectFromLiveKit() {
    debugPrint('TechWorld: Disconnecting from LiveKit');

    // Cancel all LiveKit-related subscriptions
    _trackSubscribedSubscription?.cancel();
    _trackSubscribedSubscription = null;
    _localTrackPublishedSubscription?.cancel();
    _localTrackPublishedSubscription = null;
    _liveKitPositionSubscription?.cancel();
    _liveKitPositionSubscription = null;
    _participantJoinedSubscription?.cancel();
    _participantJoinedSubscription = null;
    _participantLeftSubscription?.cancel();
    _participantLeftSubscription = null;
    _avatarSubscription?.cancel();
    _avatarSubscription = null;

    // Clear pending avatar data
    _pendingAvatars.clear();

    // Clear the service reference so _connectToLiveKit can reconnect
    _liveKitService = null;

    // Remove all player bubbles
    for (final bubble in _playerBubbles.values) {
      bubble.removeFromParent();
    }
    _playerBubbles.clear();
    _audioEnabledParticipants.clear();

    // Remove other player components
    for (final component in _otherPlayerComponentsMap.values) {
      component.removeFromParent();
    }
    _otherPlayerComponentsMap.clear();

    // Remove bot character
    if (_botCharacterComponent != null) {
      _botCharacterComponent!.removeFromParent();
      _botCharacterComponent = null;
    }

    // Reset position tracking
    _lastPlayerGridPosition = null;
  }

  void dispose() {
    _authStateChangesSubscription?.cancel();
    activeChallenge.dispose();
    activeTerminalPosition.dispose();
    mapEditorActive.dispose();
    currentMap.dispose();
    _disconnectFromLiveKit();
  }
}

