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

  group('a FAILED apply must not latch (cage-match #530, Carnot)', () {
    // Eighth instance of this branch's confirmed class: local state advanced
    // beside an unconfirmed effect. The trailing-edge timer cleared `pending`
    // and advanced `lastApplied` BEFORE calling apply — and a throw inside a
    // Timer callback is a silent async error. The final spec in a burst was
    // then lost twice over: nothing applied it, and lastApplied now equalled
    // it, so a rebroadcast of the same spec deduped away too. Peers rendered a
    // stale avatar until some DIFFERENT spec arrived.

    test('a spec that ALWAYS throws is dropped after maxApplyFailures, not '
        'retried forever', () {
      // Tesla, PR #530 round 3. `pending` left set on throw means the window
      // just scheduled retries — and for a spec that throws every time that is
      // a composite attempt plus a log line every interval, forever, driven by
      // a value a PEER chose. This class's header calls itself the bound on
      // peer-controlled compose work, so an unbounded retry inside it is the
      // bound leaking.
      fakeAsync((async) {
        var attempts = 0;
        final throttle = AvatarUpdateThrottle(
          interval: window,
          apply: (id, spec) {
            if (spec == b) {
              attempts++;
              throw StateError('this spec can never compose');
            }
          },
        );

        throttle.submit('peer', a);
        throttle.submit('peer', b);

        // Far more windows than the bound allows.
        for (var i = 0; i < 12; i++) {
          async.elapse(window);
        }

        expect(attempts, AvatarUpdateThrottle.maxApplyFailures,
            reason: 'the retry must stop, not run for the life of the room');
      });
    });

    test('a NEWER spec submitted during a synchronous apply is not dropped',
        () {
      // Secondary strike, same finding: clearing `pending` blindly after
      // _apply wipes anything _apply re-entrantly submitted for this peer —
      // the same lost update the latch-after-apply order exists to prevent,
      // one step later.
      fakeAsync((async) {
        final applied = <AvatarSpec>[];
        late AvatarUpdateThrottle throttle;
        var reentered = false;
        throttle = AvatarUpdateThrottle(
          interval: window,
          apply: (id, spec) {
            applied.add(spec);
            if (spec == b && !reentered) {
              reentered = true;
              throttle.submit('peer', c); // lands in pending mid-apply
            }
          },
        );

        throttle.submit('peer', a);
        throttle.submit('peer', b);
        applied.clear();

        async.elapse(window); // applies b, which submits c
        async.elapse(window); // c must still be pending, and apply

        expect(applied, contains(c),
            reason: 'a spec that arrived during the apply must survive it');
      });
    });

    test('the trailing update is RETRIED when apply throws', () {
      fakeAsync((async) {
        final applied = <AvatarSpec>[];
        // Fail only the FIRST attempt at spec b — the trailing edge. The
        // leading edge is already correct: submit() applies before latching,
        // and a throw there propagates out synchronously with no window
        // created, so the next submit retries as a fresh leading edge.
        var failedOnce = false;
        final throttle = AvatarUpdateThrottle(
          interval: window,
          apply: (id, spec) {
            if (spec == b && !failedOnce) {
              failedOnce = true;
              throw StateError('sheet composite failed');
            }
            applied.add(spec);
          },
        );

        throttle.submit('peer', a); // leading edge applies immediately
        throttle.submit('peer', b); // queued as pending
        applied.clear();

        async.elapse(window); // trailing edge fires and THROWS
        expect(applied, isEmpty);

        async.elapse(window); // next window must retry the same spec
        expect(applied, equals([b]),
            reason: 'a spec that never landed must not be recorded as '
                'applied, or the peer stays stale forever');
      });
    });

    test('NULL ARM: a succeeding apply still latches and does not repeat', () {
      withThrottle((throttle, applied, async) {
        throttle.submit('peer', a);
        throttle.submit('peer', b);
        applied.clear();

        async.elapse(window);
        expect(applied.map((e) => e.$2), equals([b]));

        async.elapse(window * 3);
        expect(applied.map((e) => e.$2), equals([b]),
            reason: 'a landed apply must not be retried');
      });
    });
  });
}
