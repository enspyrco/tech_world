import 'dart:async';
import 'dart:math';

class ProximityEvent {
  ProximityEvent({
    required this.playerId,
    required this.isNearby,
    required this.position,
  });

  final String playerId;
  final bool isNearby;
  final Point<int> position;
}

/// Service that detects when players are within proximity of each other.
///
/// Uses Chebyshev distance (max of x/y difference) to account for diagonal movement.
class ProximityService {
  ProximityService({this.proximityThreshold = 3});

  /// Distance in grid squares to trigger proximity
  final int proximityThreshold;

  final _proximityController = StreamController<ProximityEvent>.broadcast();
  final Set<String> _nearbyPlayers = {};

  Stream<ProximityEvent> get proximityEvents => _proximityController.stream;
  Set<String> get nearbyPlayers => Set.unmodifiable(_nearbyPlayers);

  /// Check proximity between local player and all other players.
  /// Emits events when players enter or exit proximity range.
  void checkProximity({
    required Point<int> localPlayerPosition,
    required Map<String, Point<int>> otherPlayerPositions,
  }) {
    for (final entry in otherPlayerPositions.entries) {
      final playerId = entry.key;
      final otherPosition = entry.value;

      final distance =
          _calculateChebyshevDistance(localPlayerPosition, otherPosition);
      final isNearby = distance <= proximityThreshold;
      final wasNearby = _nearbyPlayers.contains(playerId);

      if (isNearby && !wasNearby) {
        _nearbyPlayers.add(playerId);
        _proximityController.add(ProximityEvent(
          playerId: playerId,
          isNearby: true,
          position: otherPosition,
        ));
      } else if (!isNearby && wasNearby) {
        _nearbyPlayers.remove(playerId);
        _proximityController.add(ProximityEvent(
          playerId: playerId,
          isNearby: false,
          position: otherPosition,
        ));
      }
    }

    // Handle players who left the game
    final currentPlayerIds = otherPlayerPositions.keys.toSet();
    final removedPlayers = _nearbyPlayers.difference(currentPlayerIds);
    for (final playerId in removedPlayers) {
      _nearbyPlayers.remove(playerId);
      _proximityController.add(ProximityEvent(
        playerId: playerId,
        isNearby: false,
        position: const Point(0, 0),
      ));
    }
  }

  /// Chebyshev distance - allows diagonal movement to count as 1 step
  int _calculateChebyshevDistance(Point<int> a, Point<int> b) {
    return max((a.x - b.x).abs(), (a.y - b.y).abs());
  }

  void dispose() {
    _proximityController.close();
  }
}
