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

  DreamfinderProximitySignal build({bool withService = true}) =>
      DreamfinderProximitySignal(
        liveKitService: () => withService ? service : null,
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

    test('stepping over the edge flips exactly once each way', () {
      final signal = build();
      signal.update(playerGrid: const Point(14, 10), territory: box); // out
      signal.update(playerGrid: const Point(13, 10), territory: box); // in
      signal.update(playerGrid: const Point(12, 10), territory: box); // deeper
      signal.update(playerGrid: const Point(14, 10), territory: box); // out
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
    test('a null territory (DF absent) exits a player who was inside', () {
      final signal = build();
      signal.update(playerGrid: const Point(10, 10), territory: box);
      signal.update(playerGrid: const Point(10, 10), territory: null);
      expect(signal.isNear, isFalse);
      verify(() => service.publishDfProximity(near: false)).called(1);
    });

    test('a null playerGrid (no local player) exits too', () {
      final signal = build();
      signal.update(playerGrid: const Point(10, 10), territory: box);
      signal.update(playerGrid: null, territory: box);
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
      );
      signal.update(playerGrid: const Point(10, 10), territory: box);
      verifyNever(() => service.publishDfProximity(near: any(named: 'near')));
      present = true;
      signal.update(playerGrid: const Point(10, 10), territory: box);
      verify(() => service.publishDfProximity(near: true)).called(1);
    });
  });

  group('reset', () {
    test('publishes an unconditional exit for a player who leaves', () {
      final signal = build();
      signal.update(playerGrid: const Point(10, 10), territory: box);
      signal.reset();
      expect(signal.isNear, isFalse);
      verify(() => service.publishDfProximity(near: false)).called(1);
    });

    test('exits even when never near — the bot may hold stale state', () {
      build().reset();
      verify(() => service.publishDfProximity(near: false)).called(1);
    });
  });
}
