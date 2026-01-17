import 'package:tech_world/flame/shared/constants.dart';

/// We use an enhanced enum for direction that has up, down, left, right as
/// well as the diagonals. Each direction has the relevant offsets that are used
/// to create the [MoveEffect]s that are applied in order to
/// make the player follow the path.
/// The [PlayerComponent] is a
/// [SpriteAnimationGroupComponent] that maps direction to the appropriate
/// animation.
enum Direction {
  up(offsetX: 0, offsetY: -gridSquareSizeDouble),
  upLeft(offsetX: -gridSquareSizeDouble, offsetY: -gridSquareSizeDouble),
  upRight(offsetX: gridSquareSizeDouble, offsetY: -gridSquareSizeDouble),
  down(offsetX: 0, offsetY: gridSquareSizeDouble),
  downLeft(offsetX: -gridSquareSizeDouble, offsetY: gridSquareSizeDouble),
  downRight(offsetX: gridSquareSizeDouble, offsetY: gridSquareSizeDouble),
  left(offsetX: -gridSquareSizeDouble, offsetY: 0),
  right(offsetX: gridSquareSizeDouble, offsetY: 0),
  none(offsetX: 0, offsetY: 0);

  const Direction({
    required this.offsetX,
    required this.offsetY,
  });

  final double offsetX;
  final double offsetY;
}

/// Map from tuple deltas to Direction (used by a_star_algorithm which uses (int, int) tuples)
const Map<(int, int), Direction> directionFromTuple = {
  (0, -1): Direction.up,
  (1, -1): Direction.upRight,
  (-1, 1): Direction.downLeft,
  (0, 1): Direction.down,
  (-1, -1): Direction.upLeft,
  (1, 1): Direction.downRight,
  (-1, 0): Direction.left,
  (1, 0): Direction.right,
};
