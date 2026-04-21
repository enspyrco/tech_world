import 'dart:math';

import 'package:collection/collection.dart';
import 'package:tech_world/flame/maps/door_data.dart';
import 'package:tech_world/flame/maps/terminal_mode.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tileset.dart';
import 'package:tech_world/map_editor/terrain_grid.dart';

/// A game map definition containing barrier layout and spawn configuration.
///
/// Maps define the walkable/non-walkable areas of the game world.
/// Barriers are specified in mini-grid coordinates (0 to gridSize-1).
///
/// Maps can optionally include tileset-based rendering via [floorLayer] and
/// [objectLayer].
class GameMap {
  const GameMap({
    required this.id,
    required this.name,
    required this.barriers,
    this.spawnPoint = const Point(25, 25),
    this.terminals = const [],
    this.floorLayer,
    this.objectLayer,
    this.objectLayerPriorityOverrides,
    this.tilesetIds = const [],
    this.terrainGrid,
    this.customTilesets = const [],
    this.walls = const {},
    this.doors = const [],
    this.terminalMode = TerminalMode.code,
  });

  /// Unique identifier for this map.
  final String id;

  /// Display name shown to players.
  final String name;

  /// List of barrier positions in mini-grid coordinates.
  /// Players cannot walk through these cells.
  final List<Point<int>> barriers;

  /// Default spawn point for players in mini-grid coordinates.
  final Point<int> spawnPoint;

  /// Positions of coding terminal stations in mini-grid coordinates.
  final List<Point<int>> terminals;

  /// Optional floor tile layer — rendered below everything as a cached Picture.
  final TileLayerData? floorLayer;

  /// Optional object tile layer — rendered with y-sorted priority for depth.
  final TileLayerData? objectLayer;

  /// Priority overrides for specific object layer tiles.
  ///
  /// Maps `(x, y)` grid positions to a priority value that replaces the
  /// default `y` priority. Used for wall cap tiles that should sort with the
  /// barrier row below them (e.g. a cap at y=6 gets priority 7 to match
  /// the wall face). Only relevant for predefined maps with known geometry.
  final Map<(int, int), int>? objectLayerPriorityOverrides;

  /// IDs of tilesets used by this map. Ensures they're loaded before rendering.
  final List<String> tilesetIds;

  /// Optional terrain grid for editor round-trips.
  ///
  /// Tracks which terrain type each cell belongs to, enabling the editor to
  /// re-evaluate bitmask tiles when loading a saved map. Not needed at runtime.
  final TerrainGrid? terrainGrid;

  /// Custom tilesets used by this map that are not predefined in assets.
  ///
  /// Their images are stored in Firebase Storage and downloaded on demand.
  /// Metadata is persisted via [TileMapFormat] so other clients know which
  /// tilesets to fetch.
  final List<Tileset> customTilesets;

  /// Wall positions mapped to style IDs (e.g. `"gray_brick"`).
  ///
  /// Every wall is also a barrier (blocks movement), but not every barrier
  /// is a wall. Only wall positions get face + cap tile art at runtime.
  final Map<Point<int>, String> walls;

  /// Doors placed on the map.
  ///
  /// Each door is a barrier when locked, passable when unlocked. Doors can
  /// require specific challenges to be completed before they unlock.
  final List<DoorData> doors;

  /// What type of interaction terminals provide in this map.
  ///
  /// Defaults to [TerminalMode.code] (coding challenges). Maps can override
  /// this to [TerminalMode.prompt] for prompt spell challenges.
  final TerminalMode terminalMode;

  /// Whether this map uses tileset-based rendering.
  bool get usesTilesets =>
      tilesetIds.isNotEmpty ||
      walls.isNotEmpty ||
      (floorLayer != null && !floorLayer!.isEmpty) ||
      (objectLayer != null && !objectLayer!.isEmpty);

  static const _listEquality = ListEquality<Point<int>>();
  static const _stringListEquality = ListEquality<String>();
  static const _tilesetListEquality = ListEquality<Tileset>();
  static const _wallsEquality = MapEquality<Point<int>, String>();
  static const _doorListEquality = ListEquality<DoorData>();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GameMap &&
          id == other.id &&
          name == other.name &&
          spawnPoint == other.spawnPoint &&
          _listEquality.equals(barriers, other.barriers) &&
          _listEquality.equals(terminals, other.terminals) &&
          _stringListEquality.equals(tilesetIds, other.tilesetIds) &&
          floorLayer == other.floorLayer &&
          objectLayer == other.objectLayer &&
          terrainGrid == other.terrainGrid &&
          _tilesetListEquality.equals(customTilesets, other.customTilesets) &&
          _wallsEquality.equals(walls, other.walls) &&
          _doorListEquality.equals(doors, other.doors) &&
          terminalMode == other.terminalMode;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        spawnPoint,
        _listEquality.hash(barriers),
        _listEquality.hash(terminals),
        _stringListEquality.hash(tilesetIds),
        floorLayer,
        objectLayer,
        terrainGrid,
        _tilesetListEquality.hash(customTilesets),
        _wallsEquality.hash(walls),
        _doorListEquality.hash(doors),
        terminalMode,
      );
}
