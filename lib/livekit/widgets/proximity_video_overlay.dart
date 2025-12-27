import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/livekit/widgets/bot_bubble.dart';
import 'package:tech_world/livekit/widgets/video_bubble.dart';
import 'package:tech_world/proximity/proximity_service.dart';

/// The bot user ID - must match the server's bot_user.dart
const _botUserId = 'bot-claude';
const _botDisplayName = 'Claude';

/// Overlay that displays video bubbles above players when they are in proximity.
class ProximityVideoOverlay extends StatefulWidget {
  const ProximityVideoOverlay({
    required this.room,
    required this.techWorld,
    required this.proximityService,
    this.bubbleSize = 80,
    super.key,
  });

  final Room room;
  final TechWorld techWorld;
  final ProximityService proximityService;
  final double bubbleSize;

  @override
  State<ProximityVideoOverlay> createState() => _ProximityVideoOverlayState();
}

class _ProximityVideoOverlayState extends State<ProximityVideoOverlay> {
  late final StreamSubscription<ProximityEvent> _proximitySubscription;
  Timer? _updateTimer;

  final Map<String, Point<int>> _nearbyPlayerPositions = {};

  @override
  void initState() {
    super.initState();

    _proximitySubscription =
        widget.proximityService.proximityEvents.listen((event) {
      setState(() {
        if (event.isNearby) {
          _nearbyPlayerPositions[event.playerId] = event.position;
        } else {
          _nearbyPlayerPositions.remove(event.playerId);
        }
      });
    });

    // Poll for position updates and proximity checks
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final positions = widget.techWorld.otherPlayerPositions;

      // Update positions of nearby players
      for (final playerId in _nearbyPlayerPositions.keys.toList()) {
        if (positions.containsKey(playerId)) {
          _nearbyPlayerPositions[playerId] = positions[playerId]!;
        }
      }

      // Check proximity
      widget.proximityService.checkProximity(
        localPlayerPosition: widget.techWorld.localPlayerPosition,
        otherPlayerPositions: positions,
      );

      // Trigger rebuild for position updates
      if (_nearbyPlayerPositions.isNotEmpty) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _proximitySubscription.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  Participant? _findParticipant(String playerId) {
    // Check local participant
    if (widget.room.localParticipant?.identity == playerId) {
      return widget.room.localParticipant;
    }
    // Check remote participants
    for (final participant in widget.room.remoteParticipants.values) {
      if (participant.identity == playerId) {
        return participant;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportCenter = Offset(
          constraints.maxWidth / 2,
          constraints.maxHeight / 2,
        );

        final localPlayerGridPos = widget.techWorld.localPlayerPosition;
        final bubbles = <Widget>[];

        // Add bubbles for nearby players
        for (final entry in _nearbyPlayerPositions.entries) {
          final screenPosition = _gridToScreen(
            entry.value,
            localPlayerGridPos,
            viewportCenter,
          );

          // Only show if on screen
          if (!_isOnScreen(screenPosition, constraints)) continue;

          // Special handling for bot - show BotBubble instead of VideoBubble
          if (entry.key == _botUserId) {
            bubbles.add(
              Positioned(
                left: screenPosition.dx - widget.bubbleSize / 2,
                top: screenPosition.dy - widget.bubbleSize - 20,
                child: BotBubble(
                  key: ValueKey(entry.key),
                  name: _botDisplayName,
                  size: widget.bubbleSize,
                ),
              ),
            );
            continue;
          }

          // Regular participant handling
          final participant = _findParticipant(entry.key);
          if (participant != null) {
            bubbles.add(
              Positioned(
                left: screenPosition.dx - widget.bubbleSize / 2,
                top: screenPosition.dy - widget.bubbleSize - 20,
                child: VideoBubble(
                  key: ValueKey(entry.key),
                  participant: participant,
                  size: widget.bubbleSize,
                ),
              ),
            );
          }
        }

        // Add local player bubble if any other players are nearby
        if (_nearbyPlayerPositions.isNotEmpty &&
            widget.room.localParticipant != null) {
          bubbles.add(
            Positioned(
              left: viewportCenter.dx - widget.bubbleSize / 2,
              top: viewportCenter.dy - widget.bubbleSize - 20,
              child: VideoBubble(
                key: const ValueKey('local'),
                participant: widget.room.localParticipant!,
                size: widget.bubbleSize,
              ),
            ),
          );
        }

        return Stack(children: bubbles);
      },
    );
  }

  /// Convert grid position to screen coordinates.
  /// Since camera follows the local player (centered), we calculate
  /// other positions relative to the local player's position.
  Offset _gridToScreen(
    Point<int> gridPosition,
    Point<int> localPlayerGridPos,
    Offset viewportCenter,
  ) {
    // Calculate difference in grid positions
    final deltaX = gridPosition.x - localPlayerGridPos.x;
    final deltaY = gridPosition.y - localPlayerGridPos.y;

    // Convert to pixels and add to viewport center
    return Offset(
      viewportCenter.dx + deltaX * gridSquareSize,
      viewportCenter.dy + deltaY * gridSquareSize,
    );
  }

  bool _isOnScreen(Offset position, BoxConstraints constraints) {
    return position.dx >= -widget.bubbleSize &&
        position.dx <= constraints.maxWidth + widget.bubbleSize &&
        position.dy >= -widget.bubbleSize &&
        position.dy <= constraints.maxHeight + widget.bubbleSize;
  }
}
