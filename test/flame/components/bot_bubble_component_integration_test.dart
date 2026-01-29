import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/bot_bubble_component.dart';
import 'package:tech_world/flame/components/bot_status.dart';
import 'package:tech_world/flame/tech_world_game.dart';

/// A test version of TechWorldGame for BotBubbleComponent testing
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

    camera.viewfinder.anchor = Anchor.center;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BotBubbleComponent integration tests', () {
    setUp(() {
      // Reset bot status before each test
      botStatusNotifier.value = BotStatus.idle;
    });

    testWithGame<TestGameWithMockImages>(
      'mounts correctly with default size',
      TestGameWithMockImages.new,
      (game) async {
        final bubble = BotBubbleComponent();

        await game.world.add(bubble);
        await game.ready();

        expect(bubble.isMounted, isTrue);
        expect(bubble.bubbleSize, equals(48));
        expect(bubble.size.x, equals(48));
        expect(bubble.size.y, equals(48));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'mounts with custom bubble size',
      TestGameWithMockImages.new,
      (game) async {
        final bubble = BotBubbleComponent(bubbleSize: 64);

        await game.world.add(bubble);
        await game.ready();

        expect(bubble.isMounted, isTrue);
        expect(bubble.bubbleSize, equals(64));
        expect(bubble.size.x, equals(64));
        expect(bubble.size.y, equals(64));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'has bottom center anchor',
      TestGameWithMockImages.new,
      (game) async {
        final bubble = BotBubbleComponent();

        await game.world.add(bubble);
        await game.ready();

        expect(bubble.anchor, equals(Anchor.bottomCenter));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'updates animation time during game update',
      TestGameWithMockImages.new,
      (game) async {
        final bubble = BotBubbleComponent();

        await game.world.add(bubble);
        await game.ready();

        // Simulate game updates
        game.update(0.1);
        game.update(0.1);
        game.update(0.1);

        // Component should still be mounted after updates
        expect(bubble.isMounted, isTrue);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'responds to status changes to thinking',
      TestGameWithMockImages.new,
      (game) async {
        final bubble = BotBubbleComponent();

        await game.world.add(bubble);
        await game.ready();

        // Change status to thinking
        botStatusNotifier.value = BotStatus.thinking;

        // Update game to process the change
        game.update(0.016);

        // Component should still be mounted
        expect(bubble.isMounted, isTrue);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'responds to status changes back to idle',
      TestGameWithMockImages.new,
      (game) async {
        final bubble = BotBubbleComponent();

        await game.world.add(bubble);
        await game.ready();

        // Change status to thinking
        botStatusNotifier.value = BotStatus.thinking;
        game.update(0.016);

        // Change back to idle
        botStatusNotifier.value = BotStatus.idle;
        game.update(0.016);

        // Component should still be mounted
        expect(bubble.isMounted, isTrue);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'cleans up listener on remove',
      TestGameWithMockImages.new,
      (game) async {
        final bubble = BotBubbleComponent();

        await game.world.add(bubble);
        await game.ready();

        // Remove the component
        game.world.remove(bubble);
        await game.ready();

        // Should be removed
        expect(bubble.isMounted, isFalse);

        // Status changes after removal should not cause errors
        botStatusNotifier.value = BotStatus.thinking;
        botStatusNotifier.value = BotStatus.idle;
      },
    );

    testWithGame<TestGameWithMockImages>(
      'renders correctly in thinking state',
      TestGameWithMockImages.new,
      (game) async {
        botStatusNotifier.value = BotStatus.thinking;
        final bubble = BotBubbleComponent();

        await game.world.add(bubble);
        await game.ready();

        // Run several update cycles to animate
        for (var i = 0; i < 10; i++) {
          game.update(0.016);
        }

        expect(bubble.isMounted, isTrue);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'renders correctly in idle state',
      TestGameWithMockImages.new,
      (game) async {
        final bubble = BotBubbleComponent();

        await game.world.add(bubble);
        await game.ready();

        // Run several update cycles
        for (var i = 0; i < 10; i++) {
          game.update(0.016);
        }

        expect(bubble.isMounted, isTrue);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'multiple bubbles can be added',
      TestGameWithMockImages.new,
      (game) async {
        final bubble1 = BotBubbleComponent(bubbleSize: 48);
        final bubble2 = BotBubbleComponent(bubbleSize: 64);

        await game.world.add(bubble1);
        await game.world.add(bubble2);
        await game.ready();

        expect(bubble1.isMounted, isTrue);
        expect(bubble2.isMounted, isTrue);
        expect(bubble1.bubbleSize, isNot(equals(bubble2.bubbleSize)));
      },
    );
  });
}
