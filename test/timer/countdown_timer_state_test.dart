import 'package:flutter/foundation.dart';
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

    test('tick re-derives remaining as the clock advances', () {
      // The absolute-end model recomputes remaining from `endsAt - now`, so
      // ticks track elapsed wall time rather than blindly decrementing.
      var now = DateTime.fromMillisecondsSinceEpoch(0);
      final state = CountdownTimerState(now: () => now);
      state.start(5);
      now = now.add(const Duration(seconds: 1));
      state.tick();
      expect(state.remaining, const Duration(seconds: 4));
      now = now.add(const Duration(seconds: 1));
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
      var now = DateTime.fromMillisecondsSinceEpoch(0);
      var finishedCount = 0;
      final state =
          CountdownTimerState(onFinished: () => finishedCount++, now: () => now);
      state.start(3);
      now = now.add(const Duration(seconds: 1));
      state.tick(); // 2
      now = now.add(const Duration(seconds: 1));
      state.tick(); // 1
      expect(finishedCount, 0);
      now = now.add(const Duration(seconds: 1));
      state.tick(); // 0 -> finished
      expect(state.running, isFalse);
      expect(state.remaining, Duration.zero);
      expect(finishedCount, 1);

      // Further ticks after finishing do nothing.
      now = now.add(const Duration(seconds: 1));
      state.tick();
      expect(finishedCount, 1);
    });

    test('a tick after the end instant clamps to zero and finishes', () {
      var now = DateTime.fromMillisecondsSinceEpoch(0);
      var finished = false;
      final state =
          CountdownTimerState(onFinished: () => finished = true, now: () => now);
      state.start(2);
      now = now.add(const Duration(seconds: 10)); // way past the end
      state.tick();
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
      var now = DateTime.fromMillisecondsSinceEpoch(0);
      final state = CountdownTimerState(now: () => now);
      state.start(60);
      now = now.add(const Duration(seconds: 1));
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
        var now = DateTime.fromMillisecondsSinceEpoch(0);
        final state = CountdownTimerState(now: () => now);
        state.start(5);
        now = now.add(const Duration(milliseconds: 800)); // 4.2s left
        state.tick();
        expect(state.formatted, '00:05');
      });

      test('reads 00:00 when finished', () {
        var now = DateTime.fromMillisecondsSinceEpoch(0);
        final state = CountdownTimerState(now: () => now);
        state.start(1);
        now = now.add(const Duration(seconds: 1));
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

    group('absolute-end model (late-joiner catch-up)', () {
      // A controllable clock so tests are deterministic — no wall time.
      late DateTime now;
      CountdownTimerState build({VoidCallback? onFinished}) =>
          CountdownTimerState(onFinished: onFinished, now: () => now);

      setUp(() => now = DateTime.fromMillisecondsSinceEpoch(1000000));

      test('start derives remaining from an absolute end instant', () {
        final state = build();
        state.start(60);
        expect(state.remaining, const Duration(seconds: 60));

        // Time advances 20s; remaining re-derives from the clock on tick.
        now = now.add(const Duration(seconds: 20));
        state.tick();
        expect(state.remaining, const Duration(seconds: 40));
      });

      test(
          'startAt computes remaining from end timestamp — a late joiner '
          'mid-countdown catches up to the real remaining', () {
        // The starter began a 60s timer 20s ago. A joiner arriving NOW must
        // see ~40s left, not a fresh 60s.
        final endsAt = now.add(const Duration(seconds: 40)); // 60s started 20s ago
        final state = build();
        state.startAt(endsAt);
        expect(state.running, isTrue);
        expect(state.remaining, const Duration(seconds: 40));
      });

      test('startAt with an already-elapsed end finishes immediately', () {
        var finished = false;
        final state = build(onFinished: () => finished = true);
        state.startAt(now.subtract(const Duration(seconds: 5)));
        expect(state.running, isFalse);
        expect(state.remaining, Duration.zero);
        expect(finished, isTrue);
      });

      test('tick re-derives remaining from the clock, robust to skipped ticks',
          () {
        // Even if the ticker misses beats (tab backgrounded), the next tick
        // snaps remaining to the true value rather than drifting.
        final state = build();
        state.start(60);
        now = now.add(const Duration(seconds: 35)); // a long pause
        state.tick();
        expect(state.remaining, const Duration(seconds: 25));
      });

      test('tick crossing the end instant fires onFinished once', () {
        var finishedCount = 0;
        final state = build(onFinished: () => finishedCount++);
        state.start(5);
        now = now.add(const Duration(seconds: 4));
        state.tick();
        expect(state.running, isTrue);
        expect(finishedCount, 0);
        now = now.add(const Duration(seconds: 2)); // now past the end
        state.tick();
        expect(state.running, isFalse);
        expect(state.remaining, Duration.zero);
        expect(finishedCount, 1);
        // Further ticks after finishing do nothing.
        now = now.add(const Duration(seconds: 1));
        state.tick();
        expect(finishedCount, 1);
      });
    });
  });
}
