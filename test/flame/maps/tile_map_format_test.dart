import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/tile_map_format.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';

void main() {
  group('TileMapFormat', () {
    test('serializes a simple map without tile layers', () {
      const map = GameMap(
        id: 'test_map',
        name: 'Test Map',
        barriers: [Point(1, 2), Point(3, 4)],
        spawnPoint: Point(10, 10),
        terminals: [Point(5, 5)],
      );

      final json = TileMapFormat.toJson(map);

      expect(json['id'], 'test_map');
      expect(json['name'], 'Test Map');
      expect(json['spawnPoint'], {'x': 10, 'y': 10});
      expect(json['barriers'], [
        {'x': 1, 'y': 2},
        {'x': 3, 'y': 4},
      ]);
      expect(json['terminals'], [
        {'x': 5, 'y': 5},
      ]);
      // Tile fields omitted when not present.
      expect(json.containsKey('tilesetIds'), isFalse);
      expect(json.containsKey('floorLayer'), isFalse);
      expect(json.containsKey('objectLayer'), isFalse);
    });

    test('serializes and deserializes tile layers', () {
      final floorLayer = TileLayerData();
      floorLayer.setTile(0, 0, const TileRef(tilesetId: 'test', tileIndex: 0));
      floorLayer.setTile(1, 0, const TileRef(tilesetId: 'test', tileIndex: 1));

      final objectLayer = TileLayerData();
      objectLayer.setTile(
          5, 10, const TileRef(tilesetId: 'test', tileIndex: 8));

      final map = GameMap(
        id: 'tile_map',
        name: 'Tile Map',
        barriers: const [Point(2, 2)],
        spawnPoint: const Point(25, 25),
        terminals: const [],
        tilesetIds: const ['test'],
        floorLayer: floorLayer,
        objectLayer: objectLayer,
      );

      final json = TileMapFormat.toJson(map);
      expect(json['tilesetIds'], ['test']);
      expect(json['floorLayer'], hasLength(2));
      expect(json['objectLayer'], hasLength(1));

      final restored = TileMapFormat.fromJson(json);
      expect(restored.id, 'tile_map');
      expect(restored.name, 'Tile Map');
      expect(restored.spawnPoint, const Point(25, 25));
      expect(restored.barriers, hasLength(1));
      expect(restored.tilesetIds, ['test']);
      expect(
        restored.floorLayer!.tileAt(0, 0),
        const TileRef(tilesetId: 'test', tileIndex: 0),
      );
      expect(
        restored.floorLayer!.tileAt(1, 0),
        const TileRef(tilesetId: 'test', tileIndex: 1),
      );
      expect(
        restored.objectLayer!.tileAt(5, 10),
        const TileRef(tilesetId: 'test', tileIndex: 8),
      );
    });

    test('JSON string round-trip preserves all data', () {
      final floorLayer = TileLayerData();
      floorLayer.setTile(
          10, 20, const TileRef(tilesetId: 'modern', tileIndex: 42));

      final map = GameMap(
        id: 'roundtrip',
        name: 'Round Trip Test',
        barriers: const [Point(1, 1), Point(2, 2), Point(3, 3)],
        spawnPoint: const Point(5, 5),
        terminals: const [Point(8, 8)],
        tilesetIds: const ['modern'],
        floorLayer: floorLayer,
      );

      final jsonString = TileMapFormat.toJsonString(map);
      final restored = TileMapFormat.fromJsonString(jsonString);

      expect(restored.id, map.id);
      expect(restored.name, map.name);
      expect(restored.spawnPoint, map.spawnPoint);
      expect(restored.barriers.length, map.barriers.length);
      expect(restored.terminals.length, map.terminals.length);
      expect(restored.tilesetIds, map.tilesetIds);
      expect(
        restored.floorLayer!.tileAt(10, 20),
        const TileRef(tilesetId: 'modern', tileIndex: 42),
      );
      expect(restored.objectLayer, isNull);
    });

    test('fromJson handles missing optional fields gracefully', () {
      final json = {
        'id': 'minimal',
        'name': 'Minimal',
        'spawnPoint': {'x': 25, 'y': 25},
        'barriers': <dynamic>[],
        'terminals': <dynamic>[],
      };

      final map = TileMapFormat.fromJson(json);
      expect(map.id, 'minimal');
      expect(map.tilesetIds, isEmpty);
      expect(map.floorLayer, isNull);
      expect(map.objectLayer, isNull);
      expect(map.usesTilesets, isFalse);
    });
  });
}
