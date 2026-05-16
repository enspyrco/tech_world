import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Color, Colors;
import 'package:livekit_client/livekit_client.dart';
import 'package:logging/logging.dart';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import 'package:tech_world/bots/bot_config.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/flame/components/bot_character_component.dart';
import 'package:tech_world/flame/components/bubble_field_component.dart';
import 'package:tech_world/flame/components/dreamfinder_component.dart';
import 'package:tech_world/flame/components/merged_video_bubble_component.dart';
import 'package:tech_world/flame/components/player_bubble_component.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/components/video_bubble_component.dart';
import 'package:tech_world/events/dispatch.dart';
import 'package:tech_world/events/types.dart';
import 'package:tech_world/livekit/dreamfinder_avatar_bridge.dart';
import 'package:tech_world/livekit/livekit_service.dart';

final _log = Logger('BubbleManager');

/// Manages the lifecycle of all player proximity bubbles in the game world.
///
/// Plain Dart class (not a Flame Component). Receives a callback to add
/// components to the World, keeping component tree ownership in TechWorld.
///
/// Responsibilities:
///  - Proximity detection and bubble creation/removal
///  - Physics repulsion between overlapping bubbles
///  - Metaball field and merged video rendering
///  - Audio enable/disable based on distance
///  - Shader loading and assignment
///  - Dreamfinder avatar bridge lifecycle
class BubbleManager {
  BubbleManager({
    required PlayerComponent localPlayer,
    required void Function(Component) addComponent,
    required Map<String, PlayerComponent> remotePlayers,
    required Map<String, BotCharacterComponent> bots,
    this.hideVideoBubbles = false,
    this.reduceMotion = false,
  })  : _localPlayer = localPlayer,
        _addComponent = addComponent,
        _remotePlayers = remotePlayers,
        _bots = bots;

  /// When true, all proximity bubbles render as [PlayerBubbleComponent]
  /// (avatar-only) regardless of whether the underlying participant has a
  /// video track. Audio and player avatars are unaffected.
  ///
  /// Mutable so the owning game world can apply the user's saved preference
  /// before each room entry. Existing bubbles are not retroactively swapped —
  /// the toggle takes effect for newly created bubbles only.
  bool hideVideoBubbles;

  /// When true, purely decorative animation on proximity video bubbles
  /// renders in its resting state: no breathing scale, no glow pulse, no
  /// voice ripples, and the metaball merge field/animation freezes.
  ///
  /// Gameplay-essential animation (avatar walk, bubble physics repulsion,
  /// camera, tile rendering) is unaffected. Universal benefit (vestibular
  /// disorders, low-power devices, ADHD, autism, motion sensitivity).
  ///
  /// Mutable so the owning game world can apply the user's saved preference
  /// before each room entry. Applied to newly-created bubbles and to the
  /// shared metaball field/merged-video components on next update.
  bool reduceMotion;

  // ── Construction-time stable references ──────────────────────────────────

  final PlayerComponent _localPlayer;
  final void Function(Component) _addComponent;
  final Map<String, PlayerComponent> _remotePlayers;
  final Map<String, BotCharacterComponent> _bots;

  // ── Bot status (arrives after construction, when ChatService is created) ──

  ValueListenable<BotStatus> _botStatus = ValueNotifier(BotStatus.absent);

  // ── LiveKit (arrives after construction) ─────────────────────────────────

  LiveKitService? _liveKitService;
  DreamfinderAvatarBridge? _dreamfinderAvatarBridge;

  // ── Mutable references set by TechWorld ──────────────────────────────────

  DreamfinderComponent? dreamfinderComponent;
  String dreamfinderIdentity = dreamfinderBot.identity;

  // ── Bubble state ─────────────────────────────────────────────────────────

  final Map<String, PositionComponent> _playerBubbles = {};
  final Map<String, Vector2> _bubbleDisplacements = {};
  final Set<String> _audioEnabledParticipants = {};
  Point<int>? _lastPlayerGridPosition;

  // ── Rendering components ─────────────────────────────────────────────────

  BubbleFieldComponent? _bubbleField;
  MergedVideoBubbleComponent? _mergedBubble;

