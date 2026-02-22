import 'package:tech_world/flame/tiles/tile_animation.dart';

/// Lightweight animation ticker that cycles through frame indices at a fixed
/// step time.
///
/// Unlike Flame's `SpriteAnimationTicker`, this works with tile indices rather
/// than `Sprite` objects, deferring sprite lookup to render time. This avoids
/// importing Flame's internal `src/` API and keeps the animation logic simple.
class AnimationTicker {
  AnimationTicker(this.animation);

  final TileAnimation animation;

  double _elapsed = 0;

  /// The tile index of the current animation frame.
  int get currentFrameIndex {
    if (animation.frameCount == 0) return animation.baseTileIndex;
    final frameIdx = (_elapsed / animation.stepTime).floor() %
        animation.frameCount;
    return animation.frameIndices[frameIdx];
  }

  /// Advance the animation clock by [dt] seconds.
  void update(double dt) {
    _elapsed += dt;
    // Wrap at cycle boundary to prevent floating-point precision loss over
    // long play sessions. The modulo keeps _elapsed within one cycle so
    // currentFrameIndex stays accurate.
    final cycleDuration = animation.stepTime * animation.frameCount;
    if (_elapsed >= cycleDuration) {
      _elapsed %= cycleDuration;
    }
  }
}
