import 'dart:math';

/// A game map definition containing barrier layout and spawn configuration.
///
/// Maps define the walkable/non-walkable areas of the game world.
/// Barriers are specified in mini-grid coordinates (0 to gridSize-1).
class GameMap {
  const GameMap({
    required this.id,
    required this.name,
    required this.barriers,
    this.spawnPoint = const Point(25, 25),
    this.terminals = const [],
  });

  /// Unique identifier for this map.
  final String id;

  /// Display name shown to players.
  final String name;

  /// List of barrier positions in mini-grid coordinates.
  /// Players cannot walk through these cells.
  final List<Point<int>> barriers;

  /// Default spawn point for players in mini-grid coordinates.
  final Point<int> spawnPoint;

  /// Positions of coding terminal stations in mini-grid coordinates.
  final List<Point<int>> terminals;
}
