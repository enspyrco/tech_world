import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/keyboard_movement.dart';

/// v2 keyboard-movement helper tests: combined-direction resolution
/// (continuous-while-held + diagonals) and the per-tick step decision.
///
/// These exercise the *pure* input-mapping layer in isolation — no Flame, no
/// rendering. Movement is one cell per step in any direction (grid cadence);
/// there is deliberately no pixel-speed normalisation (a diagonal cell covers
/// ~√2 more pixels than a cardinal one), so there is nothing of that shape to
/// pin here. The continuous walk is paced by the move animation via the idle
/// gate in [nextKeyboardStep].
void main() {
  group('directionForKeys (combined held-key resolution)', () {
    test('empty set yields Direction.none', () {
      expect(directionForKeys({}), Direction.none);
    });

    test('a non-movement key alone yields Direction.none', () {
      expect(directionForKeys({LogicalKeyboardKey.space}), Direction.none);
    });

    test('single cardinal keys resolve to single-axis directions', () {
      expect(directionForKeys({LogicalKeyboardKey.keyW}), Direction.up);
      expect(directionForKeys({LogicalKeyboardKey.keyS}), Direction.down);
      expect(directionForKeys({LogicalKeyboardKey.keyA}), Direction.left);
      expect(directionForKeys({LogicalKeyboardKey.keyD}), Direction.right);
    });

    test('arrow keys resolve the same as WASD', () {
      expect(directionForKeys({LogicalKeyboardKey.arrowUp}), Direction.up);
      expect(directionForKeys({LogicalKeyboardKey.arrowDown}), Direction.down);
      expect(directionForKeys({LogicalKeyboardKey.arrowLeft}), Direction.left);
      expect(
          directionForKeys({LogicalKeyboardKey.arrowRight}), Direction.right);
    });

    test('two perpendicular keys resolve to the matching diagonal', () {
      expect(directionForKeys({LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyD}),
          Direction.upRight);
      expect(directionForKeys({LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyA}),
          Direction.upLeft);
      expect(directionForKeys({LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyD}),
          Direction.downRight);
      expect(directionForKeys({LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyA}),
          Direction.downLeft);
    });

    test('mixing WASD and arrow keys still resolves a diagonal', () {
      expect(
        directionForKeys(
            {LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyD}),
        Direction.upRight,
      );
    });

    test('opposing keys on an axis cancel each other out', () {
      // Up + Down cancel vertically -> no vertical component.
      expect(directionForKeys({LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyS}),
          Direction.none);
      // Up + Down + Right -> the live axis (right) survives.
      expect(
        directionForKeys({
          LogicalKeyboardKey.keyW,
          LogicalKeyboardKey.keyS,
          LogicalKeyboardKey.keyD,
        }),
        Direction.right,
      );
    });

    test('all four cardinals held cancel to Direction.none', () {
      expect(
        directionForKeys({
          LogicalKeyboardKey.keyW,
          LogicalKeyboardKey.keyA,
          LogicalKeyboardKey.keyS,
          LogicalKeyboardKey.keyD,
        }),
        Direction.none,
      );
    });
  });

  group('nextKeyboardStep (idle-gated continuous cadence)', () {
    Set<LogicalKeyboardKey> held() => {LogicalKeyboardKey.keyD};

    test('no step while the player is moving (re-entrancy guard)', () {
      // Across many ticks of held-key time, while the player reports moving, no
      // step is ever issued — otherwise a second move would clobber the in-flight
      // cell animation mid-cell.
      for (var i = 0; i < 60; i++) {
        expect(
          nextKeyboardStep(keysPressed: held(), playerIsMoving: true),
          isNull,
          reason: 'must never re-issue a step mid-cell-move',
        );
      }
    });

    test(
        'continuous, no idle gap: the very first idle tick after a move steps '
        'again with the key still held', () {
      // Simulate the held-key lifecycle frame by frame. The move animation IS
      // the cadence: the instant playerIsMoving flips false, the next tick must
      // step (no dead frame). This is the FLIP of the old ticker behaviour, which
      // forced an extra ~0.2s gap after every cell.
      final keys = held();

      // Idle with a key held -> step.
      expect(nextKeyboardStep(keysPressed: keys, playerIsMoving: false),
          Direction.right);

      // The move runs for some frames; gate blocks every one.
      for (var i = 0; i < 12; i++) {
        expect(nextKeyboardStep(keysPressed: keys, playerIsMoving: true),
            isNull);
      }

      // Move completes -> the FIRST idle frame steps again immediately, no gap.
      expect(nextKeyboardStep(keysPressed: keys, playerIsMoving: false),
          Direction.right,
          reason: 'continuous walk: step on the first idle frame, no idle gap');
    });

    test('idle with a diagonal held steps diagonally', () {
      expect(
        nextKeyboardStep(
          keysPressed: {LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyD},
          playerIsMoving: false,
        ),
        Direction.upRight,
      );
    });

    test('no step when no movement key is held, regardless of idle state', () {
      expect(
        nextKeyboardStep(
          keysPressed: {LogicalKeyboardKey.space},
          playerIsMoving: false,
        ),
        isNull,
      );
      expect(
        nextKeyboardStep(keysPressed: {}, playerIsMoving: false),
        isNull,
      );
    });

    test('opposing keys cancel to no step even when idle', () {
      expect(
        nextKeyboardStep(
          keysPressed: {LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyD},
          playerIsMoving: false,
        ),
        isNull,
      );
    });
  });
}
