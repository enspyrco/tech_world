import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/prompt/spell_slot_service.dart';

void main() {
  group('SpellSlotService', () {
    group('initial state', () {
      test('starts with max slots available', () {
        final service = SpellSlotService(maxSlots: 3);
        addTearDown(service.dispose);

        expect(service.availableSlots, 3);
        expect(service.maxSlots, 3);
        expect(service.canCast, isTrue);
      });

      test('timeUntilNextRegen is null when full', () {
        final service = SpellSlotService();
        addTearDown(service.dispose);

        expect(service.timeUntilNextRegen, isNull);
      });
    });

    group('consumeSlot', () {
      test('decrements available slots and returns true', () {
        final service = SpellSlotService(maxSlots: 3);
        addTearDown(service.dispose);

        expect(service.consumeSlot(), isTrue);
        expect(service.availableSlots, 2);
      });

      test('returns false when no slots available', () {
        final service = SpellSlotService(maxSlots: 1);
        addTearDown(service.dispose);

        expect(service.consumeSlot(), isTrue);
        expect(service.consumeSlot(), isFalse);
        expect(service.availableSlots, 0);
      });

      test('consumes multiple slots when cost > 1', () {
        final service = SpellSlotService(maxSlots: 4);
        addTearDown(service.dispose);

        expect(service.consumeSlot(cost: 2), isTrue);
        expect(service.availableSlots, 2);
      });

      test('fails when cost exceeds available slots', () {
        final service = SpellSlotService(maxSlots: 3);
        addTearDown(service.dispose);

        service.consumeSlot(); // 2 left
        expect(service.consumeSlot(cost: 3), isFalse);
        expect(service.availableSlots, 2);
      });

      test('notifies listeners on consume', () {
        final service = SpellSlotService(maxSlots: 3);
        addTearDown(service.dispose);

        var notified = false;
        service.addListener(() => notified = true);
        service.consumeSlot();

        expect(notified, isTrue);
      });
    });

    group('canCast', () {
      test('true when slots available', () {
        final service = SpellSlotService(maxSlots: 1);
        addTearDown(service.dispose);

        expect(service.canCast, isTrue);
      });

      test('false when empty', () {
        final service = SpellSlotService(maxSlots: 1);
        addTearDown(service.dispose);

        service.consumeSlot();
        expect(service.canCast, isFalse);
      });
    });

    group('regeneration', () {
      test('regenerates a slot after the interval', () {
        FakeAsync().run((async) {
          final service = SpellSlotService(
            maxSlots: 3,
            regenInterval: const Duration(minutes: 3),
            clock: () => async.getClock(DateTime(2026)).now(),
          );
          addTearDown(service.dispose);

          service.consumeSlot(); // 2 left
          expect(service.availableSlots, 2);

          async.elapse(const Duration(minutes: 3));
          expect(service.availableSlots, 3);
        });
      });

      test('notifies listeners on regen', () {
        FakeAsync().run((async) {
          final service = SpellSlotService(
            maxSlots: 2,
            regenInterval: const Duration(seconds: 10),
            clock: () => async.getClock(DateTime(2026)).now(),
          );
          addTearDown(service.dispose);

          service.consumeSlot();

          var notifyCount = 0;
          service.addListener(() => notifyCount++);

          async.elapse(const Duration(seconds: 10));
          expect(notifyCount, 1);
        });
      });

      test('stops regenerating at max slots', () {
        FakeAsync().run((async) {
          final service = SpellSlotService(
            maxSlots: 2,
            regenInterval: const Duration(seconds: 5),
            clock: () => async.getClock(DateTime(2026)).now(),
          );
          addTearDown(service.dispose);

          service.consumeSlot(); // 1 left

          async.elapse(const Duration(seconds: 5)); // back to 2
          expect(service.availableSlots, 2);

          // Wait another interval — should stay at 2, not go to 3.
          async.elapse(const Duration(seconds: 5));
          expect(service.availableSlots, 2);
        });
      });

      test('regenerates multiple slots over time', () {
        FakeAsync().run((async) {
          final service = SpellSlotService(
            maxSlots: 3,
            regenInterval: const Duration(seconds: 10),
            clock: () => async.getClock(DateTime(2026)).now(),
          );
          addTearDown(service.dispose);

          service.consumeSlot();
          service.consumeSlot(); // 1 left

          async.elapse(const Duration(seconds: 10)); // 2
          expect(service.availableSlots, 2);

          async.elapse(const Duration(seconds: 10)); // 3 (full)
          expect(service.availableSlots, 3);
        });
      });

      test('timeUntilNextRegen returns remaining time', () {
        FakeAsync().run((async) {
          final service = SpellSlotService(
            maxSlots: 3,
            regenInterval: const Duration(minutes: 3),
            clock: () => async.getClock(DateTime(2026)).now(),
          );
          addTearDown(service.dispose);

          service.consumeSlot();

          async.elapse(const Duration(minutes: 1));
          final remaining = service.timeUntilNextRegen;
          expect(remaining, isNotNull);
          expect(remaining!.inMinutes, 2);
        });
      });
    });

    group('progression scaling', () {
      test('adds max slots every 3 challenges', () {
        final service = SpellSlotService(maxSlots: 3);
        addTearDown(service.dispose);

        service.updateProgression(
          challengesCompleted: 6,
          baseMaxSlots: 3,
        );
        // 3 base + 2 bonus (6 ~/ 3) = 5
        expect(service.maxSlots, 5);
      });

      test('caps max slots at 7', () {
        final service = SpellSlotService(maxSlots: 3);
        addTearDown(service.dispose);

        service.updateProgression(
          challengesCompleted: 30,
          baseMaxSlots: 3,
        );
        expect(service.maxSlots, 7);
      });

      test('decreases regen interval every 5 challenges', () {
        final service = SpellSlotService(
          maxSlots: 3,
          regenInterval: const Duration(minutes: 3),
        );
        addTearDown(service.dispose);

        service.updateProgression(
          challengesCompleted: 5,
          baseMaxSlots: 3,
          baseRegenInterval: const Duration(minutes: 3),
        );
        // 180s - 30s = 150s
        expect(service.regenInterval.inSeconds, 150);
      });

      test('floors regen interval at 1 minute', () {
        final service = SpellSlotService(
          maxSlots: 3,
          regenInterval: const Duration(minutes: 3),
        );
        addTearDown(service.dispose);

        service.updateProgression(
          challengesCompleted: 50,
          baseMaxSlots: 3,
          baseRegenInterval: const Duration(minutes: 3),
        );
        expect(service.regenInterval.inSeconds, 60);
      });

      test('notifies listeners on progression update', () {
        final service = SpellSlotService(maxSlots: 3);
        addTearDown(service.dispose);

        var notified = false;
        service.addListener(() => notified = true);
        service.updateProgression(
          challengesCompleted: 3,
          baseMaxSlots: 3,
        );
        expect(notified, isTrue);
      });
    });

    group('serialization', () {
      test('round-trip preserves state', () {
        final now = DateTime.utc(2026, 4, 21, 8);
        final service = SpellSlotService(
          maxSlots: 4,
          regenInterval: const Duration(minutes: 2),
          clock: () => now,
        );
        addTearDown(service.dispose);

        service.consumeSlot(); // 3 left
        service.updateProgression(
          challengesCompleted: 6,
          baseMaxSlots: 4,
          baseRegenInterval: const Duration(minutes: 2),
        );

        final json = service.toJson();
        final restored = SpellSlotService.fromJson(json, clock: () => now);
        addTearDown(restored.dispose);

        expect(restored.availableSlots, service.availableSlots);
        expect(restored.maxSlots, service.maxSlots);
        expect(restored.regenInterval, service.regenInterval);
        expect(restored.challengesCompleted, service.challengesCompleted);
      });

      test('offline regen applies on restore', () {
        final savedAt = DateTime.utc(2026, 4, 21, 8);
        // 10 minutes later — should regen 3 slots at 3-minute interval.
        final restoredAt = savedAt.add(const Duration(minutes: 10));

        final json = {
          'availableSlots': 1,
          'maxSlots': 5,
          'regenIntervalSeconds': 180,
          'lastRegenAt': savedAt.toIso8601String(),
          'challengesCompleted': 3,
        };

        final service =
            SpellSlotService.fromJson(json, clock: () => restoredAt);
        addTearDown(service.dispose);

        // 1 + (600s ~/ 180s = 3) = 4
        expect(service.availableSlots, 4);
      });

      test('offline regen does not exceed max', () {
        final savedAt = DateTime.utc(2026, 4, 21, 8);
        final restoredAt = savedAt.add(const Duration(hours: 1));

        final json = {
          'availableSlots': 2,
          'maxSlots': 3,
          'regenIntervalSeconds': 60,
          'lastRegenAt': savedAt.toIso8601String(),
          'challengesCompleted': 0,
        };

        final service =
            SpellSlotService.fromJson(json, clock: () => restoredAt);
        addTearDown(service.dispose);

        expect(service.availableSlots, 3);
      });

      test('no lastRegenAt means no offline regen', () {
        final json = {
          'availableSlots': 1,
          'maxSlots': 3,
          'regenIntervalSeconds': 180,
          'lastRegenAt': null,
          'challengesCompleted': 0,
        };

        final service = SpellSlotService.fromJson(json);
        addTearDown(service.dispose);

        expect(service.availableSlots, 1);
      });

      test('toJson includes all fields', () {
        final now = DateTime.utc(2026, 4, 21, 8);
        final service = SpellSlotService(
          maxSlots: 3,
          regenInterval: const Duration(minutes: 3),
          clock: () => now,
        );
        addTearDown(service.dispose);

        service.consumeSlot();

        final json = service.toJson();
        expect(json, containsPair('availableSlots', 2));
        expect(json, containsPair('maxSlots', 3));
        expect(json, containsPair('regenIntervalSeconds', 180));
        expect(json, containsPair('lastRegenAt', now.toIso8601String()));
        expect(json, containsPair('challengesCompleted', 0));
      });
    });

    group('dispose', () {
      test('cancels regen timer', () {
        FakeAsync().run((async) {
          final service = SpellSlotService(
            maxSlots: 2,
            regenInterval: const Duration(seconds: 5),
            clock: () => async.getClock(DateTime(2026)).now(),
          );

          service.consumeSlot(); // starts timer
          service.dispose();

          // Timer should be cancelled — no regen.
          async.elapse(const Duration(seconds: 10));
          expect(service.availableSlots, 1);
        });
      });
    });
  });
}
