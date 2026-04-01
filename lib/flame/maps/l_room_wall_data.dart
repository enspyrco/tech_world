import 'dart:math';

import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/map_editor/wall_grid.dart';

export 'package:tech_world/flame/tiles/tile_layer_data.dart' show TileLayerData;
export 'package:tech_world/map_editor/wall_grid.dart' show WallGrid;

/// All structural wall barriers in the L-Room.
///
/// These define the L-shaped wall layout: a vertical wall at x=4 (with a
/// doorway gap at y=17) and a horizontal wall at y=7.
const lRoomWallBarriers = <Point<int>>[
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
];

/// Build the L-Room's wall object layer by lifting tiles from the floor layer.
///
/// For each structural wall barrier:
/// - **Face**: copies the floor tile at (x, y) into the object layer for
///   depth-sorted rendering.
/// - **Cap**: copies the floor tile at (x, y-1) into the object layer for
///   north-facing walls, enabling wall-top occlusion.
///
/// The caps look identical to the floor tiles underneath — that's intentional.
/// They exist for depth sorting: with priority bumped to y (by
/// [computePriorityOverrides]), the cap renders in front of the player when
/// they walk north of the wall.
({TileLayerData objectLayer, WallGrid wallGrid}) buildLRoomWalls(
  TileLayerData floorLayer,
) {
  final wallGrid = WallGrid();
  final objectLayer = TileLayerData();

  final wallPositions = <(int, int)>{
    for (final b in lRoomWallBarriers) (b.x, b.y),
  };

  for (final (x, y) in wallPositions) {
    wallGrid.setWall(x, y, 'gray_brick');

    // Face: copy floor tile at barrier position.
    final face = floorLayer.tileAt(x, y);
    if (face != null) {
      objectLayer.setTile(x, y, face);
    }

    // Cap: copy floor tile at y-1 for north-facing walls (no wall above).
    if (!wallPositions.contains((x, y - 1))) {
      final cap = floorLayer.tileAt(x, y - 1);
      if (cap != null) {
        objectLayer.setTile(x, y - 1, cap);
      }
    }
  }

  return (objectLayer: objectLayer, wallGrid: wallGrid);
}
