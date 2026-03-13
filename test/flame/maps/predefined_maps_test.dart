import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/predefined_maps.dart';
import 'package:tech_world/flame/shared/constants.dart';

void main() {
  group('Predefined Maps', () {
    group('openArena', () {
      test('has correct id', () {
        expect(openArena.id, equals('open_arena'));
      });

      test('has correct name', () {
        expect(openArena.name, equals('Open Arena'));
      });

      test('has no barriers', () {
        expect(openArena.barriers, isEmpty);
      });

      test('has spawn point at center', () {
        expect(openArena.spawnPoint, equals(const Point(25, 25)));
      });
    });

    group('lRoom', () {
      test('has correct id', () {
        expect(lRoom.id, equals('l_room'));
      });

      test('has correct name', () {
        expect(lRoom.name, equals('The L-Room'));
      });

      test('has L-shaped wall barriers', () {
        expect(lRoom.barriers, isNotEmpty);
        // Vertical wall at x=4 (22 cells) + horizontal wall at y=7 (13 cells)
        expect(lRoom.barriers.length, equals(35));
      });

      test('has spawn point at (10, 15)', () {
        expect(lRoom.spawnPoint, equals(const Point(10, 15)));
      });

      test('has 2 terminals', () {
        expect(lRoom.terminals.length, equals(2));
      });

      test('uses tilesets for rendering', () {
        expect(lRoom.usesTilesets, isTrue);
        expect(lRoom.tilesetIds, contains('single_room'));
      });

      test('has non-empty floor layer', () {
        expect(lRoom.floorLayer, isNotNull);
        expect(lRoom.floorLayer!.isEmpty, isFalse);
      });

      test('floor layer references single_room tileset', () {
        expect(
          lRoom.floorLayer!.referencedTilesetIds,
          equals({'single_room'}),
        );
      });
    });

    group('fourCorners', () {
      test('has correct id', () {
        expect(fourCorners.id, equals('four_corners'));
      });

      test('has correct name', () {
        expect(fourCorners.name, equals('Four Corners'));
      });

      test('has no predefined barriers', () {
        expect(fourCorners.barriers, isEmpty);
      });

      test('has spawn point at center', () {
        expect(fourCorners.spawnPoint, equals(const Point(25, 25)));
      });
    });

    group('simpleMaze', () {
      test('has correct id', () {
        expect(simpleMaze.id, equals('simple_maze'));
      });

      test('has correct name', () {
        expect(simpleMaze.name, equals('Simple Maze'));
      });

      test('has no predefined barriers', () {
        expect(simpleMaze.barriers, isEmpty);
      });

      test('has spawn point at (8, 8)', () {
        expect(simpleMaze.spawnPoint, equals(const Point(8, 8)));
      });
    });

    group('theLibrary', () {
      test('has correct id', () {
        expect(theLibrary.id, equals('the_library'));
      });

      test('has correct name', () {
        expect(theLibrary.name, equals('The Library'));
      });

      test('has no predefined barriers', () {
        expect(theLibrary.barriers, isEmpty);
      });

      test('has 4 terminal stations', () {
        expect(theLibrary.terminals.length, equals(4));
      });

      test('has a spawn point', () {
        expect(theLibrary.spawnPoint, isNotNull);
      });
    });

    group('theWorkshop', () {
      test('has correct id', () {
        expect(theWorkshop.id, equals('the_workshop'));
      });

      test('has correct name', () {
        expect(theWorkshop.name, equals('The Workshop'));
      });

      test('has no predefined barriers', () {
        expect(theWorkshop.barriers, isEmpty);
      });

      test('has 2 terminal stations', () {
        expect(theWorkshop.terminals.length, equals(2));
      });

      test('has a spawn point', () {
        expect(theWorkshop.spawnPoint, isNotNull);
      });
    });

    group('allMaps', () {
      test('contains all predefined maps', () {
        expect(allMaps, contains(openArena));
        expect(allMaps, contains(lRoom));
        expect(allMaps, contains(fourCorners));
        expect(allMaps, contains(simpleMaze));
        expect(allMaps, contains(theLibrary));
        expect(allMaps, contains(theWorkshop));
      });

      test('has exactly 6 maps', () {
        expect(allMaps.length, equals(6));
      });

      test('all maps have unique ids', () {
        final ids = allMaps.map((m) => m.id).toSet();
        expect(ids.length, equals(allMaps.length));
      });

      test('all maps have unique names', () {
        final names = allMaps.map((m) => m.name).toSet();
        expect(names.length, equals(allMaps.length));
      });

      test('only lRoom has predefined barriers (offline fallback)', () {
        for (final map in allMaps) {
          if (map.id == 'l_room') {
            expect(map.barriers, isNotEmpty,
                reason: 'lRoom should have L-wall barriers for offline play');
          } else {
            expect(map.barriers, isEmpty,
                reason: '${map.name} should have no predefined barriers');
          }
        }
      });
    });

    group('defaultMap', () {
      test('is lRoom', () {
        expect(defaultMap, equals(lRoom));
      });

      test('has L-wall barriers for offline play', () {
        expect(defaultMap.barriers, isNotEmpty);
      });

      test('is in allMaps', () {
        expect(allMaps, contains(defaultMap));
      });
    });

    group('spawn and terminal validation', () {
      test('all spawn points are within grid bounds', () {
        for (final map in allMaps) {
          expect(map.spawnPoint.x, greaterThanOrEqualTo(0),
              reason: '${map.name} spawn x >= 0');
          expect(map.spawnPoint.y, greaterThanOrEqualTo(0),
              reason: '${map.name} spawn y >= 0');
          expect(map.spawnPoint.x, lessThan(gridSize),
              reason: '${map.name} spawn x < gridSize');
          expect(map.spawnPoint.y, lessThan(gridSize),
              reason: '${map.name} spawn y < gridSize');
        }
      });

      test('all terminals are within grid bounds', () {
        for (final map in allMaps) {
          for (final terminal in map.terminals) {
            expect(terminal.x, greaterThanOrEqualTo(0),
                reason: '${map.name} terminal x >= 0');
            expect(terminal.y, greaterThanOrEqualTo(0),
                reason: '${map.name} terminal y >= 0');
            expect(terminal.x, lessThan(gridSize),
                reason: '${map.name} terminal x < gridSize');
            expect(terminal.y, lessThan(gridSize),
                reason: '${map.name} terminal y < gridSize');
          }
        }
      });
    });
  });
}
