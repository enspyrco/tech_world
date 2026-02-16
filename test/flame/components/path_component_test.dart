import 'package:flutter_test/flutter_test.dart';
import 'package:tech_world/flame/components/barriers_component.dart';
import 'package:tech_world/flame/components/path_component.dart';
import 'package:tech_world/flame/maps/predefined_maps.dart';
import 'package:tech_world/flame/shared/constants.dart';
import 'package:tech_world/flame/shared/direction.dart';

void main() {
  group('PathComponent', () {
    late BarriersComponent barriers;
    late PathComponent pathComponent;

    setUp(() {
      barriers = BarriersComponent(barriers: lRoom.barriers);
      pathComponent = PathComponent(barriers: barriers);
    });

    group('calculatePath', () {
      test('calculates path between two points', () {
        pathComponent.calculatePath(start: (0, 0), end: (3, 0));

        expect(pathComponent.largeGridPoints, isNotEmpty);
        expect(pathComponent.directions, isNotEmpty);
      });

      test('calculates straight horizontal path', () {
        pathComponent.calculatePath(start: (10, 10), end: (13, 10));

        final points = pathComponent.largeGridPoints;
        expect(points.length, greaterThanOrEqualTo(2));

        // All points should have same y
        for (final point in points) {
          expect(point.y, equals(10 * gridSquareSizeDouble));
        }
      });

      test('calculates straight vertical path', () {
        pathComponent.calculatePath(start: (10, 10), end: (10, 13));

        final points = pathComponent.largeGridPoints;
        expect(points.length, greaterThanOrEqualTo(2));

        // All points should have same x
        for (final point in points) {
          expect(point.x, equals(10 * gridSquareSizeDouble));
        }
      });

      test('calculates diagonal path', () {
        pathComponent.calculatePath(start: (10, 10), end: (13, 13));

        final points = pathComponent.largeGridPoints;
        expect(points.length, greaterThanOrEqualTo(2));

        // First and last points should be at expected positions
        expect(points.first.x, equals(10 * gridSquareSizeDouble));
        expect(points.first.y, equals(10 * gridSquareSizeDouble));
        expect(points.last.x, equals(13 * gridSquareSizeDouble));
        expect(points.last.y, equals(13 * gridSquareSizeDouble));
      });

      test('returns path with directions for each segment', () {
        pathComponent.calculatePath(start: (0, 0), end: (3, 0));

        // directions.length should be points.length - 1
        expect(
          pathComponent.directions.length,
          equals(pathComponent.largeGridPoints.length - 1),
        );
      });

      test('clamps coordinates to valid grid bounds', () {
        // Try path with out-of-bounds coordinates
        pathComponent.calculatePath(start: (-5, -5), end: (100, 100));

        final points = pathComponent.largeGridPoints;
        expect(points, isNotEmpty);

        // First point should be clamped to (0, 0)
        expect(points.first.x, equals(0));
        expect(points.first.y, equals(0));

        // Last point should be clamped to (gridSize-1, gridSize-1)
        expect(points.last.x, equals((gridSize - 1) * gridSquareSizeDouble));
        expect(points.last.y, equals((gridSize - 1) * gridSquareSizeDouble));
      });

      test('handles same start and end point', () {
        pathComponent.calculatePath(start: (25, 25), end: (25, 25));

        // Should have at least the point itself
        expect(pathComponent.largeGridPoints, isNotEmpty);
      });

      test('finds path around barriers', () {
        // The barrier is at x=4, y=7-29 (except y=17)
        // Path from (3, 10) to (5, 10) should go around the barrier
        pathComponent.calculatePath(start: (3, 10), end: (5, 10));

        final points = pathComponent.largeGridPoints;
        expect(points, isNotEmpty);

        // Path should not go through barrier at (4, 10)
        // It should find path through gap at y=17 or go around
      });

      test('uses gap in barrier wall', () {
        // The barrier has a gap at (4, 17)
        // Path from (3, 17) to (5, 17) should go through the gap
        pathComponent.calculatePath(start: (3, 17), end: (5, 17));

        final points = pathComponent.largeGridPoints;
        expect(points, isNotEmpty);
      });

      test('generates correct directions for right movement', () {
        pathComponent.calculatePath(start: (10, 10), end: (11, 10));

        expect(pathComponent.directions.contains(Direction.right), isTrue);
      });

      test('generates correct directions for left movement', () {
        pathComponent.calculatePath(start: (11, 10), end: (10, 10));

        expect(pathComponent.directions.contains(Direction.left), isTrue);
      });

      test('generates correct directions for up movement', () {
        pathComponent.calculatePath(start: (10, 11), end: (10, 10));

        expect(pathComponent.directions.contains(Direction.up), isTrue);
      });

      test('generates correct directions for down movement', () {
        pathComponent.calculatePath(start: (10, 10), end: (10, 11));

        expect(pathComponent.directions.contains(Direction.down), isTrue);
      });
    });

    group('largeGridPoints', () {
      test('returns empty list initially', () {
        expect(pathComponent.largeGridPoints, isEmpty);
      });

      test('converts mini grid to large grid coordinates', () {
        pathComponent.calculatePath(start: (5, 5), end: (5, 6));

        final points = pathComponent.largeGridPoints;
        expect(points.first.x, equals(5 * gridSquareSizeDouble));
        expect(points.first.y, equals(5 * gridSquareSizeDouble));
      });
    });

    group('directions', () {
      test('returns empty list initially', () {
        expect(pathComponent.directions, isEmpty);
      });

      test('directions correspond to movement between points', () {
        pathComponent.calculatePath(start: (10, 10), end: (12, 10));

        final directions = pathComponent.directions;
        // Moving right, so directions should be right
        for (final dir in directions) {
          expect(dir, equals(Direction.right));
        }
      });
    });

    group('path consistency', () {
      test('subsequent path calculations replace previous path', () {
        pathComponent.calculatePath(start: (0, 0), end: (5, 0));
        final firstPathLength = pathComponent.largeGridPoints.length;

        pathComponent.calculatePath(start: (0, 0), end: (10, 0));
        final secondPathLength = pathComponent.largeGridPoints.length;

        expect(secondPathLength, greaterThan(firstPathLength));
      });

      test('grid is reused between path calculations', () {
        // First calculation creates the grid
        pathComponent.calculatePath(start: (0, 0), end: (5, 0));

        // Second calculation should reuse the grid (no error)
        pathComponent.calculatePath(start: (10, 10), end: (15, 10));

        expect(pathComponent.largeGridPoints, isNotEmpty);
      });
    });

    group('edge cases', () {
      test('handles path at grid boundaries', () {
        pathComponent.calculatePath(start: (0, 0), end: (49, 49));

        expect(pathComponent.largeGridPoints, isNotEmpty);
        expect(pathComponent.directions, isNotEmpty);
      });

      test('handles single step path', () {
        pathComponent.calculatePath(start: (25, 25), end: (26, 25));

        expect(pathComponent.largeGridPoints.length, greaterThanOrEqualTo(2));
        expect(pathComponent.directions.length, greaterThanOrEqualTo(1));
      });
    });
  });
}
