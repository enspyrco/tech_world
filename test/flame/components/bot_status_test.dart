import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/bot_status.dart';

void main() {
  group('BotStatus', () {
    test('has idle status', () {
      expect(BotStatus.idle, isNotNull);
      expect(BotStatus.idle.name, equals('idle'));
    });

    test('has thinking status', () {
      expect(BotStatus.thinking, isNotNull);
      expect(BotStatus.thinking.name, equals('thinking'));
    });

    test('has absent status', () {
      expect(BotStatus.absent, isNotNull);
      expect(BotStatus.absent.name, equals('absent'));
    });

    test('has exactly 3 values', () {
      expect(BotStatus.values.length, equals(3));
    });

    test('values are unique', () {
      final uniqueValues = BotStatus.values.toSet();
      expect(uniqueValues.length, equals(BotStatus.values.length));
    });
  });

  group('botStatusNotifier', () {
    setUp(() {
      // Reset to idle before each test
      botStatusNotifier.value = BotStatus.idle;
    });

    test('is a ValueNotifier', () {
      expect(botStatusNotifier, isA<ValueNotifier<BotStatus>>());
    });

    test('initial value is idle', () {
      // Reset and check
      botStatusNotifier.value = BotStatus.idle;
      expect(botStatusNotifier.value, equals(BotStatus.idle));
    });

    test('can set value to thinking', () {
      botStatusNotifier.value = BotStatus.thinking;
      expect(botStatusNotifier.value, equals(BotStatus.thinking));
    });

    test('can toggle between idle and thinking', () {
      expect(botStatusNotifier.value, equals(BotStatus.idle));

      botStatusNotifier.value = BotStatus.thinking;
      expect(botStatusNotifier.value, equals(BotStatus.thinking));

      botStatusNotifier.value = BotStatus.idle;
      expect(botStatusNotifier.value, equals(BotStatus.idle));
    });

    test('notifies listeners on value change', () {
      int notifyCount = 0;
      void listener() {
        notifyCount++;
      }

      botStatusNotifier.addListener(listener);
      expect(notifyCount, equals(0));

      botStatusNotifier.value = BotStatus.thinking;
      expect(notifyCount, equals(1));

      botStatusNotifier.value = BotStatus.idle;
      expect(notifyCount, equals(2));

      botStatusNotifier.removeListener(listener);
    });

    test('does not notify when setting same value', () {
      botStatusNotifier.value = BotStatus.idle;

      int notifyCount = 0;
      void listener() {
        notifyCount++;
      }

      botStatusNotifier.addListener(listener);

      // Setting the same value should not notify
      botStatusNotifier.value = BotStatus.idle;
      expect(notifyCount, equals(0));

      botStatusNotifier.removeListener(listener);
    });

    test('multiple listeners are notified', () {
      int listener1Count = 0;
      int listener2Count = 0;

      void listener1() => listener1Count++;
      void listener2() => listener2Count++;

      botStatusNotifier.addListener(listener1);
      botStatusNotifier.addListener(listener2);

      botStatusNotifier.value = BotStatus.thinking;

      expect(listener1Count, equals(1));
      expect(listener2Count, equals(1));

      botStatusNotifier.removeListener(listener1);
      botStatusNotifier.removeListener(listener2);
    });
  });
}
