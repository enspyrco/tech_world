import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/shared/dreamfinder_territory.dart';

void main() {
  group('DreamfinderTerritory.resolve', () {
    test('produces a symmetric square when clear of the grid edges', () {
      final rect = const DreamfinderTerritory(center: Point(20, 20), radius: 3)
          .resolve(50);
      expect(rect.minX, 17);
      expect(rect.minY, 17);
      expect(rect.maxX, 23);
      expect(rect.maxY, 23);
    });

    test('clamps to the grid at a corner (no negative bounds)', () {
      final rect = const DreamfinderTerritory(center: Point(1, 1), radius: 3)
          .resolve(50);
      expect(rect.minX, 0);
      expect(rect.minY, 0);
      expect(rect.maxX, 4);
      expect(rect.maxY, 4);
    });

    test('clamps to the far edge (never exceeds gridSize - 1)', () {
      final rect = const DreamfinderTerritory(center: Point(49, 49), radius: 3)
          .resolve(50);
      expect(rect.maxX, 49);
      expect(rect.maxY, 49);
      expect(rect.minX, 46);
      expect(rect.minY, 46);
    });
  });

  group('TerritoryRect.contains', () {
    final rect =
        const DreamfinderTerritory(center: Point(20, 20), radius: 3).resolve(50);

    test('includes the centre and all four corners (inclusive bounds)', () {
      expect(rect.contains(20, 20), isTrue);
      expect(rect.contains(17, 17), isTrue);
      expect(rect.contains(23, 23), isTrue);
      expect(rect.contains(17, 23), isTrue);
      expect(rect.contains(23, 17), isTrue);
    });

    test('excludes a cell one step outside any edge', () {
      expect(rect.contains(16, 20), isFalse);
      expect(rect.contains(24, 20), isFalse);
      expect(rect.contains(20, 16), isFalse);
      expect(rect.contains(20, 24), isFalse);
    });
  });

  group('wire round-trip (bot contract)', () {
    test('toWire is [minX, minY, maxX, maxY]', () {
      final rect =
          const DreamfinderTerritory(center: Point(20, 20), radius: 3)
              .resolve(50);
      expect(rect.toWire(), [17, 17, 23, 23]);
    });

    test('tryParse inverts toWire', () {
      final rect =
          const DreamfinderTerritory(center: Point(10, 30), radius: 2)
              .resolve(50);
      final parsed = TerritoryRect.tryParse(rect.toWire());
      expect(parsed, equals(rect));
    });

    test('tryParse tolerates doubles on the wire (JSON numbers)', () {
      final parsed = TerritoryRect.tryParse([17.0, 17.0, 23.0, 23.0]);
      expect(parsed, const TerritoryRect(minX: 17, minY: 17, maxX: 23, maxY: 23));
    });

    test('tryParse rejects malformed shapes', () {
      expect(TerritoryRect.tryParse(null), isNull);
      expect(TerritoryRect.tryParse([1, 2, 3]), isNull);
      expect(TerritoryRect.tryParse([1, 2, 3, 4, 5]), isNull);
    });
  });

  group('GameMap.resolveDreamfinderTerritory', () {
    test('derives a default square from spawnPoint when none is authored', () {
      const map = GameMap(
        id: 'm',
        name: 'M',
        barriers: [],
        spawnPoint: Point(25, 25),
      );
      // Default centre = spawn + (8, -5) = (33, 20), radius 3.
      final rect = map.resolveDreamfinderTerritory(50);
      expect(rect.center, const Point(33, 20));
      expect(rect.toWire(), [30, 17, 36, 23]);
    });

    test('uses an explicitly authored territory when present', () {
      const map = GameMap(
        id: 'm',
        name: 'M',
        barriers: [],
        spawnPoint: Point(25, 25),
        dreamfinderTerritory:
            DreamfinderTerritory(center: Point(10, 10), radius: 2),
      );
      final rect = map.resolveDreamfinderTerritory(50);
      expect(rect.toWire(), [8, 8, 12, 12]);
    });

    test('authored territory participates in map equality', () {
      const a = GameMap(
        id: 'm',
        name: 'M',
        barriers: [],
        dreamfinderTerritory:
            DreamfinderTerritory(center: Point(10, 10), radius: 2),
      );
      const b = GameMap(
        id: 'm',
        name: 'M',
        barriers: [],
        dreamfinderTerritory:
            DreamfinderTerritory(center: Point(11, 10), radius: 2),
      );
      expect(a == b, isFalse);
    });
  });
}
