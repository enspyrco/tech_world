import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/bot_character_component.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/flame/tech_world_game.dart';

/// A test version of TechWorldGame that uses mock images
class TestGameWithMockImages extends TechWorldGame {
  TestGameWithMockImages() : super(world: World());

  @override
  Future<void> onLoad() async {
    // Generate and add mock images instead of loading from assets
    images.add('NPC11.png', await generateImage(384, 256));
    images.add('NPC12.png', await generateImage(384, 256));
    images.add('NPC13.png', await generateImage(384, 256));
    images.add('single_room.png', await generateImage(800, 600));
    images.add('claude_bot.png', await generateImage(48, 48));

    // Also add to Flame.images which BotCharacterComponent uses
    Flame.images.add('claude_bot.png', await generateImage(48, 48));

    camera.viewfinder.anchor = Anchor.center;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BotCharacterComponent integration tests', () {
    setUp(() {
      // Reset bot status before each test
      botStatusNotifier.value = BotStatus.idle;
    });

    testWithGame<TestGameWithMockImages>(
      'onLoad loads image and component is mounted',
      TestGameWithMockImages.new,
      (game) async {
        final bot = BotCharacterComponent(
          position: Vector2(100, 100),
          id: 'bot-claude',
          displayName: 'Claude',
        );

        await game.world.add(bot);
        await game.ready();

        // After onLoad, component should be mounted
        expect(bot.isMounted, isTrue);
        expect(bot.isLoaded, isTrue);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'has correct size and anchor after onLoad',
      TestGameWithMockImages.new,
      (game) async {
        final bot = BotCharacterComponent(
          position: Vector2(200, 200),
          id: 'bot-claude',
          displayName: 'Claude',
        );

        await game.world.add(bot);
        await game.ready();

        expect(bot.size.x, equals(48));
        expect(bot.size.y, equals(48));
        expect(bot.anchor, equals(Anchor.centerLeft));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'onTapDown toggles bot status',
      TestGameWithMockImages.new,
      (game) async {
        final bot = BotCharacterComponent(
          position: Vector2(100, 100),
          id: 'bot-claude',
          displayName: 'Claude',
        );

        await game.world.add(bot);
        await game.ready();

        // Initial status should be idle
        expect(botStatusNotifier.value, equals(BotStatus.idle));

        // Create a mock tap event using flame_test helper
        final event = createTapDownEvents(game: game);

        // Simulate tap down - should toggle to thinking
        bot.onTapDown(event);
        expect(botStatusNotifier.value, equals(BotStatus.thinking));

        // Another tap - should toggle back to idle
        bot.onTapDown(event);
        expect(botStatusNotifier.value, equals(BotStatus.idle));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'multiple bots can be added to game',
      TestGameWithMockImages.new,
      (game) async {
        final bot1 = BotCharacterComponent(
          position: Vector2(100, 100),
          id: 'bot-1',
          displayName: 'Bot 1',
        );

        final bot2 = BotCharacterComponent(
          position: Vector2(200, 200),
          id: 'bot-2',
          displayName: 'Bot 2',
        );

        await game.world.add(bot1);
        await game.world.add(bot2);
        await game.ready();

        expect(bot1.isMounted, isTrue);
        expect(bot2.isMounted, isTrue);
        expect(bot1.position, isNot(equals(bot2.position)));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'position updates correctly',
      TestGameWithMockImages.new,
      (game) async {
        final bot = BotCharacterComponent(
          position: Vector2(0, 0),
          id: 'bot-claude',
          displayName: 'Claude',
        );

        await game.world.add(bot);
        await game.ready();

        expect(bot.position.x, equals(0));
        expect(bot.position.y, equals(0));

        bot.position = Vector2(150, 250);

        expect(bot.position.x, equals(150));
        expect(bot.position.y, equals(250));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'miniGridPosition updates with position',
      TestGameWithMockImages.new,
      (game) async {
        final bot = BotCharacterComponent(
          position: Vector2(64, 96), // 2, 3 in mini grid (assuming 32px grid)
          id: 'bot-claude',
          displayName: 'Claude',
        );

        await game.world.add(bot);
        await game.ready();

        expect(bot.miniGridPosition.x, equals(2));
        expect(bot.miniGridPosition.y, equals(3));

        // Update position
        bot.position = Vector2(160, 192); // 5, 6 in mini grid
        expect(bot.miniGridPosition.x, equals(5));
        expect(bot.miniGridPosition.y, equals(6));
      },
    );
  });
}
