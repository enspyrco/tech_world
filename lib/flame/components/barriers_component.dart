import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:pathfinding/core/grid.dart' as pf;
import 'package:tech_world/flame/shared/constants.dart';

/// A [BarriersComponent] keeps a list of points that the player cannot walk
/// through and adds RectangleComponents for each point so the barrier are
/// drawn on screen. The points are part of the minigrid - a 2d grid of integers
/// that A* operates on.
class BarriersComponent extends PositionComponent with HasWorldReference {
  BarriersComponent({required List<Point<int>> barriers}) : _points = barriers;

  final Paint _paint = Paint()..color = const Color.fromRGBO(0, 0, 255, 0);

  final List<RectangleComponent> _rectangles = [];

  /// When false, barrier rectangles are hidden (used during map editor mode).
  bool get renderBarriers => _renderBarriers;
  bool _renderBarriers = false;
  set renderBarriers(bool value) {
    _renderBarriers = value;
    for (final rect in _rectangles) {
      if (value) {
        rect.paint.color = const Color.fromRGBO(0, 0, 255, 1);
      } else {
        rect.paint.color = const Color.fromRGBO(0, 0, 255, 0);
      }
    }
  }

  /// The list of [Point]s that make up the barriers in the minigrid space.
  final List<Point<int>> _points;

  /// Returns barriers as tuples for compatibility.
  List<(int, int)> get tuples => _points.map((p) => (p.x, p.y)).toList();

  /// Creates a pathfinding Grid with barriers marked as unwalkable.
  /// Note: Grid must be cloned before each pathfinding call.
  pf.Grid createGrid() {
    // Create matrix: 0 = walkable, 1 = obstacle
    final matrix = List.generate(
      gridSize,
      (_) => List.filled(gridSize, 0),
    );

    for (final point in _points) {
      matrix[point.y][point.x] = 1;
    }

    return pf.Grid(gridSize, gridSize, matrix);
  }

  /// Remove all barrier rectangles from the world.
  void removeBarriers() {
    for (final rect in _rectangles) {
      rect.removeFromParent();
    }
    _rectangles.clear();
  }

  /// Add [RectangleComponent]s to draw each barrier in the large grid that is
  /// in canvas space.
  @override
  onLoad() {
    for (int i = 0; i < _points.length; i++) {
      final rect = RectangleComponent(
        position: Vector2(_points[i].x * gridSquareSizeDouble,
            _points[i].y * gridSquareSizeDouble),
        size: Vector2.array([gridSquareSizeDouble, gridSquareSizeDouble]),
        anchor: Anchor.center,
        paint: Paint()..color = _paint.color,
      );
      _rectangles.add(rect);
      world.add(rect);
    }
  }
}
