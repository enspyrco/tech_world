import 'package:flame/sprite.dart';

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
