import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/shared/constants.dart';

void main() {
  group('Grid Constants', () {
    test('gridSize is 50', () {
      expect(gridSize, equals(50));
    });

    test('gridSquareSize is 32', () {
      expect(gridSquareSize, equals(32));
    });

    test('gridSquareSizeDouble is 32.0', () {
      expect(gridSquareSizeDouble, equals(32.0));
    });

    test('gridSquareSize and gridSquareSizeDouble are consistent', () {
      expect(gridSquareSizeDouble, equals(gridSquareSize.toDouble()));
    });

    test('total grid dimensions are calculated correctly', () {
      final totalWidth = gridSize * gridSquareSize;
      final totalHeight = gridSize * gridSquareSize;
      expect(totalWidth, equals(1600)); // 50 * 32
      expect(totalHeight, equals(1600));
    });

    test('total grid dimensions with double precision', () {
      final totalWidth = gridSize * gridSquareSizeDouble;
      final totalHeight = gridSize * gridSquareSizeDouble;
      expect(totalWidth, equals(1600.0));
      expect(totalHeight, equals(1600.0));
    });
  });
}
