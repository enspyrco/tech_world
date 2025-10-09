import 'dart:ui';

import 'package:flame/components.dart';
import 'package:tech_world/flame/shared/constants.dart';

/// The [GridComponent] is made up of a set of one pixel wide [RectangleComponent]s
/// that allow drawing the grid on the canvas.
class GridComponent extends PositionComponent with HasWorldReference {
  final Paint _paint = Paint()..color = const Color.fromRGBO(255, 0, 255, 1);

  @override
  onLoad() {
    for (int i = 0; i < gridSize + 1; i++) {
      world.add(
        RectangleComponent(
            position: Vector2(gridSquareSizeDouble * i, 0.0),
            size: Vector2.array([1, gridSize * gridSquareSizeDouble]),
            anchor: Anchor.topCenter,
            paint: _paint),
      );
    }
    for (int i = 0; i < gridSize + 1; i++) {
      world.add(
        RectangleComponent(
            position: Vector2(0, gridSquareSizeDouble * i),
            size: Vector2.array([gridSize * gridSquareSizeDouble, 1]),
            anchor: Anchor.bottomLeft,
            paint: _paint),
      );
    }
  }
}
