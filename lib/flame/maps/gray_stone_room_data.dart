import 'dart:math';

import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';

import 'game_map.dart';

/// Tileset used for the gray stone room.
const _tilesetId = 'room_builder_office';

/// Warm beige brick floor tile (row 9, col 4 in room_builder_office).
const _floorTileIndex = 149;

/// Build the default room with a beige floor.
///
/// No predefined barriers or walls — all structural data (barriers, wall
/// style, terminals) comes from Firestore at runtime.
GameMap buildGrayStoneRoom() {
  return GameMap(
    id: 'l_room',
    name: 'Imagination Center',
    barriers: const [],
    spawnPoint: const Point(25, 25),
    floorLayer: _buildFloorLayer(),
    tilesetIds: const [_tilesetId],
  );
}

/// Fill the entire 50×50 grid with lavender floor tiles.
TileLayerData _buildFloorLayer() {
  final layer = TileLayerData();
  const ref = TileRef(tilesetId: _tilesetId, tileIndex: _floorTileIndex);
  for (var y = 0; y < 50; y++) {
    for (var x = 0; x < 50; x++) {
      layer.setTile(x, y, ref);
    }
  }
  return layer;
}
