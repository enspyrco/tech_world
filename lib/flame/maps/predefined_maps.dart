import 'dart:math';

import 'package:logging/logging.dart';

import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';

import 'door_data.dart';
import 'game_map.dart';
import 'gray_stone_room_data.dart';
import 'map_parser.dart';
import 'terminal_mode.dart';

final _log = Logger('PredefinedMaps');

/// Open Arena - no barriers, free movement everywhere.
const openArena = GameMap(
  id: 'open_arena',
  name: 'Open Arena',
  barriers: [],
  spawnPoint: Point(25, 25),
);

/// Imagination Center — beige floor from `room_builder_office`.
///
/// Barriers and wall tiles are generated at runtime from Firestore data.
final lRoom = buildGrayStoneRoom();

/// Four Corners - open map, barriers come from painted tiles.
const fourCorners = GameMap(
  id: 'four_corners',
  name: 'Four Corners',
  barriers: [],
  spawnPoint: Point(25, 25),
);

/// Simple Maze - barriers come from painted tiles.
const simpleMaze = GameMap(
  id: 'simple_maze',
  name: 'Simple Maze',
  barriers: [],
  spawnPoint: Point(8, 8),
);

// ---------------------------------------------------------------------------
// ASCII art maps - spawn and terminal placement only (no barriers).
//
// Legend: . = open, S = spawn, T = terminal
// Each map is a 50x50 grid (gridSize from constants.dart).
// ---------------------------------------------------------------------------

/// The Library - a quiet study space with terminal stations at study desks.
/// Barriers come from painted tiles; ASCII defines only spawn and terminals.
final theLibrary = parseAsciiMap(
  id: 'the_library',
  name: 'The Library',
  ascii: _theLibraryAscii,
);

/// The Workshop - a maker space with open collaboration areas and terminals.
/// Barriers come from painted tiles; ASCII defines only spawn and terminals.
final theWorkshop = parseAsciiMap(
  id: 'the_workshop',
  name: 'The Workshop',
  ascii: _theWorkshopAscii,
);

/// The Wizard's Tower — a prompt spell map with gated progression.
///
/// Four chambers stacked vertically inside a single tower:
///   Antechamber (bottom) → Great Hall → Upper Study → Sanctum (top)
///
/// Each internal wall has a single door. Solve the room's terminals to
/// unlock the door and ascend. Terminals are ordered so challenge difficulty
/// increases from bottom (Beginner) to top (Advanced).
///
/// 6 terminals across 2 spell schools (Evocation + Divination), 3 doors.
final wizardsTower = GameMap(
  id: 'wizards_tower',
  name: "The Wizard's Tower",
  barriers: _wizardsTowerBarriers(),
  spawnPoint: const Point(24, 42),
  tilesetIds: const ['room_builder_office', 'ext_terrains'],
  floorLayer: _wizardsTowerFloor(),
  terminals: const [
    // Order determines challenge assignment via allPromptChallenges[index].
    Point(24, 41), // 0 → evocation_fizzbuzz    (Beginner)  — Antechamber
    Point(20, 31), // 1 → evocation_countdown   (Beginner)  — Great Hall left
    Point(20, 21), // 2 → evocation_diamond     (Intermediate) — Upper Study left
    Point(29, 31), // 3 → divination_color      (Beginner)  — Great Hall right
    Point(29, 21), // 4 → divination_extract    (Intermediate) — Upper Study right
    Point(24, 11), // 5 → divination_pattern    (Advanced)  — Sanctum
  ],
  doors: [
    // D0: Exit the Antechamber — prove you can instruct precisely.
    DoorData(
      position: const Point(24, 36),
      requiredChallengeIds: ['evocation_fizzbuzz'],
    ),
    // D1: Exit the Great Hall — master basics of both schools.
    DoorData(
      position: const Point(24, 25),
      requiredChallengeIds: ['evocation_countdown', 'divination_color'],
    ),
    // D2: Enter the Sanctum — intermediate mastery required.
    DoorData(
      position: const Point(24, 15),
      requiredChallengeIds: ['evocation_diamond', 'divination_extract'],
    ),
  ],
  walls: _wizardsTowerWalls(),
  terminalMode: TerminalMode.prompt,
);

/// All available maps.
final allMaps = [
  openArena,
  lRoom,
  fourCorners,
  simpleMaze,
  theLibrary,
  theWorkshop,
  wizardsTower,
];

/// Default map to use when none is specified.
final defaultMap = lRoom;

