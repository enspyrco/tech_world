import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/timer/countdown_timer_state.dart';

void main() {
  group('CountdownTimerState', () {
    test('starts not running with zero remaining', () {
      final state = CountdownTimerState();
      expect(state.running, isFalse);
      expect(state.remaining, Duration.zero);
    });

    test('start sets running and remaining', () {
      final state = CountdownTimerState();
      state.start(180);
      expect(state.running, isTrue);
      expect(state.remaining, const Duration(seconds: 180));
    });

    test('start ignores non-positive durations', () {
      final state = CountdownTimerState();
      state.start(0);
      expect(state.running, isFalse);
      state.start(-10);
      expect(state.running, isFalse);
    });

    test('tick decreases remaining', () {
      final state = CountdownTimerState();
      state.start(5);
      state.tick();
      expect(state.remaining, const Duration(seconds: 4));
      state.tick();
      expect(state.remaining, const Duration(seconds: 3));
    });

    test('tick is a no-op when not running', () {
      final state = CountdownTimerState();
      state.tick();
      expect(state.running, isFalse);
      expect(state.remaining, Duration.zero);
    });

    test('reaching zero stops and fires onFinished exactly once', () {
      var finishedCount = 0;
      final state = CountdownTimerState(onFinished: () => finishedCount++);
      state.start(3);
      state.tick(); // 2
      state.tick(); // 1
      expect(finishedCount, 0);
      state.tick(); // 0 -> finished
      expect(state.running, isFalse);
      expect(state.remaining, Duration.zero);
      expect(finishedCount, 1);

      // Further ticks after finishing do nothing.
      state.tick();
      expect(finishedCount, 1);
    });

    test('a tick larger than remaining clamps to zero and finishes', () {
      var finished = false;
      final state = CountdownTimerState(onFinished: () => finished = true);
      state.start(2);
      state.tick(const Duration(seconds: 10));
      expect(state.remaining, Duration.zero);
      expect(state.running, isFalse);
      expect(finished, isTrue);
    });

    test('cancel stops without firing onFinished', () {
      var finished = false;
      final state = CountdownTimerState(onFinished: () => finished = true);
      state.start(60);
      state.cancel();
      expect(state.running, isFalse);
      expect(state.remaining, Duration.zero);
      expect(finished, isFalse);
    });

    test('start replaces a running countdown', () {
      final state = CountdownTimerState();
      state.start(60);
      state.tick();
      expect(state.remaining, const Duration(seconds: 59));
      state.start(10);
      expect(state.remaining, const Duration(seconds: 10));
      expect(state.running, isTrue);
    });

    group('formatted mm:ss', () {
      test('zero-pads minutes and seconds', () {
        final state = CountdownTimerState();
        state.start(65);
        expect(state.formatted, '01:05');
      });

      test('handles a full ten minutes', () {
        final state = CountdownTimerState();
        state.start(600);
        expect(state.formatted, '10:00');
      });

      test('rounds up sub-second remaining', () {
        final state = CountdownTimerState();
        state.start(5);
        state.tick(const Duration(milliseconds: 800)); // 4.2s left
        expect(state.formatted, '00:05');
      });

      test('reads 00:00 when finished', () {
        final state = CountdownTimerState();
        state.start(1);
        state.tick();
        expect(state.formatted, '00:00');
      });
    });

    test('notifies listeners on start, tick, cancel', () {
      var notifications = 0;
      final state = CountdownTimerState()..addListener(() => notifications++);
      state.start(3); // 1
      state.tick(); // 2
      state.cancel(); // 3
      expect(notifications, 3);
    });
  });
}