  // ── Merge group cache ───────────────────────────────────────────────────

  bool _mergeGroupDirty = true;
  List<String> _cachedMergeGroup = [];

  // ── Shader programs ───────────────────────────────────────────────────────

  ui.FragmentProgram? _shaderProgram;
  ui.FragmentProgram? _metaballShaderProgram;
  ui.FragmentProgram? _mergedVideoShaderProgram;

  // ── AV diagnostics ─────────────────────────────────────────────────────────

  /// When true, the 5-second snapshot timer runs and AV state-transition
  /// events are dispatched. Toggled at runtime from main.dart via
  /// [setAvDiagnosticsEnabled].
  bool avDiagnosticsEnabled = false;

  double _snapshotTimer = 0;
  static const double _snapshotIntervalSeconds = 5.0;

  // ── Constants ─────────────────────────────────────────────────────────────

  static const _localPlayerBubbleKey = '_local_player_';
  static const int _visualThreshold = 5; // grid squares — bubbles visible
  static const int _audioThreshold = 2; // grid squares — audio enabled
  static final _bubbleOffset =
      Vector2(16, -20); // center horizontally, above sprite
  static const double _mergeThreshold = 96.0; // 1.5× bubble diameter
  static const double _bubbleDiameter = 64.0;
  static const double _maxTetherDistance = 24.0;
  static const double _repulsionDamping = 0.85;
  // Force coefficient: 0.5 (base strength) / 0.016 (60 fps reference dt).
  static const double _repulsionForceCoefficient = 31.25;

  // ═══════════════════════════════════════════════════════════════════════════
  // Public API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Chebyshev distance (max of x/y difference) — the metric for proximity.
  static int chebyshevDistance(Point<int> a, Point<int> b) =>
      max((a.x - b.x).abs(), (a.y - b.y).abs());

  /// Load all three shader programs in parallel.
  Future<void> loadShaders() => Future.wait([
        _loadVideoBubbleShader(),
        _loadMetaballShader(),
        _loadMergedVideoShader(),
      ]);

  /// Called when LiveKitService becomes available (after connectToLiveKit).
  void setLiveKitService(LiveKitService service) {
    _liveKitService = service;
  }

  /// Called when ChatService becomes available (after room join).
  void setBotStatus(ValueListenable<BotStatus> status) {
    _botStatus = status;
  }

