import 'dart:math';

import 'package:logging/logging.dart';

import 'game_map.dart';
import 'l_room_tile_data.dart';
import 'map_parser.dart';

final _log = Logger('PredefinedMaps');

/// Open Arena - no barriers, free movement everywhere.
const openArena = GameMap(
  id: 'open_arena',
  name: 'Open Arena',
  barriers: [],
  spawnPoint: Point(25, 25),
);

/// The L-Room - original map with tile-based offline fallback.
///
/// Visual content comes from the `single_room` tileset. Barriers define the
/// L-shaped wall layout for offline play.
final lRoom = GameMap(
  id: 'l_room',
  name: 'The L-Room',
  barriers: const [
    // Vertical wall at x=4 (gap at y=17 for door)
    Point(4, 7), Point(4, 8), Point(4, 9), Point(4, 10), Point(4, 11),
    Point(4, 12), Point(4, 13), Point(4, 14), Point(4, 15), Point(4, 16),
    Point(4, 18), Point(4, 19), Point(4, 20), Point(4, 21), Point(4, 22),
    Point(4, 23), Point(4, 24), Point(4, 25), Point(4, 26), Point(4, 27),
    Point(4, 28), Point(4, 29),
    // Horizontal wall at y=7
    Point(5, 7), Point(6, 7), Point(7, 7), Point(8, 7), Point(9, 7),
    Point(10, 7), Point(11, 7), Point(12, 7), Point(13, 7), Point(14, 7),
    Point(15, 7), Point(16, 7), Point(17, 7),
  ],
  spawnPoint: const Point(10, 15),
  terminals: const [Point(8, 12), Point(14, 12)],
  floorLayer: buildLRoomFloorLayer(),
  tilesetIds: const ['single_room', 'room_builder_office'],
  wallDefId: 'gray_brick',
);

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

/// All available maps.
final allMaps = [
  openArena,
  lRoom,
  fourCorners,
  simpleMaze,
  theLibrary,
  theWorkshop,
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
  final hasVisualLayers = map.floorLayer != null || map.objectLayer != null;

  // ignore: avoid_print
  print('FALLBACK_DIAG: "${map.name}" hasVisualLayers=$hasVisualLayers, '
      'wallDefId=${map.wallDefId}, tilesetIds=${map.tilesetIds}');

  // Even when visual layers exist, we may need to fill in metadata like
  // wallDefId from the predefined match (e.g. Firestore rooms saved before
  // wallDefId was added).
  if (hasVisualLayers && map.wallDefId != null) {
    // ignore: avoid_print
    print('FALLBACK_DIAG: skipped — already has visual layers and wallDefId');
    return map;
  }

  final predefined = _findPredefinedMatch(map);
  if (predefined == null) {
    if (!hasVisualLayers) {
      _log.info('Visual fallback: "${map.name}" has no visual layers and '
          'no predefined match');
    }
    return map;
  }

  // Fill in wallDefId from predefined even when visual layers already exist.
  // ignore: avoid_print
  print('FALLBACK_DIAG: predefined match found: "${predefined.name}", '
      'predefined.wallDefId=${predefined.wallDefId}');
  if (hasVisualLayers) {
    if (predefined.wallDefId != null && map.wallDefId == null) {
      // ignore: avoid_print
      print('FALLBACK_DIAG: filling wallDefId="${predefined.wallDefId}" '
          'and merging tilesetIds=${[...map.tilesetIds, ...predefined.tilesetIds]}');
      return GameMap(
        id: map.id,
        name: map.name,
        barriers: map.barriers,
        spawnPoint: map.spawnPoint,
        terminals: map.terminals,
        floorLayer: map.floorLayer,
        objectLayer: map.objectLayer,
        objectLayerPriorityOverrides: map.objectLayerPriorityOverrides,
        tilesetIds: {...map.tilesetIds, ...predefined.tilesetIds}.toList(),
        terrainGrid: map.terrainGrid,
        customTilesets: map.customTilesets,
        wallDefId: predefined.wallDefId,
      );
    }
    return map;
  }

  _log.info('Visual fallback: "${map.name}" (id=${map.id}) has no visual '
      'layers, applying predefined match...');

  final needsFloor = predefined.floorLayer != null;
  final needsObjects = predefined.objectLayer != null;
  final needsTilesetIds =
      map.tilesetIds.isEmpty && predefined.tilesetIds.isNotEmpty;

  if (!needsFloor && !needsObjects && !needsTilesetIds) return map;

  return GameMap(
    id: map.id,
    name: map.name,
    barriers: map.barriers,
    spawnPoint: map.spawnPoint,
    terminals: map.terminals,
    floorLayer: predefined.floorLayer,
    objectLayer: predefined.objectLayer,
    objectLayerPriorityOverrides: predefined.objectLayerPriorityOverrides,
    tilesetIds: map.tilesetIds.isEmpty ? predefined.tilesetIds : map.tilesetIds,
    terrainGrid: map.terrainGrid ?? predefined.terrainGrid,
    customTilesets: map.customTilesets,
    wallDefId: map.wallDefId ?? predefined.wallDefId,
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
