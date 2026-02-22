import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/map_editor/terrain_grid.dart';

void main() {
  late TerrainGrid grid;

  setUp(() {
    grid = TerrainGrid();
  });

  group('get / set', () {
    test('starts empty — all cells null', () {
      for (var y = 0; y < gridSize; y++) {
        for (var x = 0; x < gridSize; x++) {
          expect(grid.terrainAt(x, y), isNull);
        }
      }
    });

    test('setTerrain and terrainAt round-trip', () {
      grid.setTerrain(5, 10, 'water');
      expect(grid.terrainAt(5, 10), 'water');
    });

    test('setTerrain to null clears a cell', () {
      grid.setTerrain(5, 10, 'water');
      grid.setTerrain(5, 10, null);
      expect(grid.terrainAt(5, 10), isNull);
    });

    test('different terrains can coexist', () {
      grid.setTerrain(0, 0, 'water');
      grid.setTerrain(1, 0, 'sand');
      expect(grid.terrainAt(0, 0), 'water');
      expect(grid.terrainAt(1, 0), 'sand');
    });
  });

  group('bounds', () {
    test('terrainAt returns null for out-of-bounds', () {
      expect(grid.terrainAt(-1, 0), isNull);
      expect(grid.terrainAt(0, -1), isNull);
      expect(grid.terrainAt(gridSize, 0), isNull);
      expect(grid.terrainAt(0, gridSize), isNull);
    });

    test('setTerrain silently ignores out-of-bounds', () {
      grid.setTerrain(-1, 0, 'water');
      grid.setTerrain(gridSize, 0, 'water');
      // No exception, grid unchanged.
      expect(grid.isEmpty, isTrue);
    });
  });

  group('isTerrainAt', () {
    test('returns true when terrain matches', () {
      grid.setTerrain(3, 4, 'water');
      expect(grid.isTerrainAt(3, 4, 'water'), isTrue);
    });

    test('returns false when terrain differs', () {
      grid.setTerrain(3, 4, 'sand');
      expect(grid.isTerrainAt(3, 4, 'water'), isFalse);
    });

    test('returns false for empty cell', () {
      expect(grid.isTerrainAt(3, 4, 'water'), isFalse);
    });

    test('returns false for out-of-bounds', () {
      expect(grid.isTerrainAt(-1, 0, 'water'), isFalse);
    });
  });

  group('isEmpty', () {
    test('new grid is empty', () {
      expect(grid.isEmpty, isTrue);
    });

    test('grid with a cell is not empty', () {
      grid.setTerrain(0, 0, 'water');
      expect(grid.isEmpty, isFalse);
    });

    test('grid is empty after clearing all cells', () {
      grid.setTerrain(0, 0, 'water');
      grid.setTerrain(0, 0, null);
      expect(grid.isEmpty, isTrue);
    });
  });

  group('clear', () {
    test('clears all cells', () {
      grid.setTerrain(0, 0, 'water');
      grid.setTerrain(10, 10, 'sand');
      grid.clear();
      expect(grid.isEmpty, isTrue);
      expect(grid.terrainAt(0, 0), isNull);
      expect(grid.terrainAt(10, 10), isNull);
    });
  });

  group('JSON serialization', () {
    test('empty grid serializes to empty list', () {
      expect(grid.toJson(), isEmpty);
    });

    test('serializes non-null cells as sparse list', () {
      grid.setTerrain(5, 10, 'water');
      grid.setTerrain(20, 30, 'sand');

      final json = grid.toJson();
      expect(json, hasLength(2));
      expect(json[0], {'x': 5, 'y': 10, 'terrain': 'water'});
      expect(json[1], {'x': 20, 'y': 30, 'terrain': 'sand'});
    });

    test('fromJson restores grid', () {
      final json = [
        {'x': 5, 'y': 10, 'terrain': 'water'},
        {'x': 20, 'y': 30, 'terrain': 'sand'},
      ];
      final restored = TerrainGrid.fromJson(json);
      expect(restored.terrainAt(5, 10), 'water');
      expect(restored.terrainAt(20, 30), 'sand');
      expect(restored.terrainAt(0, 0), isNull);
    });

    test('JSON round-trip preserves data', () {
      grid.setTerrain(0, 0, 'water');
      grid.setTerrain(49, 49, 'sand');
      grid.setTerrain(25, 25, 'water');

      final json = grid.toJson();
      final restored = TerrainGrid.fromJson(json);

      for (var y = 0; y < gridSize; y++) {
        for (var x = 0; x < gridSize; x++) {
          expect(
            restored.terrainAt(x, y),
            grid.terrainAt(x, y),
            reason: 'Mismatch at ($x, $y)',
          );
        }
      }
    });

    test('fromJson ignores out-of-bounds entries', () {
      final json = [
        {'x': -1, 'y': 0, 'terrain': 'water'},
        {'x': 50, 'y': 0, 'terrain': 'water'},
      ];
      final restored = TerrainGrid.fromJson(json);
      expect(restored.isEmpty, isTrue);
    });
  });
}
