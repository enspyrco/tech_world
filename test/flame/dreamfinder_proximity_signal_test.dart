import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tech_world/flame/dreamfinder_proximity_signal.dart';
import 'package:tech_world/flame/shared/dreamfinder_territory.dart';
import 'package:tech_world/livekit/livekit_service.dart';

class MockLiveKitService extends Mock implements LiveKitService {}

void main() {
  // Rewritten 2026-08-30. The previous suite pinned a distance-with-hysteresis
  // contract that has been deliberately replaced by territory containment:
  // Dreamfinder wanders INSIDE his square, so measuring distance to his sprite
  // let him hear players standing outside the box beside him. Reported from
  // outside as "he hears us when we're nearby the box".
  //
  // These tests are written against the box, so the cases that matter are the
  // ones just outside a corner and just outside an edge — the exact geometry
  // the old distance test got wrong.

  late MockLiveKitService service;

  // A 7x7 square (radius 3 about (10,10)) — the authored default shape.
  const box = TerritoryRect(minX: 7, minY: 7, maxX: 13, maxY: 13);

  DreamfinderProximitySignal build({
    bool withService = true,
    int proximityRadius = 5,
  }) =>
      DreamfinderProximitySignal(
        liveKitService: () => withService ? service : null,
        proximityRadius: () => proximityRadius,
      );

  setUp(() {
    service = MockLiveKitService();
    when(() => service.publishDfProximity(near: any(named: 'near')))
        .thenAnswer((_) async {});
  });

  group('containment', () {
    test('inside the box publishes near: true once', () {
      build().update(playerGrid: const Point(10, 10), territory: box);
      verify(() => service.publishDfProximity(near: true)).called(1);
    });

    test('a cell ON the boundary is inside — bounds are inclusive', () {
      build().update(playerGrid: const Point(13, 13), territory: box);
      verify(() => service.publishDfProximity(near: true)).called(1);
    });

    test('outside the box publishes nothing — it was never near', () {
      build().update(playerGrid: const Point(20, 20), territory: box);
      verifyNever(() => service.publishDfProximity(near: any(named: 'near')));
    });
  });

  group('the regression this rewrite exists for', () {
    // Under the old distance rule these players were HEARD, because DF could be
    // standing at the near edge of his own square and the test measured the gap
    // to him rather than the box.
    test('one cell outside the edge is NOT heard, however close DF stands', () {
      final signal = build();
      signal.update(playerGrid: const Point(14, 10), territory: box);
      expect(signal.isNear, isFalse);
      verifyNever(() => service.publishDfProximity(near: any(named: 'near')));
    });

    test('diagonally outside the corner is NOT heard', () {
      final signal = build();
      signal.update(playerGrid: const Point(14, 14), territory: box);
      expect(signal.isNear, isFalse);
    });

    test('stepping over the edge flips exactly once each way', () async {
      // Pumped between crossings: at most ONE publish is in flight, so a later
      // desire waits for the outstanding one rather than racing it. In the
      // game loop these are separate frames; in a test they are separate
      // microtask turns.
      final signal = build();
      signal.update(playerGrid: const Point(14, 10), territory: box); // out
      signal.update(playerGrid: const Point(13, 10), territory: box); // in
      signal.update(playerGrid: const Point(12, 10), territory: box); // deeper
      await pumpEventQueue();
      signal.update(playerGrid: const Point(14, 10), territory: box); // out
      await pumpEventQueue();
      verify(() => service.publishDfProximity(near: true)).called(1);
      verify(() => service.publishDfProximity(near: false)).called(1);
    });
  });

  group('transition-only emission', () {
    test('walking around inside the box never re-publishes', () {
      final signal = build();
      signal.update(playerGrid: const Point(8, 8), territory: box);
      for (var x = 8; x <= 13; x++) {
        signal.update(playerGrid: Point(x, 9), territory: box);
      }
      verify(() => service.publishDfProximity(near: true)).called(1);
    });

    test('standing still outside never publishes at all', () {
      final signal = build();
      for (var i = 0; i < 10; i++) {
        signal.update(playerGrid: const Point(0, 0), territory: box);
      }
      verifyNever(() => service.publishDfProximity(near: any(named: 'near')));
    });
  });

  group('absence forces an exit', () {
    test('a null territory (DF absent) exits a player who was inside',
        () async {
      final signal = build();
      signal.update(playerGrid: const Point(10, 10), territory: box);
      await pumpEventQueue();
      signal.update(playerGrid: const Point(10, 10), territory: null);
      await pumpEventQueue();
      expect(signal.isNear, isFalse);
      verify(() => service.publishDfProximity(near: false)).called(1);
    });

    test('a null playerGrid (no local player) exits too', () async {
      final signal = build();
      signal.update(playerGrid: const Point(10, 10), territory: box);
      await pumpEventQueue();
      signal.update(playerGrid: null, territory: box);
      await pumpEventQueue();
      expect(signal.isNear, isFalse);
      verify(() => service.publishDfProximity(near: false)).called(1);
    });
  });

  group('never latch what you could not send', () {
    test('no service: state is untouched so the transition re-fires', () {
      final signal = build(withService: false);
      signal.update(playerGrid: const Point(10, 10), territory: box);
      // Nothing was published, so nothing may be remembered as published.
      expect(signal.isNear, isFalse);
    });

    test('the retry actually lands once the service appears', () {
      var present = false;
      final signal = DreamfinderProximitySignal(
        liveKitService: () => present ? service : null,
        proximityRadius: () => 5,
      );
      signal.update(playerGrid: const Point(10, 10), territory: box);
      verifyNever(() => service.publishDfProximity(near: any(named: 'near')));
      present = true;
      signal.update(playerGrid: const Point(10, 10), territory: box);
      verify(() => service.publishDfProximity(near: true)).called(1);
    });
  });

  group('reset', () {
    // CONTRACT CHANGE, deliberate. reset() used to publish an exit
    // UNCONDITIONALLY, including when the bot had never been told anyone was
    // near. That belt-and-braces existed because the old latch could not be
    // trusted: it advanced at send time whether or not the send landed, so the
    // teardown path could not tell a real "near: true" from a phantom one and
    // had to assume the worst.
    //
    // With confirmed state, that doubt is gone. reset() is now just
    // `_desired = false` down the same reconcile path as everything else, so
    // it sends an exit exactly when the bot believes otherwise and stays quiet
    // when it does not. Removing the coupling removed the reason for the
    // redundant message, rather than keeping the message as a guard.

    test('publishes an exit for a player who was near', () async {
      final signal = build();
      signal.update(playerGrid: const Point(10, 10), territory: box);
      await pumpEventQueue();
      signal.reset();
      await pumpEventQueue();
      expect(signal.isNear, isFalse);
      verify(() => service.publishDfProximity(near: false)).called(1);
    });

    test('is SILENT when the bot already believes the player is not near',
        () async {
      // A bot that was told nothing does not think anyone is near it, and a
      // fresh agent-* dispatch starts the same way — so there is nothing to
      // correct and nothing worth a message.
      build().reset();
      await pumpEventQueue();
      verifyNever(
          () => service.publishDfProximity(near: any(named: 'near')));
    });

    test('a player who leaves and re-enters is re-announced to a NEW agent',
        () async {
      // The case that made the old unconditional exit feel necessary, and the
      // one this design has to get right: Dreamfinder leaves, a fresh agent-*
      // arrives, and the player never moved.
      final signal = build();
      signal.update(playerGrid: const Point(10, 10), territory: box);
      await pumpEventQueue();

      signal.reset(); // DF left; the room survives
      await pumpEventQueue();
      expect(signal.isNear, isFalse);

      // New agent, same square, same standing player.
      signal.update(playerGrid: const Point(10, 10), territory: box);
      await pumpEventQueue();
      expect(signal.isNear, isTrue);
      verify(() => service.publishDfProximity(near: true)).called(2);
    });
  });

  group('publish failure must not latch (cage-match #530, findings 1+2)', () {
    // RED-PROVING INTENT: against the pre-fix code every test in this group
    // fails. `update` latched `_wasInside` and then called the async publish
    // unawaited, so a rejected publish consumed the transition locally and it
    // never re-fired — the "signal lost forever" bug the file's own invariant
    // names, escaping through the one door the `service == null` guard did
    // not cover.

    test('a failed publish leaves the transition un-latched so it retries',
        () async {
      when(() => service.publishDfProximity(near: any(named: 'near')))
          .thenAnswer((_) async => throw StateError('data channel gone'));

      final signal = build();
      signal.update(playerGrid: const Point(10, 10), territory: box);
      await pumpEventQueue();

      // The publish was attempted...
      verify(() => service.publishDfProximity(near: true)).called(1);
      // ...but it failed, so the signal must NOT believe the bot knows.
      expect(signal.isNear, isFalse,
          reason: 'a rejected publish must un-latch, or the enter is lost '
              'forever and Dreamfinder never hears this player');

      // Next frame, still inside: the transition must fire AGAIN.
      when(() => service.publishDfProximity(near: any(named: 'near')))
          .thenAnswer((_) async {});
      signal.update(playerGrid: const Point(10, 10), territory: box);
      await pumpEventQueue();

      verify(() => service.publishDfProximity(near: true)).called(1);
      expect(signal.isNear, isTrue);
    });

    test('a successful publish still latches exactly once', () async {
      // NULL ARM: the failure path must not make the healthy path chatty.
      final signal = build();
      signal.update(playerGrid: const Point(10, 10), territory: box);
      await pumpEventQueue();
      signal.update(playerGrid: const Point(11, 11), territory: box);
      await pumpEventQueue();

      verify(() => service.publishDfProximity(near: true)).called(1);
      expect(signal.isNear, isTrue);
    });

    test('a failed teardown exit re-latches so a later update can resend',
        () async {
      final signal = build();
      signal.update(playerGrid: const Point(10, 10), territory: box);
      await pumpEventQueue();
      expect(signal.isNear, isTrue);

      when(() => service.publishDfProximity(near: any(named: 'near')))
          .thenAnswer((_) async => throw StateError('leaving'));
      signal.reset();
      await pumpEventQueue();

      expect(signal.isNear, isTrue,
          reason: 'if the exit never reached the bot, the cleared local state '
              'must not claim it did — the bot still holds near:true');
    });

    test('a failed NO-OP exit must not invent a near:true that never was',
        () async {
      // Round-2 finding: restoring a blind `true` on reset failure was wrong.
      // When the last published state was already outside, this exit is a
      // no-op — and a failed no-op would mint a `near: true` that was never
      // published, making isNear lie and letting a later update emit a
      // spurious exit.
      when(() => service.publishDfProximity(near: any(named: 'near')))
          .thenAnswer((_) async => throw StateError('never connected'));

      final signal = build();
      expect(signal.isNear, isFalse);

      signal.reset();
      await pumpEventQueue();

      expect(signal.isNear, isFalse,
          reason: 'nothing was ever published as near:true, so a failed '
              'no-op exit must leave the state at false');
    });
  });

  group('radius 0 is the kill switch (cage-match #530, Tesla)', () {
    // Tesla's conjunction: the radius preference OWNS the gate, territory
    // NARROWS within it. Before this, a player who set "Proximity range" to 0
    // still had Dreamfinder hearing them while they stood on his square — no
    // bubble, no audio, and no way to know the bot was listening.

    test('radius 0: standing dead centre is never heard', () {
      final signal = build(proximityRadius: 0);
      signal.update(playerGrid: const Point(10, 10), territory: box);
      verifyNever(
          () => service.publishDfProximity(near: any(named: 'near')));
      expect(signal.isNear, isFalse);
    });

    test('radius 0 forces an exit for someone already inside', () async {
      // The preference is applied at room entry, but the gate must be a
      // function of the CURRENT value, not of how we got here.
      var radius = 5;
      final signal = DreamfinderProximitySignal(
        liveKitService: () => service,
        proximityRadius: () => radius,
      );
      signal.update(playerGrid: const Point(10, 10), territory: box);
      await pumpEventQueue();
      verify(() => service.publishDfProximity(near: true)).called(1);

      radius = 0;
      signal.update(playerGrid: const Point(10, 10), territory: box);
      await pumpEventQueue();
      verify(() => service.publishDfProximity(near: false)).called(1);
      expect(signal.isNear, isFalse);
    });

    test('NULL ARM: a non-zero radius still defers to territory', () {
      // The radius must not become a DISTANCE test — comparing it to distance
      // is the coupling PR #529 removed, and would re-open the
      // heard-from-outside-the-box bug.
      final signal = build(proximityRadius: 5);
      // One cell outside the box, well within a radius of 5.
      signal.update(playerGrid: const Point(14, 10), territory: box);
      verifyNever(
          () => service.publishDfProximity(near: any(named: 'near')));
      // Inside the box: heard.
      signal.update(playerGrid: const Point(13, 10), territory: box);
      verify(() => service.publishDfProximity(near: true)).called(1);
    });
  });
}
