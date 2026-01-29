import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/bot_character_component.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/flame/shared/constants.dart';

void main() {
  group('BotCharacterComponent', () {
    setUp(() {
      // Reset bot status before each test
      botStatusNotifier.value = BotStatus.idle;
    });

    group('constructor', () {
      test('creates component with required parameters', () {
        final bot = BotCharacterComponent(
          position: Vector2(100, 200),
          id: 'bot-1',
          displayName: 'Claude',
        );

        expect(bot.id, equals('bot-1'));
        expect(bot.displayName, equals('Claude'));
        expect(bot.position.x, equals(100));
        expect(bot.position.y, equals(200));
      });

      test('has fixed size of 48x48', () {
        final bot = BotCharacterComponent(
          position: Vector2.zero(),
          id: 'bot-1',
          displayName: 'Claude',
        );

        expect(bot.size.x, equals(48));
        expect(bot.size.y, equals(48));
      });

      test('has centerLeft anchor', () {
        final bot = BotCharacterComponent(
          position: Vector2.zero(),
          id: 'bot-1',
          displayName: 'Claude',
        );

        expect(bot.anchor, equals(Anchor.centerLeft));
      });
    });

    group('miniGridPosition', () {
      test('converts position to mini grid coordinates', () {
        final bot = BotCharacterComponent(
          position: Vector2(gridSquareSizeDouble * 5, gridSquareSizeDouble * 10),
          id: 'bot',
          displayName: 'Bot',
        );

        final miniGrid = bot.miniGridPosition;
        expect(miniGrid.x, equals(5));
        expect(miniGrid.y, equals(10));
      });

      test('rounds position correctly', () {
        final bot = BotCharacterComponent(
          position: Vector2(
            gridSquareSizeDouble * 5 + 0.5,
            gridSquareSizeDouble * 10 + 0.5,
          ),
          id: 'bot',
          displayName: 'Bot',
        );

        final miniGrid = bot.miniGridPosition;
        expect(miniGrid.x, equals(5));
        expect(miniGrid.y, equals(10));
      });

      test('returns Point<int>', () {
        final bot = BotCharacterComponent(
          position: Vector2.zero(),
          id: 'bot',
          displayName: 'Bot',
        );

        expect(bot.miniGridPosition, isA<Point<int>>());
      });

      test('handles origin position', () {
        final bot = BotCharacterComponent(
          position: Vector2.zero(),
          id: 'bot',
          displayName: 'Bot',
        );

        expect(bot.miniGridPosition, equals(const Point(0, 0)));
      });

      test('handles large coordinates', () {
        final bot = BotCharacterComponent(
          position: Vector2(
            gridSquareSizeDouble * (gridSize - 1),
            gridSquareSizeDouble * (gridSize - 1),
          ),
          id: 'bot',
          displayName: 'Bot',
        );

        final miniGrid = bot.miniGridPosition;
        expect(miniGrid.x, equals(gridSize - 1));
        expect(miniGrid.y, equals(gridSize - 1));
      });
    });

    group('id and displayName', () {
      test('stores id correctly', () {
        final bot = BotCharacterComponent(
          position: Vector2.zero(),
          id: 'claude-bot-123',
          displayName: 'Test Bot',
        );

        expect(bot.id, equals('claude-bot-123'));
      });

      test('stores displayName correctly', () {
        final bot = BotCharacterComponent(
          position: Vector2.zero(),
          id: 'bot',
          displayName: 'Claude Assistant',
        );

        expect(bot.displayName, equals('Claude Assistant'));
      });

      test('id is final', () {
        final bot = BotCharacterComponent(
          position: Vector2.zero(),
          id: 'final-id',
          displayName: 'Test',
        );

        // id should be accessible but final (can't be changed)
        expect(bot.id, equals('final-id'));
      });
    });

    group('bot status interaction', () {
      test('starts with idle status', () {
        expect(botStatusNotifier.value, equals(BotStatus.idle));
      });

      test('toggles to thinking status', () {
        botStatusNotifier.value = BotStatus.thinking;
        expect(botStatusNotifier.value, equals(BotStatus.thinking));
      });

      test('toggles back to idle status', () {
        botStatusNotifier.value = BotStatus.thinking;
        botStatusNotifier.value = BotStatus.idle;
        expect(botStatusNotifier.value, equals(BotStatus.idle));
      });
    });

    group('position', () {
      test('position is PositionComponent', () {
        final bot = BotCharacterComponent(
          position: Vector2(50, 100),
          id: 'bot',
          displayName: 'Bot',
        );

        expect(bot, isA<PositionComponent>());
      });

      test('position can be updated', () {
        final bot = BotCharacterComponent(
          position: Vector2(0, 0),
          id: 'bot',
          displayName: 'Bot',
        );

        bot.position = Vector2(100, 200);
        expect(bot.position.x, equals(100));
        expect(bot.position.y, equals(200));
      });

      test('miniGridPosition reflects position changes', () {
        final bot = BotCharacterComponent(
          position: Vector2(0, 0),
          id: 'bot',
          displayName: 'Bot',
        );

        expect(bot.miniGridPosition, equals(const Point(0, 0)));

        bot.position = Vector2(gridSquareSizeDouble * 10, gridSquareSizeDouble * 20);
        expect(bot.miniGridPosition, equals(const Point(10, 20)));
      });
    });
  });
}
