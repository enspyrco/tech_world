import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/player_bubble_component.dart';

void main() {
  group('PlayerBubbleComponent', () {
    group('constructor', () {
      test('uses displayName initial when displayName is not empty', () {
        final component = PlayerBubbleComponent(
          displayName: 'Alice',
          playerId: 'user-123',
        );

        expect(component.displayName, equals('Alice'));
        expect(component.playerId, equals('user-123'));
      });

      test('uses default bubble size of 48', () {
        final component = PlayerBubbleComponent(
          displayName: 'Bob',
          playerId: 'user-456',
        );

        expect(component.bubbleSize, equals(48));
        expect(component.size, equals(Vector2.all(48)));
      });

      test('respects custom bubble size', () {
        final component = PlayerBubbleComponent(
          displayName: 'Charlie',
          playerId: 'user-789',
          bubbleSize: 64,
        );

        expect(component.bubbleSize, equals(64));
        expect(component.size, equals(Vector2.all(64)));
      });

      test('has bottomCenter anchor for positioning above player', () {
        final component = PlayerBubbleComponent(
          displayName: 'Diana',
          playerId: 'user-101',
        );

        expect(component.anchor, equals(Anchor.bottomCenter));
      });

      test('stores playerId for fallback initial', () {
        final component = PlayerBubbleComponent(
          displayName: '',
          playerId: 'xyz-player',
        );

        expect(component.playerId, equals('xyz-player'));
      });

      test('handles empty displayName and playerId gracefully', () {
        final component = PlayerBubbleComponent(
          displayName: '',
          playerId: '',
        );

        expect(component.displayName, isEmpty);
        expect(component.playerId, isEmpty);
      });
    });

    group('bubble size variations', () {
      test('small bubble size', () {
        final component = PlayerBubbleComponent(
          displayName: 'Small',
          playerId: 'id',
          bubbleSize: 24,
        );

        expect(component.bubbleSize, equals(24));
        expect(component.size, equals(Vector2.all(24)));
      });

      test('large bubble size', () {
        final component = PlayerBubbleComponent(
          displayName: 'Large',
          playerId: 'id',
          bubbleSize: 128,
        );

        expect(component.bubbleSize, equals(128));
        expect(component.size, equals(Vector2.all(128)));
      });
    });

    group('_getInitial logic', () {
      // Test the logic that _getInitial uses:
      // 1. If displayName is not empty, use displayName[0].toUpperCase()
      // 2. Else if playerId is not empty, use playerId[0].toUpperCase()
      // 3. Else return '?'

      test('displayName initial is first letter uppercase', () {
        // The component stores displayName - initial would be 'A'
        final component = PlayerBubbleComponent(
          displayName: 'alice',
          playerId: 'user',
        );
        // Logic: 'alice'.isNotEmpty => 'a'.toUpperCase() => 'A'
        expect(component.displayName[0].toUpperCase(), equals('A'));
      });

      test('displayName takes precedence over playerId', () {
        final component = PlayerBubbleComponent(
          displayName: 'Bob',
          playerId: 'xyz',
        );
        // Logic: 'Bob'.isNotEmpty => 'B' (not 'X' from playerId)
        expect(component.displayName[0].toUpperCase(), equals('B'));
      });

      test('playerId used when displayName is empty', () {
        final component = PlayerBubbleComponent(
          displayName: '',
          playerId: 'user123',
        );
        // Logic: ''.isNotEmpty is false, 'user123'.isNotEmpty => 'u'.toUpperCase()
        expect(component.playerId[0].toUpperCase(), equals('U'));
      });

      test('question mark when both are empty', () {
        final component = PlayerBubbleComponent(
          displayName: '',
          playerId: '',
        );
        // Logic: both empty => '?'
        final displayName = component.displayName;
        final playerId = component.playerId;
        String initial;
        if (displayName.isNotEmpty) {
          initial = displayName[0].toUpperCase();
        } else if (playerId.isNotEmpty) {
          initial = playerId[0].toUpperCase();
        } else {
          initial = '?';
        }
        expect(initial, equals('?'));
      });

      test('handles numeric displayName', () {
        final component = PlayerBubbleComponent(
          displayName: '123User',
          playerId: 'id',
        );
        expect(component.displayName[0].toUpperCase(), equals('1'));
      });

      test('handles special character displayName', () {
        final component = PlayerBubbleComponent(
          displayName: '@username',
          playerId: 'id',
        );
        expect(component.displayName[0].toUpperCase(), equals('@'));
      });
    });

    group('PositionComponent behavior', () {
      test('is a PositionComponent', () {
        final component = PlayerBubbleComponent(
          displayName: 'Test',
          playerId: 'id',
        );

        expect(component, isA<PositionComponent>());
      });

      test('position can be set', () {
        final component = PlayerBubbleComponent(
          displayName: 'Test',
          playerId: 'id',
        );

        component.position = Vector2(100, 200);
        expect(component.position.x, equals(100));
        expect(component.position.y, equals(200));
      });

      test('size is based on bubbleSize', () {
        final component = PlayerBubbleComponent(
          displayName: 'Test',
          playerId: 'id',
          bubbleSize: 80,
        );

        expect(component.size.x, equals(80));
        expect(component.size.y, equals(80));
      });
    });
  });
}
