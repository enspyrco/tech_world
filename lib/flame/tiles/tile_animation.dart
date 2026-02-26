/// Defines an animation sequence for a tile within a tileset.
///
/// Animation is a tileset-level property — a tile index either animates or it
/// doesn't, regardless of which map it's placed on. When a rendering component
/// encounters an animated tile, it cycles through [frameIndices] at
/// [stepTime]-second intervals instead of rendering a static sprite.
///
/// All tiles sharing the same [TileAnimation] animate in sync (standard for
/// pixel-art water, lava, torches, etc.).
class TileAnimation {
  const TileAnimation({
    required this.baseTileIndex,
    required this.frameIndices,
    this.stepTime = 0.3,
  }) : assert(stepTime > 0, 'stepTime must be positive');

  /// The canonical tile index for this animation — typically the first frame.
  ///
  /// Used as the identifier when looking up animations. Any frame index in
  /// [frameIndices] maps back to this animation.
  final int baseTileIndex;

  /// All frame tile indices in order. Must contain at least 2 entries for a
  /// meaningful animation.
  final List<int> frameIndices;

  /// Seconds per frame. Must be positive. Defaults to 0.3s (≈3.3 fps).
  final double stepTime;

  /// The number of frames in this animation.
  int get frameCount => frameIndices.length;

  /// Whether [tileIndex] is one of this animation's frame indices.
  ///
  /// Used to detect animated tiles regardless of which frame was painted in
  /// the editor.
  bool containsIndex(int tileIndex) => frameIndices.contains(tileIndex);
}
