import 'dart:math';
import 'dart:ui';

import 'package:a_star_algorithm/a_star_algorithm.dart';
import 'package:flame/components.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/direction.dart';

class PathComponent extends Component with HasWorldReference {
  List<Point> _miniGridPoints = [];
  List<Vector2> _largeGridPoints = [];
  List<RectangleComponent> _pathRectangles = [];
  List<Direction> _pathDirections = [];
  final BarriersComponent _barriers;
  final _paint = Paint()..color = const Color.fromARGB(50, 255, 255, 255);
  final _startPaint = Paint()..color = const Color.fromARGB(255, 0, 255, 255);
  final _endPaint = Paint()..color = const Color.fromARGB(255, 255, 255, 0);

  PathComponent({required BarriersComponent barriers}) : _barriers = barriers;

  void calculatePath({required Point<int> start, required Point<int> end}) {
    print('calculating path from ${start} to ${end}');
    _miniGridPoints = AStar(
      rows: gridSize,
      columns: gridSize,
      start: start,
      end: end,
      barriers: _barriers.points,
    ).findThePath().toList();

    print(_miniGridPoints);

    _largeGridPoints = [];
    _pathDirections = [];
    for (int i = 0; i < _miniGridPoints.length; i++) {
      _largeGridPoints.add(Vector2.array([
        _miniGridPoints[i].x * gridSquareSizeDouble,
        _miniGridPoints[i].y * gridSquareSizeDouble
      ]));

      if (i == _miniGridPoints.length - 1) break;
      _pathDirections.add(
          directionFrom[_miniGridPoints[i + 1] - _miniGridPoints[i]] ??
              Direction.none);
    }

    print(_largeGridPoints);
    print(_pathDirections);
  }

  void drawPath() {
    for (final rectangle in _pathRectangles) {
      world.remove(rectangle);
    }

    _pathRectangles = _miniGridPoints
        .map<RectangleComponent>(
          (point) => RectangleComponent(
            position: Vector2.array([
              point.x * gridSquareSizeDouble,
              point.y * gridSquareSizeDouble
            ]),
            size: Vector2.all(gridSquareSizeDouble),
            paint: _paint,
          ),
        )
        .toList();

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
