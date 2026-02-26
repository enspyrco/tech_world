import 'dart:math';

import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/generators/grid_utils.dart';
import 'package:tech_world/flame/maps/generators/map_generator.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// Generates a maze using the recursive backtracker algorithm.
///
/// Algorithm:
/// 1. Start with a filled grid (all walls).
/// 2. Carve passages using 2-cell steps (wall + passage) for visible corridors.
///    The playable area allows up to 24x24 maze cells.
/// 3. Random DFS with stack-based backtracking.
/// 4. Optionally remove dead ends based on [GeneratorConfig.mazeDeadEndRemovalChance].
/// 5. Spawn at the maze start cell.
GameMap generateMaze({required int seed, required GeneratorConfig config}) {
  final rng = Random(seed);
  final grid = createFilledGrid();

  // Maze cells live on odd coordinates within the playable area.
  // With gridSize=50, odd coords 1,3,5,...,47 give us 24 cells per axis.
  const startX = 1;
  const startY = 1;

  // Carve the starting cell.
  grid[startY][startX] = false;

  final stack = <Point<int>>[const Point(startX, startY)];

  while (stack.isNotEmpty) {
    final current = stack.last;
    final neighbors = _unvisitedNeighbors(grid, current);

    if (neighbors.isEmpty) {
      stack.removeLast();
    } else {
      final next = neighbors[rng.nextInt(neighbors.length)];

      // Carve the wall between current and next.
      final wallX = current.x + (next.x - current.x) ~/ 2;
      final wallY = current.y + (next.y - current.y) ~/ 2;
      grid[wallY][wallX] = false;

      // Carve the next cell.
      grid[next.y][next.x] = false;
      stack.add(next);
    }
  }

  // Remove dead ends.
  if (config.mazeDeadEndRemovalChance > 0) {
    _removeDeadEnds(grid, rng, config.mazeDeadEndRemovalChance);
  }

  // Ensure connectivity (should already be connected, but safety net).
  final region = largestOpenRegion(grid);
  removeDisconnectedRegions(grid, region);

  final spawn = const Point(startX, startY);

  final layers = buildTileLayers(grid);

  return GameMap(
    id: 'generated_maze_$seed',
    name: 'Maze #$seed',
    barriers: gridToBarriers(grid),
    spawnPoint: spawn,
    floorLayer: layers.floor,
    objectLayer: layers.objects,
    tilesetIds: const ['room_builder_office'],
  );
}

// ---------------------------------------------------------------------------
// Maze carving helpers
// ---------------------------------------------------------------------------

/// Cardinal directions as 2-cell steps (for the maze grid).
const _directions = [
  Point(0, -2), // up
  Point(0, 2), // down
  Point(-2, 0), // left
  Point(2, 0), // right
];

/// Returns unvisited neighbors (still walls) reachable by a 2-cell step.
List<Point<int>> _unvisitedNeighbors(Grid grid, Point<int> cell) {
  final neighbors = <Point<int>>[];
  for (final dir in _directions) {
    final nx = cell.x + dir.x;
    final ny = cell.y + dir.y;
    if (nx > 0 && nx < gridSize && ny > 0 && ny < gridSize && grid[ny][nx]) {
      neighbors.add(Point(nx, ny));
    }
  }
  return neighbors;
}

// ---------------------------------------------------------------------------
// Dead-end removal
// ---------------------------------------------------------------------------

/// Removes dead ends by opening a wall to a random adjacent corridor.
///
/// A dead end is an open cell with exactly 3 wall neighbors in the 4 cardinal
/// directions. Multiple passes are made until no more removals occur.
void _removeDeadEnds(Grid grid, Random rng, double chance) {
  var changed = true;
  while (changed) {
    changed = false;
    for (var y = 1; y < gridSize - 1; y++) {
      for (var x = 1; x < gridSize - 1; x++) {
        if (grid[y][x]) continue; // skip walls

        final wallCount = _cardinalWalls(grid, x, y);
        if (wallCount == 3 && rng.nextDouble() < chance) {
          // Find a wall neighbor that, if removed, connects to another
          // open cell (or just remove any wall neighbor).
          final wallDirs = <Point<int>>[];
          for (final dir in _cardinalDirs) {
            final nx = x + dir.x;
            final ny = y + dir.y;
            if (nx > 0 &&
                nx < gridSize - 1 &&
                ny > 0 &&
                ny < gridSize - 1 &&
                grid[ny][nx]) {
              wallDirs.add(dir);
            }
          }
          if (wallDirs.isNotEmpty) {
            final dir = wallDirs[rng.nextInt(wallDirs.length)];
            grid[y + dir.y][x + dir.x] = false;
            changed = true;
          }
        }
      }
    }
  }
}

const _cardinalDirs = [
  Point(0, -1),
  Point(0, 1),
  Point(-1, 0),
  Point(1, 0),
];

int _cardinalWalls(Grid grid, int x, int y) {
  var count = 0;
  for (final dir in _cardinalDirs) {
    if (grid[y + dir.y][x + dir.x]) count++;
  }
  return count;
}
