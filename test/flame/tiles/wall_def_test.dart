import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/barrier_occlusion.dart';

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
}
