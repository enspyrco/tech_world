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
        expect(lRoom.name, equals('Imagination Center'));
      });

      test('has no predefined barriers (all from Firestore)', () {
        expect(lRoom.barriers, isEmpty);
      });

      test('has default spawn point', () {
        expect(lRoom.spawnPoint, equals(const Point(25, 25)));
      });

      test('has no predefined terminals', () {
        expect(lRoom.terminals, isEmpty);
      });

      test('uses tilesets for rendering', () {
        expect(lRoom.usesTilesets, isTrue);
        expect(lRoom.tilesetIds, contains('room_builder_office'));
      });

      test('has non-empty floor layer', () {
        expect(lRoom.floorLayer, isNotNull);
        expect(lRoom.floorLayer!.isEmpty, isFalse);
      });

      test('floor layer references room_builder_office tileset', () {
        expect(
          lRoom.floorLayer!.referencedTilesetIds,
          equals({'room_builder_office'}),
        );
      });

      test('object layer is built at runtime', () {
        expect(lRoom.objectLayer, isNull);
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

      test('no predefined maps have hardcoded barriers', () {
        for (final map in allMaps) {
          expect(map.barriers, isEmpty,
              reason: '${map.name} should have no predefined barriers');
        }
      });
    });

    group('applyPredefinedVisualFallback', () {
      test('fills in missing floorLayer by name match', () {
        // Simulate a Firestore room that matches by name.
        const firestoreMap = GameMap(
          id: 'abc123firestore',
          name: 'Imagination Center',
          barriers: [Point(5, 5), Point(6, 5)], // Firestore barriers
          spawnPoint: Point(10, 15),
        );

        final merged = applyPredefinedVisualFallback(firestoreMap);

        // Visual layers filled from predefined L-Room.
        expect(merged.floorLayer, isNotNull);
        expect(merged.floorLayer!.isEmpty, isFalse);
        expect(merged.tilesetIds, contains('room_builder_office'));

        // Structural data preserved from Firestore.
        expect(merged.id, 'abc123firestore');
        expect(merged.name, 'Imagination Center');
        expect(merged.barriers.length, 2);
      });

      test('matches by legacy name and updates to current name', () {
        // Firestore room still has old name from before the rename.
        const firestoreMap = GameMap(
          id: 'abc123firestore',
          name: 'The L-Room',
          barriers: [Point(5, 5)],
        );

        final merged = applyPredefinedVisualFallback(firestoreMap);

        // Should match via legacy name and apply visual layers.
        expect(merged.floorLayer, isNotNull);
        // Name should be updated to current predefined name.
        expect(merged.name, 'Imagination Center');
        // Structural data preserved.
        expect(merged.id, 'abc123firestore');
      });

      test('fills in missing floorLayer by direct ID match', () {
        // Direct ID match (e.g. predefined map used without Firestore).
        const firestoreMap = GameMap(
          id: 'l_room',
          name: 'Imagination Center',
          barriers: [Point(4, 7)], // different barriers
          spawnPoint: Point(12, 18),
        );

        final merged = applyPredefinedVisualFallback(firestoreMap);

        expect(merged.floorLayer, isNotNull);
        expect(merged.barriers.length, 1); // Firestore barriers preserved
        expect(merged.spawnPoint, const Point(12, 18));
      });

      test('preserves existing floorLayer from Firestore', () {
        // If the Firestore room already has a floor layer, keep it.
        final existingFloor = lRoom.floorLayer!;
        final firestoreMap = GameMap(
          id: 'abc123',
          name: 'Imagination Center',
          barriers: const [Point(5, 5)],
          floorLayer: existingFloor,
          tilesetIds: const ['room_builder_office'],
        );

        final merged = applyPredefinedVisualFallback(firestoreMap);

        // Floor layer preserved from Firestore.
        expect(identical(merged.floorLayer, existingFloor), isTrue);
        expect(merged.tilesetIds, contains('room_builder_office'));
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

      test('preserves walls from Firestore during visual fallback', () {
        // Regression: walls field was omitted in the fallback merge,
        // silently dropping wall style data on every room load.
        final walls = {
          const Point(5, 5): 'modern_gray_07',
          const Point(6, 5): 'modern_gray_07',
        };
        final firestoreMap = GameMap(
          id: 'abc123',
          name: 'Imagination Center',
          barriers: const [Point(5, 5), Point(6, 5)],
          walls: walls,
        );

        final merged = applyPredefinedVisualFallback(firestoreMap);

        // Walls must survive the merge — not silently dropped to empty.
        expect(merged.walls, equals(firestoreMap.walls),
            reason: 'Wall style data must be preserved through visual fallback');
        expect(merged.walls.length, 2);
        expect(merged.walls[const Point(5, 5)], 'modern_gray_07');
      });

      test('preserves terminals and custom tilesets from Firestore', () {
        const firestoreMap = GameMap(
          id: 'abc123',
          name: 'Imagination Center',
          barriers: [Point(5, 5)],
          terminals: [Point(5, 5), Point(10, 10)],
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

      test('has floor layer for offline play', () {
        expect(defaultMap.floorLayer, isNotNull);
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
