import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/map_editor/automap_rule.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

/// Tileset ID for the room builder office sprite sheet (16 columns).
const _tilesetId = 'room_builder_office';

/// All predefined automap rules.
const List<AutomapRule> allAutomapRules = [
  wallShadowRule,
  wallTopTrimRule,
];

/// Wall Shadows — places a shadow transition tile below every wall.
///
/// Condition: current cell is `open` AND cell above is a `barrier`.
/// Output: shadow tile on the object layer.
///
/// Tile index 80 = row 5, col 0 — light stone with top band, creates a
/// shadow/transition effect below wall tiles.
const wallShadowRule = AutomapRule(
  id: 'wall_shadow',
  name: 'Wall Shadows',
  conditions: [
    AutomapCondition(dx: 0, dy: 0, structureType: TileType.open),
    AutomapCondition(dx: 0, dy: -1, structureType: TileType.barrier),
  ],
  output: AutomapOutput(
    targetLayer: 'object',
    tile: TileRef(tilesetId: _tilesetId, tileIndex: 80),
  ),
  priority: 10,
);

/// Wall Top Trim — places a decorative cap on the top edge of walls.
///
/// Condition: current cell is a `barrier` AND cell above is `open`.
/// Output: decorative cap tile on the object layer.
///
/// Tile index 53 = row 3, col 5 — wall-top piece that sits above the
/// default wall fill tile (index 69 at row 4, col 5).
const wallTopTrimRule = AutomapRule(
  id: 'wall_top_trim',
  name: 'Wall Top Trim',
  conditions: [
    AutomapCondition(dx: 0, dy: 0, structureType: TileType.barrier),
    AutomapCondition(dx: 0, dy: -1, structureType: TileType.open),
  ],
  output: AutomapOutput(
    targetLayer: 'object',
    tile: TileRef(tilesetId: _tilesetId, tileIndex: 53),
  ),
  priority: 5,
);
