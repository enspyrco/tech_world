import 'package:tech_world/flame/shared/direction.dart';

/// Animation states for the Dreamfinder character.
///
/// Unlike regular players who only have directional walk animations,
/// Dreamfinder has additional states for idle behavior and reactions.
enum DreamfinderState {
  /// Looping "working" idle animation (sprite sheet row 1).
  working,

  /// One-shot "surprised" reaction (sprite sheet row 2).
  surprised,

  /// Standing still, facing down (frame 0 of walkDown).
  idle,

  // Walk directions (sprite sheet row 0).
  walkDown,
  walkLeft,
  walkUp,
  walkRight,
  walkDownLeft,
  walkDownRight,
  walkUpLeft,
  walkUpRight,
}

/// Maps a movement [Direction] to the corresponding walk animation state.
DreamfinderState walkStateFromDirection(Direction d) => switch (d) {
      Direction.up => DreamfinderState.walkUp,
      Direction.down => DreamfinderState.walkDown,
      Direction.left => DreamfinderState.walkLeft,
      Direction.right => DreamfinderState.walkRight,
      Direction.upLeft => DreamfinderState.walkUpLeft,
      Direction.upRight => DreamfinderState.walkUpRight,
      Direction.downLeft => DreamfinderState.walkDownLeft,
      Direction.downRight => DreamfinderState.walkDownRight,
      Direction.none => DreamfinderState.idle,
    };
