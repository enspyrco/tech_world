import 'dart:math';

import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/generators/grid_utils.dart';
import 'package:tech_world/flame/maps/generators/map_generator.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// Generates a cave-like map using cellular automata.
///
/// Algorithm:
/// 1. Random fill with [GeneratorConfig.caveFillChance] wall probability.
/// 2. Border cells are always walls.
/// 3. Run [GeneratorConfig.caveSmoothingIterations] smoothing passes (B5/S4).
/// 4. Keep the largest connected open region, fill rest as walls.
/// 5. Spawn at the centroid of the largest region.
GameMap generateCave({required int seed, required GeneratorConfig config}) {
  final rng = Random(seed);
  final grid = _randomFill(rng, config.caveFillChance);

  for (var i = 0; i < config.caveSmoothingIterations; i++) {
    _smooth(grid);
  }

  final region = largestOpenRegion(grid);
  removeDisconnectedRegions(grid, region);
  final spawn = findSpawnPoint(grid, region);

  final layers = buildTileLayers(grid, floorTileIndex: 162);

  return GameMap(
    id: 'generated_cave_$seed',
    name: 'Cave #$seed',
    barriers: gridToBarriers(grid),
    spawnPoint: spawn,
    floorLayer: layers.floor,
    objectLayer: layers.objects,
    tilesetIds: const ['room_builder_office'],
  );
}

/// Creates a grid with random walls. Border cells are always walls.
Grid _randomFill(Random rng, double fillChance) {
  final grid = createEmptyGrid();
  for (var y = 0; y < gridSize; y++) {
    for (var x = 0; x < gridSize; x++) {
      if (x == 0 || x == gridSize - 1 || y == 0 || y == gridSize - 1) {
        grid[y][x] = true; // solid border
      } else {
        grid[y][x] = rng.nextDouble() < fillChance;
      }
    }
  }
  return grid;
}

/// One smoothing pass using the B5/S4 rule:
/// - A wall stays if it has >= 4 wall neighbors (survives).
/// - An open cell becomes wall if it has >= 5 wall neighbors (birth).
void _smooth(Grid grid) {
  final snapshot =
      List.generate(gridSize, (y) => List.of(grid[y]));

  for (var y = 1; y < gridSize - 1; y++) {
    for (var x = 1; x < gridSize - 1; x++) {
      final walls = _countWallNeighbors(snapshot, x, y);
      if (snapshot[y][x]) {
        grid[y][x] = walls >= 4; // survive
      } else {
        grid[y][x] = walls >= 5; // birth
      }
    }
  }
}

/// Counts the 8 neighbors of (x, y) that are walls.
int _countWallNeighbors(Grid grid, int x, int y) {
  var count = 0;
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      if (dx == 0 && dy == 0) continue;
      if (grid[y + dy][x + dx]) count++;
    }
  }
  return count;
}
