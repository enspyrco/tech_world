/// Definition of a terrain type for auto-terrain brushing.
///
/// Maps simplified bitmask values (from [computeBitmask]) to tile indices
/// within a specific tileset. The editor uses this to automatically select
/// the correct edge/corner/center tile based on neighboring cells.
class TerrainDef {
  /// Creates a terrain definition.
  ///
  /// [id] is a unique slug (e.g. `'water'`). [tilesetId] identifies which
  /// tileset contains the terrain tiles. [bitmaskToTileIndex] maps each of
  /// the 47 simplified bitmask values to a tile index in that tileset.
  const TerrainDef({
    required this.id,
    required this.name,
    required this.tilesetId,
    required this.bitmaskToTileIndex,
    this.previewTileIndex,
  });

  /// Unique identifier for this terrain (e.g. `'water'`).
  final String id;

  /// Human-readable display name (e.g. `'Water'`).
  final String name;

  /// The tileset containing this terrain's tiles.
  final String tilesetId;

  /// Maps simplified bitmask values to tile indices in [tilesetId].
  ///
  /// Should have an entry for each of the 47 unique simplified bitmask values
  /// produced by [simplifyBitmask].
  final Map<int, int> bitmaskToTileIndex;

  /// Optional tile index to use as a preview thumbnail in the UI.
  ///
  /// If null, falls back to the tile for bitmask 255 (fully surrounded).
  final int? previewTileIndex;

  /// Look up the tile index for a given simplified bitmask.
  ///
  /// Returns `null` if the bitmask has no mapping.
  int? tileIndexForBitmask(int simplifiedBitmask) {
    return bitmaskToTileIndex[simplifiedBitmask];
  }

  /// The tile index to use for preview/thumbnail display.
  ///
  /// Returns [previewTileIndex] if set, otherwise the tile for bitmask 255
  /// (center tile, fully surrounded), or 0 as a final fallback.
  int get preview => previewTileIndex ?? bitmaskToTileIndex[255] ?? 0;
}
