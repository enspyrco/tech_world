import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/predefined_maps.dart';

void main() {
  group('GameMap', () {
    test('creates map with required fields', () {
      final map = GameMap(
        id: 'test-map',
        name: 'Test Map',
        barriers: [const Point(1, 1), const Point(2, 2)],
      );

      expect(map.id, equals('test-map'));
      expect(map.name, equals('Test Map'));
      expect(map.barriers.length, equals(2));
      expect(map.spawnPoint, equals(const Point(25, 25))); // default
    });

    test('creates map with custom spawn point', () {
      final map = GameMap(
        id: 'custom',
        name: 'Custom',
        barriers: [],
        spawnPoint: const Point(10, 10),
      );

      expect(map.spawnPoint, equals(const Point(10, 10)));
    });

    test('barriers list is accessible', () {
      final barriers = [
        const Point(5, 5),
        const Point(6, 5),
        const Point(7, 5),
      ];
      final map = GameMap(
        id: 'wall',
        name: 'Wall',
        barriers: barriers,
      );

      expect(map.barriers, equals(barriers));
      expect(map.barriers.length, equals(3));
    });
  });

  group('Predefined Maps', () {
    test('openArena has no barriers', () {
      expect(openArena.id, equals('open_arena'));
      expect(openArena.name, equals('Open Arena'));
      expect(openArena.barriers, isEmpty);
    });

    test('lRoom has L-shaped barriers', () {
      expect(lRoom.id, equals('l_room'));
      expect(lRoom.name, equals('The L-Room'));
      expect(lRoom.barriers, isNotEmpty);
      // Verify it contains expected barrier positions (vertical wall at x=4)
      expect(lRoom.barriers.contains(const Point(4, 10)), isTrue);
    });

    test('fourCorners has barriers in corners', () {
      expect(fourCorners.id, equals('four_corners'));
      expect(fourCorners.barriers, isNotEmpty);
    });

    test('simpleMaze has maze pattern', () {
      expect(simpleMaze.id, equals('simple_maze'));
      expect(simpleMaze.barriers, isNotEmpty);
    });

    test('defaultMap is lRoom', () {
      expect(defaultMap, equals(lRoom));
    });

    test('allMaps contains all predefined maps', () {
      expect(allMaps, contains(openArena));
      expect(allMaps, contains(lRoom));
      expect(allMaps, contains(fourCorners));
      expect(allMaps, contains(simpleMaze));
      expect(allMaps.length, greaterThanOrEqualTo(4));
    });
  });
}
