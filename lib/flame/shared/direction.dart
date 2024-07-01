import 'dart:math';

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

final Map<Point, Direction> directionFrom = {
  const Point(0, -1): Direction.up,
  const Point(1, -1): Direction.upRight,
  const Point(-1, 1): Direction.downLeft,
  const Point(0, 1): Direction.down,
  const Point(-1, -1): Direction.upLeft,
  const Point(1, 1): Direction.downRight,
  const Point(-1, 0): Direction.left,
  const Point(1, 0): Direction.right,
};
