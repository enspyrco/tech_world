import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/door_data.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/tile_map_format.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

void main() {
  group('Door tool', () {
    late MapEditorState state;

    setUp(() {
      state = MapEditorState();
    });

    test('paints door + barrier', () {
      state.setTool(EditorTool.door);
      state.paintTile(10, 10);

      expect(state.tileAt(10, 10), TileType.barrier);
      expect(state.isDoorAt(10, 10), isTrue);
      expect(state.doorAt(10, 10), isNotNull);
      expect(state.doorAt(10, 10)!.position, const Point(10, 10));
    });

    test('door is not a wall', () {
      state.setTool(EditorTool.door);
      state.paintTile(10, 10);

      expect(state.isWallAt(10, 10), isFalse);
    });

    test('eraser clears door + barrier', () {
      state.setTool(EditorTool.door);
      state.paintTile(10, 10);
      expect(state.isDoorAt(10, 10), isTrue);
      expect(state.tileAt(10, 10), TileType.barrier);

      state.setTool(EditorTool.eraser);
      state.paintTile(10, 10);

      expect(state.tileAt(10, 10), TileType.open);
      expect(state.isDoorAt(10, 10), isFalse);
    });

    test('doorMap returns unmodifiable view', () {
      state.setTool(EditorTool.door);
      state.paintTile(5, 5);
      state.paintTile(6, 6);

      final doorMap = state.doorMap;
      expect(doorMap, hasLength(2));
      expect(doorMap.containsKey((5, 5)), isTrue);
      expect(doorMap.containsKey((6, 6)), isTrue);
    });

    test('clearGrid clears doors', () {
      state.setTool(EditorTool.door);
      state.paintTile(5, 5);
      expect(state.isDoorAt(5, 5), isTrue);

      state.clearGrid();
      expect(state.isDoorAt(5, 5), isFalse);
      expect(state.doorMap, isEmpty);
    });

    test('toGameMap exports doors', () {
      state.setTool(EditorTool.door);
      state.paintTile(5, 5);
      state.paintTile(6, 6);

      final map = state.toGameMap();

      expect(map.doors, hasLength(2));
      expect(
        map.doors.map((d) => d.position),
        containsAll([const Point(5, 5), const Point(6, 6)]),
      );

      // Doors should also appear as barriers.
      expect(map.barriers, contains(const Point(5, 5)));
      expect(map.barriers, contains(const Point(6, 6)));
    });

    test('loadFromGameMap restores doors', () {
      final map = GameMap(
        id: 'test',
        name: 'Test',
        barriers: const [Point(5, 5)],
        doors: [
          DoorData(
            position: const Point(5, 5),
            requiredChallengeIds: ['fizzbuzz'],
          ),
        ],
      );

      state.loadFromGameMap(map);

      expect(state.isDoorAt(5, 5), isTrue);
      expect(state.doorAt(5, 5)!.requiredChallengeIds, ['fizzbuzz']);
    });
  });

  group('Door serialization round-trip', () {
    test('GameMap with doors round-trips through TileMapFormat', () {
      final map = GameMap(
        id: 'door_test',
        name: 'Door Test',
        barriers: const [Point(5, 10), Point(6, 10)],
        terminals: const [],
        doors: [
          DoorData(
            position: const Point(5, 10),
            requiredChallengeIds: ['hello_dart'],
          ),
          DoorData(position: const Point(6, 10)),
        ],
      );

      final json = TileMapFormat.toJson(map);
      expect(json['doors'], hasLength(2));

      final restored = TileMapFormat.fromJson(json);
      expect(restored.doors, hasLength(2));
      expect(restored.doors[0].position, const Point(5, 10));
      expect(restored.doors[0].requiredChallengeIds, ['hello_dart']);
      expect(restored.doors[1].position, const Point(6, 10));
      expect(restored.doors[1].requiredChallengeIds, isEmpty);
    });

    test('GameMap without doors omits doors key', () {
      const map = GameMap(
        id: 'no_doors',
        name: 'No Doors',
        barriers: [],
      );

      final json = TileMapFormat.toJson(map);
      expect(json.containsKey('doors'), isFalse);
    });

    test('fromJson handles missing doors key', () {
      final json = {
        'id': 'legacy',
        'name': 'Legacy Map',
        'spawnPoint': {'x': 25, 'y': 25},
        'barriers': <Map<String, int>>[],
        'terminals': <Map<String, int>>[],
      };

      final map = TileMapFormat.fromJson(json);
      expect(map.doors, isEmpty);
    });
  });
}
