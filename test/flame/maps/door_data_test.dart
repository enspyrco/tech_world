import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/door_data.dart';

void main() {
  group('DoorData', () {
    test('serializes to JSON without challenges', () {
      final door = DoorData(position: const Point(5, 10));
      final json = door.toJson();

      expect(json['x'], 5);
      expect(json['y'], 10);
      expect(json.containsKey('challenges'), isFalse);
    });

    test('serializes to JSON with challenges', () {
      final door = DoorData(
        position: const Point(3, 7),
        requiredChallengeIds: ['fizzbuzz', 'palindrome'],
      );
      final json = door.toJson();

      expect(json['x'], 3);
      expect(json['y'], 7);
      expect(json['challenges'], ['fizzbuzz', 'palindrome']);
    });

    test('deserializes from JSON without challenges', () {
      final door = DoorData.fromJson({'x': 5, 'y': 10});

      expect(door.position, const Point(5, 10));
      expect(door.requiredChallengeIds, isEmpty);
      expect(door.isUnlocked, isFalse);
    });

    test('deserializes from JSON with challenges', () {
      final door = DoorData.fromJson({
        'x': 3,
        'y': 7,
        'challenges': ['fizzbuzz', 'palindrome'],
      });

      expect(door.position, const Point(3, 7));
      expect(door.requiredChallengeIds, ['fizzbuzz', 'palindrome']);
    });

    test('round-trips through JSON', () {
      final original = DoorData(
        position: const Point(12, 24),
        requiredChallengeIds: ['hello_dart'],
      );
      final restored = DoorData.fromJson(original.toJson());

      expect(restored.position, original.position);
      expect(
        restored.requiredChallengeIds,
        original.requiredChallengeIds,
      );
    });

    test('equality works', () {
      final a = DoorData(
        position: const Point(1, 2),
        requiredChallengeIds: ['a'],
      );
      final b = DoorData(
        position: const Point(1, 2),
        requiredChallengeIds: ['a'],
      );
      final c = DoorData(
        position: const Point(3, 4),
        requiredChallengeIds: ['a'],
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, b.hashCode);
    });
  });
}
