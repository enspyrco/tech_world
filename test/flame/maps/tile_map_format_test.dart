import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/maps/tile_map_format.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/flame/tiles/tileset.dart';
import 'package:tech_world/map_editor/terrain_grid.dart';

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
      expect(map.terrainGrid, isNull);
      expect(map.usesTilesets, isFalse);
    });

    test('serializes and deserializes terrain grid', () {
      final terrainGrid = TerrainGrid();
      terrainGrid.setTerrain(5, 10, 'water');
      terrainGrid.setTerrain(6, 10, 'water');

      final map = GameMap(
        id: 'terrain_map',
        name: 'Terrain Map',
        barriers: const [],
        terrainGrid: terrainGrid,
      );

      final json = TileMapFormat.toJson(map);
      expect(json.containsKey('terrainGrid'), isTrue);
      expect(json['terrainGrid'], hasLength(2));

      final restored = TileMapFormat.fromJson(json);
      expect(restored.terrainGrid, isNotNull);
      expect(restored.terrainGrid!.terrainAt(5, 10), 'water');
      expect(restored.terrainGrid!.terrainAt(6, 10), 'water');
      expect(restored.terrainGrid!.terrainAt(0, 0), isNull);
    });

    test('omits terrainGrid from JSON when null', () {
      const map = GameMap(
        id: 'no_terrain',
        name: 'No Terrain',
        barriers: [],
      );

      final json = TileMapFormat.toJson(map);
      expect(json.containsKey('terrainGrid'), isFalse);
    });

    test('terrain grid survives JSON string round-trip', () {
      final terrainGrid = TerrainGrid();
      terrainGrid.setTerrain(10, 20, 'water');
      terrainGrid.setTerrain(11, 20, 'sand');

      final map = GameMap(
        id: 'terrain_roundtrip',
        name: 'Terrain Round Trip',
        barriers: const [],
        terrainGrid: terrainGrid,
      );

      final jsonString = TileMapFormat.toJsonString(map);
      final restored = TileMapFormat.fromJsonString(jsonString);

      expect(restored.terrainGrid, isNotNull);
      expect(restored.terrainGrid!.terrainAt(10, 20), 'water');
      expect(restored.terrainGrid!.terrainAt(11, 20), 'sand');
    });

    group('customTilesets', () {
      test('toJson includes customTilesets when present', () {
        const tileset = Tileset(
          id: 'custom_abc123',
          name: 'My Tileset',
          imagePath: 'custom/custom_abc123.png',
          tileSize: 16,
          columns: 8,
          rows: 4,
          isCustom: true,
        );

        final map = GameMap(
          id: 'custom_map',
          name: 'Custom Map',
          barriers: const [],
          customTilesets: const [tileset],
        );

        final json = TileMapFormat.toJson(map);
        expect(json.containsKey('customTilesets'), isTrue);
        expect(json['customTilesets'], hasLength(1));

        final tsJson = (json['customTilesets'] as List).first;
        expect(tsJson['id'], 'custom_abc123');
        expect(tsJson['name'], 'My Tileset');
        expect(tsJson['imagePath'], 'custom/custom_abc123.png');
        expect(tsJson['tileSize'], 16);
        expect(tsJson['columns'], 8);
        expect(tsJson['rows'], 4);
      });

      test('toJson omits customTilesets when empty', () {
        const map = GameMap(
          id: 'no_custom',
          name: 'No Custom',
          barriers: [],
        );

        final json = TileMapFormat.toJson(map);
        expect(json.containsKey('customTilesets'), isFalse);
      });

      test('fromJson deserializes customTilesets with isCustom = true', () {
        final json = {
          'id': 'custom_map',
          'name': 'Custom Map',
          'spawnPoint': {'x': 25, 'y': 25},
          'barriers': <dynamic>[],
          'terminals': <dynamic>[],
          'customTilesets': [
            {
              'id': 'custom_abc123',
              'name': 'My Tileset',
              'imagePath': 'custom/custom_abc123.png',
              'tileSize': 16,
              'columns': 8,
              'rows': 4,
            },
          ],
        };

        final map = TileMapFormat.fromJson(json);
        expect(map.customTilesets, hasLength(1));
        expect(map.customTilesets.first.id, 'custom_abc123');
        expect(map.customTilesets.first.isCustom, isTrue);
        expect(map.customTilesets.first.columns, 8);
        expect(map.customTilesets.first.rows, 4);
      });

      test('fromJson handles missing customTilesets gracefully', () {
        final json = {
          'id': 'minimal',
          'name': 'Minimal',
          'spawnPoint': {'x': 25, 'y': 25},
          'barriers': <dynamic>[],
          'terminals': <dynamic>[],
        };

        final map = TileMapFormat.fromJson(json);
        expect(map.customTilesets, isEmpty);
      });

      test('round-trip preserves customTilesets', () {
        const tileset = Tileset(
          id: 'custom_roundtrip',
          name: 'Roundtrip Tileset',
          imagePath: 'custom/custom_roundtrip.png',
          tileSize: 16,
          columns: 10,
          rows: 5,
          isCustom: true,
        );

        final floorLayer = TileLayerData();
        floorLayer.setTile(
          0,
          0,
          const TileRef(tilesetId: 'custom_roundtrip', tileIndex: 0),
        );

        final map = GameMap(
          id: 'rt_map',
          name: 'RT Map',
          barriers: const [],
          tilesetIds: const ['custom_roundtrip'],
          floorLayer: floorLayer,
          customTilesets: const [tileset],
        );

        final jsonString = TileMapFormat.toJsonString(map);
        final restored = TileMapFormat.fromJsonString(jsonString);

        expect(restored.customTilesets, hasLength(1));
        expect(restored.customTilesets.first.id, 'custom_roundtrip');
        expect(restored.customTilesets.first.isCustom, isTrue);
        expect(restored.customTilesets.first.tileSize, 16);
        expect(restored.customTilesets.first.columns, 10);
        expect(restored.customTilesets.first.rows, 5);
      });
    });
  });
}
