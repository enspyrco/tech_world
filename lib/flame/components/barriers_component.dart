import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// A [BarriersComponent] keeps a list of points that the player cannot walk
/// through and adds RectangleComponents for each point so the barrier are
/// drawn on screen. The points are part of the minigrid - a 2d grid of integers
/// that A* operates on.
class BarriersComponent extends PositionComponent with HasWorldReference {
  BarriersComponent();

  final Paint _paint = Paint()..color = const Color.fromRGBO(0, 0, 255, 1);

  /// The list of [Point]s that make up the barriers in the minigrid space
  final List<Point<int>> points = const [
    Point(4, 7),
    Point(4, 8),
    Point(4, 9),
    Point(4, 10),
    Point(4, 11),
    Point(4, 12),
    Point(4, 13),
    Point(4, 14),
    Point(4, 15),
    Point(4, 16),
    Point(4, 17),
    Point(5, 7),
    Point(6, 7),
    Point(7, 7),
    Point(8, 7),
    Point(9, 7),
    Point(10, 7),
    Point(11, 7),
    Point(12, 7),
  ];

  /// Add [RectangleComponent]s to draw each barrier in the large grid that is
  /// in canvas space.
  @override
  onLoad() {
    for (int i = 0; i < points.length; i++) {
      world.add(
        RectangleComponent(
            position: Vector2(points[i].x * gridSquareSizeDouble,
                points[i].y * gridSquareSizeDouble),
            size: Vector2.array([gridSquareSizeDouble, gridSquareSizeDouble]),
            anchor: Anchor.center,
            paint: _paint),
      );
    }
  }
}
