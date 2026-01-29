import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/grid_component.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tech_world_game.dart';

/// A test version of TechWorldGame for GridComponent testing
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

  group('GridComponent integration tests', () {
    testWithGame<TestGameWithMockImages>(
      'onLoad adds rectangle components to world',
      TestGameWithMockImages.new,
      (game) async {
        final grid = GridComponent();

        await game.world.add(grid);
        await game.ready();

        // Grid should be mounted
        expect(grid.isMounted, isTrue);

        // World should contain rectangle components for grid lines
        // (gridSize + 1) vertical lines + (gridSize + 1) horizontal lines
        final rectangles =
            game.world.children.whereType<RectangleComponent>().toList();

        // Each line is a RectangleComponent
        // We expect (gridSize + 1) * 2 rectangles total (vertical + horizontal)
        expect(rectangles.length, equals((gridSize + 1) * 2));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'grid lines have correct dimensions',
      TestGameWithMockImages.new,
      (game) async {
        final grid = GridComponent();

        await game.world.add(grid);
        await game.ready();

        final rectangles =
            game.world.children.whereType<RectangleComponent>().toList();

        // Separate vertical and horizontal lines
        final verticalLines =
            rectangles.where((r) => r.size.x == 1).toList();
        final horizontalLines =
            rectangles.where((r) => r.size.y == 1).toList();

        // Check we have the right number of each
        expect(verticalLines.length, equals(gridSize + 1));
        expect(horizontalLines.length, equals(gridSize + 1));

        // Check vertical line dimensions
        for (final line in verticalLines) {
          expect(line.size.x, equals(1));
          expect(line.size.y, equals(gridSize * gridSquareSizeDouble));
        }

        // Check horizontal line dimensions
        for (final line in horizontalLines) {
          expect(line.size.x, equals(gridSize * gridSquareSizeDouble));
          expect(line.size.y, equals(1));
        }
      },
    );

    testWithGame<TestGameWithMockImages>(
      'vertical lines have correct positions',
      TestGameWithMockImages.new,
      (game) async {
        final grid = GridComponent();

        await game.world.add(grid);
        await game.ready();

        final rectangles =
            game.world.children.whereType<RectangleComponent>().toList();
        final verticalLines =
            rectangles.where((r) => r.size.x == 1).toList();

        // Sort by x position
        verticalLines.sort((a, b) => a.position.x.compareTo(b.position.x));

        // Check first and last line positions
        expect(verticalLines.first.position.x, equals(0));
        expect(
          verticalLines.last.position.x,
          equals(gridSize * gridSquareSizeDouble),
        );
      },
    );

    testWithGame<TestGameWithMockImages>(
      'horizontal lines have correct positions',
      TestGameWithMockImages.new,
      (game) async {
        final grid = GridComponent();

        await game.world.add(grid);
        await game.ready();

        final rectangles =
            game.world.children.whereType<RectangleComponent>().toList();
        final horizontalLines =
            rectangles.where((r) => r.size.y == 1).toList();

        // Sort by y position
        horizontalLines.sort((a, b) => a.position.y.compareTo(b.position.y));

        // Check first and last line positions
        expect(horizontalLines.first.position.y, equals(0));
        expect(
          horizontalLines.last.position.y,
          equals(gridSize * gridSquareSizeDouble),
        );
      },
    );
  });
}
