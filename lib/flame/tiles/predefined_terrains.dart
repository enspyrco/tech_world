import 'package:tech_world/flame/tiles/terrain_def.dart';

/// Predefined terrain definitions for auto-terrain brushing.
///
/// Each terrain defines a mapping from the 47 simplified bitmask values to
/// tile indices in a specific tileset. The tiles were pre-rendered from
/// RPG Maker A2-format base tiles using quarter-tile compositing.

/// Helper to compute a tile index in a 32-column tileset.
int _idx(int row, int col) => row * 32 + col;

/// Water terrain definition for the `ext_terrains` tileset.
///
/// Pre-rendered from base tiles at rows 35–37, cols 0–1 of `ext_terrains.png`.
/// Composited tiles placed at rows 60–67, cols 0–5.
final waterTerrain = TerrainDef(
  id: 'water',
  name: 'Water',
  tilesetId: 'ext_terrains',
  previewTileIndex: _idx(67, 4), // bitmask 255: fully surrounded water
  bitmaskToTileIndex: {
    // 0 edges (isolated)
    0: _idx(60, 0),

    // 1 edge
    1: _idx(60, 1), // N only
    4: _idx(60, 2), // E only
    16: _idx(60, 5), // S only
    64: _idx(62, 1), // W only

    // 2 adjacent edges
    5: _idx(60, 3), // N+E
    7: _idx(60, 4), // N+E+NE
    20: _idx(61, 1), // E+S
    28: _idx(61, 4), // E+S+SE
    80: _idx(63, 0), // S+W
    112: _idx(64, 2), // S+W+SW
    65: _idx(62, 2), // N+W
    193: _idx(65, 4), // N+W+NW

    // 2 opposite edges
    17: _idx(61, 0), // N+S
    68: _idx(62, 3), // E+W

    // 3 edges
    21: _idx(61, 2), // N+E+S (no corners)
    23: _idx(61, 3), // N+E+S+NE
    29: _idx(61, 5), // N+E+S+SE
    31: _idx(62, 0), // N+E+S+NE+SE
    69: _idx(62, 4), // N+E+W (no corners)
    71: _idx(62, 5), // N+E+W+NE
    197: _idx(65, 5), // N+E+W+NW
    199: _idx(66, 0), // N+E+W+NE+NW
    84: _idx(63, 2), // E+S+W (no corners)
    92: _idx(63, 5), // E+S+W+SE
    116: _idx(64, 4), // E+S+W+SW
    124: _idx(65, 1), // E+S+W+SE+SW
    81: _idx(63, 1), // N+S+W (no corners)
    113: _idx(64, 3), // N+S+W+SW
    209: _idx(66, 1), // N+S+W+NW
    241: _idx(67, 0), // N+S+W+NW+SW

    // 4 edges (all edge neighbors present, corners vary)
    85: _idx(63, 3), // N+E+S+W (no corners)
    87: _idx(63, 4), // +NE
    93: _idx(64, 0), // +SE
    95: _idx(64, 1), // +NE+SE
    117: _idx(64, 5), // +SW
    119: _idx(65, 0), // +NE+SW
    125: _idx(65, 2), // +SE+SW
    127: _idx(65, 3), // +NE+SE+SW
    213: _idx(66, 2), // +NW
    215: _idx(66, 3), // +NE+NW
    221: _idx(66, 4), // +SE+NW
    223: _idx(66, 5), // +NE+SE+NW
    245: _idx(67, 1), // +SW+NW
    247: _idx(67, 2), // +NE+SW+NW
    253: _idx(67, 3), // +SE+SW+NW
    255: _idx(67, 4), // all (fully surrounded)
  },
);

/// All predefined terrain definitions.
final List<TerrainDef> allTerrains = [waterTerrain];

/// Look up a terrain definition by its [id].
///
/// Returns `null` if no terrain with that ID exists.
TerrainDef? lookupTerrain(String id) {
  for (final terrain in allTerrains) {
    if (terrain.id == id) return terrain;
  }
  return null;
}
