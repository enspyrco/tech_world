import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:livekit_client/livekit_client.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/player_bubble_component.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/components/video_bubble_component.dart';
import 'package:tech_world/flame/shared/tech_world_config.dart';
import 'package:tech_world/livekit/livekit_service.dart';

/// Callback to add a component to the game world.
typedef AddComponent = void Function(Component component);

/// Manages player bubble components (video, static, bot) based on proximity.
///
/// Bubbles follow their target components automatically via their own update().
class BubbleManager {
  BubbleManager({
    required AddComponent addComponent,
    required PositionComponent localPlayerComponent,
  })  : _addComponent = addComponent,
        _localPlayerComponent = localPlayerComponent;

  final AddComponent _addComponent;
  final PositionComponent _localPlayerComponent;

  // Bubble components - shown when player is near other players
  final Map<String, PositionComponent> _playerBubbles = {};
  Point<int>? _lastPlayerGridPosition;

  // LiveKit integration for video bubbles
  LiveKitService? _liveKitService;
  ui.FragmentProgram? _shaderProgram;

  /// Set the LiveKit service for video bubble support.
  void setLiveKitService(LiveKitService service) {
    _liveKitService = service;
  }

  /// Set the shader program for video bubble effects.
  void setShaderProgram(ui.FragmentProgram program) {
    _shaderProgram = program;
  }

  /// Update bubbles based on player positions.
  ///
  /// Creates/removes bubbles based on proximity. Position updates are handled
  /// by each bubble's own update() method.
  void update({
    required Point<int> localPlayerPosition,
    required String localPlayerDisplayName,
    required String localPlayerId,
    required Map<String, PlayerComponent> otherPlayers,
  }) {
    // Skip update if player hasn't moved to a new grid position
    if (_lastPlayerGridPosition == localPlayerPosition) {
      return;
    }
    _lastPlayerGridPosition = localPlayerPosition;

    // Check each other player for proximity
    final nearbyPlayerIds = <String>{};

    for (final entry in otherPlayers.entries) {
      final playerId = entry.key;
      final playerComponent = entry.value;

      // Calculate Chebyshev distance (max of x/y difference)
      final otherGrid = playerComponent.miniGridPosition;
      final distance = max(
        (otherGrid.x - localPlayerPosition.x).abs(),
        (otherGrid.y - localPlayerPosition.y).abs(),
      );

      final isNearby = distance <= TechWorldConfig.proximityThreshold;

      if (isNearby) {
        nearbyPlayerIds.add(playerId);

        if (!_playerBubbles.containsKey(playerId)) {
          final bubble = _createBubbleForPlayer(playerId, playerComponent);
          _playerBubbles[playerId] = bubble;
          _addComponent(bubble);
        }
      }
    }

    // Show local player's bubble if near anyone
    if (nearbyPlayerIds.isNotEmpty) {
      if (!_playerBubbles.containsKey(TechWorldConfig.localPlayerBubbleKey)) {
        final localBubble = _createLocalPlayerBubble(
          displayName: localPlayerDisplayName,
          playerId: localPlayerId,
        );
        _playerBubbles[TechWorldConfig.localPlayerBubbleKey] = localBubble;
        _addComponent(localBubble);
      }
      nearbyPlayerIds.add(TechWorldConfig.localPlayerBubbleKey);
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
  }

  PositionComponent _createBubbleForPlayer(
      String playerId, PlayerComponent playerComponent) {
    if (playerId == TechWorldConfig.botUserId) {
      return BotBubbleComponent(
        name: TechWorldConfig.botDisplayName,
        target: playerComponent,
      );
    }

    // Check if this player has a LiveKit participant with video
    final participant = _liveKitService?.getParticipant(playerId);
    if (participant != null && _hasVideoTrack(participant)) {
      final videoBubble = VideoBubbleComponent(
        participant: participant,
        displayName: playerComponent.displayName,
        target: playerComponent,
        bubbleSize: TechWorldConfig.defaultBubbleSize,
        targetFps: TechWorldConfig.defaultTargetFps,
      );

      if (_shaderProgram != null) {
        videoBubble.setShader(_shaderProgram!.fragmentShader());
      }

      return videoBubble;
    }

    // Fallback to static bubble
    return PlayerBubbleComponent(
      displayName: playerComponent.displayName,
      playerId: playerId,
      target: playerComponent,
    );
  }

  PositionComponent _createLocalPlayerBubble({
    required String displayName,
    required String playerId,
  }) {
    final localParticipant = _liveKitService?.localParticipant;

    if (localParticipant != null && _hasVideoTrack(localParticipant)) {
      final videoBubble = VideoBubbleComponent(
        participant: localParticipant,
        displayName: displayName,
        target: _localPlayerComponent,
        bubbleSize: TechWorldConfig.defaultBubbleSize,
        targetFps: TechWorldConfig.defaultTargetFps,
      );

      if (_shaderProgram != null) {
        videoBubble.setShader(_shaderProgram!.fragmentShader());
      }

      // Local player gets a cyan glow
      videoBubble.glowColor = Colors.cyan;

      return videoBubble;
    }

    // Fallback to static bubble
    return PlayerBubbleComponent(
      displayName: displayName,
      playerId: playerId,
      target: _localPlayerComponent,
    );
  }

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

  /// Refresh a player's bubble (recreate if video is now available).
  void refreshBubble(
    String bubbleKey, {
    required bool isLocal,
    required String localPlayerDisplayName,
    required String localPlayerId,
    required Map<String, PlayerComponent> otherPlayers,
  }) {
    final existingBubble = _playerBubbles[bubbleKey];
    if (existingBubble == null) return;

    // If it's already a video bubble, no need to refresh
    if (existingBubble is VideoBubbleComponent) return;

    // For remote players, we need the player component
    if (!isLocal) {
      final playerComponent = otherPlayers[bubbleKey];
      if (playerComponent == null) return;
    }

    // Remove old bubble
    existingBubble.removeFromParent();

    // Create new bubble (might be video bubble now)
    final newBubble = isLocal
        ? _createLocalPlayerBubble(
            displayName: localPlayerDisplayName,
            playerId: localPlayerId,
          )
        : _createBubbleForPlayer(bubbleKey, otherPlayers[bubbleKey]!);

    _playerBubbles[bubbleKey] = newBubble;
    _addComponent(newBubble);
  }

  /// Update speaking state on a video bubble.
  void updateSpeakingState(String participantId, bool isSpeaking) {
    final bubble = _playerBubbles[participantId];
    if (bubble is VideoBubbleComponent) {
      bubble.speakingLevel = isSpeaking ? 1.0 : 0.0;
    }
  }

  /// Notify a video bubble that its track is ready for capture.
  void notifyTrackReady(String participantId) {
    final bubble = _playerBubbles[participantId];
    if (bubble is VideoBubbleComponent) {
      bubble.notifyTrackReady();
    }
  }
}
