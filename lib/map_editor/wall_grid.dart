import 'package:tech_world/flame/shared/constants.dart';

/// A [gridSize]x[gridSize] grid tracking which wall definition each cell uses.
///
/// Parallel to [TerrainGrid]. The wall grid records the *semantic* wall type
/// (e.g. `'gray_brick'`) while the object tile layer holds the *visual* tile
/// references. At runtime, the tile layer is self-sufficient — the wall grid
/// is only needed for editor round-trips (re-evaluating bitmask tiles when
/// loading a saved map).
class WallGrid {
  /// Create an empty wall grid (all cells null).
  WallGrid()
      : _grid = List.generate(
          gridSize,
          (_) => List<String?>.filled(gridSize, null),
        );

  final List<List<String?>> _grid;

  /// Get the wall def ID at ([x], [y]), or null if empty or out of bounds.
  String? wallAt(int x, int y) {
    if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) return null;
    return _grid[y][x];
  }

  /// Set (or clear) the wall def at ([x], [y]).
  void setWall(int x, int y, String? wallDefId) {
    if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) return;
    _grid[y][x] = wallDefId;
  }

  /// Whether the cell at ([x], [y]) has any wall.
  bool isWallAt(int x, int y) {
    return wallAt(x, y) != null;
  }

  /// Whether the cell at ([x], [y]) has the given [wallDefId].
  bool isWallOfTypeAt(int x, int y, String wallDefId) {
    return wallAt(x, y) == wallDefId;
  }

  /// Whether every cell is null.
  bool get isEmpty {
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        if (_grid[y][x] != null) return false;
      }
    }
    return true;
  }

  /// Clear all cells to null.
  void clear() {
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        _grid[y][x] = null;
      }
    }
  }

  /// Create a deep copy of this grid.
  WallGrid copy() {
    final clone = WallGrid();
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        clone._grid[y][x] = _grid[y][x];
      }
    }
    return clone;
  }

  /// Serialize to a sparse JSON list (only non-null cells).
  ///
  /// Format: `[{x, y, wall}, ...]`
  List<Map<String, dynamic>> toJson() {
    final entries = <Map<String, dynamic>>[];
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final wall = _grid[y][x];
        if (wall != null) {
          entries.add({'x': x, 'y': y, 'wall': wall});
        }
      }
    }
    return entries;
  }

  /// Deserialize from a sparse JSON list.
  factory WallGrid.fromJson(List<dynamic> json) {
    final grid = WallGrid();
    for (final entry in json) {
      final map = entry as Map<String, dynamic>;
      final x = map['x'] as int;
      final y = map['y'] as int;
      final wall = map['wall'] as String;
      grid.setWall(x, y, wall);
    }
    return grid;
  }
}
