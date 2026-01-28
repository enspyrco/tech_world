import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/bot_status.dart';

void main() {
  group('BotBubbleComponent', () {
    setUp(() {
      // Reset bot status before each test
      botStatusNotifier.value = BotStatus.idle;
    });

    test('uses default bubble size of 48', () {
      final component = BotBubbleComponent();

      expect(component.bubbleSize, equals(48));
      expect(component.size, equals(Vector2.all(48)));
    });

    test('respects custom bubble size', () {
      final component = BotBubbleComponent(bubbleSize: 64);

      expect(component.bubbleSize, equals(64));
      expect(component.size, equals(Vector2.all(64)));
    });

    test('has bottomCenter anchor for positioning above player', () {
      final component = BotBubbleComponent();

      expect(component.anchor, equals(Anchor.bottomCenter));
    });

    test('clawdOrange constant is correct', () {
      expect(BotBubbleComponent.clawdOrange.toARGB32(), equals(0xFFD97757));
    });
  });

  group('BotStatus', () {
    test('botStatusNotifier defaults to idle', () {
      // Create new notifier to test default
      final notifier = ValueNotifier<BotStatus>(BotStatus.idle);

      expect(notifier.value, equals(BotStatus.idle));
    });

    test('can change to thinking status', () {
      botStatusNotifier.value = BotStatus.thinking;

      expect(botStatusNotifier.value, equals(BotStatus.thinking));
    });

    test('can change back to idle status', () {
      botStatusNotifier.value = BotStatus.thinking;
      botStatusNotifier.value = BotStatus.idle;

      expect(botStatusNotifier.value, equals(BotStatus.idle));
    });
  });
}
