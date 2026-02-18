import 'dart:async';
import 'dart:math';

class ProximityEvent {
  ProximityEvent({
    required this.playerId,
    required this.isNearby,
    required this.position,
    required this.distance,
  });

  final String playerId;
  final bool isNearby;
  final Point<int> position;

  /// Chebyshev distance between the local player and this player.
  final int distance;
}

/// Service that detects when players are within proximity of each other.
///
/// Uses Chebyshev distance (max of x/y difference) to account for diagonal movement.
class ProximityService {
  ProximityService({this.proximityThreshold = 5});

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
          distance: distance,
        ));
      } else if (!isNearby && wasNearby) {
        _nearbyPlayers.remove(playerId);
        _proximityController.add(ProximityEvent(
          playerId: playerId,
          isNearby: false,
          position: otherPosition,
          distance: distance,
        ));
      } else if (isNearby && wasNearby) {
        // Already nearby — emit update with current distance for fade
        _proximityController.add(ProximityEvent(
          playerId: playerId,
          isNearby: true,
          position: otherPosition,
          distance: distance,
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
        distance: proximityThreshold + 1,
      ));
    }
  }

  /// Chebyshev distance - allows diagonal movement to count as 1 step
  int _calculateChebyshevDistance(Point<int> a, Point<int> b) {
    return max((a.x - b.x).abs(), (a.y - b.y).abs());
  }

  /// Calculate visual opacity based on Chebyshev distance.
  ///
  /// - Distance 0–1: 1.0 (fully visible)
  /// - Distance 2: 0.8
  /// - Distance 3: 0.5
  /// - Distance 4: 0.2
  /// - Distance 5+: 0.0 (removed by caller)
  static double calculateOpacity(int distance) {
    if (distance <= 1) return 1.0;
    if (distance == 2) return 0.8;
    if (distance == 3) return 0.5;
    if (distance == 4) return 0.2;
    return 0.0;
  }

  void dispose() {
    _proximityController.close();
  }
}
