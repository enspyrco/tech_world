import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';

/// A [gridSize]x[gridSize] grid of optional tile references.
///
/// Used for both floor and object tile layers. Null cells are empty (no tile).
class TileLayerData {
  /// Create an empty layer (all cells null).
  TileLayerData()
      : _grid = List.generate(
          gridSize,
          (_) => List<TileRef?>.filled(gridSize, null),
        );

  /// Create a layer pre-filled from a flat list in row-major order.
  TileLayerData.fromGrid(List<List<TileRef?>> grid) : _grid = grid;

  final List<List<TileRef?>> _grid;

  /// Get the tile at ([x], [y]), or null if empty or out of bounds.
  TileRef? tileAt(int x, int y) {
    if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) return null;
    return _grid[y][x];
  }

  /// Set (or clear) the tile at ([x], [y]).
  void setTile(int x, int y, TileRef? ref) {
    if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) return;
    _grid[y][x] = ref;
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

  /// Collect all unique tileset IDs referenced in this layer.
  Set<String> get referencedTilesetIds {
    final ids = <String>{};
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final ref = _grid[y][x];
        if (ref != null) ids.add(ref.tilesetId);
      }
    }
    return ids;
  }

  /// Serialize to a sparse JSON list (only non-null tiles).
  ///
  /// Format: `[{x, y, tilesetId, tileIndex}, ...]`
  List<Map<String, dynamic>> toJson() {
    final tiles = <Map<String, dynamic>>[];
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final ref = _grid[y][x];
        if (ref != null) {
          tiles.add({
            'x': x,
            'y': y,
            ...ref.toJson(),
          });
        }
      }
    }
    return tiles;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TileLayerData) return false;
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        if (_grid[y][x] != other._grid[y][x]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = 0;
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        hash = Object.hash(hash, _grid[y][x]);
      }
    }
    return hash;
  }

  /// Deserialize from a sparse JSON list.
  factory TileLayerData.fromJson(List<dynamic> json) {
    final layer = TileLayerData();
    for (final entry in json) {
      final map = entry as Map<String, dynamic>;
      final x = map['x'] as int;
      final y = map['y'] as int;
      layer.setTile(x, y, TileRef.fromJson(map));
    }
    return layer;
  }
}
