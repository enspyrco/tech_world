import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/avatar/avatar_spec.dart';
import 'package:tech_world/avatar/avatar_update_throttle.dart';
import 'package:tech_world/avatar/parts/avatar_part.dart';

void main() {
  const a = AvatarSpec(parts: CompositeAvatar(body: BodyId.npc11));
  const b = AvatarSpec(parts: CompositeAvatar(body: BodyId.npc12));
  const c = AvatarSpec(parts: CompositeAvatar(body: BodyId.npc13));
  const window = Duration(milliseconds: 500);

  /// Runs [body] with a throttle whose applications are recorded, under fake
  /// time so the window can be crossed deterministically.
  void withThrottle(
    void Function(AvatarUpdateThrottle throttle, List<(String, AvatarSpec)> applied,
            FakeAsync async)
        body,
  ) {
    fakeAsync((async) {
      final applied = <(String, AvatarSpec)>[];
      final throttle = AvatarUpdateThrottle(
        interval: window,
        apply: (id, spec) => applied.add((id, spec)),
      );
      body(throttle, applied, async);
      throttle.clear();
    });
  }

  test('the first update for a peer applies immediately', () {
    withThrottle((throttle, applied, async) {
      throttle.submit('p1', a);
      expect(applied, [('p1', a)],
          reason: 'a player changing character should see it at once');
    });
  });

  test('a flood inside the window collapses to ONE extra apply', () {
    withThrottle((throttle, applied, async) {
      throttle.submit('p1', a);
      for (var i = 0; i < 100; i++) {
        throttle.submit('p1', i.isEven ? b : c);
      }
      expect(applied, hasLength(1), reason: 'still inside the window');

      async.elapse(window);
      expect(applied, hasLength(2));
    });
  });

  test('the peer ends up wearing what they FINISHED on, not what arrived first',
      () {
    withThrottle((throttle, applied, async) {
      throttle.submit('p1', a);
      throttle.submit('p1', b);
      throttle.submit('p1', c); // the one they settled on

      async.elapse(window);
      expect(applied.last, ('p1', c));
    });
  });

  test('an unchanged re-broadcast inside the window is dropped', () {
    // Late-joiner catch-up re-publishes an avatar that is already applied.
    // Scheduling a recomposite for it would be pure waste.
    withThrottle((throttle, applied, async) {
      throttle.submit('p1', a);
      throttle.submit('p1', a);

      async.elapse(window * 3);
      expect(applied, hasLength(1));
    });
  });

  test('after a quiet window the next update is a leading edge again', () {
    withThrottle((throttle, applied, async) {
      throttle.submit('p1', a);
      async.elapse(window * 2); // goes quiet

      throttle.submit('p1', b);
      expect(applied, hasLength(2),
          reason: 'immediate, not delayed by a stale window');
    });
  });

  test('peers are throttled independently', () {
    withThrottle((throttle, applied, async) {
      throttle.submit('p1', a);
      throttle.submit('p2', b);
      expect(applied, hasLength(2), reason: 'one peer cannot delay another');

      throttle.submit('p1', c);
      expect(applied, hasLength(2));
      async.elapse(window);
      expect(applied, hasLength(3));
    });
  });

  group('teardown', () {
    test('forget cancels a pending apply for a peer who left', () {
      withThrottle((throttle, applied, async) {
        throttle.submit('p1', a);
        throttle.submit('p1', b); // pending

        throttle.forget('p1');

        // Two separate properties, and only the second needs the cancel:
        // dropping the peer from the map already makes the callback a no-op,
        // so the behavioural assertion below passes either way. The timer
        // itself is the leak — one per departing peer, still holding the zone.
        expect(async.pendingTimers, isEmpty,
            reason: 'a departed peer must not leave a live timer');

        async.elapse(window * 3);
        expect(applied, hasLength(1),
            reason: 'applying to a departed peer targets a dead component');
      });
    });

    test('forget does not disturb other peers', () {
      withThrottle((throttle, applied, async) {
        throttle.submit('p1', a);
        throttle.submit('p2', a);
        throttle.submit('p2', b);

        throttle.forget('p1');
        async.elapse(window);

        expect(applied.last, ('p2', b));
        expect(applied, hasLength(3));
      });
    });

    test('clear cancels every peer', () {
      withThrottle((throttle, applied, async) {
        throttle.submit('p1', a);
        throttle.submit('p2', a);
        throttle.submit('p1', b);
        throttle.submit('p2', c);

        throttle.clear();
        async.elapse(window * 3);

        expect(applied, hasLength(2), reason: 'only the two leading edges');
      });
    });

    test('no timer outlives clear', () {
      fakeAsync((async) {
        final throttle = AvatarUpdateThrottle(
          interval: window,
          apply: (_, __) {},
        );
        throttle.submit('p1', a);
        throttle.submit('p2', b);
        expect(async.pendingTimers, hasLength(2),
            reason: 'positive control: the timers exist to be cleaned up');

        throttle.clear();

        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}
