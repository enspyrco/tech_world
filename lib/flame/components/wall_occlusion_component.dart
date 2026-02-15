import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// Creates sprite overlays for each barrier cell using a sub-region of the
/// background PNG. These overlays sit above the background but use y-based
/// priority so that characters walking behind (north of) walls are occluded.
class WallOcclusionComponent extends Component {
  WallOcclusionComponent({
    required ui.Image backgroundImage,
    required List<Point<int>> barriers,
  })  : _backgroundImage = backgroundImage,
        _barriers = barriers;

  final ui.Image _backgroundImage;
  final List<Point<int>> _barriers;
  final List<SpriteComponent> _overlays = [];

  @override
  Future<void> onLoad() async {
    for (final barrier in _barriers) {
      final srcX = barrier.x * gridSquareSizeDouble;
      final srcY = barrier.y * gridSquareSizeDouble;

      // Skip if the barrier cell falls outside the image bounds.
      if (srcX + gridSquareSizeDouble > _backgroundImage.width ||
          srcY + gridSquareSizeDouble > _backgroundImage.height) {
        continue;
      }

      final sprite = Sprite(
        _backgroundImage,
        srcPosition: Vector2(srcX, srcY),
        srcSize: Vector2.all(gridSquareSizeDouble),
      );

      final overlay = SpriteComponent(
        sprite: sprite,
        position: Vector2(srcX, srcY),
        size: Vector2.all(gridSquareSizeDouble),
        // +2 accounts for 64px-tall character sprites spanning 2 grid rows.
        priority: barrier.y + 2,
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
