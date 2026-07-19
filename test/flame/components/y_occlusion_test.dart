import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/components/tile_object_layer_component.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tech_world_game.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/flame/tiles/tileset.dart';
import 'package:tech_world/flame/tiles/tileset_registry.dart';

/// A [TechWorldGame] with mock images so real [PlayerComponent]s load their
/// sprite sheets, plus a pre-registered 1×1 tileset so
/// [TileObjectLayerComponent] produces real sprites. [PlayerComponent] asserts
/// its game is a [TechWorldGame], so a bare [FlameGame] won't do.
class _OcclusionTestGame extends TechWorldGame {
  _OcclusionTestGame() : super(world: World());

  late final TilesetRegistry registry;

  @override
  Future<void> onLoad() async {
    // Player sprite sheet (12 frames of 32×64 across 4 directions).
    images.add('NPC11.png', await generateImage(384, 256));

    registry = TilesetRegistry(images: images);
    registry.loadFromImage(
      const Tileset(
        id: 't',
        name: 'test',
        imagePath: 't.png',
        tileSize: gridSquareSize,
        columns: 1,
        rows: 1,
      ),
      await generateImage(gridSquareSize, gridSquareSize),
    );
    camera.viewfinder.anchor = Anchor.center;
  }
}

/// Tests verifying the y-based occlusion contract *between* real
/// [TileObjectLayerComponent] sprites and real [PlayerComponent]s.
///
/// ## How y-occlusion works
///
/// Flame's [World] sorts children by `priority` (higher renders on top).
/// Depth-sorting characters against wall tiles requires both to live in the
/// **same priority space**:
///
/// - Characters: `priority = row * kPriorityStride + xTieBreak`, where
///   `xTieBreak ∈ [0, kPriorityStride)` — see [PlayerComponent.update].
/// - Object tiles: `priority = (override ?? row) * kPriorityStride`.
///
/// Because the character tie-break is strictly less than `kPriorityStride`, a
/// character on the *same* effective row as a tile deterministically renders
/// in front (the goal of PR #376), while a character one row north renders
/// behind (occluded by the wall top / archway).
///
/// ## Regression guard (PR #376 → this fix)
///
/// #376 scaled only the *character* side by `kPriorityStride` and left the
/// object layer at raw grid-y. That put every wall top ~1000× below any
/// character, so the player rendered in front of all wall tops and archways —
/// occlusion silently died for months. These tests read the **real** priority
/// fields off both components (never re-deriving the formula) so the scale
/// contract can never drift apart again undetected.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A north-facing wall face sits at [barrierRow]; its cap tile renders one
  // row north (at [capRow]) but is priority-bumped to the barrier row so it
  // sorts with the wall face and occludes a player walking above it.
  const barrierRow = 10;
  const capRow = barrierRow - 1;
  const capX = 5;

  /// Loads an object layer holding a single wall-cap tile at ([capX], [capRow])
  /// whose priority override is the barrier row, and returns the real sprite.
  Future<SpriteComponent> loadCapSprite(_OcclusionTestGame game) async {
    final layer = TileLayerData()
      ..setTile(capX, capRow, const TileRef(tilesetId: 't', tileIndex: 0));

    final objectLayer = TileObjectLayerComponent(
      layerData: layer,
      registry: game.registry,
      priorityOverrides: const {(capX, capRow): barrierRow},
    );
    await game.world.add(objectLayer);
    await game.ready();

    final capPos =
        Vector2(capX * gridSquareSizeDouble, capRow * gridSquareSizeDouble);
    return game.world.children
        .whereType<SpriteComponent>()
        .firstWhere((s) => s.position == capPos);
  }

  /// Adds a real player, positions it at [row], drives one frame so
  /// [PlayerComponent.update] sets `priority`, and returns the live component.
  Future<PlayerComponent> playerAtRow(_OcclusionTestGame game, int row) async {
    final player = PlayerComponent(
      position: Vector2(0, row * gridSquareSizeDouble),
      id: 'p',
      displayName: 'P',
    );
    await game.world.add(player);
    await game.ready();
    game.update(0); // triggers the per-frame priority computation
    return player;
  }

  group('Y-based occlusion (real component priorities)', () {
    testWithGame<_OcclusionTestGame>(
      'wall cap and characters share the same priority scale',
      _OcclusionTestGame.new,
      (game) async {
        final cap = await loadCapSprite(game);
        // Cap is bumped to the barrier row, on the character scale.
        expect(cap.priority, equals(barrierRow * kPriorityStride));
      },
    );

    testWithGame<_OcclusionTestGame>(
      'player north of the wall renders BEHIND its cap (occluded)',
      _OcclusionTestGame.new,
      (game) async {
        final cap = await loadCapSprite(game);
        final player = await playerAtRow(game, capRow); // north of wall face
        expect(
          player.priority,
          lessThan(cap.priority),
          reason: 'A player above the wall must be occluded by the wall top. '
              'This is the exact behavior PR #376 broke.',
        );
      },
    );

    testWithGame<_OcclusionTestGame>(
      'player at the wall row renders IN FRONT (deterministic tie-break)',
      _OcclusionTestGame.new,
      (game) async {
        final cap = await loadCapSprite(game);
        final player = await playerAtRow(game, barrierRow);
        expect(
          player.priority,
          greaterThanOrEqualTo(cap.priority),
          reason: 'Same-row player wins the tie (renders in front) — the '
              'deterministic same-y ordering #376 set out to provide.',
        );
      },
    );

    testWithGame<_OcclusionTestGame>(
      'player south of the wall renders IN FRONT',
      _OcclusionTestGame.new,
      (game) async {
        final cap = await loadCapSprite(game);
        final player = await playerAtRow(game, barrierRow + 1);
        expect(
          player.priority,
          greaterThan(cap.priority),
          reason: 'A player below the wall is closer to camera; renders '
              'in front.',
        );
      },
    );
  });

  group('TileObjectLayerComponent construction', () {
    test('can be constructed with layer data and registry', () {
      final layer = TileLayerData();
      final registry = TilesetRegistry.forTesting();

      final component = TileObjectLayerComponent(
        layerData: layer,
        registry: registry,
      );

      expect(component.layerData, same(layer));
      expect(component.registry, same(registry));
    });
  });
}
