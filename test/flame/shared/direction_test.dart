import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/direction.dart';

void main() {
  // The previous version of this file asserted, for each of nine Direction
  // values, that the offsets matched the literal declarations in the source
  // file. Those tests can only fail if a typo is introduced AND survives
  // analyzer + reviewer — and even then they restate the source of truth
  // rather than catching a behavioral bug.
  //
  // What CAN'T be expressed by Dart's type system, and what CAN go wrong
  // without anyone noticing, is the bijection between Direction (used by
  // PlayerComponent rendering) and directionFromTuple (used by a_star
  // pathfinding). If those drift apart, paths animate in the wrong
  // direction, or the player turns to face the wrong way at corners.

  group('Direction ↔ directionFromTuple bijection', () {
    test('every non-none Direction has a unique tuple inverse', () {
      // For each Direction (except none), reduce its (offsetX, offsetY)
      // to a unit tuple and look it up in directionFromTuple. The result
      // must round-trip back to the same Direction.
      for (final dir in Direction.values) {
        if (dir == Direction.none) continue;
        final unitTuple = (
          dir.offsetX.sign.toInt(),
          dir.offsetY.sign.toInt(),
        );
        expect(
          directionFromTuple[unitTuple],
          dir,
          reason: 'Direction.${dir.name} offsets ${unitTuple} '
              'do not round-trip through directionFromTuple',
        );
      }
    });

    test('directionFromTuple covers exactly the 8 non-none directions', () {
      final mappedDirections = directionFromTuple.values.toSet();
      final expectedDirections = Direction.values.toSet()..remove(Direction.none);
      expect(mappedDirections, equals(expectedDirections));
      // Cardinality follows from set equality, but pin it explicitly so
      // a future addition like "stay" doesn't silently become a no-op.
      expect(directionFromTuple.length, 8);
    });

    test('off-grid tuples return null', () {
      // Pathfinding sometimes produces these on edges; we rely on the
      // map returning null rather than a wrong direction.
      expect(directionFromTuple[(0, 0)], isNull);
      expect(directionFromTuple[(2, 0)], isNull);
      expect(directionFromTuple[(-1, 2)], isNull);
    });
  });

  group('offset magnitudes', () {
    test('every direction is exactly one grid square in each dimension', () {
      // The path-following animation assumes a single-square step. If a
      // diagonal accidentally became 2 squares on one axis, the player
      // would skate at 2x speed in that direction. The compiler can't
      // catch a wrong constant; this can.
      const cell = gridSquareSizeDouble;
      for (final dir in Direction.values) {
        expect(dir.offsetX.abs(), anyOf(0.0, cell),
            reason: '${dir.name} offsetX magnitude');
        expect(dir.offsetY.abs(), anyOf(0.0, cell),
            reason: '${dir.name} offsetY magnitude');
      }
    });

    test('only Direction.none has both axes zero', () {
      for (final dir in Direction.values) {
        final isStill = dir.offsetX == 0 && dir.offsetY == 0;
        expect(isStill, dir == Direction.none,
            reason: '${dir.name} should-be-still=${dir == Direction.none}');
      }
    });
  });

  group('screen-coordinate semantics', () {
    // The bijection tests above prove Direction and directionFromTuple are
    // mutually consistent — but a coordinated inversion (flip every offsetY
    // sign AND swap the corresponding map keys) would pass every test in
    // the groups above. These four anchors pin the convention to Flame's
    // screen coordinates (y grows downward), so an inversion would have to
    // either mismatch the bijection (caught above) or violate "up means
    // smaller y" (caught here). Without them, an internally-consistent
    // inverted world would ship silently.
    test('Direction.up moves toward smaller y', () {
      expect(Direction.up.offsetY, lessThan(0));
      expect(Direction.up.offsetX, equals(0));
    });

    test('Direction.down moves toward larger y', () {
      expect(Direction.down.offsetY, greaterThan(0));
      expect(Direction.down.offsetX, equals(0));
    });

    test('Direction.right moves toward larger x', () {
      expect(Direction.right.offsetX, greaterThan(0));
      expect(Direction.right.offsetY, equals(0));
    });

    test('Direction.left moves toward smaller x', () {
      expect(Direction.left.offsetX, lessThan(0));
      expect(Direction.left.offsetY, equals(0));
    });
  });
}
