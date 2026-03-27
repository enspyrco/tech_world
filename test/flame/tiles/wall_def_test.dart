import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/wall_def.dart';

void main() {
  group('computeWallBitmask', () {
    test('isolated barrier returns 0', () {
      final barriers = {(5, 5)};
      expect(computeWallBitmask(5, 5, barriers), equals(0));
    });

    test('barrier with neighbor to the north', () {
      final barriers = {(5, 5), (5, 4)};
      expect(
        computeWallBitmask(5, 5, barriers),
        equals(WallBitmask.n),
      );
    });

    test('barrier with neighbor to the east', () {
      final barriers = {(5, 5), (6, 5)};
      expect(
        computeWallBitmask(5, 5, barriers),
        equals(WallBitmask.e),
      );
    });

    test('horizontal wall middle has E + W', () {
      final barriers = {(4, 5), (5, 5), (6, 5)};
      expect(
        computeWallBitmask(5, 5, barriers),
        equals(WallBitmask.e | WallBitmask.w),
      );
    });

    test('vertical wall middle has N + S', () {
      final barriers = {(5, 4), (5, 5), (5, 6)};
      expect(
        computeWallBitmask(5, 5, barriers),
        equals(WallBitmask.n | WallBitmask.s),
      );
    });

    test('L-corner has S + E', () {
      final barriers = {(5, 5), (5, 6), (6, 5)};
      expect(
        computeWallBitmask(5, 5, barriers),
        equals(WallBitmask.s | WallBitmask.e),
      );
    });

    test('all four neighbors returns 15', () {
      final barriers = {(5, 4), (6, 5), (5, 6), (4, 5), (5, 5)};
      expect(
        computeWallBitmask(5, 5, barriers),
        equals(WallBitmask.n | WallBitmask.e | WallBitmask.s | WallBitmask.w),
      );
    });

    test('does not include diagonal neighbors', () {
      // Only diagonal neighbors — should return 0.
      final barriers = {(5, 5), (4, 4), (6, 4), (4, 6), (6, 6)};
      expect(computeWallBitmask(5, 5, barriers), equals(0));
    });
  });

  group('WallDef', () {
    test('faceForBitmask returns mapped tile index', () {
      final def = WallDef(
        id: 'test',
        name: 'Test',
        tilesetId: 'test_tileset',
        faceBitmaskToTileIndex: {0: 42, 5: 99},
        capBitmaskToTileIndex: {4: 10},
      );

      expect(def.faceForBitmask(0), equals(42));
      expect(def.faceForBitmask(5), equals(99));
      expect(def.faceForBitmask(3), isNull);
    });

    test('capForBitmask returns mapped tile index', () {
      final def = WallDef(
        id: 'test',
        name: 'Test',
        tilesetId: 'test_tileset',
        faceBitmaskToTileIndex: {},
        capBitmaskToTileIndex: {4: 10, 6: 20},
      );

      expect(def.capForBitmask(4), equals(10));
      expect(def.capForBitmask(6), equals(20));
      expect(def.capForBitmask(0), isNull);
    });
  });
}
