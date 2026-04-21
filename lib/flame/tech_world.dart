import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, Colors, FontWeight, TextStyle;
import 'package:logging/logging.dart';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/bots/bot_config.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/editor/predefined_challenges.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/components/door_component.dart';
import 'package:tech_world/flame/maps/barrier_occlusion.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/bot_character_component.dart';
import 'package:tech_world/flame/components/dreamfinder_component.dart';
import 'package:tech_world/flame/components/map_preview_component.dart';
import 'package:tech_world/flame/components/player_bubble_component.dart';
import 'package:tech_world/flame/components/tile_floor_component.dart';
import 'package:tech_world/flame/components/tile_object_layer_component.dart';
// Grid lines — uncomment for visual debugging:
// import 'package:tech_world/flame/components/grid_component.dart';
import 'package:tech_world/flame/components/path_component.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/components/terminal_component.dart';
import 'package:tech_world/flame/components/video_bubble_component.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/predefined_maps.dart';
import 'package:tech_world/flame/maps/door_data.dart';
import 'package:tech_world/flame/maps/terminal_mode.dart';
import 'package:tech_world/prompt/predefined_prompt_challenges.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/tileset_cache_provider.dart';
import 'package:tech_world/flame/tiles/tileset_storage_service.dart';
import 'package:tech_world/flame/tiles/tileset.dart';
import 'package:tech_world/flame/tiles/tileset_registry.dart';
import 'package:tech_world/flame/tiles/wall_style_def.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';
import 'package:tech_world/map_editor/map_sync_service.dart';
import 'package:tech_world/flame/shared/player_path.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/avatar/avatar.dart';
import 'package:tech_world/avatar/predefined_avatars.dart';
import 'package:tech_world/livekit/dreamfinder_avatar_bridge.dart';
import 'package:tech_world/livekit/livekit_service.dart';
import 'package:tech_world/proximity/proximity_service.dart';
import 'package:tech_world/progress/progress_service.dart';
import 'package:tech_world/utils/locator.dart';