/// O(1) lookup of predefined maps by ID.
final Map<String, GameMap> _predefinedMapLookup = {
  for (final m in allMaps) m.id: m,
};

/// Fill in missing visual layers from a predefined map, if one exists.
///
/// When a [GameMap] is loaded from Firestore, it may predate the addition
/// of tileset-based rendering. This finds the matching predefined map and
/// merges in its visual layers (floor, object, tilesetIds) without overriding
/// any structural data (barriers, spawn, terminals) or any visual data the
/// Firestore version already has.
///
/// Matching works two ways:
/// 1. By map ID (for predefined maps used directly).
/// 2. By structural fingerprint — Firestore rooms get the document ID as
///    their map ID, so the original predefined ID is lost. We match by
///    comparing the barrier set, which is a unique structural signature.
///
/// Returns [map] unchanged if there is no predefined match or nothing to fill.
GameMap applyPredefinedVisualFallback(GameMap map) {
  // Already has ALL visual layers — nothing to fill.
  if (map.floorLayer != null && map.objectLayer != null) {
    _log.fine('Visual fallback skipped: "${map.name}" already has all visual layers');
    return map;
  }

  _log.info('Visual fallback: "${map.name}" (id=${map.id}), '
      'floorLayer=${map.floorLayer != null}, objectLayer=${map.objectLayer != null}');

  final predefined = _findPredefinedMatch(map);
  if (predefined == null) return map;

  // Merge each missing layer independently. A Firestore map might have a
  // floor layer from before wall tiles existed but no object layer — we
  // still want to fill in the wall object layer from the predefined match.
  final needsFloor = map.floorLayer == null && predefined.floorLayer != null;
  final needsObjects =
      map.objectLayer == null && predefined.objectLayer != null;
  final needsTilesetIds =
      predefined.tilesetIds.isNotEmpty &&
      !predefined.tilesetIds.every(map.tilesetIds.contains);
  if (!needsFloor && !needsObjects && !needsTilesetIds) {
    return map;
  }

  // Merge tileset IDs from both sources (deduped, order-preserving).
  final mergedTilesetIds = {...map.tilesetIds, ...predefined.tilesetIds}.toList();

  return GameMap(
    id: map.id,
    name: map.name,
    barriers: map.barriers,
    spawnPoint: map.spawnPoint,
    terminals: map.terminals,
    floorLayer: map.floorLayer ?? predefined.floorLayer,
    objectLayer: map.objectLayer ?? predefined.objectLayer,
    objectLayerPriorityOverrides: predefined.objectLayerPriorityOverrides,
    tilesetIds: mergedTilesetIds,
    terrainGrid: map.terrainGrid ?? predefined.terrainGrid,
    customTilesets: map.customTilesets,
    walls: map.walls,
  );
}

/// Find a predefined map matching [map], by ID, name, or barrier structure.
GameMap? _findPredefinedMatch(GameMap map) {
  // Fast path: direct ID match (for predefined maps used without Firestore).
  final byId = _predefinedMapLookup[map.id];
  if (byId != null) {
    _log.info('Visual fallback: matched by ID "${map.id}"');
    return byId;
  }

  // Only consider predefined maps with visual layers worth merging.
  final candidates =
      allMaps.where((m) => m.floorLayer != null || m.objectLayer != null);

  // Match by name — Firestore rooms preserve the map name at the room level.
  for (final predefined in candidates) {
    if (predefined.name == map.name) {
      _log.info('Visual fallback: matched by name "${map.name}"');
      return predefined;
    }
  }

  // Match by barrier fingerprint — structural comparison.
  if (map.barriers.isNotEmpty) {
    final mapBarrierSet = Set<Point<int>>.from(map.barriers);
    for (final predefined in candidates) {
      if (predefined.barriers.length != mapBarrierSet.length) continue;
      if (Set<Point<int>>.from(predefined.barriers)
          .containsAll(mapBarrierSet)) {
        _log.info(
            'Visual fallback: matched by barriers → "${predefined.name}"');
        return predefined;
      }
    }
  }

  _log.fine('Visual fallback: no match for "${map.id}" / "${map.name}"');
  return null;
}

// ---------------------------------------------------------------------------
// ASCII art map data — barriers removed, only spawn (S) and terminals (T).
// ---------------------------------------------------------------------------

//       0         1         2         3         4
//       0123456789012345678901234567890123456789012345678901
const _theLibraryAscii = '''
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
.....T......T......T......T.......................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
.............S....................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................''';

