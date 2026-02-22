import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/predefined_terrains.dart';
import 'package:tech_world/flame/tiles/terrain_bitmask.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

void main() {
  late MapEditorState state;

  setUp(() {
    state = MapEditorState();
    state.setActiveLayer(ActiveLayer.floor);
  });

  group('Terrain brush selection', () {
    test('starts with no active terrain brush', () {
      expect(state.activeTerrainBrush, isNull);
    });

    test('setTerrainBrush sets and notifies', () {
      var notified = false;
      state.addListener(() => notified = true);

      state.setTerrainBrush(waterTerrain);

      expect(state.activeTerrainBrush, waterTerrain);
      expect(notified, isTrue);
    });

    test('setTerrainBrush(null) clears terrain brush', () {
      state.setTerrainBrush(waterTerrain);
      state.setTerrainBrush(null);
      expect(state.activeTerrainBrush, isNull);
    });
  });

  group('paintTerrain', () {
    setUp(() {
      state.setTerrainBrush(waterTerrain);
    });

    test('paints terrain at the given cell', () {
      state.paintTerrain(5, 10);
      expect(state.terrainGrid.terrainAt(5, 10), 'water');
    });

    test('sets a tile on the floor layer', () {
      state.paintTerrain(5, 10);
      final tile = state.floorLayerData.tileAt(5, 10);
      expect(tile, isNotNull);
      expect(tile!.tilesetId, 'ext_terrains');
    });

    test('isolated cell gets bitmask-0 tile', () {
      state.paintTerrain(25, 25);

      final tile = state.floorLayerData.tileAt(25, 25);
      expect(tile, isNotNull);
      expect(
        tile!.tileIndex,
        waterTerrain.tileIndexForBitmask(0),
        reason: 'Isolated cell should get bitmask-0 tile',
      );
    });

    test('two adjacent cells update each other', () {
      state.paintTerrain(10, 10);
      state.paintTerrain(11, 10); // East of first cell

      // Cell (10,10) now has an east neighbor → should have E bit set.
      final tile1 = state.floorLayerData.tileAt(10, 10);
      expect(
        tile1!.tileIndex,
        waterTerrain.tileIndexForBitmask(Bitmask.e),
        reason: 'Left cell should have E neighbor',
      );

      // Cell (11,10) has a west neighbor → should have W bit set.
      final tile2 = state.floorLayerData.tileAt(11, 10);
      expect(
        tile2!.tileIndex,
        waterTerrain.tileIndexForBitmask(Bitmask.w),
        reason: 'Right cell should have W neighbor',
      );
    });

    test('fully surrounded cell gets bitmask-255 tile', () {
      // Paint a 3x3 block of water.
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          state.paintTerrain(20 + dx, 20 + dy);
        }
      }

      final centerTile = state.floorLayerData.tileAt(20, 20);
      expect(
        centerTile!.tileIndex,
        waterTerrain.tileIndexForBitmask(255),
        reason: 'Center of 3x3 block should be fully surrounded',
      );
    });

    test('notifies listeners once per paintTerrain call', () {
      var notifyCount = 0;
      state.addListener(() => notifyCount++);

      state.paintTerrain(5, 5);
      expect(notifyCount, 1, reason: 'Single notification per paint call');
    });

    test('out-of-bounds paintTerrain is a no-op', () {
      state.paintTerrain(-1, 0);
      state.paintTerrain(0, -1);
      state.paintTerrain(gridSize, 0);
      state.paintTerrain(0, gridSize);
      // No exception, terrain grid unchanged.
      expect(state.terrainGrid.isEmpty, isTrue);
    });

    test('painting over existing terrain updates tile', () {
      state.paintTerrain(5, 5);
      final tileBefore = state.floorLayerData.tileAt(5, 5);

      // Paint adjacent cell to change bitmask.
      state.paintTerrain(6, 5);
      final tileAfter = state.floorLayerData.tileAt(5, 5);

      expect(tileAfter!.tileIndex, isNot(tileBefore!.tileIndex),
          reason: 'Tile should update when neighbor is added');
    });
  });

  group('eraseTerrainAt', () {
    setUp(() {
      state.setTerrainBrush(waterTerrain);
    });

    test('clears terrain and tile at cell', () {
      state.paintTerrain(5, 5);
      expect(state.terrainGrid.terrainAt(5, 5), 'water');
      expect(state.floorLayerData.tileAt(5, 5), isNotNull);

      state.eraseTerrainAt(5, 5);
      expect(state.terrainGrid.terrainAt(5, 5), isNull);
      expect(state.floorLayerData.tileAt(5, 5), isNull);
    });

    test('updates neighbors when erasing', () {
      // Paint two adjacent cells.
      state.paintTerrain(10, 10);
      state.paintTerrain(11, 10);

      // Erase the east cell — the west cell should revert to isolated.
      state.eraseTerrainAt(11, 10);

      final tile = state.floorLayerData.tileAt(10, 10);
      expect(
        tile!.tileIndex,
        waterTerrain.tileIndexForBitmask(0),
        reason: 'Cell should revert to isolated after neighbor erased',
      );
    });

    test('erasing non-terrain cell is a no-op', () {
      state.eraseTerrainAt(5, 5);
      expect(state.terrainGrid.isEmpty, isTrue);
    });

    test('out-of-bounds eraseTerrainAt is a no-op', () {
      state.eraseTerrainAt(-1, 0);
      state.eraseTerrainAt(gridSize, 0);
      // No exception.
    });

    test('erasing updates neighbors even after switching to manual mode', () {
      // Paint two adjacent water cells.
      state.paintTerrain(10, 10);
      state.paintTerrain(11, 10);

      // Switch to manual mode (null terrain brush).
      state.setTerrainBrush(null);

      // Erase the east cell — the west cell should revert to isolated.
      state.eraseTerrainAt(11, 10);

      final tile = state.floorLayerData.tileAt(10, 10);
      expect(
        tile!.tileIndex,
        waterTerrain.tileIndexForBitmask(0),
        reason: 'Cell should revert to isolated even after brush switch',
      );
    });
  });

  group('clearAll integration', () {
    test('clearAll resets terrain grid', () {
      state.setTerrainBrush(waterTerrain);
      state.paintTerrain(5, 5);
      state.paintTerrain(10, 10);

      state.clearAll();

      expect(state.terrainGrid.isEmpty, isTrue);
      expect(state.activeTerrainBrush, isNull);
    });
  });

  group('loadFromGameMap terrain roundtrip', () {
    test('toGameMap includes terrainGrid when non-empty', () {
      state.setTerrainBrush(waterTerrain);
      state.paintTerrain(5, 5);

      final map = state.toGameMap();
      expect(map.terrainGrid, isNotNull);
      expect(map.terrainGrid!.terrainAt(5, 5), 'water');
    });

    test('toGameMap excludes terrainGrid when empty', () {
      final map = state.toGameMap();
      expect(map.terrainGrid, isNull);
    });

    test('loadFromGameMap restores terrain grid', () {
      state.setTerrainBrush(waterTerrain);
      state.paintTerrain(5, 5);
      state.paintTerrain(6, 5);

      final map = state.toGameMap();

      final state2 = MapEditorState();
      state2.loadFromGameMap(map);

      expect(state2.terrainGrid.terrainAt(5, 5), 'water');
      expect(state2.terrainGrid.terrainAt(6, 5), 'water');
      expect(state2.terrainGrid.terrainAt(0, 0), isNull);

      // Floor layer should also be restored.
      expect(state2.floorLayerData.tileAt(5, 5), isNotNull);
      expect(
        state2.floorLayerData.tileAt(5, 5),
        equals(TileRef(
          tilesetId: 'ext_terrains',
          tileIndex: waterTerrain.tileIndexForBitmask(Bitmask.e)!,
        )),
      );
    });
  });
}