  /// Main per-frame entry point. Called from TechWorld.update().
  void update(double dt) {
    // ── Periodic AV snapshot ──────────────────────────────────────────────
    if (avDiagnosticsEnabled) {
      _snapshotTimer += dt;
      if (_snapshotTimer >= _snapshotIntervalSeconds) {
        _snapshotTimer = 0;
        _dispatchPipelineSnapshots();
      }
    }

    final playerGrid = _localPlayer.miniGridPosition;

    // Skip proximity re-evaluation if player hasn't moved to a new grid cell.
    if (_lastPlayerGridPosition == playerGrid) {
      _updateBubblePositions(dt);
      return;
    }
    _lastPlayerGridPosition = playerGrid;

    // Check each other player for proximity.
    final nearbyPlayerIds = <String>{};
    int closestDistance = _visualThreshold + 1;

    for (final entry in _remotePlayers.entries) {
      final playerId = entry.key;
      final playerComponent = entry.value;

      final distance =
          chebyshevDistance(playerGrid, playerComponent.miniGridPosition);
      final isVisible = distance <= _visualThreshold;

      if (isVisible) {
        nearbyPlayerIds.add(playerId);
        if (distance < closestDistance) closestDistance = distance;

        if (!_playerBubbles.containsKey(playerId)) {
          final bubble = _createBubbleForPlayer(playerId, playerComponent);
          bubble.position = playerComponent.position + _bubbleOffset;
          _playerBubbles[playerId] = bubble;
          _addComponent(bubble);
          _dispatchBubbleCreated(playerId, bubble);
        }

        _setBubbleOpacity(_playerBubbles[playerId]!, distance);
        _updateParticipantAudio(playerId, distance);
      } else {
        // Beyond visual range — ensure audio is disabled.
        _updateParticipantAudio(playerId, distance);
      }
    }

    // Check proximity to Dreamfinder.
    if (dreamfinderComponent != null) {
      final dfGrid = dreamfinderComponent!.miniGridPosition;
      final dfDistance = chebyshevDistance(playerGrid, dfGrid);

      if (dfDistance <= _visualThreshold) {
        nearbyPlayerIds.add(dreamfinderIdentity);
        if (dfDistance < closestDistance) closestDistance = dfDistance;

        if (!_playerBubbles.containsKey(dreamfinderIdentity)) {
          final dfParticipant =
              _liveKitService?.getParticipant(dreamfinderIdentity);
          PositionComponent bubble;
          if (dfParticipant != null && !hideVideoBubbles) {
            bubble = _createDreamfinderVideoBubble(dfParticipant);
          } else {
            bubble = BotBubbleComponent(botStatus: _botStatus);
          }
          bubble.position =
              dreamfinderComponent!.position + _bubbleOffset;
          _playerBubbles[dreamfinderIdentity] = bubble;
          _addComponent(bubble);
        }
      }
    }

    // Check proximity to all bot characters.
    for (final entry in _bots.entries) {
      final botId = entry.key;
      final botComp = entry.value;
      final botDistance =
          chebyshevDistance(playerGrid, botComp.miniGridPosition);

      if (botDistance <= _visualThreshold) {
        nearbyPlayerIds.add(botId);
        if (botDistance < closestDistance) closestDistance = botDistance;

        if (!_playerBubbles.containsKey(botId)) {
          final bubble = BotBubbleComponent(botStatus: _botStatus);
          bubble.position = botComp.position + _bubbleOffset;
          _playerBubbles[botId] = bubble;
          _addComponent(bubble);
        }
      }
    }

    // Show local player's bubble if near anyone.
    if (nearbyPlayerIds.isNotEmpty) {
      if (!_playerBubbles.containsKey(_localPlayerBubbleKey)) {
        final localBubble = _createLocalPlayerBubble();
        localBubble.position = _localPlayer.position + _bubbleOffset;
        _playerBubbles[_localPlayerBubbleKey] = localBubble;
        _addComponent(localBubble);
      }
      _setBubbleOpacity(
          _playerBubbles[_localPlayerBubbleKey]!, closestDistance);
      nearbyPlayerIds.add(_localPlayerBubbleKey);
    }

    // Remove bubbles for players no longer nearby.
    final toRemove = <String>[];
    for (final playerId in _playerBubbles.keys) {
      if (!nearbyPlayerIds.contains(playerId)) {
        _playerBubbles[playerId]?.removeFromParent();
        toRemove.add(playerId);
      }
    }
    for (final playerId in toRemove) {
      _playerBubbles.remove(playerId);
      if (avDiagnosticsEnabled) {
        dispatch([AvBubbleRemoved(participant: playerId)]);
      }
    }

    _updateBubblePositions(dt);
  }

  /// Refresh (upgrade to video or re-create) the bubble for a remote player.
  void refreshBubbleForPlayer(String playerId) {
    // Handle Dreamfinder separately.
    if (isDreamfinderIdentity(playerId) && dreamfinderComponent != null) {
      final existingBubble = _playerBubbles[playerId];
      final dfParticipant =
          _liveKitService?.getParticipant(dreamfinderIdentity);
      if (dfParticipant == null) return;

      // When the user has hidden video bubbles, never upgrade the DF bubble
      // to a video bubble — the existing BotBubbleComponent stays in place.
      if (hideVideoBubbles) return;

      final hasCanvasCapture = existingBubble is VideoBubbleComponent &&
          existingBubble.externalVideoCapture != null;
      final needsUpgrade = existingBubble is! VideoBubbleComponent ||
          (!hasCanvasCapture && _dreamfinderAvatarBridge?.isReady == true);

      if (needsUpgrade) {
        existingBubble?.removeFromParent();
        final videoBubble = _createDreamfinderVideoBubble(dfParticipant);
        videoBubble.position =
            dreamfinderComponent!.position + _bubbleOffset;
        _playerBubbles[playerId] = videoBubble;
        _addComponent(videoBubble);
      }
      return;
    }

    final existingBubble = _playerBubbles[playerId];
    if (existingBubble == null) return;

    if (existingBubble is VideoBubbleComponent) return;

    final playerComponent = _remotePlayers[playerId];
    if (playerComponent == null) return;

    existingBubble.removeFromParent();

    final newBubble = _createBubbleForPlayer(playerId, playerComponent);
    newBubble.position = playerComponent.position + _bubbleOffset;
    _playerBubbles[playerId] = newBubble;
    _addComponent(newBubble);
  }

