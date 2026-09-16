import 'dart:async';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/flame/maps/game_map.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/flame/tiles/predefined_tilesets.dart';
import 'package:tech_world/flame/tiles/tileset_registry.dart';

/// What a failed map switch owes the rest of the app (claude-tasks#4463).
///
/// `_loadMapInternal` takes down two pieces of state together —
/// `_isLoadingMap` and `gameReady` — and used to restore them on different
/// paths: the first in `finally`, the second as the last statement of the
/// `try`. Anything throwing in between left `gameReady` false indefinitely.
///
/// The fix deliberately does NOT restore `gameReady` in `finally`. After a
/// failed load `_removeMapComponents()` has already run and the world really
/// is not ready, so a restored `true` would be a lie. The defect was that
/// nothing SAID so, and that is what these tests pin: the false must be
/// accompanied, never silent, and it must be recoverable.
class TestGameWithMockImages extends TechWorldGame {
  TestGameWithMockImages({required World world}) : super(world: world);

  @override
  Future<void> onLoad() async {
    images.add('NPC11.png', await generateImage(512, 64));
    images.add('NPC12.png', await generateImage(512, 64));
    images.add('NPC13.png', await generateImage(512, 64));
    images.add('claude_bot.png', await generateImage(48, 48));
    for (final tileset in allTilesets) {
      images.add(
        tileset.imagePath,
        await generateImage(
            tileset.columns * tileset.tileSize, tileset.rows * tileset.tileSize),
      );
    }
    tilesetRegistry = TilesetRegistry(images: images);
    await tilesetRegistry.loadAll(allTilesets);
    camera.viewfinder.anchor = Anchor.center;
  }
}

GameMap _map(String id) => GameMap(
      id: id,
      name: 'Map $id',
      barriers: const [],
      spawnPoint: const Point(5, 5),
      terminals: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<AuthUser> authController;
  setUp(() => authController = StreamController<AuthUser>.broadcast());
  tearDown(() => authController.close());

  TestGameWithMockImages newGame() => TestGameWithMockImages(
      world: TechWorld(authStateChanges: authController.stream));

  testWithGame<TestGameWithMockImages>(
    'a throwing load leaves gameReady false AND says why',
    newGame,
    (game) async {
      await game.ready();
      final world = game.world as TechWorld;
      expect(world.gameReady.value, isTrue, reason: 'onLoad completed');

      world.debugMapLoadFault =
          () => Future<void>.error(StateError('tileset gone'));

      await expectLater(
        world.loadMap(_map('broken')),
        throwsA(isA<StateError>()),
        reason: 'the throw must still reach callers that await — main.dart '
            "routes it to _leaveRoom, and the toolbar's SnackBar needs it",
      );

      expect(world.gameReady.value, isFalse,
          reason: 'honest: _removeMapComponents() ran, the world IS unready');
      expect(world.mapLoadError.value, isNotNull,
          reason: 'THE FIX. A false gameReady with a null message is exactly '
              'the silent wedge #4463 reports — the pair must move together');
      expect(world.mapLoadError.value, contains('Map broken'),
          reason: 'names the map the player picked, not just "an error"');
    },
  );

  testWithGame<TestGameWithMockImages>(
    'a later successful load clears the error — the wedge is escapable',
    newGame,
    (game) async {
      await game.ready();
      final world = game.world as TechWorld;

      world.debugMapLoadFault =
          () => Future<void>.error(StateError('tileset gone'));
      await expectLater(
          world.loadMap(_map('broken')), throwsA(isA<StateError>()));
      expect(world.mapLoadError.value, isNotNull);

      // The recovery the banner tells the player to attempt.
      world.debugMapLoadFault = null;
      await world.loadMap(_map('good'));

      expect(world.gameReady.value, isTrue);
      expect(world.mapLoadError.value, isNull,
          reason: 'a stale error banner over a working world is its own bug');
    },
  );

  testWithGame<TestGameWithMockImages>(
    'a failed load does not wedge the concurrency guard',
    newGame,
    (game) async {
      await game.ready();
      final world = game.world as TechWorld;

      world.debugMapLoadFault =
          () => Future<void>.error(StateError('tileset gone'));
      await expectLater(
          world.loadMap(_map('broken')), throwsA(isA<StateError>()));

      // `_isLoadingMap` is restored in `finally`; if it were not, every
      // subsequent load would hit the "another load is in progress" early
      // return and the world would be permanently stuck on the broken map.
      world.debugMapLoadFault = null;
      await world.loadMap(_map('after'));
      expect(world.currentMap.value.id, 'after');
    },
  );
}
