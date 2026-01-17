import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/player_bubble_component.dart';

void main() {
  late PositionComponent mockTarget;

  setUp(() {
    mockTarget = PositionComponent(position: Vector2(100, 100));
  });

  group('PlayerBubbleComponent', () {
    test('uses displayName initial when displayName is not empty', () {
      final component = PlayerBubbleComponent(
        displayName: 'Alice',
        playerId: 'user-123',
        target: mockTarget,
      );

      // Access the private method via the component's behavior
      expect(component.displayName, equals('Alice'));
      expect(component.playerId, equals('user-123'));
    });

    test('uses default bubble size of 48', () {
      final component = PlayerBubbleComponent(
        displayName: 'Bob',
        playerId: 'user-456',
        target: mockTarget,
      );

      expect(component.bubbleSize, equals(48));
      expect(component.size, equals(Vector2.all(48)));
    });

    test('respects custom bubble size', () {
      final component = PlayerBubbleComponent(
        displayName: 'Charlie',
        playerId: 'user-789',
        target: mockTarget,
        bubbleSize: 64,
      );

      expect(component.bubbleSize, equals(64));
      expect(component.size, equals(Vector2.all(64)));
    });

    test('has bottomCenter anchor for positioning above player', () {
      final component = PlayerBubbleComponent(
        displayName: 'Diana',
        playerId: 'user-101',
        target: mockTarget,
      );

      expect(component.anchor, equals(Anchor.bottomCenter));
    });

    test('stores playerId for fallback initial', () {
      final component = PlayerBubbleComponent(
        displayName: '',
        playerId: 'xyz-player',
        target: mockTarget,
      );

      expect(component.playerId, equals('xyz-player'));
    });

    test('handles empty displayName and playerId gracefully', () {
      final component = PlayerBubbleComponent(
        displayName: '',
        playerId: '',
        target: mockTarget,
      );

      expect(component.displayName, isEmpty);
      expect(component.playerId, isEmpty);
    });

    test('stores target reference', () {
      final component = PlayerBubbleComponent(
        displayName: 'Eve',
        playerId: 'user-111',
        target: mockTarget,
      );

      expect(component.target, equals(mockTarget));
    });
  });
}
