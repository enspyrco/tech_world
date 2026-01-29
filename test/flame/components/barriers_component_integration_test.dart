import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tech_world_game.dart';

/// A test version of TechWorldGame for BarriersComponent testing
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

  group('BarriersComponent integration tests', () {
    testWithGame<TestGameWithMockImages>(
      'onLoad adds rectangle components for each barrier',
      TestGameWithMockImages.new,
      (game) async {
        final barriers = BarriersComponent();

        await game.world.add(barriers);
        await game.ready();

        // Barriers should be mounted
        expect(barriers.isMounted, isTrue);

        // World should contain rectangle components for each barrier point
        final rectangles =
            game.world.children.whereType<RectangleComponent>().toList();

        // The number of rectangles should match the number of barrier tuples
        expect(rectangles.length, equals(barriers.tuples.length));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'barrier rectangles have correct size',
      TestGameWithMockImages.new,
      (game) async {
        final barriers = BarriersComponent();

        await game.world.add(barriers);
        await game.ready();

        final rectangles =
            game.world.children.whereType<RectangleComponent>().toList();

        // Each barrier rectangle should be gridSquareSize x gridSquareSize
        for (final rect in rectangles) {
          expect(rect.size.x, equals(gridSquareSizeDouble));
          expect(rect.size.y, equals(gridSquareSizeDouble));
        }
      },
    );

    testWithGame<TestGameWithMockImages>(
      'barrier rectangles have center anchor',
      TestGameWithMockImages.new,
      (game) async {
        final barriers = BarriersComponent();

        await game.world.add(barriers);
        await game.ready();

        final rectangles =
            game.world.children.whereType<RectangleComponent>().toList();

        // Each barrier should have center anchor
        for (final rect in rectangles) {
          expect(rect.anchor, equals(Anchor.center));
        }
      },
    );

    testWithGame<TestGameWithMockImages>(
      'barrier rectangles are at correct positions',
      TestGameWithMockImages.new,
      (game) async {
        final barriers = BarriersComponent();

        await game.world.add(barriers);
        await game.ready();

        final rectangles =
            game.world.children.whereType<RectangleComponent>().toList();
        final tuples = barriers.tuples;

        // Convert rectangle positions to mini grid coordinates and verify
        final rectanglePositions = rectangles.map((r) {
          final x = (r.position.x / gridSquareSizeDouble).round();
          final y = (r.position.y / gridSquareSizeDouble).round();
          return (x, y);
        }).toSet();

        // All barrier tuples should have a corresponding rectangle
        for (final tuple in tuples) {
          expect(
            rectanglePositions.contains(tuple),
            isTrue,
            reason: 'Barrier at $tuple should have a rectangle',
          );
        }
      },
    );

    testWithGame<TestGameWithMockImages>(
      'multiple barriers can be added to game',
      TestGameWithMockImages.new,
      (game) async {
        final barriers1 = BarriersComponent();
        final barriers2 = BarriersComponent();

        await game.world.add(barriers1);
        await game.world.add(barriers2);
        await game.ready();

        expect(barriers1.isMounted, isTrue);
        expect(barriers2.isMounted, isTrue);

        // Should have double the rectangles
        final rectangles =
            game.world.children.whereType<RectangleComponent>().toList();
        expect(rectangles.length, equals(barriers1.tuples.length * 2));
      },
    );
  });
}