//       0         1         2         3         4
//       0123456789012345678901234567890123456789012345678901
const _theWorkshopAscii = '''
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..............T...................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..............T...................................
..................................................
..................................................
..................................................
..................................................
.........S........................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................
..................................................''';

// ---------------------------------------------------------------------------
// Wizard's Tower barrier geometry
// ---------------------------------------------------------------------------
//
// A single 18-wide (cols 16–33) × 37-tall (rows 8–44) rectangle divided
// into four chambers by internal horizontal walls. Each internal wall has
// a 1-cell doorway at col 24.
//
//   Row  8:  ##################  <- top wall
//   Row  9-14: #              #  <- Sanctum
//   Row 15:  ########.########  <- wall (door D2 at col 24)
//   Row 16-24: #              #  <- Upper Study
//   Row 25:  ########.########  <- wall (door D1 at col 24)
//   Row 26-35: #              #  <- Great Hall
//   Row 36:  ########.########  <- wall (door D0 at col 24)
//   Row 37-43: #              #  <- Antechamber
//   Row 44:  ##################  <- bottom wall
//
List<Point<int>> _wizardsTowerBarriers() {
  final barriers = <Point<int>>[];

  const left = 16;
  const right = 33;
  const top = 8;
  const bottom = 44;
  const doorCol = 24;

  // Top and bottom walls (full width).
  for (var x = left; x <= right; x++) {
    barriers.add(Point(x, top));
    barriers.add(Point(x, bottom));
  }

  // Left and right walls (excluding top/bottom rows already placed).
  for (var y = top + 1; y < bottom; y++) {
    barriers.add(Point(left, y));
    barriers.add(Point(right, y));
  }

  // Internal horizontal walls with doorway gap at doorCol.
  for (final row in [15, 25, 36]) {
    for (var x = left + 1; x < right; x++) {
      if (x != doorCol) {
        barriers.add(Point(x, row));
      }
    }
  }

  return barriers;
}

/// Assign a wall style to each barrier, color-coded by chamber.
///
///   Sanctum (rows 8–15):       purple      — the most magical
///   Upper Study (rows 16–25):  burgundy    — intermediate, rich
///   Great Hall (rows 26–36):   deep_teal   — beginner, welcoming
///   Antechamber (rows 37–44):  charcoal    — entry, stone
Map<Point<int>, String> _wizardsTowerWalls() {
  return {
    for (final b in _wizardsTowerBarriers())
      b: _chamberStyle(b.y),
  };
}

String _chamberStyle(int y) {
  if (y <= 15) return 'purple';
  if (y <= 25) return 'burgundy';
  if (y <= 36) return 'deep_teal';
  return 'charcoal';
}

/// Build the floor layer for the Wizard's Tower.
///
/// Fills the interior of each chamber (and doorway gaps) with floor tiles
/// from the `room_builder_office` tileset. Different tiles per chamber
/// give visual variety matching the wall color progression.
TileLayerData _wizardsTowerFloor() {
  const tilesetId = 'room_builder_office';
  // Floor tile indices from room_builder_office (rows 5+, 16 columns):
  //   149 = warm beige brick (row 9, col 5)  — Antechamber
  //   148 = slightly darker variant           — Great Hall
  //   146 = gray stone                        — Upper Study
  //   144 = dark stone                        — Sanctum
  final layer = TileLayerData();
  final barrierSet = {
    for (final b in _wizardsTowerBarriers()) (b.x, b.y),
  };

  // Grass tile from ext_terrains — row 7, col 22 (index 246).
  const grassRef = TileRef(tilesetId: 'ext_terrains', tileIndex: 246);

  // Fill the entire grid with grass first.
  for (var y = 0; y < 50; y++) {
    for (var x = 0; x < 50; x++) {
      layer.setTile(x, y, grassRef);
    }
  }

  // Overwrite interior cells with chamber-specific floor tiles.
  for (var y = 9; y <= 43; y++) {
    for (var x = 17; x <= 32; x++) {
      if (barrierSet.contains((x, y))) continue;
      layer.setTile(x, y, const TileRef(tilesetId: tilesetId, tileIndex: 149));
    }
  }

  // Also fill doorway gap cells.
  for (final row in [15, 25, 36]) {
    layer.setTile(24, row, const TileRef(tilesetId: tilesetId, tileIndex: 149));
  }

  return layer;
}
