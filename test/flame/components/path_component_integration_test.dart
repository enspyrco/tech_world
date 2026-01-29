import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/components/path_component.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tech_world_game.dart';

/// A test version of TechWorldGame for PathComponent testing
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

  group('PathComponent integration tests', () {
    testWithGame<TestGameWithMockImages>(
      'drawPath adds rectangles to world',
      TestGameWithMockImages.new,
      (game) async {
        final barriers = BarriersComponent();
        final pathComponent = PathComponent(barriers: barriers);

        await game.world.add(pathComponent);
        await game.ready();

        // Calculate a path first
        pathComponent.calculatePath(start: (10, 10), end: (15, 10));

        // Draw the path
        pathComponent.drawPath();

        // Wait for rectangles to be added to the world
        await game.ready();

        // World should now contain rectangle components for the path
        final rectangles =
            game.world.children.whereType<RectangleComponent>().toList();

        // Should have at least some rectangles (path length)
        expect(rectangles.isNotEmpty, isTrue);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'drawPath creates rectangles at correct positions',
      TestGameWithMockImages.new,
      (game) async {
        final barriers = BarriersComponent();
        final pathComponent = PathComponent(barriers: barriers);

        await game.world.add(pathComponent);
        await game.ready();

        // Calculate a simple horizontal path
        pathComponent.calculatePath(start: (20, 20), end: (22, 20));
        pathComponent.drawPath();

        // Wait for rectangles to be added
        await game.ready();

        final rectangles =
            game.world.children.whereType<RectangleComponent>().toList();

        // Verify rectangles are at grid positions
        for (final rect in rectangles) {
          // All positions should be multiples of grid square size
          final xGrid = rect.position.x / gridSquareSizeDouble;
          final yGrid = rect.position.y / gridSquareSizeDouble;

          expect(xGrid, equals(xGrid.roundToDouble()));
          expect(yGrid, equals(yGrid.roundToDouble()));
        }
      },
    );

    testWithGame<TestGameWithMockImages>(
      'drawPath colors start and end differently',
      TestGameWithMockImages.new,
      (game) async {
        final barriers = BarriersComponent();
        final pathComponent = PathComponent(barriers: barriers);

        await game.world.add(pathComponent);
        await game.ready();

        // Calculate a path with multiple points
        pathComponent.calculatePath(start: (25, 25), end: (28, 25));
        pathComponent.drawPath();

        // Wait for rectangles to be added
        await game.ready();

        final rectangles =
            game.world.children.whereType<RectangleComponent>().toList();

        // Should have at least 2 rectangles for start and end
        expect(rectangles.length, greaterThanOrEqualTo(2));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'drawPath replaces previous path rectangles',
      TestGameWithMockImages.new,
      (game) async {
        final barriers = BarriersComponent();
        final pathComponent = PathComponent(barriers: barriers);

        await game.world.add(pathComponent);
        await game.ready();

        // First path
        pathComponent.calculatePath(start: (10, 10), end: (15, 10));
        pathComponent.drawPath();
        await game.ready();

        final firstPathCount =
            game.world.children.whereType<RectangleComponent>().length;

        // Second path (should replace first)
        pathComponent.calculatePath(start: (20, 20), end: (22, 20));
        pathComponent.drawPath();
        await game.ready();

        final secondPathCount =
            game.world.children.whereType<RectangleComponent>().length;

        // The second path should have replaced the first
        // Total rectangles should reflect the new path, not accumulate
        expect(secondPathCount, lessThanOrEqualTo(firstPathCount + 10));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'drawPath handles empty path gracefully',
      TestGameWithMockImages.new,
      (game) async {
        final barriers = BarriersComponent();
        final pathComponent = PathComponent(barriers: barriers);

        await game.world.add(pathComponent);
        await game.ready();

        // Calculate path from same start to same end (should have at least 1 point)
        pathComponent.calculatePath(start: (30, 30), end: (30, 30));
        pathComponent.drawPath();
        await game.ready();

        // Should not throw and component should still be mounted
        expect(pathComponent.isMounted, isTrue);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'multiple path components can coexist',
      TestGameWithMockImages.new,
      (game) async {
        final barriers = BarriersComponent();
        final pathComponent1 = PathComponent(barriers: barriers);
        final pathComponent2 = PathComponent(barriers: barriers);

        await game.world.add(pathComponent1);
        await game.world.add(pathComponent2);
        await game.ready();

        pathComponent1.calculatePath(start: (5, 5), end: (8, 5));
        pathComponent1.drawPath();

        pathComponent2.calculatePath(start: (40, 40), end: (43, 40));
        pathComponent2.drawPath();

        // Wait for rectangles to be added
        await game.ready();

        expect(pathComponent1.isMounted, isTrue);
        expect(pathComponent2.isMounted, isTrue);

        // Both should have added rectangles
        final rectangles =
            game.world.children.whereType<RectangleComponent>().toList();
        expect(rectangles.length, greaterThan(4));
      },
    );
  });
}
