import 'dart:math';

import 'package:collection/collection.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';

/// A game map definition containing barrier layout and spawn configuration.
///
/// Maps define the walkable/non-walkable areas of the game world.
/// Barriers are specified in mini-grid coordinates (0 to gridSize-1).
///
/// Maps can optionally include tileset-based rendering via [floorLayer] and
/// [objectLayer]. When [usesTilesets] is true, the tile layers are rendered
/// instead of a plain background image.
class GameMap {
  const GameMap({
    required this.id,
    required this.name,
    required this.barriers,
    this.spawnPoint = const Point(25, 25),
    this.terminals = const [],
    this.backgroundImage,
    this.floorLayer,
    this.objectLayer,
    this.tilesetIds = const [],
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

  /// Optional background image filename (in assets/images/).
  /// When set, the image is rendered behind barriers with wall occlusion.
  final String? backgroundImage;

  /// Optional floor tile layer — rendered below everything as a cached Picture.
  final TileLayerData? floorLayer;

  /// Optional object tile layer — rendered with y-sorted priority for depth.
  final TileLayerData? objectLayer;

  /// IDs of tilesets used by this map. Ensures they're loaded before rendering.
  final List<String> tilesetIds;

  /// Whether this map uses tileset-based rendering.
  bool get usesTilesets =>
      tilesetIds.isNotEmpty ||
      (floorLayer != null && !floorLayer!.isEmpty) ||
      (objectLayer != null && !objectLayer!.isEmpty);

  static const _listEquality = ListEquality<Point<int>>();
  static const _stringListEquality = ListEquality<String>();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GameMap &&
          id == other.id &&
          name == other.name &&
          spawnPoint == other.spawnPoint &&
          backgroundImage == other.backgroundImage &&
          _listEquality.equals(barriers, other.barriers) &&
          _listEquality.equals(terminals, other.terminals) &&
          _stringListEquality.equals(tilesetIds, other.tilesetIds) &&
          floorLayer == other.floorLayer &&
          objectLayer == other.objectLayer;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        spawnPoint,
        backgroundImage,
        _listEquality.hash(barriers),
        _listEquality.hash(terminals),
        _stringListEquality.hash(tilesetIds),
        floorLayer,
        objectLayer,
      );
}
