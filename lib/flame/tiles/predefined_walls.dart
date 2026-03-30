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
/// Cap tiles use outline pieces from rows 0–2 that have a horizontal
/// line at the bottom (representing the wall top edge).
// TODO(nick): refine cap tile indices after visual verification.
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
  // Cap tiles — top halves of wall segments at y-1 above barriers.
  // Row 3 contains the top halves; row 4 the bottom halves.
  // Gray stone family appears at cols 8-9 (indices 56-57 in row 3).
  // Trying 56 (left edge), 57 (right edge), 56 (fill) for now.
  capBitmaskToTileIndex: {
    WallBitmask.s: 56, // isolated cap
    WallBitmask.s | WallBitmask.e: 56, // left end of cap row
    WallBitmask.s | WallBitmask.w: 57, // right end of cap row
    WallBitmask.s | WallBitmask.e | WallBitmask.w: 56, // cap middle
    WallBitmask.s | WallBitmask.n: 56, // vertical (rare)
    WallBitmask.s | WallBitmask.n | WallBitmask.e: 56,
    WallBitmask.s | WallBitmask.n | WallBitmask.w: 57,
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
