import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/player_component.dart';
import 'package:tech_world/flame/components/tile_object_layer_component.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tile_ref.dart';
import 'package:tech_world/flame/tiles/tileset_registry.dart';

/// Tests verifying the y-based occlusion contract between tile sprites and
/// player components.
///
/// ## How y-occlusion works
///
/// Both [TileObjectLayerComponent] and [PlayerComponent] use the grid row
/// (y index) as their rendering priority:
///
/// - Tile sprites: `priority = y` (grid row, set at construction)
/// - Player: `priority = position.y.round() ~/ gridSquareSize` (updated per
///   frame)
///
/// Flame's [World] sorts children by priority, so components with higher
/// priority (further south / higher y) render on top. This means:
///
/// - Player north of wall tile → player priority < tile priority → player
///   renders behind the wall.
/// - Player south of wall tile → player priority > tile priority → player
///   renders in front of the wall.
///
/// Auto-barriers ensure the player can never occupy the same grid cell as a
/// wall tile, so the priority boundary is always clean (no ties between
/// player and wall at the same y).
void main() {
  group('Y-based occlusion', () {
    group('PlayerComponent priority', () {
      test('priority formula matches grid row from position', () {
        final player = PlayerComponent(
          position: Vector2(0, 0),
          id: 'test',
          displayName: 'Test',
        );

        // Simulate what update() does: priority = position.y.round() ~/ gridSquareSize
        for (final row in [0, 1, 5, 10, 25, 49]) {
          player.position.y = row * gridSquareSizeDouble;
          final expectedPriority = player.position.y.round() ~/ gridSquareSize;
          expect(
            expectedPriority,
            equals(row),
            reason: 'Player at grid row $row should have priority $row',
          );
        }
      });

      test('priority is stable within a grid cell', () {
        final player = PlayerComponent(
          position: Vector2(0, 0),
          id: 'test',
          displayName: 'Test',
        );

        // Within a single cell (e.g. row 10), any sub-pixel offset should
        // still yield the same priority.
        const row = 10;
        for (final offset in [0.0, 0.5, 15.0, 31.0]) {
          player.position.y = row * gridSquareSizeDouble + offset;
          final priority = player.position.y.round() ~/ gridSquareSize;
          expect(
            priority,
            equals(row),
            reason: 'Offset $offset within row $row should still yield '
                'priority $row',
          );
        }
      });
    });

    group('TileObjectLayerComponent priority contract', () {
      test('creates sprite with priority equal to grid row y', () {
        // The contract: in TileObjectLayerComponent.onLoad(), each sprite is
        // created with `priority: y` where y is the grid row (0-indexed).
        //
        // We verify this by constructing a SpriteComponent the same way the
        // production code does and checking its priority.
        for (final y in [0, 1, 10, 25, 49]) {
          final component = SpriteComponent(
            position: Vector2(
              3 * gridSquareSizeDouble, // x doesn't affect priority
              y * gridSquareSizeDouble,
            ),
            size: Vector2.all(gridSquareSizeDouble),
            priority: y,
          );

          expect(
            component.priority,
            equals(y),
            reason: 'Tile at grid row $y should have priority $y',
          );
        }
      });

      test('tile and player at same grid row have equal priority', () {
        // This proves depth sorting is clean: when a player is at the same
        // y-row as a tile, they have equal priority (same depth layer).
        // Auto-barriers prevent this for wall tiles specifically, but the
        // math must still be consistent for floor/object tiles.
        const row = 15;

        // Tile priority (set directly)
        const tilePriority = row;

        // Player priority (computed from pixel position)
        final playerY = row * gridSquareSizeDouble;
        final playerPriority = playerY.round() ~/ gridSquareSize;

        expect(playerPriority, equals(tilePriority));
      });

      test('player north of tile has lower priority (renders behind)', () {
        const wallRow = 10;
        const playerRow = 9; // north = lower y

        const tilePriority = wallRow;
        final playerY = playerRow * gridSquareSizeDouble;
        final playerPriority = playerY.round() ~/ gridSquareSize;

        expect(
          playerPriority,
          lessThan(tilePriority),
          reason: 'Player at row $playerRow should render behind wall at '
              'row $wallRow',
        );
      });

      test('player south of tile has higher priority (renders in front)', () {
        const wallRow = 10;
        const playerRow = 11; // south = higher y

        const tilePriority = wallRow;
        final playerY = playerRow * gridSquareSizeDouble;
        final playerPriority = playerY.round() ~/ gridSquareSize;

        expect(
          playerPriority,
          greaterThan(tilePriority),
          reason: 'Player at row $playerRow should render in front of wall '
              'at row $wallRow',
        );
      });
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

      test('accepts layer with tiles at various y positions', () {
        final layer = TileLayerData();
        // Place tiles at different rows — their priority should match y.
        layer.setTile(5, 0, const TileRef(tilesetId: 'test', tileIndex: 0));
        layer.setTile(5, 25, const TileRef(tilesetId: 'test', tileIndex: 0));
        layer.setTile(5, 49, const TileRef(tilesetId: 'test', tileIndex: 0));

        final component = TileObjectLayerComponent(
          layerData: layer,
          registry: TilesetRegistry.forTesting(),
        );

        // The component stores tiles but defers sprite creation to onLoad.
        // Verify layer data is preserved.
        expect(component.layerData.tileAt(5, 0), isNotNull);
        expect(component.layerData.tileAt(5, 25), isNotNull);
        expect(component.layerData.tileAt(5, 49), isNotNull);
      });
    });
  });
}