final _log = Logger('TechWorld');

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
  final Map<String, BotCharacterComponent> _botCharacterComponents = {};
  DreamfinderComponent? _dreamfinderComponent;
  /// The LiveKit identity of the active Dreamfinder participant.
  /// Defaults to [dreamfinderBot.identity] (`bot-dreamfinder`) but updated
  /// at runtime when the embodied agent joins with an `agent-{jobId}` identity.
  String _dreamfinderIdentity = dreamfinderBot.identity;
  DreamfinderAvatarBridge? _dreamfinderAvatarBridge;
  // final GridComponent _gridComponent = GridComponent();
  BarriersComponent _barriersComponent =
      BarriersComponent(barriers: defaultMap.barriers);
  PathComponent? _pathComponent;

  /// The currently loaded map.
  final ValueNotifier<GameMap> currentMap = ValueNotifier(defaultMap);

  final List<TerminalComponent> _terminalComponents = [];
  final List<DoorComponent> _doorComponents = [];

  // Bubble components - shown when player is near other players
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

  /// Notifier for active code challenge ID. Null means no editor open.
  final ValueNotifier<String?> activeChallenge = ValueNotifier(null);

  /// Notifier for active prompt challenge ID. Null means no prompt panel open.
  final ValueNotifier<String?> activePromptChallenge = ValueNotifier(null);

  /// Grid position of the terminal the player is currently interacting with.
  /// Null when no editor is open.
  final ValueNotifier<Point<int>?> activeTerminalPosition =
      ValueNotifier(null);

  /// Whether the map editor sidebar is active.
  final ValueNotifier<bool> mapEditorActive = ValueNotifier(false);

  MapPreviewComponent? _mapPreviewComponent;
  TileFloorComponent? _tileFloor;
  TileObjectLayerComponent? _tileObjectLayer;
  bool _isLoadingMap = false;

  /// Signals when the game world has finished loading and is ready to display.
  ///
  /// Set to `true` at the end of [onLoad] (initial mount) or after
  /// [_loadMapComponents] completes during a runtime map switch.
  final ValueNotifier<bool> gameReady = ValueNotifier(false);

  /// Pre-fetched tileset image bytes, keyed by tileset ID.
  ///
  /// Populated by [prefetchTilesetBytes] before the game engine mounts so
  /// that [_loadMapComponents] can consume them (via `.remove()`) instead of
  /// downloading again. The `.remove()` call frees memory after decode.
  final Map<String, Uint8List> _tilesetByteCache = {};

  /// Download tileset image bytes into [_tilesetByteCache] for [map].
  ///
  /// Call this *before* the game engine mounts so that downloads overlap
  /// with LiveKit connection and other setup. When [_loadMapComponents]
  /// later needs bytes, it pulls from the cache instead of re-downloading.
  ///
  /// Only fetches tilesets not already loaded in the registry (which isn't
  /// available pre-mount, so we check conservatively).
  Future<void> prefetchTilesetBytes(GameMap map) async {
    final storageService = TilesetStorageService();
    final futures = <Future<void>>[];

    // Custom tilesets (e.g. user-uploaded).
    for (final tileset in map.customTilesets) {
      if (_tilesetByteCache.containsKey(tileset.id)) continue;
      futures.add(() async {
        try {
          final bytes = await storageService.downloadTilesetImage(tileset.id);
          if (bytes != null) _tilesetByteCache[tileset.id] = bytes;
        } catch (e) {
          _log.warning('prefetchTilesetBytes: failed for ${tileset.id}', e);
        }
      }());
    }

    // Wall tilesets.
    if (map.walls.isNotEmpty) {
      final neededIds = <String>{};
      for (final styleId in map.walls.values) {
        final style = lookupWallStyle(styleId);
        if (style != null && !_tilesetByteCache.containsKey(style.tilesetId)) {
          neededIds.add(style.tilesetId);
        }
      }
      if (neededIds.isNotEmpty) {
        final downloader = await createCachedDownloader(
          (id) => storageService.downloadTilesetImage(id),
        );
        for (final id in neededIds) {
          futures.add(() async {
            try {
              final bytes = await downloader(id);
              if (bytes != null) _tilesetByteCache[id] = bytes;
            } catch (e) {
              _log.warning('prefetchTilesetBytes: failed for $id', e);
            }
          }());
        }
      }
    }

    await Future.wait(futures);
    _log.info('prefetchTilesetBytes: cached ${_tilesetByteCache.keys}');
  }

  /// Close the code editor panel.
  void closeEditor() {
    // Only publish if we were actually in the editor.
    if (activeChallenge.value != null) {
      _liveKitService?.publishTerminalActivity(action: 'close');
    }
    activeChallenge.value = null;
    activePromptChallenge.value = null;
    activeTerminalPosition.value = null;
  }

  /// Enter map editor mode — shows preview overlay on the canvas.
  void enterEditorMode(MapEditorState editorState) {
    // Close code editor if open (also notifies the bot).
    closeEditor();

    // Pre-load the current map so the editor and canvas show existing layout.
    editorState.loadFromGameMap(currentMap.value);

    mapEditorActive.value = true;

    // Create collaborative sync service if LiveKit is connected.
    if (_liveKitService != null) {
      _mapSyncService = MapSyncService(
        liveKitService: _liveKitService!,
        editorState: editorState,
        localPlayerId: _userPlayerComponent.id,
      );
      Locator.add<MapSyncService>(_mapSyncService!);
    }

    // Hide tile objects during editing.
    _tileObjectLayer?.hide();

    // Hide normal barriers and add the preview component.
    _barriersComponent.renderBarriers = false;
    _mapPreviewComponent = MapPreviewComponent(editorState: editorState);
    add(_mapPreviewComponent!);

    // Listen for editor changes to update pathfinding grid.
    _editorState = editorState;
    editorState.addListener(_onEditorStateChanged);
  }

  /// Exit map editor mode — removes preview, optionally applies changes.
  ///
  /// When [applyChanges] is true (the default), the edited map is compared
  /// to [currentMap] and applied if different. When false, edits are discarded
  /// and the original map components are simply re-shown.
  Future<void> exitEditorMode({bool applyChanges = true}) async {
    mapEditorActive.value = false;

    if (applyChanges && _editorState != null) {
      // Apply the full edited map to the game world so barriers, terminals,
      // and tile layers all reflect whatever was changed.
      final editedMap = _editorState!.toGameMap();
      if (editedMap != currentMap.value) {
        _removeMapComponents();
        await _loadMapComponents(editedMap);
        currentMap.value = editedMap;
      } else {
        _tileObjectLayer?.show();
      }
    } else {
      // Discard — just re-show the original tile objects.
      _tileObjectLayer?.show();
    }

    // Stop listening for editor changes.
    _editorState?.removeListener(_onEditorStateChanged);
    _editorState = null;

    // Dispose collaborative sync service.
    if (_mapSyncService != null) {
      _mapSyncService!.dispose();
      Locator.remove<MapSyncService>();
      _mapSyncService = null;
    }

    // Rebuild pathfinding grid from default barriers.
    _pathComponent?.invalidateGrid();

    if (_mapPreviewComponent != null) {
      _mapPreviewComponent!.removeFromParent();
      _mapPreviewComponent = null;
    }
    // Show debug barriers only for maps without visual layers. Maps with
    // tilesets render walls visually, so the blue debug rectangles would be
    // distracting.
    _barriersComponent.renderBarriers = !currentMap.value.usesTilesets;
  }

  MapEditorState? _editorState;
  MapSyncService? _mapSyncService;

  /// Called when the editor state changes — rebuild pathfinding grid.
  void _onEditorStateChanged() {
    final editor = _editorState;
    if (editor == null) return;
    _pathComponent?.setGridFromEditor(editor);
  }

  /// Check if a challenge is completed via the [ProgressService].
  bool _isChallengeCompleted(String challengeId) {
    return Locator.maybeLocate<ProgressService>()
            ?.isChallengeCompleted(challengeId) ??
        false;
  }

  /// Update all terminal components' [isCompleted] state from current progress.
  void refreshTerminalStates() {
    // Only code-mode terminals track challenge completion.
    if (currentMap.value.terminalMode != TerminalMode.code) return;
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
  StreamSubscription<(Participant, VideoTrack)>?
      _trackUnsubscribedSubscription;
  StreamSubscription<LocalTrackPublication>? _localTrackPublishedSubscription;
  StreamSubscription<PlayerPath>? _liveKitPositionSubscription;
  StreamSubscription<RemoteParticipant>? _participantJoinedSubscription;
  StreamSubscription<RemoteParticipant>? _participantLeftSubscription;
  StreamSubscription<AvatarUpdate>? _avatarSubscription;
  StreamSubscription<(Participant, bool)>? _speakingSubscription;
  StreamSubscription<String?>? _connectionLostSubscription;
  StreamSubscription<void>? _mapInfoRequestedSubscription;

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
    // Include all bot positions
    for (final entry in _botCharacterComponents.entries) {
      positions[entry.key] = entry.value.miniGridPosition;
    }
    if (_dreamfinderComponent != null) {
      positions[_dreamfinderIdentity] =
          _dreamfinderComponent!.miniGridPosition;
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

    // Check proximity to Dreamfinder (separate from other bots — has its
    // own component type and can publish a video track for the holographic
    // wizard projection).
    if (_dreamfinderComponent != null) {
      final dfGrid = _dreamfinderComponent!.miniGridPosition;
      final dfDistance = max(
        (dfGrid.x - playerGrid.x).abs(),
        (dfGrid.y - playerGrid.y).abs(),
      );

      if (dfDistance <= _visualThreshold) {
        nearbyPlayerIds.add(_dreamfinderIdentity);
        if (dfDistance < closestDistance) closestDistance = dfDistance;

        if (!_playerBubbles.containsKey(_dreamfinderIdentity)) {
          // Create Dreamfinder's video bubble eagerly once the participant
          // exists. The video track may subscribe slightly later than the
          // participant join event, so gating bubble creation on _hasVideoTrack
          // can leave the hologram stuck on a static placeholder forever.
          final dfParticipant =
              _liveKitService?.getParticipant(_dreamfinderIdentity);
          PositionComponent bubble;
          if (dfParticipant != null) {
            bubble = _createDreamfinderVideoBubble(dfParticipant);
          } else {
            bubble = BotBubbleComponent();
          }
          bubble.position =
              _dreamfinderComponent!.position + _bubbleOffset;
          _playerBubbles[_dreamfinderIdentity] = bubble;
          add(bubble);
        }
      }
    }

    // Check proximity to all bot characters
    for (final entry in _botCharacterComponents.entries) {
      final botId = entry.key;
      final botComp = entry.value;
      final botGrid = botComp.miniGridPosition;
      final botDistance = max(
        (botGrid.x - playerGrid.x).abs(),
        (botGrid.y - playerGrid.y).abs(),
      );

      if (botDistance <= _visualThreshold) {
        nearbyPlayerIds.add(botId);
        if (botDistance < closestDistance) closestDistance = botDistance;

        if (!_playerBubbles.containsKey(botId)) {
          final bubble = BotBubbleComponent();
          bubble.position = botComp.position + _bubbleOffset;
          _playerBubbles[botId] = bubble;
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
      } else if (entry.key == _dreamfinderIdentity &&
          _dreamfinderComponent != null) {
        entry.value.position =
            _dreamfinderComponent!.position + _bubbleOffset;
        entry.value.priority = _dreamfinderComponent!.priority + 1;
      } else if (_botCharacterComponents.containsKey(entry.key)) {
        final botComp = _botCharacterComponents[entry.key]!;
        entry.value.position = botComp.position + _bubbleOffset;
        entry.value.priority = botComp.priority + 1;
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

  /// Initialize the Dreamfinder 3D avatar bridge (web only).
  ///
  /// Creates a hidden iframe that renders the Three.js avatar, then captures
  /// frames from its canvas for display as a [VideoBubbleComponent] in the
  /// Flame world. Also forwards audio and mood data channels to the iframe
  /// for lip-sync and expression changes.
  void _initDreamfinderAvatarBridge() {
    if (_dreamfinderAvatarBridge != null) return;
    final liveKit = _liveKitService;
    if (liveKit == null) return;

    _dreamfinderAvatarBridge =
        DreamfinderAvatarBridge(liveKitService: liveKit);
    _dreamfinderAvatarBridge!.initialize().then((_) {
      if (_dreamfinderAvatarBridge?.isReady == true) {
        _log.info('Dreamfinder avatar bridge ready — refreshing bubble');
        _refreshBubbleForPlayer(_dreamfinderIdentity);
      }
    });
  }

  /// Create a [VideoBubbleComponent] configured for Dreamfinder's holographic
  /// wizard projection (gold glow, 10fps for ethereal quality).
  ///
  /// If the 3D avatar bridge is active, uses its [CanvasCapture] as the frame
  /// source instead of a LiveKit video track (which DF does not publish).
  VideoBubbleComponent _createDreamfinderVideoBubble(
      Participant participant) {
    final videoBubble = VideoBubbleComponent(
      participant: participant,
      displayName: dreamfinderBot.displayName,
      bubbleSize: 64,
      targetFps: 10,
      externalCanvasCapture: _dreamfinderAvatarBridge?.canvasCapture,
    );
    videoBubble.glowColor = const Color(0xFFDAA520); // gold
    videoBubble.glowIntensity = 0.7;
    return videoBubble;
  }

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
    _log.info('LiveKit participant joined: ${participant.identity}');
    _refreshBubbleForPlayer(participant.identity);

    // Create component based on participant type
    if (isBotIdentity(participant.identity)) {
      final botConfig = getBotConfig(participant.identity);
      final spawn = currentMap.value.spawnPoint;
      // Stable spawn offset based on registry order (not arrival order),
      // so reconnecting bots always land in the same position.
      final botIndex =
          allBotIdentities.toList().indexOf(participant.identity);

      if (isDreamfinderIdentity(participant.identity) &&
          _pathComponent != null) {
        // Dreamfinder — use DreamfinderComponent with idle behavior.
        // Update identity to match whatever the agent SDK assigned
        // (e.g. `agent-{jobId}` instead of `bot-dreamfinder`).
        _dreamfinderIdentity = participant.identity;
        if (_dreamfinderComponent == null) {
          final dfComp = DreamfinderComponent(
            position: Vector2(
              (spawn.x + 8).clamp(0, gridSize - 1) * gridSquareSizeDouble,
              (spawn.y - 5).clamp(0, gridSize - 1) * gridSquareSizeDouble,
            ),
            id: participant.identity,
            displayName: botConfig.displayName,
            pathComponent: _pathComponent!,
          );
          _dreamfinderComponent = dfComp;
          add(dfComp);

          // If the local user is already connected, notice them.
          if (_userPlayerComponent.id.isNotEmpty) {
            dfComp.noticePlayer(_userPlayerComponent.position);
          }

          // Initialize the 3D avatar bridge (web only — loads iframe renderer).
          _initDreamfinderAvatarBridge();
        }
      } else if (botConfig.spriteSheetAsset != null) {
        // Other animated bot — use PlayerComponent with sprite sheet.
        if (!_otherPlayerComponentsMap.containsKey(participant.identity)) {
          final playerComp = PlayerComponent(
            position: Vector2(
              (spawn.x + botIndex + 1) * gridSquareSizeDouble,
              spawn.y * gridSquareSizeDouble,
            ),
            id: participant.identity,
            displayName: botConfig.displayName,
            spriteAsset: botConfig.spriteSheetAsset!,
            frameCount: botConfig.spriteFrameCount,
          );
          _otherPlayerComponentsMap[participant.identity] = playerComp;
          add(playerComp);
        }
      } else {
        // Static bot — use BotCharacterComponent.
        if (!_botCharacterComponents.containsKey(participant.identity)) {
          final botComp = BotCharacterComponent(
            position: Vector2(
              (spawn.x + botIndex + 1) * gridSquareSizeDouble,
              spawn.y * gridSquareSizeDouble,
            ),
            id: participant.identity,
            displayName: botConfig.displayName,
            spriteAsset: botConfig.spriteAsset,
          );
          _botCharacterComponents[participant.identity] = botComp;
          add(botComp);
        }
      }

      // Send the current map layout so the bot knows about barriers/terminals.
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

      // Dreamfinder notices the new human player arriving.
      _dreamfinderComponent?.noticePlayer(playerComponent.position);
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
      _log.fine('LiveKit already initialized');
      return;
    }

    // Get LiveKitService from Locator (created in main.dart when user signs in)
    _liveKitService = Locator.maybeLocate<LiveKitService>();
    if (_liveKitService == null) {
      _log.info('LiveKitService not available yet');
      return;
    }

    _log.info('Using LiveKitService from Locator');

    // Respond to bot map-info requests by sending the current map.
    _mapInfoRequestedSubscription =
        _liveKitService!.mapInfoRequested.listen((_) {
      _log.info('Bot requested map-info, sending current map');
      _liveKitService?.publishMapInfo(currentMap.value);
    });

    // Subscribe to position updates from other players via LiveKit
    _liveKitPositionSubscription =
        _liveKitService!.positionReceived.listen((PlayerPath path) {
      _log.fine('LiveKit position received for ${path.playerId}');
      // Don't process our own position
      if (path.playerId == userId) return;

      if (path.playerId == _dreamfinderIdentity &&
          _dreamfinderComponent != null) {
        // Route Dreamfinder movement through its dedicated component.
        _dreamfinderComponent!
            .moveFromServer(path.directions, path.largeGridPoints);
      } else if (_botCharacterComponents.containsKey(path.playerId)) {
        // Animate bot along the full path, just like player movement.
        _botCharacterComponents[path.playerId]?.move(path.largeGridPoints);
      } else if (!isBotIdentity(path.playerId)) {
        // If player component doesn't exist, create it.
        // Skip bot identities — their component is created by
        // _handleParticipantJoined, which may arrive after the first
        // position update.
        if (!_otherPlayerComponentsMap.containsKey(path.playerId)) {
          _log.fine('Creating player component for ${path.playerId} from position data');
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
      _log.fine('Found existing participant: ${participant.identity}');
      _handleParticipantJoined(participant);
    }

    _participantLeftSubscription =
        _liveKitService!.participantLeft.listen((participant) {
      _log.info('LiveKit participant left: ${participant.identity}');

      // Remove component based on participant type
      if (isDreamfinderIdentity(participant.identity) &&
          _dreamfinderComponent != null) {
        remove(_dreamfinderComponent!);
        _dreamfinderComponent = null;
        _dreamfinderIdentity = dreamfinderBot.identity; // reset to default
        _dreamfinderAvatarBridge?.dispose();
        _dreamfinderAvatarBridge = null;
      } else if (_botCharacterComponents.containsKey(participant.identity)) {
        final botComp = _botCharacterComponents.remove(participant.identity);
        if (botComp != null) remove(botComp);
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

    _speakingSubscription =
        _liveKitService!.speakingChanged.listen((event) {
      final (participant, isSpeaking) = event;
      _updateBubbleSpeakingState(participant.identity, isSpeaking);
    });

    // Listen for track subscription events to upgrade placeholder bubbles to video
    _trackSubscribedSubscription =
        _liveKitService!.trackSubscribed.listen((event) {
      final (participant, track) = event;
      if (track.kind == TrackType.VIDEO) {
        _log.fine('Video track subscribed for ${participant.identity}, refreshing bubble');
        // This will upgrade PlayerBubbleComponent to VideoBubbleComponent
        _refreshBubbleForPlayer(participant.identity);
      }
      _notifyBubbleTrackReady(participant.identity);
    });

    // Listen for track unsubscription to downgrade video bubbles back to static
    _trackUnsubscribedSubscription =
        _liveKitService!.trackUnsubscribed.listen((event) {
      final (participant, track) = event;
      if (track.kind == TrackType.VIDEO) {
        _log.info(
            'Video track unsubscribed for ${participant.identity}, '
            'downgrading bubble');
        _downgradeVideoBubble(participant.identity);
      }
    });

    // Listen for unexpected connection loss to clean up all LiveKit state.
    // This enables reconnection: disconnectFromLiveKit() nulls _liveKitService,
    // so the guard at the top of this method will pass on the next call.
    _connectionLostSubscription =
        _liveKitService!.connectionLost.listen((reason) {
      _log.warning('LiveKit connection lost (reason: $reason), cleaning up');
      disconnectFromLiveKit();
    });

    // Listen for local track publication to refresh local bubble when camera is ready
    _localTrackPublishedSubscription =
        _liveKitService!.localTrackPublished.listen((publication) {
      if (publication.kind == TrackType.VIDEO) {
        _log.fine('Local video track published, refreshing bubble');
        _refreshLocalPlayerBubble();
      }
    });

    // Check if already connected, otherwise wait for connection
    // Note: camera/mic are enabled by the caller (_setupLiveKit in main.dart)
    // to keep media device management out of the game world layer.
    if (_liveKitService!.isConnected) {
      _log.fine('LiveKit already connected');
      _refreshLocalPlayerBubble();

      // Re-publish avatar so late joiners see our character
      if (_localAvatar != null) {
        _liveKitService!.publishAvatar(_localAvatar!);
      }
    } else {
      _log.fine('Waiting for LiveKit connection...');
    }
  }

  /// Refresh a player's bubble (recreate if video is now available)
  void _refreshBubbleForPlayer(String playerId) {
    // Handle Dreamfinder separately — it uses DreamfinderComponent, not
    // PlayerComponent. When a video track arrives, upgrade its static
    // BotBubbleComponent to a VideoBubbleComponent (holographic wizard).
    if (isDreamfinderIdentity(playerId) &&
        _dreamfinderComponent != null) {
      final existingBubble = _playerBubbles[playerId];
      final dfParticipant =
          _liveKitService?.getParticipant(_dreamfinderIdentity);
      if (dfParticipant != null && existingBubble is! VideoBubbleComponent) {
        existingBubble?.removeFromParent();
        final videoBubble = _createDreamfinderVideoBubble(dfParticipant);
        videoBubble.position =
            _dreamfinderComponent!.position + _bubbleOffset;
        _playerBubbles[playerId] = videoBubble;
        add(videoBubble);
      }
      return;
    }

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

  /// Downgrade a video bubble back to a static placeholder when the video
  /// track is unsubscribed. Without this, dead [VideoBubbleComponent]s
  /// accumulate and continue attempting frame capture on stale tracks.
  void _downgradeVideoBubble(String playerId) {
    final existingBubble = _playerBubbles[playerId];
    if (existingBubble == null) return;

    // Only downgrade if it's currently a video bubble
    if (existingBubble is! VideoBubbleComponent) return;

    final position = existingBubble.position.clone();
    existingBubble.removeFromParent();

    // Dreamfinder gets a BotBubbleComponent, others get PlayerBubbleComponent
    if (isDreamfinderIdentity(playerId)) {
      final botBubble = BotBubbleComponent(bubbleSize: 64);
      botBubble.position = position;
      _playerBubbles[playerId] = botBubble;
      add(botBubble);
    } else {
      final playerComponent = _otherPlayerComponentsMap[playerId];
      if (playerComponent != null) {
        final newBubble = PlayerBubbleComponent(
          displayName: playerComponent.displayName,
          playerId: playerId,
        );
        newBubble.position = position;
        _playerBubbles[playerId] = newBubble;
        add(newBubble);
      } else {
        // Player component already removed — just clean up the bubble entry
        _playerBubbles.remove(playerId);
      }
    }
  }

  /// Refresh local player bubble (recreate if video is now available)
  void _refreshLocalPlayerBubble() {
    final existingBubble = _playerBubbles[_localPlayerBubbleKey];
    if (existingBubble == null) return; // No bubble to refresh

    // If it's already a video bubble, no need to refresh
    if (existingBubble is VideoBubbleComponent) return;

    _log.fine('Refreshing local player bubble after camera enabled');

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
      _log.fine('Notifying bubble track ready for $participantId');
      bubble.notifyTrackReady();
    }
  }

  /// Create bubble for local player (video if available, otherwise static)
  PositionComponent _createLocalPlayerBubble() {
    final localParticipant = _liveKitService?.localParticipant;

    if (localParticipant != null && _hasVideoTrack(localParticipant)) {
      _log.fine('Creating local VideoBubbleComponent');
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

    // Load map components. If loadMap() was called before mount (e.g. from
    // the room lobby), currentMap already holds the desired map.
    final map = currentMap.value;
    await _loadMapComponents(map);

    // Position player at the map's spawn point (covers both the default map
    // and maps set by a pre-mount loadMap call).
    _userPlayerComponent.position = Vector2(
      map.spawnPoint.x * gridSquareSizeDouble,
      map.spawnPoint.y * gridSquareSizeDouble,
    );
    playerGridPosition.value = map.spawnPoint;

    final game = findGame() as TechWorldGame?;
    game?.camera.follow(_userPlayerComponent);

    // Load the video bubble shader
    await _loadVideoBubbleShader();

    gameReady.value = true;

    _authStateChangesSubscription = _authStateChanges.listen((authUser) async {
      if (authUser is SignedOutUser) {
        // User signed out - clear LiveKit state so we can reconnect on next sign-in
        disconnectFromLiveKit();
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

  /// Load map-specific components: barriers, terminals, and tile layers.
  Future<void> _loadMapComponents(GameMap map) async {
    _log.info(
      'loadMapComponents: "${map.name}" (id=${map.id}), '
      'usesTilesets=${map.usesTilesets}, '
      'floorLayer=${map.floorLayer != null ? "present (empty=${map.floorLayer!.isEmpty})" : "null"}, '
      'objectLayer=${map.objectLayer != null ? "present" : "null"}, '
      'tilesetIds=${map.tilesetIds}',
    );

    // Barriers — include locked door positions so they block movement.
    final allBarriers = [
      ...map.barriers,
      for (final door in map.doors)
        if (!door.isUnlocked) door.position,
    ];
    _barriersComponent = BarriersComponent(barriers: allBarriers);
    await add(_barriersComponent);
    _pathComponent?.barriers = _barriersComponent;

    // Terminals — only assign code challenges when terminal mode is `code`.
    for (var i = 0; i < map.terminals.length; i++) {
      final terminalPos = map.terminals[i];
      final Challenge? challenge;
      final bool isCompleted;
      if (map.terminalMode == TerminalMode.code) {
        final challengeIndex = i % allChallenges.length;
        challenge = allChallenges[challengeIndex];
        isCompleted = _isChallengeCompleted(challenge.id);
      } else {
        challenge = null;
        isCompleted = false;
      }

      // Prompt-mode terminals get prompt challenges instead.
      PromptChallenge? promptChallenge;
      if (map.terminalMode == TerminalMode.prompt) {
        final idx = i % allPromptChallenges.length;
        promptChallenge = allPromptChallenges[idx];
      }

      final terminal = TerminalComponent(
        position: Vector2(
          terminalPos.x * gridSquareSizeDouble,
          terminalPos.y * gridSquareSizeDouble,
        ),
        onInteract: challenge != null
            ? () => _onTerminalInteract(terminalPos, challenge!)
            : promptChallenge != null
                ? () => _onPromptTerminalInteract(terminalPos, promptChallenge!)
                : null,
        isCompleted: isCompleted,
      );
      _terminalComponents.add(terminal);
      await add(terminal);
    }

    // Doors — visual components for locked/unlocked gates.
    for (final door in map.doors) {
      final doorComponent = DoorComponent(
        position: Vector2(
          door.position.x * gridSquareSizeDouble,
          door.position.y * gridSquareSizeDouble,
        ),
        doorData: door,
      );
      _doorComponents.add(doorComponent);
      await add(doorComponent);
    }

    // Tile layers.
    final game = findGame() as TechWorldGame?;
    _log.info('loadMapComponents: game=${game != null}, usesTilesets=${map.usesTilesets}');
    if (game != null && map.usesTilesets) {
      final registry = game.tilesetRegistry;
      _log.info('loadMapComponents: registry loaded tilesets: ${registry.loadedIds.toList()}');

      // Download and register custom tilesets not already loaded.
      // Downloads run in parallel for faster map loading.
      // Checks _tilesetByteCache first (populated by prefetchTilesetBytes).
      final unloadedTilesets =
          map.customTilesets.where((ts) => !registry.isLoaded(ts.id));
      if (unloadedTilesets.isNotEmpty) {
        final storageService = TilesetStorageService();
        await Future.wait(unloadedTilesets.map((tileset) async {
          try {
            final bytes = _tilesetByteCache.remove(tileset.id)
                ?? await storageService.downloadTilesetImage(tileset.id);
            if (bytes != null) {
              final codec = await ui.instantiateImageCodec(bytes);
              final frame = await codec.getNextFrame();
              registry.loadFromImage(tileset, frame.image);
              await registry.analyzeBarriers(tileset.id);
            }
          } catch (e) {
            _log.warning(
              'Failed to download custom tileset ${tileset.id}', e,
            );
          }
        }));
      }

      if (map.floorLayer != null) {
        _log.info('loadMapComponents: creating TileFloorComponent');
        _tileFloor = TileFloorComponent(
          layerData: map.floorLayer!,
          registry: registry,
        );
        await add(_tileFloor!);
        _log.info('loadMapComponents: TileFloorComponent added');
      } else {
        _log.warning('loadMapComponents: NO floorLayer — floor will be black');
      }

      // Build or reuse the object layer for depth-sorted wall occlusion.
      // Priority overrides are always computed dynamically from barriers so
      // that doorway lintels work for any map (predefined, editor, Firestore).
      final barrierSet = {for (final b in map.barriers) (b.x, b.y)};

      // Wall positions for tile art — only walls get face + cap tiles.
      final wallMap = {
        for (final entry in map.walls.entries) (entry.key.x, entry.key.y): entry.value,
      };

      _log.info('loadMapComponents: barriers=${barrierSet.length}, '
          'walls=${wallMap.length}, '
          'objectLayer=${map.objectLayer != null}, '
          'floorLayer=${map.floorLayer != null}');

      // Ensure wall tilesets are loaded before generating tile art.
      // Wall tilesets (e.g. limezu_walls) are not bundled — they're
      // downloaded from Firebase Storage on first use and disk-cached.
      if (wallMap.isNotEmpty) {
        await _ensureWallTilesetsLoaded(wallMap.values, registry);
      }

      // Generate wall tile art and merge with any manually placed object tiles.
      var objectLayer = map.objectLayer;
      if (wallMap.isNotEmpty) {
        final wallLayer = buildObjectLayerFromWalls(wallMap);
        if (objectLayer != null) {
          // Merge wall tiles into existing object layer (wall tiles take
          // precedence at overlapping positions).
          objectLayer = objectLayer.mergedWith(wallLayer);
        } else {
          objectLayer = wallLayer;
        }
        _log.info('loadMapComponents: generated object layer from '
            '${wallMap.length} walls');
      }

      final overrides = barrierSet.isNotEmpty
          ? computePriorityOverrides(barrierSet)
          : map.objectLayerPriorityOverrides;

      if (overrides != null) {
        // Log lintel-related overrides for debugging.
        final lintels = overrides.entries
            .where((e) => e.value > e.key.$2 + 1)
            .toList();
        _log.info('loadMapComponents: ${overrides.length} priority overrides, '
            '${lintels.length} lintel overrides: $lintels');
      }

      if (objectLayer != null) {
        // Compute which tiles need half-height "alpha punch" rendering.
        final lintelOverlays = barrierSet.isNotEmpty
            ? computeLintelOverlayPositions(barrierSet)
            : <(int, int)>{};

        if (lintelOverlays.isNotEmpty) {
          _log.info('loadMapComponents: ${lintelOverlays.length} lintel overlay positions: $lintelOverlays');
        }

        _tileObjectLayer = TileObjectLayerComponent(
          layerData: objectLayer,
          registry: registry,
          priorityOverrides: overrides,
          lintelOverlayPositions: lintelOverlays,
          debugPriorities: false,
        );
        await add(_tileObjectLayer!);
      }
    } else {
      _log.info('loadMapComponents: skipped tile layers (game=${game != null}, usesTilesets=${map.usesTilesets})');
    }
  }

  /// Download and register any wall tilesets not already in the registry.
  ///
  /// Collects the unique tileset IDs referenced by [styleIds], resolves each
  /// to a [Tileset] definition, and downloads missing ones from Firebase
  /// Storage. On native platforms, downloads are disk-cached via
  /// [TilesetCacheService] (through [createCachedDownloader]). On web,
  /// downloads go direct (relies on browser HTTP cache).
  Future<void> _ensureWallTilesetsLoaded(
    Iterable<String> styleIds,
    TilesetRegistry registry,
  ) async {
    // Collect unique tileset definitions from the wall styles.
    final needed = <String, Tileset>{};
    for (final styleId in styleIds) {
      final style = lookupWallStyle(styleId);
      if (style == null) continue;
      if (registry.isLoaded(style.tilesetId)) continue;
      if (style.tilesetId == wallTilesetId) {
        needed[wallTilesetId] = limeZuWallsTileset;
      }
    }
    if (needed.isEmpty) return;

    _log.info('_ensureWallTilesetsLoaded: downloading ${needed.keys}');

    final storageService = TilesetStorageService();
    final downloader = await createCachedDownloader(
      (id) => storageService.downloadTilesetImage(id),
    );

    await Future.wait(needed.entries.map((entry) async {
      try {
        final bytes = _tilesetByteCache.remove(entry.key)
            ?? await downloader(entry.key);
        if (bytes != null) {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          registry.loadFromImage(entry.value, frame.image);
          _log.info('_ensureWallTilesetsLoaded: loaded ${entry.key}');
        } else {
          _log.warning('_ensureWallTilesetsLoaded: ${entry.key} not found');
        }
      } catch (e) {
        _log.warning('_ensureWallTilesetsLoaded: failed to load ${entry.key}', e);
      }
    }));
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

    // Doors
    for (final door in _doorComponents) {
      door.removeFromParent();
    }
    _doorComponents.clear();

    // Unload custom tilesets from previous map.
    final game = findGame() as TechWorldGame?;
    if (game != null) {
      for (final tileset in currentMap.value.customTilesets) {
        game.tilesetRegistry.unload(tileset.id);
      }
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
  ///
  /// Guarded against concurrent calls — if a map load is already in progress,
  /// the second call returns immediately to prevent double removal of
  /// components.
  Future<void> loadMap(GameMap map) async {
    // Fill in missing visual layers from predefined maps (e.g. Firestore
    // rooms created before tileset rendering was added).
    _log.info('loadMap: input "${map.name}" (id=${map.id}), '
        'floorLayer=${map.floorLayer != null}, tilesetIds=${map.tilesetIds}');
    final resolvedMap = applyPredefinedVisualFallback(map);
    _log.info('loadMap: resolved "${resolvedMap.name}" (id=${resolvedMap.id}), '
        'floorLayer=${resolvedMap.floorLayer != null}, tilesetIds=${resolvedMap.tilesetIds}');

    if (resolvedMap.id == currentMap.value.id) return; // Already on this map.

    // If the game engine hasn't started yet (GameWidget not mounted), just
    // update currentMap so that onLoad() picks up the correct map when it
    // runs. Loading components now would fail because tilesetRegistry isn't
    // initialized until TechWorldGame.onLoad() completes.
    if (!isMounted) {
      _log.info('loadMap: not mounted yet — deferring to onLoad');
      currentMap.value = resolvedMap;
      return;
    }

    if (_isLoadingMap) {
      _log.info('loadMap ignored — another load is in progress');
      return;
    }

    _isLoadingMap = true;
    gameReady.value = false;
    try {
      // Auto-exit editor mode if active.
      if (mapEditorActive.value) await exitEditorMode();

      // Close code editor if open — the terminals are about to change.
      closeEditor();

      _removeMapComponents();
      await _loadMapComponents(resolvedMap);

      // Reposition player to new map's spawn point.
      _userPlayerComponent.position = Vector2(
        resolvedMap.spawnPoint.x * gridSquareSizeDouble,
        resolvedMap.spawnPoint.y * gridSquareSizeDouble,
      );
      playerGridPosition.value = resolvedMap.spawnPoint;

      currentMap.value = resolvedMap;

      // Notify the bot about the new map layout
      _liveKitService?.publishMapInfo(resolvedMap);

      gameReady.value = true;
    } finally {
      _isLoadingMap = false;
    }
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

  /// Handle interaction with a prompt-mode terminal.
  void _onPromptTerminalInteract(
    Point<int> terminalPos,
    PromptChallenge challenge,
  ) {
    final playerGrid = _userPlayerComponent.miniGridPosition;
    final distance = max(
      (terminalPos.x - playerGrid.x).abs(),
      (terminalPos.y - playerGrid.y).abs(),
    );
    if (distance <= _terminalProximityThreshold) {
      activePromptChallenge.value = challenge.id;
      activeTerminalPosition.value = terminalPos;
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

  /// Unlock a door and update its visual state.
  ///
  /// Called when a prompt challenge is passed and the door's required
  /// challenges are all completed. Broadcasts the unlock to other players.
  void unlockDoor(DoorData door) {
    door.isUnlocked = true;

    // Remove the barrier at the door position so the player can walk through.
    _barriersComponent.removeBarrierAt(door.position);

    // Broadcast to other players.
    _liveKitService?.publishJson(
      {
        'type': 'door-unlock',
        'doorX': door.position.x,
        'doorY': door.position.y,
      },
      topic: 'door-unlock',
    );

    _log.info('Door unlocked at (${door.position.x}, ${door.position.y})');
  }

  /// Find all doors that require a specific challenge to be completed.
  List<DoorData> doorsForChallenge(String challengeId) {
    return currentMap.value.doors
        .where((d) => d.requiredChallengeIds.contains(challengeId) && !d.isUnlocked)
        .toList();
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
  ///
  /// Called from [main.dart] before disposing services so that stream
  /// subscriptions are cancelled while the underlying service is still alive.
  /// Also called internally when the user signs out.
  void disconnectFromLiveKit() {
    _log.info('Disconnecting from LiveKit');

    // Cancel all LiveKit-related subscriptions
    _trackSubscribedSubscription?.cancel();
    _trackSubscribedSubscription = null;
    _trackUnsubscribedSubscription?.cancel();
    _trackUnsubscribedSubscription = null;
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
    _speakingSubscription?.cancel();
    _speakingSubscription = null;
    _connectionLostSubscription?.cancel();
    _connectionLostSubscription = null;
    _mapInfoRequestedSubscription?.cancel();
    _mapInfoRequestedSubscription = null;

    // Clear pending avatar data
    _pendingAvatars.clear();

    // Clear the service reference so _connectToLiveKit can reconnect
    _liveKitService = null;

    // Clean up avatar bridge
    _dreamfinderAvatarBridge?.dispose();
    _dreamfinderAvatarBridge = null;

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

    // Remove all bot characters
    for (final botComp in _botCharacterComponents.values) {
      botComp.removeFromParent();
    }
    _botCharacterComponents.clear();

    // Reset position tracking
    _lastPlayerGridPosition = null;
    _dreamfinderIdentity = dreamfinderBot.identity;
  }

  void dispose() {
    _authStateChangesSubscription?.cancel();
    activeChallenge.dispose();
    activeTerminalPosition.dispose();
    mapEditorActive.dispose();
    currentMap.dispose();
    disconnectFromLiveKit();
  }
}
