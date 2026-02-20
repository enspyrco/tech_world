import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';

void main() {
  group('TileLayerData', () {
    test('starts empty', () {
      final layer = TileLayerData();
      expect(layer.isEmpty, isTrue);
      expect(layer.tileAt(0, 0), isNull);
      expect(layer.tileAt(25, 25), isNull);
    });

    test('setTile and tileAt round-trip', () {
      final layer = TileLayerData();
      const ref = TileRef(tilesetId: 'test', tileIndex: 3);

      layer.setTile(10, 20, ref);

      expect(layer.tileAt(10, 20), ref);
      expect(layer.isEmpty, isFalse);
    });

    test('setTile to null clears the cell', () {
      final layer = TileLayerData();
      const ref = TileRef(tilesetId: 'test', tileIndex: 0);

      layer.setTile(5, 5, ref);
      expect(layer.tileAt(5, 5), ref);

      layer.setTile(5, 5, null);
      expect(layer.tileAt(5, 5), isNull);
    });

    test('out-of-bounds coordinates return null and are ignored', () {
      final layer = TileLayerData();
      const ref = TileRef(tilesetId: 'test', tileIndex: 1);

      // Out of bounds reads return null.
      expect(layer.tileAt(-1, 0), isNull);
      expect(layer.tileAt(0, -1), isNull);
      expect(layer.tileAt(50, 0), isNull);
      expect(layer.tileAt(0, 50), isNull);

      // Out of bounds writes are silently ignored.
      layer.setTile(-1, 0, ref);
      layer.setTile(0, 50, ref);
      expect(layer.isEmpty, isTrue);
    });

    test('referencedTilesetIds collects unique IDs', () {
      final layer = TileLayerData();
      layer.setTile(0, 0, const TileRef(tilesetId: 'a', tileIndex: 0));
      layer.setTile(1, 0, const TileRef(tilesetId: 'b', tileIndex: 1));
      layer.setTile(2, 0, const TileRef(tilesetId: 'a', tileIndex: 2));

      expect(layer.referencedTilesetIds, {'a', 'b'});
    });

    test('toJson produces sparse list of non-null tiles', () {
      final layer = TileLayerData();
      layer.setTile(1, 2, const TileRef(tilesetId: 'test', tileIndex: 5));
      layer.setTile(3, 4, const TileRef(tilesetId: 'test', tileIndex: 10));

      final json = layer.toJson();
      expect(json, hasLength(2));
      expect(json[0], {
        'x': 1,
        'y': 2,
        'tilesetId': 'test',
        'tileIndex': 5,
      });
      expect(json[1], {
        'x': 3,
        'y': 4,
        'tilesetId': 'test',
        'tileIndex': 10,
      });
    });

    test('fromJson restores layer correctly', () {
      final json = [
        {'x': 5, 'y': 10, 'tilesetId': 'test', 'tileIndex': 7},
        {'x': 0, 'y': 0, 'tilesetId': 'other', 'tileIndex': 0},
      ];

      final layer = TileLayerData.fromJson(json);
      expect(
        layer.tileAt(5, 10),
        const TileRef(tilesetId: 'test', tileIndex: 7),
      );
      expect(
        layer.tileAt(0, 0),
        const TileRef(tilesetId: 'other', tileIndex: 0),
      );
      expect(layer.tileAt(1, 1), isNull);
    });

    test('JSON round-trip preserves data', () {
      final original = TileLayerData();
      original.setTile(0, 0, const TileRef(tilesetId: 'a', tileIndex: 0));
      original.setTile(49, 49, const TileRef(tilesetId: 'b', tileIndex: 15));
      original.setTile(25, 25, const TileRef(tilesetId: 'a', tileIndex: 8));

      final json = original.toJson();
      final restored = TileLayerData.fromJson(json);

      expect(restored.tileAt(0, 0), original.tileAt(0, 0));
      expect(restored.tileAt(49, 49), original.tileAt(49, 49));
      expect(restored.tileAt(25, 25), original.tileAt(25, 25));
      expect(restored.tileAt(1, 1), isNull);
    });
  });
}
