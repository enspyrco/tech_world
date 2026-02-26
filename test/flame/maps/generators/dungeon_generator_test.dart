import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/generators/grid_utils.dart';
import 'package:tech_world/flame/maps/generators/map_generator.dart';
import 'package:tech_world/flame/shared/constants.dart';

void main() {
  group('dungeon generator', () {
    test('all barriers within grid bounds', () {
      final map = generateMap(
        algorithm: MapAlgorithm.dungeon,
        config: const GeneratorConfig(seed: 42),
      );
      for (final barrier in map.barriers) {
        expect(barrier.x, inInclusiveRange(0, gridSize - 1),
            reason: 'barrier x in bounds');
        expect(barrier.y, inInclusiveRange(0, gridSize - 1),
            reason: 'barrier y in bounds');
      }
    });

    test('spawn point not on a barrier', () {
      final map = generateMap(
        algorithm: MapAlgorithm.dungeon,
        config: const GeneratorConfig(seed: 42),
      );
      final barrierSet = map.barriers.toSet();
      expect(barrierSet.contains(map.spawnPoint), isFalse);
    });

    test('all walkable space is connected', () {
      final map = generateMap(
        algorithm: MapAlgorithm.dungeon,
        config: const GeneratorConfig(seed: 42),
      );

      final grid = createEmptyGrid();
      for (final b in map.barriers) {
        grid[b.y][b.x] = true;
      }

      final reachable = floodFill(grid, map.spawnPoint);
      var totalOpen = 0;
      for (var y = 0; y < gridSize; y++) {
        for (var x = 0; x < gridSize; x++) {
          if (!grid[y][x]) totalOpen++;
        }
      }

      expect(reachable.length, totalOpen,
          reason: 'all open cells reachable from spawn');
    });

    test('no duplicate barriers', () {
      final map = generateMap(
        algorithm: MapAlgorithm.dungeon,
        config: const GeneratorConfig(seed: 42),
      );
      expect(map.barriers.toSet().length, map.barriers.length);
    });

    test('same seed produces identical map', () {
      final a = generateMap(
        algorithm: MapAlgorithm.dungeon,
        config: const GeneratorConfig(seed: 99),
      );
      final b = generateMap(
        algorithm: MapAlgorithm.dungeon,
        config: const GeneratorConfig(seed: 99),
      );
      expect(a.barriers, equals(b.barriers));
      expect(a.spawnPoint, equals(b.spawnPoint));
    });

    test('different seeds produce different maps', () {
      final a = generateMap(
        algorithm: MapAlgorithm.dungeon,
        config: const GeneratorConfig(seed: 1),
      );
      final b = generateMap(
        algorithm: MapAlgorithm.dungeon,
        config: const GeneratorConfig(seed: 2),
      );
      expect(a.barriers, isNot(equals(b.barriers)));
    });

    test('no terminals', () {
      final map = generateMap(
        algorithm: MapAlgorithm.dungeon,
        config: const GeneratorConfig(seed: 42),
      );
      expect(map.terminals, isEmpty);
    });

    test('includes tile layers and tileset IDs', () {
      final map = generateMap(
        algorithm: MapAlgorithm.dungeon,
        config: const GeneratorConfig(seed: 42),
      );
      expect(map.usesTilesets, isTrue);
      expect(map.tilesetIds, contains('room_builder_office'));
      expect(map.floorLayer, isNotNull);
      expect(map.floorLayer!.isEmpty, isFalse);
      expect(map.objectLayer, isNotNull);
      expect(map.objectLayer!.isEmpty, isFalse);
    });

    test('10 seeds without invariant violations', () {
      for (var seed = 0; seed < 10; seed++) {
        final map = generateMap(
          algorithm: MapAlgorithm.dungeon,
          config: GeneratorConfig(seed: seed),
        );

        // Barriers in bounds.
        for (final b in map.barriers) {
          expect(b.x, inInclusiveRange(0, gridSize - 1));
          expect(b.y, inInclusiveRange(0, gridSize - 1));
        }

        // Spawn not on barrier.
        expect(map.barriers.toSet().contains(map.spawnPoint), isFalse,
            reason: 'seed $seed: spawn not on barrier');

        // No duplicates.
        expect(map.barriers.toSet().length, map.barriers.length,
            reason: 'seed $seed: no duplicate barriers');

        // Connected.
        final grid = createEmptyGrid();
        for (final b in map.barriers) {
          grid[b.y][b.x] = true;
        }
        final reachable = floodFill(grid, map.spawnPoint);
        var totalOpen = 0;
        for (var y = 0; y < gridSize; y++) {
          for (var x = 0; x < gridSize; x++) {
            if (!grid[y][x]) totalOpen++;
          }
        }
        expect(reachable.length, totalOpen,
            reason: 'seed $seed: all open cells connected');
      }
    });
  });
}
