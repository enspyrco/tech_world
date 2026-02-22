import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/predefined_tilesets.dart';
import 'package:tech_world/flame/tiles/terrain_bitmask.dart';
import 'package:tech_world/flame/tiles/predefined_terrains.dart';

void main() {
  group('predefined terrains', () {
    test('allTerrains is non-empty', () {
      expect(allTerrains, isNotEmpty);
    });

    test('allTerrains has a water terrain', () {
      final water = allTerrains.firstWhere((t) => t.id == 'water');
      expect(water.name, 'Water');
      expect(water.tilesetId, 'ext_terrains');
    });
  });

  group('Water terrain', () {
    test('has exactly 47 bitmask-to-tile entries', () {
      expect(waterTerrain.bitmaskToTileIndex.length, 47);
    });

    test('covers all 47 simplified bitmask values', () {
      final keys = waterTerrain.bitmaskToTileIndex.keys.toSet();
      for (final bm in allSimplifiedBitmasks) {
        expect(keys, contains(bm), reason: 'Missing bitmask $bm');
      }
    });

    test('all tile indices are in bounds for ext_terrains', () {
      final maxIndex = extTerrains.columns * extTerrains.rows - 1;
      for (final entry in waterTerrain.bitmaskToTileIndex.entries) {
        expect(
          entry.value,
          inInclusiveRange(0, maxIndex),
          reason:
              'Tile index ${entry.value} for bitmask ${entry.key} '
              'out of bounds (max $maxIndex)',
        );
      }
    });

    test('preview tile index is in bounds', () {
      final maxIndex = extTerrains.columns * extTerrains.rows - 1;
      expect(waterTerrain.preview, inInclusiveRange(0, maxIndex));
    });

    test('tileIndexForBitmask returns values for all 47 bitmasks', () {
      for (final bm in allSimplifiedBitmasks) {
        expect(
          waterTerrain.tileIndexForBitmask(bm),
          isNotNull,
          reason: 'No tile for bitmask $bm',
        );
      }
    });

    test('lookupTerrain finds water by id', () {
      expect(lookupTerrain('water'), waterTerrain);
    });

    test('lookupTerrain returns null for unknown id', () {
      expect(lookupTerrain('nonexistent'), isNull);
    });
  });
}
