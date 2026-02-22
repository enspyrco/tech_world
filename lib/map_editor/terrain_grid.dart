import 'package:tech_world/flame/shared/constants.dart';

/// A [gridSize]x[gridSize] grid tracking which terrain type each cell belongs to.
///
/// This is a parallel data structure to [TileLayerData] used during editing.
/// The terrain grid records the *semantic* terrain type (e.g. `'water'`) while
/// the tile layer holds the *visual* tile reference. At runtime, the tile layer
/// is self-sufficient — the terrain grid is only needed for editor round-trips.
class TerrainGrid {
  /// Create an empty terrain grid (all cells null).
  TerrainGrid()
      : _grid = List.generate(
          gridSize,
          (_) => List<String?>.filled(gridSize, null),
        );

  final List<List<String?>> _grid;

  /// Get the terrain ID at ([x], [y]), or null if empty or out of bounds.
  String? terrainAt(int x, int y) {
    if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) return null;
    return _grid[y][x];
  }

  /// Set (or clear) the terrain at ([x], [y]).
  void setTerrain(int x, int y, String? terrainId) {
    if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) return;
    _grid[y][x] = terrainId;
  }

  /// Whether the cell at ([x], [y]) has the given [terrainId].
  bool isTerrainAt(int x, int y, String terrainId) {
    return terrainAt(x, y) == terrainId;
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

  /// Serialize to a sparse JSON list (only non-null cells).
  ///
  /// Format: `[{x, y, terrain}, ...]`
  List<Map<String, dynamic>> toJson() {
    final entries = <Map<String, dynamic>>[];
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final terrain = _grid[y][x];
        if (terrain != null) {
          entries.add({'x': x, 'y': y, 'terrain': terrain});
        }
      }
    }
    return entries;
  }

  /// Deserialize from a sparse JSON list.
  factory TerrainGrid.fromJson(List<dynamic> json) {
    final grid = TerrainGrid();
    for (final entry in json) {
      final map = entry as Map<String, dynamic>;
      final x = map['x'] as int;
      final y = map['y'] as int;
      final terrain = map['terrain'] as String;
      grid.setTerrain(x, y, terrain);
    }
    return grid;
  }
}
