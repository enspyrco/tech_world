import 'package:tech_world/flame/tiles/wall_def.dart';

/// Gray stone wall style from the `room_builder_office` tileset.
///
/// Tileset layout (16 columns × 14 rows, 32px tiles):
/// - Rows 0–2 (indices 0–47): Wall outline/edge pieces (caps)
/// - Rows 3–4 (indices 48–79): Wall face textures (purple, gray, brown)
/// - Rows 5–13 (indices 80–223): Floor tiles
///
/// Bitmask bits: N=1, E=2, S=4, W=8.
///
/// Face tiles use gray stone from row 4 (indices 64–67):
/// - 66: gray stone fill (no border) — wall middle
/// - 64: gray stone with left edge + white band — left end / isolated
/// - 65: gray stone with right edge + white band — right end
///
/// Cap tiles use row 3 gray stone (indices 56–57) — the top halves of
/// 2-tile-tall wall segments. The bitmask is computed at the BARRIER
/// position (not the cap position), so all 16 bitmask values need entries.
// TODO(nick): refine tile indices after visual verification.
final grayBrickWall = WallDef(
  id: 'gray_brick',
  name: 'Gray Stone',
  tilesetId: 'room_builder_office',
  faceBitmaskToTileIndex: {
    // Isolated wall (no cardinal neighbors).
    0: 64,
    // Single neighbor — end caps.
    WallBitmask.n: 66, // wall continues above only
    WallBitmask.e: 64, // wall continues right → left end
    WallBitmask.s: 66, // wall continues below only
    WallBitmask.w: 65, // wall continues left → right end
    // Two neighbors — straight walls and corners.
    WallBitmask.n | WallBitmask.s: 66, // vertical middle
    WallBitmask.e | WallBitmask.w: 66, // horizontal middle
    WallBitmask.n | WallBitmask.e: 64, // corner: N+E
    WallBitmask.n | WallBitmask.w: 65, // corner: N+W
    WallBitmask.s | WallBitmask.e: 64, // corner: S+E
    WallBitmask.s | WallBitmask.w: 65, // corner: S+W
    // Three neighbors — T-junctions.
    WallBitmask.n | WallBitmask.e | WallBitmask.w: 66, // T south
    WallBitmask.s | WallBitmask.e | WallBitmask.w: 66, // T north
    WallBitmask.n | WallBitmask.s | WallBitmask.e: 64, // T west
    WallBitmask.n | WallBitmask.s | WallBitmask.w: 65, // T east
    // All four neighbors — cross.
    WallBitmask.n | WallBitmask.e | WallBitmask.s | WallBitmask.w: 66,
  },
  // Cap tiles at y-1 above north-facing barriers. The bitmask is computed
  // for the BARRIER position, so any of the 16 bitmask values can occur.
  // Horizontal wall barriers have E+W without S; vertical wall tops have
  // S without E/W. All must be covered.
  capBitmaskToTileIndex: {
    // No neighbors (isolated barrier).
    0: 56,
    // Single neighbor.
    WallBitmask.n: 56,
    WallBitmask.e: 56, // wall to right → cap continues right
    WallBitmask.s: 56, // wall below
    WallBitmask.w: 57, // wall to left → cap continues left
    // Two neighbors.
    WallBitmask.n | WallBitmask.s: 56, // vertical middle
    WallBitmask.e | WallBitmask.w: 56, // horizontal middle ← was MISSING
    WallBitmask.n | WallBitmask.e: 56,
    WallBitmask.n | WallBitmask.w: 57,
    WallBitmask.s | WallBitmask.e: 56,
    WallBitmask.s | WallBitmask.w: 57,
    // Three neighbors.
    WallBitmask.n | WallBitmask.e | WallBitmask.w: 56,
    WallBitmask.s | WallBitmask.e | WallBitmask.w: 56,
    WallBitmask.n | WallBitmask.s | WallBitmask.e: 56,
    WallBitmask.n | WallBitmask.s | WallBitmask.w: 57,
    // All four neighbors.
    WallBitmask.n | WallBitmask.e | WallBitmask.s | WallBitmask.w: 56,
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
