import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/dreamfinder_component.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/components/path_component.dart';
import 'package:tech_world/flame/shared/dreamfinder_state.dart';
import 'package:tech_world/flame/tech_world_game.dart';

class TestGameWithDreamfinder extends TechWorldGame {
  TestGameWithDreamfinder() : super(world: World());

  @override
  Future<void> onLoad() async {
    // Mock images: dreamfinder sheet is 512x192 (3 rows of 64px)
    images.add('dreamfinder_bot_sheet.png', await generateImage(512, 192));
    camera.viewfinder.anchor = Anchor.center;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DreamfinderComponent', () {
    late PathComponent pathComponent;

    setUp(() {
      final barriers = BarriersComponent(barriers: []);
      pathComponent = PathComponent(barriers: barriers);
    });

    testWithGame<TestGameWithDreamfinder>(
      'spawns in working state',
      TestGameWithDreamfinder.new,
      (game) async {
        final df = DreamfinderComponent(
          position: Vector2(256, 160),
          id: 'bot-dreamfinder',
          displayName: 'Dreamfinder',
          pathComponent: pathComponent,
        );

        await game.world.add(pathComponent);
        await game.world.add(df);
        await game.ready();

        expect(df.isMounted, isTrue);
        expect(df.current, equals(DreamfinderState.working));
        expect(df.playing, isTrue);
      },
    );

    testWithGame<TestGameWithDreamfinder>(
      'spawns at specified position (away from player spawn)',
      TestGameWithDreamfinder.new,
      (game) async {
        // Dreamfinder should spawn at a different position than (0,0)
        final spawnPos = Vector2(256, 160);
        final df = DreamfinderComponent(
          position: spawnPos,
          id: 'bot-dreamfinder',
          displayName: 'Dreamfinder',
          pathComponent: pathComponent,
        );

        await game.world.add(pathComponent);
        await game.world.add(df);
        await game.ready();

        expect(df.position.x, equals(256));
        expect(df.position.y, equals(160));
      },
    );

    testWithGame<TestGameWithDreamfinder>(
      'noticePlayer transitions to surprised state',
      TestGameWithDreamfinder.new,
      (game) async {
        final df = DreamfinderComponent(
          position: Vector2(256, 160),
          id: 'bot-dreamfinder',
          displayName: 'Dreamfinder',
          pathComponent: pathComponent,
        );

        await game.world.add(pathComponent);
        await game.world.add(df);
        await game.ready();

        // Initially working
        expect(df.current, equals(DreamfinderState.working));

        // Player arrives
        df.noticePlayer(Vector2(800, 800));

        expect(df.current, equals(DreamfinderState.surprised));
        expect(df.playing, isTrue);
      },
    );

    testWithGame<TestGameWithDreamfinder>(
      'noticePlayer only reacts to first human',
      TestGameWithDreamfinder.new,
      (game) async {
        final df = DreamfinderComponent(
          position: Vector2(256, 160),
          id: 'bot-dreamfinder',
          displayName: 'Dreamfinder',
          pathComponent: pathComponent,
        );

        await game.world.add(pathComponent);
        await game.world.add(df);
        await game.ready();

        // First player triggers surprise
        df.noticePlayer(Vector2(800, 800));
        expect(df.current, equals(DreamfinderState.surprised));

        // Advance past surprise animation
        game.update(2.0);

        // Second player should NOT re-trigger surprise
        final stateBefore = df.current;
        df.noticePlayer(Vector2(400, 400));
        expect(df.current, equals(stateBefore));
      },
    );

    testWithGame<TestGameWithDreamfinder>(
      'moveFromServer overrides autonomous behavior',
      TestGameWithDreamfinder.new,
      (game) async {
        final df = DreamfinderComponent(
          position: Vector2(256, 160),
          id: 'bot-dreamfinder',
          displayName: 'Dreamfinder',
          pathComponent: pathComponent,
        );

        await game.world.add(pathComponent);
        await game.world.add(df);
        await game.ready();

        // Server sends a position update — should work regardless of state
        df.moveFromServer(
          [],
          [Vector2(320, 320)],
        );

        expect(df.position, equals(Vector2(320, 320)));
      },
    );

    testWithGame<TestGameWithDreamfinder>(
      'miniGridPosition reflects current position',
      TestGameWithDreamfinder.new,
      (game) async {
        final df = DreamfinderComponent(
          position: Vector2(256, 160), // grid (8, 5)
          id: 'bot-dreamfinder',
          displayName: 'Dreamfinder',
          pathComponent: pathComponent,
        );

        await game.world.add(pathComponent);
        await game.world.add(df);
        await game.ready();

        expect(df.miniGridPosition.x, equals(8));
        expect(df.miniGridPosition.y, equals(5));
      },
    );
  });
}
