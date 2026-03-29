import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/game_map.dart';
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

    group('applyPredefinedVisualFallback', () {
      test('fills in missing floorLayer by structural match (Firestore ID)',
          () {
        // Simulate a Firestore room saved before tile floor was added.
        // ID is a Firestore document ID, not the predefined map ID.
        // Barriers match the L-Room's structure exactly.
        final firestoreMap = GameMap(
          id: 'abc123firestore',
          name: "Nick's Room",
          barriers: lRoom.barriers,
          spawnPoint: lRoom.spawnPoint,
        );

        final merged = applyPredefinedVisualFallback(firestoreMap);

        // Visual layers filled from predefined L-Room.
        expect(merged.floorLayer, isNotNull);
        expect(merged.floorLayer!.isEmpty, isFalse);
        expect(merged.tilesetIds, contains('single_room'));

        // Structural data preserved from Firestore.
        expect(merged.id, 'abc123firestore');
        expect(merged.name, "Nick's Room");
        expect(merged.spawnPoint, lRoom.spawnPoint);
      });

      test('fills in missing floorLayer by direct ID match', () {
        // Direct ID match (e.g. predefined map used without Firestore).
        const firestoreMap = GameMap(
          id: 'l_room',
          name: 'The L-Room',
          barriers: [Point(4, 7)], // different barriers
          spawnPoint: Point(12, 18),
        );

        final merged = applyPredefinedVisualFallback(firestoreMap);

        expect(merged.floorLayer, isNotNull);
        expect(merged.barriers.length, 1); // Firestore barriers preserved
        expect(merged.spawnPoint, const Point(12, 18));
      });

      test('does not override existing floorLayer but fills wallDefId', () {
        // If the Firestore room already has a floor layer, keep it — but
        // fill in wallDefId from the predefined match if missing.
        final existingFloor = lRoom.floorLayer!;
        final firestoreMap = GameMap(
          id: 'abc123',
          name: 'My Room',
          barriers: lRoom.barriers,
          floorLayer: existingFloor,
          tilesetIds: const ['single_room'],
        );

        final merged = applyPredefinedVisualFallback(firestoreMap);

        // Visual layers preserved from original.
        expect(merged.floorLayer, same(existingFloor));
        // wallDefId filled from predefined match.
        expect(merged.wallDefId, equals(lRoom.wallDefId));
      });

      test('returns map unchanged if no predefined match', () {
        const customMap = GameMap(
          id: 'user_custom_map',
          name: 'My Cool Map',
          barriers: [Point(1, 1), Point(2, 2)], // unique barriers
        );

        final result = applyPredefinedVisualFallback(customMap);

        expect(identical(result, customMap), isTrue);
      });

      test('returns map unchanged for empty barriers (no structural match)',
          () {
        // Rooms with no barriers can't match predefined maps structurally.
        const firestoreMap = GameMap(
          id: 'xyz789',
          name: 'Open Room',
          barriers: [],
        );

        final result = applyPredefinedVisualFallback(firestoreMap);

        expect(identical(result, firestoreMap), isTrue);
      });

      test('preserves terminals and custom tilesets from Firestore', () {
        final firestoreMap = GameMap(
          id: 'abc123',
          name: 'My L-Room',
          barriers: lRoom.barriers,
          terminals: const [Point(5, 5), Point(10, 10)],
        );

        final merged = applyPredefinedVisualFallback(firestoreMap);

        expect(merged.terminals.length, 2);
        expect(merged.terminals[0], const Point(5, 5));
        // Visual layers added
        expect(merged.floorLayer, isNotNull);
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
