import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/keyboard_movement.dart';

/// v2 keyboard-movement helper tests: combined-direction resolution
/// (continuous-while-held + diagonals) and diagonal-speed normalisation.
///
/// These exercise the *pure* input-mapping layer in isolation — no Flame, no
/// rendering. The auto-repeat tick that consumes [directionForKeys] lives in
/// [TechWorldGame.update]; the magnitude contract that guarantees "no √2
/// diagonal speed boost" is pinned here on [movementVelocity].
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

  group('movementVelocity (diagonal normalisation — no √2 boost)', () {
    test('no movement yields a zero vector', () {
      final v = movementVelocity(Direction.none, speed: 100);
      expect(v.dx, 0);
      expect(v.dy, 0);
    });

    test('cardinal velocity magnitude equals the requested speed', () {
      const speed = 120.0;
      for (final dir in [
        Direction.up,
        Direction.down,
        Direction.left,
        Direction.right,
      ]) {
        final v = movementVelocity(dir, speed: speed);
        expect(v.distance, closeTo(speed, 1e-9),
            reason: '$dir should move at exactly `speed`');
      }
    });

    test('diagonal velocity magnitude equals cardinal magnitude (normalised)',
        () {
      const speed = 120.0;
      final cardinal = movementVelocity(Direction.right, speed: speed);
      for (final dir in [
        Direction.upLeft,
        Direction.upRight,
        Direction.downLeft,
        Direction.downRight,
      ]) {
        final diagonal = movementVelocity(dir, speed: speed);
        expect(diagonal.distance, closeTo(cardinal.distance, 1e-9),
            reason: '$dir must not be faster than a cardinal step (no √2)');
      }
    });

    test('a naive (un-normalised) diagonal WOULD be √2 faster — guard holds',
        () {
      const speed = 100.0;
      final diagonal = movementVelocity(Direction.upRight, speed: speed);
      // The un-normalised diagonal would have length speed*√2 ≈ 141.4.
      expect(diagonal.distance, lessThan(speed * 1.4142135));
      expect(diagonal.distance, closeTo(speed, 1e-9));
    });

    test('velocity direction matches the requested Direction sign', () {
      final upRight = movementVelocity(Direction.upRight, speed: 100);
      expect(upRight.dx, greaterThan(0)); // right is +x
      expect(upRight.dy, lessThan(0)); // up is -y (screen coords)
    });
  });

  group('MovementTicker (continuous-while-held cadence)', () {
    const interval = 0.2;

    test('first tick fires immediately (responsive initial step)', () {
      final ticker = MovementTicker(stepInterval: interval);
      // Even a tiny dt on a fresh ticker fires the first step.
      expect(ticker.tick(0.001), isTrue);
    });

    test('holding a key fires repeatedly, one step per interval', () {
      // Simulate a game loop driving update(dt) at 60fps with the key held.
      final ticker = MovementTicker(stepInterval: interval);
      const frameDt = 1 / 60; // ~0.0167s
      var steps = 0;
      // Run for one full second of held-key time.
      for (var t = 0.0; t < 1.0; t += frameDt) {
        if (ticker.tick(frameDt)) steps++;
      }
      // 1 immediate + ~one per 0.2s over 1s -> 5 to 6 steps. Continuous, not one.
      expect(steps, greaterThan(1),
          reason: 'held key must move continuously, not a single step');
      expect(steps, inInclusiveRange(5, 6));
    });

    test('no step fires again until the interval has elapsed', () {
      final ticker = MovementTicker(stepInterval: interval);
      expect(ticker.tick(frameInterval), isTrue); // immediate first step
      // Accumulate dt below the interval -> no further step.
      var fired = false;
      for (var elapsed = 0.0; elapsed < interval - 0.02; elapsed += 0.02) {
        if (ticker.tick(0.02)) fired = true;
      }
      expect(fired, isFalse, reason: 'should not step before stepInterval');
      // One more tick crossing the interval boundary fires.
      expect(ticker.tick(0.05), isTrue);
    });

    test('reset re-arms the immediate first step', () {
      final ticker = MovementTicker(stepInterval: interval);
      expect(ticker.tick(0.001), isTrue);
      expect(ticker.tick(0.001), isFalse); // still cooling down
      ticker.reset();
      expect(ticker.tick(0.001), isTrue); // fresh press fires immediately again
    });
  });

  group('nextKeyboardStep (idle re-entrancy gate)', () {
    const interval = 0.2;
    const frameDt = 1 / 60;

    Set<LogicalKeyboardKey> held() => {LogicalKeyboardKey.keyD};

    test('no step while the player is moving, even when the ticker would fire',
        () {
      final ticker = MovementTicker(stepInterval: interval);
      // Drive many frames of held-key time with the player reported as moving.
      // Without the gate the ticker would fire repeatedly; the gate must block
      // every one of them.
      for (var t = 0.0; t < 1.0; t += frameDt) {
        final step = nextKeyboardStep(
          keysPressed: held(),
          playerIsMoving: true,
          ticker: ticker,
          dt: frameDt,
        );
        expect(step, isNull,
            reason: 'must never re-issue a step mid-cell-move');
      }
    });

    test('the moving gate does not advance the ticker (step ready on idle)', () {
      final ticker = MovementTicker(stepInterval: interval);
      // First step consumes the immediate fire.
      expect(
        nextKeyboardStep(
          keysPressed: held(),
          playerIsMoving: false,
          ticker: ticker,
          dt: frameDt,
        ),
        Direction.right,
      );
      // While moving, accumulate well over a full interval of frames. Because
      // the gate returns BEFORE ticking, the cooldown does not advance...
      for (var t = 0.0; t < interval * 3; t += frameDt) {
        expect(
          nextKeyboardStep(
            keysPressed: held(),
            playerIsMoving: true,
            ticker: ticker,
            dt: frameDt,
          ),
          isNull,
        );
      }
      // ...so the next idle frame must still respect the cadence floor: a single
      // small idle tick has not yet elapsed the interval, so no step yet.
      expect(
        nextKeyboardStep(
          keysPressed: held(),
          playerIsMoving: false,
          ticker: ticker,
          dt: frameDt,
        ),
        isNull,
        reason: 'cooldown is preserved across the moving window',
      );
    });

    test('once idle, the next eligible tick steps in the held direction', () {
      final ticker = MovementTicker(stepInterval: interval);
      // Fresh ticker fires immediately when idle with a live direction.
      final step = nextKeyboardStep(
        keysPressed: {LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyD},
        playerIsMoving: false,
        ticker: ticker,
        dt: frameDt,
      );
      expect(step, Direction.upRight, reason: 'diagonal resolves through gate');
    });

    test('no step when no movement key is held, regardless of idle state', () {
      final ticker = MovementTicker(stepInterval: interval);
      expect(
        nextKeyboardStep(
          keysPressed: {LogicalKeyboardKey.space},
          playerIsMoving: false,
          ticker: ticker,
          dt: frameDt,
        ),
        isNull,
      );
    });
  });
}

/// A single representative frame dt used in cadence tests.
const double frameInterval = 1 / 60;
