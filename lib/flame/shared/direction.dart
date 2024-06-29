import 'dart:math';

import 'package:tech_world/flame/shared/constants.dart';

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
