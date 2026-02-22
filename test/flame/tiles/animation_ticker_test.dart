import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/tiles/animation_ticker.dart';
import 'package:tech_world/flame/tiles/tile_animation.dart';

void main() {
  group('AnimationTicker', () {
    late AnimationTicker ticker;

    setUp(() {
      ticker = AnimationTicker(
        const TileAnimation(
          baseTileIndex: 100,
          frameIndices: [100, 200, 300],
          stepTime: 0.5,
        ),
      );
    });

    test('starts on the first frame', () {
      expect(ticker.currentFrameIndex, 100);
    });

    test('stays on first frame before stepTime elapses', () {
      ticker.update(0.49);
      expect(ticker.currentFrameIndex, 100);
    });

    test('advances to second frame after one stepTime', () {
      ticker.update(0.5);
      expect(ticker.currentFrameIndex, 200);
    });

    test('advances to third frame after two stepTimes', () {
      ticker.update(1.0);
      expect(ticker.currentFrameIndex, 300);
    });

    test('wraps back to first frame after a full cycle', () {
      // Full cycle = 3 frames × 0.5s = 1.5s
      ticker.update(1.5);
      expect(ticker.currentFrameIndex, 100);
    });

    test('handles incremental updates across frames', () {
      ticker.update(0.3);
      expect(ticker.currentFrameIndex, 100);

      ticker.update(0.3); // total 0.6s → frame 1
      expect(ticker.currentFrameIndex, 200);

      ticker.update(0.5); // total 1.1s → frame 2
      expect(ticker.currentFrameIndex, 300);

      ticker.update(0.5); // total 1.6s → wraps, frame 0
      expect(ticker.currentFrameIndex, 100);
    });

    test('wraps elapsed to prevent precision loss over long sessions', () {
      // Simulate many cycles — elapsed should stay within one cycle.
      for (var i = 0; i < 10000; i++) {
        ticker.update(0.016); // ~60fps
      }
      // After 160 seconds, the ticker should still produce a valid frame.
      final index = ticker.currentFrameIndex;
      expect(
        ticker.animation.frameIndices,
        contains(index),
        reason: 'currentFrameIndex should always be a valid frame index',
      );
    });

    test('returns baseTileIndex for zero-frame animation', () {
      final emptyTicker = AnimationTicker(
        const TileAnimation(
          baseTileIndex: 42,
          frameIndices: [],
          stepTime: 0.3,
        ),
      );

      emptyTicker.update(1.0);
      expect(emptyTicker.currentFrameIndex, 42);
    });

    group('two-frame animation', () {
      late AnimationTicker twoFrame;

      setUp(() {
        twoFrame = AnimationTicker(
          const TileAnimation(
            baseTileIndex: 10,
            frameIndices: [10, 20],
            stepTime: 0.35,
          ),
        );
      });

      test('alternates between two frames', () {
        expect(twoFrame.currentFrameIndex, 10);

        twoFrame.update(0.35);
        expect(twoFrame.currentFrameIndex, 20);

        twoFrame.update(0.35);
        expect(twoFrame.currentFrameIndex, 10);
      });
    });
  });
}
