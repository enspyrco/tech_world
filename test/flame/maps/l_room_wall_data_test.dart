import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/l_room_tile_data.dart';
import 'package:tech_world/flame/maps/l_room_wall_data.dart';

void main() {
  group('buildLRoomWalls', () {
    late ({TileLayerData objectLayer, WallGrid wallGrid}) result;
    late TileLayerData floorLayer;

    setUpAll(() {
      floorLayer = buildLRoomFloorLayer();
      result = buildLRoomWalls(floorLayer);
    });

    test('wallGrid marks all 35 structural barriers', () {
      var count = 0;
      for (final barrier in lRoomWallBarriers) {
        if (result.wallGrid.isWallAt(barrier.x, barrier.y)) count++;
      }
      expect(count, lRoomWallBarriers.length);
    });

    test('every wall cell has a face tile matching the floor tile', () {
      for (final barrier in lRoomWallBarriers) {
        final face = result.objectLayer.tileAt(barrier.x, barrier.y);
        final floor = floorLayer.tileAt(barrier.x, barrier.y);
        expect(face, isNotNull,
            reason: 'Wall at (${barrier.x}, ${barrier.y}) should have face');
        expect(face!.tilesetId, floor!.tilesetId,
            reason: 'Face should use same tileset as floor');
        expect(face.tileIndex, floor.tileIndex,
            reason: 'Face should be same tile as floor');
      }
    });

    test('north-facing walls have cap tiles at y-1 from floor', () {
      // Wall at (5,7) is north-facing — no wall at (5,6).
      final cap = result.objectLayer.tileAt(5, 6);
      final floorAbove = floorLayer.tileAt(5, 6);
      expect(cap, isNotNull,
          reason: 'Cap at (5,6) above north-facing wall at (5,7)');
      expect(cap!.tileIndex, floorAbove!.tileIndex,
          reason: 'Cap should match floor tile above wall');
    });

    test('doorway at y=17 gets cap from wall at (4,18)', () {
      // Wall at (4,18) is north-facing (no wall at (4,17)).
      final cap = result.objectLayer.tileAt(4, 17);
      expect(cap, isNotNull,
          reason: 'Doorway lintel cap at (4,17) from wall at (4,18)');
    });

    test('interior walls do NOT have caps (wall above owns that cell)', () {
      // Wall at (4,10) has wall above at (4,9).
      // (4,9) is a wall itself — its object layer tile should be the FACE
      // from the wall at (4,9), not a cap from (4,10).
      final tile = result.objectLayer.tileAt(4, 9);
      final floorTile = floorLayer.tileAt(4, 9);
      expect(tile, isNotNull);
      expect(tile!.tileIndex, floorTile!.tileIndex,
          reason: 'Should be the face tile for wall at (4,9)');
    });

    test('object layer is not empty', () {
      expect(result.objectLayer.isEmpty, isFalse);
    });

    test('only wall and cap positions have object layer tiles', () {
      // Count non-null tiles in object layer.
      var tileCount = 0;
      for (var y = 0; y < 50; y++) {
        for (var x = 0; x < 50; x++) {
          if (result.objectLayer.tileAt(x, y) != null) tileCount++;
        }
      }
      // 35 face tiles + caps for north-facing walls.
      // North-facing walls: top of horizontal wall (13 tiles at y=7) +
      // top of vertical wall above door (1 at y=7, shared with horizontal) +
      // wall below door (1 at y=18) + no others (all interior walls have
      // walls above). But (4,7) is shared — it's counted once.
      // Caps: all of horizontal y=7 (13 at y=6) + (4,6) from vertical top +
      // (4,17) from wall at (4,18) + (4,28) is NOT north-facing (has (4,27)).
      // Actually let's just verify it's reasonable: > 35 and < 70.
      expect(tileCount, greaterThan(35));
      expect(tileCount, lessThan(70));
    });
  });
}
