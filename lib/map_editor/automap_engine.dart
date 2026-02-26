import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/map_editor/automap_rule.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

/// Result of running automap rules across the grid.
class AutomapResult {
  /// Creates a result with the computed tile placements and affected cells.
  const AutomapResult({
    required this.placements,
    required this.affectedCells,
  });

  /// Map from (x, y) to the tile that should be placed.
  final Map<(int, int), TileRef> placements;

  /// Set of all cells that were affected by rules.
  final Set<(int, int)> affectedCells;
}

/// Evaluate automap [rules] across the entire grid.
///
/// This is a pure function — it reads grid state through callbacks and
/// returns the computed placements without modifying any state.
///
/// [structureAt] returns the structure tile type at (x, y).
/// [objectTileAt] returns the object layer tile at (x, y), used for
/// `isEmpty` condition checks.
///
/// Rules are sorted by [AutomapRule.priority] (descending). For each cell,
/// the first matching rule wins.
AutomapResult evaluateRules({
  required List<AutomapRule> rules,
  required TileType Function(int x, int y) structureAt,
  required TileRef? Function(int x, int y) objectTileAt,
}) {
  final placements = <(int, int), TileRef>{};
  final affectedCells = <(int, int)>{};

  // Sort rules by priority descending (higher priority first).
  final sorted = List<AutomapRule>.from(rules)
    ..sort((a, b) => b.priority.compareTo(a.priority));

  for (var y = 0; y < gridSize; y++) {
    for (var x = 0; x < gridSize; x++) {
      for (final rule in sorted) {
        if (_matchesAll(rule, x, y, structureAt, objectTileAt)) {
          placements[(x, y)] = rule.output.tile;
          affectedCells.add((x, y));
          break; // First match wins
        }
      }
    }
  }

  return AutomapResult(placements: placements, affectedCells: affectedCells);
}

bool _matchesAll(
  AutomapRule rule,
  int x,
  int y,
  TileType Function(int x, int y) structureAt,
  TileRef? Function(int x, int y) objectTileAt,
) {
  for (final condition in rule.conditions) {
    final cx = x + condition.dx;
    final cy = y + condition.dy;

    if (condition.structureType != null) {
      if (structureAt(cx, cy) != condition.structureType) return false;
    }

    if (condition.isEmpty != null) {
      final hasObject = objectTileAt(cx, cy) != null;
      if (condition.isEmpty! && hasObject) return false;
      if (!condition.isEmpty! && !hasObject) return false;
    }
  }

  return true;
}
