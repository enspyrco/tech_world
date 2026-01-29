import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/direction.dart';

void main() {
  group('Direction', () {
    test('up has correct offsets', () {
      expect(Direction.up.offsetX, equals(0));
      expect(Direction.up.offsetY, equals(-gridSquareSizeDouble));
    });

    test('down has correct offsets', () {
      expect(Direction.down.offsetX, equals(0));
      expect(Direction.down.offsetY, equals(gridSquareSizeDouble));
    });

    test('left has correct offsets', () {
      expect(Direction.left.offsetX, equals(-gridSquareSizeDouble));
      expect(Direction.left.offsetY, equals(0));
    });

    test('right has correct offsets', () {
      expect(Direction.right.offsetX, equals(gridSquareSizeDouble));
      expect(Direction.right.offsetY, equals(0));
    });

    test('upLeft has correct diagonal offsets', () {
      expect(Direction.upLeft.offsetX, equals(-gridSquareSizeDouble));
      expect(Direction.upLeft.offsetY, equals(-gridSquareSizeDouble));
    });

    test('upRight has correct diagonal offsets', () {
      expect(Direction.upRight.offsetX, equals(gridSquareSizeDouble));
      expect(Direction.upRight.offsetY, equals(-gridSquareSizeDouble));
    });

    test('downLeft has correct diagonal offsets', () {
      expect(Direction.downLeft.offsetX, equals(-gridSquareSizeDouble));
      expect(Direction.downLeft.offsetY, equals(gridSquareSizeDouble));
    });

    test('downRight has correct diagonal offsets', () {
      expect(Direction.downRight.offsetX, equals(gridSquareSizeDouble));
      expect(Direction.downRight.offsetY, equals(gridSquareSizeDouble));
    });

    test('none has zero offsets', () {
      expect(Direction.none.offsetX, equals(0));
      expect(Direction.none.offsetY, equals(0));
    });

    test('all directions are unique', () {
      final allDirections = Direction.values;
      final uniqueOffsets = allDirections
          .map((d) => '${d.offsetX},${d.offsetY}')
          .toSet();
      expect(uniqueOffsets.length, equals(allDirections.length));
    });
  });

  group('directionFromTuple', () {
    test('maps (0, -1) to up', () {
      expect(directionFromTuple[(0, -1)], equals(Direction.up));
    });

    test('maps (0, 1) to down', () {
      expect(directionFromTuple[(0, 1)], equals(Direction.down));
    });

    test('maps (-1, 0) to left', () {
      expect(directionFromTuple[(-1, 0)], equals(Direction.left));
    });

    test('maps (1, 0) to right', () {
      expect(directionFromTuple[(1, 0)], equals(Direction.right));
    });

    test('maps (-1, -1) to upLeft', () {
      expect(directionFromTuple[(-1, -1)], equals(Direction.upLeft));
    });

    test('maps (1, -1) to upRight', () {
      expect(directionFromTuple[(1, -1)], equals(Direction.upRight));
    });

    test('maps (-1, 1) to downLeft', () {
      expect(directionFromTuple[(-1, 1)], equals(Direction.downLeft));
    });

    test('maps (1, 1) to downRight', () {
      expect(directionFromTuple[(1, 1)], equals(Direction.downRight));
    });

    test('returns null for invalid tuple', () {
      expect(directionFromTuple[(5, 5)], isNull);
      expect(directionFromTuple[(0, 0)], isNull);
    });

    test('covers all 8 directions', () {
      expect(directionFromTuple.length, equals(8));
    });
  });
}
