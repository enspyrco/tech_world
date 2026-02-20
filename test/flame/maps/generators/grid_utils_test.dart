import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/generators/grid_utils.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';

void main() {
  group('createFilledGrid', () {
    test('creates gridSize x gridSize grid of walls', () {
      final grid = createFilledGrid();
      expect(grid.length, gridSize);
      for (final row in grid) {
        expect(row.length, gridSize);
        expect(row.every((cell) => cell), isTrue);
      }
    });
  });

  group('createEmptyGrid', () {
    test('creates gridSize x gridSize grid of open space', () {
      final grid = createEmptyGrid();
      expect(grid.length, gridSize);
      for (final row in grid) {
        expect(row.length, gridSize);
        expect(row.every((cell) => !cell), isTrue);
      }
    });
  });

  group('floodFill', () {
    test('fills a small open area', () {
      // 5x5 grid, open 3x3 area in center
      final grid = List.generate(5, (_) => List.filled(5, true));
      for (var y = 1; y <= 3; y++) {
        for (var x = 1; x <= 3; x++) {
          grid[y][x] = false;
        }
      }
      final result = floodFill(grid, const Point(2, 2));
      expect(result.length, 9); // 3x3 open area
    });

    test('does not cross walls', () {
      // Two separate open areas divided by a wall column
      final grid = List.generate(5, (_) => List.filled(5, false));
      // Wall column at x=2
      for (var y = 0; y < 5; y++) {
        grid[y][2] = true;
      }
      final left = floodFill(grid, const Point(0, 0));
      final right = floodFill(grid, const Point(4, 0));
      // Left side: x=0,1 => 2 columns * 5 rows = 10
      expect(left.length, 10);
      // Right side: x=3,4 => 2 columns * 5 rows = 10
      expect(right.length, 10);
      // No overlap
      expect(left.intersection(right), isEmpty);
    });

    test('uses 8-directional movement (diagonals)', () {
      // Only diagonally connected cells
      final grid = List.generate(3, (_) => List.filled(3, true));
      grid[0][0] = false;
      grid[1][1] = false;
      grid[2][2] = false;
      final result = floodFill(grid, const Point(0, 0));
      expect(result, contains(const Point(1, 1)));
      expect(result, contains(const Point(2, 2)));
      expect(result.length, 3);
    });

    test('returns single cell if completely surrounded', () {
      final grid = List.generate(3, (_) => List.filled(3, true));
      grid[1][1] = false;
      final result = floodFill(grid, const Point(1, 1));
      expect(result.length, 1);
      expect(result, contains(const Point(1, 1)));
    });
  });

  group('largestOpenRegion', () {
    test('finds largest of two regions', () {
      // 10x10 grid with two separate regions
      final grid = List.generate(10, (_) => List.filled(10, true));
      // Small region: 2x2 at top-left
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 2; x++) {
          grid[y][x] = false;
        }
      }
      // Large region: 4x4 at bottom-right
      for (var y = 6; y < 10; y++) {
        for (var x = 6; x < 10; x++) {
          grid[y][x] = false;
        }
      }
      final largest = largestOpenRegion(grid);
      expect(largest.length, 16); // 4x4
      expect(largest, contains(const Point(6, 6)));
    });

    test('returns empty set for fully walled grid', () {
      final grid = createFilledGrid();
      expect(largestOpenRegion(grid), isEmpty);
    });
  });

  group('removeDisconnectedRegions', () {
    test('fills small regions, keeps largest', () {
      final grid = List.generate(10, (_) => List.filled(10, true));
      // Small region at (0,0)
      grid[0][0] = false;
      // Large region: 3x3 at (5,5)
      for (var y = 5; y < 8; y++) {
        for (var x = 5; x < 8; x++) {
          grid[y][x] = false;
        }
      }
      final keep = largestOpenRegion(grid);
      removeDisconnectedRegions(grid, keep);

      // Small region should be walled off
      expect(grid[0][0], isTrue);
      // Large region should remain open
      expect(grid[5][5], isFalse);
      expect(grid[7][7], isFalse);
    });
  });

  group('findSpawnPoint', () {
    test('returns a point within the region', () {
      final grid = createEmptyGrid();
      final region = floodFill(grid, const Point(25, 25));
      final spawn = findSpawnPoint(grid, region);
      expect(region, contains(spawn));
    });

    test('returns center-ish point for rectangular region', () {
      final grid = List.generate(10, (_) => List.filled(10, true));
      // Open area from (2,2) to (7,7)
      for (var y = 2; y <= 7; y++) {
        for (var x = 2; x <= 7; x++) {
          grid[y][x] = false;
        }
      }
      final region = floodFill(grid, const Point(4, 4));
      final spawn = findSpawnPoint(grid, region);
      // Should be near center (4 or 5, 4 or 5)
      expect(spawn.x, inInclusiveRange(3, 6));
      expect(spawn.y, inInclusiveRange(3, 6));
    });

    test('returns default for empty region', () {
      final grid = createFilledGrid();
      final spawn = findSpawnPoint(grid, {});
      expect(spawn, const Point(25, 25));
    });
  });

  group('gridToBarriers', () {
    test('converts walls to barrier points', () {
      final grid = createEmptyGrid();
      grid[0][0] = true;
      grid[5][10] = true;
      grid[49][49] = true;
      final barriers = gridToBarriers(grid);
      expect(barriers, contains(const Point(0, 0)));
      expect(barriers, contains(const Point(10, 5)));
      expect(barriers, contains(const Point(49, 49)));
      expect(barriers.length, 3);
    });

    test('returns empty list for open grid', () {
      final grid = createEmptyGrid();
      expect(gridToBarriers(grid), isEmpty);
    });
  });

  group('buildTileLayers', () {
    test('places floor tiles on open cells and wall tiles on walls', () {
      final grid = createEmptyGrid();
      grid[0][0] = true;
      grid[2][3] = true;

      final layers = buildTileLayers(grid);

      // Wall cells get object tiles (default wall index).
      expect(
        layers.objects.tileAt(0, 0),
        const TileRef(
            tilesetId: 'room_builder_office', tileIndex: wallTileDefault),
      );
      expect(
        layers.objects.tileAt(3, 2),
        const TileRef(
            tilesetId: 'room_builder_office', tileIndex: wallTileDefault),
      );

      // Open cells get floor tiles (default light stone).
      expect(
        layers.floor.tileAt(1, 1),
        const TileRef(
            tilesetId: 'room_builder_office', tileIndex: floorTileLightStone),
      );

      // Open cells have no object tile.
      expect(layers.objects.tileAt(1, 1), isNull);
      // Wall cells have no floor tile.
      expect(layers.floor.tileAt(0, 0), isNull);
    });

    test('uses custom tile indices', () {
      final grid = createEmptyGrid();
      grid[0][0] = true;

      final layers = buildTileLayers(grid, floorTileIndex: 120, wallTileIndex: 55);

      expect(layers.objects.tileAt(0, 0)!.tileIndex, 55);
      expect(layers.floor.tileAt(1, 0)!.tileIndex, 120);
    });

    test('uses custom tileset ID', () {
      final grid = createEmptyGrid();
      grid[0][0] = true;

      final layers = buildTileLayers(grid, tilesetId: 'custom');

      expect(layers.objects.tileAt(0, 0)!.tilesetId, 'custom');
      expect(layers.floor.tileAt(1, 0)!.tilesetId, 'custom');
    });

    test('every cell gets exactly one tile (floor xor object)', () {
      final grid = createEmptyGrid();
      // Scatter some walls.
      grid[0][0] = true;
      grid[10][10] = true;
      grid[25][25] = true;

      final layers = buildTileLayers(grid);

      for (var y = 0; y < gridSize; y++) {
        for (var x = 0; x < gridSize; x++) {
          final hasFloor = layers.floor.tileAt(x, y) != null;
          final hasObject = layers.objects.tileAt(x, y) != null;
          expect(hasFloor != hasObject, isTrue,
              reason: '($x,$y) should have exactly one of floor/object');
        }
      }
    });
  });
}
