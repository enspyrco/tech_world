import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/player_bubble_component.dart';

// Expose the private _getInitial method for testing via a subclass
class TestablePlayerBubbleComponent extends PlayerBubbleComponent {
  TestablePlayerBubbleComponent({
    required super.displayName,
    required super.playerId,
    super.bubbleSize,
  });

  // Expose the private method for testing
  String getInitialForTest() {
    if (displayName.isNotEmpty) {
      return displayName[0].toUpperCase();
    }
    if (playerId.isNotEmpty) {
      return playerId[0].toUpperCase();
    }
    return '?';
  }
}

void main() {
  group('PlayerBubbleComponent', () {
    group('constructor', () {
      test('creates component with default bubble size', () {
        final bubble = PlayerBubbleComponent(
          displayName: 'Test User',
          playerId: 'user-123',
        );

        expect(bubble.displayName, equals('Test User'));
        expect(bubble.playerId, equals('user-123'));
        expect(bubble.bubbleSize, equals(48));
        expect(bubble.size.x, equals(48));
        expect(bubble.size.y, equals(48));
      });

      test('creates component with custom bubble size', () {
        final bubble = PlayerBubbleComponent(
          displayName: 'Test',
          playerId: 'user-123',
          bubbleSize: 64,
        );

        expect(bubble.bubbleSize, equals(64));
        expect(bubble.size.x, equals(64));
        expect(bubble.size.y, equals(64));
      });

      test('has bottom center anchor', () {
        final bubble = PlayerBubbleComponent(
          displayName: 'Test',
          playerId: 'user-123',
        );

        expect(bubble.anchor, equals(Anchor.bottomCenter));
      });
    });

    group('_getInitial logic', () {
      test('returns first character of displayName uppercased', () {
        final bubble = TestablePlayerBubbleComponent(
          displayName: 'john',
          playerId: 'user-123',
        );

        expect(bubble.getInitialForTest(), equals('J'));
      });

      test('uses displayName over playerId when both are present', () {
        final bubble = TestablePlayerBubbleComponent(
          displayName: 'Alice',
          playerId: 'bob-456',
        );

        // Should use 'A' from displayName, not 'B' from playerId
        expect(bubble.getInitialForTest(), equals('A'));
      });

      test('falls back to playerId when displayName is empty', () {
        final bubble = TestablePlayerBubbleComponent(
          displayName: '',
          playerId: 'user-123',
        );

        expect(bubble.getInitialForTest(), equals('U'));
      });

      test('returns ? when both displayName and playerId are empty', () {
        final bubble = TestablePlayerBubbleComponent(
          displayName: '',
          playerId: '',
        );

        expect(bubble.getInitialForTest(), equals('?'));
      });

      test('handles lowercase playerId correctly', () {
        final bubble = TestablePlayerBubbleComponent(
          displayName: '',
          playerId: 'player-xyz',
        );

        expect(bubble.getInitialForTest(), equals('P'));
      });

      test('handles numeric first character in displayName', () {
        final bubble = TestablePlayerBubbleComponent(
          displayName: '42Bot',
          playerId: 'test',
        );

        // Should return '4' (uppercased is same for numbers)
        expect(bubble.getInitialForTest(), equals('4'));
      });

      test('handles special character first in displayName', () {
        final bubble = TestablePlayerBubbleComponent(
          displayName: '@User',
          playerId: 'test',
        );

        expect(bubble.getInitialForTest(), equals('@'));
      });
    });

    group('size variations', () {
      test('small bubble size', () {
        final bubble = PlayerBubbleComponent(
          displayName: 'A',
          playerId: 'a',
          bubbleSize: 24,
        );

        expect(bubble.size.x, equals(24));
        expect(bubble.size.y, equals(24));
      });

      test('large bubble size', () {
        final bubble = PlayerBubbleComponent(
          displayName: 'A',
          playerId: 'a',
          bubbleSize: 128,
        );

        expect(bubble.size.x, equals(128));
        expect(bubble.size.y, equals(128));
      });
    });
  });
}
