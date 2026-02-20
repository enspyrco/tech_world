import 'dart:convert';
import 'dart:math';

import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';

/// JSON serialization/deserialization for tileset-based maps.
///
/// Uses a sparse format where only non-null tiles are stored, keeping map
/// files compact. Barrier, spawn, and terminal data is also included so that
/// a single JSON file fully describes a map.
///
/// Format:
/// ```json
/// {
///   "id": "my_map",
///   "name": "My Map",
///   "spawnPoint": {"x": 25, "y": 25},
///   "barriers": [{"x": 1, "y": 2}, ...],
///   "terminals": [{"x": 5, "y": 10}, ...],
///   "tilesetIds": ["test"],
///   "floorLayer": [{"x": 0, "y": 0, "tilesetId": "test", "tileIndex": 0}, ...],
///   "objectLayer": [{"x": 3, "y": 4, "tilesetId": "test", "tileIndex": 5}, ...]
/// }
/// ```
class TileMapFormat {
  /// Serialize a [GameMap] to a JSON string.
  static String toJsonString(GameMap map) {
    final json = toJson(map);
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(json);
  }

  /// Serialize a [GameMap] to a JSON-compatible map.
  static Map<String, dynamic> toJson(GameMap map) {
    return {
      'id': map.id,
      'name': map.name,
      'spawnPoint': {'x': map.spawnPoint.x, 'y': map.spawnPoint.y},
      'barriers': [
        for (final b in map.barriers) {'x': b.x, 'y': b.y},
      ],
      'terminals': [
        for (final t in map.terminals) {'x': t.x, 'y': t.y},
      ],
      if (map.tilesetIds.isNotEmpty) 'tilesetIds': map.tilesetIds,
      if (map.floorLayer != null) 'floorLayer': map.floorLayer!.toJson(),
      if (map.objectLayer != null) 'objectLayer': map.objectLayer!.toJson(),
    };
  }

  /// Deserialize a [GameMap] from a JSON string.
  static GameMap fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return fromJson(json);
  }

  /// Deserialize a [GameMap] from a JSON-compatible map.
  static GameMap fromJson(Map<String, dynamic> json) {
    final spawnJson = json['spawnPoint'] as Map<String, dynamic>;
    final barriersJson = json['barriers'] as List<dynamic>;
    final terminalsJson = json['terminals'] as List<dynamic>;

    return GameMap(
      id: json['id'] as String,
      name: json['name'] as String,
      spawnPoint: Point(spawnJson['x'] as int, spawnJson['y'] as int),
      barriers: [
        for (final b in barriersJson)
          Point(
            (b as Map<String, dynamic>)['x'] as int,
            b['y'] as int,
          ),
      ],
      terminals: [
        for (final t in terminalsJson)
          Point(
            (t as Map<String, dynamic>)['x'] as int,
            t['y'] as int,
          ),
      ],
      tilesetIds: (json['tilesetIds'] as List<dynamic>?)
              ?.cast<String>()
              .toList() ??
          const [],
      floorLayer: json['floorLayer'] != null
          ? TileLayerData.fromJson(json['floorLayer'] as List<dynamic>)
          : null,
      objectLayer: json['objectLayer'] != null
          ? TileLayerData.fromJson(json['objectLayer'] as List<dynamic>)
          : null,
    );
  }
}
