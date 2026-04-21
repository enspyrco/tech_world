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

    group('wizardsTower', () {
      test('has correct id', () {
        expect(wizardsTower.id, equals('wizards_tower'));
      });

      test('uses prompt terminal mode', () {
        expect(wizardsTower.terminalMode.name, equals('prompt'));
      });

      test('has 6 terminals', () {
        expect(wizardsTower.terminals.length, equals(6));
      });

      test('has 3 doors', () {
        expect(wizardsTower.doors.length, equals(3));
      });

      test('all terminals are inside the tower walls', () {
        for (final t in wizardsTower.terminals) {
          expect(t.x, greaterThan(16), reason: 'terminal at $t left of wall');
          expect(t.x, lessThan(33), reason: 'terminal at $t right of wall');
          expect(t.y, greaterThan(8), reason: 'terminal at $t above wall');
          expect(t.y, lessThan(44), reason: 'terminal at $t below wall');
        }
      });

      test('all doors are at doorway gaps (not barriers)', () {
        final barrierSet = wizardsTower.barriers
            .map((p) => (p.x, p.y))
            .toSet();
        for (final door in wizardsTower.doors) {
          expect(
            barrierSet.contains((door.position.x, door.position.y)),
            isFalse,
            reason: 'door at ${door.position} overlaps a barrier',
          );
        }
      });

      test('spawn is inside the antechamber', () {
        final s = wizardsTower.spawnPoint;
        expect(s.x, greaterThan(16));
        expect(s.x, lessThan(33));
        expect(s.y, greaterThan(36)); // below lowest internal wall
        expect(s.y, lessThan(44));
      });

      test('doors require progressively harder challenges', () {
        // D0: 1 beginner challenge
        expect(wizardsTower.doors[0].requiredChallengeIds, hasLength(1));
        // D1: 2 beginner challenges (from different schools)
        expect(wizardsTower.doors[1].requiredChallengeIds, hasLength(2));
        // D2: 2 intermediate challenges
        expect(wizardsTower.doors[2].requiredChallengeIds, hasLength(2));
      });

      test('barriers form a closed tower with internal walls', () {
        // Outer walls: top/bottom rows fully covered, left/right cols covered.
        final barrierSet = wizardsTower.barriers
            .map((p) => (p.x, p.y))
            .toSet();

        // Top wall
        for (var x = 16; x <= 33; x++) {
          expect(barrierSet.contains((x, 8)), isTrue,
              reason: 'top wall missing at ($x, 8)');
        }
        // Bottom wall
        for (var x = 16; x <= 33; x++) {
          expect(barrierSet.contains((x, 44)), isTrue,
              reason: 'bottom wall missing at ($x, 44)');
        }
        // Doorway gaps exist at col 24 in internal walls
        for (final row in [15, 25, 36]) {
          expect(barrierSet.contains((24, row)), isFalse,
              reason: 'doorway gap missing at (24, $row)');
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
        expect(allMaps, contains(wizardsTower));
      });

      test('has exactly 7 maps', () {
        expect(allMaps.length, equals(7));
      });

      test('all maps have unique ids', () {
        final ids = allMaps.map((m) => m.id).toSet();
        expect(ids.length, equals(allMaps.length));
      });

      test('all maps have unique names', () {
        final names = allMaps.map((m) => m.name).toSet();
        expect(names.length, equals(allMaps.length));
      });

      test('tile-based maps have no hardcoded barriers', () {
        // Maps backed by painted tile layers get barriers from tiles at
        // runtime. The Wizard's Tower is an exception — it uses programmatic
        // barriers because it has no tileset and needs structural walls.
        final tileMaps =
            allMaps.where((m) => m.id != 'wizards_tower');
        for (final map in tileMaps) {
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
