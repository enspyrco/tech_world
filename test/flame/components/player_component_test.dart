import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/auth/auth_user.dart';

void main() {
  group('PlayerComponent', () {
    group('constructor', () {
      test('creates component with required parameters', () {
        final player = PlayerComponent(
          position: Vector2(100, 200),
          id: 'player-1',
          displayName: 'Test Player',
        );

        expect(player.id, equals('player-1'));
        expect(player.displayName, equals('Test Player'));
        expect(player.position.x, equals(100));
        expect(player.position.y, equals(200));
      });

      test('creates component from User', () {
        final user = AuthUser(id: 'user-123', displayName: 'John Doe');
        final player = PlayerComponent.from(user);

        expect(player.id, equals('user-123'));
        expect(player.displayName, equals('John Doe'));
        expect(player.position, equals(Vector2.zero()));
      });

      test('implements User interface', () {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'test-id',
          displayName: 'Test Name',
        );

        expect(player, isA<User>());
      });
    });

    group('miniGridPosition', () {
      test('converts position to mini grid coordinates', () {
        final player = PlayerComponent(
          position: Vector2(gridSquareSizeDouble * 5, gridSquareSizeDouble * 10),
          id: 'test',
          displayName: 'Test',
        );

        final miniGrid = player.miniGridPosition;
        expect(miniGrid.x, equals(5));
        expect(miniGrid.y, equals(10));
      });

      test('rounds position correctly', () {
        final player = PlayerComponent(
          position: Vector2(
            gridSquareSizeDouble * 5 + 0.5,
            gridSquareSizeDouble * 10 + 0.5,
          ),
          id: 'test',
          displayName: 'Test',
        );

        final miniGrid = player.miniGridPosition;
        expect(miniGrid.x, equals(5));
        expect(miniGrid.y, equals(10));
      });

      test('handles fractional positions near boundary', () {
        final player = PlayerComponent(
          position: Vector2(
            gridSquareSizeDouble * 5 + gridSquareSizeDouble - 1,
            gridSquareSizeDouble * 10 + gridSquareSizeDouble - 1,
          ),
          id: 'test',
          displayName: 'Test',
        );

        final miniGrid = player.miniGridPosition;
        // Position 5*32 + 31 = 191, rounds to 191, 191/32 = 5
        expect(miniGrid.x, equals(5));
        expect(miniGrid.y, equals(10));
      });

      test('returns Point<int>', () {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'test',
          displayName: 'Test',
        );

        expect(player.miniGridPosition, isA<Point<int>>());
      });

      test('handles origin position', () {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'test',
          displayName: 'Test',
        );

        expect(player.miniGridPosition, equals(const Point(0, 0)));
      });
    });

    group('miniGridTuple', () {
      test('converts position to tuple', () {
        final player = PlayerComponent(
          position: Vector2(gridSquareSizeDouble * 3, gridSquareSizeDouble * 7),
          id: 'test',
          displayName: 'Test',
        );

        final tuple = player.miniGridTuple;
        expect(tuple.$1, equals(3));
        expect(tuple.$2, equals(7));
      });

      test('matches miniGridPosition values', () {
        final player = PlayerComponent(
          position: Vector2(gridSquareSizeDouble * 15, gridSquareSizeDouble * 25),
          id: 'test',
          displayName: 'Test',
        );

        final point = player.miniGridPosition;
        final tuple = player.miniGridTuple;

        expect(tuple.$1, equals(point.x));
        expect(tuple.$2, equals(point.y));
      });

      test('handles large coordinates', () {
        final player = PlayerComponent(
          position: Vector2(
            gridSquareSizeDouble * (gridSize - 1),
            gridSquareSizeDouble * (gridSize - 1),
          ),
          id: 'test',
          displayName: 'Test',
        );

        final tuple = player.miniGridTuple;
        expect(tuple.$1, equals(gridSize - 1));
        expect(tuple.$2, equals(gridSize - 1));
      });
    });

    group('id and displayName', () {
      test('id is mutable', () {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'original-id',
          displayName: 'Test',
        );

        player.id = 'new-id';
        expect(player.id, equals('new-id'));
      });

      test('displayName is mutable', () {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'test',
          displayName: 'Original Name',
        );

        player.displayName = 'New Name';
        expect(player.displayName, equals('New Name'));
      });

      test('handles empty strings', () {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: '',
          displayName: '',
        );

        expect(player.id, isEmpty);
        expect(player.displayName, isEmpty);
      });

      test('handles special characters', () {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'user@domain.com',
          displayName: 'Test User (Admin)',
        );

        expect(player.id, equals('user@domain.com'));
        expect(player.displayName, equals('Test User (Admin)'));
      });
    });

    group('spriteAsset', () {
      test('defaults to NPC11.png', () {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'test',
          displayName: 'Test',
        );

        expect(player.spriteAsset, equals('NPC11.png'));
      });

      test('accepts optional spriteAsset parameter', () {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'test',
          displayName: 'Test',
          spriteAsset: 'NPC12.png',
        );

        expect(player.spriteAsset, equals('NPC12.png'));
      });

      test('PlayerComponent.from defaults to NPC11.png', () {
        final user = AuthUser(id: 'user-1', displayName: 'User');
        final player = PlayerComponent.from(user);

        expect(player.spriteAsset, equals('NPC11.png'));
      });

      test('PlayerComponent.from accepts optional spriteAsset', () {
        final user = AuthUser(id: 'user-1', displayName: 'User');
        final player = PlayerComponent.from(user, spriteAsset: 'NPC13.png');

        expect(player.spriteAsset, equals('NPC13.png'));
      });

      test('setter updates spriteAsset value (before mount)', () {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'test',
          displayName: 'Test',
        );

        player.spriteAsset = 'NPC12.png';
        expect(player.spriteAsset, equals('NPC12.png'));
      });

      test('setter is a no-op for the same value', () {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'test',
          displayName: 'Test',
          spriteAsset: 'NPC11.png',
        );

        // Should not throw or change anything
        player.spriteAsset = 'NPC11.png';
        expect(player.spriteAsset, equals('NPC11.png'));
      });
    });

    group('position updates', () {
      test('position can be changed after construction', () {
        final player = PlayerComponent(
          position: Vector2(0, 0),
          id: 'test',
          displayName: 'Test',
        );

        player.position = Vector2(100, 200);
        expect(player.position.x, equals(100));
        expect(player.position.y, equals(200));
      });

      test('miniGridPosition reflects position changes', () {
        final player = PlayerComponent(
          position: Vector2(0, 0),
          id: 'test',
          displayName: 'Test',
        );

        expect(player.miniGridPosition, equals(const Point(0, 0)));

        player.position = Vector2(gridSquareSizeDouble * 10, gridSquareSizeDouble * 20);
        expect(player.miniGridPosition, equals(const Point(10, 20)));
      });
    });
  });
}
