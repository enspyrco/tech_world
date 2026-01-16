import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';

void main() {
  group('BotBubbleComponent', () {
    test('stores name correctly', () {
      final component = BotBubbleComponent(name: 'Claude');

      expect(component.name, equals('Claude'));
    });

    test('uses default bubble size of 80', () {
      final component = BotBubbleComponent(name: 'Claude');

      expect(component.bubbleSize, equals(80));
      expect(component.size, equals(Vector2.all(80)));
    });

    test('respects custom bubble size', () {
      final component = BotBubbleComponent(name: 'Claude', bubbleSize: 100);

      expect(component.bubbleSize, equals(100));
      expect(component.size, equals(Vector2.all(100)));
    });

    test('has bottomCenter anchor for positioning above player', () {
      final component = BotBubbleComponent(name: 'Claude');

      expect(component.anchor, equals(Anchor.bottomCenter));
    });

    test('handles empty name gracefully', () {
      final component = BotBubbleComponent(name: '');

      expect(component.name, isEmpty);
    });

    test('is larger than PlayerBubbleComponent by default', () {
      final botBubble = BotBubbleComponent(name: 'Claude');

      // Bot bubble default is 80, player bubble default is 48
      expect(botBubble.bubbleSize, equals(80));
      expect(botBubble.bubbleSize, greaterThan(48));
    });
  });
}