  /// Refresh the local player's bubble (e.g. after camera comes online).
  void refreshLocalPlayerBubble() {
    final existingBubble = _playerBubbles[_localPlayerBubbleKey];
    if (existingBubble == null) return;

    if (existingBubble is VideoBubbleComponent) return;

    _log.fine('Refreshing local player bubble after camera enabled');

    existingBubble.removeFromParent();

    final newBubble = _createLocalPlayerBubble();
    newBubble.position = _localPlayer.position + _bubbleOffset;
    _playerBubbles[_localPlayerBubbleKey] = newBubble;
    _addComponent(newBubble);
  }

  /// Downgrade a video bubble to a static placeholder.
  void downgradeVideoBubble(String playerId) {
    final existingBubble = _playerBubbles[playerId];
    if (existingBubble == null) return;

    if (existingBubble is! VideoBubbleComponent) return;

    final position = existingBubble.position.clone();
    existingBubble.removeFromParent();

    if (isDreamfinderIdentity(playerId)) {
      final botBubble = BotBubbleComponent(
        botStatus: _botStatus,
        bubbleSize: 64,
      );
      botBubble.position = position;
      _playerBubbles[playerId] = botBubble;
      _addComponent(botBubble);
    } else {
      final playerComponent = _remotePlayers[playerId];
      if (playerComponent != null) {
        final newBubble = PlayerBubbleComponent(
          displayName: playerComponent.displayName,
          playerId: playerId,
        );
        newBubble.position = position;
        _playerBubbles[playerId] = newBubble;
        _addComponent(newBubble);
      } else {
        _playerBubbles.remove(playerId);
      }
    }
  }

  /// Update the speaking indicator on a video bubble.
  void updateSpeakingState(String participantId, bool isSpeaking) {
    final bubble = _playerBubbles[participantId];
    if (bubble is VideoBubbleComponent) {
      bubble.speakingLevel = isSpeaking ? 1.0 : 0.0;
    }
  }

  /// Signal that a video track is ready for frame capture.
  void notifyTrackReady(String participantId) {
    final bubble = _playerBubbles[participantId];
    if (bubble is VideoBubbleComponent) {
      _log.fine('Notifying bubble track ready for $participantId');
      bubble.notifyTrackReady();
    }
  }

  /// Initialize the Dreamfinder 3D avatar bridge (web only).
  void initDreamfinderBridge() {
    if (_dreamfinderAvatarBridge != null) return;
    final liveKit = _liveKitService;
    if (liveKit == null) return;

    _dreamfinderAvatarBridge =
        DreamfinderAvatarBridge(liveKitService: liveKit);
    _dreamfinderAvatarBridge!.initialize().then((_) {
      if (_dreamfinderAvatarBridge?.isReady == true) {
        _log.info('Dreamfinder avatar bridge ready — refreshing bubble');
        refreshBubbleForPlayer(dreamfinderIdentity);
      }
    }).catchError((Object e) {
      _log.warning('Dreamfinder avatar bridge failed to initialize: $e');
    });
  }

  /// Clean up Dreamfinder-specific state when the participant leaves.
  void handleDreamfinderLeft() {
    dreamfinderIdentity = dreamfinderBot.identity;
    _dreamfinderAvatarBridge?.dispose();
    _dreamfinderAvatarBridge = null;
  }

  /// Remove a single bubble by player ID.
  void removeBubble(String playerId) {
    final bubble = _playerBubbles.remove(playerId);
    bubble?.removeFromParent();
    _mergeGroupDirty = true;
  }

