import 'dart:ui';

import 'package:flame/components.dart';
import 'package:pathfinding/core/grid.dart' as pf;
import 'package:pathfinding/core/util.dart' as pf_util;
import 'package:pathfinding/finders/jps.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/direction.dart';
import 'package:tech_world/map_editor/map_editor_state.dart';

/// Uses Jump Point Search (JPS) to calculate a set of points that define a
/// path that avoids all barriers.
///
/// JPS is ~5x faster than A* on uniform-cost grids by "jumping" over
/// intermediate nodes in straight lines.
///
/// The [PathComponent] takes the barriers and uses JPS to calculate a set of
/// points between the start (player position) and end (clicked point).
/// The PathComponent also keeps the set of [RectangleComponent]s corresponding
/// to the grid points in canvas space, used to draw the path on the canvas.
class PathComponent extends Component with HasWorldReference {
  List<(int, int)> _miniGridPoints = [];
  List<Vector2> _largeGridPoints = [];
  List<RectangleComponent> _pathRectangles = [];
  List<Direction> _pathDirections = [];
  BarriersComponent _barriers;
  final _paint = Paint()..color = const Color.fromARGB(50, 255, 255, 255);
  final _startPaint = Paint()..color = const Color.fromARGB(150, 0, 255, 255);
  final _endPaint = Paint()..color = const Color.fromARGB(150, 255, 255, 0);

  // JPS finder instance (reusable)
  final _jps = JumpPointFinder();

  // Cached grid (created once from barriers)
  pf.Grid? _grid;

  PathComponent({required BarriersComponent barriers}) : _barriers = barriers;

  /// Update the barriers reference and invalidate the cached grid.
  set barriers(BarriersComponent newBarriers) {
    _barriers = newBarriers;
    _grid = null;
  }

  /// Use Jump Point Search to calculate a set of points that define a
  /// path that avoids all barriers.
  ///
  /// JPS returns sparse "jump points" (waypoints), so we expand them into
  /// a step-by-step path. Also calculate a direction for each path segment
  /// to create [MoveEffect]s for the [PlayerComponent].
  void calculatePath({required (int, int) start, required (int, int) end}) {
    // Clamp coordinates to valid grid bounds
    final clampedStart = (
      start.$1.clamp(0, gridSize - 1),
      start.$2.clamp(0, gridSize - 1),
    );
    final clampedEnd = (
      end.$1.clamp(0, gridSize - 1),
      end.$2.clamp(0, gridSize - 1),
    );

    // Create grid on first use
    _grid ??= _barriers.createGrid();

    // Clone grid before pathfinding (JPS modifies grid state)
    final jumpPoints = _jps.findPath(
      clampedStart.$1,
      clampedStart.$2,
      clampedEnd.$1,
      clampedEnd.$2,
      _grid!.clone(),
    );

    // Expand sparse jump points into full step-by-step path
    // JPS returns waypoints like [(0,0), (3,3), (5,5)] - we need step-by-step
    final expandedPath = _expandPath(jumpPoints);

    // Convert path format: List<List<int>> [[x,y], ...] -> List<(int, int)>
    _miniGridPoints =
        expandedPath.map<(int, int)>((p) => (p[0], p[1])).toList();

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

  /// Rebuild the pathfinding grid from editor state (barriers from the editor).
  void setGridFromEditor(MapEditorState editorState) {
    final matrix = List.generate(
      gridSize,
      (_) => List.filled(gridSize, 0),
    );
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        if (editorState.tileAt(x, y) == TileType.barrier) {
          matrix[y][x] = 1;
        }
      }
    }
    _grid = pf.Grid(gridSize, gridSize, matrix);
  }

  /// Reset the pathfinding grid so it rebuilds from barriers on next use.
  void invalidateGrid() {
    _grid = null;
  }

  /// Expand sparse jump points into a step-by-step path.
  ///
  /// JPS returns waypoints (jump points) where each consecutive pair may be
  /// more than 1 cell apart. This method interpolates between each pair using
  /// Bresenham's line algorithm to produce a path where each step is exactly
  /// 1 cell (including diagonals).
  List<List<int>> _expandPath(List<dynamic> jumpPoints) {
    if (jumpPoints.isEmpty) return [];
    if (jumpPoints.length == 1) {
      return [
        [jumpPoints[0][0] as int, jumpPoints[0][1] as int]
      ];
    }

    final List<List<int>> expanded = [];

    for (int i = 0; i < jumpPoints.length - 1; i++) {
      final x0 = jumpPoints[i][0] as int;
      final y0 = jumpPoints[i][1] as int;
      final x1 = jumpPoints[i + 1][0] as int;
      final y1 = jumpPoints[i + 1][1] as int;

      // Get all cells on the line between these two points
      final line = pf_util.getLine(x0, y0, x1, y1) as List<dynamic>;

      // Add all points except the last one (to avoid duplicates)
      // The last point of this segment is the first point of the next
      for (int j = 0; j < line.length - 1; j++) {
        expanded.add([line[j][0] as int, line[j][1] as int]);
      }
    }

    // Add the final destination point
    final last = jumpPoints.last;
    expanded.add([last[0] as int, last[1] as int]);

    return expanded;
  }
}
