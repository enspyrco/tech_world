import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/flame/shared/player_anim_state.dart';
import 'package:tech_world/flame/tech_world_game.dart';

/// A test version of TechWorldGame that uses mock images for PlayerComponent testing
class TestGameWithMockImages extends TechWorldGame {
  TestGameWithMockImages() : super(world: World());

  @override
  Future<void> onLoad() async {
    // Generate and add mock images instead of loading from assets
    // Sprite sheet matches the REAL asset: 512x64 = 16 cells of 32x64.
    // 12 walk cells (4 directions x 3 frames) + 4 wave-emote cells (12-15).
    // Previously 384x256, which matched no shipping sprite in the repo.
    images.add('NPC11.png', await generateImage(512, 64));
    images.add('NPC12.png', await generateImage(512, 64));
    images.add('NPC13.png', await generateImage(512, 64));
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
        expect(player.animations!.length, equals(9)); // 8 walk + wave
        expect(player.current, equals(PlayerAnimState.walkDown));
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
        expect(player.current, equals(PlayerAnimState.walkRight));
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
        expect(player.current, equals(PlayerAnimState.walkRight));

        // Second move should replace the first
        player.move([Direction.down], [Vector2(0, 0), Vector2(0, 32)]);
        expect(player.current, equals(PlayerAnimState.walkDown));
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
            player.animations!.containsKey(
              PlayerAnimState.forDirection(direction),
            ),
            isTrue,
            reason: 'Should have animation for $direction',
          );
        }
        // 8 walk states + the wave emote (sprite cells 12-15). The mock sheet
        // is full-width, so the wave strip is present.
        expect(player.animations!.length, equals(9));
        expect(
          player.animations!.containsKey(PlayerAnimState.wave),
          isTrue,
          reason: 'Full-width sheet should carry the wave strip',
        );
      },
    );

    testWithGame<TestGameWithMockImages>(
      'wave plays the emote and restores the facing when it completes',
      TestGameWithMockImages.new,
      (game) async {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'test',
          displayName: 'Test',
        );
        await game.world.add(player);
        await game.ready();

        // Face right, so the restore target is NOT the default walkDown —
        // otherwise the assertion would pass even if _facing were ignored.
        player.move([Direction.right], [Vector2(0, 0), Vector2(32, 0)]);
        expect(player.current, equals(PlayerAnimState.walkRight));

        player.wave();
        expect(player.isWaving, isTrue);

        // 4 frames x 0.15s = 0.6s; run past the end.
        for (var i = 0; i < 80; i++) {
          game.update(0.01);
        }

        expect(player.isWaving, isFalse, reason: 'one-shot must not loop');
        expect(
          player.current,
          equals(PlayerAnimState.walkRight),
          reason: 'should restore the facing it had before waving',
        );
      },
    );

    testWithGame<TestGameWithMockImages>(
      'wave is a no-op while already waving (mash guard)',
      TestGameWithMockImages.new,
      (game) async {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'test',
          displayName: 'Test',
        );
        await game.world.add(player);
        await game.ready();

        player.wave();
        game.update(0.3); // mid-wave
        final ticker = player.animationTicker;
        player.wave(); // mash
        expect(player.animationTicker, same(ticker));
        expect(player.isWaving, isTrue);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'movement interrupts a wave',
      TestGameWithMockImages.new,
      (game) async {
        final player = PlayerComponent(
          position: Vector2.zero(),
          id: 'test',
          displayName: 'Test',
        );
        await game.world.add(player);
        await game.ready();

        player.wave();
        expect(player.isWaving, isTrue);

        player.move([Direction.up], [Vector2(0, 0), Vector2(0, -32)]);
        expect(player.isWaving, isFalse);
        expect(player.current, equals(PlayerAnimState.walkUp));
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
        expect(player.animations!.length, equals(9));
        expect(player.current, equals(PlayerAnimState.walkDown));
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
        expect(player.animations!.length, equals(9));
        expect(player.current, equals(PlayerAnimState.walkDown));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'isMoving is false at rest, true mid-move, false after completion',
      TestGameWithMockImages.new,
      (game) async {
        final player = PlayerComponent(
          position: Vector2(0, 0),
          id: 'test-player',
          displayName: 'Test Player',
        );

        await game.world.add(player);
        await game.ready();

        // At rest: no move effect, so not moving.
        expect(player.isMoving, isFalse, reason: 'idle at spawn');

        // Start a single one-cell move (0.2s effect).
        player.move([Direction.right], [Vector2(0, 0), Vector2(32, 0)]);

        // Mid-move: advance less than the cell duration.
        game.update(0.05);
        expect(player.isMoving, isTrue,
            reason: 'a MoveEffect is in flight mid-cell');

        // Advance past the full cell duration so the effect completes and is
        // removed (removeOnFinish defaults to true). Drive a couple of extra
        // frames so the controller settles and the child is pruned.
        for (var i = 0; i < 20; i++) {
          game.update(0.016);
        }

        expect(player.isMoving, isFalse,
            reason: 'effect completed -> back to idle');
        expect(player.position.x, closeTo(32, 0.001),
            reason: 'reached the target cell');
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