  /// Remove all bubbles and reset state. Safe to call multiple times.
  void clear() {
    for (final bubble in _playerBubbles.values) {
      bubble.removeFromParent();
    }
    _playerBubbles.clear();
    _mergeGroupDirty = true;
    _bubbleDisplacements.clear();
    _bubbleField?.removeFromParent();
    _bubbleField = null;
    _mergedBubble?.removeFromParent();
    _mergedBubble = null;
    _audioEnabledParticipants.clear();
    _lastPlayerGridPosition = null;
    _liveKitService = null;
    _dreamfinderAvatarBridge?.dispose();
    _dreamfinderAvatarBridge = null;
    dreamfinderIdentity = dreamfinderBot.identity;
  }

  /// Final teardown. Call from TechWorld.dispose().
  void dispose() {
    clear();
    _shaderProgram = null;
    _metaballShaderProgram = null;
    _mergedVideoShaderProgram = null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Private — shader loading
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadVideoBubbleShader() async {
    try {
      _shaderProgram =
          await ui.FragmentProgram.fromAsset('shaders/video_bubble.frag');
    } catch (e) {
      _log.warning('Video bubble shader failed to load', e);
    }
  }

  Future<void> _loadMetaballShader() async {
    try {
      _metaballShaderProgram =
          await ui.FragmentProgram.fromAsset('shaders/metaball_field.frag');
    } catch (e) {
      _log.warning('Metaball shader failed to load', e);
    }
  }

  Future<void> _loadMergedVideoShader() async {
    try {
      _mergedVideoShaderProgram = await ui.FragmentProgram.fromAsset(
          'shaders/merged_video_bubble.frag');
    } catch (e) {
      _log.warning('Merged video shader failed to load', e);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Private — bubble creation
  // ═══════════════════════════════════════════════════════════════════════════

  bool _hasVideoTrack(Participant participant) {
    for (final publication in participant.videoTrackPublications) {
      if (publication.track != null) {
        if (participant is LocalParticipant) {
          return true;
        } else {
          if (publication.subscribed) {
            return true;
          }
        }
      }
    }
    return false;
  }

  PositionComponent _createBubbleForPlayer(
      String playerId, PlayerComponent playerComponent) {
    final participant = _liveKitService?.getParticipant(playerId);
    if (!hideVideoBubbles &&
        participant != null &&
        _hasVideoTrack(participant)) {
      final videoBubble = VideoBubbleComponent(
        participant: participant,
        displayName: playerComponent.displayName,
        bubbleSize: 64,
        targetFps: 15,
        reduceMotion: reduceMotion,
      );

      if (_shaderProgram != null) {
        videoBubble.setShader(_shaderProgram!.fragmentShader());
      }

      return videoBubble;
    }

    return PlayerBubbleComponent(
      displayName: playerComponent.displayName,
      playerId: playerId,
    );
  }

  PositionComponent _createLocalPlayerBubble() {
    final localParticipant = _liveKitService?.localParticipant;

    if (!hideVideoBubbles &&
        localParticipant != null &&
        _hasVideoTrack(localParticipant)) {
      _log.fine('Creating local VideoBubbleComponent');
      final videoBubble = VideoBubbleComponent(
        participant: localParticipant,
        displayName: _localPlayer.displayName,
        bubbleSize: 64,
        targetFps: 15,
        reduceMotion: reduceMotion,
      );

      if (_shaderProgram != null) {
        videoBubble.setShader(_shaderProgram!.fragmentShader());
      }

      videoBubble.glowColor = Colors.cyan;

      return videoBubble;
    }

    return PlayerBubbleComponent(
      displayName: _localPlayer.displayName,
      playerId: _localPlayer.id,
    );
  }

  VideoBubbleComponent _createDreamfinderVideoBubble(
      Participant participant) {
    final videoBubble = VideoBubbleComponent(
      participant: participant,
      displayName: dreamfinderBot.displayName,
      bubbleSize: 64,
      targetFps: 10,
      externalVideoCapture: _dreamfinderAvatarBridge?.canvasCapture,
      reduceMotion: reduceMotion,
    );
    videoBubble.glowColor = const Color(0xFFDAA520); // gold
    videoBubble.glowIntensity = 0.7;
    return videoBubble;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Private — proximity and audio
  // ═══════════════════════════════════════════════════════════════════════════

  void _setBubbleOpacity(PositionComponent bubble, int distance) {
    final opacity = _opacityForDistance(distance);
    if (bubble is VideoBubbleComponent) {
      bubble.opacity = opacity;
    } else if (bubble is PlayerBubbleComponent) {
      bubble.opacity = opacity;
    }
  }

  /// Visual opacity for a bubble at [distance] Chebyshev grid squares.
  ///
  /// Moved here from ProximityService — opacity is presentation, not
  /// proximity logic.
  ///
  /// - Distance 0–1: 1.0 (fully visible)
  /// - Distance 2: 0.8
  /// - Distance 3: 0.5
  /// - Distance 4: 0.2
  /// - Distance 5+: 0.0 (removed by caller)
  static double _opacityForDistance(int distance) {
    if (distance <= 1) return 1.0;
    if (distance == 2) return 0.8;
    if (distance == 3) return 0.5;
    if (distance == 4) return 0.2;
    return 0.0;
  }

  void _updateParticipantAudio(String playerId, int distance) {
    final shouldHaveAudio = distance <= _audioThreshold;
    final hasAudio = _audioEnabledParticipants.contains(playerId);

    if (shouldHaveAudio && !hasAudio) {
      _audioEnabledParticipants.add(playerId);
      _liveKitService?.setParticipantAudioEnabled(playerId, true);
      if (avDiagnosticsEnabled) {
        dispatch([AvAudioGateChanged(
          participant: playerId,
          enabled: true,
          distance: distance,
        )]);
      }
    } else if (!shouldHaveAudio && hasAudio) {
      _audioEnabledParticipants.remove(playerId);
      _liveKitService?.setParticipantAudioEnabled(playerId, false);
      if (avDiagnosticsEnabled) {
        dispatch([AvAudioGateChanged(
          participant: playerId,
          enabled: false,
          distance: distance,
        )]);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Private — physics and rendering
  // ═══════════════════════════════════════════════════════════════════════════

  void _updateBubblePositions(double dt) {
    // Bubble positions change every frame (they track their owning character),
    // so the merge group must be rechecked.
    _mergeGroupDirty = true;

    // 1. Set base positions from owning characters.
    for (final entry in _playerBubbles.entries) {
      if (entry.key == _localPlayerBubbleKey) {
        entry.value.position = _localPlayer.position + _bubbleOffset;
        entry.value.priority = _localPlayer.priority + 1;
      } else if (entry.key == dreamfinderIdentity &&
          dreamfinderComponent != null) {
        entry.value.position =
            dreamfinderComponent!.position + _bubbleOffset;
        entry.value.priority = dreamfinderComponent!.priority + 1;
        if (entry.value is VideoBubbleComponent) {
          (entry.value as VideoBubbleComponent).loadingProgress =
              _dreamfinderAvatarBridge?.avatarLoadProgress;
        }
      } else if (_bots.containsKey(entry.key)) {
        final botComp = _bots[entry.key]!;
        entry.value.position = botComp.position + _bubbleOffset;
        entry.value.priority = botComp.priority + 1;
      } else {
        final playerComponent = _remotePlayers[entry.key];
        if (playerComponent != null) {
          entry.value.position = playerComponent.position + _bubbleOffset;
          entry.value.priority = playerComponent.priority + 1;
        }
      }
    }

    // 2. Apply physics repulsion so bubbles don't overlap.
    _applyBubbleRepulsion(dt);

    // 3. Collect centres for the metaball field.
    final centres = <Vector2>[];
    int lowestPriority = 0x7fffffff;
    for (final entry in _playerBubbles.entries) {
      centres.add(entry.value.center);
      if (entry.value.priority < lowestPriority) {
        lowestPriority = entry.value.priority;
      }
    }

    _updateBubbleField(centres, lowestPriority);
    _updateMergedVideo(lowestPriority);
  }

  void _applyBubbleRepulsion(double dt) {
    final entries = _playerBubbles.entries.toList();
    if (entries.length < 2) return;

    _bubbleDisplacements
        .removeWhere((k, _) => !_playerBubbles.containsKey(k));

    final forces = <String, Vector2>{};
    for (var i = 0; i < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        final ci = entries[i].value.center;
        final cj = entries[j].value.center;
        final delta = ci - cj;
        final dist = delta.length;
        if (dist < _bubbleDiameter && dist > 0.01) {
          final overlap = _bubbleDiameter - dist;
          final direction = delta.normalized();
          final clampedDt = min(dt, 0.05);
          final push = direction * (overlap * _repulsionForceCoefficient * clampedDt);
          forces[entries[i].key] =
              (forces[entries[i].key] ?? Vector2.zero()) + push;
          forces[entries[j].key] =
              (forces[entries[j].key] ?? Vector2.zero()) - push;
        }
      }
    }

    for (final entry in entries) {
      final key = entry.key;
      var disp = _bubbleDisplacements[key] ?? Vector2.zero();
      // Damp first so accumulated drift decays before new force is applied,
      // then add this frame's force, then cap — so even a large single-frame
      // impulse cannot bypass the tether limit.
      disp = disp * _repulsionDamping;
      disp += forces[key] ?? Vector2.zero();
      if (disp.length > _maxTetherDistance) {
        disp = disp.normalized() * _maxTetherDistance;
      }
      _bubbleDisplacements[key] = disp;
      entry.value.position += disp;
    }
  }

  void _updateBubbleField(List<Vector2> centres, int lowestPriority) {
    if (centres.length < 2 || _metaballShaderProgram == null) {
      _bubbleField?.removeFromParent();
      _bubbleField = null;
      return;
    }

    if (_bubbleField == null) {
      _bubbleField = BubbleFieldComponent(
        shaderProgram: _metaballShaderProgram!,
        glowColor: const Color(0xFF00FF88),
        bubbleRadius: 32,
        reduceMotion: reduceMotion,
      );
      _addComponent(_bubbleField!);
    }

    // Live-propagate so toggling reduce-motion does not require dropping the
    // field component (which would happen only when the merge group shrinks).
    _bubbleField!.reduceMotion = reduceMotion;
    _bubbleField!.priority = lowestPriority - 1;
    _bubbleField!.updateBubblePositions(centres);
  }

  void _updateMergedVideo(int lowestPriority) {
    if (_mergedVideoShaderProgram == null) return;

    final videoBubbles = <String, VideoBubbleComponent>{};
    for (final entry in _playerBubbles.entries) {
      if (entry.value is VideoBubbleComponent) {
        videoBubbles[entry.key] = entry.value as VideoBubbleComponent;
      }
    }

    if (_mergeGroupDirty) {
      _cachedMergeGroup = _findMergeGroup(videoBubbles);
      _mergeGroupDirty = false;
    }
    final mergeGroup = _cachedMergeGroup;

    if (mergeGroup.length >= 2) {
      if (_mergedBubble == null) {
        _mergedBubble = MergedVideoBubbleComponent(
          shaderProgram: _mergedVideoShaderProgram!,
          glowColor: const Color(0xFF00FF88),
          bubbleRadius: 32,
          reduceMotion: reduceMotion,
        );
        _addComponent(_mergedBubble!);
      }
      // Live-propagate so a toggle takes effect without re-creating the merge.
      _mergedBubble!.reduceMotion = reduceMotion;

      final sources = <VideoBubbleComponent>[];
      final positions = <Vector2>[];
      for (final key in mergeGroup) {
        final bubble = videoBubbles[key]!;
        bubble.hiddenForMerge = true;
        sources.add(bubble);
        positions.add(bubble.center);
      }

      _mergedBubble!.priority = lowestPriority;
      _mergedBubble!.updateSources(sources);
      _mergedBubble!.updatePositions(positions);

      for (final entry in videoBubbles.entries) {
        if (!mergeGroup.contains(entry.key)) {
          entry.value.hiddenForMerge = false;
        }
      }
    } else {
      for (final bubble in videoBubbles.values) {
        bubble.hiddenForMerge = false;
      }
      _mergedBubble?.removeFromParent();
      _mergedBubble = null;
    }
  }

  List<String> _findMergeGroup(Map<String, VideoBubbleComponent> bubbles) {
    if (bubbles.length < 2) return [];

    final keys = bubbles.keys.toList();
    final visited = <String>{};
    List<String> largestGroup = [];

    for (final startKey in keys) {
      if (visited.contains(startKey)) continue;

      final group = <String>[startKey];
      final queue = Queue<String>()..add(startKey);
      visited.add(startKey);

      while (queue.isNotEmpty) {
        final current = queue.removeFirst();
        final currentCenter = bubbles[current]!.center;

        for (final candidateKey in keys) {
          if (visited.contains(candidateKey)) continue;
          final candidateCenter = bubbles[candidateKey]!.center;
          final dist = currentCenter.distanceTo(candidateCenter);
          if (dist < _mergeThreshold) {
            visited.add(candidateKey);
            group.add(candidateKey);
            queue.add(candidateKey);
          }
        }
      }

      if (group.length > largestGroup.length) {
        largestGroup = group;
      }
    }

    return largestGroup.length >= 2
        ? largestGroup.take(maxMergedBubbles).toList()
        : [];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Private — AV diagnostics
  // ═══════════════════════════════════════════════════════════════════════════

  void _dispatchBubbleCreated(String playerId, PositionComponent bubble) {
    if (!avDiagnosticsEnabled) return;
    final type = switch (bubble) {
      VideoBubbleComponent() => AvBubbleType.video,
      PlayerBubbleComponent() => AvBubbleType.player,
      BotBubbleComponent() => AvBubbleType.bot,
      _ => AvBubbleType.player,
    };
    dispatch([AvBubbleCreated(participant: playerId, bubbleType: type)]);
  }

  void _dispatchPipelineSnapshots() {
    final playerGrid = _localPlayer.miniGridPosition;
    final events = <AppEvent>[];

    for (final entry in _remotePlayers.entries) {
      final playerId = entry.key;
      final playerComponent = entry.value;
      final distance =
          chebyshevDistance(playerGrid, playerComponent.miniGridPosition);
      final bubble = _playerBubbles[playerId];
      final participant = _liveKitService?.getParticipant(playerId);

      events.add(_snapshotForParticipant(
        playerId: playerId,
        bubble: bubble,
        participant: participant,
        distance: distance,
        isLocal: false,
      ));
    }

    // Local player snapshot (publish state).
    final localBubble = _playerBubbles[_localPlayerBubbleKey];
    final localParticipant = _liveKitService?.localParticipant;
    events.add(_snapshotForParticipant(
      playerId: _localPlayerBubbleKey,
      bubble: localBubble,
      participant: localParticipant,
      distance: 0,
      isLocal: true,
    ));

    if (events.isNotEmpty) dispatch(events);
  }

  AvPipelineSnapshot _snapshotForParticipant({
    required String playerId,
    required PositionComponent? bubble,
    required Participant? participant,
    required int distance,
    required bool isLocal,
  }) {
    final hasVideoTrack =
        participant != null ? _hasVideoTrack(participant) : false;

    AvCaptureMethod? captureMethod;
    int captureRetryCount = 0;
    int framesCaptured = 0;
    int framesDropped = 0;

    if (bubble is VideoBubbleComponent) {
      captureMethod = bubble.diagnosticCaptureMethod;
      captureRetryCount = bubble.diagnosticCaptureRetryCount;
      framesCaptured = bubble.diagnosticFramesCaptured;
      framesDropped = bubble.diagnosticFramesDropped;
    }

    final bubbleType = switch (bubble) {
      VideoBubbleComponent() => AvBubbleType.video,
      PlayerBubbleComponent() => AvBubbleType.player,
      BotBubbleComponent() => AvBubbleType.bot,
      null => null,
      _ => AvBubbleType.player,
    };

    return AvPipelineSnapshot(
      participant: playerId,
      hasVideoTrack: hasVideoTrack,
      captureMethod: captureMethod,
      captureRetryCount: captureRetryCount,
      framesCaptured: framesCaptured,
      framesDropped: framesDropped,
      bubbleType: bubbleType,
      audioEnabled: _audioEnabledParticipants.contains(playerId),
      distance: distance,
      isLocal: isLocal,
    );
  }
}
