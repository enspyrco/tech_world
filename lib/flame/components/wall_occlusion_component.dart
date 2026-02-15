import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// Creates sprite overlays for each barrier cell using a sub-region of the
/// background PNG. These overlays sit above the background but use y-based
/// priority so that characters walking behind (north of) walls are occluded.
///
/// Each overlay extends [_wallArtHeight] cells above the barrier to cover the
/// visible wall face in the PNG. The priority equals the barrier's y so that
/// characters south of the wall (higher y) render in front, and characters
/// north (lower y) render behind.
class WallOcclusionComponent extends Component {
  WallOcclusionComponent({
    required ui.Image backgroundImage,
    required List<Point<int>> barriers,
  })  : _backgroundImage = backgroundImage,
        _barriers = barriers;

  final ui.Image _backgroundImage;
  final List<Point<int>> _barriers;
  final List<SpriteComponent> _overlays = [];

  /// How many cells above each barrier the wall art extends in the PNG.
  static const _wallArtHeight = 1;

  @override
  Future<void> onLoad() async {
    for (final barrier in _barriers) {
      // The overlay starts _wallArtHeight cells above the barrier and extends
      // down through the barrier cell itself.
      final topY = max(0, barrier.y - _wallArtHeight);
      final heightInCells = barrier.y - topY + 1;

      final srcX = barrier.x * gridSquareSizeDouble;
      final srcY = topY * gridSquareSizeDouble;
      final srcH = heightInCells * gridSquareSizeDouble;

      // Skip if the source rect falls outside the image bounds.
      if (srcX + gridSquareSizeDouble > _backgroundImage.width ||
          srcY + srcH > _backgroundImage.height) {
        continue;
      }

      final sprite = Sprite(
        _backgroundImage,
        srcPosition: Vector2(srcX, srcY),
        srcSize: Vector2(gridSquareSizeDouble, srcH),
      );

      final overlay = SpriteComponent(
        sprite: sprite,
        position: Vector2(srcX, srcY),
        size: Vector2(gridSquareSizeDouble, srcH),
        priority: barrier.y,
      );

      _overlays.add(overlay);
    }

    // Add all overlays to the parent (the World).
    final parentComponent = parent;
    if (parentComponent != null) {
      for (final overlay in _overlays) {
        parentComponent.add(overlay);
      }
    }
  }

  /// Hide wall overlays (e.g. when entering editor mode).
  void hide() {
    for (final overlay in _overlays) {
      overlay.removeFromParent();
    }
  }

  /// Show wall overlays (e.g. when exiting editor mode).
  void show() {
    final parentComponent = parent;
    if (parentComponent != null) {
      for (final overlay in _overlays) {
        parentComponent.add(overlay);
      }
    }
  }

  @override
  void onRemove() {
    hide();
    super.onRemove();
  }
}
