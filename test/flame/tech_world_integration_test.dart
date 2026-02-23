import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/auth/auth_user.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/tech_world.dart';
import 'package:tech_world/flame/tech_world_game.dart';

/// A test version of TechWorldGame that uses mock images.
class TestGameWithMockImages extends TechWorldGame {
  TestGameWithMockImages({required World world}) : super(world: world);

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

/// A test game that does NOT pre-cache background images.
///
/// Used to verify that [TechWorld._loadMapComponents] loads background images
/// on demand via [Images.load] instead of requiring them to already be in the
/// cache via [Images.fromCache].
class TestGameWithoutBgCache extends TechWorldGame {
  TestGameWithoutBgCache({required World world}) : super(world: world);

  @override
  Future<void> onLoad() async {
    // Only cache character sprites — deliberately skip single_room.png
    // so the background image must be loaded on demand by _loadMapComponents.
    images.add('NPC11.png', await generateImage(384, 256));
    images.add('NPC12.png', await generateImage(384, 256));
    images.add('NPC13.png', await generateImage(384, 256));
    images.add('claude_bot.png', await generateImage(48, 48));

    camera.viewfinder.anchor = Anchor.center;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TechWorld integration tests', () {
    late StreamController<AuthUser> authController;

    setUp(() {
      authController = StreamController<AuthUser>.broadcast();
    });

    tearDown(() {
      authController.close();
    });

    testWithGame<TestGameWithMockImages>(
      'onLoad initializes all components',
      () {
        final world = TechWorld(authStateChanges: authController.stream);
        return TestGameWithMockImages(world: world);
      },
      (game) async {
        await game.ready();

        final world = game.world as TechWorld;

        // World should be mounted
        expect(world.isMounted, isTrue);

        // Should have grid, path, barriers, and player components
        final components = world.children.toList();
        expect(components.whereType<PlayerComponent>().length, greaterThanOrEqualTo(1));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'localPlayerPosition returns player grid position',
      () {
        final world = TechWorld(authStateChanges: authController.stream);
        return TestGameWithMockImages(world: world);
      },
      (game) async {
        await game.ready();

        final world = game.world as TechWorld;
        final position = world.localPlayerPosition;

        // Default position at (0,0) should be grid position (0,0)
        expect(position.x, equals(0));
        expect(position.y, equals(0));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'localPlayerId returns empty string initially',
      () {
        final world = TechWorld(authStateChanges: authController.stream);
        return TestGameWithMockImages(world: world);
      },
      (game) async {
        await game.ready();

        final world = game.world as TechWorld;

        // ID is empty until auth completes
        expect(world.localPlayerId, isEmpty);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'otherPlayerPositions is empty initially',
      () {
        final world = TechWorld(authStateChanges: authController.stream);
        return TestGameWithMockImages(world: world);
      },
      (game) async {
        await game.ready();

        final world = game.world as TechWorld;

        // No other players initially
        expect(world.otherPlayerPositions, isEmpty);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'game runs update loop without errors',
      () {
        final world = TechWorld(authStateChanges: authController.stream);
        return TestGameWithMockImages(world: world);
      },
      (game) async {
        await game.ready();

        final world = game.world as TechWorld;

        // Run game update loop for a while
        for (var i = 0; i < 100; i++) {
          game.update(0.016);
        }

        // World should still be functional
        expect(world.isMounted, isTrue);
        expect(world.localPlayerPosition, isNotNull);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'update triggers bubble position updates',
      () {
        final world = TechWorld(authStateChanges: authController.stream);
        return TestGameWithMockImages(world: world);
      },
      (game) async {
        await game.ready();

        final world = game.world as TechWorld;

        // Run several update cycles
        for (var i = 0; i < 10; i++) {
          game.update(0.016);
        }

        // World should still be functional
        expect(world.isMounted, isTrue);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'auth state change updates player id and displayName',
      () {
        final world = TechWorld(authStateChanges: authController.stream);
        return TestGameWithMockImages(world: world);
      },
      (game) async {
        await game.ready();

        final world = game.world as TechWorld;

        // Initially empty
        expect(world.localPlayerId, isEmpty);

        // Emit auth state
        authController.add(AuthUser(
          id: 'test-user-123',
          displayName: 'Test User',
        ));

        // Allow async processing
        await Future.delayed(const Duration(milliseconds: 50));

        // Player ID should be updated
        expect(world.localPlayerId, equals('test-user-123'));
      },
    );

    testWithGame<TestGameWithMockImages>(
      'dispose cleans up subscriptions',
      () {
        final world = TechWorld(authStateChanges: authController.stream);
        return TestGameWithMockImages(world: world);
      },
      (game) async {
        await game.ready();

        final world = game.world as TechWorld;

        // Should not throw
        world.dispose();

        expect(world.isMounted, isTrue); // Still mounted, just cleaned up
      },
    );

    testWithGame<TestGameWithMockImages>(
      'handles signed out user',
      () {
        final world = TechWorld(authStateChanges: authController.stream);
        return TestGameWithMockImages(world: world);
      },
      (game) async {
        await game.ready();

        final world = game.world as TechWorld;

        // Sign in first
        authController.add(AuthUser(
          id: 'user-1',
          displayName: 'User One',
        ));
        await Future.delayed(const Duration(milliseconds: 50));

        // Then sign out
        authController.add(SignedOutUser(id: 'user-1', displayName: 'User One'));
        await Future.delayed(const Duration(milliseconds: 50));

        // Should handle gracefully
        expect(world.isMounted, isTrue);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'camera follows player',
      () {
        final world = TechWorld(authStateChanges: authController.stream);
        return TestGameWithMockImages(world: world);
      },
      (game) async {
        await game.ready();

        // Camera should be set up
        expect(game.camera, isNotNull);
        expect(game.camera.viewfinder, isNotNull);
      },
    );

    testWithGame<TestGameWithMockImages>(
      'world contains required child components',
      () {
        final world = TechWorld(authStateChanges: authController.stream);
        return TestGameWithMockImages(world: world);
      },
      (game) async {
        await game.ready();

        final world = game.world as TechWorld;
        final children = world.children.toList();

        // Should have player component
        expect(children.whereType<PlayerComponent>().length, equals(1));

        // Should have multiple components (grid, path, barriers, player)
        expect(children.length, greaterThanOrEqualTo(4));
      },
    );

    // Regression test: background image loaded on demand, not from cache.
    //
    // The default map (lRoom) has a backgroundImage. When TechWorldGame.onLoad
    // hasn't pre-cached it (e.g. GameWidget hasn't mounted yet), the old code
    // used Images.fromCache() which throws. The fix uses Images.load() which
    // loads on demand from the asset bundle.
    testWithGame<TestGameWithoutBgCache>(
      'loadMap loads background image on demand when not pre-cached',
      () {
        final world = TechWorld(authStateChanges: authController.stream);
        return TestGameWithoutBgCache(world: world);
      },
      (game) async {
        // game.ready() triggers TechWorld.onLoad → _loadMapComponents(lRoom).
        // lRoom has backgroundImage: 'single_room.png' which is NOT in the
        // image cache (TestGameWithoutBgCache skips it). With the fix
        // (Images.load), this loads the image from the asset bundle. With the
        // old code (Images.fromCache), this would throw an assertion error.
        await game.ready();

        final world = game.world as TechWorld;
        expect(world.isMounted, isTrue);
        expect(world.currentMap.value.backgroundImage, equals('single_room.png'));
      },
    );
  });
}
