import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/tile_animation.dart';

void main() {
  group('TileAnimation', () {
    test('stores base tile index, frame indices, and step time', () {
      const anim = TileAnimation(
        baseTileIndex: 10,
        frameIndices: [10, 11, 12],
        stepTime: 0.4,
      );

      expect(anim.baseTileIndex, 10);
      expect(anim.frameIndices, [10, 11, 12]);
      expect(anim.stepTime, 0.4);
    });

    test('frameCount returns the number of frame indices', () {
      const anim = TileAnimation(
        baseTileIndex: 5,
        frameIndices: [5, 6],
      );

      expect(anim.frameCount, 2);
    });

    test('uses default stepTime of 0.3 seconds', () {
      const anim = TileAnimation(
        baseTileIndex: 0,
        frameIndices: [0, 1, 2],
      );

      expect(anim.stepTime, 0.3);
    });

    test('containsIndex returns true for any frame index', () {
      const anim = TileAnimation(
        baseTileIndex: 10,
        frameIndices: [10, 20, 30],
      );

      expect(anim.containsIndex(10), isTrue);
      expect(anim.containsIndex(20), isTrue);
      expect(anim.containsIndex(30), isTrue);
    });

    test('containsIndex returns false for non-frame indices', () {
      const anim = TileAnimation(
        baseTileIndex: 10,
        frameIndices: [10, 20, 30],
      );

      expect(anim.containsIndex(0), isFalse);
      expect(anim.containsIndex(15), isFalse);
      expect(anim.containsIndex(31), isFalse);
    });
  });
}
