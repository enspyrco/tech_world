import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/tile_map_format.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

void main() {
  group('Wall tool', () {
    late MapEditorState state;

    setUp(() {
      state = MapEditorState();
    });

    test('paints wall + barrier', () {
      state.setTool(EditorTool.wall);
      state.paintTile(10, 10);

      expect(state.tileAt(10, 10), TileType.barrier);
      expect(state.isWallAt(10, 10), isTrue);
      expect(state.wallStyleAt(10, 10), 'gray_brick');
    });

    test('barrier tool paints plain barrier without wall', () {
      state.setTool(EditorTool.barrier);
      state.paintTile(10, 10);

      expect(state.tileAt(10, 10), TileType.barrier);
      expect(state.isWallAt(10, 10), isFalse);
      expect(state.wallStyleAt(10, 10), isNull);
    });

    test('barrier tool overrides wall at same position', () {
      state.setTool(EditorTool.wall);
      state.paintTile(10, 10);
      expect(state.isWallAt(10, 10), isTrue);

      state.setTool(EditorTool.barrier);
      state.paintTile(10, 10);

      expect(state.tileAt(10, 10), TileType.barrier);
      expect(state.isWallAt(10, 10), isFalse);
    });

    test('eraser clears wall + barrier', () {
      state.setTool(EditorTool.wall);
      state.paintTile(10, 10);
      expect(state.isWallAt(10, 10), isTrue);
      expect(state.tileAt(10, 10), TileType.barrier);

      state.setTool(EditorTool.eraser);
      state.paintTile(10, 10);

      expect(state.tileAt(10, 10), TileType.open);
      expect(state.isWallAt(10, 10), isFalse);
    });

    test('toGameMap exports walls', () {
      state.setTool(EditorTool.wall);
      state.paintTile(5, 5);
      state.paintTile(6, 5);

      // Paint a plain barrier to confirm it does not appear in walls.
      state.setTool(EditorTool.barrier);
      state.paintTile(7, 5);

      final map = state.toGameMap();

      expect(map.walls, hasLength(2));
      expect(map.walls[const Point(5, 5)], 'gray_brick');
      expect(map.walls[const Point(6, 5)], 'gray_brick');
      expect(map.walls.containsKey(const Point(7, 5)), isFalse);

      // All three should be barriers.
      expect(map.barriers, containsAll([
        const Point(5, 5),
        const Point(6, 5),
        const Point(7, 5),
      ]));
    });

    test('loadFromGameMap loads walls', () {
      final map = GameMap(
        id: 'test',
        name: 'Test',
        barriers: [const Point(5, 5), const Point(6, 5)],
        walls: {const Point(5, 5): 'gray_brick'},
      );

      state.loadFromGameMap(map);

      expect(state.isWallAt(5, 5), isTrue);
      expect(state.wallStyleAt(5, 5), 'gray_brick');
      expect(state.isWallAt(6, 5), isFalse);
      expect(state.tileAt(5, 5), TileType.barrier);
      expect(state.tileAt(6, 5), TileType.barrier);
    });

    test('clearGrid clears walls', () {
      state.setTool(EditorTool.wall);
      state.paintTile(5, 5);
      state.paintTile(6, 5);
      expect(state.isWallAt(5, 5), isTrue);
      expect(state.isWallAt(6, 5), isTrue);

      state.clearGrid();

      expect(state.isWallAt(5, 5), isFalse);
      expect(state.isWallAt(6, 5), isFalse);
      expect(state.tileAt(5, 5), TileType.open);
    });

    test('wallStyle defaults to gray_brick and can be changed', () {
      expect(state.wallStyle, 'gray_brick');

      state.wallStyle = 'red_brick';
      expect(state.wallStyle, 'red_brick');

      // New walls should use the updated style.
      state.setTool(EditorTool.wall);
      state.paintTile(10, 10);
      expect(state.wallStyleAt(10, 10), 'red_brick');
    });
  });

  group('TileMapFormat wall round-trip', () {
    test('serializes and deserializes walls', () {
      final original = GameMap(
        id: 'wall_test',
        name: 'Wall Test',
        barriers: [const Point(5, 5), const Point(6, 5), const Point(7, 5)],
        walls: {
          const Point(5, 5): 'gray_brick',
          const Point(7, 5): 'red_brick',
        },
      );

      final json = TileMapFormat.toJson(original);
      final restored = TileMapFormat.fromJson(json);

      expect(restored.walls, hasLength(2));
      expect(restored.walls[const Point(5, 5)], 'gray_brick');
      expect(restored.walls[const Point(7, 5)], 'red_brick');

      // Barriers should also round-trip.
      expect(restored.barriers, hasLength(3));
    });

    test('handles empty walls map', () {
      final original = GameMap(
        id: 'no_walls',
        name: 'No Walls',
        barriers: [const Point(3, 3)],
      );

      final json = TileMapFormat.toJson(original);
      final restored = TileMapFormat.fromJson(json);

      expect(restored.walls, isEmpty);
    });
  });
}
