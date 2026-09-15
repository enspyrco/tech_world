import 'package:tech_world/flame/shared/direction.dart';

/// What a [PlayerComponent]'s sprite sheet is currently showing.
///
/// Deliberately NOT a value on [Direction]: a [Direction] carries movement
/// offsets and is the *input* to pathing, while an animation state is the
/// *output* the renderer shows. A wave has no direction and no offset, so
/// folding it into [Direction] would put a non-movement concept inside the type
/// the A* pathing switches over. Same split [DreamfinderState] already makes.
enum PlayerAnimState {
  walkDown,
  walkLeft,
  walkUp,
  walkRight,
  walkDownLeft,
  walkDownRight,
  walkUpLeft,
  walkUpRight,

  /// One-shot front-facing wave — sprite cells 12–15, the strip that ships in
  /// every player sheet but went unrendered until #14's Step-0 spike found it.
  wave;

  /// The walk state that shows [d].
  ///
  /// [Direction.none] maps to [walkDown] (the resting pose) because the player
  /// sheet has no dedicated idle strip — frame 0 of the down-walk *is* idle.
  static PlayerAnimState forDirection(Direction d) => switch (d) {
        Direction.up => PlayerAnimState.walkUp,
        Direction.down => PlayerAnimState.walkDown,
        Direction.left => PlayerAnimState.walkLeft,
        Direction.right => PlayerAnimState.walkRight,
        Direction.upLeft => PlayerAnimState.walkUpLeft,
        Direction.upRight => PlayerAnimState.walkUpRight,
        Direction.downLeft => PlayerAnimState.walkDownLeft,
        Direction.downRight => PlayerAnimState.walkDownRight,
        Direction.none => PlayerAnimState.walkDown,
      };
}
