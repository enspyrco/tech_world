import 'dart:ui' show Color;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle;
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
/// World's y-priority sorting alongside player characters. If they were
/// children of *this* component they would be depth-sorted only among
/// themselves, breaking y-based depth sorting with other world-level
/// components (players, other sprites).
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
    this.priorityOverrides,
    this.lintelOverlayPositions,
    this.debugPriorities = false,
  });

  final TileLayerData layerData;
  final TilesetRegistry registry;

  /// Sparse map of `(x, y)` → priority for tiles that need a non-default
  /// priority. Used for wall caps that should sort with the barrier row below
  /// them rather than their natural y position.
  final Map<(int, int), int>? priorityOverrides;

  /// Positions that need half-height (bottom-only) rendering — the "alpha
  /// punch" for lintel overlays. These tiles contain both floor art (top half)
  /// and wall overhang art (bottom half). Only the bottom half renders in the
  /// object layer; the floor layer shows the full tile behind the player.
  final Set<(int, int)>? lintelOverlayPositions;

  /// When true, renders priority labels on each object tile for debugging.
  final bool debugPriorities;

  final List<Component> _sprites = [];
  final List<TextComponent> _debugLabels = [];

  @override
  Future<void> onLoad() async {
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final ref = layerData.tileAt(x, y);
        if (ref == null) continue;

        final sprite = registry.getSpriteForTile(ref.tilesetId, ref.tileIndex);
        if (sprite == null) continue;

        final effectivePriority = priorityOverrides?[(x, y)] ?? y;
        final isLintelOverlay =
            lintelOverlayPositions?.contains((x, y)) ?? false;

        final Component component;

        if (isLintelOverlay) {
          // Partial-height sprite: render only the top portion of the tile
          // (the dark wall overhang), clipping the bottom portion (floor
          // coloured pixels). The floor layer shows the full tile behind
          // the player; this overlay renders the overhang in front.
          //
          // The overhang art occupies roughly the top 21px of 32px tiles.
          // We clip the bottom 11px (the floor portion).
          const clipBottom = 11.0;
          final visibleHeight = gridSquareSizeDouble - clipBottom;
          final overhangSprite = Sprite(
            sprite.image,
            srcPosition: sprite.srcPosition,
            srcSize: Vector2(sprite.srcSize.x, visibleHeight),
          );
          component = SpriteComponent(
            sprite: overhangSprite,
            position: Vector2(
              x * gridSquareSizeDouble,
              y * gridSquareSizeDouble,
            ),
            size: Vector2(gridSquareSizeDouble, visibleHeight),
            priority: effectivePriority,
          );
        } else {
          component = SpriteComponent(
            sprite: sprite,
            position: Vector2(
              x * gridSquareSizeDouble,
              y * gridSquareSizeDouble,
            ),
            size: Vector2.all(gridSquareSizeDouble),
            priority: effectivePriority,
          );
        }
        _sprites.add(component);

        // Debug: add priority label on each object tile.
        if (debugPriorities) {
          final isOverridden = priorityOverrides?.containsKey((x, y)) ?? false;
          final label = TextComponent(
            text: isLintelOverlay
                ? '($x,$y)p$effectivePriority½'
                : '($x,$y)p$effectivePriority',
            position: Vector2(
              x * gridSquareSizeDouble + 2,
              y * gridSquareSizeDouble + 2,
            ),
            priority: 9999, // always on top
            textRenderer: TextPaint(
              style: TextStyle(
                fontSize: 8,
                color: isLintelOverlay
                    ? const Color(0xFFFF00FF) // magenta for lintel overlay
                    : isOverridden
                        ? const Color(0xFFFF0000) // red for overridden
                        : const Color(0xFF00FF00), // green for default
              ),
            ),
          );
          // TextComponent is a PositionComponent, not SpriteComponent.
          // Track separately for debug cleanup.
          _debugLabels.add(label);
        }
      }
    }

    // Add all sprites to the parent (the World), not to this component,
    // so they participate in the World's y-sorting.
    final parentComponent = parent;
    if (parentComponent != null) {
      for (final sprite in _sprites) {
        parentComponent.add(sprite);
      }
      for (final label in _debugLabels) {
        parentComponent.add(label);
      }
    }
  }

  /// Hide all object tiles (e.g. when entering editor mode).
  void hide() {
    for (final sprite in _sprites) {
      sprite.removeFromParent();
    }
    for (final label in _debugLabels) {
      label.removeFromParent();
    }
  }

  /// Show all object tiles (e.g. when exiting editor mode).
  void show() {
    final parentComponent = parent;
    if (parentComponent != null) {
      for (final sprite in _sprites) {
        parentComponent.add(sprite);
      }
      for (final label in _debugLabels) {
        parentComponent.add(label);
      }
    }
  }

  @override
  void onRemove() {
    hide();
    super.onRemove();
  }
}
