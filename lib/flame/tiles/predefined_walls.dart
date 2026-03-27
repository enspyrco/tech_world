import 'package:tech_world/flame/tiles/wall_def.dart';

/// Gray brick wall style from the `room_builder_office` tileset.
///
/// Tileset layout (16 columns × 14 rows, 32px tiles):
/// - Rows 0–2 (indices 0–47): Wall outline/edge pieces (caps)
/// - Rows 3–4 (indices 48–79): Wall face textures (purple, gray, brown)
/// - Rows 5–13 (indices 80–223): Floor tiles
///
/// **Tile index mapping needs visual verification.** The bitmask structure
/// is correct but specific indices may need adjustment after seeing the
/// result in-game. Use `debugWallTiles: true` on `TileObjectLayerComponent`
/// to display tile indices.
///
/// Bitmask bits: N=1, E=2, S=4, W=8.
// TODO(nick): verify tile indices visually in Chrome.
final grayBrickWall = WallDef(
  id: 'gray_brick',
  name: 'Gray Brick',
  tilesetId: 'room_builder_office',
  // Wall face tiles — rendered at barrier positions.
  // Gray brick faces appear to be in the right portion of rows 3–4.
  // Using row 4 (indices 64–79) for gray variants.
  faceBitmaskToTileIndex: {
    // Isolated wall (no cardinal neighbors).
    0: 64,
    // Single neighbor — end caps.
    WallBitmask.n: 64, // wall continues above only
    WallBitmask.e: 64, // wall continues right only
    WallBitmask.s: 64, // wall continues below only
    WallBitmask.w: 64, // wall continues left only
    // Two neighbors — straight walls and corners.
    WallBitmask.n | WallBitmask.s: 64, // vertical middle
    WallBitmask.e | WallBitmask.w: 64, // horizontal middle
    WallBitmask.n | WallBitmask.e: 64, // corner: wall above + right
    WallBitmask.n | WallBitmask.w: 64, // corner: wall above + left
    WallBitmask.s | WallBitmask.e: 64, // corner: wall below + right
    WallBitmask.s | WallBitmask.w: 64, // corner: wall below + left
    // Three neighbors — T-junctions.
    WallBitmask.n | WallBitmask.e | WallBitmask.w: 64, // T facing south
    WallBitmask.s | WallBitmask.e | WallBitmask.w: 64, // T facing north
    WallBitmask.n | WallBitmask.s | WallBitmask.e: 64, // T facing west
    WallBitmask.n | WallBitmask.s | WallBitmask.w: 64, // T facing east
    // All four neighbors — cross.
    WallBitmask.n | WallBitmask.e | WallBitmask.s | WallBitmask.w: 64,
  },
  // Wall cap tiles — rendered at y-1 above north-facing barriers.
  // S bit is always set (barrier below). Outline pieces from rows 0–2.
  capBitmaskToTileIndex: {
    // Cap with wall below only (isolated top).
    WallBitmask.s: 0,
    // Cap with wall below + right (left end of wall top).
    WallBitmask.s | WallBitmask.e: 0,
    // Cap with wall below + left (right end of wall top).
    WallBitmask.s | WallBitmask.w: 0,
    // Cap with wall below + left + right (middle of wall top).
    WallBitmask.s | WallBitmask.e | WallBitmask.w: 0,
    // Cap with wall below + above (vertical wall, not north-facing — rare).
    WallBitmask.s | WallBitmask.n: 0,
    // Cap with wall in three directions.
    WallBitmask.s | WallBitmask.n | WallBitmask.e: 0,
    WallBitmask.s | WallBitmask.n | WallBitmask.w: 0,
    // Cap surrounded.
    WallBitmask.n | WallBitmask.e | WallBitmask.s | WallBitmask.w: 0,
  },
);

/// Look up a [WallDef] by its [id].
///
/// Returns `null` if no predefined wall definition matches.
WallDef? lookupWallDef(String id) {
  switch (id) {
    case 'gray_brick':
      return grayBrickWall;
    default:
      return null;
  }
}
