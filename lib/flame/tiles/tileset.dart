import 'package:flame/sprite.dart';
import 'package:tech_world/map_editor/map_editor_state.dart' show ActiveLayer;

/// Metadata describing a tileset sprite sheet.
///
/// Each tileset is a grid of [tileSize]x[tileSize] pixel tiles arranged
/// in rows and columns within a single PNG image.
class Tileset {
  const Tileset({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.tileSize,
    required this.columns,
    required this.rows,
    this.barrierTileIndices = const {},
    this.availableLayers = const {ActiveLayer.floor, ActiveLayer.objects},
  });

  /// Unique identifier used in [TileRef.tilesetId].
  final String id;

  /// Human-readable display name.
  final String name;

  /// Path to the tileset image relative to `assets/images/`.
  final String imagePath;

  /// Size of each tile in pixels (square).
  final int tileSize;

  /// Number of tile columns in the sprite sheet.
  final int columns;

  /// Number of tile rows in the sprite sheet.
  final int rows;

  /// Tile indices within this tileset that represent solid/impassable objects.
  ///
  /// When a tile with one of these indices is painted on a visual layer, the
  /// map editor can automatically create a barrier on the structure grid.
  /// Defaults to empty (no tiles tagged).
  final Set<int> barrierTileIndices;

  /// Which editor layers this tileset should appear in.
  ///
  /// Defaults to both [ActiveLayer.floor] and [ActiveLayer.objects].
  /// Floor-only tilesets (e.g. terrains) are hidden from the Objects tab,
  /// and object-only tilesets (e.g. furniture) are hidden from the Floor tab.
  final Set<ActiveLayer> availableLayers;

  /// Whether [tileIndex] represents a solid, impassable tile.
  bool isTileBarrier(int tileIndex) => barrierTileIndices.contains(tileIndex);

  /// Total number of tiles in the sheet.
  int get tileCount => columns * rows;
}

/// A [Tileset] paired with its loaded [SpriteSheet], ready for rendering.
class LoadedTileset {
  const LoadedTileset({
    required this.tileset,
    required this.spriteSheet,
  });

  final Tileset tileset;
  final SpriteSheet spriteSheet;
}
