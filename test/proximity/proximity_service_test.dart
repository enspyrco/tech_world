import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/proximity/proximity_service.dart';

void main() {
  group('ProximityService', () {
    late ProximityService service;

    setUp(() {
      service = ProximityService(proximityThreshold: 3);
    });

    tearDown(() {
      service.dispose();
    });

    test('emits event when player enters proximity', () async {
      final events = <ProximityEvent>[];
      service.proximityEvents.listen(events.add);

      service.checkProximity(
        localPlayerPosition: const Point(5, 5),
        otherPlayerPositions: {'player1': const Point(6, 6)},
      );

      await Future.delayed(Duration.zero);

      expect(events.length, equals(1));
      expect(events[0].playerId, equals('player1'));
      expect(events[0].isNearby, isTrue);
    });

    test('emits event when player exits proximity', () async {
      final events = <ProximityEvent>[];
      service.proximityEvents.listen(events.add);

      // First, player enters proximity
      service.checkProximity(
        localPlayerPosition: const Point(5, 5),
        otherPlayerPositions: {'player1': const Point(6, 6)},
      );

      // Then, player moves out of range
      service.checkProximity(
        localPlayerPosition: const Point(5, 5),
        otherPlayerPositions: {'player1': const Point(20, 20)},
      );

      await Future.delayed(Duration.zero);

      expect(events.length, equals(2));
      expect(events[1].playerId, equals('player1'));
      expect(events[1].isNearby, isFalse);
    });

    test('does not emit duplicate events for same state', () async {
      final events = <ProximityEvent>[];
      service.proximityEvents.listen(events.add);

      // Check proximity twice with same nearby state
      service.checkProximity(
        localPlayerPosition: const Point(5, 5),
        otherPlayerPositions: {'player1': const Point(6, 6)},
      );
      service.checkProximity(
        localPlayerPosition: const Point(5, 5),
        otherPlayerPositions: {'player1': const Point(7, 7)},
      );

      await Future.delayed(Duration.zero);

      // Should only emit once for entering proximity
      expect(events.length, equals(1));
    });

    test('uses Chebyshev distance (diagonal counts as 1)', () async {
      final events = <ProximityEvent>[];
      service.proximityEvents.listen(events.add);

      // Player at diagonal distance of 3 (within threshold)
      service.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'player1': const Point(3, 3)},
      );

      await Future.delayed(Duration.zero);

      expect(events.length, equals(1));
      expect(events[0].isNearby, isTrue);
    });

    test('player at threshold + 1 is not nearby', () async {
      final events = <ProximityEvent>[];
      service.proximityEvents.listen(events.add);

      // Player at distance of 4 (outside threshold of 3)
      service.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'player1': const Point(4, 0)},
      );

      await Future.delayed(Duration.zero);

      // No event should be emitted for player already out of range
      expect(events, isEmpty);
    });

    test('handles player leaving the game', () async {
      final events = <ProximityEvent>[];
      service.proximityEvents.listen(events.add);

      // Player enters proximity
      service.checkProximity(
        localPlayerPosition: const Point(5, 5),
        otherPlayerPositions: {'player1': const Point(6, 6)},
      );

      // Player leaves the game (no longer in map)
      service.checkProximity(
        localPlayerPosition: const Point(5, 5),
        otherPlayerPositions: {},
      );

      await Future.delayed(Duration.zero);

      expect(events.length, equals(2));
      expect(events[1].isNearby, isFalse);
    });

    test('tracks multiple players independently', () async {
      final events = <ProximityEvent>[];
      service.proximityEvents.listen(events.add);

      service.checkProximity(
        localPlayerPosition: const Point(5, 5),
        otherPlayerPositions: {
          'player1': const Point(6, 6),
          'player2': const Point(7, 7),
        },
      );

      await Future.delayed(Duration.zero);

      expect(events.length, equals(2));
      expect(events.map((e) => e.playerId), containsAll(['player1', 'player2']));
    });

    test('nearbyPlayers returns unmodifiable set', () {
      service.checkProximity(
        localPlayerPosition: const Point(5, 5),
        otherPlayerPositions: {'player1': const Point(6, 6)},
      );

      expect(service.nearbyPlayers, contains('player1'));
      expect(
        () => (service.nearbyPlayers as Set).add('hacker'),
        throwsUnsupportedError,
      );
    });

    test('custom proximity threshold is respected', () async {
      final customService = ProximityService(proximityThreshold: 1);
      final events = <ProximityEvent>[];
      customService.proximityEvents.listen(events.add);

      // Player at distance 2 (outside threshold of 1)
      customService.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'player1': const Point(2, 0)},
      );

      await Future.delayed(Duration.zero);

      expect(events, isEmpty);

      customService.dispose();
    });
  });
}
