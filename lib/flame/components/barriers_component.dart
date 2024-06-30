import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// A [BarriersComponent] keeps a list of points that the player cannot walk
/// through and adds RectangleComponents for each point so the barrier are
/// drawn on screen. The points are part of the minigrid - a 2d grid of integers
/// that A* operates on.
class BarriersComponent extends Component with HasWorldReference {
  BarriersComponent();

  final Paint _paint = Paint()..color = const Color.fromRGBO(0, 0, 255, 1);

  /// The list of [Point]s that make up the barriers in the minigrid space
  final List<Point<int>> points = const [
    Point(5, 2),
    Point(5, 3),
    Point(5, 4),
    Point(5, 5),
    Point(5, 6),
    Point(5, 7),
    Point(5, 8),
    Point(5, 9),
    Point(7, 7),
    Point(7, 8),
    Point(6, 8),
    Point(1, 0),
    Point(1, 1),
    Point(1, 2),
    Point(1, 3),
    Point(1, 4),
    Point(1, 5),
    Point(1, 6),
    Point(1, 7),
    Point(1, 8),
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
            anchor: Anchor.topLeft,
            paint: _paint),
      );
    }
  }
}
