import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/bot_status.dart';

void main() {
  group('BotBubbleComponent', () {
    late ValueNotifier<BotStatus> testStatus;

    setUp(() {
      testStatus = ValueNotifier(BotStatus.idle);
    });

    tearDown(() {
      testStatus.dispose();
    });

    test('uses default bubble size of 48', () {
      final component = BotBubbleComponent(botStatus: testStatus);

      expect(component.bubbleSize, equals(48));
      expect(component.size, equals(Vector2.all(48)));
    });

    test('respects custom bubble size', () {
      final component = BotBubbleComponent(
        botStatus: testStatus,
        bubbleSize: 64,
      );

      expect(component.bubbleSize, equals(64));
      expect(component.size, equals(Vector2.all(64)));
    });

    test('has bottomCenter anchor for positioning above player', () {
      final component = BotBubbleComponent(botStatus: testStatus);

      expect(component.anchor, equals(Anchor.bottomCenter));
    });

    test('clawdOrange constant is correct', () {
      expect(BotBubbleComponent.clawdOrange.toARGB32(), equals(0xFFD97757));
    });
  });

  group('BotStatus', () {
    test('ValueNotifier defaults correctly', () {
      final notifier = ValueNotifier<BotStatus>(BotStatus.idle);
      expect(notifier.value, equals(BotStatus.idle));
      notifier.dispose();
    });

    test('can change to thinking status', () {
      final notifier = ValueNotifier<BotStatus>(BotStatus.idle);
      notifier.value = BotStatus.thinking;
      expect(notifier.value, equals(BotStatus.thinking));
      notifier.dispose();
    });

    test('can change back to idle status', () {
      final notifier = ValueNotifier<BotStatus>(BotStatus.idle);
      notifier.value = BotStatus.thinking;
      notifier.value = BotStatus.idle;
      expect(notifier.value, equals(BotStatus.idle));
      notifier.dispose();
    });
  });
}
