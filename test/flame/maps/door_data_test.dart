import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/maps/door_data.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';

void main() {
  group('DoorData', () {
    test('serializes to JSON without challenges', () {
      final door = DoorData(position: const Point(5, 10));
      final json = door.toJson();

      expect(json['x'], 5);
      expect(json['y'], 10);
      expect(json.containsKey('challenges'), isFalse);
    });

    test('serializes to JSON with challenges (uses wireName)', () {
      final door = DoorData(
        position: const Point(3, 7),
        requiredChallengeIds: const [
          PromptChallengeId.evocationFizzbuzz,
          PromptChallengeId.divinationColor,
        ],
      );
      final json = door.toJson();

      expect(json['x'], 3);
      expect(json['y'], 7);
      expect(json['challenges'], ['evocation_fizzbuzz', 'divination_color']);
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
        'challenges': ['evocation_fizzbuzz', 'divination_color'],
      });

      expect(door.position, const Point(3, 7));
      expect(door.requiredChallengeIds, [
        PromptChallengeId.evocationFizzbuzz,
        PromptChallengeId.divinationColor,
      ]);
    });

    test('round-trips through JSON', () {
      final original = DoorData(
        position: const Point(12, 24),
        requiredChallengeIds: const [PromptChallengeId.evocationDiamond],
      );
      final restored = DoorData.fromJson(original.toJson());

      expect(restored.position, original.position);
      expect(
        restored.requiredChallengeIds,
        original.requiredChallengeIds,
      );
    });

    test('silently skips unknown challenge wire forms (forward-compat)', () {
      // An older client opens a save written by a newer one. The unknown
      // challenge name shouldn't break door loading.
      final door = DoorData.fromJson({
        'x': 1,
        'y': 1,
        'challenges': ['evocation_fizzbuzz', 'future_challenge_xyz'],
      });

      expect(door.requiredChallengeIds, [
        PromptChallengeId.evocationFizzbuzz,
      ]);
    });

    test('equality works', () {
      final a = DoorData(
        position: const Point(1, 2),
        requiredChallengeIds: const [PromptChallengeId.evocationFizzbuzz],
      );
      final b = DoorData(
        position: const Point(1, 2),
        requiredChallengeIds: const [PromptChallengeId.evocationFizzbuzz],
      );
      final c = DoorData(
        position: const Point(3, 4),
        requiredChallengeIds: const [PromptChallengeId.evocationFizzbuzz],
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, b.hashCode);
    });
  });
}
