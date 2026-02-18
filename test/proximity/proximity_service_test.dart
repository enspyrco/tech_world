import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/proximity/proximity_service.dart';

void main() {
  group('ProximityService', () {
    late ProximityService service;

    setUp(() {
      service = ProximityService(proximityThreshold: 5);
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
      expect(events[0].distance, equals(1));
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

    test('emits update events with distance when already nearby', () async {
      final events = <ProximityEvent>[];
      service.proximityEvents.listen(events.add);

      // Player enters proximity at distance 1
      service.checkProximity(
        localPlayerPosition: const Point(5, 5),
        otherPlayerPositions: {'player1': const Point(6, 6)},
      );

      // Player moves further but still within range (distance 3)
      service.checkProximity(
        localPlayerPosition: const Point(5, 5),
        otherPlayerPositions: {'player1': const Point(8, 8)},
      );

      await Future.delayed(Duration.zero);

      // Should emit enter event + update event with new distance
      expect(events.length, equals(2));
      expect(events[0].distance, equals(1));
      expect(events[1].distance, equals(3));
      expect(events[1].isNearby, isTrue);
    });

    test('uses Chebyshev distance (diagonal counts as 1)', () async {
      final events = <ProximityEvent>[];
      service.proximityEvents.listen(events.add);

      // Player at diagonal distance of 5 (within threshold)
      service.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'player1': const Point(5, 5)},
      );

      await Future.delayed(Duration.zero);

      expect(events.length, equals(1));
      expect(events[0].isNearby, isTrue);
      expect(events[0].distance, equals(5));
    });

    test('player at threshold + 1 is not nearby', () async {
      final events = <ProximityEvent>[];
      service.proximityEvents.listen(events.add);

      // Player at distance of 6 (outside threshold of 5)
      service.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'player1': const Point(6, 0)},
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
      expect(events[1].distance, equals(6)); // proximityThreshold + 1
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

    test('event includes correct distance', () async {
      final events = <ProximityEvent>[];
      service.proximityEvents.listen(events.add);

      service.checkProximity(
        localPlayerPosition: const Point(0, 0),
        otherPlayerPositions: {'player1': const Point(3, 2)},
      );

      await Future.delayed(Duration.zero);

      expect(events.length, equals(1));
      expect(events[0].distance, equals(3)); // Chebyshev = max(3, 2)
    });

    test('default threshold is 5', () {
      final defaultService = ProximityService();
      expect(defaultService.proximityThreshold, equals(5));
      defaultService.dispose();
    });
  });
}
