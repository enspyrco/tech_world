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

      test('has barriers', () {
        expect(lRoom.barriers, isNotEmpty);
      });

      test('has spawn point at (10, 15)', () {
        expect(lRoom.spawnPoint, equals(const Point(10, 15)));
      });

      test('vertical wall at x=4', () {
        final verticalWall = lRoom.barriers.where((p) => p.x == 4).toList();
        expect(verticalWall, isNotEmpty);
      });

      test('horizontal wall at y=7', () {
        final horizontalWall = lRoom.barriers.where((p) => p.y == 7).toList();
        expect(horizontalWall, isNotEmpty);
      });

      test('has gap at (4, 17)', () {
        final hasGap = !lRoom.barriers.contains(const Point(4, 17));
        expect(hasGap, isTrue);
      });
    });

    group('fourCorners', () {
      test('has correct id', () {
        expect(fourCorners.id, equals('four_corners'));
      });

      test('has correct name', () {
        expect(fourCorners.name, equals('Four Corners'));
      });

      test('has barriers', () {
        expect(fourCorners.barriers, isNotEmpty);
      });

      test('has spawn point at center', () {
        expect(fourCorners.spawnPoint, equals(const Point(25, 25)));
      });

      test('has barriers in top-left corner', () {
        final topLeft = fourCorners.barriers
            .where((p) => p.x >= 2 && p.x < 7 && p.y >= 2 && p.y < 7);
        expect(topLeft, isNotEmpty);
      });

      test('has barriers in top-right corner', () {
        final topRight = fourCorners.barriers
            .where((p) => p.x >= 43 && p.x < 48 && p.y >= 2 && p.y < 7);
        expect(topRight, isNotEmpty);
      });

      test('has barriers in bottom-left corner', () {
        final bottomLeft = fourCorners.barriers
            .where((p) => p.x >= 2 && p.x < 7 && p.y >= 43 && p.y < 48);
        expect(bottomLeft, isNotEmpty);
      });

      test('has barriers in bottom-right corner', () {
        final bottomRight = fourCorners.barriers
            .where((p) => p.x >= 43 && p.x < 48 && p.y >= 43 && p.y < 48);
        expect(bottomRight, isNotEmpty);
      });

      test('center is open', () {
        final centerBarriers = fourCorners.barriers
            .where((p) => p.x >= 20 && p.x <= 30 && p.y >= 20 && p.y <= 30);
        expect(centerBarriers, isEmpty);
      });

      test('each corner block is 5x5 = 25 barriers', () {
        // Total should be 4 corners * 25 = 100 barriers
        expect(fourCorners.barriers.length, equals(100));
      });
    });

    group('simpleMaze', () {
      test('has correct id', () {
        expect(simpleMaze.id, equals('simple_maze'));
      });

      test('has correct name', () {
        expect(simpleMaze.name, equals('Simple Maze'));
      });

      test('has barriers', () {
        expect(simpleMaze.barriers, isNotEmpty);
      });

      test('has spawn point at (8, 8)', () {
        expect(simpleMaze.spawnPoint, equals(const Point(8, 8)));
      });

      test('has outer walls', () {
        // Top wall at y=5
        final topWall = simpleMaze.barriers.where((p) => p.y == 5);
        expect(topWall, isNotEmpty);

        // Bottom wall at y=44
        final bottomWall = simpleMaze.barriers.where((p) => p.y == 44);
        expect(bottomWall, isNotEmpty);
      });

      test('has gaps in outer walls', () {
        // Gap at x=20 in top wall
        final topGap = simpleMaze.barriers.where((p) => p.y == 5 && p.x == 20);
        expect(topGap, isEmpty);

        // Gap at x=25 in bottom wall
        final bottomGap =
            simpleMaze.barriers.where((p) => p.y == 44 && p.x == 25);
        expect(bottomGap, isEmpty);
      });

      test('has internal maze walls', () {
        // Horizontal wall at y=15
        final internalHorizontal = simpleMaze.barriers.where((p) => p.y == 15);
        expect(internalHorizontal, isNotEmpty);
      });
    });

    group('theLibrary', () {
      test('has correct id', () {
        expect(theLibrary.id, equals('the_library'));
      });

      test('has correct name', () {
        expect(theLibrary.name, equals('The Library'));
      });

      test('has barriers', () {
        expect(theLibrary.barriers, isNotEmpty);
      });

      test('has spawn point in entrance foyer', () {
        expect(theLibrary.spawnPoint, equals(const Point(24, 44)));
      });

      test('has 4 terminal stations', () {
        expect(theLibrary.terminals.length, equals(4));
      });

      test('terminals are not on barriers', () {
        for (final terminal in theLibrary.terminals) {
          expect(theLibrary.barriers.contains(terminal), isFalse,
              reason: 'Terminal at $terminal should not be on a barrier');
        }
      });

      test('spawn point is not on a barrier', () {
        expect(theLibrary.barriers.contains(theLibrary.spawnPoint), isFalse);
      });

      test('has perimeter walls', () {
        // North wall at y=3
        final northWall = theLibrary.barriers.where((p) => p.y == 3);
        expect(northWall, isNotEmpty);
        // West wall at x=3
        final westWall = theLibrary.barriers.where((p) => p.x == 3);
        expect(westWall, isNotEmpty);
      });

      test('has entrance gap in south wall', () {
        // Gap at x=23-26, y=46
        for (int x = 23; x <= 26; x++) {
          expect(theLibrary.barriers.contains(Point(x, 46)), isFalse,
              reason: 'Entrance gap should be open at ($x, 46)');
        }
      });
    });

    group('theWorkshop', () {
      test('has correct id', () {
        expect(theWorkshop.id, equals('the_workshop'));
      });

      test('has correct name', () {
        expect(theWorkshop.name, equals('The Workshop'));
      });

      test('has barriers', () {
        expect(theWorkshop.barriers, isNotEmpty);
      });

      test('has spawn point near entrance', () {
        expect(theWorkshop.spawnPoint, equals(const Point(5, 45)));
      });

      test('has 4 terminal stations', () {
        expect(theWorkshop.terminals.length, equals(4));
      });

      test('terminals are not on barriers', () {
        for (final terminal in theWorkshop.terminals) {
          expect(theWorkshop.barriers.contains(terminal), isFalse,
              reason: 'Terminal at $terminal should not be on a barrier');
        }
      });

      test('spawn point is not on a barrier', () {
        expect(theWorkshop.barriers.contains(theWorkshop.spawnPoint), isFalse);
      });

      test('has more barriers than the Library (more maze-like)', () {
        expect(theWorkshop.barriers.length,
            greaterThan(theLibrary.barriers.length));
      });

      test('has entrance gap in south wall', () {
        // Gap at x=4-6, y=47
        for (int x = 4; x <= 6; x++) {
          expect(theWorkshop.barriers.contains(Point(x, 47)), isFalse,
              reason: 'Entrance gap should be open at ($x, 47)');
        }
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
    });

    group('defaultMap', () {
      test('is lRoom', () {
        expect(defaultMap, equals(lRoom));
      });

      test('has barriers', () {
        expect(defaultMap.barriers, isNotEmpty);
      });

      test('is in allMaps', () {
        expect(allMaps, contains(defaultMap));
      });
    });

    group('barrier validation', () {
      test('all barriers are within grid bounds', () {
        for (final map in allMaps) {
          for (final barrier in map.barriers) {
            expect(barrier.x, greaterThanOrEqualTo(0),
                reason: '${map.name} barrier x >= 0');
            expect(barrier.y, greaterThanOrEqualTo(0),
                reason: '${map.name} barrier y >= 0');
            expect(barrier.x, lessThan(gridSize),
                reason: '${map.name} barrier x < gridSize');
            expect(barrier.y, lessThan(gridSize),
                reason: '${map.name} barrier y < gridSize');
          }
        }
      });

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

      test('spawn points are not on barriers', () {
        for (final map in allMaps) {
          expect(map.barriers.contains(map.spawnPoint), isFalse,
              reason: '${map.name} spawn point should not be on a barrier');
        }
      });

      test('no duplicate barriers in any map', () {
        for (final map in allMaps) {
          final uniqueBarriers = map.barriers.toSet();
          expect(uniqueBarriers.length, equals(map.barriers.length),
              reason: '${map.name} should not have duplicate barriers');
        }
      });

      test('all terminals are reachable from spawn point', () {
        for (final map in allMaps) {
          if (map.terminals.isEmpty) continue;

          // Build a set of barrier cells for O(1) lookup
          final barrierSet = map.barriers.toSet();

          // Flood-fill from spawn point to find all reachable cells
          final reachable = <Point<int>>{};
          final queue = <Point<int>>[map.spawnPoint];
          reachable.add(map.spawnPoint);

          while (queue.isNotEmpty) {
            final current = queue.removeLast();

            // Check all 8 neighbors (including diagonals, matching
            // the game's movement model)
            for (int dx = -1; dx <= 1; dx++) {
              for (int dy = -1; dy <= 1; dy++) {
                if (dx == 0 && dy == 0) continue;
                final neighbor = Point(current.x + dx, current.y + dy);

                // Skip out-of-bounds
                if (neighbor.x < 0 ||
                    neighbor.x >= gridSize ||
                    neighbor.y < 0 ||
                    neighbor.y >= gridSize) {
                  continue;
                }

                // Skip barriers and already-visited cells
                if (barrierSet.contains(neighbor) ||
                    reachable.contains(neighbor)) {
                  continue;
                }

                reachable.add(neighbor);
                queue.add(neighbor);
              }
            }
          }

          // Verify every terminal is in the reachable set
          for (final terminal in map.terminals) {
            expect(reachable.contains(terminal), isTrue,
                reason:
                    '${map.name}: terminal at $terminal is not reachable from '
                    'spawn point ${map.spawnPoint}');
          }
        }
      });
    });
  });
}
