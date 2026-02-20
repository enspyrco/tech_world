import 'package:flame/components.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/tiles/tile_layer_data.dart';
import 'package:tech_world/flame/tiles/tileset_registry.dart';

/// Renders the object tile layer as individual [SpriteComponent]s with
/// y-based priority for depth sorting.
///
/// ## Parent-injection pattern
///
/// Sprites are **not** added as children of this component. Instead, [onLoad]
/// adds them directly to the parent [World] so that they participate in the
/// World's y-priority sorting alongside player characters and
/// [WallOcclusionComponent] overlays. If they were children of *this*
/// component they would be depth-sorted only among themselves, breaking
/// occlusion with other world-level components.
///
/// **Ownership caveat:** This component tracks every sprite in [_sprites] but
/// the sprites' `parent` is the World. [hide], [show], and [onRemove]
/// maintain this relationship — external code should not remove these sprites
/// from the World independently.
///
/// Supports [hide] and [show] for toggling visibility during editor mode.
class TileObjectLayerComponent extends Component {
  TileObjectLayerComponent({
    required this.layerData,
    required this.registry,
  });

  final TileLayerData layerData;
  final TilesetRegistry registry;

  final List<SpriteComponent> _sprites = [];

  @override
  Future<void> onLoad() async {
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final ref = layerData.tileAt(x, y);
        if (ref == null) continue;

        final sprite = registry.getSpriteForTile(ref.tilesetId, ref.tileIndex);
        if (sprite == null) continue;

        final component = SpriteComponent(
          sprite: sprite,
          position: Vector2(
            x * gridSquareSizeDouble,
            y * gridSquareSizeDouble,
          ),
          size: Vector2.all(gridSquareSizeDouble),
          priority: y,
        );

        _sprites.add(component);
      }
    }

    // Add all sprites to the parent (the World), not to this component,
    // so they participate in the World's y-sorting.
    final parentComponent = parent;
    if (parentComponent != null) {
      for (final sprite in _sprites) {
        parentComponent.add(sprite);
      }
    }
  }

  /// Hide all object tiles (e.g. when entering editor mode).
  void hide() {
    for (final sprite in _sprites) {
      sprite.removeFromParent();
    }
  }

  /// Show all object tiles (e.g. when exiting editor mode).
  void show() {
    final parentComponent = parent;
    if (parentComponent != null) {
      for (final sprite in _sprites) {
        parentComponent.add(sprite);
      }
    }
  }

  @override
  void onRemove() {
    hide();
    super.onRemove();
  }
}
