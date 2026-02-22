import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/terrain_bitmask.dart';
import 'package:tech_world/flame/tiles/terrain_def.dart';

void main() {
  group('TerrainDef', () {
    late TerrainDef def;

    setUp(() {
      def = TerrainDef(
        id: 'water',
        name: 'Water',
        tilesetId: 'ext_terrains',
        bitmaskToTileIndex: {
          0: 10,
          255: 42,
          Bitmask.n | Bitmask.e | Bitmask.ne: 99,
        },
        previewTileIndex: 42,
      );
    });

    test('stores id, name, and tilesetId', () {
      expect(def.id, 'water');
      expect(def.name, 'Water');
      expect(def.tilesetId, 'ext_terrains');
    });

    test('tileIndexForBitmask returns correct index', () {
      expect(def.tileIndexForBitmask(0), 10);
      expect(def.tileIndexForBitmask(255), 42);
      expect(
        def.tileIndexForBitmask(Bitmask.n | Bitmask.e | Bitmask.ne),
        99,
      );
    });

    test('tileIndexForBitmask returns null for unmapped bitmask', () {
      expect(def.tileIndexForBitmask(Bitmask.s), isNull);
    });

    test('preview returns previewTileIndex when set', () {
      expect(def.preview, 42);
    });

    test('preview defaults to bitmask 255 tile when previewTileIndex is null',
        () {
      final defNoPreview = TerrainDef(
        id: 'water',
        name: 'Water',
        tilesetId: 'ext_terrains',
        bitmaskToTileIndex: {255: 77},
      );
      expect(defNoPreview.preview, 77);
    });

    test('preview returns 0 when neither previewTileIndex nor 255 entry exist',
        () {
      final defEmpty = TerrainDef(
        id: 'water',
        name: 'Water',
        tilesetId: 'ext_terrains',
        bitmaskToTileIndex: {0: 10},
      );
      expect(defEmpty.preview, 0);
    });

    test('bitmaskToTileIndex map is accessible', () {
      expect(def.bitmaskToTileIndex, hasLength(3));
    });
  });
}
