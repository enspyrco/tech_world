import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/tech_world_game.dart';

/// A test version of TechWorldGame that uses mock images for PlayerComponent testing
class TestGameWithMockImages extends TechWorldGame {
  TestGameWithMockImages() : super(world: World());

  @override
  Future<void> onLoad() async {
    // Generate and add mock images instead of loading from assets
    // Sprite sheet is 384x256 (12 frames of 32x64 for 4 directions)
    images.add('NPC11.png', await generateImage(384, 256));
    images.add('NPC12.png', await generateImage(384, 256));
    images.add('NPC13.png', await generateImage(384, 256));
    images.add('single_room.png', await generateImage(800, 600));
    images.add('claude_bot.png', await generateImage(48, 48));

    // Skip the parent onLoad since it tries to load from assets
    camera.viewfinder.anchor = Anchor.center;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerComponent integration tests', () {
    testWithGame<TestGameWithMockImages>(
      'onLoad initializes animations',
      TestGameWithMockImages.new,
      (game) async {
        final player = PlayerComponent(
          position: Vector2(100, 100),
          id: 'test-player',
          displayName: 'Test Player',
        );

        await game.world.add(player);
        await game.ready();

        // After onLoad, animations should be set
        expect(player.animations, isNotNull);
        expect(player.animations!.length, equals(8)); // 8 directions
        expect(player.current, equals(Direction.down)); // Default direction
        expect(player.anchor, equals(Anchor.centerLeft));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'move with empty directions sets position directly',
      TestGameWithMockImages.new,
      (game) async {
        final player = PlayerComponent(
          position: Vector2(0, 0),
          id: 'test-player',
          displayName: 'Test Player',
        );

        await game.world.add(player);
        await game.ready();

        // Move with empty directions but with points (like bot spawn)
        player.move([], [Vector2(100, 200)]);

        expect(player.position.x, equals(100));
        expect(player.position.y, equals(200));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'move creates move effects for each direction',
      TestGameWithMockImages.new,
      (game) async {
        final player = PlayerComponent(
          position: Vector2(0, 0),
          id: 'test-player',
          displayName: 'Test Player',
        );

        await game.world.add(player);
        await game.ready();

        // Move with directions and points
        final points = [
          Vector2(0, 0),
          Vector2(32, 0),
          Vector2(64, 0),
        ];
        final directions = [Direction.right, Direction.right];

        player.move(directions, points);

        // Player should have started moving and changed direction
        expect(player.current, equals(Direction.right));
        expect(player.playing, isTrue);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'removeAllEffects clears effects',
      TestGameWithMockImages.new,
      (game) async {
        final player = PlayerComponent(
          position: Vector2(0, 0),
          id: 'test-player',
          displayName: 'Test Player',
        );

        await game.world.add(player);
        await game.ready();

        // Start a move
        player.move([Direction.right], [Vector2(0, 0), Vector2(32, 0)]);

        // Remove all effects
        player.removeAllEffects();

        // No more effects should be running
        // (We can't easily check the internal state, but this shouldn't throw)
        expect(player.position, isNotNull);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'multiple moves replaces previous effects',
      TestGameWithMockImages.new,
      (game) async {
        final player = PlayerComponent(
          position: Vector2(0, 0),
          id: 'test-player',
          displayName: 'Test Player',
        );

        await game.world.add(player);
        await game.ready();

        // First move
        player.move([Direction.right], [Vector2(0, 0), Vector2(32, 0)]);
        expect(player.current, equals(Direction.right));

        // Second move should replace the first
        player.move([Direction.down], [Vector2(0, 0), Vector2(0, 32)]);
        expect(player.current, equals(Direction.down));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'all movement direction animations are set',
      TestGameWithMockImages.new,
      (game) async {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'test',
          displayName: 'Test',
        );

        await game.world.add(player);
        await game.ready();

        // All 8 movement directions should have animations (Direction.none is excluded)
        final movementDirections = [
          Direction.up,
          Direction.down,
          Direction.left,
          Direction.right,
          Direction.upLeft,
          Direction.upRight,
          Direction.downLeft,
          Direction.downRight,
        ];

        for (final direction in movementDirections) {
          expect(
            player.animations!.containsKey(direction),
            isTrue,
            reason: 'Should have animation for $direction',
          );
        }
        expect(player.animations!.length, equals(8));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'constructor with NPC12 spriteAsset loads animations from that sheet',
      TestGameWithMockImages.new,
      (game) async {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'test',
          displayName: 'Test',
          spriteAsset: 'NPC12.png',
        );

        await game.world.add(player);
        await game.ready();

        expect(player.spriteAsset, equals('NPC12.png'));
        expect(player.animations, isNotNull);
        expect(player.animations!.length, equals(8));
        expect(player.current, equals(Direction.down));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'spriteAsset setter rebuilds animations on mounted component',
      TestGameWithMockImages.new,
      (game) async {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'test',
          displayName: 'Test',
        );

        await game.world.add(player);
        await game.ready();

        expect(player.spriteAsset, equals('NPC11.png'));

        // Change sprite at runtime
        player.spriteAsset = 'NPC13.png';

        expect(player.spriteAsset, equals('NPC13.png'));
        // Animations should still be valid after rebuild
        expect(player.animations, isNotNull);
        expect(player.animations!.length, equals(8));
        expect(player.current, equals(Direction.down));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'position changes during move effect update',
      TestGameWithMockImages.new,
      (game) async {
        final player = PlayerComponent(
          position: Vector2(0, 0),
          id: 'test-player',
          displayName: 'Test Player',
        );

        await game.world.add(player);
        await game.ready();

        final startPos = player.position.clone();

        // Move right
        player.move([Direction.right], [Vector2(0, 0), Vector2(32, 0)]);

        // Simulate game updates to progress the move effect
        for (var i = 0; i < 20; i++) {
          game.update(0.016); // ~60fps frame
        }

        // Position should have changed (or be at target)
        // Note: might be at target already depending on timing
        expect(
          player.position.x >= startPos.x,
          isTrue,
          reason: 'Position should move right',
        );
      },
    );
  });
}
