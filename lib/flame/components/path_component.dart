import 'dart:ui';

import 'package:a_star_algorithm/a_star_algorithm.dart';
import 'package:flutter/foundation.dart';
import 'package:flame/components.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/direction.dart';

/// We use the a_star_algorithm to calculate a set of points that define a path
/// that avoids all barriers.
///
/// The [PathComponent] takes the barriers and uses the a_star_algorithm to
/// calculate a set of points between the start (player position) and end
/// (clicked point). The PathComponent also keeps the set of [RectangleComponent]s
/// corresponding to the grid points in canvas space, used to draw the path on
/// the canvas.
class PathComponent extends Component with HasWorldReference {
  List<(int, int)> _miniGridPoints = [];
  List<Vector2> _largeGridPoints = [];
  List<RectangleComponent> _pathRectangles = [];
  List<Direction> _pathDirections = [];
  final BarriersComponent _barriers;
  final _paint = Paint()..color = const Color.fromARGB(50, 255, 255, 255);
  final _startPaint = Paint()..color = const Color.fromARGB(150, 0, 255, 255);
  final _endPaint = Paint()..color = const Color.fromARGB(150, 255, 255, 0);

  PathComponent({required BarriersComponent barriers}) : _barriers = barriers;

  /// Use the a_star_algorithm to calculate a set of points that define a
  /// path that avoids all barriers.
  ///
  /// Also calculate a direction for each path segment from the points generated
  /// by the a_star_algorithm, and use the directions to create a list of
  /// [MoveEffect]s that will be passed to the [PlayerComponent] to provide
  /// player movment on taps.
  void calculatePath({required (int, int) start, required (int, int) end}) {
    _miniGridPoints = AStar(
      rows: gridSize,
      columns: gridSize,
      start: start,
      end: end,
      barriers: _barriers.tuples,
    ).findThePath().toList();

    debugPrint('$_miniGridPoints');

    _largeGridPoints = [];
    _pathDirections = [];
    for (int i = 0; i < _miniGridPoints.length; i++) {
      final (x, y) = _miniGridPoints[i];
      _largeGridPoints.add(
          Vector2.array([x * gridSquareSizeDouble, y * gridSquareSizeDouble]));

      if (i == _miniGridPoints.length - 1) break;
      final (x1, y1) = _miniGridPoints[i];
      final (x2, y2) = _miniGridPoints[i + 1];
      final delta = (x2 - x1, y2 - y1);
      _pathDirections.add(directionFromTuple[delta] ?? Direction.none);
    }
  }

  void drawPath() {
    for (final rectangle in _pathRectangles) {
      world.remove(rectangle);
    }

    _pathRectangles = _miniGridPoints.map<RectangleComponent>(
      (point) {
        final (x, y) = point;
        return RectangleComponent(
          position: Vector2.array(
              [x * gridSquareSizeDouble, y * gridSquareSizeDouble]),
          size: Vector2.all(gridSquareSizeDouble),
          paint: _paint,
        );
      },
    ).toList();

    // color the start and end points
    if (_pathRectangles.isNotEmpty) {
      _pathRectangles[0].paint = _startPaint;
      _pathRectangles[_pathRectangles.length - 1].paint = _endPaint;
    }

    for (final rectangle in _pathRectangles) {
      world.add(rectangle);
    }
  }

  List<Vector2> get largeGridPoints => _largeGridPoints;
  List<Direction> get directions => _pathDirections;
}
