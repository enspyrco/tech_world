/// Wall construction definition for auto-placing wall face and cap tiles.
///
/// Maps barrier neighbor configurations to tile indices for both wall
/// **faces** (at barrier position y) and wall **caps** (at y-1 above
/// north-facing barriers). Uses a 4-bit cardinal bitmask:
///
/// ```
///        N=1
///  W=8 | cell | E=2
///        S=4
/// ```
///
/// This is simpler than the 8-bit terrain bitmask — walls only need
/// cardinal neighbors, not diagonals.
library;

/// Direction bit constants for the 4-bit wall bitmask.
abstract final class WallBitmask {
  static const int n = 1; // barrier at (x, y-1)
  static const int e = 2; // barrier at (x+1, y)
  static const int s = 4; // barrier at (x, y+1)
  static const int w = 8; // barrier at (x-1, y)

  /// Cardinal neighbor offsets indexed by bit position.
  static const List<(int, int)> offsets = [
    (0, -1), // N (bit 0)
    (1, 0), // E (bit 1)
    (0, 1), // S (bit 2)
    (-1, 0), // W (bit 3)
  ];
}

/// Compute the 4-bit cardinal bitmask for a barrier at ([cx], [cy]).
///
/// Each bit indicates whether a barrier exists in that cardinal direction.
/// Returns a value 0–15.
int computeWallBitmask(int cx, int cy, Set<(int, int)> barriers) {
  var mask = 0;
  for (var i = 0; i < 4; i++) {
    final (dx, dy) = WallBitmask.offsets[i];
    if (barriers.contains((cx + dx, cy + dy))) {
      mask |= 1 << i;
    }
  }
  return mask;
}

/// Definition of a wall style for auto-placing construction tiles.
///
/// Parallel to [TerrainDef] but for wall construction. Maps 4-bit cardinal
/// bitmasks to tile indices in a construction tileset, for both wall faces
/// and wall caps.
class WallDef {
  /// Creates a wall definition.
  ///
  /// [id] is a unique slug (e.g. `'gray_brick'`). [tilesetId] identifies
  /// which tileset contains the wall tiles. [faceBitmaskToTileIndex] maps
  /// bitmasks to face tiles at barrier positions. [capBitmaskToTileIndex]
  /// maps bitmasks to cap tiles at y-1 above north-facing barriers.
  const WallDef({
    required this.id,
    required this.name,
    required this.tilesetId,
    required this.faceBitmaskToTileIndex,
    required this.capBitmaskToTileIndex,
  });

  /// Unique identifier for this wall style (e.g. `'gray_brick'`).
  final String id;

  /// Human-readable display name (e.g. `'Gray Brick'`).
  final String name;

  /// The tileset containing this wall style's tiles.
  final String tilesetId;

  /// Maps 4-bit cardinal bitmask → tile index for wall faces.
  ///
  /// These tiles render at barrier positions (y) in the object layer.
  final Map<int, int> faceBitmaskToTileIndex;

  /// Maps 4-bit cardinal bitmask → tile index for wall caps.
  ///
  /// These tiles render at y-1 above north-facing barriers. The S bit is
  /// always set (there's always a barrier below — that's what makes it a
  /// cap), so effectively only 8 configurations are needed.
  final Map<int, int> capBitmaskToTileIndex;

  /// Look up the face tile index for a barrier with the given neighbor mask.
  int? faceForBitmask(int bitmask) => faceBitmaskToTileIndex[bitmask];

  /// Look up the cap tile index for a wall-top with the given neighbor mask.
  int? capForBitmask(int bitmask) => capBitmaskToTileIndex[bitmask];
}
