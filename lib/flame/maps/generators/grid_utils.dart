import 'dart:math';

import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';

/// A 2D grid where `true` means wall and `false` means open space.
typedef Grid = List<List<bool>>;

/// Creates a [gridSize] x [gridSize] grid filled entirely with walls.
Grid createFilledGrid() =>
    List.generate(gridSize, (_) => List.filled(gridSize, true));

/// Creates a [gridSize] x [gridSize] grid filled entirely with open space.
Grid createEmptyGrid() =>
    List.generate(gridSize, (_) => List.filled(gridSize, false));

/// Flood-fills from [start] using 8-directional movement (matching the game's
/// Chebyshev-distance movement model). Returns the set of all reachable open
/// cells including [start].
///
/// Cells outside bounds or marked as walls are not traversed.
Set<Point<int>> floodFill(Grid grid, Point<int> start) {
  final rows = grid.length;
  final cols = rows > 0 ? grid[0].length : 0;
  final visited = <Point<int>>{};
  final stack = <Point<int>>[start];
  visited.add(start);

  while (stack.isNotEmpty) {
    final current = stack.removeLast();
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        if (dx == 0 && dy == 0) continue;
        final nx = current.x + dx;
        final ny = current.y + dy;
        if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) continue;
        final neighbor = Point(nx, ny);
        if (grid[ny][nx] || visited.contains(neighbor)) continue;
        visited.add(neighbor);
        stack.add(neighbor);
      }
    }
  }
  return visited;
}

/// Finds the largest connected region of open cells in [grid].
///
/// Returns the set of [Point<int>] belonging to that region, or an empty set
/// if the entire grid is walls.
Set<Point<int>> largestOpenRegion(Grid grid) {
  final rows = grid.length;
  final cols = rows > 0 ? grid[0].length : 0;
  final visited = <Point<int>>{};
  Set<Point<int>> largest = {};

  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      if (grid[y][x]) continue; // wall
      final pt = Point(x, y);
      if (visited.contains(pt)) continue;

      final region = floodFill(grid, pt);
      visited.addAll(region);
      if (region.length > largest.length) {
        largest = region;
      }
    }
  }
  return largest;
}

/// Fills all open cells **not** in [keepRegion] as walls. This removes
/// disconnected pockets that players could never reach.
void removeDisconnectedRegions(Grid grid, Set<Point<int>> keepRegion) {
  final rows = grid.length;
  final cols = rows > 0 ? grid[0].length : 0;
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      if (!grid[y][x] && !keepRegion.contains(Point(x, y))) {
        grid[y][x] = true;
      }
    }
  }
}

/// Picks a spawn point near the center of [region].
///
/// Sorts region cells by distance to the region's centroid and returns the
/// closest one.
Point<int> findSpawnPoint(Grid grid, Set<Point<int>> region) {
  if (region.isEmpty) return const Point(25, 25);

  // Compute centroid.
  var cx = 0.0;
  var cy = 0.0;
  for (final pt in region) {
    cx += pt.x;
    cy += pt.y;
  }
  cx /= region.length;
  cy /= region.length;

  // Find the region cell closest to the centroid.
  Point<int>? best;
  var bestDist = double.infinity;
  for (final pt in region) {
    final dist = (pt.x - cx) * (pt.x - cx) + (pt.y - cy) * (pt.y - cy);
    if (dist < bestDist) {
      bestDist = dist;
      best = pt;
    }
  }
  return best ?? const Point(25, 25);
}

/// Builds floor and object tile layers from a boolean [grid].
///
/// Open cells get a floor tile at [floorTileIndex], wall cells get a wall tile
/// at [wallTileIndex]. Both reference the [tilesetId] tileset.
({TileLayerData floor, TileLayerData objects}) buildTileLayers(
  Grid grid, {
  int floorTileIndex = 83,
  int wallTileIndex = 69,
  String tilesetId = 'room_builder_office',
}) {
  final floor = TileLayerData();
  final objects = TileLayerData();
  final floorRef = TileRef(tilesetId: tilesetId, tileIndex: floorTileIndex);
  final wallRef = TileRef(tilesetId: tilesetId, tileIndex: wallTileIndex);

  for (var y = 0; y < grid.length; y++) {
    final row = grid[y];
    for (var x = 0; x < row.length; x++) {
      if (row[x]) {
        objects.setTile(x, y, wallRef);
      } else {
        floor.setTile(x, y, floorRef);
      }
    }
  }

  return (floor: floor, objects: objects);
}

/// Converts a boolean [grid] to a list of barrier coordinates.
///
/// Every cell where `grid[y][x] == true` becomes a `Point(x, y)` in the
/// returned list.
List<Point<int>> gridToBarriers(Grid grid) {
  final barriers = <Point<int>>[];
  for (var y = 0; y < grid.length; y++) {
    final row = grid[y];
    for (var x = 0; x < row.length; x++) {
      if (row[x]) barriers.add(Point(x, y));
    }
  }
  return barriers;
}
