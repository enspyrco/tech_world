import 'package:tech_world/flame/tiles/tileset.dart';

/// Test tileset — a 4x4 grid of colored 32x32 squares for development.
///
/// Will be replaced with real LPC-style tilesets once assets are purchased.
const testTileset = Tileset(
  id: 'test',
  name: 'Test Tileset',
  imagePath: 'tilesets/test_tileset.png',
  tileSize: 32,
  columns: 4,
  rows: 4,
);

/// All available tilesets.
///
/// Add purchased LPC tilesets here (Modern Interiors, Modern Office, etc.)
/// once images are available.
const allTilesets = [
  testTileset,
];
