import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/material.dart' show TextStyle;
import 'package:tech_world/flame/shared/constants.dart';

/// The [GridComponent] draws grid lines and axis labels on the canvas.
class GridComponent extends PositionComponent with HasWorldReference {
  final Paint _paint = Paint()..color = const Color.fromRGBO(255, 0, 255, 0.3);

  @override
  onLoad() {
    // Vertical grid lines + x-axis labels along the top
    for (int i = 0; i < gridSize + 1; i++) {
      world.add(
        RectangleComponent(
            position: Vector2(gridSquareSizeDouble * i, 0.0),
            size: Vector2.array([1, gridSize * gridSquareSizeDouble]),
            anchor: Anchor.topCenter,
            paint: _paint),
      );
      // X label every 2 cells
      if (i % 2 == 0) {
        world.add(
          TextComponent(
            text: '$i',
            position: Vector2(
                i * gridSquareSizeDouble + 2, -gridSquareSizeDouble + 4),
            priority: 9999,
            textRenderer: TextPaint(
              style: TextStyle(
                fontSize: 9,
                color: const Color(0xAAFF00FF),
              ),
            ),
          ),
        );
      }
    }

    // Horizontal grid lines + y-axis labels along the left
    for (int i = 0; i < gridSize + 1; i++) {
      world.add(
        RectangleComponent(
            position: Vector2(0, gridSquareSizeDouble * i),
            size: Vector2.array([gridSize * gridSquareSizeDouble, 1]),
            anchor: Anchor.bottomLeft,
            paint: _paint),
      );
      // Y label every 2 cells
      if (i % 2 == 0) {
        world.add(
          TextComponent(
            text: '$i',
            position: Vector2(
                -gridSquareSizeDouble + 4, i * gridSquareSizeDouble + 2),
            priority: 9999,
            textRenderer: TextPaint(
              style: TextStyle(
                fontSize: 9,
                color: const Color(0xAAFF00FF),
              ),
            ),
          ),
        );
      }
    }
  }
}
