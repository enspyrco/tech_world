import 'dart:math';

import 'game_map.dart';

/// Open Arena - no barriers, free movement everywhere.
const openArena = GameMap(
  id: 'open_arena',
  name: 'Open Arena',
  barriers: [],
  spawnPoint: Point(25, 25),
);

/// The L-Room - original map with L-shaped walls.
const lRoom = GameMap(
  id: 'l_room',
  name: 'The L-Room',
  barriers: [
    // Vertical wall at x=4
    Point(4, 7),
    Point(4, 8),
    Point(4, 9),
    Point(4, 10),
    Point(4, 11),
    Point(4, 12),
    Point(4, 13),
    Point(4, 14),
    Point(4, 15),
    Point(4, 16),
    Point(4, 18),
    Point(4, 19),
    Point(4, 20),
    Point(4, 21),
    Point(4, 22),
    Point(4, 23),
    Point(4, 24),
    Point(4, 25),
    Point(4, 26),
    Point(4, 27),
    Point(4, 28),
    Point(4, 29),
    // Horizontal wall at y=7
    Point(5, 7),
    Point(6, 7),
    Point(7, 7),
    Point(8, 7),
    Point(9, 7),
    Point(10, 7),
    Point(11, 7),
    Point(12, 7),
    Point(13, 7),
    Point(14, 7),
    Point(15, 7),
    Point(16, 7),
    Point(17, 7),
  ],
  spawnPoint: Point(10, 15),
  terminals: [Point(8, 12), Point(14, 12)],
);

/// Four Corners - barriers in each corner, open center.
final fourCorners = GameMap(
  id: 'four_corners',
  name: 'Four Corners',
  barriers: [
    // Top-left corner (5x5 block)
    ..._generateBlock(2, 2, 5, 5),
    // Top-right corner
    ..._generateBlock(43, 2, 5, 5),
    // Bottom-left corner
    ..._generateBlock(2, 43, 5, 5),
    // Bottom-right corner
    ..._generateBlock(43, 43, 5, 5),
  ],
  spawnPoint: const Point(25, 25),
);

/// Simple Maze - a basic maze pattern.
final simpleMaze = GameMap(
  id: 'simple_maze',
  name: 'Simple Maze',
  barriers: _deduplicateBarriers([
    // Outer walls (with gaps for entry/exit)
    ..._generateHorizontalWall(5, 5, 40, gap: 20),
    ..._generateHorizontalWall(5, 44, 40, gap: 25),
    ..._generateVerticalWall(5, 6, 38, gap: 22), // Start at y=6 to avoid corner overlap
    ..._generateVerticalWall(44, 6, 38, gap: 22), // Start at y=6 to avoid corner overlap
    // Internal maze walls
    ..._generateHorizontalWall(10, 15, 25),
    ..._generateVerticalWall(20, 10, 20, gap: 15),
    ..._generateHorizontalWall(25, 30, 15),
    ..._generateVerticalWall(30, 20, 15, gap: 27),
  ]),
  spawnPoint: const Point(8, 8),
);

/// All available maps.
final allMaps = [openArena, lRoom, fourCorners, simpleMaze];

/// Default map to use when none is specified.
const defaultMap = lRoom;

// Helper functions for generating barrier patterns

/// Remove duplicate barriers from a list.
List<Point<int>> _deduplicateBarriers(List<Point<int>> barriers) {
  return barriers.toSet().toList();
}

/// Generate a rectangular block of barriers.
List<Point<int>> _generateBlock(int startX, int startY, int width, int height) {
  final points = <Point<int>>[];
  for (var y = startY; y < startY + height; y++) {
    for (var x = startX; x < startX + width; x++) {
      points.add(Point(x, y));
    }
  }
  return points;
}

/// Generate a horizontal wall with optional gap.
List<Point<int>> _generateHorizontalWall(int startX, int y, int length,
    {int? gap}) {
  final points = <Point<int>>[];
  for (var x = startX; x < startX + length; x++) {
    if (gap == null || x != gap) {
      points.add(Point(x, y));
    }
  }
  return points;
}

/// Generate a vertical wall with optional gap.
List<Point<int>> _generateVerticalWall(int x, int startY, int length,
    {int? gap}) {
  final points = <Point<int>>[];
  for (var y = startY; y < startY + length; y++) {
    if (gap == null || y != gap) {
      points.add(Point(x, y));
    }
  }
  return points;
}
